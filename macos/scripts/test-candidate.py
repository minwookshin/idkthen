import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('candidate', Path(__file__).with_name('verify-candidate.py'))
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


class CandidateEvidenceTests(unittest.TestCase):
    def test_manual_evidence_is_never_carried_to_a_new_binary(self):
        old = {'checks': {'automated_checks': {'status': 'passed'},
                          'fresh_install': {'status': 'passed', 'evidence': 'Old build'}}}
        new = candidate.evidence_for_run(old, 'new hash', [{'status': 'passed'}])
        self.assertEqual(new['checks']['fresh_install'], {'status': 'pending', 'evidence': ''})
        self.assertEqual(old['checks']['fresh_install']['status'], 'passed')
        self.assertEqual(new['executable_sha256'], 'new hash')

    def test_late_pass_does_not_hide_an_earlier_failure(self):
        report = candidate.evidence_for_run({'checks': {}}, 'hash', [{'status': 'failed'}, {'status': 'passed'}])
        self.assertEqual(report['checks']['automated_checks']['status'], 'failed')
        empty = candidate.evidence_for_run({'checks': {}}, 'hash', [])
        self.assertEqual(empty['checks']['automated_checks']['status'], 'failed')

    def test_timeout_and_missing_tool_produce_failed_local_records(self):
        for error, code in [(subprocess.TimeoutExpired('tool', 1), 124), (FileNotFoundError('missing'), 127)]:
            with self.subTest(code=code), tempfile.TemporaryDirectory() as folder:
                with patch.object(candidate.subprocess, 'run', side_effect=error):
                    row = candidate.run_check('fixture', ['fixture'], folder, Path(folder), 1)
                self.assertEqual(row['status'], 'failed')
                self.assertEqual(row['exit_code'], code)
                self.assertEqual(row['log_sha256'], candidate.digest(Path(folder) / 'fixture.log'))


if __name__ == '__main__':
    unittest.main()
