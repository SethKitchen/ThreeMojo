# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare native and rewritten loops at several valid indentation widths.

    sh tools/tool.sh .venv/bin/mojo check_coverage_loops --mojo .venv/bin/mojo

Fixtures carry their own source-line and decision identities. Exact loop
records check empty, exhausted, broken, continued, returned and raised
paths. Every executable retains the original five-second runtime limit.

The tool works on the repository in the current directory. With
`--baseline-build`, a frozen `build_cli` must fail on two original sources
that compile natively, as negative controls.
"""

from std.collections import Set
from std.os import makedirs
from std.os.path import realpath
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._cli import absolute_path, normal_path, parse_command_line
from tools._process import ProcessResult, run_program
from tools._python_json import py_repr
from tools._text import split_lines
from tools.check_coverage_sources import (
    BUILD_SECONDS,
    SECONDS,
    Decision,
    build_and_run,
    build_rewriter,
    manifest,
    prepare_work,
    read_text,
    remove_tree,
    require,
    run_checked,
    universal_newlines,
    write_text,
)

comptime PROGRAM = "check_coverage_loops.mojo"
"""The program name in usage messages."""
comptime USAGE = (
    "usage: check_coverage_loops.mojo [-h] [--mojo MOJO] [--output OUTPUT]\n"
    "                                 [--baseline-build BASELINE_BUILD]\n"
)
"""The usage text, as `argparse` writes it."""
comptime HELP = (
    "\nCompare native and rewritten loops at several valid indentation"
    " widths.\nFixtures carry their own source-line and decision identities."
    " Exact loop\nrecords check empty, exhausted, broken, continued, returned"
    " and raised paths.\nEvery executable retains the original five-second"
    " runtime limit.\n\noptions:\n  -h, --help            show this help"
    " message and exit\n  --mojo MOJO\n  --output OUTPUT\n  --baseline-build"
    " BASELINE_BUILD\n                        Optional frozen build_cli for"
    " negative controls.\n"
)
"""The help text after the usage."""
comptime PASS_TEXT = (
    "PASS: nine native/instrumented loop fixtures; LF/CRLF/CR and"
    " unterminated final lines; tabs in headers/literals/comments; widths 1,"
    " 2, 3, 4, 8 and mixed 2/5; exact source identities and loop outcomes;"
    " comments, multiline headers/literals, nested loops,"
    " break/continue/return, for-else and exceptions"
)
"""The line that a successful check prints."""


struct LoopFixture(Movable):
    """A loop fixture and the identities the rewriter must give it."""

    var rows: List[String]
    """The source lines, without line endings."""
    var width: Int
    """The indentation of the first level."""
    var step: Int
    """The indentation each deeper level adds."""
    var lines: List[Int]
    """The executable lines."""
    var decisions: List[Decision]
    """Each decision's line and its number of conditions, 0 for a loop."""
    var labels: Dict[String, Int]
    """The line of each labeled statement."""

    def __init__(out self, width: Int, step: Int):
        """Start an empty fixture.

        Args:
            width: The indentation of the first level.
            step: The indentation each deeper level adds.
        """
        self.rows = List[String]()
        self.width = width
        self.step = step
        self.lines = List[Int]()
        self.decisions = List[Decision]()
        self.labels = Dict[String, Int]()

    def add(
        mut self,
        depth: Int,
        text: String,
        kind: String = "",
        label: String = "",
    ):
        """Add a source line.

        Args:
            depth: The nesting level, 0 for none.
            text: The line without its indentation.
            kind: `L` for a line, `B` for a decision, or empty.
            label: A name for the line, or empty.
        """
        var indent = 0 if depth == 0 else self.width + (depth - 1) * self.step
        self.rows.append(" " * indent + text)
        var number = len(self.rows)
        if kind.byte_length() > 0:
            self.lines.append(number)
        if kind == "B":
            self.decisions.append((number, 0))
        if label.byte_length() > 0:
            self.labels[label] = number


def _escaped(ending: String) -> String:
    """Return a line ending as a Mojo string literal spells it."""
    return ending.replace("\r", "\\r").replace("\n", "\\n")


