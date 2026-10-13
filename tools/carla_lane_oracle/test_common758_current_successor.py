#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Authenticate the exact common-758 current repair and retained provenance."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

import full_audit_cleanup_contracts as audit
import typed_boundary_contracts as typed

ROOT = Path(__file__).resolve().parents[2]
SELF = 'tools/carla_lane_oracle/test_common758_current_successor.py'
HISTORICAL_AUTHORITY = 'add0cfe82b1103ee64eae23fca9340ec5500d8014309e838415d38123731931b'
EXPECTATIONS = '85020fb32ec96121aba108288eaabf41c4483e2f94e91b6beee4528af2206653'
REPAIRED = {
    'extensions/carla/geometry.mojo',
    'extensions/carla/map.mojo',
    'extensions/carla/map_builder.mojo',
    'extensions/carla/math.mojo',
    'extensions/carla/mesh_factory.mojo',
    'extensions/carla/navigation_mesh.mojo',
    'extensions/carla/opendrive.mojo',
    'extensions/carla/replayer_helper.mojo',
    'extensions/carla/road.mojo',
    'extensions/carla/traffic_manager_collision.mojo',
    'extensions/carla/traffic_manager_map.mojo',
    'tests/test_carla_junction_bounds.mojo',
    'tests/test_carla_lane_borders.mojo',
    'tests/test_carla_lane_search_positive_controls.mojo',
    'tests/test_carla_map_budget.mojo',
    'tests/test_carla_road_fixed_s.mojo',
    'tests/test_carla_support_dispatch_successor.mojo',
}
METAL_SOURCES = {
    'materials/nodes.mojo',
    'math/matrix_inverse.mojo',
    'math/scaled_products.mojo',
    'render/texture.mojo',
}
PAYLOAD_NAMES = (
    'SOURCE_PATHS', 'EDGES', 'EDGE_SHA256', 'NEW_INPUTS', 'TESTS',
    'BINDING_INPUTS', 'PRODUCTION_CLOSURE', 'NATIVE_CLOSURE',
    'TYPED_NATIVE_CLOSURE', 'TYPED_PRODUCTION_CLOSURE',
    'CURRENT_DEPENDENCIES', 'INVENTORY', 'EDGES_SHA256',
)
HISTORICAL_NAMES = (
    'EDGES', 'EDGE_SHA256', 'TESTS', 'BINDING_INPUTS',
    'CURRENT_DEPENDENCIES', 'INVENTORY', 'EDGES_SHA256',
)


def _sha(raw):
    return hashlib.sha256(raw).hexdigest()


def _historical_payload():
    return {name: getattr(typed, ('HISTORICAL_' if name in HISTORICAL_NAMES else '') + name)
            for name in PAYLOAD_NAMES}


def _previous_typed_text(path, historical_predecessor):
    """Replay the preserved old edge to recover its exact typed endpoint."""
    edge = typed.HISTORICAL_EDGES[path]
    if _sha(historical_predecessor.encode()) != edge['before_sha256']:
        raise ValueError('wrong historical predecessor')
    lines = historical_predecessor.splitlines(keepends=True)
    for start, stop, before, after in edge['edits']:
        if lines[start:start+len(before)] != before:
            raise ValueError('old forward span differs')
        lines[start:start+len(before)] = after
    result = ''.join(lines)
    if _sha(result.encode()) != edge['after_sha256']:
        raise ValueError('old endpoint differs')
    return result


