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
import test_owner_frame_lexical as owner_helpers

LANE = 'extensions/carla/lane_refinement.mojo'
ROAD = 'extensions/carla/road.mojo'
# These are the complete v17 public predecessors, recovered only through the
# exact reviewed #333 structural inverse below. Never replace these digests.
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


# Complete, explicitly reviewed wrappers. Values inside _observe_* remain the
# actual physical read objects; the provenance view is only their outer call.
_TYPED_ADAPTER_CALLS = {'verify_premises': ("_typed_source.historical_text(root, root / item['path'], (root / "
                     "item['path']).read_text())",
                     '_typed_source.historical_text(root, root / name, (root / name).read_text())',
                     '_typed_source.historical_text(root, root / name, (root / name).read_text())',
                     '_typed_source.historical_text(root, root / path, (root / path).read_text())',
                     '_typed_source.historical_text(root, name, text)',
                     "_typed_source.historical_text(root, root / item['path'], (root / "
                     "item['path']).read_text())",
                     '_typed_source.historical_bytes(root, root / prior.MIGRATION, (root / '
                     'prior.MIGRATION).read_bytes())'),
 '_verify_premises': ("_typed_source.historical_text(root, item['path'], full_audit._observe_text(root, "
                      "item['path'], (root / item['path']).read_text(), _operation=_operation), "
                      '_operation=_operation)',
                      '_typed_source.historical_text(root, name, full_audit._observe_text(root, name, (root '
                      '/ name).read_text(), _operation=_operation), _operation=_operation)',
                      '_typed_source.historical_text(root, name, full_audit._observe_text(root, name, (root '
                      '/ name).read_text(), _operation=_operation), _operation=_operation)',
                      '_typed_source.historical_text(root, path, full_audit._observe_text(root, path, (root '
                      '/ path).read_text(), _operation=_operation), _operation=_operation)',
                      '_typed_source.historical_text(root, name, text, _operation=_operation)',
                      "_typed_source.historical_text(root, item['path'], full_audit._observe_text(root, "
                      "item['path'], (root / item['path']).read_text(), _operation=_operation), "
                      '_operation=_operation)',
                      '_typed_source.historical_bytes(root, root / prior.MIGRATION, (root / '
                      'prior.MIGRATION).read_bytes(), _operation=_operation)'),
 'predecessor_pin_pair': ("_typed_source.historical_bytes(root, root / 'tools/carla_lane_oracle' / "
                          "runtime_name, (root / 'tools/carla_lane_oracle' / runtime_name).read_bytes())",
                          "_typed_source.historical_bytes(root, root / 'tools/carla_lane_oracle' / "
                          "guard_name, (root / 'tools/carla_lane_oracle' / guard_name).read_bytes())"),
 '_predecessor_pin_pair': ("_typed_source.historical_bytes(root, root / 'tools/carla_lane_oracle' / "
                           "runtime_name, (root / 'tools/carla_lane_oracle' / runtime_name).read_bytes(), "
                           '_operation=_operation)',
                           "_typed_source.historical_bytes(root, root / 'tools/carla_lane_oracle' / "
                           "guard_name, (root / 'tools/carla_lane_oracle' / guard_name).read_bytes(), "
                           '_operation=_operation)')}


def typed_adapter_predecessor(node):
    """Remove exactly #333 provenance wrappers and the checked reread view."""
    node = copy.deepcopy(node)
    expected = Counter(_TYPED_ADAPTER_CALLS[node.name])
    calls, removed = [], []
    assignment = ast.parse('text = _typed_source.historical_text(root, name, text'
        + (', _operation=_operation)' if node.name.startswith('_') else ')')).body[0]
    matches = [(parent, field, index) for parent in ast.walk(node)
               for field, values in ast.iter_fields(parent) if isinstance(values, list)
               for index, value in enumerate(values) if isinstance(value, ast.Assign)
               and ast_key(value) == ast_key(assignment)]
    if 'verify_premises' in node.name:
        if len(matches) != 1:
            raise AssertionError('one typed captured-reread projection required')
        parent, field, index = matches[0]
        statements = getattr(parent, field)
        compare = ast.parse("require(source.token_sha256(supplied) == source.token_sha256(text), "
                            "'consumer source text/bytes disagree: ' + name)").body[0]
        if field != 'body' or index != len(statements) - 1 or index == 0 or ast_key(statements[index - 1]) != ast_key(compare):
            raise AssertionError('typed projection must follow the physical reread comparison')
    elif matches:
        raise AssertionError('unreviewed typed reread projection')
    class Project(ast.NodeTransformer):
        def visit_Assign(self, item):
            if ast_key(item) == ast_key(assignment):
                removed.append(ast.unparse(item.value))
                return None
            return self.generic_visit(item)
        def visit_Call(self, item):
            if (isinstance(item.func, ast.Attribute) and isinstance(item.func.value, ast.Name)
                    and item.func.value.id == '_typed_source'):
                text = ast.unparse(item)
                if text not in expected:
                    raise AssertionError(('unreviewed typed adapter', text))
                calls.append(text)
                return self.visit(item.args[2])
            return self.generic_visit(item)
    result = Project().visit(node)
    if Counter(calls + removed) != expected:
        raise AssertionError('missing or extra typed adapter')
    if len(removed) != (1 if 'verify_premises' in node.name else 0):
        raise AssertionError('typed reread projection moved or changed')
    return result


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
        original = typed_adapter_predecessor(function_ast(module, name))
        private = typed_adapter_predecessor(private if private is not None else function_ast(module, '_' + name))
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
                self.assertEqual(hashlib.sha256(ast_key(typed_adapter_predecessor(function_ast(module, name))).encode()).hexdigest(), expected)
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
        # macOS temporary roots can have a symbolic /var ancestor. Normalize
        # only the fixture's parent; production must still reject aliased input.
        with tempfile.TemporaryDirectory(
                prefix='invariant-selector-fake-', dir=Path(tempfile.gettempdir()).resolve()) as directory:
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

    def test_selector_fixture_under_symbolic_temp_root_keeps_controls(self):
        with tempfile.TemporaryDirectory(
                prefix='invariant-selector-temp-alias-', dir=Path(tempfile.gettempdir()).resolve()) as directory:
            parent = Path(directory)
            physical = parent/'physical'
            physical.mkdir()
            symbolic = parent/'symbolic'
            symbolic.symlink_to(physical, target_is_directory=True)
            with patch.object(tempfile, 'tempdir', str(symbolic)):
                self.assertEqual(Path(tempfile.gettempdir()), symbolic)
                for control in (
                        self.test_private_selector_positive_result_and_physical_read_order_match_public,
                        self.test_private_selector_consumed_b_stops_before_declaration,
                        self.test_private_selector_supplied_comments_keep_token_equivalence):
                    with self.subTest(control=control.__name__):
                        control()
                        self.assertEqual(list(physical.iterdir()), [])
                with self.selector_fixture() as (root, raw, record, interpreted):
                    self.assertEqual(root.parent, physical)
                    self.assertEqual(root, root.resolve())
                    self.assertEqual(cleanup._regular(root, LANE).read_bytes(), raw[LANE])
                    with self.assertRaisesRegex(cleanup.ContractError, 'symbolic root or ancestor'):
                        cleanup._regular(symbolic/root.name, LANE)
                    for kind in ('root', 'ancestor', 'leaf'):
                        message = 'symbolic root or ancestor' if kind == 'root' else 'symlink input'
                        with self.subTest(alias=kind), paired_helpers.alias(root, LANE, kind):
                            with self.assertRaisesRegex(cleanup.ContractError, message):
                                cleanup._regular(root, LANE)
                        self.assertEqual(cleanup._regular(root, LANE).read_bytes(), raw[LANE])
                self.assertFalse(root.exists())
                self.assertEqual(list(physical.iterdir()), [])

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
        marker = 'extensions/carla/polynomial.mojo'
        self.assertTrue(cleanup.typed_boundary.is_current(marker, (self.root/marker).read_bytes()),
                        'current authority controls require the actual typed graph')

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
        self.assertIs(operation._checker_receipt, False)

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
        import border_parser_contracts as border
        import _full_audit_test_fixtures as fixtures
        with self.audit() as events:
            result = winner.verify(self.root)
        self.assertEqual(result['status'], 'PASS')
        typed = cleanup.typed_boundary
        edges = result['typed_boundary_successors']
        self.assertEqual(set(edges), set(typed.SOURCE_PATHS))
        for path, edge in edges.items():
            self.assertEqual(edge['after_sha256'], hashlib.sha256((self.root/path).read_bytes()).hexdigest())
        canonical = json.loads((self.root/'tools/carla_lane_oracle/winner-sign-query-migration.json').read_bytes())['canonical_source_unchanged']
        self.assertEqual(len(canonical), 112)
        helpers = cleanup.shared_helpers
        self.assertEqual(set(helpers.SOURCE_PATHS) & set(canonical), fixtures.WINNER_SHARED_HELPER_SUCCESSORS)
        self.assertNotIn('loaders/xml.mojo', canonical)
        for path in fixtures.WINNER_SHARED_HELPER_SUCCESSORS:
            self.assertEqual(canonical[path], helpers.BEFORE_SHA256[path])
            raw = (self.root/path).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), helpers.AFTER_SHA256[path])
            before = helpers.predecessor_source(path, raw.decode('utf-8'))
            self.assertEqual(hashlib.sha256(before.encode('utf-8')).hexdigest(), canonical[path])
        prior = fixtures.WINNER_PRE_BORDER_SUCCESSORS | {
            border.MODULE, fixtures.WINNER_FULL_AUDIT_NEW_DEPENDENCY}
        self.assertTrue(prior.isdisjoint(fixtures.WINNER_SHARED_HELPER_SUCCESSORS))
        historical_changed, current_changed = set(), set()
        for path, digest in canonical.items():
            raw = (self.root/path).read_bytes()
            if hashlib.sha256(raw).hexdigest() != digest:
                current_changed.add(path)
            # The current owner has completed before historical reporting is
            # inspected. These views never replace the physical fixture.
            historical = typed.historical_source(path, raw.decode('utf-8')).encode('utf-8')
            if hashlib.sha256(historical).hexdigest() != digest:
                historical_changed.add(path)
        self.assertEqual(historical_changed, prior | fixtures.WINNER_SHARED_HELPER_SUCCESSORS)
        self.assertEqual(current_changed, historical_changed | (set(canonical) & set(typed.SOURCE_PATHS)))
        self.assertEqual((len(prior), len(canonical) - len(prior)), (20, 92))
        self.assertEqual((result['reviewed_cleanup_successors'], result['canonical_dependencies_unchanged']),
                         (len(historical_changed), len(canonical) - len(historical_changed)))
        self.assertEqual(result['map_source_sha256'], hashlib.sha256((self.root/'extensions/carla/map.mojo').read_bytes()).hexdigest())
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
                path = frame.f_locals['path']
                self.assertIs(raw, frame.f_locals['raw'])
                self.assertEqual(raw, (self.root/path).read_bytes())
                self.assertTrue(cleanup.typed_boundary.is_current(path, raw))
                checked.append(path)
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
        self.root = fixtures.copy_historical_boundary_root(self, Path(__file__).resolve().parents[2])
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
        # Remove the complete reviewed negative filter at its exact location.
        # Keep all authoritative comparisons and exceptional behavior.
        _rc21_negative_filter(owner_helpers.typed_owner_ast(node, 'registry', reverse=True))
        del node.body[3]
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

    @staticmethod
    def _receipt_control_namespace():
        """Compile isolated routing mechanics, never a replacement authority."""
        raw = Path(cleanup.__file__).read_bytes()
        _checker_source_predecessor('full_audit_cleanup_contracts.py', raw)
        tree = ast.parse(raw)
        owner = next(node for node in tree.body if isinstance(node, ast.ClassDef)
                     and node.name == '_InvariantInputs')
        methods = [copy.deepcopy(node) for node in owner.body
                   if isinstance(node, ast.FunctionDef)
                   and node.name in ('_bind_checker_receipt', 'finish')]
        if len(methods) != 2:
            raise AssertionError('missing exact checker receipt methods')
        namespace = dict(vars(cleanup))
        exec(compile(ast.Module(body=methods, type_ignores=[]),
                     '<isolated-checker-receipt-mechanics>', 'exec'), namespace)
        exec(compile("""
def proof_bindings(root, executing, *, _operation, target):
    return target._bind_checker_receipt(root, executing)
def wrong_frame(root, executing, *, _operation, target):
    return target._bind_checker_receipt(root, executing)
""", '<isolated-checker-receipt-callers>', 'exec'), namespace)
        return namespace

    def test_checker_receipt_registration_requires_exact_frame_owner_and_image(self):
        import types
        root = Path('/synthetic-checker-receipt-root')
        captured = {'synthetic-checker.py': 'captured'}
        for fault in (None, 'wrong frame', 'wrong globals', 'wrong owner', 'wrong root',
                      'pending', 'capturing', 'nonbool receipt', 'nondict image', 'different image'):
            with self.subTest(fault=fault):
                namespace = self._receipt_control_namespace()
                events = []
                owner = types.SimpleNamespace(_state='active', _capturing=False,
                    _checker_receipt=False, _executing=types.MappingProxyType(captured))
                def check(actual_root):
                    events.append('owner')
                    cleanup.require(actual_root == root, 'synthetic wrong root')
                def fail(actual_owner, error):
                    self.assertIs(actual_owner, owner)
                    events.append('failure')
                    owner._checker_receipt = False
                    raise error
                owner._check_owner = check
                owner._bind_checker_receipt = types.MethodType(namespace['_bind_checker_receipt'], owner)
                namespace['_operation_fail'] = fail
                caller = namespace['proof_bindings']
                operation, actual_root, executing = owner, root, dict(captured)
                if fault == 'wrong frame': caller = namespace['wrong_frame']
                elif fault == 'wrong globals':
                    caller = types.FunctionType(caller.__code__, dict(namespace))
                elif fault == 'wrong owner': operation = object()
                elif fault == 'wrong root': actual_root = root/'foreign'
                elif fault == 'pending': owner._state = 'pending'
                elif fault == 'capturing': owner._capturing = True
                elif fault == 'nonbool receipt': owner._checker_receipt = 0
                elif fault == 'nondict image': executing = types.MappingProxyType(captured)
                elif fault == 'different image': executing = {'synthetic-checker.py': 'different'}
                if fault is None:
                    self.assertIsNone(caller(actual_root, executing, _operation=operation, target=owner))
                    self.assertIs(owner._checker_receipt, True)
                    self.assertEqual(events, ['owner'])
                else:
                    with self.assertRaises(ValueError):
                        caller(actual_root, executing, _operation=operation, target=owner)
                    self.assertIs(owner._checker_receipt, False)
                    self.assertEqual(events, ['owner', 'failure'])

    def test_checker_receipt_finalizer_keeps_unregistered_owner_scope(self):
        import types
        root = Path('/synthetic-checker-receipt-root')
        captured = {'synthetic-checker.py': 'captured'}
        cases = (('active', False, False), ('pending', False, False),
                 ('active', True, False), ('active', True, True), ('active', 1, False))
        for state, registered, changed in cases:
            with self.subTest(state=state, registered=registered, changed=changed):
                namespace = self._receipt_control_namespace()
                events = []
                owner = types.SimpleNamespace(_state=state, _checker_receipt=registered,
                    _owner=object(), _executing=types.MappingProxyType(captured),
                    _resolver_paths=frozenset())
                def check(actual_root):
                    self.assertEqual(actual_root, root)
                    events.append('owner')
                def checkpoint(actual_owner, token, actual_root):
                    self.assertIs(actual_owner, owner)
                    self.assertIs(token, owner._owner)
                    self.assertEqual(actual_root, root)
                    events.append('checkpoint')
                def executing(actual_root):
                    self.assertEqual(actual_root, root)
                    events.append('executing')
                    return {'synthetic-checker.py': 'different'} if changed else dict(captured)
                def close():
                    events.append('close')
                    owner._checker_receipt = False
                    owner._state = 'closed'
                def fail(actual_owner, error):
                    self.assertIs(actual_owner, owner)
                    events.append('failure')
                    raise error
                owner._check_owner, owner.close = check, close
                namespace.update(_CacheInputs=types.SimpleNamespace(checkpoint=checkpoint),
                    executing_checker_bindings=executing, _operation_fail=fail)
                finish = types.MethodType(namespace['finish'], owner)
                refused = changed or type(registered) is not bool
                if refused:
                    with self.assertRaisesRegex(ValueError, 'consumed receipt checker changed|invalid consumed checker receipt state'):
                        finish(root)
                    self.assertEqual(owner._state, 'closed')
                    self.assertIs(owner._checker_receipt, False)
                else:
                    self.assertIsNone(finish(root))
                    self.assertEqual(owner._state, 'finished')
                expected = ['owner']
                if state == 'active': expected.append('checkpoint')
                if registered is True: expected.append('executing')
                if refused: expected.extend(('close', 'failure'))
                self.assertEqual(events, expected)


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

def _rc21_expect_ast(node, expected, detail):
    _rc21_require(_rc21_hashlib.sha256(_rc21_ast_key(node).encode()).hexdigest() == expected, detail)


def _rc21_negative_filter(tree):
    # Fixed position and complete subtree: reject changed or moved filters.
    node = tree.body[3]
    _rc21_expect_ast(node, 'dd29d074291dc2aa6d0471f3ea5ea61d8f6ed3dea6ced680fc179fa18bfeb84b',
                     'complete reviewed V11 operation negative filter AST drift')
    return node


def _rc21_original_classifiers(new_text):
    """Invert exact #333 owner additions, then the reviewed V14/V11/V8 edits."""
    module = _rc21_ast.parse(new_text)
    old_defs = {node.name: node for node in module.body
                if isinstance(node, (_rc21_ast.FunctionDef, _rc21_ast.ClassDef))}
    old_defs.pop('_different_alias_leaf')
    operation = old_defs['_operation_frame_kind'] = owner_helpers.typed_owner_ast(
        old_defs['_operation_frame_kind'], 'operation', 'registry', reverse=True)
    cache = old_defs['_cache_verify_frame']
    owner = old_defs['_owner_module'] = owner_helpers.typed_owner_predecessor(old_defs['_owner_module'])

    # V14 captured live-helper identities are exact assignments immediately
    # after the helper, not new cache or owner authority.
    helper_index = module.body.index(old_defs['_live_function_code'])
    for offset, expected in (
            (1, '21abf36fc99d9d8fccb2df493c51bc07d44374c13026e1297fe42afc77fba4ca'),
            (2, 'aa58adbcee1ebccf3a9978bde4b8b01e18ceaed35fed3e7689c2c93b9c982587')):
        _rc21_expect_ast(module.body[helper_index + offset], expected,
                         ('V14 live-helper capture', offset))

    # V14 cache helper-frame rejection is one exact new If after the original
    # alias-leaf guard. The owner dispatch retains the original assignment in
    # its else branch; only that exact branch is used for the inverse.
    _rc21_expect_ast(cache.body[8], 'a460808e6b3a9bf5d10acd12f88a7d8eaa89004a66271bc30aeb9287f15f0dfc',
                     'V14 cache real-frame negative guard AST drift')
    del cache.body[8]
    _rc21_expect_ast(cache, '430c1279085af0c279ec1e0d3ca166bdb5de822af0f3c8595246a489d3a211e8',
                     'complete V13 cache classifier AST drift')
    _rc21_expect_ast(owner.body[1], '73a7cd0ab7fe92a00574301143c48c926cf3f46080c65edc3fc5f35b09b42553',
                     'V14 exact-string owner dispatch AST drift')
    owner.body[1] = owner.body[1].orelse[0]
    _rc21_expect_ast(owner, 'a5f60b07d07556090def6d3490be5dfeef8197ef71d8e3ff13efce5c110d4860',
                     'complete original owner helper AST drift')

    # V11 expanded just the two plain-candidate predicates. Restore the exact
    # original generator from its preserved fallback, including its return body.
    negative = _rc21_negative_filter(operation)
    _rc21_expect_ast(_rc21_ast.Module(body=negative.body[1:4], type_ignores=[]),
                     'f9db65cf09a857bb6a52f12785632601d4d0bed5c50d80dfaf28b6857a1de362',
                     'V11 two-candidate expansion AST drift')
    original_all = negative.body[2].orelse[0].value
    original_all.func.id = 'all'
    original_if = negative.body[3]
    original_if.test = original_all
    negative.body[1:4] = [original_if]
    _rc21_expect_ast(operation, '7fb32652f190b1f87b8e794aa549193d808d048f5ebc1a5656b6eaf80e96f611',
                     'complete V10 operation classifier AST drift')

    # V8 added one wrapped-negative block and one __main__ leaf conjunct.
    # Their fixed locations and complete ASTs must match before removal.
    _rc21_expect_ast(negative.body[2], '4d30aa850d4f93f1ed75f9e648d376ee834b8544348d7c39ff9345dd88d309e8',
                     'V8 wrapped-negative filter AST drift')
    del negative.body[2]
    _rc21_expect_ast(operation, 'f944d5d5c8b841659e9e573fdfa5dc1d04e73b3680b93b31eef5357a84769516',
                     'complete V7 operation classifier AST drift')
    main_test = cache.body[5].test
    _rc21_expect_ast(main_test.values[4], '5b917f2e256600ae88f3c9554802a9068254f812797dfb2e5acb70f05ae8499f',
                     'V8 cache __main__ leaf conjunct AST drift')
    del main_test.values[4]
    _rc21_expect_ast(cache, 'acb1064c8282d433ad178057445119fddc352572af638a8964f6515fbc27d859',
                     'complete V7 cache classifier AST drift')

    guards = {'_operation_frame_kind': 'cba84dcfda3a51af833b0c31fab1af75e6315e2ad074f741e9175d51362ff010', '_cache_verify_frame': 'd7cbe42a90b3841722f4cc2f13c0c99279c20289ffbacb13a9e77387199b0d1e'}
    originals = {'_operation_frame_kind': '39b16f4014f5723842f04d3913d6cb7aaef23abddfd182ae6ffbbd316e0205d0', '_cache_verify_frame': 'f52cba9ca558a0db0d9acfd0701d035b297add0863943af5e619dfe99ec71390'}
    for name, guard_hash in guards.items():
        tree = old_defs[name]
        _rc21_expect_ast(tree.body[7], guard_hash, (name, 'one exact reviewed guard at original position'))
        del tree.body[7]
        _rc21_expect_ast(tree, originals[name], (name, 'complete original classifier AST drift'))
    old_defs['_operation_frame_kind'] = owner_helpers.typed_owner_ast(
        old_defs['_operation_frame_kind'], 'operation_unguarded')
    old_defs['_owner_module'] = owner_helpers.typed_owner_ast(old_defs['_owner_module'], 'owner')
    return old_defs


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
    old_defs = _rc21_original_classifiers(new_text)
    compiled = compile(new_raw, str(after), 'exec', dont_inherit=True, optimize=_rc21_sys.flags.optimize)
    code_by_name = {code.co_name: code for code in compiled.co_consts if isinstance(code, _rc21_types.CodeType)}
    for name in ('_operation_frame_kind', '_cache_verify_frame', '_owner_module',
                 '_different_alias_leaf', '_live_function_code'):
        _rc21_require(code_by_name[name] == getattr(cleanup, name).__code__, (name, 'live classifier source binding'))
    _rc21_require(cleanup._LIVE_FUNCTION_CODE is cleanup._live_function_code
                    and cleanup._LIVE_FUNCTION_CODE_CODE is cleanup._live_function_code.__code__,
                    'reviewed live-helper capture binding')
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


def _one_ast_run(node, expected):
    """Find one exact contiguous statement sequence, never a filtered body."""
    expected = ast.parse(expected).body
    matches = []
    for parent in ast.walk(node):
        for _, body in ast.iter_fields(parent):
            if isinstance(body, list):
                for start in range(len(body) - len(expected) + 1):
                    items = body[start:start + len(expected)]
                    if all(isinstance(item, ast.AST) for item in items) and [ast_key(item) for item in items] == [ast_key(item) for item in expected]:
                        matches.append(items)
    if len(matches) != 1:
        raise AssertionError(('one exact current physical statement sequence', node.name, len(matches)))
    return matches[0]


def _seed_supplied_read_contract(node):
    """Two executed reads survive the removal of four conditional syntax copies."""
    first = _one_ast_run(node, """
current_raw = (Path(root) / MODULE).read_bytes()
if _operation is not None:
    current_raw = full_audit._observe_bytes(root, MODULE, current_raw, _operation=_operation)
require(source.token_sha256(text) == source.token_sha256(current_raw.decode('utf-8')),
        'unreviewed supplied Map source')
text = _typed_source.historical_text(root, MODULE, text, _operation=_operation)
physical = _typed_source.historical_bytes(root, MODULE, current_raw, _operation=_operation)
""")
    final = _one_ast_run(node, """
final_raw = (Path(root) / MODULE).read_bytes()
if _operation is not None:
    final_raw = full_audit._observe_bytes(root, MODULE, final_raw, _operation=_operation)
require(final_raw == current_raw, 'Map changed during supplied-view verification')
""")
    if first[-1].lineno >= final[0].lineno:
        raise AssertionError('supplied Map final read precedes admission')
    return first, final


def _station_census_read_contract(node):
    """Only authority-bearing Map census rows add a physical byte/lease read."""
    return _one_ast_run(node, """
supplied_text = ((path.read_text() if _operation is None else
                  full_audit._observe_text(root, rel.as_posix(), path.read_text(), _operation=_operation)) if _inputs is None else
                 _inputs.text_default(_input_owner, root, rel.as_posix()))
if rel.as_posix() == MODULE and station_edge is not None:
    physical = ((path.read_bytes() if _operation is None else
                 full_audit._observe_bytes(root, MODULE, path.read_bytes(), _operation=_operation)) if _inputs is None else
                _inputs.observe_bytes(_input_owner, root, MODULE))
    require(source.token_sha256(supplied_text) == source.token_sha256(physical.decode('utf-8')),
            'station census supplied and physical Map views differ')
text = _typed_source.historical_text(root, rel.as_posix(), supplied_text, _operation=_operation,
    _inputs=_inputs, _input_owner=_input_owner)
""")[1]


def _coverage_current_discriminator_contract(node):
    """Typed/historical row selection uses the preceding actual dependency digest."""
    if node.name == '_historical_reviewed_nonempty_loops':
        return _one_ast_run(node, """
current = _coverage_observe_text(root, name,
    relative_source(root, name, **operation_args).read_text(), _operation=_operation)
if sha256(current.encode('utf-8')) != actual[name]:
    return {}
""")
    if node.name == 'guarded_loop_proof':
        return _one_ast_run(node, """
current = _coverage_observe_text(root, module_path,
    relative_source(root, module_path, **operation_args).read_text(), _operation=_operation)
if sha256(current.encode('utf-8')) != actual_bindings[module_path]:
    return None
typed_current = typed.is_current(module_path, current)
""")
    raise AssertionError(('unknown coverage discriminator', node.name))