def fixture(
    width: Int, step: Int, ending: String = "\n", final_newline: Bool = True
) -> Tuple[String, LoopFixture]:
    """Return a loop fixture's source and its identities.

    Args:
        width: The indentation of the first level.
        step: The indentation each deeper level adds.
        ending: The line ending.
        final_newline: True to end the last line too.

    Returns:
        The source and the fixture.
    """
    var f = LoopFixture(width, step)
    f.add(0, "from std.testing import assert_equal")
    f.add(0, "def simple() raises:")
    f.add(1, "var total = 0", "L", "simple_start")
    f.add(1, "for index in range(2): # header", "B", "simple")
    f.add(0, "")
    f.add(0, "#\tA comment left of both suites must not establish indentation.")
    f.add(4, "# Nor can a more deeply indented comment.")
    f.add(2, "total += index", "L", "simple_body")
    f.add(1, "assert_equal(total, 1)", "L", "simple_end")
    f.add(0, "")
    f.add(0, "def flow(n: Int, stop: Bool, leave: Bool) raises -> Int:")
    f.add(1, "var total = 0", "L")
    f.add(1, "for outer in range( # start", "B", "outer")
    f.add(4, "# A header continuation is not a body.")
    f.add(3, "n # value")
    f.add(1, "):")
    f.add(0, "")
    f.add(0, "# The body starts after comments.")
    f.add(2, 'var text = String("""literal\tvalue', "L")
    f.add(0, "for fake in range(0):")
    f.add(0, "# ) and else:")
    f.add(0, 'end""")')
    var parts: List[String] = [
        "literal\\tvalue",
        "for fake in range(0):",
        "# ) and else:",
        "end",
    ]
    var expected_literal = _escaped(ending).join(parts)
    f.add(2, 'assert_equal(text, "' + expected_literal + '")', "L")
    f.add(2, "for inner in range(2):", "B", "inner")
    f.add(3, "if inner == 0:", "B")
    f.add(4, "continue", "L")
    f.add(3, "if stop:", "B")
    f.add(4, "break", "L")
    f.add(3, "total += outer + inner", "L")
    f.add(3, "if leave:", "B")
    f.add(4, "return total", "L")
    f.add(2, "else : # inner exhaustion")
    f.add(0, "# Preserve an intervening comment.")
    f.add(3, "total += 10", "L")
    f.add(1, "else\t: # outer exhaustion")
    f.add(2, "total += 100", "L")
    f.add(1, "return total", "L")
    f.add(0, "")
    f.add(0, "def exit_else(n: Int, fail: Bool) raises -> Int:")
    f.add(1, "for _ in range(n):", "B", "exit_else")
    f.add(2, "break", "L")
    f.add(1, "else:")
    f.add(2, "if fail:", "B")
    f.add(3, 'raise Error("expected else")', "L")
    f.add(2, "return 7", "L")
    f.add(1, "return 9", "L")
    f.add(0, "")
    f.add(0, "def throw_body() raises:")
    f.add(1, "for _ in range(1):", "B", "throw_body")
    f.add(2, 'raise Error("expected body")', "L")
    f.add(0, "")
    f.add(0, "def literal_header() raises:")
    f.add(1, "for index in range(", "B", "literal_header")
    f.add(3, 'String("""x')
    f.add(0, 'y""").byte_length() # a comment after the literal')
    f.add(3, "- " + String(ending.byte_length() + 1))
    f.add(1, "):")
    f.add(2, "assert_equal(index, 0)", "L")
    f.add(0, "")
    f.add(0, "def main() raises:")
    f.add(1, "simple()", "L", "main_start")
    f.add(1, "assert_equal(flow(0, False, False), 100)", "L", "main_flow")
    f.add(1, "assert_equal(flow(2, False, False), 123)", "L")
    f.add(1, "assert_equal(flow(2, True, False), 100)", "L")
    f.add(1, "assert_equal(flow(2, False, True), 1)", "L")
    f.add(1, "assert_equal(exit_else(0, False), 7)", "L")
    f.add(1, "assert_equal(exit_else(1, False), 9)", "L")
    f.add(1, "var caught = 0", "L")
    f.add(1, "try:", "L")
    f.add(2, "_ = exit_else(0, True)", "L")
    f.add(1, "except error:")
    f.add(2, 'assert_equal(String(error), "expected else")', "L")
    f.add(2, "caught += 1", "L")
    f.add(1, "try:", "L")
    f.add(2, "throw_body()", "L")
    f.add(1, "except error:")
    f.add(2, 'assert_equal(String(error), "expected body")', "L")
    f.add(2, "caught += 1", "L")
    f.add(1, "assert_equal(caught, 2)", "L")
    f.add(1, "literal_header()", "L")
    f.add(1, 'print("RESULT loops")', "L")
    var source = ending.join(f.rows) + (ending if final_newline else "")
    return (source^, f^)


def _list_text(items: List[String]) -> String:
    """Return a list of strings as Python's `repr` writes it."""
    var parts = List[String]()
    for item in items:
        parts.append(py_repr(item))
    return "[" + ", ".join(parts) + "]"


