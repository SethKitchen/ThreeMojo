"""Fail-closed controls for the bounded lane successor migration."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest

import lane_control_contracts as contract


class LaneControlContracts(unittest.TestCase):
    def setUp(self):
        self.source = Path(__file__).resolve().parents[2]
        self.temp = tempfile.TemporaryDirectory(prefix='lane-migration-')
        self.root = Path(self.temp.name)
        record = contract.verify(self.source)
        files = {record['module'], *record['producer_modules'],
                 'tests/test_carla_lane_control_successor.mojo',
                 'tools/carla_lane_oracle/lane-control-migration.json'}
        for rel in files:
            dest = self.root / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.source / rel, dest)

    def tearDown(self):
        self.temp.cleanup()

    def test_exact_record_accepts_only_bound_predecessor(self):
        record = contract.verify(self.root)
        for item in record['declarations']:
            self.assertTrue(contract.accepts_predecessor(self.root, item['path'], item['name'], (), item['before']))
            self.assertFalse(contract.accepts_predecessor(self.root, item['path'], item['name'], ('Other',), item['before']))
            self.assertFalse(contract.accepts_predecessor(self.root, item['path'], item['name'], (), item['before'].replace('return', 'raise', 1)))

    def test_mutated_premises_are_rejected(self):
        mutations = [
            ('extensions/carla/lane_refinement.mojo', 'if task[2] >= max_depth:', 'if task[2] > max_depth:'),
            ('extensions/carla/lane_refinement.mojo', 'if lo < sampled_cuts.value()[0]', 'if lo <= sampled_cuts.value()[0]'),
            ('extensions/carla/lane_refinement.mojo', 'bitcast[DType.uint64](split_at) - UInt64(1)', 'bitcast[DType.uint64](split_at) - UInt64(2)'),
            ('extensions/carla/lane_refinement.mojo', '    _require_sum2_environment()', '    pass'),
            ('extensions/carla/curve_interval.mojo', 'bits + 1', 'bits + 2'),
            ('extensions/carla/curve_sum2.mojo', 'raise Error(', 'print('),
            ('tests/test_carla_lane_control_successor.mojo', 'if interior > low and interior < high:', 'if interior > low or interior < high:'),
            ('tools/carla_lane_oracle/lane-control-migration.json', 'Five redundant predicates', 'Four redundant predicates'),
        ]
        for rel, old, new in mutations:
            with self.subTest(path=rel, mutation=old):
                path = self.root / rel
                before = path.read_text()
                self.assertIn(old, before)
                path.write_text(before.replace(old, new, 1))
                with self.assertRaises(RuntimeError):
                    contract.verify(self.root)
                path.write_text(before)


if __name__ == '__main__':
    unittest.main()
