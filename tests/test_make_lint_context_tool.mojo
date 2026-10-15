# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check CPU lint failure context without invoking the Mojo compiler.

Each test copies the maintained `lint-cpu` recipe from the `Makefile` into a
temporary project. A shell script stands in for the compiler. It reads its
failure from `config.sh`.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tests._make_recipe import (
    LOG_ARGUMENTS,
    clean_command,
    read_calls,
    section,
)
from tools.compile_fail import shell_split
from tools._process import ProcessResult, run_program, shell_quote

comptime ENTRIES = [
    "examples/first.mojo",
    "tools/second.mojo",
    "tests/suite.mojo",
]
"""The fixture entry points; the last is a suite, which lint skips."""

comptime DOCS = ["math/first.mojo", "render/second.mojo"]
"""The fixture library modules."""

comptime FLAGS = ["-I", ".", "-D", "value with spaces; $literal"]
"""The fixture's `MOJOFLAGS`, as words."""

comptime COMPILER = ["sh", "compiler.sh"]
"""The fixture's `MOJO`, as words."""

comptime SENTINEL = "LINT_CONTEXT_PRIVATE_SENTINEL=must-not-be-printed"
"""An environment value that no output may show."""


struct Project(Movable):
    """A temporary project with the real `lint-cpu` recipe."""

    var root: String
    var outer: Bool

    def __init__(out self, outer: Bool = False) raises:
        self.root = mkdtemp(prefix="lint context ")
        self.outer = outer
        Path(self.root + "/compiler.sh").write_text(
            LOG_ARGUMENTS
            + "operation=\nsource=\nstatus=\ndiagnostics=\n"
            + ". ./config.sh\n"
            + 'for last in "$@"; do :; done\n'
            + 'if [ -n "$diagnostics" ]; then\n'
            + "  printf 'compiler stdout: %s\\n' \"$last\"\n"
            + "  printf 'Failed to initialize Crashpad\\n' >&2\n"
            + "  printf 'compiler stderr: %s\\n' \"$last\" >&2\n"
            + "fi\n"
            + 'if [ -n "$operation" ] && [ "$1" = "$operation" ] \\\n'
            + '  && [ "$last" = "$source" ]; then\n'
            + '  exit "$status"\n'
            + "fi\n"
        )
        var source = Path("Makefile").read_text()
        var recipe = section(
            source,
            "lint-cpu: $(LINT_CPU_STAMP)\n",
            "\n# Compile all maintained GPU",
        )
        Path(self.root + "/Makefile").write_text(
            "JOBS := 3\nMOJO := sh compiler.sh\n"
            + 'MOJOFLAGS := -I . -D "value with spaces; \\$$literal"\n'
            + "CPU_ENTRY_POINTS := "
            + " ".join(_list(materialize[ENTRIES]()))
            + "\n"
            + "CPU_TESTS := tests/suite.mojo\n"
            + "CPU_DOC_SOURCES := "
            + " ".join(_list(materialize[DOCS]()))
            + "\n"
            + "LINT_CPU_STAMP := lint-cpu-stamp\n"
            + "stamp = touch $(1)-stamp\n"
            + recipe
            + "\n"
        )
        self.configure()

    def configure(
        self,
        operation: String = "",
        source: String = "",
        status: Int = 0,
        diagnostics: Bool = False,
    ) raises:
        Path(self.root + "/config.sh").write_text(
            "operation="
            + shell_quote(operation)
            + "\nsource="
            + shell_quote(source)
            + "\nstatus="
            + String(status)
            + "\ndiagnostics="
            + ("1" if diagnostics else "")
            + "\n"
        )

    def run(self, command: List[String]) raises -> ProcessResult:
        return run_program(
            clean_command([SENTINEL], command, self.outer),
            5,
            merge_errors=False,
            directory=self.root,
        )

    def make(self, arguments: List[String] = []) raises -> ProcessResult:
        var command: List[String] = ["make", "-s"]
        command.extend(arguments.copy())
        command.append("lint-cpu")
        return self.run(command)

    def calls(self) raises -> List[List[String]]:
        return read_calls(self.root + "/invocations")

    def stamped(self) -> Bool:
        return Path(self.root + "/lint-cpu-stamp").exists()

    def wrapper(
        self, operation: String, source: String, arguments: List[String] = []
    ) raises -> ProcessResult:
        """Run the maintained shell wrapper directly: xargs and make map a
        failed child's status, so only this boundary shows the exact one."""
        var preview_arguments: List[String] = ["-n"]
        preview_arguments.extend(arguments.copy())
        var preview = self.make(preview_arguments)
        assert_equal(preview.status, 0, preview.errors)
        var tokens = shell_split(preview.output)
        var scripts = List[String]()
        for index in range(len(tokens) - 2):
            if tokens[index] == "sh" and tokens[index + 1] == "-c":
                scripts.append(tokens[index + 2])
        assert_equal(len(scripts), 2)
        return self.run(
            [
                "/bin/sh",
                "-c",
                scripts[1 if operation == "doc" else 0],
                "_",
                source,
            ]
        )

    def close(self) raises:
        _ = run_program(["rm", "-rf", self.root], 10)


