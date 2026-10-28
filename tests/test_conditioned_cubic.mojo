# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The conditioned cubic stays inside its exact local interval."""

from std.ffi import external_call
from std.memory import bitcast
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tools._bigint import BigInt
from tools._fraction import Fraction


struct Interval(Movable):
    """A closed exact interval."""

    var low: Fraction
    var high: Fraction

    def __init__(out self, var low: Fraction, var high: Fraction):
        self.low = low^
        self.high = high^

    def magnitude(self) -> Fraction:
        var left = abs(self.low)
        var right = abs(self.high)
        if left < right:
            return right^
        return left^


def _point(value: Fraction) -> Interval:
    return Interval(value.copy(), value.copy())


def _word(value: Float64) -> UInt64:
    return bitcast[DType.uint64](value)


def _float(bits: UInt64) -> Float64:
    return bitcast[DType.float64](bits)


def _inf() -> Float64:
    return _float(UInt64(0x7FF0000000000000))


def _neg_inf() -> Float64:
    return _float(UInt64(0xFFF0000000000000))


def _nan() -> Float64:
    return _float(UInt64(0x7FF8000000000000))


def _max_finite() -> Float64:
    return _float(UInt64(0x7FEFFFFFFFFFFFFF))


def _nextafter(value: Float64, toward: Float64) -> Float64:
    return external_call["nextafter", Float64](value, toward)


@no_inline
def _add(left: Float64, right: Float64) -> Float64:
    """Add two floats without a fused multiply-add."""
    return left + right


@no_inline
def _sub(left: Float64, right: Float64) -> Float64:
    """Subtract two floats without a fused multiply-add."""
    return left - right


@no_inline
def _mul(left: Float64, right: Float64) -> Float64:
    """Multiply two floats without a fused multiply-add."""
    return left * right


def _finite(value: Float64) -> Bool:
    return value == value and value - value == 0.0


def _f(value: Float64) raises -> Fraction:
    return Fraction.from_float(value)


def _power(exponent: Int) raises -> Fraction:
    if exponent >= 0:
        return Fraction(BigInt.power_of_two(exponent))
    return Fraction.of(BigInt(1), BigInt.power_of_two(-exponent))


def _pow2(exponent: Int) raises -> Float64:
    return _rn(_power(exponent))


def _floor_log2(value: Fraction) raises -> Int:
    var exponent = value.numerator.bit_length() - value.denominator.bit_length()
    if value < _power(exponent):
        return exponent - 1
    return exponent


def _rho(magnitude: Fraction) raises -> Fraction:
    if magnitude < _power(-1021):
        return _power(-1074)
    return _power(_floor_log2(magnitude) - 53)


def _rn(value: Fraction) raises -> Float64:
    try:
        return value.to_float()
    except:
        if value.numerator.negative:
            return _neg_inf()
        return _inf()


def _same_point(interval: Interval, value: Fraction) -> Bool:
    return interval.low == value and interval.high == value


def _interval_add(left: Interval, right: Interval) raises -> Interval:
    return Interval(left.low + right.low, left.high + right.high)


def _interval_neg(value: Interval) -> Interval:
    return Interval(-value.high, -value.low)


def _interval_sub(left: Interval, right: Interval) raises -> Interval:
    return _interval_add(left, _interval_neg(right))


def _interval_mul(left: Interval, right: Interval) raises -> Interval:
    var values = List[Fraction]()
    values.append(left.low * right.low)
    values.append(left.low * right.high)
    values.append(left.high * right.low)
    values.append(left.high * right.high)
    var low = values[0].copy()
    var high = values[0].copy()
    for value in values:
        if value < low:
            low = value.copy()
        if high < value:
            high = value.copy()
    return Interval(low^, high^)


def _contains(interval: Interval, value: Fraction) -> Bool:
    return interval.low <= value and value <= interval.high


