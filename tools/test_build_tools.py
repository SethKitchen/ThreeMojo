# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Regression tests for make cache keys, coverage staging, and capture records."""

import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


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


if __name__ == '__main__':
    unittest.main()
