# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check the maintained coverage tree's import inputs without compiling Mojo."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


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
                       'examples/unrelated.mojo')
        for name in self.inputs:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('original ' + name + '\n')
        (self.root / 'compiler.py').write_text(
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
            '(root / "manifest.txt").write_text("\\n".join(sys.argv[4:]))\n')
        source = (ROOT / 'Makefile').read_text()
        start = source.index('define run\n')
        run = source[start:source.index('\nendef', start) + len('\nendef')]
        start = source.index('COVERAGE_PASSTHROUGH :=')
        passthrough = source[start:source.index('\n\n', start)]
        start = source.index('coverage-instrument:\n')
        recipe = source[start:source.index('\ncoverage-capture:', start)]
        (self.root / 'Makefile').write_text(
            'MOJO := python3 compiler.py\nMOJOFLAGS :=\nCOV_DIR := build\n'
            'LIB_SOURCES := math/measured.mojo math/unmeasured.mojo\n'
            'ENTRY_POINTS := bench/helper.mojo bench/nested/driver.mojo '
            'tests/test_driver.mojo examples/unrelated.mojo\n'
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
                         'math/measured.mojo')
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
