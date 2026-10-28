# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""A relocated capture keeps one receipt across two checkouts."""

import contextlib
import io
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
import venv

import coverage_io
import coverage_loop_proofs as loops
import test_coverage_loop_proofs as fixtures


def wheel(root):
    env = root / '.venv'
    binary = env / 'bin'
    # Exercise a real isolated environment, including Python's own configuration.
    # The test runner must use an upstream interpreter without distro import hooks.
    venv.EnvBuilder(with_pip=False, symlinks=True).create(env)
    python = binary / 'python'
    launcher = binary / 'mojo'
    launcher.write_text('#!' + str(python) + '\nfrom mojo._entrypoints import exec_mojo\nexec_mojo()\n')
    site = env / 'lib' / ('python' + str(sys.version_info.major) + '.' + str(sys.version_info.minor)) / 'site-packages'
    payload = {'mojo/_entrypoints.py': 'def exec_mojo(): pass\n',
               'modular/bin/mojo': 'compiler payload\n',
               'modular/bin/lld': 'linker payload\n',
               'modular/lib/mojo/std.mojoc': 'standard library payload\n'}
    for name, content in payload.items():
        path = site / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    for package in ('mojo_compiler', 'mojo_compiler_mojo_libs'):
        directory = site / (package + '-1.1.0.dist-info')
        directory.mkdir()
        (directory / 'METADATA').write_text('Name: ' + package.replace('_', '-') + '\nVersion: 1.1.0\n')
        (directory / 'RECORD').write_text(''.join(name + ',,\n' for name in payload))
    return launcher, site


class RelocatedCaptureTests(unittest.TestCase):
    def test_generation_capture_report_across_independent_roots(self):
        fixture = fixtures.ProofBindingTests('test_changed_source_invalidates_the_proof')
        fixture.setUp()
        try:
            (fixture.root / '.venv/bin/mojo').unlink()
            launcher, site = wheel(fixture.root)
            fixture.regenerate()
            envelope = loops.seal(fixture.root, fixture.build, 'Mojo fixture', '-Werror')
            capture, output = fixture.hits / 'test_fixture.txt.gz', fixture.hits / 'test_fixture.out'
            command = fixture.command(envelope)
            self.assertEqual(coverage_io.capture(command, output, capture, loop_proof=fixture.receipt,
                                                 source_root=fixture.root), 0)
            with tempfile.TemporaryDirectory() as tmp:
                other = Path(tmp) / 'different-checkout'
                shutil.copytree(fixture.root, other, symlinks=True)
                other_launcher = other / '.venv/bin/mojo'
                body = other_launcher.read_bytes().split(b'\n', 1)[1]
                other_launcher.write_bytes(b'#!' + os.fsencode(other / '.venv/bin/python') + b'\n' + body)
                build = other / 'build'
                loops.begin_generation(other, build, 'Mojo fixture', '-Werror', sources=['module.mojo'])
                fixtures.model_generation(other, build)
                new = loops.seal(other, build, 'Mojo fixture', '-Werror')
                self.assertEqual(envelope, new)
                loops.verify_captures([build / 'hits/test_fixture.txt.gz'], new)
                # Compiler-free report invocation tests wrapper identity flow;
                # it does not claim a native reporter or coverage gate result.
                report_command = [sys.executable, '-c', 'import sys; assert "R module 2 T" in open(sys.argv[1]).read()',
                                  str(build / 'manifest.txt')]
                with contextlib.redirect_stdout(io.StringIO()):
                    status = coverage_io.report_with_loop_proofs(report_command, [build / 'hits/test_fixture.txt.gz'],
                                root=other, build=build, compiler='Mojo fixture', flags='-Werror')
                self.assertEqual(status, 0)
                driver = other / site.relative_to(fixture.root) / 'modular/bin/mojo'
                old_driver = driver.read_bytes()
                driver.write_bytes(old_driver + b'changed payload\n')
                with self.assertRaisesRegex(ValueError, 'Stale|checkpoint'):
                    loops.verify(build / 'loop-proofs.json', other, build, 'Mojo fixture', '-Werror')
                driver.write_bytes(old_driver)
                (other / 'module.mojo').write_text('source mutation\n')
                with self.assertRaisesRegex(ValueError, 'Stale|Source'):
                    loops.verify(build / 'loop-proofs.json', other, build, 'Mojo fixture', '-Werror')
        finally:
            fixture.doCleanups()


if __name__ == '__main__':
    unittest.main()
