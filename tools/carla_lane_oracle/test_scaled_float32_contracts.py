# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact inverses, physical bindings and same-owner refusal for #746."""
from contextlib import contextmanager
from functools import wraps
import hashlib
import itertools
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

import scaled_float32_contracts as scaled
import full_audit_cleanup_contracts as cleanup
import _full_audit_test_fixtures as fixtures

ROOT = Path(__file__).resolve().parents[2]


class ScaledFloat32LeafControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        baseline = fixtures.common758_leaf_texts(ROOT)
        cls.after = {name: baseline[name] for name in scaled.SOURCE_PATHS}
        cls.before = {name: scaled.predecessor_source(name, value)
                      for name, value in cls.after.items()}

    def test_all_exact_edges_reconstruct_complete_historical_sources(self):
        for name, after in self.after.items():
            before = self.before[name]
            self.assertEqual(scaled.sha(before), scaled.BEFORE_SHA256[name])
            forward = before
            for label, old, new in scaled.EDITS[name]:
                self.assertEqual(forward.count(old), 1, (name, label))
                forward = forward.replace(old, new, 1)
            self.assertEqual(forward, after)

    def test_every_before_after_combination_has_only_its_exact_edges(self):
        for flags in itertools.product((False, True), repeat=len(scaled.SOURCE_PATHS)):
            texts = {name: (self.after if active else self.before)[name]
                     for name, active in zip(scaled.SOURCE_PATHS, flags)}
            self.assertEqual(scaled.verify_sources(texts), tuple(
                name for name, active in zip(scaled.SOURCE_PATHS, flags) if active))

    def test_unknown_comments_line_endings_and_partial_sources_reject(self):
        for name, value in self.after.items():
            for bad in (value + '\n# changed\n', value.replace('\n', '\r\n'),
                        value[:-1], value.replace('from ', 'import ', 1)):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    scaled.verify_sources({name: bad})
        for texts in ({}, {'unknown.mojo': ''}, {scaled.MATH: b'not text'}):
            with self.assertRaises(ValueError): scaled.verify_sources(texts)

    def test_dtype_formula_import_and_extra_statement_mutations_reject(self):
        text = self.after[scaled.MATH]
        for old, new in (
                ('comptime if dtype == DType.float32:', 'if dtype == DType.float32:'),
                ('comptime if dtype == DType.float32:', 'comptime if dtype == DType.float64:'),
                ('exponent + top - 148', 'exponent + top - 149'),
                ('126 << 23', '127 << 23'),
                ('23 - top', '22 - top'),
                ('from std.bit import count_leading_zeros', 'from other import count_leading_zeros'),
                ('    if value != 0 and abs(value) < tiny:', '    value = 0\n    if value != 0 and abs(value) < tiny:')):
            self.assertEqual(text.count(old), 1)
            with self.subTest(new=new), self.assertRaises(ValueError):
                scaled.predecessor_source(scaled.MATH, text.replace(old, new, 1))
        scaled.verify_float64_domain(self.before[scaled.MATH], text)

    def test_apple_inverse_guard_rename_and_host_body_mutations_reject(self):
        text = self.after[scaled.INVERSE]
        for old, new in (
                ('if is_apple_gpu() else', 'if not is_apple_gpu() else'),
                ('else _inverse_exact_cofactors[size]', 'else _inverse_scaled_float32[size]'),
                ('def _inverse_exact_cofactors[', 'def _inverse_cofactors['),
                ('from std.sys.info import is_apple_gpu', 'from other import is_apple_gpu'),
                ('    if determinant == 0:\n        return False, result^',
                 '    if determinant == 1:\n        return False, result^')):
            self.assertEqual(text.count(old), 1, old)
            with self.subTest(new=new), self.assertRaises(ValueError):
                scaled.predecessor_source(scaled.INVERSE, text.replace(old, new, 1))
        scaled.verify_host_inverse_domain(self.before[scaled.INVERSE], text)

    def test_inverse_inventory_cannot_drop_reorder_or_change_a_span(self):
        for name, spans in scaled.EDITS.items():
            label, old, new = spans[0]
            for changed in (spans[:-1], tuple(reversed(spans)),
                            ((label, old + '?', new), *spans[1:])):
                if changed == spans:
                    continue
                with self.subTest(name=name), patch.dict(scaled.EDITS, {name: changed}):
                    with self.assertRaises(ValueError):
                        scaled.predecessor_source(name, self.after[name])

    def test_executed_leaf_code_defaults_and_module_witness_are_bound(self):
        self.assertEqual(cleanup.executing_checker_bindings()[scaled.LEAF],
                         hashlib.sha256((ROOT/scaled.LEAF).read_bytes()).hexdigest())
        with patch.object(scaled, 'verify_sources', lambda values: ()):
            with self.assertRaisesRegex(ValueError, 'executing function changed'):
                cleanup.executing_checker_bindings()
        with patch.object(scaled.verify_sources, '__defaults__', ('changed',)):
            with self.assertRaisesRegex(ValueError, 'defaults changed'):
                cleanup.executing_checker_bindings()
        with patch.object(scaled, '_EXECUTED_MODULE_CODE', compile('pass', scaled.__file__, 'exec')):
            with self.assertRaisesRegex(ValueError, 'module-code witness changed'):
                cleanup.executing_checker_bindings()