def _list[size: Int](table: Array[String, size]) -> List[String]:
    var out = List[String]()
    for item in table:
        out.append(item)
    return out^


def _call(
    operation: String, source: String, target: List[String] = []
) -> List[String]:
    """Return the compiler arguments of one lint call."""
    var call: List[String] = [operation]
    call.extend(_list(materialize[FLAGS]()))
    call.extend(target.copy())
    call.extend(["--Werror", "-o", "/dev/null", source])
    return call^


def _command(operation: String, source: String) -> List[String]:
    """Return the whole command line of one lint call."""
    var command = _list(materialize[COMPILER]())
    command.extend(_call(operation, source))
    return command^


def _sorted(var calls: List[List[String]]) -> List[String]:
    """Return calls as sorted text lines, to compare them in any order."""
    var lines = List[String]()
    for call in calls:
        lines.append("\x1f".join(call))
    sort(lines)
    return lines^


def _same_calls(
    var left: List[List[String]], var right: List[List[String]]
) -> Bool:
    return _sorted(left^) == _sorted(right^)


def _expected_diagnostics(source: String) raises -> String:
    """Filter the stub's output with the host's own `sed`.

    GNU and BSD sed differ on an unterminated final line, so the expectation
    uses the host's filter, as the wrapper does.
    """
    var result = run_program(
        [
            "sh",
            "-c",
            'printf "%s" "$1" | sed /Crashpad/d',
            "_",
            "compiler stdout: "
            + source
            + "\nFailed to initialize Crashpad\n"
            + "compiler stderr: "
            + source,
        ],
        5,
        merge_errors=False,
    )
    assert_equal(result.status, 0)
    return result.output


def _no_sentinel(result: ProcessResult) raises:
    var text = result.output + result.errors
    assert_equal(text.find("must-not-be-printed"), -1)
    assert_equal(text.find("LINT_CONTEXT_PRIVATE_SENTINEL"), -1)


def _assert_context(
    result: ProcessResult, operation: String, source: String, status: Int
) raises:
    var lines = result.errors.splitlines()
    assert_equal(len(lines), 2, result.errors)
    assert_equal(
        String(lines[0]),
        "lint-cpu failed: " + source + " (exit " + String(status) + ")",
    )
    var line = String(lines[1])
    assert_true(line.startswith("command: "), result.errors)
    var argv = shell_split(String(line[byte=9:]))
    assert_true(argv == _command(operation, source))
    _no_sentinel(result)


def test_success_preserves_exact_selection_arguments_and_silence() raises:
    var project = Project()
    var result = project.make()
    assert_equal(result.status, 0, result.output + result.errors)
    var expected = List[List[String]]()
    expected.append(_call("build", "examples/first.mojo"))
    expected.append(_call("build", "tools/second.mojo"))
    for path in materialize[DOCS]():
        expected.append(_call("doc", path))
    assert_true(_same_calls(project.calls(), expected^))
    assert_equal(result.output, "No warnings (CPU).\n")
    assert_equal(result.errors, "")
    assert_true(project.stamped())
    project.close()


def test_target_override_is_build_only_and_default_doc_flags_are_preserved() raises:
    var project = Project()
    var target: List[String] = [
        "--target-triple=x86_64-unknown-linux-gnu",
        "--target-cpu=x86-64-v3",
    ]
    var result = project.make(["LINT_CPU_BUILD_FLAGS=" + " ".join(target)])
    assert_equal(result.status, 0, result.output + result.errors)
    var expected = List[List[String]]()
    expected.append(_call("build", "examples/first.mojo", target))
    expected.append(_call("build", "tools/second.mojo", target))
    for path in materialize[DOCS]():
        expected.append(_call("doc", path))
    assert_true(_same_calls(project.calls(), expected^))
    var source = Path("Makefile").read_text()
    assert_true(
        source.find(
            "--setting=$(call quote,lint-cpu-build-flags:"
            "$(LINT_CPU_BUILD_FLAGS))"
        )
        >= 0
    )
    project.close()


