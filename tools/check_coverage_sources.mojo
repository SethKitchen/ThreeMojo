# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check inherited defaults and collision-safe probes with the native compiler.

    sh tools/tool.sh .venv/bin/mojo check_coverage_sources --mojo .venv/bin/mojo

The fixtures run with a strict five-second process limit. Manifest
expectations are independent of the scanner. Raw records check original
source identities, short-circuit order, exceptional abandonment, and
per-invocation buffers.

The tool works on the repository in the current directory. It builds
`coverage/build_cli.mojo`, rewrites each fixture with it, and builds and runs
the native and the rewritten fixture. `check_coverage_loops.mojo` uses the
same helpers.
"""

from std.os import listdir, makedirs, mkdir
from std.os.path import isdir, realpath
from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from tools._cli import absolute_path, normal_path, parse_command_line
from tools._process import ProcessResult, run_program
from tools._python_json import py_repr
from tools._text import split_lines

comptime SECONDS = 5.0
"""The time limit of one fixture program, in seconds."""
comptime BUILD_SECONDS = 3600.0
"""The time limit of one compilation or rewrite, in seconds."""
comptime PROGRAM = "check_coverage_sources.mojo"
"""The program name in usage messages."""
comptime USAGE = (
    "usage: check_coverage_sources.mojo [-h] [--mojo MOJO] [--output OUTPUT]\n"
)
"""The usage text, as `argparse` writes it."""
comptime HELP = (
    "\nCheck inherited defaults and collision-safe probes with the native"
    " compiler.\nThe fixtures run with a strict five-second process limit."
    " Manifest\nexpectations are independent of the scanner. Raw records"
    " check original source\nidentities, short-circuit order, exceptional"
    " abandonment, and per-invocation\nbuffers.\n\noptions:\n  -h, --help  "
    "     show this help message and exit\n  --mojo MOJO\n  --output OUTPUT\n"
)
"""The help text after the usage."""
comptime PASS_TEXT = (
    "PASS: trait-only imported module and inherited default exact L/B/C/M"
    " identities and full raw stream; abstract declarations, recursion,"
    " exceptions, nested generic callbacks, type and probe aliases, and"
    " exact loop-line collisions"
)
"""The line that a successful check prints."""

comptime DEFAULTS = '''"""Inherited bodies retain documentation."""
trait Choice:
    """One abstract requirement and a default."""
    def seed(self) -> Bool:
        """Implement this requirement."""
        ...  # abstract

    def choose(self, other: Bool) -> Bool:
        """Evaluate with a private invocation buffer."""
        if self.seed() and other:
            return True
        return False

@fieldwise_init
struct Default(Choice):
    var value: Bool
    def seed(self) -> Bool:
        return self.value

def main():
    var yes = Default(True)
    var no = Default(False)
    print(yes.choose(True), yes.choose(False), no.choose(True))
'''
"""The fixture with an inherited default method."""

comptime STRESS_TEMPLATE = """from std.testing import assert_equal

trait Inherited:
    def leaf(self, value: Bool, fail: Bool, mut order: String) raises -> Bool:
        order += "l"
        if fail:
            raise Error("expected")
        return value

    def choose(self, first: Bool, second: Bool, fail: Bool, mut order: String) raises -> Bool:
        if self.leaf(first, False, order) and self.leaf(second, fail, order):
            return True
        return False

    def recursive(self, depth: Int, mut order: String) -> Bool:
        order += "r"
        if depth > 0 and self.recursive(depth - 1, order):
            return True
        return False

    def nested(self) -> Bool:
        var List = 7
        var Int = 8
        var _cov_eval_buffer = True
        def inner(_cov_hit: Bool, _cov_branch: Bool) capturing -> Bool:
            if _cov_hit and _cov_branch:
                return True
            return False
        if invoke[inner]() and List == 7 and Int == 8 and _cov_eval_buffer:
            return True
        return False

struct Consumer(Inherited):
    def __init__(out self):
        pass

def invoke[_cov_branch: def(Bool, Bool) capturing[_] -> Bool]() -> Bool:
    if _cov_branch(True, False):
        return True
    return _cov_branch(True, True)

