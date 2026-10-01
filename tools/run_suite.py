# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
"""Run a built test suite and fail every test that takes too long.

    python3 tools/run_suite.py --seconds 5 --suite tests/test_a.mojo \\
        -- .cache/bin/test_a

runs the program, passes its output through, and exits with an error when
one test took longer than `--seconds`. A slow test is a slow library: make
the code under test faster, not the test smaller.

The limit applies to each test and not to the suite. `TestSuite` holds all
of its output until the program exits, through a pipe and a terminal alike,
so nothing can see one test end while the suite runs. The check therefore
has three parts:

- After the suite exits, its header, result records and summary must agree.
  A zero exit code without complete test results is not a pass.
- Every result line gives the test's time in
  milliseconds. A time over the limit fails that test.
- While the suite runs, a hung test never gets to report. The program is
  stopped when it runs longer than the limit multiplied by the number of
  tests in the suite, plus one limit for startup. No suite of fast tests
  can reach that.
"""

import argparse
from collections import Counter
import re
import subprocess
import sys

from test_environment import isolated_environment

# `PASS [ 2000.245 ] test_name`, after the color codes are removed.
TIME = r"[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?"
RESULT = re.compile(r"^\s*(PASS|FAIL|SKIP)\s*\[\s*(" + TIME + r")\s*\]\s*(\S+)")
HEADER = re.compile(r"^\s*Running\s+(\d+)\s+tests?\s+for\s+.+?\s*$")
SUMMARY = re.compile(
    r"^\s*Summary\s*\[\s*" + TIME + r"\s*\]\s*"
    r"(\d+)\s+tests?\s+run:\s*(\d+)\s+passed\s*,\s*"
    r"(\d+)\s+failed\s*,\s*(\d+)\s+skipped\s*$")
COLOR = re.compile(r"\x1b\[[0-9;]*m")
# `TestSuite.discover_tests` runs every function whose name starts `test_`.
TEST = re.compile(r"^def\s+test_\w*\s*\(", re.MULTILINE)
# The exit code of `timeout(1)`, so a stopped suite reads the same way.
TIMED_OUT = 124


def count_tests(text):
    """Return the number of test functions that `text` defines."""
    return len(TEST.findall(text))


def slow_tests(output, seconds):
    """Return (name, seconds) for each result in `output` over the limit."""
    slow = []
    for line in COLOR.sub("", output).splitlines():
        match = RESULT.match(line)
        if match and float(match.group(2)) / 1000.0 > seconds:
            slow.append((match.group(3), float(match.group(2)) / 1000.0))
    return slow


def result_errors(output):
    """Return errors unless one complete TestSuite run reports no failures.

    Runtime counts are authoritative. The source-text count is only a hang
    budget estimate; imported or generated tests can change the actual count.
    Diagnostic output, including device-skip notices, is left uninterpreted.
    """
    headers, summaries = [], []
    header_lines, summary_lines, result_lines = [], [], []
    results = Counter()
    errors = []
    for number, line in enumerate(COLOR.sub("", output).splitlines()):
        if match := HEADER.fullmatch(line):
            headers.append(int(match.group(1)))
            header_lines.append(number)
        if match := SUMMARY.fullmatch(line):
            summaries.append(tuple(map(int, match.groups())))
            summary_lines.append(number)
        if match := RESULT.match(line):
            results[match.group(1)] += 1
            result_lines.append(number)
    if results['FAIL']:
        errors.append('one or more test results report FAIL')
    if len(headers) != 1 or len(summaries) != 1:
        errors.append('expected one complete TestSuite header and summary')
        return errors
    if (header_lines[0] >= summary_lines[0]
            or any(not header_lines[0] < n < summary_lines[0] for n in result_lines)):
        errors.append('test result records are outside the run header and summary')
    total, passed, failed, skipped = summaries[0]
    if total <= 0:
        errors.append('the suite reported no tests')
    if headers[0] != total:
        errors.append('the run header and summary test counts differ')
    if passed + failed + skipped != total:
        errors.append('the summary totals do not add up')
    if (results['PASS'], results['FAIL'], results['SKIP']) != (passed, failed, skipped):
        errors.append('test result records do not match the summary totals')
    if failed:
        errors.append('the summary reports failed tests')
    return errors


def budget(seconds, tests):
    """Return the seconds a suite of `tests` tests can run before a hang."""
    return seconds * (max(tests, 1) + 1)


def main(argv):
    """Run the suite, and return its exit code or the failure's."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--seconds", type=float, required=True)
    parser.add_argument("--suite", required=True)
    parser.add_argument("command", nargs="+")
    args = parser.parse_args(argv)
    with open(args.suite, encoding="utf-8") as source:
        limit = budget(args.seconds, count_tests(source.read()))
    try:
        with isolated_environment() as environment:
            run = subprocess.run(
                args.command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL,
                timeout=limit,
                env=environment,
            )
    except subprocess.TimeoutExpired as expired:
        if expired.output:
            sys.stdout.write(expired.output.decode("utf-8", "replace"))
        print(
            f"{args.suite}: stopped after {limit:g}s. A test hangs or takes "
            f"longer than {args.seconds:g}s."
        )
        return TIMED_OUT
    output = run.stdout.decode("utf-8", "replace")
    sys.stdout.write(output)
    slow = slow_tests(output, args.seconds)
    for name, took in slow:
        print(
            f"{args.suite}: {name} took {took:.2f}s, over the "
            f"{args.seconds:g}s limit for one test."
        )
    if run.returncode != 0:
        return run.returncode
    errors = result_errors(output)
    for error in errors:
        print(f"{args.suite}: invalid test results: {error}.")
    return 1 if slow or errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
