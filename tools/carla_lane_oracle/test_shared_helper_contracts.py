# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact extraction, physical helper closure and truthful receipt controls."""
from contextlib import contextmanager
import ast
import hashlib
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

import shared_helper_contracts as helpers
import full_audit_cleanup_contracts as cleanup
import _full_audit_test_fixtures as fixtures

ROOT = Path(__file__).resolve().parents[2]
LEAF = 'tools/carla_lane_oracle/shared_helper_contracts.py'
DISTANCE = 'extensions/carla/curve_distance.mojo'
XML = 'loaders/xml.mojo'
UTF8 = 'loaders/utf8.mojo'


class SharedHelperLeafControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        baseline = fixtures.common758_leaf_texts(ROOT)
        cls.texts = {path: baseline[path]
                     for path in (*helpers.SOURCE_PATHS, *helpers.PROVIDERS)}

    def test_each_exact_inverse_recovers_the_complete_original_bytes(self):
        self.assertEqual(helpers.verify_correspondence(self.texts), helpers.SOURCE_PATHS)
        for path in helpers.SOURCE_PATHS:
            current = self.texts[path]
            before = helpers.predecessor_source(path, current)
            self.assertEqual(helpers.sha(before), helpers.BEFORE_SHA256[path])
            self.assertEqual(helpers.source.token_sha256(before), helpers.BEFORE_TOKEN_SHA256[path])
            forward = before
            for name, old, new in helpers.EDITS[path]:
                self.assertEqual(forward.count(old), 1, (path, name))
                forward = forward.replace(old, new, 1)
            self.assertEqual(forward, current)

    def test_unknown_comment_crlf_raw_and_token_endpoints_reject(self):
        for path in helpers.SOURCE_PATHS:
            text = self.texts[path]
            for bad in (text + '\n# changed\n', text.replace('\n', '\r\n'),
                        helpers.predecessor_source(path, text)):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    helpers.predecessor_source(path, bad)
            with patch.object(helpers.source, 'token_sha256', return_value='0' * 64):
                with self.assertRaises(ValueError): helpers.predecessor_source(path, text)

    def test_inverse_inventory_missing_reordered_duplicate_and_modified_reject(self):
        for path, edits in helpers.EDITS.items():
            variants = (edits[:-1], edits + (edits[-1],), tuple(reversed(edits)))
            for changed in variants:
                if changed == edits: continue
                with self.subTest(path=path, count=len(changed)), patch.dict(
                        helpers.EDITS, {path: changed}), self.assertRaises(ValueError):
                    helpers.predecessor_source(path, self.texts[path])
            name, old, new = edits[0]
            for first in ((name, old + '\n', new), (name, old, new + '?')):
                with patch.dict(helpers.EDITS, {path: (first, *edits[1:])}), self.assertRaises(ValueError):
                    helpers.predecessor_source(path, self.texts[path])

    def test_provider_body_qualifier_docstring_and_import_mutations_reject(self):
        mutations = {
            'extensions/carla/curve_interval.mojo': ('bits + 1', 'bits + 2'),
            UTF8: ('mut out: List[UInt8]', 'out: List[UInt8]'),
            'render/color_math.mojo': ('a.r + (b.r - a.r) * t', 'a.r + b.r * t'),
        }
        for path, (old, new) in mutations.items():
            self.assertIn(old, self.texts[path])
            for text in (self.texts[path].replace(old, new, 1),
                         self.texts[path] + '\ndef extra():\n    pass\n',
                         self.texts[path].replace('def ', '@always_inline\ndef ', 1)):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    helpers.verify_correspondence({**self.texts, path: text})
        for path in helpers.SOURCE_PATHS:
            text = self.texts[path]
            for bad in (text.replace(helpers.IMPORTS[path], helpers.IMPORTS[path] + ' as hidden', 1),
                        text + '\nmix_opaque = other\n'):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    helpers.predecessor_source(path, bad)

    def test_local_distance_scope_requires_exactly_its_live_provider(self):
        provider = 'extensions/carla/curve_interval.mojo'
        local = {path: self.texts[path] for path in (DISTANCE, provider)}
        self.assertEqual(helpers.verify_correspondence(local), (DISTANCE,))
        with self.assertRaises(ValueError): helpers.verify_correspondence({DISTANCE: local[DISTANCE]})
        with self.assertRaises(ValueError): helpers.verify_correspondence({**local, 'extra.mojo': ''})
        self.assertEqual(helpers.verify_correspondence({
            DISTANCE: helpers.predecessor_source(DISTANCE, local[DISTANCE])}), ())

    def test_leaf_function_defaults_and_module_witness_are_executed_bindings(self):
        self.assertEqual(cleanup.executing_checker_bindings()[LEAF],
                         hashlib.sha256((ROOT/LEAF).read_bytes()).hexdigest())
        function = helpers.verify_correspondence
        with patch.object(helpers, 'verify_correspondence', lambda texts: tuple()):
            with self.assertRaisesRegex(ValueError, 'executing function changed'):
                cleanup.executing_checker_bindings()
        with patch.object(function, '__defaults__', ('changed',)):
            with self.assertRaisesRegex(ValueError, 'defaults changed'):
                cleanup.executing_checker_bindings()
        with patch.object(helpers, '_EXECUTED_MODULE_CODE', compile('pass', helpers.__file__, 'exec')):
            with self.assertRaisesRegex(ValueError, 'module-code witness changed'):
                cleanup.executing_checker_bindings()


