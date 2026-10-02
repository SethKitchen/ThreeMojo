# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exercise the GPU compile-only Make recipes without invoking Mojo."""

from pathlib import Path
import json
import os
import re
import shlex
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
GPU_ENTRIES = (
    'tests/test_gpu.mojo', 'tests/test_gpu_layout.mojo',
    'tests/test_gpu_volume_packing.mojo', 'bench/raster_bench.mojo',
)


class GpuCompileRecipeTests(unittest.TestCase):
    def run_recipe(self, targets=('compile-gpu',), failed_source=None, extra_entry=False):
        source = (ROOT / 'Makefile').read_text()
        start = source.index('compile-gpu: $(COMPILE_GPU_STAMP)\n')
        end = source.index('\n# mojo format', start)
        # Use the maintained lists, including their variable references.
        lists = '\n'.join(re.findall(
            r'^GPU_(?:LIB_SOURCES|HOST_TESTS|TESTS|ENTRY_POINTS)\s*:=.*$',
            source.replace('\\\n', ' '), re.MULTILINE))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'compiler.py').write_text(
                'import json, sys\n'
                'with open("invocations", "a") as log:\n'
                '    log.write(json.dumps(sys.argv[1:]) + "\\n")\n'
                f'if sys.argv[-1] == {failed_source!r}:\n'
                '    print("compile error from " + sys.argv[-1])\n'
                '    raise SystemExit(7)\n')
            (root / 'Makefile').write_text(
                'JOBS := 1\nMOJO := python3 compiler.py\n'
                'MOJOFLAGS := -I . --target-accelerator=sm_80\n'
                'COMPILE_GPU_STAMP := compile-gpu-stamp\n'
                'LINT_GPU_STAMP := lint-gpu-stamp\n'
                'stamp = touch $(1)-stamp\n' + lists + '\n'
                + ('GPU_ENTRY_POINTS += tests/new_device.mojo\n' if extra_entry else '')
                + source[start:end] + '\n')
            # Parent make overrides must never replace the harmless stub.
            environment = {key: value for key, value in os.environ.items()
                           if key not in {'MAKEFLAGS', 'MFLAGS', 'MAKEOVERRIDES',
                                          'MAKELEVEL', 'MAKEFILES', 'GNUMAKEFLAGS'}}
            results = [subprocess.run(['make', '-s', *shlex.split(target)], cwd=root,
                                      text=True, capture_output=True, env=environment)
                       for target in targets]
            log = root / 'invocations'
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            stamps = {path.name for path in root.glob('*-stamp')}
            return results, calls, stamps

    def test_all_entries_build_with_explicit_target_without_running(self):
        results, calls, stamps = self.run_recipe(extra_entry=True)
        self.assertEqual(results[0].returncode, 0, results[0].stdout + results[0].stderr)
        self.assertEqual({call[-1] for call in calls},
                         {*GPU_ENTRIES, 'tests/new_device.mojo'})
        for call in calls:
            self.assertEqual(call[:-1], [
                'build', '-I', '.', '--target-accelerator=sm_80',
                '--Werror', '-o', '/dev/null',
            ])
        self.assertEqual(stamps, {'compile-gpu-stamp'})
        self.assertIn('compiled (not run)', results[0].stdout)

    def test_any_entry_compile_error_fails_without_stamping(self):
        for entry in GPU_ENTRIES:
            with self.subTest(entry=entry):
                results, calls, stamps = self.run_recipe(failed_source=entry)
                self.assertNotEqual(results[0].returncode, 0)
                self.assertIn('compile error from ' + entry, results[0].stdout)
                self.assertEqual(stamps, set())
                self.assertNotIn('compiled (not run)', results[0].stdout)

    def test_cache_hit_skips_build_and_force_rebuilds(self):
        results, calls, stamps = self.run_recipe(
            targets=('compile-gpu', 'compile-gpu', '-B compile-gpu'))
        self.assertTrue(all(result.returncode == 0 for result in results))
        self.assertEqual(len(calls), 2 * len(GPU_ENTRIES))
        self.assertNotIn('compiled (not run)', results[1].stdout)
        self.assertIn('compiled (not run)', results[2].stdout)
        self.assertEqual(stamps, {'compile-gpu-stamp'})

    def test_lint_reuses_the_compile_step_and_still_checks_library_docs(self):
        results, calls, stamps = self.run_recipe(
            targets=('lint-gpu MOJOFLAGS="-I ."',))
        self.assertEqual(results[0].returncode, 0, results[0].stdout + results[0].stderr)
        self.assertEqual([call[0] for call in calls],
                         ['build'] * len(GPU_ENTRIES) + ['doc'] * 2)
        self.assertEqual({call[-1] for call in calls if call[0] == 'doc'},
                         {'render/gpu.mojo', 'render/gpu_vxgi.mojo'})
        self.assertEqual(stamps, {'compile-gpu-stamp', 'lint-gpu-stamp'})
        for call in calls:
            self.assertEqual(call[1:3], ['-I', '.'])
            self.assertNotIn('--target-accelerator=sm_80', call)

    def test_failed_compile_also_blocks_lint_docs_and_success_stamp(self):
        results, calls, stamps = self.run_recipe(
            targets=('lint-gpu',), failed_source='tests/test_gpu.mojo')
        self.assertNotEqual(results[0].returncode, 0)
        self.assertTrue(all(call[0] == 'build' for call in calls))
        self.assertEqual(stamps, set())
        self.assertNotIn('No warnings (GPU)', results[0].stdout)

    def test_outer_make_overrides_cannot_replace_the_fixture_compiler(self):
        with patch.dict(os.environ, {
            'MAKEFLAGS': '-- MOJO=nonexistent-outer-compiler',
            'MAKEOVERRIDES': 'MOJO=nonexistent-outer-compiler',
            'MFLAGS': '-e', 'GNUMAKEFLAGS': '-e',
            'MAKEFILES': 'nonexistent-outer-include', 'MAKELEVEL': '7',
        }):
            results, calls, stamps = self.run_recipe()
            self.assertEqual(results[0].returncode, 0, results[0].stdout + results[0].stderr)
            self.assertEqual(len(calls), len(GPU_ENTRIES))
            self.assertEqual(stamps, {'compile-gpu-stamp'})


if __name__ == '__main__':
    unittest.main()
