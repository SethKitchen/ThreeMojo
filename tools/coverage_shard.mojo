# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Print one group of coverage captures, longest first.

    coverage_shard 2/8 tests/test_a.mojo tests/test_b.mojo ...

CPU sharding uses import size. A coverage capture also writes costly probe
output, so this tool uses the measured seconds in
`tools/coverage_costs.json`. The profile decides only the order and the
group of each suite: every given suite is kept.
"""

from std.collections import Set
from std.sys import argv, exit, stderr

from tools._imports import SourceCache, mojo_files
from tools._schedule import load_costs, parse_shard, schedule, strip_dot, weight

comptime PROFILE = "tools/coverage_costs.json"
"""The measured seconds of each capture."""


def group(root: String, arguments: List[String]) raises -> String:
    """Return the chosen group, as the tool prints it.

    Args:
        root: The repository root.
        arguments: `I/N` and then the suites.

    Returns:
        The suites of group I, from the longest capture down, joined by
        spaces.

    Raises:
        Error: If the arguments name no group, the profile is not valid, a
            suite repeats, or a suite cannot be read.
    """
    var index = 0
    var count = 0
    if len(arguments) == 0 or not parse_shard(arguments[0], index, count):
        raise Error("expected I/N with 1 <= I <= N")
    var suites = List[String]()
    for position in range(1, len(arguments)):
        suites.append(strip_dot(arguments[position]))
    var costs = load_costs(root + "/" + PROFILE)
    var known = Set[String]()
    for path in mojo_files(root):
        known.add(path)
    var cache = SourceCache()
    var weights = List[Int]()
    for suite in suites:
        weights.append(weight(root, suite, known, cache))
    return " ".join(schedule(suites, count, costs, weights)[index - 1])


def main() raises:
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        print(group(".", arguments))
    except error:
        print("coverage_shard:", error, file=stderr)
        exit(2)
