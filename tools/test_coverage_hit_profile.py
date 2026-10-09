# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Command and object-composition controls for optional compiled captures."""
import contextlib
import gzip
import io
import json
import os
from pathlib import Path
from types import SimpleNamespace
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import coverage_hit_aot as profile
import coverage_io
import native_test_support as native


class CompiledProfileCommands(unittest.TestCase):
    def setUp(self):
        self.root = Path('/tmp/coverage-profile-controls')
        self.suite = self.root / 'tests/test_carla_sum2_environment.mojo'
        self.command = ['mojo', 'run', '-I', str(self.root), '--Werror',
                        '--num-threads', '1', str(self.suite),
                        'argument with spaces', '--literal', str(self.suite)]

    def test_raw_profile_keeps_the_exact_command_and_environment(self):
        before = dict(os.environ)
        with patch.object(native, 'build_object') as build:
            command, name = profile.prepare_profile(
                self.root, self.suite, self.root/'cache', 'cc', self.command, 'raw')
        self.assertEqual(command, self.command)
        self.assertIsNot(command, self.command)
        self.assertIsNone(name)
        self.assertEqual(dict(os.environ), before)
        build.assert_not_called()

    def test_plain_compiled_profile_preserves_source_identity_and_program_args(self):
        command, name = profile.prepare_profile(
            self.root, self.suite, self.root/'cache', 'cc', self.command, 'aot')
        self.assertEqual(command, self.command)
        self.assertEqual(name, str(self.suite))
        with patch.object(native, 'dependency_inputs', return_value=[]):
            build, execute = native.prepare_run_commands(
                self.root, self.suite, self.root/'cache', 'cc', command,
                self.root/'temporary executable')
        self.assertEqual(build[:2], ['mojo', 'build'])
        self.assertEqual(build[2:-3], self.command[2:7])
        self.assertEqual(build[-1], str(self.suite))
        self.assertEqual(execute[1:], self.command[8:])

    def test_cache_and_fp_fixture_objects_are_both_linked_before_the_source(self):
        sink = SimpleNamespace(st_mode=stat.S_IFIFO, st_dev=17, st_ino=23)
        cache_object = self.root/'cache-helper.o'
        fp_object = self.root/'fp-fixture.o'
        with patch.dict(os.environ, {}, clear=True), \
             patch.object(profile.platform, 'system', return_value='Linux'), \
             patch.object(profile.os, 'fstat', return_value=sink), \
             patch.object(native, 'compiler_identity', return_value={'id': 'cc'}) as identity, \
             patch.object(native, 'build_object', side_effect=[cache_object, fp_object]) as objects, \
             patch.object(native, 'dependency_inputs', return_value=['tools/fixtures/carla_sum2_fp_state.c']):
            prepared, name = profile.prepare_profile(
                self.root, self.suite, self.root/'cache', 'cc', self.command, 'aot-hits')
            build, execute = native.prepare_run_commands(
                self.root, self.suite, self.root/'cache', 'cc', prepared, self.root/'binary')
            self.assertEqual(os.environ['THREEMOJO_COVERAGE_PIPE_DEVICE'], '17')
            self.assertEqual(os.environ['THREEMOJO_COVERAGE_PIPE_INODE'], '23')
        self.assertEqual(name, str(self.suite))
        self.assertEqual(build.count('-Xlinker'), 2)
        self.assertIn('-DTHREEMOJO_COVERAGE_HIT_CACHE', build)
        for obj in (cache_object, fp_object):
            index = build.index(str(obj))
            self.assertEqual(build[index-1], '-Xlinker')
            self.assertLess(index, build.index(str(self.suite)))
        self.assertEqual(execute[1:], self.command[8:])
        self.assertEqual(objects.call_count, 2)
        self.assertEqual(identity.call_args_list[0].args, ('cc -pthread',))
        self.assertEqual(identity.call_args_list[1].args, ('cc',))

    def test_private_profile_rejects_non_linux_before_building(self):
        with patch.object(profile.platform, 'system', return_value='Darwin'), \
             patch.object(native, 'build_object') as build:
            with self.assertRaisesRegex(ValueError, 'Linux'):
                profile.prepare_profile(self.root, self.suite, self.root/'cache',
                                        'cc', self.command, 'aot-hits')
        build.assert_not_called()

    def test_private_profile_rejects_a_regular_file_sink_before_building(self):
        with patch.object(profile.platform, 'system', return_value='Linux'), \
             patch.object(profile.os, 'fstat', return_value=SimpleNamespace(st_mode=stat.S_IFREG)), \
             patch.object(native, 'build_object') as build:
            with self.assertRaisesRegex(ValueError, 'capture pipe'):
                profile.prepare_profile(self.root, self.suite, self.root/'cache',
                                        'cc', self.command, 'aot-hits')
        build.assert_not_called()

    def test_missing_or_non_run_source_is_rejected(self):
        for command in (['mojo'], ['mojo', 'build', str(self.suite)],
                        ['mojo', 'run', '-I', str(self.root), '/tmp/other.mojo']):
            with self.assertRaises(ValueError):
                profile.source_index(command, self.suite)


    def profile_arguments(self, mode):
        return ['--profile', mode, '--root', str(self.root), '--suite',
                str(self.suite), '--cache', str(self.root/'cache'),
                '--', *self.command]

    def test_main_raw_nonfixture_executes_the_original_command(self):
        with patch.object(profile.sys, 'addaudithook') as hook, \
             patch.object(native, 'dependency_inputs', return_value=[]), \
             patch.object(profile.os, 'execvp', side_effect=SystemExit(0)) as execute, \
             patch.object(native, 'run_fixture') as translated:
            with self.assertRaises(SystemExit) as outcome:
                profile.main(self.profile_arguments('raw'))
        self.assertEqual(outcome.exception.code, 0)
        execute.assert_called_once_with(self.command[0], self.command)
        translated.assert_not_called()
        hook.assert_not_called()

    def test_main_raw_fixture_keeps_the_narrow_translation(self):
        with patch.object(native, 'dependency_inputs', return_value=['fp.c']), \
             patch.object(native, 'run_fixture', return_value=19) as translated, \
             patch.object(profile.os, 'execvp') as execute:
            self.assertEqual(profile.main(self.profile_arguments('raw')), 19)
        translated.assert_called_once_with(self.root, self.suite,
                                           self.root/'cache', 'cc', self.command)
        execute.assert_not_called()

    def test_main_compiled_profile_forwards_original_source_argv0(self):
        prepared = [*self.command[:7], '-Dtest', *self.command[7:]]
        with patch.object(profile, 'prepare_profile', return_value=(prepared, str(self.suite))), \
             patch.object(native, 'run_fixture', return_value=23) as translated:
            self.assertEqual(profile.main(self.profile_arguments('aot-hits')), 23)
        translated.assert_called_once_with(self.root, self.suite,
                                           self.root/'cache', 'cc', prepared,
                                           program_name=str(self.suite))

    def test_native_execution_substitutes_only_argv0_and_keeps_inherited_context(self):
        build = ['mojo', 'build', str(self.suite)]
        execute = ['/tmp/private executable', 'argument with spaces', '--literal']
        with patch.object(native, 'prepare_run_commands', return_value=(build, execute)), \
             patch.object(native.subprocess, 'run', side_effect=[
                 SimpleNamespace(returncode=0), SimpleNamespace(returncode=0)]) as run:
            self.assertEqual(native.run_fixture(self.root, self.suite,
                             self.root/'cache', 'cc', self.command,
                             program_name=str(self.suite)), 0)
        self.assertEqual(run.call_args_list[0].args, (build,))
        self.assertEqual(run.call_args_list[1].args,
                         ([str(self.suite), *execute[1:]],))
        self.assertEqual(run.call_args_list[1].kwargs,
                         {'executable': execute[0], 'check': False})
        for call in run.call_args_list:
            for inherited in ('cwd', 'env', 'stdin', 'stdout', 'stderr'):
                self.assertNotIn(inherited, call.kwargs)


