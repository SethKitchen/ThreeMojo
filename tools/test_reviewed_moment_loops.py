# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact runtime literal proofs; compile-time sites stay outside the mask."""
from pathlib import Path
import tempfile
import unittest
import coverage_loop_proofs as loops

ROOT = Path(__file__).resolve().parents[1]
MODULE = 'extensions/carla/spiral_moment_proof'


class ReviewedMomentLoopsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='reviewed moment loops ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / (MODULE + '.mojo')
        self.path.parent.mkdir(parents=True)
        self.original = (ROOT / (MODULE + '.mojo')).read_text()
        self.path.write_text(self.original)

    def test_exact_runtime_sites_and_cardinalities(self):
        expected = {92: 5, 98: 5, 111: 21, 119: 21, 125: 11, 163: 4}
        actual = {line: row for line, row in loops.reviewed_nonempty_loops(self.root, MODULE).items() if row['kind'] == 'literal-range'}
        self.assertEqual(set(actual), set(expected))
        self.assertEqual(loops.constant_loops(self.original), {})
        for line, count in expected.items():
            row = actual[line]
            self.assertEqual((row['kind'], row['cardinality'], row['maximum_cardinality']),
                             ('literal-range', count, count))
            self.assertEqual((row['required'], row['impossible']), ('T', 'F'))
            self.assertTrue(self.original.splitlines()[line - 1].strip().startswith('for '))
        self.assertFalse({76, 79, 97} & set(actual))

    def test_every_runtime_site_mutation_revokes_all_masks(self):
        for line in (92, 98, 111, 119, 125, 163):
            lines = self.original.splitlines(keepends=True)
            lines[line - 1] = lines[line - 1].split('range(')[0] + 'range(0):\n'
            with self.subTest(line=line):
                self.path.write_text(''.join(lines))
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, MODULE), {})

    def test_binding_import_comptime_and_line_mutations_revoke(self):
        mutations = [self.original + '\nfrom custom import range\n',
                     self.original + '\ndef range(n: Int) -> List[Int]:\n    return []\n',
                     self.original.replace('comptime for index in range(5):',
                                           'comptime for index in range(4):'),
                     '\n' + self.original]
        for text in mutations:
            with self.subTest(text=text[-60:]):
                self.path.write_text(text)
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, MODULE), {})

    def test_missing_source_revokes(self):
        self.path.unlink()
        self.assertEqual(loops.reviewed_nonempty_loops(self.root, MODULE), {})


if __name__ == '__main__':
    unittest.main()
