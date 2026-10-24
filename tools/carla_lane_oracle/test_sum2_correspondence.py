#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Fixed-pin and hash-independent controls for the Sum2 source migration.

No test executes Mojo. The exact same candidate must pass before mutation.
Unittest assertions and explicit errors stay active under optimized Python.
"""
from pathlib import Path
import unittest
from unittest.mock import patch

import check_sampled_values as sampled
import full_audit_cleanup_contracts as cleanup
import source_contracts
import sum2_contracts

ROOT = Path(__file__).resolve().parents[2]


# This module's fixed byte/line/body assertions describe the historical main
# graph. The #333 current graph has separate physical admission/mutation tests.
_CURRENT_SOURCE_ROOT = ROOT


def setUpModule():
    global ROOT
    import _full_audit_test_fixtures as historical_fixtures
    owner = type('HistoricalModuleFixture', (), {
        'addCleanup': staticmethod(unittest.addModuleCleanup)})()
    ROOT = historical_fixtures.copy_historical_boundary_root(owner, _CURRENT_SOURCE_ROOT)
    unittest.addModuleCleanup(globals().__setitem__, 'ROOT', _CURRENT_SOURCE_ROOT)

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
                target = ROOT/'extensions/carla'/f'{module}.mojo'
                original = target.read_text()
                self.assertEqual(original.count('def ' + name + '['), 1)
                changed = original.replace('def ' + name + '[', 'def  ' + name + '[', 1)
                self.assertNotEqual(original, changed)
                self.assertEqual(source_contracts.token_sha256(changed),
                                 source_contracts.token_sha256(original))
                # These are the actual production declaration selectors. The
                # positive is semantic selection, not full raw-source admission.
                self.assertEqual(sampled.dump(sampled.unique_function(
                                     sampled.syntax_tree(changed), name)),
                                 sampled.dump(sampled.unique_function(
                                     sampled.syntax_tree(original), name)))
                read = Path.read_text
                with patch.object(Path, 'read_text', lambda path, *a, **k:
                                  changed if path == target else read(path, *a, **k)):
                    with self.assertRaises(ValueError) as raised:
                        sum2_contracts.verify(ROOT)
                error = raised.exception
                self.assertIs(type(error), ValueError)
                message = ('full-audit cleanup successor: consumed operation text changed: '
                           + 'extensions/carla/' + module + '.mojo')
                # The retained current Map gate captures both physical inputs
                # before the Sum2 semantic projection can select declarations.
                self.assertEqual(str(error),
                                 'Sum2 complete guarded caller changed or routing changed: '
                                 'map (' + message + ')')
                error = error.__cause__
                self.assertIs(type(error), cleanup._OperationCoherenceError)
                self.assertEqual(str(error), message)
                self.assertIs(type(error.__cause__), cleanup.ContractError)
                self.assertEqual(str(error.__cause__), message)

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


if __name__ == '__main__':
    unittest.main()
