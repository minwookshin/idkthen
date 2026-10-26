import importlib.util
import pathlib
import json
import plistlib
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('release', pathlib.Path(__file__).with_name('release-macos.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

class ReleaseEvidenceTests(unittest.TestCase):
    def evidence(self):
        keys = ['automated_checks','fresh_install','textedit_typing_undo','safari_typing_undo',
                'chrome_typing_undo','secure_field_skip','ime_and_paste','login_items',
                'permission_recovery','voiceover','minimum_macos_runtime',
                'update_and_remove','typing_stability','undo_shortcut']
        return {'executable_sha256':'a'*64, 'support_url':'https://example.com/help',
                'privacy_url':'https://example.com/privacy', 'public_support_confirmed':True,
                'checks':{key:{'status':'passed','evidence':'Fixture evidence only'} for key in keys}}
    def test_complete_fixture(self):
        self.assertTrue(release.validate_evidence(self.evidence(),'a'*64))
    def test_different_build(self):
        with self.assertRaises(ValueError): release.validate_evidence(self.evidence(),'b'*64)
    def test_missing_evidence(self):
        data = self.evidence(); data['checks']['chrome_typing_undo']['evidence']=''
        with self.assertRaises(ValueError): release.validate_evidence(data,'a'*64)
    def test_blank_evidence_does_not_count_as_validation(self):
        data = self.evidence(); data['checks']['fresh_install']['evidence']=' \n '
        with self.assertRaises(ValueError): release.validate_evidence(data,'a'*64)
    def test_lifecycle_stability_and_shortcut_cannot_be_skipped(self):
        for key in ['update_and_remove','typing_stability','undo_shortcut']:
            data = self.evidence(); del data['checks'][key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                release.validate_evidence(data,'a'*64)
    def test_pending_runtime(self):
        data = self.evidence(); data['checks']['minimum_macos_runtime']['status']='pending'
        with self.assertRaises(ValueError): release.validate_evidence(data,'a'*64)
    def test_support_not_confirmed(self):
        data = self.evidence(); data['public_support_confirmed']=False
        with self.assertRaises(ValueError): release.validate_evidence(data,'a'*64)
    def test_unsafe_url(self):
        data = self.evidence(); data['privacy_url']='https://user:password@example.com/'
        with self.assertRaises(ValueError): release.validate_evidence(data,'a'*64)


class WebsiteStagingTests(unittest.TestCase):
    def manifest(self):
        return {'version':'0.14.1','available':True,'notarized':True,'channel':'verified-preview',
                'sha256':'a'*64,'minimumMacOS':'14.0','architecture':'arm64',
                'downloadURL':'https://example.com/downloads/idkthen-0.14.1.zip'}

    def test_manifest_requires_matching_site_version_and_verification(self):
        self.assertEqual(release.validate_manifest(self.manifest(),'https://example.com/'),'idkthen-0.14.1.zip')
        for change in [{'available':False},{'notarized':False},{'channel':'development-preview'},
                       {'version':'../evil'},{'sha256':'bad'},
                       {'downloadURL':'https://another.example/downloads/idkthen-0.14.1.zip'},
                       {'downloadURL':'https://example.com/downloads/idkthen-0.14.0.zip'}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                release.validate_manifest({**self.manifest(), **change},'https://example.com')

    def test_site_origin_rejects_credentials_and_paths(self):
        for origin in ['http://example.com','https://user:secret@example.com','https://example.com/path',
                       'https://example.com/?token=secret']:
            with self.subTest(origin=origin), self.assertRaises(ValueError):
                release.validate_manifest(self.manifest(),origin)

    def test_archive_rejects_traversal_links_and_wrong_bundle(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = pathlib.Path(folder)/'fixture.zip'
            for name in ['../outside','/absolute','Other.app/Contents/Info.plist','idkthen.app/../../outside','idkthen.app\\..\\outside']:
                with zipfile.ZipFile(archive,'w') as z:
                    z.writestr('idkthen.app/Contents/Info.plist','fixture')
                    z.writestr(name,'fixture')
                with self.subTest(name=name), self.assertRaises(ValueError): release.validate_archive(archive)
            with zipfile.ZipFile(archive,'w') as z:
                z.writestr('idkthen.app/Contents/Info.plist','fixture')
                link=zipfile.ZipInfo('idkthen.app/link'); link.create_system=3
                link.external_attr=(stat.S_IFLNK | 0o777) << 16
                z.writestr(link,'/tmp/outside')
            with self.assertRaises(ValueError): release.validate_archive(archive)

    def test_expected_bundle_with_macos_metadata_is_allowed(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = pathlib.Path(folder)/'fixture.zip'
            with zipfile.ZipFile(archive,'w') as z:
                z.writestr('idkthen.app/Contents/Info.plist','fixture')
                z.writestr('__MACOSX/idkthen.app/Contents/._Info.plist','metadata')
            release.validate_archive(archive)

    def fixture(self, root):
        package, site = root/'package', root/'site'
        package.mkdir(); (site/'dist').mkdir(parents=True)
        (site/'dist/index.html').write_text('fixture')
        (site/'dist/release.json').write_text('{"available":false}')
        manifest = self.manifest()
        archive = package/'idkthen-0.14.1.zip'
        with zipfile.ZipFile(archive,'w') as z:
            z.writestr('idkthen.app/Contents/Info.plist',plistlib.dumps({
                'CFBundleIdentifier':'dev.pairtype.preview','CFBundleExecutable':'idkthen',
                'CFBundleShortVersionString':'0.14.1','LSMinimumSystemVersion':'14.0'}))
            z.writestr('idkthen.app/Contents/MacOS/idkthen',b'fixture-executable')
        manifest['sha256'] = release.sha256(archive)
        (package/'release.json').write_text(json.dumps(manifest))
        evidence = ReleaseEvidenceTests().evidence()
        evidence['executable_sha256'] = release.hashlib.sha256(b'fixture-executable').hexdigest()
        (package/'validation-evidence.json').write_text(json.dumps(evidence))
        return package, site, archive, manifest

    def fake_command(self, *args):
        # Unit fixture only; this does NOT prove actual signing or notarization.
        if args[0] == 'ditto':
            with zipfile.ZipFile(args[3]) as z: z.extractall(args[4])
        elif args[0] == 'lipo': return 'arm64'
        return ''

    def test_checksum_failure_does_not_change_website(self):
        with tempfile.TemporaryDirectory() as folder:
            package,site,archive,_ = self.fixture(pathlib.Path(folder))
            archive.write_bytes(b'corrupted')
            with self.assertRaisesRegex(ValueError,'checksum'):
                release.stage_website(package,site,'https://example.com')
            self.assertEqual((site/'dist/release.json').read_text(),'{"available":false}')
            self.assertFalse((site/'dist/downloads').exists())

    def test_signature_failure_does_not_change_website(self):
        with tempfile.TemporaryDirectory() as folder:
            package,site,_,_ = self.fixture(pathlib.Path(folder))
            with patch.object(release,'command',side_effect=self.fake_command), patch.object(release,'verify_signature',side_effect=ValueError('unsigned')):
                with self.assertRaisesRegex(ValueError,'unsigned'):
                    release.stage_website(package,site,'https://example.com')
            self.assertEqual((site/'dist/release.json').read_text(),'{"available":false}')
            self.assertFalse((site/'dist/downloads').exists())

    def test_stages_only_verified_artifact_and_manifest_without_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            package,site,archive,manifest = self.fixture(pathlib.Path(folder))
            with patch.object(release,'command',side_effect=self.fake_command), patch.object(release,'verify_signature'):
                release.stage_website(package,site,'https://example.com')
                release.stage_website(package,site,'https://example.com')  # identical retry
                target = site/'dist/downloads'/archive.name
                self.assertEqual(release.sha256(target),manifest['sha256'])
                self.assertEqual(json.loads((site/'dist/release.json').read_text()),manifest)
                self.assertFalse((site/'dist/validation-evidence.json').exists())
                target.write_bytes(b'different existing release')
                with self.assertRaisesRegex(ValueError,'Never overwrite'):
                    release.stage_website(package,site,'https://example.com')

if __name__ == '__main__': unittest.main()
