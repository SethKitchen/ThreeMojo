# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check native asset lookup and temporary-root ownership across processes.

Compilation is separate from each unchanged five-second execution limit.
The check never changes the assets and needs no GPU or Python bridge in Mojo.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

from run_suite import result_errors, slow_tests

ROOT = Path(__file__).resolve().parent.parent
SECONDS = 5


def run(command, environment, cwd, *, error=None, suite=False):
    """Require a bounded successful child or a specific controlled failure."""
    result = subprocess.run(command, cwd=cwd, env=environment, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=SECONDS)
    if error is not None:
        if result.returncode <= 0 or error not in result.stdout:
            raise AssertionError(f'Expected controlled error {error!r}: {result}')
    else:
        if result.returncode or (not suite and 'PORTABILITY PASS' not in result.stdout):
            raise AssertionError(f'Child failed: {result}')
        if suite and (result_errors(result.stdout) or slow_tests(result.stdout, SECONDS)):
            raise AssertionError(f'Invalid or slow suite: {result.stdout}')
    return result


def environment(**values):
    """Remove inherited roots before adding this subprocess's explicit inputs."""
    result = os.environ.copy()
    for key in tuple(result):
        if key in ('THREEMOJO_ASSET_ROOT', 'THREEMOJO_TEST_TMPDIR') or key.startswith('THREEMOJO_PORTABILITY_'):
            result.pop(key)
    result.update(values)
    return result


def check_assets(binary, folder, assets):
    unrelated = folder / 'unrelated working directory'
    unrelated.mkdir()
    missing = folder / 'nonexistent asset root'
    # Both high-level loaders work outside the repository with an absolute root.
    for action, suffix in (('face', 'face/ict_face.bin'), ('hair', 'hair/layered.bin')):
        run([str(binary)], environment(THREEMOJO_ASSET_ROOT=str(assets),
            THREEMOJO_PORTABILITY_ACTION=action), unrelated)
        # A relative root keeps its original call-time working-directory meaning.
        relative = os.path.relpath(assets, unrelated)
        run([str(binary)], environment(THREEMOJO_ASSET_ROOT=relative,
            THREEMOJO_PORTABILITY_ACTION=action), unrelated)
        # Check unset and empty repository-root defaults without changing fixtures.
        for setting in ({}, {'THREEMOJO_ASSET_ROOT': ''}):
            run([str(binary)], environment(THREEMOJO_PORTABILITY_ACTION=action,
                **setting), ROOT)
        # No silent fallback, even when the working directory has valid defaults.
        for cwd in (ROOT, unrelated):
            run([str(binary)], environment(THREEMOJO_ASSET_ROOT=str(missing),
                THREEMOJO_PORTABILITY_ACTION=action), cwd,
                error=str(missing / suffix))
    # Explicit file callers are independent of the high-level root setting.
    run([str(binary)], environment(THREEMOJO_ASSET_ROOT=str(missing),
        THREEMOJO_PORTABILITY_ACTION='explicit',
        THREEMOJO_PORTABILITY_MODEL=str(assets / 'face/ict_face.bin')), unrelated)
    print('PASS asset roots: absolute, relative, unset, empty, missing, explicit file')