def legacy_collision() -> Int:
    var _cov_hit = 1
    var _cov_hit_ = 2
    var _cov_branch = 3
    var _cov_branch_ = 4
    var _cov_loop_LOOP = 40
    var _cov_loop__LOOP = 50
    for index in range(2):  # COLLIDING_LOOP
        if index > 0:
            _cov_hit += 1
    for index in range(0):
        _cov_branch += index
    return _cov_hit + _cov_hit_ + _cov_branch + _cov_branch_ + _cov_loop_LOOP + _cov_loop__LOOP

def main() raises:
    var value = Consumer()
    var order = String("")
    assert_equal(value.choose(False, True, False, order), False)
    assert_equal(order, "l")
    order = ""
    assert_equal(value.choose(True, False, False, order), False)
    assert_equal(order, "ll")
    order = ""
    assert_equal(value.choose(True, True, False, order), True)
    assert_equal(order, "ll")
    order = ""
    try:
        _ = value.choose(True, True, True, order)
    except error:
        order += "e"
    assert_equal(order, "lle")
    order = ""
    assert_equal(value.choose(True, False, False, order), False)
    assert_equal(order, "ll")
    order = ""
    assert_equal(value.recursive(3, order), False)
    assert_equal(order, "rrrr")
    assert_equal(value.nested(), True)
    assert_equal(legacy_collision(), 101)
    print("RESULT inherited defaults, exceptions, recursion, callbacks, collisions")
"""
"""The stress fixture, with `LOOP` in place of its colliding loop's line."""

comptime Decision = Tuple[Int, Int]
"""A decision's line and its number of conditions."""


# --- Python's meanings ---------------------------------------------------------


def require(condition: Bool, message: String = "") raises:
    """Fail as Python's `assert` fails.

    Args:
        condition: The value that must be true.
        message: The assertion message, or empty for none.

    Raises:
        Error: `AssertionError` and the message, if `condition` is false.
    """
    if not condition:
        if message.byte_length() > 0:
            raise Error("AssertionError: " + message)
        raise Error("AssertionError")


def count_of(text: String, part: String) -> Int:
    """Return the non-overlapping occurrences of a string, as `str.count`.

    Args:
        text: The text to search.
        part: A nonempty string.

    Returns:
        The number of occurrences.
    """
    var found = 0
    var at = text.find(part)
    while at >= 0:
        found += 1
        at = text.find(part, at + part.byte_length())
    return found


def line_of(text: String, marker: String) raises -> Int:
    """Return the first line that holds a marker, counted from 1.

    Args:
        text: The text.
        marker: The text to find.

    Returns:
        The line number.

    Raises:
        Error: `StopIteration` if no line holds the marker.
    """
    var number = 0
    for line in split_lines(text):
        number += 1
        if line.find(marker) >= 0:
            return number
    raise Error("StopIteration")


def universal_newlines(text: String) -> String:
    """Return text with CR LF and CR as LF, as Python's text mode reads it.

    Args:
        text: The text.

    Returns:
        The text with LF line endings only.
    """
    return text.replace("\r\n", "\n").replace("\r", "\n")


def read_text(path: String) raises -> String:
    """Read a file as `Path.read_text` does, with universal newlines.

    Args:
        path: The file.

    Returns:
        The text.

    Raises:
        Error: If the file cannot be read.
    """
    return universal_newlines(String(from_utf8_lossy=Path(path).read_bytes()))


def write_text(path: String, text: String) raises:
    """Write text to a file, unchanged.

    Args:
        path: The file.
        text: The text.

    Raises:
        Error: If the file cannot be written.
    """
    Path(path).write_bytes(text.as_bytes())


def command_text(command: List[String]) -> String:
    """Return a command as Python writes a list of strings.

    Args:
        command: The program and its arguments.

    Returns:
        The text, such as `['mojo', 'build']`.
    """
    var parts = List[String]()
    for word in command:
        parts.append(py_repr(word))
    return "[" + ", ".join(parts) + "]"


def _seconds(timeout: Float64) -> String:
    """Return a time limit as Python writes the number it was given."""
    if Float64(Int(timeout)) == timeout:
        return String(Int(timeout))
    return String(timeout)


