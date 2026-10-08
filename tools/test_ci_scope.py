# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Scoped CI regression fixtures. No Mojo compiler or native suite is run."""

import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import ci_scope


SOURCES = {
    'core/common.mojo': 'def common():\n    pass\n',
    'core/used.mojo': 'from core.common import common\ndef used():\n    pass\n',
    'core/consumer.mojo': 'from core.used import used\ndef consumer():\n    pass\n',
    'core/other.mojo': 'def other():\n    pass\n',
    'tests/_helper.mojo': 'from core.used import used\n',
    'tests/test_a.mojo': 'from tests._helper import used\nfrom core.common import common\n',
    'tests/test_b.mojo': 'from core.common import common\n',
    'tests/test_consumer.mojo': 'from core.consumer import consumer\n',
    'tests/test_other.mojo': 'from core.other import other\n',
    'examples/used.mojo': 'from core.used import used\n',
    'render/gpu.mojo': 'from core.used import used\n# "assets/gpu/"\n',
    'tests/test_gpu.mojo': 'from render.gpu import gpu\n',
    'tests/test_gpu_layout.mojo': 'from render.gpu import gpu\n',
    'coverage/runtime.mojo': 'def runtime():\n    pass\n',
    'tests/test_coverage.mojo': 'from coverage.runtime import runtime\n',
}


def selected(changed, *, sources=None, old=None):
    with patch.object(ci_scope, 'source_tree', return_value=sources or SOURCES):
        return ci_scope.plan(changed, old={} if old is None else old)


