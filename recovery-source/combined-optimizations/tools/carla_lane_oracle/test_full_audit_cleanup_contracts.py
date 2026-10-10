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
from functools import wraps
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


class NativeDependencyInventoryBatching(unittest.TestCase):
    """Small real-file graphs exercise traversal scope without native runs."""

    def setUp(self):
        folder = tempfile.TemporaryDirectory(prefix='cleanup-native-closure-')
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)

    def sources(self, texts):
        for name, text in texts.items():
            path = self.root/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8')
        return set(texts), {name: (self.root/name).read_bytes() for name in texts}

    def test_shared_cyclic_duplicate_roots_keep_union_and_first_visit_order(self):
        known, snapshots = self.sources({
            'tests/first.mojo': 'import common.shared\nimport common.first\n',
            'tests/second.mojo': 'import common.shared\nimport tests.first\n',
            'common/shared.mojo': 'import common.cycle\n',
            'common/cycle.mojo': 'import common.shared\n',
            'common/first.mojo': '# First-only dependency.\n',
        })
        witnesses = ('tests/first.mojo', 'tests/second.mojo', 'tests/first.mojo')
        reads = []
        read = Path.read_bytes
        def observed(path, *args, **kwargs):
            if path.is_relative_to(self.root):
                reads.append(path.relative_to(self.root).as_posix())
            return read(path, *args, **kwargs)
        with patch.object(Path, 'read_bytes', observed):
            expected = set()
            for witness in witnesses:
                expected.update(cleanup.dependency_inventory(self.root, roots=(witness,),
                    entries=('tests',), _known=known, _snapshots=snapshots))
            first_visits = list(dict.fromkeys(reads))
            self.assertGreater(len(reads), len(first_visits))
            reads.clear()
            with patch.object(cleanup, 'dependency_inventory',
                              wraps=cleanup.dependency_inventory) as traversal:
                actual = cleanup._native_dependency_inventory(self.root,
                    witnesses=witnesses, _known=known, _snapshots=snapshots)
            self.assertEqual(traversal.call_count, 1)
            self.assertEqual(traversal.call_args.kwargs['roots'], tuple(reversed(witnesses)))
            self.assertEqual(traversal.call_args.kwargs['entries'], ('tests',))
            self.assertIs(traversal.call_args.kwargs['_known'], known)
            self.assertIs(traversal.call_args.kwargs['_snapshots'], snapshots)
            self.assertEqual(reads, first_visits)
            self.assertEqual(len(reads), len(set(reads)))
        self.assertEqual(actual, expected)
        self.assertEqual(actual, known)

    def test_native_only_dependencies_do_not_merge_production_closure(self):
        known, snapshots = self.sources({
            'production/main.mojo': 'import common.shared\n',
            'tests/first.mojo': 'import common.shared\n',
            'tests/second.mojo': 'import tests.native_only\n',
            'common/shared.mojo': '# Shared dependency.\n',
            'tests/native_only.mojo': '# Native-only dependency.\n',
        })
        reads = []
        read = Path.read_bytes
        def observed(path, *args, **kwargs):
            if path.is_relative_to(self.root):
                reads.append(path.relative_to(self.root).as_posix())
            return read(path, *args, **kwargs)
        with patch.object(Path, 'read_bytes', observed), patch.object(
                cleanup, 'dependency_inventory', wraps=cleanup.dependency_inventory) as traversal:
            production = cleanup.dependency_inventory(self.root,
                roots=('production/main.mojo',), entries=('production',),
                _known=known, _snapshots=snapshots)
            native = cleanup._native_dependency_inventory(self.root,
                witnesses=('tests/first.mojo', 'tests/second.mojo'),
                _known=known, _snapshots=snapshots)
        self.assertEqual(traversal.call_count, 2)
        self.assertEqual(production, {'production/main.mojo', 'common/shared.mojo'})
        self.assertEqual(native, {'tests/first.mojo', 'tests/second.mojo',
                                 'common/shared.mojo', 'tests/native_only.mojo'})
        self.assertEqual(reads.count('common/shared.mojo'), 2)

    def test_distinct_entry_contexts_keep_separate_traversals(self):
        known, snapshots = self.sources({
            'tests/first.mojo': 'import common.worker\n',
            'bench/second.mojo': 'import common.worker\n',
            'common/worker.mojo': 'import helper\n',
            'tests/helper.mojo': '# First entry context.\n',
            'bench/helper.mojo': '# Second entry context.\n',
        })
        witnesses = ('tests/first.mojo', 'bench/second.mojo', 'tests/first.mojo')
        with patch.object(cleanup, 'dependency_inventory',
                          wraps=cleanup.dependency_inventory) as traversal:
            actual = cleanup._native_dependency_inventory(self.root,
                witnesses=witnesses, _known=known, _snapshots=snapshots)
        self.assertEqual(actual, known)
        self.assertEqual(traversal.call_count, len(witnesses))
        for witness, call in zip(witnesses, traversal.call_args_list, strict=True):
            self.assertEqual(call.kwargs['roots'], (witness,))
            self.assertEqual(call.kwargs['entries'], (str(Path(witness).parent),))
            self.assertIs(call.kwargs['_known'], known)
            self.assertIs(call.kwargs['_snapshots'], snapshots)

    def test_missing_root_or_physical_dependency_still_rejects(self):
        known, snapshots = self.sources({
            'tests/first.mojo': 'import tests.native_only\n',
            'tests/native_only.mojo': '# Native-only dependency.\n',
        })
        with self.assertRaisesRegex(cleanup.ContractError, 'missing maintained dependency'):
            cleanup._native_dependency_inventory(self.root,
                witnesses=('tests/missing.mojo',), _known=known, _snapshots=snapshots)
        (self.root/'tests/native_only.mojo').unlink()
        with self.assertRaises(OSError):
            cleanup._native_dependency_inventory(self.root,
                witnesses=('tests/first.mojo',), _known=known, _snapshots=snapshots)

    def test_each_consumed_raw_source_matches_snapshot_before_parsing(self):
        known, snapshots = self.sources({
            'tests/first.mojo': 'import common.shared\n',
            'tests/second.mojo': 'import common.shared\n',
            'common/shared.mojo': '# Shared dependency.\n',
        })
        witnesses = ('tests/first.mojo', 'tests/second.mojo')
        read = Path.read_bytes
        for name in sorted(known):
            changed = snapshots[name] + b'# Transient consumed B.\n'
            reads = []
            def transient(path, *args, **kwargs):
                raw = read(path, *args, **kwargs)
                if path == self.root/name:
                    reads.append(raw)
                    return changed
                return raw
            with self.subTest(source=name), patch.object(Path, 'read_bytes', transient), patch.object(
                    cleanup, '_physical_text', wraps=cleanup._physical_text) as parse:
                with self.assertRaisesRegex(cleanup.ContractError, 'source changed during import census'):
                    cleanup._native_dependency_inventory(self.root,
                        witnesses=witnesses, _known=known, _snapshots=snapshots)
                self.assertEqual(len(reads), 1)
                self.assertNotIn(changed, [call.args[0] for call in parse.call_args_list])
            self.assertEqual((self.root/name).read_bytes(), snapshots[name])
            # Each call has a new visited set and consumes the current bytes.
            self.assertEqual(cleanup._native_dependency_inventory(self.root,
                witnesses=witnesses, _known=known, _snapshots=snapshots), known)

    def test_empty_witnesses_do_not_start_a_traversal(self):
        with patch.object(cleanup, 'dependency_inventory') as traversal:
            self.assertEqual(cleanup._native_dependency_inventory(self.root,
                witnesses=(), _known=set(), _snapshots={}), set())
            traversal.assert_not_called()


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

    def test_native_batch_preserves_final_source_path_and_resolver_checks(self):
        # Mutate after all dependency consumption and bound-source checks.
        # Final checks must still reject, including an include-root shadow.
        with tempfile.TemporaryDirectory(prefix='cleanup-final-resolver-') as folder:
            include = Path(folder)
            cases = (
                (self.root, cleanup.NATIVE_WITNESSES[0], 'input changed during verification'),
                (self.root, 'tests/fresh_native_batch_input.mojo',
                 'source path inventory changed during verification'),
                (self.root, 'tests/std.mojopkg', 'resolver surface changed during verification'),
                (include, 'std.mojopkg', 'resolver surface changed during verification'),
            )
            inventory = cleanup.inventory
            for root, name, message in cases:
                path = root/name
                previous = path.read_bytes() if path.exists() else None
                consumed = []
                @wraps(inventory)
                def changed(*args, **kwargs):
                    result = inventory(*args, **kwargs)
                    consumed.append(True)
                    path.write_bytes((previous or b'') + b'\n# Late mutation.\n')
                    return result
                try:
                    with self.subTest(root=str(root), input=name), patch.object(cleanup, 'inventory', changed):
                        with self.assertRaisesRegex(cleanup.ContractError, message):
                            cleanup.verify(self.root, include_roots=(include,))
                    self.assertEqual(consumed, [True])
                finally:
                    if previous is None:
                        path.unlink(missing_ok=True)
                    else:
                        path.write_bytes(previous)
            cleanup.verify(self.root, exact=True, include_roots=(include,))

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
        before = ('if terms > max_terms - center_work:\n'
                  '            raise Error("Lane refinement exhausted its quadrature work limit")')
        changed = mutate_function(self, self.current, '_try_lane_center_bound', before,
                                  'if terms > max_terms - center_work:\n'
                                  '            raise Error(r"Lane refinement exhausted its quadrature work limit")')
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
                    'math.mojo', 'tests/math.mojo',
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

    def test_resolver_namespace_boundaries_keep_unrelated_leaves(self):
        # The real repository already contains geometries/utils.mojo while
        # math/utils.mojo is consumed. Neither leaf makes the other a shadow.
        self.assertTrue((self.root/'geometries/utils.mojo').is_file())
        cleanup.verify(self.root, exact=True)
        with tempfile.TemporaryDirectory(prefix='cleanup-qualified-resolver-') as folder:
            include = Path(folder)
            for root in (self.root, include):
                for name in ('unconsumed_namespace/utils.mojo',
                             'unconsumed_namespace/geometry.mojo'):
                    with self.subTest(root=str(root), positive=name), physical_change(root, name, b'# unrelated qualified leaf\n'):
                        cleanup.verify(self.root, include_roots=(include,))
                for name in ('tests/math.mojo', 'bench/extensions.mojopkg',
                             'math.mojoc', 'math.mojopkg', 'tests/math.mojoc',
                             'tests/math.mojopkg', 'bench/extensions.mojoc',
                             'extensions/carla/lane_refinement.mojoc',
                             'tests/extensions/carla/lane_refinement.mojo',
                             'tests/math/__init__.mojo', 'tests/extensions/__init__.mojo',
                             'tests/Math.mojo', 'tests/std/__init__.mojo'):
                    with self.subTest(root=str(root), negative=name), physical_change(root, name, b'# actual entry namespace competitor\n'):
                        with self.assertRaises(cleanup.ContractError):
                            cleanup.verify(self.root, include_roots=(include,))
            for root in (self.root, include):
                for name in ('MATH', 'extensions/CARLA'):
                    directory = root/name
                    directory.mkdir(parents=True)
                    try:
                        with self.subTest(root=str(root), empty_case_prefix=name):
                            with self.assertRaises(cleanup.ContractError):
                                cleanup.verify(self.root, include_roots=(include,))
                    finally:
                        directory.rmdir()
            # This is an allowed qualified path, not bare math in an entry dir.
            # The maintained generation-origin protocol owns staged bytes.
            with physical_change(include, 'extensions/carla/math.mojo', b'# staged instrumentation view\n'):
                cleanup.verify(self.root, include_roots=(include,))
            cleanup.verify(self.root, exact=True)

    def test_maintained_resolver_keeps_ordered_entry_roots_before_repository(self):
        affected = cleanup._sibling('affected')
        known = {'tools/probe.mojo', 'tests/probe.mojo', 'pkg/one.mojo',
                 'helper.mojo', 'pkg/helper.mojo', 'tools/helper.mojo', 'tests/helper.mojo'}
        self.assertEqual(affected.resolve('helper', 'pkg/one.mojo', known,
                                          entries=['tests', 'tools']),
                         ['tests/helper.mojo', 'tools/helper.mojo', 'helper.mojo'])
        self.assertEqual(affected.resolve('helper', 'pkg/one.mojo', known,
                                          entries=['tools', 'tests']),
                         ['tools/helper.mojo', 'tests/helper.mojo', 'helper.mojo'])
        self.assertEqual(affected.resolve('helper', 'pkg/one.mojo', known,
                                          entries=['tests', 'tests']),
                         ['tests/helper.mojo', 'helper.mojo'])
        self.assertEqual(affected.resolve('helper', 'tools/probe.mojo', known),
                         ['tools/helper.mojo', 'helper.mojo'])
        self.assertEqual(affected.resolve('helper', 'pkg/one.mojo',
                                          {'pkg/one.mojo', 'pkg/helper.mojo'}, entries=['tools']), [])
        prefix_known = {'tools/pkg/__init__.mojo', 'tools/pkg.mojo',
                        'tools/pkg/sub/__init__.mojo', 'tools/pkg/sub.mojo',
                        'pkg/__init__.mojo', 'pkg.mojo', 'pkg/sub/one.mojo'}
        self.assertEqual(affected.resolve('pkg.sub.one', 'pkg/other.mojo', prefix_known,
                                          entries=['tools']),
                         ['tools/pkg/__init__.mojo', 'tools/pkg.mojo',
                          'tools/pkg/sub/__init__.mojo', 'tools/pkg/sub.mojo',
                          'pkg/__init__.mojo', 'pkg.mojo', 'pkg/sub/one.mojo'])
        self.assertEqual(affected.entry_directories({
            'tools/probe.mojo': 'def main():\n    pass\n',
            'tests/probe.mojo': 'fn main():\n    pass\n',
            'pkg/one.mojo': '# def main():\nfrom helper import value\n',
        }), ['tests', 'tools'])

    def test_dependency_census_uses_entry_directory_for_transitive_imports(self):
        # A sparse physical fixture exercises only the maintained resolver
        # primitive. It makes no complete-source-admission claim.
        with tempfile.TemporaryDirectory(prefix='cleanup-entry-roots-') as folder:
            root = Path(folder)
            files = {
                'tools/probe.mojo': 'from pkg.one import value\ndef main():\n    pass\n',
                'tests/probe.mojo': 'from pkg.one import value\ndef main():\n    pass\n',
                'pkg/one.mojo': 'from helper import value\n',
                'helper.mojo': 'def value() -> Int:\n    return 0\n',
                'tools/helper.mojo': 'def value() -> Int:\n    return 1\n',
                'tests/helper.mojo': 'def value() -> Int:\n    return 2\n',
                'pkg/helper.mojo': 'def value() -> Int:\n    return 3\n',
            }
            for name, text in files.items():
                target = root/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text)
            for entry in ('tools', 'tests'):
                with self.subTest(compiled_entry_directory=entry):
                    self.assertEqual(cleanup.dependency_inventory(root,
                        roots=(entry+'/probe.mojo',), entries=(entry,)),
                        {entry+'/probe.mojo', 'pkg/one.mojo', entry+'/helper.mojo', 'helper.mojo'})
            self.assertEqual(cleanup.dependency_inventory(root,
                roots=('tools/probe.mojo', 'tests/probe.mojo'), entries=('tests', 'tools')),
                {'tools/probe.mojo', 'tests/probe.mojo', 'pkg/one.mojo',
                 'tests/helper.mojo', 'tools/helper.mojo', 'helper.mojo'})

    def test_entry_namespace_symlinks_and_real_qualified_byte_mutation_reject(self):
        name = 'extensions/carla/math.mojo'
        original = (self.root/name).read_bytes()
        with physical_change(self.root, name, original+b'\n# Changed actual producer.\n'):
            self.reject_current()
        cleanup.verify(self.root, exact=True)
        with tempfile.TemporaryDirectory(prefix='cleanup-entry-symlink-') as folder:
            include = Path(folder)
            for root in (self.root, include):
                with self.subTest(root=str(root), symlink='entry module'), physical_change(
                        root, 'tests/math.mojo', b'# placeholder\n') as path:
                    path.unlink()
                    path.symlink_to(self.root/'math/utils.mojo')
                    with self.assertRaises(cleanup.ContractError):
                        cleanup.verify(self.root, include_roots=(include,))
                link = root/'tests/extensions'
                parent_existed = link.parent.exists()
                link.parent.mkdir(parents=True, exist_ok=True)
                try:
                    link.symlink_to(self.root/'extensions', target_is_directory=True)
                    with self.subTest(root=str(root), symlink='entry package'):
                        with self.assertRaises(cleanup.ContractError):
                            cleanup.verify(self.root, include_roots=(include,))
                finally:
                    link.unlink()
                    if not parent_existed:
                        link.parent.rmdir()
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
        import seed_count_contracts as seed_count
        historical = fixtures.historical_root(self, ROOT)
        self.assertEqual(cleanup.reviewed_sum2_callers(historical), {})
        self.assertEqual(guard.verify(historical)['status'], 'PASS')
        path = historical/VALUE
        original = path.read_bytes()
        grouped = original.decode().replace('var magnitude = value', 'var magnitude = (value)', 1)
        self.assertNotEqual(grouped.encode(), original)
        # Match the maintained sampled grouping fixture: current seed-score
        # successors bind this dependency byte-for-byte. Use the fully verified
        # historical Map only for this isolated historical grouping control.
        seed_before = seed_count.historical_source(ROOT).encode('utf-8')
        self.assertEqual(cleanup.sha(seed_before), seed_count.BEFORE_SHA256)
        with physical_change(historical, seed_count.MODULE, seed_before):
            self.assertEqual(guard.verify(historical)['status'], 'PASS')
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
                    self.assertRegex(result.stderr,
                        r'(?m)^full_audit_cleanup_contracts\.ContractError: '
                        r'full-audit cleanup successor: [^\n]+\n?\Z')
                    if module == 'source_contracts':
                        cause, separator, refusal = result.stderr.partition(
                            '\nThe above exception was the direct cause of the following exception:\n')
                        self.assertTrue(separator, result.stderr)
                        self.assertIn("ImportError: cannot import name 'token_sha256' from 'source_contracts'",
                                      cause)
                        self.assertIn('full_audit_cleanup_contracts.ContractError: '
                                      'full-audit cleanup successor: dependency import failed', refusal)

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
elif route == 'test_accepted_successor_contracts':
    consumer.prior.verify(root)
