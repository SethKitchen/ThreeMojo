#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""New reconstruction controls, not recovered historical test bytes.

Physical roots qualify first. Historical tests receive explicit fixed source
files only; current source admission and independent center semantics have
separate positive and adversarial controls. Run unchanged with Python and -O.
"""
import copy
from contextlib import contextmanager, nullcontext
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
    # A differently cased path can name the existing entry on macOS. Retain
    # that entry's actual spelling, including when this control removes it.
    original_path = path
    if previous is not None:
        entries = list(path.parent.iterdir())
        original_path = next((entry for entry in entries if entry.name == path.name), None)
        if original_path is None:
            original_path = next(entry for entry in entries
                                 if entry.name.casefold() == path.name.casefold()
                                 and entry.samefile(path))
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
        if path.is_symlink() or (previous is None and path.exists()):
            path.unlink()
        if previous is not None:
            original_path.write_bytes(previous)
        for folder in created:
            folder.rmdir()


@contextmanager
def physical_directory_spelling(path, spelling):
    """Exercise a real case-only rename and restore the complete directory."""
    target = path.with_name(spelling)
    if path.name == spelling or path.name.casefold() != spelling.casefold():
        raise AssertionError('fixture requires a different case spelling')
    if target.exists() and not target.samefile(path):
        raise AssertionError('case fixture would replace a distinct directory')
    with tempfile.TemporaryDirectory(prefix='cleanup-case-spelling-', dir=path.parent) as folder:
        staged = Path(folder)/'original'
        path.rename(staged)
        try:
            staged.rename(target)
            yield target
        finally:
            if target.exists():
                target.rename(staged)
            staged.rename(path)


@contextmanager
def physical_case_directory(root, name):
    """Create a case competitor, or rename its existing filesystem alias."""
    directory = root/name
    if directory.exists():
        original = next(entry for entry in directory.parent.iterdir()
                        if entry.name.casefold() == directory.name.casefold()
                        and entry.samefile(directory))
        with physical_directory_spelling(original, directory.name) as changed:
            yield changed
        return
    created = []
    parent = directory
    while not parent.exists():
        created.append(parent)
        parent = parent.parent
    directory.mkdir(parents=True)
    try:
        yield directory
    finally:
        for folder in created:
            folder.rmdir()


class PhysicalFixtureRestoration(unittest.TestCase):
    """Small real-file controls for case-preserving mutation and restoration."""

    def setUp(self):
        folder = tempfile.TemporaryDirectory(
            prefix='cleanup-fixture-restore-', dir=Path(tempfile.gettempdir()).resolve())
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)

    def test_file_case_alias_restores_original_spelling_and_bytes(self):
        path = self.root/'canonical.mojo'
        path.write_bytes(b'# original\n')
        names = {entry.name for entry in self.root.iterdir()}
        with physical_change(self.root, 'CANONICAL.mojo', b'# changed\n') as changed:
            self.assertEqual(changed.read_bytes(), b'# changed\n')
        self.assertEqual({entry.name for entry in self.root.iterdir()}, names)
        self.assertEqual(path.read_bytes(), b'# original\n')
        # A missing-file control must also restore the physical entry name.
        with physical_change(self.root, path.name, None):
            self.assertFalse(path.exists())
        self.assertEqual({entry.name for entry in self.root.iterdir()}, names)
        self.assertEqual(path.read_bytes(), b'# original\n')
        alias = self.root/'CANONICAL.mojo'
        if not alias.exists():
            # Case-sensitive filesystems can hold two distinct hardlink names.
            # Removing one must restore that exact entry, not its peer.
            alias.hardlink_to(path)
            names.add(alias.name)
            with physical_change(self.root, alias.name, None):
                self.assertFalse(alias.exists())
            self.assertEqual({entry.name for entry in self.root.iterdir()}, names)
            self.assertEqual(alias.read_bytes(), b'# original\n')
            self.assertEqual(path.read_bytes(), b'# original\n')

    def test_file_symlink_mutation_restores_without_writing_through_link(self):
        path, target = self.root/'canonical.mojo', self.root/'target.mojo'
        path.write_bytes(b'# original\n')
        target.write_bytes(b'# target\n')
        with physical_change(self.root, path.name, b'# changed\n') as changed:
            changed.unlink()
            changed.symlink_to(target)
        self.assertFalse(path.is_symlink())
        self.assertEqual(path.read_bytes(), b'# original\n')
        self.assertEqual(target.read_bytes(), b'# target\n')

    def test_directory_case_rename_refuses_and_restores_even_on_exception(self):
        directory = self.root/'math'
        directory.mkdir()
        (directory/'utils.mojo').write_bytes(b'# unchanged provider\n')
        paths = {'math/utils.mojo'}
        original_names = {path.relative_to(self.root).as_posix()
                          for path in self.root.rglob('*')}
        self.assertTrue(cleanup.resolver_unshadowed(self.root, paths))
        for fail in (False, True):
            with self.subTest(exception=fail):
                expected = (self.assertRaisesRegex(RuntimeError, '^fixture body failure$')
                            if fail else nullcontext())
                with expected:
                    with physical_directory_spelling(directory, 'MATH') as changed:
                        self.assertIn('MATH', {entry.name for entry in self.root.iterdir()})
                        self.assertNotIn('math', {entry.name for entry in self.root.iterdir()})
                        self.assertEqual((changed/'utils.mojo').read_bytes(), b'# unchanged provider\n')
                        self.assertFalse(cleanup.resolver_unshadowed(self.root, paths))
                        if fail:
                            raise RuntimeError('fixture body failure')
                self.assertEqual({path.relative_to(self.root).as_posix()
                                  for path in self.root.rglob('*')}, original_names)
                self.assertEqual((directory/'utils.mojo').read_bytes(), b'# unchanged provider\n')
                self.assertTrue(cleanup.resolver_unshadowed(self.root, paths))


class NativeDependencyInventoryBatching(unittest.TestCase):
    """Small real-file graphs exercise traversal scope without native runs."""

    def setUp(self):
        folder = tempfile.TemporaryDirectory(
            prefix='cleanup-native-closure-', dir=Path(tempfile.gettempdir()).resolve())
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
        expected = {cleanup.MIGRATION, cleanup.CONSUMER_LEDGER,
                    *cleanup.CHECKER_PATHS, *cleanup.SOURCE_PATHS}
        for group in cleanup.BOUND_GROUPS:
            expected.update(self.record[group])
        expected.update(cleanup.shared_helper_proof_bindings(self.root))
        # Supplemental authorities extend the historical receipt with their
        # own exact source and correctness-test obligations.
        station, runtime = cleanup.station, cleanup.runtime_view
        deviation = cleanup.deviation
        runtime_raw = (self.root/runtime.MIGRATION).read_bytes()
        self.assertEqual(cleanup.sha(runtime_raw), runtime.MIGRATION_SHA256)
        runtime_record = json.loads(runtime_raw)
        self.assertEqual(set(runtime_record['correctness_tests']), set(runtime.TESTS))
        # The physical Map is the deviation endpoint (#685). Its edge extends
        # the station edge, so both leaves and both test sets are bound.
        self.assertEqual(cleanup.sha((self.root/station.MODULE).read_bytes()), deviation.AFTER_SHA256)
        supplemental = {
            station.MODULE: deviation.AFTER_SHA256, **station.TESTS, **deviation.TESTS,
            runtime.MIGRATION: runtime.MIGRATION_SHA256,
            **runtime_record['correctness_tests'],
        }
        supplemental.update(cleanup.scaled_float32.AFTER_SHA256)
        supplemental.update(cleanup.scaled_float32.PACKAGE_INPUTS)
        supplemental.update(cleanup.scaled_float32.PROVIDER_INPUTS)
        supplemental.update(cleanup.scaled_float32.TESTS)
        for leaf in ('map_station_contracts.py', 'map_deviation_contracts.py',
                     'runtime_view_contracts.py', 'scaled_float32_contracts.py'):
            path = 'tools/carla_lane_oracle/' + leaf
            supplemental[path] = cleanup.DEPENDENCY_TOOL_SHA256[path]
        supplemental.update(cleanup._witness_format_bindings(self.root))
        expected.update(supplemental)
        self.assertEqual(set(bindings), expected)
        self.assertEqual({path: bindings[path] for path in supplemental}, supplemental)
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
        # The original provider mutation now meets its mandatory helper gate
        # first. A consumed, unchanged non-helper still reaches the bound-group
        # checkpoint, so neither refusal layer is lost to the composition.
        helper_inputs = (set(cleanup.shared_helpers.SOURCE_PATHS)
                         | set(cleanup.shared_helpers.PROVIDERS)
                         | set(cleanup.shared_helpers.TESTS))
        self.assertIn(name, helper_inputs)
        self.assertNotIn('extensions/carla/road.mojo', helper_inputs)
        for name, refusal, last in (
                (name, 'shared-helper fixture changed', 'B'),
                ('extensions/carla/road.mojo', 'bound input changed after consumption', 'A')):
            path = self.root/name
            original = path.read_bytes()
            self.assertIn(name, self.record['dependency_inventory'])
            self.assertIn(name, self.record['unchanged_inputs'])
            observed = []
            def consumed_then_restored(p, *args, **kwargs):
                raw = read(p, *args, **kwargs)
                if p == path:
                    caller = sys._getframe(1)
                    in_bound = (caller.f_code is cleanup.verify.__code__
                                and caller.f_locals.get('group') in cleanup.BOUND_GROUPS)
                    observed.append('A' if in_bound else 'B')
                    if not in_bound:
                        return raw+b'\n# Consumed B before bound A.\n'
                return raw
            with self.subTest(consumed=name), patch.object(Path, 'read_bytes', consumed_then_restored):
                with self.assertRaises(cleanup.ContractError) as caught:
                    cleanup.verify(self.root)
            self.assertEqual(str(caught.exception),
                             'full-audit cleanup successor: ' + refusal + ': ' + name)
            self.assertIn('B', observed)
            self.assertEqual(observed[-1], last)
            if last == 'B':
                self.assertNotIn('A', observed, 'helper refusal must precede the bound group')
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
        with tempfile.TemporaryDirectory(
                prefix='cleanup-final-resolver-', dir=Path(tempfile.gettempdir()).resolve()) as folder:
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
        with tempfile.TemporaryDirectory(
                prefix='cleanup-ancestor-', dir=Path(tempfile.gettempdir()).resolve()) as folder:
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
        with tempfile.TemporaryDirectory(
                prefix='cleanup-include-root-', dir=Path(tempfile.gettempdir()).resolve()) as folder:
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
        with tempfile.TemporaryDirectory(
                prefix='cleanup-qualified-resolver-', dir=Path(tempfile.gettempdir()).resolve()) as folder:
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
                    with self.subTest(root=str(root), case_prefix=name), physical_case_directory(root, name):
                        with self.assertRaises(cleanup.ContractError):
                            cleanup.verify(self.root, include_roots=(include,))
            # This is an allowed qualified path, not bare math in an entry dir.
            # The maintained generation-origin protocol owns staged bytes.
            with physical_change(include, 'extensions/carla/math.mojo', b'# staged instrumentation view\n'):
                cleanup.verify(self.root, include_roots=(include,))
            cleanup.verify(self.root, exact=True)

    def test_include_origin_metadata_keeps_exact_coordinates_and_source_guards(self):
        name = 'extensions/carla/math.mojo'
        origin = name + '.cov-origin'
        paths = (set(self.record['dependency_inventory']) | set(self.record['inventory'])
                 | set(self.record['native_dependency_inventory']))
        self.assertIn(name, paths)
        self.assertNotIn('tests/math.mojo', paths)
        self.assertIn('math/__init__.mojo', paths)
        self.assertNotIn('extensions/carla/math/__init__.mojo', paths)
        include_paths = paths | {path + '.cov-origin' for path in paths
                                 if path.endswith('.mojo')}
        with tempfile.TemporaryDirectory(
                prefix='cleanup-origin-include-', dir=Path(tempfile.gettempdir()).resolve()) as folder:
            include = Path(folder)
            with physical_change(include, name, (self.root/name).read_bytes()):
                # This gate checks lookup topology only. The maintained origin
                # verifier separately binds and rejects changed metadata bytes.
                with physical_change(include, origin, b'opaque origin metadata\n'):
                    self.assertFalse(cleanup.resolver_unshadowed(include, paths))
                    self.assertTrue(cleanup.resolver_unshadowed(include, include_paths))
                    cleanup.verify(self.root, exact=True, include_roots=(include,))
                target = include/origin
                target.symlink_to(include/name)
                try:
                    self.assertFalse(cleanup.resolver_unshadowed(include, include_paths))
                finally:
                    target.unlink()
                target.mkdir()
                try:
                    self.assertFalse(cleanup.resolver_unshadowed(include, include_paths))
                finally:
                    target.rmdir()
                for competitor in ('tests/math.mojo.cov-origin',
                                   'extensions/carla/Math.mojo.cov-origin',
                                   'extensions/carla/math.mojo.cov-origin.mojopkg',
                                   'math.mojo', 'math.mojopkg', 'extensions/carla/math/__init__.mojo'):
                    with self.subTest(competitor=competitor), physical_change(
                            include, competitor, b'# not an eligible origin sidecar\n'):
                        self.assertFalse(cleanup.resolver_unshadowed(include, include_paths))
                cleanup.verify(self.root, exact=True, include_roots=(include,))
            with physical_change(self.root, origin, b'not allowed in the source root\n'):
                self.assertFalse(cleanup.resolver_unshadowed(self.root, paths))
                with self.assertRaisesRegex(cleanup.ContractError, 'resolver surface'):
                    cleanup.verify(self.root, exact=True, include_roots=(include,))
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
        with tempfile.TemporaryDirectory(
                prefix='cleanup-entry-roots-', dir=Path(tempfile.gettempdir()).resolve()) as folder:
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
        with tempfile.TemporaryDirectory(
                prefix='cleanup-entry-symlink-', dir=Path(tempfile.gettempdir()).resolve()) as folder:
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
        with tempfile.TemporaryDirectory(
                prefix='cleanup-symlink-', dir=Path(tempfile.gettempdir()).resolve()) as folder:
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
            with tempfile.TemporaryDirectory(dir=Path(tempfile.gettempdir()).resolve()) as directory:
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




# The fake class is a bounded ownership/decoding preflight. It deliberately
# replaces qualification, and makes no claim about real source admission.
class CacheInputViewPreflight(unittest.TestCase):
    def setUp(self):
        from contextlib import ExitStack
        import types
        folder = tempfile.TemporaryDirectory(
            prefix='cache-input-fake-', dir=Path(tempfile.gettempdir()).resolve())
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.authority = json.loads((ROOT/cleanup.MIGRATION).read_bytes())
        self.cache_record = json.loads((ROOT/cache.MIGRATION).read_bytes())
        self.cache_record['preserved_records'] = {}
        self.cache_record['inventory'] = {}
        for name in cleanup.SOURCE_PATHS:
            target = self.root/name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT/name).read_bytes())
        authority = self.root/cleanup.MIGRATION
        authority.parent.mkdir(parents=True, exist_ok=True)
        authority.write_bytes((ROOT/cleanup.MIGRATION).read_bytes())
        self.sample = 'sample.mojo'
        (self.root/self.sample).write_bytes('# café\r\nvar label = "a\\r\\nb"\r\n'.encode('utf-8'))
        self.views = []
        self.checkpoints = []
        self.callback = lambda view, owner: None

        # _publish must see the actual current full-audit verify function in
        # full-audit globals. This is an explicitly fake qualification fixture,
        # not an assertion that an arbitrary caller can publish in production.
        def fake_verify(root, *, exact=False, include_roots=(),
                        _expected_lane_raw=None, _capture=None):
            root = Path(root)
            _capture._check_pending(root)
            snapshots = {path.relative_to(root).as_posix(): path.read_bytes()
                         for path in root.rglob('*') if path.is_file()}
            known = {name for name in snapshots if name.endswith('.mojo')}
            _capture._publish(root, snapshots, (root/MIGRATION).read_bytes(),
                              known, known, (), set(), {})
            return read_record(root)

        fake = types.FunctionType(fake_verify.__code__, vars(cleanup), 'verify')
        fake.__kwdefaults__ = fake_verify.__kwdefaults__.copy()
        self.stack.enter_context(patch.object(cleanup, 'verify', fake))
        self.stack.enter_context(patch.object(cleanup, 'read_record', return_value=self.authority))
        self.stack.enter_context(patch.object(cache, 'read_record', return_value=self.cache_record))
        self.stack.enter_context(patch.object(cache, 'reverse_exact', return_value='fake inverse'))

        checkpoint = cleanup._CacheInputs.checkpoint
        @wraps(checkpoint)
        def fake_checkpoint(view, owner, root):
            view._check(owner, root)
            self.checkpoints.append(view)
        self.stack.enter_context(patch.object(cleanup._CacheInputs, 'checkpoint', fake_checkpoint))

        inventory = cache.inventory
        @wraps(inventory)
        def fake_inventory(root, *, verified_lane_source=None,
                           _inputs=None, _input_owner=None):
            self.assertIsNotNone(_inputs)
            _inputs._check(_input_owner, root)
            self.views.append((_inputs, _input_owner))
            self.callback(_inputs, _input_owner)
            return {}
        self.stack.enter_context(patch.object(cache, 'inventory', fake_inventory))

    def run_owner(self, callback=None):
        if callback is not None:
            self.callback = callback
        return cache.verify(self.root)

    def assert_closed(self, view, owner):
        self.assertEqual(view._state, 'closed')
        self.assertFalse(view._raw)
        self.assertIsNone(view._owner_frame)
        for method, args in (
                ('raw', (self.sample,)), ('text_default', (self.sample,)),
                ('text_utf8', (self.sample,)), ('observe_bytes', (self.sample,)),
                ('known_paths', ()), ('production_paths', ()),
                ('exact_edges', ()), ('checkpoint', ())):
            with self.subTest(method=method), self.assertRaises(ValueError):
                getattr(view, method)(owner, self.root, *args)
        view.close(owner)
        self.assertEqual(view._state, 'closed')

    def test_preflight_success_releases_image_frame_and_no_result_escape(self):
        result = self.run_owner()
        self.assertEqual(result, self.cache_record)
        self.assertEqual(len(self.views), 1)
        view, owner = self.views[0]
        self.assertIn(view, self.checkpoints)
        self.assert_closed(view, owner)
        def inspect(value):
            self.assertNotIsInstance(value, cleanup._CacheInputs)
            if isinstance(value, dict):
                for key, child in value.items():
                    inspect(key)
                    inspect(child)
            elif isinstance(value, (tuple, list, set, frozenset)):
                for child in value:
                    inspect(child)
        inspect(result)
        inspect(cleanup.inventory.cache_info() if hasattr(cleanup.inventory, 'cache_info') else ())
        self.assertFalse(any(value is view for value in vars(cleanup).values()))
        self.assertFalse(any(value is view for value in vars(cache).values()))

    def test_preflight_exception_preserves_primary_and_releases_image(self):
        failure = RuntimeError('primary owned consumer failure')
        def consume(view, owner):
            raise failure
        with self.assertRaises(RuntimeError) as caught:
            self.run_owner(consume)
        self.assertIs(caught.exception, failure)
        self.assertEqual(self.checkpoints, [])
        self.assert_closed(*self.views[0])
        self.run_owner(lambda view, owner: None)
        self.assert_closed(*self.views[-1])

    def test_preflight_immutable_raw_default_newlines_and_raw_utf8_are_distinct(self):
        import io
        raw = (self.root/self.sample).read_bytes()
        expected_default = io.TextIOWrapper(io.BytesIO(raw), encoding=None, newline=None).read()
        expected_utf8 = raw.decode('utf-8')
        self.assertNotEqual(expected_default, expected_utf8)
        self.assertEqual(cleanup._physical_text(raw), raw.decode('utf-8').replace('\r\n', '\n'))
        def consume(view, owner):
            with patch.object(Path, 'read_bytes', side_effect=AssertionError('image read touched disk')):
                self.assertIs(type(view.raw(owner, self.root, self.sample)), bytes)
                self.assertEqual(view.raw(owner, self.root, self.sample), raw)
                self.assertEqual(view.text_default(owner, self.root, self.sample), expected_default)
                self.assertEqual(view.text_utf8(owner, self.root, self.sample), expected_utf8)
            with self.assertRaises(TypeError):
                view._raw[self.sample] = b'changed'
            known = view.known_paths(owner, self.root)
            production = view.production_paths(owner, self.root)
            self.assertIsInstance(known, frozenset)
            self.assertIn(self.sample, known)
            self.assertEqual(set(production), set(known))
            with self.assertRaises(ValueError):
                view.raw(owner, self.root, 'unknown.mojo')
            self.assertNotEqual(source.token_sha256('var s = "a\\r\\nb"\n'),
                                source.token_sha256('var s = "a\\nb"\n'))
        self.run_owner(consume)

    def test_preflight_default_decoder_uses_none_encoding_and_preserves_cause(self):
        import io
        real = io.TextIOWrapper
        calls = []
        def observed(*args, **kwargs):
            calls.append(kwargs.copy())
            return real(*args, **kwargs)
        def consume(view, owner):
            with patch.object(io, 'TextIOWrapper', observed):
                view.text_default(owner, self.root, self.sample)
            self.assertTrue(calls)
            self.assertIsNone(calls[-1].get('encoding'))
            self.assertIsNone(calls[-1].get('newline'))
        self.run_owner(consume)

    def test_preflight_wrong_owner_root_thread_copies_and_pending_refuse(self):
        from concurrent.futures import ThreadPoolExecutor
        def consume(view, owner):
            with self.assertRaises(ValueError):
                view.raw(object(), self.root, self.sample)
            with self.assertRaises(ValueError):
                view.raw(owner, self.root/'different', self.sample)
            with ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(view.raw, owner, self.root, self.sample)
                with self.assertRaises(ValueError):
                    future.result(timeout=10)
            for copier in (copy.copy, copy.deepcopy):
                try:
                    duplicate = copier(view)
                except (TypeError, ValueError):
                    continue
                with self.assertRaises(ValueError):
                    duplicate.raw(owner, self.root, self.sample)
            pending = cleanup._CacheInputs(owner, self.root, sys._getframe())
            with self.assertRaises(ValueError):
                pending.raw(owner, self.root, self.sample)
            pending.close(owner)
            self.assertEqual(view.raw(owner, self.root, self.sample),
                             (self.root/self.sample).read_bytes())
        self.run_owner(consume)
        with self.assertRaises(ValueError):
            cleanup._cache_lane_inputs(self.root, (self.root/LANE).read_text(), object())

    def test_preflight_nested_nearest_owner_cannot_borrow_outer_image(self):
        outer = []
        def consume(view, owner):
            if not outer:
                outer.append((view, owner))
                cache.verify(self.root)
                self.assertEqual(view.raw(owner, self.root, self.sample),
                                 (self.root/self.sample).read_bytes())
            else:
                outer_view, outer_owner = outer[0]
                self.assertIsNot(view, outer_view)
                with self.assertRaises(ValueError):
                    outer_view.raw(outer_owner, self.root, self.sample)
                with self.assertRaises(ValueError):
                    view.raw(outer_owner, self.root, self.sample)
        self.run_owner(consume)
        self.assertEqual(len(self.views), 2)
        for view, owner in self.views:
            self.assert_closed(view, owner)

    def test_preflight_retained_frame_is_inactive_after_return(self):
        frames = []
        def consume(view, owner):
            frames.append(view._owner_frame)
            self.assertEqual(frames[-1].f_code, cache.verify.__code__)
        self.run_owner(consume)
        self.assertIsNotNone(frames[0])
        self.assert_closed(*self.views[0])

    def test_preflight_factory_closes_before_and_after_publication_failure(self):
        for publication in (False, True):
            captured = []
            failure = RuntimeError('factory failed ' + str(publication))
            publish = cleanup._CacheInputs._publish
            @wraps(publish)
            def failed(view, *args, **kwargs):
                captured.append((view, view._owner))
                if publication:
                    publish(view, *args, **kwargs)
                raise failure
            # The wrapper cannot call the real publish because it deliberately
            # enforces a direct verifier frame. For post-publication failure,
            # fault the factory's predecessor construction instead.
            if publication:
                reverse = cleanup.reverse_exact
                @wraps(reverse)
                def broken_predecessor(*args, **kwargs):
                    frame = sys._getframe(1)
                    self.assertEqual(frame.f_code.co_name, '_cache_lane_inputs')
                    view = frame.f_locals['_pending']
                    self.assertEqual(view._state, 'active')
                    captured.append((view, view._owner))
                    raise failure
                context = patch.object(cleanup, 'reverse_exact', broken_predecessor)
            else:
                context = patch.object(cleanup._CacheInputs, '_publish', failed)
            with self.subTest(published=publication), context:
                with self.assertRaises(RuntimeError) as caught:
                    self.run_owner()
            self.assertIs(caught.exception, failure)
            self.assertEqual(len(captured), 1)
            self.assert_closed(*captured[0])
        self.assertEqual(self.views, [])

    def test_preflight_retained_raw_requires_builtin_bytes_before_equality(self):
        class EqualBytes(bytes):
            def __eq__(self, other):
                raise AssertionError('exotic equality must not execute')
        class EqualObject:
            def __eq__(self, other):
                raise AssertionError('foreign equality must not execute')
        def consume(view, owner):
            raw = (self.root/self.sample).read_bytes()
            for changed in (raw + b'# B\n', EqualBytes(raw), bytearray(raw), EqualObject()):
                with self.subTest(kind=type(changed).__name__), patch.object(
                        Path, 'read_bytes', return_value=changed):
                    with self.assertRaises(ValueError):
                        view.observe_bytes(owner, self.root, self.sample)
            error = PermissionError('denied current sample')
            with patch.object(Path, 'read_bytes', side_effect=error):
                with self.assertRaises(ValueError) as caught:
                    view.observe_bytes(owner, self.root, self.sample)
            self.assertIs(caught.exception.__cause__, error)
        self.run_owner(consume)

    def test_preflight_private_partial_arguments_and_public_record_freshness(self):
        import seed_count_contracts as seed
        target = self.root/seed.MIGRATION
        target.parent.mkdir(parents=True, exist_ok=True)
        original = (ROOT/seed.MIGRATION).read_bytes()
        target.write_bytes(original)
        def consume(view, owner):
            expected = seed.read_record(self.root, _inputs=view, _input_owner=owner)
            second = seed.read_record(self.root, _inputs=view, _input_owner=owner)
            self.assertEqual(expected, second)
            self.assertIsNot(expected, second)
            expected['schema'] = 999
            self.assertEqual(seed.read_record(self.root, _inputs=view, _input_owner=owner)['schema'], 1)
            expected = second
            with physical_change(self.root, seed.MIGRATION, original + b' '):
                self.assertEqual(seed.read_record(self.root, _inputs=view, _input_owner=owner), expected)
                with self.assertRaisesRegex(ValueError, 'immutable successor record changed'):
                    seed.read_record(self.root)
            for keywords in ({'_inputs': view}, {'_input_owner': owner}):
                with self.subTest(keywords=tuple(keywords)), self.assertRaises(ValueError):
                    seed.read_record(self.root, **keywords)
        self.run_owner(consume)

    def test_preflight_changed_cwd_include_context_and_decode_failures(self):
        import os
        (self.root/'invalid.mojo').write_bytes(b'# invalid UTF-8 \xff\n')
        original_cwd = Path.cwd()
        def consume(view, owner):
            import io
            with self.assertRaises(ValueError) as caught:
                view.text_utf8(owner, self.root, 'invalid.mojo')
            self.assertIsInstance(caught.exception.__cause__, UnicodeError)
            default_failure = UnicodeDecodeError('test-default', b'\xff', 0, 1, 'injected decoder error')
            with patch.object(io, 'TextIOWrapper', side_effect=default_failure):
                with self.assertRaises(ValueError) as caught:
                    view.text_default(owner, self.root, 'invalid.mojo')
            self.assertIs(caught.exception.__cause__, default_failure)
            try:
                os.chdir(self.root)
                with self.assertRaisesRegex(ValueError, 'working directory changed'):
                    view.raw(owner, self.root, self.sample)
            finally:
                os.chdir(original_cwd)
            saved = view._include_roots
            try:
                view._include_roots = (str(self.root/'alternate'),)
                with self.assertRaises(ValueError):
                    view.raw(owner, self.root, self.sample)
            finally:
                view._include_roots = saved
        self.run_owner(consume)


    def test_preflight_exact_requests_recheck_all_four_and_return_fresh_edges(self):
        def consume(view, owner):
            first = view.exact_edges(owner, self.root)
            second = view.exact_edges(owner, self.root)
            self.assertEqual(first, second)
            self.assertIsNot(first, second)
            self.assertEqual(set(first), set(cleanup.SOURCE_PATHS))
            for name in cleanup.SOURCE_PATHS:
                self.assertIsNot(first[name], second[name])
                self.assertEqual(second[name]['after_sha256'], cleanup.AFTER_SHA256[name])
            first[LANE]['after_sha256'] = 'changed returned dictionary'
            self.assertEqual(view.exact_edges(owner, self.root)[LANE]['after_sha256'],
                             cleanup.AFTER_SHA256[LANE])
        self.run_owner(consume)
        self.assertEqual(len(self.checkpoints), 4)

    def test_preflight_historical_owner_stays_lazy_and_original_io_error_survives(self):
        (self.root/LANE).write_text(self.authority['sources'][LANE]['before_source'])
        observed = []
        def historical_inventory(root, **kwargs):
            observed.append(kwargs)
            self.assertNotIn('_inputs', kwargs)
            self.assertNotIn('_input_owner', kwargs)
            return {}
        with patch.object(cache, 'inventory', historical_inventory), patch.object(
                cleanup, 'verify', side_effect=AssertionError('historical owner acquired current authority')):
            self.assertEqual(cache.verify(self.root), self.cache_record)
        self.assertEqual(len(observed), 1)
        self.assertEqual(self.views, [])
        missing = FileNotFoundError('historical lane missing')
        with patch.object(Path, 'read_text', side_effect=missing):
            with self.assertRaises(FileNotFoundError) as caught:
                cache.verify(self.root)
        self.assertIs(caught.exception, missing)


    def test_preflight_registered_and_unregistered_alias_frames_block_outer_borrow(self):
        from contextlib import ExitStack
        import importlib.util
        def consume(view, owner):
            for registered in (False, True):
                name = '_cache_input_fake_nested_alias_' + str(registered)
                spec = importlib.util.spec_from_file_location(name, cache.__file__)
                alias = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(alias)
                reached = []
                def nested_inventory(root, **kwargs):
                    reached.append(True)
                    self.assertNotIn('_inputs', kwargs)
                    with self.assertRaisesRegex(ValueError, 'cache input owner is not active'):
                        view.raw(owner, self.root, self.sample)
                    return {}
                with self.subTest(registered=registered), ExitStack() as stack:
                    if registered:
                        stack.enter_context(patch.dict(sys.modules, {name: alias}))
                    stack.enter_context(patch.object(alias, 'read_record', return_value=self.cache_record))
                    stack.enter_context(patch.object(alias, 'reverse_exact', return_value='fake historical inverse'))
                    stack.enter_context(patch.object(alias, 'inventory', nested_inventory))
                    stack.enter_context(patch.object(cleanup, 'reviewed_text',
                        return_value=self.authority['sources'][LANE]['before_source']))
                    self.assertEqual(alias.verify(self.root), self.cache_record)
                self.assertEqual(reached, [True])
                self.assertEqual(view.raw(owner, self.root, self.sample),
                                 (self.root/self.sample).read_bytes())
        self.run_owner(consume)


class CacheInputViewCurrentControls(unittest.TestCase):
    """Real current-root sampling controls; never part of fake preflight."""

    def setUp(self):
        import seed_count_contracts as seed
        self.seed = seed
        self.root = fixtures.copy_current_root(self, ROOT)
        self.record = cleanup.read_record(self.root)
        self.seed_record = seed.read_record(self.root)
        self.cache_record = cache.read_record(self.root)

    @contextmanager
    def at_inventory(self, callback, *, after=False):
        original = cache.inventory
        @wraps(original)
        def observed(root, **kwargs):
            view, owner = kwargs.get('_inputs'), kwargs.get('_input_owner')
            self.assertIsNotNone(view)
            if not after:
                callback(view, owner)
            result = original(root, **kwargs)
            if after:
                callback(view, owner)
            return result
        with patch.object(cache, 'inventory', observed):
            yield

    def test_current_one_semantic_gate_two_checkpoints_and_all_score_predicates(self):
        from contextlib import ExitStack
        calls, checkpoints, predicates = [], [], {}
        binding, checkpoint = cleanup.executing_checker_bindings, cleanup._CacheInputs.checkpoint
        @wraps(binding)
        def admitted(*args, **kwargs):
            frame = sys._getframe(1)
            if (frame.f_globals is vars(cleanup) and frame.f_code.co_name == 'verify'
                    and 'executing' not in frame.f_locals):
                calls.append({'exact': frame.f_locals['exact'],
                              '_capture': frame.f_locals['_capture']})
            return binding(*args, **kwargs)
        @wraps(checkpoint)
        def checked(view, owner, root):
            checkpoints.append(view)
            return checkpoint(view, owner, root)
        names = ('score_predecessor_source', 'frontier_predecessor_source',
                 'support_predecessor_source', 'optional_predecessor_source',
                 'verify_source', 'dependency_inventory',
                 'verify_score_caller_inventory', 'verify_premises', 'verify_score_live')
        with ExitStack() as stack:
            stack.enter_context(patch.object(cleanup, 'executing_checker_bindings', admitted))
            stack.enter_context(patch.object(cleanup._CacheInputs, 'checkpoint', checked))
            for name in names:
                predicates[name] = stack.enter_context(patch.object(
                    self.seed, name, wraps=getattr(self.seed, name)))
            result = cache.verify(self.root)
        self.assertEqual(result, self.cache_record)
        self.assertEqual(len(calls), 1)
        self.assertFalse(calls[0].get('exact', False))
        self.assertIsInstance(calls[0]['_capture'], cleanup._CacheInputs)
        self.assertEqual(len(checkpoints), 2)
        self.assertIs(checkpoints[0], checkpoints[1])
        self.assertEqual(checkpoints[0]._state, 'closed')
        for name, predicate in predicates.items():
            with self.subTest(predicate=name):
                self.assertGreater(predicate.call_count, 0)

    def test_current_capture_keeps_initial_read_two_three_and_verify_group_aba(self):
        name = 'extensions/carla/curve_interval.mojo'
        path = self.root/name
        original, read = path.read_bytes(), Path.read_bytes
        for flip_at in (2, 3):
            seen = []
            def changed(candidate, *args, **kwargs):
                raw = read(candidate, *args, **kwargs)
                if candidate == path:
                    seen.append(raw)
                    if len(seen) == flip_at:
                        return raw + b'\n# Initial capture B.\n'
                return raw
            with self.subTest(read_number=flip_at), patch.object(Path, 'read_bytes', changed):
                with self.assertRaisesRegex(ValueError, 'changed'):
                    cache.verify(self.root)
            self.assertGreaterEqual(len(seen), flip_at)
            self.assertEqual(path.read_bytes(), original)
        helper_inputs = (set(cleanup.shared_helpers.SOURCE_PATHS)
                         | set(cleanup.shared_helpers.PROVIDERS)
                         | set(cleanup.shared_helpers.TESTS))
        self.assertIn(name, helper_inputs)
        self.assertNotIn('extensions/carla/road.mojo', helper_inputs)
        for name, refusal, last in (
                (name, 'shared-helper fixture changed', 'B'),
                ('extensions/carla/road.mojo', 'bound input changed after consumption', 'A')):
            path = self.root/name
            original = path.read_bytes()
            self.assertIn(name, self.record['dependency_inventory'])
            self.assertIn(name, self.record['unchanged_inputs'])
            seen = []
            def consumed_then_restored(candidate, *args, **kwargs):
                raw = read(candidate, *args, **kwargs)
                if candidate == path:
                    caller = sys._getframe(1)
                    bound = (caller.f_code is cleanup.verify.__code__
                             and caller.f_locals.get('group') in cleanup.BOUND_GROUPS)
                    seen.append('A' if bound else 'B')
                    if not bound:
                        return raw + b'\n# Consumed B before original bound A.\n'
                return raw
            with self.subTest(consumed=name), patch.object(Path, 'read_bytes', consumed_then_restored):
                with self.assertRaises(ValueError) as caught:
                    cache.verify(self.root)
            self.assertEqual(str(caught.exception),
                             'cache-key successor: full-audit cleanup successor: '
                             + refusal + ': ' + name)
            self.assertIn('B', seen)
            self.assertEqual(seen[-1], last)
            if last == 'B':
                self.assertNotIn('A', seen, 'helper refusal must precede the bound group')
            self.assertEqual(path.read_bytes(), original)
        self.assertEqual(cache.verify(self.root), self.cache_record)

    def test_current_retained_map_each_observation_refuses_b_before_parsing(self):
        seed = self.seed
        path = self.root/seed.MODULE
        original = path.read_bytes()
        prior = seed.score_family_predecessor_source(original.decode('utf-8')).encode('utf-8')
        mutants = (('prior', prior), ('comment', original + b'\n# Retained B.\n'),
                   ('crlf', original.replace(b'\n', b'\r\n')))
        observe, read, inverse = cleanup._CacheInputs.observe_bytes, Path.read_bytes, seed.score_family_predecessor_source
        for site in (('inventory', 1), ('verify_score', 1), ('verify_score', 2), ('inventory', 2)):
            for label, changed in mutants:
                counts, injected, parsed = {}, [], []
                active = []
                @wraps(observe)
                def observed(view, owner, root, name):
                    caller = sys._getframe(1).f_code.co_name
                    if name == seed.MODULE and caller in ('inventory', 'verify_score'):
                        counts[caller] = counts.get(caller, 0) + 1
                        active.append((caller, counts[caller]))
                        try:
                            return observe(view, owner, root, name)
                        finally:
                            active.pop()
                    return observe(view, owner, root, name)
                def raw(candidate, *args, **kwargs):
                    actual = read(candidate, *args, **kwargs)
                    if candidate == path and active and active[-1] == site:
                        injected.append(site)
                        return changed
                    return actual
                @wraps(inverse)
                def parsed_map(text):
                    parsed.append(text)
                    self.assertNotEqual(text, changed.decode('utf-8'))
                    return inverse(text)
                with self.subTest(site=site, mutant=label), patch.object(
                        cleanup._CacheInputs, 'observe_bytes', observed), patch.object(
                        Path, 'read_bytes', raw), patch.object(seed, 'score_family_predecessor_source', parsed_map):
                    with self.assertRaisesRegex(ValueError, 'owned input changed: ' + seed.MODULE):
                        cache.verify(self.root)
                self.assertEqual(injected, [site])
                self.assertEqual(path.read_bytes(), original)
                self.assertTrue(all(text != changed.decode('utf-8') for text in parsed))

    def test_current_removed_reads_use_captured_a_and_keep_every_semantic_predicate(self):
        from contextlib import ExitStack
        seed = self.seed
        removed_bytes = {'read_record', 'verify_score', 'dependency_inventory', '_verify_bound_inputs', 'verify_premises'}
        removed_text = {(cache.__name__, 'inventory'), (seed.__name__, 'verify_score_caller_inventory')}
        byte_read, text_read, image_read = Path.read_bytes, Path.read_text, cleanup._CacheInputs.raw
        hooks, image_reads, semantics = [], [], {}
        expected = {name: (self.root/name).read_bytes() for name in (
            seed.MIGRATION, *seed.SCORE_TESTS, 'extensions/carla/curve_interval.mojo',
            'extensions/carla/road.mojo', 'extensions/carla/map_search.mojo',
            'extensions/carla/curve_sum2.mojo', seed.MODULE, LANE)}
        def raw(path, *args, **kwargs):
            value = byte_read(path, *args, **kwargs)
            caller = sys._getframe(1)
            if caller.f_globals is vars(seed) and caller.f_code.co_name in removed_bytes:
                hooks.append(('bytes', caller.f_code.co_name, str(path)))
                return value + b'\n# B at an intentionally eliminated read.\n'
            return value
        def text(path, *args, **kwargs):
            value = text_read(path, *args, **kwargs)
            caller = sys._getframe(1)
            if ((caller.f_globals.get('__name__'), caller.f_code.co_name) in removed_text
                    and not (caller.f_globals is vars(cache) and path == self.root/seed.MODULE)):
                hooks.append(('text', caller.f_code.co_name, str(path)))
                return value + '\n_winner_seed_update_score(_same_cache_key)\n'
            return value
        @wraps(image_read)
        def stored(view, owner, root, name):
            value = image_read(view, owner, root, name)
            image_reads.append(name)
            if name in expected:
                self.assertEqual(value, expected[name])
            return value
        with ExitStack() as stack:
            stack.enter_context(patch.object(Path, 'read_bytes', raw))
            stack.enter_context(patch.object(Path, 'read_text', text))
            stack.enter_context(patch.object(cleanup._CacheInputs, 'raw', stored))
            for name in ('checked_edits', 'verify_source', 'verify_score_live',
                         'verify_score_caller_inventory', 'verify_premises', 'score_live_observables'):
                semantics[name] = stack.enter_context(patch.object(seed, name, wraps=getattr(seed, name)))
            self.assertEqual(cache.verify(self.root), self.cache_record)
        self.assertEqual(hooks, [], 'removed hooks must be absent, not counted as refusal successes')
        self.assertTrue(set(expected) <= set(image_reads))
        for name, predicate in semantics.items():
            with self.subTest(predicate=name):
                self.assertGreater(predicate.call_count, 0)

    def test_current_removed_categories_pair_initial_and_final_persistent_b(self):
        seed = self.seed
        cases = (
            ('cache-production', 'extensions/carla/road.mojo'),
            ('seed-record', seed.MIGRATION),
            ('seed-fixture', next(iter(seed.SCORE_TESTS))),
            ('seed-historical', next(iter(self.seed_record['historical_records']))),
            ('seed-graph-and-support', 'extensions/carla/curve_interval.mojo'),
            ('seed-optional-premise', 'extensions/carla/map_search.mojo'),
        )
        for category, name in cases:
            original = (self.root/name).read_bytes()
            changed = original + b'\n# Persistent B for ' + category.encode() + b'.\n'
            with self.subTest(category=category, phase='initial'), physical_change(self.root, name, changed):
                with self.assertRaises(ValueError):
                    cache.verify(self.root)
            injections = []
            def mutate(view, owner):
                injections.append(name)
                (self.root/name).write_bytes(changed)
            try:
                with self.subTest(category=category, phase='owner-final'), self.at_inventory(mutate, after=True):
                    with self.assertRaisesRegex(ValueError, 'owned input changed: ' + name):
                        cache.verify(self.root)
                self.assertEqual(injections, [name])
            finally:
                (self.root/name).write_bytes(original)

    def test_current_second_gate_views_removed_first_views_and_final_bytes_retained(self):
        read = Path.read_text
        calls, injected = [], []
        def late_only(path, *args, **kwargs):
            value = read(path, *args, **kwargs)
            caller = sys._getframe(1)
            if caller.f_globals is vars(cleanup) and caller.f_code.co_name == 'verify' and path == self.root/CURVE:
                calls.append(path)
                if len(calls) == 2:
                    injected.append(path)
                    return value + '\nunreviewed_second_gate_operation()\n'
            return value
        with patch.object(Path, 'read_text', late_only):
            self.assertEqual(cache.verify(self.root), self.cache_record)
        self.assertEqual(calls, [self.root/CURVE])
        self.assertEqual(injected, [], 'the old second supplied-view hook is intentionally absent')
        first = []
        def initial_bad(path, *args, **kwargs):
            value = read(path, *args, **kwargs)
            caller = sys._getframe(1)
            if caller.f_globals is vars(cleanup) and caller.f_code.co_name == 'verify' and path == self.root/CURVE:
                first.append(path)
                return value + '\nunreviewed_first_gate_operation()\n'
            return value
        with patch.object(Path, 'read_text', initial_bad):
            with self.assertRaisesRegex(ValueError, 'supplied and physical source views differ'):
                cache.verify(self.root)
        self.assertEqual(first, [self.root/CURVE])
        original = (self.root/CURVE).read_bytes()
        changed = []
        def physical_b(view, owner):
            changed.append(True)
            (self.root/CURVE).write_bytes(original + b'\n# Late endpoint B.\n')
        try:
            with self.at_inventory(physical_b, after=True):
                with self.assertRaisesRegex(ValueError, 'owned input changed: ' + CURVE):
                    cache.verify(self.root)
            self.assertEqual(changed, [True])
        finally:
            (self.root/CURVE).write_bytes(original)

    def test_current_map_supplied_comments_allowed_semantics_refuse_before_projection(self):
        seed, read = self.seed, Path.read_text
        original = (self.root/seed.MODULE).read_bytes()
        for semantic in (False, True):
            observed, inverse_inputs = [], []
            def supplied(path, *args, **kwargs):
                value = read(path, *args, **kwargs)
                caller = sys._getframe(1)
                if path == self.root/seed.MODULE and caller.f_globals is vars(cache) and caller.f_code.co_name == 'inventory':
                    observed.append(path)
                    return value + ('\nunreviewed_map_operation()\n' if semantic else '\n# Supplied café comment.\n')
                return value
            inverse = seed.score_family_predecessor_source
            @wraps(inverse)
            def projected(text):
                inverse_inputs.append(text)
                self.assertNotIn('unreviewed_map_operation()', text)
                return inverse(text)
            with self.subTest(semantic=semantic), patch.object(Path, 'read_text', supplied), patch.object(seed, 'score_family_predecessor_source', projected):
                if semantic:
                    with self.assertRaisesRegex(ValueError, 'unreviewed supplied score-helper source'):
                        cache.verify(self.root)
                    self.assertEqual(inverse_inputs, [])
                else:
                    self.assertEqual(cache.verify(self.root), self.cache_record)
                    self.assertTrue(inverse_inputs)
            self.assertEqual(observed, [self.root/seed.MODULE])
            self.assertEqual((self.root/seed.MODULE).read_bytes(), original)

    def test_current_exact_condition_stays_at_seed_boundary_and_all_four_endpoints(self):
        from contextlib import ExitStack
        edges = cleanup._CacheInputs.exact_edges
        raw = {name: (self.root/name).read_bytes() for name in cleanup.SOURCE_PATHS}
        for changed_paths, expected_calls in tuple(((name,), 1) for name in cleanup.SOURCE_PATHS) + ((tuple(cleanup.SOURCE_PATHS), 0),):
            calls, semantic_completed = [], []
            @wraps(edges)
            def exact(view, owner, root):
                calls.append(view)
                return edges(view, owner, root)
            def admitted(view, owner):
                semantic_completed.append(view)
                self.assertEqual(view._state, 'active')
            with self.subTest(changed_paths=changed_paths), ExitStack() as stack:
                for name in changed_paths:
                    stack.enter_context(physical_change(self.root, name, b'# Stable token-only endpoint.\n' + raw[name]))
                stack.enter_context(patch.object(cleanup._CacheInputs, 'exact_edges', exact))
                stack.enter_context(self.at_inventory(admitted))
                message = ('unreviewed complete live endpoint' if expected_calls else
                           'historical record, live dependency or regression fixture changed')
                with self.assertRaisesRegex(ValueError, message):
                    cache.verify(self.root)
                self.assertEqual(len(calls), expected_calls)
                self.assertEqual(len(semantic_completed), 1, 'first admission must remain semantic')
        # A single exact captured source is sufficient to trigger all four
        # exact assertions; three other comment-compatible variants must fail.
        for exact_path in (CURVE, LANE, VALUE):
            calls = []
            @wraps(edges)
            def exact(view, owner, root):
                calls.append(view)
                return edges(view, owner, root)
            with self.subTest(single_exact=exact_path), ExitStack() as stack:
                for name in cleanup.SOURCE_PATHS:
                    if name != exact_path:
                        stack.enter_context(physical_change(self.root, name, b'# Token-compatible.\n' + raw[name]))
                stack.enter_context(patch.object(cleanup._CacheInputs, 'exact_edges', exact))
                with self.assertRaisesRegex(ValueError, 'unreviewed complete live endpoint'):
                    cache.verify(self.root)
            self.assertEqual(len(calls), 1)

    def test_current_fresh_seed_lookup_uses_separate_modules_and_none_entries(self):
        seed = self.seed
        self.assertIsNot(seed.cache_key, cleanup._sibling('cache_key'))
        self.assertIsNot(seed.affected, cleanup._sibling('affected'))
        discover, parse, resolve = seed.cache_key.input_paths, seed.affected.imported_names, seed.affected.resolve
        found, texts, resolved = [], [], []
        def discovery(root, *args, **kwargs):
            values = list(discover(root, *args, **kwargs))
            found.append((root, values))
            return values
        def parsed(text):
            texts.append(text)
            return parse(text)
        def resolution(*args, **kwargs):
            self.assertEqual(len(args), 3)
            self.assertNotIn('entries', kwargs)
            resolved.append((args[1], frozenset(args[2])))
            return resolve(*args, **kwargs)
        with patch.object(seed.cache_key, 'input_paths', discovery), patch.object(
                seed.affected, 'imported_names', parsed), patch.object(seed.affected, 'resolve', resolution):
            self.assertEqual(cache.verify(self.root), self.cache_record)
        self.assertEqual(len(found), 1)
        # The reviewed XML helper imports one additional UTF-8 provider. Bind
        # the exact parser inputs instead of merely increasing a call count.
        xml, utf8 = 'loaders/xml.mojo', 'loaders/utf8.mojo'
        self.assertEqual(cleanup.sha((self.root/xml).read_bytes()),
                         cleanup.shared_helpers.AFTER_SHA256[xml])
        expected_paths = {seed.MODULE, *self.seed_record['unchanged_inputs'], utf8}
        self.assertNotIn(utf8, self.seed_record['unchanged_inputs'])
        expected_texts = [(self.root/name).read_bytes().decode('utf-8')
                          for name in sorted(expected_paths)]
        self.assertCountEqual(texts, expected_texts)
        self.assertIn((self.root/utf8).read_bytes().decode('utf-8'), texts)
        self.assertTrue(resolved)
        expected_known = frozenset(path.as_posix() for path in found[0][1] if path.suffix == '.mojo')
        self.assertTrue(all(known == expected_known for _, known in resolved))
        changed, parsed_after_change = [], []
        def different_known(root):
            values = list(discover(root))
            changed.append(True)
            return values + [Path('never-captured-negative.mojo')]
        def forbidden_parse(text):
            parsed_after_change.append(text)
            return parse(text)
        with patch.object(seed.cache_key, 'input_paths', different_known), patch.object(
                seed.affected, 'imported_names', forbidden_parse):
            with self.assertRaisesRegex(ValueError, 'owned dependency input paths changed'):
                cache.verify(self.root)
        self.assertEqual(changed, [True])
        self.assertEqual(parsed_after_change, [], 'changed known set must refuse before graph parsing')

    def test_current_production_entries_native_parents_and_seed_fallback_remain_separate(self):
        seed = self.seed
        production, native, seed_calls = [], [], []
        dependency, resolve = cleanup.dependency_inventory, seed.affected.resolve
        @wraps(dependency)
        def observed(root, **kwargs):
            calls = native if kwargs.get('roots') == tuple(reversed(cleanup.NATIVE_WITNESSES)) else production
            calls.append(kwargs.copy())
            return dependency(root, **kwargs)
        def fallback(*args, **kwargs):
            seed_calls.append((args, kwargs.copy()))
            return resolve(*args, **kwargs)
        with patch.object(cleanup, 'dependency_inventory', observed), patch.object(seed.affected, 'resolve', fallback):
            cache.verify(self.root)
        self.assertTrue(production)
        production_call = next(call for call in production if tuple(call['roots'])[:4] == cleanup.SOURCE_PATHS)
        self.assertEqual(tuple(production_call['entries']), tuple(self.record['entry_directories']))
        all_calls = production + native
        witness_calls = [call for call in all_calls if set(call['roots']) <= set(cleanup.NATIVE_WITNESSES)]
        self.assertTrue(witness_calls)
        for call in witness_calls:
            parents = {str(Path(name).parent) for name in call['roots']}
            self.assertEqual(len(parents), 1)
            self.assertEqual(set(call['entries']), parents)
        self.assertTrue(seed_calls)
        self.assertTrue(all(len(args) == 3 and 'entries' not in kwargs for args, kwargs in seed_calls))
        # Independently requested include contexts must perform fresh checks.
        with tempfile.TemporaryDirectory(
                prefix='cache-input-include-', dir=Path(tempfile.gettempdir()).resolve()) as directory:
            include = Path(directory)
            (include/'std.mojopkg').write_bytes(b'include-root competitor')
            attempted = []
            def independent(view, owner):
                attempted.append(True)
                with self.assertRaisesRegex(ValueError, 'resolver surface'):
                    cleanup.verify(self.root, include_roots=(include,))
            with self.at_inventory(independent):
                cache.verify(self.root)
            self.assertEqual(attempted, [True])

    def test_current_source_record_new_negative_missing_and_resolver_final_refuse(self):
        from contextlib import ExitStack
        cases = (
            ('source', 'extensions/carla/road.mojo', 'owned input changed'),
            ('authority', cleanup.MIGRATION, 'record changed|owned input changed'),
            ('new-negative-production', 'new_negative_namespace/quiet.mojo', 'path inventory changed'),
            ('missing-input', 'extensions/carla/curve_interval.mojo', 'regular|unreadable|missing'),
            ('resolver', 'std.mojopkg', 'resolver surface'),
        )
        for kind, name, message in cases:
            changes, finished_edges = [], []
            exact = cleanup._CacheInputs.exact_edges
            @wraps(exact)
            def edge(view, owner, root):
                value = exact(view, owner, root)
                finished_edges.append(True)
                return value
            with self.subTest(kind=kind), ExitStack() as stack:
                def change(view, owner):
                    self.assertEqual(finished_edges, [True])
                    previous = (self.root/name).read_bytes() if (self.root/name).exists() else b''
                    changed = None if kind == 'missing-input' else previous + b'\n# Owner-final B.\n'
                    stack.enter_context(physical_change(self.root, name, changed))
                    changes.append(kind)
                stack.enter_context(patch.object(cleanup._CacheInputs, 'exact_edges', edge))
                stack.enter_context(self.at_inventory(change, after=True))
                with self.assertRaisesRegex(ValueError, message):
                    cache.verify(self.root)
                self.assertEqual(changes, [kind])

    def test_current_checker_final_uses_original_baseline(self):
        from contextlib import ExitStack
        finished, baselines = [], []
        with ExitStack() as stack:
            def mutate(view, owner):
                baselines.append(dict(view._executing))
                self.assertTrue(baselines[-1])
                # This is an actual executing helper replacement, not a new
                # post-mutation baseline supplied to the owned checkpoint.
                stack.enter_context(patch.object(cleanup, '_physical_text', lambda raw: raw.decode('utf-8')))
                finished.append(True)
            stack.enter_context(self.at_inventory(mutate, after=True))
            with self.assertRaisesRegex(ValueError, 'executing function changed|executing checker changed'):
                cache.verify(self.root)
            self.assertEqual(finished, [True])
            self.assertEqual(len(baselines), 1)

    def test_current_equal_byte_leaf_and_ancestor_aliases_fail_final_regular_checks(self):
        for kind in ('leaf', 'ancestor'):
            original = self.root/LANE if kind == 'leaf' else self.root/'extensions'
            saved = original.with_name(original.name + '.owned-original')
            hooked = []
            def alias(view, owner):
                original.rename(saved)
                original.symlink_to(saved, target_is_directory=kind == 'ancestor')
                hooked.append(kind)
            try:
                with self.subTest(kind=kind), self.at_inventory(alias, after=True):
                    with self.assertRaisesRegex(ValueError, 'symbolic|symlink|regular'):
                        cache.verify(self.root)
                self.assertEqual(hooked, [kind])
            finally:
                if original.is_symlink():
                    original.unlink()
                if saved.exists():
                    saved.rename(original)

    def test_current_public_helpers_stay_fresh_while_owned_view_is_active(self):
        seed, direct = self.seed, []
        def public(view, owner):
            # A private image read remains A while a direct public read sees B.
            name = seed.MIGRATION
            original = (self.root/name).read_bytes()
            expected = seed.read_record(self.root, _inputs=view, _input_owner=owner)
            with physical_change(self.root, name, original + b' '):
                self.assertEqual(seed.read_record(self.root, _inputs=view, _input_owner=owner), expected)
                with self.assertRaisesRegex(ValueError, 'immutable successor record changed'):
                    seed.read_record(self.root)
                with self.assertRaises(ValueError):
                    seed.verify_score(self.root)
                with self.assertRaises(ValueError):
                    cleanup.verified_edges(self.root)
            direct.append(True)
        with self.at_inventory(public):
            self.assertEqual(cache.verify(self.root), self.cache_record)
        self.assertEqual(direct, [True])

    def test_current_consecutive_roots_and_relative_root_interpretation_are_fresh(self):
        import os
        other = fixtures.copy_current_root(self, ROOT)
        calls = []
        checkpoint = cleanup._CacheInputs.checkpoint
        @wraps(checkpoint)
        def checked(view, owner, root):
            calls.append((view, str(Path(root).absolute())))
            return checkpoint(view, owner, root)
        with patch.object(cleanup._CacheInputs, 'checkpoint', checked):
            cache.verify(self.root)
            cache.verify(other)
            cache.verify(self.root)
        self.assertEqual(len({id(view) for view, _ in calls}), 3)
        self.assertEqual([root for _, root in calls[::2]], [str(self.root), str(other), str(self.root)])
        cwd = Path.cwd()
        try:
            os.chdir(self.root.parent)
            self.assertEqual(cache.verify(Path(self.root.name)), self.cache_record)
        finally:
            os.chdir(cwd)

    def test_current_capture_sink_cannot_be_supplied_by_arbitrary_callers(self):
        pending = cleanup._CacheInputs(object(), self.root, sys._getframe())
        owner = pending._owner
        for kwargs in ({'_capture': pending}, {'_capture': pending, 'exact': True},
                       {'_capture': pending, 'include_roots': (self.root,)}):
            with self.subTest(kwargs=tuple(kwargs)), self.assertRaises(ValueError):
                cleanup.verify(self.root, **kwargs)
            self.assertEqual(pending._state, 'pending')
            self.assertFalse(pending._raw)
        with self.assertRaises(ValueError):
            cleanup._cache_lane_inputs(self.root, (self.root/LANE).read_text(), object())
        pending.close(owner)
        self.assertEqual(cleanup.verify(self.root, exact=True), self.record)

    def test_current_dynamic_negative_paths_and_non_ascii_census_use_complete_image(self):
        from contextlib import ExitStack
        seed = self.seed
        names = ('owned_negative_namespace/__init__.mojo',
                 'owned_negative_namespace/nested_alpha/quiet.mojo',
                 'owned_negative_namespace/tools/quiet.mojo')
        a = '# café: negative production input\r\n'.encode('utf-8')
        import io
        default_a = io.TextIOWrapper(io.BytesIO(a), encoding=None, newline=None).read()
        read, hooks, seen = Path.read_text, [], []
        def eliminated(path, *args, **kwargs):
            value = read(path, *args, **kwargs)
            caller = sys._getframe(1)
            if (path.is_relative_to(self.root) and path.relative_to(self.root).as_posix() in names
                    and (caller.f_globals is vars(cache) or caller.f_globals is vars(seed))):
                hooks.append(path)
                return value + '\n_winner_seed_update_score(_same_cache_key)\n'
            return value
        def check(view, owner):
            known = view.known_paths(owner, self.root)
            production = view.production_paths(owner, self.root)
            for name in names:
                self.assertIn(name, known)
                self.assertIn(name, production)
                self.assertEqual(view.raw(owner, self.root, name), a)
                self.assertEqual(view.text_default(owner, self.root, name), default_a)
            seen.append(True)
        with ExitStack() as stack:
            for name in names:
                stack.enter_context(physical_change(self.root, name, a))
            stack.enter_context(patch.object(Path, 'read_text', eliminated))
            stack.enter_context(self.at_inventory(check))
            self.assertEqual(cache.verify(self.root), self.cache_record)
        self.assertEqual(seen, [True])
        self.assertEqual(hooks, [], 'negative files still consume captured A, not a removed supplied view')
        b = a + b'\n_winner_seed_update_score()\n'
        with physical_change(self.root, names[0], b):
            with self.assertRaisesRegex(ValueError, 'caller inventory'):
                cache.verify(self.root)
        with physical_change(self.root, names[0], a):
            touched = []
            def late(view, owner):
                touched.append(True)
                (self.root/names[0]).write_bytes(b)
            with self.at_inventory(late, after=True):
                with self.assertRaisesRegex(ValueError, 'owned input changed'):
                    cache.verify(self.root)
            self.assertEqual(touched, [True])

        # The immutable resolver union protects tests, not tools. Both are
        # production census inputs; admitted tools is covered above, while the
        # recorded tests namespace must still refuse before publication.
        resolver_paths = (set(self.record['dependency_inventory'])
                          | set(self.record['inventory'])
                          | set(self.record['native_dependency_inventory']))
        protected_names = {Path(path).parts[0].casefold() for path in resolver_paths} | {'std'}
        self.assertIn('tests', protected_names)
        self.assertNotIn('tools', protected_names)
        for protected in ('tests',):
            name = 'owned_negative_namespace/' + protected + '/quiet.mojo'
            created, resolver_results, published = [], [], []
            initialize = cleanup._CacheInputs.__init__
            resolver = cleanup.resolver_unshadowed
            publish = cleanup._CacheInputs._publish
            @wraps(initialize)
            def initialized(view, *args, **kwargs):
                initialize(view, *args, **kwargs)
                created.append(view)
            @wraps(resolver)
            def checked(root, paths):
                result = resolver(root, paths)
                frame = sys._getframe(1)
                if (root == self.root and frame.f_globals is vars(cleanup)
                        and frame.f_code.co_name == 'verify'):
                    pending = frame.f_locals['_capture']
                    self.assertIsNotNone(pending)
                    resolver_results.append((result, pending._state))
                return result
            @wraps(publish)
            def publication(view, *args, **kwargs):
                published.append(view)
                self.fail('protected nested namespace must refuse before publication')
            with self.subTest(protected_namespace=protected), physical_change(self.root, name, a):
                production = {path.relative_to(self.root).as_posix()
                              for path in guard.production_mojo_paths(self.root)}
                known = {path.as_posix() for path in seed.cache_key.input_paths(self.root)
                         if path.suffix == '.mojo'}
                self.assertIn(name, production)
                self.assertIn(name, known)
                with patch.object(cleanup._CacheInputs, '__init__', initialized), patch.object(
                        cleanup, 'resolver_unshadowed', checked), patch.object(
                        cleanup._CacheInputs, '_publish', publication):
                    with self.assertRaisesRegex(ValueError,
                            'unreviewed alternate, compiled, package, symlink or std resolver surface'):
                        cache.verify(self.root)
                self.assertEqual(resolver_results, [(False, 'pending')])
                self.assertEqual(published, [])
                self.assertEqual(len(created), 1)
                self.assertEqual(created[0]._state, 'closed')
                self.assertFalse(created[0]._raw)
                self.assertIsNone(created[0]._owner_frame)

    def test_current_importlib_alias_stays_fresh_and_never_issues_owned_view(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('_cache_input_public_alias_control', cache.__file__)
        alias = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(alias)
        calls, inventories = [], []
        binding, inventory = cleanup.executing_checker_bindings, alias.inventory
        @wraps(binding)
        def observed(*args, **kwargs):
            frame = sys._getframe(1)
            if (frame.f_globals is vars(cleanup) and frame.f_code.co_name == 'verify'
                    and 'executing' not in frame.f_locals):
                calls.append((frame.f_locals['exact'], frame.f_locals['_capture']))
            return binding(*args, **kwargs)
        @wraps(inventory)
        def default_inventory(*args, **kwargs):
            inventories.append(kwargs.copy())
            self.assertNotIn('_inputs', kwargs)
            self.assertNotIn('_input_owner', kwargs)
            return inventory(*args, **kwargs)
        factory = cleanup._cache_lane_inputs
        @wraps(factory)
        def forbidden_factory(*args, **kwargs):
            self.fail('an unrecognized alias must choose the fresh public path before factory issuance')
        with patch.object(cleanup, 'executing_checker_bindings', observed), patch.object(
                alias, 'inventory', default_inventory), patch.object(cleanup, '_cache_lane_inputs', forbidden_factory):
            self.assertEqual(alias.verify(self.root), self.cache_record)
        self.assertEqual(calls, [(False, None), (True, None)])
        self.assertEqual(len(inventories), 1)

    def test_current_image_covers_all_104_fixed_paths_and_complete_lookup_context(self):
        seed = self.seed
        required = {cache.MIGRATION, cache.MODULE, seed.MIGRATION, seed.MODULE, *seed.SCORE_TESTS}
        required.update('tools/carla_lane_oracle/' + name for name in self.cache_record['preserved_records'])
        for group in ('historical_records', 'unchanged_inputs', 'unchanged_correctness_tests', 'after_correctness_tests'):
            required.update(self.seed_record[group])
        required.update(self.seed_record['layout_routing'])
        required.update(item['path'] for item in self.seed_record['premise_declarations'])
        required.update(item[0] for item in (*seed.OPTIONAL_EXTRA_PREMISES, *seed.SUPPORT_EXTRA_PREMISES))
        self.assertEqual(len(required), 104)
        expected = {name: (self.root/name).read_bytes() for name in required}
        checked = []
        def complete(view, owner):
            self.assertTrue(required <= set(view._raw))
            self.assertEqual({name: view.raw(owner, self.root, name) for name in required}, expected)
            self.assertEqual(view.known_paths(owner, self.root), frozenset(
                path.as_posix() for path in seed.cache_key.input_paths(self.root) if path.suffix == '.mojo'))
            self.assertEqual(view.production_paths(owner, self.root), frozenset(
                path.relative_to(self.root).as_posix() for path in guard.production_mojo_paths(self.root)))
            self.assertEqual(view._entries, tuple(self.record['entry_directories']))
            self.assertEqual(view._native_contexts,
                             tuple((name, (str(Path(name).parent),)) for name in cleanup.NATIVE_WITNESSES))
            self.assertEqual(view._include_roots, ())
            self.assertEqual(view._root, str(self.root.absolute()))
            checked.append(True)
        with self.at_inventory(complete):
            self.assertEqual(cache.verify(self.root), self.cache_record)
        self.assertEqual(checked, [True])

    def test_current_standalone_cache_inventory_still_reads_supplied_non_map_text(self):
        original = cache.inventory
        read, hooks, comparisons = Path.read_text, [], []
        name = 'extensions/carla/road.mojo'
        predecessor = cleanup.reverse_exact(LANE, self.record['sources'][LANE]['after_source'],
                                            self.record['sources'][LANE])
        def fresh(view, owner):
            def supplied(path, *args, **kwargs):
                value = read(path, *args, **kwargs)
                caller = sys._getframe(1)
                if path == self.root/name and caller.f_globals is vars(cache) and caller.f_code.co_name == 'inventory':
                    hooks.append(path)
                    return value + '\n_same_cache_key()\n'
                return value
            with patch.object(Path, 'read_text', supplied):
                result = original(self.root, verified_lane_source=predecessor)
            self.assertIn(name, result)
            self.assertNotEqual(result, self.cache_record['inventory'])
            comparisons.append(True)
        with self.at_inventory(fresh):
            self.assertEqual(cache.verify(self.root), self.cache_record)
        self.assertEqual(comparisons, [True])
        self.assertEqual(hooks, [self.root/name])

    def test_current_owned_map_io_failure_preserves_cause_and_single_prefix(self):
        read = Path.read_text
        failure = PermissionError('retained Map supplied view unreadable')
        hooks = []
        def denied(path, *args, **kwargs):
            caller = sys._getframe(1)
            if path == self.root/self.seed.MODULE and caller.f_globals is vars(cache) and caller.f_code.co_name == 'inventory':
                hooks.append(path)
                raise failure
            return read(path, *args, **kwargs)
        with patch.object(Path, 'read_text', denied):
            with self.assertRaisesRegex(ValueError, 'unreadable owned Map view') as caught:
                cache.verify(self.root)
        self.assertEqual(hooks, [self.root/self.seed.MODULE])
        self.assertIs(caught.exception.__cause__, failure)
        self.assertEqual(str(caught.exception).count('cache-key successor:'), 1)

    def test_current_retained_map_exotic_values_fail_before_equality_or_parser(self):
        class EqualBytes(bytes):
            def __eq__(self, other):
                raise AssertionError('retained exotic bytes equality must not execute')
        class EqualObject:
            def __eq__(self, other):
                raise AssertionError('retained foreign equality must not execute')
        seed = self.seed
        path = self.root/seed.MODULE
        original = path.read_bytes()
        observe, read, inverse = cleanup._CacheInputs.observe_bytes, Path.read_bytes, seed.score_family_predecessor_source
        for site in (('inventory', 1), ('verify_score', 1), ('verify_score', 2), ('inventory', 2)):
            for changed in (EqualBytes(original), bytearray(original), EqualObject()):
                counts, injected, active, parsed = {}, [], [], []
                @wraps(observe)
                def observed(view, owner, root, name):
                    caller = sys._getframe(1).f_code.co_name
                    if name == seed.MODULE and caller in ('inventory', 'verify_score'):
                        counts[caller] = counts.get(caller, 0) + 1
                        active.append((caller, counts[caller]))
                        try:
                            return observe(view, owner, root, name)
                        finally:
                            active.pop()
                    return observe(view, owner, root, name)
                def raw(candidate, *args, **kwargs):
                    actual = read(candidate, *args, **kwargs)
                    if candidate == path and active and active[-1] == site:
                        injected.append((site, len(parsed)))
                        return changed
                    return actual
                @wraps(inverse)
                def parsed_map(text):
                    self.assertFalse(injected, 'no parser may run after a retained exotic value')
                    parsed.append(text)
                    return inverse(text)
                with self.subTest(site=site, kind=type(changed).__name__), patch.object(
                        cleanup._CacheInputs, 'observe_bytes', observed), patch.object(
                        Path, 'read_bytes', raw), patch.object(seed, 'score_family_predecessor_source', parsed_map):
                    with self.assertRaisesRegex(ValueError, 'owned input changed: ' + seed.MODULE):
                        cache.verify(self.root)
                self.assertEqual(len(injected), 1)
                self.assertEqual(injected[0], (site, len(parsed)))
                self.assertEqual(path.read_bytes(), original)

if __name__ == '__main__':
    unittest.main()
