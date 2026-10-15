# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact fraction controls for stored-Float32 animation clock operations.

    reference_animation_loops [--check | --write]

decodes and rounds every operand without host floating-point arithmetic.
It keeps the three.js r180 boundary, initial reverse and finite-finish
conventions, and imports no production code. `--check` verifies
`assets/animation/loop_reference.txt`; `--write` replaces it; with neither,
the tool prints the controls.

The cases are those of the Python generator this tool replaces: the random
cases come from `random.Random(610)`.
"""

from std.collections import Set
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._python_random import PythonRandom

comptime MAX = (1 << 63) - 1
"""The largest loop count."""
comptime INF = 0x7F800000
"""The bits of Float32 infinity."""
comptime SIGN = 0x80000000
"""The Float32 sign bit."""
comptime PATH = "assets/animation/loop_reference.txt"
"""The saved controls."""


def exact(bits: Int) raises -> Fraction:
    """Decode finite Float32 bits to their exact value.

    Args:
        bits: The float's bits.

    Returns:
        The value.

    Raises:
        Error: If the bits encode an infinity or a NaN.
    """
    var negative = bits & SIGN != 0
    var magnitude = bits & (SIGN - 1)
    var exponent = magnitude >> 23
    var significand = magnitude & 0x7FFFFF
    if exponent >= 255:
        raise Error("not a finite float")
    if exponent != 0:
        significand |= 1 << 23
    var power = max(exponent, 1) - 150
    var value = Fraction(
        BigInt(significand) << power
    ) if power >= 0 else Fraction.of(
        BigInt(significand), BigInt.power_of_two(-power)
    )
    return -value if negative else value^


def _power_of_two(exponent: Int) raises -> Fraction:
    """Return 2**exponent for any integer exponent."""
    if exponent >= 0:
        return Fraction(BigInt.power_of_two(exponent))
    return Fraction.of(BigInt(1), BigInt.power_of_two(-exponent))


def rounded(value: Fraction) raises -> Int:
    """Round a rational to Float32 bits, with ties to even.

    Args:
        value: The value.

    Returns:
        The bits of the nearest Float32; an overflow is infinite.
    """
    var sign = SIGN if value.numerator.negative else 0
    var magnitude = abs(value)
    if magnitude.is_zero():
        return sign
    var exponent = (
        magnitude.numerator.bit_length() - magnitude.denominator.bit_length()
    )
    if magnitude < _power_of_two(exponent):
        exponent -= 1
    var quantum = max(exponent - 23, -149)
    var scaled = magnitude / _power_of_two(quantum)
    var parts = scaled.numerator.divmod(scaled.denominator)
    var significand = parts[0].copy()
    var twice = parts[1] * BigInt(2)
    if twice > scaled.denominator or (
        twice == scaled.denominator and significand.is_odd()
    ):
        significand = significand + BigInt(1)
    if significand >= BigInt(1 << 24):
        significand = significand >> 1
        quantum += 1
    var field = quantum + 150
    if field >= 255:
        return sign | INF
    var stored = significand.to_int()
    if stored < 1 << 23:
        return sign | stored
    return sign | (field << 23) | (stored - (1 << 23))


@fieldwise_init
struct Case(Copyable, Movable):
    """One clock step: the action's state and the step's inputs."""

    var length: Int
    """The clip length's bits."""
    var phase: Int
    """The current time's bits."""
    var seconds: Int
    """The step's bits."""
    var scale: Int
    """The time scale's bits."""
    var mode: Int
    """0 once, 1 repeat, 2 ping-pong."""
    var repetitions: Int
    """The repetitions, or -1 for no limit."""
    var started: Int
    """1 when the action has started."""
    var count: Int
    """The loop count."""

    def values(self) -> List[Int]:
        """Return the fields in order.

        Returns:
            The eight fields.
        """
        return [
            self.length,
            self.phase,
            self.seconds,
            self.scale,
            self.mode,
            self.repetitions,
            self.started,
            self.count,
        ]


def _big(value: Int) -> BigInt:
    """Return a machine integer as a big one."""
    return BigInt(value)


