# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Run a built test suite and fail every test that takes too long.

    run_suite --seconds 5 --suite tests/test_a.mojo -- .cache/bin/test_a
    run_suite --results-only --suite tests/test_a.mojo -- PROGRAM...

runs the program, passes its output through, and exits with an error when
one test took longer than `--seconds`. A slow test is a slow library: make
the code under test faster, not the test smaller.

The GPU Make targets use `--results-only`. It checks the same output, and
the caller keeps its own time limit.

The limit applies to each test and not to the suite. `TestSuite` holds all
of its output until the program exits, so nothing can see one test end
while the suite runs. The check therefore has three parts:

- After the suite exits, its header, result records and summary must agree.
  A zero exit code without complete test results is not a pass.
- Every result line gives the test's time in milliseconds. A time over the
  limit fails that test.
- While the suite runs, a hung test never gets to report. The program is
  stopped when it runs longer than the limit multiplied by the number of
  tests in the suite, plus one limit for startup. No suite of fast tests
  can reach that.

Each run gets a private temporary directory, in `TMPDIR` when it is set.
The program sees it as `TMPDIR` and as `THREEMOJO_TEST_TMPDIR`, and the tool
removes it after any outcome.
"""

from std.os import getenv
from std.os.path import realpath
from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from tools._process import run_program
from tools._text import split_lines

comptime TIMED_OUT = 124
"""The exit status of `timeout(1)`, so a stopped suite reads the same way."""


def _is_space(byte: UInt8) -> Bool:
    """Return whether a byte is white space, as regular expressions see it."""
    return (
        byte == 32 or (byte >= 9 and byte <= 13) or (byte >= 28 and byte <= 31)
    )


def _is_digit(byte: UInt8) -> Bool:
    """Return whether a byte is a decimal digit."""
    return byte >= 48 and byte <= 57


struct _Cursor:
    """A position in one line, for the small patterns of `TestSuite` output."""

    var text: String
    var at: Int

    def __init__(out self, text: String):
        self.text = text
        self.at = 0

    def done(self) -> Bool:
        return self.at >= self.text.byte_length()

    def peek(self) -> UInt8:
        return self.text.as_bytes()[self.at] if not self.done() else 0

    def spaces(mut self) -> Int:
        """Skip white space, and return how much there was."""
        var start = self.at
        while not self.done() and _is_space(self.peek()):
            self.at += 1
        return self.at - start

    def word(mut self, word: String) -> Bool:
        """Take `word` when it comes next."""
        if self.text.find(word, self.at) == self.at:
            self.at += word.byte_length()
            return True
        return False

    def digits(mut self) -> String:
        """Take one or more decimal digits, or nothing."""
        var start = self.at
        while not self.done() and _is_digit(self.peek()):
            self.at += 1
        return String(self.text[byte = start : self.at])

    def time(mut self) -> String:
        """Take a time: digits, an optional fraction and an exponent."""
        var start = self.at
        if self.digits().byte_length() == 0:
            self.at = start
            return String()
        if self.peek() == 46:
            var dot = self.at
            self.at += 1
            if self.digits().byte_length() == 0:
                self.at = dot
        var mark = self.at
        if self.peek() == 101 or self.peek() == 69:
            self.at += 1
            if self.peek() == 43 or self.peek() == 45:
                self.at += 1
            if self.digits().byte_length() == 0:
                self.at = mark
        return String(self.text[byte = start : self.at])


def strip_color(text: String) -> String:
    """Remove terminal color codes: escape, `[`, digits and `;`, then `m`.

    Args:
        text: Program output.

    Returns:
        The text without color codes.
    """
    var out = String()
    var bytes = text.as_bytes()
    var start = 0
    var index = 0
    while index < len(bytes):
        if (
            bytes[index] == 27
            and index + 1 < len(bytes)
            and bytes[index + 1] == 91
        ):
            var end = index + 2
            while end < len(bytes) and (
                _is_digit(bytes[end]) or bytes[end] == 59
            ):
                end += 1
            if end < len(bytes) and bytes[end] == 109:
                out += String(text[byte=start:index])
                index = end + 1
                start = index
                continue
        index += 1
    out += String(text[byte=start:])
    return out^


struct Result(Copyable, Movable):
    """One `PASS`, `FAIL` or `SKIP` record."""

    var status: String
    """`PASS`, `FAIL` or `SKIP`."""
    var milliseconds: Float64
    """The test's time."""
    var name: String
    """The test's name."""

    def __init__(out self, status: String, milliseconds: Float64, name: String):
        """Make a record.

        Args:
            status: `PASS`, `FAIL` or `SKIP`.
            milliseconds: The test's time.
            name: The test's name.
        """
        self.status = status
        self.milliseconds = milliseconds
        self.name = name