struct Jet(Movable):
    """A value with first and second derivatives and a stored error."""

    var value: Interval
    var first: Interval
    var second: Interval
    var error: Fraction

    def __init__(
        out self,
        var value: Interval,
        var first: Interval,
        var second: Interval,
        var error: Fraction,
    ):
        self.value = value^
        self.first = first^
        self.second = second^
        self.error = error^


def _constant(value: Float64) raises -> Jet:
    var exact = _f(value)
    return Jet(
        _point(exact.copy()),
        _point(Fraction(0)),
        _point(Fraction(0)),
        Fraction(0),
    )


def _variable(low: Float64, high: Float64) raises -> Jet:
    return Jet(
        Interval(_f(low), _f(high)),
        _point(Fraction(1)),
        _point(Fraction(0)),
        Fraction(0),
    )


def _zero_point(interval: Interval) -> Bool:
    return _same_point(interval, Fraction(0))


def _jet_add(left: Jet, right: Jet) raises -> Jet:
    var ideal = _interval_add(left.value, right.value)
    var inherited = left.error + right.error
    var error = inherited + _rho(ideal.magnitude() + inherited)
    if _zero_point(left.value) and left.error == Fraction(0):
        error = right.error.copy()
    elif _zero_point(right.value) and right.error == Fraction(0):
        error = left.error.copy()
    return Jet(
        ideal^,
        _interval_add(left.first, right.first),
        _interval_add(left.second, right.second),
        error^,
    )


def _jet_neg(value: Jet) -> Jet:
    return Jet(
        _interval_neg(value.value),
        _interval_neg(value.first),
        _interval_neg(value.second),
        value.error.copy(),
    )


def _jet_sub(left: Jet, right: Jet) raises -> Jet:
    return _jet_add(left, _jet_neg(right))


def _jet_mul(left: Jet, right: Jet) raises -> Jet:
    var ideal = _interval_mul(left.value, right.value)
    var inherited = (
        left.value.magnitude() * right.error
        + right.value.magnitude() * left.error
        + left.error * right.error
    )
    var error = inherited + _rho(ideal.magnitude() + inherited)
    if (_zero_point(left.value) and left.error == Fraction(0)) or (
        _zero_point(right.value) and right.error == Fraction(0)
    ):
        error = Fraction(0)
    elif _same_point(left.value, Fraction(1)) and left.error == Fraction(0):
        error = right.error.copy()
    elif _same_point(right.value, Fraction(1)) and right.error == Fraction(0):
        error = left.error.copy()
    var first = _interval_add(
        _interval_mul(left.first, right.value),
        _interval_mul(left.value, right.first),
    )
    var two = _point(Fraction(2))
    var second = _interval_add(
        _interval_add(
            _interval_mul(left.second, right.value),
            _interval_mul(_interval_mul(two, left.first), right.first),
        ),
        _interval_mul(left.value, right.second),
    )
    return Jet(ideal^, first^, second^, error^)


def _polynomial(
    a: Float64,
    b: Float64,
    c: Float64,
    d: Float64,
    station: Float64,
    argument: Jet,
) raises -> Jet:
    var local = _jet_sub(argument, _constant(station))
    var inner = _jet_add(_constant(c), _jet_mul(local, _constant(d)))
    var middle = _jet_add(_constant(b), _jet_mul(local, inner))
    return _jet_add(_constant(a), _jet_mul(local, middle))


def _ideal_at(
    a: Fraction,
    b: Fraction,
    c: Fraction,
    d: Fraction,
    station: Fraction,
    x: Fraction,
) raises -> Fraction:
    var local = x - station
    return a + local * (b + local * (c + local * d))


def _ideal(
    a: Float64, b: Float64, c: Float64, d: Float64, station: Float64, x: Float64
) raises -> Fraction:
    return _ideal_at(_f(a), _f(b), _f(c), _f(d), _f(station), _f(x))


