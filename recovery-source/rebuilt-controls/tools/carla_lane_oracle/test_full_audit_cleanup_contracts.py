#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""New reconstruction controls, not recovered historical test bytes.

Physical roots qualify first. Historical tests receive explicit fixed source
files only; current source admission and independent center semantics have
separate positive and adversarial controls. Run unchanged with Python and -O.
"""
import copy
from contextlib import contextmanager
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import tokenize
import unittest
from unittest.mock import patch

import full_audit_cleanup_contracts as cleanup
import _full_audit_test_fixtures as fixtures
import cache_key_contracts as cache
import optional_runtime_contracts as optional
import rounded_line_selector_contracts as selector
import rounded_line_singleton_contracts as singleton
import source_contracts as source
import sum2_guard_contracts as guard
from test_optional_runtime_contracts import replace_token_fragment

ROOT = Path(__file__).resolve().parents[2]
LANE = 'extensions/carla/lane_refinement.mojo'
CURVE = 'extensions/carla/curve_bounds.mojo'
VALUE = 'extensions/carla/lane_value_bounds.mojo'
JUNCTION = 'extensions/carla/junction_bounds.mojo'
EXPECTED_EDITS = {
    CURVE: ('finite_nonnegative_blend',),
    VALUE: ('finite_nonnegative_blend',),
    LANE: ('finite_rounded_inverse', 'finite_width_first',
           'post_local_natural_enclosure', 'chord_endpoint_admission_before_derivative',
           'center_variant_import', 'center_bound_declarations_and_producer',
           'center_cache_ownership_move', 'center_invocation_context_initialization',
           'center_bound_proposal_dispatch'),
    JUNCTION: ('distinct_sorted_cut',),
}
EXPECTED_SUBSTITUTIONS = (
    ('context.section', 'section', 4), ('context.lane', 'lane', 4),
    ('context.root.low', 'low', 1), ('context.root.high', 'high', 1),
    ('context.location', 'location', 5), ('context.spiral_proof', 'spiral_proof', 3),
    ('context.frozen', 'frozen', 2), ('context.external_witness', 'external_witness', 5),
    ('context.cached_fast', 'cached_fast', 5), ('context.cached_expansion', 'cached_expansion', 5),
    ('cell.low', 'lo', 9), ('cell.high', 'hi', 9), ('policy.upper', 'best_upper', 7),
    ('policy.scale', 'scale', 11), ('policy.tolerance', 'tolerance', 4),
    ('policy.goal', 'goal', 4), ('whole_work', 'work', 2),
    ('terms', 'certificate.terms', 7), ('nodes', 'certificate.nodes', 2),
)
EXPECTED_EXITS = (
    ('fast_discard', '_LaneBoundDiscard', 'fast_lower', 'cell'),
    ('fast_close', '_LaneBoundClose', 'fast_lower', 'cell'),
    ('natural_discard', '_LaneBoundDiscard', 'natural', 'cell'),
    ('natural_close', '_LaneBoundClose', 'natural', 'cell'),
    ('tightened_discard', '_LaneBoundDiscard', 'tightened_lower', 'cell'),
    ('tightened_close', '_LaneBoundClose', 'tightened_lower', 'cell'),
    ('final_discard', '_LaneBoundDiscard', 'lower', 'support'),
    ('final_close', '_LaneBoundClose', 'lower', 'support'),
    ('support_contract', '_LaneBoundContract', 'lower', 'support'),
)
# Exact current owners. These are independent of the complete after hash.
CENTER_MUTANTS = (
    ('count_refusal', '_try_lane_center_bound', 'if center_work >= 0:', 'if center_work > 0:'),
    ('center_debit', '_try_lane_center_bound',
     'terms += center_work\n        var fast_center: Optional[_Jet] = None',
     'terms += 0\n        var fast_center: Optional[_Jet] = None'),
    ('whole_cell_debit', '_try_lane_center_bound', 'terms += whole_work', 'terms += 0'),
    ('strict_discard', '_try_lane_center_bound', 'if fast_lower > policy.upper:', 'if fast_lower >= policy.upper:'),
    ('cache_key', '_try_lane_center_bound',
     '_same_cache_key(context.cached_fast.value()[0], context.cached_fast.value()[1], station_word, scale_word)',
     '_same_cache_key(context.cached_fast.value()[0], context.cached_fast.value()[1], station_word, station_word)'),
    ('context_root', '_run_lane_search',
     'section, lane, _Interval(low, high), location, spiral_proof, frozen, external_witness.copy(), None, None',
     'section, lane, _Interval(low, low), location, spiral_proof, frozen, external_witness.copy(), None, None'),
    ('cache_lifetime', '_run_lane_search', 'external_witness.copy(), None, None',
     'external_witness.copy(), None, saved'),
    ('direct_counter_alias', '_run_lane_search',
     '_LaneBoundPolicy(best_upper, scale, tolerance, goal), certificate.nodes, certificate.terms, max_nodes, max_terms',
     '_LaneBoundPolicy(best_upper, scale, tolerance, goal), certificate.terms, certificate.nodes, max_nodes, max_terms'),
    ('caller_discard', '_run_lane_search', 'if bound.isa[_LaneBoundDiscard]():',
     'if bound.isa[_LaneBoundClose]():'),
    ('caller_contract', '_run_lane_search', 'var support = bound[_LaneBoundContract].support',
     'var support = bound[_LaneBoundClose].support'),
    ('caller_lower', '_run_lane_search', 'close.lower, scale', '0.0, scale'),
    ('caller_support', '_run_lane_search', 'close.support.low, close.support.high',
     'low, high'),
    ('caller_depth', '_run_lane_search', 'pending.append((support.low, support.high, task[2] + 1))',
     'pending.append((support.low, support.high, task[2]))'),
    ('accuracy_ulp', '_scaled_accuracy', '_Interval.point(64.0)', '_Interval.point(65.0)'),
    ('local_iteration_cap', '_local_seed', 'while steps < 40:', 'while steps < 41:'),
    ('dead_premise', '_global_lower', 'domain.second.low > 0.0', 'domain.second.low >= 0.0'),
)


def mutate_function(case, text, name, before, after):
    _, span, tokens = guard.function_span(text, name, ())
    start = tokens[span[0]].start[0] - 1
    end = tokens[span[1] - 1].start[0] - 1
    lines = text.splitlines(keepends=True)
    function = ''.join(lines[start:end])
    changed = replace_token_fragment(function, before, after)
    case.assertNotEqual(changed, function)
    return ''.join(lines[:start]) + changed + ''.join(lines[end:])


@contextmanager
def physical_change(root, name, raw):
    path = root/name
    previous = path.read_bytes() if path.exists() else None
    created = []
    parent = path.parent
    while not parent.exists():
        created.append(parent)
        parent = parent.parent
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        if raw is None:
            path.unlink()
        else:
            path.write_bytes(raw)
        yield path
    finally:
        if path.is_symlink() or path.exists():
            path.unlink()
        if previous is not None:
            path.write_bytes(previous)
        for folder in created:
            folder.rmdir()


class FullAuditCleanupContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.record = cleanup.verify(ROOT, exact=True)
        cls.item = cls.record['sources'][LANE]
        cls.current = cls.item['after_source']
        cls.descriptor = cls.item['center_extraction']
        cls.intermediate = cls.descriptor['intermediate_source']

    def setUp(self):
        self.root = fixtures.copy_current_root(self, ROOT)

    def semantic(self, text):
        return cleanup.verify_center_correspondence(self.intermediate, text, self.descriptor)

    def reject_current(self):
        with self.assertRaises(cleanup.ContractError):
            cleanup.verify(self.root)
        with self.assertRaises(cleanup.ContractError):
            cleanup.verified_edges(self.root)

    def test_complete_current_positive_and_exact_receipt_bindings(self):
        self.assertEqual(cleanup.verify(self.root, exact=True), self.record)
        self.assertIsNone(self.semantic(self.current))
        bindings = cleanup.proof_bindings(self.root)
        expected = {cleanup.MIGRATION, *cleanup.CHECKER_PATHS, *cleanup.SOURCE_PATHS}
        for group in cleanup.BOUND_GROUPS:
            expected.update(self.record[group])
        self.assertEqual(set(bindings), expected)
        for path, digest in bindings.items():
            self.assertEqual(cleanup.sha((self.root/path).read_bytes()), digest)
        self.assertEqual(len(self.record['historical_records']), 38)
        self.assertEqual(len(self.record['unchanged_inputs']), 61)
        self.assertTrue(self.record['qualification_ready'])
        self.assertEqual(self.record['unresolved_inputs'], [])
        for path, edge in cleanup.verified_edges(self.root).items():
            self.assertTrue(cleanup.extends_digest(self.root, path,
                edge['before_sha256'], edge['after_sha256']))

    def test_all_twelve_named_exact_inverses_and_each_span_boundary(self):
        self.assertEqual(cleanup.EDIT_NAMES, EXPECTED_EDITS)
        self.assertEqual(sum(map(len, EXPECTED_EDITS.values())), 12)
        total = 0
        for path, item in self.record['sources'].items():
            self.assertEqual(tuple(edit['name'] for edit in item['edits']), EXPECTED_EDITS[path])
            self.assertEqual(cleanup.reverse_exact(path, item['after_source'], item), item['before_source'])
            self.assertEqual(cleanup.sha(item['before_source']), cleanup.BEFORE_SHA256[path])
            text = item['after_source']
            for edit in reversed(item['edits']):
                with self.subTest(path=path, edit=edit['name']):
                    self.assertEqual(text.count(edit['after']), 1)
                    for broken in (text.replace(edit['after'], '', 1), text + edit['after']):
                        with self.assertRaises(cleanup.ContractError):
                            cleanup._reverse_span(broken, edit)
                    for field in ('before', 'after', 'before_sha256', 'after_sha256'):
                        changed = copy.deepcopy(edit)
                        changed[field] += 'x'
                        with self.assertRaises(cleanup.ContractError):
                            cleanup._reverse_span(text, changed)
                    text = cleanup._reverse_span(text, edit)
                    total += 1
            self.assertEqual(text, item['before_source'])
            for edits in (item['edits'][:-1], item['edits'] + item['edits'][:1],
                          list(reversed(item['edits'])) if len(item['edits']) > 1 else []):
                changed = copy.deepcopy(item)
                changed['edits'] = edits
                with self.assertRaises(cleanup.ContractError):
                    cleanup.reverse_exact(path, item['after_source'], changed)
        self.assertEqual(total, 12)
        self.assertEqual(cleanup.reverse_center_exact(self.current, self.item), self.intermediate)

    def test_center_semantic_positive_does_not_require_complete_after_hash(self):
        # This separate cleanup theorem lies outside the center extraction
        # helper's declaration scope; full source admission must still reject.
        self.assertNotIn('_rounded_axis_lane_minimum', self.descriptor['function_declarations'])
        changed = mutate_function(self, self.current, '_rounded_axis_lane_minimum',
                                  'seed = min(max(seed, lo), hi)', 'seed = max(min(seed, lo), hi)')
        self.assertNotEqual(cleanup.sha(changed), cleanup.AFTER_SHA256[LANE])
        self.assertIsNone(self.semantic(changed))
        with physical_change(self.root, LANE, changed.encode()):
            self.reject_current()
        self.assertIsNone(self.semantic(self.current))

    def test_all_nineteen_substitution_counts_and_preceding_dot_collisions(self):
        self.assertEqual(cleanup.CENTER_SUBSTITUTIONS, EXPECTED_SUBSTITUTIONS)
        self.assertEqual(len(EXPECTED_SUBSTITUTIONS), 19)
        stream = cleanup._center_phase(self.current, True)
        self.assertTrue(cleanup._center_substitute(stream))
        for name, _, count in EXPECTED_SUBSTITUTIONS:
            tokens = cleanup._values(name)
            locations = [(row, index) for row, (_, values) in enumerate(stream)
                         for index in range(len(values) - len(tokens) + 1)
                         if values[index:index+len(tokens)] == tokens
                         and (index == 0 or values[index-1] != [tokenize.OP, '.'])]
            self.assertEqual(len(locations), count)
            row, index = locations[0]
            for mode in ('missing', 'extra', 'preceding_member'):
                changed = copy.deepcopy(stream)
                if mode == 'missing':
                    changed[row][1][index:index+len(tokens)] = [[tokenize.NAME, 'unreviewed']]
                elif mode == 'extra':
                    changed.append([0, [[tokenize.NAME, 'var'], [tokenize.NAME, 'decoy'],
                                        [tokenize.OP, '='], *tokens]])
                else:
                    changed[row][1][index:index] = [[tokenize.NAME, 'outer'], [tokenize.OP, '.']]
                with self.subTest(substitution=name, mode=mode):
                    with self.assertRaisesRegex(cleanup.ContractError, 'substitution counts changed'):
                        cleanup._center_substitute(changed)
        # Root-like fields on an unrelated object cannot replace real roots.
        for before, after in (('context.section', 'other.context.section'),
                              ('cell.low', 'other.cell.low')):
            changed = mutate_function(self, self.current, '_try_lane_center_bound',
                                      before, after) if self.current.count(before) == 1 else None
            # These roots legitimately occur more than once; select one token
            # occurrence in the numerical phase without global replacement.
            if changed is None:
                marker = 'var center_s = _expansion_center(cell.low, cell.high, best)'
                if before == 'cell.low':
                    changed = mutate_function(self, self.current, '_try_lane_center_bound', marker,
                                               marker.replace(before, after, 1))
                else:
                    changed = self.current.replace(before, after, 1)
            with self.assertRaisesRegex(cleanup.ContractError, 'substitution counts changed'):
                self.semantic(changed)

    def test_twenty_seven_independent_exit_payload_mutants(self):
        self.assertEqual(tuple((e['name'], e['alternative'], e['lower'], e['support'])
                               for e in self.descriptor['exit_map']), EXPECTED_EXITS)
        tested = 0
        for label, alternative, lower, support in EXPECTED_EXITS:
            before = f'return _LaneBoundProposal({alternative}({lower}, {support}))'
            alternatives = ('_LaneBoundClose' if alternative != '_LaneBoundClose' else '_LaneBoundDiscard',
                            'unreviewed_lower', 'unreviewed_support')
            afters = (f'return _LaneBoundProposal({alternatives[0]}({lower}, {support}))',
                      f'return _LaneBoundProposal({alternative}({alternatives[1]}, {support}))',
                      f'return _LaneBoundProposal({alternative}({lower}, {alternatives[2]}))')
            for field, after in zip(('alternative', 'lower', 'support'), afters):
                with self.subTest(exit=label, field=field):
                    changed = mutate_function(self, self.current, '_try_lane_center_bound', before, after)
                    with self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
                        self.semantic(changed)
                    tested += 1
        self.assertEqual(tested, 27)
        self.assertIsNone(self.semantic(self.current))

    def test_current_context_policy_cache_dispatch_caps_and_dead_premises(self):
        for label, owner, before, after in CENTER_MUTANTS:
            changed = mutate_function(self, self.current, owner, before, after)
            with self.subTest(current_owner=label):
                with self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
                    self.semantic(changed)
                with physical_change(self.root, LANE, changed.encode()):
                    self.reject_current()
        for before, after in (
                ('var section: Int\n    var lane: Int\n    var root: _Interval',
                 'var section: Int\n    var lane: Int\n    var root: Float64'),
                ('struct _LaneBoundPolicy(ImplicitlyCopyable):', 'struct _LaneBoundPolicy(Copyable):'),
                ('_LaneBoundDiscard, _LaneBoundClose, _LaneBoundContract',
                 '_LaneBoundClose, _LaneBoundDiscard, _LaneBoundContract')):
            self.assertEqual(self.current.count(before), 1)
            changed = self.current.replace(before, after, 1)
            with self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
                self.semantic(changed)
        cleanup.verify(self.root, exact=True)

    def test_center_declarations_owners_mutability_and_duplicates_reject(self):
        self.assertEqual(len(self.descriptor['structural_declarations']), 6)
        self.assertEqual(len(self.descriptor['function_declarations']), 14)
        for name, item in self.descriptor['structural_declarations'].items():
            self.assertEqual(cleanup.center_declaration_sha256(self.current, name, item['kind']),
                             item['tokens_sha256'])
            duplicate = ('\ncomptime ' + name + ' = Int\n' if item['kind'] == 'comptime'
                         else '\nstruct ' + name + ':\n    var fake: Int\n')
            with self.subTest(declaration=name), self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
                self.semantic(self.current+duplicate)
            if item['kind'] == 'struct':
                marker = '@fieldwise_init\nstruct ' + name
                self.assertEqual(self.current.count(marker), 1)
                with self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
                    self.semantic(self.current.replace(marker, 'struct '+name, 1))
        for name in self.descriptor['function_declarations']:
            with self.subTest(function=name), self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
                self.semantic(self.current+'\ndef '+name+'():\n    pass\n')
        for before, after in (
                ('var upper: Float64\n    var scale: Float64\n    var tolerance: Float64',
                 'var scale: Float64\n    var upper: Float64\n    var tolerance: Float64'),
                ('mut context: _LaneExpansionContext', 'context: _LaneExpansionContext'),
                ('mut nodes: Int,\n    mut terms: Int,', 'var nodes: Int,\n    var terms: Int,')):
            changed = (mutate_function(self, self.current, '_try_lane_center_bound', before, after)
                       if before.startswith(('mut ', 'var nodes')) else
                       self.current.replace(before, after, 1))
            self.assertNotEqual(changed, self.current)
            with self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
                self.semantic(changed)
        with self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
            cleanup.center_declaration_sha256(
                'struct OtherOwner:\n    struct _LaneBoundClose:\n        var lower: Float64\n',
                '_LaneBoundClose', 'struct')
        with self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
            cleanup.center_declaration_sha256(self.current, '_LaneBoundClose', 'def')

    def test_center_phase_exit_predicate_depth_order_and_fallthrough_reject(self):
        cases = (
            ('if lower > policy.upper:', 'if lower >= policy.upper:'),
            ('if support.low > cell.low or support.high < cell.high:',
             'if support.low > cell.low and support.high < cell.high:'),
            ('terms += center_work\n        var fast_center: Optional[_Jet] = None',
             'var fast_center: Optional[_Jet] = None\n        terms += center_work'),
            ('context.cached_fast = (station_word, scale_word, fast_center.value())',
             'context.cached_fast = (station_word, station_word, fast_center.value())'),
            ('context.cached_expansion = (station_word, scale_word, center)',
             'context.cached_expansion = (station_word, scale_word, domain)'),
            ('return None', 'return _LaneBoundProposal(_LaneBoundDiscard(0.0, cell))'),
            ('var center_s = _expansion_center(cell.low, cell.high, best)',
             'var center_s = (_expansion_center(cell.low, cell.high, best))'),
            ('var lower = max(natural, _global_lower(domain, center, delta))',
             'var lower = max((natural), _global_lower(domain, center, delta))'),
        )
        for before, after in cases:
            with self.subTest(fragment=before):
                changed = mutate_function(self, self.current, '_try_lane_center_bound', before, after)
                with self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
                    self.semantic(changed)
        before = '        if lower > policy.upper:\n            return _LaneBoundProposal(_LaneBoundDiscard(lower, support))'
        self.assertEqual(self.current.count(before), 1)
        for changed in (self.current.replace(before, before.replace('            return', '        return'), 1),
                        self.current.replace('    return None\n\n\ndef _run_lane_search(',
                                             '\n\ndef _run_lane_search(', 1)):
            self.assertNotEqual(changed, self.current)
            with self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
                self.semantic(changed)
        self.assertIsNone(self.semantic('# Inert comment.\n'+self.current))

    def test_center_malformed_inputs_fail_with_contract_error_and_prefix(self):
        for current in (None, 42, '', 'def _try_lane_center_bound(:\n',
                        self.current.replace('var center_s =', 'var center_s = (', 1)):
            with self.subTest(source_type=type(current).__name__):
                with self.assertRaisesRegex(cleanup.ContractError, 'center extraction:'):
                    self.semantic(current)
        for descriptor in (None, [], '', {'schema': 1}):
            with self.assertRaisesRegex(cleanup.ContractError, 'center extraction:'):
                cleanup.verify_center_correspondence(self.intermediate, self.current, descriptor)
        for before in (None, '', 'def _run_lane_search():\n    pass\n'):
            with self.assertRaisesRegex(cleanup.ContractError, 'center extraction:'):
                cleanup.verify_center_correspondence(before, self.current, self.descriptor)

    def test_snapshot_a_b_a_and_stale_supplied_historical_view_reject(self):
        # A remains on disk. A fake read returns B only during one consumed
        # stage, then A again. A final-only re-read would miss this mutation.
        name = 'extensions/carla/curve_interval.mojo'
        path = self.root/name
        original = path.read_bytes()
        read = Path.read_bytes
        self.assertIn(name, self.record['dependency_inventory'])
        self.assertIn(name, self.record['unchanged_inputs'])
        for flip_at in (2, 3):
            observed = []
            def changed(p, *args, **kwargs):
                raw = read(p, *args, **kwargs)
                if p == path:
                    observed.append(raw)
                    if len(observed) == flip_at:
                        return raw+b'\n# Transient B snapshot.\n'
                return raw
            with self.subTest(read_number=flip_at), patch.object(Path, 'read_bytes', changed):
                with self.assertRaisesRegex(cleanup.ContractError, 'changed'):
                    cleanup.verify(self.root)
            self.assertGreaterEqual(len(observed), flip_at)
            self.assertEqual(path.read_bytes(), original)
            cleanup.verify(self.root, exact=True)
        observed = []
        def consumed_then_restored(p, *args, **kwargs):
            raw = read(p, *args, **kwargs)
            if p == path:
                caller = sys._getframe(1)
                in_bound = caller.f_code.co_name == 'verify' and 'group' in caller.f_locals
                observed.append('A' if in_bound else 'B')
                if not in_bound:
                    return raw+b'\n# Consumed B before bound A.\n'
            return raw
        with patch.object(Path, 'read_bytes', consumed_then_restored):
            with self.assertRaisesRegex(cleanup.ContractError, 'bound input changed after consumption'):
                cleanup.verify(self.root)
        self.assertIn('B', observed)
        self.assertEqual(observed[-1], 'A')
        self.assertEqual(path.read_bytes(), original)
        cleanup.verify(self.root, exact=True)
        broken = self.current.replace('if center_work >= 0:', 'if center_work > 0:', 1)
        with physical_change(self.root, LANE, broken.encode()):
            self.assertEqual(cleanup.reviewed_text(self.root, LANE, self.item['before_source']),
                             self.item['before_source'])
            self.reject_current()
            for contract in (guard, selector, singleton):
                with self.assertRaises(ValueError):
                    contract.verify(self.root)
        cleanup.verify(self.root, exact=True)

    def test_symlink_ancestor_of_actual_and_include_roots_rejects(self):
        with tempfile.TemporaryDirectory(prefix='cleanup-ancestor-') as folder:
            base = Path(folder)
            actual = base/'actual'
            actual.mkdir()
            nested = actual/'nested'
            nested.mkdir()
            alias = base/'alias'
            alias.symlink_to(actual, target_is_directory=True)
            # Even an empty include root with a symlink ancestor is refused.
            with self.assertRaises(cleanup.ContractError):
                cleanup.verify(self.root, include_roots=(alias/'nested',))
            actual_repo = base/'repository'
            actual_repo.symlink_to(self.root.parent, target_is_directory=True)
            with self.assertRaises(cleanup.ContractError):
                cleanup.verify(actual_repo/self.root.name)
        cleanup.verify(self.root, exact=True)

    def test_variant_import_removal_alias_and_wrong_route_reject(self):
        before = 'from std.utils import Variant'
        self.assertEqual(self.current.count(before), 1)
        for after in ('', 'from std.utils import Variant as Hidden', 'from unreviewed import Variant'):
            with self.subTest(import_change=after), physical_change(
                    self.root, LANE, self.current.replace(before, after, 1).encode()):
                self.reject_current()
                for contract in (selector, singleton):
                    with self.assertRaises(ValueError):
                        contract.verify_premises(self.root)
                    with self.assertRaises(ValueError):
                        contract.verify(self.root)

    def test_descriptor_scope_counts_exits_and_intermediate_cannot_be_refreshed(self):
        for field in self.descriptor:
            changed = copy.deepcopy(self.descriptor)
            changed[field] = None
            with self.subTest(field=field):
                with self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
                    cleanup.verify_center_correspondence(self.intermediate, self.current, changed)
        for changed in (self.intermediate.replace('while steps < 40:', 'while steps < 41:', 1),
                        self.intermediate + self.intermediate):
            with self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
                cleanup.verify_center_correspondence(changed, self.current, self.descriptor)

    def test_exact_token_physical_crlf_and_string_spellings_remain_distinct(self):
        for name in cleanup.SOURCE_PATHS:
            raw = (self.root/name).read_bytes()
            for changed in (b'# Inert source comment.\n' + raw, raw.replace(b'\n', b'\r\n')):
                with self.subTest(path=name, crlf=b'\r\n' in changed), physical_change(self.root, name, changed):
                    cleanup.verify(self.root)
                    self.assertEqual(cleanup.predecessor_source(self.root, name),
                                     self.record['sources'][name]['before_source'])
                    with self.assertRaises(cleanup.ContractError):
                        cleanup.verify(self.root, exact=True)
                    with self.assertRaises(cleanup.ContractError):
                        cleanup.proof_bindings(self.root)
                    self.assertEqual((self.root/name).read_bytes(), changed)
        self.assertNotEqual(cleanup._rows('var word = r"\\r\\n"\n'),
                            cleanup._rows('var word = r"\\n"\n'))
        self.assertNotEqual(cleanup._rows('var word = "\\r\\n"\n'),
                            cleanup._rows('var word = "\\n"\n'))
        self.assertNotEqual(cleanup._rows('var word = "text"\n'),
                            cleanup._rows("var word = 'text'\n"))
        before = 'raise Error("Lane refinement exhausted its quadrature work limit")'
        changed = mutate_function(self, self.current, '_try_lane_center_bound', before,
                                  'raise Error(r"Lane refinement exhausted its quadrature work limit")')
        with self.assertRaisesRegex(cleanup.ContractError, 'center extraction'):
            self.semantic(changed)

    def test_read_text_and_physical_bytes_must_agree_before_projection(self):
        path = self.root/LANE
        read = Path.read_text
        for supplied in (self.item['before_source'],
                         self.current.replace('if center_work >= 0:', 'if center_work > 0:', 1)):
            with patch.object(Path, 'read_text', lambda p, *a, **k:
                              supplied if p == path else read(p, *a, **k)):
                self.reject_current()
                for contract in (selector, singleton):
                    with self.assertRaisesRegex(ValueError, 'text/bytes disagree'):
                        contract.verify_premises(self.root)
        cleanup.verify(self.root, exact=True)

    def test_each_live_source_and_mixed_historical_root_revokes_prior_positive(self):
        for name, item in self.record['sources'].items():
            for raw in (item['before_source'].encode(),
                        (item['after_source'] + '\ndef unreviewed() -> Int:\n    return 1\n').encode(), None):
                with self.subTest(path=name, missing=raw is None), physical_change(self.root, name, raw):
                    self.reject_current()
                    with self.assertRaises(cleanup.ContractError):
                        cleanup.predecessor_source(self.root, name)
                cleanup.verify(self.root, exact=True)
        with physical_change(self.root, LANE, self.intermediate.encode()):
            self.reject_current()
            with self.assertRaises(ValueError):
                optional.verify_semantics(self.root)

    def test_all_bound_records_premises_and_native_fixtures_revoke_after_positive(self):
        for group in cleanup.BOUND_GROUPS:
            self.assertTrue(self.record[group], group)
            for name in self.record[group]:
                raw = (self.root/name).read_bytes()
                with self.subTest(group=group, path=name), physical_change(self.root, name, raw+b'\n'):
                    self.reject_current()
            cleanup.verify(self.root, exact=True)
        with physical_change(self.root, cleanup.MIGRATION,
                             (self.root/cleanup.MIGRATION).read_bytes()+b' '):
            self.reject_current()
        cleanup.verify(self.root, exact=True)

    def test_record_schema_duplicate_keys_and_resealed_mutations_reject(self):
        raw = (self.root/cleanup.MIGRATION).read_bytes()
        mutations = [raw.replace(b'"schema": 3', b'"schema": 3, "schema": 3', 1)]
        for key, value in (('schema', True), ('qualification_ready', False),
                           ('unresolved_inputs', ['missing']), ('sources', {}),
                           ('inventory', {}), ('dependency_inventory', [])):
            changed = copy.deepcopy(self.record)
            changed[key] = value
            mutations.append((json.dumps(changed, indent=2)+'\n').encode())
        for changed in mutations:
            self.assertNotEqual(raw, changed)
            with physical_change(self.root, cleanup.MIGRATION, changed):
                with self.assertRaises(cleanup.ContractError):
                    cleanup.read_record(self.root)
        cleanup.verify(self.root, exact=True)

    def test_new_caller_alias_reexport_package_and_entrypoint_censuses_reject(self):
        variants = (
            ('new_namespace/caller.mojo', 'from extensions.carla.lane_refinement import _try_lane_center_bound as hidden\n'),
            ('new_namespace/caller.mojo', 'import extensions.carla.lane_refinement as hidden\ndef call():\n    return hidden._try_lane_center_bound()\n'),
            ('new_namespace/__init__.mojo', 'from extensions.carla.lane_refinement import *\n'),
            ('new_namespace/caller.mojo', 'def main():\n    pass\n'),
            ('extensions/carla/fresh.mojo', 'from extensions.carla.lane_refinement import _LaneBoundProposal\n'),
        )
        for name, text in variants:
            with self.subTest(path=name, source=text), physical_change(self.root, name, text.encode()):
                self.reject_current()
        cleanup.verify(self.root, exact=True)

    def test_root_and_include_resolver_shadow_surfaces_reject(self):
        variants = ('std/utils.mojo', 'std.mojo', 'extensions.mojopkg',
                    'extensions/carla/lane_refinement.mojopkg',
                    'extensions/carla/lane_refinement/__init__.mojo',
                    'extensions/carla/Lane_Refinement.mojo', 'tests/__init__.mojo',
                    'math.mojo', 'extensions/carla/math.mojo',
                    'extensions/carla/std/utils.mojo', 'docs/wiki/Math.txt')
        with tempfile.TemporaryDirectory(prefix='cleanup-include-root-') as folder:
            include = Path(folder)
            cleanup.verify(self.root, include_roots=(include,))
            for root in (self.root, include):
                for name in variants:
                    with self.subTest(root='actual' if root == self.root else 'include', name=name), physical_change(root, name, b'# shadow\n'):
                        with self.assertRaises(cleanup.ContractError):
                            cleanup.verify(self.root, include_roots=(include,))
                cleanup.verify(self.root, include_roots=(include,))
            # Exact inert documentation exceptions stay narrow and regular.
            for name in ('docs/wiki/Math.md', 'docs/wiki/Units.md', 'docs/wiki/Extensions.md'):
                with physical_change(include, name, b'Inert documentation.\n'):
                    cleanup.verify(self.root, include_roots=(include,))
            target = include/LANE
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((self.root/LANE).read_bytes())
            cleanup.verify(self.root, include_roots=(include,))
            target.write_bytes(target.read_bytes()+b'\n# Instrumented include bytes.\n')
            # Native include roots contain generated instrumentation. This
            # gate protects resolver topology; generation-origin and capture
            # tests separately bind their source-to-staged-byte relationship.
            cleanup.verify(self.root, include_roots=(include,))

    def test_symlink_source_prefix_root_and_inert_exception_reject(self):
        path = self.root/LANE
        original = path.read_bytes()
        external = self.root/'unconsumed-target.txt'
        external.write_bytes(original)
        path.unlink()
        try:
            path.symlink_to(external)
            self.reject_current()
        finally:
            path.unlink()
            path.write_bytes(original)
            external.unlink()
        with tempfile.TemporaryDirectory(prefix='cleanup-symlink-') as folder:
            link = Path(folder)/'root'
            link.symlink_to(self.root, target_is_directory=True)
            with self.assertRaises(cleanup.ContractError):
                cleanup.verify(link)
            include = Path(folder)/'include'
            include.mkdir()
            prefix = include/'extensions'
            prefix.symlink_to(self.root/'extensions', target_is_directory=True)
            with self.assertRaises(cleanup.ContractError):
                cleanup.verify(self.root, include_roots=(include,))
            prefix.unlink()
            inert = include/'docs/wiki/Math.md'
            inert.parent.mkdir(parents=True)
            inert.symlink_to(self.root/LANE)
            with self.assertRaises(cleanup.ContractError):
                cleanup.verify(self.root, include_roots=(include,))

    def test_supplied_source_admission_is_named_and_rejects_mixed_views(self):
        actual = {p: (self.root/p).read_text() for p in cleanup.SOURCE_PATHS}
        projected = cleanup.reviewed_sources(self.root, actual)
        self.assertEqual(projected, {p: i['before_source'] for p, i in self.record['sources'].items()})
        mixed = dict(actual)
        mixed[CURVE] = self.record['sources'][CURVE]['before_source']
        with self.assertRaises(cleanup.ContractError):
            cleanup.reviewed_sources(self.root, mixed)
        unrelated = 'extensions/carla/curve_interval.mojo'
        supplied = {**actual, unrelated: (self.root/unrelated).read_text() + '\ndef fake():\n    pass\n'}
        with self.assertRaises(cleanup.ContractError):
            cleanup.reviewed_sources(self.root, supplied)
        with self.assertRaises(cleanup.ContractError):
            cleanup.predecessor_source(self.root, unrelated)
        self.assertFalse(cleanup.extends_digest(self.root, unrelated, '0'*64, '1'*64))
        self.assertFalse(cleanup.extends_digest(self.root, LANE, '0'*64, cleanup.AFTER_SHA256[LANE]))
        with self.assertRaises(cleanup.ContractError):
            cleanup.reviewed_lane_before_center_text(self.root, self.item['before_source'])
        with self.assertRaises(cleanup.ContractError):
            cleanup.reviewed_text(self.root, LANE, self.current.replace('if center_work >= 0:', 'if False:', 1))

    def test_sum2_historical_grouping_and_current_mixed_root_controls(self):
        historical = fixtures.historical_root(self, ROOT)
        self.assertEqual(cleanup.reviewed_sum2_callers(historical), {})
        self.assertEqual(guard.verify(historical)['status'], 'PASS')
        path = historical/VALUE
        original = path.read_bytes()
        grouped = original.decode().replace('var magnitude = value', 'var magnitude = (value)', 1)
        self.assertNotEqual(grouped.encode(), original)
        with physical_change(historical, VALUE, grouped.encode()):
            self.assertEqual(cleanup.reviewed_sum2_callers(historical), {})
            self.assertEqual(guard.verify(historical)['status'], 'PASS')
        self.assertEqual(set(cleanup.reviewed_sum2_callers(self.root)), set(cleanup.SOURCE_PATHS))
        self.assertEqual(guard.verify(self.root)['status'], 'PASS')
        with physical_change(self.root, CURVE, self.record['sources'][CURVE]['before_source'].encode()):
            with self.assertRaises(cleanup.ContractError):
                cleanup.reviewed_sum2_callers(self.root)
            with self.assertRaises(ValueError):
                guard.verify(self.root)

    def test_rounded_pre_cache_post_cache_and_current_positives(self):
        historical = fixtures.historical_root(self, ROOT)
        path = historical/LANE
        post_cache = path.read_bytes()
        pre_cache = cache.predecessor_source(historical).encode()
        self.assertNotEqual(pre_cache, post_cache)
        for raw in (pre_cache, post_cache):
            with physical_change(historical, LANE, raw):
                for contract in (selector, singleton):
                    self.assertEqual(contract.verify_premises(historical), contract.verify(historical))
                read = Path.read_text
                with patch.object(Path, 'read_text', lambda p, *a, **k:
                                  self.current if p == path else read(p, *a, **k)):
                    for contract in (selector, singleton):
                        with self.assertRaisesRegex(ValueError, 'text/bytes disagree'):
                            contract.verify_premises(historical)
                        with self.assertRaisesRegex(ValueError, 'text/bytes disagree'):
                            contract.verify(historical)
                for contract in (selector, singleton):
                    self.assertEqual(contract.verify_premises(historical), contract.verify(historical))
        for contract in (selector, singleton):
            self.assertEqual(contract.verify_premises(self.root), contract.verify(self.root))

    def test_rounded_live_minimum_context_and_center_mutations_remain_mandatory(self):
        for contract in (selector, singleton):
            contract.verify(self.root)
        minimum = mutate_function(self, self.current, '_rounded_axis_lane_minimum',
                                  'seed = min(max(seed, lo), hi)', 'seed = max(min(seed, lo), hi)')
        center = mutate_function(self, self.current, '_try_lane_center_bound',
                                 'if center_work >= 0:', 'if center_work > 0:')
        context_name = 'extensions/carla/curve_rounded_line.mojo'
        context = (self.root/context_name).read_bytes()
        self.assertEqual(context.count(b'if not (x.known and y.known):'), 1)
        changed_context = context.replace(b'if not (x.known and y.known):', b'if False:', 1)
        for label, lane, context_raw in (
                ('minimum', minimum.encode(), context), ('center', center.encode(), context),
                ('context', self.current.encode(), changed_context),
                ('combined', center.encode(), changed_context),
                ('intermediate', self.intermediate.encode(), context)):
            with self.subTest(label=label), physical_change(self.root, LANE, lane), physical_change(self.root, context_name, context_raw):
                for contract in (selector, singleton):
                    with self.assertRaises(ValueError):
                        contract.verify_premises(self.root)
                    with self.assertRaises(ValueError):
                        contract.verify(self.root)
            for contract in (selector, singleton):
                contract.verify(self.root)

    def test_executing_checker_identity_and_receipt_copy_stay_live(self):
        for name in cleanup.CHECKER_PATHS:
            raw = (self.root/name).read_bytes()
            with self.subTest(checker=name), physical_change(self.root, name, raw+b'\n# Modified receipt checker.\n'):
                with self.assertRaises(cleanup.ContractError):
                    cleanup.proof_bindings(self.root)
        with patch.object(cleanup, '_center_phase', lambda text, current: []):
            with self.assertRaisesRegex(cleanup.ContractError, 'executing function changed'):
                cleanup.verify(self.root)
        with patch.object(cleanup.verify, '__kwdefaults__', {'exact': True, 'include_roots': ()}):
            with self.assertRaisesRegex(cleanup.ContractError, 'executing callable defaults changed'):
                cleanup.executing_checker_bindings(self.root)
        cleanup.verify(self.root, exact=True)

    def test_stale_dependency_constants_cannot_be_relabelled_by_fresh_disk_bytes(self):
        # Import first, then change only a constant on disk without adding
        # lines, then reload the gate while its consumed dependency remains
        # loaded. Function code alone cannot detect this stale-global seam.
        cases = (
            ('tools/carla_lane_oracle/source_contracts.py',
             "'curve_sum2', 'lane_geometry'", "'unreviewed', 'lane_geometry'"),
            ('tools/carla_lane_oracle/sum2_guard_contracts.py',
             "NONPRODUCTION = {'tests',", "NONPRODUCTION = {'unreviewed',"),
            ('tools/affected.py', r'main\s*\(', r'else\s*\('),
            ('tools/cache_key.py', "SKIP = {'.git',", "SKIP = {'.unreviewed',"),
        )
        command = '''import importlib, sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root/'tools/carla_lane_oracle'))
import full_audit_cleanup_contracts
path = root/sys.argv[2]
original = path.read_bytes()
before, after = sys.argv[3].encode(), sys.argv[4].encode()
if original.count(before) != 1:
    raise RuntimeError('stale-global mutation anchor not unique')
try:
    path.write_bytes(original.replace(before, after, 1))
    del sys.modules['full_audit_cleanup_contracts']
    gate = importlib.import_module('full_audit_cleanup_contracts')
    gate.executing_checker_bindings(root)
finally:
    path.write_bytes(original)
'''
        for mode in ([], ['-O']):
            for name, before, after in cases:
                with self.subTest(mode=mode, dependency=name):
                    original = (self.root/name).read_bytes()
                    self.assertEqual(original.count(before.encode()), 1)
                    result = subprocess.run([sys.executable, *mode, '-B', '-c', command,
                                             str(self.root), name, before, after],
                                            capture_output=True, text=True, timeout=120)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('full-audit cleanup successor:', result.stderr)
                    self.assertEqual((self.root/name).read_bytes(), original)
        cleanup.verify(self.root, exact=True)

    def test_direct_center_import_routing_and_cross_kind_shadowing_reject(self):
        before = 'from std.utils import Variant'
        self.assertEqual(self.current.count(before), 1)
        for replacement in ('', 'from std.utils import Variant as Hidden',
                            'from unreviewed import Variant'):
            with self.subTest(import_change=replacement):
                with self.assertRaisesRegex(cleanup.ContractError, 'center extraction:'):
                    self.semantic(self.current.replace(before, replacement, 1))
        for suffix in ('\ncomptime Variant = Int\n',
                       '\nfrom unreviewed import Hidden as _LaneExpansionContext\n'):
            with self.assertRaisesRegex(cleanup.ContractError, 'center extraction:'):
                self.semantic(self.current+suffix)
        for name, item in self.descriptor['structural_declarations'].items():
            shadow = ('\ndef '+name+'():\n    pass\n' if item['kind'] == 'struct'
                      else '\nstruct '+name+':\n    var fake: Int\n')
            with self.subTest(shadow=name), self.assertRaisesRegex(cleanup.ContractError, 'center extraction:'):
                self.semantic(self.current+shadow)
        for name in self.descriptor['function_declarations']:
            with self.subTest(shadow=name), self.assertRaisesRegex(cleanup.ContractError, 'center extraction:'):
                self.semantic(self.current+'\ncomptime '+name+' = unreviewed\n')
        self.assertIsNone(self.semantic(self.current))

    def test_module_identity_accepts_same_mode_and_relocated_roots(self):
        # The copied tree is a real relocation, not a virtual filesystem.
        # Runtime/interpreter integrity remains trusted. These checks bind
        # actually executed module frames to their current source files.
        self.assertNotEqual(self.root.resolve(), ROOT.resolve())
        command = '''import sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root/'tools/carla_lane_oracle'))
import full_audit_cleanup_contracts as cleanup
cleanup.verify(root, exact=True)
cleanup.proof_bindings(root)
print('relocated same-mode identity accepted')
'''
        for mode in ([], ['-O']):
            result = subprocess.run([sys.executable, *mode, '-B', '-c', command, str(self.root)],
                                    cwd=self.root, capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            self.assertIn('relocated same-mode identity accepted', result.stdout)

    def test_stale_timestamp_size_valid_dependency_pyc_is_not_current_source(self):
        # Compile a mutant, then restore the original sealed physical source
        # at the same size/timestamp. Raw source identity passes; the executed
        # module-frame witness must detect the stale pyc program. -B suppresses
        # writes, not existing pyc loads.
        cases = (
            ('tools/carla_lane_oracle/source_contracts.py',
             "'curve_sum2', 'lane_geometry'", "'curve_else', 'lane_geometry'"),
            ('tools/carla_lane_oracle/sum2_guard_contracts.py',
             "NONPRODUCTION = {'tests',", "NONPRODUCTION = {'other',"),
            ('tools/affected.py', r'main\s*\(', r'else\s*\('),
            ('tools/cache_key.py', "SKIP = {'.git',", "SKIP = {'.old',"),
        )
        command = '''import hashlib, importlib.util, os, py_compile, struct, sys
from pathlib import Path
root = Path(sys.argv[1])
path = root/sys.argv[2]
original = path.read_bytes()
before, after = sys.argv[3].encode(), sys.argv[4].encode()
if original.count(before) != 1 or len(before) != len(after):
    raise RuntimeError('stale-pyc mutation must be unique and size-preserving')
state = path.stat()
cache = Path(importlib.util.cache_from_source(str(path)))
prior_cache = cache.read_bytes() if cache.exists() else None
try:
    path.write_bytes(original.replace(before, after, 1))
    os.utime(path, ns=(state.st_atime_ns, state.st_mtime_ns))
    py_compile.compile(str(path), cfile=str(cache), doraise=True,
                       optimize=sys.flags.optimize,
                       invalidation_mode=py_compile.PycInvalidationMode.TIMESTAMP)
    path.write_bytes(original)
    os.utime(path, ns=(state.st_atime_ns, state.st_mtime_ns))
    if hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(original).digest():
        raise RuntimeError('physical dependency is not the original sealed source')
    magic, flags, timestamp, size = struct.unpack('<4sIII', cache.read_bytes()[:16])
    if (magic != importlib.util.MAGIC_NUMBER or flags != 0
            or timestamp != int(path.stat().st_mtime) & 0xffffffff
            or size != len(path.read_bytes())):
        raise RuntimeError('stale timestamp pyc is not a valid cache candidate')
    sys.path.insert(0, str(root/'tools/carla_lane_oracle'))
    import full_audit_cleanup_contracts as cleanup
    cleanup.executing_checker_bindings(root)
finally:
    path.write_bytes(original)
    os.utime(path, ns=(state.st_atime_ns, state.st_mtime_ns))
    if prior_cache is None:
        cache.unlink(missing_ok=True)
    else:
        cache.write_bytes(prior_cache)
'''
        for mode in ([], ['-O']):
            for name, before, after in cases:
                self.assertEqual(len(before), len(after))
                original = (self.root/name).read_bytes()
                with self.subTest(mode=mode, dependency=name):
                    result = subprocess.run([sys.executable, *mode, '-B', '-c', command,
                                             str(self.root), name, before, after],
                                            cwd=self.root, capture_output=True, text=True, timeout=120)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('executed dependency module differs from captured source: ' + name,
                                  result.stderr)
                    self.assertEqual((self.root/name).read_bytes(), original)
        cleanup.verify(self.root, exact=True)

    def test_incomplete_consumed_module_import_fails_closed(self):
        command = '''import importlib.util, sys, types
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root/'tools/carla_lane_oracle'))
name = sys.argv[2]
path = root/sys.argv[3]
incomplete = types.ModuleType(name)
incomplete.__file__ = str(path)
incomplete.__spec__ = importlib.util.spec_from_file_location(name, path)
sys.modules[name] = incomplete
import full_audit_cleanup_contracts as cleanup
cleanup.executing_checker_bindings(root)
'''
        cases = (
            ('source_contracts', 'tools/carla_lane_oracle/source_contracts.py'),
            ('sum2_guard_contracts', 'tools/carla_lane_oracle/sum2_guard_contracts.py'),
            ('_full_audit_cleanup_affected', 'tools/affected.py'),
            ('_full_audit_cleanup_cache_key', 'tools/cache_key.py'),
        )
        for mode in ([], ['-O']):
            for module, name in cases:
                with self.subTest(mode=mode, dependency=name):
                    result = subprocess.run([sys.executable, *mode, '-B', '-c', command,
                                             str(self.root), module, name],
                                            cwd=self.root, capture_output=True, text=True, timeout=120)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('full-audit cleanup successor:', result.stderr)

    def test_consumer_first_import_orders_normal_and_optimized(self):
        # Each process starts with the actual named consumer before any
        # explicit gate import. This includes transitive/circular imports and
        # the maintained sampled checker's importlib loader entrypoint.
        command = '''import importlib, importlib.util, sys
from pathlib import Path
root = Path(sys.argv[1])
route = sys.argv[2]
sys.path.insert(0, str(root/'tools/carla_lane_oracle'))
if route == 'sampled-spec':
    spec = importlib.util.spec_from_file_location(
        'sampled_consumer_first', root/'tools/carla_lane_oracle/check_sampled_values.py')
    if spec is None or spec.loader is None:
        raise RuntimeError('sampled consumer loader unavailable')
    consumer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(consumer)
else:
    consumer = importlib.import_module(route)
import full_audit_cleanup_contracts as cleanup
cleanup.verify(root, exact=True)
cleanup.proof_bindings(root)
if route == 'source_contracts':
    consumer.verify_group(root, 'optional_runtime')
else:
    consumer.verify(root)
print('consumer-first accepted: ' + route)
'''
        routes = ('sum2_guard_contracts', 'cache_key_contracts',
                  'seed_count_contracts', 'source_contracts', 'sampled-spec')
        for mode in ([], ['-O']):
            for route in routes:
                with self.subTest(mode=mode, first_consumer=route):
                    result = subprocess.run([sys.executable, *mode, '-B', '-c', command,
                                             str(self.root), route], cwd=self.root,
                                            capture_output=True, text=True, timeout=120)
                    self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
                    self.assertIn('consumer-first accepted: ' + route, result.stdout)

    def test_normal_and_optimized_python_preserve_positive_and_count_refusal(self):
        command = ('import sys; from pathlib import Path; '
                   'sys.path.insert(0, str(Path(sys.argv[1])/"tools/carla_lane_oracle")); '
                   'import full_audit_cleanup_contracts as c; '
                   'c.verify(Path(sys.argv[2]), exact=True)')
        for mode in ([], ['-O']):
            result = subprocess.run([sys.executable, *mode, '-B', '-c', command, str(ROOT), str(self.root)],
                                    capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            changed = self.current.replace('if center_work >= 0:', 'if center_work > 0:', 1)
            with physical_change(self.root, LANE, changed.encode()):
                result = subprocess.run([sys.executable, *mode, '-B', '-c', command, str(ROOT), str(self.root)],
                                        capture_output=True, text=True, timeout=120)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('full-audit cleanup successor:', result.stderr)


if __name__ == '__main__':
    unittest.main()