def test_progress_names_each_command_and_preserves_failure_status() raises:
    var project = Project()
    for pair in [("build", "examples/first.mojo"), ("doc", "math/first.mojo")]:
        var operation = pair[0]
        var source = pair[1]
        for status in [0, 7]:
            project.configure(operation, source, status)
            var result = project.wrapper(
                operation, source, ["LINT_CPU_PROGRESS=1"]
            )
            assert_equal(result.status, status)
            var lines = result.output.splitlines()
            assert_equal(len(lines), 2)
            var prefix = " lint-" + operation + "-start: "
            var first = String(lines[0])
            var at = first.find(prefix)
            assert_true(at >= 0)
            assert_true(
                shell_split(String(first[byte = at + prefix.byte_length() :]))
                == _command(operation, source)
            )
            assert_true(
                String(lines[1]).endswith(
                    " lint-"
                    + operation
                    + "-end: source="
                    + source
                    + " exit="
                    + String(status)
                )
            )
            assert_true(first.byte_length() <= 4096)
            _no_sentinel(result)
            if status != 0:
                _assert_context(result, operation, source, status)
            else:
                assert_equal(result.errors, "")
    project.close()


def test_each_wrapper_preserves_exact_failure_status_and_diagnostics() raises:
    var project = Project()
    for pair in [("build", "examples/first.mojo"), ("doc", "math/first.mojo")]:
        var operation = pair[0]
        var source = pair[1]
        for status in [1, 7, 139, 255]:
            project.configure(operation, source, status, diagnostics=True)
            var result = project.wrapper(operation, source)
            assert_equal(result.status, status)
            # The existing wrapper combines compiler stderr into stdout,
            # strips Crashpad, and trims the final captured newline.
            assert_equal(result.output, _expected_diagnostics(source))
            _assert_context(result, operation, source, status)
    project.close()


def test_each_wrapper_preserves_success_diagnostics_without_context() raises:
    var project = Project()
    project.configure(diagnostics=True)
    for pair in [("build", "examples/first.mojo"), ("doc", "math/first.mojo")]:
        var result = project.wrapper(pair[0], pair[1])
        assert_equal(result.status, 0)
        assert_equal(result.output, _expected_diagnostics(pair[1]))
        assert_equal(result.errors, "")
    project.close()


def test_build_failure_keeps_all_entries_and_blocks_docs_and_stamp() raises:
    var project = Project()
    project.configure("build", "examples/first.mojo", 7)
    var result = project.make()
    assert_equal(result.status, 2)
    var calls = project.calls()
    var sources = List[String]()
    for call in calls:
        sources.append(call[len(call) - 1])
        assert_equal(call[0], "build")
    sort(sources)
    var expected: List[String] = ["examples/first.mojo", "tools/second.mojo"]
    assert_true(sources == expected)
    assert_true(
        result.errors.find("lint-cpu failed: examples/first.mojo (exit 7)") >= 0
    )
    assert_equal(result.output.find("No warnings"), -1)
    assert_false(project.stamped())
    project.close()


def test_doc_failure_keeps_all_selected_inputs_and_blocks_stamp() raises:
    var project = Project()
    project.configure("doc", "math/first.mojo", 7)
    var result = project.make()
    assert_equal(result.status, 2)
    var sources = List[String]()
    for call in project.calls():
        sources.append(call[len(call) - 1])
    sort(sources)
    var expected: List[String] = [
        "examples/first.mojo",
        "math/first.mojo",
        "render/second.mojo",
        "tools/second.mojo",
    ]
    assert_true(sources == expected)
    assert_true(
        result.errors.find("lint-cpu failed: math/first.mojo (exit 7)") >= 0
    )
    assert_equal(result.output.find("No warnings"), -1)
    assert_false(project.stamped())
    project.close()


def test_success_cache_hit_and_force_rebuild() raises:
    var project = Project()
    var first = project.make()
    assert_equal(first.status, 0, first.errors)
    var calls = _sorted(project.calls())
    var cached = project.make()
    assert_equal(cached.status, 0, cached.errors)
    assert_equal(cached.output + cached.errors, "")
    assert_true(_sorted(project.calls()) == calls)
    var rebuilt = project.make(["-B"])
    assert_equal(rebuilt.status, 0, rebuilt.errors)
    var twice = calls.copy()
    twice.extend(calls.copy())
    sort(twice)
    assert_true(_sorted(project.calls()) == twice)
    project.close()


def test_parent_make_overrides_cannot_invoke_another_compiler() raises:
    var project = Project(outer=True)
    var result = project.make()
    assert_equal(result.status, 0, result.errors)
    assert_equal(len(project.calls()), 4)
    project.close()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
