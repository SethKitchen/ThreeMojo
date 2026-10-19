# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact formatting inverse, live bindings and owned failure controls."""
from functools import wraps
import hashlib
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

import witness_format_contracts as witness
import full_audit_cleanup_contracts as cleanup
import _full_audit_test_fixtures as fixtures

ROOT = Path(__file__).resolve().parents[2]
LEAF = 'tools/carla_lane_oracle/witness_format_contracts.py'


class WitnessFormatLeafControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import _full_audit_test_fixtures as historical_fixtures
        owner = type('HistoricalClassFixture', (), {
            'addCleanup': staticmethod(cls.addClassCleanup)})()
        cls.historical_root = historical_fixtures.copy_historical_boundary_root(owner, ROOT)

    def test_all_four_exact_inverses_and_forward_replay(self):
        self.assertEqual(len(witness.SOURCE_PATHS), 4)
        record = cleanup.read_record(self.historical_root)
        for path in witness.SOURCE_PATHS:
            current = (self.historical_root/path).read_bytes().decode('utf-8')
            before = witness.predecessor_source(path, current)
            self.assertEqual(witness.observations(before), witness.observations(current))
            for group in ('native_witnesses', 'native_dependency_inputs'):
                self.assertEqual(witness.sha(before), record[group][path])
            self.assertEqual(witness.source.token_sha256(before), witness.BEFORE_TOKEN_SHA256[path])
            self.assertEqual(witness.source.token_sha256(current), witness.AFTER_TOKEN_SHA256[path])
            text = before
            for _, old, new in witness.EDITS[path]:
                self.assertEqual(text.count(old), 1)
                text = text.replace(old, new, 1)
            self.assertEqual(text, current)
            self.assertEqual(witness.edge(path)['after_sha256'], witness.sha(current))

    def test_unknown_semantic_and_raw_endpoints_refuse(self):
        for path in witness.SOURCE_PATHS:
            current = (self.historical_root/path).read_text()
            old = witness.predecessor_source(path, current)
            for changed in (old, current+'\n# unreviewed\n', current.replace('\n', '\r\n'),
                            current.replace('assert_', 'unreviewed_assert_', 1)):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    witness.predecessor_source(path, changed)
        with self.assertRaises(ValueError): witness.predecessor_source('tests/other.mojo', current)
        with self.assertRaises(ValueError): witness.edge('tests/other.mojo')

    def test_missing_duplicated_reordered_and_corrupt_inverse_refuse(self):
        for path in witness.SOURCE_PATHS:
            current = (self.historical_root/path).read_text()
            original = witness.EDITS[path]
            variants = [original[:-1], original+(original[-1],)]
            if len(original) > 1: variants.append(tuple(reversed(original)))
            name, before, after = original[0]
            variants.extend((((name, before+'\n', after),)+original[1:],
                             ((name, before, after+'?'),)+original[1:]))
            for edits in variants:
                with patch.dict(witness.EDITS, {path: edits}), self.assertRaises(ValueError):
                    witness.predecessor_source(path, current)

    def test_only_import_call_comma_and_plain_string_formatting_are_equivalent(self):
        pairs = [('from a import b, c\n', 'from a import (\n    b,\n    c,\n)\n'),
                 ('f(a, b)\n', 'f(\n    a,\n    b,\n)\n'),
                 ('print("one two")\n', 'print(\n    "one"\n    " two"\n)\n')]
        for old, new in pairs:
            self.assertEqual(witness.observations(old), witness.observations(new))
        for old, new in [('f((a,))\n', 'f((a))\n'), ('f(a, b)\n', 'f(b, a)\n'),
                         ('f(a + b)\n', 'f(a - b)\n'), ('f(1)\n', 'f(2)\n'),
                         ('print("a b")\n', 'print("ab")\n'),
                         ('if a:\n    f()\ng()\n', 'if a:\n    f()\n    g()\n'),
                         ('# one\nf()\n', '# two\nf()\n')]:
            self.assertNotEqual(witness.observations(old), witness.observations(new))

    def test_executed_leaf_functions_defaults_and_module_witness_are_bound(self):
        self.assertEqual(cleanup.executing_checker_bindings()[LEAF],
                         hashlib.sha256((self.historical_root/LEAF).read_bytes()).hexdigest())
        with patch.object(witness, 'predecessor_source', lambda path, text: text):
            with self.assertRaisesRegex(ValueError, 'executing function changed'):
                cleanup.executing_checker_bindings()
        with patch.object(witness.predecessor_source, '__defaults__', ('foreign',)):
            with self.assertRaisesRegex(ValueError, 'defaults changed'):
                cleanup.executing_checker_bindings()
        with patch.object(witness, '_EXECUTED_MODULE_CODE', compile('pass', witness.__file__, 'exec')):
            with self.assertRaisesRegex(ValueError, 'module-code witness changed'):
                cleanup.executing_checker_bindings()