def check_scratch(binary, suite, mojo, folder):
    parent = folder / "TMPDIR with spaces and an apostrophe's"
    parent.mkdir()
    marker = folder / 'scratch-root.txt'
    env = environment(TMPDIR=str(parent), THREEMOJO_PORTABILITY_ACTION='scratch',
                      THREEMOJO_PORTABILITY_MARKER=str(marker))
    for fail in ('', 'yes'):
        child = dict(env, THREEMOJO_PORTABILITY_FAIL=fail)
        run([str(binary)], child, folder,
            error='expected direct-process failure' if fail else None)
        root = Path(marker.read_text())
        assert root.parent == parent and root.is_absolute(), root
        assert not root.exists(), root
        assert not list(parent.iterdir()), list(parent.iterdir())
    # A relative TMPDIR becomes an absolute, process-owned root.
    relative = dict(env, TMPDIR=parent.name)
    run([str(binary)], relative, folder)
    root = Path(marker.read_text())
    assert root.parent == parent and not root.exists(), root
    # The stdlib can select relative TMP/TEMP when TMPDIR is empty. Cleanup
    # must retain the created absolute path even if the child changes cwd.
    elsewhere = folder / 'different cleanup cwd'
    elsewhere.mkdir()
    fallback = dict(env, TMPDIR='', TMP=parent.name, TEMP=parent.name,
                    THREEMOJO_PORTABILITY_CHDIR=str(elsewhere))
    run([str(binary)], fallback, folder)
    root = Path(marker.read_text())
    assert root.parent == parent and not root.exists(), root
    assert not list(elsewhere.iterdir()) and not list(parent.iterdir())
    # Supplied roots remain caller-owned on both normal and exceptional exit.
    borrowed = folder / 'runner-owned'
    borrowed.mkdir()
    sentinel = borrowed / 'sentinel'
    sentinel.write_text('keep')
    for fail in ('', 'yes'):
        child = dict(env, THREEMOJO_TEST_TMPDIR=str(borrowed),
                     THREEMOJO_PORTABILITY_FAIL=fail)
        run([str(binary)], child, folder,
            error='expected direct-process failure' if fail else None)
        assert Path(marker.read_text()) == borrowed
        assert sentinel.read_text() == 'keep'
        assert (borrowed / 'same.bin').read_text() == 'fixture'
        assert not list(parent.iterdir()), list(parent.iterdir())
    # Two simultaneous direct processes write the same name under distinct roots.
    release = folder / 'release'
    processes = []
    deadline = time.monotonic() + SECONDS
    try:
        markers = [folder / f'concurrent-{index}.txt' for index in range(2)]
        for index, ready in enumerate(markers):
            child = dict(env, THREEMOJO_PORTABILITY_MARKER=str(ready),
                         THREEMOJO_PORTABILITY_CONTENTS=str(index),
                         THREEMOJO_PORTABILITY_RELEASE=str(release))
            processes.append(subprocess.Popen([str(binary)], cwd=folder, env=child,
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT))
        while not all(path.exists() and path.stat().st_size for path in markers):
            if time.monotonic() >= deadline or any(p.poll() is not None for p in processes):
                raise AssertionError('Concurrent processes did not become ready')
            time.sleep(0.005)
        roots = [Path(path.read_text()) for path in markers]
        assert roots[0] != roots[1], roots
        for index, root in enumerate(roots):
            assert root.parent == parent and (root / 'same.bin').read_text() == str(index)
        release.touch()
        for process in processes:
            output, _ = process.communicate(timeout=max(0.001, deadline - time.monotonic()))
            assert process.returncode == 0 and 'PORTABILITY PASS' in output, output
        assert all(not root.exists() for root in roots), roots
        assert not list(parent.iterdir()), list(parent.iterdir())
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
            process.communicate()
    # The pinned stdlib refuses symlinks during cleanup. That error must not
    # bypass environment restoration or touch the target. The outer Python
    # owner safely removes the deliberately retained test fixture afterward.
    external = folder / 'symlink-target'
    external.mkdir()
    (external / 'sentinel').write_text('keep')
    bad_marker = folder / 'cleanup-root.txt'
    bad_release = folder / 'cleanup-release'
    child = dict(env, THREEMOJO_PORTABILITY_MARKER=str(bad_marker),
                 THREEMOJO_PORTABILITY_RELEASE=str(bad_release))
    process = subprocess.Popen([str(binary)], cwd=folder, env=child, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + SECONDS
    try:
        while not (bad_marker.exists() and bad_marker.stat().st_size):
            if time.monotonic() >= deadline or process.poll() is not None:
                raise AssertionError('Cleanup-error process did not become ready')
            time.sleep(0.005)
        root = Path(bad_marker.read_text())
        assert root.parent == parent and root.name.startswith('threemojo-test-'), root
        (root / 'external-link').symlink_to(external, target_is_directory=True)
        bad_release.touch()
        output, _ = process.communicate(timeout=max(0.001, deadline - time.monotonic()))
        assert process.returncode > 0 and 'can not be a symbolic link' in output, output
        assert (external / 'sentinel').read_text() == 'keep'
        shutil.rmtree(root)
        assert not list(parent.iterdir()), list(parent.iterdir())
    finally:
        if process.poll() is None:
            process.kill()
        process.communicate()
    # Built direct execution and literal mojo run need no wrapper or root variable.
    direct = environment(TMPDIR=str(parent))
    run([str(suite)], direct, folder, suite=True)
    # mojo run includes compilation; TestSuite's own unchanged per-test timings
    # are checked below, while the compiler has a separate bounded build budget.
    command = [mojo, 'run', '--Werror', '-I', str(ROOT),
               str(ROOT / 'tests/test_scratch.mojo')]
    result = subprocess.run(command, cwd=folder, env=direct, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=300)
    assert result.returncode == 0, result.stdout
    assert not result_errors(result.stdout), result.stdout
    assert not slow_tests(result.stdout, SECONDS), result.stdout
    assert not list(parent.iterdir()), list(parent.iterdir())
    print('PASS temporary roots: direct run, errors, nested, borrowed, TMPDIR, concurrent')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--mojo', default=str(ROOT / '.venv/bin/mojo'))
    args = parser.parse_args(argv)
    mojo = shutil.which(args.mojo) or str(Path(args.mojo).resolve())
    assets = (ROOT / 'assets').resolve()
    with tempfile.TemporaryDirectory(prefix='threemojo-portability-') as temporary:
        folder = Path(temporary).resolve()
        binary = folder / 'probe'
        suite = folder / 'scratch'
        for source, output in ((ROOT / 'tests/portability_probe.mojo', binary),
                               (ROOT / 'tests/test_scratch.mojo', suite)):
            subprocess.run([mojo, 'build', '--Werror', '-I', str(ROOT),
                str(source), '-o', str(output)],
                cwd=ROOT, check=True, timeout=300)
        check_assets(binary, folder, assets)
        check_scratch(binary, suite, mojo, folder)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