def outcome(control: Case) raises -> List[Int]:
    """Step an animation clock exactly, as three.js r180 does in Float32.

    Args:
        control: The state and the step.

    Returns:
        The failure flag, the stored time, the loops passed, the loop count,
        the started flag, the finished flag, the direction and the finish
        event flag. On failure no timing or event field changes.
    """
    var length = exact(control.length)
    var phase = exact(control.phase)
    var original: List[Int] = [
        1,
        control.phase,
        17,
        control.count,
        control.started,
        1,
        1,
        0,
    ]
    var step_bits = rounded(exact(control.seconds) * exact(control.scale))
    if step_bits & (SIGN - 1) == INF:
        return original^
    var step = exact(step_bits)
    if step.is_zero():
        return [0, control.phase, 0, control.count, control.started, 0, 1, 0]
    var moved_bits = rounded(phase + step)
    if moved_bits & (SIGN - 1) == INF:
        return original^
    var moved = exact(moved_bits)
    var zero = Fraction(0)
    var direction = -1 if step < zero else 1
    if control.mode == 0:
        var finished = moved >= length or moved < zero
        var low = length.copy() if length <= moved else moved.copy()
        var endpoint = zero.copy() if zero >= low else low^
        return [
            0,
            rounded(endpoint),
            0,
            control.count if control.started != 0 else 0,
            1,
            Int(finished),
            direction if finished else 1,
            Int(finished),
        ]
    var limit = _big(MAX)
    var before = phase // length
    if abs(before) > limit:
        return original^
    var after = moved // length
    var delta = after - before
    var running_count = _big(
        0
    ) if control.started == 0 and step > zero else _big(control.count)
    if not delta.is_zero() and control.repetitions >= 0:
        var pending = _big(control.repetitions) - running_count
        if pending < _big(0):
            pending = _big(0)
        if pending <= abs(delta):
            var end: Fraction
            if control.mode == 1:
                end = length.copy() if step > zero else zero.copy()
            else:
                var legs = pending.copy() if pending > _big(1) else _big(1)
                var stop = (
                    before + legs if step > zero else before - legs + _big(1)
                )
                # The initial reverse boundary wraps before complete legs.
                # Zero repetitions finish there without that initial wrap.
                if control.started == 0 and step < zero and pending > _big(1):
                    stop = stop + _big(1)
                end = length.copy() if not (
                    stop % _big(2)
                ).is_zero() else zero.copy()
            return [
                0,
                rounded(end),
                0,
                control.count,
                control.started,
                1,
                direction,
                1,
            ]
    if abs(delta) > limit or running_count + abs(delta) > limit:
        return original^
    var remainder = moved - Fraction(after) * length
    var leg = control.mode == 2 and not (after % _big(2)).is_zero()
    if (
        control.mode == 2
        and control.started == 0
        and step < zero
        and not delta.is_zero()
    ):
        leg = not leg
    var reduced = remainder + length if leg else remainder.copy()
    var stored = rounded(reduced)
    if stored == INF:
        return original^
    var upper = length * Fraction(2) if leg else length.copy()
    if exact(stored) >= upper:
        stored -= 1
    var counted = (
        running_count + abs(delta)
    ).to_int() if not delta.is_zero() else control.count
    return [
        0,
        stored,
        delta.to_int(),
        counted,
        Int(control.started != 0 or not delta.is_zero()),
        0,
        direction,
        0,
    ]


def _key(values: List[Int]) -> String:
    """Return a text that sorts as Python sorts the tuple of integers."""
    var key = String()
    for value in values:
        # Offsetting by 2**63 orders signed values as unsigned ones.
        var digits = String(UInt64(value) ^ (UInt64(1) << 63))
        key += "0" * (20 - digits.byte_length()) + digits + " "
    return key^


def _add(mut seen: Set[String], mut result: List[Case], control: Case):
    """Add a control once."""
    var key = _key(control.values())
    if not key in seen:
        seen.add(key)
        result.append(control.copy())


