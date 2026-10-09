# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Replay the real CARLA control generators without a compiler or formatter."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CONTROLS = (
    ('lane_distance', 'lane_distance_fraction', 100),
    ('power', 'power_fraction', 128),
    ('directed', 'directed_fraction', 128),
    ('index', 'index_admission', 96),
)


class CarlaControlReplayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'tools').mkdir()
        (self.root / 'tests').mkdir()
        self.cwd = self.root / 'unrelated'
        self.cwd.mkdir()
        for name, fixture, _ in CONTROLS:
            shutil.copyfile(ROOT / f'tools/generate_carla_{name}_controls.py',
                            self.root / f'tools/generate_carla_{name}_controls.py')
            shutil.copyfile(ROOT / f'tests/test_carla_{fixture}.mojo',
                            self.root / f'tests/test_carla_{fixture}.mojo')

    def run_generator(self, name, *args, optimized=False):
        # Only Python is available. Neither Mojo nor a formatter can be found.
        env = dict(os.environ, PATH='', PYTHONDONTWRITEBYTECODE='1')
        command = [sys.executable, '-B']
        if optimized:
            command.append('-O')
        command += [str(self.root / f'tools/generate_carla_{name}_controls.py'), *args]
        return subprocess.run(command, cwd=self.cwd, env=env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              timeout=5)

    def snapshot(self):
        return {str(path.relative_to(self.root)): (path.read_bytes(),
                path.stat().st_mtime_ns, path.stat().st_ino)
                for path in self.root.rglob('*') if path.is_file()}

    def assert_read_only(self, name, *args, success, optimized=False):
        before = self.snapshot()
        result = self.run_generator(name, *args, optimized=optimized)
        self.assertEqual(result.returncode == 0, success, result.stdout)
        self.assertEqual(self.snapshot(), before, result.stdout)
        return result

    def test_committed_fixtures_replay_exactly_without_writes(self):
        # These copies are the committed fixtures, not generated expectations.
        for name, _, count in CONTROLS:
            with self.subTest(generator=name):
                result = self.assert_read_only(name, '--check', success=True)
                self.assertIn(f'Verified {count}', result.stdout)

    def test_default_generation_and_json_need_no_existing_fixture_or_header(self):
        # There are no sibling source fixtures from which to borrow headers.
        for name, fixture, count in CONTROLS:
            with self.subTest(generator=name):
                target = self.root / f'tests/test_carla_{fixture}.mojo'
                expected = target.read_bytes()
                target.unlink()
                report = self.root / f'{name}.json'
                result = self.run_generator(name, '--json', str(report))
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(target.read_bytes(), expected)
                self.assertEqual(len(json.loads(report.read_text())), count)
                self.assert_read_only(name, '--check', success=True)

    def test_numeric_import_assertion_and_format_drift_fail_without_repair(self):
        for name, fixture, _ in CONTROLS:
            target = self.root / f'tests/test_carla_{fixture}.mojo'
            original = target.read_bytes()
            start = original.index(b'UInt64(0x') + len(b'UInt64(0x')
            corruptions = {
                'numeric word': original[:start] + b'F' + original[start + 1:],
                'import': original.replace(b'from extensions.carla.',
                                           b'from extensions.wrong.', 1),
                'assertion': original.replace(b'assert_true(', b'assert_false(', 1),
                'space': original.replace(b'    var cases:', b'     var cases:', 1),
                'newline': original.replace(b'\n', b'\r\n'),
                'truncated': original[:-1],
                'non UTF-8': original + b'\xff',
            }
            for label, changed in corruptions.items():
                with self.subTest(generator=name, corruption=label):
                    self.assertNotEqual(changed, original)
                    target.write_bytes(changed)
                    result = self.assert_read_only(name, '--check', success=False)
                    self.assertIn('is stale', result.stdout)
            target.write_bytes(original)

    def test_missing_and_unreadable_fixtures_fail_without_creation(self):
        for name, fixture, _ in CONTROLS:
            with self.subTest(generator=name):
                target = self.root / f'tests/test_carla_{fixture}.mojo'
                target.unlink()
                result = self.assert_read_only(name, '--check', success=False)
                self.assertIn('Cannot check', result.stdout)
                self.assertFalse(target.exists())
                target.mkdir()
                result = self.assert_read_only(name, '--check', success=False)
                self.assertIn('Cannot check', result.stdout)
                self.assertTrue(target.is_dir())
                target.rmdir()

    def test_conflicting_and_unknown_arguments_fail_before_any_write(self):
        report = self.root / 'report.json'
        report.write_bytes(b'preserve this report\n')
        for name, _, _ in CONTROLS:
            for args in [('--check', '--json', str(report)),
                         ('--json', str(report), '--check'),
                         ('--check', '--json', str(self.root / 'new.json')),
                         ('--check', '--unknown'), ('--unknown',),
                         ('--che',), ('--jso', str(report)), ('positional',)]:
                with self.subTest(generator=name, args=args):
                    result = self.assert_read_only(name, *args, success=False)
                    self.assertEqual(result.returncode, 2, result.stdout)

    def test_optimized_python_cannot_disable_drift_check(self):
        for name, fixture, _ in CONTROLS:
            with self.subTest(generator=name):
                self.assert_read_only(name, '--check', success=True, optimized=True)
                target = self.root / f'tests/test_carla_{fixture}.mojo'
                target.write_bytes(target.read_bytes() + b'\n')
                self.assert_read_only(name, '--check', success=False, optimized=True)


if __name__ == '__main__':
    unittest.main()
