#!/usr/bin/env python3
"""Explicit release stages. Never remove quarantine, disable Gatekeeper, or print credentials."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
import zipfile

REQUIRED_CHECKS = {'automated_checks', 'fresh_install', 'textedit_typing_undo', 'safari_typing_undo',
                   'chrome_typing_undo', 'secure_field_skip', 'ime_and_paste', 'login_items',
                   'permission_recovery', 'voiceover', 'minimum_macos_runtime',
                   'update_and_remove', 'typing_stability', 'undo_shortcut'}


def command(*args):
    result = subprocess.run(list(map(str, args)), text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f'{args[0]} {args[1]} failed: {result.stderr.strip() or result.stdout.strip()}')
    return result.stdout + result.stderr


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def bundle(app):
    app = Path(app).resolve()
    if app.suffix != '.app' or not app.is_dir():
        raise ValueError('Expected an existing .app bundle.')
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    if not executable.is_file() or not re.fullmatch(r'\d+\.\d+\.\d+', info['CFBundleShortVersionString']):
        raise ValueError('Missing executable or invalid version.')
    return app, info, executable


def verify_signature(app):
    command('codesign', '--verify', '--deep', '--strict', app)
    details = command('codesign', '-d', '--verbose=4', app)
    if 'Authority=Developer ID Application:' not in details:
        raise ValueError('Release needs a Developer ID Application signature; development/ad-hoc signatures are rejected.')
    if '(runtime)' not in details or 'Timestamp=' not in details:
        raise ValueError('Release needs Hardened Runtime and a secure timestamp.')
    return details


def validate_evidence(evidence, executable_hash):
    if evidence.get('executable_sha256') != executable_hash:
        raise ValueError('Validation evidence must match this signed executable SHA-256.')
    checks = evidence.get('checks', {})
    missing = sorted(key for key in REQUIRED_CHECKS if checks.get(key, {}).get('status') != 'passed'
                     or not isinstance(checks.get(key, {}).get('evidence'), str)
                     or not checks[key]['evidence'].strip())
    if missing:
        raise ValueError('Release checks incomplete: ' + ', '.join(missing))
    for field in ('support_url', 'privacy_url'):
        url = urlsplit(evidence.get(field, ''))
        if url.scheme != 'https' or not url.netloc or url.username or url.password:
            raise ValueError(f'A real public {field} is required.')
    if evidence.get('public_support_confirmed') is not True:
        raise ValueError('Public support contact and privacy page must be confirmed.')
    return True


def validate_manifest(manifest, site_url):
    """The first release is served from this site's own immutable downloads directory."""
    version = manifest.get('version', '')
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Invalid release version.')
    if (manifest.get('available') is not True or manifest.get('notarized') is not True
            or manifest.get('channel') != 'verified-preview'
            or not re.fullmatch(r'[a-f0-9]{64}', manifest.get('sha256', ''))):
        raise ValueError('Only a verified release manifest may be staged.')
    origin = urlsplit(site_url)
    if (origin.scheme != 'https' or not origin.netloc or origin.username or origin.password
            or origin.query or origin.fragment or origin.path not in ('', '/')):
        raise ValueError('Provide the exact public HTTPS site origin without a path or credentials.')
    name = f'idkthen-{version}.zip'
    expected = f'{origin.scheme}://{origin.netloc}/downloads/{name}'
    if manifest.get('downloadURL') != expected:
        raise ValueError('Release URL must match this site and version: ' + expected)
    return name


def validate_archive(archive):
    """Inspect before ditto extraction. This app has no symlinks or embedded frameworks."""
    with zipfile.ZipFile(archive) as package:
        members = package.infolist()
        if len(members) > 2048 or sum(item.file_size for item in members) > 128 * 1024 * 1024:
            raise ValueError('Release archive exceeds the expected app size.')
        names = set()
        for item in members:
            path = PurePosixPath(item.filename)
            if (path.is_absolute() or not path.parts or '..' in path.parts or '\\' in item.filename
                    or path.parts[0] not in ('idkthen.app', '__MACOSX')
                    or stat.S_ISLNK(item.external_attr >> 16) or item.flag_bits & 1
                    or item.filename in names):
                raise ValueError('Release archive contains an unexpected or unsafe entry.')
            names.add(item.filename)
        if 'idkthen.app/Contents/Info.plist' not in names:
            raise ValueError('Release archive does not contain idkthen.app.')


