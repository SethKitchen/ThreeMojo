# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Run a program and keep its exit status, its output and a time limit.

`std.subprocess.run` returns the standard output only. A project tool must
also know the exit status, keep the standard error, and stop a program that
does not finish. `run_program` does all three with a short POSIX shell
script, so it works on Linux and on macOS:

- The program reads from `/dev/null`. Its standard output and standard
  error go to one file, in the order the program writes them.
- The shell starts the program with `exec`, so the process the timer kills
  is the program itself.
- A timer process sends `SIGKILL` when the limit passes, and leaves a mark
  file. A program that ends first stops the timer.

The output is decoded as UTF-8, with a replacement character for each
invalid byte.
"""

from std.os import listdir, remove, rmdir
from std.pathlib import Path
from std.subprocess import run
from std.tempfile import mkdtemp

# The characters that `shell_quote` can leave unquoted, as in Python's
# `shlex.quote`.
comptime _SAFE = (
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./-_"
)


def shell_quote(word: String) -> String:
    """Return `word` quoted for a POSIX shell.

    Args:
        word: One argument.

    Returns:
        `word` unchanged when it holds only safe characters, otherwise
        `word` in single quotes, with each single quote spelled `'"'"'`.
    """
    var safe = word.byte_length() > 0
    for byte in word.as_bytes():
        var found = False
        for allowed in _SAFE.as_bytes():
            if byte == allowed:
                found = True
                break
        if not found:
            safe = False
            break
    if safe:
        return word
    return "'" + word.replace("'", "'\"'\"'") + "'"


struct ProcessResult(Movable):
    """What a finished program left: its status and its output."""

    var status: Int
    """The exit status. A program killed by signal N has status 128 + N."""
    var output: String
    """The standard output and standard error, in the order written."""
    var timed_out: Bool
    """True when the time limit stopped the program."""

    def __init__(out self, status: Int, var output: String, timed_out: Bool):
        """Make a result.

        Args:
            status: The exit status.
            output: The combined output.
            timed_out: True when the time limit stopped the program.
        """
        self.status = status
        self.output = output^
        self.timed_out = timed_out


def _remove_tree(directory: String) raises:
    """Remove a flat temporary directory and its files."""
    for name in listdir(directory):
        remove(Path(directory) / name)
    rmdir(directory)


def run_program(
    arguments: List[String], timeout: Float64
) raises -> ProcessResult:
    """Run a program to its end or to its time limit.

    Args:
        arguments: The program and its arguments. The first is found on
            `PATH` when it has no slash.
        timeout: The time limit in seconds.

    Returns:
        The exit status, the combined output, and whether the time limit
        stopped the program.

    Raises:
        Error: If `arguments` is empty, the time limit is not positive, or
            the shell cannot start or report a status.
    """
    if len(arguments) == 0:
        raise Error("run_program needs a program")
    if not timeout > 0:
        raise Error("run_program needs a positive time limit")
    var directory = mkdtemp(prefix="threemojo-process-")
    try:
        var output = directory + "/output"
        var command = String("exec")
        for argument in arguments:
            command += " " + shell_quote(argument)
        var script = (
            "out="
            + shell_quote(output)
            + "\n( "
            + command
            + ' ) </dev/null >"$out" 2>&1 &\n'
            + "pid=$!\n"
            + "( trap 'kill \"$s\" 2>/dev/null; exit 0' TERM\n"
            + "  sleep "
            + String(timeout)
            + " & s=$!\n"
            + '  wait "$s"\n'
            + '  kill -KILL "$pid" 2>/dev/null && : >"$out.timeout"\n'
            # The timer must not hold the pipe that returns the status.
            + ") </dev/null >/dev/null 2>&1 &\n"
            + "w=$!\n"
            + 'wait "$pid"; rc=$?\n'
            + 'kill "$w" 2>/dev/null; wait "$w" 2>/dev/null\n'
            + "printf '%d' \"$rc\"\n"
        )
        var reported = run("sh -c " + shell_quote(script))
        var status = Int(reported)
        var bytes = Path(output).read_bytes()
        var timed_out = Path(output + ".timeout").exists()
        return ProcessResult(status, String(from_utf8_lossy=bytes), timed_out)
    finally:
        _remove_tree(directory)
