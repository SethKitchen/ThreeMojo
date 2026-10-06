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
import coverage_shard


class CoverageSchedulingTests(unittest.TestCase):
    def test_profile_is_positive_finite_and_complete_for_recorded_suites(self):
        costs = coverage_shard.load_costs(coverage_shard.PROFILE)
        self.assertEqual(len(costs), 525)
        self.assertGreater(costs['tests/test_hair_styles.mojo'], 4000)

    def test_rejects_invalid_costs_and_duplicate_keys(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'costs.json'
            for value in [0, -1, float('nan'), float('inf'), True, '4', None]:
                path.write_text(json.dumps({'seconds': {'tests/test_a.mojo': value}}))
                with self.assertRaises(ValueError):
                    coverage_shard.load_costs(path)
            path.write_text('{"seconds":{"tests/test_a.mojo":1,"tests/test_a.mojo":2}}')
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                coverage_shard.load_costs(path)
            for name in ['../test_a.mojo', 'tests/test_a/../b.mojo', 'tests/a.mojo']:
                path.write_text(json.dumps({'seconds': {name: 1}}))
                with self.assertRaises(ValueError):
                    coverage_shard.load_costs(path)

    def test_partition_is_complete_deterministic_and_longest_first(self):
        costs = coverage_shard.load_costs(coverage_shard.PROFILE)
        suites = list(costs)
        groups = coverage_shard.schedule(suites, 6, costs, lambda suite: 1000)
        self.assertEqual(sorted(sum(groups, [])), sorted(suites))
        self.assertEqual(len(set(sum(groups, []))), len(suites))
        self.assertEqual(groups, coverage_shard.schedule(list(reversed(suites)), 6, costs, lambda suite: 1000))
        for group in groups:
            self.assertEqual(group, sorted(group, key=lambda suite: (-costs[suite], suite)))

    def test_unknown_suites_and_empty_groups_are_kept(self):
        costs = {'known': 20}
        sizes = {'known': 200, 'new': 400, 'tiny': 1}
        groups = coverage_shard.schedule(list(sizes), 5, costs, sizes.__getitem__)
        self.assertEqual(groups, [['new'], ['known'], ['tiny'], [], []])
        self.assertEqual(coverage_shard.schedule([], 2, costs, sizes.__getitem__), [[], []])
        self.assertEqual(coverage_shard.schedule(['new'], 1, {}, sizes.__getitem__), [['new']])
        with self.assertRaises(ValueError):
            coverage_shard.schedule(['new', 'new'], 1, costs, sizes.__getitem__)
        with self.assertRaises(ValueError):
            coverage_shard.schedule(['new'], 0, costs, sizes.__getitem__)

    def test_cpu_shard_keeps_its_existing_input_order(self):
        # Coverage adds a separate scheduler; the CPU CLI keeps path order.
        import shard
        suites = ['tests/test_clock.mojo', 'tests/test_color_utils.mojo']
        with patch('affected.mojo_files', return_value=suites), \
                patch('os.path.getsize', return_value=100), \
                patch('shard.weight', return_value=100), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(shard.main(['1/1', *suites]), 0)
        self.assertEqual(output.getvalue().split(), suites)

    def test_invalid_cli_fails_closed(self):
        with contextlib.redirect_stderr(io.StringIO()):
            for args in [[], ['0/6'], ['7/6'], ['1/0'], ['x/6'], ['1/2/3']]:
                self.assertEqual(coverage_shard.main(args), 2)

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

    def test_absent_profile_fails_closed(self):
        with tempfile.TemporaryDirectory() as folder, \
                patch('coverage_shard.PROFILE', Path(folder) / 'absent.json'), \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(coverage_shard.main(['1/1', 'tests/test_new.mojo']), 2)

    def test_progress_stops_on_spawn_failure(self):
        with tempfile.TemporaryDirectory() as folder, patch('builtins.print') as output:
            root = Path(folder)
            with self.assertRaises(FileNotFoundError):
                coverage_io.capture(['/no/such/coverage-command'], root / 'out', root / 'err.gz')
            self.assertTrue(any('aborted;' in str(call) for call in output.call_args_list))


if __name__ == '__main__':
    unittest.main()
