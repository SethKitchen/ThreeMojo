#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Source-bound guard controls; injected outcomes never stand in for native FP probes."""
import ast
import copy
import json
import math
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import check_sampled_values as sampled
import source_contracts
import sum2_contracts
import sum2_guard_contracts as guard

ROOT = Path(__file__).resolve().parents[2]
# name, module, actual function, exact before, exact after.
CASES = [
    ('volatile_one', 'curve_sum2', '_sum2_supported_environment', 'one_slot.unsafe_load[volatile=True]()', 'one_slot.unsafe_load[volatile=False]()'),
    ('volatile_half', 'curve_sum2', '_sum2_supported_environment', 'half_slot.unsafe_load[volatile=True]()', 'half_slot.unsafe_load[volatile=False]()'),
    ('volatile_tiny', 'curve_sum2', '_sum2_supported_environment', 'tiny_slot.unsafe_load[volatile=True]()', 'tiny_slot.unsafe_load[volatile=False]()'),
    ('probe_offset', 'curve_sum2', '_sum2_supported_environment', 'one_slot[unsafe_offset=0]', 'one_slot[unsafe_offset=1]'),
    ('always_true', 'curve_sum2', '_sum2_supported_environment', '    var one_slot', '    return True\n    var one_slot'),
    ('always_false', 'curve_sum2', '_sum2_supported_environment', '    var one_slot', '    return False\n    var one_slot'),
    ('wrong_half_word', 'curve_sum2', '_sum2_supported_environment', '0x3CA0000000000000', '0x3C90000000000000'),
    ('wrong_one_word', 'curve_sum2', '_sum2_supported_environment', '0x3FF0000000000000', '0x3FF0000000000001'),
    ('zero_tiny', 'curve_sum2', '_sum2_supported_environment', 'tiny_slot[unsafe_offset=0] = UInt64(1)', 'tiny_slot[unsafe_offset=0] = UInt64(0)'),
    ('wrong_odd_input', 'curve_sum2', '_sum2_supported_environment', 'one_word + UInt64(1)', 'one_word + UInt64(2)'),
    ('wrong_odd_expected', 'curve_sum2', '_sum2_supported_environment', 'UInt64(0x3FF0000000000002)', 'UInt64(0x3FF0000000000001)'),
    ('tie_guard_and', 'curve_sum2', '_sum2_supported_environment', 'or bitcast[\n        DType.uint64\n    ](odd[0])', 'and bitcast[\n        DType.uint64\n    ](odd[0])'),
    ('discard_tiny_residual', 'curve_sum2', '_sum2_supported_environment', 'first[0], first[1], -one', 'first[0], 0.0, -one'),
    ('omit_probe_finish', 'curve_sum2', '_sum2_supported_environment', 'last[0] + last[1]', 'last[0]'),
    ('float_underflow_comparison', 'curve_sum2', '_sum2_supported_environment', 'bitcast[DType.uint64](last[0] + last[1]) == UInt64(1)', '(last[0] + last[1]) == tiny'),
    ('wrapper_always_supported', 'curve_sum2', '_sum2_error', 'if not _sum2_supported_environment():', 'if False:'),
    ('wrapper_inverts_predicate', 'curve_sum2', '_sum2_error', 'if not _sum2_supported_environment():', 'if _sum2_supported_environment():'),
    ('wrapper_refusal_zero', 'curve_sum2', '_sum2_error', 'return inf[DType.float64]()', 'return 0.0'),
    ('wrapper_changes_leaf_args', 'curve_sum2', '_sum2_error', '(magnitude, inherited, count)', '(inherited, magnitude, count)'),
    ('require_always_supported', 'curve_sum2', '_require_sum2_environment', 'if not _sum2_supported_environment():', 'if False:'),
    ('require_returns_on_refusal', 'curve_sum2', '_require_sum2_environment', 'raise Error(', 'return Error('),
    ('scalar_missing_guard', 'lane_geometry', '_lane_spiral', '    _require_sum2_environment()\n', ''),
    ('fresh_missing_guard', 'curve_bounds', '_spiral_expression', 'if not _sum2_supported_environment():', 'if False:'),
    ('fresh_finite_refusal', 'curve_bounds', '_spiral_expression', '            inf[DType.float64](),', '            0.0,'),
    ('fresh_bypasses_checked_leaf', 'curve_bounds', '_spiral_expression', '_sum2_error_checked(\n        x_magnitude.high', '_sum2_error(\n        x_magnitude.high'),
    ('cached_missing_check', 'curve_bounds', '_lane_jet_model_proof', 'if proof and not _sum2_supported_environment():', 'if False:'),
    ('cached_wrong_predicate', 'curve_bounds', '_lane_jet_model_proof', 'if proof and not _sum2_supported_environment():', 'if proof and _sum2_supported_environment():'),
    ('cached_finite_refusal', 'curve_bounds', '_lane_jet_model_proof', 'return _unknown_point()', 'return (_Jet.constant(0.0), _Jet.constant(0.0), _Jet.constant(0.0))'),
    ('pack_missing_check', 'spiral_domain_proof', '_try_pack_spiral_proof', 'if not _sum2_supported_environment():', 'if False:'),
    ('cached_private_error', 'spiral_domain_proof', '_spiral_proof_branch', 'x.error = proof.first_x_error', 'x.error = 0.0'),
    ('moment_builder_missing_check', 'spiral_moment_proof', '_try_build_spiral_moments', 'if not _sum2_supported_environment():', 'if False:'),
    ('moment_expansion_missing_check', 'spiral_moment_proof', '_try_spiral_moment_expansion', 'if not _sum2_supported_environment():', 'if False:'),
    ('table_expansion_missing_check', 'spiral_moment_table', '_try_spiral_moment_expansion', 'if not _sum2_supported_environment():', 'if False:'),
    ('contains_missing_check', 'lane_refinement', '_lane_certificate_contains', '    _require_sum2_environment()\n', ''),
    ('refine_missing_check', 'lane_refinement', '_refine_lane_certificate', '    _require_sum2_environment()\n', ''),
    ('rounded_prerequisite_omitted', 'lane_refinement', '_refine_lane_certificate', 'if not axis and _RoundedBox.bounds(low, high).known:', 'if not axis:'),
    ('rounded_prerequisite_inverted', 'lane_refinement', '_refine_lane_certificate', 'if not axis and _RoundedBox.bounds(low, high).known:', 'if not axis and not _RoundedBox.bounds(low, high).known:'),
    ('rounded_prerequisite_disjoined', 'lane_refinement', '_refine_lane_certificate', 'if not axis and _RoundedBox.bounds(low, high).known:', 'if not axis or _RoundedBox.bounds(low, high).known:'),
    ('rounded_prerequisite_wrong_domain', 'lane_refinement', '_refine_lane_certificate', '_RoundedBox.bounds(low, high).known', '_RoundedBox.bounds(low, low).known'),
    ('rounded_prerequisite_wrong_field', 'lane_refinement', '_refine_lane_certificate', '_RoundedBox.bounds(low, high).known', '_RoundedBox.bounds(low, high).high'),
    ('continue_missing_check', 'lane_refinement', '_continue_lane_certificate', '    _require_sum2_environment()\n', ''),
    ('query_missing_check', 'map', '_closest_lane_certificate_with_work', '        _require_sum2_environment()\n', ''),
    ('segments_missing_check', 'map', '_create_segments', '        _require_sum2_environment()\n', ''),
    ('builder_missing_check', 'map_builder', 'build', '        _require_sum2_environment()\n', ''),
]


