#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Fixed-pin and hash-independent controls for the Sum2 source migration.

No test executes Mojo. The exact same candidate must pass before mutation.
Unittest assertions and explicit errors stay active under optimized Python.
"""
from fractions import Fraction as F
import math
from pathlib import Path
import unittest
from unittest.mock import patch

import check_sampled_values as sampled
import source_contracts
import sum2_contracts
from sum2_analysis import sum2_error, U
from test_sum2_oracle import two_sum, sum2, from_word, to_word

ROOT = Path(__file__).resolve().parents[2]

# name, module, before, after. Each target must actually occur in the passing
# source. Pins remain byte-identical throughout every test.
CASES = [
    ('residual_operand', 'curve_sum2', 'high - total', 'high - term'),
    ('residual_sign', 'curve_sum2', 'total_error + term_error', 'total_error - term_error'),
    ('residual_omitted', 'curve_sum2', 'correction + residual', 'correction'),
    ('correction_overwritten', 'curve_sum2', 'correction + residual', 'residual'),
    ('tuple_order', 'curve_sum2', '(high, correction + residual)', '(correction + residual, high)'),
    ('materialization_barrier', 'curve_sum2', '@no_inline\n', ''),
    ('count_lower', 'curve_sum2', 'count < 1', 'count < 0'),
    ('count_upper', 'curve_sum2', 'count > 1073741824', 'count > 2147483648'),
    ('magnitude_finite', 'curve_sum2', 'not isfinite(magnitude)', 'False'),
    ('magnitude_sign', 'curve_sum2', 'magnitude < 0.0', 'magnitude < -1.0'),
    ('magnitude_range', 'curve_sum2', '8.452712498170644e270', '1.7976931348623157e308'),
    ('inherited_finite', 'curve_sum2', 'not isfinite(inherited)', 'False'),
    ('inherited_sign', 'curve_sum2', 'inherited < 0.0', 'inherited < -1.0'),
    ('zero_return', 'curve_sum2', 'if magnitude == 0.0:\n        return inherited', 'if magnitude == 0.0:\n        return 0.0'),
    ('count_one_return', 'curve_sum2', 'if count == 1:\n        return inherited', 'if count == 1:\n        return 0.0'),
    ('gamma_count', 'curve_sum2', 'Float64(count - 1)', 'Float64(count)'),
    ('gamma_denominator', 'curve_sum2', '_Interval.point(1.0) - nu', '_Interval.point(1.0) + nu'),
    ('gamma_squared', 'curve_sum2', 'gamma * gamma', 'gamma'),
    ('missing_final_round', 'curve_sum2', '(u + gamma * gamma)', '(gamma * gamma)'),
    ('missing_inherited', 'curve_sum2', '_Interval.point(inherited)\n        +', '_Interval.point(0.0)\n        +'),
    ('inward_bound', 'curve_sum2', '    ).high', '    ).low'),
    ('helper_alias', 'lane_geometry', 'import _sum2_update', 'import _sum2_update as _other_update'),
    ('helper_shadow', 'lane_geometry', '    var x = Float64(0.0)', '    var _sum2_update = Float64(0.0)\n    var x = Float64(0.0)'),
    ('initial_correction', 'lane_geometry', 'var x_correction = Float64(0.0)', 'var x_correction = Float64(1.0)'),
    ('negative_zero_init', 'lane_geometry', 'var x_correction = Float64(0.0)', 'var x_correction = Float64(-0.0)'),
    ('reset_correction', 'lane_geometry', '        var start = step * Float64(piece)', '        x_correction = Float64(0.0)\n        var start = step * Float64(piece)'),
    ('wrong_tuple_index', 'lane_geometry', 'x_correction = next_x[1]', 'x_correction = next_x[0]'),
    ('swap_axis', 'lane_geometry', 'y = next_y[0]', 'y = next_x[0]'),
    ('omitted_finish', 'lane_geometry', 'geometry.x + (x + x_correction)', 'geometry.x + x'),
    ('early_origin', 'lane_geometry', 'geometry.x + (x + x_correction)', '(geometry.x + x) + x_correction'),
    ('wrong_count', 'curve_bounds', 'x_inherited.high, 5 * pieces', 'x_inherited.high, pieces'),
    ('missing_error_term', 'curve_bounds', '_Interval.point(term_x.error)', '_Interval.point(0.0)'),
    ('missing_magnitude_term', 'curve_bounds', '_Interval.point(\n                term_x.rounded_value().magnitude()\n            )', '_Interval.point(0.0)'),
    ('ideal_magnitude', 'curve_bounds', 'term_x.rounded_value().magnitude()', 'term_x.value.magnitude()'),
    ('inward_magnitude', 'curve_bounds', 'x_magnitude.high, x_inherited.high', 'x_magnitude.low, x_inherited.high'),
    ('aux_value_mutation', 'curve_bounds', '    x.error = _sum2_error', '    x.value = _Interval.point(0.0)\n    x.error = _sum2_error'),
    ('aux_first_mutation', 'curve_bounds', '    x.error = _sum2_error', '    x.first = _Interval.point(0.0)\n    x.error = _sum2_error'),
    ('aux_second_mutation', 'curve_bounds', '    x.error = _sum2_error', '    x.second = _Interval.point(0.0)\n    x.error = _sum2_error'),
    ('aux_escape', 'curve_bounds', '    x.error = _sum2_error', '    leak(x_magnitude)\n    x.error = _sum2_error'),
    ('term_rebind', 'curve_bounds', '            x = x + term_x', '            term_x = term_y\n            x = x + term_x'),
    ('term_mutation', 'curve_bounds', '            x = x + term_x', '            term_x.error = 0.0\n            x = x + term_x'),
    ('term_branch_leak', 'curve_bounds', '        while i < 5:', '        while i < 5 and x_magnitude.high < 1.0:'),
    ('translation_sign', 'curve_bounds', '- Expression.constant(Float64(translation.x))', '+ Expression.constant(Float64(translation.x))'),
    ('envelope_legacy_sum', 'spiral_roundoff_proof', '_sum2_error(absolute_sum.high, inherited.high, count)', '_sequential_sum_error(absolute_sum.high, inherited.high, count)'),
    ('envelope_missing_n', 'spiral_roundoff_proof', 'n * _Interval.point(term.error)', '_Interval.point(term.error)'),
    ('envelope_missing_origin', 'spiral_roundoff_proof', '_ValueJet.constant(origin) + accumulated', 'accumulated'),
    ('envelope_unsupported_count', 'spiral_roundoff_proof', 'count > 320', 'count > 640'),
    ('eligibility_phase_leak', 'spiral_roundoff_proof', 'geometry.heading != 0.0', 'geometry.heading > 1.0'),
    ('eligibility_boundary_leak', 'spiral_roundoff_proof', 'domain.low <= 0.0', 'domain.low < 0.0'),
]


class Sum2SourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.semantic = sum2_contracts.verify(ROOT)
        cls.dependencies = source_contracts.verify_group(ROOT, 'canonical_accumulation')
        cls.pins = (ROOT/source_contracts.PINS).read_bytes()
        cls.moment_pins = (ROOT/'tools/carla_lane_oracle/spiral-moment-pins.json').read_bytes()

    def test_passing_candidate_and_exact_projection_counts(self):
        self.assertEqual(self.semantic['status'], 'PASS')
        projection = self.semantic['ideal_projection']
        for key, count in (('sum2_auxiliary_declarations', 4), ('sum2_term_definitions', 2),
                           ('sum2_auxiliary_updates', 4), ('sum2_error_writes', 2)):
            self.assertEqual(projection[key], count)
        self.assertFalse(self.semantic['native_codegen_qualified'])
        self.assertEqual(len(self.dependencies), 11)

    def semantic_change(self, module, change, reject=True):
        target = ROOT/'extensions/carla'/f'{module}.mojo'
        original = target.read_text()
        changed = change(original)
        self.assertNotEqual(original, changed)
        read = Path.read_text
        with patch.object(Path, 'read_text', lambda path, *a, **k:
                          changed if path == target else read(path, *a, **k)):
            if reject:
                with self.assertRaises((ValueError, SyntaxError)):
                    sum2_contracts.verify(ROOT)
            else:
                self.assertEqual(sum2_contracts.verify(ROOT)['status'], 'PASS')

    @staticmethod
    def docstring_decoy(text, name, before, after):
        frozen = sampled.function(text, name)
        changed = text.replace('def ' + name + '[', 'def  ' + name + '[', 1)
        changed = changed.replace(before, after, 1)
        opening = changed.index('"""')
        closing = changed.index('"""', opening + 3)
        return (changed[:closing] + '\n' + frozen +
                '\ndef _review_sentinel():\n    pass\n' + changed[closing:])

    def test_actual_ideal_declaration_not_docstring_decoy(self):
        self.semantic_change('curve_bounds', lambda text: self.docstring_decoy(
            text, '_spiral_expression', '    x.error = _sum2_error',
            '    x.value = _Interval.point(12345.0)\n    x.error = _sum2_error'))

    def test_actual_half_declaration_not_docstring_decoy(self):
        self.semantic_change('curve_interval', lambda text: self.docstring_decoy(
            text, '_stored_half',
            'result = value * _JetExpression[derivatives].constant(0.5)',
            'result = value * _JetExpression[derivatives].constant(0.25)'))

    def test_semantic_declaration_whitespace_selects_actual_node(self):
        for module, name in (('curve_bounds', '_spiral_expression'),
                             ('curve_interval', '_stored_half')):
            with self.subTest(module=module):
                self.semantic_change(module, lambda text: text.replace(
                    'def ' + name + '[', 'def  ' + name + '[', 1), reject=False)

    def test_half_helper_decorator_cannot_change_callable(self):
        self.semantic_change('curve_interval', lambda text: text.replace(
            'def _stored_half[', '@unreviewed_wrapper\ndef _stored_half[', 1))

    def test_half_import_cannot_be_redirected(self):
        self.semantic_change('curve_bounds', lambda text: text.replace(
            'from extensions.carla.curve_interval import (',
            'from unexpected.curve_interval import (', 1))

    def test_half_helper_cannot_be_rebound(self):
        for module in ('curve_bounds', 'curve_interval'):
            with self.subTest(module=module):
                self.semantic_change(module, lambda text:
                                     text + '\n_stored_half = other_callable\n')

    def test_helper_declarations_cannot_shadow_half(self):
        for module, suffix in (
                ('curve_bounds', '\ndef _stored_half[derivatives: Bool](value: '
                 '_JetExpression[derivatives]) -> _JetExpression[derivatives]:\n    return value\n'),
                ('curve_bounds', '\nstruct _stored_half:\n    pass\n'),
                ('curve_interval', '\nstruct _stored_half:\n    pass\n')):
            with self.subTest(module=module, suffix=suffix):
                self.semantic_change(module, lambda text: text + suffix)

    def test_helper_import_aliases_cannot_shadow_reviewed_functions(self):
        for module, suffix in (
                ('curve_bounds', '\nimport other as _sum2_error\n'),
                ('lane_geometry', '\nimport other as _sum2_update\n'),
                ('curve_interval', '\nimport other as _stored_half\n'),
                ('curve_interval', '\nfrom other import replacement as _stored_half\n'),
                ('curve_bounds', '\nfrom other import *\n')):
            with self.subTest(module=module, suffix=suffix):
                self.semantic_change(module, lambda text: text + suffix)

    def exercise(self, case):
        name, module, before, after = case
        target = ROOT/'extensions/carla'/f'{module}.mojo'
        original = target.read_text()
        self.assertIn(before, original, name)
        changed = original.replace(before, after, 1)
        self.assertNotEqual(original, changed)
        read = Path.read_text
        with patch.object(Path, 'read_text', lambda path, *a, **k:
                          changed if path == target else read(path, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'runtime source dependency changed'):
                source_contracts.verify_group(ROOT, 'canonical_accumulation')
            # This call has no source digest comparison. It must reject the
            # same attack independently of the frozen pin gate above.
            with self.assertRaises((ValueError, SyntaxError)):
                sum2_contracts.verify(ROOT)
        self.assertEqual((ROOT/source_contracts.PINS).read_bytes(), self.pins)
        self.assertEqual((ROOT/'tools/carla_lane_oracle/spiral-moment-pins.json').read_bytes(), self.moment_pins)


for case in CASES:
    def control(self, case=case):
        self.exercise(case)
    setattr(Sum2SourceTests, 'test_fixed_pin_and_semantic_' + case[0], control)


class Sum2BoundTests(unittest.TestCase):
    def test_range_and_count_limits(self):
        for count in (1, 2, 320, 2**30):
            for magnitude in (F(0), F(1, 2**1074), F(1), F(2**900)):
                with self.subTest(count=count, magnitude=magnitude):
                    result = sum2_error(magnitude, F(1, 2**100), count)
                    self.assertGreaterEqual(result, F(1, 2**100))
                    self.assertLess((count-1)*U, F(1, 2**23))
                    # Several-times-M intermediate bound remains far below
                    # binary64 overflow throughout the accepted proof domain.
                    self.assertLess(8*magnitude/(1-(count-1)*U), F(2**904))
        for count in (0, -1, 2**30+1, True, 1.5):
            with self.assertRaises(ValueError):
                sum2_error(F(1), F(0), count)
        for magnitude, inherited in ((-1, 0), (2**900+1, 0), (1, -1),
                                     (math.inf, 0), (-math.inf, 0), (math.nan, 0),
                                     (float.fromhex("0x1.fffffffffffffp1023"), 0),
                                     (1, math.inf), (1, -math.inf), (1, math.nan)):
            with self.assertRaises((ValueError, OverflowError)):
                sum2_error(magnitude, inherited, 2)

    def test_zero_and_single_term_shortcuts(self):
        self.assertEqual(sum2_error(0, F(3, 7), 2**30), F(3, 7))
        self.assertEqual(sum2_error(2**900, F(3, 7), 1), F(3, 7))
        self.assertEqual(to_word(sum2([-0.])), 0)
        self.assertEqual(to_word(sum2([0.])), 0)

    def test_exact_formula_and_inherited_error_are_independent(self):
        for count in (2, 5, 320, 2**30):
            gamma = F(count-1, 2**53-(count-1))
            self.assertEqual(sum2_error(F(7, 3), F(5, 13), count),
                             F(5, 13)+(F(1, 2**53)+gamma**2)*F(7, 3))
        self.assertGreater(sum2_error(1, F(1, 8), 5), sum2_error(1, 0, 5))

    def test_magnitude_and_inherited_counterexamples(self):
        values = [1., 2**-53, 2**-106]
        exact = sum(map(F, values))
        actual = F(sum2(values))
        self.assertGreater(abs(actual-exact), 0)
        self.assertLessEqual(abs(actual-exact), sum2_error(sum(map(lambda x: abs(F(x)), values)), 0, len(values)))
        # An inherited ideal-to-stored error remains even when accumulation is exact.
        stored = [1., -1.]
        ideal = [F(1)+F(1, 2**40), F(-1)]
        error = abs(F(sum2(stored))-sum(ideal))
        self.assertGreater(error, sum2_error(2, 0, 2))
        self.assertLessEqual(error, sum2_error(2, F(1, 2**40), 2))

    def test_omitted_residual_control(self):
        values = [1e16, 1., -1e16]
        ordinary = 0.0
        for value in values:
            ordinary += value
        self.assertEqual(ordinary, 0.)
        self.assertEqual(sum2(values), 1.)
        bound = sum2_error(sum(abs(F(x)) for x in values), 0, len(values))
        # The tighter theorem's exact-result term distinguishes the omitted
        # residual even when the uniform M replacement is intentionally loose.
        gamma = 2*U/(1-2*U)
        tight = U + gamma**2*sum(abs(F(x)) for x in values)
        self.assertGreater(abs(F(ordinary)-1), tight)
        self.assertLessEqual(abs(F(sum2(values))-1), bound)

    def test_binade_subnormal_and_extreme_finite_sequences(self):
        eta = from_word(1)
        sequences = ([1., 2**-53], [math.nextafter(2., 0.), 2**-53, -2.],
                     [math.ldexp(1., -1022), eta, -math.ldexp(1., -1022)],
                     [2.**898, 1., -2.**898], [2.**898, -2.**898, eta])
        for values in sequences:
            with self.subTest(values=values):
                exact = sum(map(F, values))
                magnitude = sum(abs(F(x)) for x in values)
                self.assertLessEqual(abs(F(sum2(values))-exact), sum2_error(magnitude, 0, len(values)))
                high = 0.
                for term in values:
                    next_high, residual = two_sum(high, term)
                    self.assertEqual(F(next_high)+F(residual), F(high)+F(term))
                    high = next_high


if __name__ == '__main__':
    unittest.main()
