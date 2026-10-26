#!/usr/bin/env python3
"""Collect reproducible local checks; never approve OS integration or publish a build."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import subprocess
import sys
import time

SUITES = ('conversation', 'typing', 'practice', 'self', 'usability', 'personalization',
          'language-set', 'multilingual', 'efficiency', 'product', 'lifecycle', 'smoke')


def digest(filename):
    return hashlib.sha256(Path(filename).read_bytes()).hexdigest()


def fingerprint(root, files):
    return {str(p.relative_to(root)): digest(p) for p in sorted(set(files)) if p.is_file()}


def run_check(name, args, cwd, output, timeout=180):
    started = time.monotonic()
    try:
        result = subprocess.run([str(x) for x in args], cwd=cwd, capture_output=True,
                                text=True, timeout=timeout)
        code, stdout, stderr = result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        code, stdout, stderr = 124, '', 'Check exceeded its time limit. No pass recorded.'
    except OSError as error:
        code, stdout, stderr = 127, '', str(error)
    log = output / (name + '.log')
    log.write_text(stdout + ('\n' + stderr if stderr else ''), encoding='utf-8')
    row = {'name': name, 'status': 'passed' if code == 0 else 'failed', 'exit_code': code,
           'seconds': round(time.monotonic() - started, 3), 'log': log.name, 'log_sha256': digest(log)}
    print(f'{name}: {row["status"]}', flush=True)
    return row


def evidence_for_run(template, binary_hash, checks):
    # A fresh copy prevents a previous build's manual passes from surviving a rebuild.
    evidence = json.loads(json.dumps(template))
    evidence['executable_sha256'] = binary_hash
    evidence['checks'] = {key: {'status': 'pending', 'evidence': ''} for key in template['checks']}
    evidence['checks']['automated_checks'] = {
        'status': 'passed' if checks and all(c['status'] == 'passed' for c in checks) else 'failed',
        'evidence': 'summary.json plus its SHA-256-bound local logs; does not establish live OS integration.'}
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True)
    parser.add_argument('--web', required=True)
    parser.add_argument('--output', required=True, help='New local evidence directory; never overwritten')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    app, web, output = Path(args.app).resolve(), Path(args.web).resolve(), Path(args.output).resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'dev.pairtype.preview':
        raise ValueError('Expected the idkthen preview bundle.')
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    if not (web / 'package.json').is_file():
        raise ValueError('Expected the existing web source checkout.')
    output.mkdir(parents=True, exist_ok=False)
    binary_hash = digest(executable)
    source_hashes = fingerprint(root, [root / 'Package.swift', *root.glob('Sources/**/*.swift'),
                                       *root.glob('Tests/**/*.swift'), *root.glob('scripts/*.py')])
    web_hashes = fingerprint(web, [web / 'package.json', *web.glob('tests/*.mjs'), *web.glob('dist/*')])
    checks = []
    checks.append(run_check('signature-integrity', ['codesign', '--verify', '--strict', app], root, output))
    checks.append(run_check('core-tests', ['swift', 'test', '-c', 'release'], root, output, 300))
    checks.append(run_check('release-tool-tests', [sys.executable, root / 'scripts/test-release.py'], root, output))
    checks.append(run_check('candidate-runner-tests', [sys.executable, root / 'scripts/test-candidate.py'], root, output))
    checks.append(run_check('web-tests', ['node', '--test', *sorted(web.glob('tests/*.test.mjs'))], web, output))
    for name in SUITES:
        checks.append(run_check(name, [executable, '--' + name + '-test'], root, output))
    audit = run_check('scenario-audit', [executable, '--audit-corpus', root / 'evaluation/scenarios-v1.json'], root, output)
    audit_result = None
    if audit['status'] == 'passed':
        try:
            data = json.loads((output / audit['log']).read_text())
            audit_result = {key: data[key] for key in ('passed', 'total', 'scope')}
        except (ValueError, KeyError):
            audit['status'] = 'failed'
    # Corpus recovery misses stay visible separately; they are not redefined as passes.
    checks.append(audit)
    binary_unchanged = digest(executable) == binary_hash
    source_unchanged = fingerprint(root, [root / p for p in source_hashes]) == source_hashes
    web_unchanged = fingerprint(web, [web / p for p in web_hashes]) == web_hashes
    stable = binary_unchanged and source_unchanged and web_unchanged
    if not stable:
        checks.append({'name': 'inputs-unchanged', 'status': 'failed', 'exit_code': 1})
    summary = {'created_at': datetime.now(timezone.utc).isoformat(), 'version': info['CFBundleShortVersionString'],
               'build': info['CFBundleVersion'], 'executable_sha256': binary_hash,
               'system': {'macos': platform.mac_ver()[0], 'architecture': platform.machine()},
               'inputs_unchanged': stable, 'source_sha256': source_hashes, 'web_sha256': web_hashes,
               'checks': checks, 'authored_corpus': audit_result, 'public_release_ready': False,
               'limits': 'CLI checks use synthetic text. They do not test actual typing, IME, OS undo, fresh installation, login, accessibility use or battery life.'}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    evidence = evidence_for_run(json.loads((root / 'release-evidence.template.json').read_text()), binary_hash, checks)
    (output / 'validation-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(f'Local report: {output / "summary.json"}\nPublic release remains closed.')
    return 0 if evidence['checks']['automated_checks']['status'] == 'passed' else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError) as error:
        print('Candidate verification blocked: ' + str(error), file=sys.stderr)
        sys.exit(2)
