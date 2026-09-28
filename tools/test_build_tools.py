# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Regression tests for dependency selection, cache identity, and state keys."""

from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

import affected
import cache_key


class DependencyTests(unittest.TestCase):
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
            full = subprocess.check_output(command, cwd=root, text=True).strip()
            for override in ('CPU_TESTS=', 'COVERED=', 'MOJOFLAGS=-I . -O0'):
                partial = subprocess.check_output(command + [override], cwd=root, text=True).strip()
                self.assertNotEqual(full, partial, override)


class CoverageIoTests(unittest.TestCase):
    def test_capture_and_replay_preserve_every_byte_and_order(self):
        import gzip
        import sys
        import coverage_io
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = b'COVLINE:m:1\nCOVBRANCH:m:2.0:T\nCOVBRANCH:m:2:T\n' * 10000
            captures = []
            for index in range(2):
                source = root / f'{index}.input'
                source.write_bytes(expected + str(index).encode())
                capture = root / f'{index}.txt.gz'
                self.assertEqual(coverage_io.capture([
                    sys.executable, '-c', 'import sys;sys.stderr.buffer.write(open(sys.argv[1], "rb").read());print("passed")', str(source)
                ], root / f'{index}.out', capture), 0)
                self.assertEqual(gzip.decompress(capture.read_bytes()), source.read_bytes())
                self.assertLess(capture.stat().st_size, source.stat().st_size // 10)
                captures.append(capture)
            result = root / 'replayed'
            command = [sys.executable, '-c',
                       'import sys; out=open(sys.argv[1], "wb"); [out.write(open(p,"rb").read()) for p in sys.argv[2:]]', str(result)]
            self.assertEqual(coverage_io.report(command, captures), 0)
            self.assertEqual(result.read_bytes(), expected + b'0' + expected + b'1')

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
