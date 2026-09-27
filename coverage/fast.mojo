# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Probe functions that write each new line and each new decision vector once.

`coverage/instrument.mojo` imports these names. They call `cov_state` in
`coverage/state.c`, which the coverage recipe links in. A repeated statement
then costs a table lookup instead of a write to stderr.

`hit` and `branch` must not raise. Instrumented code calls them from
functions that do not raise.
"""

from coverage.dedup import (
    BRANCH_PRINT_ONE,
    BRANCH_PRINT_VECTOR,
    BlockOrigin,
    Dedup,
)
from coverage.runtime import BRANCH_PREFIX, LINE_PREFIX
from std.ffi import external_call
from std.sys import stderr


def _base() -> Pointer[UInt8, BlockOrigin]:
    var addr = external_call["cov_state", UInt64]()
    return Pointer[UInt8, BlockOrigin](unsafe_from_address=Int(addr))


def _bytes(id: StaticString) -> Pointer[UInt8, BlockOrigin]:
    return (
        id.unsafe_ptr()
        .unsafe_bitcast[UInt8]()
        .unsafe_mut_cast[True]()
        .unsafe_origin_cast[BlockOrigin]()
    )


def _print_id(id: String, value: Bool):
    if value:
        print(BRANCH_PREFIX, id, ":T", sep="", file=stderr)
    else:
        print(BRANCH_PREFIX, id, ":F", sep="", file=stderr)


@inline(.never)
def hit(id: StaticString):
    """Record that the statement identified by `id` executed, once.

    Args:
        id: The probe id, a module path and a source line.

    """
    var table = Dedup(_base())
    if table.claim_line(_bytes(id), id.byte_length()):
        print(LINE_PREFIX, id, sep="", file=stderr)


@inline(.never)
def branch(id: StaticString, value: Bool) -> Bool:
    """Record which way the decision identified by `id` went, and pass it on.

    A repeated evaluation of the same conditions and outcome writes nothing.

    Args:
        id: The probe id. A condition id ends in `.<digits>`.
        value: Which way it went.

    Returns:
        `value`, so the call can wrap the condition it records.

    """
    var table = Dedup(_base())
    var code = table.absorb_branch(_bytes(id), id.byte_length(), value)
    if code == BRANCH_PRINT_ONE:
        if value:
            print(BRANCH_PREFIX, id, ":T", sep="", file=stderr)
        else:
            print(BRANCH_PREFIX, id, ":F", sep="", file=stderr)
    elif code == BRANCH_PRINT_VECTOR:
        var start = table.vector_start()
        var count = table.pending_count()
        for index in range(start, count):
            _print_id(table.pending_text(index), table.pending_value(index))
        if value:
            print(BRANCH_PREFIX, id, ":T", sep="", file=stderr)
        else:
            print(BRANCH_PREFIX, id, ":F", sep="", file=stderr)
        table.drop_vector()
    return value
