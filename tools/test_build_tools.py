# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Regression tests for dependency selection, cache identity, and state keys."""

import os
from pathlib import Path
import re
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import affected
import cache_key
import shard


class DependencyTests(unittest.TestCase):
    def test_coverage_parser_and_scanner_each_select_all_suites(self):
        for path in ('coverage/instrument.mojo', 'coverage/scanner.mojo'):
            reasons = []
            self.assertEqual(affected.affected_set({path: False}, reasons), affected.ALL)
            self.assertTrue(any(path in reason for reason in reasons))

    def test_multiline_comments_and_aliases(self):
        self.assertEqual(affected.imported_names('''from math import (
            vector2, # first
            vector3 as vector,
        )
        import core.scene as scene, core.assets # both
        '''), ['math', 'math.vector2', 'math.vector3', 'core.scene', 'core.assets'])

    def test_nul_paths_and_untracked_tooling(self):
        with patch.object(affected, 'git', side_effect=[
            'abc\n', 'M\0assets/quoted "name"\n雪.bin\0D\0math/old.mojo\0',
            'tools/new.py\0tests/new suite.mojo\0notes.txt\0',
        ]) as git:
            self.assertEqual(affected.changed_paths('main'), {
                'assets/quoted "name"\n雪.bin': False, 'math/old.mojo': True,
                'tools/new.py': False, 'tests/new suite.mojo': False,
            })
            self.assertIn('-z', git.call_args_list[1].args)
            self.assertIn('-z', git.call_args_list[2].args)

    def test_unknown_change_is_conservative(self):
        self.assertEqual(affected.affected_set({'tools/new.py': False}), affected.ALL)

    def test_git_failure_is_conservative(self):
        with patch.object(affected, 'git', return_value=None):
            self.assertIsNone(affected.changed_paths('missing'))

    def test_sibling_imports_and_package_initializers(self):
        known = {'math/__init__.mojo', 'math/vector3.mojo', 'tests/math.mojo'}
        self.assertEqual(affected.resolve('math.vector3', 'core/scene.mojo', known),
                         ['math/__init__.mojo', 'math/vector3.mojo'])
        self.assertEqual(affected.resolve('math', 'tests/test.mojo', known), ['tests/math.mojo'])


