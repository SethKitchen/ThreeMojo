# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Probe functions compiled into instrumented copies of the sources.

Mojo has no global variables, so a probe cannot accumulate counts in memory.
Instead each probe writes one record to stderr and the report tool dedupes
them afterwards. stderr is used so that a program's real stdout — a PPM image,
say — stays byte-for-byte unchanged while instrumented.

Neither probe may raise, or it could not be called from the many non-raising
functions in the codebase.
"""

from std.sys import stderr

comptime LINE_PREFIX = "COVLINE:"
comptime BRANCH_PREFIX = "COVBRANCH:"


@no_inline
def hit(id: StaticString):
    """Record that the statement identified by `id` executed.

    Takes a `StaticString` so a call site passes a pointer to a literal and
    allocates nothing per probe. (This was once suspected of causing a
    compile-time hang; it was not -- see docs/mojo-compiler-issue -- but it
    is the cheaper signature regardless, and `@no_inline` keeps the print
    machinery compiled once here rather than at every call site.)
    """
    print(LINE_PREFIX, id, sep="", file=stderr)


@no_inline
def branch(id: StaticString, value: Bool) -> Bool:
    """Record which way the decision identified by `id` went, and pass it on.

    Wrapping the condition itself is what makes both outcomes observable: a
    decision whose False side has no `else` block leaves no other trace.
    """
    if value:
        print(BRANCH_PREFIX, id, ":T", sep="", file=stderr)
    else:
        print(BRANCH_PREFIX, id, ":F", sep="", file=stderr)
    return value
