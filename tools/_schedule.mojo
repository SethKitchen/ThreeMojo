# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Split suites into groups of balanced cost, for `make ... SHARD=i/n`.

CI runs each group on its own runner, so a check waits for the slowest
group, not for all of them in a row. `tools/shard.mojo` weighs a suite by
the source it compiles. `tools/coverage_shard.mojo` uses the measured
seconds of each coverage capture.

The costliest suite goes first to the cheapest group, and so on down: the
longest-processing-time rule. Ties break by name and by group number, so
every runner computes the same split.
"""

from std.collections import Set
from std.math import isfinite
from std.pathlib import Path

from loaders.json import ARRAY, NUMBER, OBJECT, JsonDocument, parse_json
from tools._imports import SourceCache, closure


def weight(
    root: String, suite: String, known: Set[String], mut cache: SourceCache
) raises -> Int:
    """Return the bytes a suite compiles: its own and every file it imports,
    directly or through other files.

    Args:
        root: The repository root.
        suite: The suite.
        known: Every `.mojo` path.
        cache: What earlier calls read.

    Returns:
        The total size in bytes.

    Raises:
        Error: If a reached file cannot be read.
    """
    var total = 0
    for path in closure(root, suite, known, cache):
        total += cache.sizes[path]
    return total


def _before(
    cost: Float64, name: String, other_cost: Float64, other: String
) -> Bool:
    """Return whether a suite comes first: the higher cost, then the name."""
    if cost != other_cost:
        return cost > other_cost
    return name < other


def split(
    suites: List[String], count: Int, costs: List[Float64]
) -> List[List[String]]:
    """Deal suites into groups of balanced total cost.

    Args:
        suites: The suites.
        count: The number of groups, at least one.
        costs: The cost of each suite, in the same order.

    Returns:
        The groups. Each lists its suites from the costliest down.
    """
    var order = List[Int]()
    for index in range(len(suites)):
        var place = len(order)
        while place > 0 and _before(
            costs[index],
            suites[index],
            costs[order[place - 1]],
            suites[order[place - 1]],
        ):
            place -= 1
        order.insert(place, index)
    var groups = List[List[String]]()
    var loads = List[Float64]()
    for _ in range(count):
        groups.append(List[String]())
        loads.append(0)
    for index in order:
        var lightest = 0
        for group in range(1, count):
            if loads[group] < loads[lightest]:
                lightest = group
        groups[lightest].append(suites[index])
        loads[lightest] += costs[index]
    return groups^


def parse_shard(text: String, mut index: Int, mut count: Int) -> Bool:
    """Read `I/N`.

    Args:
        text: The argument.
        index: Set to I.
        count: Set to N.

    Returns:
        True when both are decimal digits and 1 <= I <= N.
    """
    var slash = text.find("/")
    if slash <= 0 or slash + 1 >= text.byte_length():
        return False
    for byte in text.as_bytes():
        if byte != 47 and not (byte >= 48 and byte <= 57):
            return False
    if text.find("/", slash + 1) >= 0:
        return False
    try:
        index = Int(String(text[byte=:slash]))
        count = Int(String(text[byte = slash + 1 :]))
    except:
        return False
    return index >= 1 and index <= count


def strip_dot(path: String) -> String:
    """Return a path without a leading `./`.

    Args:
        path: The path.

    Returns:
        The path.
    """
    if path.startswith("./"):
        return String(path[byte=2:])
    return path


def _refuse_duplicates(document: JsonDocument, node: Int) raises:
    """Refuse an object, at any depth, that names one key twice."""
    var kind = document.kind(node)
    if kind == OBJECT:
        var names = Set[String]()
        for index in range(document.length(node)):
            var name = document.key(node, index)
            if name in names:
                raise Error("duplicate coverage profile key: " + name)
            names.add(name)
            _refuse_duplicates(document, document.at(node, index))
    elif kind == ARRAY:
        for index in range(document.length(node)):
            _refuse_duplicates(document, document.at(node, index))


def load_costs(path: String) raises -> Dict[String, Float64]:
    """Read the measured seconds of each coverage capture.

    The file is a JSON object whose `seconds` member maps each suite to a
    positive, finite number. No object in it can name a key twice.

    Args:
        path: The profile.

    Returns:
        Each suite and its seconds.

    Raises:
        Error: If the profile cannot be read, or a suite name or a time is
            not valid.
    """
    var document = parse_json(Path(path).read_text())
    _refuse_duplicates(document, document.root())
    var table = document.get(document.root(), "seconds")
    if document.kind(table) != OBJECT or document.length(table) == 0:
        raise Error("coverage costs must be a nonempty object")
    var costs = Dict[String, Float64]()
    for index in range(document.length(table)):
        var suite = document.key(table, index)
        var value = document.at(table, index)
        var kind = document.kind(value)
        var seconds = document.number(value) if kind == NUMBER else 0.0
        if (
            not suite.startswith("tests/test_")
            or not suite.endswith(".mojo")
            or String(suite[byte=6:]).find("/") >= 0
            or kind != NUMBER
            or not isfinite(seconds)
            or not seconds > 0
        ):
            raise Error("invalid coverage cost: " + suite)
        costs[suite] = seconds
    return costs^


def schedule(
    suites: List[String],
    count: Int,
    costs: Dict[String, Float64],
    weights: List[Int],
) raises -> List[List[String]]:
    """Split coverage captures by their measured seconds.

    A suite with no measured time gets an estimate: its weight times the
    median seconds per byte of the measured suites, and at least one
    second. So a new suite is never treated as free, and no suite is left
    out.

    Args:
        suites: The suites, each once.
        count: The number of groups.
        costs: The measured seconds.
        weights: The weight of each suite, in the same order.

    Returns:
        The groups, each from the longest capture down.

    Raises:
        Error: If `count` is not positive or a suite repeats.
    """
    var seen = Set[String]()
    for suite in suites:
        seen.add(suite)
    if count < 1 or len(seen) != len(suites):
        raise Error("expected a positive shard count and unique suites")
    var ratios = List[Float64]()
    for index in range(len(suites)):
        var measured = costs.get(suites[index])
        if measured:
            ratios.append(measured.value() / Float64(max(1, weights[index])))
    var per_byte = 1.0 / 10000.0
    if len(ratios) > 0:
        sort(ratios)
        var middle = len(ratios) // 2
        per_byte = (
            ratios[middle] if len(ratios) % 2
            == 1 else (ratios[middle - 1] + ratios[middle]) / 2
        )
    var estimates = List[Float64]()
    for index in range(len(suites)):
        var measured = costs.get(suites[index])
        if measured:
            estimates.append(measured.value())
        else:
            estimates.append(max(1.0, Float64(weights[index]) * per_byte))
    return split(suites, count, estimates)
