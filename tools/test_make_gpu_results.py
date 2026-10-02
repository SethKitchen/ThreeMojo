# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Run the actual GPU Make recipes with a harmless command stub."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
PASS = ('Running 1 tests for stub.mojo\nPASS [ 1.0 ] test_stub\n'
        'Summary [ 1.0 ] 1 tests run: 1 passed , 0 failed , 0 skipped\n')
FAIL = PASS.replace('PASS [', 'FAIL [').replace('1 passed , 0 failed', '0 passed , 1 failed')


class GpuRecipeTests(unittest.TestCase):
    def run_recipe(self, device, output, status):
        source = (ROOT / 'Makefile').read_text()
        if device:
            start = source.index('test-gpu-device:\n')
            end = source.index('\n# The GPU suites', start)
            target = 'test-gpu-device'
        else:
            start = source.index('$(TEST_GPU_HOST_STAMP):\n')
            end = source.index('\ngpu-status:', start)
            target = 'host'
        recipe = source[start:end]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'tools').mkdir()
            for name in ('run_suite.py', 'test_environment.py'):
                shutil.copyfile(ROOT / 'tools' / name, root / 'tools' / name)
            (root / 'stub.py').write_text(f'print({output!r}, end="")\nraise SystemExit({status})\n')
            (root / 'Makefile').write_text(
                'JOBS := 1\nGPU_BUDGET := 10\nMOJO := python3 stub.py\n'
                'MOJOFLAGS :=\nGPU_HOST_TESTS := host.mojo\n'
                'GPU_TESTS := device.mojo host.mojo\nTEST_GPU_HOST_STAMP := host\n'
                'stamp = touch passed-stamp\n' + recipe + '\n')
            # A parent `make MOJO=...` exports overrides to every child.
            # This fixture owns its Makefile and must use its harmless stub.
            environment = {key: value for key, value in os.environ.items()
                           if key not in {'MAKEFLAGS', 'MFLAGS', 'MAKEOVERRIDES',
                                          'MAKELEVEL', 'MAKEFILES', 'GNUMAKEFLAGS'}}
            result = subprocess.run(['make', '-s', target], cwd=root, text=True,
                                    capture_output=True, env=environment)
            return result, (root / 'passed-stamp').exists()

    def test_outer_make_overrides_cannot_replace_the_fixture_compiler(self):
        with patch.dict(os.environ, {
            'MAKEFLAGS': '-- MOJO=nonexistent-outer-compiler',
            'MAKEOVERRIDES': 'MOJO=nonexistent-outer-compiler',
            'MFLAGS': '-e', 'GNUMAKEFLAGS': '-e',
            'MAKEFILES': 'nonexistent-outer-include', 'MAKELEVEL': '7',
        }):
            for device in (False, True):
                result, stamped = self.run_recipe(device, PASS, 0)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(stamped, not device)

    def test_empty_failed_and_malformed_output_cannot_pass(self):
        for device in (False, True):
            for output in ('', FAIL, PASS.replace('1 tests run', '2 tests run')):
                with self.subTest(device=device, output=output):
                    result, stamped = self.run_recipe(device, output, 0)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(stamped)
                    self.assertNotIn('suites passed.', result.stdout)

    def test_valid_results_and_device_skip_notices_are_preserved(self):
        for device in (False, True):
            result, stamped = self.run_recipe(device, 'SKIP (no accelerator): notice\n' + PASS, 0)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(stamped, not device)
            self.assertIn('SKIP (no accelerator): notice', result.stdout)

    def test_child_failure_is_not_hidden_by_valid_output(self):
        for device in (False, True):
            result, stamped = self.run_recipe(device, PASS, 7)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(stamped)


if __name__ == '__main__':
    unittest.main()
