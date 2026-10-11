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

if __name__ == '__main__':
    unittest.main()
