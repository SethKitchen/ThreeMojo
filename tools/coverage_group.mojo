# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Give one coverage command a shared deadline, then run it.

    coverage_group --seconds N -- COMMAND...

The deadline is `N` seconds from now, or sooner when
`THREEMOJO_COVERAGE_DEADLINE` is already set. The command inherits that
deadline. A real-time alarm stops it when the time is gone. A deadline
that has already passed exits 124.
"""

from std.ffi import c_int, external_call
from std.math import isinf, isnan
from std.os import getenv, setenv
from std.sys import argv, exit, stderr

from tools._owned_process import ExecPlan, python_monotonic
from tools._python_float import parse_float, python_repr

comptime DEADLINE_ENV = "THREEMOJO_COVERAGE_DEADLINE"
comptime ITIMER_REAL = 0


def run_group(seconds: Float64, command: List[String]) raises:
    """Start `command` with one coverage deadline.

    Args:
        seconds: The budget in seconds. It must be positive and finite.
        command: The program and its arguments.

    Raises:
        Error: If the budget is not positive, an inherited deadline is
            not a finite number, or the program cannot start.
    """
    if isnan(seconds) or isinf(seconds) or not seconds > 0:
        raise Error("coverage budget must be positive and finite")
    if len(command) == 0:
        raise Error("coverage group needs a command")
    var now = _monotonic()
    var deadline = now + seconds
    var inherited = getenv(DEADLINE_ENV, "")
    if inherited.byte_length() > 0:
        var earlier = parse_float(inherited)
        if isnan(earlier) or isinf(earlier):
            raise Error("coverage deadline must be finite")
        if earlier < deadline:
            deadline = earlier
    var remaining = deadline - _monotonic()
    if not remaining > 0:
        exit(124)
    _ = setenv(DEADLINE_ENV, python_repr(deadline), True)
    # A new process already uses the default SIGALRM action, which ends it.
    _arm(remaining)
    var plan = ExecPlan(command)
    var failed = plan.run()
    raise Error("cannot run " + command[0] + " (errno " + String(failed) + ")")


def _monotonic() -> Float64:
    """Return seconds from the clock that `time.monotonic` reads."""
    return python_monotonic()


def _arm(seconds: Float64):
    """Start a real-time alarm, as `signal.setitimer` does."""
    var whole = Int(seconds)
    if Float64(whole) > seconds:
        whole -= 1
    if whole < 0:
        whole = 0
    var usec = Int((seconds - Float64(whole)) * 1000000.0)
    if usec < 0:
        usec = 0
    if usec > 999999:
        usec = 999999
    if whole == 0 and usec == 0:
        usec = 1
    var spec = List[Int64](length=4, fill=0)
    var previous = List[Int64](length=4, fill=0)
    spec[2] = Int64(whole)
    spec[3] = Int64(usec)
    _ = external_call["setitimer", Int32](
        Int32(ITIMER_REAL),
        spec.unsafe_ptr().unsafe_bitcast[NoneType](),
        previous.unsafe_ptr().unsafe_bitcast[NoneType](),
    )


def _seconds(text: String) raises -> Float64:
    """Return a decimal budget."""
    return parse_float(text)


def main() raises:
    """Run the command after `--` under the coverage deadline.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    var seconds = Float64(-1)
    var command = List[String]()
    var index = 1
    var after = False
    while index < len(arguments):
        var word = String(arguments[index])
        if after:
            command.append(word)
            index += 1
            continue
        if word == "--":
            after = True
            index += 1
            continue
        if word == "--seconds":
            if index + 1 >= len(arguments):
                print(
                    "usage: coverage_group --seconds N -- COMMAND...",
                    file=stderr,
                )
                exit(2)
            seconds = _seconds(String(arguments[index + 1]))
            index += 2
            continue
        print("usage: coverage_group --seconds N -- COMMAND...", file=stderr)
        exit(2)
    if not after or not seconds > 0:
        print("usage: coverage_group --seconds N -- COMMAND...", file=stderr)
        exit(2)
    try:
        run_group(seconds, command)
    except error:
        print("coverage_group:", error, file=stderr)
        exit(1)
