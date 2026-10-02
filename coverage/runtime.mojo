# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Emit individual hits and complete, activation-local evaluation vectors.

Each function with compound decisions owns a private operand buffer. A begin
clears it before each evaluation. Recursion and concurrent calls have separate
buffers. An exception cannot emit an evaluation, and a subsequent begin clears
its partial operands. No identity, global state, or implicit nesting is needed.

Each record uses one write of at most 512 bytes, the POSIX minimum PIPE_BUF.
Concurrent writers to the capture pipe cannot interleave bytes within a record.
A failed or short write terminates the suite instead of certifying missing data.
"""

from std.ffi import external_call
from std.memory import stack_allocation

comptime LINE_PREFIX = "COVLINE:"
comptime BRANCH_PREFIX = "COVBRANCH:"
comptime EVALUATION_PREFIX = "COVEVAL2:"
comptime MAX_RECORD_BYTES = 512


@inline(.never)
def _emit(record: String):
    """Write one bounded record; terminate if complete capture is impossible."""
    var size = record.byte_length()
    if size > MAX_RECORD_BYTES:
        external_call["abort", NoneType]()
    var written = external_call["write", Int](
        2, record.unsafe_ptr().unsafe_bitcast[NoneType](), size
    )
    if written != size:
        external_call["abort", NoneType]()


@inline(.never)
def _emit_hit(id: StaticString, suffix: StaticString):
    """Assemble common hit records on the stack, without heap allocation."""
    var prefix = StaticString(LINE_PREFIX)
    var size = prefix.byte_length() + id.byte_length() + suffix.byte_length()
    if size > MAX_RECORD_BYTES:
        external_call["abort", NoneType]()
    var bytes = stack_allocation[MAX_RECORD_BYTES, UInt8]()
    var index = 0
    for value in prefix.as_bytes():
        bytes[unsafe_offset=index] = value
        index += 1
    for value in id.as_bytes():
        bytes[unsafe_offset=index] = value
        index += 1
    for value in suffix.as_bytes():
        bytes[unsafe_offset=index] = value
        index += 1
    var written = external_call["write", Int](
        2, bytes.unsafe_bitcast[NoneType](), size
    )
    if written != size:
        external_call["abort", NoneType]()


@inline(.never)
def hit(id: StaticString):
    """Record that the statement identified by `id` executed.

    Args:
        id: Static source ID. The full UTF-8 record must fit in 512 bytes.

    Returns:
        Nothing.

    Raises:
        Never. Oversized records and failed writes terminate the process.
    """
    _emit_hit(id, "\n")


@inline(.never)
def branch(id: StaticString, value: Bool) -> Bool:
    """Record an outcome hit and return the unchanged Boolean value.

    COVLINE carries all hit payloads, including condition and decision outcomes.
    Only complete COVEVAL2 records supply compound MC-DC evidence.

    Args:
        id: Static source ID. The full UTF-8 record must fit in 512 bytes.
        value: The original decision or condition outcome.

    Returns:
        The original value.

    Raises:
        Never. Oversized records and failed writes terminate the process.
    """
    _emit_hit(id, StaticString(":T\n") if value else StaticString(":F\n"))
    return value


def buffer() -> List[Int]:
    """Construct a private empty buffer without using caller-scope type names.

    Args:
        None.

    Returns:
        An empty operand buffer. Storage is allocated only when it is used.

    Raises:
        Never.
    """
    return List[Int]()


@inline(.never)
def begin(mut values: List[Int], width: Int) -> Bool:
    """Start an evaluation with every operand masked.

    Args:
        values: This function invocation's private operand buffer.
        width: The compound decision's number of leaves.

    Returns:
        True, so the original condition is evaluated by short-circuit `and`.

    Raises:
        Never.
    """
    values.clear()
    for _ in range(width):
        values.append(-1)
    return True


@inline(.never)
def leaf(
    value: Bool, mut values: List[Int], id: StaticString, index: Int
) -> Bool:
    """Record one evaluated operand, after its original expression completes.

    Args:
        value: The original operand's Boolean value.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.

    Returns:
        The original value.

    Raises:
        Never.
    """
    values[index] = Int(value)
    return branch(id, value)


@inline(.never)
def finish(value: Bool, values: List[Int], id: StaticString) -> Bool:
    """Emit a complete evaluation after every executed operand has returned.

    Args:
        value: The original decision's outcome.
        values: Only this invocation's current evaluated and masked operands.
        id: The decision's static hit identifier.

    Returns:
        The original outcome.

    Raises:
        Never.
    """
    _ = branch(id, value)
    var record = (
        String(EVALUATION_PREFIX) + String(id) + (":T:" if value else ":F:")
    )
    for state in values:
        record += "-" if state < 0 else ("T" if state > 0 else "F")
    _emit(record + ";\n")
    return value