def replace_actual(text, name, before, after):
    _, span, tokens = guard.function_span(text, name)
    first = tokens[span[0]].start[0] - 1
    last = tokens[span[1]-1].start[0] - 1
    lines = text.splitlines(keepends=True)
    body = ''.join(lines[first:last])
    if before not in body:
        raise AssertionError('guard mutation did not apply: ' + name + ': ' + before)
    return ''.join(lines[:first]) + body.replace(before, after, 1) + ''.join(lines[last:])


class EnvironmentSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.positive = sum2_contracts.verify(ROOT)
        source_contracts.verify_group(ROOT, 'canonical_accumulation')
        cls.pins = {p: (ROOT/p).read_bytes() for p in
                    (source_contracts.PINS, guard.PINS, Path('tools/carla_lane_oracle/spiral-moment-pins.json'))}

    def test_complete_guard_checkpoint_positive(self):
        result = self.positive['environment_guard']
        self.assertEqual(result['complete_caller_declarations'], 33)
        self.assertEqual(result['volatile_loads'], 3)
        self.assertEqual(result['probe_sum2_calls'], 4)
        self.assertFalse(result['native_fp_state_execution_qualified'])
        self.assertEqual(self.positive['ideal_projection']['sum2_environment_guards'], 1)

    def exercise(self, case):
        name, module, function, before, after = case
        target = ROOT/'extensions/carla'/f'{module}.mojo'
        original = target.read_text()
        changed = replace_actual(original, function, before, after)
        self.assertNotEqual(original, changed)
        read = Path.read_text
        with patch.object(Path, 'read_text', lambda path, *a, **k:
                          changed if path == target else read(path, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'runtime source dependency changed'):
                source_contracts.verify_group(ROOT, 'canonical_accumulation')
            # Direct token/AST contracts, without using source digests.
            with self.assertRaises((ValueError, SyntaxError)):
                sum2_contracts.verify(ROOT)
        for p, data in self.pins.items():
            self.assertEqual((ROOT/p).read_bytes(), data)

    def test_probe_no_inline_and_cached_alias_attacks(self):
        path = ROOT/'extensions/carla/curve_sum2.mojo'
        original = path.read_text()
        changes = [original.replace('@no_inline\ndef _sum2_supported_environment',
                                    'def _sum2_supported_environment', 1),
                   original+'\n_sum2_supported_environment = cached_true\n']
        for changed in changes:
            with self.subTest(change=changed[-100:]):
                read = Path.read_text
                with patch.object(Path, 'read_text', lambda p, *a, **k:
                                  changed if p == path else read(p, *a, **k)):
                    with self.assertRaises(ValueError):
                        guard.verify(ROOT)

    def test_rounded_prerequisite_import_cannot_be_redirected(self):
        path = ROOT/'extensions/carla/lane_refinement.mojo'
        original = path.read_text()
        changed = original.replace(
            'from extensions.carla.curve_rounded_arc import (',
            'from unexpected.curve_rounded_arc import (', 1)
        self.assertNotEqual(original, changed)
        read = Path.read_text
        with patch.object(Path, 'read_text', lambda p, *a, **k:
                          changed if p == path else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'runtime source dependency changed'):
                source_contracts.verify_group(ROOT, 'canonical_accumulation')
            # Complete routing rejects this independently of source digests.
            with self.assertRaisesRegex(ValueError, 'routing changed: lane_refinement'):
                guard.verify(ROOT)
        for p, data in self.pins.items():
            self.assertEqual((ROOT/p).read_bytes(), data)

    def test_method_decorators_are_part_of_the_actual_contract(self):
        path = ROOT/'extensions/carla/map_builder.mojo'
        original = path.read_text()
        changed = original.replace('    def build(\n', '    @no_inline\n    def build(\n', 1)
        self.assertNotEqual(original, changed)
        read = Path.read_text
        with patch.object(Path, 'read_text', lambda p, *a, **k:
                          changed if p == path else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'guarded caller changed|routing changed'):
                guard.verify(ROOT)

    def test_same_body_under_another_method_is_not_the_guarded_entry(self):
        path = ROOT/'extensions/carla/map_builder.mojo'
        original = path.read_text()
        _, span, tokens = guard.function_span(original, 'build', ('MapBuilder',))
        first = tokens[span[0]].start[0]-1
        last = tokens[span[1]-1].start[0]-1
        lines = original.splitlines(keepends=True)
        nested = ''.join('    '+line if line.strip() else line for line in lines[first:last])
        changed = (''.join(lines[:first])+'    def _guard_review_decoy(self):\n'+
                   nested+''.join(lines[last:]))
        read = Path.read_text
        with patch.object(Path, 'read_text', lambda p, *a, **k:
                          changed if p == path else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'owner/scope changed|routing changed'):
                guard.verify(ROOT)

    def test_class_entry_rebinding_is_not_hidden_by_method_body_pins(self):
        path = ROOT/'extensions/carla/map_builder.mojo'
        original = path.read_text()
        _, span, tokens = guard.function_span(original, 'build', ('MapBuilder',))
        last = tokens[span[1]-1].start[0]-1
        lines = original.splitlines(keepends=True)
        changed = (''.join(lines[:last])+'    comptime build = other_entry\n\n'+
                   ''.join(lines[last:]))
        read = Path.read_text
        with patch.object(Path, 'read_text', lambda p, *a, **k:
                          changed if p == path else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'routing changed'):
                guard.verify(ROOT)

    def test_guard_schema_and_caller_inventory_are_exact(self):
        path = ROOT/guard.PINS
        original = path.read_text()
        changes = []
        for edit in (lambda p: p.update(schema=True), lambda p: p.update(extra=1),
                     lambda p: p.update(source_manifest_sha256='0'*64),
                     lambda p: p['callers'].pop('map_builder'),
                     lambda p: p['callers']['map']['functions'].pop('_create_segments')):
            pin = json.loads(original);edit(pin);changes.append(json.dumps(pin))
        changes.append(original.replace('"schema": 2,', '"schema": 2, "schema": 2,', 1))
        for changed in changes:
            with self.subTest(pin=changed[:70]):
                read = Path.read_text
                with patch.object(Path, 'read_text', lambda p, *a, **k:
                                  changed if p == path else read(p, *a, **k)):
                    with self.assertRaises(ValueError):
                        guard.verify(ROOT)


for case in CASES:
    def control(self, case=case):
        self.exercise(case)
    setattr(EnvironmentSourceTests, 'test_fixed_pin_and_token_' + case[0], control)


class InjectedEnvironmentOutcomes(unittest.TestCase):
    """Execute the exact reviewed wrappers with both explicitly injected states.

    The predicate is never silently assumed true. These tests do not execute
    Mojo volatile operations or set/check any native floating-point mode.
    """
    def wrapper(self, name, namespace):
        guard.verify(ROOT)
        text = (ROOT/'extensions/carla/curve_sum2.mojo').read_text()
        node = sampled.unique_function(sampled.syntax_tree(guard.declaration(text, name)), name)
        node = copy.deepcopy(node)
        for arg in node.args.args:
            arg.annotation = None
        node.returns = None
        tree = ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[]))
        exec(compile(tree, '<reviewed-Sum2-wrapper>', 'exec'), namespace)
        return namespace[name]

    def test_error_wrapper_exercises_supported_and_refused_each_invocation(self):
        calls = []
        state = {'supported': False}
        def predicate():
            calls.append(('predicate', state['supported']))
            return state['supported']
        def leaf(*args):
            calls.append(('leaf', args))
            return 0.125
        class Infinity:
            def __getitem__(self, dtype):
                return lambda: math.inf
        namespace = {'_sum2_supported_environment': predicate,
                     '_sum2_error_checked': leaf, 'inf': Infinity(),
                     'DType': SimpleNamespace(float64='Float64')}
        wrapper = self.wrapper('_sum2_error', namespace)
        for supported in (False, True, False, True):
            state['supported'] = supported
            begin = len(calls)
            result = wrapper(7.0, 0.01, 5)
            self.assertEqual(calls[begin], ('predicate', supported))
            if supported:
                self.assertEqual(result, 0.125)
                self.assertEqual(calls[begin+1:], [('leaf', (7.0, 0.01, 5))])
            else:
                self.assertTrue(math.isinf(result))
                self.assertEqual(len(calls), begin+1)
        self.assertEqual(sum(call[0] == 'predicate' for call in calls), 4)
        self.assertEqual(sum(call[0] == 'leaf' for call in calls), 2)

    def test_required_wrapper_exercises_both_predicate_outcomes(self):
        calls = []
        state = {'supported': False}
        def predicate():
            calls.append(state['supported'])
            return state['supported']
        namespace = {'_sum2_supported_environment': predicate, 'Error': RuntimeError}
        wrapper = self.wrapper('_require_sum2_environment', namespace)
        for supported in (False, True, False, True):
            state['supported'] = supported
            if supported:
                self.assertIsNone(wrapper())
            else:
                with self.assertRaisesRegex(RuntimeError, 'round-to-nearest and gradual underflow'):
                    wrapper()
        self.assertEqual(calls, [False, True, False, True])


if __name__ == '__main__':
    unittest.main()
