# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Static checks for CI event policy and hardware-free GPU compilation.

The workflow needs no new Python dependency. These checks recognize its
small, explicit job guard rather than executing arbitrary expressions.
"""

from pathlib import Path
import re
import unittest


WORKFLOW = Path(__file__).resolve().parents[1] / '.github/workflows/ci.yml'
GUARD = ("github.event_name != 'pull_request' || "
         "(github.event.pull_request.draft == false && "
         "github.event.pull_request.base.ref == 'main')")
WIKI_GUARD = "always() && github.event_name == 'push' && github.ref == 'refs/heads/main' && needs.required.result == 'success'"
CHECK_JOBS = {'lint', 'lint-macos', 'cpu', 'cpu-macos', 'coverage-capture', 'coverage', 'gpu-host'}


def jobs_of(text):
    """Return each top-level job's text, without parsing nested step keys."""
    body = re.split(r'^jobs:\s*$', text, maxsplit=1, flags=re.MULTILINE)[1]
    headers = list(re.finditer(r'^  ([\w-]+):\s*$', body, re.MULTILINE))
    return {
        match.group(1): body[match.end():headers[i + 1].start() if i + 1 < len(headers) else len(body)]
        for i, match in enumerate(headers)
    }


def guard_of(job):
    """Return the job-level condition, ignoring conditions on its steps."""
    found = re.search(r'^    if: (.+)$', job, re.MULTILINE)
    return found.group(1).strip() if found else None


def allows(guard, event, draft, base="main"):
    """Evaluate only the reviewed guard, not arbitrary workflow code."""
    if guard != GUARD:
        raise ValueError('Every check job must use the explicit draft guard')
    return event != 'pull_request' or (draft is False and base == 'main')


