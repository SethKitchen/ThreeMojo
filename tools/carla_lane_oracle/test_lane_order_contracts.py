"""Fail closed if any finite-order proof premise or routing changes."""
from pathlib import Path
import shutil
import tempfile
import unittest

import lane_order_contracts as contract


class LaneOrderContracts(unittest.TestCase):
    def setUp(self):
        self.source = Path(__file__).resolve().parents[2]
        self.temp = tempfile.TemporaryDirectory(prefix='lane-order-')
        self.root = Path(self.temp.name)
        record = contract.verify(self.source)
        paths = {record['module'], *record['premise_modules'], *record['inventory'], *record['immutable_predecessor_records'],
                 'tools/carla_lane_oracle/lane-order-migration.json',
                 'tests/test_carla_lane_order_successor.mojo'}
        import cache_key_contracts as cache_key
        paths.update(cache_key.PROTECTED_INPUTS)
        for rel in paths:
            dest = self.root / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.source / rel, dest)

    def tearDown(self):
        self.temp.cleanup()

    def test_exact_predecessor_restoration(self):
        record = contract.verify(self.root)
        self.assertEqual(contract.predecessor_source(self.root), record['before'])

    def test_source_premise_mutations(self):
        lane = 'extensions/carla/lane_refinement.mojo'
        mutations = [
            (lane, 'if not (isfinite(low) and isfinite(high) and isfinite(seed)):', 'if not isfinite(seed):'),
            (lane, 'or cell.high < cell.low', 'or cell.high > cell.low'),
            (lane, 'return (certificate.low, certificate.high, certificate.depth)', 'return (certificate.high, certificate.low, certificate.depth)'),
            (lane, 'var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 0)]', 'var pending: List[Tuple[Float64, Float64, Int]] = [(high, low, 0)]'),
            (lane, 'return low + span * 0.5', 'return low - span * 0.5'),
            (lane, 'if lo < sampled_cuts.value()[0]', 'if lo <= sampled_cuts.value()[0]'),
            (lane, 'bitcast[DType.uint64](split_at) - UInt64(1)', 'bitcast[DType.uint64](split_at) - UInt64(2)'),
            (lane, 'pending.append((lo, middle, task[2] + 1))', 'pending.append((middle, lo, task[2] + 1))'),
            ('extensions/carla/curve_minimizer_support.mojo', 'result.high = min(result.high, limit.high)', 'result.high = max(result.high, limit.high)'),
            ('extensions/carla/curve_interval.mojo', 'bits + 1', 'bits + 2'),
            ('extensions/carla/curve_sum2.mojo', 'raise Error(', 'print('),
            ('tests/test_carla_lane_order_successor.mojo', 'if lo > 0.0 and isfinite(hi) and hi >= lo:', 'if lo > 0.0:'),
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

    def test_new_unchecked_production_caller_is_rejected(self):
        path = self.root / 'new_namespace/unchecked.mojo'
        path.parent.mkdir()
        path.write_text('from extensions.carla.lane_refinement import _run_lane_search as unchecked\n')
        with self.assertRaises(RuntimeError):
            contract.verify(self.root)


if __name__ == '__main__':
    unittest.main()
