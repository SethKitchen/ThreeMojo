# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compiler-free controls for complete compile-time helper scanning."""

import unittest

import check_coverage_grouping as grouping


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