def _scalar(
    a: Float64,
    b: Float64,
    c: Float64,
    d: Float64,
    station: Float64,
    x: Float64,
    fused: Int,
) raises -> Float64:
    var local = _rn(_f(x) - _f(station))
    var coefficients = List[Float64]()
    coefficients.append(a)
    coefficients.append(b)
    coefficients.append(c)
    coefficients.append(d)
    var result = coefficients[3]
    var depth = 0
    var index = 2
    while index >= 0:
        var product = _f(local) * _f(result)
        if (fused & (1 << depth)) == 0:
            product = _f(_rn(product))
        result = _rn(_f(coefficients[index]) + product)
        depth += 1
        index -= 1
    return result


def _contains_scalar(jet: Jet, value: Float64) raises -> Bool:
    var got = _f(value)
    return (
        jet.value.low - jet.error <= got and got <= jet.value.high + jet.error
    )


struct Symbol(Movable):
    """A sparse polynomial in seven variables."""

    var keys: List[String]
    var values: List[Fraction]

    def __init__(out self):
        self.keys = List[String]()
        self.values = List[Fraction]()


def _key(powers: List[Int]) -> String:
    var text = String()
    var index = 0
    for power in powers:
        if index > 0:
            text += ","
        text += String(power)
        index += 1
    return text


def _powers(key: String) -> List[Int]:
    var powers = List[Int]()
    var current = 0
    var seen = False
    for byte in key.as_bytes():
        if byte == 44:
            powers.append(current)
            current = 0
            seen = False
        else:
            current = current * 10 + Int(byte - 48)
            seen = True
    if seen or key.byte_length() > 0:
        powers.append(current)
    return powers^


def _symbol_add_term(mut symbol: Symbol, key: String, amount: Fraction) raises:
    if amount == Fraction(0):
        return
    var index = 0
    while index < len(symbol.keys):
        if symbol.keys[index] == key:
            var sum = symbol.values[index] + amount
            if sum == Fraction(0):
                var next = Symbol()
                var place = 0
                while place < len(symbol.keys):
                    if place != index:
                        next.keys.append(String(symbol.keys[place]))
                        next.values.append(symbol.values[place].copy())
                    place += 1
                symbol = next^
            else:
                symbol.values[index] = sum^
            return
        index += 1
    symbol.keys.append(key)
    symbol.values.append(amount.copy())


def _symbol_variable(index: Int) raises -> Symbol:
    var powers = List[Int]()
    var place = 0
    while place < 7:
        if place == index:
            powers.append(1)
        else:
            powers.append(0)
        place += 1
    var symbol = Symbol()
    _symbol_add_term(symbol, _key(powers), Fraction(1))
    return symbol^


def _symbol_get(symbol: Symbol, key: String) -> Fraction:
    var index = 0
    while index < len(symbol.keys):
        if symbol.keys[index] == key:
            return symbol.values[index].copy()
        index += 1
    return Fraction(0)


def _symbol_add(left: Symbol, right: Symbol) raises -> Symbol:
    var symbol = Symbol()
    var index = 0
    while index < len(left.keys):
        _symbol_add_term(
            symbol, String(left.keys[index]), left.values[index].copy()
        )
        index += 1
    index = 0
    while index < len(right.keys):
        _symbol_add_term(
            symbol, String(right.keys[index]), right.values[index].copy()
        )
        index += 1
    return symbol^


def _symbol_neg(value: Symbol) raises -> Symbol:
    var symbol = Symbol()
    var index = 0
    while index < len(value.keys):
        _symbol_add_term(
            symbol, String(value.keys[index]), -value.values[index]
        )
        index += 1
    return symbol^


def _symbol_sub(left: Symbol, right: Symbol) raises -> Symbol:
    return _symbol_add(left, _symbol_neg(right))


def _symbol_scale(value: Symbol, factor: Int) raises -> Symbol:
    var symbol = Symbol()
    if factor == 0:
        return symbol^
    var index = 0
    while index < len(value.keys):
        _symbol_add_term(
            symbol,
            String(value.keys[index]),
            value.values[index] * Fraction(factor),
        )
        index += 1
    return symbol^


