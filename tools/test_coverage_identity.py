# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compiler-free checks that identity safety does not erase model cases."""

import unittest

import check_coverage_grouping as grouping


class IdentityAdmissionTests(unittest.TestCase):
    def test_all_original_truth_trees_remain_accounted_for(self):
        self.assertEqual(len(grouping.TRUTH_CASES), 43)
        admitted = set(grouping.TRUTH_ACCEPTED)
        mixed = set(grouping.TRUTH_MIXED_REJECTED)
        retained = set(grouping.TRUTH_RETAINED_REJECTED)
        temporary = set(grouping.TRUTH_TEMPORARY_REJECTED)
        self.assertFalse(admitted & mixed or admitted & retained or mixed & retained)
        self.assertFalse(temporary & (admitted | mixed | retained))
        self.assertEqual(admitted, set())
        self.assertEqual(admitted | mixed | retained | temporary, set(range(43)))
        self.assertEqual(tuple(i for i, tree in enumerate(grouping.TRUTH_CASES)
                               if grouping.truth_supported(tree)), grouping.TRUTH_ACCEPTED)

    def test_separate_negated_variants_keep_all_43_tree_shapes(self):
        self.assertEqual(len(grouping.NEGATED_TRUTH_CASES), 43)
        for original, negated in zip(grouping.TRUTH_CASES, grouping.NEGATED_TRUTH_CASES):
            self.assertEqual(negated, grouping.negate_custom_leaves(original))
            self.assertTrue(grouping.truth_supported(negated))
            self.assertEqual(len(grouping.truth_slots(original)), len(grouping.truth_slots(negated)))

    def test_custom_temporary_selection_is_refused_even_with_bitwise_moves(self):
        for kind in ('S', 'D', 'M', 'Q', 'T'):
            with self.subTest(kind=kind):
                self.assertFalse(grouping.truth_supported(('or', (kind, 0), (kind, 1))))

    def test_retained_bitwise_left_does_not_gain_copy_invariance(self):
        for operator in ('and', 'or'):
            for left in (('P', 0), ('choose', ('B', 0), ('P', 1), ('P', 2))):
                with self.subTest(operator=operator, left=left):
                    self.assertFalse(grouping.truth_supported((operator, left, ('Q', 3))))

    def test_negation_converts_the_original_before_the_boolean_operator(self):
        for kind in ('X', 'C', 'P', 'M'):
            with self.subTest(kind=kind):
                self.assertTrue(grouping.truth_supported(('or', ('not', (kind, 0)), ('B', 1))))

    def test_last_use_sources_remove_only_the_two_post_use_reads(self):
        for number in (0, 3):
            expression = grouping.IDENTITY_POSITIVE_CASES[number][0]
            retained = grouping.identity_source(expression)
            last_use = grouping.identity_last_use_source(expression)
            suffix = ('    print("RETAINED", kept.payload)\n'
                      '    print("ADDRESS", Int(Pointer(to=kept.payload)) == kept.expected)\n')
            self.assertEqual(retained, last_use + suffix)
            self.assertIn('print("DIRECT", kept.__bool__())', last_use)
            self.assertNotIn('print("RETAINED"', last_use)

    def test_identity_controls_keep_both_condition_slots(self):
        self.assertEqual(len(grouping.IDENTITY_POSITIVE_CASES), 6)
        self.assertEqual(len(grouping.IDENTITY_REFUSED_CASES), 4)
        for expression, conversions, outcome, vector in grouping.IDENTITY_POSITIVE_CASES:
            with self.subTest(expression=expression):
                source = grouping.identity_source(expression)
                self.assertIn(f'    if {expression}:', source)
                self.assertEqual(len(vector), 2)
                self.assertEqual(set(vector) - set('TF-'), set())
                for operation in ('copy_ctor', 'move_ctor', 'del_'):
                    self.assertIn(f'Identity.__{operation}_is_trivial', source)
                self.assertIn('print("ADDRESS", Int(Pointer(to=kept.payload)) == kept.expected)', source)


class CompileTimeNameGuardTests(unittest.TestCase):
    def test_multiline_type_parameter_helper_body_is_scanned(self):
        source = (grouping.ROOT / 'coverage/runtime.mojo').read_text()
        body = grouping.helper_bodies(source)['_standard_string_optional']
        self.assertIn('comptime if T == Candidate:', body)
        self.assertIn('return _standard_string_optional[T, Optional[Candidate]]()', body)
        self.assertNotIn('def _optional_lifecycle', body)

    def test_multiline_helper_forbidden_calls_are_detected(self):
        source = (grouping.ROOT / 'coverage/runtime.mojo').read_text()
        original = '    comptime if T == Candidate:\n'
        self.assertEqual(source.count(original), 1)
        for method in ('startswith("Optional[")', 'find("[")'):
            with self.subTest(method=method):
                mutant = source.replace(
                    original, '    _ = StaticString("Optional[Int]").' + method
                    + '\n' + original)
                body = grouping.helper_bodies(mutant)['_standard_string_optional']
                self.assertIn('.' + method, body)
                self.assertIn('return _standard_string_optional[T, Optional[Candidate]]()', body)
                self.assertTrue(any(call in body for call in grouping.COMPILE_TIME_FORBIDDEN))

    def test_current_compile_time_helpers_have_no_forbidden_calls(self):
        source = (grouping.ROOT / 'coverage/runtime.mojo').read_text()
        bodies = grouping.helper_bodies(source)
        self.assertEqual(set(bodies), set(grouping.COMPILE_TIME_HELPERS))
        for name, body in bodies.items():
            for call in grouping.COMPILE_TIME_FORBIDDEN:
                with self.subTest(helper=name, call=call):
                    self.assertNotIn(call, body)


if __name__ == '__main__':
    unittest.main()