def parse_result(line: String) -> Optional[Result]:
    """Read `PASS [ 2000.245 ] test_name` at the start of a line.

    Args:
        line: One line without color codes.

    Returns:
        The record, or nothing when the line is not one.
    """
    var cursor = _Cursor(line)
    _ = cursor.spaces()
    var status = String()
    for word in ["PASS", "FAIL", "SKIP"]:
        if cursor.word(word):
            status = word
            break
    if not status:
        return None
    _ = cursor.spaces()
    if not cursor.word("["):
        return None
    _ = cursor.spaces()
    var time = cursor.time()
    if not time:
        return None
    _ = cursor.spaces()
    if not cursor.word("]"):
        return None
    _ = cursor.spaces()
    var start = cursor.at
    while not cursor.done() and not _is_space(cursor.peek()):
        cursor.at += 1
    if cursor.at == start:
        return None
    try:
        return Result(
            status, Float64(time), String(line[byte = start : cursor.at])
        )
    except:
        return None


def parse_header(line: String) -> Int:
    """Read the whole line `Running N tests for SUITE`.

    Args:
        line: One line without color codes.

    Returns:
        N, or -1 when the line is not a header.
    """
    var cursor = _Cursor(line)
    _ = cursor.spaces()
    if not cursor.word("Running") or cursor.spaces() == 0:
        return -1
    var count = cursor.digits()
    if not count or cursor.spaces() == 0 or not cursor.word("test"):
        return -1
    _ = cursor.word("s")
    if cursor.spaces() == 0 or not cursor.word("for") or cursor.spaces() == 0:
        return -1
    if cursor.done():
        return -1
    try:
        return Int(count)
    except:
        return -1


def parse_summary(line: String) -> List[Int]:
    """Read the whole line `Summary [ T ] N tests run: P passed , F failed ,
    S skipped`.

    Args:
        line: One line without color codes.

    Returns:
        N, P, F and S, or nothing when the line is not a summary.
    """
    var none = List[Int]()
    var cursor = _Cursor(line)
    _ = cursor.spaces()
    if not cursor.word("Summary"):
        return none^
    _ = cursor.spaces()
    if not cursor.word("["):
        return none^
    _ = cursor.spaces()
    if not cursor.time():
        return none^
    _ = cursor.spaces()
    if not cursor.word("]"):
        return none^
    _ = cursor.spaces()
    var values = List[String]()
    values.append(cursor.digits())
    if not values[0] or cursor.spaces() == 0 or not cursor.word("test"):
        return none^
    _ = cursor.word("s")
    if cursor.spaces() == 0 or not cursor.word("run:"):
        return none^
    for word in ["passed", "failed", "skipped"]:
        _ = cursor.spaces()
        var number = cursor.digits()
        if not number or cursor.spaces() == 0 or not cursor.word(word):
            return none^
        values.append(number)
        _ = cursor.spaces()
        if word != "skipped" and not cursor.word(","):
            return none^
    if not cursor.done():
        return none^
    var numbers = List[Int]()
    for value in values:
        try:
            numbers.append(Int(value))
        except:
            return none^
    return numbers^