def run_checked(
    command: List[String], timeout: Float64, directory: String = ""
) raises -> ProcessResult:
    """Run a program that must succeed, and keep its two output streams.

    Args:
        command: The program and its arguments.
        timeout: The time limit in seconds.
        directory: The working directory, or empty for the current one.

    Returns:
        The result. Its status is negative for a signal, as in Python, and
        its outputs have universal newlines.

    Raises:
        Error: If the program does not finish in time, or exits with a
            status other than 0.
    """
    var result = run_program(
        command, timeout, merge_errors=False, directory=directory
    )
    if result.timed_out:
        raise Error(
            "subprocess.TimeoutExpired: Command '"
            + command_text(command)
            + "' timed out after "
            + _seconds(timeout)
            + " seconds"
        )
    var status = result.status
    if status > 128:
        status = 128 - status
    var output = universal_newlines(result.output)
    var errors = universal_newlines(result.errors)
    if status != 0:
        raise Error(
            "RuntimeError: "
            + command_text(command)
            + ":\n"
            + output
            + "\n"
            + errors
        )
    return ProcessResult(status, output^, errors^, False)


def copy_tree(source: String, target: String) raises:
    """Copy a directory, without any entry named `build`.

    Args:
        source: The directory to copy.
        target: The new directory.

    Raises:
        Error: If a file cannot be read or written.
    """
    mkdir(target)
    var names = listdir(source)
    sort(names)
    for name in names:
        if name == "build":
            continue
        var path = source + "/" + name
        if isdir(path):
            copy_tree(path, target + "/" + name)
        else:
            Path(target + "/" + name).write_bytes(Path(path).read_bytes())


def remove_tree(path: String) raises:
    """Remove a directory and what it holds.

    Args:
        path: The directory.

    Raises:
        Error: If the shell cannot run.
    """
    _ = run_program(["rm", "-rf", path], 60)


def prepare_work(prefix: String) raises -> String:
    """Make a work directory with `native` and `rewritten` copies of the
    coverage package, and build the rewriter.

    Args:
        prefix: The temporary directory's name prefix.

    Returns:
        The work directory. The caller removes it.

    Raises:
        Error: If a copy fails.
    """
    var work = mkdtemp(prefix=prefix)
    var root = realpath(".")
    for folder in ["native", "rewritten"]:
        mkdir(work + "/" + folder)
        copy_tree(root + "/coverage", work + "/" + folder + "/coverage")
    return work


def build_rewriter(mojo: String, work: String) raises:
    """Build `coverage/build_cli.mojo` as `work/build`.

    Args:
        mojo: The compiler.
        work: The work directory.

    Raises:
        Error: If the build fails.
    """
    var root = realpath(".")
    _ = run_checked(
        [
            mojo,
            "build",
            "-Werror",
            "-I",
            root,
            root + "/coverage/build_cli.mojo",
            "-o",
            work + "/build",
        ],
        BUILD_SECONDS,
    )


def build_and_run(
    mojo: String, folder: String, module: String
) raises -> ProcessResult:
    """Build a fixture against its folder's coverage package, and run it.

    Args:
        mojo: The compiler.
        folder: The folder with the fixture and the coverage package.
        module: The fixture's module name.

    Returns:
        The result of the run.

    Raises:
        Error: If the build or the run fails, or the run is too slow.
    """
    var binary = folder + "/" + module
    _ = run_checked(
        [
            mojo,
            "build",
            "-Werror",
            "-I",
            folder,
            folder + "/" + module + ".mojo",
            "-o",
            binary,
        ],
        BUILD_SECONDS,
        folder,
    )
    return run_checked([binary], SECONDS)


# --- the expectations ----------------------------------------------------------


def colliding_loop() raises -> Int:
    """Return the line of the stress fixture's colliding loop.

    Returns:
        The line number.

    Raises:
        Error: If the fixture has no such loop.
    """
    return line_of(STRESS_TEMPLATE, "# COLLIDING_LOOP")


def stress_source() raises -> String:
    """Return the stress fixture with its loop line in place of `LOOP`.

    Returns:
        The source.

    Raises:
        Error: If the fixture has no colliding loop.
    """
    return String(STRESS_TEMPLATE).replace("LOOP", String(colliding_loop()))


def manifest(
    module: String, lines: List[Int], decisions: List[Decision]
) -> String:
    """Return the manifest the rewriter must write for a module.

    Args:
        module: The module name.
        lines: The executable lines.
        decisions: Each decision's line and number of conditions.

    Returns:
        The `L`, `B`, `C` and `M` rows, each with a newline.
    """
    var rows = List[String]()
    for line in lines:
        rows.append("L " + module + " " + String(line))
    for decision in decisions:
        var line = String(decision[0])
        rows.append("B " + module + " " + line)
        for slot in range(decision[1]):
            rows.append("C " + module + " " + line + " " + String(slot))
            rows.append("M " + module + " " + line + " " + String(slot))
    return "\n".join(rows) + "\n"


