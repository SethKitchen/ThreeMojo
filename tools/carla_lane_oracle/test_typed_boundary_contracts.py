#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Current typed/cubic correspondence and fail-closed inverse controls.

These tests bind current files. Historical checker fixtures are separate.
No test changes a historical record or treats an inverse as numeric parity.
"""
import copy
import hashlib
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import conditioned_cubic_contracts as conditioned
import source_contracts as source
import typed_boundary_contracts as typed
import full_audit_cleanup_contracts as audit
import _full_audit_test_fixtures as fixtures

ROOT = Path(__file__).resolve().parents[2]


class TypedBoundaryContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        baseline = fixtures.common758_leaf_texts(ROOT)
        cls.current = {path: baseline[path] for path in typed.SOURCE_PATHS}
        typed.verify_sources(dict(cls.current))

    def test_translated_method_provenance_retains_all_original_pins(self):
        import ast
        import re
        path = ROOT/'tools/carla_lane_oracle/translated_parameter_resolution.py'
        tree = ast.parse(path.read_text())
        function = next(node for node in tree.body if isinstance(node, ast.FunctionDef)
                        and node.name == 'method_bytes')
        # Pure projection only. The physical positive and mutation test below
        # lives in TypedCurrentOwnedOperation and executes complete admission.
        seen = []
        def historical(name):
            seen.append(name)
            text = (ROOT/name).read_text()
            return typed.historical_source(name, text)
        namespace = {'re': re, '_historical_text': historical}
        exec(compile(ast.Module(body=[function], type_ignores=[]), str(path), 'exec'), namespace)
        pins = json.loads((ROOT/'tools/carla_lane_oracle/translated-parameter-source.json').read_text())
        self.assertEqual(len(pins['methods']), 21)
        for item in pins['methods']:
            with self.subTest(path=item['path'], method=item['name']):
                actual = namespace['method_bytes'](item['path'], item['name'])
                self.assertEqual(hashlib.sha256(actual).hexdigest(), item['sha256'])
        self.assertEqual(seen, [item['path'] for item in pins['methods']])

    def test_oracle_runtime_composition_propagates_both_required_child_refusals(self):
        import ast
        import check_runtime_support as runtime
        import full_audit_cleanup_contracts as audit
        path = ROOT/'tools/carla_lane_oracle/oracle.py'
        tree = ast.parse(path.read_text())
        function = next(node for node in tree.body if isinstance(node, ast.FunctionDef)
                        and node.name == '_verify_runtime_contracts')
        calls = [node for node in tree.body if isinstance(node, ast.Expr)
                 and isinstance(node.value, ast.Call)
                 and isinstance(node.value.func, ast.Name)
                 and node.value.func.id == function.name]
        self.assertEqual([ast.unparse(node) for node in calls],
                         ['_verify_runtime_contracts(SOURCE)'])
        namespace = {}
        exec(compile(ast.Module(body=[function], type_ignores=[]), str(path), 'exec'), namespace)
        root = Path('/synthetic-oracle-control')
        for child in ('canonical_accumulation', 'sum2'):
            reached = []
            failure = ValueError('required oracle child refused: ' + child)
            def group(actual, name, *, _operation=None):
                self.assertEqual(actual, root)
                reached.append(name)
                if name == child:
                    raise failure
                return {'synthetic': name}
            def sum2(actual, *, _operation=None):
                self.assertEqual(actual, root)
                reached.append('sum2')
                raise failure
            # Exercise the actual public runtime dispatcher, isolating only
            # its admission and child work. Real owner/refusal controls remain
            # in TypedCurrentOwnedOperation and the maintained owner matrix.
            with self.subTest(child=child), \
                    patch.object(audit, '_operation_enter', return_value=(None, False)), \
                    patch.object(runtime, 'verify_group', group), \
                    patch.object(runtime.heading_correspondence, 'verify', return_value={}), \
                    patch.object(runtime.optional_runtime_contracts, 'verify', return_value={}), \
                    patch.object(runtime.sum2_contracts, 'verify', sum2):
                with self.assertRaises(ValueError) as raised:
                    namespace[function.name](root)
                self.assertIs(raised.exception, failure)
            self.assertIn('canonical_accumulation', reached)
            self.assertEqual(reached[-1], child)

    def test_exact_provenance_reconstruction_has_no_lexical_result_cache(self):
        path = 'extensions/carla/map.mojo'
        first = typed.predecessor_source(path, self.current[path])
        changed = copy.deepcopy(typed.EDGES)
        changed[path]['before_sha256'] = '0'*64
        with patch.object(typed, 'EDGES', changed), self.assertRaises(ValueError):
            typed.predecessor_source(path, self.current[path])
        self.assertEqual(typed.predecessor_source(path, self.current[path]), first)

    def test_replaced_and_wrapped_token_helpers_keep_effects_and_refusal(self):
        from functools import wraps
        path = 'extensions/carla/map.mojo'
        original = source.token_sha256
        calls = []
        @wraps(original)
        def observed(text):
            calls.append(text)
            return original(text)
        with patch.object(source, 'token_sha256', observed):
            typed.predecessor_source(path, self.current[path])
        self.assertEqual(len(calls), 2)
        @wraps(original)
        def refused(text):
            raise ValueError('wrapped lexical refusal')
        with patch.object(source, 'token_sha256', refused):
            with self.assertRaisesRegex(ValueError, 'wrapped lexical refusal'):
                typed.predecessor_source(path, self.current[path])
        with patch.object(source, 'token_sha256', lambda text: '0'*64):
            with self.assertRaises(ValueError):
                typed.predecessor_source(path, self.current[path])

    def test_reconstruction_observes_parser_change_after_complete_admission(self):
        path = 'extensions/carla/map.mojo'
        typed.verify_sources(dict(self.current))
        # Keep existing lexical caches populated: a parser change must not
        # inherit their prior successful digest.
        with patch.object(source.tokenize, '_generate_tokens_from_c_tokenizer',
                          side_effect=ValueError('late parser refusal')):
            with self.assertRaisesRegex(ValueError, 'lexical parser domain changed'):
                typed.predecessor_source(path, self.current[path])

    def test_mutated_keyword_defaults_cannot_reuse_warm_lexical_results(self):
        path = 'extensions/carla/map.mojo'
        typed.verify_sources(dict(self.current))
        original = dict(source.json.dumps.__kwdefaults__)
        try:
            source.json.dumps.__kwdefaults__['ensure_ascii'] = False
            with self.assertRaisesRegex(ValueError, 'lexical parser domain changed'):
                typed.predecessor_source(path, self.current[path])
        finally:
            source.json.dumps.__kwdefaults__.clear()
            source.json.dumps.__kwdefaults__.update(original)

    def test_sampled_entry_reaches_the_original_physical_observer(self):
        import check_sampled_values as sampled
        import full_audit_cleanup_contracts as audit
        import tempfile
        class Observed(RuntimeError):
            pass
        events = []
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            name = 'extensions/carla/curve_bounds.mojo'
            path = root/name
            path.parent.mkdir(parents=True)
            path.write_text('physical current observation')
            def observe(actual_root, actual_name, text, *, _operation=None):
                events.append((actual_root, actual_name, text, _operation))
                raise Observed('physical read reached observer')
            # Isolate entry evaluation before any proof semantics. The original
            # code failed with UnboundLocalError before this read observer.
            with patch.object(audit, '_operation_enter', return_value=(None, False)), \
                    patch.object(sampled._typed_source, '_observe_text', observe):
                with self.assertRaisesRegex(Observed, 'physical read reached observer'):
                    sampled.verify(root)
        self.assertEqual(events, [(root, name, 'physical current observation', None)])

    def test_shared_helper_fixture_transport_keeps_physical_receipts_and_final_join(self):
        import ast
        import inspect
        import tempfile
        import full_audit_cleanup_contracts as audit
        helpers = audit.shared_helpers
        fixture = 'tests/test_carla_render_scene.mojo'
        inputs = {*helpers.SOURCE_PATHS, *helpers.PROVIDERS, *helpers.TESTS,
                  *helpers.package_inputs((*helpers.SOURCE_PATHS, *helpers.PROVIDERS)),
                  'tools/carla_lane_oracle/shared_helper_contracts.py'}
        self.assertEqual(inputs & set(typed.EDGES), {fixture})
        self.assertEqual(typed.edge(fixture)['before_sha256'], helpers.TESTS[fixture])
        function = ast.parse(inspect.getsource(audit._shared_helper_bindings))
        baseline = fixtures.common758_leaf_texts(ROOT)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            for name in inputs:
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                raw = (baseline[name].encode('utf-8') if name in baseline
                       else (ROOT/name).read_bytes())
                if name in ('tools/test_conditioned_coverage_loops.py', 'tools/carla_lane_oracle/test_typed_boundary_contracts.py', 'tools/carla_lane_oracle/test_shared_helper_contracts.py', 'tools/carla_lane_oracle/test_scaled_float32_contracts.py', 'tools/carla_lane_oracle/test_common758_current_successor.py'):
                    raw = audit.qualification_predecessor_bytes(name, raw)
                path.write_bytes(raw)
            physical = (root/fixture).read_bytes()
            events = []
            def observe(actual_root, path, raw, *, _operation=None):
                self.assertEqual(actual_root, root)
                self.assertEqual(raw, (root/path).read_bytes())
                events.append(('read', path, raw))
                return raw
            def admitted(actual_root, path, text, **kwargs):
                self.assertEqual((actual_root, path, text), (root, fixture, physical.decode()))
                self.assertTrue(any(event[:2] == ('read', fixture) for event in events))
                events.append(('admitted', path, text))
                return typed.historical_source(path, text)
            def final(actual_root, *, exact, _expected_sources):
                self.assertEqual((actual_root, exact), (root, True))
                self.assertEqual(_expected_sources, {fixture: physical})
                events.append(('final', fixture, physical))
            namespace = {**vars(audit), '_operation_check': lambda *args: None,
                '_observe_bytes': observe, 'reviewed_typed_text': admitted, 'verify': final}
            # Isolate the binding orchestration; the integration suite below
            # this layer exercises the real complete-root refusal and owner.
            exec(compile(function, '<shared-helper-binding-control>', 'exec'), namespace)
            result = namespace['_shared_helper_bindings'](root, paths=helpers.SOURCE_PATHS)
            self.assertEqual(result[fixture], typed.sha(physical))
            self.assertNotEqual(result[fixture], helpers.TESTS[fixture])
            self.assertEqual([event[0] for event in events if event[1] == fixture],
                             ['read', 'admitted', 'final', 'read'])
            def changed_final(actual_root, **kwargs):
                final(actual_root, **kwargs)
                (root/fixture).write_bytes(physical + b'\n# late fixture change\n')
            namespace['verify'] = changed_final
            with self.assertRaisesRegex(ValueError, 'helper input changed during admission'):
                namespace['_shared_helper_bindings'](root, paths=helpers.SOURCE_PATHS)

    def test_followup_projection_respects_the_named_cache_helper_domain(self):
        import coverage_followup_contracts as followup
        import full_audit_cleanup_contracts as audit
        operation = object()
        raw = 'physical current supplied source'
        projected = 'admitted historical source'
        for path in followup.SOURCE_PATHS:
            if path in followup.accepted.SOURCE_PATHS:
                continue
            named = path == followup.cache_key.MODULE or path in audit.SOURCE_PATHS
            events = []
            def historical(root, name, text, *, _operation=None):
                self.assertEqual((root, name, text, _operation), (ROOT, path, raw, operation))
                self.assertFalse(named, 'named supplied-view helper must observe current text first')
                events.append('project')
                return projected
            def checked(root, name, text, *, _operation=None):
                self.assertEqual((root, name, _operation), (ROOT, path, operation))
                self.assertEqual(text, raw if named else projected)
                events.append('named' if named else 'historical identity')
                return text
            with self.subTest(path=path), patch.object(
                    followup._typed_source, 'historical_text', historical), patch.object(
                    followup.cache_key, 'reviewed_text', checked):
                self.assertEqual(followup._source_view(ROOT, path, raw, _operation=operation),
                                 raw if named else projected)
            self.assertEqual(events, ['named'] if named else ['project', 'historical identity'])

    def test_relative_checkout_paths_do_not_skip_the_typed_edge(self):
        name = 'extensions/carla/map.mojo'
        self.assertEqual(source._typed_path(Path('checkout'), Path('checkout')/name), name)
        self.assertEqual(source._typed_path(Path('checkout'), name), name)
        self.assertEqual(source._typed_path(Path('extensions'), name), name)
        self.assertEqual(source._typed_path(Path('.'), Path(name)), name)
        self.assertEqual(source._typed_path(Path('checkout'), Path('checkout/../')/name),
                         'checkout/../' + name)

    def test_projection_adapters_keep_raw_terminal_guards(self):
        import ast
        import inspect
        import seed_count_contracts as seed
        # The public verifier now owns standalone operation lifetime and
        # delegates both paths to the same body. Bind that routing before
        # inspecting the body's terminal comparison of physical bytes.
        for name, targets in (('verify', ('_verify_seed_body', '_verify_standalone')),
                              ('_verify_standalone', ('_verify_seed_body',))):
            tree = ast.parse(inspect.getsource(getattr(seed, name)))
            calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
                     and isinstance(node.func, ast.Name) and node.func.id in targets]
            self.assertCountEqual([node.func.id for node in calls], targets)
            for call in calls:
                self.assertEqual(ast.dump(call.args[0]), ast.dump(ast.Name(id='root', ctx=ast.Load())))
                self.assertEqual(next(keyword.value.id for keyword in call.keywords
                                      if keyword.arg == '_expected_raw'), '_expected_raw')
        for name in ('_verify_seed_body', 'verify_score', 'verify_support', 'verify_frontier',
                     'verify_optional', 'historical_source', 'reviewed_text'):
            with self.subTest(adapter=name):
                tree = ast.parse(inspect.getsource(getattr(seed, name)))
                checks = [node for node in ast.walk(tree) if isinstance(node, ast.Compare)
                          and isinstance(node.comparators[0], ast.Name)
                          and node.comparators[0].id == 'current_raw']
                self.assertEqual(len(checks), 1)
                self.assertFalse(any(isinstance(node, ast.Call)
                    and isinstance(node.func, ast.Attribute)
                    and node.func.attr in ('historical_bytes', 'historical_text')
                    for node in ast.walk(checks[0])))

    def test_heading_original_reads_are_observed_before_projection(self):
        import ast
        import inspect
        import heading_correspondence as heading
        tree = ast.parse(inspect.getsource(heading.verify))
        parents = {child: node for node in ast.walk(tree) for child in ast.iter_child_nodes(node)}
        reads = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Attribute) and node.func.attr == 'read_text']
        self.assertEqual(len(reads), 3)
        for read in reads:
            observed = parents[read]
            self.assertIsInstance(observed, ast.Call)
            self.assertEqual(observed.func.attr, '_observe_text')
            self.assertIs(observed.args[2], read)
            projected = parents[observed]
            self.assertEqual(projected.func.attr, 'historical_text')

    def test_budget_boundary_observes_physical_text_before_provenance(self):
        import ast
        import envelope_budget_contracts as budget
        import inspect
        import tempfile
        operation = object()
        received = []
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root/budget.MODULE
            path.parent.mkdir(parents=True)
            path.write_text(self.current[budget.MODULE])
            def consume(text, *, root=None, _operation=None):
                received.append((text, root, _operation))
                return {'status': 'observed physical argument'}
            with patch.object(budget, 'verify_text', consume), patch.object(
                    budget._typed_source, 'historical_text',
                    side_effect=AssertionError('projection preceded physical consumer')):
                self.assertEqual(budget.verify(root, _operation=operation),
                                 {'status': 'observed physical argument'})
            self.assertEqual(received, [(self.current[budget.MODULE], root, operation)])
        node = ast.parse(inspect.getsource(budget.verify_text)).body[0]
        branch = node.body[0]
        observe = branch.body[-1]
        self.assertEqual(ast.unparse(observe),
            'text = full_audit._observe_text(root, MODULE, text, _operation=_operation)')
        self.assertEqual(ast.unparse(node.body[2]),
            'text = _typed_source.historical_text(actual_root, MODULE, text, _operation=_operation)')

    def test_every_authoritative_namespace_table_is_bound(self):
        typed.verify_authority()
        for name in ('SOURCE_PATHS', 'EDGES', 'EDGE_SHA256', 'NEW_INPUTS', 'TESTS',
                     'BINDING_INPUTS', 'PRODUCTION_CLOSURE', 'NATIVE_CLOSURE',
                     'TYPED_NATIVE_CLOSURE', 'TYPED_PRODUCTION_CLOSURE',
                     'CURRENT_DEPENDENCIES', 'INVENTORY', 'EDGES_SHA256'):
            value = getattr(typed, name)
            changed = {**value, 'unreviewed': None} if isinstance(value, dict) else (                (*value, 'unreviewed') if isinstance(value, tuple) else '0'*64)
            with self.subTest(name=name), patch.object(typed, name, changed):
                with self.assertRaises(ValueError):
                    typed.verify_authority()
                with self.assertRaises(ValueError):
                    typed.verify_sources(dict(self.current))

    def test_complete_current_sources_and_exact_semantic_joins(self):
        prior = typed.verify_sources(dict(self.current))
        self.assertEqual(set(prior), set(typed.SOURCE_PATHS))
        for path, text in prior.items():
            with self.subTest(path=path):
                self.assertEqual(typed.sha(text), typed.edge(path)['before_sha256'])
                self.assertEqual(source.token_sha256(text), typed.edge(path)['before_token_sha256'])
        self.assertTrue(set(conditioned.SOURCE_PATHS) <= set(typed.SOURCE_PATHS))

    def test_physical_endpoint_is_stricter_than_equal_tokens(self):
        path = 'extensions/carla/polynomial.mojo'
        text = self.current[path]
        changed = text + '\n# An unreviewed comment is a different physical endpoint.\n'
        self.assertEqual(source.token_sha256(text), source.token_sha256(changed))
        with self.assertRaises(ValueError):
            typed.predecessor_source(path, changed)

    def test_each_current_endpoint_refuses_an_unlisted_edit(self):
        for path, text in self.current.items():
            with self.subTest(path=path), self.assertRaises(ValueError):
                typed.predecessor_source(path, text + '\n')

    def test_historical_graph_cannot_be_mixed_into_current_graph(self):
        path = conditioned.SOURCE_PATHS[0]
        mixed = dict(self.current)
        mixed[path] = typed.historical_source(path, mixed[path])
        with self.assertRaises(ValueError):
            typed.verify_sources(mixed)
        mixed = dict(self.current)
        del mixed[path]
        with self.assertRaises(ValueError):
            typed.verify_sources(mixed)
        mixed = dict(self.current)
        mixed['extensions/carla/extra.mojo'] = ''
        with self.assertRaises(ValueError):
            typed.verify_sources(mixed)

    def test_inverse_inventory_mutation_is_not_admitted(self):
        path = 'extensions/carla/map.mojo'
        changed = copy.deepcopy(typed.EDGES)
        self.assertTrue(changed[path]['edits'])
        changed[path]['edits'][0][2].append('# extra predecessor content\n')
        with patch.object(typed, 'EDGES', changed):
            with self.assertRaises(ValueError):
                typed.predecessor_source(path, self.current[path])

    def test_inverse_reordering_cannot_reuse_an_endpoint(self):
        path = 'extensions/carla/map.mojo'
        changed = copy.deepcopy(typed.EDGES)
        self.assertGreater(len(changed[path]['edits']), 1)
        changed[path]['edits'].reverse()
        hashes = dict(typed.EDGE_SHA256)
        hashes[path] = typed.sha(json.dumps(changed[path], sort_keys=True, separators=(',', ':')))
        with patch.object(typed, 'EDGES', changed), patch.object(typed, 'EDGE_SHA256', hashes):
            with self.assertRaises(ValueError):
                typed.predecessor_source(path, self.current[path])


    def test_inverse_duplicate_cannot_reuse_an_endpoint(self):
        path = 'extensions/carla/map.mojo'
        changed = copy.deepcopy(typed.EDGES)
        changed[path]['edits'].insert(0, copy.deepcopy(changed[path]['edits'][0]))
        hashes = dict(typed.EDGE_SHA256)
        hashes[path] = typed.sha(json.dumps(changed[path], sort_keys=True, separators=(',', ':')))
        with patch.object(typed, 'EDGES', changed), patch.object(typed, 'EDGE_SHA256', hashes):
            with self.assertRaises(ValueError):
                typed.predecessor_source(path, self.current[path])

    def test_zero_origin_and_conditioned_operation_roles_are_distinct(self):
        path = 'extensions/carla/polynomial.mojo'
        conditioned_text = typed.predecessor_source(path, self.current[path])
        historical = typed.historical_source(path, self.current[path])
        self.assertEqual(typed.sha(conditioned_text), conditioned.AFTER_SHA256[path])
        self.assertEqual(typed.sha(historical), conditioned.BEFORE_SHA256[path])
        self.assertNotEqual(conditioned_text, historical)
        self.assertNotEqual(typed.edge(path)['before_sha256'], typed.EDGES[path]['before_sha256'])

    def test_all_bound_current_tests_and_new_inputs_exist(self):
        for path, expected in {**typed.NEW_INPUTS, **typed.TESTS, **typed.BINDING_INPUTS}.items():
            with self.subTest(path=path):
                target = ROOT/path
                self.assertFalse(target.is_symlink())
                raw = target.read_bytes()
                if path in ('tools/test_conditioned_coverage_loops.py', 'tools/carla_lane_oracle/test_typed_boundary_contracts.py', 'tools/carla_lane_oracle/test_shared_helper_contracts.py', 'tools/carla_lane_oracle/test_scaled_float32_contracts.py', 'tools/carla_lane_oracle/test_common758_current_successor.py'):
                    raw = audit.qualification_predecessor_bytes(path, raw)
                self.assertEqual(hashlib.sha256(raw).hexdigest(), expected)
        self.assertTrue(any(path.startswith('tests/compile_fail/') for path in typed.TESTS))
        self.assertIn('tests/test_carla_conditioned_polynomial.mojo', typed.TESTS)
        self.assertIn('extensions/carla/quantity_boundary.mojo', typed.NEW_INPUTS)

    def test_native_and_production_closures_bind_unit_provider(self):
        for closure in (typed.PRODUCTION_CLOSURE, typed.NATIVE_CLOSURE):
            self.assertEqual(len(closure), len(set(closure)))
            self.assertIn('extensions/carla/polynomial.mojo', closure)
            self.assertIn('extensions/carla/quantity_boundary.mojo', closure)
            self.assertIn('units/si.mojo', closure)


if __name__ == '__main__':
    unittest.main()
