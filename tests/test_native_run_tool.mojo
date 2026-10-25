# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Raw coverage runs a fixture suite in the capture process group."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program, shell_quote


def _script() -> String:
    """Return the fake Mojo compiler used by these tests."""
    var text = "#!/bin/sh\n"
    text += 'printf \'%s\\n\' "$@" > "$LOG"\n'
    text += 'if [ "$1" != build ]; then\n'
    text += '  exit "${PLAIN_STATUS:-4}"\n'
    text += "fi\n"
    text += 'if [ -n "${BUILD_STATUS:-}" ]; then\n'
    text += '  exit "$BUILD_STATUS"\n'
    text += "fi\n"
    text += "prev=\n"
    text += "out=\n"
    text += 'for arg in "$@"; do\n'
    text += '  if [ "$prev" = -o ]; then out=$arg; fi\n'
    text += "  prev=$arg\n"
    text += "done\n"
    text += 'if [ "${BINARY:-run}" = signal ]; then\n'
    text += "  printf '%s\\n' '#!/bin/sh' 'kill -TERM $$' > \"$out\"\n"
    text += "else\n"
    text += (
        "  printf '%s\\n' '#!/bin/sh' 'printf \"%s\\n\" \"$@\" > \"$MARK\"'"
        + " 'exit 0' > \"$out\"\n"
    )
    text += "fi\n"
    text += 'chmod +x "$out"\n'
    text += "exit 0\n"
    return text


def _setup() raises -> String:
    """Return a tree with one plain suite and one fixture suite."""
    var root = mkdtemp(prefix="native-support-")
    var made = run_program(
        [
            "mkdir",
            "-p",
            root + "/tests",
            root + "/tools/fixtures",
            root + "/cache",
            root + "/include",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    Path(root + "/tests/test_plain.mojo").write_text("def main():\n    pass\n")
    Path(root + "/tests/test_carla_sum2_environment.mojo").write_text(
        "def main():\n    pass\n"
    )
    Path(root + "/tools/fixtures/carla_sum2_fp_state.c").write_text(
        "int marker(void) { return 1; }\n"
    )
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
    suite: String,
    log: String,
    mark: String,
    words: String,
    build_status: String,
    binary: String,
) raises -> ProcessResult:
    """Run the built tool and return its status and streams."""
    var script = (
        "env LOG="
        + shell_quote(log)
        + " MARK="
        + shell_quote(mark)
        + " BUILD_STATUS="
        + shell_quote(build_status)
        + " BINARY="
        + shell_quote(binary)
        + " sh tools/tool.sh "
        + shell_quote(tool_mojo())
        + " native_test_support run --root "
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
    return run_program(["sh", "-c", script], 20.0, merge_errors=False)


def _next(text: String, name: String) raises -> String:
    """Return the log line after `name`."""
    var lines = text.split("\n")
    var index = 0
    while index < len(lines):
        if lines[index] == name and index + 1 < len(lines):
            return String(lines[index + 1])
        index += 1
    raise Error("missing " + name)


def test_a_plain_run_keeps_the_mojo_command() raises:
    var root = _setup()
    try:
        var suite = root + "/tests/test_plain.mojo"
        var log = root + "/log"
        var ran = _run(
            root,
            suite,
            log,
            root + "/mark",
            "run -I "
            + shell_quote(root + "/include")
            + " "
            + shell_quote(suite)
            + " kept",
            "",
            "",
        )
        assert_equal(ran.status, 4)
        var text = Path(log).read_text()
        assert_equal(text.find("run\n"), 0)
        assert_true(text.find("\nkept\n") >= 0)
        assert_equal(text.find("-Xlinker"), -1)
    finally:
        _cleanup(root)


def test_a_fixture_run_builds_then_runs_in_this_group() raises:
    var root = _setup()
    try:
        var suite = root + "/tests/test_carla_sum2_environment.mojo"
        var log = root + "/log"
        var mark = root + "/mark"
        var ran = _run(
            root,
            suite,
            log,
            mark,
            "run -I "
            + shell_quote(root + "/include")
            + " "
            + shell_quote(suite)
            + " "
            + shell_quote("two words"),
            "",
            "",
        )
        assert_equal(ran.status, 0)
        var text = Path(log).read_text()
        assert_equal(text.find("build\n"), 0)
        assert_true(text.find("\n-I\n" + root + "/include\n") >= 0)
        assert_true(text.find("\n-Xlinker\n") >= 0)
        var executable = _next(text, "-o")
        assert_false(Path(executable).exists())
        assert_equal(Path(mark).read_text(), "two words\n")
    finally:
        _cleanup(root)


def test_a_failed_fixture_build_does_not_run() raises:
    var root = _setup()
    try:
        var suite = root + "/tests/test_carla_sum2_environment.mojo"
        var log = root + "/log"
        var mark = root + "/mark"
        var ran = _run(
            root,
            suite,
            log,
            mark,
            "run " + shell_quote(suite),
            "7",
            "",
        )
        assert_equal(ran.status, 7)
        assert_false(Path(mark).exists())
        var executable = _next(Path(log).read_text(), "-o")
        assert_false(Path(executable).exists())
    finally:
        _cleanup(root)


def test_a_fixture_program_signal_is_128_plus_the_signal() raises:
    var root = _setup()
    try:
        var suite = root + "/tests/test_carla_sum2_environment.mojo"
        var log = root + "/log"
        var ran = _run(
            root,
            suite,
            log,
            root + "/mark",
            "run " + shell_quote(suite),
            "",
            "signal",
        )
        assert_equal(ran.status, 143)
        var executable = _next(Path(log).read_text(), "-o")
        assert_false(Path(executable).exists())
    finally:
        _cleanup(root)


def test_a_fixture_run_without_its_source_fails() raises:
    var root = _setup()
    try:
        var suite = root + "/tests/test_carla_sum2_environment.mojo"
        var ran = _run(
            root,
            suite,
            root + "/log",
            root + "/mark",
            "run " + shell_quote(root + "/other.mojo"),
            "",
            "",
        )
        assert_equal(ran.status, 1)
        assert_true(
            ran.errors.find("native fixture run is missing its Mojo source")
            >= 0
        )
    finally:
        _cleanup(root)


def test_a_fixture_build_still_links_the_object() raises:
    var root = _setup()
    try:
        var suite = root + "/tests/test_carla_sum2_environment.mojo"
        var log = root + "/log"
        var program = root + "/program"
        var ran = _run(
            root,
            suite,
            log,
            root + "/mark",
            "build -o " + shell_quote(program) + " " + shell_quote(suite),
            "",
            "",
        )
        assert_equal(ran.status, 0)
        var text = Path(log).read_text()
        assert_equal(text.find("build\n"), 0)
        assert_true(text.find("\n-Xlinker\n") >= 0)
        assert_true(Path(program).is_file())
    finally:
        _cleanup(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "native_test_support"],
        120.0,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
