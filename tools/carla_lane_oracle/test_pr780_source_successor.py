# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact PR780 lineage and current physical-source rejection controls."""
import ast
import copy
import hashlib
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

import full_audit_cleanup_contracts as owner
import pr780_source_successor as successor
import _full_audit_test_fixtures as fixtures

ROOT = Path(__file__).resolve().parents[2]


class ExactSourceSuccessorControls(unittest.TestCase):
    def test_historical_authorities_are_unchanged(self):
        self.assertEqual(owner.sha((ROOT/owner.PR760_IMAGE).read_bytes()),
                         'ef91b7edab2c8a597aeedc90f86e834d5227aad5770ebe39e0438944f246f7cf')
        self.assertEqual(owner.sha((ROOT/'tools/carla_lane_oracle/pr760_arithmetic_stage.py').read_bytes()),
                         '03757bafb02fbb3908919839c18d5c2c443f46469aeb01393dee57ae22054359')
        self.assertEqual(owner.sha((ROOT/'tools/carla_lane_oracle/typed_boundary_contracts.py').read_bytes()),
                         '59cc73b325af897981a2d7299cf2d4ed3c61d3ea64d5f958f2b85aef51666362')
        self.assertEqual(owner.sha((ROOT/owner.PR760_OWNER_PREDECESSOR).read_bytes()),
                         '6138ba2dcac394c716ea9ed32e74e0c6d15857d5c605fc82304d21d0c80fdc69')

    def test_exact_sources_round_trip_into_original_image(self):
        image = json.loads((ROOT/owner.PR760_IMAGE).read_bytes())
        previous_pins = {**image['inputs'], **owner._pr776_input_pins(),
                         **owner._pr776_bound_inputs()}
        physical = {path: (ROOT/path).read_bytes() for path in successor.EDGES}
        previous = successor.verify_sources(physical)
        self.assertEqual(set(previous), set(successor.EDGES))
        for path, prior in previous.items():
            edge = successor.EDGES[path]
            with self.subTest(path=path):
                self.assertEqual(owner.sha(prior), previous_pins[path])
                self.assertEqual(owner.sha(prior), edge['before_sha256'])
                self.assertEqual(owner.sha(physical[path]), edge['after_sha256'])
                lines = prior.decode().splitlines(keepends=True)
                for edit in edge['edits']:
                    start, old = edit['start'], edit['before']
                    self.assertEqual(lines[start:start+len(old)], old)
                    lines[start:start+len(old)] = edit['after']
                self.assertEqual(''.join(lines).encode(), physical[path])
                self.assertEqual(successor.predecessor_bytes(path, prior), prior)
                self.assertEqual((ROOT/path).read_bytes(), physical[path])

    def test_unknown_mutable_modified_and_mixed_inputs_are_refused(self):
        physical = {path: (ROOT/path).read_bytes() for path in successor.EDGES}
        for path, raw in physical.items():
            prior = successor.predecessor_bytes(path, raw)
            for changed in (raw+b'\n', raw[:-1], raw.replace(b'\n', b'\r\n'),
                            bytearray(raw), raw.decode(), b''):
                with self.subTest(path=path, kind=type(changed).__name__), self.assertRaises(ValueError):
                    successor.predecessor_bytes(path, changed)
            with self.subTest(path=path), self.assertRaises(ValueError):
                successor.verify_sources({**physical, path: prior})
        missing = dict(physical)
        missing.pop(next(iter(missing)))
        for changed in (missing, {**physical, 'unreviewed.mojo': b'pass\n'}):
            with self.assertRaises(ValueError):
                successor.verify_sources(changed)
        raw = b'unrelated bytes'
        self.assertIs(successor.predecessor_bytes('unreviewed.mojo', raw), raw)

    def test_namespace_and_coordinated_digest_changes_are_refused(self):
        changed = copy.deepcopy(successor.EDGES)
        changed[next(iter(changed))]['after_sha256'] = '0'*64
        with patch.object(successor, 'EDGES', changed), self.assertRaises(ValueError):
            successor.verify_data()
        payload = {'edges': changed, 'bound_inputs': successor.BOUND_INPUTS}
        digest = owner.sha(json.dumps(payload, sort_keys=True, separators=(',', ':')))
        with patch.object(successor, 'EDGES', changed), patch.object(successor, 'DATA_SHA256', digest):
            with self.assertRaises(ValueError):
                successor.verify_data()
        with patch.object(successor, 'BOUND_INPUTS', {}), self.assertRaises(ValueError):
            successor.verify_data()

    def test_nonbuiltin_digest_selector_cannot_admit_changed_data(self):
        class EqualString(str):
            def __eq__(self, other):
                return True
        class EqualObject:
            def __eq__(self, other):
                return True
        changed = dict(successor.BOUND_INPUTS)
        changed['tests/test_loader_bounds.mojo'] = '0'*64
        for selector in (EqualString(successor.DATA_SHA256), EqualObject()):
            with self.subTest(kind=type(selector).__name__), patch.object(
                    successor, 'DATA_SHA256', selector), patch.object(
                    successor, 'BOUND_INPUTS', changed):
                with self.assertRaisesRegex(ValueError, 'not a builtin string'):
                    successor._data_snapshot()
                with self.assertRaisesRegex(ValueError, 'not a builtin string'):
                    owner.executing_checker_bindings(ROOT)
        successor.verify_data()
        owner.executing_checker_bindings(ROOT)

    def test_inverse_consumes_detached_exact_data(self):
        path = 'core/extent.mojo'
        raw = (ROOT/path).read_bytes()
        expected = successor.predecessor_bytes(path, raw)
        original = successor._predecessor
        calls = []
        def transient(name, value, edge):
            self.assertIsNot(edge, successor.EDGES[name])
            self.assertIsNot(edge['edits'], successor.EDGES[name]['edits'])
            digest = successor.EDGES[name]['before_sha256']
            successor.EDGES[name]['before_sha256'] = '0'*64
            try:
                calls.append(name)
                return original(name, value, edge)
            finally:
                successor.EDGES[name]['before_sha256'] = digest
        with patch.object(successor, '_predecessor', transient):
            self.assertEqual(successor.predecessor_bytes(path, raw), expected)
        self.assertEqual(calls, [path])
        successor.verify_data()

    def test_executing_inverse_code_is_bound(self):
        function = successor.predecessor_bytes
        original = function.__code__
        constants = list(original.co_consts)
        index = next(i for i, value in enumerate(constants)
                     if type(value) is str and value.startswith('predecessor requires'))
        constants[index] += ' changed'
        try:
            function.__code__ = original.replace(co_consts=tuple(constants))
            with self.assertRaisesRegex(ValueError, 'executing function changed'):
                owner.executing_checker_bindings(ROOT)
        finally:
            function.__code__ = original
        owner.executing_checker_bindings(ROOT)

    def test_owner_consumes_only_authenticated_detached_extension_data(self):
        tree = ast.parse((ROOT/'tools/carla_lane_oracle/full_audit_cleanup_contracts.py').read_text())
        self.assertFalse([node for node in ast.walk(tree)
                          if isinstance(node, ast.Attribute)
                          and isinstance(node.value, ast.Name)
                          and node.value.id == 'pr780_successor'
                          and node.attr in ('EDGES', 'BOUND_INPUTS')])
        snapshot = successor._data_snapshot()
        self.assertIsNot(snapshot['edges'], successor.EDGES)
        self.assertIsNot(snapshot['bound_inputs'], successor.BOUND_INPUTS)
        for path in successor.EDGES:
            self.assertIsNot(snapshot['edges'][path], successor.EDGES[path])


class PhysicalSourceSuccessorControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cleanup = unittest.TestCase()
        cls.root = fixtures.copy_current_root(cls.cleanup, ROOT)
        cls.bindings = owner.proof_bindings(cls.root)

    @classmethod
    def tearDownClass(cls):
        cls.cleanup.doCleanups()

    def test_receipt_retains_current_sources_witnesses_and_checker(self):
        for path in (*successor.EDGES, *successor.BOUND_INPUTS,
                     'tools/carla_lane_oracle/pr780_source_successor.py'):
            with self.subTest(path=path):
                self.assertEqual(self.bindings[path], owner.sha((self.root/path).read_bytes()))
        self.assertEqual(owner._pr760_candidate_bindings(self.root)['closures'],
                         {name: frozenset(paths) for name, paths in
                          json.loads((self.root/owner.PR760_IMAGE).read_bytes())['closures'].items()})

    def test_every_old_mixed_and_changed_endpoint_refuses_physical_admission(self):
        for path in successor.EDGES:
            target = self.root/path
            raw = target.read_bytes()
            prior = successor.predecessor_bytes(path, raw)
            for changed in (prior, raw+b'\n'):
                try:
                    target.write_bytes(changed)
                    with self.subTest(path=path, digest=owner.sha(changed)), self.assertRaises(ValueError):
                        owner.proof_bindings(self.root)
                finally:
                    target.write_bytes(raw)
        owner.proof_bindings(self.root)

    def test_bound_regressions_and_checker_are_required(self):
        for path in (*successor.BOUND_INPUTS, 'tools/carla_lane_oracle/pr780_source_successor.py'):
            target = self.root/path
            raw = target.read_bytes()
            try:
                target.write_bytes(raw+b'\n')
                with self.subTest(path=path), self.assertRaises(ValueError):
                    owner.proof_bindings(self.root)
                target.unlink()
                with self.subTest(path=path, missing=True), self.assertRaises((ValueError, FileNotFoundError)):
                    owner.proof_bindings(self.root)
            finally:
                target.write_bytes(raw)
        owner.proof_bindings(self.root)

    def test_transient_observation_drift_refuses_even_with_unchanged_disk(self):
        path = 'core/extent.mojo'
        target = self.root/path
        raw = target.read_bytes()
        read = Path.read_bytes
        calls = []
        def changed(file):
            value = read(file)
            if file == target and not calls:
                calls.append(file)
                return value+b'\n'
            return value
        with patch.object(Path, 'read_bytes', changed), self.assertRaises(ValueError):
            owner.proof_bindings(self.root)
        self.assertEqual(calls, [target])
        self.assertEqual(target.read_bytes(), raw)
        owner.proof_bindings(self.root)

    def test_transient_regression_table_change_cannot_change_consumed_pins(self):
        path = 'tests/test_loader_bounds.mojo'
        target = self.root/path
        raw = target.read_bytes()
        digest = successor.BOUND_INPUTS[path]
        changed = raw + b'\n# unreviewed regression source\n'
        read = Path.read_bytes
        calls = []
        def transient(file):
            value = read(file)
            frame = sys._getframe(1)
            if (frame.f_code.co_name == 'observe'
                    and frame.f_back.f_code is owner._pr760_candidate_bindings.__code__):
                if file == self.root/'tests/test_anatomy_muscle.mojo' and not calls:
                    successor.BOUND_INPUTS[path] = owner.sha(changed)
                    calls.append('change')
                elif file == target and calls == ['change']:
                    successor.BOUND_INPUTS[path] = digest
                    calls.append('restore')
            return value
        try:
            target.write_bytes(changed)
            with patch.object(Path, 'read_bytes', transient), self.assertRaisesRegex(
                    ValueError, 'PR780 bound input changed'):
                owner._pr760_candidate_bindings(self.root)
            self.assertEqual(calls, ['change', 'restore'])
        finally:
            successor.BOUND_INPUTS[path] = digest
            target.write_bytes(raw)
        owner.proof_bindings(self.root)


if __name__ == '__main__':
    unittest.main()