class SharedHelperIntegrationControls(unittest.TestCase):
    def setUp(self):
        self.root = fixtures.copy_current_root(self, ROOT)

    @contextmanager
    def changed(self, name, raw):
        path = self.root/name
        old = path.read_bytes()
        path.write_bytes(raw)
        try: yield
        finally: path.write_bytes(old)

    def test_live_receipt_uses_actual_helpers_and_preserves_all_historical_records(self):
        record = cleanup.read_record(self.root)
        records = {path: (self.root/path).read_bytes() for path in record['historical_records']}
        bindings = cleanup.proof_bindings(self.root)
        # The new native closure reaches the rendering provider directly.
        color = 'render/color_math.mojo'
        self.assertEqual(bindings[color], cleanup.sha((self.root/color).read_bytes()))
        self.assertEqual(cleanup.sha(cleanup.pr760_stage.predecessor_source(
            color, (self.root/color).read_text())), cleanup.typed_boundary.CURRENT_DEPENDENCIES[color])
        bindings.update(cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS))
        for path in (*helpers.SOURCE_PATHS, *helpers.PROVIDERS, *helpers.TESTS, LEAF):
            self.assertEqual(bindings[path], hashlib.sha256((self.root/path).read_bytes()).hexdigest())
        for group in ('unchanged_inputs', 'native_dependency_inputs'):
            for path in (DISTANCE, XML):
                self.assertEqual(record[group][path], helpers.BEFORE_SHA256[path])
        self.assertNotIn(UTF8, record['dependency_inventory'])
        self.assertNotIn(UTF8, record['native_dependency_inventory'])
        self.assertEqual(records, {path: (self.root/path).read_bytes() for path in records})
        self.assertEqual(hashlib.sha256((self.root/cleanup.MIGRATION).read_bytes()).hexdigest(),
                         cleanup.MIGRATION_SHA256)
        self.assertEqual(hashlib.sha256((self.root/cleanup.CONSUMER_LEDGER).read_bytes()).hexdigest(),
                         cleanup.CONSUMER_LEDGER_SHA256)

    def test_typed_render_fixture_requires_the_complete_current_graph(self):
        fixture = 'tests/test_carla_render_scene.mojo'
        raw = (self.root/fixture).read_bytes()
        self.assertTrue(cleanup.typed_boundary.is_current(fixture, raw))
        self.assertEqual(cleanup.typed_boundary.edge(fixture)['before_sha256'],
                         helpers.TESTS[fixture])
        polynomial = 'extensions/carla/polynomial.mojo'
        with self.changed(polynomial, (self.root/polynomial).read_bytes() + b'\n# changed\n'):
            with self.assertRaises(ValueError):
                cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)

    def test_historical_helper_endpoints_keep_the_original_import_closure(self):
        self.root = fixtures.copy_historical_boundary_root(self, ROOT)
        originals = {path: (self.root/path).read_bytes() for path in helpers.SOURCE_PATHS}
        try:
            for path, raw in originals.items():
                (self.root/path).write_text(helpers.predecessor_source(path, raw.decode()))
            record = cleanup.verify(self.root, exact=True)
            self.assertEqual(cleanup.shared_helper_edges(self.root), {})
            self.assertEqual(cleanup.dependency_inventory(self.root,
                roots=(*cleanup.SOURCE_PATHS, *record['inventory']),
                entries=record['entry_directories']), set(record['dependency_inventory']))
            receipt = cleanup.proof_bindings(self.root)
            self.assertEqual(receipt[DISTANCE], helpers.BEFORE_SHA256[DISTANCE])
            self.assertEqual(receipt[XML], helpers.BEFORE_SHA256[XML])
            self.assertNotIn(UTF8, receipt)
        finally:
            for path, raw in originals.items(): (self.root/path).write_bytes(raw)

    def test_mixed_old_xml_does_not_require_its_unimported_utf8_provider(self):
        # The current typed graph independently binds this provider. The old
        # XML's local import closure does not relax that full-graph authority.
        historical = fixtures.copy_historical_boundary_root(self, ROOT)
        common = fixtures.copy_common758_boundary_root(self, ROOT)
        for root, typed in ((common, True), (historical, False)):
            old_xml = helpers.predecessor_source(XML, (root/XML).read_text()).encode()
            with self.subTest(typed=typed), patch.object(self, 'root', root), self.changed(XML, old_xml):
                utf8 = root/UTF8
                raw = utf8.read_bytes(); utf8.unlink()
                try:
                    bound = cleanup.shared_helper_proof_bindings(root)
                    self.assertIn(DISTANCE, bound)
                    self.assertEqual(bound[XML], helpers.BEFORE_SHA256[XML])
                    self.assertNotIn(UTF8, bound)
                    if typed:
                        with self.assertRaises(cleanup.ContractError) as caught:
                            cleanup.verify(root, exact=True)
                        self.assertIsInstance(caught.exception.__cause__, FileNotFoundError)
                        self.assertEqual(caught.exception.__cause__.filename, str(utf8))
                    else:
                        cleanup.verify(root, exact=True)
                finally: utf8.write_bytes(raw)

    def test_pr760_old_xml_cannot_borrow_the_current_provider_image(self):
        baseline = fixtures.common758_leaf_texts(self.root)
        old = helpers.predecessor_source(XML, baseline[XML]).encode('utf-8')
        with self.changed(XML, old):
            with self.assertRaises(ValueError):
                cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)
            utf8 = self.root/UTF8
            raw = utf8.read_bytes()
            utf8.unlink()
            try:
                with self.assertRaises(FileNotFoundError) as caught:
                    cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)
                self.assertEqual(caught.exception.filename, str(utf8))
            finally:
                utf8.write_bytes(raw)
        cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)

    def test_fabricated_or_incomplete_owned_view_cannot_admit_sources(self):
        class Fake:
            _executing = {LEAF: hashlib.sha256((ROOT/LEAF).read_bytes()).hexdigest()}
            def raw(self, owner, root, path): return (ROOT/path).read_bytes()
        for view, owner in ((Fake(), object()), (Fake(), None), (None, object())):
            with self.assertRaises(ValueError):
                cleanup.shared_helper_proof_bindings(self.root, _inputs=view, _input_owner=owner)
            with self.assertRaises(ValueError):
                cleanup._shared_helper_bindings(self.root, _inputs=view, _input_owner=owner)

    def test_each_new_provider_test_and_leaf_is_bound_and_unreadable_fails(self):
        read = Path.read_bytes
        for name in (*helpers.PROVIDERS, *helpers.TESTS, LEAF):
            with self.subTest(path=name):
                with self.changed(name, read(self.root/name) + b'\n# changed\n'):
                    with self.assertRaises(ValueError): cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)
                failure = OSError('helper input unreadable')
                def unreadable(path, *args, **kwargs):
                    if path == self.root/name: raise failure
                    return read(path, *args, **kwargs)
                with patch.object(Path, 'read_bytes', unreadable), self.assertRaises((OSError, ValueError)) as caught:
                    cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)
                cause = caught.exception
                while cause.__cause__ is not None:
                    cause = cause.__cause__
                self.assertIs(cause, failure)

    def test_new_helper_resolver_package_symlink_and_extra_import_reject(self):
        for name in ('loaders/utf8.mojopkg', 'render/color_math.mojopkg',
                     'loaders/utf8/__init__.mojo'):
            path = self.root/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('# resolver shadow\n')
            try:
                with self.assertRaises(ValueError):
                    cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)
            finally:
                path.unlink()
                if name.endswith('__init__.mojo'): path.parent.rmdir()
        path = self.root/UTF8
        original = path.read_bytes()
        path.unlink(); path.symlink_to(self.root/XML)
        try:
            with self.assertRaises(ValueError): cleanup.verify(self.root)
        finally:
            path.unlink(); path.write_bytes(original)
        with self.changed(XML, (self.root/XML).read_bytes() + b'\nimport render.color_math\n'):
            with self.assertRaises(ValueError): cleanup.verify(self.root)

    def test_renderer_shadow_after_admission_rejects_at_the_same_owner_exit(self):
        from functools import wraps
        import winner_sign_contracts as winner
        original = cleanup.shared_helper_edges
        historical = fixtures.historical_root(self, ROOT)
        for label, root in (('current', self.root), ('historical', historical)):
            shadow = root/'render/color_math.mojopkg'
            injected = []
            @wraps(original)
            def add_shadow(candidate, **kwargs):
                result = original(candidate, **kwargs)
                if sys._getframe(1).f_globals is vars(winner):
                    shadow.write_bytes(b'unreviewed compiled helper')
                    injected.append(True)
                return result
            try:
                with self.subTest(endpoint=label), patch.object(
                        cleanup, 'shared_helper_edges', add_shadow):
                    with self.assertRaises(cleanup._OperationCoherenceError): winner.verify(root)
                self.assertEqual(injected, [True])
            finally:
                if shadow.exists(): shadow.unlink()

    def test_pending_historical_helper_bytes_are_rechecked_after_admission(self):
        from functools import wraps
        import winner_sign_contracts as winner
        self.root = fixtures.historical_root(self, ROOT)
        original = cleanup.shared_helper_edges
        for name in ('render/color_math.mojo', LEAF):
            target = self.root/name
            raw = target.read_bytes()
            injected = []
            @wraps(original)
            def change_after_admission(root, **kwargs):
                result = original(root, **kwargs)
                if sys._getframe(1).f_globals is vars(winner):
                    target.write_bytes(raw + b'\n# changed after helper admission\n')
                    injected.append(True)
                return result
            try:
                with self.subTest(path=name), patch.object(
                        cleanup, 'shared_helper_edges', change_after_admission):
                    with self.assertRaises(cleanup._OperationCoherenceError): winner.verify(self.root)
                self.assertEqual(injected, [True])
            finally: target.write_bytes(raw)

    def test_nonentry_render_libraries_are_not_compiled_namespace_shadows(self):
        for name in ('extensions/animals/anatomy/render.mojo',
                     'extensions/building/views/render.mojo'):
            self.assertTrue((self.root/name).is_file())
        bindings = cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)
        color = 'render/color_math.mojo'
        self.assertEqual(bindings[color], cleanup.sha((self.root/color).read_bytes()))
        self.assertEqual(cleanup.sha(cleanup.pr760_stage.predecessor_source(
            color, (self.root/color).read_text())), helpers.PROVIDERS[color])
        self.assertEqual(bindings[cleanup.MIGRATION], cleanup.MIGRATION_SHA256)
        paths = {name for name in bindings if name.endswith('.mojo')}
        self.assertFalse(cleanup.resolver_unshadowed(self.root, paths))
        entries = cleanup.read_record(self.root)['entry_directories']
        self.assertTrue(cleanup.resolver_unshadowed(self.root, paths,
            **cleanup._render_lookup_args(paths, entries)))
        # The correction grants no authority to a new standalone entrypoint.
        common = fixtures.copy_common758_boundary_root(self, ROOT)
        for cohort, root, message in (
                ('pr760', self.root, 'PR760 maintained entry directories changed'),
                ('common758', common, 'maintained entrypoint directories changed')):
            with self.subTest(cohort=cohort):
                cleanup.shared_helper_proof_bindings(root, paths=helpers.SOURCE_PATHS)
                entry = root/'extensions/animals/anatomy/helper_scope_entry.mojo'
                self.assertFalse(entry.exists())
                entry.write_text('def main():\n    pass\n')
                try:
                    with self.assertRaises(cleanup.ContractError) as caught:
                        cleanup.shared_helper_proof_bindings(root, paths=helpers.SOURCE_PATHS)
                    self.assertEqual(str(caught.exception),
                                     'full-audit cleanup successor: ' + message)
                finally: entry.unlink()
                cleanup.shared_helper_proof_bindings(root, paths=helpers.SOURCE_PATHS)

    def test_render_namespace_is_protected_at_root_tests_and_production_entries(self):
        for name in ('render.mojo', 'tests/render.mojopkg', 'examples/render.mojo',
                     'bench/mojo10/render/__init__.mojo'):
            path = self.root/name
            existed = path.parent.is_dir()
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('# genuine namespace competitor\n')
            try:
                with self.subTest(path=name), self.assertRaises(ValueError):
                    cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)
            finally:
                path.unlink()
                if not existed: path.parent.rmdir()
        shadow = self.root/'tests/render'
        shadow.symlink_to(self.root/'render', target_is_directory=True)
        try:
            with self.assertRaises(ValueError):
                cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)
        finally: shadow.unlink()

    def test_entry_source_observation_and_final_path_census_cannot_be_restored_away(self):
        source = self.root/'extensions/animals/anatomy/render.mojo'
        read = Path.read_bytes
        visits = []
        def changed(path, *args, **kwargs):
            raw = read(path, *args, **kwargs)
            if path == source and sys._getframe(1).f_code in (
                    cleanup._helper_entry_census.__code__, cleanup._helper_entry_census_finish.__code__):
                visits.append(True)
                if len(visits) == 2: return raw + b'\ndef main():\n    pass\n'
            return raw
        with patch.object(Path, 'read_bytes', changed), self.assertRaisesRegex(
                ValueError, 'render entry source changed'):
            cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)
        self.assertEqual(len(visits), 2)
        # A late compiled-package shadow is absent from the Mojo path census;
        # the final scoped topology check must still see it.
        for late_name, payload in (('tests/render.mojopkg', b'compiled shadow'),
                                   ('helper_scope_late/main.mojo', b'def main():\n    pass\n')):
            late = self.root/late_name
            visits.clear()
            def created(path, *args, **kwargs):
                raw = read(path, *args, **kwargs)
                if path == source and sys._getframe(1).f_code in (
                        cleanup._helper_entry_census.__code__, cleanup._helper_entry_census_finish.__code__):
                    visits.append(True)
                    if len(visits) == 2:
                        late.parent.mkdir(parents=True, exist_ok=True)
                        late.write_bytes(payload)
                return raw
            try:
                with self.subTest(path=late_name), patch.object(Path, 'read_bytes', created):
                    with self.assertRaises(ValueError):
                        cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)
                self.assertEqual(len(visits), 2)
            finally:
                if late.exists(): late.unlink()
                if late_name.startswith('helper_scope_late/'): late.parent.rmdir()
        cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)

    def test_entry_census_requires_builtin_bytes_before_and_after_classification(self):
        class AlwaysEqual(bytes):
            def __eq__(self, other): return True
        source = self.root/'extensions/animals/anatomy/render.mojo'
        read = Path.read_bytes
        for target_visit in (1, 2):
            visits = []
            def changed(path, *args, **kwargs):
                raw = read(path, *args, **kwargs)
                if path == source and sys._getframe(1).f_code in (
                        cleanup._helper_entry_census.__code__, cleanup._helper_entry_census_finish.__code__):
                    visits.append(True)
                    if len(visits) == target_visit:
                        return AlwaysEqual(raw + b'\ndef main():\n    pass\n')
                return raw
            with self.subTest(visit=target_visit), patch.object(Path, 'read_bytes', changed):
                diagnostic = 'source is not physical bytes' if target_visit == 1 else 'source changed'
                with self.assertRaisesRegex(ValueError, diagnostic):
                    cleanup.shared_helper_proof_bindings(self.root, paths=helpers.SOURCE_PATHS)
            self.assertEqual(len(visits), target_visit)

    def test_pending_entry_census_failure_stays_poisoned_after_catch_and_restore(self):
        from functools import wraps
        import winner_sign_contracts as winner
        self.root = fixtures.historical_root(self, ROOT)
        source = self.root/'extensions/animals/anatomy/render.mojo'
        read, original = Path.read_bytes, cleanup.shared_helper_edges
        injected, caught = [], []
        def changed(path, *args, **kwargs):
            raw = read(path, *args, **kwargs)
            frame = sys._getframe(1)
            while frame is not None and frame.f_code.co_name != '_helper_entry_census':
                frame = frame.f_back
            if path == source and frame is not None and not injected:
                injected.append(True)
                return raw + b'\ndef main():\n    pass\n'
            return raw
        @wraps(original)
        def retried(root, **kwargs):
            try: return original(root, **kwargs)
            except ValueError as error:
                caught.append(str(error))
                return original(root, **kwargs)
        with patch.object(Path, 'read_bytes', changed), patch.object(
                cleanup, 'shared_helper_edges', retried):
            with self.assertRaises(cleanup._OperationCoherenceError): winner.verify(self.root)
        self.assertEqual(injected, [True])
        self.assertTrue(caught)

    def test_pending_entry_source_exit_rejects_overridden_byte_equality(self):
        import winner_sign_contracts as winner
        class AlwaysEqual(bytes):
            def __eq__(self, other): return True
        self.root = fixtures.historical_root(self, ROOT)
        source = self.root/'extensions/animals/anatomy/render.mojo'
        read, injected = Path.read_bytes, []
        def changed(path, *args, **kwargs):
            raw = read(path, *args, **kwargs)
            caller = sys._getframe(1)
            if path == source and caller.f_globals is vars(cleanup) and caller.f_code.co_name == 'finish':
                injected.append(True)
                return AlwaysEqual(raw + b'\ndef main():\n    pass\n')
            return raw
        with patch.object(Path, 'read_bytes', changed):
            with self.assertRaises(cleanup._OperationCoherenceError): winner.verify(self.root)
        self.assertEqual(injected, [True])

    def test_render_callers_have_no_includes_and_coverage_keeps_arithmetic_scope(self):
        for filename in ('border_parser_contracts.py', 'winner_sign_contracts.py'):
            tree = ast.parse((ROOT/'tools/carla_lane_oracle'/filename).read_text())
            calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
                     and isinstance(node.func, ast.Attribute) and node.func.attr == 'shared_helper_edges']
            self.assertEqual(len(calls), 1)
            self.assertNotIn('include_roots', {keyword.arg for keyword in calls[0].keywords})
        tree = ast.parse((ROOT/'tools/coverage_loop_proofs.py').read_text())
        calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Attribute) and node.func.attr == 'shared_helper_proof_bindings']
        self.assertEqual(len(calls), 1)
        paths = next(keyword.value for keyword in calls[0].keywords if keyword.arg == 'paths')
        self.assertEqual(ast.literal_eval(paths), helpers.ARITHMETIC_PATHS)
        tree = ast.parse((ROOT/'tools/carla_lane_oracle/full_audit_cleanup_contracts.py').read_text())
        proof = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'proof_bindings')
        calls = [node for node in ast.walk(proof) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Name) and node.func.id == 'shared_helper_proof_bindings']
        self.assertEqual(len(calls), 1)
        self.assertNotIn('paths', {keyword.arg for keyword in calls[0].keywords})

    def test_consumed_helper_failure_stays_sticky_after_catch_and_restore(self):
        from functools import wraps
        import winner_sign_contracts as winner
        read, original = Path.read_bytes, cleanup.shared_helper_edges
        target = self.root/'render/color_math.mojo'
        injected, caught = [], []
        def transient(path, *args, **kwargs):
            raw = read(path, *args, **kwargs)
            caller = sys._getframe(1)
            operation = caller.f_locals.get('_operation')
            if (path == target and caller.f_globals is vars(cleanup)
                    and caller.f_code.co_name == 'observe' and operation is not None
                    and operation._state == 'active' and not injected):
                injected.append(True)
                return raw + b'\n# transient consumed helper\n'
            return raw
        @wraps(original)
        def retry(root, **kwargs):
            try: return original(root, **kwargs)
            except ValueError as error:
                caught.append(error)
                return original(root, **kwargs)
        with patch.object(Path, 'read_bytes', transient), patch.object(cleanup, 'shared_helper_edges', retry):
            with self.assertRaises(cleanup._OperationCoherenceError) as final:
                winner.verify(self.root)
        self.assertEqual(injected, [True])
        expected = ('full-audit cleanup successor: consumed operation bytes changed: '
                    'render/color_math.mojo')
        self.assertEqual(len(caught), 1)
        self.assertIsInstance(caught[0], cleanup._OperationCoherenceError)
        self.assertEqual(str(caught[0]), expected)
        self.assertIsInstance(caught[0].__cause__, cleanup.ContractError)
        self.assertEqual(str(caught[0].__cause__), expected)
        self.assertEqual(str(final.exception), expected)


if __name__ == '__main__':
    unittest.main()