class ScaledFloat32PhysicalControls(unittest.TestCase):
    def setUp(self):
        self.root = fixtures.copy_current_root(self, ROOT)

    @contextmanager
    def changed(self, name, value):
        path = self.root/name
        old = path.read_bytes()
        path.write_bytes(value)
        try:
            yield
        finally:
            path.write_bytes(old)

    def test_all_three_owners_admit_current_bytes_without_rewriting_records(self):
        import seed_count_contracts as seed
        import border_parser_contracts as border
        paths = (cleanup.MIGRATION, 'tools/carla_lane_oracle/seed-count-successor.json',
                 'tools/carla_lane_oracle/border-parser-successor.json')
        before = {name: (self.root/name).read_bytes() for name in paths}
        cleanup.verify(self.root, exact=True)
        seed.verify(self.root)
        border.verify(self.root)
        receipt = cleanup.proof_bindings(self.root)
        for name in (*scaled.SOURCE_PATHS, *scaled.TESTS, *scaled.PACKAGE_INPUTS, *scaled.PROVIDER_INPUTS, scaled.LEAF):
            self.assertEqual(receipt[name], hashlib.sha256((self.root/name).read_bytes()).hexdigest())
        self.assertEqual(before, {name: (self.root/name).read_bytes() for name in paths})
        record = cleanup.read_record(self.root)
        for group in ('unchanged_inputs', 'native_dependency_inputs'):
            self.assertEqual(record[group][scaled.MATH], scaled.BEFORE_SHA256[scaled.MATH])

    def test_historical_and_mixed_endpoints_keep_truthful_receipts(self):
        self.root = fixtures.copy_historical_boundary_root(self, ROOT)
        original = {name: (self.root/name).read_bytes() for name in scaled.SOURCE_PATHS}
        try:
            for name in scaled.SOURCE_PATHS:
                (self.root/name).write_text(scaled.predecessor_source(name, original[name].decode()))
            self.assertEqual(cleanup.scaled_float32_edges(self.root), {})
            cleanup.verify(self.root, exact=True)
            for name in scaled.SOURCE_PATHS:
                (self.root/name).write_bytes(original[name])
                receipt = cleanup.scaled_float32_proof_bindings(self.root)
                self.assertEqual(receipt[name], scaled.AFTER_SHA256[name])
                cleanup.verify(self.root, exact=True)
        finally:
            for name, raw in original.items(): (self.root/name).write_bytes(raw)

    def test_constructor_theorem_retains_its_historical_table_and_live_receipt(self):
        # Proof derivation imports its package namespace lazily, after import
        # of the coverage module itself, so retain that namespace for the test.
        self.enterContext(patch.object(sys, 'path', [str(ROOT/'tools'), *sys.path]))
        import coverage_loop_proofs as loops
        expected = dict(loops.CONSTRUCTION_BOUNDARY_SOURCE_SHA256)
        for historical in (False, True):
            with self.subTest(endpoint='historical' if historical else 'current'):
                if historical:
                    self.root = fixtures.copy_historical_boundary_root(self, ROOT)
                    fixtures.write_predecessors(self.root, fixtures.verified_predecessors(self.root))
                rows = loops.construction_boundary_loops(self.root)
                self.assertEqual(len(rows), 1)
                receipt = next(iter(rows.values()))['dependency_sha256']
                for name in (scaled.MATH, scaled.LEAF, *scaled.TESTS, *scaled.PACKAGE_INPUTS, *scaled.PROVIDER_INPUTS):
                    self.assertEqual(receipt[name], hashlib.sha256((self.root/name).read_bytes()).hexdigest())
                self.assertEqual(loops.CONSTRUCTION_BOUNDARY_SOURCE_SHA256, expected)
                self.assertEqual(expected[scaled.MATH], scaled.BEFORE_SHA256[scaled.MATH])
                with self.changed(scaled.MATH, (self.root/scaled.MATH).read_bytes() + b'\n# changed\n'):
                    self.assertEqual(loops.construction_boundary_loops(self.root), {})

    def test_new_witness_leaf_and_package_changes_or_denials_fail(self):
        read = Path.read_bytes
        for name in (*scaled.TESTS, *scaled.PACKAGE_INPUTS, *scaled.PROVIDER_INPUTS, scaled.LEAF):
            with self.subTest(name=name):
                with self.changed(name, read(self.root/name) + b'\n# changed\n'):
                    with self.assertRaises(ValueError): cleanup.scaled_float32_proof_bindings(self.root)
                failure = OSError('scaled correctness input unreadable')
                def denied(path, *args, **kwargs):
                    if path == self.root/name: raise failure
                    return read(path, *args, **kwargs)
                with patch.object(Path, 'read_bytes', denied), self.assertRaises((OSError, ValueError)) as caught:
                    cleanup.scaled_float32_proof_bindings(self.root)
                cause = caught.exception
                while cause.__cause__ is not None:
                    cause = cause.__cause__
                self.assertIs(cause, failure)

    def test_missing_symlinked_and_shadowed_input_refuses(self):
        target = self.root/scaled.NATIVE_TESTS[0]
        raw = target.read_bytes()
        target.unlink()
        try:
            with self.assertRaises((OSError, ValueError)): cleanup.scaled_float32_proof_bindings(self.root)
            target.symlink_to(self.root/scaled.MATH)
            with self.assertRaises(ValueError): cleanup.scaled_float32_proof_bindings(self.root)
        finally:
            if target.is_symlink(): target.unlink()
            target.write_bytes(raw)
        shadow = self.root/'math/scaled_products.mojopkg'
        shadow.write_text('unreviewed compiled package')
        try:
            with self.assertRaisesRegex(ValueError, 'resolver'): cleanup.scaled_float32_proof_bindings(self.root)
        finally:
            shadow.unlink()

    def test_incomplete_and_fabricated_input_views_cannot_admit(self):
        class Fake:
            _executing = {scaled.LEAF: 'untrusted'}
            def raw(self, owner, root, path): return (root/path).read_bytes()
        for view, owner in ((Fake(), object()), (Fake(), None), (None, object())):
            with self.assertRaises(ValueError):
                cleanup.scaled_float32_proof_bindings(self.root, _inputs=view, _input_owner=owner)

    def test_consumed_transient_arithmetic_input_stays_failed_after_restore(self):
        import seed_count_contracts as seed
        import winner_sign_contracts as winner
        original, read = seed._verify_bound_inputs, Path.read_bytes
        injected, caught = [], []
        def transient(path, *args, **kwargs):
            raw = read(path, *args, **kwargs)
            caller = sys._getframe(1)
            if (path == self.root/scaled.MATH and caller.f_globals is vars(seed)
                    and caller.f_code.co_name == '_verify_bound_inputs' and not injected):
                injected.append(True)
                return raw + b'\n# transient consumed source\n'
            return raw
        @wraps(original)
        def catch(root, record, **kwargs):
            try:
                return original(root, record, **kwargs)
            except ValueError as error:
                caught.append(str(error))
                return original(root, record, **kwargs)
        with patch.object(Path, 'read_bytes', transient), patch.object(seed, '_verify_bound_inputs', catch):
            with self.assertRaises(cleanup._OperationCoherenceError): winner.verify(self.root)
        self.assertEqual(injected, [True])
        self.assertTrue(caught)

    def test_historical_owner_final_reread_keeps_python_witness_bound(self):
        self.root = fixtures.copy_historical_boundary_root(self, ROOT)
        import winner_sign_contracts as winner
        original = cleanup.scaled_float32_edges
        name = 'tools/carla_lane_oracle/test_scaled_float32_contracts.py'
        target, injected = self.root/name, []
        raw = target.read_bytes()
        predecessors = fixtures.verified_predecessors(self.root)
        fixtures.write_predecessors(self.root, predecessors)
        @wraps(original)
        def change_after_binding(root, **kwargs):
            result = original(root, **kwargs)
            if not injected:
                target.write_bytes(raw + b'\n# changed after physical binding\n')
                injected.append(True)
            return result
        try:
            with patch.object(cleanup, 'scaled_float32_edges', change_after_binding):
                with self.assertRaises(cleanup._OperationCoherenceError): winner.verify(self.root)
            self.assertEqual(injected, [True])
        finally:
            target.write_bytes(raw)

    def test_borrowed_cache_refusal_is_sticky_after_shadow_restore(self):
        import coverage_invariant_contracts as invariant
        original = cleanup.scaled_float32_proof_bindings
        shadow = self.root/'tests/math.mojopkg'
        caught, retried, owners = [], [], []

        @wraps(original)
        def refuse_then_restore(root, **kwargs):
            view = kwargs.get('_inputs')
            if type(view) is not cleanup._BorrowedCacheInputs or owners:
                return original(root, **kwargs)
            self.assertIsNone(kwargs.get('_operation'))
            operation = view._operation
            self.assertEqual(operation._state, 'active')
            owners.append(operation)
            shadow.write_bytes(b'late borrowed-cache namespace shadow')
            try:
                with self.assertRaises(cleanup._OperationCoherenceError) as first:
                    original(root, **kwargs)
                caught.append(first.exception)
                self.assertTrue(operation._failed)
                self.assertEqual(operation._state, 'invalid')
            finally:
                shadow.unlink()
            with self.assertRaises(cleanup._OperationCoherenceError) as second:
                original(root, **kwargs)
            retried.append(second.exception)
            self.assertEqual(str(second.exception), str(first.exception))
            raise second.exception

        with patch.object(cleanup, 'scaled_float32_proof_bindings', refuse_then_restore):
            with self.assertRaises(ValueError):
                invariant.verify(self.root)
        self.assertEqual(len(owners), 1)
        self.assertEqual(len(caught), 1)
        self.assertEqual(len(retried), 1)
        self.assertFalse(shadow.exists())
        self.assertEqual(owners[0]._state, 'closed')
        self.assertTrue(owners[0]._failed)
        self.assertFalse(owners[0]._scaled_resolver_paths)

    def test_pending_final_sweep_binds_math_python_proof(self):
        self.root = fixtures.copy_historical_boundary_root(self, ROOT)
        import winner_sign_contracts as winner
        fixtures.write_predecessors(self.root, fixtures.verified_predecessors(self.root))
        original = cleanup._InvariantInputs.finish
        name = 'tools/carla_lane_oracle/test_scaled_float32_contracts.py'
        target = self.root/name
        raw = target.read_bytes()
        owners = []

        @wraps(original)
        def finish(operation, root):
            self.assertEqual(operation._state, 'pending')
            self.assertEqual(operation._scaled_resolver_paths, scaled.NATIVE_CLOSURE)
            owners.append(operation)
            target.write_bytes(raw + b'\n# changed immediately before historical final sweep\n')
            return original(operation, root)

        try:
            with patch.object(cleanup._InvariantInputs, 'finish', finish):
                with self.assertRaisesRegex(cleanup._OperationCoherenceError,
                        'supplemental helper changed during historical operation'):
                    winner.verify(self.root)
        finally:
            target.write_bytes(raw)
        self.assertEqual(len(owners), 1)
        self.assertEqual(owners[0]._state, 'closed')
        self.assertTrue(owners[0]._failed)
        self.assertFalse(owners[0]._scaled_resolver_paths)

    def test_pending_final_sweep_refuses_late_native_compiled_shadow(self):
        self.root = fixtures.copy_historical_boundary_root(self, ROOT)
        import winner_sign_contracts as winner
        fixtures.write_predecessors(self.root, fixtures.verified_predecessors(self.root))
        original = cleanup._InvariantInputs.finish
        shadow = self.root/'tests/math.mojopkg'
        owners = []

        @wraps(original)
        def finish(operation, root):
            self.assertEqual(operation._state, 'pending')
            self.assertEqual(operation._scaled_resolver_paths, scaled.NATIVE_CLOSURE)
            owners.append(operation)
            shadow.write_bytes(b'late native compiled shadow')
            return original(operation, root)

        try:
            with patch.object(cleanup._InvariantInputs, 'finish', finish):
                with self.assertRaisesRegex(cleanup._OperationCoherenceError,
                        'scaled native resolver changed during historical operation'):
                    winner.verify(self.root)
        finally:
            if shadow.exists():
                shadow.unlink()
        self.assertEqual(len(owners), 1)
        self.assertEqual(owners[0]._state, 'closed')
        self.assertTrue(owners[0]._failed)
        self.assertFalse(owners[0]._scaled_resolver_paths)

    def test_pending_final_sweep_refuses_late_unrelated_source_census(self):
        self.root = fixtures.copy_historical_boundary_root(self, ROOT)
        import winner_sign_contracts as winner
        fixtures.write_predecessors(self.root, fixtures.verified_predecessors(self.root))
        original = cleanup._InvariantInputs.finish
        target = self.root/'tests/scaled_late_unrelated.mojo'
        owners = []

        @wraps(original)
        def finish(operation, root):
            self.assertEqual(operation._state, 'pending')
            self.assertEqual(operation._scaled_resolver_paths, scaled.NATIVE_CLOSURE)
            self.assertTrue(any(path.startswith('render/')
                                for path in operation._resolver_paths))
            owners.append(operation)
            target.write_bytes(b'# late unrelated source path\n')
            return original(operation, root)

        try:
            with patch.object(cleanup._InvariantInputs, 'finish', finish):
                with self.assertRaisesRegex(cleanup._OperationCoherenceError,
                        'render entry path census changed during historical operation'):
                    winner.verify(self.root)
        finally:
            if target.exists():
                target.unlink()
        self.assertEqual(len(owners), 1)
        self.assertEqual(owners[0]._state, 'closed')
        self.assertTrue(owners[0]._failed)

        self.assertFalse(owners[0]._scaled_resolver_paths)

    def test_pending_math_census_refuses_source_created_after_render_census(self):
        self.root = fixtures.copy_historical_boundary_root(self, ROOT)
        import winner_sign_contracts as winner
        fixtures.write_predecessors(self.root, fixtures.verified_predecessors(self.root))
        cache_key = cleanup._sibling('cache_key')
        original_paths = cache_key.input_paths
        original_finish = cleanup._InvariantInputs.finish
        target = self.root/'tests/scaled_between_censuses.mojo'
        owners = []

        @wraps(original_paths)
        def input_paths(root):
            paths = original_paths(root)
            caller = sys._getframe(1)
            if (caller.f_globals is not vars(cleanup)
                    or caller.f_code is not original_finish.__code__):
                return paths
            operation = caller.f_locals['self']
            self.assertEqual(operation._state, 'pending')
            self.assertEqual(operation._scaled_resolver_paths, scaled.NATIVE_CLOSURE)
            self.assertTrue(any(path.startswith('render/')
                                for path in operation._resolver_paths))
            self.assertFalse(owners)
            self.assertFalse(target.exists())

            def after_real_render_discovery():
                # Yield every real path unchanged. Create the file only after
                # the preserved render census has consumed its original view.
                discovered = set()
                for path in paths:
                    if path.suffix == '.mojo':
                        discovered.add(path.as_posix())
                    yield path
                self.assertEqual(discovered, operation._known)
                owners.append(operation)
                target.write_bytes(b'# source created between final censuses\n')

            return after_real_render_discovery()

        try:
            with patch.object(cache_key, 'input_paths', input_paths):
                with self.assertRaisesRegex(cleanup._OperationCoherenceError,
                        'scaled source path census changed during historical operation'):
                    winner.verify(self.root)
            self.assertTrue(target.is_file())
        finally:
            if target.exists():
                target.unlink()
        self.assertEqual(len(owners), 1)
        self.assertEqual(owners[0]._state, 'closed')
        self.assertTrue(owners[0]._failed)
        self.assertFalse(owners[0]._scaled_resolver_paths)
        self.assertFalse(owners[0]._resolver_paths)
        self.assertFalse(owners[0]._discoveries)



