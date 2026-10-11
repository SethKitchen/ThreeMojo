#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Private-adapter AST and synthetic observation wiring controls.

The Fake classes use tiny physical files and synthetic owner validation. They
prove adapter forwarding, observation placement, and public/private parity;
they do not establish real immutable-image admission or owner lifecycle safety.
The existing real-gate suites remain mandatory. No gate runs at import time.
"""
import ast
from collections import Counter
from contextlib import contextmanager
import copy
import hashlib
import inspect
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import accepted_successor_contracts as accepted
import coverage_followup_contracts as followup
import coverage_invariant_contracts as invariant
import full_audit_cleanup_contracts as cleanup
import rounded_line_selector_contracts as selector
import source_contracts as source
import sum2_guard_contracts as guard
import test_paired_pin_contracts as paired_helpers

LANE = 'extensions/carla/lane_refinement.mojo'
ROAD = 'extensions/carla/road.mojo'
# These are the complete unchanged v17 public functions, not new private hashes.
FROZEN_SELECTOR_AST = '9b5e8585b655328d7d8e33c0c81a8df14aea31e386184b98390d5b12b40ee17c'
FROZEN_PAIR_AST = '0d8a776fbcb25b7f89d6ca08e293bc3776e31794989fe2b3fc989ce7b3eb1a59'
SELECTOR_PLUMBING = (
    "full_audit._observe_text(root, item['path'], (root / item['path']).read_text(), _operation=_operation)",
    "full_audit._observe_text(root, item['path'], (root / item['path']).read_text(), _operation=_operation)",
    'full_audit._observe_text(root, name, (root / name).read_text(), _operation=_operation)',
    'full_audit._observe_text(root, name, (root / name).read_text(), _operation=_operation)',
    'full_audit._observe_text(root, path, (root / path).read_text(), _operation=_operation)',
    'full_audit._observe_bytes(root, name, physical.read_bytes(), _operation=_operation)',
    'full_audit._observe_bytes(root, name, full_audit._regular(root, name).read_bytes(), _operation=_operation)',
    "full_audit._observe_text(root, name, physical.read_text(), _operation=_operation, mode='physical', supplied=True, _checked_raw=raw)",
    '_lane_observation(root, **operation_args)', '_lane_observation(root, **operation_args)',
    'full_audit._reviewed_lane_observation(root, text, observed_raw, **operation_args)',
    'full_audit._reviewed_lane_observation(root, text, observed_raw, **operation_args)',
)
PAIR_PLUMBING = (
    '_verify_current_for_pin_pair(root, _operation=_operation)',
    '_read_current_pair_pin(root, runtime_name, _operation=_operation)',
    '_read_current_pair_pin(root, guard_name, _operation=_operation)',
    '_read_current_pair_pin(root, filename, _operation=_operation)',
)


def function_ast(module, name):
    tree = ast.parse(Path(module.__file__).read_text())
    return next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == name)


def ast_key(node):
    return ast.dump(node, include_attributes=False)


class PrivateCloneProjection(ast.NodeTransformer):
    """Remove only enumerated operation plumbing; retain all proof semantics."""
    def __init__(self, kind):
        self.kind = kind
        self.calls = []
        self.removed = Counter()
        check = ('full_audit._operation_check(_operation, root)' if kind == 'selector'
                 else '_check_operation(root, _operation)')
        self.entry = ast_key(ast.parse('if _operation is not None:\n    ' + check).body[0])
        self.fallback = ast_key(ast.parse('if _operation is None:\n    return predecessor_pin_pair(root)').body[0])
        self.arguments = ast_key(ast.parse("operation_args = {} if _operation is None else {'_operation': _operation}").body[0])

    def visit_If(self, node):
        if ast_key(node) == self.entry:
            self.removed['entry'] += 1
            return None
        if self.kind == 'pair' and ast_key(node) == self.fallback:
            self.removed['fallback'] += 1
            return None
        return self.generic_visit(node)

    def visit_Assign(self, node):
        if self.kind == 'selector' and ast_key(node) == self.arguments:
            self.removed['arguments'] += 1
            return None
        return self.generic_visit(node)

    def visit_Call(self, node):
        relevant = any(keyword.arg == '_operation' or (
            keyword.arg is None and isinstance(keyword.value, ast.Name)
            and keyword.value.id == 'operation_args') for keyword in node.keywords)
        if relevant:
            self.calls.append(ast.unparse(node))
        node = self.generic_visit(node)
        if relevant:
            if isinstance(node.func, ast.Attribute) and node.func.attr in ('_observe_text', '_observe_bytes'):
                return node.args[2]
            node.keywords = [keyword for keyword in node.keywords if keyword.arg != '_operation'
                            and not (keyword.arg is None and isinstance(keyword.value, ast.Name)
                                     and keyword.value.id == 'operation_args')]
        return node


class OperationAdapterAstControls(unittest.TestCase):
    """Frozen public contracts and narrow, fail-on-drift private-copy controls."""
    def assert_clone(self, kind, private=None):
        module, name = ((selector, 'verify_premises') if kind == 'selector'
                        else (accepted, 'predecessor_pin_pair'))
        original = function_ast(module, name)
        private = copy.deepcopy(private if private is not None else function_ast(module, '_' + name))
        self.assertEqual(private.name, '_' + name)
        self.assertEqual(private.args.kwonlyargs[-1].arg, '_operation')
        self.assertEqual(ast_key(private.args.kw_defaults[-1]), 'Constant(value=None)')
        private.name = name
        private.args.kwonlyargs.pop()
        private.args.kw_defaults.pop()
        projection = PrivateCloneProjection(kind)
        self.assertEqual(ast_key(private.body[1]), projection.entry)
        self.assertEqual(ast_key(private.body[2]),
                         projection.arguments if kind == 'selector' else projection.fallback)
        normalized = projection.visit(private)
        self.assertEqual(Counter(projection.calls), Counter(SELECTOR_PLUMBING if kind == 'selector' else PAIR_PLUMBING))
        self.assertEqual(projection.removed, Counter(entry=1, **({'arguments': 1} if kind == 'selector' else {'fallback': 1})))
        self.assertEqual(ast_key(normalized), ast_key(original))

    def test_original_public_ast_and_root_only_signatures_stay_frozen(self):
        for module, name, expected in ((selector, 'verify_premises', FROZEN_SELECTOR_AST),
                                      (accepted, 'predecessor_pin_pair', FROZEN_PAIR_AST)):
            with self.subTest(function=name):
                self.assertEqual(hashlib.sha256(ast_key(function_ast(module, name)).encode()).hexdigest(), expected)
        for function in (accepted.predecessor_pin_pair, followup.predecessor_pin_pair,
                         invariant.predecessor_pin_pair, accepted.verify_current, selector.verify):
            self.assertEqual(tuple(inspect.signature(function).parameters), ('root',))
        self.assertEqual(tuple(inspect.signature(selector.verify_premises).parameters),
                         ('root', '_return_current_admission'))

    def test_private_copies_preserve_original_predicates_constants_and_order(self):
        for kind in ('selector', 'pair'):
            with self.subTest(kind=kind):
                self.assert_clone(kind)

    def test_projection_rejects_semantic_and_observation_drift(self):
        for kind, module, name in (('selector', selector, '_verify_premises'),
                                   ('pair', accepted, '_predecessor_pin_pair')):
            for mutation in ('predicate', 'message', 'statement_order', 'entry_placement', 'observation_target'):
                altered = function_ast(module, name)
                calls = [node for node in ast.walk(altered) if isinstance(node, ast.Call)]
                proof = next(node for node in calls if isinstance(node.func, ast.Name) and node.func.id == 'require')
                if mutation == 'predicate':
                    proof.args[0] = ast.Constant(True)
                elif mutation == 'message':
                    proof.args[1] = ast.Constant('unreviewed replacement')
                elif mutation == 'statement_order':
                    altered.body[-1], altered.body[-2] = altered.body[-2], altered.body[-1]
                elif mutation == 'entry_placement':
                    altered.body[1], altered.body[3] = altered.body[3], altered.body[1]
                else:
                    observed = next(node for node in calls if any(keyword.arg == '_operation' for keyword in node.keywords))
                    observed.args[0] = ast.Name(id='foreign_root', ctx=ast.Load())
                with self.subTest(kind=kind, mutation=mutation), self.assertRaises(AssertionError):
                    self.assert_clone(kind, altered)


class OperationAdapterFakeFrameControls(unittest.TestCase):
    """Small synthetic owner/image wiring only; never real admission evidence."""
    @contextmanager
    def fake_image(self, root, raw_by_path):
        operation = object()
        def check(candidate, actual_root):
            self.assertIs(candidate, operation)
            self.assertEqual(actual_root, root)
        def observe(candidate, actual_root, path, value, mode):
            if candidate is None:
                return value
            check(candidate, actual_root)
            raw = raw_by_path[str(path)]
            expected = raw if mode == 'bytes' else cleanup._operation_text(raw, mode)
            matched = (type(value) is type(expected) and (
                source.token_sha256(value) == source.token_sha256(expected)
                if mode.startswith('supplied_') else value == expected))
            cleanup.require(matched, 'synthetic observation mismatch: ' + str(path))
            return value
        with patch.object(cleanup, '_operation_check', check), patch.object(cleanup, '_operation_observe', observe):
            yield operation

    @contextmanager
    def selector_fixture(self):
        with tempfile.TemporaryDirectory(prefix='invariant-selector-fake-') as directory:
            root = Path(directory)
            raw = {'selector.mojo': b'fake', 'reference.mojo': b'fake',
                   selector.prior.MIGRATION: b'fake', LANE: b'current scope', ROAD: b'road source'}
            for name, payload in raw.items():
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(payload)
            record = {'path': 'selector.mojo', 'before_source': 'fake', 'after_source': 'fake',
                      'after_token_sha256': source.token_sha256('fake'),
                      'prior_migration_sha256': hashlib.sha256(b'fake').hexdigest(),
                      'reference': {'path': 'reference.mojo', 'name': 'reference', 'source': 'fake'}}
            old = {'modules': {'selector.mojo': {'source': 'fake'}},
                   'import_scopes': {LANE: 'old scope'},
                   'declarations': [{'path': path, 'name': name, 'owner': [], 'source': 'fake'}
                                    for path, name in ((LANE, '_rounded_axis_lane_minimum'),
                                                       (LANE, '_refine_lane_certificate'), (ROAD, '_road_reference'))]}
            interpreted = []
            def declaration(text, name, owner):
                interpreted.append(text)
                return 'fake'
            with patch.object(selector, 'read_record', side_effect=lambda root: copy.deepcopy(record)), \
                    patch.object(selector.prior, 'read_record', side_effect=lambda root: copy.deepcopy(old)), \
                    patch.object(cleanup, '_reviewed_lane_observation', return_value=('old scope', raw[ROAD])), \
                    patch.object(guard, 'declaration', declaration):
                yield root, raw, record, interpreted

    def test_private_selector_positive_result_and_physical_read_order_match_public(self):
        with self.selector_fixture() as (root, raw, record, interpreted), self.fake_image(root, raw) as operation:
            traces = []
            original_text, original_bytes = Path.read_text, Path.read_bytes
            for private in (False, True):
                events = []
                def text(path, *args, **kwargs):
                    events.append(('text', path.relative_to(root).as_posix()))
                    return original_text(path, *args, **kwargs)
                def binary(path, *args, **kwargs):
                    events.append(('bytes', path.relative_to(root).as_posix()))
                    return original_bytes(path, *args, **kwargs)
                with patch.object(Path, 'read_text', text), patch.object(Path, 'read_bytes', binary):
                    result = (selector._verify_premises(root, _return_current_admission=True, _operation=operation)
                              if private else selector.verify_premises(root, _return_current_admission=True))
                self.assertEqual(result, (record, True))
                traces.append(events)
            self.assertEqual(traces[0], traces[1])
            self.assertEqual(traces[0].count(('bytes', LANE)), 3)
            self.assertEqual(traces[0].count(('bytes', ROAD)), 2)

    def test_private_selector_consumed_b_stops_before_declaration(self):
        cases = [('text', 'selector.mojo', selector._verify_premises, 1),
                 ('text', 'reference.mojo', selector._verify_premises, 1),
                 ('bytes', LANE, selector._lane_observation, 1),
                 ('text', LANE, selector._lane_observation, 1)]
        cases += [(mode, name, selector._verify_premises, occurrence)
                  for name in (LANE, ROAD) for mode, occurrence in (('bytes', 1), ('bytes', 2), ('text', 1))]
        for mode, name, frame, occurrence in cases:
            with self.subTest(mode=mode, path=name, frame=frame.__name__, occurrence=occurrence), \
                    self.selector_fixture() as (root, raw, record, interpreted), self.fake_image(root, raw) as operation:
                original = getattr(Path, 'read_' + mode)
                visits = []
                marker = '\ndef unreviewed_private_observation():\n    pass\n'
                def changed(path, *args, **kwargs):
                    value = original(path, *args, **kwargs)
                    if path == root/name and sys._getframe(1).f_code is frame.__code__:
                        visits.append(name)
                        if len(visits) == occurrence:
                            return value + (marker.encode() if mode == 'bytes' else marker)
                    return value
                with patch.object(Path, 'read_' + mode, changed):
                    with self.assertRaisesRegex(ValueError, 'synthetic observation mismatch|checked physical and supplied views differ'):
                        selector._verify_premises(root, _operation=operation)
                self.assertEqual(len(visits), occurrence)
                self.assertFalse(any('unreviewed_private_observation' in text for text in interpreted))
                self.assertEqual((root/name).read_bytes(), raw[name])

    def test_private_selector_supplied_comments_keep_token_equivalence(self):
        with self.selector_fixture() as (root, raw, record, interpreted), self.fake_image(root, raw) as operation:
            original = Path.read_text
            visits = []
            def commented(path, *args, **kwargs):
                text = original(path, *args, **kwargs)
                if path == root/LANE and sys._getframe(1).f_code is selector._lane_observation.__code__:
                    visits.append(LANE)
                    return '# Token-equivalent supplied view.\n' + text
                return text
            with patch.object(Path, 'read_text', commented):
                self.assertEqual(selector._verify_premises(root, _operation=operation), record)
            self.assertEqual(visits, [LANE])

    def pin_fixture(self):
        fixture = paired_helpers.PairedPinFakeControls('test_fixed_shape_order_signatures_and_single_freshness')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        return fixture

    def test_private_pair_positive_result_and_read_order_match_public(self):
        fixture = self.pin_fixture()
        raw = {paired_helpers.PIN_DIR + '/' + name: payload
               for name, payload in zip(paired_helpers.NAMES, fixture.active)}
        for current in (False, True):
            with self.subTest(current=current), fixture.synthetic(current), self.fake_image(fixture.root, raw) as operation:
                original = Path.read_bytes
                traces = []
                for private in (False, True):
                    events = []
                    def observed(path, *args, **kwargs):
                        events.append(path.relative_to(fixture.root).as_posix())
                        return original(path, *args, **kwargs)
                    with patch.object(Path, 'read_bytes', observed):
                        result = (accepted._predecessor_pin_pair(fixture.root, _operation=operation)
                                  if private else accepted.predecessor_pin_pair(fixture.root))
                    paired_helpers.assert_pair(self, result)
                    self.assertEqual(result, fixture.outputs['accepted'])
                    traces.append(events)
                self.assertEqual(traces[0], traces[1])
                self.assertEqual(len(traces[0]), 4 if current else 2)

    def test_private_pair_consumed_and_final_b_stop_before_json(self):
        fixture = self.pin_fixture()
        raw = {paired_helpers.PIN_DIR + '/' + name: payload
               for name, payload in zip(paired_helpers.NAMES, fixture.active)}
        for current in (False, True):
            frame = accepted._read_current_pair_pin if current else accepted._predecessor_pin_pair
            for name in paired_helpers.NAMES:
                for occurrence in ((1, 2) if current else (1,)):
                    path = paired_helpers.PIN_DIR + '/' + name
                    with self.subTest(current=current, name=name, occurrence=occurrence), \
                            fixture.synthetic(current), self.fake_image(fixture.root, raw) as operation:
                        original, parser = Path.read_bytes, json.loads
                        visits, interpreted = [], []
                        bad = raw[path] + b' '
                        def changed(target, *args, **kwargs):
                            value = original(target, *args, **kwargs)
                            if target == fixture.root/path and sys._getframe(1).f_code is frame.__code__:
                                visits.append(path)
                                if len(visits) == occurrence:
                                    return bad
                            return value
                        def parsed(value, *args, **kwargs):
                            if value == bad:
                                interpreted.append(value)
                            return parser(value, *args, **kwargs)
                        expected_error = ('synthetic observation mismatch' if current
                                          else 'unreviewed runtime pin successor: ' + name)
                        with patch.object(Path, 'read_bytes', changed), patch.object(json, 'loads', parsed):
                            with self.assertRaisesRegex(ValueError, expected_error):
                                accepted._predecessor_pin_pair(fixture.root, _operation=operation)
                        self.assertEqual(len(visits), occurrence)
                        self.assertEqual(interpreted, [])
                        self.assertEqual((fixture.root/path).read_bytes(), raw[path])


class BoundedOwnerCurrentControls(unittest.TestCase):
    """Real gates and public owners over the existing complete physical fixture.

    Wrappers retain their original functions and checks. Faults enter at actual
    consumer reads or after a real admission; none replaces an authority image.
    These controls do not replace the full per-callsite mutation matrix.
    """

    def setUp(self):
        import _full_audit_test_fixtures as fixtures
        self.root = fixtures.copy_current_root(self, Path(__file__).resolve().parents[2])

    @contextmanager
    def audit(self, core=cleanup, callback=None):
        from contextlib import ExitStack
        from functools import wraps
        events = {'admissions': [], 'finalizers': [], 'records': [],
                  'callbacks': [], 'frames': set()}
        binding, checkpoint, record = (core.executing_checker_bindings,
                                       core._CacheInputs.checkpoint, core._operation_record)
        notified = set()

        @wraps(binding)
        def admitted(*args, **kwargs):
            frame = sys._getframe(1)
            if (frame.f_globals is vars(core) and frame.f_code is core.verify.__code__
                    and 'executing' not in frame.f_locals):
                events['admissions'].append(frame.f_locals['_capture'])
            return binding(*args, **kwargs)

        @wraps(checkpoint)
        def finalized(view, owner, root):
            events['finalizers'].append(view)
            return checkpoint(view, owner, root)

        @wraps(record)
        def projected(operation, root, **kwargs):
            value = record(operation, root, **kwargs)
            events['records'].append(operation)
            frame = sys._getframe(1)
            while frame is not None:
                kind = core._operation_frame_kind(frame)
                if kind is not None:
                    events['frames'].add(kind)
                frame = frame.f_back
            if callback is not None and id(operation) not in notified:
                notified.add(id(operation))
                events['callbacks'].append(operation)
                callback(operation)
            return value

        with ExitStack() as stack:
            stack.enter_context(patch.object(core, 'executing_checker_bindings', admitted))
            stack.enter_context(patch.object(core._CacheInputs, 'checkpoint', finalized))
            stack.enter_context(patch.object(core, '_operation_record', projected))
            yield events

    def coverage(self):
        # Coverage uses its real package namespace. Never alias it to the
        # top-level verifier used by the invariant tests above.
        tools = str(Path(__file__).resolve().parents[1])
        if tools not in sys.path:
            self.addCleanup(sys.path.remove, tools)
            sys.path.insert(0, tools)
        import coverage_loop_proofs as loops
        from carla_lane_oracle import full_audit_cleanup_contracts as core
        return loops, core

    def assert_public_coherence_error(self, error, operation):
        """Require the established accepted-pin public envelope and its cause."""
        self.assertIs(type(error), ValueError)
        self.assertIs(type(error.__cause__), cleanup._OperationCoherenceError)
        self.assertTrue(operation._failed)
        self.assertTrue(operation._failure_reason)
        self.assertEqual(str(error.__cause__), operation._failure_reason)
        self.assertEqual(str(error),
                         'unreviewed complete successor: ' + operation._failure_reason)

    def assert_closed(self, operation, core=cleanup):
        self.assertIs(type(operation), core._InvariantInputs)
        self.assertEqual(operation._state, 'closed')
        self.assertFalse(operation._raw)
        self.assertIsNone(operation._record_raw)
        self.assertIsNone(operation._owner_frame)
        self.assertEqual(operation._observations, [])
        self.assertEqual(operation._discoveries, [])

    def assert_one_owner(self, events, kind, core=cleanup):
        self.assertEqual(len(events['admissions']), 1)
        operation = events['admissions'][0]
        self.assertEqual(operation._kind, kind)
        self.assertEqual(events['finalizers'], [operation])
        self.assertTrue(events['records'])
        self.assertTrue(all(value is operation for value in events['records']))
        self.assert_closed(operation, core)
        return operation

    def test_current_invariant_calls_admit_finalize_and_dispose_independently(self):
        owners = []
        for _ in range(2):
            with self.audit() as events:
                result = invariant.verify(self.root)
            self.assertEqual(len(result['sources']), 4)
            owners.append(self.assert_one_owner(events, 'invariant'))
            self.assertFalse(any(value is owners[-1] for value in vars(invariant).values()))
            self.assertFalse(any(value is owners[-1] for value in vars(cleanup).values()))
        self.assertIsNot(owners[0], owners[1])
        for operation in owners:
            for copier in (copy.copy, copy.deepcopy):
                with self.assertRaises(ValueError):
                    copier(operation)
            with self.assertRaises(cleanup._OperationCoherenceError):
                cleanup._operation_check(operation, self.root)
            operation.close()
            self.assert_closed(operation)

    def test_current_winner_children_borrow_without_finalizing_parent(self):
        import winner_sign_contracts as winner
        with self.audit() as events:
            result = winner.verify(self.root)
        self.assertEqual(result['status'], 'PASS')
        self.assertEqual(result['reviewed_cleanup_successors'], 20)
        self.assert_one_owner(events, 'winner')
        self.assertTrue({'winner', 'invariant', 'border'} <= events['frames'])

    def test_current_decorated_border_has_one_own_lifetime(self):
        import border_parser_contracts as border
        with self.audit() as events:
            result = border.verify(self.root)
        self.assertEqual(result['after_sha256'], border.AFTER_SHA256)
        self.assert_one_owner(events, 'border')

    def test_current_map_and_rtree_never_share_an_image(self):
        loops, core = self.coverage()
        owners = []
        for module, kind in (('extensions/carla/map', 'map_loops'),
                             ('extensions/carla/rtree', 'rtree_loops')):
            with self.subTest(module=module), self.audit(core) as events:
                result = loops.reviewed_nonempty_loops(self.root, module)
            self.assertTrue(result)
            self.assertTrue(all(line == row['line'] for line, row in result.items()))
            owners.append(self.assert_one_owner(events, kind, core))
        self.assertIsNot(owners[0], owners[1])

    def test_current_foreign_root_thread_and_cwd_poison_the_owner(self):
        import os
        from concurrent.futures import ThreadPoolExecutor
        for fault in ('root', 'thread', 'cwd'):
            rejected = []
            def consume(operation):
                with self.assertRaises(cleanup._OperationCoherenceError):
                    if fault == 'root':
                        cleanup._operation_check(operation, self.root/'foreign')
                    elif fault == 'thread':
                        with ThreadPoolExecutor(max_workers=1) as pool:
                            pool.submit(cleanup._operation_check, operation, self.root).result(timeout=5)
                    else:
                        previous = Path.cwd()
                        try:
                            os.chdir(self.root)
                            cleanup._operation_check(operation, self.root)
                        finally:
                            os.chdir(previous)
                rejected.append(fault)
                self.assertTrue(operation._failed)
                self.assertFalse(operation._raw)
                with self.assertRaises(cleanup._OperationCoherenceError):
                    cleanup._operation_check(operation, self.root)
            with self.subTest(fault=fault), self.audit(callback=consume) as events:
                with self.assertRaises(ValueError) as public_error:
                    invariant.verify(self.root)
            self.assertEqual(len(events['admissions']), 1)
            self.assertEqual(events['callbacks'], events['admissions'])
            self.assertEqual(rejected, [fault])
            self.assert_public_coherence_error(public_error.exception, events['admissions'][0])
            self.assert_closed(events['admissions'][0])

    def test_current_primary_exception_closes_without_a_success_finalizer(self):
        failure = RuntimeError('independent consumer failure')
        def consume(operation):
            raise failure
        with self.audit(callback=consume) as events:
            with self.assertRaises(RuntimeError) as caught:
                invariant.verify(self.root)
        self.assertIs(caught.exception, failure)
        self.assertEqual(events['finalizers'], [])
        self.assert_closed(events['admissions'][0])

    def test_current_nested_public_owner_is_fresh_and_blocks_the_outer_handle(self):
        owners = []
        def consume(operation):
            owners.append(operation)
            if len(owners) == 1:
                self.assertEqual(len(invariant.verify(self.root)['sources']), 4)
            else:
                self.assertIsNot(operation, owners[0])
                with self.assertRaisesRegex(cleanup._OperationCoherenceError,
                                            'nearer independent operation'):
                    cleanup._operation_check(owners[0], self.root)
                cleanup._operation_check(operation, self.root)
        with self.audit(callback=consume) as events:
            with self.assertRaises(ValueError) as public_error:
                invariant.verify(self.root)
        self.assertEqual(events['admissions'], owners)
        self.assertEqual(events['finalizers'], [owners[1]])
        self.assert_public_coherence_error(public_error.exception, owners[0])
        for operation in owners:
            self.assert_closed(operation)

    def test_current_direct_and_arbitrary_borrow_routes_refuse(self):
        import border_parser_contracts as border
        import winner_sign_contracts as winner
        for target in ('invariant', 'border', 'arbitrary'):
            rejected = []
            def consume(operation):
                def arbitrary():
                    return invariant.verify(self.root, _operation=operation)
                route = arbitrary if target == 'arbitrary' else lambda: (
                    invariant.verify(self.root, _operation=operation) if target == 'invariant'
                    else border.verify(self.root, _operation=operation))
                with self.assertRaisesRegex(cleanup._OperationCoherenceError, 'exact private wrapper'):
                    route()
                rejected.append(target)
                self.assertTrue(operation._failed)
            with self.subTest(target=target), self.audit(callback=consume) as events:
                with self.assertRaises(cleanup._OperationCoherenceError):
                    winner.verify(self.root)
            self.assertEqual(len(events['admissions']), 1)
            self.assertEqual(events['callbacks'], events['admissions'])
            self.assertEqual(rejected, [target])
            self.assert_closed(events['admissions'][0])

    def test_current_registered_and_unregistered_aliases_block_outer_use(self):
        import importlib.util
        from contextlib import ExitStack
        from functools import wraps
        for registered in (False, True):
            name = '_bounded_invariant_alias_' + str(registered)
            spec = importlib.util.spec_from_file_location(name, invariant.__file__)
            alias = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(alias)
            reached = []
            def consume(operation):
                read_record = alias.read_record
                @wraps(read_record)
                def alias_read(root):
                    frame = sys._getframe(1)
                    self.assertIs(frame.f_globals, vars(alias))
                    self.assertIsNone(frame.f_locals['_operation'])
                    reached.append(True)
                    cleanup._operation_check(operation, root)
                    self.fail('alias frame permitted the outer owner')
                with patch.object(alias, 'read_record', alias_read):
                    with self.assertRaisesRegex(cleanup._OperationCoherenceError,
                                                'nearer independent operation'):
                        alias.verify(self.root)
            with self.subTest(registered=registered), ExitStack() as stack:
                if registered:
                    stack.enter_context(patch.dict(sys.modules, {name: alias}))
                events = stack.enter_context(self.audit(callback=consume))
                with self.assertRaises(ValueError) as public_error:
                    invariant.verify(self.root)
            self.assertEqual(reached, [True])
            self.assert_public_coherence_error(public_error.exception, events['admissions'][0])
            self.assert_closed(events['admissions'][0])

    def test_current_each_exact_demand_rechecks_four_immutable_endpoints(self):
        from functools import wraps
        checked = []
        original = cleanup.sha
        @wraps(original)
        def hashed(raw):
            frame = sys._getframe(1)
            if frame.f_code is cleanup._InvariantInputs._admit.__code__ and frame.f_locals['exact']:
                checked.append(frame.f_locals['path'])
            return original(raw)
        def consume(operation):
            with self.assertRaises(TypeError):
                operation._raw[ROAD] = b'changed captured input'
            with patch.object(cleanup, 'sha', hashed):
                first = cleanup.verified_edges(self.root, _operation=operation)
                second = cleanup.verified_edges(self.root, _operation=operation)
            self.assertEqual(Counter(checked), Counter({name: 2 for name in cleanup.SOURCE_PATHS}))
            self.assertEqual(first, second)
            self.assertIsNot(first, second)
            first[LANE]['after_sha256'] = 'changed caller result'
            self.assertEqual(second[LANE]['after_sha256'], cleanup.AFTER_SHA256[LANE])
        with self.audit(callback=consume) as events:
            invariant.verify(self.root)
        self.assert_one_owner(events, 'invariant')

    def test_current_direct_private_misuse_rejects_and_finally_closes(self):
        for fault in ('wrong_token', 'unlisted_path'):
            failure = RuntimeError('stop after rejected private access: ' + fault)
            def consume(operation):
                with self.assertRaises(ValueError):
                    if fault == 'wrong_token':
                        operation.raw(object(), self.root, ROAD)
                    else:
                        operation.raw(operation._owner, self.root, 'unlisted.mojo')
                # Reject this access, then exit. Do not require later reuse or
                # a poison policy for private misuse outside the owned graph.
                raise failure
            with self.subTest(fault=fault), self.audit(callback=consume) as events:
                with self.assertRaises(RuntimeError) as caught:
                    invariant.verify(self.root)
            self.assertIs(caught.exception, failure)
            self.assertEqual(events['finalizers'], [])
            self.assert_closed(events['admissions'][0])

    def test_current_invalid_exact_request_is_sticky_when_caught(self):
        rejected = []
        def consume(operation):
            with self.assertRaisesRegex(cleanup._OperationCoherenceError, 'exactness request'):
                cleanup._operation_record(operation, self.root, exact='yes')
            rejected.append('invalid_exact')
            self.assertTrue(operation._failed)
            self.assertFalse(operation._raw)
            with self.assertRaises(cleanup._OperationCoherenceError):
                cleanup._operation_record(operation, self.root)
        with self.audit(callback=consume) as events:
            with self.assertRaises(ValueError) as public_error:
                invariant.verify(self.root)
        self.assertEqual(len(events['admissions']), 1)
        self.assertEqual(events['callbacks'], events['admissions'])
        self.assertEqual(rejected, ['invalid_exact'])
        self.assert_public_coherence_error(public_error.exception, events['admissions'][0])
        self.assert_closed(events['admissions'][0])

    def test_current_consumed_text_and_bytes_refuse_before_semantic_use(self):
        import winner_sign_contracts as winner
        from functools import wraps
        for mode, module, name in (('text', invariant, LANE), ('bytes', winner, ROAD)):
            read = getattr(Path, 'read_' + mode)
            body = inspect.unwrap(module.verify).__code__
            visits, interpreted = [], []
            marker = '\n# Unreviewed consumed operation bytes.\n'
            token = source.token_sha256
            @wraps(token)
            def interpreted_text(text):
                if marker in text:
                    interpreted.append(text)
                return token(text)
            def changed(path, *args, **kwargs):
                value = read(path, *args, **kwargs)
                frame = sys._getframe(1)
                if (path == self.root/name and frame.f_globals is vars(module)
                        and frame.f_code is body
                        and frame.f_locals.get('_operation') is not None
                        and frame.f_locals['_operation']._state == 'active'):
                    visits.append(name)
                    return value + (marker.encode() if mode == 'bytes' else marker)
                return value
            original = (self.root/name).read_bytes()
            with self.subTest(mode=mode), self.audit() as events, patch.object(
                    Path, 'read_' + mode, changed), patch.object(source, 'token_sha256', interpreted_text):
                with self.assertRaisesRegex(cleanup._OperationCoherenceError, 'consumed operation'):
                    module.verify(self.root)
            self.assertEqual(visits, [name])
            self.assertEqual(interpreted, [])
            self.assertEqual((self.root/name).read_bytes(), original)
            self.assert_closed(events['admissions'][0])

    def test_current_finalizer_rejects_persistent_bytes_and_new_source_census(self):
        from functools import wraps
        finish = cleanup._InvariantInputs.finish
        for fault in ('bytes', 'census'):
            target = self.root/(ROAD if fault == 'bytes' else 'extensions/carla/unreviewed_owner.mojo')
            original = target.read_bytes() if target.exists() else None
            injected = []
            @wraps(finish)
            def finalized(operation, root):
                injected.append(operation)
                target.write_bytes((original or b'') + b'\n# Persistent owner mutation.\n')
                return finish(operation, root)
            try:
                with self.subTest(fault=fault), self.audit() as events, patch.object(
                        cleanup._InvariantInputs, 'finish', finalized):
                    with self.assertRaises(cleanup._OperationCoherenceError):
                        invariant.verify(self.root)
                self.assertEqual(injected, events['admissions'])
                self.assert_closed(injected[0])
            finally:
                if original is None:
                    target.unlink(missing_ok=True)
                else:
                    target.write_bytes(original)

    def test_current_validation_only_transient_change_has_no_extra_sampling(self):
        # Option B permits this only between actual consumers and finalization.
        # The consumed-read test above still rejects B even when disk stays A.
        target = self.root/ROAD
        original = target.read_bytes()
        def consume(operation):
            try:
                target.write_bytes(original + b'\n# Unconsumed transient change.\n')
                with patch.object(Path, 'read_bytes', side_effect=AssertionError('extra image sampling')):
                    operation.checkpoint(operation._owner, self.root)
            finally:
                target.write_bytes(original)
        with self.audit(callback=consume) as events:
            invariant.verify(self.root)
        self.assert_one_owner(events, 'invariant')

    def test_historical_invariant_keeps_lazy_current_admission(self):
        import _full_audit_test_fixtures as fixtures
        from functools import wraps
        record = cleanup.read_record(self.root)
        predecessors = {name: cleanup.reverse_exact(name, item['after_source'], item).encode('utf-8')
                        for name, item in record['sources'].items()}
        fixtures.write_predecessors(self.root, predecessors)
        states, owners = [], []
        finish = cleanup._InvariantInputs.finish
        @wraps(finish)
        def finalized(operation, root):
            states.append(operation._state)
            owners.append(operation)
            return finish(operation, root)
        with self.audit() as events, patch.object(cleanup._InvariantInputs, 'finish', finalized):
            result = invariant.verify(self.root)
        self.assertEqual(len(result['sources']), 4)
        self.assertEqual(events['admissions'], [])
        self.assertEqual(events['finalizers'], [])
        self.assertEqual(states, ['pending'])
        self.assert_closed(owners[0])

    def test_current_caught_guarded_read_failure_discards_existing_map_rows(self):
        loops, core = self.coverage()
        from functools import wraps
        guarded, read = loops.guarded_loop_proof, Path.read_bytes
        earlier, injected = [], []
        @wraps(guarded)
        def proof(root, rule, **kwargs):
            result = sys._getframe(1).f_locals['result']
            self.assertTrue(result, 'construction must produce a real earlier row')
            earlier.append(set(result))
            def changed(path, *args, **settings):
                raw = read(path, *args, **settings)
                caller = sys._getframe(1)
                if (not injected and caller.f_code is loops._reviewed_dependency_hashes.__code__
                        and path == root/'extensions/carla/map.mojo'):
                    injected.append(path)
                    return raw + b'\n# Consumed B after a real earlier row.\n'
                return raw
            with patch.object(Path, 'read_bytes', changed):
                return guarded(root, rule, **kwargs)
        with self.audit(core) as events, patch.object(loops, 'guarded_loop_proof', proof):
            self.assertEqual(loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map'), {})
        self.assertTrue(earlier)
        self.assertEqual(len(injected), 1)
        self.assertTrue(events['admissions'][0]._failed)
        self.assert_closed(events['admissions'][0], core)

    def test_current_actual_stream_reads_reject_changed_short_wrong_and_failed_chunks(self):
        loops, core = self.coverage()
        original_open = Path.open
        for fault in ('changed', 'short', 'wrong_eof', 'io'):
            visited, injected = [], []
            message = {'changed': 'consumed operation bytes',
                       'short': 'consumed operation bytes',
                       'wrong_eof': 'Non-byte coverage source stream',
                       'io': 'injected stream failure'}[fault]
            def consume(operation):
                target = self.root/ROAD
                class Stream:
                    def __init__(self, stream):
                        self.stream = stream
                        self.calls = 0
                    def __enter__(self):
                        self.stream.__enter__()
                        return self
                    def __exit__(self, *args):
                        return self.stream.__exit__(*args)
                    def read(self, size):
                        raw = self.stream.read(size)
                        self.calls += 1
                        visited.append((size, self.calls))
                        if fault == 'io':
                            injected.append(fault)
                            raise PermissionError('injected stream failure')
                        if fault == 'wrong_eof' and not raw:
                            injected.append(fault)
                            return bytearray()
                        if self.calls == 1:
                            if fault == 'changed':
                                injected.append(fault)
                                return raw + b'\n# Stream B.\n'
                            if fault == 'short':
                                injected.append(fault)
                                return raw[:-1]
                        return raw
                def opened(path, *args, **kwargs):
                    stream = original_open(path, *args, **kwargs)
                    if path == target and sys._getframe(1).f_code is loops.file_sha256.__code__:
                        self.assertEqual(args, ('rb',))
                        return Stream(stream)
                    return stream
                with patch.object(Path, 'open', opened):
                    with self.assertRaisesRegex(core._OperationCoherenceError, message):
                        loops.file_sha256(target, _operation=operation, _root=self.root)
                self.assertTrue(operation._failed)
                with self.assertRaises(core._OperationCoherenceError):
                    core._operation_check(operation, self.root)
            with self.subTest(fault=fault), self.audit(core, consume) as events:
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map'), {})
            self.assertTrue(visited)
            self.assertEqual(injected, [fault])
            self.assertTrue(all(size == 1 << 20 for size, _ in visited))
            self.assert_closed(events['admissions'][0], core)

    def test_current_duplicate_proof_conflict_remains_an_error(self):
        # Only the fault is synthetic: both colliding rows are real proofs.
        loops, core = self.coverage()
        from functools import wraps
        guarded = loops.guarded_loop_proof
        collided = []
        @wraps(guarded)
        def proof(root, rule, **kwargs):
            result = sys._getframe(1).f_locals['result']
            value = guarded(root, rule, **kwargs)
            self.assertTrue(result)
            self.assertIsNotNone(value)
            changed = dict(value, line=next(iter(result)))
            collided.append(changed['line'])
            return changed
        with self.audit(core) as events, patch.object(loops, 'guarded_loop_proof', proof):
            with self.assertRaisesRegex(ValueError, 'Conflicting reviewed loop proof') as caught:
                loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map')
        self.assertNotIsInstance(caught.exception, core._OperationCoherenceError)
        self.assertEqual(len(collided), 1)
        self.assert_closed(events['admissions'][0], core)


class BoundedOwnerSyntheticBoundaryControls(unittest.TestCase):
    """Routing/frame controls only; no claim of real current-image admission."""

    def test_arbitrary_factory_and_unsupported_borrow_do_not_create_authority(self):
        root = Path(__file__).resolve().parents[2]
        self.assertEqual(cleanup._operation_enter(root, 'invariant'), (None, False))
        with self.assertRaisesRegex(ValueError, 'direct owner factory'):
            cleanup._InvariantInputs(root, sys._getframe(), 'invariant')
        with self.assertRaisesRegex(ValueError, 'unsupported context'):
            cleanup._operation_enter(root, None, object(), include_roots=(root,))

    def test_nonempty_include_and_unrelated_module_keep_original_fresh_dispatch(self):
        from contextlib import ExitStack
        tools = str(Path(__file__).resolve().parents[1])
        with patch.object(sys, 'path', [tools, *sys.path]):
            import coverage_loop_proofs as loops
            from carla_lane_oracle import full_audit_cleanup_contracts as core
        root = Path(__file__).resolve().parents[2]
        for module, includes in (('extensions/carla/map', (root,)),
                                 ('extensions/carla/rtree', (root,)), ('unrelated/module', ())):
            calls = []
            def historical(actual_root, actual_module, **kwargs):
                calls.append(('historical', actual_root, actual_module, kwargs))
                return {}
            def construction(actual_root, **kwargs):
                calls.append(('construction', actual_root, module, kwargs))
                return {}
            def guarded(actual_root, rule, **kwargs):
                calls.append(('guarded', actual_root, rule[0], kwargs))
                return None
            with self.subTest(module=module, includes=includes), ExitStack() as stack:
                stack.enter_context(patch.object(core, '_operation_enter', side_effect=AssertionError('unexpected owner')))
                stack.enter_context(patch.object(loops, '_historical_reviewed_nonempty_loops', historical))
                stack.enter_context(patch.object(loops, 'construction_boundary_loops', construction))
                stack.enter_context(patch.object(loops, 'guarded_loop_proof', guarded))
                self.assertEqual(loops.reviewed_nonempty_loops(root, module, include_roots=includes), {})
            self.assertTrue(calls)
            for _, actual_root, actual_module, kwargs in calls:
                self.assertEqual((actual_root, actual_module), (root, module))
                self.assertEqual(kwargs, {'include_roots': includes})

    def test_negative_frame_filter_matches_unfiltered_results_and_errors(self):
        import types
        node = copy.deepcopy(function_ast(cleanup, '_operation_frame_kind'))
        # Remove exactly the reviewed absolute-path/plain-function negative
        # filter. Keep all authoritative comparisons and exceptional behavior.
        filter_node = next(statement for statement in node.body if isinstance(statement, ast.If)
                           and 'filename.startswith' in ast.unparse(statement.test))
        node.body.remove(filter_node)
        node.name = '_unfiltered_frame_kind'
        namespace = dict(vars(cleanup))
        exec(compile(ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[])),
                     '<unfiltered-operation-frame-control>', 'exec'), namespace)
        reference = namespace[node.name]
        def plain():
            pass
        def cyclic():
            pass
        cyclic.__wrapped__ = cyclic
        frames = [None, types.SimpleNamespace(f_globals=globals(), f_code=plain.__code__, f_locals={})]
        for filename in (invariant.__file__, 'relative/coverage_invariant_contracts.py', None):
            for function in (None, plain, cyclic):
                frames.append(types.SimpleNamespace(
                    f_globals={'__file__': filename, 'verify': function},
                    f_code=plain.__code__, f_locals={}))
        frames.append(types.SimpleNamespace(f_globals=vars(invariant),
                                            f_code=invariant.verify.__code__, f_locals={}))
        def outcome(function, frame, aliases):
            try:
                return ('result', function(frame, include_aliases=aliases))
            except Exception as error:
                return ('error', type(error), str(error))
        for frame in frames:
            for aliases in (False, True):
                with self.subTest(frame=frame, aliases=aliases):
                    self.assertEqual(outcome(cleanup._operation_frame_kind, frame, aliases),
                                     outcome(reference, frame, aliases))

# Append before the maintained module's final unittest.main() guard.
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Reviewed classifier and lexical mechanics controls. These are not real
# immutable-image lifecycle qualification; the separate lifecycle tests remain.
import importlib as _rm_importlib
import os as _rm_os
from pathlib import Path as _rm_Path, PosixPath as _rm_PosixPath
import sys as _rm_sys
import unittest as _rm_unittest
from unittest.mock import patch as _rm_patch


def _reviewed_mechanics_module(stem):
    prefix = (__package__ + '.') if __package__ else ''
    if stem != 'coverage_loop_proofs':
        return _rm_importlib.import_module(prefix + stem)
    # Reuse the same supported canonical namespace as this test. Restore the
    # temporary import search entry before any classifier/helper observation.
    cleanup = _rm_importlib.import_module(prefix + 'full_audit_cleanup_contracts')
    root = _rm_Path(cleanup.__file__).resolve().parents[2]
    name = 'tools.coverage_loop_proofs' if prefix.startswith('tools.') else 'coverage_loop_proofs'
    with _rm_patch.object(_rm_sys, 'path', [str(root / 'tools'), *_rm_sys.path]):
        return _rm_importlib.import_module(name)

"""Focused differential classifier controls, not source qualification.

