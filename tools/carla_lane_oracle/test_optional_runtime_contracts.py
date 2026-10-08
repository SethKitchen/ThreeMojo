#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Fixed-pin and separate semantic mutations for optional runtime obligations.

Each mutation starts from the accepted exact selected runtime. No production
file is edited; no test changes pins to make a broken baseline pass. Native
FP state, mathematical soundness, budgets and coverage have separate controls.
"""
import ast
import copy
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import textwrap
import tokenize
import unittest
from unittest.mock import patch

import optional_runtime_contracts as optional
import source_contracts as sources
import sum2_guard_contracts as guards
import check_sampled_values as sampled

ROOT = Path(__file__).resolve().parents[2]
# name, module, function, exact before, exact after, semantic diagnostic
CASES = [
    ('owner_low', 'curve_objective_model', '_restrict_objective_model', 'low < model.low', 'low < model.low - 1.0', 'owner low'),
    ('owner_high', 'curve_objective_model', '_restrict_objective_model', 'high > model.high', 'high > model.high + 1.0', 'owner high'),
    ('scale_word', 'curve_objective_model', '_restrict_objective_model', 'bitcast[DType.uint64](scale) != model.scale_word', 'False', 'scale word'),
    ('owner_error', 'curve_objective_model', '_restrict_objective_model', 'model.domain.second, model.domain.error', 'model.domain.second, model.center.error', 'whole-owner curvature and error'),
    ('owner_curvature', 'curve_objective_model', '_restrict_objective_model', 'model.domain.second, model.domain.error', 'model.center.second, model.domain.error', 'whole-owner curvature and error'),
    ('unknown_derivative', 'curve_objective_model', '_try_objective_model', 'or not _model_interval(domain.second)', 'or False', 'whole-owner second'),
    ('invalid_error', 'curve_objective_model', '_try_objective_model', 'or domain.error < 0.0', 'or domain.error > 0.0', 'error nonnegative'),
    ('center_outside', 'curve_objective_model', '_try_objective_model', 'or center_s > high', 'or center_s > high + 1.0', 'center inside owner high'),
    ('taylor_half', 'curve_objective_model', '_restrict_objective_model', '_Interval.point(0.5)', '_Interval.point(0.25)', 'Taylor value restriction'),
    ('support_error_substitution', 'curve_minimizer_support', '_minimizer_support', '_Interval.point(2.0) * _Interval.point(domain.error)', '_Interval.point(2.0) * _Interval.point(center.error)', 'whole-domain error'),
    ('support_convex_error', 'curve_minimizer_support', '_minimizer_support', '_Interval.point(4.0) * _Interval.point(domain.error)', '_Interval.point(2.0) * _Interval.point(domain.error)', 'convex support'),
    ('support_actual_witness', 'curve_minimizer_support', '_minimizer_support', 'or best < low', 'or best < low - 1.0', 'witness lower containment'),
    ('stored_predicate_strict', 'curve_sample_dispatch', '_sample_dispatch_predicate', ') > local', ') >= local', 'stored subtraction/clamp'),
    ('stored_predicate_subtraction', 'curve_sample_dispatch', '_sample_dispatch_predicate', 'station - origin', 'station + origin', 'stored subtraction/clamp'),
    ('predecessor_bracket', 'curve_sample_dispatch', '_sample_dispatch_cut', 'bits += 1', 'bits += 2', 'first passing station'),
    ('actual_cut_index', 'curve_sample_dispatch', '_try_sample_dispatch_cuts', 'min(max(station - record.s, 0.0), geometry.length)', 'min(max(station + record.s, 0.0), geometry.length)', 'actual cut sample index'),
    ('actual_after_index', 'curve_sample_dispatch', '_try_sample_dispatch_cuts', 'after_index != threshold_at', 'False', 'both actual indices'),
    ('dispatch_node_headroom', 'curve_sample_dispatch', '_try_sample_dispatch_cuts', 'nodes > max_nodes - node_reserve', 'nodes > max_nodes - 1', 'complete dispatch followup reserve'),
    ('dispatch_term_headroom', 'curve_sample_dispatch', '_try_sample_dispatch_cuts', 'term_reserve > max_terms - terms', 'extra > max_terms - terms', 'complete dispatch followup reserve'),
    ('dispatch_term_debit', 'curve_sample_dispatch', '_try_sample_dispatch_cuts', 'var extra = 8 * count', 'var extra = 6 * count', 'complete optional dispatch debit'),
    ('dispatch_cut_cap', 'curve_sample_dispatch', '_try_sample_dispatch_cuts', 'count > 2', 'count > 3', 'at most two'),
    ('grouped_unchecked_error', 'spiral_grouped_roundoff_proof', '_grouped_origin_error', '_sum2_error_checked(magnitude.high, inherited.high, count)', '_sum2_error(magnitude.high, inherited.high, count)', 'checked error arguments'),
    ('grouped_dropped_count', 'spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope', 'x_inherited, 5 * pieces, geometry.x', 'x_inherited, pieces, geometry.x', 'complete X stored-term count'),
    ('grouped_distance_error', 'spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope', 'd.value, _Interval.whole(), _Interval.whole(), d.error', 'd.value, _Interval.whole(), _Interval.whole(), 0.0', 'original ideal distance'),
    ('grouped_multiplicity', 'spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope', '1 if weight == 2 else 2', '1 if weight == 2 else 1', 'weight multiplicity'),
    ('grouped_work', 'spiral_grouped_roundoff_proof', '_spiral_grouped_roundoff_work', '3 * min(4, pieces)', '2 * min(4, pieces)', 'whole count work'),
    ('grouped_union_admission', 'spiral_grouped_lane', '_try_grouped_lane_jet', 'max_terms - terms < 24', 'max_terms - terms < 12', 'whole optional union'),
    ('grouped_second_count_debit', 'spiral_grouped_lane', '_try_grouped_lane_jet', 'extra += _spiral_grouped_roundoff_work(counts[1])', 'extra += 0', 'second count debit'),
    ('grouped_second_count_domain', 'spiral_grouped_lane', '_try_grouped_lane_jet', 'counts[1] - counts[0] > 1', 'counts[1] - counts[0] > 2', 'at-most-two count'),
    ('grouped_debit_omission', 'spiral_grouped_lane', '_try_grouped_lane_jet', 'terms += extra', 'terms += 0', 'atomic whole-count debit'),
    ('grouped_hidden_fallback', 'spiral_grouped_lane', '_try_grouped_lane_jet', 'require_reuse=True', 'require_reuse=False', 'hidden GL'),
    ('metered_fallback_reservation', 'spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope_metered', 'work + fallback_work > max_terms - terms', 'work > max_terms - terms', 'independent fallback'),
    ('actual_witness_source', 'lane_refinement', '_run_lane_search', 'var best = certificate.s', 'var best = low', 'actual certificate witness'),
    ('actual_witness_point', 'lane_refinement', '_run_lane_search', 'var best_point = certificate.point.copy()', 'var best_point = query_point.copy()', 'actual witness point'),
    ('cached_term_reservation', 'curve_objective_model', '_objective_followup_room', '(remaining - center_work) // 8', 'remaining // 8', 'overflow-safe integer followup'),
    ('dispatch_child_predecessor', 'lane_refinement', '_run_lane_search', 'bitcast[DType.uint64](split_at) - UInt64(1)', 'bitcast[DType.uint64](split_at) - UInt64(2)', 'every stored owner station'),
    ('logical_dispatch_fee', 'map', '_query_node_step_cost', 'fixed += 16', 'fixed += 15', 'dispatch logical fee'),
]
CASES.extend([
    ('followup_negative_nodes', 'curve_objective_model', '_objective_followup_room', 'nodes < 0', 'nodes < -1', 'overflow-safe integer followup'),
    ('followup_consumed_nodes', 'curve_objective_model', '_objective_followup_room', 'nodes > max_nodes', 'nodes > max_nodes + 1', 'overflow-safe integer followup'),
    ('followup_negative_terms', 'curve_objective_model', '_objective_followup_room', 'terms < 0', 'terms < -1', 'overflow-safe integer followup'),
    ('followup_consumed_terms', 'curve_objective_model', '_objective_followup_room', 'terms > max_terms', 'terms > max_terms + 1', 'overflow-safe integer followup'),
    ('followup_negative_reference', 'curve_objective_model', '_objective_followup_room', 'reference_work < 0', 'reference_work < -1', 'overflow-safe integer followup'),
    ('followup_negative_center', 'curve_objective_model', '_objective_followup_room', 'center_work < 0', 'center_work < -1', 'overflow-safe integer followup'),
    ('followup_one_short_node', 'curve_objective_model', '_objective_followup_room', 'max_nodes - nodes >= 4', 'max_nodes - nodes >= 3', 'overflow-safe integer followup'),
    ('followup_one_short_term', 'curve_objective_model', '_objective_followup_room', '// 8', '// 7', 'overflow-safe integer followup'),
    ('followup_center_admission', 'curve_objective_model', '_objective_followup_room', 'center_work <= remaining', 'True', 'overflow-safe integer followup'),
    ('followup_overflow_form', 'curve_objective_model', '_objective_followup_room', 'reference_work <= (remaining - center_work) // 8', '8 * reference_work + center_work <= remaining', 'overflow-safe integer followup'),
    ('grouped_recheck_headroom', 'lane_refinement', '_run_lane_search', 'if max_nodes - certificate.nodes >= 2:', 'if max_nodes - certificate.nodes >= 1:', 'grouped caller must retain recheck'),
    ('grouped_stale_optional_result', 'lane_refinement', '_run_lane_search', 'var grouped: Optional[Tuple[_Jet, _Jet, _Jet]] = None', 'var grouped: Optional[Tuple[_Jet, _Jet, _Jet]] = previous_grouped', 'grouped caller must retain recheck'),
    ('dispatch_descendant_nodes', 'curve_sample_dispatch', '_try_sample_dispatch_cuts', '3 * count + 2', '3 * count + 1', 'descendants and rechecks'),
    ('dispatch_descendant_terms', 'curve_sample_dispatch', '_try_sample_dispatch_cuts', '16 * count', '16 * count - 1', 'descendant term reserve'),
])

CASES.extend([
    ('recheck_one_short', 'curve_objective_model', '_objective_recheck_room', 'nodes < max_nodes', 'nodes <= max_nodes', 'cached-closure recheck admission'),
    ('recheck_negative_counter', 'curve_objective_model', '_objective_recheck_room', 'nodes >= 0', 'nodes >= -1', 'cached-closure recheck admission'),
])

# The twelve removed caller mutations are retained verbatim in the removal
# migration record. These adversarial replacements require the production
# consumer to remain absent and the original fresh path/memo to remain intact.
CASES.extend([
    ('model_state_reintroduction', 'lane_refinement', '_run_lane_search',
     'var sampled_checked = False', 'var cached_model = None\n    var sampled_checked = False',
     'search state reintroduced'),
    ('model_capture_reintroduction', 'lane_refinement', '_run_lane_search',
     'var delta = _Interval(lo, hi) - _Interval.point(center_s)',
     'var hidden = _try_objective_model(lo, hi, center_s, scale, domain, center)\n            var delta = _Interval(lo, hi) - _Interval.point(center_s)',
     'production consumer reintroduced'),
    ('model_restriction_reintroduction', 'lane_refinement', '_run_lane_search',
     'var best = certificate.s', 'var hidden = _restrict_objective_model(previous, low, high, 1.0)\n    var best = certificate.s',
     'production consumer reintroduced'),
    ('fresh_producer_stale_domain', 'lane_refinement', '_run_lane_search',
     'point_domain = _lane_jet_with_proof(road, section, lane, lo, hi, low, high, spiral_proof)',
     'point_domain = previous_domain', 'fresh current-cell producer'),
    ('fresh_producer_wrong_owner', 'lane_refinement', '_run_lane_search',
     'point_domain = _lane_jet_with_proof(road, section, lane, lo, hi, low, high, spiral_proof)',
     'point_domain = _lane_jet_with_proof(road, section, lane, low, high, low, high, spiral_proof)',
     'fresh current-cell producer'),
    ('fresh_producer_unpaid', 'lane_refinement', '_run_lane_search',
     optional.FRESH_PRODUCER, textwrap.indent(optional.FRESH_PRODUCER.replace('certificate.terms += work', 'certificate.terms += 0').strip(), ' ' * 12),
     'fresh current-cell producer'),
    ('fresh_producer_early_cached_closure', 'lane_refinement', '_run_lane_search',
     'var point_domain: Tuple[_Jet, _Jet, _Jet]',
     'if previous_lower > best_upper:\n                continue\n            var point_domain: Tuple[_Jet, _Jet, _Jet]',
     'fresh current-cell producer'),
    ('fresh_producer_wrong_work', 'lane_refinement', '_run_lane_search',
     'var work = _reference_work(road, lo, hi)', 'var work = _reference_work(road, low, high)',
     'current cell work'),
    ('fast_memo_wrong_station', 'lane_refinement', '_run_lane_search',
     '_same_cache_key(cached_fast.value()[0], cached_fast.value()[1], station_word, scale_word)',
     '_same_cache_key(cached_fast.value()[0], cached_fast.value()[1], cached_fast.value()[0], scale_word)',
     'exact station/scale proof'),
    ('fast_memo_wrong_scale', 'lane_refinement', '_run_lane_search',
     '_same_cache_key(cached_fast.value()[0], cached_fast.value()[1], station_word, scale_word)',
     '_same_cache_key(cached_fast.value()[0], cached_fast.value()[1], station_word, cached_fast.value()[1])',
     'exact station/scale proof'),
    ('expansion_memo_wrong_station', 'lane_refinement', '_run_lane_search',
     '_same_cache_key(cached_expansion.value()[0], cached_expansion.value()[1], station_word, scale_word)',
     '_same_cache_key(cached_expansion.value()[0], cached_expansion.value()[1], cached_expansion.value()[0], scale_word)',
     'exact station/scale translated'),
    ('expansion_memo_wrong_scale', 'lane_refinement', '_run_lane_search',
     '_same_cache_key(cached_expansion.value()[0], cached_expansion.value()[1], station_word, scale_word)',
     '_same_cache_key(cached_expansion.value()[0], cached_expansion.value()[1], station_word, cached_expansion.value()[1])',
     'exact station/scale translated'),
    ('memo_key_inexact', 'lane_refinement', '_same_cache_key',
     'SIMD[DType.uint64, 2](station, scale) == SIMD[DType.uint64, 2](other_station, other_scale)',
     'SIMD[DType.uint64, 2](station, scale) <= SIMD[DType.uint64, 2](other_station, other_scale)',
     'exact station/scale memo key'),
    ('memo_cross_invocation', 'lane_refinement', '_run_lane_search',
     'var cached_expansion: Optional[Tuple[UInt64, UInt64, _Jet]] = None',
     'var cached_expansion: Optional[Tuple[UInt64, UInt64, _Jet]] = saved',
     'memo lifetime is one search invocation'),
    ('retained_model_fee', 'map', '_query_node_step_cost', 'fixed += 14', 'fixed += 0',
     'retained containing-model logical fee'),
])

for module, name in (
        ('curve_objective_model', '_try_objective_model'),
        ('curve_objective_model', '_restrict_objective_model'),
        ('curve_sample_dispatch', '_sample_dispatch_cut'),
        ('curve_sample_dispatch', '_try_sample_dispatch_cuts'),
        ('spiral_grouped_lane', '_try_grouped_lane_jet'),
        ('spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope'),
        ('spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope_metered')):
    CASES.append(('fresh_guard_' + name, module, name,
                  'if not _sum2_supported_environment():', 'if False:', 'fresh invocation guard'))


def replace_token_fragment(source, before, after):
    """Mutate one exact executable fragment independent of formatter wrapping.

    Retain actual function selection and every operator/name/literal. Comments
    and whitespace cannot redirect the mutation to a textual decoy. No pin or
    semantic assertion is weakened by this test-fixture normalization.
    """
    ignored = {tokenize.COMMENT, tokenize.NL, tokenize.NEWLINE, tokenize.INDENT,
               tokenize.DEDENT, tokenize.ENDMARKER}
    def executable(text):
        result = [token for token in sources.tokens(text) if token.type not in ignored]
        # The formatter may add a final comma when it wraps call arguments.
        # This is mutation-location matching only, never a production gate.
        return [token for index, token in enumerate(result)
                if not (token.string == ',' and index + 1 < len(result)
                        and result[index + 1].string in (')', ']'))]
    actual = executable(source)
    wanted = [(token.type, token.string) for token in executable(before)]
    values = [(token.type, token.string) for token in actual]
    matches = [i for i in range(len(actual)) if values[i:i+len(wanted)] == wanted]
    if len(matches) != 1:
        raise AssertionError('missing or ambiguous executable mutation fragment: ' + before)
    lines = source.splitlines(keepends=True)
    offsets = [0]
    for line in lines:
        offsets.append(offsets[-1] + len(line))
    first, last = actual[matches[0]], actual[matches[0] + len(wanted) - 1]
    start = offsets[first.start[0] - 1] + first.start[1]
    end = offsets[last.end[0] - 1] + last.end[1]
    return source[:start] + after.lstrip(' \t') + source[end:]


class OptionalRuntimeContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.semantic = optional.verify(ROOT)
        cls.guarded = guards.verify(ROOT)
        cls.sampled = sampled.verify(ROOT)
        cls.pins = {path: (ROOT/path).read_bytes() for path in (sources.PINS, guards.PINS)}

    def changed(self, module, name, before, after):
        path = ROOT/'extensions/carla'/f'{module}.mojo'
        original = path.read_text()
        function, span, tokens = guards.function_span(original, name, ())
        first, last = tokens[span[0]].start[0]-1, tokens[span[1]-1].start[0]-1
        lines = original.splitlines(keepends=True)
        original_function = ''.join(lines[first:last])
        replacement = replace_token_fragment(original_function, before, after)
        self.assertNotEqual(replacement, original_function)
        return path, ''.join(lines[:first]) + replacement + ''.join(lines[last:])

    def exercise(self, case):
        _, module, name, before, after, diagnostic = case
        path, changed = self.changed(module, name, before, after)
        read = Path.read_text
        with patch.object(Path, 'read_text', lambda p, *a, **k:
                          changed if p == path else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, diagnostic):
                optional.verify_semantics(ROOT)
            with self.assertRaisesRegex(ValueError, 'runtime source dependency changed'):
                sources.verify_group(ROOT, 'optional_runtime')
        for path, pin in self.pins.items():
            self.assertEqual((ROOT/path).read_bytes(), pin)

    def test_mutation_fixtures_survive_formatter_wrapping(self):
        source = ('def reviewed():\n    var error = _sum2_error_checked(\n'
                  '        magnitude.high,  # same operand\n        inherited.high,\n'
                  '        count,\n    )\n')
        changed = replace_token_fragment(source,
            '_sum2_error_checked(magnitude.high, inherited.high, count)',
            '_sum2_error_checked(magnitude.high, inherited.high, 1)')
        self.assertIn('inherited.high, 1)', changed)
        self.assertNotIn('count', changed)
        with self.assertRaises(AssertionError):
            replace_token_fragment(source, '_sum2_error_checked(0.0, inherited.high, count)', 'broken()')

    def test_all_five_new_modules_have_dependency_contracts(self):
        expected = {'extensions/carla/' + name + '.mojo' for name in optional.NEW_MODULES}
        self.assertTrue(expected.issubset(sources.GROUP_PATHS['optional_runtime']))
        self.assertEqual(len(expected), 5)
        self.assertFalse(self.semantic['native_execution_qualified'])
        self.assertEqual(self.guarded['complete_caller_declarations'], 29)

    def test_omitted_new_dependency_rejects_schema(self):
        read = Path.read_text
        original = json.loads(self.pins[sources.PINS])
        for name in optional.NEW_MODULES:
            changed = json.loads(json.dumps(original))
            del changed['groups']['optional_runtime']['extensions/carla/' + name + '.mojo']
            with self.subTest(module=name), patch.object(Path, 'read_text',
                    lambda p, *a, **k: json.dumps(changed) if p == ROOT/sources.PINS else read(p, *a, **k)):
                with self.assertRaisesRegex(ValueError, 'dependency path set'):
                    sources.verify_group(ROOT, 'optional_runtime')

    def test_try_only_projection_preserves_all_historical_graph_constants(self):
        text = (ROOT/'extensions/carla/curve_bounds.mojo').read_text()
        import hashlib
        self.assertEqual(hashlib.sha256(sampled.dump(sampled.reviewed_reference_tree(text)).encode()).hexdigest(),
                         sampled.REFERENCE_MODULE_GRAPHS['curve_bounds.mojo'])
        for before, after in (('require_reuse: Bool = False', 'require_reuse: Bool = True'),
                              ('elif require_reuse:', 'elif False:'),
                              ('elif require_reuse:\n        # Optional callers separately reserve their one original fallback.\n        return _unknown_point()',
                               'elif require_reuse:\n        return reused.value()')):
            with self.subTest(before=before), self.assertRaises(sampled.CheckError):
                sampled.reviewed_reference_tree(replace_token_fragment(text, before, after))

    def test_debit_cannot_move_after_first_raw_envelope(self):
        path, changed = self.changed('spiral_grouped_lane', '_try_grouped_lane_jet',
            'terms += extra\n    var first = _try_spiral_grouped_roundoff_envelope(geometry, d, counts[0])',
            'var first = _try_spiral_grouped_roundoff_envelope(geometry, d, counts[0])\n    terms += extra')
        read = Path.read_text
        with patch.object(Path, 'read_text', lambda p, *a, **k: changed if p == path else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'atomic whole-count debit'):
                optional.verify_semantics(ROOT)

    def test_dispatch_cannot_move_before_original_closures(self):
        path = ROOT/'extensions/carla/lane_refinement.mojo'
        original = path.read_text()
        setup = '''        if not sampled_checked:
            sampled_checked = True
            sampled_cuts = _try_sample_dispatch_cuts(
                road, low, high, certificate.nodes, certificate.terms,
                max_nodes, max_terms,
            )
'''
        marker = '        var best_upper = best_bounds.high\n        var work = _reference_work(road, lo, hi)\n'
        changed = replace_token_fragment(original, setup, '')
        changed = replace_token_fragment(changed, marker, setup + marker)
        read = Path.read_text
        with patch.object(Path, 'read_text', lambda p, *a, **k: changed if p == path else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'depth refusal precedes dispatch'):
                optional.verify_semantics(ROOT)

    def test_global_inventory_rejects_new_modules_aliases_and_reexports(self):
        pins = json.loads(self.pins[guards.PINS])
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            paths = set(pins['protected_inventory']) | {str(guards.PINS)}
            for module in guards.CALLERS:
                paths.add('extensions/carla/' + module + '.mojo')
            for path in paths:
                target = root/path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT/path, target)
            self.assertEqual(guards.verify(root)['status'], 'PASS')
            cases = [
                'from extensions.carla.curve_sum2 import _sum2_error_checked as concealed\ndef unchecked():\n    return concealed(1.0, 0.0, 5)\n',
                'import extensions.carla.curve_sum2 as concealed\ndef unchecked():\n    return concealed._sum2_error_checked(1.0, 0.0, 5)\n',
                'from extensions.carla.curve_sum2 import *\ndef unchecked():\n    return _sum2_error_checked(1.0, 0.0, 5)\n',
                'from extensions.carla.spiral_grouped_roundoff_proof import _grouped_origin_error as unchecked\n',
            ]
            target = root/'extensions/build/new_runtime_namespace/__init__.mojo'
            target.parent.mkdir(parents=True)
            for text in cases:
                with self.subTest(source=text):
                    target.write_text(text)
                    with self.assertRaisesRegex(ValueError, 'global protected-helper'):
                        guards.verify(root)
            target.write_text('# _sum2_error_checked in an inert comment\n')
            self.assertEqual(guards.verify(root)['status'], 'PASS')

    def test_absence_rejects_import_alias_reexport_and_indirect_consumers(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = root/'extensions/new_runtime_namespace/__init__.mojo'
            target.parent.mkdir(parents=True)
            cases = (
                'from extensions.carla.curve_objective_model import _ObjectiveModel as Hidden\n',
                'import extensions.carla.curve_objective_model as hidden\n',
                'from extensions.carla.curve_objective_model import *\n',
                'def hidden():\n    return _try_objective_model\n',
                'def hidden():\n    return adapter._restrict_objective_model\n',
                'def hidden():\n    return _objective_followup_room(0, 0, 4, 8, 1, 0)\n',
                'def hidden():\n    return _objective_recheck_room(0, 1)\n',
            )
            for source in cases:
                with self.subTest(source=source):
                    target.write_text(source)
                    with self.assertRaisesRegex(ValueError, 'production consumer reintroduced'):
                        optional.verify_no_containing_model_consumers(root)
            target.write_text('# curve_objective_model _ObjectiveModel\n'
                              '"""_try_objective_model is historical evidence."""\n')
            optional.verify_no_containing_model_consumers(root)
            helper = root/'extensions/carla/curve_objective_model.mojo'
            helper.parent.mkdir(parents=True)
            helper.write_text((ROOT/'extensions/carla/curve_objective_model.mojo').read_text())
            tests = root/'tests/model.mojo'
            tests.parent.mkdir()
            tests.write_text(cases[0])
            optional.verify_no_containing_model_consumers(root)

    def test_absence_checks_actual_solver_imports_and_inert_decoys(self):
        path = ROOT/'extensions/carla/lane_refinement.mojo'
        original = path.read_text()
        read = Path.read_text
        for prefix in ('from extensions.carla.curve_objective_model import _ObjectiveModel as Hidden\n',
                       'import extensions.carla.curve_objective_model as hidden\n'):
            with self.subTest(prefix=prefix), patch.object(Path, 'read_text',
                    lambda p, *a, **k: prefix + original if p == path else read(p, *a, **k)):
                with self.assertRaisesRegex(ValueError, 'production consumer reintroduced'):
                    optional.verify_semantics(ROOT)
                with self.assertRaisesRegex(ValueError, 'runtime source dependency changed'):
                    sources.verify_group(ROOT, 'optional_runtime')
                with self.assertRaisesRegex(ValueError, 'routing changed'):
                    guards.verify(ROOT)
        prefix = '# cached_model _restrict_objective_model\n'
        with patch.object(Path, 'read_text',
                lambda p, *a, **k: prefix + original if p == path else read(p, *a, **k)):
            self.assertEqual(optional.verify(ROOT)['status'], 'PASS')
            self.assertEqual(guards.verify(ROOT)['status'], 'PASS')

    def test_removal_manifest_is_bound_and_retains_historical_controls(self):
        path = ROOT/'tools/carla_lane_oracle/containing-model-removal-migration.json'
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),
                         guards.CONTAINING_MODEL_REMOVAL_SHA256)
        manifest = json.loads(path.read_text())
        self.assertEqual(manifest['base_tree'], 'e161dd9b8f46e2ec006b57fd2167d67a1b217ad5')
        self.assertEqual(len(manifest['historical_removed_caller_controls']), 12)
        self.assertEqual({row['group'] for row in manifest['dependency_changes']},
                         {'canonical_accumulation', 'optional_runtime', 'translation', 'support'})
        self.assertEqual({row['path'] for row in manifest['dependency_changes']},
                         {'extensions/carla/lane_refinement.mojo'})
        # A later reviewed migration can move a frozen file forward. Each
        # successor must start exactly where the previous record ended.
        successors = json.loads((ROOT/'tools/carla_lane_oracle/'
                                 'default-query-restoration-migration.json').read_text())
        for path, hashes in manifest['runtime_freeze']['manifest']['files'].items():
            expected = hashes['after']
            for step in successors['raw_successors'].get(path, []):
                self.assertEqual(step['before'], expected)
                expected = step['after']
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), expected)
        self.assertTrue(manifest['solver_removal_projection']['map_complete_tokens_equal'])
        self.assertEqual(manifest['solver_removal_projection']['projected_ast_sha256'],
                         manifest['solver_removal_projection']['successor_ast_sha256'])
        retained = {case[0] for case in CASES if case[1] == 'curve_objective_model'}
        self.assertTrue({'owner_low', 'owner_high', 'scale_word', 'cached_term_reservation',
                         'followup_one_short_node', 'followup_one_short_term',
                         'recheck_one_short', 'recheck_negative_counter'}.issubset(retained))

    def test_unreviewed_removal_lineage_rejects(self):
        changed = json.loads(self.pins[guards.PINS])
        changed['containing_model_removal_sha256'] = '0' * 64
        read = Path.read_text
        with patch.object(Path, 'read_text', lambda p, *a, **k:
                          json.dumps(changed) if p == ROOT/guards.PINS else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'unreviewed containing-model removal lineage'):
                guards.verify(ROOT)

    def test_missing_global_inventory_binding_rejects(self):
        changed = json.loads(self.pins[guards.PINS])
        del changed['protected_inventory']['extensions/carla/spiral_grouped_lane.mojo']
        read = Path.read_text
        with patch.object(Path, 'read_text', lambda p, *a, **k:
                          json.dumps(changed) if p == ROOT/guards.PINS else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'global protected-helper'):
                guards.verify(ROOT)

    def test_continuation_preserves_cumulative_work_and_saved_depth(self):
        for before, after in (
                ('_require_sum2_environment()', '_require_sum2_environment()\n    certificate.nodes = 0'),
                ('_require_sum2_environment()', '_require_sum2_environment()\n    certificate.terms = 0'),
                ('if cell.depth < 0:', 'if cell.depth < -1:'),
                ('terminal.append(cell)', 'terminal.append(_ClosedInterval(cell.low, cell.high, 0, cell.lower, cell.scale))')):
            path, changed = self.changed('lane_refinement', '_continue_lane_certificate', before, after)
            read = Path.read_text
            with self.subTest(change=after), patch.object(Path, 'read_text', lambda p, *a, **k:
                              changed if p == path else read(p, *a, **k)):
                with self.assertRaisesRegex(ValueError, 'complete guarded caller changed'):
                    guards.verify(ROOT)
                with self.assertRaisesRegex(ValueError, 'runtime source dependency changed'):
                    sources.verify_group(ROOT, 'optional_runtime')

    def test_grouped_reserve_cannot_bypass_prepaid_fallback_order(self):
        cases = (
            ('certificate.terms += work', 'certificate.terms += 0'),
            ('if max_nodes - certificate.nodes >= 2:', 'if True:'),
            ('point_domain = _lane_jet(road, section, lane, lo, hi)', 'point_domain = grouped.value()'),
        )
        original = optional.GROUPED_ADMISSION
        for before, after in cases:
            path, changed = self.changed('lane_refinement', '_run_lane_search',
                original, textwrap.indent(original.replace(before, after, 1).strip(), ' ' * 16))
            read = Path.read_text
            with self.subTest(change=after), patch.object(Path, 'read_text', lambda p, *a, **k:
                              changed if p == path else read(p, *a, **k)):
                with self.assertRaisesRegex(ValueError, 'grouped caller must retain recheck'):
                    optional.verify_semantics(ROOT)
                with self.assertRaisesRegex(ValueError, 'runtime source dependency changed'):
                    sources.verify_group(ROOT, 'optional_runtime')

    def checked_integer_function(self, node):
        node = copy.deepcopy(node)
        for argument in node.args.args:
            argument.annotation = None
        node.returns = None
        module = ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[]))
        namespace = {}
        exec(compile(module, '<reviewed-integer-admission>', 'exec'), namespace)
        return namespace[node.name]

    def test_actual_integer_helper_exact_one_short_and_overflow_boundaries(self):
        optional.verify_semantics(ROOT)
        function = self.checked_integer_function(optional.body(ROOT, 'curve_objective_model', '_objective_followup_room'))
        class CheckedInt(int):
            def __new__(cls, value):
                if not -(1 << 63) <= value < (1 << 63):
                    raise OverflowError('signed Int overflow')
                return super().__new__(cls, value)
            def __sub__(self, other):
                return CheckedInt(int(self) - int(other))
            def __floordiv__(self, other):
                return CheckedInt(int(self) // int(other))
        maximum = (1 << 63) - 1
        rows = [(5, 7, 9, 26, 2, 3), (5, 7, 8, 26, 2, 3),
                (5, 7, 9, 25, 2, 3), (0, 0, 4, 0, 0, 0),
                (maximum - 4, 0, maximum, maximum, maximum // 8, 7),
                (0, 0, 4, maximum, maximum, maximum),
                (0, 0, -(1 << 63), maximum, 0, 0),
                (0, 0, 4, -(1 << 63), 0, 0)]
        rows += [tuple(-1 if i == position else value for i, value in enumerate(rows[0]))
                 for position in range(6)]
        for row in rows:
            nodes, terms, max_nodes, max_terms, reference, center = row
            expected = (0 <= nodes <= max_nodes and 0 <= terms <= max_terms
                        and reference >= 0 and center >= 0 and max_nodes - nodes >= 4
                        and center + 8 * reference <= max_terms - terms)
            with self.subTest(row=row):
                self.assertEqual(function(*map(CheckedInt, row)), expected)
        self.assertTrue(function(*rows[0]))
        self.assertFalse(function(*rows[1]))
        self.assertFalse(function(*rows[2]))

    def test_actual_recheck_helper_exact_and_one_short(self):
        optional.verify_semantics(ROOT)
        function = self.checked_integer_function(optional.body(ROOT, 'curve_objective_model', '_objective_recheck_room'))
        for nodes, maximum, expected in ((0, 1, True), (0, 0, False), (7, 8, True),
                                         (7, 7, False), (-1, 8, False),
                                         ((1 << 63) - 2, (1 << 63) - 1, True),
                                         ((1 << 63) - 1, (1 << 63) - 1, False),
                                         (0, -(1 << 63), False)):
            with self.subTest(nodes=nodes, maximum=maximum):
                self.assertEqual(function(nodes, maximum), expected)

    def test_actual_dispatch_exact_and_one_short_reserves(self):
        optional.verify_semantics(ROOT)
        actual = optional.body(ROOT, 'curve_sample_dispatch', '_try_sample_dispatch_cuts')
        expected = sampled.syntax_tree(optional.DISPATCH_ADMISSION).body
        wanted = [sampled.dump(item) for item in expected]
        body = [sampled.dump(item) for item in actual.body]
        places = [i for i in range(len(body)) if body[i:i+len(wanted)] == wanted]
        self.assertEqual(len(places), 1)
        node = ast.parse('def dispatch(count, nodes, terms, max_nodes, max_terms):\n    pass').body[0]
        node.body = copy.deepcopy(actual.body[places[0]:places[0] + len(wanted)])
        node.body += ast.parse('return (nodes, terms)').body
        function = self.checked_integer_function(node)
        for count in (1, 2):
            max_nodes, max_terms = 7 + 3 * count + 2, 11 + 16 * count
            with self.subTest(count=count):
                self.assertEqual(function(count, 7, 11, max_nodes, max_terms), (8, 11 + 8 * count))
                self.assertIsNone(function(count, 7, 11, max_nodes - 1, max_terms))
                self.assertIsNone(function(count, 7, 11, max_nodes, max_terms - 1))
        for count in (-1, 0, 3, (1 << 63) - 1):
            self.assertIsNone(function(count, 0, 0, 100, 100))

    def test_unreviewed_checked_leaf_edge_inside_existing_module_rejects(self):
        path = ROOT/'extensions/carla/spiral_grouped_roundoff_proof.mojo'
        text = path.read_text() + '\ndef _unchecked_extra():\n    return _sum2_error_checked(1.0, 0.0, 5)\n'
        read = Path.read_text
        with patch.object(Path, 'read_text', lambda p, *a, **k: text if p == path else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'routing changed|helper binding/use'):
                guards.verify(ROOT)


for case in CASES:
    def control(self, case=case):
        self.exercise(case)
    setattr(OptionalRuntimeContracts, 'test_mutation_' + case[0], control)


if __name__ == '__main__':
    unittest.main()
