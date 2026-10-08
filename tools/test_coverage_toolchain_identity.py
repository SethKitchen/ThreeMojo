# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compiler-free relocation and actual-byte mutation controls."""

import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
import venv
from unittest.mock import patch

import coverage_io
import coverage_loop_proofs as loops
import coverage_toolchain_identity as identity
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


class ToolchainIdentityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.a = self.base / 'runner-a'
        self.b = self.base / 'unrelated-root' / 'runner-b'
        self.launcher_a, self.site_a = wheel(self.a)
        self.launcher_b, self.site_b = wheel(self.b)

    def test_relocated_install_has_same_semantic_identity(self):
        self.assertNotEqual(self.launcher_a.read_bytes(), self.launcher_b.read_bytes())
        self.assertEqual(identity.executable_identity(self.launcher_a), identity.executable_identity(self.launcher_b))
        self.assertEqual(loops._command_identity(str(self.launcher_a), self.a, self.a / 'stage'),
                         loops._command_identity(str(self.launcher_b), self.b, self.b / 'stage'))

    def test_wrong_venv_shebang_and_import_hooks_fail_closed(self):
        body = self.launcher_a.read_bytes().split(b'\n', 1)[1]
        self.launcher_a.write_bytes(b'#!' + os.fsencode(self.b / '.venv/bin/python') + b'\n' + body)
        with self.assertRaisesRegex(ValueError, 'different environment'):
            identity.executable_identity(self.launcher_a)
        for name in ('redirect.pth', 'sitecustomize.py', 'usercustomize.py'):
            hook = self.site_b / name
            hook.write_text('raise RuntimeError("hook must not execute")\n')
            try:
                with self.assertRaisesRegex(ValueError, 'import redirection'):
                    identity.executable_identity(self.launcher_b)
            finally:
                hook.unlink()
        shadow = self.b / '.venv/bin/re'
        shadow.mkdir()
        with self.assertRaisesRegex(ValueError, 'import shadow'):
            identity.executable_identity(self.launcher_b)
        shadow.rmdir()
        init = self.site_b / 'mojo/__init__.py'
        init.write_text('__path__ = ["/unbound"]\n')
        with self.assertRaisesRegex(ValueError, 'package initialization'):
            identity.executable_identity(self.launcher_b)
        init.unlink()
        config = self.b / '.venv/pyvenv.cfg'
        config.write_text(config.read_text().replace('false', 'true'))
        with self.assertRaisesRegex(ValueError, 'exclude system'):
            identity.executable_identity(self.launcher_b)

    def test_body_driver_linker_stdlib_and_package_code_changes_are_not_equivalent(self):
        before = identity.executable_identity(self.launcher_a)
        for file in (self.launcher_b, self.site_b / 'modular/bin/mojo',
                     self.site_b / 'modular/bin/lld', self.site_b / 'modular/lib/mojo/std.mojoc',
                     self.site_b / 'mojo/_entrypoints.py'):
            raw = file.read_bytes()
            try:
                file.write_bytes(raw + b'changed\n')
                self.assertNotEqual(before, identity.executable_identity(self.launcher_b))
            finally:
                file.write_bytes(raw)

    def test_interpreter_bytes_and_capabilities_stay_bound(self):
        before = identity.executable_identity(self.launcher_a)
        actual = identity.digest
        interpreter = (self.a / '.venv/bin/python').resolve()
        with patch.object(identity, 'digest', side_effect=lambda p: '0' * 64 if Path(p) == interpreter else actual(p)):
            self.assertNotEqual(before, identity.executable_identity(self.launcher_a))
        actual_run = identity.subprocess.run
        def changed(*args, **kwargs):
            result = actual_run(*args, **kwargs)
            fields = json.loads(result.stdout)
            fields['version'] += 'changed'
            result.stdout = json.dumps(fields)
            return result
        with patch.object(identity.subprocess, 'run', side_effect=changed):
            self.assertNotEqual(before, identity.executable_identity(self.launcher_a))

    def test_interpreter_environment_and_loaded_customizers_fail_closed(self):
        actual_run = identity.subprocess.run
        for changed_field, changed_value in (
                ('implementation', 'other-python'),
                ('prefix', str(self.b / '.venv')),
                ('user_site', True),
                ('user_site', None),
                ('customizers', ['sitecustomize']),
                ('customizers', ['usercustomize'])):
            with self.subTest(field=changed_field, value=changed_value):
                def changed(*args, **kwargs):
                    result = actual_run(*args, **kwargs)
                    fields = json.loads(result.stdout)
                    fields[changed_field] = changed_value
                    result.stdout = json.dumps(fields)
                    return result
                with patch.object(identity.subprocess, 'run', side_effect=changed):
                    with self.assertRaisesRegex(ValueError, 'environment or import customization'):
                        identity.executable_identity(self.launcher_a)

        def extra_site(*args, **kwargs):
            result = actual_run(*args, **kwargs)
            fields = json.loads(result.stdout)
            fields['sites'].append(str(self.b / 'unbound-site-packages'))
            result.stdout = json.dumps(fields)
            return result
        with patch.object(identity.subprocess, 'run', side_effect=extra_site):
            with self.assertRaisesRegex(ValueError, 'site-packages does not match'):
                identity.executable_identity(self.launcher_a)

    def test_overrides_missing_payload_and_unvalidated_shebang_fail_closed(self):
        with patch.dict(os.environ, {'MODULAR_MOJO_MAX_DRIVER_PATH': '/other/compiler'}):
            with self.assertRaisesRegex(ValueError, 'override'):
                identity.executable_identity(self.launcher_a)
        (self.site_a / 'modular/bin/mojo').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing'):
            identity.executable_identity(self.launcher_a)
        self.launcher_b.write_text('#!/usr/bin/env python3\nfrom mojo._entrypoints import exec_mojo\n')
        with self.assertRaisesRegex(ValueError, 'interpreter'):
            identity.executable_identity(self.launcher_b)


