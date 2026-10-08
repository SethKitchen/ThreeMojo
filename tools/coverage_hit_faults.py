#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check evidence sources without compiling; --compile-run is explicit opt-in."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile


def require(condition, message):
    """Keep evidence checks active under optimized Python too."""
    if not condition:
        raise RuntimeError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parent / 'coverage_hit_cache.c')
    parser.add_argument('--cc', default=os.environ.get('CC', 'cc'))
    parser.add_argument('--compile-run', action='store_true')
    parser.add_argument('--build-dir', type=Path)
    parser.add_argument('--receipt', type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    harness = Path(__file__).resolve().parent / 'fixtures/coverage_hit_transport_faults.c'
    source_bytes = source.read_bytes()
    harness_bytes = harness.read_bytes()
    text = source_bytes.decode()
    # These are source preflight assertions, not execution of C semantics.
    require('if ((device || inode) && !enabled)\n        abort();' in text, "qualification check failed: 'if ((device || inode) && !enabled)\\n        abort();' in text")
    require(text.index('write_record(probe_sink, bytes, size);') < text.index('memcpy(slot->bytes, bytes, size);'), "qualification check failed: text.index('write_record(probe_sink, bytes, size);') < text.index('memcpy(slot->bytes, bytes, size);')")
    require('pthread_atfork(NULL, NULL, child_after_fork)' in text, "qualification check failed: 'pthread_atfork(NULL, NULL, child_after_fork)' in text")
    require('O_WRONLY | O_NONBLOCK | O_CLOEXEC' in text, "qualification check failed: 'O_WRONLY | O_NONBLOCK | O_CLOEXEC' in text")
    require(text.count('memcpy(slot->bytes, bytes, size);') == 1, "qualification check failed: text.count('memcpy(slot->bytes, bytes, size);') == 1")
    require('#include TRANSPORT_SOURCE' in harness_bytes.decode(), "qualification check failed: '#include TRANSPORT_SOURCE' in harness_bytes.decode()")
    result = {
        'source': str(source),
        'source_sha256': hashlib.sha256(source_bytes).hexdigest(),
        'harness_sha256': hashlib.sha256(harness_bytes).hexdigest(),
        'source_preflight': 'passed',
        'native_harness': 'not compiled or run',
    }
    if args.compile_run:
        compiler = shlex.split(args.cc)
        if not compiler:
            raise ValueError('empty compiler command')
        if args.build_dir is not None:
            args.build_dir.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='transport-review-', dir=args.build_dir) as directory:
            executable = Path(directory) / 'transport-fault-harness'
            command = [*compiler, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pthread',
                       '-DTRANSPORT_SOURCE=' + json.dumps(str(source)), str(harness), '-o', str(executable)]
            build = subprocess.run(command, capture_output=True, text=True, timeout=30)
            result.update(compile_command=command, compile_returncode=build.returncode,
                          compile_stdout=build.stdout, compile_stderr=build.stderr)
            if build.returncode == 0:
                completed = subprocess.run([str(executable)], capture_output=True, text=True, timeout=5)
                result.update(native_harness='passed' if completed.returncode == 0 else 'failed',
                              run_returncode=completed.returncode, run_stdout=completed.stdout,
                              run_stderr=completed.stderr)
            else:
                result['native_harness'] = 'compile failed'
    result['source_unchanged'] = source.read_bytes() == source_bytes
    require(result['source_unchanged'], "qualification check failed: result['source_unchanged']")
    formatted = json.dumps(result, indent=2) + '\n'
    if args.receipt:
        args.receipt.write_text(formatted)
    print(formatted, end='')
    if args.compile_run and result['native_harness'] != 'passed':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
