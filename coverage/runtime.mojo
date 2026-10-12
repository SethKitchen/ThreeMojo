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
from std.reflection import reflect
from std.sys import is_defined
from std.traits import (
    IsTriviallyCopyable,
    IsTriviallyDeinitable,
    IsTriviallyMovable,
)

comptime LINE_PREFIX = "COVLINE:"
comptime BRANCH_PREFIX = "COVBRANCH:"
comptime EVALUATION_PREFIX = "COVEVAL2:"
comptime MAX_RECORD_BYTES = 512
# A slot whose repeated native truth conversions disagreed. Its vector
# character is `?`, which the parsers refuse instead of certifying MC-DC.
comptime INCONSISTENT = 2


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
def _observe(
    mut values: List[Int], id: StaticString, index: Int, outcome: Bool
):
    """Record one native truth conversion of a custom operand.

    The first conversion fills the slot and writes the condition hit. A later
    conversion of the same selected object with the same truth adds nothing.
    A later conversion with a different truth writes that hit too and marks
    the slot inconsistent, so the vector cannot certify MC-DC.
    """
    var state = values[index]
    if state == Int(outcome):
        return
    values[index] = Int(outcome) if state < 0 else INCONSISTENT
    _emit_hit(id, StaticString(":T\n") if outcome else StaticString(":F\n"))


struct _OwnedLeaf[T: Boolable & Movable & Deinitable, origin: Origin[mut=True]](
    Boolable, Movable
):
    """An owned temporary operand that records each native truth conversion.

    The type has no operand origin. Two temporaries of one native type give one
    proxy type, so Mojo keeps its same-type or mixed-type operator semantics.
    The proxy is not copyable, so a selected operand moves as it does natively.
    """

    var value: Self.T
    var values: Pointer[List[Int], Self.origin]
    var id: StaticString
    var index: Int

    def __init__(
        out self,
        var value: Self.T,
        values: Pointer[List[Int], Self.origin],
        id: StaticString,
        index: Int,
    ):
        """Take ownership of the temporary operand without converting it.

        Args:
            value: The temporary operand.
            values: The current invocation's operand buffer.
            id: The condition's static hit identifier.
            index: The condition's slot in the buffer.
        """
        self.value = value^
        self.values = values
        self.id = id
        self.index = index

    def __bool__(self) -> Bool:
        """Convert the operand once for this native truth test and record it.

        Returns:
            The operand's own `__bool__` result.
        """
        var outcome = self.value.__bool__()
        _observe(self.values[], self.id, self.index, outcome)
        return outcome


struct _BorrowedLeaf[
    T: Boolable, value_origin: Origin[mut=False], origin: Origin[mut=True]
](Boolable, Movable):
    """A borrowed retained operand that records each native truth conversion.

    The type keeps the operand origin, so Mojo keeps the operand alive. Only
    non-implicitly-copyable operands use it. A surrounding `not` can convert
    it before an `and` or `or` node. A raw retained operand requires native
    mixed-type semantics, which the node guard conservatively refuses.
    """

    var value: Pointer[Self.T, Self.value_origin]
    var values: Pointer[List[Int], Self.origin]
    var id: StaticString
    var index: Int

    def __init__(
        out self,
        value: Pointer[Self.T, Self.value_origin],
        values: Pointer[List[Int], Self.origin],
        id: StaticString,
        index: Int,
    ):
        """Borrow the retained operand without converting it.

        Args:
            value: The retained operand.
            values: The current invocation's operand buffer.
            id: The condition's static hit identifier.
            index: The condition's slot in the buffer.
        """
        self.value = value
        self.values = values
        self.id = id
        self.index = index

    def __bool__(self) -> Bool:
        """Convert the operand once for this native truth test and record it.

        Returns:
            The operand's own `__bool__` result.
        """
        var outcome = self.value[].__bool__()
        _observe(self.values[], self.id, self.index, outcome)
        return outcome


