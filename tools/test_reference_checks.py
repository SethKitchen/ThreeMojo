# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Run the reference generators that check their saved fixtures.

Each generator holds an exact oracle for one native fixture. Without this
test, nothing ran them, so an edited fixture or expected value went stale
silently.
"""

from pathlib import Path
import subprocess
import sys
import unittest

TOOLS = Path(__file__).resolve().parent

# The segment script checks with top-level asserts and takes no --check flag.
CHECKS = (('reference_volume_lighting.py', '--check'),
          ('reference_remainders.py', '--check'),
          ('reference_animation_loops.py', '--check'),
          ('reference_segment_geometry.py',))


class ReferenceCheckTests(unittest.TestCase):
    def test_saved_fixtures_match_their_oracles(self):
        for script, *flags in CHECKS:
            with self.subTest(script=script):
                result = subprocess.run(
                    [sys.executable, str(TOOLS / script), *flags],
                    cwd=TOOLS.parent, text=True, timeout=60,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                self.assertEqual(result.returncode, 0, result.stdout)


if __name__ == '__main__':
    unittest.main()
