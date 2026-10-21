#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact C API expectation extension and additive water-witness provenance."""
import copy
import hashlib
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import full_audit_cleanup_contracts as owner
import _full_audit_test_fixtures as fixtures

ROOT = Path(__file__).resolve().parents[2]
EXPECTATIONS = 'tools/compile_fail_expectations.json'
PATHS = (
    'tests/test_water.mojo', EXPECTATIONS,
    'tools/carla_lane_oracle/test_expectation_binding_successor.py',
    'tools/carla_lane_oracle/test_pr760_physical_image.py',
    'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py',
    'tools/carla_lane_oracle/test_typed_boundary_contracts.py',
)
ADDED = {f'tests/compile_fail/a_{kind}_{selector}_is_not_a_bare_int.mojo'
         for kind in ('gpu', 'splat') for selector in ('info', 'part')}


class ExactSuccessorControls(unittest.TestCase):
    def test_preserved_image_and_typed_authority_are_unchanged(self):
        self.assertEqual(owner.sha((ROOT/owner.PR760_IMAGE).read_bytes()),
                         'ef91b7edab2c8a597aeedc90f86e834d5227aad5770ebe39e0438944f246f7cf')
        self.assertEqual(owner.sha((ROOT/'tools/carla_lane_oracle/typed_boundary_contracts.py').read_bytes()),
                         '59cc73b325af897981a2d7299cf2d4ed3c61d3ea64d5f958f2b85aef51666362')
        data = json.loads((ROOT/owner.PR760_IMAGE).read_bytes())
        for path in PATHS:
            raw = (ROOT/path).read_bytes()
            previous = owner.pr776_predecessor_bytes(path, raw)
            self.assertEqual(owner.sha(previous), data['inputs'][path])
            self.assertNotEqual(previous, raw)
            self.assertEqual((ROOT/path).read_bytes(), raw)

    def test_expectations_append_exactly_four_records_and_preserve_all_704(self):
        raw = (ROOT/EXPECTATIONS).read_bytes()
        prior = owner.pr776_predecessor_bytes(EXPECTATIONS, raw)
        old, current = json.loads(prior), json.loads(raw)
        self.assertEqual((len(old), len(current)), (704, 708))
        self.assertEqual(set(current)-set(old), ADDED)
        self.assertEqual({path: current[path] for path in old}, old)
        self.assertEqual(owner.sha(prior), owner.typed_boundary.BINDING_INPUTS[EXPECTATIONS])
        historical = owner.typed_boundary.expectation_predecessor(prior)
        self.assertEqual(owner.sha(historical), owner.typed_boundary.HISTORICAL_BINDING_INPUTS[EXPECTATIONS])
        self.assertEqual(len(json.loads(historical)), 689)
        for path in ADDED:
            record = current[path]
            self.assertEqual(len(record['errors']), 1)
            self.assertEqual(record['notes'], ['function declared here'])
            self.assertEqual((record['errors'][0]['line'], record['errors'][0]['column']), (12, 21))

    def test_typed_witness_adds_only_the_exact_expectation_predecessor_join(self):
        path = 'tools/carla_lane_oracle/test_typed_boundary_contracts.py'
        raw = (ROOT/path).read_bytes()
        raw = owner.pr780_successor.predecessor_bytes(path, raw)
        prior = owner.pr776_predecessor_bytes(path, raw)
        addition = (b"                if path == 'tools/compile_fail_expectations.json':\n"
                    b'                    raw = audit.pr776_predecessor_bytes(path, raw)\n')
        self.assertEqual(raw.count(addition), 1)
        self.assertEqual(raw.replace(addition, b'', 1), prior)
        archive = ROOT/'tools/carla_lane_oracle/pr760-test_typed_boundary_contracts-predecessor.txt'
        historical = archive.read_bytes()
        self.assertEqual(owner.qualification_predecessor_bytes(path, raw), historical)
        self.assertEqual(owner.qualification_predecessor_bytes(path, prior), historical)
        self.assertEqual(owner.sha(historical), owner.typed_boundary.BINDING_INPUTS[path])
        changed = raw.replace(b'raw = audit.pr776_predecessor_bytes(path, raw)',
                              b'raw = bytes(raw)', 1)
        for endpoint in (changed, raw+b'\n'):
            with self.subTest(digest=owner.sha(endpoint)), self.assertRaises(ValueError):
                owner.qualification_predecessor_bytes(path, endpoint)

    def test_no_unreviewed_endpoint_or_mutable_input_can_be_projected(self):
        for path in PATHS:
            raw = (ROOT/path).read_bytes()
            prior = owner.pr776_predecessor_bytes(path, raw)
            for bad in (prior, raw+b'\n', raw[:-1], raw.replace(b'\n', b'\r\n'),
                        bytearray(raw), raw.decode(), b''):
                with self.subTest(path=path, kind=type(bad).__name__, size=len(bad)):
                    with self.assertRaises(ValueError):
                        owner.pr776_predecessor_bytes(path, bad)
        with self.assertRaises(ValueError):
            owner.pr776_predecessor_bytes('unreviewed', b'')

    def test_missing_extra_old_changed_and_added_changed_diagnostics_are_refused(self):
        raw = (ROOT/EXPECTATIONS).read_bytes()
        current = json.loads(raw)
        missing = copy.deepcopy(current)
        del missing[sorted(ADDED)[0]]
        extra = {**current, 'tests/compile_fail/unreviewed.mojo': {}}
        old_changed = copy.deepcopy(current)
        old_changed[sorted(set(current)-ADDED)[0]]['errors'][0]['message'] += ' changed'
        addition_changed = copy.deepcopy(current)
        addition_changed[sorted(ADDED)[0]]['errors'][0]['line'] += 1
        for value in (missing, extra, old_changed, addition_changed):
            encoded = (json.dumps(value, indent=2)+'\n').encode()
            with self.subTest(digest=owner.sha(encoded)), self.assertRaises(ValueError):
                owner.pr776_predecessor_bytes(EXPECTATIONS, encoded)

    def test_live_inverse_code_mutation_is_refused(self):
        function = owner.pr776_predecessor_bytes
        original = function.__code__
        constants = list(original.co_consts)
        index = next(i for i, value in enumerate(constants)
                     if type(value) is str and value.startswith('PR776 predecessor requires'))
        constants[index] += ' changed'
        try:
            function.__code__ = original.replace(co_consts=tuple(constants))
            with self.assertRaisesRegex(ValueError, 'executing function changed'):
                owner.executing_checker_bindings(ROOT)
        finally:
            function.__code__ = original
        owner.executing_checker_bindings(ROOT)


class PhysicalSuccessorControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cleanup = unittest.TestCase()
        cls.root = fixtures.copy_current_root(cls.cleanup, ROOT)
        cls.bindings = owner.proof_bindings(cls.root)

    @classmethod
    def tearDownClass(cls):
        cls.cleanup.doCleanups()

    def test_receipt_keeps_every_current_byte_and_new_diagnostic_fixture(self):
        for path in (*PATHS, *sorted(ADDED),
                     'tools/carla_lane_oracle/test_pr776_input_successors.py'):
            with self.subTest(path=path):
                self.assertEqual(self.bindings[path], owner.sha((self.root/path).read_bytes()))

    def test_old_mixed_or_modified_endpoints_cannot_borrow_current_admission(self):
        for path in PATHS:
            target = self.root/path
            raw = target.read_bytes()
            previous = owner.pr776_predecessor_bytes(path, raw)
            for changed in (previous, raw+b'\n'):
                try:
                    target.write_bytes(changed)
                    with self.subTest(path=path, digest=owner.sha(changed)):
                        with self.assertRaises(ValueError):
                            owner.proof_bindings(self.root)
                finally:
                    target.write_bytes(raw)
        owner.proof_bindings(self.root)

    def test_new_fixture_changes_and_missing_regression_are_refused(self):
        for path in (*sorted(ADDED), 'tools/carla_lane_oracle/test_pr776_input_successors.py'):
            target = self.root/path
            raw = target.read_bytes()
            try:
                target.write_bytes(raw+b'\n')
                with self.subTest(path=path), self.assertRaises(ValueError):
                    owner.proof_bindings(self.root)
                target.unlink()
                with self.subTest(path=path, missing=True), self.assertRaises(ValueError):
                    owner.proof_bindings(self.root)
            finally:
                target.write_bytes(raw)
        owner.proof_bindings(self.root)


if __name__ == '__main__':
    unittest.main()
