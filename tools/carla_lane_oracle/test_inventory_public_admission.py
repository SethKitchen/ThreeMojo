# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Canonical inventory entry scopes: real frames, lifecycle and context refusal.

Early-stop controls establish scope selection only. They make no claim of
successful source admission. Positive controls run the complete real verifier.
"""
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from functools import wraps
import importlib.util
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import full_audit_cleanup_contracts as cleanup
import lane_order_contracts as lane
import source_contracts as source
import sum2_guard_contracts as guard
import _full_audit_test_fixtures as fixtures

ROOT = Path(__file__).resolve().parents[2]
ENTRIES = (guard, lane)


class SelectionStop(Exception):
    pass


@contextmanager
def profiling(callback):
    previous = sys.getprofile()
    if previous is not None:
        raise AssertionError('selection controls require an empty profiler slot')
    sys.setprofile(callback)
    try:
        yield
    finally:
        sys.setprofile(previous)


class InventoryPublicAdmissionControls(unittest.TestCase):
    def alias(self, module):
        spec = importlib.util.spec_from_file_location('_inventory_scope_alias_' + module.__name__, module.__file__)
        alias = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(alias)
        return alias

    def first_projection(self, module, action):
        # Stop at the actual first adapter boundary, outside a profiler callback.
        # These controls exercise scope selection/context, never source admission.
        seen = []
        def wrap(original):
            @wraps(original)
            def observe(*args, **kwargs):
                caller = sys._getframe(1)
                if (not seen and caller.f_globals is vars(module)
                        and caller.f_code is module.verify.__code__):
                    scope = caller.f_locals.get('_typed_admission')
                    seen.append(scope)
                    action(scope)
                return original(*args, **kwargs)
            return observe
        with patch.object(source, 'historical_text', wrap(source.historical_text)), patch.object(
                source, 'historical_bytes', wrap(source.historical_bytes)):
            module.verify(ROOT)
        self.assertEqual(len(seen), 1)
        return seen

    def test_canonical_pending_scopes_reject_root_thread_and_cwd_and_stay_poisoned(self):
        for module in ENTRIES:
            for fault in ('root', 'thread', 'cwd'):
                seen = []
                def fail_context(scope):
                    self.assertIs(type(scope), cleanup._PublicAdmission)
                    self.assertEqual(scope._state, 'pending')
                    seen.append(scope)
                    if fault == 'root':
                        with self.assertRaisesRegex(cleanup.ContractError, 'root, thread or working directory'):
                            scope._check(scope._owner, ROOT/'other')
                    elif fault == 'thread':
                        with ThreadPoolExecutor(max_workers=1) as pool:
                            future = pool.submit(scope._check, scope._owner, ROOT)
                            with self.assertRaisesRegex(cleanup.ContractError, 'root, thread or working directory'):
                                future.result()
                    else:
                        before = Path.cwd()
                        with tempfile.TemporaryDirectory() as directory:
                            try:
                                os.chdir(directory)
                                with self.assertRaisesRegex(cleanup.ContractError, 'root, thread or working directory'):
                                    scope._check(scope._owner, ROOT)
                            finally:
                                os.chdir(before)
                    self.assertTrue(scope._failed)
                    with self.assertRaisesRegex(cleanup.ContractError, 'inactive public admission'):
                        scope._check(scope._owner, ROOT)
                    raise SelectionStop()
                with self.subTest(entry=module.__name__, fault=fault), self.assertRaises(SelectionStop):
                    self.first_projection(module, fail_context)
                self.assertEqual(len(seen), 1)
                self.assertEqual(seen[0]._state, 'closed')
                self.assertFalse(seen[0]._raw)
                self.assertIsNone(seen[0]._owner_frame)

    def test_unregistered_alias_and_replaced_canonical_slot_never_issue_scope(self):
        for module in ENTRIES:
            for candidate, replaced in ((self.alias(module), False), (module, True)):
                seen = []
                def stop(scope):
                    seen.append(scope)
                    self.assertIsNone(scope)
                    raise SelectionStop()
                with self.subTest(entry=module.__name__, replaced=replaced):
                    with patch.dict(sys.modules, {module.__name__: self.alias(module)}) if replaced else patch.dict(sys.modules, {}):
                        with self.assertRaises(SelectionStop):
                            self.first_projection(candidate, stop)
                    self.assertEqual(seen, [None])

    def test_nested_alias_frame_is_a_barrier_and_slot_swap_poison_is_sticky(self):
        for module in ENTRIES:
            alias = self.alias(module)
            captured = []
            def nested(scope):
                self.assertIs(type(scope), cleanup._PublicAdmission)
                captured.append(scope)
                def alias_stop(selected):
                    self.assertIsNone(selected)
                    alias_frame = sys._getframe(2)
                    self.assertIs(alias_frame.f_globals, vars(alias))
                    self.assertFalse(scope._authenticate_frame(alias_frame))
                    raise SelectionStop()
                with self.assertRaises(SelectionStop):
                    self.first_projection(alias, alias_stop)
                with patch.dict(sys.modules, {module.__name__: alias}):
                    with self.assertRaisesRegex(cleanup.ContractError, 'owner code changed'):
                        scope._check(scope._owner, ROOT)
                self.assertTrue(scope._failed)
                with self.assertRaisesRegex(cleanup.ContractError, 'inactive public admission'):
                    scope._check(scope._owner, ROOT)
                raise SelectionStop()
            with self.subTest(entry=module.__name__), self.assertRaises(SelectionStop):
                self.first_projection(module, nested)
            self.assertEqual(len(captured), 1)
            self.assertEqual(captured[0]._state, 'closed')
            self.assertIsNone(captured[0]._owner_frame)

    def test_explicit_operation_bypasses_public_factory_and_rejects_invalid_owner(self):
        for module in ENTRIES:
            entered = []
            def observe(frame, event, value):
                if event == 'call' and frame.f_code is cleanup._PublicAdmission.__enter__.__code__:
                    entered.append(frame)
            with self.subTest(entry=module.__name__), profiling(observe):
                with self.assertRaises(ValueError):
                    module.verify(ROOT, _operation=object())
            self.assertEqual(entered, [])

    def test_qualified_package_entries_select_their_own_canonical_scope(self):
        command = """
