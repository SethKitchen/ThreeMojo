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
from std.iter import downcast
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

# The bound of an owned operand.
comptime _Owned = Boolable & Movable & Deinitable


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

    A one-type operator selects an `Optional` by a move or a copy. That can
    run the element's own move, copy and destructor code. `node` refuses such
    an operator, because this probe records only the truth.

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


struct _BorrowedLeaf[
    T: Boolable, value_origin: Origin[mut=False], origin: Origin[mut=True]
](Boolable, Movable):
    """A borrowed retained operand that records each native truth conversion.

    The type keeps the operand origin, so Mojo keeps the operand alive. A
    surrounding `not` converts the borrowed operand once and does not copy it.
    A native mixed-type `and` or `or` also converts it once, but a custom
    merge can replace that conversion, so `node` refuses the form. A native
    same-type operator selects an owned copy or move of the operand. `node`
    refuses a same-type operator of these proxies too.
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


# A temporary custom operand is converted in place. Even a bitwise move
# into an owning proxy changes its address. Unary not converts once here;
# node refuses operators that instead select and reconvert an owned value.
# A retained custom operand must keep its original identity for its first
# truth test. A bitwise copy still changes the address seen by __bool__.
comptime _Retained[
    T: Boolable, value_origin: Origin[mut=False], origin: Origin[mut=True]
] = _BorrowedLeaf[T, value_origin, origin]


@inline(.never)
def leaf[
    T: _Owned,
    origin: Origin[mut=True],
    //,
    *Ts: AnyType,
](
    var value: T,
    ref[origin] values: List[Int],
    id: StaticString,
    index: Int,
    *extra: *Ts,
) -> Bool:
    """Convert a temporary custom operand in its original storage.

    A temporary argument binds to `value` without a move. Moving it into a
    proxy would change the object observed by an address-sensitive __bool__,
    even when the move runs no source code. Convert once in place, as unary
    `not` does, and destroy at the same expression boundary. `node` refuses
    a custom one-type operator: it must select an owned object and convert
    that object again. A mixed custom operator remains refused too.

    Args:
        value: The original temporary, never copied or moved by the probe.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.
        extra: The overload-resolution fallback pack; callers leave it empty.

    Returns:
        The original object's truth, recorded exactly once.
    """
    return leaf(value.__bool__(), values, id, index)


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
) -> _Retained[T, value_origin, origin]:
    """Probe a retained custom operand in a recording proxy.

    A surrounding `not` converts a retained operand once, without a copy, so
    a borrowing proxy keeps it. `node` refuses a native mixed-type `and` or
    `or` of a custom operand, because a custom merge can replace its
    conversion. Native same-type `and` or `or` copies or moves a retained
    operand into its result, and converts that value again. A borrowing proxy
    cannot copy or move the operand, so `node` refuses a same-type operator
    whose result is a borrowing proxy.

    Even a bitwise copy changes the operand's address. A custom truth test
    can observe that identity, so no retained operand is copied here. Native
    selection happens only after its first truth test; `node` refuses a
    same-type selection whose borrowing proxy cannot reproduce that step.

    Args:
        value: The original retained operand, borrowed without copying.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.
        extra: The overload-resolution fallback pack; callers leave it empty.

    Returns:
        A proxy that borrows the original operand and records its truth
        conversions without changing its identity.
    """
    return _BorrowedLeaf[T, value_origin, origin](
        Pointer(to=value), Pointer(to=values), id, index
    )


struct _Right[N: AnyType](TrivialRegisterPassable):
    """Probe a right operand of an `and` or `or` operator.

    `N` is the native result type of the operator. A native one-type operator
    selects its right operand without a conversion, and its result owns it.
    A retained right operand is copied, or moved at its last use, when Mojo
    evaluates it. An owned argument of type `N` gets exactly that copy or
    move, at that point. Mojo prefers this overload because its argument type
    is not generic. Every other operand is probed as `leaf` probes it.
    """

    def __init__(out self):
        """Make a probe for one right operand."""
        pass

    @inline(.never)
    def of(
        self, value: Bool, mut values: List[Int], id: StaticString, index: Int
    ) -> Bool:
        """Record a Boolean right operand.

        Args:
            value: The original Boolean operand.
            values: The current invocation's operand buffer.
            id: The condition's static hit identifier.
            index: The condition's slot in the buffer.

        Returns:
            The unchanged operand.
        """
        return leaf(value, values, id, index)

    @inline(.never)
    def of(
        self,
        value: SIMD[DType.bool, 1],
        mut values: List[Int],
        id: StaticString,
        index: Int,
    ) -> Bool:
        """Record a scalar SIMD right operand.

        Args:
            value: The Boolean scalar, borrowed without copying.
            values: The current invocation's operand buffer.
            id: The condition's static hit identifier.
            index: The condition's slot in the buffer.

        Returns:
            The scalar's Boolean value.
        """
        return leaf(value, values, id, index)

    @inline(.never)
    def of(
        self, value: Int, mut values: List[Int], id: StaticString, index: Int
    ) -> Bool:
        """Record an integer right operand.

        Args:
            value: The integer, borrowed without copying.
            values: The current invocation's operand buffer.
            id: The condition's static hit identifier.
            index: The condition's slot in the buffer.

        Returns:
            The operand's Boolean value.
        """
        return leaf(value, values, id, index)

    @inline(.never)
    def of(
        self,
        value: String,
        mut values: List[Int],
        id: StaticString,
        index: Int,
    ) -> Bool:
        """Record a retained string right operand.

        Args:
            value: The string, borrowed without copying.
            values: The current invocation's operand buffer.
            id: The condition's static hit identifier.
            index: The condition's slot in the buffer.

        Returns:
            The operand's Boolean value.
        """
        return leaf(value, values, id, index)

    @inline(.never)
    def of[
        T: Movable, //
    ](
        self,
        value: Optional[T],
        mut values: List[Int],
        id: StaticString,
        index: Int,
    ) -> Bool:
        """Record a retained `Optional` right operand.

        Parameters:
            T: The element type.

        Args:
            value: The optional value, borrowed without copying.
            values: The current invocation's operand buffer.
            id: The condition's static hit identifier.
            index: The condition's slot in the buffer.

        Returns:
            The operand's Boolean value.
        """
        return leaf(value, values, id, index)

    @inline(.never)
    def of[
        T: Movable, //
    ](
        self,
        value: List[T],
        mut values: List[Int],
        id: StaticString,
        index: Int,
    ) -> Bool:
        """Record a retained list right operand.

        Parameters:
            T: The element type.

        Args:
            value: The list, borrowed without copying.
            values: The current invocation's operand buffer.
            id: The condition's static hit identifier.
            index: The condition's slot in the buffer.

        Returns:
            The operand's Boolean value.
        """
        return leaf(value, values, id, index)

    @inline(.never)
    def of[
        origin: Origin[mut=True], //
    ](
        self,
        var value: downcast[Self.N, _Owned],
        ref[origin] values: List[Int],
        id: StaticString,
        index: Int,
    ) -> Bool where conforms_to(Self.N, _Owned):
        """Own a right operand of the operator's result type.

        Mojo copies a retained operand into `value`, or moves it at its last
        use, as the native operator does. A temporary binds without a move.
        A fixed pure overload is preferred where one applies. The only
        constraint is a trait conformance, so a generic caller can prove it.

        Parameters:
            origin: The operand buffer's origin.

        Args:
            value: The operand, owned as the native result owns it.
            values: The current invocation's operand buffer.
            id: The condition's static hit identifier.
            index: The condition's slot in the buffer.

        Returns:
            The original owned argument's truth, recorded without an extra
            move. Custom one-type selection is refused by `node`.
        """
        return leaf(value.__bool__(), values, id, index)

    @inline(.never)
    def of[
        T: _Owned,
        origin: Origin[mut=True],
        //,
        *Ts: AnyType,
    ](
        self,
        var value: T,
        ref[origin] values: List[Int],
        id: StaticString,
        index: Int,
        *extra: *Ts,
    ) -> Bool:
        """Probe a temporary right operand of another type.

        Parameters:
            T: The operand type.
            origin: The operand buffer's origin.
            Ts: The overload-resolution fallback pack.

        Args:
            value: The temporary operand, never copied.
            values: The current invocation's operand buffer.
            id: The condition's static hit identifier.
            index: The condition's slot in the buffer.
            extra: The overload-resolution fallback pack; callers leave it
                empty.

        Returns:
            The temporary operand's truth, recorded in place without a move.
        """
        return leaf(value.__bool__(), values, id, index)

    @inline(.never)
    def of[
        T: Boolable,
        value_origin: Origin[mut=False],
        origin: Origin[mut=True],
        //,
        *Ts: AnyType,
    ](
        self,
        ref[value_origin] value: T,
        ref[origin] values: List[Int],
        id: StaticString,
        index: Int,
        *extra: *Ts,
    ) -> _Retained[T, value_origin, origin]:
        """Probe a retained right operand of another type.

        Parameters:
            T: The operand type.
            value_origin: The operand's origin.
            origin: The operand buffer's origin.
            Ts: The overload-resolution fallback pack.

        Args:
            value: The retained operand, borrowed without a copy.
            values: The current invocation's operand buffer.
            id: The condition's static hit identifier.
            index: The condition's slot in the buffer.
            extra: The overload-resolution fallback pack; callers leave it
                empty.

        Returns:
            The probe that `leaf` makes for a retained operand.
        """
        return leaf(value, values, id, index)


def right[N: AnyType]() -> _Right[N]:
    """Make the probe of one right operand of an `and` or `or` operator.

    Parameters:
        N: The operator's native result type.

    Returns:
        A probe whose `of` overloads record the operand.
    """
    return _Right[N]()


# True for the fixed scalar types of `_pure`, by type identity. Their reflected
# names are "Bool", "SIMD[DType.bool, 1]", "SIMD[DType.int, 1]" and "String".
comptime _scalar[T: AnyType] = (
    T == Bool or T == Scalar[DType.bool] or T == Int or T == String
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
        or _starts(name, "List[")
        or _optional(name)
    )


def _starts(name: StaticString, prefix: StaticString) -> Bool:
    """Return True if `name` starts with `prefix`, compared byte by byte.

    It gives the result of `name.startswith(prefix)`. `node` evaluates the
    reflected-name tests at compile time, and pinned Mojo 1.1.0 can deadlock
    a single-threaded build that evaluates `startswith` there. The coverage
    build of `materials/nodes.mojo` waits forever on one such test.

    Args:
        name: A reflected type name.
        prefix: The prefix to look for.

    Returns:
        True if the first bytes of `name` are the bytes of `prefix`.
    """
    var size = prefix.byte_length()
    if name.byte_length() < size:
        return False
    var text = name.as_bytes()
    var head = prefix.as_bytes()
    for index in range(size):
        if text[index] != head[index]:
            return False
    return True


def _bracket(name: StaticString) -> Int:
    """Return the byte length of `name` through its first `[`.

    It gives `name.find("[") + 1` without `find`, for the reason that
    `_starts` gives.

    Args:
        name: A reflected type name.

    Returns:
        The index of the first `[` plus one, or 0 if `name` has none.
    """
    var text = name.as_bytes()
    for index in range(len(text)):
        if text[index] == UInt8(ord("[")):
            return index + 1
    return 0


def _optional(name: StaticString) -> Bool:
    """Return True for an Optional type name, with or without its module."""
    return _starts(name, "Optional[") or _starts(
        name, "std.collections.optional.Optional["
    )


def _borrowed(name: StaticString) -> Bool:
    """Return True for the type name of a borrowing recording proxy.

    The prefix comes from the proxy's own reflected name, so it follows the
    runtime module path. A source type name always has its own module.

    Args:
        name: A reflected type name.

    Returns:
        True if the name is a `_BorrowedLeaf` instantiation.
    """
    comptime proxy = reflect[
        _BorrowedLeaf[Bool, ImmutAnyOrigin, MutAnyOrigin]
    ].name()
    comptime prefix = proxy[byte = : _bracket(proxy)]
    return _starts(name, prefix)


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
    A same-type result must be an owning proxy: a borrowing proxy cannot copy
    or move the retained left operand that the native operator selects. A
    temporary is converted in place to `Bool`: an owning proxy would add an
    identity-changing move. Custom same-type operators are therefore refused
    for temporaries as well, including those with bitwise moves.

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
    # Fixed scalar operands and results take the pure-type branch below, and
    # a scalar result is not Optional. Type identity answers them without
    # the reflected-name tests, such as `flag or mask.reduce_or()`.
    comptime if _scalar[L] and _scalar[R] and _scalar[N]:
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
    # A custom same-type operator must select an owned object after the left
    # truth test, then convert that selected object. Retained proxies borrow;
    # temporary probes convert in place to Bool. Neither supplies an owning
    # proxy with native identity, so no custom same-type selection is admitted.
    return (
        rewritten != "Bool"
        and not _borrowed(rewritten)
        and left == right
        and left == native
    )


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
        " cause is an implicit conversion between operand types, a one-type"
        " operator that selects a retained custom operand before its native"
        " selection point (including identity-changing bitwise copies), a"
        " one-type operator over custom temporaries with identity-changing"
        " extra moves, a one-type operator over a type with a user-defined move"
        " constructor, a custom mixed-type operator whose Bool result cannot"
        " distinguish a user-defined merge from Boolean fallback, or an"
        " Optional result with observable copy, move, or destructor effects."
        " Do not exclude the source; see the coverage truth-conversion limit."
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
