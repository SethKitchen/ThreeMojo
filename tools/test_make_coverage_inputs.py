# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check the maintained coverage tree's import inputs without compiling Mojo."""

import os
import hashlib
import inspect
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import affected
import suite_key
import coverage_loop_proofs
from test_coverage_loop_proofs import model_generation


ROOT = Path(__file__).resolve().parent.parent
MAKE_ENVIRONMENT = {'MAKEFLAGS', 'MFLAGS', 'MAKEOVERRIDES', 'MAKELEVEL',
                    'MAKEFILES', 'GNUMAKEFLAGS'}


class CoverageInputTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='coverage inputs ')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.environment = {key: value for key, value in os.environ.items()
                            if key not in MAKE_ENVIRONMENT}
        self.inputs = ('math/measured.mojo', 'math/unmeasured.mojo',
                       'bench/helper.mojo', 'bench/nested/driver.mojo',
                       'coverage/runtime.mojo', 'tests/test_driver.mojo',
                       'tests/_shared.mojo', 'tests/_nested.mojo',
                       'examples/unrelated.mojo',
                       'tools/doc_lint.mojo', 'tools/anatomy_pairs.mojo',
                       'tools/anatomy_probe.mojo',
                       'tools/capture_carla_fixed_s_controls.mojo',
                       'tools/draco_export_check.mojo',
                       'tools/fixtures/carla_sum2_fp_state.c')
        for name in self.inputs:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('original ' + name + '\n')
        shutil.copyfile(ROOT / 'tools/native_test_support.py',
                        self.root / 'tools/native_test_support.py')
        for name in coverage_loop_proofs.TOOL_INPUTS:
            destination = self.root / name
            if name != 'Makefile' and not destination.exists():
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, destination)
        (self.root / 'compiler.py').write_text(
            inspect.getsource(model_generation) + '\n' +
            'import os, sys\n'
            'from pathlib import Path\n'
            'assert sys.argv[1:3] == ["run", "coverage/build_cli.mojo"]\n'
            'if os.environ.get("FAIL_INSTRUMENTER"):\n'
            '    raise SystemExit(7)\n'
            'root = Path(sys.argv[3])\n'
            'for name in sys.argv[4:]:\n'
            '    path = root / name\n'
            '    path.parent.mkdir(parents=True, exist_ok=True)\n'
            '    path.write_text("instrumented " + name + "\\n")\n'
            '(root / "manifest.txt").write_text("".join("L " + name.removesuffix(".mojo") + " 1\\n" for name in sys.argv[4:]))\n'
            'model_generation(Path.cwd(), root, sys.argv[4:])\n')
        source = (ROOT / 'Makefile').read_text()
        quote = next(line for line in source.splitlines() if line.startswith('quote ='))
        start = source.index('define run\n')
        run = source[start:source.index('\nendef', start) + len('\nendef')]
        start = source.index('COVERAGE_PASSTHROUGH :=')
        passthrough = source[start:source.index('\n\n', start)]
        start = source.index('coverage-instrument:\n')
        recipe = source[start:source.index('\ncoverage-capture:', start)]
        (self.root / 'Makefile').write_text(
            'MOJO := python3 compiler.py\nMOJOFLAGS :=\nCOV_DIR := build\n' + quote + '\n' +
            'LIB_SOURCES := math/measured.mojo math/unmeasured.mojo\n'
            'HELPER_LIBS := tests/_shared.mojo tests/_nested.mojo tools/anatomy_pairs.mojo\n'
            'ENTRY_POINTS := bench/helper.mojo bench/nested/driver.mojo '
            'tests/test_driver.mojo examples/unrelated.mojo '
            'tools/doc_lint.mojo tools/anatomy_probe.mojo '
            'tools/capture_carla_fixed_s_controls.mojo tools/draco_export_check.mojo\n'
            'TESTS := tests/test_driver.mojo\n'
            'COVERED := math/measured.mojo\n' + run + '\n' +
            passthrough + '\n' + recipe)

    def make(self, *arguments):
        return subprocess.run(['make', '-s', *arguments, 'coverage-instrument'],
                              cwd=self.root, text=True, capture_output=True,
                              env=self.environment, timeout=5)

    def test_import_helpers_copy_without_expanding_measurement(self):
        result = self.make()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / 'build/manifest.txt').read_text(),
                         'L math/measured 1\n')
        coverage_loop_proofs.verify(self.root / 'build/loop-proofs.json',
                                    self.root, self.root / 'build', '', '',
                                    mojo='python3 compiler.py', capture_cache='/native-coverage', suites=[])
        for name in self.inputs:
            target = self.root / 'build' / name
            if name == 'examples/unrelated.mojo':
                self.assertFalse(target.exists())
            elif name == 'math/measured.mojo':
                self.assertEqual(target.read_text(), 'instrumented ' + name + '\n')
            else:
                self.assertEqual(target.read_bytes(), (self.root / name).read_bytes())

    def test_explicitly_measured_helper_is_not_overwritten(self):
        result = self.make('COVERED=math/measured.mojo bench/helper.mojo')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / 'build/bench/helper.mojo').read_text(),
                         'instrumented bench/helper.mojo\n')
        self.assertEqual((self.root / 'build/bench/nested/driver.mojo').read_bytes(),
                         (self.root / 'bench/nested/driver.mojo').read_bytes())

    def test_nested_test_helpers_copy_unchanged_without_new_obligations(self):
        nested = b'from math.measured import value\r\n'
        shared = b'from tests._nested import value\n'
        (self.root / 'tests/_nested.mojo').write_bytes(nested)
        (self.root / 'tests/_shared.mojo').write_bytes(shared)
        result = self.make()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / 'build/tests/_nested.mojo').read_bytes(), nested)
        self.assertEqual((self.root / 'build/tests/_shared.mojo').read_bytes(), shared)
        self.assertEqual((self.root / 'build/manifest.txt').read_text(),
                         'L math/measured 1\n')

    def test_tool_imports_resolve_inside_stage_and_remain_proof_bound(self):
        # Reproduce the doc-link suite's imported CLI, with a nested tool
        # dependency. Resolve solely against staged files: no real-tree fallback.
        (self.root / 'tests/test_driver.mojo').write_text(
            'from tools.doc_lint import check_links\n')
        (self.root / 'tools/doc_lint.mojo').write_text(
            'from tools.anatomy_probe import helper\n'
            'def main():\n    pass\n')
        result = self.make()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        build = self.root / 'build'
        source_files = set(self.inputs)
        staged_files = {path.relative_to(build).as_posix()
                        for path in build.rglob('*.mojo')}
        imports = {}
        with patch.object(affected, 'ROOT', str(self.root)):
            closure = suite_key.closure('tests/test_driver.mojo', source_files, imports)
        self.assertIn('tools/doc_lint.mojo', closure)
        self.assertIn('tools/anatomy_probe.mojo', closure)
        for name in closure:
            self.assertIn(name, staged_files)
            for imported in affected.imported_names((self.root / name).read_text()):
                self.assertEqual(affected.resolve(imported, name, staged_files),
                                 affected.resolve(imported, name, source_files))
        envelope = coverage_loop_proofs.verify(
            build / 'loop-proofs.json', self.root, build, '', '',
            mojo='python3 compiler.py', capture_cache='/native-coverage', suites=[])
        for name in self.inputs:
            if not name.startswith('tools/') or not name.endswith('.mojo'):
                continue
            original = (self.root / name).read_bytes()
            self.assertEqual((build / name).read_bytes(), original)
            digest = hashlib.sha256(original).hexdigest()
            self.assertEqual(envelope['receipt']['inputs'][name],
                             {'source': digest, 'instrumented': digest})
            (build / name).write_bytes(original + b'# changed after sealing\n')
            with self.assertRaises(ValueError):
                coverage_loop_proofs.check_capture_inputs(envelope, self.root, build)
            (build / name).write_bytes(original)
        coverage_loop_proofs.check_capture_inputs(envelope, self.root, build)
        self.assertEqual((build / 'manifest.txt').read_text(), 'L math/measured 1\n')

    def test_empty_measurement_stays_unmeasured(self):
        result = self.make('COVERED=')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('coverage not measured', result.stdout)
        self.assertFalse((self.root / 'build').exists())

    def test_instrumenter_failure_stops_before_copying(self):
        self.environment['FAIL_INSTRUMENTER'] = '1'
        result = self.make()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'build/bench/helper.mojo').exists())
        self.assertFalse((self.root / 'build/manifest.txt').exists())


if __name__ == '__main__':
    unittest.main()
