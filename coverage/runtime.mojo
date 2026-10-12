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

# The bound of an owned operand, and of an implicitly copyable one.
comptime _Owned = Boolable & Movable & Deinitable
comptime _Copied = _Owned & ImplicitlyCopyable

# True if copies, moves and destruction of `T` run no source code.
comptime _bitwise[T: AnyType] = (
    downcast[T, _Copied].__copy_ctor_is_trivial
    and downcast[T, _Copied].__move_ctor_is_trivial
    and downcast[T, _Copied].__del__is_trivial
) if conforms_to(T, _Copied) else False


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


# The probe of a temporary custom operand: an owning proxy or its truth. A
# proxy owns the operand, so the operand must move into it. Only a bitwise move
# runs no source code. An operand with a user-defined move constructor is
# converted once in place instead, and the probe is its `Bool`.
comptime _Temporary[T: _Owned, origin: Origin[mut=True]] = (
    _OwnedLeaf[T, origin] if T.__move_ctor_is_trivial else Bool
)

# The probe of a retained custom operand. A bitwise operand is copied into an
# owning proxy. Its proxy type has no operand origin, so a one-type operator
# stays one-type, also with a temporary of the same type. Another operand is
# borrowed with its origin.
comptime _Retained[
    T: Boolable, value_origin: Origin[mut=False], origin: Origin[mut=True]
] = (
    _OwnedLeaf[downcast[T, _Owned], origin] if _bitwise[T] else _BorrowedLeaf[
        T, value_origin, origin
    ]
)


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
) -> _Temporary[T, origin]:
    """Probe a temporary custom operand without an extra move or conversion.

    Mojo selects this overload for a temporary and the `ref` overload for a
    retained value. The trailing pack makes both a fallback after the fixed
    pure-type overloads. A temporary argument binds to `value` without a move.

    A bitwise-movable operand moves into a proxy and is not converted here.
    The native `and`, `or`, `not` and truth context convert the proxy as they
    would the operand.

    Another operand is converted here once, and then destroyed. `not` also
    converts a temporary once, at once, and then destroys it. A native
    one-type operator moves the selected operand into its result instead, so
    `node` refuses it: the probes are `Bool`. `node` also refuses a two-type
    operator of a custom operand.

    Args:
        value: The temporary operand, never copied.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.
        extra: The overload-resolution fallback pack; callers leave it empty.

    Returns:
        A proxy that owns the operand and records its truth conversions, or
        the operand's recorded truth if it has a user-defined move constructor.
    """
    comptime if T.__move_ctor_is_trivial:
        return rebind_var[_Temporary[T, origin]](
            _OwnedLeaf[T, origin](value^, Pointer(to=values), id, index)
        )
    else:
        return rebind_var[_Temporary[T, origin]](
            leaf(value.__bool__(), values, id, index)
        )


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

    A bitwise operand is copied into an owning proxy instead. Its copy, move
    and destruction run no source code, so the extra copy is not observable.
    The native and instrumented truth tests read equal bytes.

    Args:
        value: The retained operand. Only a bitwise operand is copied.
        values: The current invocation's operand buffer.
        id: The condition's static hit identifier.
        index: The condition's slot in the buffer.
        extra: The overload-resolution fallback pack; callers leave it empty.

    Returns:
        A proxy that owns a bitwise copy of the operand or borrows it, and
        that records its truth conversions.
    """
    comptime if _bitwise[T]:
        comptime O = downcast[T, _Owned]
        # A bitwise copy: no copy constructor runs.
        var copy = rebind[downcast[T, _Copied]](value)
        return rebind_var[_Retained[T, value_origin, origin]](
            _OwnedLeaf[O, origin](
                rebind_var[O](copy^), Pointer(to=values), id, index
            )
        )
    else:
        return rebind_var[_Retained[T, value_origin, origin]](
            _BorrowedLeaf[T, value_origin, origin](
                Pointer(to=value), Pointer(to=values), id, index
            )
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
    ) -> _Temporary[downcast[Self.N, _Owned], origin] where conforms_to(
        Self.N, _Owned
    ):
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
            A proxy that owns the operand and records its truth conversions,
            or the operand's recorded truth if it has a user-defined move
            constructor.
        """
        comptime T = downcast[Self.N, _Owned]
        comptime if T.__move_ctor_is_trivial:
            return rebind_var[_Temporary[T, origin]](
                _OwnedLeaf[T, origin](value^, Pointer(to=values), id, index)
            )
        else:
            return rebind_var[_Temporary[T, origin]](
                leaf(value.__bool__(), values, id, index)
            )

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
    ) -> _Temporary[T, origin]:
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
            The probe that `leaf` makes for a temporary operand.
        """
        comptime if T.__move_ctor_is_trivial:
            return rebind_var[_Temporary[T, origin]](
                _OwnedLeaf[T, origin](value^, Pointer(to=values), id, index)
            )
        else:
            return rebind_var[_Temporary[T, origin]](
                leaf(value.__bool__(), values, id, index)
            )

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
    comptime prefix = proxy[byte = : proxy.find("[") + 1]
    return name.startswith(prefix)


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
    temporary with a user-defined move constructor is already `Bool`, so a
    same-type operator of such temporaries is refused too.

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
    # Same-type: one native type, kept by one recording proxy type. The
    # native operator selects an owned copy or move of a retained operand.
    # A borrowing proxy selects only the borrow, so it cannot keep that.
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
        " operator that selects a retained operand whose copy runs source"
        " code, a one-type operator over a type with a user-defined move"
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
