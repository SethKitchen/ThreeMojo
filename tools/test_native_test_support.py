# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compiler-free native-fixture selection, cache and instrumented-root tests."""
import hashlib
import json
from pathlib import Path
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
        command = ['mojo', 'build', '--Werror', str(suite)]
        with patch.object(native, 'compiler_identity', side_effect=AssertionError('not needed')):
            self.assertEqual(native.prepare_command(self.root, suite, self.root/'cache', '', command), command)

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
        with patch.object(native, 'compiler_identity', return_value=IDENTITY), \
                patch.object(native, 'build_object', return_value=destination/'fixture.o') as build:
            actual = native.prepare_command(destination, suite, self.root/'cache', 'fake-cc', command)
        self.assertEqual(build.call_args.args[0], destination)
        self.assertEqual(actual[-1], str(suite))
        self.assertEqual(actual[2:4], ['-I', str(destination)])
        self.assertNotIn(str(self.root/SUITE), actual)

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