class Common758CurrentSuccessor(unittest.TestCase):
    def test_all_213_historical_edges_and_authority_remain_exact(self):
        payload = _historical_payload()
        self.assertEqual(_sha(json.dumps(payload, sort_keys=True, separators=(',', ':')).encode()),
                         HISTORICAL_AUTHORITY)
        self.assertEqual(len(typed.HISTORICAL_EDGES), 213)
        self.assertEqual(set(typed.EDGES), set(typed.HISTORICAL_EDGES))
        typed.verify_authority()

    def test_current_tables_are_only_the_closed_reviewed_overrides(self):
        expected = {'EDGES': REPAIRED, 'EDGE_SHA256': REPAIRED,
                    # #746 also rebinds four unedged Metal sources.
                    'CURRENT_DEPENDENCIES': REPAIRED | METAL_SOURCES,
                    'TESTS': {p for p in REPAIRED if p.startswith('tests/')},
                    'INVENTORY': {'extensions/carla/map.mojo', 'extensions/carla/map_builder.mojo'}}
        for name, paths in expected.items():
            current, old = getattr(typed, name), getattr(typed, 'HISTORICAL_'+name)
            with self.subTest(table=name):
                self.assertEqual(set(current), set(old))
                self.assertEqual({p for p in old if old[p] != current[p]}, paths)
        self.assertIn(SELF, typed.BINDING_INPUTS)
        self.assertEqual(typed.BINDING_INPUTS[SELF], _sha((ROOT/SELF).read_bytes()))
        self.assertEqual(typed.HISTORICAL_BINDING_INPUTS['tools/compile_fail_expectations.json'],
                         EXPECTATIONS)
        # Common admission checks actual689 bytes. Each feature extension owns
        # its exact693 endpoint and six controls; all current binding entries
        # remain authenticated by the current authority and physical owner.
        typed.verify_authority()

    def test_current_endpoints_join_the_exact_original_predecessors(self):
        current = {p: (ROOT/p).read_text() for p in typed.SOURCE_PATHS}
        joined = typed.verify_sources(current)
        for path in sorted(REPAIRED):
            with self.subTest(path=path):
                predecessor = typed.predecessor_source(path, current[path])
                self.assertEqual(_sha(predecessor.encode()),
                                 typed.HISTORICAL_EDGES[path]['before_sha256'])
                previous_typed = _previous_typed_text(path, predecessor)
                self.assertNotEqual(previous_typed, current[path])
                self.assertEqual(_sha(current[path].encode()), typed.EDGES[path]['after_sha256'])
                self.assertEqual(_sha(joined[path].encode()), typed.edge(path)['before_sha256'])

    def test_old_mixed_and_modified_current_endpoints_are_refused(self):
        current = {p: (ROOT/p).read_text() for p in typed.SOURCE_PATHS}
        for path in sorted(REPAIRED):
            predecessor = typed.predecessor_source(path, current[path])
            old = _previous_typed_text(path, predecessor)
            with self.subTest(path=path):
                self.assertFalse(typed.is_current(path, old))
                with self.assertRaises(ValueError):
                    typed.predecessor_source(path, old)
                with self.assertRaises(ValueError):
                    typed.predecessor_source(path, current[path]+'\n')
                with self.assertRaises(ValueError):
                    typed.verify_sources({**current, path: old})

    def test_late_historical_and_current_namespace_mutations_are_refused(self):
        typed.verify_authority()
        for name in (*HISTORICAL_NAMES, *('HISTORICAL_'+n for n in HISTORICAL_NAMES)):
            value = getattr(typed, name)
            changed = {**value, 'unreviewed': None} if isinstance(value, dict) else '0'*64
            with self.subTest(name=name), patch.object(typed, name, changed):
                with self.assertRaises(ValueError):
                    typed.verify_authority()

    def test_inverse_and_digest_changes_cannot_authorize_a_new_endpoint(self):
        path = 'extensions/carla/map.mojo'
        altered = copy.deepcopy(typed.EDGES)
        altered[path]['after_sha256'] = '0'*64
        hashes = {**typed.EDGE_SHA256,
                  path: _sha(json.dumps(altered[path], sort_keys=True, separators=(',', ':')).encode())}
        with patch.object(typed, 'EDGES', altered), patch.object(typed, 'EDGE_SHA256', hashes):
            with self.assertRaises(ValueError):
                typed.verify_authority()
            with self.assertRaises(ValueError):
                typed.predecessor_source(path, (ROOT/path).read_text())


class Common758CurrentOwnedInputs(unittest.TestCase):
    def test_receipt_names_actual_current_repair_and_guard_bytes(self):
        result = audit.proof_bindings(ROOT)
        for path in sorted(REPAIRED | {SELF, 'tools/compile_fail_expectations.json'}):
            with self.subTest(path=path):
                self.assertEqual(result[path], _sha((ROOT/path).read_bytes()))
        for path in REPAIRED:
            self.assertNotEqual(result[path], typed.HISTORICAL_EDGES[path]['after_sha256'])

    def test_first_and_final_physical_current_map_reads_are_refused(self):
        target = ROOT/'extensions/carla/map.mojo'
        original = Path.read_bytes
        raw = target.read_bytes()
        # Map is observed during source admission, exact dependency binding,
        # and the final image reread. Exercise the first and final observations.
        for at_read in (1, 3):
            reads = []
            def changed(path, *args, **kwargs):
                if (path == target and sys._getframe(1).f_code is
                        audit._typed_boundary_bindings.__code__):
                    reads.append(path)
                    return raw+b'\n' if len(reads) == at_read else raw
                return original(path, *args, **kwargs)
            with self.subTest(at_read=at_read), patch.object(Path, 'read_bytes', changed):
                with self.assertRaises(ValueError):
                    audit._typed_boundary_bindings(ROOT)
            self.assertEqual(len(reads), at_read)
            self.assertEqual(target.read_bytes(), raw)


if __name__ == '__main__':
    unittest.main()