@inline(.never)
def leaf[
    T: Boolable & Movable & Deinitable,
    origin: Origin[mut=True],
    //,
    *Ts: AnyType,
](
    var value: T,
    ref[origin] values: List[Int],
    id: StaticString,
    index: Int,
    *extra: *Ts,
) -> _OwnedLeaf[T, origin]:
    """Move a temporary custom operand into a recording proxy.

    Mojo selects this overload for a temporary and the `ref` overload for a
    retained value. The trailing pack makes both a fallback after the fixed
    pure-type overloads. The operand is not converted here: the native `and`,
    `or`, `not` and truth context convert the proxy as they would the operand.

    Args:
        value: The temporary operand, moved without a copy.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.
        extra: The overload-resolution fallback pack; callers leave it empty.

    Returns:
        A proxy that owns the operand and records its truth conversions.
    """
    # The move into the proxy is extra. Only a bitwise move hides it.
    comptime assert T.__move_ctor_is_trivial, (
        "Coverage cannot yet preserve a temporary custom Boolable compound"
        " operand with a user-defined move constructor: the probe would add a"
        " move. Do not exclude the source; see the coverage truth-conversion"
        " limit."
    )
    return _OwnedLeaf[T, origin](value^, Pointer(to=values), id, index)


@inline(.never)
def leaf[
    T: Boolable,
    value_origin: Origin[mut=False],
    origin: Origin[mut=True],
    //,
    *Ts: AnyType,
](
    ref[value_origin] value: T,
    ref[origin] values: List[Int],
    id: StaticString,
    index: Int,
    *extra: *Ts,
) -> _BorrowedLeaf[T, value_origin, origin]:
    """Borrow a retained custom operand in a recording proxy.

    Native same-type `and` or `or` copies a retained operand into its result.
    A borrowing proxy cannot reproduce that copy, so an implicitly copyable
    retained operand is rejected. Other retained operands can pass through
    `not`; the node guard refuses their raw mixed-type `and` or `or` uses.

    Args:
        value: The retained operand, borrowed without a copy.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.
        extra: The overload-resolution fallback pack; callers leave it empty.

    Returns:
        A proxy that borrows the operand and records its truth conversions.
    """
    comptime assert not conforms_to(T, ImplicitlyCopyable), (
        "Coverage cannot yet preserve a retained implicitly copyable custom"
        " Boolable compound operand: native same-type and/or copies it. Do not"
        " exclude the source; see the coverage truth-conversion limit."
    )
    return _BorrowedLeaf[T, value_origin, origin](
        Pointer(to=value), Pointer(to=values), id, index
    )


def _pure(name: StaticString) -> Bool:
    """Return True for a type whose operands convert to Bool without probes.

    These are the fixed `leaf` overloads. Pinned Mojo 1.1.0 names prelude
    types without a module and every source type with its module, so a source
    type cannot take one of these names.
    """
    return (
        name == "Bool"
        or name == "SIMD[DType.bool, 1]"
        or name == "SIMD[DType.int, 1]"
        or name == "String"
        or name.startswith("List[")
        or _optional(name)
    )


def _optional(name: StaticString) -> Bool:
    """Return True for an Optional type name, with or without its module."""
    return name.startswith("Optional[") or name.startswith(
        "std.collections.optional.Optional["
    )


def _standard_string_optional[
    T: AnyType, Candidate: Movable & Deinitable = String
]() -> Bool:
    """Recognize only standard String and its standard Optional wrappers.

    Standard String copy and destruction manage storage without invoking
    user payload methods. Keep this existing standard-value case separate
    from arbitrary custom payloads with observable lifecycle methods.
    """
    comptime if T == Candidate:
        return True
    # Each canonical Optional wrapper lengthens its reflected name. Length
    # only stops the search; admission always requires exact type identity.
    comptime if (
        reflect[Candidate].name().byte_length()
        >= reflect[T].name().byte_length()
    ):
        return False
    return _standard_string_optional[T, Optional[Candidate]]()