class CacheTests(unittest.TestCase):
    def test_each_consumed_input_and_flags_changes_key(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('assets/fixture.bin', 'tools/affected.py', 'core/__init__.mojo', 'Makefile'):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'first')
            original = cache_key.cache_key(root, ['-I .'])
            self.assertNotEqual(original, cache_key.cache_key(root, ['-I . -O0']))
            for name in ('assets/fixture.bin', 'tools/affected.py', 'core/__init__.mojo', 'Makefile'):
                path = root / name
                path.write_bytes(b'second')
                self.assertNotEqual(original, cache_key.cache_key(root, ['-I .']), name)
                path.write_bytes(b'first')
            (root / 'assets/fixture.bin').rename(root / 'assets/renamed.bin')
            self.assertNotEqual(original, cache_key.cache_key(root, ['-I .']))

    def test_coverage_instrumenter_changes_invalidate_coverage_stamp(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tool = root / 'coverage/instrument.mojo'
            tool.parent.mkdir()
            tool.write_text('top-level-only parser')
            before = cache_key.cache_key(root, ['covered:module.mojo'])
            tool.write_text('grouped leaf parser')
            after = cache_key.cache_key(root, ['covered:module.mojo'])
            self.assertNotEqual(before, after)
            scanner = root / 'coverage/scanner.mojo'
            scanner.write_text('quote-aware scanner')
            self.assertNotEqual(after, cache_key.cache_key(root, ['covered:module.mojo']))

    def test_generated_outputs_are_not_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = cache_key.cache_key(root, [])
            for folder in ('.cache', 'coverage/build', 'node_modules', '.venv'):
                path = root / folder / 'generated.mojo'
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('ignored')
            self.assertEqual(original, cache_key.cache_key(root, []))


class MaterialStateTests(unittest.TestCase):
    def test_optimizer_key_accounts_for_every_material_field(self):
        root = Path(__file__).resolve().parent.parent
        source = (root / 'materials/material.mojo').read_text()
        body = source.split('struct Material(ImplicitlyCopyable):', 1)[1].split('    def __init__', 1)[0]
        fields = set(re.findall(r'^    var (\w+):', body, re.M))
        signature = (root / 'core/scene_optimizer.mojo').read_text().split('def material_signature(', 1)[1].split('def attributes_signature(', 1)[0]
        represented = set(re.findall(r'material\.(\w+)', signature))
        self.assertEqual(fields, represented, 'Update the complete material key when adding state')
        # Composite state has more than a single numeric value.
        for component in ('line_width.world_units', 'scattering.map', 'scattering.power',
                          'env_map_rotation.order.first', 'color.a'):
            self.assertIn('material.' + component, signature)



class GpuStatusTests(unittest.TestCase):
    def test_physical_virtual_absent_and_detection_error(self):
        import contextlib
        import io
        import sys
        import types
        import gpu_status

        driver = types.ModuleType('max.driver')
        driver.accelerator_count = lambda: 1
        driver.is_virtual_device_mode = lambda: False
        with patch.dict(sys.modules, {'max': types.ModuleType('max'), 'max.driver': driver}):
            with patch.object(sys, 'argv', ['gpu_status.py', '--available']):
                self.assertEqual(gpu_status.main(), 0)
                driver.is_virtual_device_mode = lambda: True
                self.assertEqual(gpu_status.main(), 1)
                driver.is_virtual_device_mode = lambda: False
                driver.accelerator_count = lambda: 0
                self.assertEqual(gpu_status.main(), 1)
            with patch.object(sys, 'argv', ['gpu_status.py']), contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(gpu_status.main(), 0)
                self.assertIn('SKIP', output.getvalue())
                driver.accelerator_count = lambda: 1
                self.assertEqual(gpu_status.main(), 0)
                self.assertIn('present', output.getvalue())
            with patch.object(sys, 'argv', ['gpu_status.py']), contextlib.redirect_stderr(io.StringIO()):
                del driver.accelerator_count
                self.assertEqual(gpu_status.main(), 2)


class ShardTests(unittest.TestCase):
    def test_groups_cover_every_suite_once_and_balance(self):
        weights = {'a': 9, 'b': 7, 'c': 4, 'd': 3, 'e': 2, 'f': 1}
        groups = shard.split(list(weights), 3, weights.__getitem__)
        dealt = [name for group in groups for name in group]
        self.assertEqual(sorted(dealt), sorted(weights))
        loads = [sum(weights[name] for name in group) for group in groups]
        self.assertEqual(sorted(loads), [8, 9, 9])
        # The same split every time.
        self.assertEqual(groups, shard.split(list(weights), 3, weights.__getitem__))

    def test_a_group_keeps_the_given_order_and_refuses_a_bad_index(self):
        import contextlib
        import io
        suites = ['tests/test_potpack.mojo', 'tests/test_vector3.mojo']
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(shard.main(['1/1'] + suites), 0)
        self.assertEqual(output.getvalue().split(), suites)
        with contextlib.redirect_stderr(io.StringIO()):
            for bad in ([], ['0/2'], ['3/2'], ['x/2'], ['1']):
                self.assertEqual(shard.main(bad), 2)


class MakeCacheTests(unittest.TestCase):
    def test_explicit_partial_checks_have_distinct_keys(self):
        import subprocess
        root = Path(__file__).resolve().parent.parent
        # A second makefile adds the target: macOS ships GNU Make 3.81,
        # which has no --eval.
        with tempfile.TemporaryDirectory() as scratch:
            extra = Path(scratch) / 'key.mk'
            extra.write_text('cache-key-test:\n\t@echo $(HASH)\n')
            command = ['make', '--no-print-directory', '-s', '-f', 'Makefile',
                       '-f', str(extra), 'cache-key-test']
            # CI runs this under `make AFFECTED=...`, which reaches this make
            # through MAKEFLAGS and the environment. A documentation-only
            # change then selects no suites, so CPU_TESTS= changes nothing.
            # Compare the explicit overrides against the full selection.
            env = {key: value for key, value in os.environ.items()
                   if key not in ('AFFECTED', 'MAKEFLAGS', 'MFLAGS', 'MAKELEVEL')}
            full = subprocess.check_output(command, cwd=root, text=True, env=env).strip()
            for override in ('CPU_TESTS=', 'COVERED=', 'MOJOFLAGS=-I . -O0'):
                partial = subprocess.check_output(command + [override], cwd=root, text=True,
                                                  env=env).strip()
                self.assertNotEqual(full, partial, override)


class CoverageStagingTests(unittest.TestCase):
    TEST_HELPERS = ('tests/carla_fixed_s_fixture.mojo',
                    'tests/exact_predicates_oracle.mojo')

    def seed_stub_instrumentation(self, root, destination):
        # The compiler is stubbed, but emits original-format outputs after
        # make clears the build directory. The proof binding stage stays real.
        compiler = destination.parent / 'staging_compiler.py'
        import inspect
        from test_coverage_loop_proofs import model_generation
        compiler.write_text(
            inspect.getsource(model_generation) + '\n' +
            'from pathlib import Path\nimport shutil, sys\n'
            'if sys.argv[1:] == ["--version"]:\n'
            '    print("staging fixture compiler")\n'
            '    raise SystemExit(0)\n'
            'index = sys.argv.index("coverage/build_cli.mojo")\n'
            'build = Path(sys.argv[index + 1])\n'
            f'root = Path({str(root)!r})\n'
            'rows = []\n'
            'for name in sys.argv[index + 2:]:\n'
            '    target = build / name\n'
            '    target.parent.mkdir(parents=True, exist_ok=True)\n'
            '    shutil.copyfile(root / name, target)\n'
            '    rows.append("L " + name.removesuffix(".mojo") + " 1\\n")\n'
            '(build / "manifest.txt").write_text("".join(rows))\n'
            'model_generation(root, build, sys.argv[index + 2:])\n')
        return compiler

    def test_import_only_helpers_are_libraries_and_coverage_passthrough(self):
        import subprocess
        root = Path(__file__).resolve().parent.parent
        names = ('HELPER_LIBS', 'DOC_SOURCES', 'ENTRY_POINTS',
                 'COVERAGE_PASSTHROUGH', 'COVERED')
        with tempfile.TemporaryDirectory() as directory:
            extra = Path(directory) / 'classification.mk'
            extra.write_text('classification-test:\n' + ''.join(
                f'\t@echo {name}=$({name})\n' for name in names))
            for inherited in (None, '-- AFFECTED=HEAD'):
                # CI exports command-line selections through MAKEFLAGS.
                # This checks canonical classification, not an affected slice.
                environment = {} if inherited is None else {'MAKEFLAGS': inherited}
                with self.subTest(makeflags=inherited), patch.dict('os.environ', environment):
                    output = subprocess.check_output([
                        'make', '--no-print-directory', '-s', '-f', 'Makefile',
                        '-f', str(extra), 'classification-test', 'AFFECTED=',
                    ], cwd=root, text=True)
                    values = dict(line.split('=', 1) for line in output.splitlines())
                    classified = {name: set(values[name].split()) for name in names}
                    for helper in self.TEST_HELPERS:
                        for name in ('HELPER_LIBS', 'DOC_SOURCES', 'COVERAGE_PASSTHROUGH'):
                            self.assertIn(helper, classified[name], name)
                        for name in ('ENTRY_POINTS', 'COVERED'):
                            self.assertNotIn(helper, classified[name], name)
                    # Measured production code stays instrumented, not copied through.
                    self.assertIn('math/vector3.mojo', classified['COVERED'])
                    self.assertTrue(classified['COVERED'].isdisjoint(
                        classified['COVERAGE_PASSTHROUGH']))

    def test_import_only_helpers_are_copied_beside_their_suites(self):
        import subprocess
        root = Path(__file__).resolve().parent.parent
        suites = ('tests/test_carla_fixed_s_fraction.mojo',
                  'tests/test_exact_predicates.mojo')
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'instrumented'
            compiler = self.seed_stub_instrumentation(root, destination)
            # Only the compiler is stubbed; exercise the real copy-through
            # recipe with its default helper classification.
            subprocess.run([
                'make', '--no-print-directory', '-s', 'coverage-instrument',
                f'MOJO=python3 {compiler}', f'COV_DIR={destination}',
                'LIB_SOURCES=math/vector3.mojo', 'COVERED=math/vector3.mojo',
                f'COVERAGE_TESTS={" ".join(suites)}',
                f'TESTS={" ".join(suites)}',
            ], cwd=root, check=True, capture_output=True, text=True)
            for path in self.TEST_HELPERS + suites:
                self.assertEqual((destination / path).read_bytes(),
                                 (root / path).read_bytes(), path)

    def test_unselected_sibling_modules_are_staged(self):
        import subprocess
        root = Path(__file__).resolve().parent.parent
        selected = 'tests/test_carla_render_scene.mojo'
        sibling = 'tests/test_carla_assets.mojo'
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'instrumented'
            compiler = self.seed_stub_instrumentation(root, destination)
            subprocess.run([
                'make', '--no-print-directory', '-s', 'coverage-instrument',
                f'MOJO=python3 {compiler}', f'COV_DIR={destination}',
                'COVERED=math/vector3.mojo', 'COVERAGE_PASSTHROUGH=',
                f'COVERAGE_TESTS={selected}', f'TESTS={selected} {sibling}',
            ], cwd=root, check=True, capture_output=True, text=True)
            self.assertTrue((destination / selected).is_file())
            self.assertTrue((destination / sibling).is_file())
            self.assertEqual((destination / sibling).read_bytes(),
                             (root / sibling).read_bytes())


class CoverageIoTests(unittest.TestCase):
    def test_kill_accepts_unreaped_group_only_where_macos_reports_eperm(self):
        import errno
        import coverage_io
        process = coverage_io._CaptureProcess(['true'], None, None, None)
        process.child, process.active = SimpleNamespace(pid=12345), True
        denied = PermissionError(errno.EPERM, 'Operation not permitted')
        with patch('coverage_io.os.killpg', side_effect=denied) as killpg:
            with patch('coverage_io.sys.platform', 'darwin'):
                process._kill()
            with patch('coverage_io.sys.platform', 'linux'), \
                    self.assertRaises(PermissionError) as raised:
                process._kill()
        self.assertIs(raised.exception, denied)
        self.assertEqual(killpg.call_count, 2)

    def test_capture_keeps_each_record_once_and_replay_keeps_order(self):
        self.check_capture_and_replay()

    def test_capture_and_replay_close_files_under_resource_warnings(self):
        with patch.dict('os.environ', {'PYTHONWARNINGS': 'error::ResourceWarning'}):
            self.check_capture_and_replay()

    def check_capture_and_replay(self):
        import gzip
        import sys
        import coverage_io
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stream = b'COVLINE:m:1\nCOVLINE:m:2.0:T\nCOVLINE:m:2:T\nCOVEVAL2:m:2:T:T-;\n' * 10000
            reduced = (b'COVLINE:m:1\nCOVLINE:m:2.0:T\nCOVLINE:m:2:T\n'
                       b'COVEVAL2:m:2:T:T-;\n')
            captures = []
            for index in range(2):
                source = root / f'{index}.input'
                source.write_bytes(stream + str(index).encode())
                capture = root / f'{index}.txt.gz'
                self.assertEqual(coverage_io.capture([
                    sys.executable, '-c', 'import sys,pathlib;sys.stderr.buffer.write(pathlib.Path(sys.argv[1]).read_bytes());print("passed")', str(source)
                ], root / f'{index}.out', capture), 0)
                # Other output passes through, after the records.
                self.assertEqual(gzip.decompress(capture.read_bytes()), reduced + str(index).encode())
                captures.append(capture)
            result = root / 'replayed'
            command = [sys.executable, '-c',
                       'import sys,shutil\nwith open(sys.argv[1], "wb") as out:\n'
                       ' for path in sys.argv[2:]:\n'
                       '  with open(path, "rb") as source: shutil.copyfileobj(source, out)', str(result)]
            self.assertEqual(coverage_io.report(command, captures), 0)
            self.assertEqual(result.read_bytes(), reduced + b'0' + reduced + b'1')

    def test_reducer_keeps_recursive_vectors_abandoned_hits_and_order(self):
        import coverage_io
        written = []
        reducer = coverage_io.Reducer(written.append)
        stream = [
            b'COVLINE:a:1.0:T\n', b'COVLINE:a:1.0:F\n',
            b'COVEVAL2:a:1:F:F-;\n', b'COVLINE:b:2.0:T\n',
            b'COVLINE:a:1.1:F\n', b'COVEVAL2:a:1:F:TF;\n',
            # A partial evaluation contributes a hit but no completed vector.
            b'COVLINE:b:2.1:T\n', b'COVLINE:b:2.0:F\n',
            b'COVEVAL2:b:2:F:F--;\n',
            b'hello\n', b'COVBRANCH:simple:3:T\n',
        ]
        for line in stream + stream[:8]:
            reducer.feed(line)
        self.assertEqual(written, stream[:-1] + [b'COVLINE:simple:3:T\n', stream[-1]])
        self.assertEqual(len(reducer.evaluations), 4)
        self.assertFalse(hasattr(reducer, 'pending'))

    def test_legacy_compound_records_require_recapture(self):
        import coverage_io
        written = []
        reducer = coverage_io.Reducer(written.append)
        with self.assertRaisesRegex(ValueError, 'recapture'):
            reducer.feed(b'COVBRANCH:m:4.0:T\n')
        self.assertEqual(written, [])
        self.assertEqual(reducer.evaluations, set())

    def test_malformed_version_two_records_are_rejected(self):
        import coverage_io
        for record in (
            b'COVEVAL2:m:4:T:TT', b'COVEVAL2:m:4:T:T;',
            b'COVEVAL2:m:4:T:--;', b'COVEVAL2:m:4:T:TX;',
            b'COVEVAL2:m:4:garbage:TT;', b'COVEVAL2:m:4.0:T:TT;',
            b'COVEVAL2:m:0:T:TT;', b'COVEVAL2::4:T:TT;',
            b'COVEVAL2:m:4:T:' + b'T' * 512 + b';',
        ):
            written = []
            reducer = coverage_io.Reducer(written.append)
            with self.assertRaisesRegex(ValueError, 'Malformed'):
                reducer.feed(record + b'\n')
            self.assertEqual(written, [])
            self.assertEqual(reducer.evaluations, set())

    def test_repeated_abandoned_and_complete_records_use_bounded_state(self):
        import coverage_io
        written = []
        reducer = coverage_io.Reducer(written.append)
        for _ in range(10000):
            reducer.feed(b'COVLINE:m:4.1:T\n')
            reducer.feed(b'COVEVAL2:m:4:F:F-;\n')
            reducer.feed(b'COVEVAL2:m:4:F:TF;\n')
        self.assertEqual(len(written), 3)
        self.assertEqual(len(reducer.evaluations), 2)
        self.assertEqual(len(reducer.payloads), 1)

    def test_utf8_record_sizes_and_missing_newline_fail_closed(self):
        import coverage_io
        prefix = 'COVEVAL2:é:1:T:'.encode()
        for size in (511, 512, 513):
            record = prefix + b'T' * (size - len(prefix) - 2) + b';\n'
            self.assertEqual(len(record), size)
            written = []
            reducer = coverage_io.Reducer(written.append)
            if size <= 512:
                reducer.feed(record)
                self.assertEqual(written, [record])
            else:
                with self.assertRaises(ValueError):
                    reducer.feed(record)
                self.assertEqual(written, [])
        for record in (b'COVEVAL2:m:4:T:TT', b'COVEVAL2:m:4:T:TT;'):
            with self.assertRaises(ValueError):
                coverage_io.Reducer(lambda value: None).feed(record)

    def test_invalid_outcome_is_rejected_before_it_adds_a_hit(self):
        import coverage_io
        for state in (b'', b'garbage', b't', b'False', b'T:extra'):
            for probe in (b'm:4', b'm:4.0'):
                written = []
                reducer = coverage_io.Reducer(written.append)
                with self.assertRaisesRegex(ValueError, 'Malformed branch outcome'):
                    reducer.feed(b'COVBRANCH:' + probe + b':' + state + b'\n')
                self.assertEqual(written, [])
                self.assertEqual(reducer.payloads, set())
                self.assertEqual(reducer.evaluations, set())

    def test_capture_cannot_fabricate_false_from_invalid_outcome(self):
        import gzip
        import sys
        import coverage_io
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(ValueError, 'Malformed branch outcome'):
                coverage_io.capture([sys.executable, '-c',
                    'import sys;sys.stderr.write("COVLINE:m:4\\nCOVBRANCH:m:4:T\\nCOVBRANCH:m:4:garbage\\n")'],
                    root / 'out', root / 'err.gz')
            self.assertNotIn(b'COVBRANCH:m:4:F', gzip.decompress((root / 'err.gz').read_bytes()))

    def test_failed_suite_retains_diagnostics_and_exit_status(self):
        import contextlib
        import io
        import sys
        import coverage_io
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()) as output:
            root = Path(directory)
            status = coverage_io.capture([sys.executable, '-c',
                'import sys; print("failed assertion");sys.stderr.write("COVLINE:m:1\\nerror detail\\n");sys.exit(7)'],
                root / 'out', root / 'err.gz')
            self.assertEqual(status, 7)
            self.assertIn('failed assertion', output.getvalue())
            self.assertIn('error detail', output.getvalue())

    def test_reporter_failure_does_not_wait_for_unread_fifos(self):
        import gzip
        import sys
        import coverage_io
        with tempfile.TemporaryDirectory() as directory:
            capture = Path(directory) / 'unused.gz'
            capture.write_bytes(gzip.compress(b'valid'))
            self.assertEqual(coverage_io.report([sys.executable, '-c', 'import sys;sys.exit(3)'], [capture]), 3)


if __name__ == '__main__':
    unittest.main()
