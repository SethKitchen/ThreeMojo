#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Fixed-pin mutations on a genuinely passing reviewed runtime candidate.

Discovered by the unchanged official nested test-tools discovery. These tests
verify source-integrity detection, not production mathematical correctness.
"""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import check_sampled_values as sampled
import check_runtime_support as runtime
import heading_correspondence
import sum2_guard_contracts
import source_contracts as contracts

ROOT = Path(__file__).resolve().parents[2]
TARGET = 'lane_value_bounds.mojo'


def replace_in_function(text, name, before, after):
    matches = list(re.finditer(r'(?m)^def ' + re.escape(name.rstrip('(')) + r'[\[(]', text))
    if len(matches) != 1:
        raise AssertionError('ambiguous mutation target: ' + name)
    begin = matches[0].start()
    match = re.search(r'(?m)^(?:def |@)', text[begin+4:])
    end = begin+4+match.start() if match else len(text)
    body = text[begin:end]
    if before not in body:
        raise AssertionError('mutation not applied: ' + name + ': ' + before)
    return text[:begin] + body.replace(before, after, 1) + text[end:]


# name, gate, module, function, exact before, exact after. None means file-wide.
CASES = [
    ('half_factor', 'stored_arithmetic', 'curve_interval.mojo', '_stored_half', 'constant(0.5)', 'constant(0.25)'),
    ('half_operand', 'stored_arithmetic', 'curve_interval.mojo', '_stored_half', 'result = value *', 'result = value +'),
    ('half_inherited_error', 'stored_arithmetic', 'curve_interval.mojo', '_stored_half', '_Interval.point(value.error)', '_Interval.point(0.0)'),
    ('half_minimum', 'stored_arithmetic', 'curve_interval.mojo', '_stored_half', 'UInt64(623)', 'UInt64(622)'),
    ('half_maximum', 'stored_arithmetic', 'curve_interval.mojo', '_stored_half', 'UInt64(1423)', 'UInt64(1424)'),
    ('half_nonfinite', 'stored_arithmetic', 'curve_interval.mojo', '_stored_half', 'not value.value.is_finite()', 'value.value.is_finite()'),
    ('half_unordered', 'stored_arithmetic', 'curve_interval.mojo', '_stored_half', 'value.value.low > value.value.high', 'value.value.low < value.value.high'),
    ('half_negative_error', 'stored_arithmetic', 'curve_interval.mojo', '_stored_half', 'value.error < 0.0', 'value.error > 0.0'),
    ('difference_operand', 'stored_arithmetic', 'curve_interval.mojo', '_stored_difference', 'result = one - two', 'result = two - one'),
    ('difference_endpoint', 'stored_arithmetic', 'curve_interval.mojo', '_stored_difference', 'left.low >= right.high * 0.5', 'left.low >= right.low * 0.5'),
    ('difference_factor', 'stored_arithmetic', 'curve_interval.mojo', '_stored_difference', 'right.low * 2.0', 'right.low * 4.0'),
    ('difference_inherited_error', 'stored_arithmetic', 'curve_interval.mojo', '_stored_difference', 'one.error + two.error', 'one.error - two.error'),
    ('difference_zero_guard', 'stored_arithmetic', 'curve_interval.mojo', '_stored_difference', 'one.error == 0.0 and two.error == 0.0', 'one.error == 0.0 or two.error == 0.0'),
    ('difference_fallback', 'stored_arithmetic', 'curve_interval.mojo', '_stored_difference', 'return result', 'return one'),
    ('blend_difference_sign', 'stored_arithmetic', 'curve_interval.mojo', '_stored_blend_error', '_Interval.point(one), -_Interval.point(two)', '_Interval.point(one), _Interval.point(two)'),
    ('blend_complement_weight', 'stored_arithmetic', 'curve_interval.mojo', '_stored_blend_error', '_Interval.point(abs(two))', '_Interval.point(abs(one))'),
    ('blend_rate_error', 'stored_arithmetic', 'curve_interval.mojo', '_stored_blend_error', '_Interval.point(rate.error)', '_Interval.point(0.0)'),
    ('blend_complement_error', 'stored_arithmetic', 'curve_interval.mojo', '_stored_blend_error', '+ _Interval.point(abs(two)) * _Interval.point(complement_error)', '+ _Interval.point(0.0)'),
    ('blend_first_error', 'stored_arithmetic', 'curve_interval.mojo', '_stored_blend_error', '+ _Interval.point(first_error)\n        + _Interval.point(second_error)\n        + _Interval.point(final_error)', '+ _Interval.point(second_error)\n        + _Interval.point(final_error)'),
    ('blend_second_error', 'stored_arithmetic', 'curve_interval.mojo', '_stored_blend_error', '+ _Interval.point(second_error)\n        + _Interval.point(final_error)', '+ _Interval.point(final_error)'),
    ('blend_final_error', 'stored_arithmetic', 'curve_interval.mojo', '_stored_blend_error', '+ _Interval.point(final_error)', '+ _Interval.point(0.0)'),
    ('blend_subnormal_support', 'stored_arithmetic', 'curve_interval.mojo', '_stored_blend_error', 'UInt64(623)', 'UInt64(1)'),
    ('blend_negative_error', 'stored_arithmetic', 'curve_interval.mojo', '_stored_blend_error', 'rate.error < 0.0', 'rate.error > 0.0'),
    ('blend_finite_error', 'stored_arithmetic', 'curve_interval.mojo', '_stored_blend_error', 'not isfinite(rate.error)', 'isfinite(rate.error)'),
    ('bridge_error_reset', 'stored_arithmetic', 'curve_interval.mojo', '_without_derivatives', 'value.error', '0.0'),
    ('bridge_round_ideal', 'stored_arithmetic', 'curve_interval.mojo', '_without_derivatives', 'value.value,', 'value.rounded_value(),'),
    ('primitive_qualifier', 'stored_arithmetic', 'curve_interval.mojo', None, 'comptime if not Self.derivatives:', 'if not Self.derivatives:'),
    ('atan_branch', 'sampled', TARGET, '_atan_value_branch', 'magnitude * _expression_polynomial', 'magnitude + _expression_polynomial'),
    ('atan_guard', 'sampled', TARGET, '_atan_value', 'domain.low < 0.0', 'domain.low <= 0.0'),
    ('atan2_guard', 'sampled', TARGET, '_atan2_value', 'dx.low > 0.0', 'dx.low >= 0.0'),
    ('polynomial_operand', 'sampled', TARGET, '_polynomial_value', '- _ValueJet.constant(shift)', '+ _ValueJet.constant(shift)'),
    ('unknown_interval', 'sampled', TARGET, '_unknown_value_point', '_Interval.whole()', '_Interval.point(0.0)'),
    ('geometry_clamp', 'sampled', TARGET, '_value_geometry_distance', 'domain.low >= geometry.length', 'domain.low > geometry.length'),
    ('sample_blend_operand', 'sampled', TARGET, '_sample_blend_value', 'constant(one)', 'constant(two)'),
    ('sample_index', 'sampled', TARGET, '_sample_value', 'geometry.samples[index + 1]', 'geometry.samples[index]'),
    ('sample_shared_rate', 'sampled', TARGET, '_sample_blend_value', '_stored_blend_error(rate, one, two)', '_stored_blend_error(_ValueJet.constant(0.0), one, two)'),
    ('sample_negative_guard', 'sampled', TARGET, '_sample_blend_value', 'coupled_error >= 0.0', 'coupled_error <= 0.0'),
    ('sinc_boundary', 'sampled', TARGET, '_sinc_value', 'domain.high <= _QUARTER_PI', 'domain.high < _QUARTER_PI'),
    ('sinc_coefficients', 'sampled', TARGET, '_sinc_value', '_SIN_COEFFICIENTS', '_ATAN_COEFFICIENTS'),
    ('arc_overflow', 'sampled', TARGET, '_arc_offset_value', 'if not isfinite(radius):', 'if isfinite(radius):'),
    ('arc_translation', 'sampled', TARGET, '_arc_offset_value', '- _ValueJet.constant(Float64(translation.x))', '+ _ValueJet.constant(Float64(translation.x))'),
    ('arc_result_index', 'sampled', TARGET, '_arc_offset_value', 'chord * trig[1]', 'chord * trig[0]'),
    ('arc_unapproved_half', 'sampled', TARGET, '_arc_offset_value', 'turn * _ValueJet.constant(0.5)', '_stored_half(turn)'),
    ('constant_phase', 'sampled', TARGET, '_constant_sincos_value', 'abs(heading) > _PHASE_LIMIT', 'abs(heading) < _PHASE_LIMIT'),
    ('constant_derivative_projection', 'sampled', TARGET, '_constant_sincos_value', 'unknown, unknown, 0.0', 'unknown, unknown, 1.0'),
    ('sampled_specialization', 'sampled', TARGET, '_sampled_lane_value_bound', '_lane_value_bound_impl[False]', '_lane_value_bound_impl[True]'),
    ('broad_specialization', 'sampled', TARGET, '_lane_value_bound(', '_lane_value_bound_impl[True]', '_lane_value_bound_impl[False]'),
    ('spiral_bridge', 'sampled', TARGET, '_lane_value_bound(', '_lane_jet(road, section, lane, low, high)', '_lane_jet(road, section, lane, low, low)'),
    ('spiral_missing_record', 'sampled', TARGET, '_lane_value_bound(', 'at >= 0', 'at > 0'),
    ('target_qualifier', 'sampled', TARGET, '_lane_value_bound_impl', 'comptime if all_geometry:', 'if all_geometry:'),
    ('target_generic', 'sampled', TARGET, '_lane_value_bound_impl', 'all_geometry: Bool', 'all_geometry: Int'),
    ('missing_helper', 'sampled', TARGET, None, 'def _sinc_value(', 'def _renamed_sinc_value('),
    ('import_alias', 'sampled', TARGET, None, '    _stored_half,', '    _stored_difference as _stored_half,'),
    ('top_level_execution', 'sampled', TARGET, None, 'def _uncertain_value(', 'unexpected()\n\ndef _uncertain_value('),
    ('derivative_read', 'sampled', TARGET, '_sinc_value', 'var domain = value.rounded_value().absolute()', 'var domain = value.first.absolute()'),
    ('table_count_support', 'eligibility', 'spiral_moment_table.mojo', None, 'pieces > 64', 'pieces > 65'),
    ('roundoff_count_support', 'eligibility', 'spiral_roundoff_proof.mojo', None, 'pieces > 64', 'pieces > 65'),
    ('roundoff_accumulation', 'eligibility', 'spiral_roundoff_proof.mojo', None, 'count > 320', 'count > 325'),
    ('root_containment', 'eligibility', 'spiral_domain_proof.mojo', '_spiral_proof_matches', 'high > root_high', 'high < root_high'),
    ('clamp_support', 'eligibility', 'spiral_domain_proof.mojo', '_spiral_proof_matches', 'domain.low <= 0.0', 'domain.low < 0.0'),
    ('two_count_join', 'eligibility', 'spiral_domain_proof.mojo', '_spiral_proof_matches', 'counts[1] - counts[0] > 1', 'counts[1] - counts[0] > 2'),
    ('quadrant_support', 'eligibility', 'spiral_moment_proof.mojo', '_all_spiral_nodes_quadrant_zero', 'floor(selection.low) == 0.0 and', 'floor(selection.low) == 0.0 or'),
    ('proof_x_sign', 'translation', 'spiral_domain_proof.mojo', '_spiral_proof_branch', '- _Jet.constant(Float64(translation.x))', '+ _Jet.constant(Float64(translation.x))'),
    ('proof_y_sign', 'translation', 'spiral_domain_proof.mojo', '_spiral_proof_branch', '+ _Jet.constant(Float64(translation.y))', '- _Jet.constant(Float64(translation.y))'),
    ('proof_x_infinite_error', 'translation', 'spiral_domain_proof.mojo', '_spiral_proof_branch', 'x.error = inf[DType.float64]()', 'x.error = 0.0'),
    ('proof_y_infinite_error', 'translation', 'spiral_domain_proof.mojo', '_spiral_proof_branch', 'y.error = inf[DType.float64]()', 'y.error = 0.0'),
    ('proof_translation_conjunction', 'translation', 'spiral_domain_proof.mojo', '_spiral_proof_branch', 'translation.x != 0.0 or translation.y != 0.0', 'translation.x != 0.0 and translation.y != 0.0'),
    ('expansion_infinite_error', 'translation', 'curve_bounds.mojo', '_try_proof_expansion_jet', 'result.error = inf[DType.float64]()', 'result.error = 0.0'),
    ('expansion_final_zero_query', 'translation', 'curve_bounds.mojo', '_try_proof_expansion_jet', 'point, Vector3(0, 0, 0), scale', 'point, location, scale'),
    ('expansion_count_guard', 'translation', 'curve_bounds.mojo', '_try_proof_expansion_jet', 'counts[0] != counts[1]', 'counts[0] == counts[1]'),
    ('ideal_error_mode', 'translation', 'curve_bounds.mojo', '_lane_jet_model_proof', '_finite_spiral_ideal_branch(', '_finite_spiral_moment_branch('),
    ('proof_fallback', 'translation', 'curve_bounds.mojo', '_lane_jet_model_proof', 'if reused:', 'if not reused:'),
    ('global_domain_error', 'translation', 'lane_refinement.mojo', '_global_lower', 'taylor.low - domain.error', 'taylor.low - center.error'),
    ('table_work_22', 'support', 'spiral_moment_table.mojo', '_try_lookup_spiral_moments', 'var work = 22', 'var work = 21'),
    ('proof_work_1024', 'translation', 'curve_bounds.mojo', '_try_lane_envelope_capture', '1024 * branches', '1023 * branches'),
    ('work_debit', 'support', 'lane_refinement.mojo', '_checked_center', 'terms += work', 'terms += 1'),
    ('work_guard', 'support', 'lane_refinement.mojo', '_checked_center', 'terms > max_terms - work', 'terms >= max_terms - work'),
]


for _file, _function in heading_correspondence.CONSUMERS.items():
    CASES.append(('heading_stale_half_' + _file[:-5], 'eligibility', _file, _function,
                  '_stored_half(rate) * d', '_Jet.constant(0.5) * rate * d'))
    CASES.append(('ideal_u_misplaced_half_' + _file[:-5], 'eligibility', _file, _function,
                  '_Jet.constant(0.5) * rate * d * d', '_stored_half(rate) * d * d'))
CASES.append(('eligibility_misplaced_half', 'eligibility', 'spiral_moment_proof.mojo',
              '_all_spiral_nodes_quadrant_zero', '_Jet.constant(0.5) * rate * t',
              '_stored_half(rate) * t'))


class FixedRuntimeCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Positive baselines first. Mutations cannot pass by all failing an
        # obsolete pin: the exact same scripts and pin bytes accept this tree.
        cls.sampled_positive = sampled.verify(ROOT)
        cls.support_positive = runtime.verify(ROOT)
        cls.pin = (ROOT/contracts.PINS).read_bytes()

    def exercise(self, case):
        name, gate, file, function, before, after = case
        path = ROOT/'extensions/carla'/file
        original = path.read_text()
        if function:
            changed = replace_in_function(original, function, before, after)
        else:
            self.assertIn(before, original)
            changed = original.replace(before, after, 1)
        self.assertNotEqual(original, changed)
        read = Path.read_text
        def read_changed(current, *args, **kwargs):
            return changed if current == path else read(current, *args, **kwargs)
        with patch.object(Path, 'read_text', read_changed):
            if gate == 'sampled':
                with self.assertRaises((sampled.CheckError, SyntaxError)):
                    sampled.verify(ROOT)
            else:
                with self.assertRaisesRegex(ValueError, 'runtime source dependency changed \\[' + gate + '\\]'):
                    contracts.verify_group(ROOT, gate)
        self.assertEqual((ROOT/contracts.PINS).read_bytes(), self.pin)

    def test_positive_reports_name_real_root_and_keep_primitive(self):
        self.assertEqual(self.sampled_positive['copied_functions'], 8)
        self.assertEqual(self.sampled_positive['dispatch_functions'], 6)
        self.assertEqual(self.sampled_positive['additional_source_pairs'], 3)
        self.assertEqual(self.support_positive['repo_root'], str(ROOT))

    def test_benign_comments_preserve_all_gates(self):
        read = Path.read_text
        def annotated(path, *args, **kwargs):
            text = read(path, *args, **kwargs)
            return text + '\n# Benign source commentary\n' if path.suffix == '.mojo' else text
        with patch.object(Path, 'read_text', annotated):
            sampled.verify(ROOT)
            runtime.verify(ROOT)

    def test_matched_wrong_full_and_value_blends_reject_reference(self):
        read = Path.read_text
        paths = {ROOT/'extensions/carla/curve_bounds.mojo', ROOT/'extensions/carla'/TARGET}
        def wrong(path, *args, **kwargs):
            text = read(path, *args, **kwargs)
            return text.replace('constant(one)', 'constant(two)', 1) if path in paths else text
        with patch.object(Path, 'read_text', wrong):
            with self.assertRaisesRegex(sampled.CheckError, 'reference module changed'):
                sampled.verify(ROOT)

    def test_exact_dependency_schema_and_path_sets(self):
        original = json.loads(self.pin)
        cases = []
        for group in contracts.GROUP_PATHS:
            value = json.loads(self.pin); value['groups'][group].pop(next(iter(value['groups'][group])))
            cases.append(value)
        value = json.loads(self.pin); value['groups']['stored_arithmetic']['../unexpected.mojo'] = '0'*64; cases.append(value)
        value = json.loads(self.pin); value['groups']['unexpected'] = {}; cases.append(value)
        value = json.loads(self.pin); value['schema'] = True; cases.append(value)
        read = Path.read_text
        for value in cases:
            with self.subTest(value=value), patch.object(Path, 'read_text',
                lambda p, *a, **k: json.dumps(value) if p == ROOT/contracts.PINS else read(p, *a, **k)):
                with self.assertRaises(ValueError):
                    contracts.verify_group(ROOT, 'stored_arithmetic')

    def test_heading_semantic_projection_keeps_distinct_graphs(self):
        positive = heading_correspondence.verify(ROOT)
        self.assertEqual(positive['heading_consumers'], 3)
        read = Path.read_text
        cases = []
        for filename, name in heading_correspondence.CONSUMERS.items():
            cases.extend((
                (filename, name, '_stored_half(rate) * d',
                 '_Jet.constant(0.5) * rate * d', 'scalar heading differs'),
                (filename, name, '_Jet.constant(0.5) * rate * d * d',
                 '_stored_half(rate) * d * d', 'ideal u graph changed'),
                (filename, name, 'geometry.curvature_end - geometry.curvature_start',
                 'geometry.curvature_end + geometry.curvature_start', 'stored rate differs'),
            ))
        cases.append(('spiral_moment_proof.mojo', '_all_spiral_nodes_quadrant_zero',
                      '_Jet.constant(0.5) * rate * t', '_stored_half(rate) * t',
                      'original eligibility phase graph changed'))
        for filename, name, before, after, diagnostic in cases:
            path = ROOT/'extensions/carla'/filename
            changed = replace_in_function(path.read_text(), name, before, after)
            with self.subTest(filename=filename, diagnostic=diagnostic), patch.object(
                Path, 'read_text', lambda p, *a, **k: changed if p == path else read(p, *a, **k)):
                # Independent of the token hash failure, this semantic check
                # distinguishes fresh heading, ideal u, and eligibility roles.
                with self.assertRaisesRegex(ValueError, diagnostic):
                    heading_correspondence.verify(ROOT)
        self.assertEqual((ROOT/contracts.PINS).read_bytes(), self.pin)

    def test_duplicate_dependency_pin_key_rejects(self):
        read = Path.read_text
        duplicated = self.pin.decode().replace('"schema": 1,', '"schema": 1, "schema": 1,', 1)
        with patch.object(Path, 'read_text',
            lambda p, *a, **k: duplicated if p == ROOT/contracts.PINS else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'duplicate runtime source pin key'):
                contracts.verify_group(ROOT, 'stored_arithmetic')

    def test_cli_positive_negative_and_missing_inputs_normal_and_optimized(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            paths = set(p for group in contracts.GROUP_PATHS.values() for p in group)
            paths.add('extensions/carla/lane_value_bounds.mojo')
            paths.add(str(contracts.PINS))
            paths.add('tools/carla_lane_oracle/spiral-moment-pins.json')
            paths.add('tools/carla_lane_oracle/sum2-guard-pins.json')
            paths.update(json.loads((ROOT/sum2_guard_contracts.PINS).read_text())['protected_inventory'])
            for name in paths:
                to = root/name; to.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT/name, to)
            for mode in ([], ['-O']):
                for script in ('check_sampled_values.py', 'check_runtime_support.py'):
                    command = [sys.executable, *mode, '-B', str(Path(__file__).parent/script), '--repo-root', str(root)]
                    positive = subprocess.run(command, capture_output=True, text=True)
                    self.assertEqual(positive.returncode, 0, positive.stdout+positive.stderr)
                    target = root/'extensions/carla/curve_interval.mojo'; text = target.read_text()
                    target.write_text(text.replace('result = one - two', 'result = two - one', 1))
                    rejected = subprocess.run(command, capture_output=True, text=True)
                    self.assertNotEqual(rejected.returncode, 0); self.assertIn('FAIL:', rejected.stdout)
                    target.write_text(text)
                    pin = root/contracts.PINS; data = pin.read_bytes(); pin.unlink()
                    missing = subprocess.run(command, capture_output=True, text=True)
                    self.assertNotEqual(missing.returncode, 0); self.assertIn('FAIL:', missing.stdout)
                    pin.write_bytes(data)


for _case in CASES:
    def test(self, case=_case):
        self.exercise(case)
    setattr(FixedRuntimeCandidateTests, 'test_mutation_' + _case[0], test)


if __name__ == '__main__':
    unittest.main()
