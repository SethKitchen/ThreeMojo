# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Static checks for CI event policy and hardware-free GPU compilation.

The checks read the workflow text and recognize its small, explicit job
guard. They do not run workflow expressions. `tools/ci_scope.mojo` runs this
suite when the workflow changes, because the suite quotes its path.
"""

from std.collections import Set
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime WORKFLOW = ".github/workflows/ci.yml"
"""The workflow that the checks read."""

comptime GUARD = (
    "github.event_name != 'pull_request' || "
    "(github.event.pull_request.draft == false && "
    "github.event.pull_request.base.ref == 'main')"
)
"""The reviewed guard of the planning job."""

comptime WIKI_GUARD = (
    "always() && github.event_name == 'push' && github.ref =="
    " 'refs/heads/main' && needs.required.result == 'success'"
)
"""The guard of the wiki job."""

comptime CHECK_JOBS = [
    "lint",
    "tools",
    "tools-discovery",
    "lint-macos",
    "tools-macos",
    "tools-discovery-macos",
    "cpu",
    "cpu-macos",
    "coverage-capture",
    "coverage",
    "gpu-host",
]
"""The jobs that run checks."""

comptime RUN = "sh tools/tool.sh .venv/bin/mojo ci_scope run -- "
"""The start of each planned Make command."""


# --- text helpers that stand in for the few regular expressions -------------


def _lines(text: String) -> List[String]:
    """Return the lines of a text, without their line ends."""
    var out = List[String]()
    for line in text.split("\n"):
        out.append(String(line))
    return out^


def _has_line(text: String, line: String) -> Bool:
    """Return whether one whole line of a text is `line`."""
    for item in _lines(text):
        if item == line:
            return True
    return False


def _has_lines(text: String, block: String) -> Bool:
    """Return whether `block` starts at a line start and ends at a line end."""
    var start = 0
    while True:
        var at = text.find(block, start)
        if at < 0:
            return False
        var end = at + block.byte_length()
        var before = at == 0 or text.as_bytes()[at - 1] == 10
        var after = end == text.byte_length() or text.as_bytes()[end] == 10
        if before and after:
            return True
        start = at + 1


def _dotted_at(text: String, start: Int, pattern: String) -> Bool:
    """Return whether a pattern matches a text at a byte offset, where `.`
    stands for any one character but a line end, as in a regular
    expression."""
    var left = text.as_bytes()
    var right = pattern.as_bytes()
    if start < 0 or start + len(right) > len(left):
        return False
    for index in range(len(right)):
        var byte = left[start + index]
        if right[index] == 46:
            if byte == 10:
                return False
        elif byte != right[index]:
            return False
    return True


def _dotted(text: String, pattern: String) -> Bool:
    """Return whether a whole text matches a dotted pattern."""
    return text.byte_length() == pattern.byte_length() and _dotted_at(
        text, 0, pattern
    )


def _dotted_search(text: String, pattern: String) -> Bool:
    """Return whether a dotted pattern matches anywhere in a text."""
    for start in range(text.byte_length() - pattern.byte_length() + 1):
        if _dotted_at(text, start, pattern):
            return True
    return False


def _commands(job: String, prefix: String) -> List[String]:
    """Return each `run:` line's command that starts with `prefix`.

    The prefix is a regular-expression prefix: each `.` in it stands for any
    character. The command must be longer than the prefix.
    """
    var out = List[String]()
    var head = "        run: "
    for line in _lines(job):
        if not line.startswith(head):
            continue
        var command = String(line[byte = head.byte_length() :])
        if command.byte_length() <= prefix.byte_length():
            continue
        if _dotted_at(command, 0, prefix):
            out.append(command)
    return out^


def _shard_list(job: String) -> Optional[String]:
    """Return the text between the brackets of `        shard: [...]`."""
    var head = "        shard: ["
    for line in _lines(job):
        if line.startswith(head) and line.endswith("]"):
            var inner = String(
                line[byte = head.byte_length() : line.byte_length() - 1]
            )
            if inner.byte_length() == 0:
                continue
            var good = True
            for byte in inner.as_bytes():
                if not (
                    (byte >= 48 and byte <= 57) or byte == 44 or byte == 32
                ):
                    good = False
            if good:
                return inner
    return None


def _is_word(byte: UInt8) -> Bool:
    """Return whether a byte is a regular-expression word character."""
    return (
        (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
    )


def _is_space(byte: UInt8) -> Bool:
    """Return whether a byte is regular-expression white space."""
    return byte == 32 or (byte >= 9 and byte <= 13)


def _sets_jobs(text: String) -> Bool:
    """Return whether a text has `\\bJOBS\\s*=`."""
    var bytes = text.as_bytes()
    var start = 0
    while True:
        var at = text.find("JOBS", start)
        if at < 0:
            return False
        start = at + 1
        if at > 0 and _is_word(bytes[at - 1]):
            continue
        var index = at + 4
        while index < len(bytes) and _is_space(bytes[index]):
            index += 1
        if index < len(bytes) and bytes[index] == 61:
            return True


def _has_step_guard(text: String) -> Bool:
    """Return whether a text has `(?m)^      -?\\s*if:`."""
    var bytes = text.as_bytes()
    var line = 0
    while line < len(bytes):
        if text[byte=line:].startswith("      "):
            var index = line + 6
            if index < len(bytes) and bytes[index] == 45:
                index += 1
            while index < len(bytes) and _is_space(bytes[index]):
                index += 1
            if text[byte=index:].startswith("if:"):
                return True
        var end = text.find("\n", line)
        if end < 0:
            return False
        line = end + 1
    return False


def _header(line: String) -> Optional[String]:
    """Return the name of a job header line `  NAME:`, with optional white
    space after the colon."""
    if not line.startswith("  "):
        return None
    var bytes = line.as_bytes()
    var index = 2
    while index < len(bytes) and (_is_word(bytes[index]) or bytes[index] == 45):
        index += 1
    if index == 2 or index >= len(bytes) or bytes[index] != 58:
        return None
    for rest in range(index + 1, len(bytes)):
        if not _is_space(bytes[rest]):
            return None
    return String(line[byte=2:index])


def jobs_of(text: String) raises -> Dict[String, String]:
    """Return each top-level job's text, without parsing nested step keys.

    Args:
        text: The workflow.

    Returns:
        Each job name and its text, from the end of its header line to the
        start of the next header.

    Raises:
        Error: If the workflow has no `jobs:` line.
    """
    var lines = _lines(text)
    var offset = 0
    var body = -1
    var starts = List[Int]()
    for line in lines:
        starts.append(offset)
        offset += line.byte_length() + 1
    for index in range(len(lines)):
        var line = lines[index]
        if line.startswith("jobs:"):
            var blank = True
            for byte in line.as_bytes()[5:]:
                if not _is_space(byte):
                    blank = False
            if blank:
                body = index
                break
    if body < 0:
        raise Error("no jobs")
    var names = List[String]()
    var first = List[Int]()
    var after = List[Int]()
    for index in range(body + 1, len(lines)):
        var name = _header(lines[index])
        if name:
            names.append(name.value())
            first.append(starts[index])
            after.append(starts[index] + lines[index].byte_length())
    var jobs = Dict[String, String]()
    for index in range(len(names)):
        var end = (
            first[index + 1] if index + 1 < len(names) else text.byte_length()
        )
        jobs[names[index]] = String(text[byte = after[index] : end])
    return jobs^


def guard_of(job: String) -> Optional[String]:
    """Return the job-level condition, ignoring conditions on its steps.

    Args:
        job: One job's text.

    Returns:
        The stripped condition, or nothing.
    """
    for line in _lines(job):
        if line.startswith("    if: ") and line.byte_length() > 8:
            return String(String(line[byte=8:]).strip())
    return None


def allows(
    guard: String, event: String, draft: Optional[Bool], base: String = "main"
) raises -> Bool:
    """Evaluate only the reviewed guard, not arbitrary workflow code.

    Args:
        guard: The job's guard.
        event: The event name.
        draft: Whether the pull request is a draft, or nothing.
        base: The base branch.

    Returns:
        Whether the guard admits the event.

    Raises:
        Error: If the guard is not the reviewed one.
    """
    if guard != GUARD:
        raise Error("Every check job must use the explicit draft guard")
    var ready = draft.__bool__() and not draft.value()
    return event != "pull_request" or (ready and base == "main")


def _event(text: String, name: String) -> Optional[String]:
    """Return the lines after `  NAME:` that start with four spaces."""
    var lines = _lines(text)
    for index in range(len(lines)):
        if lines[index] == "  " + name + ":":
            var block = String()
            var next = index + 1
            # Each captured line must end with a line end.
            while next + 1 < len(lines) and lines[next].startswith("    "):
                block += lines[next] + "\n"
                next += 1
            if block.byte_length() == 0:
                return None
            return block
    return None


def _workflow() raises -> String:
    return Path(".github/workflows/ci.yml").read_text()


def _jobs() raises -> Dict[String, String]:
    return jobs_of(_workflow())


# --- the checks ---------------------------------------------------------------


def test_text_helpers_follow_the_regular_expressions() raises:
    assert_true(_dotted("sh tools/tool.sh", "sh tools.tool.sh"))
    assert_false(_dotted("sh tools\ntool.sh", "sh tools.tool.sh"))
    assert_false(_dotted("sh", "sh."))
    assert_true(_dotted_search("a\nrun: x", "run. x"))
    assert_false(_dotted_search("run", "run: x"))
    assert_true(_sets_jobs("make JOBS =1"))
    assert_true(_sets_jobs("JOBS\n="))
    assert_false(_sets_jobs("MAKEJOBS=1"))
    assert_false(_sets_jobs("JOBS: 1"))
    assert_true(_has_step_guard("x\n      - if: y\n"))
    assert_true(_has_step_guard("      if: y"))
    assert_false(_has_step_guard("    if: y\n"))
    assert_false(_has_step_guard("      - run: x"))
    assert_true(_has_lines("a\nb\nc", "b\nc"))
    assert_false(_has_lines("a\nbc", "b"))
    assert_equal(_header("  lint:  ").value(), "lint")
    assert_false(_header("  lint: x"))
    assert_false(_header("   lint:"))
    assert_false(_header("  :"))
    var jobs = jobs_of("on:\n  a:\njobs:\n  one:\n    x\n  two: \n    y\n")
    assert_equal(len(jobs), 2)
    assert_equal(jobs["one"], "\n    x\n")
    assert_equal(jobs["two"], "\n    y\n")
    with assert_raises(contains="no jobs"):
        _ = jobs_of("on:\n  a:\n")
    assert_equal(_shard_list("        shard: [1, 2]\n").value(), "1, 2")
    assert_false(_shard_list("        shard: [a]\n"))
    assert_false(_shard_list("        shard: []\n"))
    assert_false(guard_of("      if: x\n"))
    assert_false(_event("  pull_request:\n  push:\n", "pull_request"))
    assert_false(_event("x\n", "pull_request"))


def test_lint_tools_and_native_gates_have_explicit_conditions() raises:
    var jobs = _jobs()
    for name in ["lint", "lint-macos"]:
        var job = jobs[name]
        assert_true(_has_line(job, "    timeout-minutes: 240"), name)
        assert_equal(job.find("test-tools"), -1)
        for pair in [
            ("coverage_tools", "test-coverage-tool"),
            ("portability", "test-portability"),
            ("docs", "docs-check"),
        ]:
            var pattern = (
                "if: needs.scope.outputs.run_"
                + pair[0]
                + " == 'true'\n        run: "
                + RUN
                + pair[1]
            )
            assert_true(_dotted_search(job, pattern), pattern)
        assert_true(
            job.find("if: needs.scope.outputs.run_native == 'true'") >= 0
        )
        assert_equal(job.find("Install Xvfb"), -1)
    assert_true(jobs["lint"].find("run -- fmt-check") >= 0)
    assert_true(jobs["lint"].find("run -- compile-fail") >= 0)
    assert_true(
        jobs["lint"].find(
            'run -- lint-cpu LINT_CPU_BUILD_FLAGS="--target-triple='
            'x86_64-unknown-linux-gnu --target-cpu=x86-64-v3"'
            " LINT_CPU_PROGRESS=1"
        )
        >= 0
    )


def test_tool_regressions_run_in_every_group_on_both_platforms() raises:
    var jobs = _jobs()
    for name in ["tools", "tools-macos"]:
        var job = jobs[name]
        assert_true(_has_line(job, "    timeout-minutes: 240"), name)
        var groups = _shard_list(job)
        assert_true(groups.__bool__())
        var count = len(groups.value().split(","))
        assert_equal(count, 6)
        var expected = String()
        for index in range(1, count + 1):
            if index > 1:
                expected += ", "
            expected += String(index)
        assert_equal(groups.value(), expected)
        var commands = _commands(job, RUN)
        assert_equal(len(commands), 1)
        assert_equal(
            commands[0],
            RUN
            + "test-tools-oracle TOOLS_SHARD=${{ matrix.shard }}/"
            + String(count),
        )
        assert_true(job.find("fail-fast: false") >= 0)
    assert_true(_has_line(jobs["tools"], "    runs-on: ubuntu-latest"))
    assert_true(_has_line(jobs["tools-macos"], "    runs-on: macos-latest"))


def test_general_and_asset_discovery_have_dedicated_required_jobs() raises:
    var jobs = _jobs()
    for pair in [
        ("tools-discovery", "ubuntu-latest"),
        ("tools-discovery-macos", "macos-latest"),
    ]:
        var job = jobs[pair[0]]
        assert_true(_has_line(job, "    timeout-minutes: 240"), pair[0])
        assert_true(_has_line(job, "    runs-on: " + pair[1]), pair[0])
        assert_false(_shard_list(job).__bool__())
        assert_equal(job.find("strategy:"), -1)
        assert_false(_has_step_guard(job))
        var commands = _commands(job, RUN)
        assert_equal(len(commands), 1)
        assert_equal(commands[0], RUN + "test-tools-discovery")
        assert_true(job.find("uv python install --no-bin 3.12.14") >= 0)
        assert_true(
            job.find('"$PYTHON" -m venv --without-pip --prompt ThreeMojo .venv')
            >= 0
        )
        assert_true(
            job.find('uv pip install --python .venv/bin/python "mojo==1.1.0"')
            >= 0
        )
        assert_equal(job.find("TOOLS_SHARD="), -1)


def test_macos_lint_preserves_name_and_serializes_compilers() raises:
    var jobs = _jobs()
    var job = jobs["lint-macos"]
    assert_true(job.find("name: check-cpu (macOS, Apple Silicon) lint") >= 0)
    assert_true(job.find("run -- lint-cpu JOBS=1") >= 0)
    assert_true(job.find("run -- test-coverage-tool JOBS=1") >= 0)
    assert_true(job.find("run -- test-portability JOBS=1") >= 0)
    assert_equal(jobs["cpu-macos"].find("part: lint"), -1)


def test_only_macos_cpu_checks_serialize_outer_compilers() raises:
    var jobs = _jobs()
    var job = jobs["cpu-macos"]
    assert_true(_has_line(job, "    runs-on: macos-latest"))
    assert_true(_has_line(job, "    timeout-minutes: 150"))
    var commands = _commands(job, RUN)
    assert_equal(len(commands), 1)
    assert_equal(commands[0], RUN + "${{ matrix.target }} JOBS=1")
    # The GPU compile job has its own existing JOBS=1 contract.
    for name in ["lint", "cpu", "coverage-capture", "coverage"]:
        assert_false(_sets_jobs(jobs[name]), name)


def test_linux_cpu_compilers_use_one_thread_without_changing_the_suites() raises:
    var job = _jobs()["cpu"]
    assert_true(_has_line(job, "    timeout-minutes: 120"))
    assert_true(job.find("shard: [1, 2, 3]") >= 0)
    var commands = _commands(job, RUN)
    assert_equal(len(commands), 1)
    assert_equal(
        commands[0],
        RUN
        + "test-cpu SHARD=${{ matrix.shard }}/3 "
        + 'MOJOFLAGS="-I . --num-threads 1 --target-triple=x86_64-unknown-'
        + 'linux-gnu --target-cpu=x86-64-v3"',
    )
    assert_false(_sets_jobs(job))


def test_portable_cpu_target_does_not_leak_into_other_platforms_or_gates() raises:
    var text = _workflow()
    var jobs = jobs_of(text)
    for entry in jobs.items():
        if entry.key != "cpu" and entry.key != "lint":
            assert_equal(entry.value.find("--target-cpu=x86-64-v3"), -1)
            assert_equal(
                entry.value.find("--target-triple=x86_64-unknown-linux-gnu"),
                -1,
            )
    assert_equal(jobs["lint"].find("MOJOFLAGS="), -1)
    assert_equal(jobs["lint"].count("LINT_CPU_BUILD_FLAGS="), 1)
    assert_equal(jobs["cpu"].count("MOJOFLAGS="), 1)
    assert_equal(text.find("MOJOFLAGS:"), -1)
    assert_equal(jobs["lint"].find("continue-on-error:"), -1)


def test_compiler_telemetry_is_opted_in_only_for_the_linux_cpu_step() raises:
    var jobs = _jobs()
    assert_true(jobs["cpu"].find('THREEMOJO_COMPILER_TELEMETRY: "1"') >= 0)
    assert_true(
        _has_lines(
            jobs["cpu"],
            "      - name: test-cpu\n        env:\n"
            + '          THREEMOJO_COMPILER_TELEMETRY: "1"',
        )
    )
    for entry in jobs.items():
        if entry.key != "cpu":
            assert_equal(entry.value.find("THREEMOJO_COMPILER_TELEMETRY"), -1)


def test_compiler_metadata_is_a_separate_linux_cpu_diagnostic() raises:
    var jobs = _jobs()
    var job = jobs["cpu"]
    var command = (
        "run: sh tools/tool.sh .venv/bin/mojo compiler_metadata "
        + "> compiler-metadata.json"
    )
    assert_equal(job.count(command), 1)
    assert_true(job.find(command) < job.find("- name: test-cpu"))
    assert_equal(job.find("continue-on-error:"), -1)
    for entry in jobs.items():
        if entry.key != "cpu":
            assert_equal(entry.value.find("compiler_metadata"), -1)
    # The existing exact-command test also pins original flags/shards.
    assert_true(
        job.find(
            "run: "
            + RUN
            + "test-cpu SHARD=${{ matrix.shard }}/3 "
            + 'MOJOFLAGS="-I . --num-threads 1 --target-triple=x86_64-unknown-'
            + 'linux-gnu --target-cpu=x86-64-v3"'
        )
        >= 0
    )


def test_compiler_metadata_artifact_is_bounded_scoped_and_uploaded_early() raises:
    var jobs = _jobs()
    var job = jobs["cpu"]
    var block = (
        "      - name: Preserve compiler metadata before CPU compilation\n"
        + "        uses: actions/upload-artifact@v4\n"
        + "        with:\n"
        + "          name: compiler-metadata-${{ matrix.shard }}-attempt-${{"
        " github.run_attempt }}\n"
        + "          path: compiler-metadata.json\n"
        + "          if-no-files-found: error\n"
        + "          retention-days: 1\n"
    )
    assert_equal(job.count(block), 1)
    assert_true(job.find("> compiler-metadata.json") < job.find(block))
    assert_true(job.find(block) < job.find("- name: test-cpu"))
    assert_equal(job.count("uses: actions/upload-artifact@v4"), 1)
    for entry in jobs.items():
        if entry.key != "cpu":
            assert_equal(entry.value.find("compiler-metadata.json"), -1)


def test_only_planner_admits_ready_direct_main_pr_push_and_manual_events() raises:
    var jobs = _jobs()
    var found = guard_of(jobs["scope"])
    assert_true(found.__bool__())
    var guard = found.value()
    assert_equal(guard, GUARD)
    assert_false(allows(guard, "pull_request", True))
    assert_false(allows(guard, "pull_request", False, "feature/parent"))
    assert_true(allows(guard, "pull_request", False))
    assert_true(allows(guard, "push", None))
    assert_true(allows(guard, "workflow_dispatch", None))
    with assert_raises(contains="explicit draft guard"):
        _ = allows("true", "push", None)
    assert_equal(
        guard_of(jobs["required"]).value(), "always() && (" + GUARD + ")"
    )


# tests/test_ci_scope_tool.mojo checks each job's guard against the
# planner's JOBS table.
def test_every_work_job_requires_successful_planning() raises:
    var jobs = _jobs()
    var expected = Set[String]()
    for name in materialize[CHECK_JOBS]():
        expected.add(name)
    expected.add("scope")
    expected.add("required")
    expected.add("wiki")
    var names = Set[String]()
    for entry in jobs.items():
        names.add(entry.key)
    assert_true(names == expected)
    for name in materialize[CHECK_JOBS]():
        assert_true(
            _has_line(jobs[name], "    needs: scope")
            or _has_line(jobs[name], "    needs: [scope, coverage-capture]"),
            name,
        )


def test_scope_uses_immutable_baselines_and_manual_full_audit() raises:
    var text = _workflow()
    var job = jobs_of(text)["scope"]
    assert_true(
        job.find("PR_BASE: ${{ github.event.pull_request.base.sha }}") >= 0
    )
    assert_true(job.find("PUSH_BASE: ${{ github.event.before }}") >= 0)
    var plan = "sh tools/tool.sh .venv/bin/mojo ci_scope plan "
    assert_true(job.find(plan + '--base "$PR_BASE"') >= 0)
    assert_true(job.find(plan + '--base "$PUSH_BASE"') >= 0)
    assert_true(job.find(plan + "--full") >= 0)
    assert_equal(text.find("origin/main"), -1)


def test_full_inventory_uses_hash_bound_artifact_not_large_environment_value() raises:
    var text = _workflow()
    var jobs = jobs_of(text)
    assert_true(jobs["scope"].find("path: .cache/ci-selection.json") >= 0)
    assert_true(jobs["scope"].find("if-no-files-found: error") >= 0)
    assert_true(jobs["scope"].find("include-hidden-files: true") >= 0)
    var names = List[String]()
    for name in materialize[CHECK_JOBS]():
        names.append(name)
    names.append("required")
    for name in names:
        var job = jobs[name]
        assert_true(job.find("name: ci-selection") >= 0, name)
        assert_true(job.find("uses: actions/download-artifact@v4") >= 0, name)
        assert_true(
            job.find(
                "CI_SELECTION_SHA256: ${{ needs.scope.outputs.selection }}"
            )
            >= 0,
            name,
        )
    assert_equal(text.find("CI_SELECTION:"), -1)


def test_required_check_has_all_results_and_no_ignored_failures() raises:
    var text = _workflow()
    var job = jobs_of(text)["required"]
    assert_true(
        job.find(
            "needs: [scope, lint, tools, tools-discovery, cpu, lint-macos,"
            " tools-macos, tools-discovery-macos, cpu-macos,"
            " coverage-capture, coverage, gpu-host]"
        )
        >= 0
    )
    assert_true(job.find("CI_NEEDS: ${{ toJSON(needs) }}") >= 0)
    assert_true(
        job.find("run: sh tools/tool.sh .venv/bin/mojo ci_scope aggregate") >= 0
    )
    assert_equal(text.find("continue-on-error:"), -1)


def test_newer_runs_cancel_only_same_pr_or_ref() raises:
    var text = _workflow()
    assert_true(
        text.find(
            "group: ${{ github.workflow }}-${{"
            " github.event.pull_request.number || github.ref }}"
        )
        >= 0
    )
    assert_true(text.find("cancel-in-progress: true") >= 0)


def test_ready_for_review_retains_the_default_pr_events() raises:
    var event = _event(_workflow(), "pull_request")
    assert_true(event.__bool__())
    var block = event.value()
    var start = block.find("types: [")
    assert_true(start >= 0)
    var end = block.find("]", start)
    assert_true(end > start + 8)
    var types = Set[String]()
    for value in String(block[byte = start + 8 : end]).split(","):
        types.add(String(String(value).strip()))
    var expected = Set[String]()
    for name in ["opened", "synchronize", "reopened", "ready_for_review"]:
        expected.add(name)
    assert_true(types == expected)


def test_pull_request_trigger_keeps_main_branch_filter() raises:
    var event = _event(_workflow(), "pull_request")
    assert_true(event.__bool__())
    assert_true(_has_line(event.value(), "    branches: [main]"))


def test_main_push_manual_and_read_permissions_are_preserved() raises:
    var text = _workflow()
    assert_true(_has_lines(text, "  push:\n    branches: [main]"))
    var manual = False
    for line in _lines(text):
        if line.startswith("  workflow_dispatch:") and (
            String(line[byte=20:]).strip().byte_length() == 0
        ):
            manual = True
    assert_true(manual)
    assert_true(_has_lines(text, "permissions:\n  contents: read"))


def test_gpu_job_compiles_before_running_only_host_suites() raises:
    var job = _jobs()["gpu-host"]
    var commands = _commands(job, RUN)
    assert_equal(len(commands), 3)
    assert_equal(
        commands[0],
        RUN + 'compile-gpu JOBS=1 MOJOFLAGS="-I . --target-accelerator=sm_80"',
    )
    assert_equal(commands[1], RUN + "test-gpu-host")
    # Metal kernel AIR, checked without a GPU (modular/modular#7238).
    assert_equal(commands[2], RUN + "check-gpu-air")
    assert_equal(job.find("continue-on-error:"), -1)
    assert_false(_has_step_guard(job))


def test_gpu_job_keeps_pinned_toolchain_and_timeout() raises:
    var job = _jobs()["gpu-host"]
    assert_true(job.find('uv pip install "mojo==1.1.0" "max==26.6.0"') >= 0)
    assert_true(_has_line(job, "    name: test-gpu-host (MAX, no GPU)"))
    assert_true(_has_line(job, "    runs-on: ubuntu-latest"))
    assert_true(_has_line(job, "    timeout-minutes: 30"))


def test_wiki_remains_main_push_only() raises:
    var jobs = _jobs()
    assert_equal(guard_of(jobs["wiki"]).value(), WIKI_GUARD)
    assert_true(jobs["wiki"].find("needs: required") >= 0)


def test_coverage_keeps_all_shards_and_its_report_dependency() raises:
    var jobs = _jobs()
    assert_true(jobs["coverage"].find("needs: [scope, coverage-capture]") >= 0)
    assert_true(
        jobs["coverage-capture"].find("shard: [1, 2, 3, 4, 5, 6, 7, 8]") >= 0
    )
    # The group count in the command matches the matrix.
    assert_true(
        jobs["coverage-capture"].find("SHARD=${{ matrix.shard }}/8 ") >= 0
    )
    assert_true(
        jobs["coverage"].find(
            "sh tools/tool.sh .venv/bin/mojo ci_scope run -- coverage-report"
        )
        >= 0
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
