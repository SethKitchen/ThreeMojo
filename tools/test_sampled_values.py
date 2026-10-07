#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compiler-free fail-closed controls, discovered by make test-tools."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT/'tools/carla_lane_oracle/check_sampled_values.py'
spec = importlib.util.spec_from_file_location('carla_sampled_value_checker', SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class SampledValueCorrespondenceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        pin = self.root/'tools/carla_lane_oracle/runtime-source-pins.json'
        pin.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT/'tools/carla_lane_oracle/runtime-source-pins.json', pin)
        moment_pin = self.root/'tools/carla_lane_oracle/spiral-moment-pins.json'
        shutil.copyfile(ROOT/'tools/carla_lane_oracle/spiral-moment-pins.json', moment_pin)
        guard_pin = self.root/'tools/carla_lane_oracle/sum2-guard-pins.json'
        shutil.copyfile(ROOT/'tools/carla_lane_oracle/sum2-guard-pins.json', guard_pin)
        from tools.carla_lane_oracle.source_contracts import GROUP_PATHS
        paths = set(GROUP_PATHS['canonical_accumulation'])
        paths.update(json.loads(guard_pin.read_text())['protected_inventory'])
        paths.update(GROUP_PATHS['optional_runtime'])
        paths.update('extensions/carla/' + name for name in
                     ('curve_trig.mojo', 'geometry.mojo', 'lane_value_bounds.mojo'))
        for name in paths:
            target = self.root/name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT/name, target)

    def change(self, name, before, after):
        path = self.root/'extensions/carla'/name
        text = path.read_text()
        self.assertIn(before, text)
        path.write_text(text.replace(before, after, 1))

    def rejected(self):
        with self.assertRaises((m.CheckError, SyntaxError)):
            m.verify(self.root)
        result = subprocess.run([sys.executable, '-O', '-B', str(SCRIPT),
                                 '--repo-root', str(self.root)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'FAIL:', result.stdout)

    def test_current_exact_correspondence(self):
        result = m.verify(self.root)
        self.assertEqual(result['copied_functions'], 8)
        self.assertEqual(result['dispatch_functions'], 6)

    def test_optimized_python_keeps_checks(self):
        result = subprocess.run([sys.executable, '-O', '-B', str(SCRIPT),
                                 '--repo-root', str(self.root)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(b'"status": "PASS"', result.stdout)

    def test_comments_and_redundant_grouping_preserve_correspondence(self):
        self.change('lane_value_bounds.mojo', 'var magnitude = value',
                    '# Documentation only.\n    var magnitude = (\n        value\n    )')
        m.verify(self.root)

    def test_changed_value_arithmetic_rejected(self):
        self.change('lane_value_bounds.mojo',
                    'var result = magnitude * _expression_polynomial(',
                    'var result = magnitude + _expression_polynomial(')
        self.rejected()

    def test_stale_copy_after_full_jet_change_rejected(self):
        self.change('curve_trig.mojo',
                    'var result = magnitude * _jet_polynomial(',
                    'var result = magnitude + _jet_polynomial(')
        self.rejected()

    def test_nonfinite_guard_change_rejected(self):
        self.change('lane_value_bounds.mojo', 'if not domain.is_finite():',
                    'if domain.is_finite():')
        self.rejected()

    def test_signed_zero_guard_change_rejected(self):
        self.change('lane_value_bounds.mojo', 'and not _sign_bit(one.tv)',
                    'and _sign_bit(one.tv)')
        self.rejected()

    def test_derivative_read_rejected(self):
        self.change('lane_value_bounds.mojo', 'var magnitude = value',
                    'var leaked = value.first\n    var magnitude = value')
        self.rejected()

    def test_type_and_primitive_changes_require_renewed_review(self):
        self.change('curve_interval.mojo', 'var error: Float64',
                    'var error: Float32')
        self.rejected()

    def test_derivative_free_alias_change_rejected(self):
        self.change('curve_interval.mojo',
                    'comptime _ValueJet = _JetExpression[False]',
                    'comptime _ValueJet = _JetExpression[True]')
        self.rejected()

    def test_missing_or_extra_helper_rejected(self):
        self.change('lane_value_bounds.mojo', 'def _sample_value(',
                    'def _sample_value_changed(')
        self.rejected()

    def test_wrong_shared_import_rejected(self):
        self.change('lane_value_bounds.mojo',
                    '    _ValueJet,',
                    '    _Jet as _ValueJet,')
        self.rejected()


    def test_commented_alias_cannot_spoof_actual_declaration(self):
        self.change('curve_interval.mojo',
                    'comptime _ValueJet = _JetExpression[False]',
                    '# comptime _ValueJet = _JetExpression[False]\ncomptime _ValueJet = _JetExpression[True]')
        self.rejected()

    def test_duplicate_actual_alias_rejected(self):
        self.change('curve_interval.mojo',
                    'comptime _ValueJet = _JetExpression[False]',
                    'comptime _ValueJet = _JetExpression[False]\ncomptime _ValueJet = _JetExpression[False]')
        self.rejected()

    def test_shared_generic_derivative_read_rejected(self):
        self.change('curve_trig.mojo',
                    'comptime Expression = _JetExpression[derivatives]\n    var domain = value.rounded_value()',
                    'comptime Expression = _JetExpression[derivatives]\n    var domain = value.first')
        self.rejected()

    def test_full_jet_bridge_change_rejected(self):
        self.change('curve_trig.mojo',
                    'return _expression_polynomial(coefficients, x)',
                    'return _expression_polynomial(coefficients, x + x)')
        self.rejected()

    def test_target_decorator_not_dropped_by_function_slice(self):
        self.change('lane_value_bounds.mojo',
                    'def _uncertain_value(', '@no_inline\ndef _uncertain_value(')
        self.rejected()

    def test_copied_source_decorator_change_rejected(self):
        self.change('curve_trig.mojo',
                    'def _atan_branch(', '@no_inline\ndef _atan_branch(')
        self.rejected()

    def test_full_reference_dispatch_change_rejected(self):
        path = self.root/'extensions/carla/curve_bounds.mojo'
        text = path.read_text()
        start = text.index('def _reference_jet_capture[')
        before = text[start:]
        self.assertIn('if geometry.kind == LINE:', before)
        after = before.replace('if geometry.kind == LINE:',
                               'if geometry.kind == PARAM_POLY3:', 1)
        path.write_text(text[:start] + after)
        self.rejected()

    def test_full_lane_dispatch_change_rejected(self):
        path = self.root/'extensions/carla/curve_bounds.mojo'
        text = path.read_text()
        start = text.index('def _lane_jet_model_proof[')
        before = text[start:]
        self.assertIn('if record.geometry.kind == ARC:', before)
        after = before.replace('if record.geometry.kind == ARC:',
                               'if record.geometry.kind == PARAM_POLY3:', 1)
        path.write_text(text[:start] + after)
        self.rejected()


    def test_union_setup_before_return_is_bound(self):
        path = self.root/'extensions/carla/curve_bounds.mojo'
        text = path.read_text()
        start = text.index('def _union_points[')
        end = text.index('def _arc_offset_jet(', start)
        region = text[start:end]
        self.assertIn('    return (', region)
        region = region.replace('    one: Tuple[', '    var one: Tuple[', 1)
        region = region.replace('    return (', '    one = two\n    return (', 1)
        path.write_text(text[:start] + region + text[end:])
        self.rejected()

    def test_reference_scalar_alias_routing_is_bound(self):
        self.change('curve_bounds.mojo', '    _curve_cos,',
                    '    _curve_sin as _curve_cos,')
        self.rejected()

    def test_primitive_import_routing_is_bound(self):
        path = self.root/'extensions/carla/curve_interval.mojo'
        text = path.read_text()
        self.assertIn('from std.math import ', text)
        text = text.replace('from std.math import ', 'from unrelated.math import ', 1)
        path.write_text(text)
        self.rejected()


    def test_type_flag_query_is_forbidden(self):
        self.change('lane_value_bounds.mojo', '    var magnitude = value',
                    '    comptime if _ValueJet.derivatives:\n        var forbidden = 0.0\n    var magnitude = value')
        with self.assertRaisesRegex(m.CheckError, 'derivative-field/flag'):
            m.verify(self.root)
        self.rejected()

    def test_matched_derivative_sensitive_edits_still_require_review(self):
        self.change('curve_trig.mojo', '    var magnitude = value',
                    '    var magnitude = value\n    comptime if _Jet.derivatives:\n        magnitude = _Jet.constant(0.0)')
        self.change('lane_value_bounds.mojo', '    var magnitude = value',
                    '    var magnitude = value\n    comptime if _ValueJet.derivatives:\n        magnitude = _ValueJet.constant(0.0)')
        self.rejected()


if __name__ == '__main__':
    unittest.main()
