# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Command and object-composition controls for optional compiled captures."""
import os
from pathlib import Path
from types import SimpleNamespace
import stat
import unittest
from unittest.mock import patch

import coverage_hit_aot as profile
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
        with patch.object(native, 'dependency_inputs', return_value=[]), \
             patch.object(profile.os, 'execvp', side_effect=SystemExit(0)) as execute, \
             patch.object(native, 'run_fixture') as translated:
            with self.assertRaises(SystemExit) as outcome:
                profile.main(self.profile_arguments('raw'))
        self.assertEqual(outcome.exception.code, 0)
        execute.assert_called_once_with(self.command[0], self.command)
        translated.assert_not_called()

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


if __name__ == '__main__':
    unittest.main()