Import real canonical modules only when this script is explicitly authorized to
run. Compile just the old/new classifiers into isolated globals. Never replace
production functions, source bytes, sys.modules, or a source admission graph.
Synthetic frame records carry actual code and module-global identities. They
exercise classification only; real operation lifecycle controls remain separate.
"""
import ast as _rc21_ast
from contextlib import nullcontext as _rc21_nullcontext
import hashlib as _rc21_hashlib
import importlib as _rc21_importlib
import json as _rc21_json
from pathlib import Path as _rc21_Path
import sys as _rc21_sys
import types as _rc21_types
from unittest.mock import patch as _rc21_patch
_rc21_UNSET = object()
_rc21_CHECK_COUNT = 0
_rc21_OP_NAMES = ('coverage_invariant_contracts.py', 'winner_sign_contracts.py', 'border_parser_contracts.py', 'coverage_loop_proofs.py')

def _rc21_require(value, detail=None):
    """Always active in normal and optimized Python, unlike assert."""
    global _rc21_CHECK_COUNT
    _rc21_CHECK_COUNT += 1
    if not value:
        if detail is None:
            raise AssertionError
        raise AssertionError(detail)

def _rc21_definitions(text):
    return {node.name: node for node in _rc21_ast.parse(text).body if isinstance(node, (_rc21_ast.FunctionDef, _rc21_ast.ClassDef))}

def _rc21_ast_key(node):
    return _rc21_ast.dump(node, include_attributes=False)

def _rc21_function(code, namespace):
    return _rc21_types.FunctionType(code, namespace, code.co_name)

def _rc21_frame(namespace, code, **locals_):
    return _rc21_types.SimpleNamespace(f_globals=namespace, f_code=code, f_locals=locals_)

def _rc21_outcome(call, input_flag=_rc21_UNSET):
    try:
        value = call()
        if input_flag is not _rc21_UNSET and value is input_flag:
            return {'value_is_input_flag': True}
        return {'value': value}
    except Exception as error:
        return {'exception': type(error).__module__ + '.' + type(error).__qualname__, 'message': str(error)}

def _rc21_main():
    global _rc21_CHECK_COUNT
    _rc21_CHECK_COUNT = 0
    cleanup = _reviewed_mechanics_module('full_audit_cleanup_contracts')
    after = _rc21_Path(cleanup.__file__).absolute()
    root = after.parents[2]
    new_raw = after.read_bytes()
    new_text = new_raw.decode('utf-8')
    new_defs = _rc21_definitions(new_text)
    helper_hash = '3def29f2a78a9b5b66185e4df1a416e9db5b931aeee0edec7febe89bf25db2eb'
    _rc21_require(_rc21_hashlib.sha256(_rc21_ast_key(new_defs['_different_alias_leaf']).encode()).hexdigest() == helper_hash, 'reviewed classifier helper AST drift')
    guards = {'_operation_frame_kind': 'cba84dcfda3a51af833b0c31fab1af75e6315e2ad074f741e9175d51362ff010', '_cache_verify_frame': 'd7cbe42a90b3841722f4cc2f13c0c99279c20289ffbacb13a9e77387199b0d1e'}
    originals = {'_operation_frame_kind': '39b16f4014f5723842f04d3913d6cb7aaef23abddfd182ae6ffbbd316e0205d0', '_cache_verify_frame': 'f52cba9ca558a0db0d9acfd0701d035b297add0863943af5e619dfe99ec71390'}
    old_defs = dict(new_defs)
    old_defs.pop('_different_alias_leaf')
    for name, guard_hash in guards.items():
        tree = _rc21_ast.parse(_rc21_ast.get_source_segment(new_text, new_defs[name])).body[0]
        removed = [node for node in tree.body if isinstance(node, _rc21_ast.If) and _rc21_hashlib.sha256(_rc21_ast_key(node).encode()).hexdigest() == guard_hash]
        _rc21_require(len(removed) == 1, (name, 'one exact reviewed guard'))
        tree.body = [node for node in tree.body if node is not removed[0]]
        _rc21_require(_rc21_hashlib.sha256(_rc21_ast_key(tree).encode()).hexdigest() == originals[name], (name, 'complete original classifier AST drift'))
        old_defs[name] = tree
    compiled = compile(new_raw, str(after), 'exec', dont_inherit=True, optimize=_rc21_sys.flags.optimize)
    code_by_name = {code.co_name: code for code in compiled.co_consts if isinstance(code, _rc21_types.CodeType)}
    for name in (*guards, '_owner_module', '_different_alias_leaf'):
        _rc21_require(code_by_name[name] == getattr(cleanup, name).__code__, (name, 'live classifier source binding'))
    modules = {name: _reviewed_mechanics_module(name) for name in ('coverage_invariant_contracts', 'winner_sign_contracts', 'border_parser_contracts', 'cache_key_contracts', 'lane_order_contracts', 'coverage_followup_contracts', 'coverage_loop_proofs')}
    _rc21_require(all((_rc21_Path(module.__file__).absolute().is_relative_to(root) for module in modules.values())), 'canonical fixture module roots')
    names = ('_owner_module', '_cache_verify_frame', '_operation_frame_kind')
    counts = {'cases': 0, 'equivalent': 0, 'negative_path_elisions': 0}
    details = []

    def contexts(core_file=str(after), *, main_module=None, registration=None, os_name=None):
        result = []
        for defs in (old_defs, new_defs):
            namespace = dict(vars(cleanup))
            namespace.pop('_different_alias_leaf', None)
            registry = dict(_rc21_sys.modules)
            if main_module is not None:
                registry['__main__'] = main_module
            if registration is not None:
                registry[registration[0]] = registration[1]
            namespace['sys'] = _rc21_types.SimpleNamespace(modules=registry)
            namespace['__file__'] = core_file
            if os_name is not None:
                namespace['os'] = _rc21_types.SimpleNamespace(name=os_name)
            calls = []

            def observed_path(value, _calls=calls):
                _calls.append(value)
                return _rc21_Path(value)
            namespace['Path'] = observed_path
            selected = [defs[name] for name in names]
            if '_different_alias_leaf' in defs:
                selected.insert(0, defs['_different_alias_leaf'])
            tree = _rc21_ast.Module(body=selected, type_ignores=[])
            exec(compile(tree, '<isolated-classifier-control>', 'exec'), namespace)
            result.append((namespace, calls))
        return result

    def compare(label, candidate, *, classifiers=('_operation_frame_kind', '_cache_verify_frame'), include_aliases=True, core_file=str(after), main_module=None, registration=None, os_name=None, missing_cwd=False, elide=False, expected=_rc21_UNSET, expected_error=None, preserve_path_calls=False, flag_factory=None, expected_bool_calls=None, expected_flag_return=False):
        pair = contexts(core_file, main_module=main_module, registration=registration, os_name=os_name)
        for classifier in classifiers:
            results = []
            calls = []
            bool_calls = []
            for namespace, path_calls in pair:
                path_calls.clear()
                scope = _rc21_patch('os.getcwd', side_effect=FileNotFoundError('control missing cwd')) if missing_cwd else _rc21_nullcontext()
                flag = include_aliases if flag_factory is None else flag_factory()
                with scope:
                    results.append(_rc21_outcome(lambda: namespace[classifier](candidate, include_aliases=flag), input_flag=flag if flag_factory is not None else _rc21_UNSET))
                calls.append(len(path_calls))
                bool_calls.append(flag.calls if flag_factory is not None else None)
            _rc21_require(results[0] == results[1], (label, classifier, results))
            if 'value' in results[0] and 'value' in results[1]:
                _rc21_require(type(results[0]['value']) is type(results[1]['value']), (label, results))
            if flag_factory is not None:
                _rc21_require(bool_calls == [expected_bool_calls, expected_bool_calls], (label, bool_calls))
            if expected_flag_return:
                _rc21_require(results[0] == {'value_is_input_flag': True}, (label, results))
            if expected is not _rc21_UNSET:
                wanted = expected[classifier] if type(expected) is dict else expected
                _rc21_require(results[0] == {'value': wanted}, (label, classifier, results, wanted))
                _rc21_require(type(results[0]['value']) is type(wanted), (label, results, wanted))
            if expected_error is not None:
                _rc21_require(results[0] == {'exception': expected_error[0], 'message': expected_error[1]}, (label, classifier, results, expected_error))
            if preserve_path_calls:
                _rc21_require(calls[0] > 0 and calls[0] == calls[1], (label, classifier, calls))
            if elide:
                _rc21_require(calls[0] > 0 and calls[1] == 0, (label, classifier, calls))
                counts['negative_path_elisions'] += 1
            counts['cases'] += 1
            counts['equivalent'] += 1
            details.append({'label': label, 'classifier': classifier, 'include_aliases': include_aliases, 'outcome': results[0], 'old_path_constructions': calls[0], 'new_path_constructions': calls[1], 'bool_calls': bool_calls})
    live = cleanup._live_function_code
    for name, module in modules.items():
        symbol = 'reviewed_nonempty_loops' if name == 'coverage_loop_proofs' else 'verify'
        for include_aliases in (False, True):
            choices = ('extensions/carla/map', 'extensions/carla/rtree', 'other') if symbol != 'verify' else (None,)
            for module_name in choices:
                operation_kind = {'coverage_invariant_contracts': 'invariant', 'winner_sign_contracts': 'winner', 'border_parser_contracts': 'border'}.get(name)
                if name == 'coverage_loop_proofs':
                    operation_kind = {'extensions/carla/map': 'map_loops', 'extensions/carla/rtree': 'rtree_loops'}.get(module_name, 'other_loops')
                compare('canonical:' + name + ':' + str(module_name), _rc21_frame(vars(module), live(getattr(module, symbol)), module=module_name), include_aliases=include_aliases, expected={'_operation_frame_kind': operation_kind, '_cache_verify_frame': name == 'cache_key_contracts'})
    for name in ('cache_key_contracts', 'lane_order_contracts', 'coverage_followup_contracts'):
        module = modules[name]
        compare('measured-operation-negative:' + name, _rc21_frame(vars(module), live(module.verify)), classifiers=('_operation_frame_kind',), elide=True, expected=None)
    for name in ('coverage_invariant_contracts', 'lane_order_contracts', 'coverage_followup_contracts'):
        module = modules[name]
        compare('measured-cache-negative:' + name, _rc21_frame(vars(module), live(module.verify)), classifiers=('_cache_verify_frame',), elide=True, expected=False)
    base_code = modules['coverage_invariant_contracts'].verify.__code__
    oracle = root / 'tools/carla_lane_oracle'
    paths = [str(oracle / name) for name in (*_rc21_OP_NAMES[:3], 'cache_key_contracts.py')]
    paths += [str(root / 'tools/coverage_loop_proofs.py'), str(oracle / 'other.py'), str(root / 'wrong/coverage_invariant_contracts.py'), str(oracle) + '//./coverage_invariant_contracts.py', str(oracle) + '//./other.py', str(oracle / 'other.py') + '/', str(oracle / 'other.py') + '/.', str(oracle / 'other.py') + '/..', 'relative.py', '', '/', '/.', '/..', None, 7]

    class ExoticString(str):
        pass
    paths.append(ExoticString(str(oracle / 'coverage_invariant_contracts.py')))
    for path in paths:
        namespace = {'__file__': path, '__name__': '_classifier_alias'}
        actual = _rc21_function(base_code, namespace)
        namespace['verify'] = actual
        namespace['reviewed_nonempty_loops'] = actual
        candidate = _rc21_frame(namespace, actual.__code__, module='extensions/carla/map')
        for include_aliases in (False, True):
            compare('spelling:' + repr(path), candidate, include_aliases=include_aliases)
        alias = _rc21_types.ModuleType('_classifier_alias')
        alias.__dict__.update(namespace)
        alias.verify = _rc21_function(base_code, vars(alias))
        alias.reviewed_nonempty_loops = alias.verify
        _rc21_require(alias.verify.__globals__ is vars(alias))
        compare('registered-alias:' + repr(path), _rc21_frame(vars(alias), alias.verify.__code__, module='extensions/carla/map'), registration=(alias.__name__, alias))
    expected_aliases = ((oracle / 'coverage_invariant_contracts.py', 'alias_invariant', False), (oracle / 'winner_sign_contracts.py', 'alias_winner', False), (oracle / 'border_parser_contracts.py', 'alias_border', False), (root / 'tools/coverage_loop_proofs.py', 'alias_loops', False), (oracle / 'cache_key_contracts.py', None, True), (root / 'wrong/coverage_invariant_contracts.py', None, False))
    for path, operation_kind, cache_kind in expected_aliases:
        for registered in (False, True):
            alias = _rc21_types.ModuleType('_explicit_classifier_alias')
            alias.__file__ = str(path)
            alias.verify = _rc21_function(base_code, vars(alias))
            alias.reviewed_nonempty_loops = alias.verify
            _rc21_require(alias.verify.__globals__ is vars(alias))
            for include_aliases in (False, True):
                compare('explicit-alias:' + str(path) + ':' + str(registered), _rc21_frame(vars(alias), alias.verify.__code__, module='extensions/carla/map'), registration=(alias.__name__, alias) if registered else None, include_aliases=include_aliases, expected={'_operation_frame_kind': operation_kind if include_aliases else None, '_cache_verify_frame': cache_kind if include_aliases else False})
    namespace = {'__file__': str(oracle / 'coverage_invariant_contracts.py')}
    renamed = _rc21_function(base_code.replace(co_name='renamed_public_entry'), namespace)
    namespace['verify'] = renamed
    compare('renamed-matching-alias', _rc21_frame(namespace, renamed.__code__), classifiers=('_operation_frame_kind',), expected='alias_invariant')

    class ExoticWrapped:

        def __init__(self):
            self.visits = 0

        @property
        def __wrapped__(self):
            self.visits += 1
            raise ValueError('control exotic wrapper')
    for kind in ('plain', 'wrapped', 'multiwrapped', 'cyclic', 'exotic'):
        for leaf in ('coverage_invariant_contracts.py', 'cache_key_contracts.py', 'other.py'):
            namespace = {'__file__': str(oracle / leaf)}
            target = _rc21_function(base_code, namespace)
            outer = _rc21_function(base_code.replace(co_name='wrapper'), namespace)
            outer.__wrapped__ = target
            if kind == 'plain':
                value = target
            elif kind == 'wrapped':
                value = outer
            elif kind == 'multiwrapped':
                value = _rc21_function(base_code.replace(co_name='outer'), namespace)
                value.__wrapped__ = outer
            elif kind == 'cyclic':
                value = outer
                value.__wrapped__ = value
            else:
                value = ExoticWrapped()
            namespace['verify'] = value
            for classifier, matching_leaf, good in (('_operation_frame_kind', 'coverage_invariant_contracts.py', 'alias_invariant'), ('_cache_verify_frame', 'cache_key_contracts.py', True)):
                negative = None if classifier == '_operation_frame_kind' else False
                matched = leaf == matching_leaf
                expected_error = None
                if matched and kind in ('cyclic', 'exotic'):
                    expected_error = (cleanup.ContractError.__module__ + '.' + cleanup.ContractError.__qualname__, 'full-audit cleanup successor: cyclic executing function wrapper') if kind == 'cyclic' else ('builtins.ValueError', 'control exotic wrapper')
                compare('wrapper:' + kind + ':' + leaf, _rc21_frame(namespace, target.__code__), classifiers=(classifier,), expected=_rc21_UNSET if expected_error else good if matched else negative, expected_error=expected_error, preserve_path_calls=matched)
            if kind == 'exotic':
                _rc21_require(value.visits == (2 if leaf != 'other.py' else 0), (leaf, value.visits))
    namespace = {'__file__': 'relative.py'}
    namespace['verify'] = _rc21_function(base_code, namespace)
    compare('missing-cwd-relative', _rc21_frame(namespace, namespace['verify'].__code__), missing_cwd=True, expected_error=('builtins.FileNotFoundError', 'control missing cwd'), preserve_path_calls=True)
    namespace['__file__'] = str(oracle / 'other.py')
    compare('missing-cwd-relative-core', _rc21_frame(namespace, namespace['verify'].__code__), core_file='relative/core.py', missing_cwd=True, expected_error=('builtins.FileNotFoundError', 'control missing cwd'), preserve_path_calls=True)
    for core in ('relative/core.py', '/', '/.', '/..', str(after) + '/', str(after) + '/.', None, 3, ExoticString(str(after))):
        compare('core-spelling:' + repr(core), _rc21_frame(namespace, namespace['verify'].__code__), core_file=core, preserve_path_calls=True)
    compare('non-posix-fallback', _rc21_frame(namespace, namespace['verify'].__code__), os_name='nt', preserve_path_calls=True)
    for leaf in ('cache_key_contracts.py', 'other.py'):
        main_module = _rc21_types.ModuleType('__main__')
        main_module.__file__ = str(oracle / leaf)
        main_module.verify = _rc21_function(modules['cache_key_contracts'].verify.__code__, vars(main_module))
        compare('cache-main:' + leaf, _rc21_frame(vars(main_module), main_module.verify.__code__), classifiers=('_cache_verify_frame',), main_module=main_module, expected=leaf == 'cache_key_contracts.py')
    main_module = _rc21_types.ModuleType('__main__')
    main_module.__file__ = str(oracle / 'cache_key_contracts.py')
    main_module.verify = _rc21_function(modules['cache_key_contracts'].verify.__code__, vars(main_module))
    wrong_code = base_code.replace(co_name='not_the_main_verify')
    for code in (main_module.verify.__code__, wrong_code):
        compare('cache-main-invalid-core:' + code.co_name, _rc21_frame(vars(main_module), code), classifiers=('_cache_verify_frame',), main_module=main_module, core_file='/', expected_error=('builtins.ValueError', "PosixPath('/') has an empty name"), preserve_path_calls=True)
    compare('cache-main-relative-core-missing-cwd', _rc21_frame(vars(main_module), wrong_code), classifiers=('_cache_verify_frame',), main_module=main_module, core_file='relative/core.py', missing_cwd=True, expected_error=('builtins.FileNotFoundError', 'control missing cwd'), preserve_path_calls=True)
    main_module.__file__ = 'relative-main.py'
    compare('cache-main-relative-file-missing-cwd', _rc21_frame(vars(main_module), wrong_code), classifiers=('_cache_verify_frame',), main_module=main_module, missing_cwd=True, expected_error=('builtins.FileNotFoundError', 'control missing cwd'), preserve_path_calls=True)

    class CustomFlag:

        def __init__(self, sequence):
            self.sequence = sequence
            self.calls = 0

        def __bool__(self):
            item = self.sequence[min(self.calls, len(self.sequence) - 1)]
            self.calls += 1
            if item == 'raise':
                raise ValueError('control flag truthiness')
            return item
    namespace = {'__file__': str(oracle / 'cache_key_contracts.py')}
    namespace['verify'] = _rc21_function(base_code, namespace)
    candidate = _rc21_frame(namespace, namespace['verify'].__code__)
    for trailing in ('', '/'):
        namespace['__file__'] = str(oracle / 'cache_key_contracts.py') + trailing
        for label, sequence in (('truthy', (True,)), ('falsey', (False,)), ('true-false', (True, False)), ('false-true', (False, True)), ('true-raise', (True, 'raise')), ('raising', ('raise',))):
            raising = sequence[0] == 'raise'
            compare('custom-flag:' + str(trailing) + ':' + label, candidate, classifiers=('_cache_verify_frame',), flag_factory=lambda sequence=sequence: CustomFlag(sequence), expected_bool_calls=1, expected=True if sequence[0] is True else _rc21_UNSET, expected_flag_return=sequence[0] is False, expected_error=('builtins.ValueError', 'control flag truthiness') if raising else None)
    namespace['__file__'] = str(oracle / 'cache_key_contracts.py')
    for flag, cache_result in ((0, 0), (1, True), (None, None)):
        compare('builtin-nonbool-flag:' + repr(flag), candidate, include_aliases=flag, expected={'_operation_frame_kind': None, '_cache_verify_frame': cache_result})
    compare('no-frame', None, expected={'_operation_frame_kind': None, '_cache_verify_frame': False})
    _rc21_require(counts == {'cases': 291, 'equivalent': 291, 'negative_path_elisions': 6}, counts)
    _rc21_require(after.read_bytes() == new_raw, 'classifier source changed during controls')
    return counts

"""Focused lexical-only differential controls; run only after source approval.