# Exact reviewed consumed-value boundaries only. Source spans are derived at runtime.
# Tuple: module, original owner, physical expression, expected count, selections.
# Each selection is (index, stable site suffix, comparator mode, narrow binding kind).
_OPERATION_REACHED_READ_SPECS = (
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'reviewed_text',
     "_regular(root, path).read_text(encoding='utf-8')", 1,
     ((0, 'typed-public-utf8-default', 'physical', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'reviewed_lane_before_center_text',
     '_regular(root, path).read_bytes()', 2, (
         (0, 'typed-center-supplied-first', 'bytes', 'observe'),
         (1, 'typed-center-supplied-final', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/heading_correspondence.py', 'verify',
     "(path / 'curve_bounds.mojo').read_text()", 1,
     ((0, 'typed-heading-producer', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/heading_correspondence.py', 'verify',
     '(path / filename).read_text()', 1,
     ((0, 'typed-heading-consumers', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/heading_correspondence.py', 'verify',
     "(path / 'spiral_moment_proof.mojo').read_text()", 1,
     ((0, 'typed-heading-eligibility', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_score_caller_inventory',
     'path.read_bytes()', 2, ((1, 'typed-station-census-physical', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_score_caller_inventory',
     '_inputs.observe_bytes(_input_owner, root, MODULE)', 1,
     ((0, 'station-census-lease', 'bytes', 'lease'),)),
    ('tools/carla_lane_oracle/optional_runtime_contracts.py', 'body',
     "(root / ('extensions/carla/' + module + '.mojo')).read_text()", 1,
     ((0, 'typed-runtime-body', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/optional_runtime_contracts.py', 'verify_no_containing_model_consumers',
     'path.read_text()', 1, ((0, 'typed-runtime-callers', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/optional_runtime_contracts.py', 'verify_semantics',
     "(root / 'extensions/carla/curve_bounds.mojo').read_text()", 1,
     ((0, 'typed-runtime-reference', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_contracts.py', 'verify',
     "(root / ('extensions/carla/' + name + '.mojo')).read_text()", 1,
     ((0, 'typed-sum2-source-batch', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_contracts.py', 'verify',
     "(root / 'tools/carla_lane_oracle/spiral-moment-pins.json').read_text()", 1,
     ((0, 'typed-sum2-pin', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_contracts.py', 'verify',
     "(root / 'extensions/carla/curve_interval.mojo').read_text()", 1,
     ((0, 'typed-sum2-interval', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/check_sampled_values.py', 'verify',
     'path.read_text()', 1, ((0, 'typed-sampled-initial-batch', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/check_sampled_values.py', 'verify',
     'path.read_bytes()', 1, ((0, 'typed-sampled-final-sources', 'bytes', 'observe'),)),
    # #333 current physical admission/provenance seams. The original sites
    # below remain in the same matrix; this list adds the successor reads.
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', '_typed_boundary_bindings',
     '_regular(root, marker).read_bytes()', 1, ((0, 'typed-marker-first', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', '_typed_boundary_bindings',
     '_regular(root, path).read_bytes()', 4, (
         (0, 'typed-historical-mix-guard', 'bytes', 'observe'),
         (1, 'typed-source-first', 'bytes', 'observe'),
         (2, 'typed-bound-input-first', 'bytes', 'observe'),
         (3, 'typed-bound-input-final', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'reviewed_typed_text',
     '_regular(root, path).read_bytes()', 2, (
         (0, 'typed-provenance-first', 'bytes', 'observe'),
         (1, 'typed-provenance-final', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'typed_successor_edges',
     '_regular(root, marker).read_bytes()', 1, ((0, 'typed-edge-marker', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'typed_successor_edges',
     '_regular(root, path).read_bytes()', 1, ((0, 'typed-edge-source', 'bytes', 'observe'),)),
    ('tools/coverage_loop_proofs.py', '_historical_reviewed_nonempty_loops',
     'relative_source(root, name, **operation_args).read_text()', 1,
     ((0, 'typed-loop-current-source', 'default', 'observe'),)),
    ('tools/coverage_loop_proofs.py', 'guarded_loop_proof',
     'relative_source(root, module_path, **operation_args).read_text()', 1,
     ((0, 'typed-guarded-current-source', 'default', 'observe'),)),
    ('tools/coverage_loop_proofs.py', 'guarded_loop_proof',
     'relative_source(root, path.as_posix(), **operation_args).read_text()', 1,
     ((0, 'typed-guarded-current-caller', 'default', 'observe'),)),
    ('tools/coverage_loop_proofs.py', '_typed_construction_boundary_loops',
     'relative_source(root, path, **operation_args).read_bytes()', 1,
     ((0, 'typed-construction-input', 'bytes', 'observe'),)),
    ('tools/coverage_loop_proofs.py', 'construction_boundary_loops',
     'relative_source(root, name, **operation_args).read_text()', 1,
     ((0, 'typed-construction-source', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/consumer_successor_ledger.py', '_read',
     'audit._regular(root, path).read_bytes()', 1, ((0, '82:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/runtime_boundary_contracts.py', 'verify',
     '(root / MIGRATION).read_bytes()', 1, ((0, '66:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/render_actor_reuse_contracts.py', 'verify',
     '(root / MIGRATION).read_bytes()', 1, ((0, '59:1', 'bytes', 'observe'),)),
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
     '(root / MODULE).read_bytes()', 4, ((1, '709:1', 'bytes', 'observe'),
         (3, 'typed-seed-dispatch-final', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'reviewed_text',
     '(Path(root) / MODULE).read_bytes()', 2, ((0, '754:1', 'bytes', 'observe'), (1, '766:1', 'bytes', 'observe'))),
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
     '(root / path).read_bytes()', 2, ((0, '47:1', 'bytes', 'observe'), (1, '81:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/reviewed_cleanup_contracts.py', 'verify_premises',
     '(root / SOURCE_PATHS[0]).read_text()', 1, ((0, '103:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/reviewed_cleanup_contracts.py', 'verify_premises',
     '(root / SOURCE_PATHS[1]).read_text()', 1, ((0, '104:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/reviewed_cleanup_contracts.py', 'verify_premises',
     '(root / SOURCE_PATHS[2]).read_text()', 1, ((0, '105:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/reviewed_cleanup_contracts.py', 'verify',
     '(root / path).read_text()', 2, ((0, '252:1', 'default', 'observe'), (1, '266:1', 'default', 'observe'))),
    ('tools/carla_lane_oracle/runtime_boundary_contracts.py', 'verify',
     '(root / path).read_bytes()', 2, ((0, '54:1', 'bytes', 'observe'), (1, '88:1', 'bytes', 'observe'))),
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
     'path.read_bytes()', 5, ((0, '798:1', 'bytes', 'observe'),
                            (1, 'typed-source-final', 'bytes', 'observe'),
                            (2, 'shared-helper-source-final', 'bytes', 'observe'),
                            (3, 'cleanup-source-final', 'bytes', 'observe'),
                            (4, '828:1', 'bytes', 'observe'))),
    # Only the exact shared-helper successor branch added to this owner.
    # Its checker, provider and package samples retain their physical values.
    ('tools/coverage_loop_proofs.py', '_reviewed_dependency_hashes',
     'relative_source(root, leaf, **operation_args).read_bytes()', 2,
     ((0, 'shared-helper-checker-first', 'bytes', 'observe'),
      (1, 'shared-helper-checker-final', 'bytes', 'observe'))),
    ('tools/coverage_loop_proofs.py', '_reviewed_dependency_hashes',
     'relative_source(root, provider, **operation_args).read_bytes()', 2,
     ((0, 'shared-helper-provider-first', 'bytes', 'observe'),
      (1, 'shared-helper-provider-final', 'bytes', 'observe'))),
    ('tools/coverage_loop_proofs.py', '_reviewed_dependency_hashes',
     'relative_source(root, package, **operation_args).read_bytes()', 1,
     ((0, 'shared-helper-package-first', 'bytes', 'observe'),)),
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
        if relative == 'tools/coverage_loop_proofs.py' and owner in (
                '_historical_reviewed_nonempty_loops', 'guarded_loop_proof'):
            _coverage_current_discriminator_contract(node)
        if relative == 'tools/carla_lane_oracle/seed_count_contracts.py':
            if owner == 'reviewed_text':
                _seed_supplied_read_contract(node)
            elif owner == 'verify_score_caller_inventory':
                _station_census_read_contract(node)
        key = ast.dump(ast.parse(expression, mode='eval').body, include_attributes=False)
        calls = sorted((item for item in ast.walk(node) if isinstance(item, ast.Call)
                        and ast.dump(item, include_attributes=False) == key),
                       key=lambda item: (item.lineno, item.col_offset))
        case.assertEqual(len(calls), expected_count, (relative, owner, expression))
        if (relative, owner, expression) == (
                'tools/coverage_loop_proofs.py', '_reviewed_dependency_hashes', 'path.read_bytes()'):
            # Both successor final rereads must observe the physical value
            # before equality; the typed one precedes historical projection.
            parents = {child: parent for parent in ast.walk(node)
                       for child in ast.iter_child_nodes(parent)}
            for index in (1, 3):
                observation = parents[calls[index]]
                expected = ast.parse('_coverage_observe_bytes(root, name, path.read_bytes(), '
                                     '_operation=_operation)', mode='eval').body
                case.assertEqual(ast_key(observation), ast_key(expected))
                case.assertIsInstance(parents[observation], ast.Compare)
                case.assertEqual(ast_key(parents[observation].comparators[0]),
                                 ast_key(ast.Name(id='raw', ctx=ast.Load())))
        for index, suffix, mode, binding in selections:
            call = calls[index]
            if suffix.startswith('typed-'):
                parents = {child: parent for parent in ast.walk(node)
                           for child in ast.iter_child_nodes(parent)}
                observed = parents[call]
                case.assertIsInstance(observed, ast.Call)
                if (relative, owner, suffix) == (
                        'tools/carla_lane_oracle/check_sampled_values.py', 'verify',
                        'typed-sampled-initial-batch'):
                    # verify later binds a local named source. The physical
                    # batch must use its unshadowed module import explicitly.
                    case.assertEqual(ast.unparse(observed.func), '_typed_source._observe_text')
                else:
                    case.assertIn(ast.unparse(observed.func), ('_observe_bytes', '_observe_text', '_coverage_observe_bytes',
                        '_coverage_observe_text', 'source._observe_text', 'audit._observe_bytes',
                        'full_audit._observe_bytes'))
                case.assertIs(observed.args[2], call)
                operation_keywords = [keyword.value for keyword in observed.keywords if keyword.arg == '_operation']
                case.assertEqual([ast_key(value) for value in operation_keywords],
                                 [ast_key(ast.Name(id='_operation', ctx=ast.Load()))])
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
    # generic _observe call. Keep its exact endpoint-paired chained predicate.
    cache_filename = str((Path(code_root)/'tools/carla_lane_oracle/cache_key_contracts.py').absolute())
    cache_tree = trees[cache_filename]
    inventory_node = next(item for item in cache_tree.body
                          if isinstance(item, ast.FunctionDef) and item.name == 'inventory')
    local_predicate = ast.parse(_CURRENT_LOCAL_S_PREDICATE, mode='eval').body
    predicate_key = ast.dump(local_predicate, include_attributes=False)
    guarded_comparisons = [item for item in ast.walk(inventory_node)
        if isinstance(item, ast.Call) and isinstance(item.func, ast.Name)
        and item.func.id == 'require' and len(item.args) == 2
        and ast.dump(item.args[0], include_attributes=False) == predicate_key
        and isinstance(item.args[1], ast.Constant)
        and item.args[1].value == 'unreviewed supplied score-helper source']
    case.assertEqual(len(guarded_comparisons), 1)
    case.assertIsInstance(guarded_comparisons[0].args[0], ast.BoolOp)
    case.assertIsInstance(guarded_comparisons[0].args[0].op, ast.And)
    local_call = guarded_comparisons[0].args[0].values[0].left
    local_span = (local_call.lineno, local_call.end_lineno,
                  local_call.col_offset, local_call.end_col_offset)

    reads, streams, observation_events, match_events, primitive_entries = [], [], [], [], []
    boundary_entries = []
    leases = []
    read_index, stream_index, stream_value_index, publish_replays = {}, {}, {}, {}
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

    def publish_occurrence(operation, path, value, mode, frame):
        publish = inspect.unwrap(type(operation)._publish)
        if frame.f_code is not publish.__code__ or frame.f_globals is not publish.__globals__:
            return None, None
        case.assertIn(frame.f_code, original_family(frame, '_InvariantInputs._publish'))
        case.assertIs(frame.f_locals['self'], operation)
        case.assertIs(frame.f_locals['value'], value)
        case.assertEqual((frame.f_locals['path'], frame.f_locals['mode']), (path, mode))
        case.assertEqual(operation._state, 'active')
        case.assertTrue(operation._capturing)
        replay = publish_replays.setdefault(id(frame), {'frame': frame, 'next': 0})
        case.assertIs(replay['frame'], frame)
        queued = operation._observations[replay['next']]
        case.assertEqual((queued[0], queued[2]), (path, mode))
        case.assertIs(queued[1], value)
        return queued, replay

    def queued_stream(operation, path, value, queued):
        if queued is None:
            return None
        candidates = [item for item in stream_value_index.get((id(operation), path, id(value)), ())
                      if item['operation'] is operation and item['observed_value'] is value
                      and item['observed'] and item['queued_tuple'] is queued
                      and not item['matched']]
        case.assertLessEqual(len(candidates), 1, 'ambiguous retained stream observation')
        if not candidates:
            return None
        return candidates[0]

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
                case.assertNotEqual(found[3], 'local_raw_residual',
                    'cleanup local comparator entered an owned route; review its binding')
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
            queued_count = len(operation._observations) if stream is not None and phase == 'pending' else None
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
                stream['observed_value'] = value
                stream['observation_phase'] = phase
                stream['queued_tuple'] = None
                if queued_count is not None:
                    case.assertEqual(len(operation._observations), queued_count + 1)
                    queued = operation._observations[queued_count]
                    case.assertEqual((queued[0], queued[2]), (path, mode))
                    case.assertIs(queued[1], value)
                    stream['queued_tuple'] = queued
                    stream['queued_index'] = queued_count
                stream_value_index.setdefault((id(operation), path, id(value)), []).append(stream)
            return result
        return observed

    def matcher(original):
        @wraps(original)
        def matched(operation, root, path, value, mode):
            item = latest(operation, path, value, mode)
            queued, replay = publish_occurrence(operation, path, value, mode, sys._getframe(1))
            stream = joined_stream(operation, path, value) if mode == 'bytes' else None
            origin = 'live_original_frame' if stream is not None else None
            if stream is None and mode == 'bytes':
                stream = queued_stream(operation, path, value, queued)
                if stream is not None:
                    origin = 'queued_publish_replay'
            event = {'operation': operation, 'path': path, 'mode': mode,
                     'read_sequence': item['sequence'] if item is not None else None,
                     'returned': False}
            match_events.append(event)
            result = original(operation, root, path, value, mode)
            event['returned'] = True
            if replay is not None:
                replay['next'] += 1
            if item is not None:
                item['matched'] = True
            if stream is not None:
                stream['matched'] = True
                stream['comparison_phase'] = operation._state
                stream['comparison_origin'] = origin
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
                diagnostic = {key: item.get(key) for key in ('path', 'open_site', 'read_site',
                    'phase', 'observation_phase', 'queued_index', 'comparison_origin', 'comparison_phase')}
                diagnostic['route'] = route
                case.assertTrue(item['eof'], diagnostic)
                case.assertTrue(item['requests'], diagnostic)
                case.assertTrue(all(size == 1 << 20 for size in item['requests']), diagnostic)
                case.assertTrue(item['stream'].closed, diagnostic)
                case.assertTrue(item['observed'], diagnostic)
                case.assertTrue(item['matched'], diagnostic)
                case.assertIs(type(item['observed_value']), bytes, diagnostic)
                case.assertEqual(item['comparison_phase'], 'active', diagnostic)
                case.assertEqual(item['comparison_origin'], 'queued_publish_replay'
                    if item['observation_phase'] == 'pending' else 'live_original_frame', diagnostic)
                if item['observation_phase'] == 'pending':
                    case.assertIs(item['queued_tuple'][1], item['observed_value'], diagnostic)
                case.assertTrue(all(event['returned'] for event in item['read_calls']), diagnostic)
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
                    'stream_binding_counts': [
                        [path, observation_phase, comparison_origin, comparison_phase, count]
                        for (path, observation_phase, comparison_origin, comparison_phase), count
                        in sorted(Counter((item['path'], item['observation_phase'],
                            item['comparison_origin'], item['comparison_phase'])
                            for item in actual_streams).items())],
                    'original_streams': len(actual_streams)}
        try:
            yield summarize
        finally:
            # Release retained values and executing frames after this owner,
            # including a failed positive run. None survives into another call.
            read_index.clear()
            stream_index.clear()
            stream_value_index.clear()
            publish_replays.clear()
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
        import check_runtime_support as runtime
        import check_sampled_values as sampled
        loops, coverage_core = self.coverage()
        code_root = Path(__file__).resolve().parents[2]
        routes = (
            ('invariant', cleanup, lambda: invariant.verify(self.root)),
            ('winner', cleanup, lambda: winner.verify(self.root)),
            ('runtime', cleanup, lambda: runtime.verify(self.root)),
            ('sampled', cleanup, lambda: sampled.verify(self.root)),
            ('map_loops', coverage_core, lambda: loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map')),
            ('rtree_loops', coverage_core, lambda: loops.reviewed_nonempty_loops(self.root, 'extensions/carla/rtree')),
        )
        owners = []
        for kind, core, run in routes:
            with self.subTest(owner=kind):
                with self.audit(core) as events, _operation_reached_bindings(
                        self, code_root, self.root, (cleanup, coverage_core)) as summarize:
                    result = run()
                    self.assertTrue(result)
                    operation = self.assert_one_owner(events, kind, core)
                    self.assertTrue(all(operation is not previous for previous in owners))
                    owners.append(operation)
                    report = summarize(operation, kind)
                    for suffix in ('typed-marker-first', 'typed-source-first',
                                   'typed-bound-input-first', 'typed-bound-input-final'):
                        self.assertIn('tools/carla_lane_oracle/full_audit_cleanup_contracts.py:' + suffix,
                                      report['reached_sites'])
                    if kind in ('invariant', 'winner', 'runtime', 'sampled'):
                        for suffix in ('typed-provenance-first', 'typed-provenance-final'):
                            self.assertIn('tools/carla_lane_oracle/full_audit_cleanup_contracts.py:' + suffix,
                                          report['reached_sites'])
                    if kind in ('runtime', 'sampled'):
                        self.assertTrue({kind, 'invariant'} <= events['frames'])
                        self.assertEqual(set(result['typed_boundary_successors']), set(cleanup.typed_boundary.SOURCE_PATHS))
                        for path, edge in result['typed_boundary_successors'].items():
                            self.assertEqual(edge['after_sha256'], hashlib.sha256((self.root/path).read_bytes()).hexdigest())
                        for suffix in ('typed-sum2-source-batch', 'typed-sum2-pin', 'typed-sum2-interval'):
                            self.assertIn('tools/carla_lane_oracle/sum2_contracts.py:' + suffix, report['reached_sites'])
                    if kind == 'runtime':
                        for suffix in ('typed-heading-producer', 'typed-heading-consumers', 'typed-heading-eligibility'):
                            self.assertIn('tools/carla_lane_oracle/heading_correspondence.py:' + suffix, report['reached_sites'])
                        for suffix in ('typed-runtime-body', 'typed-runtime-callers', 'typed-runtime-reference'):
                            self.assertIn('tools/carla_lane_oracle/optional_runtime_contracts.py:' + suffix, report['reached_sites'])
                    if kind == 'sampled':
                        for suffix in ('typed-sampled-initial-batch', 'typed-sampled-final-sources'):
                            self.assertIn('tools/carla_lane_oracle/check_sampled_values.py:' + suffix, report['reached_sites'])
                    if kind == 'map_loops':
                        self.assertIn('tools/coverage_loop_proofs.py:typed-source-final', report['reached_sites'])
                    # These shared-helper theorem branches remain outside the
                    # six owned routes. The typed/cleanup rereads are current. Never report them as exercised owner
                    # observations merely because their AST addresses exist.
                    self.assertLessEqual({
                        'tools/coverage_loop_proofs.py:' + suffix for suffix in (
                            'shared-helper-source-final',
                            'shared-helper-checker-first', 'shared-helper-checker-final',
                            'shared-helper-provider-first', 'shared-helper-provider-final',
                            'shared-helper-package-first')},
                        set(report['residual_unreached_sites']))
                print('OPERATION_REACHED_BINDINGS ' + json.dumps(report, sort_keys=True))



# Distinct consumed-input mechanisms. Source-only proposal; gate/authority paths
# are always original. See the separately frozen 8-method / 18-owner plan.


def _checker_source_predecessor(name, raw):
    """Invert enumerated complete checker edits; retain every untouched byte.

    This test-only inverse never supplies a production root or observation.
    Its predecessor digest is the original whole-file pin, including unrelated
    functions. Mapping ranges address current physical calls from old site IDs.
    """
    if type(raw) is not bytes:
        raise AssertionError('checker source must be physical builtin bytes')
    lines = raw.decode('utf-8').splitlines(keepends=True)
    result, mapping, cursor = [], {}, 0
    for start, stop, before, after in _TYPED_CHECKER_SOURCE_EDITS[name]:
        if not cursor <= start <= stop <= len(lines) or tuple(lines[start:stop]) != after:
            raise AssertionError(('unreviewed checker successor span', name, start, stop))
        for current in range(cursor, start):
            mapping[len(result) + 1] = (current + 1, current + 1)
            result.append(lines[current])
        for line in before:
            mapping[len(result) + 1] = (start + 1, stop)
            result.append(line)
        cursor = stop
    for current in range(cursor, len(lines)):
        mapping[len(result) + 1] = (current + 1, current + 1)
        result.append(lines[current])
    predecessor = ''.join(result).encode('utf-8')
    if hashlib.sha256(predecessor).hexdigest() != BoundedOwnerDistinctMechanismControls._SOURCE_SHA256[name]:
        raise AssertionError(('whole predecessor checker bytes changed', name))
    return predecessor, mapping


_CURRENT_LOCAL_S_PREDICATE = (
    'source.token_sha256(text) == source.token_sha256('
    '_inputs.text_default(_input_owner, root, rel.as_posix())) '
    'and source.token_sha256(_typed_source.historical_text(root, rel.as_posix(), text, '
    '_operation=_operation, _inputs=_inputs, _input_owner=_input_owner)) '
    '== seed_count.score_family_token_sha256(hashlib.sha256(provenance).hexdigest())')
_CURRENT_LOCAL_S_REQUIRE = "require(" + _CURRENT_LOCAL_S_PREDICATE + ", 'unreviewed supplied score-helper source')"


# BEGIN REVIEWED #333 CHECKER SOURCE INVERSE
_TYPED_CHECKER_SOURCE_EDITS = {
    'accepted_successor_contracts.py': (
        (3, 8,
         (),
         (
          'if __package__:\n',
          '    from . import source_contracts as _typed_source\n',
          'else:\n',
          '    import source_contracts as _typed_source\n',
          '\n',
         ),
        ),
        (9, 10,
         (),
         (
          '# #333 explicit historical provenance views; current inputs remain operation-owned.\n',
         ),
        ),
        (55, 56,
         (),
         (
          '\n',
         ),
        ),
        (62, 63,
         (
          '    payload = (root/MIGRATION).read_bytes()\n',
         ),
         (
          '    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())\n',
         ),
        ),
        (68, 69,
         (
          "    require(hashlib.sha256((root/'tools/carla_lane_oracle/coverage-followup-migration.json').read_bytes()).hexdigest()\n",
         ),
         (
          "    require(hashlib.sha256(_typed_source.historical_bytes(root, root/'tools/carla_lane_oracle/coverage-followup-migration.json', (root/'tools/carla_lane_oracle/coverage-followup-migration.json').read_bytes())).hexdigest()\n",
         ),
        ),
        (72, 73,
         (
          "        require(hashlib.sha256((root/'tools/carla_lane_oracle'/name).read_bytes()).hexdigest()\n",
         ),
         (
          "        require(hashlib.sha256(_typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/name, (root/'tools/carla_lane_oracle'/name).read_bytes())).hexdigest()\n",
         ),
        ),
        (87, 88,
         (
          "        require(source.token_sha256(_observe_text(root, path, (root/path).read_text(), _operation=_operation)) == item['after_token_sha256'],\n",
         ),
         (
          "        require(source.token_sha256(_typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)) == item['after_token_sha256'],\n",
         ),
        ),
        (132, 133,
         (
          "        payload = full_audit._observe_bytes(root, 'tools/carla_lane_oracle/'+filename, payload, _operation=_operation)\n",
         ),
         (
          "        payload = _typed_source.historical_bytes(root, 'tools/carla_lane_oracle/'+filename, full_audit._observe_bytes(root, 'tools/carla_lane_oracle/'+filename, payload, _operation=_operation), _operation=_operation)\n",
         ),
        ),
        (167, 176,
         (
          "    for path, item in record['sources'].items():\n",
          "        require(source.token_sha256(_observe_text(root, path, (root/path).read_text(), _operation=_operation)) == item['after_token_sha256'],\n",
          "                'unreviewed complete successor: ' + path)\n",
          "        require(hashlib.sha256(item['before_complete_module'].encode()).hexdigest()\n",
          "                == item['before_sha256'], 'historical module changed: ' + path)\n",
         ),
         (
          '    try:\n',
          "        for path, item in record['sources'].items():\n",
          "            require(source.token_sha256(_typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)) == item['after_token_sha256'],\n",
          "                    'unreviewed complete successor: ' + path)\n",
          "            require(hashlib.sha256(item['before_complete_module'].encode()).hexdigest()\n",
          "                    == item['before_sha256'], 'historical module changed: ' + path)\n",
          '    except ValueError as error:\n',
          '        raise ValueError(\n',
          "            'unreviewed complete successor: ' + str(error)) from error\n",
         ),
        ),
        (228, 229,
         (
          '        full_audit._observe_bytes(root, relative, payload, _operation=_operation)\n',
         ),
         (
          '        _typed_source.historical_bytes(root, relative, full_audit._observe_bytes(root, relative, payload, _operation=_operation), _operation=_operation)\n',
         ),
        ),
        (256, 257,
         (
          "        runtime_raw = (root/'tools/carla_lane_oracle'/runtime_name).read_bytes()\n",
         ),
         (
          "        runtime_raw = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/runtime_name, (root/'tools/carla_lane_oracle'/runtime_name).read_bytes())\n",
         ),
        ),
        (263, 264,
         (
          "        guard_raw = (root/'tools/carla_lane_oracle'/guard_name).read_bytes()\n",
         ),
         (
          "        guard_raw = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/guard_name, (root/'tools/carla_lane_oracle'/guard_name).read_bytes())\n",
         ),
        ),
        (302, 303,
         (
          "        runtime_raw = (root/'tools/carla_lane_oracle'/runtime_name).read_bytes()\n",
         ),
         (
          "        runtime_raw = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/runtime_name, (root/'tools/carla_lane_oracle'/runtime_name).read_bytes(), _operation=_operation)\n",
         ),
        ),
        (309, 310,
         (
          "        guard_raw = (root/'tools/carla_lane_oracle'/guard_name).read_bytes()\n",
         ),
         (
          "        guard_raw = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/guard_name, (root/'tools/carla_lane_oracle'/guard_name).read_bytes(), _operation=_operation)\n",
         ),
        ),
    ),
    'cache_key_contracts.py': (
        (10, 15,
         (),
         (
          'if __package__:\n',
          '    from . import source_contracts as _typed_source\n',
          'else:\n',
          '    import source_contracts as _typed_source\n',
          '\n',
         ),
        ),
        (115, 118,
         (
          '            require(hashlib.sha256(physical).hexdigest() in {seed_count.SCORE_AFTER_SHA256, seed_count.station.AFTER_SHA256, seed_count.deviation.AFTER_SHA256},\n',
         ),
         (
          '            provenance = _typed_source.historical_bytes(root, rel.as_posix(), physical,\n',
          '                _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)\n',
          '            require(hashlib.sha256(provenance).hexdigest() in {seed_count.SCORE_AFTER_SHA256, seed_count.station.AFTER_SHA256, seed_count.deviation.AFTER_SHA256},\n',
         ),
        ),
        (121, 124,
         (
          '                    == seed_count.score_family_token_sha256(hashlib.sha256(physical).hexdigest()),\n',
         ),
         (
          '                    and source.token_sha256(_typed_source.historical_text(root, rel.as_posix(), text,\n',
          '                        _operation=_operation, _inputs=_inputs, _input_owner=_input_owner))\n',
          '                    == seed_count.score_family_token_sha256(hashlib.sha256(provenance).hexdigest()),\n',
         ),
        ),
        (127, 130,
         (),
         (
          '        supplied_text = text\n',
          '        text = _typed_source.historical_text(root, rel.as_posix(), text, _operation=_operation,\n',
          '                                              _inputs=_inputs, _input_owner=_input_owner)\n',
         ),
        ),
        (144, 147,
         (
          '            physical_digest = hashlib.sha256(physical).hexdigest()\n',
         ),
         (
          '            provenance = _typed_source.historical_bytes(root, rel.as_posix(), physical,\n',
          '                _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)\n',
          '            physical_digest = hashlib.sha256(provenance).hexdigest()\n',
         ),
        ),
        (152, 154,
         (
          '                require(supplied_tokens == seed_count.score_family_token_sha256(physical_digest),\n',
         ),
         (
          "                require(source.token_sha256(supplied_text) == source.token_sha256(physical.decode('utf-8'))\n",
          '                        and supplied_tokens == seed_count.score_family_token_sha256(physical_digest),\n',
         ),
        ),
        (167, 168,
         (
          "                text = seed_count.score_family_predecessor_source(physical.decode('utf-8'))\n",
         ),
         (
          "                text = seed_count.score_family_predecessor_source(provenance.decode('utf-8'))\n",
         ),
        ),
        (282, 286,
         (),
         (
          '    text = _typed_source.historical_text(root, MODULE, text, _operation=_operation)\n',
          '    observed = _typed_source.historical_text(root, MODULE, observed, _operation=_operation)\n',
          '    require(source.token_sha256(text) == source.token_sha256(observed),\n',
          "            'unreviewed supplied lane source')\n",
         ),
        ),
    ),
    'coverage_followup_contracts.py': (
        (3, 8,
         (),
         (
          'if __package__:\n',
          '    from . import source_contracts as _typed_source\n',
          'else:\n',
          '    import source_contracts as _typed_source\n',
          '\n',
         ),
        ),
        (9, 10,
         (),
         (
          '# #333 explicit historical provenance views; current inputs remain operation-owned.\n',
         ),
        ),
        (64, 65,
         (),
         (
          '\n',
         ),
        ),
        (70, 71,
         (
          '    payload = (root/MIGRATION).read_bytes()\n',
         ),
         (
          '    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())\n',
         ),
        ),
        (76, 77,
         (
          '    require(hashlib.sha256(prior.read_bytes()).hexdigest() ==\n',
         ),
         (
          '    require(hashlib.sha256(_typed_source.historical_bytes(root, prior, prior.read_bytes())).hexdigest() ==\n',
         ),
        ),
        (79, 80,
         (
          "        require(hashlib.sha256((root/'tools/carla_lane_oracle'/name).read_bytes()).hexdigest()\n",
         ),
         (
          "        require(hashlib.sha256(_typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/name, (root/'tools/carla_lane_oracle'/name).read_bytes())).hexdigest()\n",
         ),
        ),
        (104, 117,
         (),
         (
          'def _source_view(root, path, physical_text, *, _operation=None):\n',
          '    """Keep supplied physical views only for the helper\'s named authority domain."""\n',
          '    if __package__:\n',
          '        from . import full_audit_cleanup_contracts as cleanup\n',
          '    else:\n',
          '        import full_audit_cleanup_contracts as cleanup\n',
          '    if path == cache_key.MODULE or path in cleanup.SOURCE_PATHS:\n',
          '        return cache_key.reviewed_text(root, path, physical_text, _operation=_operation)\n',
          '    historical = _typed_source.historical_text(root, path, physical_text, _operation=_operation)\n',
          "    # For unrelated modules cache_key's historical API is an identity function.\n",
          '    return cache_key.reviewed_text(root, path, historical, _operation=_operation)\n',
          '\n',
          '\n',
         ),
        ),
        (127, 128,
         (
          "        require(source.token_sha256(accepted.predecessor_text(root, path, **operation_args) if path in accepted.SOURCE_PATHS else cache_key.reviewed_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), **operation_args)) == item['after_token_sha256'],\n",
         ),
         (
          "        require(source.token_sha256(accepted.predecessor_text(root, path, **operation_args) if path in accepted.SOURCE_PATHS else _source_view(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), **operation_args)) == item['after_token_sha256'],\n",
         ),
        ),
    ),
    'coverage_loop_proofs.py': (
        (330, 409,
         (),
         (
          '\n',
          '\n',
          '# #333 transports only these reviewed theorem sites from exact main2d81.\n',
          '# The complete current scalar/bound/API graph is admitted first. Pure row\n',
          '# correspondence cannot itself grant a coverage mask or source receipt.\n',
          "_TYPED_LOOP_MAIN_SHA256 = {'extensions/carla/curve_rounded_arc.mojo': '7bc84049fed26cb7b14b4fa4603ee36d55cdeb7055c62df50cf10d6a2ce90745',\n",
          " 'extensions/carla/curve_rounded_line.mojo': '6741ad9d7434c08070de3c959cb49ac42939ac633d1dcd48c9f5cdfdaa719aed',\n",
          " 'extensions/carla/curve_sample_dispatch.mojo': '91ede65bbc39ac57ca54239513b462d3c71e90cacd085b8bafb2bff514767a86',\n",
          " 'extensions/carla/junction_bounds.mojo': 'd8b7a6de8e495ab16f0cbe9688459eb544ac9ef6c8ec0c44c952ed5b4743a615',\n",
          " 'extensions/carla/lane_refinement.mojo': '13ae6d4658458a7d243597428eee762f9bbc40f8fe3507a47beac9ebd4ac1737',\n",
          " 'extensions/carla/map.mojo': '0e2d282fcd6c70217e7413b7febe40619af070f7adbeaefa3fd56d95562c404b',\n",
          " 'extensions/carla/opendrive.mojo': '9ff9b750af2c1c1a92fe3f3dfe1e49566e9d6f8c39a3576e0d4cf542bc8cdc28',\n",
          " 'extensions/carla/rtree.mojo': 'be63ea929c25e0a55600d19568e5f8a117e2f712850ea3da0d977c39b002d460'}\n",
          "_TYPED_LOOP_ROWS = {('extensions/carla/curve_rounded_arc', 228): (228, (), '_rounded_arc_context'),\n",
          " ('extensions/carla/curve_rounded_line', 93): (93, (), '_rounded_line_axis_context'),\n",
          " ('extensions/carla/curve_sample_dispatch', 126): (126, (), '_try_sample_dispatch_cuts'),\n",
          " ('extensions/carla/junction_bounds', 706): (706, (), '_lane_section_box_with_work'),\n",
          " ('extensions/carla/lane_refinement', 145): (146, (), '_axis_lane_minimum'),\n",
          " ('extensions/carla/lane_refinement', 726): (736, (), '_lane_certificate_dominates_cells'),\n",
          " ('extensions/carla/lane_refinement', 1289): (1299, (), '_continue_lane_certificate'),\n",
          " ('extensions/carla/lane_refinement', 1314): (1324, (), '_continue_lane_certificate'),\n",
          " ('extensions/carla/map', 1491): (1511, (), '_try_winner_seed'),\n",
          " ('extensions/carla/map', 2272): (2294, ('Map',), '_closest_lane_certificate_with_work'),\n",
          " ('extensions/carla/map', 2279): (2301, ('Map',), '_closest_lane_certificate_with_work'),\n",
          " ('extensions/carla/map', 2301): (2323, ('Map',), '_closest_lane_certificate_with_work'),\n",
          " ('extensions/carla/map', 2373): (2395, ('Map',), '_closest_lane_certificate_with_work'),\n",
          " ('extensions/carla/map', 2378): (2400, ('Map',), '_closest_lane_certificate_with_work'),\n",
          " ('extensions/carla/map', 2387): (2409, ('Map',), '_closest_lane_certificate_with_work'),\n",
          " ('extensions/carla/map', 2396): (2418, ('Map',), '_closest_lane_certificate_with_work'),\n",
          " ('extensions/carla/map', 4055): (4106, ('Map',), '_add_segment'),\n",
          " ('extensions/carla/opendrive', 450): (450, (), '_active'),\n",
          " ('extensions/carla/opendrive', 593): (593, (), '_border_widths'),\n",
          " ('extensions/carla/opendrive', 601): (601, (), '_border_widths'),\n",
          " ('extensions/carla/opendrive', 615): (615, (), '_border_widths'),\n",
          " ('extensions/carla/opendrive', 617): (617, (), '_border_widths'),\n",
          " ('extensions/carla/opendrive', 621): (621, (), '_border_widths'),\n",
          " ('extensions/carla/opendrive', 787): (787, (), '_lanes'),\n",
          " ('extensions/carla/rtree', 666): (666, ('_Rtree',), '_nearest_next')}\n",
          '\n',
          '\n',
          'def _typed_loop_row(module, historical_line, expression, current):\n',
          '    """Locate one unchanged loop in its exact reviewed declaration owner.\n',
          '\n',
          '    The whole endpoint and inverse must be sealed. Match the complete ordered\n',
          '    loop-statement inventory of the owner, not just a line or expression.\n',
          '    Owners call this only after physical current graph admission.\n',
          '    """\n',
          '    from carla_lane_oracle import typed_boundary_contracts as typed\n',
          '    from carla_lane_oracle import seed_count_contracts as seed\n',
          '    item = _TYPED_LOOP_ROWS.get((module, historical_line))\n',
          "    name = module + '.mojo'\n",
          '    if item is None or not typed.is_current(name, current):\n',
          '        return None\n',
          '    previous = typed.historical_source(name, current)\n',
          "    if sha256(previous.encode('utf-8')) != _TYPED_LOOP_MAIN_SHA256[name]:\n",
          '        return None\n',
          '    main_line, owner, function = item\n',
          '    before, before_first, before_last = seed._function_span(previous, function, owner)\n',
          '    after, after_first, after_last = seed._function_span(current, function, owner)\n',
          '    old_statements, new_statements = _statements(before), _statements(after)\n',
          "    expected = _statements('for value in ' + expression + ':\\n    pass\\n')\n",
          '    if old_statements is None or new_statements is None or expected is None:\n',
          '        return None\n',
          '    def for_rows(statements, first):\n',
          '        return [(first + row[0].start[0], tuple(token.string for token in row))\n',
          "                for row in statements if row[0].string == 'for']\n",
          '    old_rows = for_rows(old_statements, before_first)\n',
          '    new_rows = for_rows(new_statements, after_first)\n',
          '    if [words for _, words in old_rows] != [words for _, words in new_rows]:\n',
          '        return None\n',
          '    selected = [(index, words) for index, (line, words) in enumerate(old_rows)\n',
          '                if line == main_line]\n',
          '    if len(selected) != 1:\n',
          '        return None\n',
          '    index, words = selected[0]\n',
          "    if len(words) < 5 or words[2] != 'in' or words[-1] != ':' or words[3:-1] != tuple(\n",
          '            token.string for token in expected[0])[3:-1]:\n',
          '        return None\n',
          '    return new_rows[index][0]\n',
         ),
        ),
        (984, 999,
         (),
         (
          '        physical_digest = digest\n',
          '        from carla_lane_oracle import typed_boundary_contracts as typed\n',
          '        if typed.is_current(name, raw):\n',
          '            from carla_lane_oracle import full_audit_cleanup_contracts as cleanup\n',
          '            current_bindings = cleanup.proof_bindings(\n',
          '                root, include_roots=include_roots, **operation_args)\n',
          '            if (current_bindings.get(name) != physical_digest\n',
          '                    or _coverage_observe_bytes(root, name, path.read_bytes(),\n',
          '                        _operation=_operation) != raw):\n',
          '                return None\n',
          '            actual.update(current_bindings)\n',
          '            # The current numerical/API graph was physically admitted above.\n',
          '            # This exact inverse now supplies historical provenance only.\n',
          "            checked = typed.historical_source(name, raw.decode('utf-8'))\n",
          "            digest = sha256(checked.encode('utf-8'))\n",
         ),
        ),
        (1005, 1006,
         (
          '            actual[name] = digest\n',
         ),
         (
          '            actual[name] = physical_digest\n',
         ),
        ),
        (1064, 1065,
         (
          '                actual[name] = digest\n',
         ),
         (
          '                actual[name] = physical_digest\n',
         ),
        ),
        (1069, 1073,
         (
          '                actual.update(cleanup.proof_bindings(root, include_roots=include_roots))\n',
          '                if path.read_bytes() != raw:\n',
         ),
         (
          '                actual.update(cleanup.proof_bindings(\n',
          '                    root, include_roots=include_roots, **operation_args))\n',
          '                if _coverage_observe_bytes(root, name, path.read_bytes(),\n',
          '                                           _operation=_operation) != raw:\n',
         ),
        ),
        (1074, 1075,
         (
          '                actual[name] = digest\n',
         ),
         (
          '                actual[name] = physical_digest\n',
         ),
        ),
        (1093, 1094,
         (
          '        actual[name] = digest\n',
         ),
         (
          '        actual[name] = physical_digest\n',
         ),
        ),
        (1095, 1109,
         (),
         (
          '\n',
          '\n',
          'def _final_unowned_typed_loop_bindings(root, bindings, *, include_roots=()):\n',
          '    """Fresh final topology/caller admission after current lexical transport.\n',
          '\n',
          '    This helper is only for unowned standalone rows. Map/R-tree retain their\n',
          '    existing owning operation and sticky finalization; no kind is broadened.\n',
          '    """\n',
          '    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup\n',
          '    fresh = cleanup.proof_bindings(root, include_roots=include_roots)\n',
          '    if any(bindings.get(name) != digest for name,digest in fresh.items()):\n',
          '        return False\n',
          '    return all(sha256(relative_source(root,name).read_bytes()) == digest\n',
          '               for name,digest in bindings.items())\n',
         ),
        ),
        (1154, 1182,
         (
          '    return {line: {\n',
          "        'line': line, 'kind': kind, 'cardinality': minimum,\n",
          "        'maximum_cardinality': maximum, 'required': 'T', 'impossible': 'F',\n",
          "        'expression': expression, 'proof_id': proof_id,\n",
          "        'dependency_sha256': actual,\n",
          '    } for line, kind, minimum, maximum, expression, proof_id in sites}\n',
         ),
         (
          '    try:\n',
          '        result = {}\n',
          '        from carla_lane_oracle import typed_boundary_contracts as typed\n',
          "        name = module + '.mojo'\n",
          '        current = _coverage_observe_text(root, name,\n',
          '            relative_source(root, name, **operation_args).read_text(), _operation=_operation)\n',
          "        if sha256(current.encode('utf-8')) != actual[name]:\n",
          '            return {}\n',
          '        for line, kind, minimum, maximum, expression, proof_id in sites:\n',
          '            if typed.is_current(name, current):\n',
          '                line = _typed_loop_row(module, line, expression, current)\n',
          '                if line is None:\n',
          '                    return {}\n',
          '            result[line] = {\n',
          "                'line': line, 'kind': kind, 'cardinality': minimum,\n",
          "                'maximum_cardinality': maximum, 'required': 'T', 'impossible': 'F',\n",
          "                'expression': expression, 'proof_id': proof_id,\n",
          "                'dependency_sha256': actual,\n",
          '            }\n',
          '        if (typed.is_current(name, current) and _operation is None\n',
          '                and not _final_unowned_typed_loop_bindings(\n',
          '                    root, actual, include_roots=include_roots)):\n',
          '            return {}\n',
          '        return result\n',
          '    except (OSError, ValueError, ImportError, UnicodeError) as error:\n',
          '        if _operation is not None and isinstance(error, (OSError, UnicodeError)):\n',
          '            cleanup._operation_fail(_operation, error)\n',
          '        return {}\n',
         ),
        ),
        (1201, 1214,
         (
          "        if (module == 'extensions/carla/map'\n",
         ),
         (
          '        from carla_lane_oracle import typed_boundary_contracts as typed\n',
          "        module_path = module + '.mojo'\n",
          '        current = _coverage_observe_text(root, module_path,\n',
          '            relative_source(root, module_path, **operation_args).read_text(),\n',
          '            _operation=_operation)\n',
          "        if sha256(current.encode('utf-8')) != actual_bindings[module_path]:\n",
          '            return None\n',
          '        typed_current = typed.is_current(module_path, current)\n',
          '        if typed_current:\n',
          '            line = _typed_loop_row(module, line, expression, current)\n',
          '            if line is None:\n',
          '                return None\n',
          "        if (not typed_current and module == 'extensions/carla/map'\n",
         ),
        ),
        (1233, 1234,
         (
          '        if ((module, line) in _CLEANUP_LOOP_ROWS\n',
         ),
         (
          '        if (not typed_current and (module, line) in _CLEANUP_LOOP_ROWS\n',
         ),
        ),
        (1242, 1247,
         (),
         (
          '            paths = tuple(cache_key.input_paths(Path(root)))\n',
          '            if _operation is not None:\n',
          '                cleanup._operation_known_paths(root, frozenset(\n',
          "                    path.as_posix() for path in paths if path.suffix == '.mojo'),\n",
          '                    _operation=_operation)\n',
         ),
        ),
        (1248, 1249,
         (
          '                path.as_posix() for path in cache_key.input_paths(Path(root))\n',
         ),
         (
          '                path.as_posix() for path in paths\n',
         ),
        ),
        (1250, 1253,
         (
          '                and re.search(pattern,\n',
          '                              relative_source(root, path.as_posix()).read_text())\n',
         ),
         (
          '                and re.search(pattern, _coverage_observe_text(root, path.as_posix(),\n',
          '                    relative_source(root, path.as_posix(), **operation_args).read_text(),\n',
          '                    _operation=_operation))\n',
         ),
        ),
        (1272, 1276,
         (),
         (
          '        if (typed_current and _operation is None\n',
          '                and not _final_unowned_typed_loop_bindings(\n',
          '                    root, actual_bindings, include_roots=include_roots)):\n',
          '            return None\n',
         ),
        ),
        (1416, 1472,
         (),
         (
          'def _typed_construction_boundary_loops(root, current, *, include_roots=(), _operation=None):\n',
          '    """Re-admit the nonempty-list theorem for the exact typed current graph.\n',
          '\n',
          '    Successful same-owner _build_transform still calls the concrete private\n',
          '    Road implementation and rejects a missing geometry before success. The\n',
          '    boundary producer still appends that geometry into a fresh owned list.\n',
          '    Numerical value changes and new early refusals do not weaken this fact.\n',
          '    """\n',
          '    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup\n',
          '    from carla_lane_oracle import typed_boundary_contracts as typed\n',
          "    operation_args = {} if _operation is None else {'_operation': _operation}\n",
          '    bindings = cleanup.proof_bindings(root, include_roots=include_roots, **operation_args)\n',
          "    name = 'extensions/carla/map.mojo'\n",
          "    if (bindings.get(name) != sha256(current.encode('utf-8'))\n",
          '            or not typed.is_current(name, current)):\n',
          '        return {}\n',
          "    line = _typed_loop_row('extensions/carla/map', CONSTRUCTION_BOUNDARY_LINE,\n",
          "                           'boundaries', current)\n",
          '    if line is None:\n',
          '        return {}\n',
          '    # Preserve the actual whole-maintained-source caller census. A pure\n',
          '    # historical view cannot hide a new caller, alias, package, or std shadow.\n',
          '    for location in (root, *include_roots):\n',
          '        if (not _density_stdlib_unshadowed(location, **operation_args)\n',
          '                or not _construction_boundary_callers(location, **operation_args)):\n',
          '            return {}\n',
          '    if (_operation is None and not _final_unowned_typed_loop_bindings(\n',
          '            root, bindings, include_roots=include_roots)):\n',
          '        return {}\n',
          '    # The receipt has disjoint executing-checker and source-input domains.\n',
          '    # Recheck both physical images. A checker copy is not a source observation;\n',
          '    # the owner separately retains this consumed premise through finalization.\n',
          '    try:\n',
          '        executing = cleanup.executing_checker_bindings(root)\n',
          '        cleanup.require(all(bindings.get(path) == digest\n',
          '                            for path, digest in executing.items()),\n',
          "                        'construction receipt checker image changed')\n",
          '    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:\n',
          '        cleanup._operation_fail(_operation, error)\n',
          '    for path, expected in bindings.items():\n',
          '        if path in executing:\n',
          '            continue\n',
          '        raw = _coverage_observe_bytes(root, path,\n',
          '            relative_source(root, path, **operation_args).read_bytes(),\n',
          '            _operation=_operation)\n',
          '        if sha256(raw) != expected:\n',
          '            return {}\n',
          '    return {line: {\n',
          "        'line': line, 'kind': 'reviewed-nonempty-iterator', 'cardinality': 1,\n",
          "        'minimum_cardinality': 1, 'maximum_cardinality': None,\n",
          "        'required': 'T', 'impossible': 'F', 'expression': 'boundaries',\n",
          "        'proof_id': 'construction-geometry-boundary-list',\n",
          "        'dependency_sha256': bindings,\n",
          '    }}\n',
          '\n',
          '\n',
         ),
        ),
        (1482, 1490,
         (),
         (
          '        from carla_lane_oracle import typed_boundary_contracts as typed\n',
          "        name = 'extensions/carla/map.mojo'\n",
          '        current = _coverage_observe_text(root, name,\n',
          '            relative_source(root, name, **operation_args).read_text(),\n',
          '            _operation=_operation)\n',
          '        if typed.is_current(name, current):\n',
          '            return _typed_construction_boundary_loops(\n',
          '                root, current, include_roots=include_roots, **operation_args)\n',
         ),
        ),
    ),
    'full_audit_cleanup_contracts.py': (
        (50, 52,
         (),
         (
          '        from . import typed_boundary_contracts as typed_boundary\n',
          '        from . import conditioned_cubic_contracts as conditioned_cubic\n',
         ),
        ),
        (61, 63,
         (),
         (
          '        import typed_boundary_contracts as typed_boundary\n',
          '        import conditioned_cubic_contracts as conditioned_cubic\n',
         ),
        ),
        (143, 150,
         (
          "DEPENDENCY_TOOL_SHA256 = {'tools/carla_lane_oracle/witness_format_contracts.py': 'a76ba6d5bf18be80c151fd03ea7a7ebeb75af1c1ed8af1600037d5f75ac13cb3',\n",
          " 'tools/carla_lane_oracle/runtime_view_contracts.py': '0afad70cdd83529e89550aaca0c1a469e2b25ca963a90e2b7b17e1a2fd324193',\n",
         ),
         (
          "DEPENDENCY_TOOL_SHA256 = {'tools/affected.py': 'a56194a3e722ad341a42f3defec282b8154f5e4db8340df855f0199ea9830ebb',\n",
          " 'tools/cache_key.py': 'ec06247feb8fe079c30b6da19fc655ffec363f1ce8e3372d063bf728e8c804c4',\n",
          " 'tools/carla_lane_oracle/conditioned_cubic_contracts.py': 'df99ea0826d5efa936c56e4ece9aa79b41806b60e52121c4f564a8de5d5b0198',\n",
          " 'tools/carla_lane_oracle/consumer_successor_ledger.py': 'ce9a639084dfcc1442c6ac7535060cf5a123c2eb96683d2f35816ec26b0599ed',\n",
          " 'tools/carla_lane_oracle/map_deviation_contracts.py': '741a95b3fd3d0d51253dfef36327997c19ac90b9230a73942dd4697dcefffd39',\n",
          " 'tools/carla_lane_oracle/map_station_contracts.py': 'caca22f46767ced3037d839a7941cb73a8ccf816238ad2037e28715f060055b7',\n",
          " 'tools/carla_lane_oracle/runtime_view_contracts.py': '67316129402fac643be3c6e49ceef94bcb25c1ef92f81fd764a6abb583f89e34',\n",
         ),
        ),
        (151, 155,
         (
          " 'tools/carla_lane_oracle/map_station_contracts.py': 'caca22f46767ced3037d839a7941cb73a8ccf816238ad2037e28715f060055b7',\n",
          " 'tools/carla_lane_oracle/map_deviation_contracts.py': '741a95b3fd3d0d51253dfef36327997c19ac90b9230a73942dd4697dcefffd39',\n",
          " 'tools/carla_lane_oracle/consumer_successor_ledger.py': '8c18296f05a4a5150fc6ef8b4ae287479096b5bcff6f1047c82e6aae405310a1',\n",
          " 'tools/affected.py': 'a56194a3e722ad341a42f3defec282b8154f5e4db8340df855f0199ea9830ebb',\n",
          " 'tools/cache_key.py': 'ec06247feb8fe079c30b6da19fc655ffec363f1ce8e3372d063bf728e8c804c4',\n",
          " 'tools/carla_lane_oracle/source_contracts.py': '857dd399291611dd35e11adbbdde0fca03ed4ff4277eec54ed3ec5815bbaf791',\n",
          " 'tools/carla_lane_oracle/sum2_guard_contracts.py': 'cf9bb32fd36fefb641e2c97210bfffe0fac00b5b773e87b5b19d46877afbf9a4'}\n",
         ),
         (
          " 'tools/carla_lane_oracle/source_contracts.py': 'f3e419be69aed14ab6eb4af13ec50927c58b41b3081cd973f948f958eb1d471a',\n",
          " 'tools/carla_lane_oracle/sum2_guard_contracts.py': 'acbf385486e2b0dfe15a409d039cd31c8e9fed295704bc6adcb4289818b65f63',\n",
          " 'tools/carla_lane_oracle/typed_boundary_contracts.py': '02a632f5e9f3c69be6f32d996e153e6a4fec43c281367e8f1d3a710163f46f22',\n",
          " 'tools/carla_lane_oracle/witness_format_contracts.py': 'a76ba6d5bf18be80c151fd03ea7a7ebeb75af1c1ed8af1600037d5f75ac13cb3'}\n",
         ),
        ),
        (223, 226,
         (
          "                 'tools/carla_lane_oracle/witness_format_contracts.py')\n",
         ),
         (
          "                 'tools/carla_lane_oracle/witness_format_contracts.py',\n",
          "                 'tools/carla_lane_oracle/typed_boundary_contracts.py',\n",
          "                 'tools/carla_lane_oracle/conditioned_cubic_contracts.py')\n",
         ),
        ),
        (692, 693,
         (
          "for _module in (source, guard, _sibling('affected'), _sibling('cache_key'), consumer_ledger, station, shared_helpers, runtime_view, deviation, witness_format):\n",
         ),
         (
          "for _module in (source, guard, _sibling('affected'), _sibling('cache_key'), consumer_ledger, station, shared_helpers, runtime_view, deviation, witness_format, typed_boundary, conditioned_cubic):\n",
         ),
        ),
        (730, 731,
         (
          '               vars(deviation), vars(witness_format))\n',
         ),
         (
          '               vars(deviation), vars(witness_format), vars(typed_boundary), vars(conditioned_cubic))\n',
         ),
        ),
        (761, 763,
         (
          '            supplied = Path(root) / relative\n',
          '            require(not supplied.is_symlink() and sha(supplied.read_bytes()) == captured,\n',
         ),
         (
          '            supplied = _regular(root, relative)\n',
          '            require(sha(supplied.read_bytes()) == captured,\n',
         ),
        ),
        (765, 767,
         (),
         (
          '    typed_boundary.verify_authority()\n',
          '    conditioned_cubic.verify_authority()\n',
         ),
        ),
        (877, 878,
         (
          'def resolver_unshadowed(root, paths, *, render_entries=None):\n',
         ),
         (
          'def resolver_unshadowed(root, paths, *, render_entries=None, typed_entries=None):\n',
         ),
        ),
        (900, 908,
         (),
         (
          '    if typed_entries is not None and (type(typed_entries) is not frozenset\n',
          "            or '.' not in typed_entries or any(type(path) is not str or not path\n",
          "            or Path(path).is_absolute() or '..' in Path(path).parts for path in typed_entries)):\n",
          '        return False\n',
          '    # Only these newly introduced families use the established compiled-entry\n',
          '    # lookup rule. Every pre-333 family keeps its historical refusal policy.\n',
          "    typed_families = ('animation', 'cameras', 'core', 'exporters', 'geometries',\n",
          "                      'lights', 'materials', 'objects', 'postprocessing', 'renderers')\n",
         ),
        ),
        (952, 955,
         (
          '                                     or relative_dir.casefold() in render_entries))\n',
         ),
         (
          '                                     or relative_dir.casefold() in render_entries)\n',
          '                                and (scoped_name not in typed_families or typed_entries is None\n',
          '                                     or relative_dir.casefold() in typed_entries))\n',
         ),
        ),
        (976, 988,
         (
          '    """Restrict only render\'s namespace clause with an established entry census."""\n',
          "    if not any(path.startswith('render/') for path in paths):\n",
         ),
         (
          '    """Scope only reviewed new families with an established entry census.\n',
          '\n',
          '    Exact module and package prefixes never use this namespace-only exception.\n',
          '    The caller checks the complete physical source/entry inventory before and\n',
          '    after the operation; adding a new entry or import cannot reuse this scope.\n',
          '    Include-root calls intentionally omit these arguments and stay conservative.\n',
          '    """\n',
          "    render = any(path.startswith('render/') for path in paths)\n",
          "    typed = any(path.split('/')[0] in ('animation', 'cameras', 'core', 'exporters',\n",
          "        'geometries', 'lights', 'materials', 'objects', 'postprocessing', 'renderers')\n",
          '        for path in paths)\n',
          '    if not render and not typed:\n',
         ),
        ),
        (989, 996,
         (
          "    require(type(entries) in (tuple, list), 'missing render entry census')\n",
          "    return {'render_entries': frozenset(('.', *(path.casefold() for path in entries),\n",
          '        *(str(Path(path).parent).casefold() for path in shared_helpers.TESTS)))}\n',
         ),
         (
          "    require(type(entries) in (tuple, list), 'missing compiled entry census')\n",
          "    roots = frozenset(('.', *(path.casefold() for path in entries),\n",
          '        *(str(Path(path).parent).casefold() for path in shared_helpers.TESTS)))\n',
          '    typed_roots = roots | frozenset(str(Path(path).parent).casefold()\n',
          '                                    for path in typed_boundary.TESTS)\n',
          "    return {**({'render_entries': roots} if render else {}),\n",
          "            **({'typed_entries': typed_roots} if typed else {})}\n",
         ),
        ),
        (1257, 1258,
         (
          '            require(sha(self.raw(owner, root, path)) == AFTER_SHA256[path],\n',
         ),
         (
          "            require(sha(_historical_typed_text(path, self.raw(owner, root, path).decode('utf-8'))) == AFTER_SHA256[path],\n",
         ),
        ),
        (1345, 1349,
         (),
         (
          "        elif kind == 'runtime':\n",
          "            name = 'check_runtime_support'\n",
          "        elif kind == 'sampled':\n",
          "            name = 'check_sampled_values'\n",
         ),
        ),
        (1354, 1356,
         (
          "                'winner': 'winner_sign_contracts', 'border': 'border_parser_contracts'}.get(kind)\n",
         ),
         (
          "                'winner': 'winner_sign_contracts', 'border': 'border_parser_contracts',\n",
          "                'runtime': 'check_runtime_support', 'sampled': 'check_sampled_values'}.get(kind)\n",
         ),
        ),
        (1409, 1411,
         (),
         (
          "                            (prefix + 'check_runtime_support', 'verify'),\n",
          "                            (prefix + 'check_sampled_values', 'verify'),\n",
         ),
        ),
        (1420, 1421,
         (
          "    for kind in ('invariant', 'winner', 'border'):\n",
         ),
         (
          "    for kind in ('invariant', 'winner', 'border', 'runtime', 'sampled'):\n",
         ),
        ),
        (1434, 1436,
         (
          "                                         'border_parser_contracts.py', 'coverage_loop_proofs.py')):\n",
         ),
         (
          "                                         'border_parser_contracts.py', 'check_runtime_support.py',\n",
          "                                         'check_sampled_values.py', 'coverage_loop_proofs.py')):\n",
         ),
        ),
        (1439, 1441,
         (
          "                       ('border', 'border_parser_contracts.py')):\n",
         ),
         (
          "                       ('border', 'border_parser_contracts.py'),\n",
          "                       ('runtime', 'check_runtime_support.py'), ('sampled', 'check_sampled_values.py')):\n",
         ),
        ),
        (1457, 1458,
         (
          "    if kind not in ('invariant', 'border') or operation._kind != 'winner':\n",
         ),
         (
          "    if kind not in ('invariant', 'border') or operation._kind not in ('winner', 'runtime', 'sampled'):\n",
         ),
        ),
        (1505, 1506,
         (
          "                and operation._kind == 'winner', 'invalid private operation wrapper')\n",
         ),
         (
          "                and operation._kind in ('winner', 'runtime', 'sampled'), 'invalid private operation wrapper')\n",
         ),
        ),
        (1517, 1518,
         (
          "        require(kind in ('invariant', 'winner', 'border', 'map_loops', 'rtree_loops'),\n",
         ),
         (
          "        require(kind in ('invariant', 'winner', 'border', 'runtime', 'sampled', 'map_loops', 'rtree_loops'),\n",
         ),
        ),
        (1659, 1660,
         (),
         (
          '        self._checker_receipt = False\n',
         ),
        ),
        (1675, 1694,
         (),
         (
          '        self._checker_receipt = False\n',
          '\n',
          '    def _bind_checker_receipt(self, root, executing):\n',
          '        """Retain only a supplied checker image consumed by this operation."""\n',
          '        try:\n',
          '            self._check_owner(root)\n',
          '            caller = sys._getframe(1)\n',
          '            require(caller.f_globals is globals()\n',
          '                    and caller.f_code is _live_function_code(proof_bindings)\n',
          "                    and caller.f_locals.get('_operation') is self\n",
          '                    and type(executing) is dict\n',
          '                    and type(self._checker_receipt) is bool\n',
          "                    and self._state == 'active' and not self._capturing,\n",
          "                    'checker receipt requires its active proof-binding owner')\n",
          '            require(executing == dict(self._executing),\n',
          "                    'checker receipt differs from captured executing image')\n",
          '            self._checker_receipt = True\n',
          '        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:\n',
          '            _operation_fail(self, error)\n',
         ),
        ),
        (1846, 1849,
         (
          '                    require(sha(self.raw(self._owner, root, path)) == AFTER_SHA256[path],\n',
         ),
         (
          '                    raw = self.raw(self._owner, root, path)\n',
          '                    require(sha(raw) == AFTER_SHA256[path] or (typed_boundary.is_current(path, raw)\n',
          "                            and typed_boundary.edge(path)['before_sha256'] == AFTER_SHA256[path]),\n",
         ),
        ),
        (1865, 1870,
         (),
         (
          '                    require(type(self._checker_receipt) is bool,\n',
          "                            'invalid consumed checker receipt state')\n",
          '                    if self._checker_receipt:\n',
          '                        require(executing_checker_bindings(root) == dict(self._executing),\n',
          "                                'consumed receipt checker changed during owned verification')\n",
         ),
        ),
        (1913, 1914,
         (),
         (
          '        self._checker_receipt = False\n',
         ),
        ),
        (2017, 2017,
         (
          '        require(digest == AFTER_TOKEN_SHA256[path],\n',
          "                'unreviewed supplied successor source: ' + path)\n",
         ),
         (),
        ),
        (2021, 2023,
         (),
         (
          '        require(digest == AFTER_TOKEN_SHA256[path] or typed_boundary.is_current(path, raw),\n',
          "                'unreviewed supplied successor source: ' + path)\n",
         ),
        ),
        (2084, 2085,
         (),
         (
          '    typed_fixtures = {}\n',
         ),
        ),
        (2086, 2096,
         (
          "        require(sha(raw) == expected[path], 'shared-helper fixture changed: ' + path)\n",
         ),
         (
          '        historical = raw\n',
          '        if path in tests and typed_boundary.is_current(path, raw):\n',
          '            # Arithmetic capture has no typed fixture edge. Supplemental native\n',
          '            # fixtures use the complete current graph before exact provenance;\n',
          '            # source/provider extraction identities remain unchanged.\n',
          "            require(_snapshots is None, 'typed fixture entered arithmetic helper capture')\n",
          "            historical = reviewed_typed_text(root, path, raw.decode('utf-8'),\n",
          "                _operation=_operation, _inputs=_inputs, _input_owner=_input_owner).encode('utf-8')\n",
          '            typed_fixtures[path] = raw\n',
          "        require(sha(historical) == expected[path], 'shared-helper fixture changed: ' + path)\n",
         ),
        ),
        (2100, 2104,
         (),
         (
          '    if typed_fixtures and _inputs is None and _operation is None:\n',
          '        # Owned views retain their complete final sweep. A standalone typed\n',
          '        # fixture must join the same physical image at the terminal root gate.\n',
          '        verify(root, exact=True, _expected_sources=typed_fixtures)\n',
         ),
        ),
        (2106, 2107,
         (
          '    return {**expected, **{path: sha(raw) for path, raw in sources.items()}}\n',
         ),
         (
          '    return {path: sha(raw) for path, raw in {**sources, **bound}.items()}\n',
         ),
        ),
        (2187, 2187,
         (
          '    runtime_view.steps(root, _operation=_operation)\n',
         ),
         (),
        ),
        (2192, 2193,
         (),
         (
          '    runtime_view.checked_steps(record)\n',
         ),
        ),
        (2201, 2203,
         (
          "        require(sha(value) == expected, 'runtime view bound input changed: ' + path)\n",
         ),
         (
          "        require(sha(_historical_typed_text(path, value.decode('utf-8'))) == expected,\n",
          "                'runtime view bound input changed: ' + path)\n",
         ),
        ),
        (2206, 2207,
         (
          '        result[path] = expected\n',
         ),
         (
          '        result[path] = sha(value)\n',
         ),
        ),
        (2222, 2225,
         (
          '    if sha(raw) == station.BEFORE_SHA256:\n',
          '        require(source.token_sha256(_physical_text(raw)) == station.BEFORE_TOKEN_SHA256,\n',
         ),
         (
          "    historical = _historical_typed_text(station.MODULE, raw.decode('utf-8'))\n",
          '    if sha(historical) == station.BEFORE_SHA256:\n',
          '        require(source.token_sha256(historical) == station.BEFORE_TOKEN_SHA256,\n',
         ),
        ),
        (2227, 2228,
         (
          '    require(sha(raw) in (station.AFTER_SHA256, deviation.AFTER_SHA256),\n',
         ),
         (
          '    require(sha(historical) in (station.AFTER_SHA256, deviation.AFTER_SHA256),\n',
         ),
        ),
        (2229, 2230,
         (
          "    station.predecessor_source(deviation.station_source(raw.decode('utf-8')))\n",
         ),
         (
          '    station.predecessor_source(deviation.station_source(historical))\n',
         ),
        ),
        (2233, 2234,
         (
          '    if sha(raw) == deviation.AFTER_SHA256:\n',
         ),
         (
          '    if sha(historical) == deviation.AFTER_SHA256:\n',
         ),
        ),
        (2239, 2241,
         (
          "        require(sha(value) == expected, 'station correctness fixture changed: ' + path)\n",
         ),
         (
          "        require(sha(_historical_typed_text(path, value.decode('utf-8'))) == expected,\n",
          "                'station correctness fixture changed: ' + path)\n",
         ),
        ),
        (2244, 2245,
         (
          '        result[path] = expected\n',
         ),
         (
          '        result[path] = sha(value)\n',
         ),
        ),
        (2264, 2266,
         (
          '            digest = sha(raw)\n',
         ),
         (
          "            historical = _historical_typed_text(path, raw.decode('utf-8'))\n",
          '            digest = sha(historical)\n',
         ),
        ),
        (2267, 2268,
         (
          "                require(source.token_sha256(raw.decode('utf-8')) ==\n",
         ),
         (
          '                require(source.token_sha256(historical) ==\n',
         ),
        ),
        (2271, 2272,
         (
          "                witness_format.predecessor_source(path, raw.decode('utf-8'))\n",
         ),
         (
          '                witness_format.predecessor_source(path, historical)\n',
         ),
        ),
        (2273, 2274,
         (
          '            result[path] = digest\n',
         ),
         (
          '            result[path] = sha(raw)\n',
         ),
        ),
        (2280, 2281,
         (
          '                require(type(raw) is bytes and sha(raw) == expected,\n',
         ),
         (
          "                require(type(raw) is bytes and sha(_historical_typed_text(path, raw.decode('utf-8'))) == expected,\n",
         ),
        ),
        (2286, 2287,
         (
          '                result[path] = expected\n',
         ),
         (
          '                result[path] = sha(raw)\n',
         ),
        ),
        (2297, 2393,
         (
          'def verify(root, *, exact=False, include_roots=(), _expected_lane_raw=None, _capture=None):\n',
         ),
         (
          'def _historical_typed_text(path, text):\n',
          '    """Pure named provenance projection; never replace a captured input."""\n',
          '    return typed_boundary.historical_source(str(path), text)\n',
          '\n',
          '\n',
          'def _typed_boundary_bindings(root, *, _snapshots=None, _operation=None):\n',
          '    """Bind the complete new source graph and current native closure once."""\n',
          '    try:\n',
          '        _operation_check(_operation, root)\n',
          "        marker = 'extensions/carla/polynomial.mojo'\n",
          '        marker_raw = _observe_bytes(root, marker, _regular(root, marker).read_bytes(),\n',
          '                                    _operation=_operation)\n',
          '        if not typed_boundary.is_current(marker, marker_raw):\n',
          '            # A local-cubic graph cannot borrow historical polynomial storage.\n',
          '            # Each exact semantic endpoint must advance in the same operation.\n',
          '            for path in conditioned_cubic.SOURCE_PATHS:\n',
          '                raw = marker_raw if path == marker else _observe_bytes(\n',
          '                    root, path, _regular(root, path).read_bytes(), _operation=_operation)\n',
          '                require(not typed_boundary.is_current(path, raw),\n',
          "                        'mixed historical and conditioned source graph: ' + path)\n",
          '            return {}\n',
          '        image = {}\n',
          '        for path in typed_boundary.SOURCE_PATHS:\n',
          '            raw = marker_raw if path == marker else _observe_bytes(\n',
          '                root, path, _regular(root, path).read_bytes(), _operation=_operation)\n',
          "            require(type(raw) is bytes, 'typed source is not physical bytes: ' + path)\n",
          '            image[path] = raw\n',
          "        typed_boundary.verify_sources({path: raw.decode('utf-8') for path, raw in image.items()})\n",
          "        leaves = ('tools/carla_lane_oracle/typed_boundary_contracts.py',\n",
          "                  'tools/carla_lane_oracle/conditioned_cubic_contracts.py')\n",
          '        conditioned_inputs = {}\n',
          '        for path, historical_digest in conditioned_cubic.BINDING_INPUTS.items():\n',
          '            if path in typed_boundary.EDGES:\n',
          '                edge = typed_boundary.edge(path)\n',
          "                require(edge['before_sha256'] == historical_digest,\n",
          "                        'typed input misses fixed conditioned witness/provider: ' + path)\n",
          '                # verify_sources above reconstructed this complete predecessor.\n',
          '                # Receipts bind current formatted bytes, not the old witness SHA.\n',
          "                conditioned_inputs[path] = edge['after_sha256']\n",
          '            else:\n',
          '                conditioned_inputs[path] = historical_digest\n',
          '        expected = {**typed_boundary.CURRENT_DEPENDENCIES, **typed_boundary.NEW_INPUTS, **typed_boundary.TESTS,\n',
          '                    **typed_boundary.BINDING_INPUTS, **conditioned_inputs,\n',
          '                    **{path: DEPENDENCY_TOOL_SHA256[path] for path in leaves}}\n',
          '        for path, digest in expected.items():\n',
          '            raw = _observe_bytes(root, path, _regular(root, path).read_bytes(), _operation=_operation)\n',
          "            require(sha(raw) == digest, 'typed boundary bound input changed: ' + path)\n",
          "            require(path not in image or image[path] == raw, 'typed input changed after source admission: ' + path)\n",
          '            image[path] = raw\n',
          '        for path, raw in image.items():\n',
          '            if _snapshots is not None:\n',
          "                require(_snapshots.setdefault(path, raw) == raw, 'typed input changed after consumption: ' + path)\n",
          '            require(_observe_bytes(root, path, _regular(root, path).read_bytes(),\n',
          '                                   _operation=_operation) == raw,\n',
          "                    'typed input changed during admission: ' + path)\n",
          '        return {path: sha(raw) for path, raw in image.items()}\n',
          '    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:\n',
          '        _operation_fail(_operation, error)\n',
          '\n',
          '\n',
          'def reviewed_typed_text(root, path, text, *, _operation=None, _inputs=None, _input_owner=None):\n',
          '    """Admit physical current bytes before returning historical provenance."""\n',
          '    path = str(path)\n',
          '    edge = typed_boundary.EDGES.get(path)\n',
          '    if edge is None:\n',
          '        return text\n',
          '    try:\n',
          '        if not (typed_boundary.is_current(path, text) or\n',
          "                source.token_sha256(text) == edge['after_token_sha256']):\n",
          '            return text\n',
          '        _operation_check(_operation, root)\n',
          '        raw = _observe_bytes(root, path, _regular(root, path).read_bytes(), _operation=_operation)\n',
          '        require(typed_boundary.is_current(path, raw),\n',
          "                'typed physical input is not the exact reviewed endpoint: ' + path)\n",
          "        physical_text = raw.decode('utf-8')\n",
          '        require(type(text) is str and source.token_sha256(text) == source.token_sha256(physical_text),\n',
          "                'supplied typed source differs from physical input: ' + path)\n",
          "        _observe_text(root, path, text, _operation=_operation, mode='physical',\n",
          '                      supplied=True, _checked_raw=raw)\n',
          "        require((_inputs is None) == (_input_owner is None), 'incomplete typed input owner')\n",
          '        if _inputs is not None:\n',
          "            require(type(_inputs) in (_CacheInputs, _BorrowedCacheInputs), 'invalid typed source owner')\n",
          "            require(_inputs.raw(_input_owner, root, path) == raw, 'typed owner image changed: ' + path)\n",
          '        elif _operation is None:\n',
          '            verify(root, exact=True)\n',
          '        else:\n',
          '            _operation_record(_operation, root, exact=True)\n',
          '        require(_observe_bytes(root, path, _regular(root, path).read_bytes(),\n',
          '                               _operation=_operation) == raw,\n',
          "                'typed source changed during provenance reconstruction: ' + path)\n",
          '        return _historical_typed_text(path, physical_text)\n',
          '    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:\n',
          '        _operation_fail(_operation, error)\n',
          '\n',
          '\n',
          'def verify(root, *, exact=False, include_roots=(), _expected_lane_raw=None, _capture=None, _expected_sources=None):\n',
         ),
        ),
        (2410, 2426,
         (
          '        for path, raw in snapshots.items():\n',
          '            text = _physical_text(raw)\n',
         ),
         (
          '        if _expected_sources is not None:\n',
          '            require(_capture is None and type(_expected_sources) is dict,\n',
          "                    'invalid supplied source capture request')\n",
          '            for path, expected in _expected_sources.items():\n',
          '                require(type(path) is str and _canonical_relative_text(path)\n',
          "                        and type(expected) is bytes, 'invalid supplied source capture value')\n",
          '                physical = _regular(root, path)\n',
          '                if path not in snapshots:\n',
          '                    snapshots[path] = physical.read_bytes()\n',
          '                require(snapshots[path] == expected,\n',
          "                        'supplied source observation changed before admission: ' + path)\n",
          '        typed_bindings = _typed_boundary_bindings(root, _snapshots=snapshots,\n',
          '            _operation=_capture if type(_capture) is _InvariantInputs else None)\n',
          '        for path in SOURCE_PATHS:\n',
          '            raw = snapshots[path]\n',
          '            text = _historical_typed_text(path, _physical_text(raw))\n',
         ),
        ),
        (2427, 2428,
         (
          '            require(source.token_sha256(supplied_view) == source.token_sha256(text),\n',
         ),
         (
          '            require(source.token_sha256(supplied_view) == source.token_sha256(_physical_text(raw)),\n',
         ),
        ),
        (2430, 2432,
         (
          '            require((not exact or sha(raw) == AFTER_SHA256[path])\n',
          "                    and source.token_sha256(_physical_text(raw)) == item['after_token_sha256']\n",
         ),
         (
          '            require((not exact or sha(text) == AFTER_SHA256[path])\n',
          "                    and source.token_sha256(text) == item['after_token_sha256']\n",
         ),
        ),
        (2449, 2450,
         (),
         (
          '                          | (set(typed_boundary.CURRENT_DEPENDENCIES) if typed_bindings else set())\n',
         ),
        ),
        (2474, 2476,
         (
          "                == set(record['dependency_inventory']) | helper_closure, 'production import inventory changed')\n",
         ),
         (
          '                == (set(typed_boundary.PRODUCTION_CLOSURE) if typed_bindings else\n',
          "                    set(record['dependency_inventory']) | helper_closure), 'production import inventory changed')\n",
         ),
        ),
        (2478, 2480,
         (
          "        require(native_found == set(record['native_dependency_inventory']) | helper_closure,\n",
         ),
         (
          '        require(native_found == (set(typed_boundary.NATIVE_CLOSURE) if typed_bindings else\n',
          "                set(record['native_dependency_inventory']) | helper_closure),\n",
         ),
        ),
        (2481, 2496,
         (),
         (
          '        if typed_bindings:\n',
          '            current_native = set()\n',
          "            test_paths = tuple(path for path in typed_boundary.TESTS if path.endswith('.mojo'))\n",
          '            for parent in sorted({str(Path(path).parent) for path in test_paths}):\n',
          '                current_native.update(dependency_inventory(root,\n',
          '                    roots=tuple(path for path in test_paths if str(Path(path).parent) == parent),\n',
          '                    entries=(parent,), _known=known, _snapshots=snapshots))\n',
          '            require(current_native == set(typed_boundary.TYPED_NATIVE_CLOSURE),\n',
          "                    'typed native test import inventory changed')\n",
          '            current_production = dependency_inventory(root,\n',
          '                roots=tuple(path for path in (*typed_boundary.SOURCE_PATHS, *typed_boundary.NEW_INPUTS)\n',
          "                    if path.endswith('.mojo') and not path.startswith(('tests/', 'tools/', 'examples/', 'bench/'))),\n",
          '                entries=entries, _known=known, _snapshots=snapshots)\n',
          '            require(current_production == set(typed_boundary.TYPED_PRODUCTION_CLOSURE),\n',
          "                    'typed production import inventory changed')\n",
         ),
        ),
        (2525, 2529,
         (
          "                require(sha(raw) == expected, 'unchanged premise, record or fixture changed: ' + path)\n",
         ),
         (
          "                historical = _historical_typed_text(path, raw.decode('utf-8')).encode('utf-8') if path in typed_boundary.EDGES and typed_bindings else raw\n",
          '                if historical != raw and expected == sha(raw):\n',
          '                    expected = sha(historical)\n',
          "                require(sha(historical) == expected, 'unchanged premise, record or fixture changed: ' + path)\n",
         ),
        ),
        (2542, 2544,
         (),
         (
          '        if typed_bindings:\n',
          '            expected_inventory = typed_boundary.INVENTORY\n',
         ),
        ),
        (2584, 2587,
         (
          "        text = _regular(root, path).read_text(encoding='utf-8')\n",
         ),
         (
          "        text = _observe_text(root, path, _regular(root, path).read_text(encoding='utf-8'),\n",
          "                             _operation=_operation, mode='physical')\n",
          '    text = reviewed_typed_text(root, path, text, _operation=_operation)\n',
         ),
        ),
        (2590, 2590,
         (
          '    if _operation is not None:\n',
          "        _observe_text(root, path, text, _operation=_operation, mode='physical', supplied=True)\n",
         ),
         (),
        ),
        (2603, 2604,
         (
          '        require(digest == AFTER_TOKEN_SHA256[path],\n',
         ),
         (
          '        require(digest == AFTER_TOKEN_SHA256[path] or typed_boundary.is_current(path, expected_raw),\n',
         ),
        ),
        (2612, 2613,
         (
          "        require(sha(road_raw) == record['unchanged_inputs'][road],\n",
         ),
         (
          "        require(sha(_historical_typed_text(road, road_raw.decode('utf-8'))) == record['unchanged_inputs'][road],\n",
         ),
        ),
        (2628, 2635,
         (
          '    record = verify(root)\n',
         ),
         (
          '    physical_inputs = {}\n',
          '    for path, text in texts.items():\n',
          '        raw = _regular(root, path).read_bytes()\n',
          '        require(source.token_sha256(text) == source.token_sha256(_physical_text(raw)),\n',
          "                'supplied successor source differs from physical input: ' + path)\n",
          '        physical_inputs[path] = raw\n',
          '    record = verify(root, _expected_sources=physical_inputs)\n',
         ),
        ),
        (2639, 2647,
         (),
         (
          '        physical = _regular(root, path).read_bytes()\n',
          '        require(physical == physical_inputs[path],\n',
          "                'supplied successor physical input changed during admission: ' + path)\n",
          '        require(source.token_sha256(text) == source.token_sha256(_physical_text(physical)),\n',
          "                'supplied successor source differs from physical input: ' + path)\n",
          '        # Only canonical physical bytes enter the exact typed inverse; caller\n',
          '        # comments have already been compared by the public supplied-view rule.\n',
          '        text = _historical_typed_text(path, _physical_text(physical))\n',
         ),
        ),
        (2654, 2655,
         (
          '            require(source.token_sha256(text) == source.token_sha256(_physical_text(raw)),\n',
         ),
         (
          '            require(raw == physical and source.token_sha256(text) == source.token_sha256(_historical_typed_text(path, _physical_text(raw))),\n',
         ),
        ),
        (2656, 2657,
         (),
         (
          '            result[path] = text\n',
         ),
        ),
        (2675, 2678,
         (
          '            changed = any(declaration_sha256(text, name) not in expected\n',
         ),
         (
          '            typed_current = typed_boundary.is_current(path, text)\n',
          '            text = _historical_typed_text(path, text)\n',
          '            changed = typed_current or any(declaration_sha256(text, name) not in expected\n',
         ),
        ),
        (2702, 2703,
         (
          'def reviewed_lane_before_center_text(root, text=None):\n',
         ),
         (
          'def reviewed_lane_before_center_text(root, text=None, *, _operation=None):\n',
         ),
        ),
        (2704, 2705,
         (),
         (
          '    supplied_raw = None\n',
         ),
        ),
        (2706, 2718,
         (
          "        require(source.token_sha256(text) == AFTER_TOKEN_SHA256[path], 'unreviewed supplied center source')\n",
          "    item = verify(root)['sources'][path]\n",
         ),
         (
          '        supplied_raw = _observe_bytes(root, path, _regular(root, path).read_bytes(),\n',
          '                                      _operation=_operation)\n',
          '        require(source.token_sha256(text) == source.token_sha256(_physical_text(supplied_raw)),\n',
          "                'unreviewed supplied center source')\n",
          '    item = (verify(root, _expected_lane_raw=supplied_raw) if _operation is None else\n',
          "            _operation_record(_operation, root, expected_lane_raw=supplied_raw))['sources'][path]\n",
          '    if supplied_raw is not None:\n',
          '        require(source.token_sha256(_historical_typed_text(path, _physical_text(supplied_raw)))\n',
          "                == AFTER_TOKEN_SHA256[path], 'unreviewed supplied center source')\n",
          '        require(_observe_bytes(root, path, _regular(root, path).read_bytes(),\n',
          '                               _operation=_operation) == supplied_raw,\n',
          "                'supplied center physical input changed during admission')\n",
         ),
        ),
        (2727, 2758,
         (),
         (
          '\n',
          '\n',
          'def typed_successor_edges(root, *, _operation=None):\n',
          '    """Return explicit current edges, separately from immutable old records."""\n',
          '    try:\n',
          "        marker = 'extensions/carla/polynomial.mojo'\n",
          '        raw = _observe_bytes(root, marker, _regular(root, marker).read_bytes(),\n',
          '                             _operation=_operation)\n',
          '        if not typed_boundary.is_current(marker, raw):\n',
          '            return {}\n',
          '        if _operation is None:\n',
          '            verify(root, exact=True)\n',
          '        else:\n',
          '            _operation_record(_operation, root, exact=True)\n',
          '        result = {}\n',
          '        for path in typed_boundary.SOURCE_PATHS:\n',
          '            current = _observe_bytes(root, path, _regular(root, path).read_bytes(),\n',
          '                                     _operation=_operation)\n',
          '            require(typed_boundary.is_current(path, current),\n',
          "                    'typed successor physical endpoint changed: ' + path)\n",
          '            edge = typed_boundary.edge(path)\n',
          "            edge['scope'] = 'explicit historical provenance; current typed API admission'\n",
          '            if path in conditioned_cubic.SOURCE_PATHS:\n',
          "                edge['conditioned_graph'] = {\n",
          "                    'before_sha256': conditioned_cubic.BEFORE_SHA256[path],\n",
          "                    'after_sha256': conditioned_cubic.AFTER_SHA256[path],\n",
          "                    'scope': 'new local-coefficient graph; no scalar bit-equivalence claim'}\n",
          '            result[path] = edge\n',
          '        return result\n',
          '    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:\n',
          '        _operation_fail(_operation, error)\n',
         ),
        ),
        (2776, 2784,
         (),
         (
          "        if result.get(station.MODULE) == typed_boundary.EDGES[station.MODULE]['after_sha256']:\n",
          '            # The public typed receipt requires the complete current graph.\n',
          "            # Keep _station_bindings itself nonrecursive for verify's capture.\n",
          '            if _operation is None:\n',
          '                verify(root, exact=True)\n',
          '            else:\n',
          '                _operation_record(_operation, root, exact=True)\n',
          '            result.update(_typed_boundary_bindings(root, _operation=_operation))\n',
         ),
        ),
        (2811, 2812,
         (),
         (
          '        result.update(_typed_boundary_bindings(root, _operation=_operation))\n',
         ),
        ),
        (2816, 2818,
         (),
         (
          '        if _operation is not None:\n',
          '            _operation._bind_checker_receipt(root, executing)\n',
         ),
        ),
    ),
    'grouped_y_finiteness_contracts.py': (
        (1, 11,
         (),
         (
          '\n',
          'if __package__:\n',
          '    from . import source_contracts as _typed_source\n',
          'else:\n',
          '    import source_contracts as _typed_source\n',
          '\n',
          'if __package__:\n',
          '    from . import source_contracts as source\n',
          'else:\n',
          '    import source_contracts as source\n',
         ),
        ),
        (42, 46,
         (
          '        modules = {p: full_audit._observe_text(root, p, text, _operation=_operation)\n',
         ),
         (
          '        modules = {p: _typed_source.historical_text(root, p, full_audit._observe_text(root, p, text, _operation=_operation), _operation=_operation)\n',
          '                   for p, text in modules.items()}\n',
          '    else:\n',
          '        modules = {p: _typed_source.historical_text(root, p, text)\n',
         ),
        ),
        (58, 59,
         (),
         (
          '# #333 explicit historical provenance views; current inputs remain operation-owned.\n',
         ),
        ),
        (66, 67,
         (
          '    payload = (root / RECORD).read_bytes()\n',
         ),
         (
          '    payload = _typed_source.historical_bytes(root, root / RECORD, (root / RECORD).read_bytes(), _operation=_operation)\n',
         ),
        ),
    ),
    'raw_cut_inverse_contracts.py': (
        (3, 8,
         (),
         (
          '\n',
          'if __package__:\n',
          '    from . import source_contracts as _typed_source\n',
          'else:\n',
          '    import source_contracts as _typed_source\n',
         ),
        ),
        (9, 10,
         (),
         (
          '# #333 explicit historical provenance views; current inputs remain operation-owned.\n',
         ),
        ),
        (31, 32,
         (
          '    payload = (root/MIGRATION).read_bytes()\n',
         ),
         (
          '    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())\n',
         ),
        ),
        (60, 61,
         (),
         (
          '    text = _typed_source.historical_text(root, SOURCE_PATH, text, _operation=_operation)\n',
         ),
        ),
        (65, 67,
         (
          '        environment = full_audit._observe_text(\n',
          "            root, 'extensions/carla/curve_sum2.mojo', environment, _operation=_operation)\n",
         ),
         (
          "        environment = full_audit._observe_text(root, 'extensions/carla/curve_sum2.mojo', environment, _operation=_operation)\n",
          "    environment = _typed_source.historical_text(root, 'extensions/carla/curve_sum2.mojo', environment, _operation=_operation)\n",
         ),
        ),
        (69, 70,
         (
          "    predecessor_payload = (root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_bytes()\n",
         ),
         (
          "    predecessor_payload = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json', (root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_bytes(), _operation=_operation)\n",
         ),
        ),
        (74, 76,
         (
          '        predecessor_text = full_audit._observe_text(\n',
          "            root, 'tools/carla_lane_oracle/curve-support-dispatch-migration.json',\n",
          '            predecessor_text, _operation=_operation, _checked_raw=predecessor_payload)\n',
         ),
         (
          "        predecessor_text = full_audit._observe_text(root, 'tools/carla_lane_oracle/curve-support-dispatch-migration.json', predecessor_text, _operation=_operation, _checked_raw=predecessor_payload)\n",
          "    predecessor_text = _typed_source.historical_text(root, 'tools/carla_lane_oracle/curve-support-dispatch-migration.json', predecessor_text, _operation=_operation)\n",
         ),
        ),
        (82, 84,
         (
          '        fixture = full_audit._observe_text(\n',
          "            root, 'tests/test_carla_raw_cut_successor.mojo', fixture, _operation=_operation)\n",
         ),
         (
          "        fixture = full_audit._observe_text(root, 'tests/test_carla_raw_cut_successor.mojo', fixture, _operation=_operation)\n",
          "    fixture = _typed_source.historical_text(root, 'tests/test_carla_raw_cut_successor.mojo', fixture, _operation=_operation)\n",
         ),
        ),
        (88, 90,
         (
          '        reference = full_audit._observe_text(\n',
          "            root, 'tests/test_carla_support_dispatch_successor.mojo', reference,\n",
          '            _operation=_operation)\n',
         ),
         (
          "        reference = full_audit._observe_text(root, 'tests/test_carla_support_dispatch_successor.mojo', reference, _operation=_operation)\n",
          "    reference = _typed_source.historical_text(root, 'tests/test_carla_support_dispatch_successor.mojo', reference, _operation=_operation)\n",
         ),
        ),
        (107, 108,
         (),
         (
          '    text = _typed_source.historical_text(root, SOURCE_PATH, text, _operation=_operation)\n',
         ),
        ),
    ),
    'seed_count_contracts.py': (
        (10, 15,
         (),
         (
          'if __package__:\n',
          '    from . import source_contracts as _typed_source\n',
          'else:\n',
          '    import source_contracts as _typed_source\n',
          '\n',
         ),
        ),
        (16, 17,
         (),
         (
          '# #333 explicit historical provenance views; current inputs remain operation-owned.\n',
         ),
        ),
        (225, 227,
         (
          '    payload = ((Path(root)/MIGRATION).read_bytes() if _inputs is None else\n',
          '               _inputs.raw(_input_owner, root, MIGRATION))\n',
         ),
         (
          '    payload = (_typed_source.historical_bytes(root, Path(root)/MIGRATION, (Path(root)/MIGRATION).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _inputs is None else\n',
          '               _typed_source.historical_bytes(root, MIGRATION, _inputs.raw(_input_owner, root, MIGRATION), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner))\n',
         ),
        ),
        (269, 270,
         (
          "    text = (Path(root)/MODULE).read_bytes().decode('utf-8')\n",
         ),
         (
          "    text = _typed_source.historical_bytes(root, Path(root)/MODULE, (Path(root)/MODULE).read_bytes()).decode('utf-8')\n",
         ),
        ),
        (373, 375,
         (
          "        text = (((root/name).read_bytes() if _operation is None else full_audit._observe_bytes(root, name, (root/name).read_bytes(), _operation=_operation)).decode('utf-8') if _inputs is None else\n",
          '                _inputs.text_utf8(_input_owner, root, name))\n',
         ),
         (
          "        text = ((_typed_source.historical_bytes(root, root/name, (root/name).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else _typed_source.historical_bytes(root, name, full_audit._observe_bytes(root, name, (root/name).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)).decode('utf-8') if _inputs is None else\n",
          '                _typed_source.historical_text(root, name, _inputs.text_utf8(_input_owner, root, name), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner))\n',
         ),
        ),
        (436, 437,
         (
          'def verify_support(root):\n',
         ),
         (
          'def verify_support(root, *, _expected_raw=None):\n',
         ),
        ),
        (440, 445,
         (
          "    text = (root/MODULE).read_bytes().decode('utf-8')\n",
         ),
         (
          '    current_raw = (root/MODULE).read_bytes()\n',
          '    if _expected_raw is not None:\n',
          '        require(type(_expected_raw) is bytes and current_raw == _expected_raw,\n',
          "                'Map observation changed before delegated verification')\n",
          "    text = _typed_source.historical_bytes(root, MODULE, current_raw).decode('utf-8')\n",
         ),
        ),
        (451, 452,
         (
          "    require((root/MODULE).read_bytes().decode('utf-8') == text,\n",
         ),
         (
          '    require((root/MODULE).read_bytes() == current_raw,\n',
         ),
        ),
        (496, 497,
         (
          'def verify_frontier(root):\n',
         ),
         (
          'def verify_frontier(root, *, _expected_raw=None):\n',
         ),
        ),
        (500, 505,
         (
          "    text = (root/MODULE).read_bytes().decode('utf-8')\n",
         ),
         (
          '    current_raw = (root/MODULE).read_bytes()\n',
          '    if _expected_raw is not None:\n',
          '        require(type(_expected_raw) is bytes and current_raw == _expected_raw,\n',
          "                'Map observation changed before delegated verification')\n",
          "    text = _typed_source.historical_bytes(root, MODULE, current_raw).decode('utf-8')\n",
         ),
        ),
        (512, 513,
         (
          "    require((root/MODULE).read_bytes().decode('utf-8') == text,\n",
         ),
         (
          '    require((root/MODULE).read_bytes() == current_raw,\n',
         ),
        ),
        (567, 578,
         (
          '        text = ((path.read_text() if _operation is None else full_audit._observe_text(root, rel.as_posix(), path.read_text(), _operation=_operation)) if _inputs is None else\n',
          '                _inputs.text_default(_input_owner, root, rel.as_posix()))\n',
         ),
         (
          '        supplied_text = ((path.read_text() if _operation is None else\n',
          '                          full_audit._observe_text(root, rel.as_posix(), path.read_text(), _operation=_operation)) if _inputs is None else\n',
          '                         _inputs.text_default(_input_owner, root, rel.as_posix()))\n',
          '        if rel.as_posix() == MODULE and station_edge is not None:\n',
          '            physical = ((path.read_bytes() if _operation is None else\n',
          '                         full_audit._observe_bytes(root, MODULE, path.read_bytes(), _operation=_operation)) if _inputs is None else\n',
          '                        _inputs.observe_bytes(_input_owner, root, MODULE))\n',
          "            require(source.token_sha256(supplied_text) == source.token_sha256(physical.decode('utf-8')),\n",
          "                    'station census supplied and physical Map views differ')\n",
          '        text = _typed_source.historical_text(root, rel.as_posix(), supplied_text, _operation=_operation,\n',
          '            _inputs=_inputs, _input_owner=_input_owner)\n',
         ),
        ),
        (664, 665,
         (
          'def verify_score(root, *, _inputs=None, _input_owner=None, _operation=None):\n',
         ),
         (
          'def verify_score(root, *, _inputs=None, _input_owner=None, _operation=None, _expected_raw=None):\n',
         ),
        ),
        (670, 678,
         (
          "    text = (((root/MODULE).read_bytes() if _operation is None else full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation)).decode('utf-8') if _inputs is None else\n",
          "            _inputs.observe_bytes(_input_owner, root, MODULE).decode('utf-8'))\n",
         ),
         (
          '    current_raw = (((root/MODULE).read_bytes() if _operation is None else\n',
          '                    full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation)) if _inputs is None else\n',
          '                   _inputs.observe_bytes(_input_owner, root, MODULE))\n',
          '    if _expected_raw is not None:\n',
          '        require(type(_expected_raw) is bytes and current_raw == _expected_raw,\n',
          "                'Map observation changed before delegated verification')\n",
          '    text = _typed_source.historical_bytes(root, MODULE, current_raw, _operation=_operation,\n',
          "        _inputs=_inputs, _input_owner=_input_owner).decode('utf-8')\n",
         ),
        ),
        (679, 681,
         (
          '        require(hashlib.sha256(((root/path).read_bytes() if _operation is None else full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)) if _inputs is None else\n',
          '                               _inputs.raw(_input_owner, root, path)).hexdigest() == expected,\n',
         ),
         (
          '        require(hashlib.sha256((_typed_source.historical_bytes(root, root/path, (root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else _typed_source.historical_bytes(root, path, full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)) if _inputs is None else\n',
          '                               _typed_source.historical_bytes(root, path, _inputs.raw(_input_owner, root, path), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)).hexdigest() == expected,\n',
         ),
        ),
        (687, 689,
         (
          '            require(hashlib.sha256(((root/path).read_bytes() if _operation is None else full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)) if _inputs is None else\n',
          '                                   _inputs.raw(_input_owner, root, path)).hexdigest() == expected,\n',
         ),
         (
          '            require(hashlib.sha256((_typed_source.historical_bytes(root, root/path, (root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else _typed_source.historical_bytes(root, path, full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)) if _inputs is None else\n',
          '                                   _typed_source.historical_bytes(root, path, _inputs.raw(_input_owner, root, path), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)).hexdigest() == expected,\n',
         ),
        ),
        (692, 694,
         (
          '            require(hashlib.sha256(((root/path).read_bytes() if _operation is None else full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)) if _inputs is None else\n',
          '                                   _inputs.raw(_input_owner, root, path)).hexdigest() == expected,\n',
         ),
         (
          '            require(hashlib.sha256((_typed_source.historical_bytes(root, root/path, (root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else _typed_source.historical_bytes(root, path, full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)) if _inputs is None else\n',
          '                                   _typed_source.historical_bytes(root, path, _inputs.raw(_input_owner, root, path), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)).hexdigest() == expected,\n',
         ),
        ),
        (711, 715,
         (
          "    final_text = (((root/MODULE).read_bytes() if _operation is None else full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation)).decode('utf-8') if _inputs is None else\n",
          "                  _inputs.observe_bytes(_input_owner, root, MODULE).decode('utf-8'))\n",
          '    require(final_text == text,\n',
         ),
         (
          '    final_raw = (((root/MODULE).read_bytes() if _operation is None else\n',
          '                  full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation)) if _inputs is None else\n',
          '                 _inputs.observe_bytes(_input_owner, root, MODULE))\n',
          '    require(final_raw == current_raw,\n',
         ),
        ),
        (750, 752,
         (
          '           and hashlib.sha256(((root/path).read_bytes() if _operation is None else full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)) if _inputs is None else\n',
          '                              _inputs.raw(_input_owner, root, path)).hexdigest() == full_audit.AFTER_SHA256[path]\n',
         ),
         (
          '           and hashlib.sha256((_typed_source.historical_bytes(root, root/path, (root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else _typed_source.historical_bytes(root, path, full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)) if _inputs is None else\n',
          '                              _typed_source.historical_bytes(root, path, _inputs.raw(_input_owner, root, path), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)).hexdigest() == full_audit.AFTER_SHA256[path]\n',
         ),
        ),
        (767, 769,
         (
          '            require(hashlib.sha256(((root/path).read_bytes() if _operation is None else full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)) if _inputs is None else\n',
          '                              _inputs.raw(_input_owner, root, path)).hexdigest() == expected,\n',
         ),
         (
          '            require(hashlib.sha256((_typed_source.historical_bytes(root, root/path, (root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else _typed_source.historical_bytes(root, path, full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)) if _inputs is None else\n',
          '                              _typed_source.historical_bytes(root, path, _inputs.raw(_input_owner, root, path), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)).hexdigest() == expected,\n',
         ),
        ),
        (772, 773,
         (
          'def verify_optional(root):\n',
         ),
         (
          'def verify_optional(root, *, _expected_raw=None):\n',
         ),
        ),
        (776, 781,
         (
          "    text = (root/MODULE).read_bytes().decode('utf-8')\n",
         ),
         (
          '    current_raw = (root/MODULE).read_bytes()\n',
          '    if _expected_raw is not None:\n',
          '        require(type(_expected_raw) is bytes and current_raw == _expected_raw,\n',
          "                'Map observation changed before delegated verification')\n",
          "    text = _typed_source.historical_bytes(root, MODULE, current_raw).decode('utf-8')\n",
         ),
        ),
        (786, 787,
         (
          "    require((root/MODULE).read_bytes().decode('utf-8') == text,\n",
         ),
         (
          '    require((root/MODULE).read_bytes() == current_raw,\n',
         ),
        ),
        (814, 816,
         (
          "        text = (((root/path).read_bytes() if _operation is None else full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)).decode('utf-8') if _inputs is None else\n",
          '                    _inputs.text_utf8(_input_owner, root, path))\n',
         ),
         (
          "        text = ((_typed_source.historical_bytes(root, root/path, (root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else _typed_source.historical_bytes(root, path, full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)).decode('utf-8') if _inputs is None else\n",
          '                    _typed_source.historical_text(root, path, _inputs.text_utf8(_input_owner, root, path), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner))\n',
         ),
        ),
        (833, 835,
         (
          "            text = (((root/path).read_bytes() if _operation is None else full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)).decode('utf-8') if _inputs is None else\n",
          '                    _inputs.text_utf8(_input_owner, root, path))\n',
         ),
         (
          "            text = ((_typed_source.historical_bytes(root, root/path, (root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else _typed_source.historical_bytes(root, path, full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)).decode('utf-8') if _inputs is None else\n",
          '                    _typed_source.historical_text(root, path, _inputs.text_utf8(_input_owner, root, path), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner))\n',
         ),
        ),
        (852, 854,
         (
          "            actual = declaration((((root/path).read_bytes() if _operation is None else full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)).decode('utf-8') if _inputs is None else\n",
          '                    _inputs.text_utf8(_input_owner, root, path)), name, owner)\n',
         ),
         (
          "            actual = declaration(((_typed_source.historical_bytes(root, root/path, (root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else _typed_source.historical_bytes(root, path, full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)).decode('utf-8') if _inputs is None else\n",
          '                    _typed_source.historical_text(root, path, _inputs.text_utf8(_input_owner, root, path), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)), name, owner)\n',
         ),
        ),
        (858, 860,
         (
          "            actual = declaration((((root/path).read_bytes() if _operation is None else full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)).decode('utf-8') if _inputs is None else\n",
          '                    _inputs.text_utf8(_input_owner, root, path)), name, owner)\n',
         ),
         (
          "            actual = declaration(((_typed_source.historical_bytes(root, root/path, (root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else _typed_source.historical_bytes(root, path, full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)).decode('utf-8') if _inputs is None else\n",
          '                    _typed_source.historical_text(root, path, _inputs.text_utf8(_input_owner, root, path), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)), name, owner)\n',
         ),
        ),
        (863, 865,
         (
          "    text = (((root/MODULE).read_bytes() if _operation is None else full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation)).decode('utf-8') if _inputs is None else\n",
          '            _inputs.text_utf8(_input_owner, root, MODULE))\n',
         ),
         (
          "    text = ((_typed_source.historical_bytes(root, root/MODULE, (root/MODULE).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else _typed_source.historical_bytes(root, MODULE, full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)).decode('utf-8') if _inputs is None else\n",
          '            _typed_source.historical_text(root, MODULE, _inputs.text_utf8(_input_owner, root, MODULE), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner))\n',
         ),
        ),
        (881, 882,
         (
          'def verify(root, *, _operation=None):\n',
         ),
         (
          'def verify(root, *, _operation=None, _expected_raw=None):\n',
         ),
        ),
        (885, 891,
         (
          "    text = ((root/MODULE).read_bytes() if _operation is None else full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation)).decode('utf-8')\n",
         ),
         (
          '    current_raw = ((root/MODULE).read_bytes() if _operation is None else\n',
          '                   full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation))\n',
          '    if _expected_raw is not None:\n',
          '        require(type(_expected_raw) is bytes and current_raw == _expected_raw,\n',
          "                'Map observation changed before delegated verification')\n",
          "    text = _typed_source.historical_bytes(root, MODULE, current_raw, _operation=_operation).decode('utf-8')\n",
         ),
        ),
        (892, 910,
         (
          "        return verify_score(root, **({} if _operation is None else {'_operation': _operation}))\n",
          '    if sha(text) == FRONTIER_AFTER_SHA256:\n',
          '        return verify_frontier(root)\n',
          '    if sha(text) == SUPPORT_AFTER_SHA256:\n',
          '        return verify_support(root)\n',
          '    if sha(text) == OPTIONAL_AFTER_SHA256:\n',
          '        return verify_optional(root)\n',
          '    edge = verify_source(text, record)\n',
          '    if edge is None:\n',
          '        return None\n',
          "    _verify_bound_inputs(root, record, **({} if _operation is None else {'_operation': _operation}))\n",
          "    verify_premises(root, record, after=True, **({} if _operation is None else {'_operation': _operation}))\n",
          '    # A caller must not project a source different from the one just verified.\n',
          "    require(((root/MODULE).read_bytes() if _operation is None else full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation)).decode('utf-8') == text, 'Map changed during verification')\n",
         ),
         (
          "        edge = verify_score(root, **({'_expected_raw': current_raw} if _operation is None else {'_operation': _operation}))\n",
          '    elif sha(text) == FRONTIER_AFTER_SHA256:\n',
          '        edge = verify_frontier(root, _expected_raw=current_raw)\n',
          '    elif sha(text) == SUPPORT_AFTER_SHA256:\n',
          '        edge = verify_support(root, _expected_raw=current_raw)\n',
          '    elif sha(text) == OPTIONAL_AFTER_SHA256:\n',
          '        edge = verify_optional(root, _expected_raw=current_raw)\n',
          '    else:\n',
          '        edge = verify_source(text, record)\n',
          '        if edge is None:\n',
          '            return None\n',
          "        _verify_bound_inputs(root, record, **({} if _operation is None else {'_operation': _operation}))\n",
          "        verify_premises(root, record, after=True, **({} if _operation is None else {'_operation': _operation}))\n",
          "    # Reconcile the dispatch observation as well as the delegated verifier's\n",
          '    # own capture; an equal historical projection cannot hide a physical swap.\n',
          '    final_raw = ((root/MODULE).read_bytes() if _operation is None else\n',
          '                 full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation))\n',
          "    require(final_raw == current_raw, 'Map changed during verification')\n",
         ),
        ),
        (919, 921,
         (
          "    text = full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation).decode('utf-8')\n",
         ),
         (
          '    current_raw = full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation)\n',
          "    text = _typed_source.historical_bytes(root, MODULE, current_raw, _operation=_operation).decode('utf-8')\n",
         ),
        ),
        (926, 928,
         (
          "    require(verify(root, **operation_args) is not None, 'after Map did not activate its reviewed edge')\n",
          "    require(full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation).decode('utf-8') == text, 'Map changed during reconstruction')\n",
         ),
         (
          "    require(verify(root, **({'_expected_raw': current_raw} if _operation is None else operation_args)) is not None, 'after Map did not activate its reviewed edge')\n",
          "    require(full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), _operation=_operation) == current_raw, 'Map changed during reconstruction')\n",
         ),
        ),
        (946, 953,
         (
          '    physical = ((Path(root)/MODULE).read_bytes() if _operation is None else full_audit._observe_bytes(root, MODULE, (Path(root)/MODULE).read_bytes(), _operation=_operation))\n',
         ),
         (
          '    current_raw = (Path(root)/MODULE).read_bytes()\n',
          '    if _operation is not None:\n',
          '        current_raw = full_audit._observe_bytes(root, MODULE, current_raw, _operation=_operation)\n',
          "    require(source.token_sha256(text) == source.token_sha256(current_raw.decode('utf-8')),\n",
          "            'unreviewed supplied Map source')\n",
          '    text = _typed_source.historical_text(root, MODULE, text, _operation=_operation)\n',
          '    physical = _typed_source.historical_bytes(root, MODULE, current_raw, _operation=_operation)\n',
         ),
        ),
        (966, 971,
         (
          "    require(verify(root, **({} if _operation is None else {'_operation': _operation})) is not None, 'after Map did not activate its reviewed edge')\n",
          '    require(((Path(root)/MODULE).read_bytes() if _operation is None else full_audit._observe_bytes(root, MODULE, (Path(root)/MODULE).read_bytes(), _operation=_operation)) == physical,\n',
          "            'Map changed during supplied-view verification')\n",
         ),
         (
          "    require(verify(root, **({'_expected_raw': current_raw} if _operation is None else {'_operation': _operation})) is not None, 'after Map did not activate its reviewed edge')\n",
          '    final_raw = (Path(root)/MODULE).read_bytes()\n',
          '    if _operation is not None:\n',
          '        final_raw = full_audit._observe_bytes(root, MODULE, final_raw, _operation=_operation)\n',
          "    require(final_raw == current_raw, 'Map changed during supplied-view verification')\n",
         ),
        ),
    ),
    'source_contracts.py': (
        (235, 236,
         (
          '        checked = text\n',
         ),
         (
          '        checked = historical_text(root, path, text, **operation_args)\n',
         ),
        ),
        (238, 239,
         (
          "                and token_sha256(text) != pins['groups'][group][path]):\n",
         ),
         (
          "                and token_sha256(checked) != pins['groups'][group][path]):\n",
         ),
        ),
        (248, 249,
         (
          "        if path == PREFIX + 'lane_refinement.mojo' and token_sha256(text) != pins['groups'][group][path]:\n",
         ),
         (
          "        if path == PREFIX + 'lane_refinement.mojo' and token_sha256(checked) != pins['groups'][group][path]:\n",
         ),
        ),
        (258, 259,
         (
          "        elif path == PREFIX + 'map.mojo' and token_sha256(text) != pins['groups'][group][path]:\n",
         ),
         (
          "        elif path == PREFIX + 'map.mojo' and token_sha256(checked) != pins['groups'][group][path]:\n",
         ),
        ),
        (274, 276,
         (
          'def verify_qualifiers(root, filename, text):\n',
          '    pins = read_pins(root)\n',
         ),
         (
          'def verify_qualifiers(root, filename, text, *, _operation=None):\n',
          '    pins = read_pins(root, _operation=_operation)\n',
         ),
        ),
        (277, 278,
         (
          '    checked = text\n',
         ),
         (
          '    checked = historical_text(root, PREFIX + filename, text, _operation=_operation)\n',
         ),
        ),
        (279, 280,
         (
          "            and qualifier_sha256(text) != pins['qualifiers'][filename]):\n",
         ),
         (
          "            and qualifier_sha256(checked) != pins['qualifiers'][filename]):\n",
         ),
        ),
        (285, 286,
         (
          '            checked = full_audit.reviewed_text(root, PREFIX + filename, text)\n',
         ),
         (
          '            checked = full_audit.reviewed_text(root, PREFIX + filename, text, _operation=_operation)\n',
         ),
        ),
        (290, 346,
         (),
         (
          '\n',
          '\n',
          'def _typed_path(root, path):\n',
          '    relative = str(path)\n',
          "    if not relative.endswith('.mojo'):\n",
          '        return None\n',
          '    if Path(relative).is_absolute():\n',
          '        relative = Path(relative).relative_to(root).as_posix()\n',
          '    elif isinstance(path, Path):\n',
          '        # Callers passing root/path may use a non-dot relative checkout root.\n',
          '        # Canonical module strings remain relative to root, never prefix-stripped.\n',
          '        root_text = str(root)\n',
          "        if (root_text not in ('', '.') and not Path(root_text).is_absolute()\n",
          "                and '..' not in Path(root_text).parts and '..' not in path.parts\n",
          "                and relative.startswith(root_text + '/')):\n",
          '            relative = relative[len(root_text) + 1:]\n',
          '    return relative\n',
          '\n',
          '\n',
          'def historical_text(root, path, text, *, _operation=None, _inputs=None, _input_owner=None):\n',
          '    """Expose a fixed historical view only after actual current admission.\n',
          '\n',
          '    Reads and owned observations stay physical. The conditioned semantic\n',
          '    successor, rather than old byte-identity claims, binds the new graph.\n',
          '    """\n',
          '    relative = _typed_path(root, path)\n',
          '    if relative is None:\n',
          '        return text\n',
          '    if __package__:\n',
          '        from . import typed_boundary_contracts as typed\n',
          '    else:\n',
          '        import typed_boundary_contracts as typed\n',
          '    if relative not in typed.EDGES:\n',
          '        return text\n',
          '    if __package__:\n',
          '        from . import full_audit_cleanup_contracts as audit\n',
          '    else:\n',
          '        import full_audit_cleanup_contracts as audit\n',
          '    return audit.reviewed_typed_text(root, relative, text, _operation=_operation,\n',
          '                                     _inputs=_inputs, _input_owner=_input_owner)\n',
          '\n',
          '\n',
          'def historical_bytes(root, path, raw, *, _operation=None, _inputs=None, _input_owner=None):\n',
          '    """Preserve physical reads before one named historical-source projection."""\n',
          '    relative = _typed_path(root, path)\n',
          '    if relative is None:\n',
          '        return raw\n',
          '    if __package__:\n',
          '        from . import typed_boundary_contracts as typed\n',
          '    else:\n',
          '        import typed_boundary_contracts as typed\n',
          '    if relative not in typed.EDGES:\n',
          '        return raw\n',
          "    require(type(raw) is bytes, 'historical input is not physical bytes')\n",
          "    return historical_text(root, relative, raw.decode('utf-8'), _operation=_operation,\n",
          "                           _inputs=_inputs, _input_owner=_input_owner).encode('utf-8')\n",
         ),
        ),
    ),
}
# END REVIEWED #333 CHECKER SOURCE INVERSE
class BoundedOwnerDistinctMechanismControls(unittest.TestCase):
    setUp = BoundedOwnerCurrentControls.setUp
    audit = BoundedOwnerCurrentControls.audit
    coverage = BoundedOwnerCurrentControls.coverage
    assert_closed = BoundedOwnerCurrentControls.assert_closed
    assert_one_owner = BoundedOwnerCurrentControls.assert_one_owner
    assert_public_coherence_error = BoundedOwnerCurrentControls.assert_public_coherence_error

    _SOURCE_SHA256 = {
        'accepted_successor_contracts.py': '7a3accef16e213e0c68f366e0349ba7010c997ddf4559817d775269e0278cf18',
        'cache_key_contracts.py': '4dd8d16b6d7f1d415631cde453f9270cfe58fd6cdf1cd382e4e7cdde4ea076e2',
        'coverage_followup_contracts.py': '37258b36b2a1d2c5b0e5959efb764f7ba4c0c3271467345c229f302dc7c192a0',
        'coverage_loop_proofs.py': 'c70c73fad4702cd41eeed5273dec6382c7be6111cd28d47daba195c2dd10c4be',
        'full_audit_cleanup_contracts.py': '091df2a89a23f27b411477e61cb4532673baa1e8280c276cd6440a29af6ccca1',
        'grouped_y_finiteness_contracts.py': 'ebb2b381263ffde628fda521393cbdc115e3f39db070d42e4790b75cd4e31307',
        'raw_cut_inverse_contracts.py': 'ca1cb6bbba485f994a15a4771774383fc8a7f0d4673e028f7785aca109df73e5',
        'seed_count_contracts.py': '099269aecd67f590ddee6a10e7ebddb83541401559312112b129b0aa2abece18',
        'source_contracts.py': '857dd399291611dd35e11adbbdde0fca03ed4ff4277eec54ed3ec5815bbaf791',
    }

    def _site(self, function, line, expression):
        """Bind a primitive to original globals, code family and AST address."""
        from types import CodeType
        original = inspect.unwrap(function)
        path = Path(original.__code__.co_filename)
        raw = path.read_bytes()
        predecessor, line_mapping = _checker_source_predecessor(path.name, raw)
        old_tree = ast.parse(predecessor)
        tree = ast.parse(raw)
        if line == 'station-census':
            self.assertEqual((path.name, original.__name__, expression),
                ('seed_count_contracts.py', 'verify_score_caller_inventory',
                 '_inputs.observe_bytes(_input_owner, root, MODULE)'))
            node = next(item for item in tree.body if isinstance(item, ast.FunctionDef)
                        and item.name == original.__name__)
            clause = _station_census_read_contract(node)
            first, last = clause.lineno, clause.end_lineno
        else:
            old_bodies = [node for node in ast.walk(old_tree) if isinstance(node, ast.FunctionDef)
                          and node.name == original.__name__]
            old_calls = [node for body in old_bodies for node in ast.walk(body)
                         if isinstance(node, ast.Call) and node.lineno == line
                         and ast.unparse(node) == expression]
            self.assertEqual(len(old_calls), 1, ('frozen predecessor site', path.name, line, expression))
            first, last = line_mapping[line]
        current_expression = (_CURRENT_LOCAL_S_REQUIRE if expression.startswith(
            'require(source.token_sha256(text) == source.token_sha256(_inputs.text_default') else expression)
        current_key = ast_key(ast.parse(current_expression, mode='eval').body)
        # Compilation creates code only; it never imports or executes a gate.
        compiled = compile(raw, str(path), 'exec', dont_inherit=True,
                           optimize=sys.flags.optimize)
        candidates = []
        def compiled_functions(code):
            if (code.co_name == original.__code__.co_name
                    and code.co_firstlineno == original.__code__.co_firstlineno):
                candidates.append(code)
            for item in code.co_consts:
                if isinstance(item, CodeType):
                    compiled_functions(item)
        compiled_functions(compiled)
        self.assertEqual(len(candidates), 1)
        self.assertEqual(original.__code__, candidates[0], 'loaded checker code differs from source')
        self.assertEqual(original.__code__.co_filename, candidates[0].co_filename)
        bodies = [node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)
                  and node.name == original.__name__
                  and node.lineno == original.__code__.co_firstlineno]
        self.assertEqual(len(bodies), 1)
        calls = [node for node in ast.walk(bodies[0]) if isinstance(node, ast.Call)
                 and first <= node.lineno <= last and ast_key(node) == current_key]
        self.assertEqual(len(calls), 1, (path.name, line, first, last, expression))
        call = calls[0]
        codes = []
        def retain(code):
            codes.append((code, tuple(code.co_positions())))
            for item in code.co_consts:
                if isinstance(item, CodeType):
                    retain(item)
        retain(original.__code__)
        def matches(frame):
            if frame is None or frame.f_globals is not original.__globals__:
                return False
            positions = next((rows for code, rows in codes if frame.f_code is code), None)
            offset = frame.f_lasti // 2
            if positions is None or not 0 <= offset < len(positions):
                return False
            first, last, left, right = positions[offset]
            return (None not in (first, last, left, right)
                    and (call.lineno, call.col_offset) <= (first, left)
                    and (last, right) <= (call.end_lineno, call.end_col_offset))
        return matches

    @staticmethod
    def _frame(function, frame):
        original = inspect.unwrap(function)
        while frame is not None:
            if frame.f_globals is original.__globals__ and frame.f_code is original.__code__:
                return frame
            frame = frame.f_back
        return None

    def _followup_route(self, frame):
        """Source-derived propagation route, with no source/accepted catch."""
        found = self._frame(followup.verify, frame)
        return (found is not None
                and self._frame(followup.accepts_predecessor_source, found.f_back) is found.f_back
                and self._frame(invariant.verify, found.f_back.f_back) is found.f_back.f_back)

    def _cache_followup_route(self, cache, frame):
        found = self._frame(cache.verify, frame)
        if found is None:
            return False
        for function in (cache.predecessor_source, cache.reviewed_text,
                         followup._source_view, followup.verify):
            found = found.f_back
            if found is None or self._frame(function, found) is not found:
                return False
        return self._followup_route(found)

    def _active(self, function, frame, core=cleanup):
        found = self._frame(function, frame)
        operation = found.f_locals.get('_operation') if found is not None else None
        return (operation if type(operation) is core._InvariantInputs
                and operation._state == 'active' and not operation._capturing else None)

    def _assert_refused(self, events, operation, reason, core=cleanup, *, finalized=False):
        self.assertEqual(events['admissions'], [operation])
        self.assertEqual(events['finalizers'], [operation] if finalized else [])
        self.assertTrue(operation._failed)
        self.assertEqual(operation._failure_reason, reason)
        self.assert_closed(operation, core)

    def _assert_direct(self, error, operation, reason, core=cleanup):
        self.assertIs(type(error), core._OperationCoherenceError)
        self.assertEqual(str(error), reason)
        self.assertEqual(operation._failure_reason, reason)
        self.assertIs(type(error.__cause__), core.ContractError)
        self.assertEqual(str(error.__cause__), reason)

    def _assert_lease_closed(self, lease):
        self.assertIs(type(lease), cleanup._BorrowedCacheInputs)
        self.assertEqual(lease._state, 'closed')
        self.assertFalse(lease._raw)
        self.assertIsNone(lease._record_raw)
        self.assertIsNone(lease._operation)
        self.assertIsNone(lease._owner_frame)
        self.assertFalse(lease._known)
        self.assertFalse(lease._production)

    @contextmanager
    def _no_marked_semantics(self, marked):
        """Keep admission's parser identities until the exact marked read."""
        from contextlib import ExitStack
        from functools import wraps
        with ExitStack() as stack:
            armed = False
            def arm():
                nonlocal armed
                self.assertFalse(armed, 'semantic sinks armed more than once')
                self.assertEqual(marked, [], 'semantic sinks armed after marked publication')
                for module, name in ((source, 'token_sha256'), (source, 'tokens'), (json, 'loads')):
                    original = getattr(module, name)
                    def install(original):
                        @wraps(original)
                        def checked(value, *args, **kwargs):
                            self.assertFalse(any(value is item for item in marked),
                                             'marked observation reached semantic sink')
                            return original(value, *args, **kwargs)
                        return checked
                    stack.enter_context(patch.object(module, name, install(original)))
                armed = True
            try:
                yield arm
            finally:
                self.assertEqual(armed, bool(marked),
                                 'semantic sink arming and marked publication differ')

    def test_shared_helper_local_final_reread_rejects_and_recovers(self):
        """Exercise the new local theorem seam without fabricating an owner."""
        from functools import wraps
        loops, core = self.coverage()
        module = 'extensions/carla/lane_distance'
        path = 'extensions/carla/curve_distance.mojo'
        physical = (self.root/path).read_bytes()
        site = self._site(loops._reviewed_dependency_hashes, 959, 'path.read_bytes()')
        baseline = loops.reviewed_nonempty_loops(self.root, module)
        self.assertEqual(set(baseline), {50})
        self.assertEqual(baseline[50]['dependency_sha256'][path],
                         hashlib.sha256(physical).hexdigest())
        for fault in ('changed', 'io'):
            with self.subTest(fault=fault):
                original_read = Path.read_bytes
                original_observe = loops._coverage_observe_bytes
                injected, marked, observed = [], [], []
                failure = PermissionError('shared-helper final reread denied')

                @wraps(original_read)
                def read(actual, *args, **kwargs):
                    value = original_read(actual, *args, **kwargs)
                    frame = sys._getframe(1)
                    if site(frame) and actual == self.root/path:
                        self.assertEqual(injected, [])
                        self.assertIsNone(frame.f_locals['_operation'])
                        self.assertEqual(frame.f_locals['raw'], physical)
                        self.assertEqual(value, physical)
                        injected.append(frame)
                        if fault == 'io':
                            raise failure
                        value += b'\n# changed final helper read\n'
                        marked.append(value)
                    return value

                @wraps(original_observe)
                def observe(root, name, value, *, _operation=None):
                    if marked and value is marked[0]:
                        self.assertEqual((root, name), (self.root, path))
                        self.assertIsNone(_operation)
                        self.assertIs(sys._getframe(1), injected[0])
                        observed.append(value)
                    return original_observe(root, name, value, _operation=_operation)

                with self.audit(core) as events, patch.object(Path, 'read_bytes', read), \
                        patch.object(loops, '_coverage_observe_bytes', observe):
                    result = loops.reviewed_nonempty_loops(self.root, module)
                self.assertEqual(result, {})
                self.assertEqual(len(injected), 1)
                self.assertEqual(observed, marked)
                self.assertEqual(len(observed), 1 if fault == 'changed' else 0)
                self.assertEqual(events['admissions'], [])
                self.assertEqual(events['finalizers'], [])
                self.assertIs(Path.read_bytes, original_read)
                self.assertEqual((self.root/path).read_bytes(), physical)
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, module), baseline)
                print('COVERAGE_HELPER_FINAL_CONTROL ' + json.dumps({
                    'fault': fault, 'module': module, 'path': path,
                    'site': 'shared-helper-source-final', 'owned': False,
                    'reached': len(injected), 'refused': True, 'restored': True},
                    sort_keys=True))

    def test_distinct_pending_observation_reconciles_at_real_publication(self):
        from functools import wraps
        path = 'extensions/carla/curve_rounded_line.mojo'
        physical = (self.root/path).read_bytes()
        site = self._site(accepted._verify_current_for_pin_pair, 162, '(root / path).read_text()')
        original_read, original_match = Path.read_text, cleanup._InvariantInputs._match
        original_token = source.token_sha256
        marked, injected, reconciled, token_uses = [], [], [], []
        @wraps(original_read)
        def read(actual, *args, **kwargs):
            value = original_read(actual, *args, **kwargs)
            frame = sys._getframe(1)
            if site(frame) and actual == self.root/path and not injected:
                operation = frame.f_locals['_operation']
                self.assertIs(type(operation), cleanup._InvariantInputs)
                self.assertEqual(operation._state, 'pending')
                self.assertFalse(operation._capturing)
                injected.append(operation)
                value += '\n# queued observation B\n'
                marked.append(value)
            return value
        @wraps(original_token)
        def token(value, *args, **kwargs):
            if marked and value is marked[0]:
                frame = sys._getframe(1)
                self.assertIs(frame.f_globals, vars(cleanup))
                self.assertEqual(injected[0]._state, 'pending')
                token_uses.append(frame.f_code)
            return original_token(value, *args, **kwargs)
        @wraps(original_match)
        def match(operation, root, name, value, mode):
            if marked and value is marked[0]:
                caller = sys._getframe(1)
                self.assertIs(self._frame(cleanup._InvariantInputs._publish, caller), caller)
                self.assertIs(operation, injected[0])
                self.assertEqual((name, mode), (path, 'default'))
                self.assertEqual(operation._state, 'active')
                self.assertTrue(operation._capturing)
                self.assertIn((path, value, mode), operation._observations)
                reconciled.append(operation)
            return original_match(operation, root, name, value, mode)
        with self.audit() as events, patch.object(Path, 'read_text', read), \
                patch.object(source, 'token_sha256', token), \
                patch.object(cleanup._InvariantInputs, '_match', match):
            with self.assertRaises(ValueError) as raised:
                invariant.verify(self.root)
        self.assertEqual(len(injected), 1)
        operation = injected[0]
        self.assertEqual(reconciled, [operation])
        # Typed provenance admission now happens before the accepted semantic
        # comparison. Only its two supplied-view checks and the checked-raw
        # observation may tokenize B before exact queued publication refuses it.
        self.assertEqual(token_uses, [cleanup.reviewed_typed_text.__code__,
                                      cleanup.reviewed_typed_text.__code__,
                                      cleanup._observe_text.__code__])
        self.assertEqual(events['records'], [])
        self.assert_public_coherence_error(raised.exception, operation)
        self._assert_refused(events, operation,
            'full-audit cleanup successor: consumed operation text changed: ' + path)
        self.assertEqual((self.root/path).read_bytes(), physical)

    def test_distinct_grouped_y_batch_reads_all_five_before_observation_refusal(self):
        from functools import wraps
        import grouped_y_finiteness_contracts as grouped
        site = self._site(grouped.verify, 31, '(root / p).read_text()')
        path = next(iter(grouped.EXPECTED))
        physical = (self.root/path).read_bytes()
        original_read, original_verify = Path.read_text, grouped.verify_text
        marked, injected, reads, batches = [], [], [], []
        @wraps(original_read)
        def read(actual, *args, **kwargs):
            value = original_read(actual, *args, **kwargs)
            frame = sys._getframe(1)
            operation = self._active(grouped.verify, frame)
            if (site(frame) and operation is not None
                    and self._frame(accepted._verify_current_for_pin_pair,
                                    self._frame(grouped.verify, frame).f_back)
                    is self._frame(grouped.verify, frame).f_back):
                body = self._frame(grouped.verify, frame)
                if not batches:
                    batches.append(body)
                if body is batches[0]:
                    reads.append(actual.relative_to(self.root).as_posix())
                    if actual == self.root/path:
                        self.assertEqual(injected, [])
                        injected.append(operation)
                        value += '\n# grouped batch B\n'
                        arm_semantic_sinks()
                        marked.append(value)
            return value
        @wraps(original_verify)
        def verify(modules):
            self.assertFalse(any(value is item for value in modules.values() for item in marked))
            return original_verify(modules)
        with self.audit() as events, patch.object(Path, 'read_text', read), \
                patch.object(grouped, 'verify_text', verify), self._no_marked_semantics(marked) as arm_semantic_sinks:
            with self.assertRaises(ValueError) as raised:
                invariant.verify(self.root)
        self.assertEqual(len(injected), 1)
        self.assertEqual(reads, list(grouped.EXPECTED))
        operation = injected[0]
        self.assert_public_coherence_error(raised.exception, operation)
        self._assert_refused(events, operation,
            'full-audit cleanup successor: consumed operation text changed: ' + path)
        self.assertTrue(events['records'])
        self.assertEqual((self.root/path).read_bytes(), physical)

    def test_distinct_raw_cut_second_json_text_binds_original_checked_bytes(self):
        from functools import wraps
        import raw_cut_inverse_contracts as raw_cut
        path = 'tools/carla_lane_oracle/curve-support-dispatch-migration.json'
        physical = (self.root/path).read_bytes()
        site = self._site(raw_cut.verify_premises, 66,
                         "(root / 'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_text()")
        original = Path.read_text
        marked, injected, checked = [], [], []
        @wraps(original)
        def read(actual, *args, **kwargs):
            value = original(actual, *args, **kwargs)
            frame = sys._getframe(1)
            operation = self._active(raw_cut.verify_premises, frame)
            if (site(frame) and actual == self.root/path and operation is not None
                    and self._followup_route(frame)
                    and self._frame(raw_cut.verify, frame.f_back) is frame.f_back
                    and self._frame(followup.verify, frame.f_back.f_back) is frame.f_back.f_back
                    and not injected):
                self.assertEqual(frame.f_locals['predecessor_payload'], physical)
                self.assertEqual(hashlib.sha256(physical).hexdigest(),
                                 frame.f_locals['record']['predecessor_migration_sha256'])
                checked.append(frame.f_locals['predecessor_payload'])
                injected.append(operation)
                value = ' \n' + value
                arm_semantic_sinks()
                marked.append(value)
            return value
        with self.audit() as events, patch.object(Path, 'read_text', read), \
                self._no_marked_semantics(marked) as arm_semantic_sinks:
            with self.assertRaises(cleanup._OperationCoherenceError) as raised:
                invariant.verify(self.root)
        self.assertEqual(len(injected), 1)
        self.assertEqual(checked, [physical])
        operation = injected[0]
        reason = 'full-audit cleanup successor: checked physical and supplied views differ: ' + path
        self._assert_direct(raised.exception, operation, reason)
        self._assert_refused(events, operation, reason)
        self.assertEqual((self.root/path).read_bytes(), physical)

    def test_distinct_explicit_utf8_pins_and_group_refuse_before_semantics(self):
        from functools import wraps
        import winner_sign_contracts as winner
        cases = ((source.read_pins, 202, "(root / PINS).read_text(encoding='utf-8')", source.PINS),
                 (source.verify_group, 234, "(root / path).read_text(encoding='utf-8')",
                  'extensions/carla/curve_sum2.mojo'))
        for function, line, expression, path in cases:
            with self.subTest(role=function.__name__):
                site = self._site(function, line, expression)
                original, physical = Path.read_text, (self.root/path).read_bytes()
                marked, injected, modes = [], [], []
                observe = cleanup._operation_observe
                @wraps(original)
                def read(actual, *args, **kwargs):
                    value = original(actual, *args, **kwargs)
                    frame = sys._getframe(1)
                    operation = self._active(function, frame)
                    group = self._frame(source.verify_group, frame)
                    if (site(frame) and actual == self.root/path and operation is not None
                            and group is not None and group.f_locals['group'] == 'canonical_accumulation'
                            and self._frame(winner.verify, group.f_back) is group.f_back and not injected):
                        self.assertEqual(kwargs, {'encoding': 'utf-8'})
                        self.assertEqual(args, ())
                        injected.append(operation)
                        value = (' \n' + value if function is source.read_pins
                                 else value + '\n# UTF8 group B\n')
                        arm_semantic_sinks()
                        marked.append(value)
                    return value
                @wraps(observe)
                def observed(operation, root, name, value, mode):
                    if marked and value is marked[0]:
                        self.assertIs(operation, injected[0])
                        self.assertEqual(name, path)
                        modes.append(mode)
                    return observe(operation, root, name, value, mode)
                with self.audit() as events, patch.object(Path, 'read_text', read), \
                        patch.object(cleanup, '_operation_observe', observed), self._no_marked_semantics(marked) as arm_semantic_sinks:
                    with self.assertRaises(cleanup._OperationCoherenceError) as raised:
                        winner.verify(self.root)
                self.assertEqual(len(injected), 1)
                self.assertEqual(modes, ['physical'])
                operation = injected[0]
                reason = 'full-audit cleanup successor: consumed operation text changed: ' + str(path)
                self._assert_direct(raised.exception, operation, reason)
                self._assert_refused(events, operation, reason)
                self.assertEqual((self.root/path).read_bytes(), physical)

    def _lease_sites(self, cache, seed):
        # Keep the four original IDs; the new census observation is slot 5
        # and executes between slots 2 and 3.
        return (
            self._site(cache.inventory, 106, '_inputs.observe_bytes(_input_owner, root, rel.as_posix())'),
            self._site(seed.verify_score, 649, '_inputs.observe_bytes(_input_owner, root, MODULE)'),
            self._site(seed.verify_score, 684, '_inputs.observe_bytes(_input_owner, root, MODULE)'),
            self._site(cache.inventory, 150, '_inputs.observe_bytes(_input_owner, root, rel.as_posix())'),
            self._site(seed.verify_score_caller_inventory, 'station-census',
                       '_inputs.observe_bytes(_input_owner, root, MODULE)'),
        )

    @staticmethod
    def _lease_position(frame, sites):
        while frame is not None:
            for position, matches in enumerate(sites, 1):
                if matches(frame):
                    return position
            frame = frame.f_back
        return None

    def test_distinct_borrowed_map_observations_delegate_all_five_faults(self):
        from functools import wraps
        import os
        import cache_key_contracts as cache
        import seed_count_contracts as seed
        path = 'extensions/carla/map.mojo'
        physical = (self.root/path).read_bytes()
        sites = self._lease_sites(cache, seed)
        primitive = self._site(cleanup._CacheInputs.observe_bytes, 1205,
                               '_regular(root, path).read_bytes()')
        sequence = (1, 2, 5, 3, 4)
        for fault in ('changed', 'foreign_bytes', 'io', 'context', 'fourth', 'census'):
            with self.subTest(fault=fault):
                injected, selected, successes, attempts, equality = [], [], [], [], []
                failure = PermissionError('distinct borrowed Map read denied')
                original_read = Path.read_bytes
                original_observe = cleanup._BorrowedCacheInputs.observe_bytes
                original_check = cleanup._BorrowedCacheInputs._check
                class ForeignBytes(bytes):
                    def __eq__(self, other):
                        equality.append(other)
                        raise AssertionError('non-builtin bytes reached equality')
                def choose(lease, frame):
                    position = self._lease_position(frame, sites)
                    if (type(lease) is cleanup._BorrowedCacheInputs
                            and self._cache_followup_route(cache, frame) and position is not None):
                        if not selected:
                            self.assertEqual(position, 1)
                            self.assertEqual(lease._operation._state, 'active')
                            selected.append((lease, lease._operation))
                        if lease is selected[0][0]:
                            return position
                    return None
                @wraps(original_observe)
                def observe(lease, owner, root, name):
                    position = choose(lease, sys._getframe(1)) if name == path else None
                    if position is not None:
                        attempts.append((lease, position))
                    value = original_observe(lease, owner, root, name)
                    if position is not None:
                        self.assertIs(type(value), bytes)
                        self.assertEqual(value, physical)
                        successes.append((lease, position, value))
                    return value
                @wraps(original_read)
                def read(actual, *args, **kwargs):
                    value = original_read(actual, *args, **kwargs)
                    frame = sys._getframe(1)
                    if primitive(frame) and actual == self.root/path and fault != 'context':
                        lease = frame.f_locals['self']
                        position = choose(lease, frame)
                        target = 4 if fault == 'fourth' else 5 if fault == 'census' else 1
                        if position == target and not injected:
                            self.assertEqual(value, physical)
                            if fault in ('fourth', 'census'):
                                self.assertEqual([(view is lease, slot, data == physical)
                                                  for view, slot, data in successes],
                                                 [(True, slot, True) for slot in sequence[:sequence.index(target)]])
                            injected.append((lease, position))
                            if fault == 'io':
                                raise failure
                            if fault == 'foreign_bytes':
                                return ForeignBytes(value)
                            return value + b'\n# borrowed Map B\n'
                    return value
                @wraps(original_check)
                def check(lease, owner, root):
                    frame = sys._getframe(1)
                    base = self._frame(cleanup._CacheInputs.observe_bytes, frame)
                    if (fault == 'context' and not injected and base is not None
                            and base.f_locals['path'] == path
                            and self._frame(cleanup._CacheInputs.raw, frame) is frame
                            and choose(lease, frame) == 1):
                        injected.append((lease, 1))
                        before = Path.cwd()
                        self.assertNotEqual(before, self.root)
                        try:
                            os.chdir(self.root)
                            return original_check(lease, owner, root)
                        finally:
                            os.chdir(before)
                    return original_check(lease, owner, root)
                with self.audit() as events, patch.object(Path, 'read_bytes', read), \
                        patch.object(cleanup._BorrowedCacheInputs, 'observe_bytes', observe), \
                        patch.object(cleanup._BorrowedCacheInputs, '_check', check):
                    with self.assertRaises(cleanup._OperationCoherenceError) as raised:
                        invariant.verify(self.root)
                self.assertEqual(len(selected), 1)
                lease, operation = selected[0]
                target = 4 if fault == 'fourth' else 5 if fault == 'census' else 1
                self.assertEqual(injected, [(lease, target)])
                self.assertEqual(attempts, [(lease, slot) for slot in sequence[:sequence.index(target) + 1]])
                self.assertEqual([(view, slot) for view, slot, value in successes],
                                 [(lease, slot) for slot in sequence[:sequence.index(target)]])
                self.assertEqual(equality, [])
                detail = ('cache input root or working directory changed' if fault == 'context'
                          else ('unreadable owned input: ' if fault == 'io' else 'owned input changed: ') + path)
                reason = 'full-audit cleanup successor: ' + detail
                self._assert_direct(raised.exception, operation, reason)
                if fault == 'io':
                    self.assertIs(raised.exception.__cause__.__cause__, failure)
                else:
                    self.assertIsNone(raised.exception.__cause__.__cause__)
                self._assert_refused(events, operation, reason)
                self._assert_lease_closed(lease)
                self.assertEqual((self.root/path).read_bytes(), physical)

    def test_distinct_borrowed_map_local_supplied_text_preserves_its_own_contract(self):
        from functools import wraps
        import cache_key_contracts as cache
        import seed_count_contracts as seed
        path = 'extensions/carla/map.mojo'
        physical = (self.root/path).read_bytes()
        site = self._site(cache.inventory, 103, 'path.read_text()')
        local_require = self._site(cache.inventory, 113,
            "require(source.token_sha256(text) == source.token_sha256(_inputs.text_default(_input_owner, root, rel.as_posix())) == seed_count.score_family_token_sha256(hashlib.sha256(physical).hexdigest()), 'unreviewed supplied score-helper source')")
        sites = self._lease_sites(cache, seed)
        for fault in ('comment', 'tokens', 'io'):
            with self.subTest(fault=fault):
                injected, selected, compared, observations, projected = [], [], [], [], []
                failure = OSError('distinct local supplied Map read denied')
                original_read, original_require = Path.read_text, cache.require
                original_observe = cleanup._BorrowedCacheInputs.observe_bytes
                original_projection = seed.score_family_predecessor_source
                @wraps(original_read)
                def read(actual, *args, **kwargs):
                    value = original_read(actual, *args, **kwargs)
                    frame = sys._getframe(1)
                    if site(frame) and actual == self.root/path and self._cache_followup_route(cache, frame) and not injected:
                        lease = frame.f_locals['_inputs']
                        self.assertIs(type(lease), cleanup._BorrowedCacheInputs)
                        self.assertEqual(lease._operation._state, 'active')
                        selected.append((lease, lease._operation))
                        injected.append(fault)
                        if fault == 'io':
                            raise failure
                        return value + ('\n# local supplied comment B\n' if fault == 'comment'
                                        else '\nvar distinct_unreviewed_map_token = 1\n')
                    return value
                @wraps(original_require)
                def require(condition, message):
                    frame = sys._getframe(1)
                    if (selected and local_require(frame)
                            and frame.f_locals['_inputs'] is selected[0][0]):
                        compared.append(condition)
                    return original_require(condition, message)
                @wraps(original_observe)
                def observe(lease, owner, root, name):
                    position = self._lease_position(sys._getframe(1), sites)
                    value = original_observe(lease, owner, root, name)
                    if selected and lease is selected[0][0] and name == path and position is not None:
                        self.assertEqual(value, physical)
                        observations.append(position)
                    return value
                @wraps(original_projection)
                def projection(text):
                    frame = self._frame(cache.inventory, sys._getframe(1))
                    if selected and frame is not None and frame.f_locals['_inputs'] is selected[0][0]:
                        projected.append(text)
                    return original_projection(text)
                with self.audit() as events, patch.object(Path, 'read_text', read), \
                        patch.object(cache, 'require', require), \
                        patch.object(cleanup._BorrowedCacheInputs, 'observe_bytes', observe), \
                        patch.object(seed, 'score_family_predecessor_source', projection):
                    if fault == 'comment':
                        result = invariant.verify(self.root)
                    else:
                        with self.assertRaises(cache.ContractError) as raised:
                            invariant.verify(self.root)
                self.assertEqual(injected, [fault])
                self.assertEqual(len(selected), 1)
                lease, operation = selected[0]
                if fault == 'comment':
                    self.assertEqual(len(result['sources']), 4)
                    self.assertEqual(compared, [True])
                    self.assertEqual(observations, [1, 2, 5, 3, 4])
                    self.assertTrue(projected)
                    self.assertIs(self.assert_one_owner(events, 'invariant'), operation)
                else:
                    self.assertIs(type(raised.exception), cache.ContractError)
                    self.assertEqual(events['admissions'], [operation])
                    self.assertEqual(events['finalizers'], [])
                    self.assertEqual(compared, [False] if fault == 'tokens' else [])
                    self.assertEqual(observations, [1] if fault == 'tokens' else [])
                    self.assertEqual(projected, [])
                    self.assertEqual(str(raised.exception), 'cache-key successor: ' + (
                        'unreviewed supplied score-helper source' if fault == 'tokens'
                        else 'unreadable owned Map view'))
                    self.assertIs(raised.exception.__cause__, failure if fault == 'io' else None)
                    self.assert_closed(operation)
                self._assert_lease_closed(lease)
                self.assertEqual((self.root/path).read_bytes(), physical)

    def test_distinct_fresh_production_and_known_discoveries_refuse_four_faults(self):
        from functools import wraps
        loops, core = self.coverage()
        from carla_lane_oracle import seed_count_contracts as seed
        production_site = self._site(seed.verify_score_caller_inventory, 542,
                                     'guard.production_mojo_paths(root)')
        known_site = self._site(loops._construction_boundary_callers, 1220,
                                'cache_key.input_paths(Path(root))')
        production_catch = self._site(core._operation_production_paths, 1541,
                                      '_operation_fail(_operation, error)')
        known_catch = self._site(loops.construction_boundary_loops, 1349,
                                 'cleanup._operation_fail(_operation, error)')
        omitted = 'extensions/carla/cameras.mojo'
        added = 'extensions/carla/distinct_unlisted_discovery.mojo'
        self.assertNotIn('_winner_seed_update_score', (self.root/omitted).read_text())
        self.assertFalse((self.root/added).exists())
        for fault in ('production_omit', 'production_io', 'known_add', 'known_io'):
            with self.subTest(fault=fault):
                production = fault.startswith('production')
                module = seed.guard if production else loops.cache_key
                name = 'production_mojo_paths' if production else 'input_paths'
                original = getattr(module, name)
                original_fail, original_discovery = core._operation_fail, core._InvariantInputs._discovery
                injected, selected, yielded, exhausted, comparisons, caught = [], [], [], [], [], []
                failure = OSError('distinct ' + fault + ' iterator denied')
                site = production_site if production else known_site
                function = seed.verify_score_caller_inventory if production else loops._construction_boundary_callers
                @wraps(original)
                def discovered(root, *args, **kwargs):
                    iterator = original(root, *args, **kwargs)
                    frame = sys._getframe(1)
                    operation = self._active(function, frame, core)
                    if not site(frame) or operation is None or selected:
                        return iterator
                    self.assertEqual(Path(root), self.root)
                    if production:
                        self.assertIsNone(frame.f_locals['_inputs'])
                    selected.append(operation)
                    def changed():
                        for path in iterator:
                            relative = path.relative_to(self.root).as_posix() if production else path.as_posix()
                            yielded.append(relative)
                            if fault.endswith('_io') and not injected:
                                injected.append(fault)
                                raise failure
                            if fault == 'production_omit' and relative == omitted:
                                self.assertEqual(injected, [])
                                injected.append(fault)
                                continue
                            yield path
                        exhausted.append(True)
                        if fault == 'known_add':
                            self.assertEqual(injected, [])
                            injected.append(fault)
                            yield Path(added)
                    return changed()
                @wraps(original_discovery)
                def discovery(operation, root, paths, kind):
                    if selected and operation is selected[0] and injected:
                        comparisons.append((kind, paths))
                    return original_discovery(operation, root, paths, kind)
                @wraps(original_fail)
                def fail(operation, error):
                    if error is failure:
                        self.assertIs(operation, selected[0])
                        self.assertTrue((production_catch if production else known_catch)(sys._getframe(1)))
                        caught.append(error)
                    return original_fail(operation, error)
                with self.audit(core) as events, patch.object(module, name, discovered), \
                        patch.object(core._InvariantInputs, '_discovery', discovery), \
                        patch.object(core, '_operation_fail', fail):
                    result = loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map')
                self.assertEqual(result, {})
                self.assertEqual(injected, [fault])
                self.assertEqual(len(selected), 1)
                operation = selected[0]
                self.assertTrue(yielded)
                if fault.endswith('_io'):
                    self.assertEqual(caught, [failure])
                    self.assertEqual(exhausted, [])
                    self.assertEqual(comparisons, [])
                    reason = str(failure)
                else:
                    self.assertEqual(caught, [])
                    self.assertEqual(exhausted, [True])
                    expected = set(yielded)
                    if production:
                        self.assertEqual(yielded.count(omitted), 1)
                        expected.remove(omitted)
                    else:
                        self.assertNotIn(added, yielded)
                        expected = {path for path in expected if Path(path).suffix == '.mojo'} | {added}
                    kind = 'production' if production else 'known'
                    self.assertEqual(comparisons, [(kind, frozenset(expected))])
                    reason = 'full-audit cleanup successor: consumed operation path census changed: ' + kind
                self._assert_refused(events, operation, reason, core)
                self.assertFalse((self.root/added).exists())

    def test_distinct_late_map_finalizer_discards_every_real_completed_proof(self):
        from functools import wraps
        loops, core = self.coverage()
        module = 'extensions/carla/map'
        expected = {rule[5] for rule in loops.GUARDED_LOOP_RULES if rule[0] == module}
        expected.add('construction-geometry-boundary-list')
        self.assertGreater(len(expected), 1)
        original, original_fail = core._InvariantInputs.finish, core._operation_fail
        physical = (self.root/ROAD).read_bytes()
        injected, completed, failures = [], [], []
        reason = 'full-audit cleanup successor: owned input changed: ' + ROAD
        @wraps(original)
        def finish(operation, root):
            frame = sys._getframe(1)
            self.assertIs(self._frame(loops.reviewed_nonempty_loops, frame), frame)
            self.assertIs(frame.f_locals['_operation'], operation)
            self.assertEqual(frame.f_locals['module'], module)
            self.assertEqual(operation._state, 'active')
            self.assertEqual(injected, [])
            rows = frame.f_locals['result']
            self.assertTrue(all(line == row['line'] for line, row in rows.items()))
            proof_ids = {row['proof_id'] for row in rows.values()}
            self.assertLessEqual(expected, proof_ids)
            completed.append(proof_ids)
            injected.append(operation)
            (root/ROAD).write_bytes(physical + b'\n# late finalizer B\n')
            return original(operation, root)
        @wraps(original_fail)
        def fail(operation, error):
            if injected and operation is injected[0] and str(error) == reason:
                failures.append(error)
            return original_fail(operation, error)
        try:
            with self.audit(core) as events, patch.object(core._InvariantInputs, 'finish', finish), \
                    patch.object(core, '_operation_fail', fail):
                result = loops.reviewed_nonempty_loops(self.root, module)
        finally:
            (self.root/ROAD).write_bytes(physical)
        self.assertEqual(result, {})
        self.assertEqual(len(injected), 1)
        self.assertEqual(len(completed), 1)
        self.assertLessEqual(expected, completed[0])
        self.assertEqual(len(failures), 1)
        self.assertIs(type(failures[0]), core.ContractError)
        self.assertIsNone(failures[0].__cause__)
        self._assert_refused(events, injected[0], reason, core, finalized=True)
        self.assertEqual((self.root/ROAD).read_bytes(), physical)


class ReviewedAbsoluteRootTextMechanics(unittest.TestCase):
    """Pure root spelling conversion; no input admission or cached authority."""

    _V35_CALLER_AST = {
        '_CacheInputs._check_context': '6e5b17072ca307797a39ef291fd0fee1ba431a0a5dfddde1e7ceda0672c9921d',
        '_private_operation_wrapper': '85e1d09445b46b340c3ba5b4973463a685b14487845a07cd365420295c61c29c',
    }
    _HELPER_AST_SHA = '280c064b53770cbdb8239251de6a5e629884a9f491b5979911058b100c6f0312'
    _ROOT_BUILTINS = ('__import__', 'all', 'getattr', 'isinstance', 'len', 'list', 'next', 'str',
                      'type', 'vars', 'ImportError', 'OSError', 'ValueError',
                      'TypeError', 'RuntimeError')

    @staticmethod
    def _one_definition(body, name):
        matches = [node for node in body if isinstance(node, (ast.FunctionDef, ast.ClassDef))
                   and node.name == name]
        if len(matches) != 1:
            raise AssertionError(('one root-conversion definition', name))
        return matches[0]

    @staticmethod
    def _binding_sites(body, names):
        # This is a finite declaration/rebinding check, not a source evaluator.
        # Do not descend into unrelated function or class local namespaces.
        sites = []
        for statement in body:
            if isinstance(statement, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                bound = {statement.name}
            else:
                bound = set()
                for node in ast.walk(statement):
                    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                        bound.add(node.name)
                    elif isinstance(node, (ast.Import, ast.ImportFrom)):
                        bound.update(alias.asname or alias.name.split('.')[0] for alias in node.names)
                    elif isinstance(node, ast.Name) and isinstance(node.ctx, (ast.Store, ast.Del)):
                        bound.add(node.id)
                    elif isinstance(node, ast.ExceptHandler) and node.name:
                        bound.add(node.name)
                    elif isinstance(node, (ast.Attribute, ast.Subscript)) and isinstance(node.ctx, (ast.Store, ast.Del)):
                        target = node.value
                        while isinstance(target, (ast.Attribute, ast.Subscript)):
                            target = target.value
                        if isinstance(target, ast.Name):
                            bound.add(target.id)
            if bound.intersection(names):
                sites.append(statement)
        return sites

    def _assert_root_projection(self, tree, source_tree):
        definitions = {name: self._one_definition(tree.body, name) for name in
                       ('_absolute_root_text', '_CacheInputs', '_private_operation_wrapper',
                        '_owner_module', 'require', 'ContractError')}
        helper = copy.deepcopy(definitions['_absolute_root_text'])
        condition = helper.body[1].body[1].body[1]
        _rc21_expect_ast(condition.test, '54e8dec820940f1e9f7fa3db81947711670b43becdf24ef3a4c4fd7a62e60c38',
                         'V10 root-string condition AST drift')
        condition.test = ast.parse("text == '/' or (text.startswith('/') and all("
                                   "part not in ('', '.', '..') for part in text[1:].split('/')))",
                                   mode='eval').body
        _rc21_expect_ast(helper, self._HELPER_AST_SHA, 'complete original root helper AST drift')

        cls = definitions['_CacheInputs']
        context = self._one_definition(cls.body, '_check_context')
        self.assertEqual(self._binding_sites(cls.body, {'_check_context'}), [context])
        header = copy.deepcopy(cls)
        header.body = []
        _rc21_expect_ast(header, '4e8b41b5eb76c028593ead8ae5d8bf20afaed0df8f1a5a124de6e3923e1e50c8',
                         'root-conversion owner class header AST drift')
        for name, node in (('_CacheInputs._check_context', context),
                           ('_private_operation_wrapper', definitions['_private_operation_wrapper'])):
            checked = (owner_helpers.typed_owner_ast(node, 'private', reverse=True)
                       if name == '_private_operation_wrapper' else node)
            original, count = self._reverse(checked)
            self.assertEqual(count, 1)
            _rc21_expect_ast(original, self._V35_CALLER_AST[name], (name, 'complete V35 caller AST drift'))
        # Retain the original two-site assertion across the complete module.
        without_helper = copy.deepcopy(tree)
        without_helper.body = [node for node in without_helper.body
                               if not isinstance(node, ast.FunctionDef) or node.name != '_absolute_root_text']
        _, count = self._reverse(without_helper)
        self.assertEqual(count, 2)

        for name, expected in (
                ('require', '531a60a4ed0275a1b20c7a1dfade0631ab04a8f49bc6c143fd5895c687b322e1'),
                ('ContractError', 'a2c26b3043e0cbb0f8e9f746710f1dd081901375b1feeeec02a62e11d5f3b587')):
            _rc21_expect_ast(definitions[name], expected, (name, 'root-conversion dependency AST drift'))
        owner = owner_helpers.typed_owner_predecessor(definitions['_owner_module'])
        _rc21_expect_ast(owner.body[1], '73a7cd0ab7fe92a00574301143c48c926cf3f46080c65edc3fc5f35b09b42553',
                         'V14 root-conversion owner dispatch AST drift')
        owner.body[1] = owner.body[1].orelse[0]
        _rc21_expect_ast(owner, 'a5f60b07d07556090def6d3490be5dfeef8197ef71d8e3ff13efce5c110d4860',
                         'complete original root-conversion owner helper AST drift')

        watched = set(definitions) | set(self._ROOT_BUILTINS) | {'Path', 'PosixPath', 'os', 'sys', 'types', 'source', '__package__'}
        imports = [node for node in tree.body if isinstance(node, (ast.Import, ast.ImportFrom))
                   and self._binding_sites([node], watched)]
        self.assertEqual([ast_key(node) for node in imports], [ast_key(node) for node in ast.parse(
            'import types\nimport os\nfrom pathlib import Path, PosixPath\nimport sys').body])
        routes = [node for node in tree.body if isinstance(node, ast.Try)
                  and any(isinstance(child, (ast.Import, ast.ImportFrom))
                          and any(alias.asname == 'source' for alias in child.names) for child in ast.walk(node))]
        self.assertEqual(len(routes), 1)
        route = copy.deepcopy(routes[0])
        # Project unrelated sibling imports only. Preserve package routing,
        # exception handling and every binding relevant to this closure.
        for branch in (route.body[0].body, route.body[0].orelse):
            branch[:] = [node for node in branch if not isinstance(node, (ast.Import, ast.ImportFrom))
                         or self._binding_sites([node], watched)]
        _rc21_expect_ast(route, '718148af9e25144b4b3f6f8b8ceef51c21dd18ad5c5160f2931e41eb77860e60',
                         'root-conversion source import route AST drift')
        allowed = [*definitions.values(), *imports, routes[0]]
        self.assertEqual(self._binding_sites(tree.body, watched),
                         [node for node in tree.body if node in allowed])

        scope = self._one_definition(source_tree.body, 'lexical_memo_scope')
        _rc21_expect_ast(scope, '00d14c23b4efc7ab3aec27e257848bf15c652a028f8c88a589f9fb30bdd3007c',
                         'root-conversion lexical scope identity AST drift')
        scope_bindings = self._binding_sites(source_tree.body, {'lexical_memo_scope', 'contextmanager'})
        self.assertEqual(len(scope_bindings), 2)
        self.assertEqual(ast_key(scope_bindings[0]), ast_key(ast.parse('from contextlib import contextmanager').body[0]))
        self.assertIs(scope_bindings[1], scope)

    def _checked_functions(self):
        import abc
        import builtins
        import contextlib
        import os
        import pathlib
        import types
        if (cleanup.os.name != 'posix' or sys.version_info[:2] != (3, 12)
                or type(getattr(pathlib.PosixPath('/alpha'), '_raw_paths', None)) is not list):
            self.skipTest('fast-layout matrix requires pinned Python3.12 POSIX pathlib')
        raw = Path(cleanup.__file__).read_bytes()
        tree = ast.parse(raw)
        helper = next(item for item in tree.body
                      if isinstance(item, ast.FunctionDef) and item.name == '_absolute_root_text')
        source_raw = Path(source.__file__).read_bytes()
        source_tree = ast.parse(source_raw)
        self._assert_root_projection(tree, source_tree)
        compiled = compile(raw, cleanup.__file__, 'exec', dont_inherit=True, optimize=sys.flags.optimize)
        codes = [item for item in compiled.co_consts if isinstance(item, types.CodeType)
                 and item.co_name == '_absolute_root_text']
        self.assertEqual(codes, [cleanup._absolute_root_text.__code__])
        pending = [compiled]
        core_codes = {}
        while pending:
            code = pending.pop()
            core_codes[code.co_qualname] = code
            pending.extend(item for item in code.co_consts if isinstance(item, types.CodeType))
        self.assertEqual(core_codes['_CacheInputs._check_context'], cleanup._CacheInputs._check_context.__code__)
        self.assertEqual(core_codes['_private_operation_wrapper'], cleanup._private_operation_wrapper.__code__)
        for name in ('require', '_owner_module'):
            self.assertEqual(core_codes[name], getattr(cleanup, name).__code__)
        self.assertEqual(cleanup.ContractError.__bases__, (ValueError, RuntimeError))
        functions = (cleanup._absolute_root_text, cleanup._CacheInputs._check_context,
                     cleanup._private_operation_wrapper, cleanup.require, cleanup._owner_module)
        for function in functions:
            self.assertIs(function.__globals__, vars(cleanup))
        for name, value in (('os', os), ('sys', sys), ('types', types), ('source', source),
                            ('Path', pathlib.Path), ('PosixPath', pathlib.PosixPath)):
            self.assertIs(getattr(cleanup, name), value)
        self.assertIs(types.FunctionType, type(cleanup.require))
        self.assertIs(types.CodeType, type(cleanup.require.__code__))
        for name in self._ROOT_BUILTINS:
            self.assertNotIn(name, vars(cleanup))
            for function in functions:
                self.assertIs(function.__builtins__[name], getattr(builtins, name))
        # The bridge reads this decorated function's identity; it never executes
        # its memo body. Bind both layers without pulling in memo internals.
        source_compiled = compile(source_raw, source.__file__, 'exec', dont_inherit=True,
                                  optimize=sys.flags.optimize)
        scope_code = next(code for code in source_compiled.co_consts
                          if isinstance(code, types.CodeType) and code.co_name == 'lexical_memo_scope')
        self.assertIs(source.contextmanager, contextlib.contextmanager)
        self.assertEqual(source.lexical_memo_scope.__wrapped__.__code__, scope_code)
        self.assertIs(source.lexical_memo_scope.__wrapped__.__globals__, vars(source))
        context_raw = Path(contextlib.__file__).read_bytes()
        pending = [compile(context_raw, contextlib.__file__, 'exec', dont_inherit=True,
                           optimize=sys.flags.optimize)]
        context_codes = {}
        while pending:
            code = pending.pop()
            context_codes[code.co_qualname] = code
            pending.extend(item for item in code.co_consts if isinstance(item, types.CodeType))
        self.assertEqual(context_codes['contextmanager'], contextlib.contextmanager.__code__)
        self.assertEqual(context_codes['contextmanager.<locals>.helper'], source.lexical_memo_scope.__code__)
        self.assertIs(source.lexical_memo_scope.__globals__, vars(contextlib))
        self.assertEqual(source.lexical_memo_scope.__code__.co_freevars, ('func',))
        self.assertIs(source.lexical_memo_scope.__closure__[0].cell_contents,
                      source.lexical_memo_scope.__wrapped__)
        self.assertEqual(context_codes['ContextDecorator.__call__'], contextlib.ContextDecorator.__call__.__code__)
        self.assertIs(contextlib.contextmanager.__globals__, vars(contextlib))
        self.assertIs(contextlib.ContextDecorator.__call__.__globals__, vars(contextlib))
        manager = contextlib._GeneratorContextManager
        self.assertIs(type(manager), abc.ABCMeta)
        self.assertEqual(manager.__bases__, (contextlib._GeneratorContextManagerBase,
                         contextlib.AbstractContextManager, contextlib.ContextDecorator))
        for owner, names in ((manager, ('__enter__', '__exit__')),
                             (contextlib._GeneratorContextManagerBase, ('__init__', '_recreate_cm'))):
            for name in names:
                method = vars(owner)[name]
                self.assertEqual(context_codes[owner.__name__ + '.' + name], method.__code__)
                self.assertIs(method.__globals__, vars(contextlib))
        # Bind the reference implementation to actual checked stdlib source,
        # independently of interpreter optimization or relocation.
        stdlib = Path(pathlib.__file__).read_bytes()
        pending = [compile(stdlib, pathlib.__file__, 'exec', dont_inherit=True,
                           optimize=sys.flags.optimize)]
        names = {'PurePath.__init__', 'PurePath.__str__', 'Path.__init__',
                 'Path.__new__', 'Path.absolute', 'Path.cwd', 'PurePath.is_absolute',
                 'PurePath._load_parts', 'PurePath._parse_path', 'PurePath._format_parsed_parts',
                 'PurePath.drive', 'PurePath.root', 'PurePath._tail', 'PurePath.with_segments'}
        found = {}
        while pending:
            code = pending.pop()
            if code.co_qualname in names:
                found[code.co_qualname] = code
            pending.extend(item for item in code.co_consts if isinstance(item, types.CodeType))
        for qualified in names:
            owner, name = qualified.split('.')
            live = getattr(getattr(pathlib, owner), name)
            if isinstance(live, property): live = live.fget
            self.assertEqual(found[qualified], live.__code__)
        return tree, helper

    @staticmethod
    def _root_text_outcome(call):
        try:
            value = call()
            return ('return', type(value), value)
        except Exception as error:
            cause = error.__cause__
            return ('error', type(error), error.args,
                    None if cause is None else (type(cause), cause.args))

    @staticmethod
    def _reverse(node):
        class Reverse(ast.NodeTransformer):
            def __init__(self):
                self.count = 0
            def visit_Call(self, item):
                item = self.generic_visit(item)
                if isinstance(item.func, ast.Name) and item.func.id == '_absolute_root_text':
                    if len(item.args) != 1 or item.keywords:
                        raise AssertionError('unexpected root helper call shape')
                    self.count += 1
                    value = ast.parse('str(Path(ROOT).absolute())', mode='eval').body
                    value.args[0].func.value.args[0] = item.args[0]
                    return ast.copy_location(value, item)
                return item
        reverse = Reverse()
        value = reverse.visit(copy.deepcopy(node))
        return value, reverse.count

    def test_only_two_original_root_expressions_change(self):
        # Native fallback is checked even outside the scoped POSIX layout matrix.
        self.assertEqual(cleanup._absolute_root_text('relative'), str(Path('relative').absolute()))
        self._checked_functions()

    def test_projection_accepts_unrelated_source_change(self):
        tree = ast.parse(Path(cleanup.__file__).read_bytes())
        source_tree = ast.parse(Path(source.__file__).read_bytes())
        unrelated = self._one_definition(tree.body, 'native_support_mapping')
        unrelated.body.insert(0, ast.Pass())
        self._assert_root_projection(tree, source_tree)

    def test_projection_rejects_relevant_source_and_binding_changes(self):
        original = ast.parse(Path(cleanup.__file__).read_bytes())
        original_source = ast.parse(Path(source.__file__).read_bytes())
        for mutation in ('require', 'exception_base', 'owner', 'path_import', 'package_route',
                         'builtin_rebinding', 'class_header', 'method_rebinding', 'method_duplicate',
                         'conditional_method_rebinding', 'scope_decorator', 'caller_cwd'):
            tree, source_tree = copy.deepcopy(original), copy.deepcopy(original_source)
            definitions = {node.name: node for node in tree.body
                           if isinstance(node, (ast.FunctionDef, ast.ClassDef))}
            if mutation == 'require':
                definitions['require'].body[0].test = ast.Constant(False)
            elif mutation == 'exception_base':
                definitions['ContractError'].bases[0] = ast.Name(id='TypeError', ctx=ast.Load())
            elif mutation == 'owner':
                definitions['_owner_module'].body[1].test = ast.Constant(False)
            elif mutation == 'path_import':
                node = next(node for node in tree.body if isinstance(node, ast.ImportFrom) and node.module == 'pathlib')
                node.module = 'unreviewed_pathlib'
            elif mutation == 'package_route':
                node = next(node for node in tree.body if isinstance(node, ast.Try))
                node.body[0].test = ast.Constant(True)
            elif mutation == 'builtin_rebinding':
                tree.body.append(ast.parse('str = unreviewed_str').body[0])
            elif mutation == 'class_header':
                definitions['_CacheInputs'].decorator_list.append(ast.Name(id='unreviewed_decorator', ctx=ast.Load()))
            elif mutation == 'method_rebinding':
                definitions['_CacheInputs'].body.append(ast.parse('_check_context = unreviewed_context').body[0])
            elif mutation == 'method_duplicate':
                context = self._one_definition(definitions['_CacheInputs'].body, '_check_context')
                definitions['_CacheInputs'].body.append(copy.deepcopy(context))
            elif mutation == 'conditional_method_rebinding':
                definitions['_CacheInputs'].body.append(ast.parse(
                    'if True:\n    def _check_context(self, root): pass').body[0])
            elif mutation == 'scope_decorator':
                self._one_definition(source_tree.body, 'lexical_memo_scope').decorator_list = []
            else:
                context = self._one_definition(definitions['_CacheInputs'].body, '_check_context')
                cwd = next(node for node in ast.walk(context) if isinstance(node, ast.Call)
                           and ast_key(node) == ast_key(ast.parse('Path.cwd()', mode='eval').body))
                cwd.func.attr = 'home'
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                self._assert_root_projection(tree, source_tree)

    def test_fresh_values_callbacks_and_fallback_errors_match(self):
        from pathlib import PosixPath, PurePosixPath, PureWindowsPath
        import os
        tree, helper = self._checked_functions()
        fast = next(item.lineno for item in ast.walk(helper) if isinstance(item, ast.Return)
                    and isinstance(item.value, ast.Name) and item.value.id == 'text')
        fallback = next(item.lineno for item in ast.walk(helper) if isinstance(item, ast.Return)
                        and isinstance(item.value, ast.Call))
        class Foreign:
            def __init__(self, events, value='/alpha', failure=False):
                self.events, self.value, self.failure = events, value, failure
            def __fspath__(self):
                self.events.append('fspath')
                if self.failure:
                    raise OSError('deliberate root callback failure')
                return self.value
        class Text(str):
            def __new__(cls, value, events, failure=None):
                result = super().__new__(cls, value)
                result.events, result.failure = events, failure
                return result
            def __bool__(self):
                self.events.append('text-bool')
                if self.failure == 'bool': raise ValueError('early lazy text failure')
                return len(self) != 0
            def split(self, *args, **kwargs):
                self.events.append('text-split')
                if self.failure == 'split': raise RuntimeError('late lazy text failure')
                return super().split(*args, **kwargs)
        class RawList(list):
            def __iter__(self):
                self.events.append('raw-iter')
                return super().__iter__()
        class Derived(PosixPath):
            def __getattribute__(self, name):
                if name == '_raw_paths':
                    object.__getattribute__(self, 'events').append('path-raw')
                return super().__getattribute__(name)
        def raw_case(kind):
            def factory(events):
                root = PosixPath('/alpha')
                if kind == 'missing':
                    del root._raw_paths
                elif kind == 'tuple':
                    root._raw_paths = ('/alpha',)
                elif kind == 'list-subclass':
                    value = RawList(['/alpha']); value.events = events
                    root._raw_paths = value
                elif kind == 'non-string':
                    root._raw_paths = [17]
                elif kind == 'lazy-string':
                    root._raw_paths = [Text('/alpha', events)]
                elif kind in ('lazy-early-failure', 'lazy-late-failure'):
                    root._raw_paths = [Text('/alpha' if kind == 'lazy-early-failure' else 'relative',
                                            events, 'bool' if kind == 'lazy-early-failure' else 'split')]
                elif kind == 'cached':
                    root._str, root._drv, root._root, root._tail_cached = '/wrong', '', '/', ['wrong']
                return root
            return factory
        def derived(events):
            root = Derived('/alpha'); root.events = events
            return root
        cases = []
        canonical = ['/', '/alpha', '/alpha/beta', '/with spaces', '/Å/雪', '/Case/case',
                     '/colon:part/back\\slash', '/nul\x00part', '/' + 'x'*512]
        for value in canonical:
            for parsed in (False, True):
                def factory(events, value=value, parsed=parsed):
                    root = PosixPath(value)
                    if parsed:
                        str(root); root.parts
                    return root
                cases.append((repr((value, parsed)), factory, 'fast', None))
        for value in ['', '.', '..', 'relative', '/alpha/', '//alpha', '///alpha',
                      '/alpha//beta', '/alpha/./beta', '/alpha/../beta']:
            cases.append((repr(value), lambda events, value=value: PosixPath(value), 'fallback', None))
        for value in ['/alpha', '', 17, None, b'/alpha']:
            cases.append(('foreign-'+repr(value), lambda events, value=value: value, 'fallback',
                          None if isinstance(value, str) else TypeError))
        cases.extend([('pure-posix', lambda events: PurePosixPath('/alpha'), 'fallback', None),
                      ('pure-windows', lambda events: PureWindowsPath('C:/alpha'), 'fallback', None)])
        cases.extend([
            ('multiple-raw', lambda events: PosixPath('/alpha', 'beta'), 'fallback', None),
            ('path-subclass', derived, 'fallback', None),
            ('pathlike', lambda events: Foreign(events), 'fallback', None),
            ('pathlike-raises', lambda events: Foreign(events, failure=True), 'fallback', OSError),
            ('pathlike-invalid', lambda events: Foreign(events, 17), 'fallback', TypeError),
            ('str-subclass', lambda events: Text('/alpha', events), 'fallback', None),
        ])
        for kind in ('missing', 'tuple', 'list-subclass', 'non-string', 'lazy-string',
                     'lazy-early-failure', 'lazy-late-failure', 'cached'):
            cases.append((kind, raw_case(kind), 'fast' if kind == 'cached' else 'fallback',
                          {'missing': AttributeError, 'non-string': AttributeError,
                           'lazy-early-failure': ValueError, 'lazy-late-failure': RuntimeError}.get(kind)))
        counts = Counter()
        for name, factory, expected_branch, expected_error in cases:
            with self.subTest(name=name):
                old_events, new_events, branches = [], [], []
                old_root, new_root = factory(old_events), factory(new_events)
                old_events.clear(); new_events.clear()
                def cwd_old():
                    old_events.append('cwd'); return '/observed-cwd'
                def cwd_new():
                    new_events.append('cwd'); return '/observed-cwd'
                with patch.object(os, 'getcwd', cwd_old), patch.object(
                        Path, 'stat', side_effect=AssertionError('unexpected filesystem stat')), patch.object(
                        Path, 'lstat', side_effect=AssertionError('unexpected filesystem lstat')), patch.object(
                        os, 'scandir', side_effect=AssertionError('unexpected filesystem scan')), patch(
                        'builtins.open', side_effect=AssertionError('unexpected filesystem open')), patch(
                        'io.open', side_effect=AssertionError('unexpected filesystem open')):
                    old = self._root_text_outcome(lambda: str(Path(old_root).absolute()))
                def trace(frame, event, arg):
                    if frame.f_code is cleanup._absolute_root_text.__code__ and event == 'line':
                        if frame.f_lineno == fast: branches.append('fast')
                        if frame.f_lineno == fallback: branches.append('fallback')
                    return trace
                previous = sys.gettrace()
                try:
                    sys.settrace(trace)
                    with patch.object(os, 'getcwd', cwd_new), patch.object(
                            Path, 'stat', side_effect=AssertionError('unexpected filesystem stat')), patch.object(
                            Path, 'lstat', side_effect=AssertionError('unexpected filesystem lstat')), patch.object(
                        os, 'scandir', side_effect=AssertionError('unexpected filesystem scan')), patch(
                        'builtins.open', side_effect=AssertionError('unexpected filesystem open')), patch(
                        'io.open', side_effect=AssertionError('unexpected filesystem open')):
                        new = self._root_text_outcome(lambda: cleanup._absolute_root_text(new_root))
                finally:
                    sys.settrace(previous)
                self.assertEqual(new, old)
                self.assertEqual(new[:2], ('return', str) if expected_error is None else ('error', expected_error))
                self.assertEqual(new_events, old_events)
                self.assertEqual(branches, [expected_branch])
                counts.update(branches)
        self.assertEqual(counts, {'fast': 19, 'fallback': 30})
        for root in (PosixPath('/alpha'), PosixPath('relative')):
            with self.subTest(missing_cwd=str(root)), patch.object(os, 'getcwd', side_effect=OSError('missing cwd')):
                new = self._root_text_outcome(lambda: cleanup._absolute_root_text(root))
                self.assertEqual(new, self._root_text_outcome(lambda: str(Path(root).absolute())))
                self.assertEqual(new[:2], ('return', str) if root.is_absolute() else ('error', OSError))
        import types
        with patch.object(cleanup, 'os', types.SimpleNamespace(name='unsupported')):
            self.assertEqual(cleanup._absolute_root_text(PosixPath('/alpha')), '/alpha')

    def test_context_keeps_fresh_cwd_short_circuit_and_exception_order(self):
        import os
        from types import SimpleNamespace
        tree, helper = self._checked_functions()
        cls = next(item for item in tree.body if isinstance(item, ast.ClassDef) and item.name == '_CacheInputs')
        node = next(item for item in cls.body if getattr(item, 'name', None) == '_check_context')
        reference, count = self._reverse(node)
        self.assertEqual(count, 1)
        namespace = dict(vars(cleanup))
        exec(compile(ast.fix_missing_locations(ast.Module(body=[reference], type_ignores=[])),
                     '<original-context>', 'exec'), namespace)
        for root, stored, observed_cwd, includes, expected_cwd, succeeds in (
            ('/alpha', '/alpha', '/work', (), 1, True),
            ('/wrong', '/alpha', '/work', (), 0, False),
            ('/alpha', '/alpha', '/changed', (), 1, False),
            ('/alpha', '/alpha', OSError('missing cwd'), (), 1, False),
            ('/alpha', '/alpha', '/work', ('foreign',), 1, False),
            ('relative', '/work/relative', '/work', (), 2, True),
        ):
            outcomes, events = [], []
            for call in (namespace['_check_context'], cleanup._CacheInputs._check_context):
                seen = []
                def cwd():
                    seen.append('cwd')
                    if isinstance(observed_cwd, Exception): raise observed_cwd
                    return observed_cwd
                state = SimpleNamespace(_root=stored, _cwd='/work', _include_roots=includes)
                with patch.object(os, 'getcwd', cwd):
                    outcomes.append(self._root_text_outcome(lambda: call(state, Path(root))))
                events.append(seen)
            self.assertEqual(outcomes[0], outcomes[1])
            self.assertEqual(outcomes[1][:2], ('return', type(None)) if succeeds else ('error', cleanup.ContractError))
            self.assertEqual(events, [['cwd']*expected_cwd]*2)

    def test_private_bridge_keeps_both_root_checks_in_order(self):
        import types
        tree, helper = self._checked_functions()
        node = next(item for item in tree.body if isinstance(item, ast.FunctionDef)
                    and item.name == '_private_operation_wrapper')
        reference, count = self._reverse(node)
        self.assertEqual(count, 1)
        namespace = dict(vars(cleanup))
        exec(compile(ast.fix_missing_locations(ast.Module(body=[reference], type_ignores=[])),
                     '<original-private-bridge>', 'exec'), namespace)
        module = types.ModuleType('private_bridge_fixture')
        exec('def verify(root): pass\ndef _verify_owned(root): pass\n', vars(module))
        class LoggedRoot:
            def __init__(self, label, events, value):
                self.label, self.events, self.value = label, events, value
            def __fspath__(self):
                self.events.append(self.label)
                if isinstance(self.value, Exception): raise self.value
                return self.value
        namespace['_owner_module'] = lambda kind: module
        for first, second, first_kind, second_kind, expected, order in (
            ('/alpha', '/alpha', 'logged', 'logged', True, ['first', 'second']),
            ('/wrong', '/alpha', 'logged', 'logged', False, ['first']),
            ('/alpha', '/wrong', 'logged', 'logged', False, ['first', 'second']),
            ('/alpha', '/alpha', 'path', 'path', True, []),
            ('/wrong', '/alpha', 'path', 'path', False, []),
            ('/alpha', '/wrong', 'path', 'path', False, []),
            ('/alpha', '/alpha', 'path', 'logged', True, ['second']),
            ('/wrong', '/alpha', 'path', 'logged', False, []),
            ('/alpha', OSError('second root failed'), 'path', 'logged', False, ['second']),
        ):
            results = []
            for call in (namespace['_private_operation_wrapper'], cleanup._private_operation_wrapper):
                events = []
                operation = types.SimpleNamespace(_kind='winner', _root='/alpha')
                caller = types.SimpleNamespace(f_globals=vars(module), f_code=module._verify_owned.__code__,
                    f_locals={'_operation': operation, 'root': Path(second) if second_kind == 'path' else LoggedRoot('second', events, second)})
                frame = types.SimpleNamespace(f_globals=vars(module), f_code=module.verify.__code__, f_back=caller,
                    f_locals={'_operation': operation, 'root': Path(first) if first_kind == 'path' else LoggedRoot('first', events, first)})
                with patch.object(cleanup, '_owner_module', lambda kind: module):
                    outcome = self._root_text_outcome(lambda: call(frame, 'invariant', operation) is caller)
                results.append((outcome, events))
            self.assertEqual(results[0], results[1])
            wanted = ('error', OSError, ('second root failed',), None) if isinstance(second, Exception) else ('return', bool, expected)
            self.assertEqual(results[1], (wanted, order))


class TypedCheckerSuccessorStaticControls(unittest.TestCase):
    @staticmethod
    def checker_path(name):
        root = Path(__file__).resolve().parents[2]
        return root / ('tools/' if name == 'coverage_loop_proofs.py'
                       else 'tools/carla_lane_oracle/') / name

    def test_complete_predecessor_bytes_remain_frozen(self):
        for name, digest in BoundedOwnerDistinctMechanismControls._SOURCE_SHA256.items():
            with self.subTest(checker=name):
                raw = self.checker_path(name).read_bytes()
                before, mapping = _checker_source_predecessor(name, raw)
                self.assertEqual(hashlib.sha256(before).hexdigest(), digest)
                self.assertEqual(set(mapping), set(range(1, len(before.splitlines()) + 1)))
                # The current checker is distinct; the historical fixture never
                # becomes the source executed by these current controls.
                self.assertNotEqual(raw, before)

    def test_unrelated_edits_in_every_complete_checker_are_refused(self):
        for name in BoundedOwnerDistinctMechanismControls._SOURCE_SHA256:
            raw = self.checker_path(name).read_bytes()
            with self.subTest(checker=name), self.assertRaises(AssertionError):
                _checker_source_predecessor(name, raw + b'\ndef unreviewed_unrelated_checker():\n    return True\n')
            start, stop, _, after = next(edit for edit in _TYPED_CHECKER_SOURCE_EDITS[name]
                                        if edit[3])
            lines = raw.decode('utf-8').splitlines(keepends=True)
            lines[start] = lines[start].rstrip('\n') + ' # changed successor span\n'
            with self.subTest(checker=name, fault='new span'), self.assertRaises(AssertionError):
                _checker_source_predecessor(name, ''.join(lines).encode('utf-8'))

    def test_exact_current_physical_observation_addresses(self):
        root = Path(__file__).resolve().parents[2]
        with _operation_reached_bindings(self, root, root, (cleanup,)):
            pass

    def test_distinct_old_site_ids_bind_unique_current_compiled_calls(self):
        import cache_key_contracts as cache
        import grouped_y_finiteness_contracts as grouped
        import raw_cut_inverse_contracts as raw_cut
        import seed_count_contracts as seed
        controls = BoundedOwnerDistinctMechanismControls()
        loops, core = BoundedOwnerCurrentControls.coverage(self)
        from carla_lane_oracle import seed_count_contracts as package_seed
        cases = (
            (loops._reviewed_dependency_hashes, 959, 'path.read_bytes()'),
            (accepted._verify_current_for_pin_pair, 162, '(root / path).read_text()'),
            (grouped.verify, 31, '(root / p).read_text()'),
            (raw_cut.verify_premises, 66, "(root / 'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_text()"),
            (source.read_pins, 202, "(root / PINS).read_text(encoding='utf-8')"),
            (source.verify_group, 234, "(root / path).read_text(encoding='utf-8')"),
            (cache.inventory, 106, '_inputs.observe_bytes(_input_owner, root, rel.as_posix())'),
            (seed.verify_score, 649, '_inputs.observe_bytes(_input_owner, root, MODULE)'),
            (seed.verify_score, 684, '_inputs.observe_bytes(_input_owner, root, MODULE)'),
            (cache.inventory, 150, '_inputs.observe_bytes(_input_owner, root, rel.as_posix())'),
            (seed.verify_score_caller_inventory, 'station-census', '_inputs.observe_bytes(_input_owner, root, MODULE)'),
            (cleanup._CacheInputs.observe_bytes, 1205, '_regular(root, path).read_bytes()'),
            (cache.inventory, 103, 'path.read_text()'),
            (cache.inventory, 113, "require(source.token_sha256(text) == source.token_sha256(_inputs.text_default(_input_owner, root, rel.as_posix())) == seed_count.score_family_token_sha256(hashlib.sha256(physical).hexdigest()), 'unreviewed supplied score-helper source')"),
            (package_seed.verify_score_caller_inventory, 542, 'guard.production_mojo_paths(root)'),
            (loops._construction_boundary_callers, 1220, 'cache_key.input_paths(Path(root))'),
            (core._operation_production_paths, 1541, '_operation_fail(_operation, error)'),
            (loops.construction_boundary_loops, 1349, 'cleanup._operation_fail(_operation, error)'),
        )
        for function, line, expression in cases:
            with self.subTest(function=function.__qualname__, line=line):
                self.assertTrue(callable(controls._site(function, line, expression)))

    def test_typed_public_adapter_projection_rejects_new_authority_drift(self):
        for module, name in ((selector, 'verify_premises'), (selector, '_verify_premises'),
                             (accepted, 'predecessor_pin_pair'), (accepted, '_predecessor_pin_pair')):
            original = function_ast(module, name)
            for fault in ('path', 'operation', 'missing', 'inner read'):
                node = copy.deepcopy(original)
                calls = [item for item in ast.walk(node) if isinstance(item, ast.Call)
                         and isinstance(item.func, ast.Attribute) and isinstance(item.func.value, ast.Name)
                         and item.func.value.id == '_typed_source']
                call = calls[0]
                if fault == 'path': call.args[1] = ast.Constant('foreign.mojo')
                elif fault == 'operation': call.keywords.append(ast.keyword(arg='_operation', value=ast.Constant(None)))
                elif fault == 'missing': call.func.value.id = 'unreviewed_source'
                else: call.args[2] = ast.Constant('historical substitute')
                with self.subTest(function=name, fault=fault), self.assertRaises(AssertionError):
                    typed_adapter_predecessor(node)

    def test_typed_captured_reread_projection_cannot_precede_physical_compare(self):
        for name in ('verify_premises', '_verify_premises'):
            node = function_ast(selector, name)
            for parent in ast.walk(node):
                body = getattr(parent, 'body', ())
                if not isinstance(body, list):
                    continue
                for index, item in enumerate(body):
                    if (isinstance(item, ast.Assign) and isinstance(item.value, ast.Call)
                            and ast.unparse(item.value).startswith('_typed_source.historical_text(root, name, text')):
                        body[index - 1], body[index] = body[index], body[index - 1]
                        break
                else:
                    continue
                break
            else:
                self.fail('missing captured-reread projection control')
            with self.subTest(function=name), self.assertRaises(AssertionError):
                typed_adapter_predecessor(node)

    def test_seed_supplied_read_shape_preserves_observation_before_projection(self):
        import seed_count_contracts as seed
        original = function_ast(seed, 'reviewed_text')
        first, final = _seed_supplied_read_contract(original)
        self.assertEqual([ast.unparse(item.value) for item in (first[0], final[0])],
                         ['(Path(root) / MODULE).read_bytes()'] * 2)
        for fault in ('first observation', 'supplied compare', 'early projection', 'final observation', 'raw equality'):
            node = copy.deepcopy(original)
            before, after = _seed_supplied_read_contract(node)
            if fault == 'first observation': before[1].body[0].value.args[2] = ast.Name(id='historical', ctx=ast.Load())
            elif fault == 'supplied compare': before[2].value.args[0] = ast.Constant(True)
            elif fault == 'early projection':
                left, right = node.body.index(before[2]), node.body.index(before[3])
                node.body[left], node.body[right] = node.body[right], node.body[left]
            elif fault == 'final observation': after[1].body[0].value.args[2] = ast.Name(id='current_raw', ctx=ast.Load())
            else: after[2].value.args[0] = ast.parse('physical == physical', mode='eval').body
            with self.subTest(fault=fault), self.assertRaises(AssertionError):
                _seed_supplied_read_contract(node)

    def test_station_census_adds_only_authority_map_observation_before_projection(self):
        import seed_count_contracts as seed
        original = function_ast(seed, 'verify_score_caller_inventory')
        _station_census_read_contract(original)
        for fault in ('endpoint guard', 'unobserved lease', 'unchecked supplied text'):
            node = copy.deepcopy(original)
            clause = _station_census_read_contract(node)
            if fault == 'endpoint guard': clause.test = ast.parse('rel.as_posix() == MODULE', mode='eval').body
            elif fault == 'unobserved lease':
                call = next(item for item in ast.walk(clause) if isinstance(item, ast.Call)
                            and ast.unparse(item) == '_inputs.observe_bytes(_input_owner, root, MODULE)')
                call.func.attr = 'raw'
            else: clause.body[1].value.args[0] = ast.Constant(True)
            with self.subTest(fault=fault), self.assertRaises(AssertionError):
                _station_census_read_contract(node)

    def test_each_seed_dispatch_reconciles_outer_current_bytes_after_delegate(self):
        """Isolated control-flow checks; no synthetic root is admitted as real."""
        import types
        import seed_count_contracts as seed
        raw = Path(seed.__file__).read_bytes()
        _checker_source_predecessor('seed_count_contracts.py', raw)
        definition = function_ast(seed, 'verify')
        compiled = compile(ast.Module(body=[definition], type_ignores=[]),
                           '<isolated-current-seed-dispatch-control>', 'exec')
        for route, digest in (('verify_score', seed.SCORE_AFTER_SHA256),
                              ('verify_frontier', seed.FRONTIER_AFTER_SHA256),
                              ('verify_support', seed.SUPPORT_AFTER_SHA256),
                              ('verify_optional', seed.OPTIONAL_AFTER_SHA256)):
            for changed in (False, True):
                with self.subTest(route=route, changed=changed), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    target = root/seed.MODULE
                    target.parent.mkdir(parents=True)
                    target.write_bytes(b'current physical A')
                    events, projections, reads = [], [], []
                    edge = {'isolated_delegate': route}
                    def projected(actual_root, path, value, **kwargs):
                        self.assertEqual((actual_root, path, value), (root, seed.MODULE, b'current physical A'))
                        projections.append(value)
                        # Constant provenance deliberately cannot distinguish A/B.
                        return b'identical historical projection'
                    def delegate(actual_root, **kwargs):
                        self.assertEqual(actual_root, root)
                        self.assertEqual(kwargs, {'_expected_raw': b'current physical A'})
                        events.append(route)
                        if changed: target.write_bytes(b'current physical B')
                        return edge
                    def unexpected(*args, **kwargs):
                        self.fail('wrong delegated or historical verification branch')
                    namespace = dict(vars(seed))
                    namespace.update(read_record=lambda *args, **kwargs: {},
                        sha=lambda value: digest,
                        _typed_source=types.SimpleNamespace(historical_bytes=projected))
                    for name in ('verify_score', 'verify_frontier', 'verify_support', 'verify_optional',
                                 'verify_source', '_verify_bound_inputs', 'verify_premises'):
                        namespace[name] = delegate if name == route else unexpected
                    exec(compiled, namespace)
                    original_read = Path.read_bytes
                    def read(path):
                        value = original_read(path)
                        if path == target: reads.append(value)
                        return value
                    with patch.object(Path, 'read_bytes', read):
                        if changed:
                            with self.assertRaisesRegex(ValueError, 'Map changed during verification'):
                                namespace['verify'](root)
                        else:
                            self.assertIs(namespace['verify'](root), edge)
                    self.assertEqual(events, [route])
                    self.assertEqual(projections, [b'current physical A'])
                    self.assertEqual(reads, [b'current physical A',
                        b'current physical B' if changed else b'current physical A'])

    def test_coverage_row_discriminators_retain_actual_dependency_join(self):
        loops, _ = BoundedOwnerCurrentControls.coverage(self)
        for name in ('_historical_reviewed_nonempty_loops', 'guarded_loop_proof'):
            original = function_ast(loops, name)
            _coverage_current_discriminator_contract(original)
            for fault in ('wrong digest', 'unchecked current'):
                node = copy.deepcopy(original)
                statements = _coverage_current_discriminator_contract(node)
                check = statements[1]
                if fault == 'wrong digest': check.test.comparators[0] = ast.Constant('historical pin')
                else: check.test = ast.Constant(False)
                with self.subTest(function=name, fault=fault), self.assertRaises(AssertionError):
                    _coverage_current_discriminator_contract(node)

    def test_semantic_sink_guards_arm_only_at_marked_publication(self):
        controls = BoundedOwnerDistinctMechanismControls()
        sinks = ((source, 'token_sha256'), (source, 'tokens'), (json, 'loads'))
        originals = [getattr(module, name) for module, name in sinks]
        expected = [function('{}') for function in originals]
        marked = []
        with controls._no_marked_semantics(marked) as arm:
            self.assertTrue(all(getattr(module, name) is original
                                for (module, name), original in zip(sinks, originals)))
            arm()
            marker = 'marked semantic input'
            marked.append(marker)
            for (module, name), value in zip(sinks, expected):
                with self.subTest(sink=name):
                    function = getattr(module, name)
                    with self.assertRaisesRegex(AssertionError, 'marked observation reached semantic sink'):
                        function(marker)
                    self.assertEqual(function('{}'), value)
            with self.assertRaisesRegex(AssertionError, 'armed more than once'):
                arm()
        self.assertTrue(all(getattr(module, name) is original
                            for (module, name), original in zip(sinks, originals)))
        for fault in ('unarmed publication', 'arming without publication', 'arming after publication'):
            marked = []
            with self.subTest(fault=fault), self.assertRaisesRegex(
                    AssertionError, 'semantic sink arming and marked publication differ'):
                with controls._no_marked_semantics(marked) as arm:
                    if fault == 'arming without publication':
                        arm()
                    else:
                        marked.append('unobserved marked input')
                        if fault == 'arming after publication':
                            with self.assertRaisesRegex(AssertionError, 'armed after marked publication'):
                                arm()
            self.assertTrue(all(getattr(module, name) is original
                                for (module, name), original in zip(sinks, originals)))


    def test_checker_receipt_lifecycle_and_return_registration_are_explicit(self):
        raw = Path(cleanup.__file__).read_bytes()
        _checker_source_predecessor('full_audit_cleanup_contracts.py', raw)
        tree = ast.parse(raw)
        owner = next(node for node in tree.body if isinstance(node, ast.ClassDef)
                     and node.name == '_InvariantInputs')
        for name in ('__init__', '_invalidate', 'close'):
            node = next(item for item in owner.body if isinstance(item, ast.FunctionDef)
                        and item.name == name)
            _one_ast_run(node, 'self._checker_receipt = False')
        binding = next(node for node in tree.body if isinstance(node, ast.FunctionDef)
                       and node.name == 'proof_bindings')
        statements = _one_ast_run(binding, """
if _operation is not None:
    _operation._bind_checker_receipt(root, executing)
return result
""")
        calls = [item for item in ast.walk(binding) if isinstance(item, ast.Call)
                 and isinstance(item.func, ast.Attribute) and item.func.attr == '_bind_checker_receipt']
        self.assertEqual(len(calls), 1)
        self.assertIs(calls[0], statements[0].body[0].value)



if __name__ == '__main__':
    unittest.main()
