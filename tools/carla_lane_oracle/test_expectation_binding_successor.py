#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check the exact four-record expectation extension of the #333 input."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

import full_audit_cleanup_contracts as audit
import typed_boundary_contracts as typed

ROOT = Path(__file__).resolve().parents[2]
PATH = 'tools/compile_fail_expectations.json'
BEFORE = '85020fb32ec96121aba108288eaabf41c4483e2f94e91b6beee4528af2206653'
ADDED = {
    'tests/compile_fail/a_contact_mode_is_not_a_bare_int.mojo',
    'tests/compile_fail/a_failure_mode_is_not_a_bare_int.mojo',
    'tests/compile_fail/a_load_kind_is_not_a_bare_int.mojo',
    'tests/compile_fail/a_pipe_run_is_not_a_bare_int.mojo',
}


class ExpectationBindingSuccessor(unittest.TestCase):
    def setUp(self):
        self.raw = (ROOT/PATH).read_bytes()

    def test_exact_byte_predecessor_keeps_all_689_records(self):
        before = typed.expectation_predecessor(self.raw)
        self.assertEqual(hashlib.sha256(before).hexdigest(), BEFORE)
        self.assertEqual(typed.HISTORICAL_BINDING_INPUTS[PATH], BEFORE)
        self.assertEqual(len(typed.EXPECTATION_SUCCESSOR['edits']), 4)
        self.assertTrue(all(not before for _, _, before, _ in
                            typed.EXPECTATION_SUCCESSOR['edits']))
        old, current = json.loads(before), json.loads(self.raw)
        self.assertEqual((len(old), len(current)), (689, 693))
        self.assertEqual(set(current)-set(old), ADDED)
        self.assertEqual({key: current[key] for key in old}, old)
        self.assertEqual({key: current[key] for key in ADDED},
                         typed.EXPECTATION_SUCCESSOR['added_records'])
        # Nested diagnostic key order was retained in the historical file.
        canonical = (json.dumps(old, indent=2, sort_keys=True)+'\n').encode()
        self.assertNotEqual(canonical, before)

    def test_old_missing_extra_changed_and_malformed_inputs_are_refused(self):
        current = json.loads(self.raw)
        before = typed.expectation_predecessor(self.raw)
        missing = copy.deepcopy(current)
        del missing[sorted(ADDED)[0]]
        extra = {**current, 'tests/compile_fail/unreviewed.mojo': {}}
        old_changed = copy.deepcopy(current)
        old_key = sorted(set(current)-ADDED)[0]
        old_changed[old_key]['errors'][0]['message'] += ' changed'
        addition_changed = copy.deepcopy(current)
        addition_changed[sorted(ADDED)[0]]['errors'][0]['line'] += 1
        mutated = [before, self.raw+b'\n', b'{', bytearray(self.raw)]
        mutated += [(json.dumps(value, indent=2, sort_keys=True)+'\n').encode()
                    for value in (missing, extra, old_changed, addition_changed)]
        for raw in mutated:
            with self.subTest(kind=type(raw).__name__, size=len(raw)):
                with self.assertRaises(ValueError):
                    typed.expectation_predecessor(raw)

    def test_late_current_map_and_historical_map_changes_are_refused(self):
        typed.verify_binding_successor(PATH, self.raw)
        for name in ('BINDING_INPUTS', 'COMMON_BINDING_INPUTS', 'HISTORICAL_BINDING_INPUTS'):
            original = getattr(typed, name)
            changed = {**original, PATH: '0'*64}
            with self.subTest(name=name), patch.object(typed, name, changed):
                with self.assertRaises(ValueError):
                    typed.verify_binding_successor(PATH, self.raw)
                with self.assertRaises(ValueError):
                    audit.executing_checker_bindings(ROOT)

    def test_late_addition_and_inverse_metadata_changes_are_refused(self):
        typed.verify_binding_successor(PATH, self.raw)
        for field in ('added_records', 'edits', 'after_sha256'):
            changed = copy.deepcopy(typed.EXPECTATION_SUCCESSOR)
            if field == 'added_records':
                changed[field][sorted(ADDED)[0]]['notes'].append('unreviewed')
            elif field == 'edits':
                changed[field] = changed[field][1:]
            else:
                changed[field] = '0'*64
            with self.subTest(field=field), patch.object(typed, 'EXPECTATION_SUCCESSOR', changed):
                with self.assertRaises(ValueError):
                    typed.verify_binding_successor(PATH, self.raw)
                with self.assertRaises(ValueError):
                    audit.executing_checker_bindings(ROOT)


class ExpectationBindingCurrentInputs(unittest.TestCase):
    def test_current_receipt_names_actual_extended_input_bytes(self):
        raw = (ROOT/PATH).read_bytes()
        result = audit.proof_bindings(ROOT)
        digest = hashlib.sha256(raw).hexdigest()
        self.assertEqual(result[PATH], digest)
        self.assertEqual(typed.BINDING_INPUTS[PATH], digest)
        self.assertNotEqual(result[PATH], BEFORE)

    def test_first_and_final_physical_input_changes_are_refused(self):
        target = ROOT/PATH
        raw = target.read_bytes()
        original = Path.read_bytes
        for at_read in (1, 2):
            reads = []
            def changed(path, *args, **kwargs):
                if (path == target and sys._getframe(1).f_code is
                        audit._typed_boundary_bindings.__code__):
                    reads.append(path)
                    return raw+b'\n' if len(reads) == at_read else raw
                return original(path, *args, **kwargs)
            with self.subTest(at_read=at_read), patch.object(Path, 'read_bytes', changed):
                with self.assertRaises(ValueError):
                    audit._typed_boundary_bindings(ROOT)
            self.assertEqual(len(reads), at_read)
            self.assertEqual(target.read_bytes(), raw)


if __name__ == '__main__':
    unittest.main()
