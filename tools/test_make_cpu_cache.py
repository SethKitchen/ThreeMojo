# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exercise the CPU xargs recipe without running the Mojo compiler."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


class CpuCacheRecipeTests(unittest.TestCase):
    def run_recipe(self, pairs, compiler_status=0):
        source = (ROOT / 'Makefile').read_text()
        start = source.index('\t@xargs -n 2 -P $(JOBS)')
        end = source.index('\n\t@echo "All ', start)
        recipe = source[start:end]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for folder in ('cache/bin', 'cache/suites', 'tools', 'tests'):
                (root / folder).mkdir(parents=True, exist_ok=True)
            sentinel = root / 'cache/bin/preserve'
            sentinel.write_text('unchanged')
            (root / 'cache/suites-to-run').write_text(pairs)
            for name in ('test_a', 'test_b'):
                (root / f'tests/{name}.mojo').write_text('def test_stub():\n    pass\n')
            for name in ('run_suite.py', 'test_environment.py'):
                shutil.copyfile(ROOT / 'tools' / name, root / 'tools' / name)
            output = ('Running 1 tests for stub.mojo\n'
                      'PASS [ 1.0 ] test_stub\n'
                      'Summary [ 1.0 ] 1 tests run: 1 passed , 0 failed , 0 skipped\n')
            program = '#!/usr/bin/env python3\nprint(' + repr(output) + ', end="")\n'
            (root / 'compiler.py').write_text(
                'from pathlib import Path\nimport sys\n'
                'with open("invocations", "a") as log: log.write(sys.argv[-1] + "\\n")\n'
                f'if {compiler_status}: raise SystemExit({compiler_status})\n'
                'binary = Path(sys.argv[sys.argv.index("-o") + 1])\n'
                f'binary.write_text({program!r})\n'
                'binary.chmod(0o700)\n')
            (root / 'Makefile').write_text(
                'JOBS := 1\nCACHE_DIR := cache\nBIN_DIR := cache/bin\n'
                'SUITE_STAMPS := cache/suites\nMOJO := python3 compiler.py\n'
                'TEST_TIMEOUT := 5\nall:\n' + recipe + '\n')
            result = subprocess.run(['make', '-s'], cwd=root, text=True, capture_output=True)
            calls = (root / 'invocations').read_text().splitlines() if (root / 'invocations').exists() else []
            stamps = sorted(path.name for path in (root / 'cache/suites').iterdir())
            self.assertEqual(sentinel.read_text(), 'unchanged')
            return result, calls, stamps

    def test_empty_cache_hit_does_not_invoke_compiler_or_mutate_stamps(self):
        result, calls, stamps = self.run_recipe('')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls, [])
        self.assertEqual(stamps, [])
        self.assertEqual(result.stderr, '')

    def test_nonempty_pairs_run_and_receive_their_own_stamps(self):
        result, calls, stamps = self.run_recipe('tests/test_a.mojo aaa\ntests/test_b.mojo bbb\n')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls, ['tests/test_a.mojo', 'tests/test_b.mojo'])
        self.assertEqual(stamps, ['test_a-aaa', 'test_b-bbb'])

    def test_failed_build_is_not_stamped_or_hidden(self):
        result, calls, stamps = self.run_recipe('tests/test_a.mojo aaa\n', 7)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, ['tests/test_a.mojo'])
        self.assertEqual(stamps, [])
        self.assertIn('Some CPU suites FAILED.', result.stdout)


if __name__ == '__main__':
    unittest.main()