def _optional_lifecycle[T: AnyType]() -> Bool:
    """Check the operations omitted by an Optional-valued selection.

    A move-only value can retain its original destructor. A selected retained
    copy creates another object, so both its copy and destruction must have
    no user-visible effects. String uses the fixed standard-value rule.
    """
    comptime if not IsTriviallyMovable[T]:
        return False
    comptime if not conforms_to(T, ImplicitlyCopyable):
        return True
    return (
        IsTriviallyCopyable[T] and IsTriviallyDeinitable[T]
    ) or _standard_string_optional[T]()


def node[L: AnyType, R: AnyType, N: AnyType, I: AnyType]() -> Bool:
    """Check that probes keep one `and`/`or` operator's native semantics.

    Mojo tests a same-type operand again in the enclosing context. Without a
    type join, it converts each evaluated mixed-type operand once. An implicit
    conversion can join two operand types. The probes keep the native operator,
    so its proxy types must select the same semantics. Fixed pure operands
    become `Bool`. An implicit `Optional` wrap can replace a value with
    presence. An Optional-valued selection also needs the lifecycle check.
    A custom type merge can itself return `Bool`, so a native `Bool` result
    alone cannot prove that the operator used mixed-type Boolean fallback.

    Parameters:
        L: The native left operand type.
        R: The native right operand type.
        N: The native result type.
        I: The instrumented result type.

    Returns:
        True if the instrumented operator keeps the native truth semantics.
    """
    # Fixed Bool operands and results already pass the pure-type branch.
    # Check actual type identity before reflected-name classification. This
    # keeps all four query arguments relevant without reflecting this tuple.
    comptime if L == Bool and R == Bool and N == Bool and I == Bool:
        return True
    comptime left = reflect[L].name()
    comptime right = reflect[R].name()
    comptime native = reflect[N].name()
    comptime rewritten = reflect[I].name()
    comptime if _pure(left) and _pure(right) and _pure(native):
        # An Optional can itself be an Optional's element. Both operands
        # being Optional does not rule out a wrap that changes emptiness to
        # presence. Preserve only the same Optional type on both sides.
        comptime if _optional(native):
            return (
                left == native and right == native and _optional_lifecycle[N]()
            )
        return True
    comptime if native == "Bool":
        # A custom __merge_with__ may return Bool and run source-visible
        # code after the left truth test. Proxies erase that merge and use
        # Boolean fallback instead, with the same reflected result type.
        # The pinned reflection API cannot inspect applicable overloads.
        # Refuse this ambiguity rather than silently change execution.
        return False
    # Same-type: one native type, kept by one recording proxy type.
    return rewritten != "Bool" and left == right and left == native


@inline(.never)
def truth[T: Boolable, //, kept: Bool](value: T) -> Bool:
    """Apply the decision's final native truth test to its compound value.

    It runs before `finish` borrows the buffer, so no proxy aliases that borrow.

    Parameters:
        T: The compound condition's type, Bool or a recording proxy.
        kept: Whether every operator keeps its native semantics. See `node`.

    Args:
        value: The compound condition's value.

    Returns:
        The value's Boolean conversion, evaluated exactly once.
    """
    comptime assert kept, (
        "Coverage cannot yet preserve this compound condition: the probes"
        " would change how an and/or operator joins its operand types. The"
        " cause is an implicit conversion between operand types, a retained"
        " implicitly copyable custom Boolable operand, or a custom mixed-type"
        " operator whose Bool result cannot distinguish a user-defined merge"
        " from Boolean fallback, or an Optional result with observable copy,"
        " move, or destructor effects. Do not exclude the source; see the"
        " coverage truth-conversion limit."
    )
    return value.__bool__()


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
        if state == INCONSISTENT:
            record += "?"
        else:
            record += "-" if state < 0 else ("T" if state > 0 else "F")
    _emit_evaluation(record + ";\n")
    return value
