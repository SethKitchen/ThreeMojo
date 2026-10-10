# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Four individually bound loop proofs, without generic scope inference."""
from pathlib import Path
import tempfile
import unittest
import coverage_loop_proofs as loops

ROOT = Path(__file__).resolve().parents[1]
AXES = 'extensions/carla/lane_distance'
PRODUCER = 'extensions/carla/curve_distance'
BLEND = 'extensions/carla/curve_interval'
HAIR = 'extensions/humanoid/skeleton/head/hair/strands'


class ReviewedAdditionalLoopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='reviewed additional loops ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for module in (AXES, PRODUCER, BLEND, HAIR):
            target = self.root/(module+'.mojo')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT/(module+'.mojo')).read_bytes())

    def test_exact_sites_and_truthful_cardinalities(self):
        expected = {AXES: {50: ('reviewed-nonempty-range', 1, 3)},
                    BLEND: {592: ('literal-list', 4, 4)},
                    HAIR: {225: ('literal-range', 2, 2), 231: ('literal-range', 3, 3)}}
        for module, sites in expected.items():
            actual = loops.reviewed_nonempty_loops(self.root, module)
            self.assertEqual(set(actual), set(sites))
            for line, metadata in sites.items():
                self.assertEqual((actual[line]['kind'], actual[line]['cardinality'], actual[line]['maximum_cardinality']), metadata)
                self.assertEqual((actual[line]['required'], actual[line]['impossible']), ('T', 'F'))
                self.assertNotIn(line, loops.constant_loops((self.root/(module+'.mojo')).read_text()))
        self.assertEqual(loops.reviewed_nonempty_loops(self.root, 'unlisted/module'), {})

    def test_axis_assertion_alias_call_and_iterable_mutations_reject(self):
        cases = [(PRODUCER, 'comptime assert axes >= 1 and axes <= 3', 'comptime assert axes >= 0 and axes <= 3'),
                 (PRODUCER, 'comptime assert axes >= 1 and axes <= 3', 'comptime assert axes >= 1 and axes <= 4'),
                 (AXES, 'var bound = _distance_normalized_square[axes](point, query, scale)', 'var bound = _Interval(0.0, 0.0)'),
                 (AXES, '_normalized_square as _distance_normalized_square', '_unchecked_square as _distance_normalized_square'),
                 (AXES, 'var original = _normalized_square[axes](point, query, scale)', 'var original = _normalized_square[1](point, query, scale)'),
                 (AXES, 'for axis in range(axes):', 'for axis in range(axes - 1):')]
        for module, before, after in cases:
            path = self.root/(module+'.mojo');original = path.read_text()
            self.assertIn(before, original)
            with self.subTest(module=module, before=before):
                path.write_text(original.replace(before, after))
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, AXES), {})
                path.write_text(original)

    def test_exact_float_elements_and_method_literals_are_bound(self):
        cases = [(BLEND, '[actual_rate.low, actual_rate.high, one, two]', '[one]'),
                 (BLEND, '[actual_rate.low, actual_rate.high, one, two]', 'List[Float64]()'),
                 (BLEND, 'var low: Float64', 'var low: Float32'),
                 (HAIR, 'for end in range(2):', 'for end in range(0):'),
                 (HAIR, 'for channel in range(3):', 'for channel in range(0):')]
        for module, before, after in cases:
            path = self.root/(module+'.mojo');original = path.read_text()
            self.assertIn(before, original)
            with self.subTest(module=module, before=before):
                path.write_text(original.replace(before, after))
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, module), {})
                path.write_text(original)

    def test_complete_module_binding_rejects_range_or_list_shadow(self):
        for module, suffix in [(AXES, '\nfrom custom import range\n'),
                               (HAIR, '\ndef range(value: Int) -> List[Int]:\n    return []\n'),
                               (BLEND, '\nfrom custom import List\n')]:
            path = self.root/(module+'.mojo');original = path.read_text()
            path.write_text(original+suffix)
            self.assertEqual(loops.reviewed_nonempty_loops(self.root, module), {})
            path.write_text(original)


if __name__ == '__main__':
    unittest.main()
