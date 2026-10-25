"""Verify real build arguments without invoking Flutter, Gradle or a device."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

BUILD = Path(__file__).resolve().parent / 'build.sh'


class DeviceProfileBuildTests(unittest.TestCase):
    def invoke(self, profile=None, revision=None, target='android-arm'):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / 'flutter'
            log = root / 'argv.json'
            fake.write_text('#!/usr/bin/env python3\nimport json,os,sys\n'
                            'with open(os.environ["KAZUMI_PROFILE_ARGV"],"w") as f:\n'
                            ' json.dump(sys.argv[1:],f)\n')
            fake.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       KAZUMI_PROFILE_ARGV=str(log))
            for name in ['KAZUMI_TV_DEVICE_PROFILE', 'KAZUMI_TV_REVISION']:
                env.pop(name, None)
            if profile is not None:
                env['KAZUMI_TV_DEVICE_PROFILE'] = profile
            if revision is not None:
                env['KAZUMI_TV_REVISION'] = revision
            result = subprocess.run(['bash', str(BUILD), '--target-platform', target],
                                    env=env, capture_output=True, text=True)
            return result, json.loads(log.read_text()) if log.exists() else None

    def test_generic_is_the_default_not_implicit_low_ram_tuning(self):
        result, args = self.invoke()
        self.assertEqual(result.returncode, 0)
        self.assertIn('--dart-define=KAZUMI_TV_DEVICE_PROFILE=generic', args)
        self.assertIn('--dart-define=KAZUMI_TV_REVISION=r5.6.1-generic', args)

    def test_hisense_scope_keeps_the_requested_arm64_target(self):
        result, args = self.invoke('hisense-mt9655', target='android-arm64')
        self.assertEqual(result.returncode, 0)
        self.assertIn('--dart-define=KAZUMI_TV_DEVICE_PROFILE=hisense-mt9655', args)
        self.assertEqual(args[-2:], ['--target-platform', 'android-arm64'])

    def test_z9x_requires_explicit_target_and_keeps_the_requested_abi(self):
        result, args = self.invoke('xgimi-z9x')
        self.assertEqual(result.returncode, 0)
        self.assertIn('--dart-define=KAZUMI_TV_DEVICE_PROFILE=xgimi-z9x', args)
        self.assertEqual(args[-2:], ['--target-platform', 'android-arm'])

    def test_unvalidated_hisense_target_is_rejected_before_building(self):
        result, args = self.invoke('hisense')
        self.assertEqual(result.returncode, 2)
        self.assertIsNone(args)

    def test_explicit_revision_does_not_remove_the_device_scope(self):
        result, args = self.invoke('xgimi-z9x', 'custom-revision')
        self.assertEqual(result.returncode, 0)
        self.assertIn('--dart-define=KAZUMI_TV_REVISION=custom-revision', args)
        self.assertIn('--dart-define=KAZUMI_TV_DEVICE_PROFILE=xgimi-z9x', args)


if __name__ == '__main__':
    unittest.main()
