# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check that a long format selection stays inside one shell argument.

    sh tools/tool.sh .venv/bin/mojo check_format_arguments

The old recipe put every path into one `/bin/sh -c` argument. Linux refuses
an argument of 32 pages. The current recipe gives the formatter at most 64
paths, and at most 8192 bytes of paths, in each call.
"""

from std.ffi import c_int, external_call
from std.sys import CompilationTarget

from tools._format_recipe import install_format_log, run_recipe
from tools._owned_process import SignalHold, spawn, wait_blocking


comptime _ARGUMENT_LIMIT = 131072
"""The Linux limit for one argument, in bytes: 32 pages of 4096 bytes."""

comptime _E2BIG = 7
"""The `errno` value for an argument list that is too long."""


def long_format_paths() -> List[String]:
    """Return 1789 long paths under `src/`.

    Returns:
        The paths, in index order.
    """
    var padding = String()
    for _ in range(67):
        padding += "x"
    var paths = List[String]()
    for index in range(1789):
        var digits = String(index)
        while digits.byte_length() < 4:
            digits = "0" + digits
        paths.append("src/" + digits + "_" + padding + ".mojo")
    return paths^


def repeated_shell_command(paths: List[String]) -> String:
    """Return the old recipe's shell command, twice.

    Args:
        paths: The selected paths, in order.

    Returns:
        The command the old copy loop and the old diff loop both expanded.
    """
    var body = String("for f in")
    for path in paths:
        body += " " + path
    body += "; do :; done; "
    return body + body


def _page_size() -> Int:
    """Return the system page size in bytes.

    Returns:
        The page size. Zero means `sysconf` failed.
    """
    comptime if CompilationTarget.is_linux():
        return Int(external_call["sysconf", Int](c_int(30)))
    else:
        return Int(external_call["sysconf", Int](c_int(29)))


def reject_oversized_shell_argument(command: String) raises:
    """Require Linux to refuse `command` as one shell argument.

    Other systems, and a page size other than 4096 bytes, skip the probe.
    The length check still applies on every system.

    Args:
        command: The shell command.

    Raises:
        Error: The command fits in one argument, or Linux starts it.
    """
    if command.byte_length() <= _ARGUMENT_LIMIT:
        raise Error("old format command fits in one shell argument")
    if not CompilationTarget.is_linux() or _page_size() != 4096:
        return
    try:
        var pid = spawn(["/bin/sh", "-c", command], SignalHold(), -1, True)
        _ = wait_blocking(pid)
        raise Error("oversized shell argument started")
    except error:
        var text = String(error)
        if text.find("Errno " + String(_E2BIG)) < 0:
            raise error


def _batch_bytes(paths: List[String]) -> Int:
    """Return the bytes of `paths` plus one separator for each path.

    Args:
        paths: One formatter call's paths.

    Returns:
        The byte count.
    """
    var size = 0
    for path in paths:
        size += path.byte_length() + 1
    return size


def check_long_format_batches() raises:
    """Require 1789 long paths to format in bounded batches.

    Raises:
        Error: The old command is accepted, or a batch exceeds its limit.
    """
    var paths = long_format_paths()
    var old = repeated_shell_command(paths)
    reject_oversized_shell_argument(old)
    install_format_log()
    var outcome = run_recipe(paths, limit=180)
    var text = outcome.result.output + outcome.result.errors
    if outcome.result.status != 0:
        raise Error(text)
    if len(outcome.selected) != len(paths):
        raise Error("format selection changed length")
    for index in range(len(paths)):
        if outcome.selected[index] != paths[index]:
            raise Error("format selection changed order")
    if len(outcome.calls) < 2:
        raise Error("format selection stayed in one call")
    for call in outcome.calls:
        if len(call) > 64:
            raise Error("format call has more than 64 paths")
        if _batch_bytes(call) > 8192:
            raise Error("format call exceeds 8192 path bytes")
    if not outcome.stamped:
        raise Error("format check left no stamp")


def main() raises:
    """Check the long format selection of this repository.

    Raises:
        Error: A batch exceeds its limit, or the old command is accepted.
    """
    check_long_format_batches()
    print("PASS: 1789 format paths")
