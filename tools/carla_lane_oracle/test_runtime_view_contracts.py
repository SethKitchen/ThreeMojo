# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact #333 runtime-view steps extend the boundary edges and nothing else."""
import hashlib
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import border_parser_contracts as border
import runtime_boundary_contracts as boundary
import runtime_view_contracts as view
import winner_sign_contracts as winner
import full_audit_cleanup_contracts as audit

ROOT = Path(__file__).resolve().parents[2]


def patched_bytes(target, changed):
    read = Path.read_bytes
    return patch.object(Path, 'read_bytes',
                        lambda p, *a, **k: changed if p == target else read(p, *a, **k))


class RuntimeViewSuccessorTests(unittest.TestCase):
    def test_steps_start_at_the_boundary_edges_and_compose(self):
        steps = view.steps(ROOT)
        self.assertEqual(set(steps), set(view.MODULES))
        self.assertTrue(set(view.MODULES) <= set(boundary.MODULES))
        record = json.loads((ROOT/boundary.MIGRATION).read_text())['edges']
        edges = boundary.verify(ROOT)
        parser = json.loads((ROOT/border.MIGRATION).read_text())['unchanged_inputs']
        for path, step in steps.items():
            self.assertEqual(step['before_sha256'], record[path]['after_sha256'])
            self.assertEqual(step['before_token_sha256'], record[path]['after_token_sha256'])
            live = (ROOT/path).read_bytes()
            self.assertEqual(hashlib.sha256(live).hexdigest(), step['after_sha256'])
            # The composed edge runs from the historical digest to the live one.
            self.assertEqual(edges[path]['before_sha256'], parser[path])
            self.assertEqual(edges[path]['after_sha256'], step['after_sha256'])
        for path in set(boundary.MODULES) - set(view.MODULES):
            self.assertEqual(edges[path]['after_sha256'], record[path]['after_sha256'])
        border.verify(ROOT)
        winner.verify(ROOT)

    def test_record_and_bound_test_mutation_revokes(self):
        for name in view.PROTECTED_INPUTS:
            target = ROOT/name
            with self.subTest(name=name), patched_bytes(target, target.read_bytes() + b' '):
                with self.assertRaises(ValueError):
                    view.steps(ROOT)
                with self.assertRaises(ValueError):
                    boundary.verify(ROOT)

    def test_a_changed_or_reverted_consumer_fails_closed(self):
        for name in view.MODULES:
            target = ROOT/name
            for change in (b'\n# unreviewed\n', None):
                payload = (target.read_bytes() + change if change is not None
                           else (ROOT/name).read_bytes().replace(b'Duration64', b'Float64'))
                with self.subTest(name=name, change=change), patched_bytes(target, payload):
                    for consumer in (boundary, border, winner):
                        with self.assertRaises(ValueError):
                            consumer.verify(ROOT)

    def test_a_step_that_does_not_extend_its_edge_refuses(self):
        raw = (ROOT/view.MIGRATION).read_bytes()
        record = json.loads(raw)
        path = view.MODULES[0]
        # Skip the reviewed edge: start at its historical digest instead.
        edge = json.loads((ROOT/boundary.MIGRATION).read_text())['edges'][path]
        record['steps'][path]['before_sha256'] = edge['before_sha256']
        forged = json.dumps(record, indent=2).encode() + b'\n'
        sealed = hashlib.sha256(forged).hexdigest()
        with patched_bytes(ROOT/view.MIGRATION, forged), \
                patch.object(view, 'MIGRATION_SHA256', sealed):
            # The forged step is well formed, but no longer starts at the edge.
            self.assertIn(path, view.steps(ROOT))
            with self.assertRaisesRegex(ValueError, 'does not extend the edge'):
                boundary.verify(ROOT)

    def test_malformed_scope_refuses(self):
        raw = (ROOT/view.MIGRATION).read_bytes()
        for mutate in (lambda r: r.update(issue=306),
                       lambda r: r['steps'].pop(view.MODULES[1]),
                       lambda r: r['correctness_tests'].pop(view.TESTS[0]),
                       lambda r: r['steps'][view.MODULES[0]].update(extra='x'),
                       lambda r: r['steps'][view.MODULES[0]].update(
                           after_sha256=r['steps'][view.MODULES[0]]['before_sha256'])):
            record = json.loads(raw)
            mutate(record)
            forged = json.dumps(record, indent=2).encode() + b'\n'
            with self.subTest(mutate=mutate), \
                    patched_bytes(ROOT/view.MIGRATION, forged), \
                    patch.object(view, 'MIGRATION_SHA256', hashlib.sha256(forged).hexdigest()):
                with self.assertRaises(ValueError):
                    view.steps(ROOT)