from pathlib import Path
import sys
from unittest.mock import patch
from tools.carla_lane_oracle import full_audit_cleanup_contracts as owner
from tools.carla_lane_oracle import source_contracts as source
from tools.carla_lane_oracle import sum2_guard_contracts as guard
from tools.carla_lane_oracle import lane_order_contracts as lane
class Stop(Exception): pass
for module in (guard, lane):
    seen = []
    def stop(*args, **kwargs):
        scope = sys._getframe(1).f_locals.get('_typed_admission')
        if type(scope) is not owner._PublicAdmission or scope._state != 'pending':
            raise RuntimeError('qualified canonical scope missing')
        seen.append(scope)
        raise Stop()
    with patch.object(source, 'historical_text', stop), patch.object(source, 'historical_bytes', stop):
        try: module.verify(Path.cwd())
        except Stop: pass
        else: raise RuntimeError('selection boundary was not reached')
    if len(seen) != 1 or seen[0]._state != 'closed' or seen[0]._owner_frame is not None:
        raise RuntimeError('qualified scope did not close')
print('qualified canonical scopes selected and closed')
"""
        result = subprocess.run([sys.executable, *(['-O'] if sys.flags.optimize else []),
                                 '-B', '-c', command], cwd=ROOT, check=True,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.stdout.strip(), 'qualified canonical scopes selected and closed')

    def test_real_canonical_calls_close_and_erase_admitted_images(self):
        for module in ENTRIES:
            scopes, published, checkpoints, completed, nested = [], [], [], [], []
            def observe(frame, event, value):
                if (event == 'call' and frame.f_code is cleanup._CacheInputs.checkpoint.__code__
                        and scopes and frame.f_locals.get('self') is scopes[0]):
                    checkpoints.append(scopes[0])
                if (event == 'return' and frame.f_code is cleanup._CacheInputs.checkpoint.__code__
                        and scopes and frame.f_locals.get('self') is scopes[0]):
                    completed.append(scopes[0])
                if frame.f_globals is not vars(cleanup):
                    return
                if event == 'return' and frame.f_code is cleanup._PublicAdmission.__enter__.__code__:
                    if (value._owner_frame.f_globals is vars(module)
                            and value._owner_frame.f_code is module.verify.__code__):
                        scopes.append(value)
                    else:
                        nested.append(value)
                if (event == 'return' and frame.f_code is cleanup._PublicAdmission._publish.__code__
                        and scopes and frame.f_locals['self'] is scopes[0]):
                    published.append(scopes[0])
            with self.subTest(entry=module.__name__), profiling(observe):
                result = module.verify(ROOT)
            self.assertIs(type(result), dict)
            self.assertEqual(len(scopes), 1)
            for nested_scope in nested:
                self.assertEqual(nested_scope._state, 'closed')
                self.assertFalse(nested_scope._failed)
                self.assertFalse(nested_scope._raw)
                self.assertIsNone(nested_scope._owner_frame)
            self.assertEqual(published, [scopes[0]])
            self.assertTrue(checkpoints)
            self.assertEqual(completed, checkpoints)
            scope = scopes[0]
            self.assertEqual(scope._state, 'closed')
            self.assertFalse(scope._failed)
            self.assertFalse(scope._raw)
            self.assertIsNone(scope._owner_frame)
            with self.assertRaisesRegex(cleanup.ContractError, 'inactive public admission'):
                scope.raw(scope._owner, ROOT, 'extensions/carla/map.mojo')


class InventoryPublicAdmissionPhysicalControls(unittest.TestCase):
    """Complete calls on isolated physical roots; no mocked admission result."""
    def test_physical_mutation_and_observed_aba_cannot_publish_success(self):
        root = fixtures.copy_current_root(self, ROOT)
        path = root/'extensions/carla/map.mojo'
        original = path.read_bytes()
        for module in ENTRIES:
            for fault in ('persistent', 'observed-aba'):
                scopes, changed = [], []
                read = Path.read_bytes
                def observed_read(candidate, *args, **kwargs):
                    if (fault == 'observed-aba' and not changed and candidate == path
                            and scopes and scopes[0]._state == 'active'):
                        changed.append(True)
                        candidate.write_bytes(original + b'\n# observed physical B\n')
                        try:
                            return read(candidate, *args, **kwargs)
                        finally:
                            candidate.write_bytes(original)
                    return read(candidate, *args, **kwargs)
                def observe(frame, event, value):
                    if (event == 'return' and frame.f_globals is vars(cleanup)
                            and frame.f_code is cleanup._PublicAdmission._publish.__code__):
                        scope = frame.f_locals['self']
                        if (not scopes and scope._owner_frame.f_globals is vars(module)
                                and scope._owner_frame.f_code is module.verify.__code__):
                            scopes.append(scope)
                            if fault == 'persistent':
                                path.write_bytes(original + b'\n# persistent physical B\n')
                                changed.append(True)
                try:
                    with self.subTest(entry=module.__name__, fault=fault), patch.object(
                            Path, 'read_bytes', observed_read), profiling(observe):
                        with self.assertRaises(ValueError):
                            module.verify(root)
                    self.assertEqual(changed, [True])
                    self.assertEqual(len(scopes), 1)
                    self.assertEqual(scopes[0]._state, 'closed')
                    self.assertTrue(scopes[0]._failed)
                    self.assertFalse(scopes[0]._raw)
                    self.assertIsNone(scopes[0]._owner_frame)
                finally:
                    path.write_bytes(original)
                self.assertEqual(path.read_bytes(), original)
            self.assertIs(type(module.verify(root)), dict)

    def test_terminal_checkpoint_rereads_physical_source_and_closes_on_refusal(self):
        root = fixtures.copy_current_root(self, ROOT)
        path = root/'extensions/carla/map.mojo'
        original = path.read_bytes()
        for module in ENTRIES:
            scopes, changed = [], []
            def observe(frame, event, value):
                if (event == 'return' and frame.f_globals is vars(cleanup)
                        and frame.f_code is cleanup._PublicAdmission._publish.__code__ and not scopes
                        and frame.f_locals['self']._owner_frame.f_globals is vars(module)
                        and frame.f_locals['self']._owner_frame.f_code is module.verify.__code__):
                    scopes.append(frame.f_locals['self'])
                if (event == 'call' and frame.f_code is cleanup._CacheInputs.checkpoint.__code__
                        and scopes and frame.f_locals.get('self') is scopes[0]
                        and frame.f_back.f_code is cleanup._PublicAdmission.__exit__.__code__):
                    if changed:
                        raise AssertionError('terminal checkpoint repeated')
                    changed.append(True)
                    path.write_bytes(original + b'\n# terminal physical B\n')
            try:
                with self.subTest(entry=module.__name__), profiling(observe):
                    with self.assertRaisesRegex(cleanup.ContractError,
                            'owned input changed: extensions/carla/map.mojo'):
                        module.verify(root)
                self.assertEqual(changed, [True])
                self.assertEqual(len(scopes), 1)
                self.assertEqual(scopes[0]._state, 'closed')
                self.assertFalse(scopes[0]._raw)
                self.assertIsNone(scopes[0]._owner_frame)
                with self.assertRaisesRegex(cleanup.ContractError, 'inactive public admission'):
                    scopes[0].raw(scopes[0]._owner, root, 'extensions/carla/map.mojo')
            finally:
                path.write_bytes(original)
            self.assertEqual(path.read_bytes(), original)

    def test_live_authority_mutation_rejects_and_restores(self):
        root = fixtures.copy_current_root(self, ROOT)
        for module in ENTRIES:
            table = cleanup.typed_boundary.BINDING_INPUTS
            scopes = []
            def observe(frame, event, value):
                if (event == 'return' and frame.f_globals is vars(cleanup)
                        and frame.f_code is cleanup._PublicAdmission._publish.__code__ and not scopes
                        and frame.f_locals['self']._owner_frame.f_globals is vars(module)
                        and frame.f_locals['self']._owner_frame.f_code is module.verify.__code__):
                    scopes.append(frame.f_locals['self'])
                    cleanup.typed_boundary.BINDING_INPUTS = {**table, 'unreviewed.txt': '0'*64}
            try:
                with self.subTest(entry=module.__name__), profiling(observe):
                    with self.assertRaises(ValueError):
                        module.verify(root)
                self.assertEqual(len(scopes), 1)
                self.assertEqual(scopes[0]._state, 'closed')
                self.assertTrue(scopes[0]._failed)
                self.assertFalse(scopes[0]._raw)
                self.assertIsNone(scopes[0]._owner_frame)
            finally:
                cleanup.typed_boundary.BINDING_INPUTS = table
            self.assertIs(type(module.verify(root)), dict)


if __name__ == '__main__':
    unittest.main()
