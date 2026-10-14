# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Print one balanced group of suites, for `make ... SHARD=i/n`.

    shard 2/4 tests/test_a.mojo tests/test_b.mojo ...

prints the suites of group 2 of 4, in their given order. A suite's time is
almost all compilation, and compilation grows with the source a suite
imports. So each suite weighs the bytes of every file it reaches through
its imports, itself included. `tools._schedule.split` deals the groups.
"""

from std.collections import Set
from std.sys import argv, exit, stderr

from tools._imports import SourceCache, mojo_files
from tools._schedule import parse_shard, split, strip_dot, weight


def group(root: String, arguments: List[String]) raises -> String:
    """Return the chosen group, as the tool prints it.

    Args:
        root: The repository root.
        arguments: `I/N` and then the suites.

    Returns:
        The suites of group I, in their given order, joined by spaces.

    Raises:
        Error: If the arguments name no group, or a suite cannot be read.
    """
    var index = 0
    var count = 0
    if len(arguments) == 0 or not parse_shard(arguments[0], index, count):
        raise Error("expected I/N with 1 <= I <= N")
    var suites = List[String]()
    for position in range(1, len(arguments)):
        suites.append(strip_dot(arguments[position]))
    var known = Set[String]()
    for path in mojo_files(root):
        known.add(path)
    var cache = SourceCache()
    var costs = List[Float64]()
    for suite in suites:
        costs.append(Float64(weight(root, suite, known, cache)))
    var chosen = Set[String]()
    for suite in split(suites, count, costs)[index - 1]:
        chosen.add(suite)
    var selected = List[String]()
    for suite in suites:
        if suite in chosen:
            selected.append(suite)
    return " ".join(selected)


def main() raises:
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        print(group(".", arguments))
    except error:
        print("shard:", error, file=stderr)
        exit(2)