class RuntimeViewBindingControls(unittest.TestCase):
    def test_every_missing_record_or_fixture_preserves_the_public_read_error(self):
        read = Path.read_bytes
        for name in view.PROTECTED_INPUTS:
            target = ROOT/name
            def missing(path, *args, **kwargs):
                if path == target:
                    raise FileNotFoundError(str(target))
                return read(path, *args, **kwargs)
            with self.subTest(path=name), patch.object(Path, 'read_bytes', missing):
                with self.assertRaises(FileNotFoundError):
                    view.steps(ROOT)

    def test_live_checker_code_is_bound_and_restoration_reinstates_identity(self):
        original = view.steps.__code__
        def forged(root, *, _operation=None):
            return {}
        try:
            view.steps.__code__ = forged.__code__
            with self.assertRaisesRegex(ValueError, 'executing function changed'):
                audit.executing_checker_bindings()
        finally:
            view.steps.__code__ = original
        self.assertIn('tools/carla_lane_oracle/runtime_view_contracts.py',
                      audit.executing_checker_bindings())

    def test_current_receipt_names_actual_runtime_view_authority_and_all_fixtures(self):
        bindings = audit.proof_bindings(ROOT)
        for name in (*view.PROTECTED_INPUTS,
                     'tools/carla_lane_oracle/runtime_view_contracts.py'):
            with self.subTest(path=name):
                self.assertEqual(bindings[name], hashlib.sha256((ROOT/name).read_bytes()).hexdigest())


class RuntimeViewOwnedInputControls(unittest.TestCase):
    from test_invariant_operation_inputs import BoundedOwnerCurrentControls as _owners
    setUp = _owners.setUp
    audit = _owners.audit
    assert_closed = _owners.assert_closed

    def test_consumed_record_and_fixture_mutations_remain_sticky_after_restore(self):
        for name in (view.MIGRATION, view.TESTS[0], view.FIXTURES[0]):
            def consume(operation):
                target = self.root/name
                with patched_bytes(target, target.read_bytes() + b' '):
                    with self.assertRaises(audit._OperationCoherenceError):
                        view.steps(self.root, _operation=operation)
                self.assertTrue(operation._failed)
                with self.assertRaises(audit._OperationCoherenceError):
                    view.steps(self.root, _operation=operation)
            with self.subTest(path=name), self.audit(callback=consume) as events:
                with self.assertRaises(ValueError):
                    winner.verify(self.root)
            self.assertEqual(len(events['admissions']), 1)
            self.assert_closed(events['admissions'][0])

    def test_caught_missing_reads_poison_the_real_owner_before_restoration(self):
        read = Path.read_bytes
        for name in (view.MIGRATION, view.TESTS[0]):
            def consume(operation):
                target = self.root/name
                def missing(path, *args, **kwargs):
                    if path == target:
                        raise FileNotFoundError(str(target))
                    return read(path, *args, **kwargs)
                with patch.object(Path, 'read_bytes', missing):
                    with self.assertRaises(audit._OperationCoherenceError) as caught:
                        view.steps(self.root, _operation=operation)
                self.assertIs(type(caught.exception.__cause__), FileNotFoundError)
                self.assertTrue(operation._failed)
                with self.assertRaises(audit._OperationCoherenceError):
                    view.steps(self.root, _operation=operation)
            with self.subTest(path=name), self.audit(callback=consume) as events:
                with self.assertRaises(ValueError):
                    winner.verify(self.root)
            self.assertEqual(len(events['admissions']), 1)
            self.assert_closed(events['admissions'][0])

    def test_final_checkpoint_rejects_changes_after_the_last_view_read(self):
        from functools import wraps
        checkpoint = audit._CacheInputs.checkpoint
        for name in (view.MIGRATION, view.TESTS[0]):
            target = self.root/name
            original = target.read_bytes()
            operations = []
            @wraps(checkpoint)
            def at_finish(owner, caller, root):
                self.assertEqual(owner._state, 'active')
                self.assertEqual(owner._kind, 'winner')
                operations.append(owner)
                target.write_bytes(original + b' ')
                return checkpoint(owner, caller, root)
            try:
                with self.subTest(path=name), patch.object(audit._CacheInputs, 'checkpoint', at_finish):
                    with self.assertRaisesRegex(ValueError, 'owned input changed'):
                        winner.verify(self.root)
            finally:
                target.write_bytes(original)
            self.assertEqual(len(operations), 1)
            self.assertTrue(operations[0]._failed)
            self.assert_closed(operations[0])


if __name__ == '__main__':
    unittest.main()
