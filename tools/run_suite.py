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
has two parts:

- After the suite exits, every result line gives the test's time in
  milliseconds. A time over the limit fails that test.
- While the suite runs, a hung test never gets to report. The program is
  stopped when it runs longer than the limit multiplied by the number of
  tests in the suite, plus one limit for startup. No suite of fast tests
  can reach that.
"""

import argparse
import re
import subprocess
import sys

from test_environment import isolated_environment

# `PASS [ 2000.245 ] test_name`, after the color codes are removed.
RESULT = re.compile(r"^\s*(PASS|FAIL|SKIP)\s*\[\s*([0-9.]+)\s*\]\s*(\S+)")
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
    return 1 if slow else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
