# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Coverage scheduling and progress must preserve all suites and records."""

import gzip
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import coverage_io


class CoverageSchedulingTests(unittest.TestCase):
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
