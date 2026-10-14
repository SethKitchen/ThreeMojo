# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Coverage scheduling and progress must preserve all suites and records."""

import contextlib
import gzip
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import coverage_io

PROFILE = Path(__file__).with_name('coverage_costs.json')


class CoverageSchedulingTests(unittest.TestCase):
    # tools/coverage_shard.mojo reads the profile; tests/test_shard_tool.mojo
    # tests its checks and the schedule.
    def test_profile_records_every_measured_suite(self):
        costs = json.loads(PROFILE.read_text())['seconds']
        self.assertEqual(len(costs), 718)
        self.assertEqual(costs['tests/test_hair_styles.mojo'], 1471.6)
        self.assertEqual(costs['tests/test_carla_map.mojo'], 5354.3)

    def test_timeout_is_labeled_as_a_lower_bound_not_a_completed_cost(self):
        profile = json.loads(PROFILE.read_text())
        self.assertEqual(profile['source_run_attempt'], 1)
        self.assertEqual(profile['workers_per_shard'], 4)
        self.assertEqual(profile['completed_measurements'], 717)
        estimates = profile['scheduling_estimates']
        self.assertEqual(set(estimates), {'tests/test_carla_recorder_world.mojo'})
        estimate = estimates['tests/test_carla_recorder_world.mojo']
        self.assertEqual(estimate['kind'], 'right_censored_timeout_lower_bound')
        self.assertEqual(estimate['exit_code'], 124)
        self.assertEqual(estimate['seconds'], 8281.5)
        self.assertEqual(estimate['last_completed_capture']['seconds'], 6622.2)
        self.assertEqual(profile['seconds']['tests/test_carla_recorder_world.mojo'],
                         estimate['seconds'])

    def test_progress_is_flushed_without_modifying_records_or_status(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            # Each phase waits for the parent's heartbeat. No assertion
            # depends on which thread a loaded CI runner schedules first.
            command = [sys.executable, '-c',
                       'import sys,time,pathlib\n'
                       'for index in range(2):\n'
                       ' marker=pathlib.Path(sys.argv[1])/str(index)\n'
                       ' deadline=time.monotonic()+10\n'
                       ' while not marker.exists():\n'
                       '  if time.monotonic()>deadline: raise RuntimeError("heartbeat missing")\n'
                       '  time.sleep(.001)\n'
                       ' if index==0: sys.stderr.write("COVLINE:m:1\\n");sys.stderr.flush()\n'
                       'print("diagnostic");sys.exit(7)', str(root)]
            def acknowledge(*args, **kwargs):
                if args and 'running;' in str(args[0]):
                    phase = '0' if 'waiting for probes' in str(args[0]) else '1'
                    (root / phase).touch()
            with patch('builtins.print', side_effect=acknowledge) as output:
                result = coverage_io.capture(command, root / 'test_one.out', root / 'err.gz', progress_interval=.02)
            self.assertEqual(result, 7)
            messages = [str(call.args[0]) for call in output.call_args_list if call.args]
            progress = [call for call in output.call_args_list if call.args and str(call.args[0]).startswith('Coverage ')]
            self.assertTrue(all(call.kwargs.get('flush') for call in progress))
            self.assertTrue(any('start;' in text for text in messages))
            self.assertTrue(any('running;' in text and 'waiting for probes' in text for text in messages))
            self.assertTrue(any('first probe;' in text for text in messages))
            self.assertTrue(any('running;' in text and 'runtime probes observed' in text for text in messages))
            self.assertTrue(any('complete (exit 7)' in text for text in messages))
            self.assertEqual((root / 'test_one.out').read_text(), 'diagnostic\n')
            self.assertEqual(gzip.decompress((root / 'err.gz').read_bytes()), b'COVLINE:m:1\n')

    def test_progress_stops_on_spawn_failure(self):
        with tempfile.TemporaryDirectory() as folder, patch('builtins.print') as output:
            root = Path(folder)
            with self.assertRaises(FileNotFoundError):
                coverage_io.capture(['/no/such/coverage-command'], root / 'out', root / 'err.gz')
            self.assertTrue(any('aborted;' in str(call) for call in output.call_args_list))


if __name__ == '__main__':
    unittest.main()