class RoutingTests(unittest.TestCase):
    def test_pr690_and_controller_changes_only_run_tools(self):
        paths = ['tools/test_build_tools.py', 'tools/test_compiler_metadata.py',
                 'tools/test_coverage_lifecycle.py', 'tools/ci_scope.py',
                 'tools/test_ci_scope.py', 'tools/test_ci_policy.py', '.github/workflows/ci.yml']
        value = selected(dict.fromkeys(paths, False))
        self.assertFalse(value['full'])
        self.assertEqual({name for name, flag in value['flags'].items() if flag}, {'tools', 'lint'})
        self.assertTrue(all(not files for files in value['files'].values()))

    def test_pr682_transport_and_proofs_run_real_native_protocol_checks(self):
        for path in ['tools/coverage_hit_cache.c', 'tools/fixtures/coverage_hit_transport_faults.c',
                     'tools/coverage_hit_faults.py', 'tools/check_coverage_loop_proofs.py',
                     'tools/coverage_loop_proofs.py', 'tools/carla_lane_oracle/source_contracts.py']:
            with self.subTest(path=path):
                value = selected({path: False})
                self.assertTrue(value['flags']['coverage_tools'])
                self.assertFalse(value['flags']['coverage'])
                self.assertFalse(value['flags']['cpu'])

    def test_production_changes_follow_consumers_not_shared_dependencies(self):
        value = selected({'core/used.mojo': False, 'tests/test_a.mojo': False})
        self.assertEqual(set(value['files']['cpu_tests']), {'tests/test_a.mojo', 'tests/test_consumer.mojo'})
        self.assertEqual(set(value['files']['covered']), {'core/used.mojo', 'core/consumer.mojo'})
        self.assertEqual(value['files']['coverage_tests'], value['files']['cpu_tests'])
        self.assertNotIn('core/common.mojo', value['files']['covered'])
        self.assertTrue(value['flags']['gpu'])

    def test_edited_test_runs_without_global_unchanged_library_gate(self):
        value = selected({'tests/test_a.mojo': False})
        self.assertEqual(value['files']['cpu_tests'], ['tests/test_a.mojo'])
        self.assertEqual(value['files']['covered'], [])
        self.assertFalse(value['flags']['coverage'])

    def test_edited_helper_selects_its_importers_without_import_siblings(self):
        value = selected({'tests/_helper.mojo': False})
        self.assertEqual(value['files']['cpu_tests'], ['tests/test_a.mojo'])
        self.assertEqual(value['files']['covered'], [])

    def test_examples_benchmark_results_and_generator_do_not_gate_library_coverage(self):
        value = selected({'examples/used.mojo': False, 'tools/bench_examples.py': False,
                          'bench/results-linux.json': False, 'docs/wiki/Examples.md': False})
        self.assertEqual(value['files']['cpu_entries'], ['examples/used.mojo'])
        self.assertFalse(value['flags']['cpu'])
        self.assertFalse(value['flags']['coverage'])
        self.assertTrue(value['flags']['native'])
        self.assertTrue(value['flags']['docs'])

    def test_removed_import_retains_old_transitive_coverage(self):
        sources = dict(SOURCES)
        sources['tests/test_a.mojo'] = 'def test_nothing():\n    pass\n'
        value = selected({'tests/test_a.mojo': False}, sources=sources, old=SOURCES)
        self.assertEqual(set(value['files']['covered']), {'core/common.mojo', 'core/used.mojo'})
        self.assertIn('tests/test_b.mojo', value['files']['coverage_tests'])
        self.assertNotIn('tests/test_b.mojo', value['files']['cpu_tests'])

    def test_deleted_test_preserves_old_obligations_without_running_missing_file(self):
        sources = dict(SOURCES)
        del sources['tests/test_a.mojo']
        value = selected({'tests/test_a.mojo': True}, sources=sources, old=SOURCES)
        self.assertNotIn('tests/test_a.mojo', value['files']['cpu_tests'])
        self.assertIn('core/used.mojo', value['files']['covered'])
        self.assertIn('tests/test_b.mojo', value['files']['coverage_tests'])

    def test_removed_helper_import_and_package_reexport_survive(self):
        before = dict(SOURCES)
        before['core/__init__.mojo'] = 'from core.facade import used\n'
        before['core/facade.mojo'] = 'from core.used import used\n'
        before['tests/_helper.mojo'] = 'from core import used\n'
        after = dict(before)
        after['tests/_helper.mojo'] = 'def unrelated():\n    pass\n'
        value = selected({'tests/_helper.mojo': False}, sources=after, old=before)
        self.assertIn('core/used.mojo', value['files']['covered'])
        self.assertIn('core/common.mojo', value['files']['covered'])

    def test_new_sibling_shadow_cannot_erase_removed_import_obligation(self):
        before = {'core/module.mojo': 'def foo():\n    pass\n',
                  'tests/test_a.mojo': 'from core.module import foo\n'}
        after = dict(before)
        after['tests/test_a.mojo'] = 'def empty():\n    pass\n'
        after['tests/core/module.mojo'] = 'def foo():\n    pass\n'
        value = selected({'tests/test_a.mojo': False, 'tests/core/module.mojo': False},
                         sources=after, old=before)
        self.assertEqual(value['files']['covered'], ['core/module.mojo'])
        self.assertTrue(value['flags']['coverage'])

    def test_deleted_shared_module_still_selects_cpu_and_gpu_consumers(self):
        sources = dict(SOURCES)
        del sources['core/used.mojo']
        value = selected({'core/used.mojo': True}, sources=sources)
        self.assertTrue(value['flags']['gpu'])
        self.assertIn('tests/test_a.mojo', value['files']['cpu_tests'])
        self.assertIn('core/consumer.mojo', value['files']['covered'])

    def test_gpu_quoted_asset_uses_expanded_seeds(self):
        value = selected({'assets/gpu/file with spaces\n雪.bin': False})
        self.assertTrue(value['flags']['gpu'])
        self.assertFalse(value['flags']['cpu'])
        self.assertFalse(value['flags']['coverage'])

    def test_docs_and_empty_changes_skip_all_native_work_even_on_main(self):
        for change in [{}, {'README.md': False}, {'coverage/README.md': False},
                       {'tools/carla_lane_oracle/README.md': False}, {'assets/gpu/README.md': False}]:
            value = selected(change)
            for name in ('native', 'cpu', 'coverage', 'gpu', 'coverage_tools', 'portability'):
                self.assertFalse(value['flags'][name], (change, name))

    def test_unknown_input_and_runtime_named_test_are_full_audits(self):
        for change in [None, {'Makefile': False}, {'unknown.cfg': False},
                       {'tools/new_runtime.py': False}, {'tools/test_environment.py': False},
                       {'.github/workflows/other.yml': False}, {'new_package/module.mojo': False},
                       {'untracked.mojo': False}]:
            self.assertTrue(selected(change)['full'])

    def test_benchmark_report_only_keeps_python_provenance_gate(self):
        value = selected({'bench/results-linux.json': False})
        self.assertTrue(value['flags']['tools'])
        self.assertFalse(value['flags']['native'])
        self.assertFalse(value['flags']['coverage'])

    def test_native_portability_embedded_protocol_and_export_dependencies(self):
        sources = dict(SOURCES)
        sources['tests/portability_probe.mojo'] = 'from core.used import used\n'
        self.assertTrue(selected({'core/used.mojo': False}, sources=sources)['flags']['portability'])
        self.assertTrue(selected({'render/tasks.mojo': False})['flags']['coverage_tools'])
        self.assertTrue(selected({'assets/carla/tools/export/build_towns.py': False})['flags']['export'])

    def test_unavailable_test_history_is_full_audit(self):
        with patch.object(ci_scope, 'source_tree', return_value=SOURCES), \
                patch.object(ci_scope, 'previous_tests', side_effect=OSError('unavailable')):
            self.assertTrue(ci_scope.plan({'tests/test_a.mojo': False}, base='missing')['full'])

    def test_unreadable_graph_is_error_not_empty_success(self):
        with patch.object(ci_scope, 'source_tree', side_effect=UnicodeError('bad source')):
            with self.assertRaises(UnicodeError):
                ci_scope.plan({'README.md': False})

    def test_unsafe_native_filename_fails_instead_of_entering_make(self):
        sources = dict(SOURCES)
        sources['tests/test_$(shell touch BAD).mojo'] = 'pass\n'
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            selected(None, sources=sources)