class WitnessFormatPhysicalControls(unittest.TestCase):
    def setUp(self):
        self.root = fixtures.copy_current_root(self, ROOT)
        self.paths = (*witness.SOURCE_PATHS, LEAF, *witness.BOUND_INPUTS)

    def test_receipts_join_both_historical_groups_and_bind_all_live_inputs(self):
        record = cleanup.verify(self.root, exact=True)
        bindings = cleanup.proof_bindings(self.root)
        for path in witness.SOURCE_PATHS:
            for group in ('native_witnesses', 'native_dependency_inputs'):
                self.assertEqual(record[group][path], witness.BEFORE_SHA256[path])
            if path in cleanup.typed_boundary.EDGES:
                edge = cleanup.typed_boundary.edge(path)
                self.assertEqual(edge['before_sha256'], witness.AFTER_SHA256[path])
                self.assertEqual(bindings[path], edge['after_sha256'])
            else:
                self.assertEqual(bindings[path], witness.AFTER_SHA256[path])
        for path in self.paths:
            self.assertEqual(bindings[path], cleanup.sha((self.root/path).read_bytes()))
        self.assertEqual((self.root/cleanup.MIGRATION).read_bytes(), (ROOT/cleanup.MIGRATION).read_bytes())

    def test_historical_and_individually_formatted_witnesses_remain_exact(self):
        # Formatting-only endpoints belong to the named historical graph.
        # All other physical controls in this class retain the current root.
        self.root = fixtures.copy_historical_boundary_root(self, ROOT)
        raw = {p: (self.root/p).read_bytes() for p in witness.SOURCE_PATHS}
        old = {p: witness.predecessor_source(p, value.decode()).encode() for p, value in raw.items()}
        for path, value in old.items(): (self.root/path).write_bytes(value)
        self.assertEqual(cleanup._witness_format_bindings(self.root), {})
        cleanup.verify(self.root, exact=True)
        for path in witness.SOURCE_PATHS:
            (self.root/path).write_bytes(raw[path])
            bindings = cleanup._witness_format_bindings(self.root)
            self.assertEqual(bindings[path], witness.AFTER_SHA256[path])
            for other in witness.SOURCE_PATHS:
                self.assertEqual(bindings[other], cleanup.sha((self.root/other).read_bytes()))
            cleanup.verify(self.root, exact=True)
            (self.root/path).write_bytes(old[path])

    def test_every_missing_mutated_and_unreadable_witness_and_proof_input_refuses(self):
        read = Path.read_bytes
        for name in self.paths:
            target = self.root/name
            original = target.read_bytes()
            for missing in (False, True):
                with self.subTest(path=name, missing=missing):
                    try:
                        if missing: target.unlink()
                        else: target.write_bytes(original+b'\n# unreviewed\n')
                        with self.assertRaises((OSError, ValueError)): cleanup._witness_format_bindings(self.root)
                        with self.assertRaises(ValueError): cleanup.verify(self.root)
                    finally: target.write_bytes(original)
            def denied(path, *args, **kwargs):
                if path == target: raise OSError('witness-format read denied')
                return read(path, *args, **kwargs)
            with patch.object(Path, 'read_bytes', denied), self.assertRaises((OSError, ValueError)):
                cleanup._witness_format_bindings(self.root)

    def test_leaf_binding_does_not_acquire_whole_repository_context(self):
        # Observe the real current checker without invalidating its code seal.
        census = cleanup.guard.production_mojo_paths
        calls = []
        def reject_census(frame, event, value):
            if event == 'call' and frame.f_code is census.__code__:
                calls.append(True)
                raise AssertionError('extra census')
        previous = sys.getprofile()
        try:
            sys.setprofile(reject_census)
            with self.assertRaisesRegex(AssertionError, 'extra census'):
                list(census(self.root))
            self.assertEqual(calls, [True])
            # Python disables a profile callback after it raises. Rearm it for
            # the actual positive; any real census call must still fail.
            sys.setprofile(reject_census)
            bindings = cleanup._witness_format_bindings(self.root)
            self.assertEqual(calls, [True])
        finally:
            sys.setprofile(previous)
        self.assertEqual(set(bindings), set(self.paths))
        self.assertNotIn('math/scaled_products.mojo', bindings)
        with patch.object(cleanup.guard, 'production_mojo_paths', side_effect=AssertionError('extra census')):
            with self.assertRaisesRegex(cleanup.ContractError, 'executing function changed'):
                cleanup._witness_format_bindings(self.root)
        # The original pre-typed leaf still accepts the original monkeypatch
        # control, proving its no-census behavior independently of this edge.
        historical = fixtures.copy_historical_boundary_root(self, ROOT)
        with patch.object(cleanup.guard, 'production_mojo_paths', side_effect=AssertionError('extra census')):
            old_bindings = cleanup._witness_format_bindings(historical)
        self.assertEqual(set(old_bindings), set(self.paths))
        self.assertNotIn('math/scaled_products.mojo', old_bindings)
        for root, actual in ((self.root, bindings), (historical, old_bindings)):
            self.assertEqual(actual, {name: cleanup.sha((root/name).read_bytes())
                                      for name in self.paths})

    def test_alias_paths_and_native_module_shadows_refuse(self):
        current = self.root
        try:
            for cohort in ('pr760', 'common758'):
                self.root = (current if cohort == 'pr760' else
                             fixtures.copy_common758_boundary_root(self, ROOT))
                with self.subTest(cohort=cohort):
                    self._check_alias_paths_and_native_module_shadows_refuse(cohort)
        finally:
            self.root = current

    def _check_alias_paths_and_native_module_shadows_refuse(self, cohort):
        for name in (witness.SOURCE_PATHS[0], *witness.BOUND_INPUTS):
            target = self.root/name
            old = target.read_bytes()
            saved = target.with_suffix(target.suffix+'.saved')
            target.rename(saved)
            try:
                target.symlink_to(saved)
                with self.assertRaises((OSError, ValueError)): cleanup._witness_format_bindings(self.root)
            finally:
                target.unlink(); saved.rename(target)
            self.assertEqual(target.read_bytes(), old)
        alias = self.root.parent/(self.root.name+'-alias')
        alias.symlink_to(self.root, target_is_directory=True)
        try:
            with self.assertRaises(ValueError): cleanup._witness_format_bindings(alias)
        finally: alias.unlink()
        shadow = self.root/'tests/extensions/carla/lane_refinement.mojo'
        created = []
        parent = shadow.parent
        while not parent.exists():
            created.append(parent)
            parent = parent.parent
        shadow.parent.mkdir(parents=True)
        shadow.write_text('# unreviewed entry-local shadow\n')
        try:
            reason = ('PR760 exact dependency closure changed' if cohort == 'pr760'
                      else 'resolver')
            with self.assertRaisesRegex(ValueError, reason):
                cleanup.verify(self.root)
        finally:
            shadow.unlink()
            for parent in created:
                parent.rmdir()
        cleanup.verify(self.root, exact=True)

    def test_each_bound_input_is_reread_after_consumption(self):
        read = Path.read_bytes
        for name in self.paths:
            target = self.root/name
            seen = []
            def changed(path, *args, **kwargs):
                raw = read(path, *args, **kwargs)
                if path == target:
                    seen.append(True)
                    if len(seen) == 2: return raw+b'\n# transient B\n'
                return raw
            with self.subTest(path=name), patch.object(Path, 'read_bytes', changed):
                with self.assertRaisesRegex(ValueError, 'changed during admission'):
                    cleanup._witness_format_bindings(self.root)
            self.assertEqual(len(seen), 2)
            self.assertEqual(read(target), read(ROOT/name))

    def test_full_gate_final_reread_catches_late_proof_input_mutation(self):
        current = self.root
        try:
            for cohort in ('pr760', 'common758'):
                self.root = (current if cohort == 'pr760' else
                             fixtures.copy_common758_boundary_root(self, ROOT))
                with self.subTest(cohort=cohort):
                    self._check_full_gate_late_proof_input_mutation(cohort)
        finally:
            self.root = current

    def _check_full_gate_late_proof_input_mutation(self, cohort):
        original = cleanup.inventory
        target = self.root/next(iter(witness.BOUND_INPUTS))
        old = target.read_bytes()
        @wraps(original)
        def late(*args, **kwargs):
            value = original(*args, **kwargs)
            target.write_bytes(old+b'\n# after witness admission\n')
            return value
        try:
            # PR760 consumes inventory within its image admission; the same late
            # mutation meets its physical reread before the outer final sweep.
            reason = ('PR760 source changed after consumption: ' + target.relative_to(self.root).as_posix()
                      if cohort == 'pr760' else 'input changed during verification')
            with patch.object(cleanup, 'inventory', late), self.assertRaisesRegex(ValueError, reason):
                cleanup.verify(self.root)
        finally: target.write_bytes(old)

    def test_pending_caught_restore_remains_sticky_in_actual_owner(self):
        import coverage_invariant_contracts as invariant
        original = cleanup._witness_format_bindings
        read = Path.read_bytes
        target = self.root/witness.SOURCE_PATHS[0]
        injected, caught, retried, owners = [], [], [], []
        def transient(path, *args, **kwargs):
            raw = read(path, *args, **kwargs)
            caller = sys._getframe(1)
            if path == target and caller.f_code is original.__code__ and not injected:
                injected.append(True)
                return raw+b'\n# observed transient B\n'
            return raw
        @wraps(original)
        def catch(root, **kwargs):
            owner = kwargs.get('_operation')
            if owner is not None and not owners:
                owners.append(owner)
                self.assertEqual(owner._state, 'pending')
            try: return original(root, **kwargs)
            except ValueError as error:
                self.assertIs(type(error), cleanup._OperationCoherenceError)
                caught.append(error)
                with self.assertRaises(cleanup._OperationCoherenceError) as retry:
                    original(root, **kwargs)
                self.assertEqual(str(retry.exception), str(error))
                retried.append(retry.exception)
                raise retry.exception
        with patch.object(Path, 'read_bytes', transient), patch.object(cleanup, '_witness_format_bindings', catch):
            with self.assertRaisesRegex(ValueError, 'unreviewed complete successor:') as public:
                invariant.verify(self.root)
        self.assertIs(type(public.exception), ValueError)
        self.assertEqual(injected, [True]); self.assertEqual(len(caught), 1); self.assertEqual(len(owners), 1)
        self.assertEqual(len(retried), 1)
        self.assertIs(public.exception.__cause__, retried[0])
        self.assertIs(type(public.exception.__cause__), cleanup._OperationCoherenceError)
        self.assertEqual(read(target), read(ROOT/witness.SOURCE_PATHS[0]))

    def test_active_owner_final_reread_catches_late_witness_and_proof_changes(self):
        import coverage_invariant_contracts as invariant
        original = cleanup._InvariantInputs.finish
        for name in (witness.SOURCE_PATHS[0], next(iter(witness.BOUND_INPUTS))):
            target = self.root/name
            old = target.read_bytes()
            reached = []
            @wraps(original)
            def finish(owner, root):
                self.assertEqual(owner._state, 'active')
                reached.append(True)
                target.write_bytes(old+b'\n# mutation at outer finish\n')
                return original(owner, root)
            try:
                with patch.object(cleanup._InvariantInputs, 'finish', finish):
                    with self.assertRaisesRegex(cleanup._OperationCoherenceError, 'owned input changed'):
                        invariant.verify(self.root)
            finally: target.write_bytes(old)
            self.assertEqual(reached, [True])


if __name__ == '__main__':
    unittest.main()
