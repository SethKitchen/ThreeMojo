# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""The negative-fixture manifest matches the fixtures; no job regenerates it.

The checker is `tools/compile_fail.mojo`, tested in
`tests/test_compile_fail_tool.mojo`. These checks read repository files, so
they stay with the tool tests that run on every change.
"""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent


class ManifestTests(unittest.TestCase):
    def test_manifest_covers_exact_fixture_set(self):
        manifest = json.loads((ROOT / 'tools/compile_fail_expectations.json').read_text())
        fixtures = {p.relative_to(ROOT).as_posix()
                    for p in (ROOT / 'tests/compile_fail').glob('*.mojo')}
        self.assertEqual(set(manifest), fixtures)
        for name, expected in manifest.items():
            lines = (ROOT / name).read_text().splitlines()
            self.assertTrue(expected['errors'], name)
            for error in expected['errors']:
                self.assertTrue(1 <= error['line'] <= len(lines), name)
                self.assertGreater(error['column'], 0, name)

    def test_make_and_ci_never_request_regeneration(self):
        paths = [ROOT / 'Makefile'] + list((ROOT / '.github/workflows').glob('*.yml'))
        for path in paths:
            with self.subTest(path=path):
                self.assertNotIn('--update-expectations', path.read_text())


if __name__ == '__main__':
    unittest.main()