def stage_website(release_dir, site, site_url):
    release_dir, site = Path(release_dir).resolve(), Path(site).resolve()
    dist = site / 'dist'
    if not (dist / 'index.html').is_file() or not (dist / 'release.json').is_file():
        raise ValueError('Expected the existing idkthen website with dist/index.html and release.json.')
    manifest = json.loads((release_dir / 'release.json').read_text())
    name = validate_manifest(manifest, site_url)
    evidence = json.loads((release_dir / 'validation-evidence.json').read_text())
    with tempfile.TemporaryDirectory(prefix='idkthen-stage-') as temporary:
        temporary = Path(temporary)
        archive = temporary / name
        shutil.copyfile(release_dir / name, archive)
        if sha256(archive) != manifest['sha256']:
            raise ValueError('Release ZIP checksum differs from its manifest.')
        validate_archive(archive)
        extracted = temporary / 'extracted'
        command('ditto', '-x', '-k', archive, extracted)
        app, info, executable = bundle(extracted / 'idkthen.app')
        if (info['CFBundleIdentifier'] != 'dev.pairtype.preview'
                or info['CFBundleShortVersionString'] != manifest['version']
                or info['LSMinimumSystemVersion'] != manifest.get('minimumMacOS')
                or command('lipo', '-archs', executable).strip() != manifest.get('architecture')):
            raise ValueError('Release metadata does not match the packaged app.')
        verify_signature(app)
        command('xcrun', 'stapler', 'validate', app)
        command('spctl', '--assess', '--type', 'execute', '--verbose=2', app)
        validate_evidence(evidence, sha256(executable))
        # Nothing in the website changes before every check above succeeds.
        downloads = dist / 'downloads'
        if downloads.is_symlink():
            raise ValueError('Downloads directory must not be a symlink.')
        downloads.mkdir(exist_ok=True)
        destination = downloads / name
        if destination.exists() or destination.is_symlink():
            if destination.is_symlink() or sha256(destination) != manifest['sha256']:
                raise ValueError('A different artifact already uses this version. Never overwrite a release.')
        else:
            # An exclusive creation keeps an existing version immutable.
            try:
                with destination.open('xb') as stream, archive.open('rb') as source:
                    shutil.copyfileobj(source, stream)
            except FileExistsError:
                raise ValueError('Release appeared concurrently; retry after inspecting it.')
            except OSError:
                destination.unlink(missing_ok=True)
                raise
        # The helper publishes ZIP + manifest from a single source snapshot.
        with tempfile.NamedTemporaryFile(mode='w', dir=dist, prefix='.release-', delete=False) as stream:
            staged_manifest = Path(stream.name)
            json.dump(manifest, stream, indent=2)
            stream.write('\n')
        try:
            os.replace(staged_manifest, dist / 'release.json')
        finally:
            staged_manifest.unlink(missing_ok=True)
    return {'archive': str(destination), 'manifest': str(dist / 'release.json'),
            'next': 'Update release notes and requirements, run web tests, then publish this source with Sites. Verify the anonymous hosted ZIP checksum.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='stage', required=True)
    pre = sub.add_parser('preflight', help='Read-only local distribution check')
    pre.add_argument('--app', required=True)
    sign = sub.add_parser('sign', help='Copy and sign a release bundle with a supplied Developer ID identity')
    sign.add_argument('--app', required=True); sign.add_argument('--output', required=True)
    sign.add_argument('--identity', required=True, help='Developer ID certificate SHA-1 or exact identity name')
    notarize = sub.add_parser('notarize', help='Upload the signed app to Apple using an existing Keychain profile')
    notarize.add_argument('--app', required=True); notarize.add_argument('--keychain-profile', required=True)
    package = sub.add_parser('package', help='Verify notarization and evidence, then create a release ZIP and manifest')
    package.add_argument('--app', required=True); package.add_argument('--evidence', required=True)
    package.add_argument('--output', required=True); package.add_argument('--download-url', required=True)
    stage = sub.add_parser('stage-website', help='Reverify a release package and stage ZIP + manifest in the existing website; does not publish')
    stage.add_argument('--release', required=True); stage.add_argument('--site', required=True)
    stage.add_argument('--site-url', required=True)
    args = parser.parse_args()
    if args.stage == 'stage-website':
        print(json.dumps(stage_website(args.release, args.site, args.site_url), indent=2))
        return 0
    app, info, executable = bundle(args.app)
    if args.stage == 'preflight':
        identities = command('security', 'find-identity', '-v', '-p', 'codesigning')
        try:
            verify_signature(app)
            signed = True
        except (ValueError, RuntimeError):
            signed = False
        result = {'version': info['CFBundleShortVersionString'], 'bundle_id': info['CFBundleIdentifier'],
                  'architectures': command('lipo', '-archs', executable).strip(),
                  'minimum_macos': info.get('LSMinimumSystemVersion'),
                  'developer_id_available': 'Developer ID Application:' in identities,
                  'distribution_signature_valid': signed,
                  'public_release_ready': False,
                  'next': 'Sign, validate the signed build, notarize, then package with completed evidence.'}
        print(json.dumps(result, indent=2))
        return 0 if signed else 2
    if args.stage == 'sign':
        identities = command('security', 'find-identity', '-v', '-p', 'codesigning')
        if not any('Developer ID Application:' in line and args.identity in line for line in identities.splitlines()):
            raise ValueError('The selected identity is not an available Developer ID Application certificate.')
        output = Path(args.output).resolve()
        if output.exists() or output.suffix != '.app':
            raise ValueError('Choose a new output path ending in .app; existing files are never overwritten.')
        command('ditto', app, output)
        command('codesign', '--force', '--options', 'runtime', '--timestamp', '--sign', args.identity, output)
        verify_signature(output)
        _, _, signed_executable = bundle(output)
        print(json.dumps({'signed_app': str(output), 'executable_sha256': sha256(signed_executable),
                          'next': 'Validate this exact build before opening public downloads.'}, indent=2))
        return 0
    verify_signature(app)
    if args.stage == 'notarize':
        with tempfile.TemporaryDirectory(prefix='idkthen-notary-') as temporary:
            archive = Path(temporary) / 'idkthen-submit.zip'
            command('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
            result = json.loads(command('xcrun', 'notarytool', 'submit', archive,
                                        '--keychain-profile', args.keychain_profile, '--wait', '--output-format', 'json'))
            print(json.dumps({'submission_id': result.get('id'), 'status': result.get('status')}))
            if result.get('status') != 'Accepted':
                raise ValueError('Apple did not accept this submission. Inspect its notary log before proceeding.')
        command('xcrun', 'stapler', 'staple', app)
        command('xcrun', 'stapler', 'validate', app)
        command('spctl', '--assess', '--type', 'execute', '--verbose=2', app)
        print('Apple notarization, stapled ticket and Gatekeeper assessment passed.')
        return 0
    evidence = json.loads(Path(args.evidence).read_text())
    validate_evidence(evidence, sha256(executable))
    command('xcrun', 'stapler', 'validate', app)
    command('spctl', '--assess', '--type', 'execute', '--verbose=2', app)
    download = urlsplit(args.download_url)
    if download.scheme != 'https' or not download.netloc or download.username or download.password or not download.path.endswith('.zip'):
        raise ValueError('Download URL must be a public HTTPS ZIP URL without credentials.')
    output = Path(args.output).resolve()
    if output.exists():
        raise ValueError('Choose a new output directory; release artifacts are immutable.')
    output.mkdir(parents=True)
    archive = output / ('idkthen-' + info['CFBundleShortVersionString'] + '.zip')
    command('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
    manifest = {'version': info['CFBundleShortVersionString'], 'channel': 'verified-preview',
                'available': True, 'downloadURL': args.download_url, 'sha256': sha256(archive),
                'minimumMacOS': info['LSMinimumSystemVersion'], 'architecture': command('lipo', '-archs', executable).strip(),
                'notarized': True, 'notesURL': './release-notes.html'}
    (output / 'release.json').write_text(json.dumps(manifest, indent=2) + '\n')
    shutil.copyfile(args.evidence, output / 'validation-evidence.json')
    print(json.dumps({'archive': str(archive), 'manifest': str(output / 'release.json'),
                      'next': 'Use stage-website to verify and stage ZIP + manifest together, update release notes, then publish and verify the hosted checksum.'}, indent=2))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, RuntimeError, OSError, KeyError, zipfile.BadZipFile) as error:
        print('Release blocked: ' + str(error), file=sys.stderr)
        sys.exit(2)