FAKE_RUNTIME = """import os, sys
assert not any(key.startswith("THREEMOJO_COVERAGE_PHASES") for key in os.environ)
sys.stdout.buffer.write(b'PASS\\n')
sys.stderr.buffer.write(b'COVLINE:module:2:T\\nCOVBRANCH:module:3:T\\n')
raise SystemExit(int(os.environ.get('TEST_RUNTIME_STATUS', '0')))
"""


class PhaseObserverTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='coverage phases ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.suite = self.root/'tests/test_fixture.mojo'
        self.suite.parent.mkdir()
        self.suite.write_text('def main():\n    pass\n')
        self.compiler = self.root/'fake mojo'
        self.compiler.write_text('#!' + sys.executable + '\n' +
            'import os, pathlib, sys\n'
            'assert not any(key.startswith("THREEMOJO_COVERAGE_PHASES") for key in os.environ)\n'
            'assert sys.argv[1] == "build"\n'
            'status = int(os.environ.get("TEST_BUILD_STATUS", "0"))\n'
            'if status: raise SystemExit(status)\n'
            'output = pathlib.Path(sys.argv[sys.argv.index("-o") + 1])\n'
            'output.write_text(' + repr('#!' + sys.executable + '\n' + FAKE_RUNTIME) + ')\n'
            'output.chmod(0o700)\n')
        self.compiler.chmod(0o700)
        self.cc = self.root/'fake cc'
        self.cc.write_text('#!' + sys.executable + '\n' +
            'import pathlib, sys\n'
            'if "--version" in sys.argv: print("fake cc version")\n'
            'else: pathlib.Path(sys.argv[sys.argv.index("-o") + 1]).write_bytes(b"object")\n')
        self.cc.chmod(0o700)
        self.command = [str(self.compiler), 'run', '-I', str(self.root),
                        '-Dliteral=$value; spaced', str(self.suite)]
        self.output = self.root/'test_fixture.out'
        self.sidecar = self.root/'test_fixture.phases.jsonl'

    def arguments(self, mode='aot', trailing=()):
        import shlex
        return [sys.executable, str(Path(profile.__file__).resolve()),
                '--profile', mode, '--root', str(self.root), '--suite', str(self.suite),
                '--cache', str(self.root/'cache'), '--cc', shlex.quote(str(self.cc)),
                '--', *self.command, *trailing]

    def environment(self, command):
        environment = os.environ.copy()
        coverage_io._prepare_phases(command, self.output, None, environment)
        return environment

    def run_profile(self, *, mode='aot', build=0, runtime=0, trailing=()):
        command = self.arguments(mode, trailing)
        environment = self.environment(command)
        environment.update(TEST_BUILD_STATUS=str(build), TEST_RUNTIME_STATUS=str(runtime),
                           NEVER_LOG_THIS_SECRET='private environment value')
        result = subprocess.run(command, env=environment, capture_output=True, timeout=4)
        rows = [json.loads(line) for line in self.sidecar.read_text().splitlines()]
        return result, rows

    def test_actual_build_runtime_launch_requests_and_final_status(self):
        result, rows = self.run_profile(trailing=['argument with spaces', '--literal'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b'PASS\n')
        self.assertEqual(result.stderr, b'COVLINE:module:2:T\nCOVBRANCH:module:3:T\n')
        self.assertEqual([r['phase'] for r in rows], [
            'capture_header', 'mojo_build_launch_request',
            'native_runtime_launch_request', 'adapter_finish'])
        build, runtime, finish = rows[1:]
        self.assertEqual(build['executable'], str(self.compiler))
        self.assertEqual(build['argv'][:5], [str(self.compiler), 'build', '-I',
                                            str(self.root), '-Dliteral=$value; spaced'])
        self.assertEqual(build['argv'][-1], str(self.suite))
        self.assertEqual(runtime['argv'], [str(self.suite)])
        self.assertEqual(runtime['executable'], build['argv'][-2])
        self.assertEqual(runtime['omitted_program_arguments'], 2)
        self.assertEqual(finish['status'], 0)
        self.assertTrue(finish['diagnostics_complete'])
        self.assertEqual(len({r['adapter_pid'] for r in rows[1:]}), 1)
        self.assertEqual(sorted(r['monotonic'] for r in rows[1:]),
                         [r['monotonic'] for r in rows[1:]])
        text = self.sidecar.read_text()
        for private in ('NEVER_LOG_THIS_SECRET', 'private environment value',
                        'argument with spaces', '--literal'):
            self.assertNotIn(private, text)

    def test_build_failure_cannot_emit_runtime_launch_or_success(self):
        result, rows = self.run_profile(build=23)
        self.assertEqual(result.returncode, 23)
        self.assertEqual([r['phase'] for r in rows], [
            'capture_header', 'mojo_build_launch_request', 'adapter_finish'])
        self.assertEqual(rows[-1]['status'], 23)

    def test_runtime_failure_preserves_probes_and_failure(self):
        result, rows = self.run_profile(runtime=29)
        self.assertEqual(result.returncode, 29)
        self.assertIn(b'COVLINE:', result.stderr)
        self.assertEqual(rows[-1]['status'], 29)

    @unittest.skipUnless(sys.platform.startswith('linux'), 'Linux private hit helper')
    def test_helper_preparation_precedes_actual_build(self):
        result, rows = self.run_profile(mode='aot-hits')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([r['phase'] for r in rows], [
            'capture_header', 'native_helper_launch_request', 'native_helper_launch_request',
            'mojo_build_launch_request', 'native_runtime_launch_request', 'adapter_finish'])
        self.assertEqual(rows[1]['argv'], [str(self.cc), '-pthread', '--version'])
        self.assertIn('-c', rows[2]['argv'])
        self.assertIn('-DTHREEMOJO_COVERAGE_HIT_CACHE', rows[3]['argv'])

    def test_failed_os_launch_is_only_a_request_and_exception_is_preserved(self):
        self.compiler.unlink()
        result, rows = self.run_profile()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'FileNotFoundError', result.stderr)
        self.assertEqual(rows[1]['phase'], 'mojo_build_launch_request')
        self.assertEqual(rows[-1]['exception'], 'FileNotFoundError')
        self.assertNotIn('status', rows[-1])

    def test_capture_bytes_are_identical_with_and_without_diagnostics(self):
        command = self.arguments()
        snapshots = []
        for enabled in (True, False):
            with contextlib.ExitStack() as scope:
                scope.enter_context(contextlib.redirect_stdout(io.StringIO()))
                if not enabled:
                    scope.enter_context(patch.object(coverage_io, '_prepare_phases', return_value=None))
                errors = self.root/'test_fixture.txt.gz'
                status = coverage_io.capture(command, self.output, errors)
                snapshots.append((status, self.output.read_bytes(), gzip.decompress(errors.read_bytes())))
        self.assertEqual(snapshots[0], snapshots[1])
        self.assertEqual(snapshots[0], (0, b'PASS\n',
                                      b'COVLINE:module:2:T\nCOVLINE:module:3:T\nCOVBRANCH:module:3:T\n'))

    def test_adapter_write_fault_preserves_actual_build_failure(self):
        # Fault only the observer's low-level writes inside a fresh process.
        driver = self.root/'fault.py'
        driver.write_text('import pathlib, runpy, sys\nfrom unittest.mock import patch\n'
                          'sys.argv = sys.argv[1:]\n'
                          'sys.path.insert(0, str(pathlib.Path(sys.argv[0]).parent))\n'
                          'with patch("os.write", side_effect=OSError("full")):\n'
                          '    runpy.run_path(sys.argv[0], run_name="__main__")\n')
        command = self.arguments()
        environment = self.environment(command)
        environment['TEST_BUILD_STATUS'] = '41'
        result = subprocess.run([sys.executable, str(driver), *command[1:]],
                                env=environment, capture_output=True, timeout=4)
        self.assertEqual(result.returncode, 41, result.stderr)
        self.assertEqual(len(self.sidecar.read_text().splitlines()), 1)

    def test_silently_refused_hook_cannot_claim_complete_diagnostics(self):
        driver = self.root/'refuse.py'
        driver.write_text('import pathlib, runpy, sys\n'
                          'def refuse(event, args):\n'
                          '    if event == "sys.addaudithook": raise RuntimeError("refused")\n'
                          'sys.addaudithook(refuse)\n'
                          'sys.argv = sys.argv[1:]\n'
                          'sys.path.insert(0, str(pathlib.Path(sys.argv[0]).parent))\n'
                          'runpy.run_path(sys.argv[0], run_name="__main__")\n')
        command = self.arguments()
        result = subprocess.run([sys.executable, str(driver), *command[1:]],
                                env=self.environment(command), capture_output=True, timeout=4)
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = [json.loads(line) for line in self.sidecar.read_text().splitlines()]
        self.assertEqual(rows[-2]['phase'], 'diagnostics_incomplete')
        self.assertFalse(rows[-1]['diagnostics_complete'])

    @unittest.skipUnless(os.name == 'posix', 'POSIX coverage cancellation')
    def test_sleeping_build_and_preprobe_runtime_keep_distinct_last_requests(self):
        original_compiler = self.compiler.read_text()
        for stage, cancel in (('build', False), ('runtime', False), ('runtime', True)):
            with self.subTest(stage=stage, signal=cancel):
                # Start the unchanged absolute deadline only when the fake
                # process confirms startup. No assumption about machine speed.
                ready = self.root/'ready'
                ready.unlink(missing_ok=True)
                marker = ('import pathlib, time, os\n'
                          'pathlib.Path(' + repr(str(ready)) + ').write_text(str(os.getpid()))\n'
                          'while True: time.sleep(0.02)\n')
                if stage == 'build':
                    self.compiler.write_text('#!' + sys.executable + '\n' + marker)
                else:
                    self.compiler.write_text(original_compiler.replace(repr('#!' + sys.executable + '\n' + FAKE_RUNTIME),
                                                                       repr('#!' + sys.executable + '\n' + marker)))
                command = self.arguments()
                driver = '''import pathlib, sys, time
from unittest.mock import patch
import coverage_io
root = pathlib.Path(sys.argv[1])
original = coverage_io._CaptureProcess.__enter__
def enter(self):
    result = original(self)
    try:
        deadline = time.monotonic() + 4
        while not (root / 'ready').exists():
            if time.monotonic() >= deadline:
                raise RuntimeError('fake process did not start')
            time.sleep(0.01)
        if sys.argv[2] == 'deadline':
            self.deadline = time.monotonic() + 0.15
            self.watchdog = coverage_io.threading.Thread(target=self._deadline, daemon=True)
            self.watchdog.start()
        (root / 'supervised').touch()
        return result
    except BaseException:
        self.__exit__(*sys.exc_info())
        raise
with patch.object(coverage_io._CaptureProcess, '__enter__', enter):
    raise SystemExit(coverage_io.capture(sys.argv[3:], root/'test_fixture.out', root/'test_fixture.txt.gz'))
'''
                supervised = self.root/'supervised'
                supervised.unlink(missing_ok=True)
                environment = os.environ.copy()
                environment.pop(coverage_io.DEADLINE_ENV, None)
                environment['PYTHONPATH'] = str(Path(profile.__file__).parent)
                child = subprocess.Popen([sys.executable, '-c', driver, str(self.root),
                                          'signal' if cancel else 'deadline', *command],
                                         env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                try:
                    limit = time.monotonic() + 4
                    while not supervised.exists():
                        if child.poll() is not None or time.monotonic() >= limit:
                            self.fail('capture did not supervise the sleeping fake process')
                        time.sleep(0.01)
                    if cancel:
                        child.send_signal(signal.SIGTERM)
                    stdout, stderr = child.communicate(timeout=4)
                    self.assertEqual(child.returncode, 143 if cancel else 124, stdout + stderr)
                    rows = [json.loads(line) for line in self.sidecar.read_text().splitlines()]
                    self.assertEqual(rows[-1]['phase'], 'mojo_build_launch_request' if stage == 'build'
                                     else 'native_runtime_launch_request')
                    self.assertIn(b'phase diagnostics incomplete', stdout)
                    self.assertEqual(gzip.decompress((self.root/'test_fixture.txt.gz').read_bytes()), b'')
                    pid = int(ready.read_text())
                    limit = time.monotonic() + 3
                    while True:
                        try:
                            os.kill(pid, 0)
                            # Linux can briefly retain a killed orphan as zombie.
                            process_stat = Path('/proc')/str(pid)/'stat'
                            if process_stat.exists() and process_stat.read_text().rpartition(') ')[2].startswith('Z '):
                                break
                        except (FileNotFoundError, ProcessLookupError):
                            break
                        if time.monotonic() >= limit:
                            self.fail('capture left a live fake process')
                        time.sleep(0.01)
                finally:
                    if child.poll() is None:
                        child.terminate()
                        child.communicate(timeout=4)

    def observer(self):
        environment = self.environment(self.arguments())
        with patch.dict(os.environ, environment, clear=True):
            observer = profile._PhaseObserver(self.suite, self.command)
        self.addCleanup(observer.close)
        return observer

    def test_observer_descriptor_is_private_and_other_events_are_ignored(self):
        observer = self.observer()
        self.assertFalse(os.get_inheritable(observer.descriptor))
        before = self.sidecar.read_bytes()
        observer.audit('os.exec', ('ignored',))
        self.assertEqual(self.sidecar.read_bytes(), before)
        observer.close()
        observer.audit('subprocess.Popen', ('ignored',))
        self.assertEqual(self.sidecar.read_bytes(), before)

    def test_oversized_argv_and_event_limit_are_explicit_not_truncated(self):
        for oversized in (True, False):
            with self.subTest(oversized=oversized):
                observer = self.observer()
                if not oversized:
                    observer.events = profile.PHASE_MAX_EVENTS
                argv = [str(self.compiler), 'build', 'x' * profile.PHASE_MAX_RECORD, str(self.suite)] if oversized else ['cc']
                observer.audit('subprocess.Popen', (argv[0], argv, None, {}))
                observer.finish(status=0)
                rows = [json.loads(line) for line in self.sidecar.read_text().splitlines()]
                self.assertEqual([r['phase'] for r in rows], [
                    'capture_header', 'diagnostics_incomplete', 'adapter_finish'])
                self.assertFalse(rows[-1]['diagnostics_complete'])
                self.assertNotIn('argv', rows[1])

    def test_write_failure_cannot_mask_native_failure(self):
        observer = self.observer()
        with patch.object(profile.os, 'write', side_effect=OSError('full')):
            observer.audit('subprocess.Popen', ('cc', ['cc', '--version'], None, {}))
            observer.finish(status=37)
        self.assertIsNone(observer.descriptor)
        self.assertEqual(len(self.sidecar.read_text().splitlines()), 1)

    def test_library_and_no_sidecar_invocations_never_install_hooks(self):
        for observe, supplied in ((False, True), (True, False)):
            with self.subTest(observe=observe, supplied=supplied):
                environment = self.environment(self.arguments()) if supplied else {}
                with patch.dict(os.environ, environment, clear=True), \
                        patch.object(profile.sys, 'addaudithook') as hook, \
                        patch.object(native, 'run_fixture', return_value=31):
                    self.assertEqual(profile.main(self.arguments()[2:], _observe=observe), 31)
                hook.assert_not_called()

    def test_unknown_subprocess_is_incomplete_without_private_arguments(self):
        observer = self.observer()
        observer.audit('subprocess.Popen', ('other', ['other', 'private-token'], None, {}))
        observer.finish(status=0)
        rows = [json.loads(line) for line in self.sidecar.read_text().splitlines()]
        self.assertEqual(rows[1]['phase'], 'diagnostics_incomplete')
        self.assertFalse(rows[-1]['diagnostics_complete'])
        self.assertNotIn('private-token', self.sidecar.read_text())
        self.assertNotIn('argv', rows[1])

    def test_raw_cli_does_not_install_an_observer_even_with_a_sidecar(self):
        environment = self.environment(self.arguments())
        with patch.dict(os.environ, environment, clear=True), \
                patch.object(profile.sys, 'addaudithook') as hook, \
                patch.object(native, 'dependency_inputs', return_value=[]), \
                patch.object(profile.os, 'execvp', side_effect=SystemExit(0)), \
                self.assertRaises(SystemExit):
            profile.main(self.arguments('raw')[2:], _observe=True)
        hook.assert_not_called()

    def test_file_size_limit_and_short_writes_leave_incomplete_diagnostics(self):
        for short_write in (False, True):
            with self.subTest(short_write=short_write):
                observer = self.observer()
                original_write = os.write
                with contextlib.ExitStack() as scope:
                    if short_write:
                        scope.enter_context(patch.object(profile.os, 'write',
                            side_effect=lambda fd, data: original_write(fd, data[:5])))
                    else:
                        observer.size = profile.PHASE_MAX_BYTES - 1
                    observer.audit('subprocess.Popen', ('cc', ['cc', '--version'], None, {}))
                    observer.finish(status=0)
                self.assertIsNone(observer.descriptor)
                self.assertFalse(observer.complete)
                self.assertNotIn('adapter_finish', self.sidecar.read_text())

    def test_control_flow_exceptions_are_not_swallowed(self):
        observer = self.observer()
        with patch.object(profile.os, 'write', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                observer.audit('subprocess.Popen', ('cc', ['cc', '--version'], None, {}))


if __name__ == '__main__':
    unittest.main()