def _symbol_mul(left: Symbol, right: Symbol) raises -> Symbol:
    var symbol = Symbol()
    var i = 0
    while i < len(left.keys):
        var j = 0
        while j < len(right.keys):
            var a = _powers(left.keys[i])
            var b = _powers(right.keys[j])
            var powers = List[Int]()
            var k = 0
            while k < 7:
                powers.append(a[k] + b[k])
                k += 1
            _symbol_add_term(
                symbol, _key(powers), left.values[i] * right.values[j]
            )
            j += 1
        i += 1
    return symbol^


def _same_symbol(left: Symbol, right: Symbol) -> Bool:
    if len(left.keys) != len(right.keys):
        return False
    var index = 0
    while index < len(left.keys):
        if _symbol_get(right, left.keys[index]) != left.values[index]:
            return False
        index += 1
    index = 0
    while index < len(right.keys):
        if _symbol_get(left, right.keys[index]) != right.values[index]:
            return False
        index += 1
    return True


def _derivative(value: Symbol, index: Int) raises -> Symbol:
    var symbol = Symbol()
    var place = 0
    while place < len(value.keys):
        var powers = _powers(value.keys[place])
        if powers[index] != 0:
            var factor = powers[index]
            powers[index] -= 1
            _symbol_add_term(
                symbol, _key(powers), value.values[place] * Fraction(factor)
            )
        place += 1
    return symbol^


def _horner(
    a: Float64,
    b: Float64,
    c: Float64,
    d: Float64,
    station: Float64,
    low: Float64,
    high: Float64,
) raises:
    var enclosure = _polynomial(a, b, c, d, station, _variable(low, high))
    var mid = _rn((_f(low) + _f(high)) / Fraction(2))
    var samples = List[Float64]()
    samples.append(low)
    samples.append(mid)
    samples.append(high)
    for x in samples:
        var local = _f(x) - _f(station)
        var fa = _f(a)
        var fb = _f(b)
        var fc = _f(c)
        var fd = _f(d)
        var first = (
            fb + Fraction(2) * fc * local + Fraction(3) * fd * local * local
        )
        var second = Fraction(2) * fc + Fraction(6) * fd * local
        assert_true(_contains(enclosure.value, _ideal(a, b, c, d, station, x)))
        assert_true(_contains(enclosure.first, first))
        assert_true(_contains(enclosure.second, second))
        var fused = 0
        while fused < 8:
            var value = _scalar(a, b, c, d, station, x, fused)
            assert_true(_finite(value))
            assert_true(_contains_scalar(enclosure, value))
            fused += 1


def _legacy_expanded(
    a: Float64, b: Float64, c: Float64, d: Float64, s: Float64
) -> Float64:
    var ss = _mul(s, s)
    var sss = _mul(ss, s)
    var e0 = _sub(_add(_sub(a, _mul(b, s)), _mul(c, ss)), _mul(d, sss))
    var e1 = _add(
        _sub(b, _mul(_mul(2.0, c), s)), _mul(_mul(_mul(3.0, d), s), s)
    )
    var e2 = _sub(c, _mul(_mul(3.0, d), s))
    return _add(e0, _mul(s, _add(e1, _mul(s, _add(e2, _mul(s, d))))))


