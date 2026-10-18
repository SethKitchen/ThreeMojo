# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Caller snapshot order cannot change the current candidate binding projection."""
from pathlib import Path
import unittest

from carla_lane_oracle import full_audit_cleanup_contracts as owner

ROOT = Path(__file__).resolve().parents[1]


class CandidateBindingOrderControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expected = owner._pr760_candidate_bindings(ROOT)['bindings']

    def test_reversed_complete_prefill_keeps_exact_order_and_values(self):
        snapshots = {path: (ROOT / path).read_bytes()
                     for path in reversed(self.expected)}
        before = dict(snapshots)
        actual = owner._pr760_candidate_bindings(ROOT, _snapshots=snapshots)['bindings']
        self.assertEqual(list(actual.items()), list(self.expected.items()))
        self.assertEqual(list(actual), sorted(actual))
        self.assertEqual(snapshots, before)

    def test_stale_consumed_prefill_still_refuses(self):
        path = 'examples/carla.mojo'
        self.assertIn(path, self.expected)
        with self.assertRaisesRegex(owner.ContractError, 'PR760 source changed before entry census'):
            owner._pr760_candidate_bindings(ROOT,
                _snapshots={path: (ROOT / path).read_bytes() + b'\n# stale observation\n'})

    def test_inherited_only_prefill_keeps_final_freshness_check(self):
        path = 'README.md'
        self.assertNotIn(path, self.expected)
        raw = (ROOT / path).read_bytes()
        actual = owner._pr760_candidate_bindings(ROOT, _snapshots={path: raw})['bindings']
        self.assertEqual(actual[path], owner.sha(raw))
        self.assertEqual(set(actual), set(self.expected) | {path})
        with self.assertRaisesRegex(owner.ContractError, 'PR760 source changed after consumption'):
            owner._pr760_candidate_bindings(ROOT,
                _snapshots={path: raw + b'\n# stale inherited observation\n'})


if __name__ == '__main__':
    unittest.main()
