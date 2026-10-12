#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Current physical #333 owner and resolver regression controls.

This suite intentionally uses the real typed root, never a historical inverse.
Each operation captures and verifies anew. A module-lifetime physical fixture
reduces copying only; no admission result survives between operations.
"""
from contextlib import contextmanager
from functools import wraps
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import _full_audit_test_fixtures as fixtures
import check_runtime_support as runtime
import full_audit_cleanup_contracts as audit
import typed_boundary_contracts as typed

ROOT = Path(__file__).resolve().parents[2]


class TypedNamespaceResolution(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(dir=Path(tempfile.gettempdir()).resolve())
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.paths = {'geometries/shape.mojo', 'extensions/carla/polynomial.mojo'}
        for name in self.paths:
            path = self.root/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('# reviewed model input\n')
        self.entries = ['tests', 'examples']
        self.options = audit._render_lookup_args(self.paths, self.entries)

    @contextmanager
    def added(self, name):
        path = self.root/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('# unreviewed namespace candidate\n')
        try:
            yield path
        finally:
            path.unlink()

    def test_assets_directory_is_not_a_compiled_lookup_root(self):
        (self.root/'assets/geometries').mkdir(parents=True)
        self.assertFalse(audit.resolver_unshadowed(self.root, self.paths))
        self.assertTrue(audit.resolver_unshadowed(self.root, self.paths, **self.options))

    def test_historical_namespace_policy_is_not_narrowed(self):
        with self.added('assets/extensions.mojo'):
            self.assertFalse(audit.resolver_unshadowed(self.root, self.paths, **self.options))

    def test_new_family_refuses_every_actual_entry_and_package_prefix(self):
        for name in ('geometries.mojo', 'tests/geometries.mojopkg',
                     'examples/geometries/__init__.mojo',
                     'geometries/shape/__init__.mojo', 'geometries/shape.mojopkg'):
            with self.subTest(path=name), self.added(name):
                self.assertFalse(audit.resolver_unshadowed(self.root, self.paths, **self.options))

    def test_library_imports_do_not_add_the_importer_directory_to_search(self):
        affected = audit._sibling('affected')
        known = {*self.paths, 'assets/geometries/shape.mojo',
                 'library/geometries/shape.mojo', 'examples/geometries/shape.mojo'}
        # A qualified import from a library still resolves in its compiled
        # entry directory and -I root, not that library's parent directory.
        self.assertEqual(set(affected.resolve('geometries.shape',
            'library/reader.mojo', known, entries=self.entries)),
            {'geometries/shape.mojo', 'examples/geometries/shape.mojo'})
        self.assertIn('library/geometries/shape.mojo', affected.resolve(
            'geometries.shape', 'library/reader.mojo', known, entries=['library']))
        self.assertIn('assets/geometries/shape.mojo', affected.resolve(
            'assets.geometries.shape', 'library/reader.mojo', known, entries=self.entries))

    def test_new_entry_root_does_not_inherit_old_exclusion(self):
        with self.added('assets/geometries.mojo'):
            self.assertTrue(audit.resolver_unshadowed(self.root, self.paths, **self.options))
            new = audit._render_lookup_args(self.paths, [*self.entries, 'assets'])
            self.assertFalse(audit.resolver_unshadowed(self.root, self.paths, **new))

    def test_supplied_checker_parent_symlink_is_not_a_regular_receipt_image(self):
        actual = self.root/'actual-tools'
        actual.mkdir()
        (self.root/'tools').symlink_to(actual, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink input: tools/carla_lane_oracle/full_audit_cleanup_contracts.py'):
            audit.executing_checker_bindings(self.root)


class TypedCurrentOwnedOperation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        owner = type('FixtureOwner', (), {'addCleanup': staticmethod(cls.addClassCleanup)})()
        cls.root = fixtures.copy_current_root(owner, ROOT)

    def test_translated_method_projection_requires_current_map_and_deviation_leaf(self):
        import ast
        import hashlib
        import json
        import re
        runner = ROOT/'tools/carla_lane_oracle/translated_parameter_resolution.py'
        tree = ast.parse(runner.read_text())
        names = {'_current_bytes', '_historical_text', '_finish_current_graph', 'method_bytes'}
        functions = [node for node in tree.body if isinstance(node, ast.FunctionDef)
                     and node.name in names]
        self.assertEqual({node.name for node in functions}, names)
        bindings = audit.proof_bindings(self.root)
        namespace = {'SOURCE': self.root, '_CURRENT_BINDINGS': bindings,
                     '_OBSERVED': {}, 'hashlib': hashlib, 're': re,
                     'full_audit': audit, 'typed_boundary': typed}
        exec(compile(ast.Module(body=functions, type_ignores=[]), str(runner), 'exec'), namespace)
        pins = json.loads((self.root/'tools/carla_lane_oracle/translated-parameter-source.json').read_text())
        self.assertEqual(len(pins['methods']), 21)
        for item in pins['methods']:
            actual = namespace['method_bytes'](item['path'], item['name'])
            self.assertEqual(hashlib.sha256(actual).hexdigest(), item['sha256'])
        namespace['_finish_current_graph']()
        map_name = 'extensions/carla/map.mojo'
        leaf_name = 'tools/carla_lane_oracle/map_deviation_contracts.py'
        for name in (map_name, leaf_name):
            target = self.root/name
            raw = target.read_bytes()
            self.assertEqual(bindings[name], hashlib.sha256(raw).hexdigest())
            marker = b'                certificate[0],'
            if name == map_name:
                self.assertEqual(raw.count(marker), 1)
                changed = raw.replace(marker, b'                certificate[0] + 1.0,', 1)
            else:
                changed = raw + b'\n# unreviewed deviation leaf\n'
            try:
                target.write_bytes(changed)
                with self.subTest(input=name), self.assertRaises(ValueError):
                    audit.proof_bindings(self.root)
                with self.subTest(consumed=name), self.assertRaisesRegex(
                        ValueError, 'Current fixture input changed'):
                    if name == map_name:
                        namespace['method_bytes'](map_name, '_subdivide_segment')
                    else:
                        namespace['_finish_current_graph']()
            finally:
                target.write_bytes(raw)

    @contextmanager
    def after_last_consumer(self, action):
        original = runtime.sum2_contracts.verify
        fired = []
        @wraps(original)
        def verify(root, *, _operation=None):
            result = original(root, _operation=_operation)
            self.assertIsNotNone(_operation)
            self.assertEqual(_operation._state, 'active')
            action(_operation)
            fired.append(True)
            return result
        with patch.object(runtime.sum2_contracts, 'verify', verify):
            yield fired

    def test_current_public_supplied_views_match_raw_before_projection(self):
        import seed_count_contracts as seed
        import rounded_line_singleton_contracts as singleton
        import source_contracts as source
        map_path = self.root/seed.MODULE
        current = map_path.read_text()
        historical = typed.historical_source(seed.MODULE, current)
        # A stale historical supplied view must fail before invoking the old
        # semantic family. This tests the physical current root, not a mock root.
        with patch.object(seed, 'verify', side_effect=AssertionError('semantic family reached')):
            with self.assertRaisesRegex(ValueError, 'unreviewed supplied Map source'):
                seed.reviewed_text(self.root, seed.MODULE, historical)
        # Isolate the public supplied-view seam; complete typed admission still
        # executes physically. Full family semantics are exercised by the
        # independent aggregate current-owner positive above.
        with patch.object(seed, 'verify', return_value={'edge': 'checked by aggregate control'}):
            plain = seed.reviewed_text(self.root, seed.MODULE, current)
            commented = seed.reviewed_text(self.root, seed.MODULE, current + '\n# supplied comment\n')
        self.assertEqual(plain, commented)
        lane = self.root/'extensions/carla/lane_refinement.mojo'
        physical_lane = lane.read_text()
        old_lane = typed.historical_source('extensions/carla/lane_refinement.mojo', physical_lane)
        original = Path.read_text
        def supplied(path, *args, **kwargs):
            return old_lane if path == lane else original(path, *args, **kwargs)
        with patch.object(Path, 'read_text', supplied):
            with self.assertRaisesRegex(ValueError, 'consumer lane source text/bytes disagree'):
                singleton._lane_text(self.root)
        def commented_lane(path, *args, **kwargs):
            text = original(path, *args, **kwargs)
            return text + '\n# supplied comment\n' if path == lane else text
        with patch.object(Path, 'read_text', commented_lane):
            result = singleton._lane_text(self.root)
        self.assertEqual(source.token_sha256(result), source.token_sha256(old_lane))

    def test_current_multi_source_comments_use_canonical_physical_projection(self):
        texts = {path: (self.root/path).read_text() for path in audit.SOURCE_PATHS}
        plain = audit.reviewed_sources(self.root, texts)
        commented = audit.reviewed_sources(self.root, {
            path: text + '\n# supplied comment\n' for path, text in texts.items()})
        self.assertEqual(plain, commented)
        stale = dict(texts)
        path = audit.SOURCE_PATHS[0]
        stale[path] = typed.historical_source(path, texts[path])
        with self.assertRaisesRegex(ValueError, 'supplied successor source differs from physical input'):
            audit.reviewed_sources(self.root, stale)

    def test_supplied_capture_is_joined_to_the_actual_admission_image(self):
        import sys
        texts = {path: (self.root/path).read_text() for path in audit.SOURCE_PATHS}
        name = audit.SOURCE_PATHS[0]
        historical = typed.historical_source(name, texts[name]).encode()
        texts[name] = historical.decode()
        target = self.root/name
        original = Path.read_bytes
        def old_outside_gate(path, *args, **kwargs):
            if path == target and sys._getframe(1).f_code is audit.reviewed_sources.__code__:
                return historical
            return original(path, *args, **kwargs)
        with patch.object(Path, 'read_bytes', old_outside_gate):
            with self.assertRaisesRegex(ValueError, 'supplied source observation changed before admission'):
                audit.reviewed_sources(self.root, texts)

    def test_public_center_view_keeps_current_comments_and_refuses_stale_tokens(self):
        name = audit.SOURCE_PATHS[2]
        current = (self.root/name).read_text()
        historical = typed.historical_source(name, current)
        with patch.object(audit, 'verify', side_effect=AssertionError('admission reached')):
            with self.assertRaisesRegex(ValueError, 'unreviewed supplied center source'):
                audit.reviewed_lane_before_center_text(self.root, historical)
        plain = audit.reviewed_lane_before_center_text(self.root)
        self.assertEqual(audit.reviewed_lane_before_center_text(
            self.root, current + '\n# supplied comment\n'), plain)

    def test_public_station_receipt_requires_the_complete_current_cubic_graph(self):
        baseline = audit.station_proof_bindings(self.root)
        name = 'extensions/carla/polynomial.mojo'
        path = self.root/name
        original = path.read_bytes()
        self.assertEqual(baseline[name], typed.sha(original))
        try:
            path.write_bytes(original + b'\n# invalid current cubic graph\n')
            with self.assertRaises(ValueError):
                audit.station_proof_bindings(self.root)
        finally:
            path.write_bytes(original)

    def test_unowned_projection_final_read_cannot_swap_to_historical_bytes(self):
        import seed_count_contracts as seed
        import sys
        target = self.root/seed.MODULE
        current = target.read_bytes()
        historical = typed.historical_source(seed.MODULE, current.decode()).encode()
        original = Path.read_bytes
        reads = []
        def changed_final(path, *args, **kwargs):
            if path == target and sys._getframe(1).f_code is seed.historical_source.__code__:
                reads.append(path)
                return historical if len(reads) == 2 else current
            return original(path, *args, **kwargs)
        with patch.object(Path, 'read_bytes', changed_final), patch.object(
                seed, 'verify', return_value={'edge': 'checked by aggregate control'}):
            with self.assertRaisesRegex(ValueError, 'Map changed during reconstruction'):
                seed.historical_source(self.root)
        self.assertEqual(len(reads), 2)

    def test_current_owner_reports_actual_sources_and_explicit_chain(self):
        result = runtime.verify(self.root)
        self.assertEqual(result['status'], 'PASS')
        edges = result['typed_boundary_successors']
        self.assertEqual(set(edges), set(typed.SOURCE_PATHS))
        for path, edge in edges.items():
            self.assertEqual(edge['after_sha256'], typed.sha((self.root/path).read_bytes()))
        self.assertIn('conditioned_graph', edges['extensions/carla/polynomial.mojo'])

    def test_late_native_witness_and_provider_mutations_are_refused(self):
        for name in ('tests/test_carla_conditioned_polynomial.mojo',
                     'extensions/carla/quantity_boundary.mojo', 'units/si.mojo'):
            path = self.root/name
            before = path.read_bytes()
            try:
                with self.subTest(path=name), self.after_last_consumer(
                        lambda owner: path.write_bytes(before + b'\n# late edit\n')) as fired:
                    with self.assertRaises(ValueError):
                        runtime.verify(self.root)
                self.assertEqual(fired, [True])
            finally:
                path.write_bytes(before)

    def test_late_package_entry_and_compiled_namespace_additions_are_refused(self):
        for name, payload in (
                ('tests/geometries.mojopkg', b'compiled shadow'),
                ('geometries/shape/__init__.mojo', b'# new package\n'),
                ('assets/new_entry.mojo', b'def main():\n    pass\n')):
            path = self.root/name
            parent_existed = path.parent.exists()
            path.parent.mkdir(parents=True, exist_ok=True)
            try:
                with self.subTest(path=name), self.after_last_consumer(
                        lambda owner: path.write_bytes(payload)) as fired:
                    with self.assertRaises(ValueError):
                        runtime.verify(self.root)
                self.assertEqual(fired, [True])
            finally:
                path.unlink(missing_ok=True)
                if not parent_existed:
                    path.parent.rmdir()

    def test_late_symlink_of_bound_native_input_is_refused(self):
        path = self.root/'tests/test_carla_conditioned_polynomial.mojo'
        before = path.read_bytes()
        other = self.root/'bound-native-copy.txt'
        other.write_bytes(before)
        def replace(owner):
            path.unlink()
            path.symlink_to(other)
        try:
            with self.after_last_consumer(replace) as fired, self.assertRaises(ValueError):
                runtime.verify(self.root)
            self.assertEqual(fired, [True])
        finally:
            path.unlink(missing_ok=True)
            path.write_bytes(before)
            other.unlink()

    def test_late_authority_namespace_mutation_is_refused(self):
        previous = typed.BINDING_INPUTS
        try:
            def replace(owner):
                typed.BINDING_INPUTS = {**previous, 'unreviewed.txt': '0'*64}
            with self.after_last_consumer(replace) as fired, self.assertRaises(ValueError):
                runtime.verify(self.root)
            self.assertEqual(fired, [True])
        finally:
            typed.BINDING_INPUTS = previous

    def test_caught_observation_failure_remains_sticky(self):
        path = 'extensions/carla/polynomial.mojo'
        def fail_and_catch(owner):
            try:
                audit._observe_bytes(self.root, path, b'changed after capture', _operation=owner)
            except ValueError:
                pass
        with self.after_last_consumer(fail_and_catch) as fired, self.assertRaises(ValueError):
            runtime.verify(self.root)
        self.assertEqual(fired, [True])


if __name__ == '__main__':
    unittest.main()