class HostedIdentitySetupTests(unittest.TestCase):
    def test_hosted_tooling_uses_an_upstream_test_interpreter(self):
        root = Path(__file__).resolve().parent.parent
        workflow = (root / '.github/workflows/ci.yml').read_text()
        for start, end in (('  lint:', '  cpu:'),
                           ('  cpu-macos:', '  # Coverage runs beside')):
            with self.subTest(job=start.strip()):
                job = workflow.split(start, 1)[1].split(end, 1)[0]
                self.assertIn('uv python install --no-bin 3.12.14', job)
                self.assertIn('uv python find --managed-python --no-project 3.12.14', job)
                self.assertIn('echo "$(dirname "$PYTHON")" >> "$GITHUB_PATH"', job)
                self.assertIn('"$PYTHON" -m venv --without-pip --prompt ThreeMojo .venv', job)
                self.assertIn('uv pip install --python .venv/bin/python "mojo==1.1.0"', job)
                self.assertNotIn('uses: actions/setup-python', job)
                self.assertNotIn('uv venv --prompt ThreeMojo', job)
                self.assertNotIn('LD_LIBRARY_PATH', job)

    def test_capture_and_report_pin_the_same_immutable_toolchain_image(self):
        root = Path(__file__).resolve().parent.parent
        workflow = (root / '.github/workflows/ci.yml').read_text()
        capture = workflow.split('  coverage-capture:', 1)[1].split('  coverage:', 1)[0]
        report = workflow.split('  coverage:', 1)[1].split('  # Compile the GPU', 1)[0]
        image = 'python:3.12.14-bookworm@sha256:dbbe4ceb97851e2e5fa83798b239811f871cb743b259ba3563737349f6bcfaa0'
        self.assertIn('    container: ' + image, capture)
        self.assertIn('    container: ' + image, report)
        self.assertIn('COV_BUDGET=9000', capture)
        self.assertIn('SHARD=${{ matrix.shard }}/8', capture)
        self.assertIn('timeout-minutes: 170', capture)
        self.assertIn('timeout-minutes: 60', report)
        self.assertNotIn('sudo', capture)
        self.assertIn('path: coverage/build/hits/', capture)
        self.assertIn('path: coverage/build/hits/', report)


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
