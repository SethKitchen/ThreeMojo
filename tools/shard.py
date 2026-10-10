# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
"""Split the suites into balanced groups, for `make ... SHARD=i/n`.

    python3 tools/shard.py 2/4 tests/test_a.mojo tests/test_b.mojo ...

prints the suites of group 2 of 4, in their given order. CI runs each
group on its own runner, so a check waits for the slowest group, not for
all of them in a row.

A suite's time is almost all compilation, and compilation grows with the
source a suite imports, not with the suite alone. So each suite weighs
the bytes of every file it reaches through its imports, itself included.
The heaviest suite goes first to the lightest group, and so on down: the
longest-processing-time rule. Ties break by name, so every runner computes
the same split.
"""

import os
import sys

import affected


def weight(suite, known, sizes, cache):
    """Return the bytes of `suite` and of every file it imports, directly or
    through other files."""
    if suite in cache:
        return cache[suite]
    seen = {suite}
    stack = [suite]
    while stack:
        path = stack.pop()
        with open(os.path.join(affected.ROOT, path), encoding="utf-8") as source:
            text = source.read()
        # Every import in the build searches the suite's directory first.
        for name in affected.imported_names(text):
            for reached in affected.resolve(name, path, known,
                                            [os.path.dirname(suite)]):
                if reached not in seen:
                    seen.add(reached)
                    stack.append(reached)
    cache[suite] = sum(sizes[path] for path in seen)
    return cache[suite]


def split(suites, count, weigh):
    """Return `suites` dealt into `count` groups of balanced total weight."""
    groups = [[] for _ in range(count)]
    loads = [0] * count
    for suite in sorted(suites, key=lambda path: (-weigh(path), path)):
        lightest = min(range(count), key=lambda group: (loads[group], group))
        groups[lightest].append(suite)
        loads[lightest] += weigh(suite)
    return groups


def main(arguments):
    """Print the suites of one group.

    Args:
        arguments: `I/N` and then the suites.

    Returns:
        Zero, or two for an `I/N` that names no group.
    """
    if not arguments:
        print("usage: shard.py I/N SUITE...", file=sys.stderr)
        return 2
    index, _, count = arguments[0].partition("/")
    if not (index.isdigit() and count.isdigit()) or not (
        1 <= int(index) <= int(count)
    ):
        print("shard.py: expected I/N with 1 <= I <= N", file=sys.stderr)
        return 2
    suites = [path.removeprefix("./") for path in arguments[1:]]
    known = set(affected.mojo_files())
    sizes = {
        path: os.path.getsize(os.path.join(affected.ROOT, path)) for path in known
    }
    cache = {}
    groups = split(
        suites, int(count), lambda path: weight(path, known, sizes, cache)
    )
    chosen = set(groups[int(index) - 1])
    print(" ".join(path for path in suites if path in chosen))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