def default_records() -> String:
    """Return the exact raw records of the rewritten defaults fixture.

    Returns:
        The records, each with a newline.
    """
    var rows: List[String] = [
        "COVLINE:defaults:21",
        "COVLINE:defaults:22",
        "COVLINE:defaults:23",
    ]
    var cases: List[Tuple[String, String, String, Int]] = [
        ("T", "T", "T", 11),
        ("T", "F", "F", 12),
        ("F", "-", "F", 12),
    ]
    for case_ in cases:
        var first = case_[0]
        var second = case_[1]
        var answer = case_[2]
        rows.append("COVLINE:defaults:10")
        rows.append("COVLINE:defaults:18")
        rows.append("COVLINE:defaults:10.0:" + first)
        if second != "-":
            rows.append("COVLINE:defaults:10.1:" + second)
        rows.append("COVLINE:defaults:10:" + answer)
        rows.append(
            "COVEVAL2:defaults:10:" + answer + ":" + first + second + ";"
        )
        rows.append("COVLINE:defaults:" + String(case_[3]))
    return "\n".join(rows) + "\n"


def _records(
    rows: List[String], source: String, marker: String
) raises -> List[String]:
    """Return the evaluation vectors of the stress decision on a marked line."""
    var line = line_of(source, marker)
    var prefix = "COVEVAL2:stress:" + String(line) + ":"
    var found = List[String]()
    for row in rows:
        if row.startswith(prefix):
            found.append(String(row[byte = prefix.byte_length() :]))
    return found^


def _same(found: List[String], expected: List[String]) -> Bool:
    """Return whether two lists of strings are equal."""
    if len(found) != len(expected):
        return False
    for index in range(len(found)):
        if found[index] != expected[index]:
            return False
    return True


def check_stress(raw: String, text: String) raises:
    """Check the raw records and the rewritten text of the stress fixture.

    Args:
        raw: The rewritten program's standard error.
        text: The rewritten source.

    Raises:
        Error: `AssertionError` if a record or a probe name differs.
    """
    var loop = String(colliding_loop())
    var source = stress_source()
    var rows = split_lines(raw)
    require(
        _same(
            _records(rows, source, "if self.leaf("),
            ["F:F-;", "F:TF;", "T:TT;", "F:TF;"],
        )
    )
    require(
        _same(
            _records(rows, source, "if depth > 0"),
            ["F:F-;", "F:TF;", "F:TF;", "F:TF;"],
        )
    )
    require(
        _same(_records(rows, source, "if _cov_hit and"), ["F:TF;", "T:TT;"])
    )
    require(_same(_records(rows, source, "if invoke[inner]"), ["T:TTTT;"]))
    require(text.find("var _cov_loop___" + loop + " = 0") >= 0)
    require(text.find("hit as _cov_hit__, branch as _cov_branch__") >= 0)
    require(text.find("buffer as _cov_eval__buffer") >= 0)
    require(raw.find("COVLINE:stress:" + loop + ":T\n") >= 0)
    var empty = String(line_of(source, "range(0)"))
    require(raw.find("COVLINE:stress:" + empty + ":F\n") >= 0)
    # The throwing second operand never creates a leaf or complete vector.
    var choose = String(line_of(source, "if self.leaf("))
    require(count_of(raw, "COVLINE:stress:" + choose + ".0:T\n") == 4)
    require(count_of(raw, "COVLINE:stress:" + choose + ".1:T\n") == 1)
    require(count_of(raw, "COVLINE:stress:" + choose + ".1:F\n") == 2)


# --- the check -----------------------------------------------------------------


