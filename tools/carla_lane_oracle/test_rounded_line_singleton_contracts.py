# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Producer, binding, predecessor, and consumer mutation controls."""
from pathlib import Path
import unittest
from unittest.mock import patch
import rounded_line_singleton_contracts as contract

ROOT = Path(__file__).resolve().parents[2]


class RoundedLineSingletonContracts(unittest.TestCase):
    def test_exact_positive(self):
        contract.verify(ROOT)

    def test_premise_mutations(self):
        cases = [
            ('curve_rounded_arc', 'return Self.bounds(value, value)', 'return Self.bounds(value, value + 1.0)'),
            ('curve_rounded_arc', '_rounded_add(self.high, other.high)', '_rounded_add(self.high, other.high) + 1.0'),
            ('curve_rounded_arc', 'var d = _rounded_multiply(self.high, other.high)', 'var d = _rounded_multiply(self.high, other.high) + 1.0'),
            ('curve_rounded_arc', 'return self + (-other)', 'return self.hull(other)'),
            ('curve_rounded_arc', 'return Self(-self.high, -self.low, self.known)', 'return Self(-self.low, self.high, self.known)'),
            ('curve_rounded_arc', 'return _RoundedBox.point(polynomial.a)', 'return _RoundedBox.bounds(polynomial.a, polynomial.a + 1.0)'),
            ('curve_rounded_arc', '@no_inline\ndef _rounded_add', 'def _rounded_add'),
            ('curve_rounded_arc', '@no_inline\ndef _rounded_multiply', 'def _rounded_multiply'),
            ('curve_rounded_arc', 'from std.math import fma, isfinite', 'from fake_math import fma, isfinite'),
            ('curve_rounded_arc', 'and low <= high', 'and True'),
            ('curve_rounded_arc', 'abs(value) >= low', 'abs(value) > 0.0'),
            ('curve_rounded_line', 'if not lane_offset.known or not elevation.known:', 'if not lane_offset.known:'),
            ('curve_rounded_line', 'if not offset.known:', 'if False:'),
            ('curve_rounded_line', 'if not width.known:', 'if False:'),
            ('curve_rounded_line', 'min(max(d.high, 0.0), length)', 'max(d.high, length)'),
            ('curve_rounded_line', 'or length < 0.0:', 'or length > 0.0:'),
            ('curve_rounded_line', 'from extensions.carla.curve_rounded_arc import (', 'from extensions.carla.fake_rounded_arc import ('),
            ('curve_rounded_line', 'def _rounded_line_axis_context(', 'def _unreviewed_line_axis_context('),
            ('curve_rounded_line', 'cosine != 0.0', 'True'),
            ('curve_rounded_line', 'sine != 0.0', 'True'),
            ('curve_trig', 'from std.math import atan, atan2, cos, floor, inf, isfinite, isnan, sin', 'from fake_math import atan, atan2, cos, floor, inf, isfinite, isnan, sin'),
            ('road_info', 'def info_index[', 'def changed_info_index['),
            ('road', 'def _check_lane(', 'def _unchecked_lane('),
            ('lane_refinement', 'from extensions.carla.curve_sum2 import _require_sum2_environment', 'from fake_environment import _require_sum2_environment'),
            ('lane_refinement', '_require_sum2_environment()', 'pass'),
            ('curve_sum2', 'def _sum2_supported_environment()', 'def _unchecked_environment()'),
            ('lane_refinement', 'terms += 1\n    var context = _rounded_line_axis_context', 'terms += 0\n    var context = _rounded_line_axis_context'),
        ]
        read = Path.read_text
        for module, old, new in cases:
            path = ROOT / ('extensions/carla/' + module + '.mojo')
            original = read(path)
            with self.subTest(module=module, old=old):
                self.assertIn(old, original)
                changed = original.replace(old, new)
                with patch.object(Path, 'read_text', lambda p, *a, **k: changed if p == path else read(p, *a, **k)):
                    with self.assertRaises((ValueError, RuntimeError)):
                        contract.verify_premises(ROOT)

    def test_polynomial_and_reference_mutation(self):
        for path, old, new in [
            ('extensions/carla/polynomial.mojo', 'var a: Float64', 'var a: Float32'),
            ('tests/test_carla_rounded_line_singleton_contract.mojo', 'offset.low != offset.high', 'False'),
        ]:
            target = ROOT/path
            read = Path.read_text
            original = read(target)
            self.assertIn(old, original)
            with patch.object(Path, 'read_text', lambda p, *a, **k: original.replace(old, new) if p == target else read(p, *a, **k)):
                with self.assertRaises((ValueError, RuntimeError)):
                    contract.verify_premises(ROOT)

    def test_record_refresh_is_not_approval(self):
        path = ROOT / contract.MIGRATION
        read = Path.read_bytes
        with patch.object(Path, 'read_bytes', lambda p, *a, **k: read(p, *a, **k) + b' ' if p == path else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'unreviewed migration'):
                contract.verify(ROOT)


if __name__ == '__main__':
    unittest.main()