def cases() raises -> List[Case]:
    """Return every control control, each once, in tuple order.

    Returns:
        The cases.
    """
    var seen = Set[String]()
    var result = List[Case]()
    var lengths = [
        1,
        3,
        0x007FFFFF,
        0x00800000,
        0x3EAAAAAB,
        0x3F800000,
        0x3FC00000,
        0x40000000,
        0x7EFFFFFF,
        0x7F000000,
        0x7F7FFFFF,
    ]
    var steps: List[Int] = [
        0,
        1,
        0x3F800000,
        0x4BFFFFFE,
        0x4BFFFFFF,
        0x4C000000,
        0x4C000001,
        0x5E800000,
        0x5EFFFFFF,
        0x5F000000,
        0x5F000001,
        0x71800000,
        0x7F7FFFFF,
    ]
    for length in lengths:
        var candidates = steps.copy()
        candidates.append(length - 1)
        candidates.append(length)
        candidates.append(min(length + 1, INF - 1))
        for step in candidates:
            for mode in range(3):
                for sign in [0, SIGN]:
                    _add(
                        seen,
                        result,
                        Case(
                            length, 0, step | sign, 0x3F800000, mode, -1, 0, -1
                        ),
                    )
    # Every exponent, ordinary rounding near boundaries, and finite ends.
    for exponent in range(255):
        var length = max(1, (exponent << 23) | 0x400000)
        for offset in [-1, 0, 1]:
            var step = max(0, min(INF - 1, length + offset))
            _add(
                seen,
                result,
                Case(length, length - 1, step, 0x3E800000, 1, -1, 1, 1),
            )
            _add(
                seen,
                result,
                Case(length, length, step | SIGN, 0x3F800000, 2, 3, 1, 1),
            )
    for mode in [1, 2]:
        for step in [
            0x3F800000,
            0x5EFFFFFF,
            0x5F000000,
            0x71800000,
            0x7F7FFFFF,
        ]:
            for sign in [0, SIGN]:
                for reps in [0, 1, 2, 3, MAX]:
                    for state in [(0, -1), (1, 1), (1, MAX)]:
                        _add(
                            seen,
                            result,
                            Case(
                                0x3F800000,
                                0,
                                step | sign,
                                0x3F800000,
                                mode,
                                reps,
                                state[0],
                                state[1],
                            ),
                        )
    var generator = PythonRandom(610)
    var scales = [
        0,
        1,
        0x3EAAAAAB,
        0x3F000000,
        0x3F800000,
        0x3FC00000,
        0x40000000,
        INF - 1,
    ]
    var repetition_choices = [-1, 0, 1, 2, MAX]
    for _ in range(700):
        var length = generator.randrange(_big(1), _big(INF)).to_int()
        # Python builds the tuple, and so draws its last item, before
        # choice draws.
        var drawn = generator.randrange(_big(0), _big(INF)).to_int()
        var phases = [0, length - 1, length, drawn]
        var phase = phases[generator.choice(4)]
        var raw = generator.randrange(_big(0), _big(INF)).to_int()
        var step = raw | [0, SIGN][generator.choice(2)]
        var scale = scales[generator.choice(len(scales))]
        var started = generator.randrange(_big(0), _big(2)).to_int()
        var mode = generator.randrange(_big(0), _big(3)).to_int()
        var repetitions = repetition_choices[
            generator.choice(len(repetition_choices))
        ]
        _add(
            seen,
            result,
            Case(
                length,
                phase,
                step,
                scale,
                mode,
                repetitions,
                started,
                1 if started != 0 else -1,
            ),
        )
    # Stored Float32 add and multiply must not silently become wider operations.
    _add(
        seen,
        result,
        Case(0x3FC00000, 0x3F000000, 0x4C000000, 0x3F800000, 1, -1, 0, -1),
    )
    _add(
        seen,
        result,
        Case(0x3F800000, 0x3F7FFFFF, 0x33800000, 0x3F800000, 1, -1, 0, -1),
    )
    _add(seen, result, Case(0x3F800000, SIGN, SIGN, 0x3F800000, 1, -1, 0, -1))
    # All independent same-leg guard outcomes, including externally set phase.
    for entry in [
        (0xBE800000, 0x3F000000, 1),
        (0x40000000, 0xBF000000, 2),
        (0x3FC00000, 0x3F000000, 2),
        (0x3F800000, 0x3E800000, 1),
        (0x3F800000, 0xBE800000, 2),
    ]:
        _add(
            seen,
            result,
            Case(
                0x3F800000, entry[0], entry[1], 0x3F800000, entry[2], -1, 1, 1
            ),
        )
    for mode in [1, 2]:
        for entry in [
            (MAX, 0x3F800000),
            (MAX - 1, 0x3F800000),
            (MAX, 0x3F000000),
        ]:
            _add(
                seen,
                result,
                Case(
                    0x3F800000, 0, entry[1], 0x3F800000, mode, -1, 1, entry[0]
                ),
            )
        for repetitions in [-1, 1]:
            _add(
                seen,
                result,
                Case(
                    0x3F800000,
                    0x40200000,
                    0xBE800000,
                    0x3F800000,
                    mode,
                    repetitions,
                    0,
                    -1,
                ),
            )
    for repetitions in [-1, 1]:
        _add(
            seen,
            result,
            Case(0x7F7FFFFF, 0, 0xBF800000, 0x3F800000, 2, repetitions, 1, 0),
        )
    for mode in range(3):
        _add(
            seen,
            result,
            Case(
                0x7F7FFFFF, 0x7F7FFFFF, 0x7F7FFFFF, 0x3F800000, mode, -1, 1, 1
            ),
        )
    var keyed = List[String]()
    var by_key = Dict[String, Int]()
    for index in range(len(result)):
        var key = _key(result[index].values())
        keyed.append(key)
        by_key[key] = index
    sort(keyed)
    var ordered = List[Case]()
    for key in keyed:
        ordered.append(result[by_key[key]].copy())
    return ordered^


def controls() raises -> Tuple[Int, String]:
    """Return the number of cases and the controls' text.

    Returns:
        The count, and one line per control: its fields and its outcome.
    """
    var rows = cases()
    var text = String()
    for control in rows:
        var words = List[String]()
        for value in control.values():
            words.append(String(value))
        for value in outcome(control):
            words.append(String(value))
        text += " ".join(words) + "\n"
    return (len(rows), text^)


def main() raises:
    var given = argv()
    var mode = String(given[1]) if len(given) > 1 else String()
    if len(given) > 2 or not (
        mode == "" or mode == "--check" or mode == "--write"
    ):
        print(
            "usage: reference_animation_loops [--check | --write]", file=stderr
        )
        exit(2)
    var made = controls()
    if mode == "--write":
        Path(PATH).write_text(made[1])
    elif mode == "--check":
        if Path(PATH).read_text() != made[1]:
            print(PATH + " is stale", file=stderr)
            exit(1)
    else:
        print(made[1], end="")
    if mode:
        print(String(made[0]) + " exact animation controls verified")