def test_the_local_polynomial_matches_its_derivatives() raises:
    """The centered and expanded forms match the local polynomial."""
    var a = _symbol_variable(0)
    var b = _symbol_variable(1)
    var c = _symbol_variable(2)
    var d = _symbol_variable(3)
    var x = _symbol_variable(4)
    var s = _symbol_variable(5)
    var center = _symbol_variable(6)
    var local = _symbol_sub(x, s)
    var p = _symbol_add(
        a,
        _symbol_mul(
            local,
            _symbol_add(
                b, _symbol_mul(local, _symbol_add(c, _symbol_mul(local, d)))
            ),
        ),
    )
    var first = _symbol_add(
        b,
        _symbol_mul(
            local,
            _symbol_add(
                _symbol_scale(c, 2), _symbol_mul(local, _symbol_scale(d, 3))
            ),
        ),
    )
    var second = _symbol_add(
        _symbol_scale(c, 2), _symbol_mul(_symbol_scale(d, 6), local)
    )
    assert_true(_same_symbol(_derivative(p, 4), first))
    assert_true(_same_symbol(_derivative(first, 4), second))
    var m = _symbol_sub(center, s)
    var delta = _symbol_sub(x, center)
    var centered = _symbol_add(
        _symbol_add(
            a,
            _symbol_mul(
                m,
                _symbol_add(
                    b, _symbol_mul(m, _symbol_add(c, _symbol_mul(m, d)))
                ),
            ),
        ),
        _symbol_mul(
            delta,
            _symbol_add(
                _symbol_add(
                    b,
                    _symbol_mul(
                        m,
                        _symbol_add(
                            _symbol_scale(c, 2),
                            _symbol_mul(m, _symbol_scale(d, 3)),
                        ),
                    ),
                ),
                _symbol_mul(
                    delta,
                    _symbol_add(
                        _symbol_add(c, _symbol_mul(_symbol_scale(m, 3), d)),
                        _symbol_mul(delta, d),
                    ),
                ),
            ),
        ),
    )
    assert_true(_same_symbol(centered, p))
    var ss = _symbol_mul(s, s)
    var sss = _symbol_mul(ss, s)
    var expanded = _symbol_add(
        _symbol_sub(
            _symbol_add(_symbol_sub(a, _symbol_mul(b, s)), _symbol_mul(c, ss)),
            _symbol_mul(d, sss),
        ),
        _symbol_mul(
            x,
            _symbol_add(
                _symbol_add(
                    _symbol_sub(b, _symbol_mul(_symbol_scale(c, 2), s)),
                    _symbol_mul(_symbol_scale(d, 3), ss),
                ),
                _symbol_mul(
                    x,
                    _symbol_add(
                        _symbol_sub(c, _symbol_mul(_symbol_scale(d, 3), s)),
                        _symbol_mul(x, d),
                    ),
                ),
            ),
        ),
    )
    assert_true(_same_symbol(expanded, p))
    var wrong_delta = _symbol_sub(x, m)
    var wrong = _symbol_add(
        _symbol_add(
            a,
            _symbol_mul(
                m,
                _symbol_add(
                    b, _symbol_mul(m, _symbol_add(c, _symbol_mul(m, d)))
                ),
            ),
        ),
        _symbol_mul(
            wrong_delta,
            _symbol_add(
                _symbol_add(
                    b,
                    _symbol_mul(
                        m,
                        _symbol_add(
                            _symbol_scale(c, 2),
                            _symbol_mul(m, _symbol_scale(d, 3)),
                        ),
                    ),
                ),
                _symbol_mul(
                    wrong_delta,
                    _symbol_add(
                        _symbol_add(c, _symbol_mul(_symbol_scale(m, 3), d)),
                        _symbol_mul(wrong_delta, d),
                    ),
                ),
            ),
        ),
    )
    assert_true(not _same_symbol(wrong, p))


