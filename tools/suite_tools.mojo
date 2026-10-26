# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Print the project tools that test suites build before they run.

    suite_tools SUITE...

A suite that drives a tool builds it first, with
`["sh", "tools/tool.sh", tool_mojo(), "--build", "NAME"]`. A cold build
takes longer than the time `run_suite` gives the whole suite. `make
test-cpu` builds each printed tool once, in parallel, before it runs the
suites, as it builds `run_suite`.

The tool reads the string literals of each suite in order. A `"--build"`
whose previous literal is `"tools/tool.sh"` names the next literal, if
`tools/NAME.mojo` exists. The names are printed sorted, one to a line.
"""

from std.collections import Set
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._imports import sorted_strings


def string_literals(text: String) -> List[String]:
    """Return the double-quoted string literals of a source, in order.

    Args:
        text: The source.

    Returns:
        The content of each literal, with escapes left as written. A
        literal in a comment is returned too. A single-quoted string is
        skipped, so a double quote inside it is not a literal.
    """
    var found = List[String]()
    var bytes = text.as_bytes()
    var index = 0
    var comment = False
    var count = len(bytes)
    while index < count:
        var byte = bytes[index]
        if comment:
            if byte == UInt8(ord("\n")):
                comment = False
            elif byte == UInt8(ord('"')):
                var start = index + 1
                var end = start
                while end < count and bytes[end] != UInt8(ord('"')):
                    if bytes[end] == UInt8(ord("\\")):
                        end += 1
                    end += 1
                found.append(String(text[byte = start : min(end, count)]))
                index = end + 1
                continue
            index += 1
            continue
        if byte == UInt8(ord("#")):
            comment = True
            index += 1
            continue
        if byte == UInt8(ord("'")):
            var end = index + 1
            while end < count and bytes[end] != UInt8(ord("'")):
                if bytes[end] == UInt8(ord("\\")):
                    end += 1
                end += 1
            index = end + 1
            continue
        if byte != UInt8(ord('"')):
            index += 1
            continue
        var start = index + 1
        var end = start
        while end < count and bytes[end] != UInt8(ord('"')):
            if bytes[end] == UInt8(ord("\\")):
                end += 1
            end += 1
        found.append(String(text[byte = start : min(end, count)]))
        index = end + 1
    return found^


def built_tools(root: String, text: String) -> List[String]:
    """Return the tools a suite builds with `tools/tool.sh --build`.

    Args:
        root: The repository root.
        text: The suite's source.

    Returns:
        Each named tool that has a `tools/NAME.mojo`, in source order.
    """
    var names = List[String]()
    var literals = string_literals(text)
    for index in range(1, len(literals) - 1):
        if literals[index] != "--build":
            continue
        if literals[index - 1] != "tools/tool.sh":
            continue
        var name = literals[index + 1]
        if Path(root + "/tools/" + name + ".mojo").is_file():
            names.append(name)
    return names^


def run(root: String, suites: List[String]) raises -> List[String]:
    """Return the tools the suites build, sorted and without repeats.

    Args:
        root: The repository root.
        suites: The suite paths, relative to the root.

    Returns:
        The tool names.

    Raises:
        Error: If a suite cannot be read.
    """
    var seen = Set[String]()
    var names = List[String]()
    for suite in suites:
        for name in built_tools(root, Path(root + "/" + suite).read_text()):
            if not name in seen:
                seen.add(name)
                names.append(name)
    return sorted_strings(names^)


def main() raises:
    """Print the tools that the named suites build."""
    var suites = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        suites.append(String(given[index]))
    try:
        for name in run(".", suites):
            print(name)
    except error:
        print("suite_tools:", error, file=stderr)
        exit(2)