elif route == 'test_production_inventory_paths':
    consumer.cache.verify(root)
    consumer.order.verify(root)
    consumer.guard.verify(root)
else:
    consumer.verify(root)
print('consumer-first accepted: ' + route)
'''
        routes = ('sum2_guard_contracts', 'cache_key_contracts',
                  'seed_count_contracts', 'source_contracts', 'sampled-spec',
                  'test_accepted_successor_contracts',
                  'test_production_inventory_paths')
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

    def test_selector_projection_one_real_gate_both_predicates_and_fresh_calls(self):
        from functools import wraps
        original = cleanup.verify
        declarations, checks, admissions, observations = [], [], [], []
        declaration, require, observe = guard.declaration, selector.require, selector._lane_observation
        @wraps(original)
        def admitted(*args, **kwargs):
            result = original(*args, **kwargs)
            admissions.append((args[0], kwargs))
            return result
        @wraps(declaration)
        def declared(text, name, owner):
            if sys._getframe(1).f_code is selector.verify_premises.__code__:
                declarations.append((name, text))
            return declaration(text, name, owner)
        def checked(value, message):
            checks.append(message)
            return require(value, message)
        def observed(root):
            observations.append(root)
            return observe(root)
        expected = selector.read_record(self.root)
        with patch.object(cleanup, 'verify', admitted), patch.object(guard, 'declaration', declared), \
                patch.object(selector, 'require', checked), patch.object(selector, '_lane_observation', observed):
            for operation in (selector.verify_premises, selector.verify, selector.verify_premises):
                before = len(admissions)
                self.assertEqual(operation(self.root), expected)
                self.assertEqual(len(admissions), before + 1)
        self.assertEqual(len(observations), 3)
        self.assertEqual(checks.count('consumer import scope changed'), 6)
        minimum = [text for name, text in declarations if name == '_rounded_axis_lane_minimum']
        self.assertEqual(minimum, [self.item['before_source']] * 3)
        self.assertEqual(sum(name == '_refine_lane_certificate' for name, _ in declarations), 3)
        for root, kwargs in admissions:
            self.assertEqual(root, self.root)
            self.assertEqual(kwargs, {'_expected_lane_raw': self.current.encode()})

    def test_selector_projection_expected_bytes_constraint_and_initial_aba(self):
        from functools import wraps
        class BytesSubclass(bytes):
            pass
        raw = (self.root/LANE).read_bytes()
        for value in (False, '', LANE, {}, object(), bytearray(raw), memoryview(raw), BytesSubclass(raw)):
            with self.subTest(kind=type(value).__name__):
                with self.assertRaisesRegex(cleanup.ContractError, 'expected lane observation is not bytes'):
                    cleanup.verify(self.root, _expected_lane_raw=value)
                with self.assertRaisesRegex(cleanup.ContractError, 'expected lane observation is not bytes'):
                    cleanup._reviewed_lane_observation(self.root, self.current, value)
        with self.assertRaisesRegex(cleanup.ContractError, 'lane observation changed'):
            cleanup.verify(self.root, _expected_lane_raw=b'')
        self.assertEqual(cleanup.verify(self.root, _expected_lane_raw=None), self.record)
        self.assertEqual(cleanup.verify(self.root, _expected_lane_raw=raw), self.record)
        read, decode = Path.read_bytes, cleanup._physical_text
        changed_raw = raw + b'\n# Initial gate B, while the selector observed A.\n'
        consumed, parsed = [], []
        def changed(path, *args, **kwargs):
            result = read(path, *args, **kwargs)
            caller = sys._getframe(1)
            if path == self.root/LANE and (caller.f_code is cleanup.verify.__code__
                    or caller.f_code.co_name == '<dictcomp>' and caller.f_back.f_code is cleanup.verify.__code__):
                consumed.append('B')
                return changed_raw
            return result
        @wraps(decode)
        def decoded(value):
            if value == changed_raw:
                parsed.append('B')
            return decode(value)
        with patch.object(Path, 'read_bytes', changed), patch.object(cleanup, '_physical_text', decoded):
            with self.assertRaisesRegex(cleanup.ContractError, 'lane observation changed before current admission'):
                selector.verify_premises(self.root)
        self.assertEqual(consumed, ['B'])
        self.assertEqual(parsed, [])
        self.assertEqual((self.root/LANE).read_bytes(), raw)

    def test_selector_projection_captured_road_b_is_not_gate_road_a(self):
        road = self.root/'extensions/carla/road.mojo'
        raw, read = road.read_bytes(), Path.read_bytes
        observations = []
        def changed(path, *args, **kwargs):
            result = read(path, *args, **kwargs)
            if path == road and sys._getframe(1).f_code is cleanup._reviewed_lane_observation.__code__:
                observations.append('B')
                return result + b'\n# Unadmitted capture B.\n'
            return result
        with patch.object(Path, 'read_bytes', changed):
            with self.assertRaisesRegex(cleanup.ContractError, 'road observation changed before current admission'):
                selector.verify_premises(self.root)
        self.assertEqual(observations, ['B'])
        self.assertEqual(road.read_bytes(), raw)

    def test_selector_projection_scope_and_minimum_remain_mandatory(self):
        from functools import wraps
        project = cleanup._reviewed_lane_observation
        before = self.item['before_source']
        altered_scope = before.replace('from extensions.carla.curve_sum2 import', 'from unreviewed_sum2 import', 1)
        altered_minimum = mutate_function(self, before, '_rounded_axis_lane_minimum',
                                         'terms += 1', 'terms += 0')
        self.assertNotEqual(altered_scope, before)
        for label, changed, message in (
                ('scope', altered_scope, 'consumer import scope changed'),
                ('minimum', altered_minimum, 'prior consumer/reference changed: _rounded_axis_lane_minimum'),
                ('both', altered_minimum.replace('from extensions.carla.curve_sum2 import',
                                                'from unreviewed_sum2 import', 1), 'consumer import scope changed')):
            calls = []
            @wraps(project)
            def projected(*args, **kwargs):
                text, road = project(*args, **kwargs)
                calls.append(text)
                return changed, road
            with self.subTest(change=label), patch.object(cleanup, '_reviewed_lane_observation', projected):
                with self.assertRaisesRegex(ValueError, message):
                    selector.verify_premises(self.root)
            self.assertEqual(calls, [before])

    def test_selector_projection_late_first_admission_rechecks_scope(self):
        from functools import wraps
        observe, project = selector._lane_observation, cleanup._reviewed_lane_observation
        before = self.item['before_source']
        for broken in (False, True):
            observations, admissions = [], []
            def observed(root):
                observations.append(root)
                if len(observations) == 1:
                    # A historical first read can precede a fresh current read.
                    return before, before.encode()
                return observe(root)
            @wraps(project)
            def projected(*args, **kwargs):
                text, road = project(*args, **kwargs)
                admissions.append(text)
                if broken:
                    text = text.replace('from extensions.carla.curve_sum2 import', 'from unreviewed_sum2 import', 1)
                return text, road
            with self.subTest(broken_scope=broken), patch.object(selector, '_lane_observation', observed), \
                    patch.object(cleanup, '_reviewed_lane_observation', projected):
                if broken:
                    with self.assertRaisesRegex(ValueError, 'consumer import scope changed'):
                        selector.verify_premises(self.root)
                else:
                    self.assertEqual(selector.verify_premises(self.root), selector.read_record(self.root))
            self.assertEqual(len(observations), 2)
            self.assertEqual(admissions, [before])

    def test_selector_projection_retained_road_and_lane_b_reject_before_parse(self):
        from functools import wraps
        road = 'extensions/carla/road.mojo'
        road_raw = (self.root/road).read_bytes()
        lane_raw = (self.root/LANE).read_bytes()
        cases = (
            (road, 'import', road_raw.replace(b'from extensions.carla.curve_distance import',
                                            b'from unreviewed_distance import', 1)),
            (road, 'unrelated_body', road_raw.replace(b'return self.lane_index(id) >= 0',
                                                    b'return self.lane_index(id) > 0', 1)),
            (road, 'comment', road_raw + b'\n# Intervening comment-only B.\n'),
            (road, 'undecodable', road_raw + b'\xff'),
            (LANE, 'semantic', lane_raw.replace(b'if center_work >= 0:', b'if center_work > 0:', 1)),
            (LANE, 'comment', lane_raw + b'\n# Later comment-only B.\n'),
        )
        read, decode, declaration = Path.read_bytes, cleanup._physical_text, guard.declaration
        for name, label, changed_raw in cases:
            original = (self.root/name).read_bytes()
            self.assertNotEqual(changed_raw, original)
            if name == road and label != 'undecodable':
                self.assertEqual(guard.declaration(changed_raw.decode(), '_check_lane', ('Road',)),
                                 guard.declaration(original.decode(), '_check_lane', ('Road',)))
            observed, decoded, declared = [], [], []
            def changed(path, *args, **kwargs):
                result = read(path, *args, **kwargs)
                if path == self.root/name and sys._getframe(1).f_code is selector.verify_premises.__code__:
                    observed.append('B' if not observed else 'A')
                    if len(observed) == 1:
                        return changed_raw
                return result
            @wraps(decode)
            def decoded_text(raw):
                if raw == changed_raw:
                    decoded.append('B')
                return decode(raw)
            @wraps(declaration)
            def declared_text(text, function, owner):
                if sys._getframe(1).f_code is selector.verify_premises.__code__:
                    declared.append(function)
                return declaration(text, function, owner)
            with self.subTest(path=name, change=label), patch.object(Path, 'read_bytes', changed), \
                    patch.object(cleanup, '_physical_text', decoded_text), patch.object(guard, 'declaration', declared_text):
                with self.assertRaisesRegex(ValueError, 'rounded LINE selector contract: consumer observation changed: ' + name):
                    selector.verify_premises(self.root)
            self.assertEqual(observed, ['B'])
            self.assertEqual(decoded, [])
            self.assertNotIn('_check_lane' if name == road else '_refine_lane_certificate', declared)
            self.assertEqual((self.root/name).read_bytes(), original)

    @contextmanager
    def _selector_projection_alias(self, name, kind):
        target = self.root if kind == 'root' else self.root/name
        if kind == 'ancestor':
            target = target.parent
        with tempfile.TemporaryDirectory(prefix='selector-observation-alias-') as directory:
            stored = Path(directory)/'physical'
            target.rename(stored)
            try:
                target.symlink_to(stored, target_is_directory=stored.is_dir())
                yield
            finally:
                if target.is_symlink():
                    target.unlink()
                stored.rename(target)

    def test_selector_projection_retained_regular_paths_reject_matching_aliases(self):
        from contextlib import ExitStack
        from functools import wraps
        regular, decode = cleanup._regular, cleanup._physical_text
        for name, kind in ((name, kind) for name in ('extensions/carla/road.mojo', LANE)
                           for kind in ('leaf', 'ancestor', 'root')):
            visits, parsed = [], []
            with ExitStack() as stack:
                @wraps(regular)
                def checked(root, relative):
                    if root == self.root and relative == name and sys._getframe(1).f_code is selector.verify_premises.__code__:
                        visits.append(relative)
                        if len(visits) == 1:
                            stack.enter_context(self._selector_projection_alias(name, kind))
                    return regular(root, relative)
                @wraps(decode)
                def decoded(raw):
                    if visits:
                        parsed.append(raw)
                    return decode(raw)
                with self.subTest(path=name, alias=kind), patch.object(cleanup, '_regular', checked), \
                        patch.object(cleanup, '_physical_text', decoded):
                    with self.assertRaisesRegex(cleanup.ContractError, 'symlink input|symbolic root or ancestor'):
                        selector.verify_premises(self.root)
                self.assertEqual(visits, [name])
                self.assertEqual(parsed, [])
            self.assertFalse((self.root/name).is_symlink())

    def test_selector_projection_final_two_paths_reject_late_changes(self):
        from contextlib import ExitStack
        from functools import wraps
        regular = cleanup._regular
        for name, kind in ((name, kind) for name in (LANE, 'extensions/carla/road.mojo')
                           for kind in ('bytes', 'missing', 'leaf', 'ancestor', 'root')):
            raw, visits = (self.root/name).read_bytes(), []
            with ExitStack() as stack:
                @wraps(regular)
                def checked(root, relative):
                    if root == self.root and relative == name and sys._getframe(1).f_code is selector.verify_premises.__code__:
                        visits.append(relative)
                        if len(visits) == 2:
                            if kind in ('bytes', 'missing'):
                                stack.enter_context(physical_change(self.root, name,
                                    raw + b'\n# After the last predicate.\n' if kind == 'bytes' else None))
                            else:
                                stack.enter_context(self._selector_projection_alias(name, kind))
                    return regular(root, relative)
                with self.subTest(path=name, change=kind), patch.object(cleanup, '_regular', checked):
                    with self.assertRaises(ValueError) as caught:
                        selector.verify_premises(self.root)
                self.assertEqual(visits, [name, name])
                if kind == 'missing':
                    self.assertRegex(str(caught.exception), 'rounded LINE selector contract: unreadable observation: ' + name)
                    self.assertIsInstance(caught.exception.__cause__, OSError)
                elif kind == 'bytes':
                    self.assertRegex(str(caught.exception), 'consumer observation changed: ' + name)
                else:
                    self.assertIsInstance(caught.exception, cleanup.ContractError)
            self.assertEqual((self.root/name).read_bytes(), raw)

    def test_selector_projection_supplied_views_and_physical_parsing(self):
        from functools import wraps
        read, declaration = Path.read_text, guard.declaration
        for name in ('extensions/carla/road.mojo', LANE):
            physical_text = (self.root/name).read_text()
            for disagree in (False, True):
                supplied, parsed = [], []
                def changed(path, *args, **kwargs):
                    text = read(path, *args, **kwargs)
                    if path == self.root/name and sys._getframe(1).f_code is selector.verify_premises.__code__:
                        # Road import scope precedes projection and stays unchanged.
                        caller = sys._getframe(1)
                        if caller.f_locals.get('lane_predecessor') is not None:
                            supplied.append(text)
                            return text + ('\ndef unreviewed_view():\n    pass\n' if disagree else '\n# Supplied-only view.\n')
                    return text
                @wraps(declaration)
                def declared(text, function, owner):
                    if sys._getframe(1).f_code is selector.verify_premises.__code__ and function == (
                            '_check_lane' if name.endswith('/road.mojo') else '_refine_lane_certificate'):
                        parsed.append(text)
                    return declaration(text, function, owner)
                with self.subTest(path=name, disagree=disagree), patch.object(Path, 'read_text', changed), \
                        patch.object(guard, 'declaration', declared):
                    if disagree:
                        with self.assertRaisesRegex(ValueError, 'consumer source text/bytes disagree: ' + name):
                            selector.verify_premises(self.root)
                    else:
                        selector.verify_premises(self.root)
                self.assertEqual(supplied, [physical_text])
                self.assertEqual(parsed, [] if disagree else [physical_text])

    def test_selector_projection_error_families_for_capture_retained_and_final_reads(self):
        from functools import wraps
        import accepted_successor_contracts as accepted
        road = 'extensions/carla/road.mojo'
        regular, read_bytes, read_text, decode = cleanup._regular, Path.read_bytes, Path.read_text, cleanup._physical_text
        cases = (
            ('capture_regular', road, False), ('capture_bytes', road, True),
            ('retained_regular', road, False), ('retained_bytes', LANE, True),
            ('retained_text', road, False), ('retained_text', LANE, True),
            ('retained_decode', road, False), ('retained_decode', LANE, True),
            ('final_regular', LANE, False), ('final_bytes', road, True),
        )
        for stage, name, wrapped in cases:
            visits, raised = [], []
            failure = (UnicodeDecodeError('utf-8', b'\xff', 0, 1, 'test observation')
                       if stage == 'retained_decode' else PermissionError('test unreadable observation'))
            @wraps(regular)
            def checked(root, relative):
                caller = sys._getframe(1)
                if root == self.root and relative == name:
                    if caller.f_code is selector.verify_premises.__code__:
                        visits.append(relative)
                        if (stage == 'retained_regular' and len(visits) == 1
                                or stage == 'final_regular' and len(visits) == 2):
                            raised.append(stage)
                            raise failure
                    if stage == 'capture_regular' and caller.f_code is cleanup._reviewed_lane_observation.__code__:
                        raised.append(stage)
                        raise failure
                return regular(root, relative)
            def bytes_read(path, *args, **kwargs):
                caller = sys._getframe(1)
                if path == self.root/name:
                    if (stage == 'capture_bytes' and caller.f_code is cleanup._reviewed_lane_observation.__code__
                            or stage == 'retained_bytes' and caller.f_code is selector.verify_premises.__code__ and len(visits) == 1
                            or stage == 'final_bytes' and caller.f_code is selector.verify_premises.__code__ and len(visits) == 2):
                        raised.append(stage)
                        raise failure
                return read_bytes(path, *args, **kwargs)
            def text_read(path, *args, **kwargs):
                if (stage == 'retained_text' and path == self.root/name and visits
                        and sys._getframe(1).f_code is selector.verify_premises.__code__):
                    raised.append(stage)
                    raise failure
                return read_text(path, *args, **kwargs)
            @wraps(decode)
            def decoded(raw):
                if stage == 'retained_decode' and visits and sys._getframe(1).f_code is selector.verify_premises.__code__:
                    raised.append(stage)
                    raise failure
                return decode(raw)
            operation = accepted.verify_current if wrapped else selector.verify_premises
            with self.subTest(stage=stage, wrapped=wrapped), patch.object(cleanup, '_regular', checked), \
                    patch.object(Path, 'read_bytes', bytes_read), patch.object(Path, 'read_text', text_read), \
                    patch.object(cleanup, '_physical_text', decoded):
                with self.assertRaises(ValueError) as caught:
                    operation(self.root)
            self.assertEqual(raised, [stage])
            error = caught.exception.__cause__ if wrapped else caught.exception
            self.assertIsInstance(error, ValueError)
            self.assertIs(error.__cause__, failure)
            if stage.startswith('capture'):
                self.assertIsInstance(error, cleanup.ContractError)
                self.assertIsInstance(error, RuntimeError)
                self.assertTrue(str(error).startswith('full-audit cleanup successor:'))
            else:
                self.assertTrue(str(error).startswith('rounded LINE selector contract: unreadable observation: ' + name))
            if wrapped:
                self.assertTrue(str(caught.exception).startswith('unreviewed complete successor: '))
        with self.assertRaises(cleanup.ContractError) as caught:
            cleanup._reviewed_lane_observation(self.root, self.current, b'\xff')
        self.assertIsInstance(caught.exception.__cause__, UnicodeError)

    def test_selector_projection_historical_lazy_inputs_and_exceptions(self):
        from functools import wraps
        historical = fixtures.historical_root(self, ROOT)
        before = self.item['before_source']
        original = cleanup.verify
        @wraps(original)
        def unexpected(*args, **kwargs):
            self.fail('historical selector unexpectedly requested current cleanup admission')
        with tempfile.TemporaryDirectory() as directory, patch.object(cleanup, 'verify', unexpected):
            self.assertEqual(cleanup._reviewed_lane_observation(Path(directory), before, before.encode()), (before, None))
            self.assertEqual(cleanup.reviewed_text(Path(directory), LANE, before), before)
            with physical_change(historical, cleanup.MIGRATION, None), \
                    physical_change(historical, 'tests/test_carla_lane_center_bound_phase.mojo', None):
                self.assertEqual(selector.verify_premises(historical), selector.verify(historical))
        read = Path.read_text
        failure = PermissionError('historical direct read stays direct')
        def unreadable(path, *args, **kwargs):
            if path == historical/LANE:
                raise failure
            return read(path, *args, **kwargs)
        with patch.object(Path, 'read_text', unreadable):
            with self.assertRaises(PermissionError) as caught:
                selector.verify_premises(historical)
        self.assertIs(caught.exception, failure)

    def test_selector_projection_stable_formatting_exact_authority_and_removed_read(self):
        from functools import wraps
        raw = (self.root/LANE).read_bytes()
        comments = (b'# def delimiter_in_a_comment():\n# @comment\n# struct Comment:\n' + raw).replace(
            b'    _lane_jet,\n', b'    _lane_jet,  # Multiline import stays complete.\n', 1)
        for changed in (comments, comments.replace(b'\n', b'\r\n')):
            with self.subTest(crlf=b'\r\n' in changed), physical_change(self.root, LANE, changed):
                self.assertEqual(selector.verify_premises(self.root), selector.verify(self.root))
                with self.assertRaises(cleanup.ContractError):
                    cleanup.verify(self.root, exact=True)
                with self.assertRaises(cleanup.ContractError):
                    cleanup.proof_bindings(self.root)
        # STRING spelling and extra grouping are still token-significant.
        for changed in (raw.replace(b'Finite global refinement', b'def misleading():\nFinite global refinement', 1),
                        raw.replace(b'while steps < 40:', b'while (steps < 40):', 1)):
            self.assertNotEqual(changed, raw)
            with physical_change(self.root, LANE, changed), self.assertRaises(ValueError):
                selector.verify_premises(self.root)
        observe, calls = selector._lane_observation, []
        def observed(root):
            calls.append(root)
            if len(calls) == 2:
                self.fail('the old second lane observation was removed after projection')
            return observe(root)
        with patch.object(selector, '_lane_observation', observed):
            selector.verify_premises(self.root)
        self.assertEqual(calls, [self.root])
        # This trace does not promise detection of a B scheduled only at the
        # removed read. Retained reads consume and reject B in separate tests.
        self.assertEqual((self.root/LANE).read_bytes(), raw)

    def test_selector_projection_separate_roots_explicit_contexts_and_failed_calls(self):
        from functools import wraps
        other = fixtures.copy_current_root(self, ROOT)
        original, admissions = cleanup.verify, []
        @wraps(original)
        def admitted(root, **kwargs):
            admissions.append((root, kwargs))
            return original(root, **kwargs)
        with patch.object(cleanup, 'verify', admitted):
            selector.verify_premises(self.root)
            road = 'extensions/carla/road.mojo'
            changed = (other/road).read_bytes() + b'\n# Changed second-root bound dependency.\n'
            with physical_change(other, road, changed):
                with self.assertRaises(cleanup.ContractError):
                    selector.verify_premises(other)
            selector.verify_premises(other)
            selector.verify_premises(self.root)
            with tempfile.TemporaryDirectory() as directory:
                include = Path(directory)
                (include/'std.mojo').write_text('# Resolver competitor.\n')
                with self.assertRaisesRegex(cleanup.ContractError, 'resolver surface'):
                    cleanup.verify(self.root, include_roots=(include,))
            self.assertEqual(cleanup.verify(self.root, exact=True), self.record)
            self.assertIn(cleanup.MIGRATION, cleanup.proof_bindings(self.root))
        self.assertEqual([root for root, _ in admissions[:4]], [self.root, other, other, self.root])
        self.assertEqual(len(admissions), 7)
        self.assertTrue(admissions[-1][1]['exact'])
        for kwargs in ({'context': object()}, {'admitted': True}, {'path': LANE}):
            with self.assertRaises(TypeError):
                cleanup._reviewed_lane_observation(self.root, self.current, self.current.encode(), **kwargs)
        with self._selector_projection_alias(LANE, 'root'):
            with self.assertRaisesRegex(cleanup.ContractError, 'symbolic root or ancestor'):
                selector.verify_premises(self.root)

    def test_selector_projection_nested_and_threaded_calls_own_their_inputs(self):
        from concurrent.futures import ThreadPoolExecutor
        from functools import wraps
        other = fixtures.copy_current_root(self, ROOT)
        original, admissions, nested = cleanup.verify, [], []
        @wraps(original)
        def admitted(root, **kwargs):
            if root == self.root and not nested:
                nested.append(selector.verify_premises(other))
            admissions.append(root)
            return original(root, **kwargs)
        with patch.object(cleanup, 'verify', admitted):
            self.assertEqual(selector.verify_premises(self.root), selector.read_record(self.root))
        self.assertEqual(admissions, [other, self.root])
        self.assertEqual(nested, [selector.read_record(other)])
        changed = (other/LANE).read_bytes() + b'\n# This root owns distinct stable bytes.\n'
        with physical_change(other, LANE, changed), ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(selector.verify_premises, (self.root, other)))
        self.assertEqual(results, [selector.read_record(self.root), selector.read_record(other)])
        self.assertEqual((self.root/LANE).read_bytes(), self.current.encode())

    def test_selector_projection_direct_import_forms(self):
        command = '''import importlib, sys
from pathlib import Path
root = Path(sys.argv[1])
if sys.argv[2] == 'package':
    sys.path.insert(0, str(root))
    selector = importlib.import_module('tools.carla_lane_oracle.rounded_line_selector_contracts')
else:
    sys.path.insert(0, str(root/'tools/carla_lane_oracle'))
    selector = importlib.import_module('rounded_line_selector_contracts')
if selector.verify_premises(root) != selector.verify(root):
    raise RuntimeError('selector results disagree')
print('selector projection import accepted: ' + sys.argv[2])
'''
        for mode in ([], ['-O']):
            for route in ('package', 'direct'):
                with self.subTest(mode=mode, route=route):
                    result = subprocess.run([sys.executable, *mode, '-B', '-c', command, str(self.root), route],
                                            cwd=self.root, capture_output=True, text=True, timeout=120)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn('selector projection import accepted: ' + route, result.stdout)



if __name__ == '__main__':
    unittest.main()
