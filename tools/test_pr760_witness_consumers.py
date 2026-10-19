# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact witness transition controls for physical consumers and test fixtures."""
from pathlib import Path
import unittest

from carla_lane_oracle import _full_audit_test_fixtures as fixtures
from carla_lane_oracle import full_audit_cleanup_contracts as owner

ROOT = Path(__file__).resolve().parents[1]
WITNESS = 'tools/carla_lane_oracle/test_witness_format_contracts.py'


class WitnessConsumerTransitions(unittest.TestCase):
    def test_typed_edges_keep_physical_receipts_and_reject_other_endpoints(self):
        root = fixtures.copy_current_root(self, ROOT)
        target = root/WITNESS
        raw = target.read_bytes()
        archive = owner.qualification_predecessor_bytes(WITNESS, raw)
        immutable = owner.typed_boundary.predecessor_source(WITNESS, archive.decode()).encode()
        self.assertEqual(owner.sha(archive), owner.typed_boundary.EDGES[WITNESS]['after_sha256'])
        self.assertEqual(owner.sha(immutable), owner.witness_format.BOUND_INPUTS[WITNESS])
        edge = owner.typed_successor_edges(root)[WITNESS]
        self.assertEqual(edge['before_sha256'], owner.sha(immutable))
        self.assertEqual(edge['after_sha256'], owner.sha(raw))
        self.assertEqual(edge['after_token_sha256'], owner.source.token_sha256(raw.decode()))
        for changed in (archive, immutable, raw+b'\n'):
            try:
                target.write_bytes(changed)
                with self.subTest(mutation=owner.sha(changed)), self.assertRaises(owner.ContractError):
                    owner.typed_successor_edges(root)
            finally:
                target.write_bytes(raw)
        self.assertEqual(owner.typed_successor_edges(root)[WITNESS], edge)

    def test_repeated_historical_transport_preserves_exact_pretyped_witness(self):
        historical = fixtures.copy_historical_boundary_root(self, ROOT)
        raw = (historical/WITNESS).read_bytes()
        self.assertEqual(owner.sha(raw), owner.typed_boundary.EDGES[WITNESS]['before_sha256'])
        # The qualification inverse must not grow a third accepted endpoint.
        with self.assertRaises(owner.ContractError):
            owner.qualification_predecessor_bytes(WITNESS, raw)
        again = fixtures.copy_historical_boundary_root(self, historical)
        self.assertEqual((again/WITNESS).read_bytes(), raw)
        target = historical/WITNESS
        try:
            target.write_bytes(raw+b'\n')
            with self.assertRaises(owner.ContractError):
                fixtures.copy_historical_boundary_root(self, historical)
        finally:
            target.write_bytes(raw)
        restored = fixtures.copy_historical_boundary_root(self, historical)
        self.assertEqual((restored/WITNESS).read_bytes(), raw)


if __name__ == '__main__':
    unittest.main()