def count_tests(text: String) -> Int:
    """Return the number of test functions a suite defines.

    `TestSuite.discover_tests` runs every top-level function whose name
    starts with `test_`.

    Args:
        text: The suite's source.

    Returns:
        The number of lines that start `def test_NAME(`.
    """
    var count = 0
    for line in split_lines(text):
        var cursor = _Cursor(line)
        if (
            not cursor.word("def")
            or cursor.spaces() == 0
            or not cursor.word("test_")
        ):
            continue
        while not cursor.done():
            var byte = cursor.peek()
            if not (
                _is_digit(byte)
                or (byte >= 65 and byte <= 90)
                or (byte >= 97 and byte <= 122)
                or byte == 95
                or byte >= 128
            ):
                break
            cursor.at += 1
        _ = cursor.spaces()
        if cursor.word("("):
            count += 1
    return count


def slow_tests(output: String, seconds: Float64) -> List[Result]:
    """Return each result over the limit.

    Args:
        output: The suite's output.
        seconds: The limit for one test.

    Returns:
        The records whose time is over the limit.
    """
    var slow = List[Result]()
    for line in split_lines(strip_color(output)):
        var result = parse_result(line)
        if result and result.value().milliseconds / 1000.0 > seconds:
            slow.append(result.value().copy())
    return slow^


def result_errors(output: String) -> List[String]:
    """Return errors unless one complete `TestSuite` run reports no failure.

    The counts the suite reports are the authority. The count of test
    functions in the source is only for the hang limit: imported tests can
    change the real count. Other lines, such as a device-skip notice, are not
    read.

    Args:
        output: The suite's output.

    Returns:
        One line for each problem, or none.
    """
    var headers = List[Int]()
    var header_lines = List[Int]()
    var summaries = List[List[Int]]()
    var summary_lines = List[Int]()
    var result_lines = List[Int]()
    var passed_records = 0
    var failed_records = 0
    var skipped_records = 0
    var errors = List[String]()
    var number = 0
    for line in split_lines(strip_color(output)):
        var header = parse_header(line)
        if header >= 0:
            headers.append(header)
            header_lines.append(number)
        var summary = parse_summary(line)
        if len(summary) > 0:
            summaries.append(summary^)
            summary_lines.append(number)
        var result = parse_result(line)
        if result:
            var status = result.value().status
            if status == "PASS":
                passed_records += 1
            elif status == "FAIL":
                failed_records += 1
            else:
                skipped_records += 1
            result_lines.append(number)
        number += 1
    if failed_records > 0:
        errors.append("one or more test results report FAIL")
    if len(headers) != 1 or len(summaries) != 1:
        errors.append("expected one complete TestSuite header and summary")
        return errors^
    var outside = header_lines[0] >= summary_lines[0]
    for line in result_lines:
        if not (header_lines[0] < line and line < summary_lines[0]):
            outside = True
    if outside:
        errors.append(
            "test result records are outside the run header and summary"
        )
    var total = summaries[0][0]
    var passed = summaries[0][1]
    var failed = summaries[0][2]
    var skipped = summaries[0][3]
    if total <= 0:
        errors.append("the suite reported no tests")
    if headers[0] != total:
        errors.append("the run header and summary test counts differ")
    if passed + failed + skipped != total:
        errors.append("the summary totals do not add up")
    if (
        passed_records != passed
        or failed_records != failed
        or skipped_records != skipped
    ):
        errors.append("test result records do not match the summary totals")
    if failed > 0:
        errors.append("the summary reports failed tests")
    return errors^


def budget(seconds: Float64, tests: Int) -> Float64:
    """Return the seconds a suite can run before it counts as hung.

    Args:
        seconds: The limit for one test.
        tests: The number of tests.

    Returns:
        The limit times one more than the number of tests, at least two.
    """
    return seconds * Float64(max(tests, 1) + 1)


def general(value: Float64) -> String:
    """Write a number as Python's `{:g}` does for the limits used here.

    Args:
        value: The number.

    Returns:
        An integral value without a fraction, otherwise the shortest form.
    """
    if value == value.__floor__() and abs(value) < 1e15:
        return String(Int(value))
    return String(value)


