# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""The repository's fixtures match their recorded manifest.

The checker is `tools/fixture_manifest.mojo`, tested in
`tests/test_fixture_tools.mojo`. This test runs it on the real repository,
whose files the Mojo suite cache does not track.
"""

import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent


class FixtureRepositoryTests(unittest.TestCase):
    def test_repository_matches_manifest(self):
        mojo = os.environ.get('MOJO', str(ROOT / '.venv/bin/mojo'))
        result = subprocess.run(
            [mojo, 'run', '-I', str(ROOT), str(ROOT / 'tools/fixture_manifest.mojo')],
            cwd=ROOT, capture_output=True, text=True, timeout=600)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('hashes match', result.stdout)


if __name__ == '__main__':
    unittest.main()
