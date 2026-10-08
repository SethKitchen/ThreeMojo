# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Separate dynamic nonempty theorem bound to immutable count admission."""
from pathlib import Path
import tempfile
import unittest
import coverage_loop_proofs as loops

ROOT = Path(__file__).resolve().parents[1]
MODULE = 'extensions/carla/spiral_moment_proof'


class ReviewedMomentNonemptyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='reviewed moment count ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / (MODULE + '.mojo')
        self.path.parent.mkdir(parents=True)
        self.original = (ROOT / (MODULE + '.mojo')).read_text()
        self.path.write_text(self.original)

    def test_exact_dynamic_site_cardinality(self):
        actual = loops.reviewed_nonempty_loops(self.root, MODULE)
        row = actual[97]
        self.assertEqual((row['kind'], row['cardinality'], row['maximum_cardinality']),
                         ('reviewed-nonempty-range', 1, 64))
        self.assertEqual((row['required'], row['impossible']), ('T', 'F'))
        self.assertEqual(row['expression'], 'range(pieces)')
        self.assertEqual(row['proof_id'], 'moment-admitted-piece-count-1-to-64')
        self.assertNotIn(97, loops.constant_loops(self.original))
        self.assertFalse({76, 79} & set(actual))

    def test_guard_parameter_binding_and_intervening_write_revoke(self):
        cases = [('pieces < 1 or pieces > 64', 'pieces < 0 or pieces > 64'),
                 ('pieces < 1 or pieces > 64', 'pieces < 1 or pieces > 65'),
                 ('pieces: Int,', 'mut pieces: Int,'),
                 ('for piece in range(pieces):', 'for piece in range(0):'),
                 ('    var moments = Array', '    pieces = 0\n    var moments = Array')]
        for old, new in cases:
            with self.subTest(old=old):
                self.assertIn(old, self.original)
                self.path.write_text(self.original.replace(old, new, 1))
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, MODULE), {})
        self.path.write_text(self.original + '\nfrom custom import range\n')
        self.assertEqual(loops.reviewed_nonempty_loops(self.root, MODULE), {})


if __name__ == '__main__':
    unittest.main()