def check_records(raw: String, module: String, f: LoopFixture) raises:
    """Check a rewritten loop fixture's raw records.

    Args:
        raw: The rewritten program's standard error.
        module: The module name.
        f: The fixture's identities.

    Raises:
        Error: `AssertionError` if a record is not allowed, a loop's
            outcomes differ, or the first ten records differ.
    """
    var allowed = Set[String]()
    for line in f.lines:
        allowed.add("COVLINE:" + module + ":" + String(line))
    for decision in f.decisions:
        for outcome in ["T", "F"]:
            allowed.add(
                "COVLINE:" + module + ":" + String(decision[0]) + ":" + outcome
            )
    var records = split_lines(raw)
    var extra = List[String]()
    for row in records:
        if not row in allowed:
            var seen = False
            for item in extra:
                if item == row:
                    seen = True
            if not seen:
                extra.append(row)
    if len(extra) > 0:
        sort(extra)
        var parts = List[String]()
        for item in extra:
            parts.append(py_repr(item))
        require(False, "{" + ", ".join(parts) + "}")
    var by_line = Dict[Int, List[String]]()
    for row in records:
        var parts = row.split(":")
        if len(parts) == 4:
            var line = Int(String(parts[2]))
            if not line in by_line:
                by_line[line] = List[String]()
            by_line[line].append(String(parts[3]))
    var expected: List[Tuple[String, String]] = [
        ("simple", "TTT"),
        ("outer", "FTTTTTTT"),
        ("inner", "TTTTTTTTTTTT"),
        ("exit_else", "FTF"),
        ("throw_body", "T"),
        ("literal_header", "TT"),
    ]
    for entry in expected:
        var label = entry[0]
        var outcomes = entry[1]
        var found = by_line.get(f.labels[label]).or_else(List[String]())
        var want = List[String]()
        for byte in outcomes.as_bytes():
            want.append(chr(Int(byte)))
        var same = len(found) == len(want)
        if same:
            for index in range(len(want)):
                if found[index] != want[index]:
                    same = False
        require(
            same,
            "("
            + py_repr(label)
            + ", "
            + _list_text(found)
            + ", "
            + py_repr(outcomes)
            + ")",
        )
    # Pin the complete simple-loop stream, including line/branch interleaving.
    var prefix = "COVLINE:" + module + ":"
    var main_start = prefix + String(f.labels["main_start"])
    var simple_start = prefix + String(f.labels["simple_start"])
    var simple = prefix + String(f.labels["simple"])
    var simple_body = prefix + String(f.labels["simple_body"])
    var simple_end = prefix + String(f.labels["simple_end"])
    var main_flow = prefix + String(f.labels["main_flow"])
    var first: List[String] = [
        main_start,
        simple_start,
        simple,
        simple + ":T",
        simple_body,
        simple + ":T",
        simple_body,
        simple + ":T",
        simple_end,
        main_flow,
    ]
    var head = List[String]()
    for index in range(min(10, len(records))):
        head.append(records[index])
    var same = len(head) == len(first)
    if same:
        for index in range(len(first)):
            if head[index] != first[index]:
                same = False
    require(same, _list_text(head))


comptime Case = Tuple[Int, Int, String, Bool]
"""A fixture's indentation width and step, line ending, and whether its last
line ends."""


def cases() -> List[Case]:
    """Return the nine fixture cases, in order.

    Returns:
        The cases.
    """
    var result = List[Case]()
    var shapes: List[Tuple[Int, Int]] = [
        (1, 1),
        (2, 2),
        (3, 3),
        (4, 4),
        (8, 8),
        (2, 5),
    ]
    for shape in shapes:
        result.append((shape[0], shape[1], String("\n"), True))
    result.append((2, 2, String("\r\n"), True))
    result.append((2, 2, String("\r"), True))
    result.append((2, 2, String("\n"), False))
    return result^


def check_baseline(
    mojo: String,
    work: String,
    baseline: String,
    output: Optional[String],
) raises:
    """Check that a frozen rewriter fails on two natively valid sources.

    Args:
        mojo: The compiler.
        work: The work directory.
        baseline: The frozen `build_cli`, with an absolute path.
        output: The folder for the evidence files, or nothing.

    Raises:
        Error: If a native source fails, or a rewritten one compiles or
            fails without the expected diagnostic.
    """
    var native = work + "/native"
    var rewritten = work + "/rewritten"
    var controls: List[Tuple[String, String]] = [
        (
            "two_space",
            (
                "def main():\n  var total = 0\n  for index in range(2):\n "
                "   total += index\n  print(total)\n"
            ),
        ),
        (
            "four_space_else",
            (
                "def main():\n    for index in range(0):\n       "
                ' print(index)\n    else:\n        print("else")\n'
            ),
        ),
    ]
    for control in controls:
        var name = control[0]
        var source = control[1]
        write_text(native + "/" + name + ".mojo", source)
        _ = run_checked(
            [
                mojo,
                "build",
                "-Werror",
                native + "/" + name + ".mojo",
                "-o",
                native + "/" + name,
            ],
            BUILD_SECONDS,
        )
        var original = run_checked([native + "/" + name], SECONDS)
        _ = run_checked(
            [baseline, rewritten, name + ".mojo"], BUILD_SECONDS, native
        )
        var failed = run_program(
            [
                mojo,
                "build",
                "-Werror",
                rewritten + "/" + name + ".mojo",
                "-o",
                rewritten + "/" + name,
            ],
            BUILD_SECONDS,
            merge_errors=False,
        )
        var diagnostic_text = universal_newlines(failed.errors)
        require(failed.status != 0, name)
        var diagnostic = (
            "statement indentation must match" if name
            == "two_space" else "unexpected"
        )
        require(diagnostic_text.find(diagnostic) >= 0, diagnostic_text)
        if output:
            var folder = output.value()
            write_text(folder + "/baseline-" + name + "-native.mojo", source)
            write_text(
                folder + "/baseline-" + name + "-rewritten.mojo",
                read_text(rewritten + "/" + name + ".mojo"),
            )
            write_text(
                folder + "/baseline-" + name + "-diagnostic.txt",
                diagnostic_text,
            )
            write_text(
                folder + "/baseline-" + name + "-stdout.txt", original.output
            )


