# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Fixed PR760 staging controls; these do not enable runtime admission."""
import ast
import copy
import hashlib
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import pr760_arithmetic_stage as stage
import pr780_source_successor as successor
import shared_helper_contracts as shared
import typed_boundary_contracts as typed

ROOT = Path(__file__).resolve().parents[2]


class StagedArithmeticControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inputs = {path: successor.predecessor_bytes(path, (ROOT/path).read_bytes())
                      for path in stage.INPUT_SHA256}
        cls.current = {path: raw.decode('utf-8') for path, raw in cls.inputs.items()}
        cls.predecessors = stage.verify_staged_sources(cls.inputs)

    def test_fixed_scope_stays_outside_public_admission(self):
        self.assertEqual(stage.STATUS, 'staged-provenance-only')
        self.assertEqual(len(stage.SOURCE_PATHS), 22)
        self.assertEqual(len(stage.EXAMPLE_PATHS), 3)
        self.assertEqual(len(stage.OUTSTANDING_TYPED_PATHS), 163)
        self.assertFalse(set(stage.SOURCE_PATHS) & set(stage.OUTSTANDING_TYPED_PATHS))
        for name in ('typed_boundary_contracts.py', 'shared_helper_contracts.py',
                     'check_runtime_support.py',
                     'check_sampled_values.py'):
            self.assertNotIn('pr760_arithmetic_stage',
                             (ROOT/'tools/carla_lane_oracle'/name).read_text())
        leaf_tree = ast.parse((ROOT/'tools/carla_lane_oracle/pr760_arithmetic_stage.py').read_text())
        self.assertFalse(any(isinstance(node, ast.Name) and node.id in
                             ('open', 'Path', 'verify', 'proof_bindings')
                             for node in ast.walk(leaf_tree)))

    def test_all_declared_qualification_witnesses_are_bound(self):
        records = stage.REGISTRY_QUALIFICATION_RECORDS
        expected = {}
        for row in records['render']['native_diagnostics']['tests']:
            expected[row['source']] = row['source_sha256']
        for row in records['core']['native_tests'].values():
            expected[row['source']] = row.get('current_formatted_source_sha256', row['source_sha256'])
            if 'ci_repair_successor' in row:
                repair = row['ci_repair_successor']
                self.assertEqual(repair['source'], row['source'])
                self.assertEqual(repair['before_sha256'], row['source_sha256'])
                self.assertEqual(repair['schema'], 'pr760-cube-test-ci-repair-v1')
                expected[row['source']] = repair['after_sha256']
        reader = records['reader_witness_successor']
        expected[reader['source']] = reader['after_sha256']
        self.assertEqual(reader['after_test_count'], 12)
        apng = stage.REGISTRY_REVIEW_RECORDS['render/apng.mojo']['checks']
        expected[apng['existing_test_source']] = apng['existing_test_sha256']
        self.assertFalse(apng['tests_run_this_review'])
        for path, digest in expected.items():
            self.assertEqual(stage.REGISTRY_TEST_SHA256[path], digest)
            self.assertEqual(stage.REGISTRY_INPUT_SHA256[path], digest)
        for row in stage.REGISTRY_REVIEW_RECORDS.values():
            for path in row.get('test_targets', ()):
                self.assertIn(path, stage.REGISTRY_TEST_SHA256)
        self.assertEqual(stage.REGISTRY_QUALIFICATION_RECORDS['remaining']
                         ['qualification']['outstanding_semantic_obligations'], [])

    def test_existing_authorities_are_untouched(self):
        import full_audit_cleanup_contracts as owner
        # Named reviewed implementation successors retain exact old evidence.
        archives = {
            'full_audit_cleanup_contracts.py': 'pr760-owner-predecessor.txt',
            'typed_boundary_contracts.py': 'pr760-typed_boundary-predecessor.txt',
            'source_contracts.py': 'pr760-source-adapter-predecessor.txt',
            'seed_count_contracts.py': 'pr760-seed_count-predecessor.txt',
            'border_parser_contracts.py': 'pr760-border_parser-predecessor.txt',
            'winner_sign_contracts.py': 'pr760-winner_sign-predecessor.txt',
            'test_common758_current_successor.py': 'pr760-test_common758_current_successor-predecessor.txt',
        }
        executing = owner.executing_checker_bindings(ROOT)
        for path, expected in stage.PROTECTED_AUTHORITY_SHA256.items():
            with self.subTest(path=path):
                physical = ROOT/path
                if physical.name in archives:
                    physical = ROOT/'tools/carla_lane_oracle'/archives[physical.name]
                    if path == 'tools/carla_lane_oracle/test_common758_current_successor.py':
                        self.assertEqual(owner.qualification_predecessor_bytes(
                            path, (ROOT/path).read_bytes()), physical.read_bytes())
                    else:
                        self.assertEqual(executing[path], hashlib.sha256((ROOT/path).read_bytes()).hexdigest())
                self.assertEqual(hashlib.sha256(physical.read_bytes()).hexdigest(), expected)
        typed.verify_authority()

    def test_all_exact_inverses_round_trip(self):
        for path, before in self.predecessors.items():
            with self.subTest(path=path):
                edge = stage.EDGES[path]
                lines = before.splitlines(keepends=True)
                for edit in edge['edits']:
                    start, old = edit['start'], edit['before']
                    self.assertEqual(lines[start:start+len(old)], old)
                    lines[start:start+len(old)] = edit['after']
                self.assertEqual(''.join(lines), self.current[path])
                self.assertEqual(stage.sha(before), edge['before_sha256'])

    def test_predecessors_join_existing_common758_and_shared738(self):
        for path in stage.EXAMPLE_PATHS:
            prior = self.predecessors[path]
            self.assertEqual(stage.sha(prior), typed.EDGES[path]['after_sha256'])
            typed.predecessor_source(path, prior)
        for path in set(stage.SOURCE_PATHS) - set(stage.EXAMPLE_PATHS):
            self.assertEqual(stage.sha(self.predecessors[path]), typed.CURRENT_DEPENDENCIES[path])
        xml = 'loaders/xml.mojo'
        self.assertEqual(stage.sha(self.predecessors[xml]), shared.AFTER_SHA256[xml])
        self.assertEqual(shared.sha(shared.predecessor_source(xml, self.predecessors[xml])),
                         shared.BEFORE_SHA256[xml])
        self.assertEqual(stage.sha(self.predecessors['loaders/utf8.mojo']),
                         shared.PROVIDERS['loaders/utf8.mojo'])

    def test_hair_scope_is_separate_exact_provenance(self):
        self.assertEqual(len(stage.HAIR_SOURCE_PATHS), 4)
        self.assertEqual(set(stage.EDGES),
                         set(stage.CARLA_REGISTRY_PATHS) | set(stage.HAIR_SOURCE_PATHS))
        self.assertFalse(set(stage.HAIR_SOURCE_PATHS) & set(stage.SOURCE_PATHS))
        self.assertFalse(set(stage.HAIR_SOURCE_PATHS) & set(stage.OUTSTANDING_TYPED_PATHS))
        for path in stage.HAIR_SOURCE_PATHS:
            current = (ROOT/path).read_bytes().decode('utf-8')
            prior = stage.predecessor_source(path, current)
            edge = stage.EDGES[path]
            self.assertEqual(stage.sha(prior), edge['before_sha256'])
            lines = prior.splitlines(keepends=True)
            for edit in edge['edits']:
                start, before = edit['start'], edit['before']
                self.assertEqual(lines[start:start+len(before)], before)
                lines[start:start+len(before)] = edit['after']
            self.assertEqual(''.join(lines), current)
            for changed in (prior, current+'\n', current.replace('\n', '\r\n')):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    stage.predecessor_source(path, changed)
        self.assertNotIn('hair-retained-nonempty-strands',
                         (ROOT/'tools/carla_lane_oracle/pr760_arithmetic_stage.py').read_text())

    def test_complete_candidate_registry_keeps_admission_closed(self):
        self.assertEqual(len(stage.CARLA_REGISTRY_PATHS), 187)
        self.assertEqual(len(stage.EDGES), 191)
        self.assertEqual(len(stage.REGISTRY_REVIEW_RECORDS), 191)
        self.assertEqual({name: len(paths) for name, paths in stage.REGISTRY_SCOPES.items()},
                         {'arithmetic_and_examples': 22, 'render': 50, 'core': 67,
                          'geometry_material_objects_postprocessing': 46, 'hair': 4,
                          'example_apng': 1, 'example_generator': 1})
        self.assertIs(stage.REGISTRY_QUALIFICATION_READY, False)
        self.assertTrue(stage.REGISTRY_UNRESOLVED_CONDITIONS)
        inputs = {path: successor.predecessor_bytes(path, (ROOT/path).read_bytes())
                  for path in stage.REGISTRY_INPUT_SHA256}
        import full_audit_cleanup_contracts as owner
        witness = 'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py'
        inputs[witness] = owner.stage_witness_predecessor_bytes(inputs[witness])
        water = 'tests/test_water.mojo'
        inputs[water] = owner.pr776_predecessor_bytes(water, inputs[water])
        predecessors = stage.verify_registry_sources(inputs)
        self.assertEqual(set(predecessors), set(stage.EDGES))
        for path, prior in predecessors.items():
            with self.subTest(path=path):
                edge = stage.EDGES[path]
                self.assertEqual(stage.sha(prior), edge['before_sha256'])
                if path in stage.EXAMPLE_PATHS:
                    self.assertEqual(stage.sha(prior), typed.EDGES[path]['after_sha256'])
                elif path in typed.CURRENT_DEPENDENCIES:
                    self.assertEqual(stage.sha(prior), typed.CURRENT_DEPENDENCIES[path])
                else:
                    self.assertIn(path, {*stage.HAIR_SOURCE_PATHS, 'render/apng.mojo', 'generators/utils.mojo'})
                lines = prior.splitlines(keepends=True)
                for edit in edge['edits']:
                    start, before = edit['start'], edit['before']
                    self.assertEqual(lines[start:start+len(before)], before)
                    lines[start:start+len(before)] = edit['after']
                self.assertEqual(''.join(lines).encode(), inputs[path])
        probes = {paths[0] for paths in stage.REGISTRY_SCOPES.values()}
        probes |= {next(iter(stage.REGISTRY_PROVIDER_SHA256)),
                   next(iter(stage.REGISTRY_TEST_SHA256)), sorted(inputs)[-1]}
        for path in probes:
            with self.subTest(path=path), self.assertRaises(ValueError):
                stage.verify_registry_sources({**inputs, path: inputs[path]+b'\n# changed\n'})
        missing = dict(inputs)
        missing.pop(next(iter(missing)))
        for altered in (missing, {**inputs, 'unreviewed.mojo': b'pass\n'}):
            with self.assertRaises(ValueError):
                stage.verify_registry_sources(altered)

    def test_old_mixed_comment_crlf_and_unknown_endpoints_reject(self):
        for path in stage.SOURCE_PATHS:
            for altered in (self.predecessors[path], self.current[path]+'\n',
                            self.current[path].replace('\n', '\r\n')):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    stage.predecessor_source(path, altered)
            with self.assertRaises(ValueError):
                stage.verify_staged_sources({**self.inputs,
                    path: self.predecessors[path].encode('utf-8')})
        with self.assertRaises(ValueError):
            stage.predecessor_source('unreviewed.mojo', 'pass\n')

    def test_every_bound_provider_and_test_rejects_changed_bytes(self):
        for path, raw in self.inputs.items():
            with self.subTest(path=path), self.assertRaises(ValueError):
                stage.verify_staged_sources({**self.inputs, path: raw+b'\n# changed\n'})
        missing = dict(self.inputs)
        missing.pop(next(iter(missing)))
        for altered in (missing, {**self.inputs, 'unreviewed.mojo': b'pass\n'}):
            with self.assertRaises(ValueError):
                stage.verify_staged_sources(altered)

    def test_inverse_and_endpoint_mutation_cannot_extend_fixed_data(self):
        path = stage.SOURCE_PATHS[0]
        for field in ('before_sha256', 'after_sha256', 'before_token_sha256', 'after_token_sha256'):
            changed = copy.deepcopy(stage.EDGES)
            changed[path][field] = '0'*64
            with self.subTest(field=field), patch.object(stage, 'EDGES', changed), self.assertRaises(ValueError):
                stage.predecessor_source(path, self.current[path])
        for operation in ('drop', 'duplicate', 'reverse', 'span'):
            changed = copy.deepcopy(stage.EDGES)
            edits = changed[path]['edits']
            if operation == 'drop':
                edits.pop()
            elif operation == 'duplicate':
                edits.append(copy.deepcopy(edits[-1]))
            elif operation == 'reverse':
                edits.reverse()
            else:
                edits[0]['start'] += 1
            with self.subTest(operation=operation), patch.object(stage, 'EDGES', changed), self.assertRaises(ValueError):
                stage.predecessor_source(path, self.current[path])

    def test_each_fixed_data_class_refuses_late_namespace_changes(self):
        stage.verify_stage_data()
        for name in stage.DATA_NAMES:
            value = getattr(stage, name)
            changed = ({**value, 'unreviewed': None} if type(value) is dict else
                       (*value, 'unreviewed') if type(value) is tuple else 'unreviewed')
            with self.subTest(name=name), patch.object(stage, name, changed), self.assertRaises(ValueError):
                stage.verify_stage_data()
        with patch.object(stage, 'DATA_SHA256', '0'*64), self.assertRaises(ValueError):
            stage.verify_stage_data()

    def test_coordinated_table_and_digest_replacement_refused(self):
        changed = copy.deepcopy(stage.EDGES)
        changed[stage.SOURCE_PATHS[0]]['after_sha256'] = '0'*64
        payload = {name: changed if name == 'EDGES' else getattr(stage, name)
                   for name in stage.DATA_NAMES}
        replacement = hashlib.sha256(json.dumps(payload, sort_keys=True,
            separators=(',', ':')).encode()).hexdigest()
        with patch.object(stage, 'EDGES', changed), patch.object(stage, 'DATA_SHA256', replacement):
            with self.assertRaises(ValueError):
                stage.verify_stage_data()

    def test_changed_lexical_evaluator_cannot_reuse_endpoint_hash(self):
        path = stage.SOURCE_PATHS[0]
        with patch.object(stage.source, 'token_sha256', return_value='0'*64), self.assertRaises(ValueError):
            stage.predecessor_source(path, self.current[path])

    def test_bulk_inverse_authenticates_before_and_after_without_a_cache(self):
        original = stage._predecessor_source
        original_edges = stage.EDGES
        calls = []

        def change_after_first(path, text, record):
            result = original(path, text, record)
            calls.append(path)
            if len(calls) == 1:
                stage.EDGES = {**original_edges, 'unreviewed.mojo': {}}
            return result

        try:
            with patch.object(stage, '_predecessor_source', side_effect=change_after_first):
                with self.assertRaises(ValueError):
                    stage.verify_staged_sources(self.inputs)
        finally:
            stage.EDGES = original_edges
        self.assertTrue(calls)
        self.assertEqual(stage.verify_staged_sources(self.inputs), self.predecessors)

    def test_named_body_and_operation_checks_are_live(self):
        stage.verify_correspondence(self.current, self.predecessors)
        for rule in stage.OPERATION_SPANS:
            path = rule['after_path']
            altered = self.current[path].replace(rule['after'], 'unreviewed_operation\n', 1)
            with self.subTest(rule=rule['name']), self.assertRaises(ValueError):
                stage.verify_correspondence({**self.current, path: altered}, self.predecessors)

    def test_complete_example_closure_contains_tools_and_six_extra_inputs(self):
        stage.verify_example_closure(stage.EXAMPLE_CLOSURE, ('examples',))
        self.assertEqual(len(stage.EXAMPLE_CLOSURE), 333)
        self.assertTrue({'core/clock.mojo', 'generators/__init__.mojo',
                         'generators/utils.mojo', 'render/apng.mojo',
                         'tools/_example_output.mojo', 'tools/_example_preview.mojo'}
                        <= set(stage.EXAMPLE_CLOSURE))
        for altered in (stage.EXAMPLE_CLOSURE[:-1],
                        (*stage.EXAMPLE_CLOSURE, 'tools/unreviewed.mojo'),
                        (*stage.EXAMPLE_CLOSURE, stage.EXAMPLE_CLOSURE[0])):
            with self.assertRaises(ValueError):
                stage.verify_example_closure(altered, ('examples',))
        with self.assertRaises(ValueError):
            stage.verify_example_closure(stage.EXAMPLE_CLOSURE, ('tools',))


if __name__ == '__main__':
    unittest.main()
