# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check import-only test helpers without invoking the Mojo compiler."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import affected
import suite_key


ROOT = Path(__file__).resolve().parent.parent
MAKE_ENVIRONMENT = {'MAKEFLAGS', 'MFLAGS', 'MAKEOVERRIDES', 'MAKELEVEL',
                    'MAKEFILES', 'GNUMAKEFLAGS'}


class TestHelperInventoryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='test helper inventory ')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.environment = {key: value for key, value in os.environ.items()
                            if key not in MAKE_ENVIRONMENT}
        self.sources = {
            'math/measured.mojo': 'def value() -> Int:\n    return 1\n',
            'tests/_nested.mojo': 'from math.measured import value\n',
            'tests/_shared.mojo': 'from tests._nested import value\n',
            'tests/test_driver.mojo': 'from tests._shared import value\n',
            'tests/test_other.mojo': 'from math.measured import value\n',
            'tests/carla_fixed_s_fixture.mojo': '# named fixture\n',
            'tests/exact_predicates_oracle.mojo': '# named oracle\n',
            'tools/anatomy_pairs.mojo': '# diagnostic adapter\n',
            'tools/driver.mojo': 'def main():\n    pass\n',
            'coverage/runtime.mojo': '# runtime\n',
            'coverage/build_cli.mojo': 'def main():\n    pass\n',
            'coverage/report_cli.mojo': 'def main():\n    pass\n',
            'tests/compile_fail/rejection.mojo': '# rejected\n',
        }
        for name, source in self.sources.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(source)
        source = (ROOT / 'Makefile').read_text()
        start = source.index('TOOL_CLIS    :=')
        end = source.index('\n# --- the optional GPU backend', start)
        self.inventory = source[start:end]
        (self.root / 'Makefile').write_text(
            'LIB_SOURCES := math/measured.mojo\n' + self.inventory +
            '\n.PHONY: inventory\ninventory:\n' + ''.join(
                '\t@printf "%s\\n" "' + name + ':$(' + name + ')"\n'
                for name in ('TEST_HELPER_LIBS', 'HELPER_LIBS', 'TOOL_LIBS',
                             'ENTRY_POINTS', 'DOC_SOURCES', 'TESTS', 'FORMATTED')))
        # Supply the source directories traversed by the maintained inventory.
        for directory in ('examples', 'bench'):
            (self.root / directory).mkdir()

    def inventory_values(self):
        result = subprocess.run(['make', '-s', 'inventory'], cwd=self.root,
                                env=self.environment, capture_output=True,
                                text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, '')
        return {name: values.split() for name, values in
                (line.split(':', 1) for line in result.stdout.splitlines())}

    def test_helpers_have_one_inventory_for_docs_formatting_and_copies(self):
        values = self.inventory_values()
        helpers = ['tests/_nested.mojo', 'tests/_shared.mojo',
                   'tests/carla_fixed_s_fixture.mojo', 'tests/exact_predicates_oracle.mojo']
        self.assertCountEqual(values['TEST_HELPER_LIBS'], helpers)
        self.assertCountEqual(values['HELPER_LIBS'], helpers + ['tools/anatomy_pairs.mojo'])
        for helper in values['HELPER_LIBS']:
            for name in ('TOOL_LIBS', 'DOC_SOURCES', 'FORMATTED'):
                self.assertEqual(values[name].count(helper), 1, (name, helper))
            self.assertNotIn(helper, values['ENTRY_POINTS'])
            self.assertNotIn(helper, values['TESTS'])
        self.assertCountEqual(values['TESTS'],
                              ['tests/test_driver.mojo', 'tests/test_other.mojo'])
        self.assertCountEqual(values['ENTRY_POINTS'],
                              values['TESTS'] + ['tools/driver.mojo',
                                                'coverage/build_cli.mojo',
                                                'coverage/report_cli.mojo'])
        self.assertIn('tests/compile_fail/rejection.mojo', values['FORMATTED'])

    def test_new_prefixed_helper_is_discovered_without_another_exclusion(self):
        helper = 'tests/_future_control.mojo'
        (self.root / helper).write_text('# another import-only helper\n')
        values = self.inventory_values()
        self.assertIn(helper, values['HELPER_LIBS'])
        self.assertIn(helper, values['DOC_SOURCES'])
        self.assertIn(helper, values['FORMATTED'])
        self.assertNotIn(helper, values['ENTRY_POINTS'])
        self.assertNotIn(helper, values['TESTS'])

    def test_nested_helpers_remain_affected_and_suite_key_dependencies(self):
        with patch.object(affected, 'ROOT', str(self.root)):
            known = set(affected.mojo_files())
            self.assertEqual(suite_key.closure('tests/test_driver.mojo', known, {}),
                             ['math/measured.mojo', 'tests/_nested.mojo',
                              'tests/_shared.mojo', 'tests/test_driver.mojo'])
            selected = affected.affected_set({'tests/_nested.mojo': False})
            self.assertNotEqual(selected, affected.ALL)
            for path in ('math/measured.mojo', 'tests/_nested.mojo',
                         'tests/_shared.mojo', 'tests/test_driver.mojo',
                         'tests/test_other.mojo'):
                self.assertIn(path, selected)
            with patch.object(suite_key, 'TOOLING', []):
                before = suite_key.suite_key('tests/test_driver.mojo', [], known, {}, [], {})
                (self.root / 'tests/_nested.mojo').write_text(
                    self.sources['tests/_nested.mojo'] + '# changed control\n')
                after = suite_key.suite_key('tests/test_driver.mojo', [], known, {}, [], {})
            self.assertNotEqual(before, after)


if __name__ == '__main__':
    unittest.main()