def check(
    mojo: String, output: Optional[String], baseline: Optional[String]
) raises:
    """Run every loop fixture natively and rewritten, and check the evidence.

    Args:
        mojo: The compiler, with an absolute path.
        output: The folder for the evidence files, or nothing.
        baseline: A frozen `build_cli` for the negative controls, or
            nothing.

    Raises:
        Error: If a build, a run or an expectation fails.
    """
    if output:
        makedirs(output.value(), exist_ok=True)
    var work = prepare_work("threemojo-loops-")
    try:
        var native = work + "/native"
        var rewritten = work + "/rewritten"
        build_rewriter(mojo, work)
        var all = cases()
        for number in range(len(all)):
            var width = all[number][0]
            var step = all[number][1]
            var ending = all[number][2]
            var module = (
                "loops_"
                + String(width)
                + "_"
                + String(step)
                + "_"
                + String(number)
            )
            var made = fixture(width, step, ending, all[number][3])
            var source = made[0]
            write_text(native + "/" + module + ".mojo", source)
            _ = run_checked(
                [work + "/build", rewritten, module + ".mojo"],
                BUILD_SECONDS,
                native,
            )
            var current_manifest = read_text(rewritten + "/manifest.txt")
            require(
                current_manifest
                == manifest(module, made[1].lines, made[1].decisions),
                current_manifest,
            )
            var results = List[ProcessResult]()
            for folder in [native, rewritten]:
                results.append(build_and_run(mojo, folder, module))
            require(
                results[0].output == results[1].output
                and results[1].output == "RESULT loops\n"
            )
            require(results[0].errors.byte_length() == 0)
            check_records(results[1].errors, module, made[1])
            var text = String(
                from_utf8_lossy=Path(
                    rewritten + "/" + module + ".mojo"
                ).read_bytes()
            )
            var literal: List[String] = [
                '"""literal\tvalue',
                "for fake in range(0):",
                "# ) and else:",
                'end"""',
            ]
            require(text.find(ending.join(literal)) >= 0)
            require(text.find('"""x' + ending + 'y"""') >= 0)
            require(
                text.find(
                    "#\tA comment left of both suites must not establish"
                    " indentation."
                )
                >= 0
            )
            if output:
                var folder = output.value()
                var stem = folder + "/" + module
                write_text(stem + "-manifest.txt", current_manifest)
                write_text(stem + "-raw.txt", results[1].errors)
                write_text(stem + "-native.mojo", source)
                write_text(stem + "-rewritten.mojo", text)
                write_text(stem + "-stdout.txt", results[0].output)
        if baseline:
            # Isolate the original two-space failure from the independent
            # else adjacency failure, using original sources already valid
            # natively.
            check_baseline(mojo, work, baseline.value(), output)
        print(PASS_TEXT)
    finally:
        remove_tree(work)


def main() raises:
    """Run the check, or print the help or a usage error.

    Raises:
        Error: If the check fails.
    """
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var command = parse_command_line(
        arguments,
        PROGRAM,
        USAGE,
        HELP,
        List[String](),
        ["--mojo", "--output", "--baseline-build"],
    )
    if command.status == -1:
        print(command.message, end="")
        exit(0)
    if command.status != 0:
        print(command.message, end="", file=stderr)
        exit(command.status)
    var mojo = absolute_path(
        command.value("--mojo", realpath(".") + "/.venv/bin/mojo")
    )
    var output = Optional[String]()
    if "--output" in command.values:
        output = normal_path(command.values["--output"])
    var baseline = Optional[String]()
    if "--baseline-build" in command.values:
        baseline = absolute_path(command.values["--baseline-build"])
    check(mojo, output, baseline)
