# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Keep coverage obligations when tests stop exercising library code."""

from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from unittest.mock import patch

import affected


FILES = {
    'core/common.mojo': 'def common():\n    pass\n',
    'core/used.mojo': 'from core.common import common\n',
    'core/other.mojo': 'def other():\n    pass\n',
    'tests/helper.mojo': 'def helper():\n    pass\n',
    'tests/test_a.mojo': 'from core.used import common\nfrom helper import helper\n',
    'tests/test_b.mojo': 'from core.common import common\n',
    'tests/test_other.mojo': 'from core.other import other\n',
    'tests/test_asset.mojo': 'from core.used import common\n# "assets/fixture/"\n',
}
RELEVANT = {
    'tests/test_a.mojo', 'tests/helper.mojo', 'tests/test_b.mojo',
    'tests/test_asset.mojo', 'core/used.mojo', 'core/common.mojo',
}


class AffectedCoverageTests(unittest.TestCase):
    def select(self, changed):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name, text in FILES.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            with patch.object(affected, 'ROOT', folder):
                return affected.affected_set(changed)

    def test_test_edit_measures_transitive_imports_and_all_relevant_suites(self):
        self.assertEqual(self.select({'tests/test_a.mojo': False}), RELEVANT)

    def test_helper_edit_measures_dependencies_of_its_users(self):
        self.assertEqual(self.select({'tests/helper.mojo': False}), RELEVANT)

    def test_test_fixture_edit_also_measures_exercised_library(self):
        # test_a is reached as an importer of core.used; its helper is not
        # measured because the edited fixture belongs to test_asset only.
        self.assertEqual(self.select({'assets/fixture/data.bin': False}),
                         RELEVANT - {'tests/helper.mojo'})

    def test_library_only_change_keeps_the_existing_reverse_import_scope(self):
        self.assertEqual(self.select({'core/used.mojo': False}),
                         {'core/used.mojo', 'tests/test_a.mojo', 'tests/test_asset.mojo'})

    def test_docs_and_empty_changes_do_not_add_coverage(self):
        self.assertEqual(self.select({}), set())
        self.assertEqual(self.select({'README.md': False}), set())

    def test_cli_keeps_removed_import_coverage_by_selecting_everything(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'tools').mkdir()
            (root / 'tools/affected.py').write_text(Path(affected.__file__).read_text())
            for name, text in FILES.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            def git(*args):
                return subprocess.run(['git', *args], cwd=root, check=True,
                                      capture_output=True, text=True)
            git('init', '-q')
            git('add', '.')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                'commit', '-qm', 'fixture')
            (root / 'tests/test_a.mojo').write_text('def test_nothing():\n    pass\n')
            result = subprocess.run(
                [sys.executable, 'tools/affected.py', '--base', 'HEAD', *FILES],
                cwd=root, check=True, capture_output=True, text=True)
            self.assertEqual(set(result.stdout.split()), set(FILES))

    def test_unknown_baseline_is_conservative_but_new_tests_have_no_old_imports(self):
        changed = {'tests/test_new.mojo': False}
        with patch.object(affected, 'git', return_value=None):
            self.assertTrue(affected.test_imports_removed(changed, 'main'))
        with patch.object(affected, 'git', side_effect=['revision\n', '']):
            self.assertFalse(affected.test_imports_removed(changed, 'main'))

    def test_unreadable_source_is_conservative_instead_of_an_empty_selection(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'tests').mkdir()
            (root / 'tests/test_bad.mojo').write_bytes(b'\xff')
            with patch.object(affected, 'ROOT', folder):
                self.assertEqual(affected.affected_set({'tests/test_bad.mojo': False}), affected.ALL)

    def test_deleted_suite_remains_conservative(self):
        self.assertEqual(self.select({'tests/test_a.mojo': True}), affected.ALL)


if __name__ == '__main__':
    unittest.main()
