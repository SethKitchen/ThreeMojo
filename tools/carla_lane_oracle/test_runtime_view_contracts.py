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


if __name__ == '__main__':
    unittest.main()
