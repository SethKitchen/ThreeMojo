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
                    return text + '\n# Token-equivalent supplied view.\n'
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


# Parent-owned real-operation lifecycle, image, and topology controls can be
# added below. Keep the synthetic scope of the classes above explicit.

if __name__ == '__main__':
    unittest.main()
