#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Focused fixed-pair controls; no admission receipt or cached output is reused.

PairedPinFakeControls and SelectorOutputFakeControls are separately selectable
synthetic wiring/schema controls. They do not establish real current admission.
All classes containing Real use full physical fixtures and unchanged real gates.
Fixture/helper modules are bound as modules, never imported TestCase classes.
No gate executes during module import. The maintained optimized inventory child
must succeed before the Real classes are authorized for execution.
"""
import ast
import copy
from contextlib import contextmanager, ExitStack
from concurrent.futures import ThreadPoolExecutor
from functools import wraps
import hashlib
import inspect
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import accepted_successor_contracts as accepted
import coverage_followup_contracts as followup
import coverage_invariant_contracts as invariant
import frozen_arc_producer_contracts as frozen
import reviewed_cleanup_contracts as reviewed
import rounded_line_selector_contracts as selector
import full_audit_cleanup_contracts as cleanup
import distance_validation_contracts as distance
import grouped_y_finiteness_contracts as grouped_y
import source_contracts as source
import sum2_guard_contracts as guard
import _full_audit_test_fixtures as fixtures
import test_full_audit_cleanup_contracts as authority_helpers

ROOT = Path(__file__).resolve().parents[2]


# This module's fixed byte/line/body assertions describe the historical main
# graph. The #333 current graph has separate physical admission/mutation tests.
_CURRENT_SOURCE_ROOT = ROOT


def setUpModule():
    global ROOT
    import _full_audit_test_fixtures as historical_fixtures
    owner = type('HistoricalModuleFixture', (), {
        'addCleanup': staticmethod(unittest.addModuleCleanup)})()
    ROOT = historical_fixtures.copy_historical_boundary_root(owner, _CURRENT_SOURCE_ROOT)
    unittest.addModuleCleanup(globals().__setitem__, 'ROOT', _CURRENT_SOURCE_ROOT)
NAMES = ('runtime-source-pins.json', 'sum2-guard-pins.json')
PIN_DIR = 'tools/carla_lane_oracle'
LANE = 'extensions/carla/lane_refinement.mojo'
ROAD = 'extensions/carla/road.mojo'
SELECTOR_V13_AST_SHA256 = '88df2a81f6dbc2934c365c7f9dbbdabeed189856de7fdccdfad4661ae2025ac5'
EXPECTED = {
    'accepted': (('90352ea83ea07dd289184995e7c00147067d2344c583090a62600ac622a8026d', 7),
                 ('4db78e328de5b3fcf75a3d33ed7f9cc26958f57c7b95dd12c7f00a8b1e752f45', 4)),
    'followup': (('7730c8ac731739073da071cf19dfd1f68ecc621e6068a8ce521d57c969831f53', 18),
                 ('d90351496c5675c353f931220a0da464cb04ac84be59730e67b916d698f7293f', 10)),
    'invariant': (('b5a075120f09b38bc707d56a04d5f7149abbfede56bad0ece45c3156eea96525', 7),
                  ('a2e02bf09d4b1660ea44c290971bd248176f282dbd352b7961ca35658d54c883', 7)),
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2) + '\n').encode()


def assert_pair(case, pair):
    case.assertIs(type(pair), tuple)
    case.assertEqual(len(pair), 2)
    for raw in pair:
        case.assertIs(type(raw), bytes)


@contextmanager
def alias(root, name, kind):
    target = root if kind == 'root' else root/name
    if kind == 'ancestor':
        target = target.parent
    with tempfile.TemporaryDirectory(prefix='paired-pin-alias-') as directory:
        stored = Path(directory)/'physical'
        target.rename(stored)
        try:
            target.symlink_to(stored, target_is_directory=stored.is_dir())
            yield
        finally:
            if target.is_symlink():
                target.unlink()
            stored.rename(target)


@contextmanager
def nonregular(root, name):
    target = root/name
    raw = target.read_bytes()
    target.unlink()
    target.mkdir()
    try:
        yield
    finally:
        target.rmdir()
        target.write_bytes(raw)



class _WithoutTypedProjection(ast.NodeTransformer):
    """Undo #333's historical projection of reads before an original-AST pin.

    `_typed_source.historical_text/bytes(root, path, value, ...)` returns
    `value` unless the path is a current typed endpoint; the original premise
    read `value` directly. Removing the wrapper (and the self-assignment it
    leaves) recovers the reviewed pre-#333 statement shape exactly.
    """

    def visit_Call(self, node):
        if (isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name)
                and node.func.value.id == '_typed_source'
                and node.func.attr in ('historical_text', 'historical_bytes')):
            return self.visit(node.args[2])
        return self.generic_visit(node)

    def visit_Assign(self, node):
        node = self.generic_visit(node)
        if (len(node.targets) == 1 and isinstance(node.targets[0], ast.Name)
                and isinstance(node.value, ast.Name) and node.value.id == node.targets[0].id):
            return None
        return node

class PairedPinFakeControls(unittest.TestCase):
    """Synthetic qualification and owner wiring only, never real gate evidence."""

    def setUp(self):
        directory = tempfile.TemporaryDirectory(
            prefix='paired-pin-fake-', dir=Path(tempfile.gettempdir()).resolve())
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        (self.root/PIN_DIR).mkdir(parents=True)
        initial = {'accepted': 'new', 'followup': 'new', 'invariant': 'new',
                   'groups': {name: {frozen.SOURCE_PATH: 'new'} for name in
                              ('eligibility', 'optional_runtime', 'translation')}}
        self.active = tuple(encoded(dict(initial, pin=name)) for name in NAMES)
        for name, raw in zip(NAMES, self.active):
            (self.root/PIN_DIR/name).write_bytes(raw)
        self.records, self.outputs = {}, {}
        payloads = self.active
        for label in ('accepted', 'followup', 'invariant'):
            items, previous = {}, []
            for name, raw in zip(NAMES, payloads):
                value = json.loads(raw)
                value[label] = 'old'
                before = encoded(value)
                items[name] = {'after_sha256': sha(raw), 'before_sha256': sha(before),
                               'transitions': [{'pointer': [label], 'after': 'new', 'before': 'old'}]}
                previous.append(before)
            self.records[label] = {'pin_files': items, 'sources': {}}
            self.outputs[label] = tuple(previous)
            payloads = tuple(previous)
        runtime = json.loads(payloads[0])
        transitions = []
        for group in ('eligibility', 'optional_runtime', 'translation'):
            runtime['groups'][group][frozen.SOURCE_PATH] = 'old'
            transitions.append({'group': group, 'path': frozen.SOURCE_PATH,
                                'after': 'new', 'before': 'old'})
        previous = encoded(runtime)
        self.records['frozen'] = {'runtime_pins_after_sha256': sha(payloads[0]),
            'runtime_pins_before_sha256': sha(previous), 'runtime_token_successors': transitions,
            'guard_pins_unchanged_sha256': sha(payloads[1])}
        self.outputs['frozen'] = (previous, payloads[1])

    @contextmanager
    def synthetic(self, current=False):
        with patch.object(accepted, '_verify_current_for_pin_pair',
                          return_value=(self.records['accepted'], current)) as qualify, \
                patch.object(followup, 'read_record', return_value=self.records['followup']), \
                patch.object(invariant, 'read_record', return_value=self.records['invariant']), \
                patch.object(frozen, 'read_record', return_value=self.records['frozen']), \
                patch.object(cleanup, 'executing_checker_bindings', return_value={'fake': 'identity'}):
            yield qualify

    def test_fixed_shape_order_signatures_and_single_freshness(self):
        for module, label in ((accepted, 'accepted'), (followup, 'followup'), (invariant, 'invariant')):
            with self.subTest(module=module.__name__):
                signature = inspect.signature(module.predecessor_pin_pair)
                self.assertEqual(tuple(signature.parameters), ('root',))
                with self.synthetic() as qualify:
                    pair = module.predecessor_pin_pair(self.root)
                    assert_pair(self, pair)
                    self.assertEqual(pair, self.outputs[label])
                    qualify.assert_called_once_with(self.root)
                with patch.object(accepted, 'verify_current', return_value=self.records['accepted']) as single:
                    self.assertEqual(accepted.predecessor_pins(self.root, NAMES[0]), self.outputs['accepted'][0])
                    self.assertEqual(accepted.predecessor_pins(self.root, NAMES[1]), self.outputs['accepted'][1])
                    self.assertEqual(single.call_args_list, [unittest.mock.call(self.root)] * 2)
        signature = inspect.signature(frozen._verified_pin_pair)
        self.assertEqual(tuple(signature.parameters), ('root', 'prior_digest', '_operation'))
        self.assertIs(signature.parameters['_operation'].kind, inspect.Parameter.KEYWORD_ONLY)
        self.assertIsNone(signature.parameters['_operation'].default)
        with self.synthetic() as qualify:
            pair = frozen._verified_pin_pair(self.root, self.records['frozen']['runtime_pins_before_sha256'])
            self.assertEqual(pair, self.outputs['frozen'])
            assert_pair(self, pair)
            qualify.assert_called_once_with(self.root)

    def test_current_pair_reads_exact_order_and_checker_baseline(self):
        reads, checks = [], []
        read, regular = Path.read_bytes, cleanup._regular
        def observed(path, *args, **kwargs):
            if path.parent == self.root/PIN_DIR:
                reads.append(path.name)
            return read(path, *args, **kwargs)
        def bindings():
            checks.append(tuple(reads))
            return {'fake': 'identity'}
        with self.synthetic(True), patch.object(Path, 'read_bytes', observed), \
                patch.object(cleanup, '_regular', wraps=regular) as paths, \
                patch.object(cleanup, 'executing_checker_bindings', bindings):
            self.assertEqual(accepted.predecessor_pin_pair(self.root), self.outputs['accepted'])
        self.assertEqual(reads, [NAMES[0], NAMES[1], NAMES[0], NAMES[1]])
        self.assertEqual(checks, [(NAMES[0],), tuple(reads)])
        self.assertEqual([call.args for call in paths.call_args_list],
                         [(self.root, PIN_DIR + '/' + name) for name in reads])

    def test_historical_pair_adds_no_regular_or_checker_restriction(self):
        with self.synthetic(False), patch.object(cleanup, '_regular', side_effect=AssertionError('new historical path check')), \
                patch.object(cleanup, 'executing_checker_bindings', side_effect=AssertionError('new historical checker check')):
            with alias(self.root, PIN_DIR + '/' + NAMES[1], 'leaf'):
                self.assertEqual(accepted.predecessor_pin_pair(self.root), self.outputs['accepted'])

    def test_outer_records_twice_before_nested_pair_and_no_late_reads(self):
        for module, inner, label in ((followup, accepted, 'followup'), (invariant, followup, 'invariant')):
            events = []
            records = [copy.deepcopy(self.records[label]), copy.deepcopy(self.records[label])]
            saved = copy.deepcopy(records)
            def record(root):
                events.append('record')
                return records[len(events) - 1]
            def pair(root):
                events.append('pair')
                return self.outputs['accepted' if label == 'followup' else 'followup']
            with self.subTest(layer=label), patch.object(module, 'read_record', record), \
                    patch.object(inner, 'predecessor_pin_pair', pair), \
                    patch.object(Path, 'read_bytes', side_effect=AssertionError('late outer bytes read')), \
                    patch.object(Path, 'read_text', side_effect=AssertionError('late outer text read')):
                self.assertEqual(module.predecessor_pin_pair(self.root), self.outputs[label])
            self.assertEqual(events, ['record', 'record', 'pair'])
            self.assertEqual(records, saved)

    def test_wrong_fixed_order_extra_missing_and_unknown_single(self):
        for module, label in ((accepted, 'accepted'), (followup, 'followup'), (invariant, 'invariant')):
            for names in (NAMES[::-1], NAMES[:1], NAMES + ('extra.json',)):
                changed = copy.deepcopy(self.records[label])
                changed['pin_files'] = {name: changed['pin_files'].get(name, {}) for name in names}
                with self.subTest(layer=label, names=names), self.synthetic(), \
                        patch.object(accepted, '_verify_current_for_pin_pair', return_value=(
                            changed if module is accepted else self.records['accepted'], False)), \
                        patch.object(module, 'read_record', return_value=changed):
                    with self.assertRaisesRegex(ValueError, 'wrong fixed ordered pin pair'):
                        module.predecessor_pin_pair(self.root)
        with patch.object(accepted, 'verify_current', return_value=self.records['accepted']) as qualify:
            self.assertEqual(accepted.predecessor_pins(self.root, 'any/path/' + NAMES[0]), self.outputs['accepted'][0])
            with self.assertRaises(KeyError) as caught:
                accepted.predecessor_pins(self.root, 'any/path/unknown.json')
            self.assertEqual(caught.exception.args, ('unknown.json',))
            self.assertEqual(qualify.call_count, 2)

    def test_every_inverse_refuses_bad_hash_json_pointer_placement_and_before_hash(self):
        for module, label, incoming in ((accepted, 'accepted', self.active),
                (followup, 'followup', self.outputs['accepted']),
                (invariant, 'invariant', self.outputs['followup'])):
            for name, raw in zip(NAMES, incoming):
                original = self.records[label]['pin_files'][name]
                for defect in ('after_hash', 'json', 'duplicate_key', 'duplicate_pointer', 'placement', 'traversal', 'before_hash'):
                    item, payload = copy.deepcopy(original), raw
                    if defect == 'after_hash':
                        payload += b' '
                    elif defect == 'json':
                        payload = b'{invalid'
                        item['after_sha256'] = sha(payload)
                    elif defect == 'duplicate_key':
                        payload = b'{"duplicate": 1, "duplicate": 2}'
                        item['after_sha256'] = sha(payload)
                    elif defect == 'duplicate_pointer':
                        item['transitions'].append(copy.deepcopy(item['transitions'][0]))
                    elif defect == 'placement':
                        item['transitions'][0]['after'] = 'absent'
                    elif defect == 'traversal':
                        item['transitions'][0]['pointer'] = ['missing', 'entry']
                    else:
                        item['before_sha256'] = '0' * 64
                    with self.subTest(layer=label, name=name, defect=defect), \
                            patch.object(module.json, 'loads', wraps=json.loads) as parser:
                        with self.assertRaises((ValueError, KeyError, TypeError)):
                            module._pin_predecessor(payload, item, name)
                        if defect == 'after_hash':
                            parser.assert_not_called()

    def test_current_nonbuiltin_bytes_and_final_primary_failure(self):
        class HostileBytes(bytes):
            def __eq__(self, other):
                raise AssertionError('nonbuiltin equality must not run')
        read = Path.read_bytes
        for name in NAMES:
            for occurrence in (1, 2):
                for convert in (bytearray, HostileBytes):
                    visits = []
                    def observed(path, *args, **kwargs):
                        raw = read(path, *args, **kwargs)
                        if path == self.root/PIN_DIR/name:
                            visits.append(name)
                            if len(visits) == occurrence:
                                return convert(raw)
                        return raw
                    with self.subTest(name=name, occurrence=occurrence, kind=convert.__name__), \
                            self.synthetic(True), patch.object(Path, 'read_bytes', observed):
                        with self.assertRaisesRegex(ValueError, 'current paired pin is not builtin bytes: ' + name):
                            accepted.predecessor_pin_pair(self.root)
                    self.assertEqual(len(visits), occurrence)
        failure = ValueError('primary runtime inverse')
        with self.synthetic(True), patch.object(accepted, '_pin_predecessor', side_effect=failure), \
                patch.object(cleanup, 'executing_checker_bindings', side_effect=AssertionError('must not finalize')):
            with self.assertRaises(ValueError) as caught:
                accepted.predecessor_pin_pair(self.root)
        self.assertIs(caught.exception, failure)

    def test_checker_baseline_mismatch_is_contract_error_and_historical_skips(self):
        with self.synthetic(True), patch.object(cleanup, 'executing_checker_bindings',
                side_effect=({'fake': 'before'}, {'fake': 'after'})) as bindings:
            with self.assertRaisesRegex(cleanup.ContractError, 'executing checker changed during paired pin projection'):
                accepted.predecessor_pin_pair(self.root)
        self.assertEqual(bindings.call_args_list, [unittest.mock.call(), unittest.mock.call()])

    def test_frozen_single_stays_none_and_never_requests_guard(self):
        with patch.object(frozen, 'read_record', return_value=self.records['frozen']), \
                patch.object(invariant, 'predecessor_pins', return_value=self.outputs['invariant'][0]) as single, \
                patch.object(invariant, 'predecessor_pin_pair', side_effect=AssertionError('single requested pair')):
            self.assertIsNone(frozen.verify_runtime_pin_successor(
                self.root, self.records['frozen']['runtime_pins_before_sha256']))
        single.assert_called_once_with(self.root, source.PINS)

    def test_public_accepted_verify_still_uses_ordinary_singles(self):
        with patch.object(accepted, 'verify_current', return_value=self.records['accepted']) as current, \
                patch.object(accepted, 'predecessor_pins', return_value=b'') as single, \
                patch.object(accepted, 'predecessor_pin_pair', side_effect=AssertionError('accepted.verify converted')):
            self.assertIs(accepted.verify(self.root), self.records['accepted'])
        current.assert_called_once_with(self.root)
        self.assertEqual(single.call_args_list, [unittest.mock.call(self.root, name) for name in NAMES])

    def test_each_owner_initial_phase_uses_one_fresh_pair(self):
        class StopAfterPins(Exception):
            pass
        path = 'fake/after-pin-source.mojo'
        records = {
            followup: dict(self.records['followup'], sources={path: {'after_token_sha256': 'unused'}}),
            invariant: dict(self.records['invariant'], sources={path: {'after_token_sha256': 'unused'}}),
            frozen: dict(self.records['frozen'], source_successor={'after_token_sha256': 'unused'}),
            reviewed: {'runtime_pins_after_sha256': self.records['frozen']['runtime_pins_before_sha256'],
                       'guard_pins_after_sha256': sha(self.outputs['frozen'][1]),
                       'sources': {path: {'after_token_sha256': 'unused'}}},
        }
        for owner, provider, method, output in (
                (followup, followup, 'predecessor_pin_pair', self.outputs['followup']),
                (invariant, invariant, '_predecessor_pin_pair', self.outputs['invariant']),
                (frozen, frozen, '_verified_pin_pair', self.outputs['frozen']),
                (reviewed, frozen, '_verified_pin_pair', self.outputs['frozen'])):
            events = []
            def record(root):
                events.append(('record', root))
                return records[owner]
            def paired(*args, **kwargs):
                events.append(('pair', args[0]))
                if owner is invariant:
                    self.assertEqual(set(kwargs), {'_operation'})
                    operation = kwargs['_operation']
                    self.assertIs(type(operation), cleanup._InvariantInputs)
                    self.assertEqual(operation._kind, 'invariant')
                    self.assertEqual(operation._state, 'pending')
                else:
                    self.assertEqual(kwargs, {})
                return output
            def stop_after_pins(source_path, *args, **kwargs):
                events.append(('source', source_path))
                raise StopAfterPins
            with self.subTest(owner=owner.__name__), patch.object(owner, 'read_record', record), \
                    patch.object(provider, method, side_effect=paired) as pair, \
                    patch.object(Path, 'read_text', stop_after_pins), \
                    patch.object(accepted, 'predecessor_pins', side_effect=AssertionError('owner used single')), \
                    patch.object(invariant, 'predecessor_pin_pair', side_effect=AssertionError('owner bypassed private invariant pair')), \
                    patch.object(cleanup, 'verify', side_effect=AssertionError('initial phase admitted source')):
                for call_index in range(2):
                    with self.assertRaises(StopAfterPins):
                        owner.verify(self.root)
                    self.assertEqual(pair.call_count, call_index + 1)
                    source_path = frozen.SOURCE_PATH if owner is frozen else path
                    self.assertEqual(events, [('record', self.root), ('pair', self.root),
                                              ('source', self.root/source_path)] * (call_index + 1))
                    if owner is invariant:
                        self.assertEqual(pair.call_args.kwargs['_operation']._state, 'closed')
                self.assertEqual(pair.call_args.args[0], self.root)
                if owner is invariant:
                    self.assertIsNot(pair.call_args_list[0].kwargs['_operation'],
                                     pair.call_args_list[1].kwargs['_operation'])

    def test_changed_multifault_priorities_are_explicit(self):
        # Synthetic isolated defects prove sequence, not real record admission.
        broken_runtime = copy.deepcopy(self.records['invariant'])
        broken_runtime['pin_files'][NAMES[0]]['after_sha256'] = '0' * 64
        for module, inner, label in ((followup, accepted, 'followup'), (invariant, followup, 'invariant')):
            failure = ValueError('second outer guard record')
            with self.subTest(priority=label + '-guard-record-first'), self.synthetic(), \
                    patch.object(module, 'read_record', side_effect=[self.records[label], failure]), \
                    patch.object(inner, 'predecessor_pin_pair', side_effect=AssertionError('qualified before second record')):
                with self.assertRaises(ValueError) as caught:
                    module.predecessor_pin_pair(self.root)
                self.assertIs(caught.exception, failure)
        with self.synthetic(), patch.object(invariant, 'read_record', return_value=broken_runtime), \
                authority_helpers.physical_change(self.root, PIN_DIR + '/' + NAMES[1], b'invalid guard'):
            with self.assertRaisesRegex(ValueError, 'accepted source successor: unreviewed runtime pin successor: ' + NAMES[1]):
                invariant.predecessor_pin_pair(self.root)
        broken_followup = copy.deepcopy(self.records['followup'])
        broken_followup['pin_files'][NAMES[1]]['after_sha256'] = '0' * 64
        with self.synthetic(), patch.object(invariant, 'read_record', return_value=broken_runtime), \
                patch.object(followup, 'read_record', return_value=broken_followup):
            with self.assertRaisesRegex(ValueError, 'coverage followup successor: unreviewed runtime pin successor: ' + NAMES[1]):
                invariant.predecessor_pin_pair(self.root)
        broken_frozen = copy.deepcopy(self.records['frozen'])
        broken_frozen['runtime_pins_after_sha256'] = '0' * 64
        broken_invariant = copy.deepcopy(self.records['invariant'])
        broken_invariant['pin_files'][NAMES[1]]['after_sha256'] = '0' * 64
        with self.synthetic(), patch.object(invariant, 'read_record', return_value=broken_invariant), \
                patch.object(frozen, 'read_record', return_value=broken_frozen):
            with self.assertRaisesRegex(ValueError, 'coverage invariant successor: unreviewed guarded pin successor: ' + NAMES[1]):
                frozen._verified_pin_pair(self.root, broken_frozen['runtime_pins_before_sha256'])


    def test_top_guard_digest_and_outer_runtime_failures_do_not_reorder_primary_error(self):
        broken = copy.deepcopy(self.records['frozen'])
        broken['runtime_pins_after_sha256'] = '0' * 64
        broken['guard_pins_unchanged_sha256'] = '0' * 64
        reviewed_record = {'runtime_pins_after_sha256': broken['runtime_pins_before_sha256'],
                           'guard_pins_after_sha256': '0' * 64}
        for owner in (frozen, reviewed):
            with self.subTest(owner=owner.__name__), self.synthetic(), \
                    patch.object(frozen, 'read_record', return_value=broken), \
                    patch.object(reviewed, 'read_record', return_value=reviewed_record):
                with self.assertRaisesRegex(ValueError, 'frozen ARC producer contract: unreviewed runtime pin successor'):
                    owner.verify(self.root)
        bad_outer = copy.deepcopy(self.records['invariant'])
        bad_outer['pin_files'][NAMES[0]]['after_sha256'] = '0' * 64
        visits, read = [], Path.read_bytes
        def changed(path, *args, **kwargs):
            raw = read(path, *args, **kwargs)
            if path == self.root/PIN_DIR/NAMES[0]:
                visits.append(path)
                if len(visits) == 2:
                    return raw + b' '
            return raw
        with self.synthetic(True), patch.object(invariant, 'read_record', return_value=bad_outer), \
                patch.object(Path, 'read_bytes', changed):
            with self.assertRaisesRegex(ValueError, 'current paired pin changed: ' + NAMES[0]):
                invariant.predecessor_pin_pair(self.root)
        self.assertEqual(len(visits), 2)


class SelectorOutputFakeControls(unittest.TestCase):
    """Output/default/frame controls with synthetic premises, not real admission."""

    def test_original_premise_ast_and_function_frame_preserved(self):
        tree = ast.parse(Path(selector.__file__).read_text())
        function = next(node for node in tree.body if isinstance(node, ast.FunctionDef)
                        and node.name == 'verify_premises')
        self.assertEqual([arg.arg for arg in function.args.kwonlyargs], ['_return_current_admission'])
        self.assertEqual(ast.dump(function.args.kw_defaults[0]), 'Constant(value=False)')
        function.args.kwonlyargs = []
        function.args.kw_defaults = []
        extras = [node for node in function.body if any(
            isinstance(child, ast.Name) and child.id == '_return_current_admission' for child in ast.walk(node))]
        self.assertEqual(len(extras), 2)
        validation, output = extras
        self.assertIsInstance(validation, ast.Expr)
        self.assertEqual(ast.unparse(validation),
                         "require(type(_return_current_admission) is bool, 'invalid current-admission output request')")
        self.assertIsInstance(output, ast.If)
        self.assertEqual(ast.unparse(output),
                         'if _return_current_admission:\n    return (record, lane_predecessor is not None)')
        self.assertIs(function.body[-2], output)
        function.body = [node for node in function.body if node not in extras]
        function = _WithoutTypedProjection().visit(function)
        self.assertEqual(sha(ast.dump(function, include_attributes=False).encode()), SELECTOR_V13_AST_SHA256)
        self.assertEqual(tuple(inspect.signature(selector.verify).parameters), ('root',))
        self.assertEqual(tuple(inspect.signature(accepted.verify_current).parameters), ('root',))

    def test_default_false_true_same_reads_and_public_verify_default_path(self):
        directory = tempfile.TemporaryDirectory(prefix='selector-output-fake-')
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        module = 'selector.mojo'
        reference = 'reference.mojo'
        for name in (module, reference, selector.prior.MIGRATION):
            target = root/name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('fake')
        old = {'modules': {module: {'source': 'fake'}}, 'import_scopes': {}, 'declarations': []}
        record = {'path': module, 'before_source': 'fake', 'after_source': 'fake',
                  'after_token_sha256': source.token_sha256('fake'),
                  'prior_migration_sha256': sha(b'fake'),
                  'reference': {'path': reference, 'name': 'reference', 'source': 'fake'}}
        read_bytes, read_text = Path.read_bytes, Path.read_text
        traces = []
        with patch.object(selector, 'read_record', return_value=record), \
                patch.object(selector.prior, 'read_record', return_value=old), \
                patch.object(guard, 'declaration', return_value='fake'):
            for kwargs in ({}, {'_return_current_admission': False}, {'_return_current_admission': True}):
                events = []
                def observed_bytes(path, *args, **kw):
                    events.append(('bytes', path.relative_to(root).as_posix()))
                    return read_bytes(path, *args, **kw)
                def observed_text(path, *args, **kw):
                    events.append(('text', path.relative_to(root).as_posix()))
                    return read_text(path, *args, **kw)
                with patch.object(Path, 'read_bytes', observed_bytes), patch.object(Path, 'read_text', observed_text):
                    result = selector.verify_premises(root, **kwargs)
                self.assertEqual(result, (record, False) if kwargs.get('_return_current_admission') else record)
                traces.append(events)
            self.assertEqual(traces, [traces[0]] * 3)
            with patch.object(selector, 'verify_premises', wraps=selector.verify_premises) as premises:
                self.assertIs(selector.verify(root), record)
                premises.assert_called_once_with(root)
            with patch.object(selector, 'verify_premises', wraps=selector.verify_premises) as premises:
                self.assertEqual(selector._verify_for_pin_pair(root), (record, False))
                premises.assert_called_once_with(root, _return_current_admission=True)

    def test_output_request_rejects_nonbuiltin_bool_before_reads(self):
        for value in (None, 0, 1, '', 'True', [], {}, object()):
            with self.subTest(type=type(value).__name__), \
                    patch.object(selector, 'read_record', side_effect=AssertionError('invalid request read record')):
                with self.assertRaisesRegex(ValueError, 'rounded LINE selector contract: invalid current-admission output request'):
                    selector.verify_premises(Path('unused'), _return_current_admission=value)


class PairedPinRealControls(unittest.TestCase):
    """Real physical qualification; all injected faults keep the real gates."""

    def setUp(self):
        self.root = fixtures.copy_historical_boundary_root(self, ROOT)

    def test_current_and_historical_exact_outputs_equal_independent_singles(self):
        historical = fixtures.historical_root(self, ROOT)
        for root in (self.root, historical):
            for module, label in ((accepted, 'accepted'), (followup, 'followup'), (invariant, 'invariant')):
                with self.subTest(root=root, layer=label):
                    pair = module.predecessor_pin_pair(root)
                    assert_pair(self, pair)
                    self.assertEqual(pair, tuple(module.predecessor_pins(root, name) for name in NAMES))
                    record = module.read_record(root)
                    self.assertEqual(tuple(record['pin_files']), NAMES)
                    for name, raw, (digest, count) in zip(NAMES, pair, EXPECTED[label]):
                        self.assertEqual(sha(raw), digest)
                        self.assertEqual(record['pin_files'][name]['before_sha256'], digest)
                        self.assertEqual(len(record['pin_files'][name]['transitions']), count)
            record = frozen.read_record(root)
            pair = frozen._verified_pin_pair(root, record['runtime_pins_before_sha256'])
            assert_pair(self, pair)
            self.assertEqual(sha(pair[0]), record['runtime_pins_before_sha256'])
            self.assertEqual(pair[1], invariant.predecessor_pins(root, NAMES[1]))
            self.assertIsNone(frozen.verify_runtime_pin_successor(root, record['runtime_pins_before_sha256']))
            self.assertEqual(len(record['runtime_token_successors']), 3)

    def test_one_real_gate_per_pair_and_two_public_singles(self):
        original, gates = cleanup.verify, []
        @wraps(original)
        def gated(*args, **kwargs):
            gates.append((args, kwargs))
            return original(*args, **kwargs)
        with patch.object(cleanup, 'verify', gated):
            first = accepted.predecessor_pin_pair(self.root)
            self.assertEqual(len(gates), 1)
            second = accepted.predecessor_pin_pair(self.root)
            self.assertEqual(len(gates), 2)
            singles = tuple(accepted.predecessor_pins(self.root, name) for name in NAMES)
            self.assertEqual(len(gates), 4)
        self.assertEqual(first, second)
        self.assertEqual(second, singles)

    def test_each_outer_record_prior_component_read_twice_before_qualification(self):
        for module, prior_name in ((followup, invariant.MIGRATION), (invariant, frozen.MIGRATION)):
            record = module.read_record(self.root)
            expected = [module.MIGRATION, prior_name,
                        *(PIN_DIR + '/' + name for name in record['components'])]
            events = []
            read, qualify = Path.read_bytes, accepted._verify_current_for_pin_pair
            def observed(path, *args, **kwargs):
                caller = sys._getframe(1)
                if caller.f_code is module.read_record.__code__:
                    events.append(path.relative_to(self.root).as_posix())
                return read(path, *args, **kwargs)
            @wraps(qualify)
            def qualified(root):
                events.append('qualification')
                return qualify(root)
            with self.subTest(layer=module.__name__), patch.object(Path, 'read_bytes', observed), \
                    patch.object(accepted, '_verify_current_for_pin_pair', qualified):
                module.predecessor_pin_pair(self.root)
            self.assertEqual(events, expected + expected + ['qualification'])

    def test_each_outer_record_first_and_second_consumed_b_fails_its_seal(self):
        read, parse = Path.read_bytes, json.loads
        for module, prior_name in ((followup, invariant.MIGRATION), (invariant, frozen.MIGRATION)):
            record = module.read_record(self.root)
            names = (module.MIGRATION, prior_name, *(PIN_DIR + '/' + name for name in record['components']))
            for name in names:
                for occurrence in (1, 2):
                    visits, interpreted = [], []
                    bad = read(self.root/name) + b' '
                    def observed(path, *args, **kwargs):
                        raw = read(path, *args, **kwargs)
                        if path == self.root/name and sys._getframe(1).f_code is module.read_record.__code__:
                            visits.append(name)
                            if len(visits) == occurrence:
                                return bad
                        return raw
                    def parsed(value, *args, **kwargs):
                        if value == bad:
                            interpreted.append(value)
                        return parse(value, *args, **kwargs)
                    with self.subTest(layer=module.__name__, name=name, occurrence=occurrence), \
                            patch.object(Path, 'read_bytes', observed), patch.object(json, 'loads', parsed), \
                            patch.object(accepted, '_verify_current_for_pin_pair', wraps=accepted._verify_current_for_pin_pair) as qualify:
                        with self.assertRaisesRegex(ValueError, 'migration record|record changed'):
                            module.predecessor_pin_pair(self.root)
                        qualify.assert_not_called()
                    self.assertEqual(len(visits), occurrence)
                    self.assertEqual(interpreted, [])

    def test_consumed_pin_b_rejects_before_json_on_both_admission_branches(self):
        historical = fixtures.historical_root(self, ROOT)
        read, parse = Path.read_bytes, json.loads
        for root in (self.root, historical):
            for name in NAMES:
                for bad in (read(root/PIN_DIR/name) + b' ', b'{bad JSON', b'{"same": 0, "same": 1}'):
                    consumed, interpreted = [], []
                    def observed(path, *args, **kwargs):
                        raw = read(path, *args, **kwargs)
                        caller = sys._getframe(1).f_code
                        if path == root/PIN_DIR/name and caller in (
                                accepted._read_current_pair_pin.__code__, accepted.predecessor_pin_pair.__code__):
                            consumed.append('B' if not consumed else 'A')
                            if len(consumed) == 1:
                                return bad
                        return raw
                    def parsed(raw, *args, **kwargs):
                        if raw == bad:
                            interpreted.append('B')
                        return parse(raw, *args, **kwargs)
                    with self.subTest(root=root, name=name, bad=bad[:20]), \
                            patch.object(Path, 'read_bytes', observed), patch.object(json, 'loads', parsed):
                        with self.assertRaisesRegex(ValueError, 'accepted source successor: unreviewed runtime pin successor: ' + name):
                            accepted.predecessor_pin_pair(root)
                    self.assertEqual(consumed, ['B'])
                    self.assertEqual(interpreted, [])
                    self.assertNotEqual(read(root/PIN_DIR/name), bad)

    def test_current_aliases_missing_nonregular_consumption_and_final_reads(self):
        regular = cleanup._regular
        for name in NAMES:
            relative = PIN_DIR + '/' + name
            raw = (self.root/relative).read_bytes()
            for occurrence in (1, 2):
                for kind in ('leaf', 'ancestor', 'root', 'missing', 'nonregular', 'bytes'):
                    visits = []
                    with ExitStack() as stack:
                        @wraps(regular)
                        def observed(root, path):
                            if root == self.root and path == relative and sys._getframe(1).f_code is accepted._read_current_pair_pin.__code__:
                                visits.append(path)
                                if len(visits) == occurrence:
                                    if kind == 'missing':
                                        stack.enter_context(authority_helpers.physical_change(root, path, None))
                                    elif kind == 'bytes':
                                        stack.enter_context(authority_helpers.physical_change(root, path, raw + b' '))
                                    elif kind == 'nonregular':
                                        stack.enter_context(nonregular(root, path))
                                    else:
                                        stack.enter_context(alias(root, path, kind))
                            return regular(root, path)
                        with self.subTest(name=name, occurrence=occurrence, kind=kind), patch.object(cleanup, '_regular', observed):
                            with self.assertRaises(ValueError) as caught:
                                accepted.predecessor_pin_pair(self.root)
                        self.assertEqual(len(visits), occurrence)
                        if kind in ('leaf', 'ancestor', 'root', 'nonregular'):
                            self.assertIsInstance(caught.exception, cleanup.ContractError)
                        elif kind == 'missing':
                            self.assertIsInstance(caught.exception.__cause__, OSError)
                            self.assertIn('unreadable current paired pin: ' + name, str(caught.exception))
                        else:
                            self.assertIn(('current paired pin changed: ' if occurrence == 2 else 'unreviewed runtime pin successor: ') + name,
                                          str(caught.exception))
                    self.assertEqual((self.root/relative).read_bytes(), raw)

    def test_transient_consumed_alias_rejects_even_when_restored_before_finalization(self):
        regular = cleanup._regular
        name = PIN_DIR + '/' + NAMES[1]
        visits = []
        @wraps(regular)
        def observed(root, relative):
            if root == self.root and relative == name and sys._getframe(1).f_code is accepted._read_current_pair_pin.__code__:
                visits.append(relative)
                if len(visits) == 1:
                    with alias(root, relative, 'leaf'):
                        return regular(root, relative)
            return regular(root, relative)
        with patch.object(cleanup, '_regular', observed):
            with self.assertRaisesRegex(cleanup.ContractError, 'symlink input'):
                accepted.predecessor_pin_pair(self.root)
        self.assertEqual(visits, [name])
        self.assertFalse((self.root/name).is_symlink())

    def test_historical_matching_aliases_stay_accepted_current_root_alias_rejects(self):
        historical = fixtures.historical_root(self, ROOT)
        expected = tuple(accepted.predecessor_pins(historical, name) for name in NAMES)
        for name in NAMES:
            for kind in ('leaf', 'ancestor', 'root'):
                with self.subTest(name=name, kind=kind), alias(historical, PIN_DIR + '/' + name, kind), \
                        patch.object(cleanup, 'verify', side_effect=AssertionError('historical current gate')), \
                        patch.object(cleanup, '_regular', side_effect=AssertionError('historical regular restriction')), \
                        patch.object(cleanup, 'executing_checker_bindings', side_effect=AssertionError('historical checker restriction')):
                    self.assertEqual(accepted.predecessor_pin_pair(historical), expected)
        with alias(self.root, PIN_DIR + '/' + NAMES[0], 'root'):
            with self.assertRaisesRegex(ValueError, 'unreviewed complete successor: .*symbolic root or ancestor') as caught:
                accepted.predecessor_pin_pair(self.root)
            self.assertIsInstance(caught.exception.__cause__, cleanup.ContractError)

    def test_actual_executing_checker_mutation_before_guard_and_finalization(self):
        inverse, read_pin = accepted._pin_predecessor, accepted._read_current_pair_pin
        for stage in ('before_guard', 'before_final_checker'):
            visits, mutations = [], []
            with ExitStack() as stack:
                def break_checker():
                    mutations.append(stage)
                    stack.enter_context(patch.object(source, 'unique_keys', lambda pairs: dict(pairs)))
                @wraps(inverse)
                def inverted(raw, item, filename):
                    result = inverse(raw, item, filename)
                    if stage == 'before_guard' and filename == NAMES[0]:
                        break_checker()
                    return result
                @wraps(read_pin)
                def read(root, filename):
                    result = read_pin(root, filename)
                    visits.append(filename)
                    if stage == 'before_final_checker' and visits == [NAMES[0], NAMES[1], NAMES[0], NAMES[1]]:
                        break_checker()
                    return result
                with self.subTest(stage=stage), patch.object(accepted, '_pin_predecessor', inverted), \
                        patch.object(accepted, '_read_current_pair_pin', read):
                    with self.assertRaisesRegex(cleanup.ContractError, 'executing function changed: .*unique_keys'):
                        accepted.predecessor_pin_pair(self.root)
                self.assertEqual(mutations, [stage])
                self.assertEqual(visits, [NAMES[0]] if stage == 'before_guard' else [NAMES[0], NAMES[1], NAMES[0], NAMES[1]])

    def test_retained_first_gate_and_removed_second_sample_are_distinguished(self):
        verify = cleanup.verify
        calls = []
        @wraps(verify)
        def second_only(root, **kwargs):
            calls.append(root)
            if len(calls) == 2:
                self.fail('removed second full gate unexpectedly remains')
            return verify(root, **kwargs)
        with patch.object(cleanup, 'verify', second_only):
            assert_pair(self, accepted.predecessor_pin_pair(self.root))
        self.assertEqual(calls, [self.root])
        # This is an explicit removed-observation control, not a consumed-B claim.
        # The following mutations are consumed at retained first-gate surfaces.
        with authority_helpers.physical_change(self.root, LANE,
                (self.root/LANE).read_bytes().replace(b'if center_work >= 0:', b'if center_work > 0:', 1)):
            with self.assertRaises(ValueError):
                accepted.predecessor_pin_pair(self.root)
        with authority_helpers.physical_change(self.root, 'new_namespace/caller.mojo', b'from extensions.carla.lane_refinement import _try_lane_center_bound as hidden\n'):
            with self.assertRaisesRegex(ValueError, 'unreviewed complete successor:') as caught:
                accepted.predecessor_pin_pair(self.root)
            self.assertIsInstance(caught.exception.__cause__, cleanup.ContractError)
        # The retained first gate rejects std.mojo through the active Float32
        # native closure or the common resolver surface, whichever runs first.
        with authority_helpers.physical_change(self.root, 'std.mojo', b'# Resolver competitor.\n'):
            with self.assertRaisesRegex(ValueError,
                    r'^unreviewed complete successor: full-audit cleanup successor: '
                    r'(?:scaled native import closure changed|unreviewed alternate, '
                    r'compiled, package, symlink or std resolver surface)$') as caught:
                accepted.predecessor_pin_pair(self.root)
            self.assertIsInstance(caught.exception.__cause__, cleanup.ContractError)

    def test_second_calls_after_source_and_pin_mutation_never_reuse_prior_bytes(self):
        retained = accepted.predecessor_pin_pair(self.root)
        assert_pair(self, retained)
        for name, changed in ((PIN_DIR + '/' + NAMES[0], (self.root/PIN_DIR/NAMES[0]).read_bytes() + b' '),
                              (LANE, (self.root/LANE).read_bytes().replace(b'if center_work >= 0:', b'if center_work > 0:', 1))):
            with self.subTest(name=name), authority_helpers.physical_change(self.root, name, changed):
                with self.assertRaises(ValueError):
                    accepted.predecessor_pin_pair(self.root)
            self.assertEqual(accepted.predecessor_pin_pair(self.root), retained)
        with self.assertRaises(TypeError):
            accepted.predecessor_pin_pair(self.root, admission=retained)

    def test_distinct_relative_nested_threaded_and_failed_calls_are_fresh(self):
        other = fixtures.copy_historical_boundary_root(self, ROOT)
        qualify = accepted._verify_current_for_pin_pair
        calls, nested = [], []
        @wraps(qualify)
        def qualified(root):
            if root == self.root and not nested:
                nested.append('started')
                nested.append(accepted.predecessor_pin_pair(other))
            calls.append(root)
            return qualify(root)
        with patch.object(accepted, '_verify_current_for_pin_pair', qualified):
            main = accepted.predecessor_pin_pair(self.root)
        self.assertEqual(calls, [other, self.root])
        self.assertEqual(nested[1], main)
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(accepted.predecessor_pin_pair, (self.root, other)))
        self.assertEqual(results, [main, main])
        relative = Path(os.path.relpath(other, Path.cwd()))
        self.assertEqual(accepted.predecessor_pin_pair(relative), main)
        with authority_helpers.physical_change(other, PIN_DIR + '/' + NAMES[1], b'bad'):
            with self.assertRaises(ValueError):
                accepted.predecessor_pin_pair(other)
        self.assertEqual(accepted.predecessor_pin_pair(other), main)
        self.assertEqual(accepted.predecessor_pin_pair(self.root), main)

    def test_direct_package_import_orders_normal_and_optimized(self):
        command = '''import importlib, sys
from pathlib import Path
root = Path(sys.argv[1])
route, first = sys.argv[2:]
sys.path.insert(0, str(root if route == 'package' else root/'tools/carla_lane_oracle'))
prefix = 'tools.carla_lane_oracle.' if route == 'package' else ''
importlib.import_module(prefix + first)
accepted = importlib.import_module(prefix + 'accepted_successor_contracts')
result = accepted.predecessor_pin_pair(root)
if type(result) is not tuple or len(result) != 2 or any(type(raw) is not bytes for raw in result):
    raise RuntimeError('invalid paired output')
second = accepted.predecessor_pin_pair(root)
if result != second:
    raise RuntimeError('fresh paired outputs differ')
'''
        for mode in ([], ['-O']):
            for route in ('package', 'direct'):
                for first in ('rounded_line_selector_contracts', 'coverage_invariant_contracts'):
                    with self.subTest(mode=mode, route=route, first=first):
                        result = subprocess.run([sys.executable, *mode, '-B', '-c', command,
                                                 str(self.root), route, first], cwd=self.root,
                                                capture_output=True, text=True, timeout=120)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class SelectorOutputRealControls(unittest.TestCase):
    """The output flag cannot publish until all actual qualifying checks finish."""

    def setUp(self):
        self.root = fixtures.copy_historical_boundary_root(self, ROOT)

    def test_real_modes_identical_read_counts_true_branch_and_public_frame(self):
        verify, read_bytes, read_text, declaration = cleanup.verify, Path.read_bytes, Path.read_text, guard.declaration
        expected = selector.read_record(self.root)
        traces = []
        for kwargs in ({}, {'_return_current_admission': False}, {'_return_current_admission': True}):
            events, frames, gates = [], [], []
            def observed_bytes(path, *args, **kw):
                if path.is_relative_to(self.root):
                    events.append(('bytes', path.relative_to(self.root).as_posix()))
                return read_bytes(path, *args, **kw)
            def observed_text(path, *args, **kw):
                if path.is_relative_to(self.root):
                    events.append(('text', path.relative_to(self.root).as_posix()))
                return read_text(path, *args, **kw)
            @wraps(declaration)
            def declared(text, name, owner):
                if sys._getframe(1).f_code is selector.verify_premises.__code__:
                    frames.append(name)
                return declaration(text, name, owner)
            @wraps(verify)
            def gated(*args, **kwargs):
                gates.append((args, kwargs))
                return verify(*args, **kwargs)
            with patch.object(cleanup, 'verify', gated), \
                    patch.object(Path, 'read_bytes', observed_bytes), patch.object(Path, 'read_text', observed_text), \
                    patch.object(guard, 'declaration', declared):
                result = selector.verify_premises(self.root, **kwargs)
            self.assertEqual(len(gates), 1)
            self.assertEqual(result, (expected, True) if kwargs.get('_return_current_admission') else expected)
            self.assertIn('_rounded_axis_lane_minimum', frames)
            self.assertIn('_refine_lane_certificate', frames)
            traces.append(events)
        self.assertEqual(traces, [traces[0]] * 3)

    def test_real_historical_false_and_later_declaration_true(self):
        historical = fixtures.historical_root(self, ROOT)
        with patch.object(cleanup, 'verify', side_effect=AssertionError('historical gate')):
            record, observed = selector._verify_for_pin_pair(historical)
        self.assertIs(observed, False)
        self.assertEqual(record, selector.read_record(historical))
        before = cleanup.read_record(self.root)['sources'][LANE]['before_source']
        observe, project = selector._lane_observation, cleanup._reviewed_lane_observation
        visits = []
        def observed(root):
            visits.append(root)
            if len(visits) == 1:
                return before, before.encode()
            return observe(root)
        admissions = []
        @wraps(project)
        def projected(*args, **kwargs):
            admissions.append((args, kwargs))
            return project(*args, **kwargs)
        with patch.object(selector, '_lane_observation', observed), \
                patch.object(cleanup, '_reviewed_lane_observation', projected):
            record, current = selector._verify_for_pin_pair(self.root)
        self.assertIs(current, True)
        self.assertEqual(len(visits), 2)
        self.assertEqual(len(admissions), 1)
        self.assertEqual(record, selector.read_record(self.root))

    def test_gate_retained_final_and_selector_token_failures_publish_no_pair(self):
        read_bytes, read_text, verify = Path.read_bytes, Path.read_text, cleanup.verify
        for name in (LANE, ROAD):
            original = read_bytes(self.root/name)
            for occurrence in (1, 2):
                visits = []
                def observed(path, *args, **kwargs):
                    raw = read_bytes(path, *args, **kwargs)
                    if path == self.root/name and sys._getframe(1).f_code is selector.verify_premises.__code__:
                        visits.append(name)
                        if len(visits) == occurrence:
                            return original + b'\n# Consumed observation B.\n'
                    return raw
                with self.subTest(name=name, occurrence=occurrence), patch.object(Path, 'read_bytes', observed):
                    with self.assertRaisesRegex(ValueError, 'consumer observation changed: ' + name):
                        accepted.predecessor_pin_pair(self.root)
                self.assertEqual(len(visits), occurrence)
        failure = cleanup.ContractError('real gate failure sentinel')
        @wraps(verify)
        def failed_gate(*args, **kwargs):
            verify(*args, **kwargs)
            raise failure
        with patch.object(cleanup, 'verify', failed_gate):
            with self.assertRaises(ValueError) as caught:
                accepted.predecessor_pin_pair(self.root)
        self.assertIs(caught.exception.__cause__, failure)
        path = selector.read_record(self.root)['path']
        seen = []
        def changed(path_object, *args, **kwargs):
            text = read_text(path_object, *args, **kwargs)
            if path_object == self.root/path and sys._getframe(1).f_code is selector._verify_for_pin_pair.__code__:
                seen.append(path)
                return text + '\ndef unreviewed_selector_tail():\n    pass\n'
            return text
        with patch.object(Path, 'read_text', changed):
            with self.assertRaisesRegex(ValueError, 'complete selector successor changed'):
                accepted.predecessor_pin_pair(self.root)
        self.assertEqual(seen, [path])

    def test_distance_and_grouped_failure_preserve_wrapper_and_block_pin_consumption(self):
        for module in (distance, grouped_y):
            original = module.verify
            failure = ValueError('downstream failure ' + module.__name__)
            def failed(root):
                original(root)
                raise failure
            with self.subTest(module=module.__name__), patch.object(module, 'verify', failed), \
                    patch.object(accepted, '_read_current_pair_pin', side_effect=AssertionError('consumed pin before qualification')):
                with self.assertRaisesRegex(ValueError, 'unreviewed complete successor: downstream failure') as caught:
                    accepted.predecessor_pin_pair(self.root)
            self.assertIs(caught.exception.__cause__, failure)


if __name__ == '__main__':
    unittest.main()