def test_a_centered_interval_contains_the_scalar() raises:
    """The centered interval and every Horner rounding meet at one station."""
    var a = 3.5
    var b = -0.25
    var c = 0.125
    var d = -0.03125
    var s = Float64(1000000)
    var low = _nextafter(s, _neg_inf())
    var high = _add(s, 2.0)
    var center = _rn((_f(low) + _f(high)) / Fraction(2))
    var ap = _point(_f(a))
    var bp = _point(_f(b))
    var cp = _point(_f(c))
    var dp = _point(_f(d))
    var m = _interval_sub(_point(_f(center)), _point(_f(s)))
    var delta = _interval_sub(Interval(_f(low), _f(high)), _point(_f(center)))
    var two = _point(Fraction(2))
    var three = _point(Fraction(3))
    var value = _interval_add(
        ap,
        _interval_mul(
            m,
            _interval_add(
                bp, _interval_mul(m, _interval_add(cp, _interval_mul(m, dp)))
            ),
        ),
    )
    var first = _interval_add(
        bp,
        _interval_mul(
            m,
            _interval_add(
                _interval_mul(two, cp),
                _interval_mul(m, _interval_mul(three, dp)),
            ),
        ),
    )
    var second = _interval_add(cp, _interval_mul(three, _interval_mul(m, dp)))
    var centered = _interval_add(
        value,
        _interval_mul(
            delta,
            _interval_add(
                first,
                _interval_mul(
                    delta, _interval_add(second, _interval_mul(delta, dp))
                ),
            ),
        ),
    )
    var natural = _polynomial(a, b, c, d, s, _variable(low, high))
    var low_bound = centered.low - natural.error
    var other_low = natural.value.low - natural.error
    if low_bound < other_low:
        low_bound = other_low.copy()
    var high_bound = centered.high + natural.error
    var other_high = natural.value.high + natural.error
    if other_high < high_bound:
        high_bound = other_high.copy()
    for x in [low, center, high]:
        assert_true(_contains(centered, _ideal(a, b, c, d, s, x)))
        var fused = 0
        while fused < 8:
            var result = _f(_scalar(a, b, c, d, s, x, fused))
            assert_true(low_bound <= result and result <= high_bound)
            fused += 1


def test_the_expanded_station_value_changes_meaning() raises:
    """The expanded polynomial at its station is not the local value."""
    var a = 3.5
    var b = 0.0
    var c = 0.0
    var d = 1.0
    var s = Float64(1000000)
    assert_equal(_legacy_expanded(a, b, c, d, s), 0.0)
    var fused = 0
    while fused < 8:
        assert_equal(_scalar(a, b, c, d, s, s, fused), 3.5)
        fused += 1
    assert_true(_ideal(a, b, c, d, s, s) == Fraction(7) / Fraction(2))


def test_every_horner_rounding_stays_inside_the_jet() raises:
    """Each fused Horner value stays inside the local jet."""
    var eta = _float(UInt64(1))
    var million = Float64(1000000)
    _horner(3.5, 0.0, 0.0, 1.0, million, million, million)
    _horner(
        3.5,
        -0.25,
        0.03125,
        -0.0078125,
        million,
        _nextafter(million, _neg_inf()),
        _nextafter(million, _inf()),
    )
    _horner(
        -2.0, 3.0, -4.0, 5.0, -million, _sub(-million, 3.0), _add(-million, 4.0)
    )
    _horner(eta, -eta, 0.0, eta, 0.0, -2.0, 2.0)
    _horner(
        1e-300,
        1e-250,
        -1e-200,
        1e-150,
        1e100,
        1e100,
        _nextafter(1e100, _inf()),
    )
    _horner(
        1e300,
        -1e250,
        1e200,
        -1e150,
        1e20,
        1e20,
        _nextafter(1e20, _inf()),
    )
    _horner(0.0, 1.0, 0.0, 0.0, -eta, eta, eta)
    var huge = _pow2(900)
    _horner(1.0, 0.0, 0.0, 0.0, huge, huge, _nextafter(huge, _inf()))


