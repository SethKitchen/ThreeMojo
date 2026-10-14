# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Keep the portable CARLA oracle checks in the official tool and CI gate."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
MAKE_ENVIRONMENT = {'MAKEFLAGS', 'MFLAGS', 'MAKEOVERRIDES', 'MAKELEVEL',
                    'MAKEFILES', 'GNUMAKEFLAGS'}


class CarlaOracleWiringTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='carla oracle wiring ')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.events = self.root / 'events.txt'
        self.environment = {key: value for key, value in os.environ.items()
                            if key not in MAKE_ENVIRONMENT}
        self.environment.update({'PYTHONDONTWRITEBYTECODE': '1',
                                 'ORACLE_WIRING_EVENTS': str(self.events)})
        for stage, directory in (('tools', 'tools'),
                                 ('assets', 'assets/carla/tools'),
                                 ('nested', 'tools/carla_lane_oracle')):
            folder = self.root / directory
            folder.mkdir(parents=True, exist_ok=True)
            (folder / 'test_sentinel.py').write_text(
                'import os\nfrom pathlib import Path\nimport unittest\n'
                'class Sentinel(unittest.TestCase):\n'
                '    def test_selected(self):\n'
                '        with Path(os.environ["ORACLE_WIRING_EVENTS"]).open("a") as output:\n'
                '            output.write(' + repr(stage + '\n') + ')\n'
                '        self.assertNotEqual(os.environ.get("ORACLE_WIRING_FAIL"), '
                + repr(stage) + ')\n')
        # Match the real non-package directory: root discovery cannot find it.
        self.assertFalse((self.root / 'tools/carla_lane_oracle/__init__.py').exists())
        (self.root / 'tools/carla_lane_oracle/spiral_moments.py').write_text(
            'import os, sys\nfrom pathlib import Path\n'
            'if sys.argv[1:] != ["--check"]:\n'
            '    raise SystemExit("expected the read-only --check mode")\n'
            'with Path(os.environ["ORACLE_WIRING_EVENTS"]).open("a") as output:\n'
            '    output.write("check\\n")\n'
            'if os.environ.get("ORACLE_WIRING_FAIL") == "check":\n'
            '    raise SystemExit(7)\n')
        source = (ROOT / 'Makefile').read_text()
        start = source.index('test-tools:\n')
        end = source.index('\n# The negative-fixture manifest names exactly', start)
        # The nested stage runs through the real parallel runner.
        runner = 'tools/parallel_unittest.py'
        (self.root / runner).write_bytes((ROOT / runner).read_bytes())
        (self.root / 'Makefile').write_text(
            '.PHONY: test-tools repository-check\nJOBS ?= 2\n' + source[start:end]
            + '\nrepository-check:\n\t@echo repository >> "$$ORACLE_WIRING_EVENTS"\n')

    def make(self, fail=None):
        self.events.write_text('')
        environment = self.environment.copy()
        environment.pop('ORACLE_WIRING_FAIL', None)
        if fail is not None:
            environment['ORACLE_WIRING_FAIL'] = fail
        result = subprocess.run(['make', '-s', 'test-tools'], cwd=self.root,
                                env=environment, text=True, capture_output=True,
                                timeout=5)
        return result, self.events.read_text().splitlines()

    def test_official_target_runs_all_discoveries_and_read_only_check_once(self):
        result, events = self.make()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(events, ['tools', 'assets', 'nested', 'check', 'repository'])

    def test_each_discovery_failure_fails_target_before_later_stages(self):
        stages = ['tools', 'assets', 'nested']
        for index, stage in enumerate(stages):
            with self.subTest(stage=stage):
                result, events = self.make(stage)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(events, stages[:index + 1])

    def test_read_only_checker_failure_fails_the_official_target(self):
        result, events = self.make('check')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(events, ['tools', 'assets', 'nested', 'check'])

    def test_linux_and_macos_ci_invoke_the_official_tool_target(self):
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        for name in ('tools', 'tools-macos'):
            job = workflow.split('\n  ' + name + ':\n', 1)[1]
            job = re.split(r'\n  [a-z][\w-]*:\n', job, maxsplit=1)[0]
            commands = re.findall(r'^\s+run: (.+)$', job, re.MULTILINE)
            count = len(re.search(r'shard: \[([0-9, ]+)\]', job).group(1).split(','))
            self.assertIn('python3 tools/ci_scope.py run -- test-tools '
                          'TOOLS_SHARD=${{ matrix.shard }}/' + str(count), commands)
            self.assertIn("if: needs.scope.outputs.run_tools == 'true'", job)

    def test_groups_together_run_every_stage_once(self):
        seen = []
        for index in (1, 2):
            environment = self.environment.copy()
            self.events.write_text('')
            result = subprocess.run(['make', '-s', 'test-tools', f'TOOLS_SHARD={index}/2'],
                                    cwd=self.root, env=environment, text=True,
                                    capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            events = self.events.read_text().splitlines()
            if index > 1:
                self.assertNotIn('tools', events)
                self.assertNotIn('assets', events)
                self.assertNotIn('check', events)
                self.assertNotIn('repository', events)
            seen += events
        self.assertEqual(sorted(seen), ['assets', 'check', 'nested', 'repository', 'tools'])



if __name__ == '__main__':
    unittest.main()