def fixed(value: Float64) -> String:
    """Write a non-negative number with two decimals, rounded.

    Args:
        value: The number.

    Returns:
        The text, as `{:.2f}` writes it.
    """
    var hundredths = Int(value * 100.0 + 0.5)
    var fraction = String(hundredths % 100)
    if hundredths % 100 < 10:
        fraction = "0" + fraction
    return String(hundredths // 100) + "." + fraction


struct Options(Movable):
    """The parsed command line."""

    var seconds: Float64
    """The limit for one test, or a negative value with `--results-only`."""
    var suite: String
    """The suite's source."""
    var command: List[String]
    """The program and its arguments."""

    def __init__(out self):
        """Start empty."""
        self.seconds = -1
        self.suite = String()
        self.command = List[String]()


def parse_options(arguments: List[String]) raises -> Options:
    """Parse the arguments after the program name.

    Args:
        arguments: The arguments.

    Returns:
        The options.

    Raises:
        Error: Unless exactly one of `--seconds` and `--results-only`, a
            `--suite`, and a program are given.
    """
    var options = Options()
    var modes = 0
    var index = 0
    while index < len(arguments):
        var argument = arguments[index]
        if argument == "--":
            for rest in range(index + 1, len(arguments)):
                options.command.append(arguments[rest])
            break
        if argument == "--results-only":
            modes += 1
        elif (
            argument == "--seconds" or argument == "--suite"
        ) and index + 1 < len(arguments):
            index += 1
            if argument == "--suite":
                options.suite = arguments[index]
            else:
                modes += 1
                options.seconds = Float64(arguments[index])
                if not options.seconds >= 0:
                    raise Error("--seconds must not be negative")
        elif argument.startswith("-"):
            raise Error("unknown option: " + argument)
        else:
            options.command.append(argument)
        index += 1
    if modes != 1:
        raise Error("give one of --seconds and --results-only")
    if not options.suite or len(options.command) == 0:
        raise Error("give --suite and a program")
    return options^


def run(options: Options) raises -> Tuple[Int, String]:
    """Run the suite, and return its exit status and the tool's output.

    Args:
        options: The parsed command line.

    Returns:
        The suite's status or the failure's, and its output followed by
        the tool's own lines.

    Raises:
        Error: If the suite's source or the temporary directory cannot be
            used.
    """
    var results_only = options.seconds < 0
    var limit: Float64
    if not results_only:
        limit = budget(
            options.seconds, count_tests(Path(options.suite).read_text())
        )
    else:
        # The caller owns the time limit; this one only stops a runaway.
        limit = 365.0 * 24.0 * 3600.0
    var parent = getenv("TMPDIR")
    var folder: String
    if parent:
        folder = mkdtemp(prefix="threemojo-test-", dir=parent)
    else:
        folder = mkdtemp(prefix="threemojo-test-")
    var root = realpath(folder)
    var command: List[String] = [
        "env",
        "THREEMOJO_TEST_TMPDIR=" + root,
        "TMPDIR=" + root,
    ]
    command.extend(options.command.copy())
    var outcome: Tuple[Int, String]
    try:
        var result = run_program(command, limit)
        var text = result.output
        if result.timed_out:
            text += (
                options.suite
                + ": stopped after "
                + general(limit)
                + "s. A test hangs or takes longer than "
                + general(options.seconds)
                + "s.\n"
            )
            outcome = (TIMED_OUT, text^)
        else:
            var failed = False
            if not results_only:
                for slow in slow_tests(result.output, options.seconds):
                    text += (
                        options.suite
                        + ": "
                        + slow.name
                        + " took "
                        + fixed(slow.milliseconds / 1000.0)
                        + "s, over the "
                        + general(options.seconds)
                        + "s limit for one test.\n"
                    )
                    failed = True
            if result.status != 0:
                outcome = (result.status, text^)
            else:
                for error in result_errors(result.output):
                    text += (
                        options.suite
                        + ": invalid test results: "
                        + error
                        + ".\n"
                    )
                    failed = True
                outcome = (1 if failed else 0, text^)
    finally:
        _ = run_program(["rm", "-rf", "--", folder], 60)
    return outcome^


def main() raises:
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var options: Options
    try:
        options = parse_options(arguments)
    except error:
        print("run_suite:", error, file=stderr)
        exit(2)
        return
    var outcome = run(options)
    print(outcome[1], end="")
    exit(outcome[0])