def check_trait_module(
    work: String,
    native: String,
    rewritten: String,
    mojo: String,
    output: Optional[String],
) raises:
    """Import a trait-only module without a later definition to add imports.

    Args:
        work: The work directory with the built rewriter.
        native: The folder of the native fixtures.
        rewritten: The folder of the rewritten fixtures.
        mojo: The compiler.
        output: The folder for the evidence files, or nothing.

    Raises:
        Error: If a build, a run or an expectation fails.
    """
    var marker = "@fieldwise_init"
    var at = String(DEFAULTS).find(marker)
    var source = String(String(DEFAULTS)[byte=:at])
    var consumer = (
        "from trait_only import Choice\n\n@fieldwise_init"
        + String(DEFAULTS)[byte = at + marker.byte_length() :]
    )
    write_text(native + "/trait_only.mojo", source)
    for folder in [native, rewritten]:
        write_text(folder + "/consumer.mojo", consumer)
    _ = run_checked(
        [work + "/build", rewritten, "trait_only.mojo"], BUILD_SECONDS, native
    )
    var text = read_text(rewritten + "/trait_only.mojo")
    var rows = split_lines(text)
    var original = split_lines(source)
    require(rows[0] == original[0])
    require(rows[1].startswith("from coverage.runtime import "))
    var current_manifest = read_text(rewritten + "/manifest.txt")
    require(current_manifest == manifest("trait_only", [10, 11, 12], [(10, 2)]))
    var results = List[ProcessResult]()
    for folder in [native, rewritten]:
        results.append(build_and_run(mojo, folder, "consumer"))
    require(
        results[0].output == results[1].output
        and results[1].output == "True False False\n"
    )
    require(results[0].errors.byte_length() == 0)
    # Caller and seed-method statements live in the unchanged consumer.
    var expected = String()
    for row in split_lines(default_records()):
        var skip = False
        for number in [18, 21, 22, 23]:
            if row == "COVLINE:defaults:" + String(number):
                skip = True
        if not skip:
            expected += row.replace(":defaults:", ":trait_only:") + "\n"
    require(results[1].errors == expected, results[1].errors)
    if output:
        var folder = output.value()
        write_text(folder + "/trait-only-manifest.txt", current_manifest)
        write_text(folder + "/trait-only-raw.txt", results[1].errors)
        write_text(folder + "/trait-only-native.mojo", source)
        write_text(folder + "/trait-only-rewritten.mojo", text)
        write_text(folder + "/trait-only-consumer.mojo", consumer)


def check(mojo: String, output: Optional[String]) raises:
    """Run every fixture natively and rewritten, and check the evidence.

    Args:
        mojo: The compiler, with an absolute path.
        output: The folder for the evidence files, or nothing.

    Raises:
        Error: If a build, a run or an expectation fails.
    """
    var work = prepare_work("threemojo-sources-")
    try:
        var native = work + "/native"
        var rewritten = work + "/rewritten"
        build_rewriter(mojo, work)
        var modules: List[Tuple[String, String]] = [
            ("defaults", String(DEFAULTS)),
            ("stress", stress_source()),
        ]
        for entry in modules:
            var module = entry[0]
            write_text(native + "/" + module + ".mojo", entry[1])
            _ = run_checked(
                [work + "/build", rewritten, module + ".mojo"],
                BUILD_SECONDS,
                native,
            )
            var current_manifest = read_text(rewritten + "/manifest.txt")
            if module == "defaults":
                require(
                    current_manifest
                    == manifest(
                        "defaults", [10, 11, 12, 18, 21, 22, 23], [(10, 2)]
                    ),
                    current_manifest,
                )
            var results = List[ProcessResult]()
            for folder in [native, rewritten]:
                results.append(build_and_run(mojo, folder, module))
            require(results[0].output == results[1].output)
            require(results[0].errors.byte_length() == 0)
            if module == "defaults":
                require(results[0].output == "True False False\n")
                require(
                    results[1].errors == default_records(), results[1].errors
                )
            else:
                check_stress(
                    results[1].errors,
                    read_text(rewritten + "/" + module + ".mojo"),
                )
            if output:
                var folder = output.value()
                makedirs(folder, exist_ok=True)
                write_text(
                    folder + "/" + module + "-manifest.txt", current_manifest
                )
                write_text(
                    folder + "/" + module + "-raw.txt", results[1].errors
                )
                for name in ["native", "rewritten"]:
                    Path(
                        folder + "/" + module + "-" + name + ".mojo"
                    ).write_bytes(
                        Path(
                            work + "/" + name + "/" + module + ".mojo"
                        ).read_bytes()
                    )
                write_text(
                    folder + "/" + module + "-stdout.txt", results[0].output
                )
        check_trait_module(work, native, rewritten, mojo, output)
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
        arguments, PROGRAM, USAGE, HELP, List[String](), ["--mojo", "--output"]
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
    check(mojo, output)