def test_a_constant_polynomial_ignores_the_local_width() raises:
    """A constant cubic keeps its value and zero derivatives."""
    var eta = _float(UInt64(1))
    var station = Float64(1000000)
    var high = _add(station, 100.0)
    var constants = List[Float64]()
    constants.append(0.0)
    constants.append(_float(UInt64(0x8000000000000000)))
    constants.append(3.5)
    constants.append(eta)
    constants.append(1e300)
    for constant in constants:
        var bound = _polynomial(
            constant, 0.0, 0.0, 0.0, station, _variable(station, high)
        )
        assert_true(_same_point(bound.value, _f(constant)))
        assert_true(_same_point(bound.first, Fraction(0)))
        assert_true(_same_point(bound.second, Fraction(0)))
        assert_true(bound.error == Fraction(0))
    var point = _polynomial(
        3.5, 2.0, 3.0, 4.0, station, _variable(station, station)
    )
    assert_true(_same_point(point.value, _f(3.5)))
    assert_true(_same_point(point.first, _f(2.0)))
    assert_true(_same_point(point.second, _f(6.0)))


def test_each_local_origin_uses_its_own_offset() raises:
    """Distinct local origins on one station stay distinct."""
    var x = Fraction(1000010)
    var origins = List[Fraction]()
    origins.append(Fraction(1000000))
    origins.append(Fraction(1000008))
    origins.append(Fraction(1000010))
    var a = Fraction(7) / Fraction(2)
    var b = Fraction(1) / Fraction(4)
    var c = Fraction(-1) / Fraction(8)
    var d = Fraction(1) / Fraction(16)
    for origin in origins:
        var local = x - origin
        var value = (
            a + b * local + c * local * local + d * local * local * local
        )
        assert_true(_ideal_at(a, b, c, d, origin, x) == value)


def test_the_town_fixture_uses_the_local_model() raises:
    """Road 5 in the town fixture matches the local elevation and offset."""
    var text = Path("assets/carla/town.xodr").read_text()
    var start = text.find(
        '<road name="curvy" length="57" id="5" junction="-1">'
    )
    var end = text.find("</road>", start)
    assert_true(start >= 0 and end > start)
    var road = String(text[byte=start:end])
    var first_elevation = road.find(
        '<elevation s="0" a="1" b="0.02" c="0" d="0"/>'
    )
    var second_elevation = road.find(
        '<elevation s="30" a="1.6" b="0" c="0.001" d="0"/>'
    )
    assert_true(first_elevation >= 0 and second_elevation > first_elevation)
    var first_offset = road.find(
        '<laneOffset s="0" a="0.5" b="0" c="0" d="0"/>'
    )
    var second_offset = road.find(
        '<laneOffset s="20" a="0.5" b="0.01" c="0" d="0"/>'
    )
    assert_true(first_offset >= 0 and second_offset > first_offset)
    assert_true(road.find('<laneSection s="0">') >= 0)
    assert_true(
        road.find(
            '<lane id="-1" type="driving">\n            <width sOffset="0"'
            ' a="3.5" b="0" c="0" d="0"/>'
        )
        >= 0
    )
    assert_true(
        road.find(
            '<lane id="-2" type="shoulder">\n            <width sOffset="0"'
            ' a="1.5" b="0" c="0" d="0"/>'
        )
        >= 0
    )
    var samples = List[Float64]()
    samples.append(0.0)
    samples.append(4.5865310585259165)
    samples.append(10.0)
    samples.append(_nextafter(20.0, _neg_inf()))
    for x in samples:
        assert_true(
            _ideal(1.0, 0.02, 0.0, 0.0, 0.0, x)
            == Fraction(1) + _f(0.02) * _f(x)
        )
        var fused = 0
        while fused < 8:
            assert_equal(_scalar(0.5, 0.0, 0.0, 0.0, 0.0, x, fused), 0.5)
            fused += 1
    for x in [Float64(40), Float64(50)]:
        var rise = _f(x) - _f(30.0)
        assert_true(
            _ideal(1.6, 0.0, 0.001, 0.0, 30.0, x)
            == _f(1.6) + _f(0.001) * rise * rise
        )
        assert_true(Fraction(2) * _f(0.001) * rise == _f(0.002) * rise)
        assert_true(
            _ideal(0.5, 0.01, 0.0, 0.0, 20.0, x)
            == _f(0.5) + _f(0.01) * (_f(x) - _f(20.0))
        )


