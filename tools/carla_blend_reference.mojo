# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rational derivation of the seven sample-blend fixture rows.

The ledger matches the former `blend_fixture_reference.py` report. The
arithmetic uses exact fractions and binary64 rounding. It does not read
production Mojo code.

    mojo run -I . tools/carla_blend_reference.mojo

The ledger is `tools/carla_lane_oracle/blend-row-ledger.json`.
"""

from std.ffi import c_int, external_call
from std.memory import bitcast
from std.os.path import realpath
from std.pathlib import Path
from std.sys import argv

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._python_float import parse_float, python_repr


def _inf() -> Float64:
    return bitcast[DType.float64](UInt64(0x7FF0000000000000))


def _neg_inf() -> Float64:
    return bitcast[DType.float64](UInt64(0xFFF0000000000000))


def _neg_zero() -> Float64:
    return bitcast[DType.float64](UInt64(0x8000000000000000))


def _max_finite() -> Float64:
    return bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))


def _nextafter(value: Float64, toward: Float64) -> Float64:
    """Return the next double after `value` toward `toward`.

    Args:
        value: The start.
        toward: The direction.

    Returns:
        The adjacent double.
    """
    return external_call["nextafter", Float64](value, toward)


def _finite(value: Float64) -> Bool:
    return value == value and value - value == 0.0


def _ulp(value: Float64) -> Float64:
    var magnitude = abs(value)
    if magnitude == 0.0:
        return _nextafter(0.0, _inf())
    return _nextafter(magnitude, _inf()) - magnitude


def _bits(value: Float64) -> UInt64:
    return bitcast[DType.uint64](value)


def _hex(value: Float64) -> String:
    var bits = _bits(value)
    var digits = String("0123456789abcdef")
    var nibbles = List[UInt8]()
    for _ in range(16):
        nibbles.append(UInt8(bits & 0xF))
        bits >>= 4
    var text = String("0x")
    for index in range(16):
        var nibble = Int(nibbles[15 - index])
        text += String(digits[byte = nibble : nibble + 1])
    return text


def _rn(value: Fraction) -> Float64:
    try:
        return value.to_float()
    except:
        return _inf() if not value.numerator.negative else _neg_inf()


def _up(value: Float64) -> Float64:
    return _nextafter(value, _inf())


def _down(value: Float64) -> Float64:
    return _nextafter(value, _neg_inf())


def _ceil64(value: Fraction) raises -> Float64:
    var rounded = _rn(value)
    if rounded == _inf():
        return rounded
    if rounded == _neg_inf():
        return -_max_finite()
    if Fraction.from_float(rounded) < value:
        return _up(rounded)
    return rounded


def _floor64(value: Fraction) raises -> Float64:
    return -_ceil64(-value)


def _eta() -> Float64:
    return _ulp(0.0)


def _min_mag() raises -> Fraction:
    return Fraction(2).__pow__(-400)


def _max_mag() raises -> Fraction:
    return Fraction(2).__pow__(400)


def _rounding(magnitude: Float64) raises -> Float64:
    if not _finite(magnitude) or magnitude < 0.0:
        return _inf()
    var half = Fraction.from_float(_ulp(magnitude)) / Fraction(2)
    var eta = Fraction.from_float(_eta())
    var chosen = half.copy() if eta < half else eta.copy()
    return _up(_rn(chosen))


def _plus(left: Float64, right: Float64) raises -> Float64:
    if _finite(left) and _finite(right):
        return _rn(Fraction.from_float(left) + Fraction.from_float(right))
    return left + right


def _times(left: Float64, right: Float64) raises -> Float64:
    if _finite(left) and _finite(right):
        return _rn(Fraction.from_float(left) * Fraction.from_float(right))
    return left * right


def _supported(value: Float64) raises -> Bool:
    if not _finite(value):
        return False
    if value == 0.0:
        return True
    var exact = Fraction.from_float(abs(value))
    return _min_mag() <= exact and exact <= _max_mag()


struct Interval(Copyable, Movable):
    var lo: Float64
    var hi: Float64

    def __init__(out self, lo: Float64, hi: Float64):
        self.lo = lo
        self.hi = hi

    @staticmethod
    def point(value: Float64) -> Interval:
        return Interval(value, value)

    @staticmethod
    def exact(lo: Fraction, hi: Fraction) raises -> Interval:
        return Interval(_floor64(lo), _ceil64(hi))

    @staticmethod
    def exact_one(value: Fraction) raises -> Interval:
        return Interval.exact(value, value)

    def point_is(self, value: Float64) -> Bool:
        return self.lo == value and self.hi == value

    def magnitude(self) -> Float64:
        return max(abs(self.lo), abs(self.hi))

    def finite(self) -> Bool:
        return _finite(self.lo) and _finite(self.hi)

    def __neg__(self) -> Interval:
        return Interval(-self.hi, -self.lo)

    def __add__(self, other: Interval) raises -> Interval:
        if self.point_is(0.0):
            return Interval(other.lo, other.hi)
        if other.point_is(0.0):
            return Interval(self.lo, self.hi)
        return Interval(
            _down(_plus(self.lo, other.lo)), _up(_plus(self.hi, other.hi))
        )

    def __mul__(self, other: Interval) raises -> Interval:
        if self.point_is(1.0):
            return Interval(other.lo, other.hi)
        if other.point_is(1.0):
            return Interval(self.lo, self.hi)
        if (self.point_is(0.0) and other.finite()) or (
            other.point_is(0.0) and self.finite()
        ):
            return Interval.point(0.0)
        var values = List[Float64]()
        for left in [self.lo, self.hi]:
            for right in [other.lo, other.hi]:
                values.append(_times(left, right))
        for value in values:
            if value != value:
                return Interval(_neg_inf(), _inf())
        var low = values[0]
        var high = values[0]
        for value in values:
            if value < low:
                low = value
            if value > high:
                high = value
        return Interval(_down(low), _up(high))


def _power_of_two(value: Float64) raises -> Bool:
    if not _finite(value) or value == 0.0:
        return False
    var exact = Fraction.from_float(abs(value))
    var top = exact.numerator.copy()
    return not top.is_zero() and top.bit_length() == top.trailing_zeros() + 1


def _tight_sum(left: Interval, right: Interval) raises -> Interval:
    def endpoint(x: Float64, y: Float64) raises -> Interval:
        if _supported(x) and _supported(y):
            return Interval.exact_one(
                Fraction.from_float(x) + Fraction.from_float(y)
            )
        return Interval.point(x) + Interval.point(y)

    var low = endpoint(left.lo, right.lo)
    var high = endpoint(left.hi, right.hi)
    return Interval(low.lo, high.hi)


def _tight_product(left: Interval, right: Interval) raises -> Interval:
    def endpoint(x: Float64, y: Float64) raises -> Interval:
        if _supported(x) and _supported(y):
            return Interval.exact_one(
                Fraction.from_float(x) * Fraction.from_float(y)
            )
        var product = _times(x, y)
        if (_power_of_two(x) or _power_of_two(y)) and (
            x == 0.0
            or y == 0.0
            or (
                _finite(product)
                and abs(product)
                > bitcast[DType.float64](UInt64(0x0010000000000000))
            )
        ):
            return Interval.point(product)
        return Interval.point(x) * Interval.point(y)

    var values = List[Interval]()
    for x in [left.lo, left.hi]:
        for y in [right.lo, right.hi]:
            values.append(endpoint(x, y))
    var low = values[0].lo
    var high = values[0].hi
    for value in values:
        if value.lo < low:
            low = value.lo
        if value.hi > high:
            high = value.hi
    return Interval(low, high)


struct Frozen(Copyable, Movable):
    var value: Interval
    var error: Float64

    def __init__(out self, value: Interval, error: Float64 = 0.0):
        self.value = value.copy()
        self.error = error

    @staticmethod
    def constant(value: Float64) -> Frozen:
        return Frozen(Interval.point(value), 0.0)

    def __neg__(self) -> Frozen:
        return Frozen(-self.value, self.error)

    def __add__(self, other: Frozen) raises -> Frozen:
        if self.value.point_is(0.0) and self.error == 0.0:
            return Frozen(other.value.copy(), other.error)
        if other.value.point_is(0.0) and other.error == 0.0:
            return Frozen(self.value.copy(), self.error)
        var value = _tight_sum(self.value, other.value)
        var inherited = _up(_plus(self.error, other.error))
        var grown = _up(_plus(value.magnitude(), inherited))
        return Frozen(value, _up(_plus(inherited, _rounding(grown))))

    def __sub__(self, other: Frozen) raises -> Frozen:
        return self + (-other)

    def __mul__(self, other: Frozen) raises -> Frozen:
        var value = _tight_product(self.value, other.value)
        var inherited = (
            Interval.point(self.value.magnitude()) * Interval.point(other.error)
            + Interval.point(other.value.magnitude())
            * Interval.point(self.error)
            + Interval.point(self.error) * Interval.point(other.error)
        ).hi
        var error = _up(
            _plus(
                inherited, _rounding(_up(_plus(value.magnitude(), inherited)))
            )
        )
        if (
            self.value.point_is(0.0)
            and self.error == 0.0
            and other.value.finite()
        ):
            error = 0.0
        elif (
            other.value.point_is(0.0)
            and other.error == 0.0
            and self.value.finite()
        ):
            error = 0.0
        elif self.value.point_is(1.0) and self.error == 0.0:
            error = other.error
        elif other.value.point_is(1.0) and other.error == 0.0:
            error = self.error
        return Frozen(value, error)


def _fraction(value: Float64) raises -> Fraction:
    return Fraction.from_float(value)


def _original(rate: Float64, left: Float64, right: Float64) raises -> Float64:
    var constant = Frozen.constant
    return (
        constant(rate) * constant(left)
        + (constant(1.0) - constant(rate)) * constant(right)
    ).error


struct Parts(Copyable, Movable):
    var present: Bool
    var complement: Float64
    var first: Float64
    var second: Float64
    var final: Float64
    var weighted: Float64
    var magnitude: Float64

    def __init__(out self):
        self.present = False
        self.complement = 0.0
        self.first = 0.0
        self.second = 0.0
        self.final = 0.0
        self.weighted = 0.0
        self.magnitude = 0.0


def _coupled(
    rate: Float64, left: Float64, right: Float64
) raises -> Tuple[Float64, Parts]:
    var parts = Parts()
    if not (_supported(rate) and _supported(left) and _supported(right)):
        return (_inf(), parts^)
    var complement = Interval.exact_one(Fraction(1) - _fraction(rate))
    var rate_exact = _fraction(rate)
    var complement_error = 0.0
    if not (
        Fraction(1) / Fraction(2) <= rate_exact and rate_exact <= Fraction(2)
    ):
        complement_error = _rounding(complement.magnitude())
    var actual = complement + Interval(-complement_error, complement_error)
    var product = Interval.exact_one(_fraction(rate) * _fraction(left))
    var products = List[Fraction]()
    products.append(_fraction(actual.lo) * _fraction(right))
    products.append(_fraction(actual.hi) * _fraction(right))
    var low = products[0].copy()
    var high = products[0].copy()
    if products[1] < low:
        low = products[1].copy()
    if products[1] > high:
        high = products[1].copy()
    var second = Interval.exact(low, high)
    var first_error = _rounding(product.magnitude())
    var second_error = _rounding(second.magnitude())
    var final_magnitude = (
        Interval.point(product.magnitude())
        + Interval.point(second.magnitude())
        + Interval.point(first_error)
        + Interval.point(second_error)
    ).hi
    var final_error = _rounding(final_magnitude)
    var weighted = (
        Interval.point(abs(right)) * Interval.point(complement_error)
    ).hi
    var allowance = (
        Interval.point(weighted)
        + Interval.point(first_error)
        + Interval.point(second_error)
        + Interval.point(final_error)
    ).hi
    parts.present = True
    parts.complement = complement_error
    parts.first = first_error
    parts.second = second_error
    parts.final = final_error
    parts.weighted = weighted
    parts.magnitude = final_magnitude
    return (allowance, parts^)


def _graphs(
    rate: Float64, left: Float64, right: Float64
) raises -> List[Float64]:
    var complement = _rn(Fraction(1) - _fraction(rate))
    var first = _rn(_fraction(rate) * _fraction(left))
    var second = _rn(_fraction(complement) * _fraction(right))
    var values = List[Float64]()
    values.append(_rn(_fraction(first) + _fraction(second)))
    values.append(_rn(_fraction(rate) * _fraction(left) + _fraction(second)))
    values.append(
        _rn(_fraction(complement) * _fraction(right) + _fraction(first))
    )
    return values^


struct Row(Copyable, Movable):
    var index: Int
    var inputs: List[Float64]
    var supported: Bool
    var original: Float64
    var coupled: Float64
    var expected: Float64
    var decrease: Int
    var exact: Fraction
    var derivative: Fraction
    var graphs: List[Float64]
    var required: Fraction
    var parts: Parts

    def __init__(out self):
        self.index = 0
        self.inputs = List[Float64]()
        self.supported = False
        self.original = 0.0
        self.coupled = 0.0
        self.expected = 0.0
        self.decrease = 0
        self.exact = Fraction(0)
        self.derivative = Fraction(0)
        self.graphs = List[Float64]()
        self.required = Fraction(0)
        self.parts = Parts()


def _three(a: Float64, b: Float64, c: Float64) -> List[Float64]:
    var row = List[Float64]()
    row.append(a)
    row.append(b)
    row.append(c)
    return row^


def _inputs() raises -> List[List[Float64]]:
    var rows = List[List[Float64]]()
    var wide = parse_float("1e16")
    var huge = parse_float("1e308")
    var tiny = parse_float("1e-308")
    rows.append(
        _three(parse_float("0.25"), parse_float("100"), parse_float("101"))
    )
    rows.append(_three(parse_float("0.1"), wide, wide + 2.0))
    rows.append(
        _three(
            parse_float("0.9999999999999999"),
            parse_float("-5.1"),
            parse_float("-5.2"),
        )
    )
    rows.append(_three(-2.0, 1.0, 3.0))
    rows.append(_three(3.0, -1.0, 2.0))
    rows.append(_three(0.5, huge, -huge))
    rows.append(_three(parse_float("0.3"), tiny, -tiny))
    return rows^


def _decrease(old: UInt64, chosen: UInt64) -> Int:
    if old >= chosen:
        return Int(old - chosen)
    return -Int(chosen - old)


def derive_rows() raises -> List[Row]:
    """Return the seven blend-fixture rows.

    Returns:
        The rows, in fixture order.

    Raises:
        Error: If a fraction or a rounding step is not finite where required.
    """
    var inputs = _inputs()
    var rows = List[Row]()
    for index in range(len(inputs)):
        var rate = inputs[index][0]
        var left = inputs[index][1]
        var right = inputs[index][2]
        var exact = _fraction(rate) * _fraction(left) + (
            Fraction(1) - _fraction(rate)
        ) * _fraction(right)
        var derivative = _fraction(left) - _fraction(right)
        var graphs = _graphs(rate, left, right)
        var maximum = Fraction(0)
        for value in graphs:
            var gap = _fraction(value) - exact
            if gap < Fraction(0):
                gap = -gap
            if maximum < gap:
                maximum = gap.copy()
        var old = _original(rate, left, right)
        var coupled = _coupled(rate, left, right)
        var chosen = old if old < coupled[0] else coupled[0]
        var row = Row()
        row.index = index
        row.inputs = inputs[index].copy()
        row.supported = _finite(coupled[0])
        row.original = old
        row.coupled = coupled[0]
        row.expected = chosen
        row.decrease = _decrease(_bits(old), _bits(chosen))
        row.exact = exact.copy()
        row.derivative = derivative.copy()
        row.graphs = graphs^
        row.required = maximum.copy()
        row.parts = coupled[1].copy()
        rows.append(row^)
    return rows^


def _fraction_text(value: Fraction) -> String:
    var text = value.numerator.to_string()
    if value.denominator != BigInt(1):
        text += "/" + value.denominator.to_string()
    return text


def _quote(text: String) -> String:
    return '"' + text + '"'


def _indent(level: Int) -> String:
    var pad = String()
    for _ in range(level):
        pad += "  "
    return pad


def ledger_text() raises -> String:
    """Return the ledger JSON, including its final newline.

    Returns:
        The text `json.dumps` writes with an indent of 2.

    Raises:
        Error: If a displayed float is not finite.
    """
    var rows = derive_rows()
    var text = String("[\n")
    for index in range(len(rows)):
        var row = rows[index].copy()
        text += "  {\n"
        text += '    "row": ' + String(row.index) + ",\n"
        text += '    "input_words": [\n'
        for input_index in range(3):
            var comma = "," if input_index < 2 else ""
            text += (
                "      " + _quote(_hex(row.inputs[input_index])) + comma + "\n"
            )
        text += "    ],\n"
        text += (
            '    "supported": ' + ("true" if row.supported else "false") + ",\n"
        )
        text += '    "original_error": ' + python_repr(row.original) + ",\n"
        text += (
            '    "original_error_word": ' + _quote(_hex(row.original)) + ",\n"
        )
        text += '    "coupled_error_word": ' + _quote(_hex(row.coupled)) + ",\n"
        text += '    "expected_error": ' + python_repr(row.expected) + ",\n"
        text += (
            '    "expected_error_word": ' + _quote(_hex(row.expected)) + ",\n"
        )
        text += (
            '    "changed_error": '
            + (
                "true" if _bits(row.original)
                != _bits(row.expected) else "false"
            )
            + ",\n"
        )
        text += '    "error_word_decrease": ' + String(row.decrease) + ",\n"
        text += (
            '    "exact_value": ' + _quote(_fraction_text(row.exact)) + ",\n"
        )
        text += (
            '    "exact_first": '
            + _quote(_fraction_text(row.derivative))
            + ",\n"
        )
        text += '    "exact_second": "0",\n'
        text += '    "value_bracket": [\n'
        text += "      " + _quote(_hex(_floor64(row.exact))) + ",\n"
        text += "      " + _quote(_hex(_ceil64(row.exact))) + "\n"
        text += "    ],\n"
        text += '    "first_bracket": [\n'
        text += "      " + _quote(_hex(_floor64(row.derivative))) + ",\n"
        text += "      " + _quote(_hex(_ceil64(row.derivative))) + "\n"
        text += "    ],\n"
        text += '    "graph_words": [\n'
        for graph in range(3):
            var comma = "," if graph < 2 else ""
            text += "      " + _quote(_hex(row.graphs[graph])) + comma + "\n"
        text += "    ],\n"
        text += (
            '    "required_error_fraction": '
            + _quote(_fraction_text(row.required))
            + ",\n"
        )
        text += (
            '    "required_error_up": '
            + python_repr(_ceil64(row.required))
            + ",\n"
        )
        text += (
            '    "required_error_word": '
            + _quote(_hex(_ceil64(row.required)))
            + ",\n"
        )
        if row.parts.present:
            text += '    "coupled_parts": {\n'
            text += (
                '      "complement_error": '
                + python_repr(row.parts.complement)
                + ",\n"
            )
            text += (
                '      "first_product_error": '
                + python_repr(row.parts.first)
                + ",\n"
            )
            text += (
                '      "second_product_error": '
                + python_repr(row.parts.second)
                + ",\n"
            )
            text += (
                '      "final_error": ' + python_repr(row.parts.final) + ",\n"
            )
            text += (
                '      "weighted_complement": '
                + python_repr(row.parts.weighted)
                + ",\n"
            )
            text += (
                '      "sum_magnitude": '
                + python_repr(row.parts.magnitude)
                + "\n"
            )
            text += "    }\n"
        else:
            text += '    "coupled_parts": null\n'
        var closer = "  },\n" if index + 1 < len(rows) else "  }\n"
        text += closer
    text += "]\n"
    return text


def summary_text() raises -> String:
    """Return the lines the script prints.

    Returns:
        One line per row, with a final newline.

    Raises:
        Error: If a row cannot be derived.
    """
    var rows = derive_rows()
    var text = String()
    for row in rows:
        text += String(row.index)
        text += " "
        text += "True" if row.supported else "False"
        text += " " + _hex(row.original)
        text += " " + _hex(row.coupled)
        text += " " + _hex(row.expected)
        text += " " + String(row.decrease)
        text += " ["
        for index in range(3):
            if index > 0:
                text += ", "
            text += "'" + _hex(row.graphs[index]) + "'"
        text += "]\n"
    return text


def repository() raises -> String:
    """Return the repository root.

    Returns:
        The absolute repository root.
    """
    var directory = realpath(".")
    for _ in range(8):
        if Path(directory + "/assets/carla/town.xodr").exists():
            return directory
        var slash = directory.rfind("/")
        if slash <= 0:
            break
        var parent = String(directory[byte=:slash])
        directory = parent
    return realpath(".")


def main() raises:
    """Write the blend ledger and print each row.

    Raises:
        Error: If the derivation fails or the command line is not empty.
    """
    if len(argv()) != 1:
        raise Error("usage: carla_blend_reference")
    var root = repository()
    var ledger = ledger_text()
    Path(root + "/tools/carla_lane_oracle/blend-row-ledger.json").write_text(
        ledger
    )
    print(summary_text(), end="")
