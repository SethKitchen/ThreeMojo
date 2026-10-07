# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Reject altered profile evidence in normal and optimized Python."""
import os
from pathlib import Path
import subprocess
import sys
import unittest

PROGRAM = r'''
from types import SimpleNamespace
import sys
from check_coverage_hit_profile import validate_capture, validate_streams
mode = sys.argv[1]
stdout = 'Running 2 tests for fixture.mojo\n    PASS [ 1.000 ] test_phase\n    PASS [ 1.000 ] test_vectors\nSummary [ 2.000 ] 2 tests run: 2 passed , 0 failed , 0 skipped\n'
warm = 'COVLINE:fact:1\n' + 'COVLINE:diagnostic:1\n' * 3 + 'COVEVAL2:runtime:decision:F:TF;\n' + 'COVEVAL2:cached:3:F:TF;\n' * 3
cold = 'COVEVAL2:compile:decision:F:TF;\n' + warm
streams = {(p,c):cold if c == 'cold' else warm for p in ['raw','aot','aot-hits'] for c in ['cold','warm']}
identities = {(p,s):s+'\nargument\ncwd\n' for p in ['raw','aot','aot-hits'] for s in ['absolute','relative']}
if mode == 'missing-vector':
    streams['aot-hits','cold'] = streams['aot-hits','cold'].replace('COVEVAL2:cached:3:F:TF;\n','',1)
elif mode == 'changed-vector':
    streams['aot-hits','cold'] = streams['aot-hits','cold'].replace('cached:3:F:TF','cached:3:T:TT')
elif mode == 'lost-hit':
    streams['aot-hits','warm'] = streams['aot-hits','warm'].replace('COVLINE:fact:1\n','')
elif mode == 'slow':
    stdout = stdout.replace('1.000','5001.000',1)
elif mode == 'missing-results':
    stdout = 'program exited without test results\n'
elif mode == 'changed-argv':
    identities['aot-hits','relative'] = 'wrong argv0\n'
elif mode == 'missing-diagnostic':
    streams['aot-hits','cold'] = streams['aot-hits','cold'].replace('COVLINE:diagnostic:1\n','',1)
elif mode == 'wrong-cache-phase':
    streams['aot-hits','warm'] = cold
try:
    for (profile,phase),stream in streams.items():
        validate_capture(SimpleNamespace(stdout=stdout,stderr=stream),phase)
    validate_streams(streams,['raw','aot','aot-hits'],identities,['absolute','relative'])
except RuntimeError:
    if mode == 'valid':
        raise
    print('REJECTED')
else:
    if mode != 'valid':
        raise SystemExit('altered evidence was accepted')
    print('VALID')
'''


class OptimizedProfileChecks(unittest.TestCase):
    def test_evidence_mutations_fail_closed_in_both_python_modes(self):
        environment = dict(os.environ)
        environment['PYTHONPATH'] = str(Path(__file__).resolve().parent)
        modes = ['valid', 'missing-vector', 'changed-vector', 'lost-hit', 'slow',
                 'missing-results', 'changed-argv', 'missing-diagnostic',
                 'wrong-cache-phase']
        for optimized in (False, True):
            for mode in modes:
                with self.subTest(optimized=optimized, mode=mode):
                    command = [sys.executable, *(['-O'] if optimized else []),
                               '-B', '-c', PROGRAM, mode]
                    result = subprocess.run(command, env=environment,
                                            text=True, capture_output=True,
                                            timeout=5)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(),
                                     'VALID' if mode == 'valid' else 'REJECTED')


if __name__ == '__main__':
    unittest.main()