class DiffTests(unittest.TestCase):
    def test_nul_paths_deletion_untracked_and_no_shell_interpolation(self):
        with patch.object(ci_scope, 'git', side_effect=['abc\n', 'abc\n',
                'M\0assets/quotes "x"\n雪.bin\0D\0core/old.mojo\0',
                'tools/new.py\0notes.txt\0']) as git:
            value = ci_scope.changed_paths('abc')
            self.assertEqual(value, {'assets/quotes "x"\n雪.bin': False,
                                     'core/old.mojo': True, 'tools/new.py': False})
            self.assertEqual(git.call_args_list[2].args[-1], '--')

    def test_unknown_divergent_and_malformed_diffs_are_full(self):
        for outputs in [['old\n', 'different\n'], ['abc\n', 'abc\n', 'M\0missing'],
                        ['abc\n', 'abc\n', 'Q\0path\0']]:
            with patch.object(ci_scope, 'git', side_effect=outputs):
                self.assertIsNone(ci_scope.changed_paths('main'))
        with patch.object(ci_scope, 'git', side_effect=OSError('missing git')):
            self.assertIsNone(ci_scope.changed_paths('main'))

    def test_real_git_rename_and_deleted_test_history(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, text in SOURCES.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            def git(*args):
                return subprocess.run(['git', *args], cwd=root, check=True, capture_output=True, text=True)
            git('init', '-q')
            git('add', '.')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture')
            (root / 'tests/test_a.mojo').rename(root / 'tests/test_renamed.mojo')
            with patch.object(ci_scope, 'ROOT', root):
                changed = ci_scope.changed_paths('HEAD')
                self.assertTrue(changed['tests/test_a.mojo'])
                self.assertFalse(changed['tests/test_renamed.mojo'])
                value = ci_scope.plan(changed, base='HEAD')
                self.assertIn('core/used.mojo', value['files']['covered'])
                self.assertIn('tests/test_renamed.mojo', value['files']['cpu_tests'])


class PlanExecutionTests(unittest.TestCase):
    def test_aggregate_requires_success_only_for_applicable_jobs(self):
        for value in [selected({'tools/test_build_tools.py': False}), selected(None), selected({})]:
            needs = {'scope': {'result': 'success'}}
            needs.update({name: {'result': 'success' if value['flags'][flag] else 'skipped'}
                          for name, flag in ci_scope.JOBS.items()})
            ci_scope.aggregate(value, needs)
            for name in needs:
                for status in ('failure', 'cancelled', 'skipped', 'success', None):
                    if status == needs[name]['result']:
                        continue
                    wrong = copy.deepcopy(needs)
                    wrong[name]['result'] = status
                    with self.assertRaises(ValueError, msg=(name, status)):
                        ci_scope.aggregate(value, wrong)
            for name in needs:
                missing = dict(needs)
                del missing[name]
                with self.assertRaises(ValueError):
                    ci_scope.aggregate(value, missing)

    def test_invalid_plan_cannot_become_noop_success(self):
        value = selected({'core/used.mojo': False})
        for bad in [None, {}, {'schema': 1}, dict(value, schema=2)]:
            with self.assertRaises(ValueError):
                ci_scope.validate(bad)
        wrong = copy.deepcopy(value)
        wrong['flags']['cpu'] = False
        with self.assertRaises(ValueError):
            ci_scope.validate(wrong)
        for path in ['../evil.mojo', '/tmp/evil.mojo', 'core/a b.mojo', 'core/$(shell evil).mojo']:
            wrong = copy.deepcopy(value)
            wrong['files']['cpu_tests'] = [path]
            with self.assertRaises(ValueError):
                ci_scope.validate(wrong)

    def test_real_make_reads_scoped_lists_before_hash_and_inherits_recursively(self):
        value = selected({'core/used.mojo': False})
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'Makefile').write_text(
                'CPU_TESTS := original\nCOVERED := original\n'
                'COVERAGE_TESTS := $(CPU_TESTS)\nHASH := $(CPU_TESTS):$(COVERED)\n'
                'test-cpu: probe\nprobe:\n\t@echo "$(HASH)|$(COVERAGE_TESTS)|$(AFFECTED)"\n\t@$(MAKE) --no-print-directory child\n'
                'child:\n\t@echo "$(CPU_TESTS)|$(COVERAGE_TESTS)"\n')
            selection = root / 'selection.mk'
            selection.write_text(ci_scope.selection_makefile(value, ['coverage-report']))
            command = ci_scope.make_command(value, ['--no-print-directory', 'test-cpu'], selection)
            result = subprocess.run(command, cwd=root, check=True, capture_output=True, text=True)
            for name in value['files']['coverage_tests']:
                self.assertIn(name, result.stdout)
            self.assertNotIn('original', result.stdout)

    def test_actual_full_plan_and_broad_scoped_plan_execute_without_argument_limits(self):
        # Use the real repository inventory, which exceeds Linux's per-string
        # exec limit if serialized in CI_SELECTION or exported MAKEFLAGS.
        full = ci_scope.plan(None)
        self.assertGreater(len(json.dumps(full)), 131072)
        broad = copy.deepcopy(full)
        broad['full'] = False
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'Makefile').write_text('test-cpu: probe\nprobe:\n\t@true\n\t@$(MAKE) --no-print-directory child\nchild:\n\t@true\n')
            for value in [full, broad]:
                selection = root / 'selection.mk'
                selection.write_text(ci_scope.selection_makefile(value, ['test-cpu']))
                result = subprocess.run(ci_scope.make_command(value, ['test-cpu'], selection),
                                        cwd=root, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_tool_regressions_do_not_inherit_native_list_overrides(self):
        value = selected({'tools/test_build_tools.py': False})
        for target in ('test-tools', 'test-coverage-tool', 'test-portability', 'docs-check',
                       'compile-gpu', 'test-gpu-host', 'check-gpu-air'):
            command = ci_scope.make_command(value, [target], '/tmp/selection.mk')
            self.assertIn('MAKEFILES=', command)
            self.assertNotIn('MAKEFILES=/tmp/selection.mk', command)

    def test_full_and_broad_plan_run_through_real_python_cli_with_file_artifact(self):
        full = ci_scope.plan(None)
        broad = copy.deepcopy(full)
        broad['full'] = False
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'tools').mkdir()
            (root / '.cache').mkdir()
            for name in ('ci_scope.py', 'affected.py'):
                (root / 'tools' / name).write_bytes((ci_scope.ROOT / 'tools' / name).read_bytes())
            (root / 'Makefile').write_text('test-cpu:\n\t@true\n')
            for value in [full, broad]:
                raw = json.dumps(value).encode()
                (root / '.cache/ci-selection.json').write_bytes(raw)
                environment = dict(os.environ, CI_SELECTION_SHA256=hashlib.sha256(raw).hexdigest())
                result = subprocess.run([sys.executable, 'tools/ci_scope.py', 'run', '--', 'test-cpu'],
                                        cwd=root, env=environment, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_inventory_stays_identical_to_maintained_makefile(self):
        variables = {'formatted': 'FORMATTED', 'cpu_entries': 'CPU_ENTRY_POINTS',
                     'cpu_docs': 'CPU_DOC_SOURCES', 'cpu_tests': 'CPU_TESTS',
                     'compile_fail': 'COMPILE_FAIL_RUN', 'covered': 'COVERED',
                     'coverage_tests': 'COVERAGE_TESTS'}
        with tempfile.TemporaryDirectory() as temporary:
            wrapper = Path(temporary) / 'inventory.mk'
            wrapper.write_text('include Makefile\ninventory:\n' + ''.join(
                "\t@printf '%s\\n' '" + key + '=$(' + var + ")'\n"
                for key, var in variables.items()))
            environment = {key: value for key, value in os.environ.items() if key not in
                           {'MAKEFLAGS', 'MFLAGS', 'MAKEOVERRIDES', 'MAKELEVEL', 'MAKEFILES',
                            'GNUMAKEFLAGS', 'AFFECTED'}}
            result = subprocess.run(['make', '-s', '-f', str(wrapper), 'inventory',
                                     'TOOLCHAIN=none', 'NATIVE_TOOLCHAIN=none', 'HASH=test'],
                                    cwd=ci_scope.ROOT, env=environment, check=True,
                                    capture_output=True, text=True)
            actual = {key: set(paths.split()) for key, paths in
                      (line.split('=', 1) for line in result.stdout.splitlines())}
            self.assertEqual(actual, ci_scope.inventories(ci_scope.source_tree()))

    def test_artifact_hash_mismatch_and_missing_plan_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(ci_scope, 'ROOT', Path(temporary)):
            root = Path(temporary)
            (root / '.cache').mkdir()
            with self.assertRaises(OSError):
                ci_scope.main(['aggregate'])
            (root / '.cache/ci-selection.json').write_text('{}')
            with patch.dict(os.environ, {'CI_SELECTION_SHA256': '0' * 64}):
                with self.assertRaisesRegex(ValueError, 'does not match'):
                    ci_scope.main(['aggregate'])


if __name__ == '__main__':
    unittest.main()