Extract one exact helper AST from sealed bytes. Do not import any repository
module or alter a candidate. Every predicate remains active under Python -O.
"""
import ast as _rl22_ast
import builtins as _rl22_builtins
from contextlib import ExitStack as _rl22_ExitStack
import hashlib as _rl22_hashlib
import json as _rl22_json
import os as _rl22_os
import pathlib as _rl22_pathlib
from pathlib import Path as _rl22_Path, PosixPath as _rl22_PosixPath, PurePosixPath as _rl22_PurePosixPath, PureWindowsPath as _rl22_PureWindowsPath
import sys as _rl22_sys
import types as _rl22_types
from unittest.mock import patch as _rl22_patch
_rl22_HELPER_AST_SHA = 'd02f09663ba33ad79ce4f5025c317f6c7bfad2e0529286b7a31430994754835f'
_rl22_UNSET = object()
_rl22_CHECKS = 0

def _rl22_require(value, detail):
    global _rl22_CHECKS
    _rl22_CHECKS += 1
    if not value:
        raise AssertionError(detail)

def _rl22_sha(raw):
    return _rl22_hashlib.sha256(raw).hexdigest()

class _rl22_LoggedText(str):

    def __new__(cls, value, log, label, fail=False):
        obj = super().__new__(cls, value)
        obj.log, obj.label, obj.fail = (log, label, fail)
        return obj

    def __bool__(self):
        self.log.append((self.label, 'bool'))
        if self.fail is True:
            raise RuntimeError(self.label + ' text parse blocked')
        return str.__len__(self) != 0

    def __getitem__(self, key):
        label = ('slice', key.start, key.stop, key.step) if isinstance(key, slice) else key
        self.log.append((self.label, 'getitem', label))
        if self.fail == 'getitem':
            raise RuntimeError(self.label + ' splitroot blocked')
        return str.__getitem__(self, key)

    def split(self, *args, **kwargs):
        self.log.append((self.label, 'split'))
        if self.fail == 'split':
            raise RuntimeError(self.label + ' split blocked')
        return str.split(self, *args, **kwargs)

class _rl22_ForeignRoot:

    def __init__(self, log, value='/a', fail=False):
        self.log, self.value, self.fail = (log, value, fail)

    def __fspath__(self):
        self.log.append(('root', 'fspath'))
        if self.fail:
            raise RuntimeError('root fspath blocked')
        return self.value

class _rl22_LoggedPath(_rl22_PosixPath):

    def __init__(self, *args, log=None):
        super().__init__(*args)
        self.log = log if log is not None else []

    @property
    def parts(self):
        self.log.append(('path', 'parts'))
        return super().parts

    @property
    def anchor(self):
        self.log.append(('path', 'anchor'))
        return super().anchor

    def with_segments(self, *segments):
        self.log.append(('path', 'with_segments', tuple((type(x).__name__ for x in segments))))
        return type(self)(*segments, log=self.log)

    def relative_to(self, root):
        self.log.append(('path', 'relative_to'))
        return super().relative_to(root)

class _rl22_DispatchOnlyPath(_rl22_PosixPath):

    def __init__(self, *args, log=None, fail=False):
        super().__init__(*args)
        self.log, self.fail = (log, fail)

    @property
    def parts(self):
        raise AssertionError('helper inspected subclass parts')

    @property
    def anchor(self):
        raise AssertionError('helper inspected subclass anchor')

    def relative_to(self, root):
        self.log.append(('dispatch', 'relative_to', type(root).__name__))
        if self.fail:
            raise RuntimeError('custom relative_to blocked')
        return _rl22_PosixPath('custom-result')

class _rl22_RawList(list):

    def __init__(self, values, log, label):
        super().__init__(values)
        self.log, self.label = (log, label)

    def __iter__(self):
        self.log.append((self.label, 'raw-list-iter'))
        return super().__iter__()

def _rl22_describe(value):
    if isinstance(value, _rl22_pathlib.PurePath):
        return ('value', type(value), str(value), value.parts)
    return ('value', type(value), value)

def _rl22_invoke(call, helper, fast_line, fallback_line):
    """Deny filesystem observations only around this one reference/helper call."""
    events, blocked = ([], [])
    old_trace = _rl22_sys.gettrace()
    _rl22_require(old_trace is None, 'unexpected existing trace callback')

    def trace(frame, event, arg):
        if frame.f_code is helper.__code__:
            if event == 'line' and frame.f_lineno in (fast_line, fallback_line):
                events.append('fast' if frame.f_lineno == fast_line else 'fallback')
            return trace
        return None

    def deny(*args, **kwargs):
        blocked.append('filesystem surface')
        raise AssertionError('filesystem surface called')
    with _rl22_ExitStack() as stack:
        for name in ('stat', 'lstat', 'resolve', 'cwd', 'absolute', 'open', 'read_bytes', 'read_text', 'iterdir', 'glob', 'rglob', 'walk'):
            stack.enter_context(_rl22_patch.object(_rl22_Path, name, deny))
        for name in ('stat', 'lstat', 'getcwd', 'listdir', 'scandir', 'readlink', 'open', 'access'):
            stack.enter_context(_rl22_patch.object(_rl22_os, name, deny))
        stack.enter_context(_rl22_patch.object(_rl22_builtins, 'open', deny))
        _rl22_sys.settrace(trace)
        try:
            try:
                value = call()
            except Exception as error:
                result = ('exception', type(error), str(error))
            else:
                result = value
        finally:
            _rl22_sys.settrace(old_trace)
    _rl22_require(not blocked, 'reference/helper attempted filesystem observation')
    if not (type(result) is tuple and result and (result[0] == 'exception')):
        result = _rl22_describe(result)
    return (result, events)

def _rl22_ordinary(path, root, path_type=_rl22_PosixPath, root_type=_rl22_PosixPath):

    def factory(log):
        return (path_type(path), root_type(root))
    return factory

def _rl22_exotic_text(path_exotic=False, root_exotic=False, preparse=False, fail_path=False, fail_root=False):

    def factory(log):
        p = _rl22_LoggedText('/a/b', log, 'path', fail_path) if path_exotic else '/a/b'
        r = _rl22_LoggedText('/a', log, 'root', fail_root) if root_exotic else '/a'
        path, root = (_rl22_PosixPath(p), _rl22_PosixPath(r))
        if preparse:
            root.parts
            path.parts
        log.clear()
        return (path, root)
    return factory

def _rl22_foreign_root(value='/a', fail=False):
    return lambda log: (_rl22_PosixPath('/a/b'), _rl22_ForeignRoot(log, value, fail))

def _rl22_raw_layout(which, layout):

    def factory(log):
        path, root = (_rl22_PosixPath('/a/b'), _rl22_PosixPath('/a'))
        target = root if which == 'root' else path
        if layout == 'missing':
            del target._raw_paths
        elif layout == 'tuple':
            target._raw_paths = tuple(target._raw_paths)
        elif layout == 'list-subclass':
            target._raw_paths = _rl22_RawList(target._raw_paths, log, which)
        elif layout == 'non-string':
            target._raw_paths = [17]
        else:
            raise AssertionError('unknown private layout case')
        return (path, root)
    return factory

def _rl22_main():
    global _rl22_CHECKS
    _rl22_CHECKS = 0
    cleanup = _reviewed_mechanics_module('full_audit_cleanup_contracts')
    source_path = _rl22_Path(cleanup.__file__)
    source_raw = source_path.read_bytes()
    tree = _rl22_ast.parse(source_raw.decode('utf-8'), filename=str(source_path))
    matches = [n for n in tree.body if isinstance(n, _rl22_ast.FunctionDef) and n.name == '_relative_path']
    _rl22_require(len(matches) == 1, 'one live helper definition')
    node = matches[0]
    _rl22_require(_rl22_sha(_rl22_ast.dump(node, include_attributes=False).encode()) == _rl22_HELPER_AST_SHA, 'reviewed relative helper AST identity')
    compiled = compile(source_raw, str(source_path), 'exec', dont_inherit=True, optimize=_rl22_sys.flags.optimize)
    codes = [code for code in compiled.co_consts if isinstance(code, _rl22_types.CodeType) and code.co_name == '_relative_path']
    helper = cleanup._relative_path
    _rl22_require(len(codes) == 1 and codes[0] == helper.__code__, 'live helper checked-source binding')
    stdlib_path = _rl22_Path(_rl22_pathlib.__file__)
    stdlib_raw = stdlib_path.read_bytes()
    compiled_stdlib = compile(stdlib_raw, str(stdlib_path), 'exec', dont_inherit=True, optimize=_rl22_sys.flags.optimize)
    pending, reference_codes = ([compiled_stdlib], [])
    while pending:
        code = pending.pop()
        if code.co_qualname == 'PurePath.relative_to':
            reference_codes.append(code)
        pending.extend((value for value in code.co_consts if isinstance(value, _rl22_types.CodeType)))
    _rl22_require(len(reference_codes) == 1 and reference_codes[0] == _rl22_pathlib.PurePath.relative_to.__code__, 'live reference equals current checked pathlib source')
    returns = [n for n in _rl22_ast.walk(node) if isinstance(n, _rl22_ast.Return)]
    fast = [n for n in returns if isinstance(n.value, _rl22_ast.Call) and isinstance(n.value.func, _rl22_ast.Name) and (n.value.func.id == 'PosixPath')]
    fallback = [n for n in returns if isinstance(n.value, _rl22_ast.Call) and isinstance(n.value.func, _rl22_ast.Attribute) and (n.value.func.attr == 'relative_to')]
    _rl22_require(len(returns) == 2 and len(fast) == len(fallback) == 1, 'exact return branches')
    records, totals = ([], {'fast': 0, 'fallback': 0})

    def compare(name, factory, branch, *, expected=_rl22_UNSET, error_type=None, first_callback=None, minimum_callbacks=0, exact_log=None, platform='posix'):
        old_log, new_log = ([], [])
        old_args, new_args = (factory(old_log), factory(new_log))
        _rl22_require(old_log == new_log, (name, 'independent fixture construction'))
        call_helper = helper
        if platform != _rl22_os.name:
            namespace = dict(helper.__globals__)
            namespace['os'] = _rl22_types.SimpleNamespace(name=platform)
            call_helper = _rl22_types.FunctionType(helper.__code__, namespace, helper.__name__)
            _rl22_require(call_helper.__code__ is helper.__code__, 'simulated platform uses live helper code')
        old, old_events = _rl22_invoke(lambda: old_args[0].relative_to(old_args[1]), helper, fast[0].lineno, fallback[0].lineno)
        new, new_events = _rl22_invoke(lambda: call_helper(*new_args), helper, fast[0].lineno, fallback[0].lineno)
        _rl22_require(old == new, (name, 'result/type/exception mismatch', old, new))
        _rl22_require(new[0] == ('value' if error_type is None else 'exception'), (name, 'explicit success/exception route', new))
        _rl22_require(old_log == new_log, (name, 'callback order/count mismatch', old_log, new_log))
        _rl22_require(old_events == [], (name, 'reference unexpectedly entered proposal'))
        _rl22_require(new_events == [branch], (name, 'actual helper branch', new_events, branch))
        _rl22_require(len(new_log) >= minimum_callbacks, (name, 'callback route not exercised'))
        if first_callback is not None:
            _rl22_require(bool(new_log) and new_log[0][0] == first_callback, (name, 'first parsing callback', new_log))
        if exact_log is not None:
            _rl22_require(new_log == exact_log, (name, 'explicit callback route', new_log))
        if expected is not _rl22_UNSET:
            _rl22_require(new[0] == 'value' and new[1] is _rl22_PosixPath and (new[2] == expected), (name, 'explicit successful result', new, expected))
        if error_type is not None:
            _rl22_require(new[0] == 'exception' and new[1] is error_type, (name, 'explicit exception route', new, error_type))
        totals[branch] += 1
        records.append({'case': name, 'branch': branch, 'outcome': new[0], 'type': new[1].__module__ + '.' + new[1].__qualname__, 'detail': new[2], 'callbacks': new_log})
    successes = [('equal', '/a', '/a', '.'), ('root-equal', '/', '/', '.'), ('root', '/a/b', '/', 'a/b'), ('nested', '/a/b/c', '/a', 'b/c'), ('dotfiles', '/a/.dot', '/a', '.dot'), ('unicode', '/a/é/漢', '/a', 'é/漢'), ('spaces', '/a/a b', '/a', 'a b'), ('case-retained', '/a/A', '/a', 'A'), ('nul', '/a/\x00x', '/a', '\x00x'), ('slashes-dots', '/a//./b///c/', '/a/.', 'b/c'), ('triple-anchor', '///a/b', '///a', 'b'), ('backslash-name', '/a/x\\y', '/a', 'x\\y'), ('colon-name', '/a/C:', '/a', 'C:'), ('prefix-root', '/a/ab', '/a', 'ab')]
    for name, path, root, expected in successes:
        compare(name, _rl22_ordinary(path, root), 'fast', expected=expected)
    components = ('a', 'ab', 'A', '.hidden', 'é', 'space x', '\x00x')
    for root_part in components:
        for leaf in components:
            compare('components:' + repr((root_part, leaf)), _rl22_ordinary('/' + root_part + '/' + leaf, '/' + root_part), 'fast', expected=leaf)
    for name, path, root, succeeds in [('sibling-prefix', '/ab/x', '/a', False), ('deeper-root', '/a', '/a/b', False), ('outside', '/b/x', '/a', False), ('case-mismatch', '/A/x', '/a', False), ('relative', 'a/b', 'a', True), ('relative-empty', '', '', True), ('relative-dot', './a/b', '.', True), ('mixed-path', 'a/b', '/a', False), ('mixed-root', '/a/b', 'a', False), ('double-slash', '//a/b', '//a', True), ('double-mixed', '//a/b', '/a', False), ('path-dotdot', '/a/../b', '/a', True), ('root-dotdot', '/a/../b', '/a/..', True), ('windows-looking', 'C:\\a\\b', 'C:\\a', False), ('windows-slashes', 'C:/a/b', 'C:/a', True)]:
        compare(name, _rl22_ordinary(path, root), 'fallback', error_type=None if succeeds else ValueError)
    compare('platform-fallback', _rl22_ordinary('/a/b', '/a'), 'fallback', expected='b', platform='nt')
    compare('pure-posix', _rl22_ordinary('/a/b', '/a', _rl22_PurePosixPath, _rl22_PurePosixPath), 'fallback')
    compare('pure-windows', _rl22_ordinary('C:/a/b', 'C:/a', _rl22_PureWindowsPath, _rl22_PureWindowsPath), 'fallback')
    compare('windows-foreign-root', _rl22_ordinary('/a/b', 'C:/a', _rl22_PosixPath, _rl22_PureWindowsPath), 'fallback', error_type=ValueError)
    compare('str-root', lambda log: (_rl22_PosixPath('/a/b'), '/a'), 'fallback', expected='b')
    compare('invalid-root', lambda log: (_rl22_PosixPath('/a/b'), 17), 'fallback', error_type=TypeError)
    compare('pathlike-root', _rl22_foreign_root(), 'fallback', expected='b', exact_log=[('root', 'fspath')])
    compare('pathlike-raising', _rl22_foreign_root(fail=True), 'fallback', error_type=RuntimeError, exact_log=[('root', 'fspath')])
    compare('pathlike-invalid-result', _rl22_foreign_root(value=b'/a'), 'fallback', error_type=TypeError, exact_log=[('root', 'fspath')])
    compare('subclass-normal', lambda log: (_rl22_LoggedPath('/a/b', log=log), _rl22_PosixPath('/a')), 'fallback', first_callback='path', minimum_callbacks=2)
    compare('subclass-root', lambda log: (_rl22_PosixPath('/a/b'), _rl22_LoggedPath('/a', log=log)), 'fallback', expected='b', exact_log=[])
    compare('subclass-dispatch', lambda log: (_rl22_DispatchOnlyPath('/a/b', log=log), _rl22_ForeignRoot(log)), 'fallback', expected='custom-result', exact_log=[('dispatch', 'relative_to', '_rl22_ForeignRoot')])
    compare('subclass-raising', lambda log: (_rl22_DispatchOnlyPath('/a/b', log=log, fail=True), _rl22_PosixPath('/a')), 'fallback', error_type=RuntimeError, exact_log=[('dispatch', 'relative_to', 'PosixPath')])
    for path_exotic, root_exotic in ((True, False), (False, True), (True, True)):
        for preparse in (False, True):
            name = 'str-subclass:' + repr((path_exotic, root_exotic, preparse))
            first = 'root' if root_exotic else 'path' if not preparse else None
            compare(name, _rl22_exotic_text(path_exotic, root_exotic, preparse), 'fallback', expected='b', first_callback=first, minimum_callbacks=1 if first else 0)
    for fail_path, fail_root in ((True, False), (False, True), (True, True)):
        compare('str-raising:' + repr((fail_path, fail_root)), _rl22_exotic_text(True, True, fail_path=fail_path, fail_root=fail_root), 'fallback', error_type=RuntimeError, first_callback='root', minimum_callbacks=1)
    for stage in ('getitem', 'split'):

        def late_parser(log, stage=stage):
            absolute = stage == 'getitem'
            path = _rl22_PosixPath('/a/b' if absolute else 'a/b')
            root = _rl22_PosixPath(_rl22_LoggedText('/a' if absolute else 'a', log, 'root', stage))
            return (path, root)
        compare('late-parser-raising:' + stage, late_parser, 'fallback', error_type=RuntimeError, first_callback='root', minimum_callbacks=2)
    for which in ('root', 'path'):
        for layout in ('missing', 'tuple', 'list-subclass', 'non-string'):
            compare('layout:' + which + ':' + layout, _rl22_raw_layout(which, layout), 'fallback', error_type=AttributeError if layout == 'missing' else TypeError if layout == 'non-string' else None)
    _rl22_require(totals['fast'] == len(successes) + len(components) ** 2, 'all expected fast cases')
    _rl22_require(totals['fallback'] == 47, 'all expected fallback cases')
    _rl22_require(sum(totals.values()) == len(records), 'all cases have explicit branch evidence')
    _rl22_require(source_path.read_bytes() == source_raw, 'helper source changed during controls')
    _rl22_require(stdlib_path.read_bytes() == stdlib_raw, 'reference source changed during controls')
    return {'cases': len(records), 'branch_counts': totals}

class ReviewedClassifierMechanics(_rm_unittest.TestCase):
    def test_reviewed_exact_guard_projection_and_291_cases(self):
        if _rm_os.name != 'posix':
            self.skipTest('The reviewed filename/error matrix is POSIX-specific.')
        result = _rc21_main()
        self.assertEqual(result, {'cases': 291, 'equivalent': 291, 'negative_path_elisions': 6})


class ReviewedRelativePathMechanics(_rm_unittest.TestCase):
    def test_reviewed_110_cases_on_supported_posix_layout(self):
        if _rm_os.name != 'posix':
            self.skipTest('The 110 reviewed fixture cases use concrete POSIX paths.')
        probe = _rm_PosixPath('/a')
        raw = getattr(probe, '_raw_paths', None)
        if type(raw) is not list or not all(type(piece) is str for piece in raw):
            self.skipTest('Private-layout fixtures are unavailable; native fallback is tested separately.')
        result = _rl22_main()
        self.assertEqual(result, {'cases': 110, 'branch_counts': {'fast': 63, 'fallback': 47}})

    def test_native_path_fallback_without_layout_requirement(self):
        cleanup = _reviewed_mechanics_module('full_audit_cleanup_contracts')
        old_path, old_root = _rm_Path('a/b'), _rm_Path('a')
        new_path, new_root = _rm_Path('a/b'), _rm_Path('a')
        old, new = old_path.relative_to(old_root), cleanup._relative_path(new_path, new_root)
        self.assertIs(type(new), type(old))
        self.assertEqual((str(new), new.parts), (str(old), old.parts))
        self.assertEqual(str(new), 'b')


# Exact reviewed consumed-value boundaries only. Source spans are derived at runtime.
# Tuple: module, original owner, physical expression, expected count, selections.
# Each selection is (index, legacy site suffix, comparator mode, narrow binding kind).
_OPERATION_REACHED_READ_SPECS = (
    ('tools/carla_lane_oracle/coverage_invariant_contracts.py', 'verify',
     '(root / path).read_text()', 1, ((0, '81:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/coverage_followup_contracts.py', 'verify',
     '(root / path).read_text()', 1, ((0, '84:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/accepted_successor_contracts.py', '_verify_current',
     '(root / path).read_text()', 1, ((0, '56:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/accepted_successor_contracts.py', '_verify_current_for_pin_pair',
     '(root / path).read_text()', 1, ((0, '117:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/accepted_successor_contracts.py', '_read_current_pair_pin',
     'full_audit._regular(root, relative).read_bytes()', 1, ((0, '166:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_lane_observation',
     'path.read_text()', 1, ((0, '36:1', 'supplied_physical', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_lane_observation',
     'path.read_bytes()', 1, ((0, '37:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_premises',
     '(root / path).read_text()', 1, ((0, '56:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_premises',
     '(root / name).read_text()', 2, ((0, '59:1', 'default', 'observe'), (1, '71:1', 'default', 'observe'))),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_premises',
     'physical.read_bytes()', 1, ((0, '92:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_premises',
     'physical.read_text()', 1, ((0, '98:1', 'supplied_physical', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_premises',
     "(root / item['path']).read_text()", 2, ((0, '106:1', 'default', 'observe'), (1, '118:1', 'default', 'observe'))),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_premises',
     'full_audit._regular(root, name).read_bytes()', 1, ((0, '124:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify',
     "(root / record['path']).read_text()", 1, ((0, '135:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_for_pin_pair',
     "(root / record['path']).read_text()", 1, ((0, '143:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/distance_validation_contracts.py', 'verify',
     '(root / MODULE).read_text()', 1, ((0, '18:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/distance_validation_contracts.py', 'verify',
     "(root / 'extensions/carla/curve_interval.mojo').read_text()", 1, ((0, '18:2', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/grouped_y_finiteness_contracts.py', 'verify',
     '(root / p).read_text()', 1, ((0, '26:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/curve_support_dispatch_contracts.py', 'reviewed_source',
     '(root / path).read_text()', 1, ((0, '43:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/curve_support_dispatch_contracts.py', 'verify_premises',
     '(root / path).read_text()', 1, ((0, '68:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/curve_support_dispatch_contracts.py', 'verify_premises',
     "(root / item['path']).read_text()", 2, ((0, '71:1', 'default', 'observe'), (1, '98:1', 'default', 'observe'))),
    ('tools/carla_lane_oracle/raw_cut_inverse_contracts.py', 'verify_premises',
     '(root / SOURCE_PATH).read_text()', 1, ((0, '47:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/raw_cut_inverse_contracts.py', 'verify_premises',
     "(root / 'extensions/carla/curve_sum2.mojo').read_text()", 1, ((0, '49:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/raw_cut_inverse_contracts.py', 'verify_premises',
     "(root / 'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_text()", 1, ((0, '53:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/raw_cut_inverse_contracts.py', 'verify_premises',
     "(root / 'tests/test_carla_raw_cut_successor.mojo').read_text()", 1, ((0, '57:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/raw_cut_inverse_contracts.py', 'verify_premises',
     "(root / 'tests/test_carla_support_dispatch_successor.mojo').read_text()", 1, ((0, '59:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/raw_cut_inverse_contracts.py', 'verify',
     '(root / SOURCE_PATH).read_text()', 1, ((0, '68:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/moment_finiteness_contracts.py', 'verify',
     '(root / MODULE).read_text()', 1, ((0, '39:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/moment_finiteness_contracts.py', 'verify',
     '(root / INTERVAL).read_text()', 1, ((0, '39:2', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/moment_finiteness_contracts.py', 'verify',
     "(root / 'extensions/carla/geometry.mojo').read_text()", 1, ((0, '39:3', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/moment_finiteness_contracts.py', 'verify',
     "(root / 'extensions/carla/curve_trig.mojo').read_text()", 1, ((0, '39:4', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/envelope_budget_contracts.py', 'verify',
     '(Path(root) / MODULE).read_text()', 1, ((0, '35:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_order_contracts.py', 'inventory',
     'path.read_text()', 1, ((0, '45:1', 'default_or_map_supplied', 'observe'),)),
    ('tools/carla_lane_oracle/lane_order_contracts.py', 'inventory',
     'path.read_bytes()', 2, ((0, '55:1', 'bytes', 'observe'), (1, '65:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/lane_order_contracts.py', 'verify',
     "(root / record['module']).read_text()", 1, ((0, '83:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_order_contracts.py', 'verify',
     '(root / rel).read_text()', 1, ((0, '87:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_order_contracts.py', 'verify',
     "(root / 'tests/test_carla_lane_order_successor.mojo').read_text()", 1, ((0, '93:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_control_contracts.py', 'verify',
     "(root / record['module']).read_text()", 1, ((0, '34:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_control_contracts.py', 'verify',
     "(root / 'tests/test_carla_lane_control_successor.mojo').read_text()", 1, ((0, '50:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_control_contracts.py', 'verify',
     "(root / item['path']).read_text()", 1, ((0, '56:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_control_contracts.py', 'verify',
     '(root / rel).read_text()', 1, ((0, '60:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/selection_finiteness_contracts.py', '_producer_text',
     '(root / path).read_text()', 1, ((0, '40:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/selection_finiteness_contracts.py', 'verify',
     "(root / 'extensions/carla/curve_interval.mojo').read_text()", 1, ((0, '53:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/selection_finiteness_contracts.py', 'verify',
     "(root / 'extensions/carla/curve_trig.mojo').read_text()", 1, ((0, '53:2', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/grouped_table_contracts.py', 'verify',
     '(root / MODULE).read_text()', 1, ((0, '38:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/grouped_table_contracts.py', 'verify',
     "(root / 'extensions/carla/geometry.mojo').read_text()", 1, ((0, '45:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/cache_key_contracts.py', 'inventory',
     'path.read_text()', 2, ((1, '89:1', 'supplied_default', 'local_s'),)),
    ('tools/carla_lane_oracle/cache_key_contracts.py', 'inventory',
     '_inputs.observe_bytes(_input_owner, root, rel.as_posix())', 2, ((0, '92:1', 'bytes', 'lease'), (1, '132:1', 'bytes', 'lease'))),
    ('tools/carla_lane_oracle/cache_key_contracts.py', 'verify',
     '(root / MODULE).read_text()', 1, ((0, '179:1', 'supplied_default', 'observe'),)),
    ('tools/carla_lane_oracle/cache_key_contracts.py', 'reviewed_text',
     '(Path(root) / MODULE).read_text()', 1, ((0, '229:1', 'supplied_default', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'dependency_inventory',
     '(root / name).read_bytes()', 2, ((1, '303:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_score_caller_inventory',
     'path.read_text()', 2, ((1, '484:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_score',
     '(root / MODULE).read_bytes()', 4, ((1, '541:1', 'bytes', 'observe'), (3, '563:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_score',
     '_inputs.observe_bytes(_input_owner, root, MODULE)', 2, ((0, '542:1', 'bytes', 'lease'), (1, '564:1', 'bytes', 'lease'))),
    ('tools/carla_lane_oracle/seed_count_contracts.py', '_verify_bound_inputs',
     '(root / path).read_bytes()', 4, ((1, '592:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_premises',
     '(root / path).read_bytes()', 8, ((1, '648:1', 'bytes', 'observe'), (3, '659:1', 'bytes', 'observe'), (5, '678:1', 'bytes', 'observe'), (7, '684:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_premises',
     '(root / MODULE).read_bytes()', 2, ((1, '689:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify',
     '(root / MODULE).read_bytes()', 4, ((1, '709:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'reviewed_text',
     '(Path(root) / MODULE).read_bytes()', 4, ((1, '754:1', 'bytes', 'observe'), (3, '766:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', '_CacheInputs.observe_bytes',
     '_regular(root, path).read_bytes()', 1, ((0, '1003:1', 'bytes', 'base'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', '_cache_lane_inputs',
     '_regular(root, path).read_bytes()', 1, ((0, '1097:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', '_reviewed_lane_observation',
     '_regular(root, road).read_bytes()', 1, ((0, '1244:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/border_parser_contracts.py', 'verify',
     '(root / MODULE).read_bytes()', 1, ((0, '156:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/border_parser_contracts.py', 'verify',
     '(root / path).read_bytes()', 3, ((0, '163:1', 'bytes', 'observe'), (1, '170:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/frozen_arc_producer_contracts.py', 'verify_premises',
     "(root / item['path']).read_text()", 1, ((0, '81:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/frozen_arc_producer_contracts.py', 'verify_premises',
     "(root / 'extensions/carla/curve_rounded_arc.mojo').read_text()", 1, ((0, '85:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/frozen_arc_producer_contracts.py', 'verify',
     '(root / SOURCE_PATH).read_text()', 1, ((0, '96:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/frozen_arc_producer_contracts.py', 'verify',
     '(root / path).read_text()', 1, ((0, '104:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'reviewed_sum2_callers',
     'physical.read_bytes()', 1, ((0, '1289:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'reviewed_sum2_callers',
     "physical.read_text(encoding='utf-8')", 1, ((0, '1291:1', 'supplied_physical', 'observe'),)),
    ('tools/carla_lane_oracle/render_actor_reuse_contracts.py', 'verify',
     '(root / path).read_bytes()', 2, ((0, '47:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/reviewed_cleanup_contracts.py', 'verify_premises',
     '(root / SOURCE_PATHS[0]).read_text()', 1, ((0, '103:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/reviewed_cleanup_contracts.py', 'verify_premises',
     '(root / SOURCE_PATHS[1]).read_text()', 1, ((0, '104:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/reviewed_cleanup_contracts.py', 'verify_premises',
     '(root / SOURCE_PATHS[2]).read_text()', 1, ((0, '105:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/reviewed_cleanup_contracts.py', 'verify',
     '(root / path).read_text()', 2, ((0, '252:1', 'default', 'observe'), (1, '266:1', 'default', 'observe'))),
    ('tools/carla_lane_oracle/runtime_boundary_contracts.py', 'verify',
     '(root / path).read_bytes()', 2, ((0, '54:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'historical_source',
     '(root / MODULE).read_bytes()', 2, ((0, '731:1', 'bytes', 'observe'), (1, '737:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/source_contracts.py', 'read_pins',
     "(root / PINS).read_text(encoding='utf-8')", 1, ((0, '180:1', 'physical', 'observe'),)),
    ('tools/carla_lane_oracle/source_contracts.py', 'verify_group',
     "(root / path).read_text(encoding='utf-8')", 1, ((0, '207:1', 'physical', 'observe'),)),
    ('tools/carla_lane_oracle/speed_parser_contracts.py', 'verify',
     '(root / MODULE).read_text()', 1, ((0, '35:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_guard_contracts.py', 'protected_inventory',
     'path.read_text()', 1, ((0, '148:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_guard_contracts.py', 'verify',
     '(root / PINS).read_text()', 1, ((0, '311:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_guard_contracts.py', 'verify',
     "(root / 'extensions/carla/curve_sum2.mojo').read_text()", 1, ((0, '331:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_guard_contracts.py', 'verify',
     '(root / path).read_text()', 1, ((0, '359:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_guard_contracts.py', 'verify',
     '(root / path).read_bytes()', 1, ((0, '384:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/winner_sign_contracts.py', 'verify',
     "(root / 'extensions/carla/map.mojo').read_bytes()", 1, ((0, '71:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/winner_sign_contracts.py', 'verify',
     '(root / path).read_bytes()', 2, ((0, '175:1', 'bytes', 'observe'), (1, '195:1', 'bytes', 'observe'))),
    ('tools/coverage_loop_proofs.py', 'file_sha256',
     "Path(path).open('rb')", 1, ((0, '156:1', 'stream_open', 'stream_open'),)),
    ('tools/coverage_loop_proofs.py', 'file_sha256',
     'stream.read(1 << 20)', 1, ((0, '157:1', 'stream_read', 'stream_read'),)),
    ('tools/coverage_loop_proofs.py', '_reviewed_dependency_hashes',
     'path.read_bytes()', 3, ((0, '798:1', 'bytes', 'observe'), (2, '828:1', 'bytes', 'observe'))),
    ('tools/coverage_loop_proofs.py', '_historical_reviewed_nonempty_loops',
     'relative_source(root, path.as_posix(), **operation_args).read_text()', 1, ((0, '853:1', 'default', 'observe'),)),
    ('tools/coverage_loop_proofs.py', '_construction_boundary_callers',
     'relative_source(root, path.as_posix(), **operation_args).read_text()', 1, ((0, '1029:1', 'default', 'observe'),)),
)


@contextmanager
def _operation_reached_bindings(case, code_root, physical_root, cores):
    """Observe reviewed read/comparison seams without changing their values.

    This is one bounded test-local ledger, not a replacement filesystem or
    authority. Frames, objects and stream chunks are kept until this one owner
    finishes; no object-id-only association or extra source sample is used.
    """
    from contextlib import ExitStack
    from functools import wraps
    import types

    sites, trees, compiled_modules, positions, families = {}, {}, {}, {}, {}
    for relative, owner, expression, expected_count, selections in _OPERATION_REACHED_READ_SPECS:
        filename = str((Path(code_root)/relative).absolute())
        if filename not in trees:
            source_raw = Path(filename).read_bytes()
            trees[filename] = ast.parse(source_raw, filename=filename)
            compiled_modules[filename] = compile(source_raw, filename, 'exec',
                dont_inherit=True, optimize=sys.flags.optimize)
        node = trees[filename]
        for component in owner.split('.'):
            matches = [item for item in node.body if getattr(item, 'name', None) == component]
            case.assertEqual(len(matches), 1, (relative, owner))
            node = matches[0]
        key = ast.dump(ast.parse(expression, mode='eval').body, include_attributes=False)
        calls = sorted((item for item in ast.walk(node) if isinstance(item, ast.Call)
                        and ast.dump(item, include_attributes=False) == key),
                       key=lambda item: (item.lineno, item.col_offset))
        case.assertEqual(len(calls), expected_count, (relative, owner, expression))
        for index, suffix, mode, binding in selections:
            call = calls[index]
            if mode == 'default_or_map_supplied':
                case.assertEqual((relative, owner),
                    ('tools/carla_lane_oracle/lane_order_contracts.py', 'inventory'))
                parents = {child: parent for parent in ast.walk(node)
                           for child in ast.iter_child_nodes(parent)}
                observation = parents[call]
                case.assertIsInstance(observation, ast.Call)
                case.assertIsInstance(observation.func, ast.Name)
                case.assertEqual(observation.func.id, '_observe_text')
                supplied = [keyword.value for keyword in observation.keywords
                            if keyword.arg == 'supplied']
                case.assertEqual(len(supplied), 1)
                case.assertEqual(ast.dump(supplied[0], include_attributes=False),
                    ast.dump(ast.parse("rel.as_posix() == 'extensions/carla/map.mojo'",
                                       mode='eval').body, include_attributes=False))
            span = (call.lineno, call.end_lineno, call.col_offset, call.end_col_offset)
            case.assertNotIn((filename, span), sites)
            sites[filename, span] = (relative + ':' + suffix, owner, mode, binding)

    # The one retained local-S comparator is deliberately not treated as a
    # generic _observe call. Keep its exact original chained predicate.
    cache_filename = str((Path(code_root)/'tools/carla_lane_oracle/cache_key_contracts.py').absolute())
    cache_tree = trees[cache_filename]
    inventory_node = next(item for item in cache_tree.body
                          if isinstance(item, ast.FunctionDef) and item.name == 'inventory')
    local_predicate = ast.parse(
        'source.token_sha256(text) == source.token_sha256('
        '_inputs.text_default(_input_owner, root, rel.as_posix())) '
        '== seed_count.SCORE_AFTER_TOKEN_SHA256', mode='eval').body
    predicate_key = ast.dump(local_predicate, include_attributes=False)
    guarded_comparisons = [item for item in ast.walk(inventory_node)
        if isinstance(item, ast.Call) and isinstance(item.func, ast.Name)
        and item.func.id == 'require' and len(item.args) == 2
        and ast.dump(item.args[0], include_attributes=False) == predicate_key
        and isinstance(item.args[1], ast.Constant)
        and item.args[1].value == 'unreviewed supplied score-helper source']
    case.assertEqual(len(guarded_comparisons), 1)
    local_call = guarded_comparisons[0].args[0].left
    local_span = (local_call.lineno, local_call.end_lineno,
                  local_call.col_offset, local_call.end_col_offset)

    reads, streams, observation_events, match_events, primitive_entries = [], [], [], [], []
    boundary_entries = []
    leases = []
    read_index, stream_index = {}, {}
    operation_types = tuple(core._InvariantInputs for core in cores)
    lease_types = tuple(core._BorrowedCacheInputs for core in cores)

    def span(frame):
        code = frame.f_code
        if code not in positions:
            positions[code] = tuple(code.co_positions())
        index = frame.f_lasti // 2
        return positions[code][index] if 0 <= index < len(positions[code]) else None

    def original_family(frame, owner):
        key = (id(frame.f_globals), owner)
        if key not in families:
            components = owner.split('.')
            function = frame.f_globals.get(components[0])
            for component in components[1:]:
                function = getattr(function, component, None)
            function = inspect.unwrap(function)
            case.assertIs(getattr(function, '__globals__', None), frame.f_globals)
            filename = str(Path(frame.f_globals['__file__']).absolute())
            compiled_owner = compiled_modules[filename]
            for component in components:
                matches = [value for value in compiled_owner.co_consts
                           if isinstance(value, types.CodeType) and value.co_name == component]
                case.assertEqual(len(matches), 1, ('unique checked-source owner', filename, owner))
                compiled_owner = matches[0]
            case.assertEqual(function.__code__, compiled_owner,
                             ('live original equals checked source', filename, owner))
            pending, codes = [function.__code__], set()
            while pending:
                code = pending.pop()
                codes.add(code)
                pending.extend(value for value in code.co_consts if isinstance(value, types.CodeType))
            families[key] = codes
        return families[key]

    def site(frame):
        filename = frame.f_globals.get('__file__')
        if type(filename) is not str:
            return None
        filename = str(Path(filename).absolute())
        found = sites.get((filename, span(frame)))
        if found is None:
            return None
        case.assertIn(frame.f_code, original_family(frame, found[1]), found[0])
        return found

    def operation_at(frame, found):
        # A comprehension may hold root/path but not the explicit operation.
        # Only walk within this exact original function's nested code family.
        allowed = original_family(frame, found[1])
        namespace = frame.f_globals
        while frame is not None and frame.f_globals is namespace and frame.f_code in allowed:
            values = frame.f_locals
            if '_operation' in values:
                value = values['_operation']
                if type(value) in operation_types:
                    return value
                if value is not None:
                    return None
            view = values.get('_inputs', values.get('self'))
            if type(view) in lease_types:
                return view._operation
            if type(view) in operation_types:
                return view
            frame = frame.f_back
        return None

    def relative(path):
        return Path(path).relative_to(physical_root).as_posix()

    def caller_chain(frame):
        result = []
        while frame is not None:
            filename = frame.f_globals.get('__file__')
            if type(filename) is str:
                filename = str(Path(filename).absolute())
                if filename in trees:
                    result.append((Path(filename).relative_to(code_root).as_posix(),
                                   frame.f_code.co_qualname, frame.f_lineno))
            frame = frame.f_back
        return result

    def lease_number(view):
        for index, previous in enumerate(leases):
            if previous is view:
                return index
        case.assertIn(type(view), lease_types)
        leases.append(view)
        return len(leases) - 1

    def record_read(found, operation, path, value, frame, phase=None):
        name = relative(path)
        mode = found[2]
        if mode == 'default_or_map_supplied':
            mode = 'supplied_default' if name == 'extensions/carla/map.mojo' else 'default'
        item = {'site': found[0], 'mode': mode, 'binding': found[3],
                'operation': operation, 'path': name, 'value': value,
                'frame': frame, 'code': frame.f_code, 'globals': frame.f_globals,
                'owner': found[1], 'span': span(frame),
                'phase': phase or operation._state, 'sequence': len(reads),
                'observed': False, 'matched': False, 'local_compared': False}
        if found[3] in ('local_s', 'lease'):
            item['caller_chain'] = caller_chain(frame)
        if found[3] == 'local_s':
            item['lease_number'] = lease_number(frame.f_locals['_inputs'])
        reads.append(item)
        read_index[id(operation), item['path'], item['mode'], id(value)] = item
        return item

    def latest(operation, path, value, mode):
        item = read_index.get((id(operation), path, mode, id(value)))
        # The index accelerates a reference comparison; the retained objects,
        # not their recyclable ids, establish the actual association.
        return item if item is not None and item['operation'] is operation and item['value'] is value else None

    def joined_stream(operation, path, value):
        item = stream_index.get((id(operation), path))
        if (item is not None and item['operation'] is operation and item['eof']
                and type(value) is bytes and value == item['composed']):
            frame = sys._getframe(1)
            while frame is not None:
                if frame is item['owner_frame']:
                    return item
                frame = frame.f_back
        return None

    def reader(original):
        @wraps(original)
        def read(path, *args, **kwargs):
            frame = sys._getframe(1)
            found = site(frame)
            operation = operation_at(frame, found) if found is not None else None
            if operation is not None:
                entry = {'frame': frame, 'operation': operation, 'site': found[0], 'returned': False}
                primitive_entries.append(entry)
            value = original(path, *args, **kwargs)
            if operation is not None:
                case.assertIn(found[3], ('observe', 'local_s', 'base'))
                entry['returned'] = True
                record_read(found, operation, path, value, frame)
            return value
        return read

    def observer(original):
        @wraps(original)
        def observed(operation, root, path, value, mode):
            item = latest(operation, path, value, mode)
            stream = joined_stream(operation, path, value) if mode == 'bytes' else None
            phase = operation._state
            event = {'operation': operation, 'path': path, 'mode': mode, 'phase': phase,
                     'read_sequence': item['sequence'] if item is not None else None,
                     'returned': False}
            observation_events.append(event)
            result = original(operation, root, path, value, mode)
            event['returned'] = True
            if item is not None:
                item['observed'] = True
            if stream is not None:
                stream['observed'] = True
            return result
        return observed

    def matcher(original):
        @wraps(original)
        def matched(operation, root, path, value, mode):
            item = latest(operation, path, value, mode)
            stream = joined_stream(operation, path, value) if mode == 'bytes' else None
            event = {'operation': operation, 'path': path, 'mode': mode,
                     'read_sequence': item['sequence'] if item is not None else None,
                     'returned': False}
            match_events.append(event)
            result = original(operation, root, path, value, mode)
            event['returned'] = True
            if item is not None:
                item['matched'] = True
            if stream is not None:
                stream['matched'] = True
            return result
        return matched

    def base_observer(original):
        @wraps(original)
        def observed(view, owner, root, path):
            operation = view._operation if type(view) in lease_types else (
                view if type(view) in operation_types else None)
            start = len(reads)
            if operation is not None:
                event = {'operation': operation, 'kind': 'base', 'returned': False}
                boundary_entries.append(event)
            value = original(view, owner, root, path)
            if operation is not None:
                event['returned'] = True
                found = [item for item in reads[start:] if item['operation'] is operation
                         and item['path'] == path and item['value'] is value
                         and item['binding'] == 'base']
                case.assertEqual(len(found), 1, ('base physical/comparison join', path))
                found[0]['matched'] = True
                if type(view) in operation_types:
                    found[0]['phase'] = 'outer_finalizer'
            return value
        return observed

    def lease_observer(original):
        @wraps(original)
        def observed(view, owner, root, path):
            frame = sys._getframe(1)
            found = site(frame)
            operation = view._operation
            start = len(reads)
            event = {'operation': operation, 'kind': 'lease', 'returned': False}
            boundary_entries.append(event)
            value = original(view, owner, root, path)
            event['returned'] = True
            if found is not None:
                case.assertEqual(found[3], 'lease')
                physical = [item for item in reads[start:] if item['operation'] is operation
                            and item['path'] == path and item['value'] is value
                            and item['binding'] == 'base' and item['matched']]
                case.assertEqual(len(physical), 1, ('lease physical/comparison join', found[0]))
                item = record_read(found, operation, Path(root)/path, value, frame)
                item['matched'] = True
                item['physical_sequence'] = physical[0]['sequence']
                item['lease_number'] = lease_number(view)
            return value
        return observed

    def token_observer(original):
        @wraps(original)
        def tokens(text, *args, **kwargs):
            frame = sys._getframe(1)
            selected = (frame.f_globals.get('__file__') is not None
                        and str(Path(frame.f_globals['__file__']).absolute()) == cache_filename
                        and span(frame) == local_span
                        and type(frame.f_locals.get('_inputs')) in lease_types)
            if selected:
                case.assertIn(frame.f_code, original_family(frame, 'inventory'))
                view = frame.f_locals.get('_inputs')
                case.assertIn(type(view), lease_types)
                item = latest(view._operation, 'extensions/carla/map.mojo', text,
                              'supplied_default')
                case.assertIsNotNone(item, 'local-S must consume the original retained text object')
                case.assertEqual(item['binding'], 'local_s')
                case.assertIs(item['frame'], frame)
                item['lease'] = view
                event = {'operation': view._operation, 'kind': 'local_s', 'returned': False}
                boundary_entries.append(event)
            value = original(text, *args, **kwargs)
            if selected:
                event['returned'] = True
                item['local_compared'] = True
            return value
        return tokens

    with ExitStack() as stack:
        original_open = Path.open
        @wraps(original_open)
        def opened(path, *args, **kwargs):
            frame = sys._getframe(1)
            found = site(frame)
            operation = operation_at(frame, found) if found is not None else None
            if operation is not None and found[3] == 'stream_open':
                entry = {'frame': frame, 'operation': operation, 'site': found[0], 'returned': False}
                primitive_entries.append(entry)
            stream = original_open(path, *args, **kwargs)
            if operation is None or found[3] != 'stream_open':
                return stream
            entry['returned'] = True
            case.assertEqual(args, ('rb',))
            case.assertEqual(kwargs, {})
            item = {'operation': operation, 'path': relative(path), 'open_site': found[0],
                    'owner': found[1], 'mode': found[2], 'phase': operation._state,
                    'open_code': frame.f_code, 'globals': frame.f_globals,
                    'open_span': span(frame),
                    'read_site': None, 'chunks': [], 'requests': [], 'eof': False,
                    'observed': False, 'matched': False, 'stream': stream,
                    'owner_frame': frame, 'read_calls': [], 'composed': None}
            streams.append(item)
            stream_index[id(operation), item['path']] = item
            original_read = stream.read
            def read(size):
                read_frame = sys._getframe(1)
                read_site = site(read_frame)
                case.assertIsNotNone(read_site, 'stream must read in its original lambda')
                case.assertEqual(read_site[3], 'stream_read')
                case.assertFalse(item['eof'], 'no read after original EOF')
                event = {'frame': read_frame, 'size': size, 'returned': False,
                         'owner': read_site[1], 'mode': read_site[2],
                         'phase': operation._state, 'code': read_frame.f_code,
                         'globals': read_frame.f_globals, 'span': span(read_frame)}
                item['read_calls'].append(event)
                value = original_read(size)
                event['returned'] = True
                case.assertIs(type(value), bytes)
                item['read_site'] = read_site[0]
                item['requests'].append(size)
                item['chunks'].append(value)
                item['eof'] = value == b''
                if item['eof']:
                    item['composed'] = b''.join(item['chunks'])
                return value
            # Keep the original stream object and its original context manager.
            # Shadow only this instance's read, calling the original exactly once.
            stack.enter_context(patch.object(stream, 'read', read))
            return stream

        stack.enter_context(patch.object(Path, 'read_bytes', reader(Path.read_bytes)))
        stack.enter_context(patch.object(Path, 'read_text', reader(Path.read_text)))
        stack.enter_context(patch.object(Path, 'open', opened))
        for core in cores:
            stack.enter_context(patch.object(core._InvariantInputs, '_observe', observer(core._InvariantInputs._observe)))
            stack.enter_context(patch.object(core._InvariantInputs, '_match', matcher(core._InvariantInputs._match)))
            stack.enter_context(patch.object(core._CacheInputs, 'observe_bytes', base_observer(core._CacheInputs.observe_bytes)))
            stack.enter_context(patch.object(core._BorrowedCacheInputs, 'observe_bytes', lease_observer(core._BorrowedCacheInputs.observe_bytes)))
        sources = {id(core.source): core.source for core in cores}
        for module in sources.values():
            stack.enter_context(patch.object(module, 'token_sha256', token_observer(module.token_sha256)))

        def summarize(operation, route):
            actual = [item for item in reads if item['operation'] is operation]
            case.assertTrue(actual, ('no reviewed physical boundary reached', route))
            for item in actual:
                with case.subTest(route=route, site=item['site'], sequence=item['sequence']):
                    if item['binding'] == 'local_s':
                        case.assertTrue(item['local_compared'])
                        case.assertIn(type(item['lease']), lease_types)
                        case.assertEqual(item['lease']._state, 'closed')
                    elif item['binding'] in ('base', 'lease'):
                        case.assertTrue(item['matched'])
                    else:
                        case.assertTrue(item['observed'], 'original returned value was not observed')
                        case.assertTrue(item['matched'], 'current queued/active value never matched its image')
            actual_streams = [item for item in streams if item['operation'] is operation]
            for item in actual_streams:
                case.assertTrue(item['eof'])
                case.assertTrue(item['requests'])
                case.assertTrue(all(size == 1 << 20 for size in item['requests']))
                case.assertTrue(item['stream'].closed)
                case.assertTrue(item['observed'])
                case.assertTrue(item['matched'])
                case.assertTrue(all(event['returned'] for event in item['read_calls']))
            reached = {item['site'] for item in actual}
            for item in actual_streams:
                reached.update((item['open_site'], item['read_site']))
            expected = {item[0] for item in sites.values()}
            case.assertTrue(any(event['operation'] is operation for event in observation_events))
            for events in (primitive_entries, observation_events, match_events, boundary_entries):
                case.assertTrue(all(event['returned'] for event in events if event['operation'] is operation))
            bindings = {}
            for item in actual:
                key = (item['site'], item['owner'], item['globals'].get('__name__'),
                       item['code'].co_qualname, item['span'])
                counts = bindings.setdefault(key, Counter())
                counts[item['path'], item['mode'], item['phase']] += 1
            for item in actual_streams:
                key = (item['open_site'], item['owner'], item['globals'].get('__name__'),
                       item['open_code'].co_qualname, item['open_span'])
                bindings.setdefault(key, Counter())[item['path'], item['mode'], item['phase']] += 1
                for event in item['read_calls']:
                    key = (item['read_site'], event['owner'], event['globals'].get('__name__'),
                           event['code'].co_qualname, event['span'])
                    bindings.setdefault(key, Counter())[
                        item['path'], event['mode'], event['phase']] += 1
            per_site = {}
            for (site_id, owner, namespace, code_name, call_span), counts in sorted(bindings.items()):
                per_site.setdefault(site_id, []).append({
                    'owner': owner, 'namespace': namespace, 'code': code_name,
                    'call_span': list(call_span),
                    'path_mode_phase_counts': [[path, mode, phase, count]
                        for (path, mode, phase), count in sorted(counts.items())]})
            lease_groups = []
            for number in sorted({item['lease_number'] for item in actual if 'lease_number' in item}):
                items = [item for item in actual if item.get('lease_number') == number]
                lease_groups.append({'lease': number,
                    'positions': sorted({item['site'] for item in items if item['binding'] == 'lease'}),
                    'local_supplied_map_seen': any(item['binding'] == 'local_s' for item in items),
                    'caller_chains': [json.loads(chain) for chain in sorted({
                        json.dumps(item['caller_chain']) for item in items})]})
            return {'route': route, 'reached_sites': sorted(reached),
                    'residual_unreached_sites': sorted(expected - reached),
                    'site_bindings': per_site,
                    'mode_counts': dict(Counter(item['mode'] for item in actual)),
                    'phase_counts': dict(Counter(item['phase'] for item in actual)),
                    'borrowed_positions': sorted({item['site'] for item in actual if item['binding'] == 'lease'}),
                    'borrowed_lease_groups': lease_groups,
                    'local_supplied_map_seen': any(item['binding'] == 'local_s' for item in actual),
                    'local_supplied_caller_chains': [json.loads(chain) for chain in sorted({
                        json.dumps(item['caller_chain']) for item in actual if item['binding'] == 'local_s'})],
                    'pending_accepted_pair_seen': any(item['phase'] == 'pending'
                        and item['site'].endswith('accepted_successor_contracts.py:117:1') for item in actual),
                    'original_streams': len(actual_streams)}
        try:
            yield summarize
        finally:
            # Release retained values and executing frames after this owner,
            # including a failed positive run. None survives into another call.
            read_index.clear()
            stream_index.clear()
            leases.clear()
            for events in (reads, streams, observation_events, match_events,
                           primitive_entries, boundary_entries):
                events.clear()


class OperationReachedBindingControls(unittest.TestCase):
    """Positive real-owner value provenance; residual sites stay explicit."""
    # Reuse helper methods only. Do not inherit the nineteen lifecycle tests.
    setUp = BoundedOwnerCurrentControls.setUp
    audit = BoundedOwnerCurrentControls.audit
    coverage = BoundedOwnerCurrentControls.coverage
    assert_closed = BoundedOwnerCurrentControls.assert_closed
    assert_one_owner = BoundedOwnerCurrentControls.assert_one_owner

    def test_current_cold_routes_preserve_consumed_value_bindings(self):
        import winner_sign_contracts as winner
        loops, coverage_core = self.coverage()
        code_root = Path(__file__).resolve().parents[2]
        routes = (
            ('invariant', cleanup, lambda: invariant.verify(self.root)),
            ('winner', cleanup, lambda: winner.verify(self.root)),
            ('map_loops', coverage_core, lambda: loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map')),
            ('rtree_loops', coverage_core, lambda: loops.reviewed_nonempty_loops(self.root, 'extensions/carla/rtree')),
        )
        owners = []
        for kind, core, run in routes:
            with self.subTest(owner=kind), self.audit(core) as events, _operation_reached_bindings(
                    self, code_root, self.root, (cleanup, coverage_core)) as summarize:
                result = run()
                self.assertTrue(result)
                operation = self.assert_one_owner(events, kind, core)
                self.assertTrue(all(operation is not previous for previous in owners))
                owners.append(operation)
                report = summarize(operation, kind)
            print('OPERATION_REACHED_BINDINGS ' + json.dumps(report, sort_keys=True))


if __name__ == '__main__':
    unittest.main()
