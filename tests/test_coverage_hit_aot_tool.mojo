# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A compiled coverage profile builds the suite and keeps its source name."""

from std.pathlib import Path
from std.sys import CompilationTarget
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program, shell_quote


def _script() -> String:
    """Return a fake Mojo compiler."""
    var text = "#!/bin/sh\n"
    text += 'printf \'%s\\n\' "$@" > "$LOG"\n'
    text += 'if [ "$1" != build ]; then\n'
    text += '  exit "${PLAIN_STATUS:-4}"\n'
    text += "fi\n"
    text += "prev=\n"
    text += "out=\n"
    text += 'for arg in "$@"; do\n'
    text += '  if [ "$prev" = -o ]; then out=$arg; fi\n'
    text += "  prev=$arg\n"
    text += "done\n"
    text += "src=$(mktemp)\n"
    text += "cat > " + '"$src"' + " << END\n"
    text += "#include <stdio.h>\n"
    text += "#include <stdlib.h>\n"
    text += "int main(int argc, char **argv) {\n"
    text += '  FILE *file = fopen(getenv("MARK"), "w");\n'
    text += "  if (!file) return 1;\n"
    text += '  fprintf(file, "%s\\n", argv[0]);\n'
    text += (
        '  for (int i = 1; i < argc; i++) fprintf(file, "%s\\n", argv[i]);\n'
    )
    text += "  fclose(file);\n"
    text += "  return 0;\n"
    text += "}\n"
    text += "END\n"
    text += 'cc -x c -o "$out" "$src"\n'
    text += "status=" + "$?" + "\n"
    text += 'rm -f "$src"\n'
    text += 'exit "$status"\n'
    return text


def _setup() raises -> String:
    """Return a tree with one plain suite and a fake compiler."""
    var root = mkdtemp(prefix="coverage-profile-")
    var made = run_program(
        ["mkdir", "-p", root + "/tests", root + "/cache", root + "/include"],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    Path(root + "/tests/test_plain.mojo").write_text("def main():\n    pass\n")
    Path(root + "/mojo").write_text(_script())
    var mode = run_program(["chmod", "+x", root + "/mojo"], 10.0)
    if mode.status != 0:
        raise Error(mode.output)
    return root


def _cleanup(root: String) raises:
    """Remove `root`."""
    var removed = run_program(["rm", "-rf", root], 10.0)
    if removed.status != 0:
        raise Error(removed.output)


def _run(
    root: String,
    profile: String,
    words: String,
    log: String,
    mark: String,
) raises -> ProcessResult:
    """Run one profile and return its status and streams."""
    var suite = root + "/tests/test_plain.mojo"
    var script = (
        "env LOG="
        + shell_quote(log)
        + " MARK="
        + shell_quote(mark)
        + " sh tools/tool.sh "
        + shell_quote(tool_mojo())
        + " coverage_hit_aot --profile "
        + profile
        + " --root "
        + shell_quote(root)
        + " --suite "
        + shell_quote(suite)
        + " --cache "
        + shell_quote(root + "/cache")
        + " -- "
        + shell_quote(root + "/mojo")
        + " "
        + words
    )
    return run_program(["sh", "-c", script], 30.0, merge_errors=False)


def test_a_compiled_profile_keeps_the_source_name() raises:
    var root = _setup()
    try:
        var suite = root + "/tests/test_plain.mojo"
        var mark = root + "/mark"
        var ran = _run(
            root,
            "aot",
            "run -I "
            + shell_quote(root + "/include")
            + " "
            + shell_quote(suite)
            + " "
            + shell_quote("two words"),
            root + "/log",
            mark,
        )
        assert_equal(ran.status, 0)
        var text = Path(root + "/log").read_text()
        assert_equal(text.find("build\n"), 0)
        assert_true(text.find("\n--num-threads\n1\n") >= 0)
        assert_equal(Path(mark).read_text(), suite + "\ntwo words\n")
    finally:
        _cleanup(root)


def test_an_existing_thread_count_stays() raises:
    var root = _setup()
    try:
        var suite = root + "/tests/test_plain.mojo"
        var ran = _run(
            root,
            "aot",
            "run --num-threads 4 " + shell_quote(suite),
            root + "/log",
            root + "/mark",
        )
        assert_equal(ran.status, 0)
        var text = Path(root + "/log").read_text()
        assert_true(text.find("\n--num-threads\n4\n") >= 0)
        assert_equal(text.find("\n--num-threads\n1\n"), -1)
    finally:
        _cleanup(root)


def test_a_raw_plain_suite_keeps_the_run_command() raises:
    var root = _setup()
    try:
        var suite = root + "/tests/test_plain.mojo"
        var ran = _run(
            root,
            "raw",
            "run " + shell_quote(suite) + " kept",
            root + "/log",
            root + "/mark",
        )
        assert_equal(ran.status, 4)
        var text = Path(root + "/log").read_text()
        assert_equal(text.find("run\n"), 0)
        assert_true(text.find("\nkept\n") >= 0)
    finally:
        _cleanup(root)


def test_exact_hits_need_a_capture_pipe() raises:
    var root = _setup()
    try:
        var suite = root + "/tests/test_plain.mojo"
        var ran = _run(
            root,
            "aot-hits",
            "run " + shell_quote(suite),
            root + "/log",
            root + "/mark",
        )
        assert_equal(ran.status, 1)
        comptime if CompilationTarget.is_linux():
            assert_true(ran.errors.find("supervised capture pipe") >= 0)
        else:
            assert_true(ran.errors.find("supports Linux only") >= 0)
    finally:
        _cleanup(root)


def test_an_unknown_profile_fails() raises:
    var root = _setup()
    try:
        var ran = _run(
            root,
            "other",
            "run " + shell_quote(root + "/tests/test_plain.mojo"),
            root + "/log",
            root + "/mark",
        )
        assert_equal(ran.status, 1)
        assert_true(ran.errors.find("unknown profile other") >= 0)
    finally:
        _cleanup(root)


def test_usage_exits_2() raises:
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "coverage_hit_aot"],
        30.0,
        merge_errors=False,
    )
    assert_equal(ran.status, 2)
    assert_true(ran.errors.find("usage: coverage_hit_aot ") >= 0)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "coverage_hit_aot"],
        120.0,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
