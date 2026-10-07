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
An interrupted write retries the complete record. Other failed or short writes
terminate the suite instead of certifying missing data.
"""

from std.ffi import external_call
from std.memory import stack_allocation
from std.sys._libc_errno import ErrNo, get_errno, set_errno
from std.sys import is_defined

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
    while True:
        var written = external_call["write", Int](
            2, record.unsafe_ptr().unsafe_bitcast[NoneType](), size
        )
        if written == size:
            return
        # EINTR reports that no bytes were written. Keep the full record atomic.
        if written != -1 or get_errno() != ErrNo.EINTR:
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
    comptime if is_defined["THREEMOJO_COVERAGE_HIT_CACHE"]():
        if not __is_run_in_comptime_interpreter:
            var saved_errno = get_errno()
            var result_errno = external_call[
                "threemojo_coverage_emit_hit", Int32
            ](bytes.unsafe_bitcast[NoneType](), size, saved_errno.value)
            set_errno(ErrNo(result_errno))
            return
    while True:
        var written = external_call["write", Int](
            2, bytes.unsafe_bitcast[NoneType](), size
        )
        if written == size:
            return
        # EINTR reports that no bytes were written. Keep the full record atomic.
        if written != -1 or get_errno() != ErrNo.EINTR:
            external_call["abort", NoneType]()


@inline(.never)
def _emit_evaluation(record: String):
    """Route every complete vector through the optional private probe sink."""
    if record.byte_length() > MAX_RECORD_BYTES:
        external_call["abort", NoneType]()
    comptime if is_defined["THREEMOJO_COVERAGE_HIT_CACHE"]():
        if not __is_run_in_comptime_interpreter:
            var saved_errno = get_errno()
            var result_errno = external_call[
                "threemojo_coverage_emit_evaluation", Int32
            ](
                record.unsafe_ptr().unsafe_bitcast[NoneType](),
                record.byte_length(),
                saved_errno.value,
            )
            set_errno(ErrNo(result_errno))
            return
    _emit(record)


@inline(.never)
def hit(id: StaticString):
    """Record that the statement identified by `id` executed.

    Oversized records and failed writes terminate the process.

    Args:
        id: Static source ID. The full UTF-8 record must fit in 512 bytes.
    """
    _emit_hit(id, "\n")


@inline(.never)
def branch[T: Boolable](id: StaticString, value: T) -> Bool:
    """Convert one truth-testable operand once and record its Boolean outcome.

    COVLINE carries all hit payloads, including condition and decision outcomes.
    Only complete COVEVAL2 records supply compound MC-DC evidence.
    Oversized records and failed writes terminate the process.

    Args:
        id: Static source ID. The full UTF-8 record must fit in 512 bytes.
        value: The original truth-testable decision or condition operand.

    Returns:
        The operand's Boolean value, evaluated exactly once.
    """
    var outcome = value.__bool__()
    _emit_hit(id, StaticString(":T\n") if outcome else StaticString(":F\n"))
    return outcome


def buffer() -> List[Int]:
    """Construct a private empty buffer without using caller-scope type names.

    Returns:
        An empty operand buffer. Storage is allocated only when it is used.
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
    """
    values.clear()
    for _ in range(width):
        values.append(-1)
    return True


@inline(.never)
def leaf(
    value: Bool, mut values: List[Int], id: StaticString, index: Int
) -> Bool:
    """Record a Boolean operand without changing its value.

    Args:
        value: The original Boolean operand.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.

    Returns:
        The unchanged operand.
    """
    values[index] = Int(value)
    return branch(id, value)


@inline(.never)
def leaf(
    value: SIMD[DType.bool, 1],
    mut values: List[Int],
    id: StaticString,
    index: Int,
) -> Bool:
    """Record a scalar SIMD comparison or standard math predicate.

    Args:
        value: The Boolean scalar, borrowed without copying.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.

    Returns:
        The scalar's Boolean value.
    """
    return leaf(value.__bool__(), values, id, index)


@inline(.never)
def leaf(
    value: Int, mut values: List[Int], id: StaticString, index: Int
) -> Bool:
    """Record a standard-library operand with a pure truth conversion.

    Args:
        value: The original truth-testable operand, borrowed without copying.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.

    Returns:
        The operand's Boolean value.
    """
    return leaf(value.__bool__(), values, id, index)


@inline(.never)
def leaf(
    value: String, mut values: List[Int], id: StaticString, index: Int
) -> Bool:
    """Record a standard-library operand with a pure truth conversion.

    Args:
        value: The original truth-testable operand, borrowed without copying.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.

    Returns:
        The operand's Boolean value.
    """
    return leaf(value.__bool__(), values, id, index)


@inline(.never)
def leaf[
    T: Movable, //
](
    value: Optional[T], mut values: List[Int], id: StaticString, index: Int
) -> Bool:
    """Record a standard-library operand with a pure truth conversion.

    Args:
        value: The original truth-testable operand, borrowed without copying.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.

    Returns:
        The operand's Boolean value.
    """
    return leaf(value.__bool__(), values, id, index)


@inline(.never)
def leaf[
    T: Movable, //
](value: List[T], mut values: List[Int], id: StaticString, index: Int) -> Bool:
    """Record a standard-library operand with a pure truth conversion.

    Args:
        value: The original truth-testable operand, borrowed without copying.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.

    Returns:
        The operand's Boolean value.
    """
    return leaf(value.__bool__(), values, id, index)


@inline(.never)
def leaf[
    T: Boolable, *Ts: AnyType
](
    value: T, mut values: List[Int], id: StaticString, index: Int, *extra: *Ts
) -> Bool:
    """Reject unverified truth conversion instead of changing source behavior.

    The trailing pack makes this a fallback after the fixed pure-type overloads.
    It also prevents implicit Optional construction from admitting a custom type.

    Args:
        value: An unsupported operand.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.
        extra: The overload-resolution fallback pack; callers leave it empty.

    Returns:
        No value. Instantiation fails with an actionable diagnostic.
    """
    comptime assert False, (
        "Coverage compound operands support Bool, scalar SIMD Bool, Int,"
        " String, Optional and List; custom Boolable truth conversions are not"
        " yet supported. Do not exclude the source; see the coverage"
        " truth-conversion limit."
    )


@inline(.never)
def finish(value: Bool, values: List[Int], id: StaticString) -> Bool:
    """Emit a complete evaluation after every executed operand has returned.

    Oversized records and failed writes terminate the process.

    Args:
        value: The original decision's outcome.
        values: Only this invocation's current evaluated and masked operands.
        id: The decision's static hit identifier.

    Returns:
        The original outcome.
    """
    _ = branch(id, value)
    var record = (
        String(EVALUATION_PREFIX) + String(id) + (":T:" if value else ":F:")
    )
    for state in values:
        record += "-" if state < 0 else ("T" if state > 0 else "F")
    _emit_evaluation(record + ";\n")
    return value
