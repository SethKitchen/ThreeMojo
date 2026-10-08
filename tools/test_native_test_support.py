# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compiler-free native-fixture selection, cache and instrumented-root tests."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import affected
import cache_key
import native_test_support as native
import suite_key

SUITE = 'tests/test_carla_sum2_environment.mojo'
FIXTURE = 'tools/fixtures/carla_sum2_fp_state.c'
IDENTITY = {'command': ['fake-cc'], 'version': 'fixture compiler 1',
            'flags': list(native.C_FLAGS), 'system': 'fixture-os', 'machine': 'fixture-cpu'}


class NativeTestSupportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='native tests ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.write(SUITE, 'def test_modes():\n    pass\n')
        self.write('tests/test_plain.mojo', 'def test_plain():\n    pass\n')
        self.write('tests/aggregate.mojo',
                   'from tests.test_carla_sum2_environment import test_modes\n')
        self.write(FIXTURE, 'int fixture(void) { return 1; }\n')
        for name in suite_key.TOOLING:
            self.write(name, '# fixture tooling\n')

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_one_inventory_selects_direct_and_transitive_dependencies(self):
        self.assertEqual(native.fixture_inputs([SUITE]), [FIXTURE])
        self.assertEqual(native.dependency_inputs(self.root, self.root / SUITE), [FIXTURE])
        self.assertEqual(native.dependency_inputs(self.root, self.root / 'tests/aggregate.mojo'), [FIXTURE])
        self.assertEqual(native.dependency_inputs(self.root, self.root / 'tests/test_plain.mojo'), [])

    def test_dependency_lookup_restores_original_root(self):
        old = affected.ROOT
        native.dependency_inputs(self.root, self.root / SUITE)
        self.assertEqual(affected.ROOT, old)
        with self.assertRaises(ValueError):
            native.dependency_inputs(self.root, self.root.parent / 'outside.mojo')
        self.assertEqual(affected.ROOT, old)

    def test_plain_command_is_unchanged_without_a_c_compiler(self):
        suite = self.root / 'tests/test_plain.mojo'
        for mode in ('build', 'run'):
            command = ['mojo', mode, '--Werror', str(suite)]
            with self.subTest(mode=mode), patch.object(
                    native, 'compiler_identity', side_effect=AssertionError('not needed')):
                self.assertEqual(native.prepare_command(
                    self.root, suite, self.root/'cache', '', command), command)

    def test_native_identity_binds_compiler_bytes_even_with_same_version(self):
        compiler = self.write('compiler', 'compiler before\n')
        version = subprocess.CompletedProcess([], 0, stdout='unchanged version\n')
        with patch.object(native.subprocess, 'run', return_value=version):
            before = native.compiler_identity(shlex.quote(str(compiler)))
            compiler.write_text('compiler after\n')
            after = native.compiler_identity(shlex.quote(str(compiler)))
        self.assertEqual(before['version'], after['version'])
        self.assertEqual(before['command'], after['command'])
        self.assertNotEqual(before['files'], after['files'])

    def test_native_identity_binds_resolved_compiler_behind_a_wrapper(self):
        wrapper = self.write('wrapper', 'wrapper bytes\n')
        compiler = self.write('compiler', 'compiler bytes\n')
        version = subprocess.CompletedProcess([], 0, stdout='same version\n')
        with patch.object(native.subprocess, 'run', return_value=version), \
                patch.object(native.shutil, 'which', return_value=str(compiler)):
            identity = native.compiler_identity(shlex.quote(str(wrapper)) + ' cc')
        self.assertEqual(set(identity['files']), {str(wrapper), str(compiler)})

    def test_build_link_argument_precedes_source_and_preserves_flags(self):
        suite = self.root / SUITE
        command = ['mojo', 'build', '--num-threads', '1', '--Werror', '-o', 'some binary', str(suite)]
        object_path = self.root / 'native cache' / 'fixture.o'
        with patch.object(native, 'compiler_identity', return_value=IDENTITY), \
                patch.object(native, 'build_object', return_value=object_path) as build:
            actual = native.prepare_command(self.root, suite, self.root/'cache', 'fake-cc', command)
        self.assertEqual(actual, command[:-1] + ['-Xlinker', str(object_path), command[-1]])
        self.assertEqual(build.call_args.args[:2], (self.root, FIXTURE))

    def test_instrumented_run_uses_copied_fixture_and_stays_in_tree(self):
        destination = self.root / 'coverage/build'
        (destination/'tests').mkdir(parents=True)
        (destination/SUITE).write_text((self.root/SUITE).read_text())
        native.copy_fixtures(self.root, destination)
        self.assertEqual((destination/FIXTURE).read_bytes(), (self.root/FIXTURE).read_bytes())
        suite = destination / SUITE
        command = ['mojo', 'run', '-I', str(destination), str(suite)]
        executable = self.root/'run directory'/'suite'
        with patch.object(native, 'compiler_identity', return_value=IDENTITY), \
                patch.object(native, 'build_object', return_value=destination/'fixture.o') as build:
            actual, execute = native.prepare_run_commands(
                destination, suite, self.root/'cache', 'fake-cc', command, executable)
        self.assertEqual(build.call_args.args[0], destination)
        self.assertEqual(actual, ['mojo', 'build', '-I', str(destination),
                                 '-o', str(executable), '-Xlinker',
                                 str(destination/'fixture.o'), str(suite)])
        self.assertEqual(execute, [str(executable)])
        self.assertNotIn(str(self.root/SUITE), actual)

    def test_run_translation_preserves_options_and_program_arguments(self):
        suite = self.root/SUITE
        executable = self.root/'temporary output'/'suite'
        options = ['-I', 'include with spaces', '-O', '0', '--num-threads', '1',
                   '--fp-mode=contract=off', '--target-cpu=x86-64-v3', '--Werror']
        arguments = ['two words', '--Wno-error', str(suite), '-o', 'program output']
        command = ['mojo', 'run', *options, str(suite), *arguments]
        obj = self.root/'fixture.o'
        with patch.object(native, 'compiler_identity', return_value=IDENTITY), \
                patch.object(native, 'build_object', return_value=obj):
            build, execute = native.prepare_run_commands(
                self.root, suite, self.root/'cache', 'fake-cc', command, executable)
        self.assertEqual(build, ['mojo', 'build', *options, '-o', str(executable),
                                 '-Xlinker', str(obj), str(suite)])
        self.assertEqual(execute, [str(executable), *arguments])
        self.assertNotIn('run', build)

    def test_fixture_run_cannot_accidentally_use_object_linker_in_jit(self):
        with self.assertRaisesRegex(ValueError, 'build command'):
            native.prepare_command(self.root, self.root/SUITE, self.root/'cache',
                                   'unused', ['mojo', 'run', str(self.root/SUITE)])

    def test_run_translation_requires_run_mode_and_source(self):
        for command in ([], ['mojo', 'build', str(self.root/SUITE)],
                        ['mojo', 'run', 'other.mojo']):
            with self.subTest(command=command), self.assertRaises(ValueError):
                native.prepare_run_commands(self.root, self.root/SUITE,
                                            self.root/'cache', 'unused', command,
                                            self.root/'binary')

    def fixture_run(self, build_status=0, run_status=0, cancel=False):
        calls = []
        temporary_root = self.root/'private temp'
        temporary_root.mkdir(exist_ok=True)

        def execute(command, **kwargs):
            self.assertEqual(kwargs, {'check': False})
            calls.append(command)
            if command[1] == 'build':
                output = Path(command[command.index('-o')+1])
                output.write_bytes(b'new executable')
                if cancel:
                    raise native._Cancelled(signal.SIGTERM)
                return subprocess.CompletedProcess(command, build_status)
            self.assertEqual(Path(command[0]).read_bytes(), b'new executable')
            return subprocess.CompletedProcess(command, run_status)

        handlers = {sig: signal.getsignal(sig)
                    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)}
        with patch.dict(os.environ, {'TMPDIR': str(temporary_root)}), \
                patch.object(native, 'compiler_identity', return_value=IDENTITY), \
                patch.object(native, 'build_object', return_value=self.root/'fixture.o'), \
                patch.object(native.subprocess, 'run', side_effect=execute):
            status = native.run_fixture(self.root, self.root/SUITE, self.root/'cache',
                                        'fake-cc', ['mojo', 'run', str(self.root/SUITE),
                                                    'program argument'])
        self.assertEqual(list(temporary_root.iterdir()), [])
        self.assertEqual({sig: signal.getsignal(sig) for sig in handlers}, handlers)
        return status, calls

    def test_run_stages_inherit_streams_environment_and_cleanup(self):
        status, calls = self.fixture_run()
        self.assertEqual(status, 0)
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[1][1:], ['program argument'])

    def test_failed_compilation_never_runs_partial_executable(self):
        status, calls = self.fixture_run(build_status=7)
        self.assertEqual(status, 7)
        self.assertEqual(len(calls), 1)

    def test_runtime_failure_and_signal_status_are_preserved(self):
        for code, expected in ((9, 9), (-signal.SIGTERM, 128+signal.SIGTERM)):
            with self.subTest(code=code):
                status, calls = self.fixture_run(run_status=code)
                self.assertEqual(status, expected)
                self.assertEqual(len(calls), 2)

    def test_cancelled_compilation_cleans_output_and_restores_handlers(self):
        status, calls = self.fixture_run(cancel=True)
        self.assertEqual(status, 128+signal.SIGTERM)
        self.assertEqual(len(calls), 1)

    def test_each_run_builds_a_fresh_executable_even_with_the_same_object_cache(self):
        first, one = self.fixture_run()
        second, two = self.fixture_run()
        self.assertEqual((first, second), (0, 0))
        self.assertNotEqual(one[1][0], two[1][0])
        self.assertEqual(one[0][one[0].index('-Xlinker')+1],
                         two[0][two[0].index('-Xlinker')+1])

    def test_cli_plain_run_execs_original_command_without_native_work(self):
        suite = self.root/'tests/test_plain.mojo'
        command = ['mojo', 'run', '-I', 'original include', str(suite), 'argument']
        with patch.object(native, 'compiler_identity', side_effect=AssertionError('not needed')), \
                patch.object(native, 'run_fixture', side_effect=AssertionError('not needed')), \
                patch.object(native.os, 'execvp', side_effect=SystemExit(17)) as execute:
            with self.assertRaises(SystemExit) as result:
                native.main(['run', '--root', str(self.root), '--suite', str(suite),
                             '--cache', str(self.root/'cache'), '--', *command])
        self.assertEqual(result.exception.code, 17)
        execute.assert_called_once_with('mojo', command)

    def test_cli_fixture_run_uses_supervised_translation(self):
        suite = self.root/SUITE
        command = ['mojo', 'run', '-I', str(self.root), str(suite)]
        with patch.object(native, 'run_fixture', return_value=23) as run, \
                patch.object(native.os, 'execvp', side_effect=AssertionError('must translate')):
            result = native.main(['run', '--root', str(self.root), '--suite', str(suite),
                                  '--cache', str(self.root/'cache'), '--cc', 'fake-cc',
                                  '--', *command])
        self.assertEqual(result, 23)
        self.assertEqual(run.call_args.args[-1], command)

    def test_missing_fixture_copy_fails(self):
        (self.root/FIXTURE).unlink()
        with self.assertRaises(FileNotFoundError):
            native.copy_fixtures(self.root, self.root/'coverage/build')

    def test_missing_or_ambiguous_source_link_target_fails(self):
        suite = self.root/SUITE
        for command in ([], ['mojo', 'doc', str(suite)], ['mojo', 'build', 'other.mojo'],
                        ['mojo', 'build', str(suite), str(suite)]):
            with self.subTest(command=command), self.assertRaises(ValueError):
                native.prepare_command(self.root, suite, self.root/'cache', 'fake-cc', command)

    def fake_compile(self, command, **kwargs):
        self.assertEqual(command[:1], ['fake-cc'])
        self.assertIn('-Werror', command)
        source = Path(command[command.index('-c') + 1])
        output = Path(command[command.index('-o') + 1])
        output.write_bytes(b'object:' + hashlib.sha256(source.read_bytes()).digest())
        return subprocess.CompletedProcess(command, 0)

    def test_object_cache_binds_source_compiler_and_object_bytes(self):
        with patch.object(native.subprocess, 'run', side_effect=self.fake_compile) as compile:
            one = native.build_object(self.root, FIXTURE, self.root/'cache', IDENTITY)
            self.assertEqual(compile.call_count, 1)
            self.assertEqual(native.build_object(self.root, FIXTURE, self.root/'cache', IDENTITY), one)
            self.assertEqual(compile.call_count, 1)
            one.write_bytes(b'corrupted')
            native.build_object(self.root, FIXTURE, self.root/'cache', IDENTITY)
            self.assertEqual(compile.call_count, 2)
            self.write(FIXTURE, 'int fixture(void) { return 2; }\n')
            two = native.build_object(self.root, FIXTURE, self.root/'cache', IDENTITY)
            self.assertNotEqual(one, two)
            changed_compiler = {**IDENTITY, 'version': 'fixture compiler 2'}
            three = native.build_object(self.root, FIXTURE, self.root/'cache', changed_compiler)
            self.assertNotEqual(two, three)
            self.assertEqual(compile.call_count, 4)
            self.assertEqual(json.loads(three.with_suffix('.json').read_text())['object_sha256'],
                             hashlib.sha256(three.read_bytes()).hexdigest())
            changed_bytes = {**changed_compiler, 'files': {'/external/cc': 'changed digest'}}
            four = native.build_object(self.root, FIXTURE, self.root/'cache', changed_bytes)
            self.assertNotEqual(three, four)
            self.assertEqual(compile.call_count, 5)

    def test_failed_compile_never_installs_object_or_metadata(self):
        error = subprocess.CalledProcessError(7, ['fake-cc'])
        with patch.object(native.subprocess, 'run', side_effect=error), \
                self.assertRaises(subprocess.CalledProcessError):
            native.build_object(self.root, FIXTURE, self.root/'cache', IDENTITY)
        self.assertEqual(list((self.root/'cache').iterdir()), [])

    def test_mutating_fixture_during_compile_is_rejected(self):
        def changing(command, **kwargs):
            self.fake_compile(command, **kwargs)
            self.write(FIXTURE, 'changed during build\n')
        with patch.object(native.subprocess, 'run', side_effect=changing), \
                self.assertRaisesRegex(ValueError, 'changed during compilation'):
            native.build_object(self.root, FIXTURE, self.root/'cache', IDENTITY)
        self.assertEqual(list((self.root/'cache').iterdir()), [])

    def key(self, suite):
        with patch.object(affected, 'ROOT', str(self.root)):
            return suite_key.suite_key(suite, ['compiler fingerprint'], set(affected.mojo_files()),
                                       {}, suite_key.asset_files(), {})

    def test_fixture_changes_only_dependent_suite_keys(self):
        native_before, plain_before = self.key(SUITE), self.key('tests/test_plain.mojo')
        aggregate_before = self.key('tests/aggregate.mojo')
        self.write(FIXTURE, 'new C fixture\n')
        self.assertNotEqual(self.key(SUITE), native_before)
        self.assertNotEqual(self.key('tests/aggregate.mojo'), aggregate_before)
        self.assertEqual(self.key('tests/test_plain.mojo'), plain_before)

    def test_global_key_and_affected_selection_include_c_and_headers(self):
        before = cache_key.cache_key(self.root, [])
        self.write(FIXTURE, 'new C fixture\n')
        self.assertNotEqual(cache_key.cache_key(self.root, []), before)
        before = cache_key.cache_key(self.root, [])
        self.write('tools/fixtures/control.h', 'changed declaration\n')
        self.assertNotEqual(cache_key.cache_key(self.root, []), before)
        self.assertEqual(affected.affected_set({FIXTURE: False}), affected.ALL)
        with patch.object(affected, 'git', side_effect=['base\n', '', FIXTURE+'\0']):
            self.assertIn(FIXTURE, affected.changed_paths('base'))

    def test_official_cpu_and_coverage_commands_share_the_adapter(self):
        make = (Path(__file__).resolve().parent.parent/'Makefile').read_text()
        self.assertIn('tools/native_test_support.py run --root .', make)
        self.assertIn('tools/native_test_support.py run --root $(COV_DIR)', make)
        self.assertIn('tools/native_test_support.py copy --root . --destination $(COV_DIR)', make)
        self.assertGreaterEqual(make.count('native-tests:$(NATIVE_TOOLCHAIN)'), 2)
        self.assertIn('TEST_TIMEOUT := 5', make)
        self.assertIn('COVERAGE_TESTS := $(CPU_TESTS)', make)


if __name__ == '__main__':
    unittest.main()
