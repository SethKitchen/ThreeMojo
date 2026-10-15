# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Run a copied Makefile recipe in a fixture, without an outer make's flags.

The suites that check the Makefile's recipes copy a recipe into a small
project and run `make` there. A shell script stands in for the compiler. It
writes each call's arguments as one line of `invocations`, separated by the
unit separator, so an argument can hold a space or a quote.
"""

from std.pathlib import Path

comptime MAKE_ENVIRONMENT = [
    "MAKEFLAGS",
    "MFLAGS",
    "MAKEOVERRIDES",
    "MAKELEVEL",
    "MAKEFILES",
    "GNUMAKEFLAGS",
]
"""The variables an outer make passes to a recursive one."""

comptime OUTER_OVERRIDES = [
    "MAKEFLAGS=-- MOJO=nonexistent-outer-compiler",
    "MAKEOVERRIDES=MOJO=nonexistent-outer-compiler",
    "MFLAGS=-e",
    "GNUMAKEFLAGS=-e",
    "MAKEFILES=nonexistent-outer-include",
    "MAKELEVEL=7",
]
"""Outer make settings that must not replace a fixture's compiler."""

comptime LOG_ARGUMENTS = (
    "line=$(printf '%s\\037' \"$@\")\n"
    + "printf '%s\\n' \"$line\" >> invocations\n"
)
"""Shell lines that append the script's arguments to `invocations`."""


def clean_command(
    settings: List[String], command: List[String], outer: Bool = False
) -> List[String]:
    """Return a command that runs without an outer make's variables.

    Args:
        settings: `NAME=VALUE` words to set for the command.
        command: The program and its arguments.
        outer: True to set `OUTER_OVERRIDES` first, as an outer make would.

    Returns:
        An `env` command line.
    """
    var words: List[String] = ["env"]
    if outer:
        for word in materialize[OUTER_OVERRIDES]():
            words.append(word)
        words.append("env")
    for name in materialize[MAKE_ENVIRONMENT]():
        words.append("-u")
        words.append(name)
    words.extend(settings.copy())
    words.extend(command.copy())
    return words^


def read_calls(path: String) raises -> List[List[String]]:
    """Return the logged calls of a stand-in compiler.

    Args:
        path: The `invocations` file. A missing file means no call.

    Returns:
        Each call's arguments, in the order written.

    Raises:
        Error: If the file cannot be read.
    """
    var calls = List[List[String]]()
    if not Path(path).exists():
        return calls^
    for line in Path(path).read_text().splitlines():
        var words = String(line).split("\x1f")
        var call = List[String]()
        for index in range(len(words) - 1):
            call.append(String(words[index]))
        calls.append(call^)
    return calls^


def section(source: String, start: String, end: String) raises -> String:
    """Return the text from a start marker to an end marker.

    Args:
        source: The Makefile.
        start: The first text of the section.
        end: The text after the section; it is not included.

    Returns:
        The section.

    Raises:
        Error: If a marker is missing.
    """
    var first = source.find(start)
    if first < 0:
        raise Error("missing Makefile text: " + start)
    var last = source.find(end, first)
    if last < 0:
        raise Error("missing Makefile text: " + end)
    return String(source[byte=first:last])


def definition(source: String, name: String) raises -> String:
    """Return one `define NAME` block, up to and with its `endef`.

    Args:
        source: The Makefile.
        name: The variable.

    Returns:
        The block.

    Raises:
        Error: If the block is missing.
    """
    return section(source, "define " + name + "\n", "\nendef") + "\nendef"
