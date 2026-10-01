# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Static checks for draft, ready, main and manual CI policy.

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
WIKI_GUARD = "github.event_name == 'push' && github.ref == 'refs/heads/main'"
CHECK_JOBS = {'lint', 'cpu', 'cpu-macos', 'coverage-capture', 'coverage', 'gpu-host'}


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

    def test_draft_pull_requests_skip_every_check_job(self):
        self.assertTrue(CHECK_JOBS <= self.jobs.keys())
        # A future check job must opt out of draft PRs too. Only the wiki
        # is separate, with its existing main-push-only condition.
        for name, job in self.jobs.items():
            if name != 'wiki':
                with self.subTest(job=name):
                    self.assertFalse(allows(guard_of(job), 'pull_request', True))

    def test_ready_main_and_manual_runs_keep_every_check_job(self):
        for name in CHECK_JOBS:
            for event, draft in [('pull_request', False), ('push', None), ('workflow_dispatch', None)]:
                with self.subTest(job=name, event=event):
                    self.assertTrue(allows(guard_of(self.jobs[name]), event, draft))

    def test_native_stack_layers_require_a_direct_main_target(self):
        # Native stacks match the workflow branch filter against their
        # ultimate base. The job guard must still reject an intermediate
        # PR's actual base, even when its stack targets main.
        for name in CHECK_JOBS:
            with self.subTest(job=name):
                self.assertFalse(allows(guard_of(self.jobs[name]),
                                        'pull_request', False, 'feature/parent'))
                self.assertTrue(allows(guard_of(self.jobs[name]),
                                       'pull_request', False, 'main'))

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

    def test_wiki_remains_main_push_only(self):
        self.assertEqual(guard_of(self.jobs['wiki']), WIKI_GUARD)
        self.assertIn('needs: [lint, cpu, cpu-macos, coverage, gpu-host]', self.jobs['wiki'])

    def test_coverage_keeps_all_shards_and_its_report_dependency(self):
        self.assertIn('needs: coverage-capture', self.jobs['coverage'])
        self.assertIn('shard: [1, 2, 3, 4, 5, 6]', self.jobs['coverage-capture'])
        self.assertIn('make -B coverage-report AFFECTED="$AFFECTED"', self.jobs['coverage'])


if __name__ == '__main__':
    unittest.main()