def test_a_later_shoulder_stays_below_the_offset_bound() raises:
    """The later shoulder offset stays inside the outward rational bound."""
    var low = _f(0.5)
    var high = low + _f(0.01) * Fraction(37)
    assert_true(low >= Fraction(1) / Fraction(2))
    assert_true(high < Fraction(22) / Fraction(25))
    var quarter = Fraction(17) / Fraction(4)
    var h_low = quarter - high
    var h_high = quarter - low
    assert_true(h_low > Fraction(0))
    assert_true(h_high <= Fraction(15) / Fraction(4))
    var center_y_lower = Fraction(105) - h_high
    var gap = center_y_lower - Fraction(-105)
    assert_true(gap * gap == Fraction(680625) / Fraction(16))


def test_a_translated_fixture_keeps_a_zero_origin() raises:
    """A moved section keeps the constant polynomial origin at zero."""
    var base = Float64(1e20)
    var curves = List[Float64]()
    curves.append(0.0)
    curves.append(1e-40)
    for c in curves:
        var k = 0
        while k < 6:
            var x = _add(base, _mul(Float64(k), 16384.0))
            var fused = 0
            while fused < 8:
                var current = _scalar(0.0002, 0.0, c, 0.0, 0.0, x, fused)
                assert_equal(
                    current,
                    _scalar(
                        0.0002,
                        0.0,
                        c,
                        0.0,
                        _float(UInt64(0x8000000000000000)),
                        x,
                        fused,
                    ),
                )
                fused += 1
            var local = x
            var inner = _add(c, _mul(local, 0.0))
            var middle = _add(0.0, _mul(local, inner))
            var legacy = _add(0.0002, _mul(local, middle))
            assert_equal(_scalar(0.0002, 0.0, c, 0.0, 0.0, x, 0), legacy)
            k += 1


def test_record_coefficients_keep_their_bits() raises:
    """A binary64 copy keeps signed zero and a subnormal."""
    var values = List[Float64]()
    values.append(_float(UInt64(0x8000000000000000)))
    values.append(0.0)
    values.append(_float(UInt64(1)))
    values.append(_float(UInt64(0x8000000000000001)))
    values.append(1e300)
    for value in values:
        assert_equal(_word(value), _word(_float(_word(value))))


def test_a_rounded_constant_rejects_an_overflowing_origin() raises:
    """A constant cubic accepts only a finite origin inside 2**400."""
    var bound = _power(400)
    assert_true(bound + bound <= _power(401))
    assert_true(_power(401) < _f(_max_finite()))
    var refused = List[Float64]()
    refused.append(_inf())
    refused.append(_neg_inf())
    refused.append(_nan())
    refused.append(_max_finite())
    refused.append(-_max_finite())
    refused.append(_nextafter(_pow2(400), _inf()))
    for origin in refused:
        var supported = False
        if _finite(origin):
            if origin == 0.0:
                supported = True
            else:
                var magnitude = abs(origin)
                supported = _pow2(-400) <= magnitude and magnitude <= _pow2(400)
        assert_true(not supported)
    var accepted = List[Float64]()
    accepted.append(-_pow2(400))
    accepted.append(0.0)
    accepted.append(_pow2(400))
    for origin in accepted:
        for x in accepted:
            assert_true(_finite(_sub(x, origin)))
            var fused = 0
            while fused < 8:
                assert_equal(_scalar(3.5, 0.0, 0.0, 0.0, origin, x, fused), 3.5)
                fused += 1


def test_a_finite_subtraction_can_overflow() raises:
    """The difference of the extreme finite values is not a finite double."""
    var maximum = _max_finite()
    var rounded = _rn(_f(maximum) - _f(-maximum))
    assert_true(rounded == _inf() or rounded == _neg_inf())


def main() raises:
    """Run the conditioned cubic tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