class CiPolicyTests(unittest.TestCase):
    def setUp(self):
        self.text = WORKFLOW.read_text()
        self.jobs = jobs_of(self.text)

    def test_lint_tools_and_native_gates_have_explicit_conditions(self):
        for name in ('lint', 'lint-macos'):
            job = self.jobs[name]
            for flag, target in [('tools', 'test-tools'), ('coverage_tools', 'test-coverage-tool'),
                                 ('portability', 'test-portability'), ('docs', 'docs-check')]:
                self.assertRegex(job, "if: needs.scope.outputs.run_" + flag +
                                 " == 'true'\n        run: python3 tools/ci_scope.py run -- " + target)
            self.assertIn("if: needs.scope.outputs.run_native == 'true'", job)
            self.assertNotIn('Install Xvfb', job)
        self.assertIn('run -- fmt-check', self.jobs['lint'])
        self.assertIn('run -- compile-fail', self.jobs['lint'])
        self.assertIn('run -- lint-cpu LINT_CPU_BUILD_FLAGS="--target-triple=x86_64-unknown-linux-gnu '
                      '--target-cpu=x86-64-v3" LINT_CPU_PROGRESS=1', self.jobs['lint'])

    def test_macos_lint_preserves_name_and_serializes_compilers(self):
        job = self.jobs['lint-macos']
        self.assertIn('name: check-cpu (macOS, Apple Silicon) lint', job)
        self.assertIn('run -- lint-cpu JOBS=1', job)
        self.assertIn('run -- test-coverage-tool JOBS=1', job)
        self.assertIn('run -- test-portability JOBS=1', job)
        self.assertNotIn('part: lint', self.jobs['cpu-macos'])

    def test_only_macos_cpu_checks_serialize_outer_compilers(self):
        job = self.jobs['cpu-macos']
        self.assertRegex(job, r'(?m)^    runs-on: macos-latest$')
        self.assertRegex(job, r'(?m)^    timeout-minutes: 150$')
        commands = re.findall(r'^        run: (python3 tools/ci_scope.py run -- .+)$', job, re.MULTILINE)
        self.assertEqual(commands, [
            'python3 tools/ci_scope.py run -- ${{ matrix.target }} JOBS=1',
        ])
        # The GPU compile job has its own existing JOBS=1 contract.
        for name in ('lint', 'cpu', 'coverage-capture', 'coverage'):
            with self.subTest(job=name):
                self.assertNotRegex(self.jobs[name], r'\bJOBS\s*=')

    def test_linux_cpu_compilers_use_one_thread_without_changing_the_suites(self):
        job = self.jobs['cpu']
        self.assertRegex(job, r'(?m)^    timeout-minutes: 120$')
        self.assertIn('shard: [1, 2, 3]', job)
        commands = re.findall(r'^        run: (python3 tools/ci_scope.py run -- .+)$', job, re.MULTILINE)
        self.assertEqual(commands, [
            'python3 tools/ci_scope.py run -- test-cpu SHARD=${{ matrix.shard }}/3 '
            'MOJOFLAGS="-I . --num-threads 1 --target-triple=x86_64-unknown-linux-gnu '
            '--target-cpu=x86-64-v3"',
        ])
        self.assertNotRegex(job, r'\bJOBS\s*=')

    def test_portable_cpu_target_does_not_leak_into_other_platforms_or_gates(self):
        for name, job in self.jobs.items():
            if name not in ('cpu', 'lint'):
                self.assertNotIn('--target-cpu=x86-64-v3', job)
                self.assertNotIn('--target-triple=x86_64-unknown-linux-gnu', job)
        self.assertNotIn('MOJOFLAGS=', self.jobs['lint'])
        self.assertEqual(self.jobs['lint'].count('LINT_CPU_BUILD_FLAGS='), 1)
        self.assertEqual(self.jobs['cpu'].count('MOJOFLAGS='), 1)
        self.assertNotIn('MOJOFLAGS:', self.text)
        self.assertNotIn('continue-on-error:', self.jobs['lint'])
        self.assertIn('timeout-minutes: 120', self.jobs['lint'])

    def test_compiler_telemetry_is_opted_in_only_for_the_linux_cpu_step(self):
        self.assertIn('THREEMOJO_COMPILER_TELEMETRY: "1"', self.jobs['cpu'])
        self.assertRegex(self.jobs['cpu'],
                         r'(?m)^      - name: test-cpu\n        env:\n'
                         r'          THREEMOJO_COMPILER_TELEMETRY: "1"$')
        for name, job in self.jobs.items():
            if name != 'cpu':
                self.assertNotIn('THREEMOJO_COMPILER_TELEMETRY', job)

    def test_compiler_metadata_is_a_separate_linux_cpu_diagnostic(self):
        job = self.jobs['cpu']
        command = ('run: .venv/bin/python tools/compiler_metadata.py '
                   '> compiler-metadata.json')
        self.assertEqual(job.count(command), 1)
        self.assertLess(job.index(command), job.index('- name: test-cpu'))
        self.assertNotIn('continue-on-error:', job)
        for name, other in self.jobs.items():
            if name != 'cpu':
                self.assertNotIn('compiler_metadata.py', other)
        # The existing exact-command test also pins original flags/shards.
        self.assertIn('run: python3 tools/ci_scope.py run -- test-cpu SHARD=${{ matrix.shard }}/3 '
                      'MOJOFLAGS="-I . --num-threads 1 --target-triple=x86_64-unknown-linux-gnu '
                      '--target-cpu=x86-64-v3"', job)

    def test_compiler_metadata_artifact_is_bounded_scoped_and_uploaded_early(self):
        job = self.jobs['cpu']
        block = ('      - name: Preserve compiler metadata before CPU compilation\n'
                 '        uses: actions/upload-artifact@v4\n'
                 '        with:\n'
                 '          name: compiler-metadata-${{ matrix.shard }}-attempt-${{ github.run_attempt }}\n'
                 '          path: compiler-metadata.json\n'
                 '          if-no-files-found: error\n'
                 '          retention-days: 1\n')
        self.assertEqual(job.count(block), 1)
        self.assertLess(job.index('> compiler-metadata.json'), job.index(block))
        self.assertLess(job.index(block), job.index('- name: test-cpu'))
        self.assertEqual(job.count('uses: actions/upload-artifact@v4'), 1)
        for name, other in self.jobs.items():
            if name != 'cpu':
                self.assertNotIn('compiler-metadata.json', other)

    def test_only_planner_admits_ready_direct_main_pr_push_and_manual_events(self):
        guard = guard_of(self.jobs['scope'])
        self.assertEqual(guard, GUARD)
        self.assertFalse(allows(guard, 'pull_request', True))
        self.assertFalse(allows(guard, 'pull_request', False, 'feature/parent'))
        for event, draft in [('pull_request', False), ('push', None), ('workflow_dispatch', None)]:
            self.assertTrue(allows(guard, event, draft))
        self.assertEqual(guard_of(self.jobs['required']), 'always() && (' + GUARD + ')')

    def test_every_work_job_requires_successful_planning_and_an_applicability_flag(self):
        from ci_scope import JOBS
        self.assertEqual(set(JOBS), CHECK_JOBS)
        self.assertEqual(set(self.jobs), CHECK_JOBS | {'scope', 'required', 'wiki'})
        for name, flag in JOBS.items():
            self.assertEqual(guard_of(self.jobs[name]), "needs.scope.outputs.run_" + flag + " == 'true'")
            self.assertRegex(self.jobs[name], r'(?m)^    needs: (scope|\[scope, coverage-capture\])$')

    def test_scope_uses_immutable_baselines_and_manual_full_audit(self):
        job = self.jobs['scope']
        self.assertIn('PR_BASE: ${{ github.event.pull_request.base.sha }}', job)
        self.assertIn('PUSH_BASE: ${{ github.event.before }}', job)
        self.assertIn('python3 tools/ci_scope.py plan --base "$PR_BASE"', job)
        self.assertIn('python3 tools/ci_scope.py plan --base "$PUSH_BASE"', job)
        self.assertIn('python3 tools/ci_scope.py plan --full', job)
        self.assertNotIn('origin/main', self.text)

    def test_full_inventory_uses_hash_bound_artifact_not_large_environment_value(self):
        self.assertIn('path: .cache/ci-selection.json', self.jobs['scope'])
        self.assertIn('if-no-files-found: error', self.jobs['scope'])
        self.assertIn('include-hidden-files: true', self.jobs['scope'])
        for name in CHECK_JOBS | {'required'}:
            job = self.jobs[name]
            self.assertIn('name: ci-selection', job)
            self.assertIn('uses: actions/download-artifact@v4', job)
            self.assertIn('CI_SELECTION_SHA256: ${{ needs.scope.outputs.selection }}', job)
        self.assertNotIn('CI_SELECTION:', self.text)

    def test_required_check_has_all_results_and_no_ignored_failures(self):
        job = self.jobs['required']
        self.assertIn('needs: [scope, lint, cpu, lint-macos, cpu-macos, coverage-capture, coverage, gpu-host]', job)
        self.assertIn('CI_NEEDS: ${{ toJSON(needs) }}', job)
        self.assertIn('run: python3 tools/ci_scope.py aggregate', job)
        self.assertNotIn('continue-on-error:', self.text)

    def test_newer_runs_cancel_only_same_pr_or_ref(self):
        self.assertIn('group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}', self.text)
        self.assertIn('cancel-in-progress: true', self.text)

    def test_ready_for_review_retains_the_default_pr_events(self):
        event = re.search(r'^  pull_request:\n((?:    .*\n)+)', self.text, re.MULTILINE)
        self.assertIsNotNone(event)
        types = re.search(r'types: \[([^\]]+)\]', event.group(1))
        self.assertIsNotNone(types)
        self.assertEqual(
            {value.strip() for value in types.group(1).split(',')},
            {'opened', 'synchronize', 'reopened', 'ready_for_review'},
        )

    def test_pull_request_trigger_keeps_main_branch_filter(self):
        event = re.search(r'^  pull_request:\n((?:    .*\n)+)', self.text, re.MULTILINE)
        self.assertIsNotNone(event)
        self.assertRegex(event.group(1), r'(?m)^    branches: \[main\]$')

    def test_main_push_manual_and_read_permissions_are_preserved(self):
        self.assertRegex(self.text, r'(?m)^  push:\n    branches: \[main\]$')
        self.assertRegex(self.text, r'(?m)^  workflow_dispatch:\s*$')
        self.assertRegex(self.text, r'(?m)^permissions:\n  contents: read$')

    def test_gpu_job_compiles_before_running_only_host_suites(self):
        job = self.jobs['gpu-host']
        commands = re.findall(r'^        run: (python3 tools/ci_scope.py run -- .+)$', job, re.MULTILINE)
        self.assertEqual(commands, [
            'python3 tools/ci_scope.py run -- compile-gpu JOBS=1 MOJOFLAGS="-I . --target-accelerator=sm_80"',
            'python3 tools/ci_scope.py run -- test-gpu-host',
            # Metal kernel AIR, checked without a GPU (modular/modular#7238).
            'python3 tools/ci_scope.py run -- check-gpu-air',
        ])
        self.assertNotIn('continue-on-error:', job)
        self.assertNotRegex(job, r'(?m)^      -?\s*if:')

    def test_gpu_job_keeps_pinned_toolchain_and_timeout(self):
        job = self.jobs['gpu-host']
        self.assertIn('uv pip install "mojo==1.1.0" "max==26.6.0"', job)
        self.assertRegex(job, r'(?m)^    name: test-gpu-host \(MAX, no GPU\)$')
        self.assertRegex(job, r'(?m)^    runs-on: ubuntu-latest$')
        self.assertRegex(job, r'(?m)^    timeout-minutes: 30$')

    def test_wiki_remains_main_push_only(self):
        self.assertEqual(guard_of(self.jobs['wiki']), WIKI_GUARD)
        self.assertIn('needs: required', self.jobs['wiki'])

    def test_coverage_keeps_all_shards_and_its_report_dependency(self):
        self.assertIn('needs: [scope, coverage-capture]', self.jobs['coverage'])
        self.assertIn('shard: [1, 2, 3, 4, 5, 6, 7, 8]', self.jobs['coverage-capture'])
        # The group count in the command matches the matrix.
        self.assertIn('SHARD=${{ matrix.shard }}/8 ', self.jobs['coverage-capture'])
        self.assertIn('python3 tools/ci_scope.py run -- coverage-report', self.jobs['coverage'])


if __name__ == '__main__':
    unittest.main()
