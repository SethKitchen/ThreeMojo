# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exercise the real test-tools recipe without running its expensive checks."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
MAKE_ENVIRONMENT = {'MAKEFLAGS', 'MFLAGS', 'MAKEOVERRIDES', 'MAKELEVEL',
                    'MAKEFILES', 'GNUMAKEFLAGS', 'TOOLS_SHARD'}


class ToolsShardTests(unittest.TestCase):
    def run_recipe(self, shard=None, fail=None):
        source = (ROOT / 'Makefile').read_text()
        owner = next(line for line in source.splitlines()
                     if line.startswith('TOOLS_SERIAL_SHARD :='))
        start = source.index('test-tools:\n')
        recipe = source[start:source.index('\n# The negative-fixture', start)]
        with tempfile.TemporaryDirectory(prefix='tools shard ') as directory:
            root = Path(directory)
            scripts = root / 'bin'
            scripts.mkdir()
            command = scripts / 'python3'
            command.write_text(
                '#!' + sys.executable + '\n'
                'import json, os, sys\n'
                'with open("calls", "a") as out:\n'
                '    out.write(json.dumps(sys.argv[1:]) + "\\n")\n'
                'if os.environ.get("FAIL_COMMAND") in sys.argv[1:]:\n'
                '    raise SystemExit(7)\n')
            command.chmod(0o700)
            (root / 'Makefile').write_text(
                'JOBS := 3\n' + owner + '\n' + recipe +
                '\nrepository-check:\n\t@python3 repository-check\n')
            env = {key: value for key, value in os.environ.items()
                   if key not in MAKE_ENVIRONMENT}
            env['PATH'] = str(scripts) + os.pathsep + env['PATH']
            if fail is not None:
                env['FAIL_COMMAND'] = fail
            else:
                env.pop('FAIL_COMMAND', None)
            args = ['make', '-s', 'test-tools']
            if shard is not None:
                args.append('TOOLS_SHARD=' + shard)
            result = subprocess.run(args, cwd=root, env=env, text=True,
                                    capture_output=True, timeout=5)
            calls = root / 'calls'
            return result, ([json.loads(line) for line in calls.read_text().splitlines()]
                            if calls.exists() else [])

    def test_unsharded_runs_all_original_commands_in_order(self):
        result, calls = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [
            ['-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_*.py'],
            ['-m', 'unittest', 'discover', '-s', 'assets/carla/tools', '-p', 'test_*.py'],
            ['tools/parallel_unittest.py', '--jobs', '3', 'tools/carla_lane_oracle'],
            ['tools/carla_lane_oracle/spiral_moments.py', '--check'],
            ['repository-check'],
        ])

    def test_every_shard_count_preserves_exactly_once_auxiliary_checks(self):
        for count in (1, 2, 3, 4, 5, 6, 7, 12):
            with self.subTest(count=count):
                all_calls = []
                for index in range(1, count + 1):
                    result, calls = self.run_recipe(f'{index}/{count}')
                    self.assertEqual(result.returncode, 0, result.stderr)
                    expected_owner = 1 if count < 5 else 5
                    discovery = [call for call in calls if call[:2] == ['-m', 'unittest']]
                    self.assertEqual(len(discovery), 2 if index == expected_owner else 0)
                    oracle = [call for call in calls if call[0] == 'tools/parallel_unittest.py']
                    self.assertEqual(oracle, [['tools/parallel_unittest.py', '--jobs', '3',
                                              '--shard', f'{index}/{count}',
                                              'tools/carla_lane_oracle']])
                    tail = [call for call in calls if call[0] in
                            ('tools/carla_lane_oracle/spiral_moments.py', 'repository-check')]
                    self.assertEqual(len(tail), 2 if index == 1 else 0)
                    all_calls.extend(call for call in calls if call not in oracle)
                self.assertEqual(sorted(all_calls), sorted([
                    ['-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_*.py'],
                    ['-m', 'unittest', 'discover', '-s', 'assets/carla/tools', '-p', 'test_*.py'],
                    ['tools/carla_lane_oracle/spiral_moments.py', '--check'],
                    ['repository-check'],
                ]))

    def test_auxiliary_failures_stop_and_fail_the_owning_shard(self):
        for shard, failed in (('5/6', 'tools'), ('5/6', 'assets/carla/tools'),
                              ('1/6', 'tools/carla_lane_oracle/spiral_moments.py'),
                              ('1/6', 'repository-check')):
            with self.subTest(shard=shard, failed=failed):
                result, calls = self.run_recipe(shard, fail=failed)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(failed, calls[-1])

    def test_oracle_failures_remain_fatal_on_every_shard(self):
        for index in range(1, 7):
            result, calls = self.run_recipe(f'{index}/6', fail='tools/parallel_unittest.py')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(calls[-1][0], 'tools/parallel_unittest.py')


if __name__ == '__main__':
    unittest.main()
