# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact #333 consumer edges extend both pinned records and nothing else."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import border_parser_contracts as border
import runtime_boundary_contracts as boundary
import winner_sign_contracts as winner

ROOT = Path(__file__).resolve().parents[2]


def patched_bytes(target, changed):
    read = Path.read_bytes
    return patch.object(Path, 'read_bytes',
                        lambda p, *a, **k: changed if p == target else read(p, *a, **k))


class RuntimeBoundarySuccessorTests(unittest.TestCase):
    def test_exact_edges_start_at_both_historical_records(self):
        edges = boundary.verify(ROOT)
        self.assertEqual(set(edges), set(boundary.MODULES))
        parser = json.loads((ROOT/border.MIGRATION).read_text())['unchanged_inputs']
        query = json.loads((ROOT/winner.MIGRATION).read_text())['canonical_source_unchanged']
        for path, edge in edges.items():
            self.assertEqual(edge['before_sha256'], parser[path])
            self.assertEqual(edge['before_sha256'], query[path])
            self.assertNotEqual(edge['before_sha256'], edge['after_sha256'])
        border.verify(ROOT)
        winner.verify(ROOT)

    def test_each_consumer_record_and_bound_test_mutation_revokes(self):
        for name in (*boundary.MODULES, *boundary.TESTS, boundary.MIGRATION):
            target = ROOT/name
            with self.subTest(name=name), patched_bytes(target, target.read_bytes() + b' '):
                with self.assertRaises(ValueError):
                    boundary.verify(ROOT)

    def test_both_records_refuse_a_changed_boundary_consumer(self):
        for name in boundary.MODULES:
            target = ROOT/name
            for consumer in (border, winner):
                with self.subTest(name=name, consumer=consumer.__name__), \
                        patched_bytes(target, target.read_bytes() + b'\n# unreviewed\n'):
                    with self.assertRaises(ValueError):
                        consumer.verify(ROOT)

    def test_other_pinned_consumers_stay_fail_closed(self):
        parser = json.loads((ROOT/border.MIGRATION).read_text())['unchanged_inputs']
        query = json.loads((ROOT/winner.MIGRATION).read_text())['canonical_source_unchanged']
        others = sorted(p for p in parser if p.endswith('.mojo') and p in query
                        and p not in boundary.MODULES and p != border.MODULE
                        and p != 'extensions/carla/map.mojo')
        target = ROOT/others[0]
        for consumer in (border, winner):
            with self.subTest(consumer=consumer.__name__), \
                    patched_bytes(target, target.read_bytes() + b'\n# unreviewed\n'):
                with self.assertRaises(ValueError):
                    consumer.verify(ROOT)


if __name__ == '__main__':
    unittest.main()