# Append this fragment before the test module's unittest.main() guard.
# These controls use genuine standalone source admission. They do not construct
# an owner, replace a proof result, or grant historical/full-root authority.
from functools import wraps
import tempfile


class ScaledFloat32ResolverControls(unittest.TestCase):
    """The small physical math proof retains all of its resolver obligations."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='scaled-native-proof-')
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.root = self.base / 'root'
        self.root.mkdir()
        self.include = self.base / 'include'
        self.include.mkdir()
        self.paths = tuple(dict.fromkeys((
            *scaled.SOURCE_PATHS, scaled.LEAF, *scaled.PACKAGE_INPUTS,
            *scaled.PROVIDER_INPUTS, *scaled.TESTS,
        )))
        baseline = fixtures.common758_leaf_texts(ROOT)
        self.original = {name: (baseline[name].encode('utf-8') if name in baseline
                         else (ROOT/name).read_bytes()) for name in self.paths}
        witness = 'tools/carla_lane_oracle/test_scaled_float32_contracts.py'
        self.original[witness] = cleanup.qualification_predecessor_bytes(
            witness, self.original[witness])
        self.expected = {
            name: hashlib.sha256(raw).hexdigest()
            for name, raw in self.original.items()
        }
        for name, raw in self.original.items():
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)

    def _proof(self, **kwargs):
        return cleanup.scaled_float32_proof_bindings(self.root, **kwargs)

    def _assert_exact_bindings(self, bindings):
        self.assertEqual(bindings, self.expected)
        self.assertEqual(
            {name for name in bindings if name.endswith('.mojo')},
            scaled.NATIVE_CLOSURE,
        )

    def _existing_case_alias(self, root, relative):
        """Recognize an actual case-folded lookup, never a second entry."""
        target = root / relative
        if not (target.exists() or target.is_symlink()):
            return None
        self.assertEqual(root, self.root)
        names = [name for name in self.paths
                 if name.casefold() == relative.casefold()]
        self.assertEqual(len(names), 1)
        name = names[0]
        self.assertNotEqual(relative, name)
        canonical = root / name
        self.assertFalse(target.is_symlink())
        self.assertTrue(target.samefile(canonical))
        self.assertEqual(
            {path.relative_to(root).as_posix()
             for path in root.rglob('*') if path.is_file()},
            set(self.paths),
        )
        self.assertEqual(target.read_bytes(), self.original[name])
        return name

    @contextmanager
    def _temporary_path(self, root, relative, *, make_parents=True):
        """Reserve a nonexistent path and remove only directories we created."""
        target = root / relative
        self.assertFalse(target.exists() or target.is_symlink())
        created = []
        parent = target.parent
        while not parent.exists():
            created.append(parent)
            parent = parent.parent
        if make_parents:
            target.parent.mkdir(parents=True, exist_ok=True)
        try:
            yield target
        finally:
            if target.exists() or target.is_symlink():
                target.unlink()
            for directory in created:
                if directory.exists():
                    directory.rmdir()

    @contextmanager
    def _extra_file(self, root, relative, raw=b'# unreviewed resolver surface\n'):
        with self._temporary_path(root, relative) as target:
            target.write_bytes(raw)
            yield target

    @contextmanager
    def _at_final_physical_read(self, action):
        """Inject only inside the public proof's final real input read loop."""
        read = Path.read_bytes
        public_code = cleanup.scaled_float32_proof_bindings.__code__
        fired = []

        def late(path, *args, **kwargs):
            raw = read(path, *args, **kwargs)
            if (not fired and path == self.root / scaled.MATH
                    and sys._getframe(1).f_code is public_code):
                fired.append(path)
                action()
            return raw

        with patch.object(Path, 'read_bytes', late):
            yield fired

    def test_exact_partial_root_needs_only_the_math_edge_proof_inputs(self):
        self.assertEqual(scaled.SOURCE_PATHS, (scaled.MATH, scaled.INVERSE))
        self.assertEqual(scaled.NATIVE_TESTS,
                         ('tests/test_scaled_products_subnormal.mojo',
                          'tests/test_matrix_inverse_float32.mojo'))
        self.assertEqual(scaled.NATIVE_CLOSURE, frozenset((
            scaled.MATH, 'math/norm.mojo', 'math/__init__.mojo',
            scaled.INVERSE, 'math/matrix_determinant.mojo',
            'tests/test_scaled_products_subnormal.mojo',
            'tests/test_matrix_inverse_float32.mojo',
        )))
        self.assertEqual(
            {path.relative_to(self.root).as_posix()
             for path in self.root.rglob('*') if path.is_file()},
            set(self.paths),
        )
        self.assertFalse((self.root / cleanup.MIGRATION).exists())
        self._assert_exact_bindings(self._proof())

    def test_legitimate_carla_math_is_accepted_without_entering_native_closure(self):
        name = 'extensions/carla/math.mojo'
        with self._extra_file(self.root, name, (ROOT / name).read_bytes()):
            bindings = self._proof()
        self._assert_exact_bindings(bindings)
        self.assertNotIn(name, bindings)
        self.assertNotIn(name, scaled.NATIVE_CLOSURE)

    def test_default_resolver_keeps_its_original_global_math_namespace_rule(self):
        paths = scaled.NATIVE_CLOSURE
        self.assertTrue(cleanup.resolver_unshadowed(self.root, paths))
        name = 'extensions/carla/math.mojo'
        with self._extra_file(self.root, name, (ROOT / name).read_bytes()):
            self.assertFalse(cleanup.resolver_unshadowed(self.root, paths))
            self.assertTrue(cleanup.resolver_unshadowed(
                self.root, paths, math_entries=frozenset(('.', 'tests'))))
            self.assertTrue(cleanup.resolver_unshadowed(self.root, paths | {name}))
            self._assert_exact_bindings(self._proof())

    def test_invalid_math_lookup_scopes_cannot_relax_the_resolver(self):
        invalid = (
            (), ('.', 'tests'), {'.', 'tests'}, frozenset(),
            frozenset(('tests',)), frozenset(('.', '/tests')),
            frozenset(('.', '../tests')), frozenset(('.', 'tests/..')),
            frozenset(('.', 1)),
        )
        for scope in invalid:
            with self.subTest(scope=scope):
                self.assertFalse(cleanup.resolver_unshadowed(
                    self.root, scaled.NATIVE_CLOSURE, math_entries=scope))

    def test_root_tests_and_include_namespace_alternatives_refuse(self):
        # Distinct directory entries compete. On a case-insensitive directory,
        # a spelling of the existing canonical inode does not add a competitor.
        root_variants = (
            'math.mojo', 'Math.mojo', 'math.MOJO', 'math.mojopkg',
            'math.mojoc', 'math.so', 'math.py', 'math.🔥',
            'Math/__init__.mojo',
        )
        entry_variants = (
            'math.mojo', 'Math.mojo', 'math.mojopkg', 'math.mojoc',
            'math.so', 'math.py', 'math.🔥', 'math/__init__.mojo',
            'Math/__init__.mojo',
        )
        cases = [(self.root, relative, ()) for relative in root_variants]
        cases += [(self.root, 'tests/' + relative, ())
                  for relative in entry_variants]
        cases += [(self.include, relative, (self.include,))
                  for relative in root_variants]
        cases += [(self.include, 'tests/' + relative, (self.include,))
                  for relative in entry_variants]
        for location, relative, include_roots in cases:
            with self.subTest(location=location.name, path=relative):
                alias = self._existing_case_alias(location, relative)
                if alias is not None:
                    self._assert_exact_bindings(self._proof(include_roots=include_roots))
                    self.assertEqual((location / relative).read_bytes(), self.original[alias])
                else:
                    with self._extra_file(location, relative):
                        with self.assertRaises(ValueError):
                            self._proof(include_roots=include_roots)

    def test_exact_provider_and_package_coordinates_stay_protected(self):
        variants = (
            'math/Scaled_Products.mojo', 'math/scaled_products.mojopkg',
            'math/scaled_products/__init__.mojo', 'math/Norm.mojo',
            'math/norm.so', 'math/norm/__init__.mojo', 'math/__init__.py',
            'Math/scaled_products.mojo', 'Tests/test_scaled_products_subnormal.mojo',
            'tests/test_scaled_products_subnormal.mojopkg',
        )
        for location, include_roots in ((self.root, ()),
                                        (self.include, (self.include,))):
            for relative in variants:
                with self.subTest(location=location.name, path=relative):
                    alias = self._existing_case_alias(location, relative)
                    if alias is not None:
                        self._assert_exact_bindings(self._proof(include_roots=include_roots))
                        self.assertEqual((location / relative).read_bytes(), self.original[alias])
                    else:
                        with self._extra_file(location, relative):
                            with self.assertRaises(ValueError):
                                self._proof(include_roots=include_roots)

    def test_math_scope_does_not_relax_std_or_other_protected_namespaces(self):
        for location, include_roots in ((self.root, ()),
                                        (self.include, (self.include,))):
            for relative in ('unrelated/std.mojo', 'unrelated/Std.mojopkg',
                             'unrelated/std/__init__.mojo', 'unrelated/tests.mojo'):
                with self.subTest(location=location.name, path=relative):
                    with self._extra_file(location, relative):
                        with self.assertRaisesRegex(ValueError, 'resolver'):
                            self._proof(include_roots=include_roots)

    def test_include_native_files_and_existing_coverage_origin_allowance(self):
        for name in sorted(scaled.NATIVE_CLOSURE):
            target = self.include / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(self.original[name])
            (self.include / (name + '.cov-origin')).write_text('source origin\n')
        self._assert_exact_bindings(self._proof(include_roots=(self.include,)))

    def test_root_and_include_root_aliases_and_aliased_ancestors_refuse(self):
        ancestor = self.base / 'ancestor-alias'
        ancestor.symlink_to(self.base, target_is_directory=True)
        root_alias = self.base / 'root-alias'
        root_alias.symlink_to(self.root, target_is_directory=True)
        include_alias = self.base / 'include-alias'
        include_alias.symlink_to(self.include, target_is_directory=True)
        for root in (root_alias, ancestor / 'root'):
            with self.subTest(root=str(root)), self.assertRaises((OSError, ValueError)):
                cleanup.scaled_float32_proof_bindings(root)
        for include in (include_alias, ancestor / 'include'):
            with self.subTest(include=str(include)), self.assertRaises((OSError, ValueError)):
                self._proof(include_roots=(include,))

    def test_each_input_and_its_package_ancestor_must_be_physical(self):
        saved = self.base / 'saved-input'
        for name in self.paths:
            target = self.root / name
            target.rename(saved)
            try:
                target.symlink_to(saved)
                with self.subTest(path=name), self.assertRaises((OSError, ValueError)):
                    self._proof()
            finally:
                target.unlink()
                saved.rename(target)
        for relative in ('math', 'tests', 'tools/carla_lane_oracle', 'docs'):
            target = self.root / relative
            # No proof-document path spelling is assumed except its real parent.
            if not target.is_dir():
                continue
            target.rename(saved)
            try:
                target.symlink_to(saved, target_is_directory=True)
                with self.subTest(ancestor=relative), self.assertRaises((OSError, ValueError)):
                    self._proof()
            finally:
                target.unlink()
                saved.rename(target)

    def test_include_package_ancestor_alias_refuses(self):
        outside = self.base / 'external-math'
        outside.mkdir()
        (outside / '__init__.mojo').write_bytes(self.original['math/__init__.mojo'])
        (self.include / 'math').symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'resolver'):
            self._proof(include_roots=(self.include,))

    def test_every_missing_and_modified_proof_input_refuses(self):
        for name in self.paths:
            target = self.root / name
            original = self.original[name]
            for missing in (True, False):
                with self.subTest(path=name, missing=missing):
                    try:
                        if missing:
                            target.unlink()
                        else:
                            target.write_bytes(original + b'\n# unreviewed input\n')
                        with self.assertRaises((OSError, ValueError)):
                            self._proof()
                    finally:
                        target.write_bytes(original)

    def test_every_unreadable_proof_input_refuses(self):
        read = Path.read_bytes
        for name in self.paths:
            target = self.root / name
            attempted = []

            def denied(path, *args, **kwargs):
                if path == target:
                    attempted.append(path)
                    raise OSError('scaled proof input read denied')
                return read(path, *args, **kwargs)

            with self.subTest(path=name), patch.object(Path, 'read_bytes', denied):
                with self.assertRaises((OSError, ValueError)):
                    self._proof()
            self.assertTrue(attempted)

    def test_actual_executing_leaf_source_read_failure_refuses(self):
        read = Path.read_bytes
        target = Path(scaled.__file__).resolve()
        attempted = []

        def denied(path, *args, **kwargs):
            if path == target:
                attempted.append(path)
                raise OSError('actual executing leaf read denied')
            return read(path, *args, **kwargs)

        with patch.object(Path, 'read_bytes', denied), self.assertRaises((OSError, ValueError)):
            self._proof()
        self.assertTrue(attempted)

    def test_transient_consumed_input_changes_are_not_hidden_by_restoration(self):
        read = Path.read_bytes
        for name in self.paths:
            target = self.root / name
            seen = []

            def transient(path, *args, **kwargs):
                raw = read(path, *args, **kwargs)
                if path == target:
                    seen.append(path)
                    if len(seen) == 2:
                        return raw + b'\n# transient consumed bytes\n'
                return raw

            with self.subTest(path=name), patch.object(Path, 'read_bytes', transient):
                with self.assertRaisesRegex(ValueError, 'scaled input changed after consumption'):
                    self._proof()
            self.assertEqual(len(seen), 2)
            self.assertEqual(read(target), self.original[name])

    def test_late_root_tests_and_include_shadows_fail_the_final_resolver(self):
        variants = ('math.mojo', 'Math.mojo', 'math.mojopkg',
                    'math.🔥', 'Math/__init__.mojo')
        cases = [(self.root, relative, ()) for relative in variants]
        cases += [(self.root, 'tests/' + relative, ()) for relative in variants]
        cases += [(self.root, 'tests/math/__init__.mojo', ())]
        cases += [(self.include, relative, (self.include,))
                  for relative in (*variants, 'tests/math.mojo',
                                   'tests/math/__init__.mojo')]
        for location, relative, includes in cases:
            with self.subTest(location=location.name, path=relative):
                alias = self._existing_case_alias(location, relative)
                if alias is not None:
                    target = location / relative
                    canonical = location / alias
                    original = self.original[alias]
                    try:
                        def change_canonical_input():
                            self.assertTrue(target.samefile(canonical))
                            target.write_bytes(b'# changed through a case alias during final read\n')
                        with self._at_final_physical_read(change_canonical_input) as fired:
                            with self.assertRaises(cleanup.ContractError) as raised:
                                self._proof(include_roots=includes)
                        self.assertIs(type(raised.exception), cleanup.ContractError)
                        self.assertEqual(str(raised.exception),
                            'full-audit cleanup successor: scaled input changed before receipt: ' + alias)
                        self.assertEqual(len(fired), 1)
                    finally:
                        # The alternate spelling is the canonical file itself;
                        # never send it through the new-path unlink cleanup.
                        canonical.write_bytes(original)
                    self.assertTrue(target.samefile(canonical))
                    self.assertEqual(target.read_bytes(), original)
                    self._assert_exact_bindings(self._proof(include_roots=includes))
                    continue
                with self._temporary_path(location, relative, make_parents=False) as target:
                    def create_shadow():
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(b'# created during the final input read\n')
                    with self._at_final_physical_read(create_shadow) as fired:
                        with self.assertRaisesRegex(ValueError, 'scaled final resolver surface changed'):
                            self._proof(include_roots=includes)
                    self.assertEqual(len(fired), 1)

    def test_late_unrelated_source_path_fails_the_final_fresh_census(self):
        with self._temporary_path(self.root, 'unrelated/late_entry.mojo',
                                  make_parents=False) as target:
            def create_source():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('def main():\n    pass\n')
            with self._at_final_physical_read(create_source) as fired:
                with self.assertRaisesRegex(ValueError, 'scaled source path census changed before receipt'):
                    self._proof()
            self.assertEqual(len(fired), 1)

    def test_late_root_include_and_package_aliases_cannot_survive_final_reads(self):
        include_package = self.include / 'math'
        include_package.mkdir()
        (include_package / '__init__.mojo').write_bytes(self.original['math/__init__.mojo'])
        targets = (self.root, self.root / 'math', self.root / 'tests',
                   self.include, include_package)
        for target in targets:
            saved = self.base / 'late-aliased-directory'

            def substitute_alias():
                target.rename(saved)
                target.symlink_to(saved, target_is_directory=True)

            fired = []
            try:
                with self.subTest(path=str(target)):
                    with self._at_final_physical_read(substitute_alias) as fired:
                        with self.assertRaises(ValueError):
                            self._proof(include_roots=(self.include,))
                    self.assertEqual(len(fired), 1)
            finally:
                if saved.exists():
                    target.unlink()
                    saved.rename(target)

    def test_equal_string_subclass_census_duplicates_refuse_before_deduplication(self):
        inputs = cleanup._sibling('cache_key')
        discover = inputs.input_paths

        class TypedText(str):
            pass

        class TypedPath(type(Path())):
            def as_posix(self):
                return TypedText(super().as_posix())

        alias = TypedPath(scaled.MATH)
        self.assertEqual(alias.as_posix(), scaled.MATH)
        self.assertIsNot(type(alias.as_posix()), str)
        # Visit all three genuine discoveries. In each case the builtin string
        # already appeared, so an unchecked set comprehension would hide this.
        for poisoned_discovery in (1, 2, 3):
            visits = []

            @wraps(discover)
            def typed_duplicate(root):
                visits.append(Path(root))
                yield from discover(root)
                if len(visits) == poisoned_discovery:
                    yield alias

            with self.subTest(discovery=poisoned_discovery):
                with patch.object(inputs, 'input_paths', typed_duplicate):
                    with self.assertRaisesRegex(ValueError, 'invalid scaled source path census item'):
                        self._proof()
                self.assertEqual(len(visits), poisoned_discovery)

    def test_equal_bytes_subclasses_refuse_at_each_final_physical_read(self):
        read = Path.read_bytes
        public_code = cleanup.scaled_float32_proof_bindings.__code__

        class TypedBytes(bytes):
            pass

        for name in self.paths:
            target = self.root / name
            injected = []

            def typed_read(path, *args, **kwargs):
                raw = read(path, *args, **kwargs)
                if path == target and sys._getframe(1).f_code is public_code:
                    injected.append(path)
                    return TypedBytes(raw)
                return raw

            with self.subTest(path=name), patch.object(Path, 'read_bytes', typed_read):
                with self.assertRaisesRegex(ValueError, 'scaled input changed before receipt'):
                    self._proof()
            self.assertEqual(len(injected), 1)
            self.assertEqual(read(target), self.original[name])

    def test_generator_include_roots_are_rechecked_after_the_final_reads(self):
        resolver = cleanup.resolver_unshadowed
        checked, yielded = [], []

        def include_locations():
            yielded.append(self.include)
            yield self.include

        @wraps(resolver)
        def inspect_resolver(root, paths, *, render_entries=None, math_entries=None):
            checked.append(Path(root))
            return resolver(root, paths, render_entries=render_entries,
                            math_entries=math_entries)

        with patch.object(cleanup, 'resolver_unshadowed', inspect_resolver):
            self._assert_exact_bindings(self._proof(include_roots=include_locations()))
        self.assertEqual(yielded, [self.include])
        self.assertEqual(checked, [self.root, self.include, self.root, self.include])

        yielded.clear()
        with self._temporary_path(self.include, 'tests/math.mojo',
                                  make_parents=False) as target:
            def create_shadow():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b'# late generator-supplied include shadow\n')
            with self._at_final_physical_read(create_shadow) as fired:
                with self.assertRaisesRegex(ValueError, 'scaled final resolver surface changed'):
                    self._proof(include_roots=include_locations())
            self.assertEqual(len(fired), 1)
            self.assertEqual(yielded, [self.include])

    def test_every_proof_input_is_physically_reread_before_receipt(self):
        read = Path.read_bytes
        public_code = cleanup.scaled_float32_proof_bindings.__code__
        for name in self.paths:
            target = self.root / name
            injected = []

            def changed(path, *args, **kwargs):
                if path == target and sys._getframe(1).f_code is public_code:
                    injected.append(path)
                    path.write_bytes(self.original[name] + b'\n# changed before final receipt\n')
                return read(path, *args, **kwargs)

            try:
                with self.subTest(path=name), patch.object(Path, 'read_bytes', changed):
                    with self.assertRaisesRegex(ValueError, 'scaled input changed before receipt'):
                        self._proof()
                self.assertEqual(len(injected), 1)
            finally:
                target.write_bytes(self.original[name])

    def test_actual_executing_leaf_is_reread_after_physical_proof_inputs(self):
        read = Path.read_bytes
        target = Path(scaled.__file__).resolve()
        seen = []

        def transient(path, *args, **kwargs):
            raw = read(path, *args, **kwargs)
            if path == target:
                seen.append(path)
                if len(seen) == 2:
                    return raw + b'\n# changed executing leaf at final check\n'
            return raw

        with patch.object(Path, 'read_bytes', transient):
            with self.assertRaisesRegex(ValueError, 'executing checker bytes changed'):
                self._proof()
        self.assertEqual(len(seen), 2)

    def test_native_context_comes_from_the_actual_witness_main(self):
        affected = cleanup._sibling('affected')
        witness = scaled.NATIVE_TESTS[0]
        text = self.original[witness].decode('utf-8')
        self.assertEqual(affected.entry_directories({witness: text}), ['tests'])
        self.assertEqual(text.count('def main('), 1)
        without_main = text.replace('def main(', 'def no_longer_an_entry(', 1)
        self.assertEqual(affected.entry_directories({witness: without_main}), [])
        seen = []
        original = affected.entry_directories

        witnesses = {name: self.original[name].decode('utf-8') for name in scaled.NATIVE_TESTS}

        @wraps(original)
        def inspect_entry_sources(sources):
            self.assertEqual(sources, witnesses)
            result = original(sources)
            seen.append(tuple(result))
            return result

        with patch.object(affected, 'entry_directories', inspect_entry_sources):
            self._assert_exact_bindings(self._proof())
        self.assertEqual(seen, [('tests',)])

    def test_unrelated_source_bytes_and_entries_are_not_consumed(self):
        # This is a native-witness receipt. It makes no claim that this unrelated
        # production entry and its local math competitor resolve equivalently.
        unrelated = {
            'extensions/carla/math.mojo': (ROOT / 'extensions/carla/math.mojo').read_bytes(),
            'unrelated/main.mojo': b'from math.scaled_products import _split\n\ndef main():\n    pass\n',
            'unrelated/math.mojo': b'# unrelated entry-local math provider\n',
            'unrelated/opaque.mojo': b'\xff\xfe not decoded by this proof\n',
        }
        for name, raw in unrelated.items():
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
        affected = cleanup._sibling('affected')
        inputs = cleanup._sibling('cache_key')
        open_file = Path.open
        read = Path.read_bytes
        classify = affected.entry_directories
        resolve = affected.resolve
        discover = inputs.input_paths
        opened, reads, final_reads, entry_calls, resolve_calls, discoveries = [], [], [], [], [], []
        public_code = cleanup.scaled_float32_proof_bindings.__code__

        def physical_open(path, *args, **kwargs):
            mode = args[0] if args else kwargs.get('mode', 'r')
            if ('r' in mode or '+' in mode) and self.root in path.parents:
                relative = path.relative_to(self.root).as_posix()
                self.assertIn(relative, self.paths, 'unrelated source bytes were opened')
                opened.append(relative)
            return open_file(path, *args, **kwargs)

        def physical_read(path, *args, **kwargs):
            if self.root in path.parents:
                relative = path.relative_to(self.root).as_posix()
                self.assertIn(relative, self.paths, 'unrelated source bytes were read')
                reads.append(relative)
                if sys._getframe(1).f_code is public_code:
                    final_reads.append(relative)
            return read(path, *args, **kwargs)

        @wraps(classify)
        def native_entries(sources):
            self.assertEqual(set(sources), set(scaled.NATIVE_TESTS))
            for name, text in sources.items():
                self.assertEqual(text, self.original[name].decode('utf-8'))
            entry_calls.append(dict(sources))
            return classify(sources)

        @wraps(resolve)
        def native_resolve(name, importer, known, entries=None):
            self.assertEqual(tuple(entries), ('tests',))
            self.assertIn(importer, scaled.NATIVE_CLOSURE)
            self.assertTrue(set(unrelated) <= known)
            resolve_calls.append((name, importer, tuple(entries)))
            return resolve(name, importer, known, entries=entries)

        @wraps(discover)
        def fresh_discovery(root):
            discoveries.append(Path(root))
            yield from discover(root)

        with patch.object(Path, 'open', physical_open), \
                patch.object(Path, 'read_bytes', physical_read), \
                patch.object(affected, 'entry_directories', native_entries), \
                patch.object(affected, 'resolve', native_resolve), \
                patch.object(inputs, 'input_paths', fresh_discovery):
            self._assert_exact_bindings(self._proof())
        self.assertEqual(set(opened), set(self.paths))
        self.assertEqual(set(reads), set(self.paths))
        self.assertEqual(set(final_reads), set(self.paths))
        self.assertEqual(len(final_reads), len(self.paths))
        self.assertTrue(all(reads.count(name) >= 3 for name in self.paths))
        self.assertEqual(len(entry_calls), 1)
        self.assertTrue(resolve_calls)
        self.assertEqual(discoveries, [self.root, self.root, self.root])


if __name__ == '__main__':
    unittest.main()
