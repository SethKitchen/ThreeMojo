# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `tools.compile_fail`: false passes are refused, diagnostics kept.

The runner tests use a fake compiler: a shell script that prints the file
`NAME.out`, runs `NAME.hook` and exits with the status in `NAME.rc`, where
NAME is the base name of the file it builds. Each call is logged.
"""

from std.os import listdir, remove, rmdir
from std.os.path import realpath
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tools.compile_fail import (
    CRASHPAD_STARTUP_WARNING,
    Diagnostics,
    Options,
    SourceError,
    check,
    clean_output,
    expected_diagnostics,
    parse_options,
    repository_errors,
    rejection_error,
    shell_split,
    strip_color,
)
from tools._process import run_program
from tools._text import split_lines

comptime FIXTURE = "tests/compile_fail/fixture.mojo"
comptime MESSAGE = "cannot implicitly convert 'Int' value to 'BodyId'"


def _diagnostic(message: String = MESSAGE) -> String:
    """Return one located error in the fixture."""
    return FIXTURE + ":13:17: error: " + message + "\n"


def _expected(message: String = MESSAGE) -> Optional[Diagnostics]:
    """Return a record with one error at 13:17."""
    var record = Diagnostics()
    record.errors.append(SourceError(13, 17, message))
    return record^


def _reason(
    status: Int, output: String, expected: Optional[Diagnostics] = None
) raises -> String:
    """Return the rejection reason, or an empty string for a rejection."""
    var reason = rejection_error(FIXTURE, status, output, expected)
    if reason:
        return reason.value()
    return ""


# --- diagnostics -------------------------------------------------------------


def test_semantic_rejection() raises:
    assert_equal(_reason(1, _diagnostic()), "")
    var absolute = _diagnostic().replace(FIXTURE, realpath(".") + "/" + FIXTURE)
    assert_equal(_reason(1, absolute), "")
    assert_equal(_reason(1, "\x1b[31m" + _diagnostic() + "\x1b[0m"), "")


def test_compiled_fixture_fails() raises:
    assert_true(_reason(0, "").find("compiled") >= 0)


def test_exact_crashpad_warning_with_expected_rejection() raises:
    for newline in ["\n", "\r\n"]:
        var output = CRASHPAD_STARTUP_WARNING + newline + _diagnostic()
        assert_equal(_reason(1, output, _expected()), "")
        var extra = output + _diagnostic("unexpected token")
        assert_true(
            _reason(1, extra, _expected()).find("unexpected source") >= 0
        )


def test_crashpad_warning_without_source_rejection_fails() raises:
    assert_true(
        _reason(1, CRASHPAD_STARTUP_WARNING + "\n").find(
            "no located source error"
        )
        >= 0
    )
    for status in [0, 139, 245]:
        assert_true(
            _reason(status, CRASHPAD_STARTUP_WARNING + "\n" + _diagnostic())
            != ""
        )


def test_crashpad_warning_does_not_hide_real_failures() raises:
    for failure in [
        "LLVM ERROR: invalid IR",
        "segmentation fault",
        "stack dump",
        "PLEASE submit a bug report",
        "internal compiler error",
        "Assertion 'x != 0' failed",
        "out of memory",
        "unable to locate module 'extensions'",
        "failed to import module 'extensions'",
    ]:
        var output = CRASHPAD_STARTUP_WARNING + "\n" + _diagnostic() + failure
        assert_true(_reason(1, output).find("infrastructure") >= 0)


def test_only_exact_whole_crashpad_warning_line_is_allowed() raises:
    var warnings = [
        "prefix " + CRASHPAD_STARTUP_WARNING,
        CRASHPAD_STARTUP_WARNING + " suffix",
        String(CRASHPAD_STARTUP_WARNING).replace(
            "handler executable", "module 'extensions'"
        ),
        _diagnostic(CRASHPAD_STARTUP_WARNING).replace("\n", ""),
    ]
    for warning in warnings:
        assert_true(
            _reason(1, warning + "\n" + _diagnostic()).find("infrastructure")
            >= 0
        )


def test_signal_timeout_and_shell_error_fail() raises:
    for status in [124, 126, 127, 137, 139, 2]:
        assert_true(_reason(status, _diagnostic()).find("abnormally") >= 0)


def test_silent_and_driver_failures_fail() raises:
    for output in [
        "",
        "mojo: error: compilation failed",
        "unknown argument: --wrong",
    ]:
        assert_true(_reason(1, output) != "")


def test_import_failure_is_not_rejection() raises:
    for message in [
        "unable to locate module 'extensions'",
        "cannot open file",
        "could not find module",
        "No such file or directory",
    ]:
        assert_true(
            _reason(1, _diagnostic(message)).find("infrastructure") >= 0
        )


def test_dependency_error_is_not_rejection() raises:
    var output = (
        _diagnostic() + "units/length.mojo:3:1: error: broken declaration\n"
    )
    assert_true(_reason(1, output).find("outside") >= 0)


def test_crash_after_diagnostic_is_not_rejection() raises:
    for suffix in [
        "LLVM ERROR: invalid IR",
        "PLEASE submit a bug report",
        "Assertion 'x != 0' failed",
        "out of memory",
    ]:
        assert_true(
            _reason(1, _diagnostic() + suffix).find("infrastructure") >= 0
        )


def test_expected_message_and_location() raises:
    assert_equal(_reason(1, _diagnostic(), _expected()), "")
    for output in [
        _diagnostic("unexpected token"),
        _diagnostic().replace(":13:17:", ":14:17:"),
        _diagnostic() + _diagnostic("unknown identifier"),
    ]:
        assert_true(
            _reason(1, output, _expected()).find("unexpected source") >= 0
        )


def test_candidate_notes_are_part_of_expected_reason() raises:
    var output = _diagnostic("no matching function in initialization")
    output += "units/kind.mojo:7:2: note: value cannot be converted to BodyId\n"
    var record = Diagnostics()
    record.errors.append(
        SourceError(13, 17, "no matching function in initialization")
    )
    record.notes.append("value cannot be converted to BodyId")
    var expected: Optional[Diagnostics] = record^
    assert_equal(_reason(1, output, expected), "")
    var drift = output.replace(
        "value cannot be converted to BodyId",
        "missing required argument: cast_shadow",
    )
    assert_true(_reason(1, drift, expected).find("unexpected source") >= 0)


def test_fatal_errors_and_paths_with_colons_are_located() raises:
    var output = "a:b.mojo:4:2: fatal error: stop here \n"
    var captured = expected_diagnostics(output)
    assert_equal(len(captured.errors), 1)
    assert_equal(captured.errors[0].line, 4)
    assert_equal(captured.errors[0].column, 2)
    assert_equal(captured.errors[0].message, "stop here")


def test_diagnostics_are_sorted_and_unique() raises:
    var output = (
        _diagnostic("b")
        + _diagnostic("a")
        + _diagnostic("a")
        + FIXTURE
        + ":2:9: error: early\n"
        + "x.mojo:1:1: note: second\n"
        + "x.mojo:2:2: note: first\n"
        + "x.mojo:2:2: note: first\n"
    )
    var captured = expected_diagnostics(output)
    assert_equal(len(captured.errors), 3)
    assert_equal(captured.errors[0].message, "early")
    assert_equal(captured.errors[1].message, "a")
    assert_equal(captured.errors[2].message, "b")
    assert_equal(len(captured.notes), 2)
    assert_equal(captured.notes[0], "first")


def test_output_cleaning() raises:
    assert_equal(strip_color("\x1b[1;31mred\x1b[0m \x1b[x"), "red \x1b[x")
    var lines = split_lines("a\r\nb\rc\nd\x0be\u2028f\n")
    assert_equal(len(lines), 6)
    assert_equal(lines[5], "f")
    assert_equal(
        clean_output("one\n" + CRASHPAD_STARTUP_WARNING + "\ntwo\n"),
        "one\ntwo",
    )


def test_shell_split_matches_shlex() raises:
    var words = shell_split(" mojo  'a b' \"c \\\" d\" e\\ f '' ")
    assert_equal(len(words), 5)
    assert_equal(words[0], "mojo")
    assert_equal(words[1], "a b")
    assert_equal(words[2], 'c " d')
    assert_equal(words[3], "e f")
    assert_equal(words[4], "")
    assert_equal(len(shell_split("")), 0)
    with assert_raises(contains="No closing quotation"):
        _ = shell_split("'open")
    with assert_raises(contains="No closing quotation"):
        _ = shell_split('"open')
    with assert_raises(contains="No escaped character"):
        _ = shell_split("end\\")


# --- options ----------------------------------------------------------------


def _arguments(text: String) raises -> List[String]:
    """Split a test command line into arguments."""
    return shell_split(text)


def test_options_follow_argparse() raises:
    var options = parse_options(
        _arguments(
            "--compiler mojo --flags=-I. --timeout 2.5 --expectations e.json"
            " --update-expectations b a -- --c"
        )
    )
    assert_equal(options.compiler, "mojo")
    assert_equal(options.flags, "-I.")
    assert_equal(options.timeout, 2.5)
    assert_equal(options.expectations, "e.json")
    assert_true(options.update)
    assert_equal(len(options.fixtures), 3)
    assert_equal(options.fixtures[2], "--c")
    assert_true(
        Options().expectations.endswith("tools/compile_fail_expectations.json")
    )
    with assert_raises(contains="required: --compiler"):
        _ = parse_options(_arguments("a.mojo"))
    with assert_raises(contains="must be positive"):
        _ = parse_options(_arguments("--compiler=mojo --timeout=0"))
    with assert_raises(contains="invalid float value"):
        _ = parse_options(_arguments("--compiler=mojo --timeout=soon"))
    with assert_raises(contains="unrecognized arguments"):
        _ = parse_options(_arguments("--compiler=mojo --wrong"))
    with assert_raises(contains="expected one argument"):
        _ = parse_options(_arguments("--compiler"))


def test_update_needs_a_fixture_and_a_compiler() raises:
    with assert_raises(contains="requires at least one explicit fixture"):
        _ = check(
            parse_options(_arguments("--compiler=x --update-expectations"))
        )
    with assert_raises(contains="must not be empty"):
        _ = check(parse_options(_arguments("--compiler='' a.mojo")))


def test_empty_selection_needs_no_compiler() raises:
    var report = check(parse_options(_arguments("--compiler=missing")))
    assert_equal(report.code, 0)
    assert_equal(report.out, "No negative fixtures selected.\n")


# --- runner -------------------------------------------------------------------

comptime _FAKE = """#!/bin/sh
dir=$(dirname "$0")
for last; do :; done
name=$(basename "$last")
printf '%s\\n' "$*" >>"$dir/calls"
[ -f "$dir/$name.out" ] && cat "$dir/$name.out"
[ -f "$dir/$name.hook" ] && dir="$dir" sh "$dir/$name.hook"
[ -f "$dir/$name.rc" ] && exit "$(cat "$dir/$name.rc")"
exit 0
"""


struct Sandbox(Movable):
    """A temporary directory with a fake compiler and a manifest."""

    var root: String
    var fixture: String
    var manifest: String

    def __init__(out self) raises:
        self.root = mkdtemp(prefix="threemojo-compile-fail-test-")
        self.fixture = self.root + "/fixture.mojo"
        self.manifest = self.root + "/expectations.json"
        Path(self.root + "/fake.sh").write_text(_FAKE)
        Path(self.fixture).write_text("def main():\n    var x: Int = 'a'\n")

    def write(self, name: String, text: String) raises:
        Path(self.root + "/" + name).write_text(text)

    def read(self, name: String) raises -> String:
        return Path(self.root + "/" + name).read_text()

    def calls(self) raises -> Int:
        if not Path(self.root + "/calls").exists():
            return 0
        return len(split_lines(self.read("calls")))

    def options(self, extra: String = "") raises -> Options:
        var arguments = List[String]()
        arguments.append("--compiler=sh " + self.root + "/fake.sh")
        arguments.append("--flags=-I .")
        arguments.append("--expectations=" + self.manifest)
        for word in shell_split(extra):
            arguments.append(word)
        arguments.append(self.fixture)
        return parse_options(arguments)

    def rejection(self, message: String = "invalid conversion") -> String:
        return self.fixture + ":1:1: error: " + message + "\n"

    def record(self) -> String:
        return (
            '{\n  "'
            + self.fixture
            + '": {\n    "errors": [\n      {\n        "column": 1,\n'
            + '        "line": 1,\n        "message": "invalid conversion"\n'
            + '      }\n    ],\n    "notes": []\n  }\n}\n'
        )

    def close(self) raises:
        """Remove the sandbox. A test calls it last, which also keeps the
        sandbox alive until the test ends."""
        _ = run_program(["rm", "-rf", self.root], 10)


def test_control_prevents_broken_compiler_false_pass() raises:
    var box = Sandbox()
    box.write("expectations.json", box.record())
    box.write("control.mojo.out", "broken compiler\n")
    box.write("control.mojo.rc", "1")
    var report = check(box.options())
    assert_equal(report.code, 1)
    assert_equal(box.calls(), 1)
    assert_true(report.out.find("control failed") >= 0)
    assert_true(report.out.find("broken compiler") >= 0)
    box.close()


def test_control_then_valid_rejection() raises:
    var box = Sandbox()
    box.write("expectations.json", box.record())
    box.write("fixture.mojo.out", box.rejection())
    box.write("fixture.mojo.rc", "1")
    var report = check(box.options())
    assert_equal(report.code, 0)
    assert_equal(box.calls(), 2)
    assert_true(report.out.find("1 negative fixtures") >= 0)
    var calls = split_lines(box.read("calls"))
    assert_true(calls[0].startswith("build -I . -o /dev/null "))
    assert_true(calls[1].endswith("build -I . -o /dev/null " + box.fixture))
    box.close()


def test_failed_fixture_diagnostics_retained() raises:
    var box = Sandbox()
    box.write("expectations.json", box.record())
    box.write("fixture.mojo.out", "unknown argument --bad\n")
    box.write("fixture.mojo.rc", "1")
    var report = check(box.options())
    assert_equal(report.code, 1)
    assert_true(report.out.find("unknown argument --bad") >= 0)
    box.close()


def test_control_with_crashpad_warning_still_requires_success() raises:
    var box = Sandbox()
    box.write("expectations.json", box.record())
    box.write("control.mojo.out", CRASHPAD_STARTUP_WARNING + "\n")
    box.write("control.mojo.rc", "139")
    var report = check(box.options())
    assert_equal(report.code, 1)
    assert_true(report.out.find(CRASHPAD_STARTUP_WARNING) >= 0)
    box.write("control.mojo.rc", "0")
    box.write(
        "fixture.mojo.out", CRASHPAD_STARTUP_WARNING + "\n" + box.rejection()
    )
    box.write("fixture.mojo.rc", "1")
    assert_equal(check(box.options()).code, 0)
    box.close()


def test_timeout_is_an_infrastructure_error() raises:
    var box = Sandbox()
    box.write("expectations.json", box.record())
    box.write("control.mojo.hook", "exec sleep 30\n")
    var report = check(box.options("--timeout=0.2"))
    assert_equal(report.code, 1)
    assert_true(report.err.find("infrastructure error") >= 0)
    assert_true(report.err.find("timed out") >= 0)
    box.close()


def test_missing_compiler_fails_the_control() raises:
    var box = Sandbox()
    box.write("expectations.json", box.record())
    var options = box.options()
    options.compiler = box.root + "/no-such-compiler"
    assert_equal(check(options).code, 1)
    box.close()


def test_missing_fixture_and_record_fail_before_control() raises:
    var box = Sandbox()
    box.write("expectations.json", "{}\n")
    var report = check(box.options())
    assert_equal(report.code, 1)
    assert_true(report.err.find("Missing expected diagnostics") >= 0)
    box.write("expectations.json", box.record())
    remove(box.fixture)
    report = check(box.options())
    assert_equal(report.code, 1)
    assert_true(report.err.find("infrastructure error") >= 0)
    assert_equal(box.calls(), 0)
    box.close()


def test_invalid_manifest_is_refused_before_control() raises:
    var box = Sandbox()
    for text in ["[]\n", "not json\n"]:
        box.write("expectations.json", text)
        var report = check(box.options("--update-expectations"))
        assert_equal(report.code, 1)
        assert_true(report.err.find("infrastructure error") >= 0)
    assert_equal(box.calls(), 0)
    box.close()


def test_normal_check_is_read_only_on_match_and_drift() raises:
    var box = Sandbox()
    box.write("expectations.json", box.record())
    box.write("fixture.mojo.rc", "1")
    for message in ["invalid conversion", "something else"]:
        box.write("fixture.mojo.out", box.rejection(message))
        _ = check(box.options())
        assert_equal(box.read("expectations.json"), box.record())
    box.close()


# --- regeneration -----------------------------------------------------------


def test_update_rewrites_only_the_selected_record() raises:
    var box = Sandbox()
    var other = (
        '  "a/other.mojo": {\n    "notes": [\n      "kept \\u00e9"\n    ],\n'
        + '    "errors": [\n      {\n        "message": "m",\n'
        + '        "column": 2,\n        "line": 3\n      }\n    ]\n  },\n'
    )
    box.write(
        "expectations.json",
        "{\n" + other + String(box.record()[byte=2:]),
    )
    box.write(
        "fixture.mojo.out",
        box.rejection("new reason")
        + box.rejection("new reason")
        + box.root
        + "/x.mojo:2:2: note: a note\n",
    )
    box.write("fixture.mojo.rc", "1")
    var report = check(box.options("--update-expectations"))
    assert_equal(report.code, 0)
    assert_true(report.out.find("Updated expectations") >= 0)
    assert_true(report.out.find("(before)") >= 0)
    # The absolute fixture path sorts before "a/other.mojo". The record the
    # update did not select keeps its field order.
    var expected = (
        '{\n  "'
        + box.fixture
        + '": {\n    "errors": [\n      {\n        "line": 1,\n'
        + '        "column": 1,\n        "message": "new reason"\n'
        + '      }\n    ],\n    "notes": [\n      "a note"\n    ]\n  },\n'
        + String(other[byte = : other.byte_length() - 2])
        + "\n}\n"
    )
    assert_equal(box.read("expectations.json"), expected)
    var names = listdir(box.root)
    for name in names:
        assert_false(name.startswith("expectations.json."))
    report = check(box.options("--update-expectations"))
    assert_true(report.out.find("Expectations unchanged.") >= 0)
    assert_equal(box.read("expectations.json"), expected)
    box.close()


def test_new_fixture_is_added_in_sorted_order() raises:
    var box = Sandbox()
    box.write("expectations.json", '{\n  "zz": []\n}\n')
    box.write("fixture.mojo.out", box.rejection())
    box.write("fixture.mojo.rc", "1")
    assert_equal(check(box.options("--update-expectations")).code, 0)
    var text = box.read("expectations.json")
    assert_true(text.find(box.fixture) < text.find('"zz": []'))
    box.close()


def test_invalid_selected_result_never_updates() raises:
    var box = Sandbox()
    box.write("expectations.json", box.record())
    box.write("fixture.mojo.out", "LLVM ERROR: broken\n")
    box.write("fixture.mojo.rc", "1")
    assert_equal(check(box.options("--update-expectations")).code, 1)
    assert_equal(box.read("expectations.json"), box.record())
    box.close()


def test_concurrent_edit_is_not_overwritten() raises:
    var box = Sandbox()
    box.write("expectations.json", box.record())
    box.write("fixture.mojo.out", box.rejection("changed"))
    box.write("fixture.mojo.rc", "1")
    box.write(
        "fixture.mojo.hook",
        "printf '{}\\n' >\"$dir/expectations.json\"\n",
    )
    var report = check(box.options("--update-expectations"))
    assert_equal(report.code, 1)
    assert_true(report.err.find("changed during compilation") >= 0)
    assert_equal(box.read("expectations.json"), "{}\n")
    box.close()


def test_update_refuses_a_symlink_and_keeps_the_mode() raises:
    var box = Sandbox()
    box.write("real.json", box.record())
    _ = run_program(["ln", "-s", "real.json", box.manifest], 10)
    box.write("fixture.mojo.out", box.rejection("changed"))
    box.write("fixture.mojo.rc", "1")
    var report = check(box.options("--update-expectations"))
    assert_equal(report.code, 1)
    assert_true(report.err.find("symlink") >= 0)
    box.write("fixture.mojo.out", box.rejection())
    assert_equal(check(box.options()).code, 0)
    remove(box.manifest)
    box.write("expectations.json", box.record())
    _ = run_program(["chmod", "640", box.manifest], 10)
    box.write("fixture.mojo.out", box.rejection("changed"))
    assert_equal(check(box.options("--update-expectations")).code, 0)
    var mode = run_program(
        [
            "sh",
            "-c",
            'stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"',
            "sh",
            box.manifest,
        ],
        10,
    )
    assert_equal(mode.output, "640\n")
    box.close()


# --- repository -------------------------------------------------------------


def test_check_repository_takes_only_the_manifest() raises:
    var options = parse_options(
        _arguments("--check-repository --expectations=e.json")
    )
    assert_true(options.check_repository)
    assert_equal(options.expectations, "e.json")
    for extra in ["--compiler=mojo", "--update-expectations", "a.mojo"]:
        with assert_raises(contains="takes only --expectations"):
            _ = parse_options(_arguments("--check-repository " + extra))


def test_repository_manifest_matches_the_fixtures() raises:
    var box = Sandbox()
    _ = run_program(
        [
            "mkdir",
            "-p",
            box.root + "/tests/compile_fail",
            box.root + "/.github/workflows",
        ],
        10,
    )
    box.write("tests/compile_fail/a.mojo", "one\ntwo\n")
    box.write("tests/compile_fail/notes.txt", "")
    box.write("Makefile", "compile-fail:\n\tcheck\n")
    box.write(".github/workflows/ci.yml", "run: make compile-fail\n")
    var good = (
        '{"tests/compile_fail/a.mojo": {"errors": [{"line": 2, "column": 1,'
        + ' "message": "m"}], "notes": []}}'
    )
    box.write("expectations.json", good)
    assert_equal(len(repository_errors(box.root, box.manifest)), 0)
    # A fixture without a record, and a record without a fixture.
    box.write("tests/compile_fail/b.mojo", "x\n")
    box.write(
        "expectations.json",
        good.replace(
            "}}",
            '}, "tests/compile_fail/gone.mojo": {"errors": [],'
            + ' "notes": []}}',
        ),
    )
    var errors = repository_errors(box.root, box.manifest)
    var text = String("\n").join(errors)
    assert_true(text.find("no manifest record: tests/compile_fail/b.mojo") >= 0)
    assert_true(text.find("no fixture: tests/compile_fail/gone.mojo") >= 0)
    _ = run_program(["rm", box.root + "/tests/compile_fail/b.mojo"], 10)
    # Locations must be on a fixture line, and a record needs an error.
    for bad in ['"line": 3', '"line": 0', '"column": 0']:
        var changed = good.replace('"line": 2', bad) if bad.find(
            "line"
        ) >= 0 else good.replace('"column": 1', bad)
        box.write("expectations.json", changed)
        assert_true(
            String("\n")
            .join(repository_errors(box.root, box.manifest))
            .find("outside its fixture")
            >= 0
        )
    box.write(
        "expectations.json",
        '{"tests/compile_fail/a.mojo": {"errors": [], "notes": []}}',
    )
    assert_true(
        repository_errors(box.root, box.manifest)[0].find("no errors") >= 0
    )
    # No Make target or workflow may regenerate the manifest.
    box.write("expectations.json", good)
    box.write(".github/workflows/ci.yml", "run: x --update-expectations\n")
    assert_equal(
        repository_errors(box.root, box.manifest)[0],
        "regeneration must stay manual: .github/workflows/ci.yml",
    )
    box.write(".github/workflows/ci.yml", "")
    box.write("Makefile", "--update-expectations\n")
    assert_equal(
        repository_errors(box.root, box.manifest)[0],
        "regeneration must stay manual: Makefile",
    )
    box.write("expectations.json", "[]")
    with assert_raises(contains="JSON object"):
        _ = repository_errors(box.root, box.manifest)
    box.close()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
