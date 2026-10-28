# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sampled blend graph stays inside its exact rational bound."""

from std.ffi import external_call
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true

from tools._bigint import BigInt
from tools._fraction import Fraction


def _inf() -> Float64:
    """Return positive infinity."""
    return bitcast[DType.float64](UInt64(0x7FF0000000000000))


def _neg_inf() -> Float64:
    """Return negative infinity."""
    return bitcast[DType.float64](UInt64(0xFFF0000000000000))


def _nextafter(value: Float64, toward: Float64) -> Float64:
    """Return the next double after `value` toward `toward`."""
    return external_call["nextafter", Float64](value, toward)


def _ulp(value: Float64) -> Float64:
    """Return the gap to the next larger magnitude."""
    var magnitude = abs(value)
    if magnitude == 0.0:
        return _nextafter(0.0, _inf())
    return _nextafter(magnitude, _inf()) - magnitude


def _min_mag() raises -> Fraction:
    """Return 2**-400."""
    return Fraction(2).__pow__(-400)


def _max_mag() raises -> Fraction:
    """Return 2**400."""
    return Fraction(2).__pow__(400)


def _f(value: Float64) raises -> Fraction:
    """Return the exact fraction for a finite float."""
    return Fraction.from_float(value)


def _rn(value: Fraction) raises -> Float64:
    """Return `float(value)`."""
    return value.to_float()


def _pow2(exponent: Int) raises -> Float64:
    """Return 2**exponent as a double."""
    if exponent >= 0:
        return _rn(Fraction(BigInt.power_of_two(exponent)))
    return _rn(Fraction.of(BigInt(1), BigInt.power_of_two(-exponent)))


def _rounding(magnitude: Fraction) raises -> Fraction:
    """Return half an ulp of the outward rounding of `magnitude`."""
    var huge = _max_mag() * _max_mag() * Fraction(4)
    if magnitude < Fraction(0) or huge < magnitude:
        raise Error("unsupported")
    if magnitude == Fraction(0):
        return Fraction(0)
    var rounded = _rn(magnitude)
    if _f(rounded) < magnitude:
        rounded = _nextafter(rounded, _inf())
    return _f(_ulp(rounded)) / Fraction(2)


def _bound(
    low: Fraction,
    high: Fraction,
    error: Fraction,
    a: Fraction,
    b: Fraction,
) raises -> Fraction:
    """Return the coupled blend bound, or raise when the domain is refused."""
    if high < low or error < Fraction(0):
        raise Error("unsupported")
    var ends = List[Fraction]()
    ends.append(low - error)
    ends.append(high + error)
    ends.append(a.copy())
    ends.append(b.copy())
    var small = _min_mag()
    var large = _max_mag()
    for value in ends:
        if not value.is_zero():
            var size = abs(value)
            if size < small or large < size:
                raise Error("unsupported")
    var mr = abs(low - error)
    var other = abs(high + error)
    if mr < other:
        mr = other.copy()
    var left = abs(Fraction(1) - low + error)
    var right = abs(Fraction(1) - high - error)
    var mc0 = left.copy()
    if mc0 < right:
        mc0 = right.copy()
    var ec = _rounding(mc0.copy())
    var mc = mc0 + ec
    var ep = _rounding(abs(a) * mr)
    var eq = _rounding(abs(b) * mc)
    var ez = _rounding(abs(a) * mr + abs(b) * mc + ep + eq)
    return abs(a - b) * error + abs(b) * ec + ep + eq + ez


def _graphs(rate: Float64, a: Float64, b: Float64) raises -> List[Float64]:
    """Return the three rounded product/sum graphs."""
    var complement = _rn(Fraction(1) - _f(rate))
    var p = _rn(_f(rate) * _f(a))
    var q = _rn(_f(complement) * _f(b))
    var out = List[Float64]()
    out.append(_rn(_f(p) + _f(q)))
    out.append(_rn(_f(rate) * _f(a) + _f(q)))
    out.append(_rn(_f(complement) * _f(b) + _f(p)))
    return out^


def _check(
    rates: List[Float64], a: Float64, b: Float64, error: Fraction
) raises:
    """Require every graph at `rates` to stay inside the coupled bound."""
    var low = _f(rates[0])
    var high = low.copy()
    for rate in rates:
        var exact = _f(rate)
        if exact < low:
            low = exact.copy()
        if high < exact:
            high = exact.copy()
    low = low - error
    high = high + error
    var limit = _bound(low, high, error.copy(), _f(a), _f(b))
    for rate in rates:
        for sign in [-1, 0, 1]:
            var ideal = _f(rate) + Fraction(sign) * error
            var fa = _f(a)
            var fb = _f(b)
            var wanted = ideal * fa + (Fraction(1) - ideal) * fb
            var results = _graphs(rate, a, b)
            for result in results:
                var gap = abs(_f(result) - wanted)
                assert_true(gap <= limit)


def _refused(
    low: Float64, high: Float64, error: Fraction, a: Float64, b: Float64
) raises:
    """Require `bound` to refuse this domain."""
    var refused = False
    try:
        _ = _bound(_f(low), _f(high), error, _f(a), _f(b))
    except:
        refused = True
    assert_true(refused)


def test_equal_constants_keep_the_rounding_error() raises:
    """Equal samples still pay the complement and rounding terms."""
    var rates = List[Float64]()
    rates.append(0.1)
    rates.append(0.3)
    rates.append(0.5)
    rates.append(0.9)
    _check(rates, 9.0, 9.0, Fraction.of(BigInt(1), BigInt(10).__pow__(12)))
    var positive = _bound(
        _f(0.3),
        _f(0.3),
        Fraction(0),
        _f(9.0),
        _f(9.0),
    )
    assert_true(Fraction(0) < positive)


def test_signs_and_extrapolation_stay_inside_the_bound() raises:
    """Both signs and rates outside [0, 1] stay inside the bound."""
    var pairs = List[Float64]()
    pairs.append(8.7)
    pairs.append(9.0)
    pairs.append(-8.7)
    pairs.append(-9.0)
    pairs.append(8.7)
    pairs.append(-9.0)
    pairs.append(-8.7)
    pairs.append(9.0)
    pairs.append(0.0)
    pairs.append(9.0)
    pairs.append(9.0)
    pairs.append(0.0)
    var rates = List[Float64]()
    rates.append(-3.0)
    rates.append(-0.01)
    rates.append(0.2)
    rates.append(0.5)
    rates.append(0.9)
    rates.append(1.1)
    rates.append(3.0)
    var error = Fraction.of(BigInt(1), BigInt(10).__pow__(14))
    var index = 0
    while index < len(pairs):
        _check(rates, pairs[index], pairs[index + 1], error.copy())
        index += 2


def test_shared_error_is_smaller_than_the_old_sum() raises:
    """The coupled error is below one fiftieth of the old inherited sum."""
    var error = Fraction.of(BigInt(1), BigInt(10).__pow__(12))
    var coupled = _bound(_f(0.3), _f(0.3), error.copy(), _f(8.7), _f(9.0))
    var inherited = (_f(8.7) + _f(9.0)) * error
    assert_true(coupled * Fraction(50) < inherited)


def test_binade_edges_stay_inside_the_bound() raises:
    """Adjacent floats at binade edges stay inside the bound."""
    var error = Fraction.of(BigInt(1), BigInt.power_of_two(52))
    for value in [0.5, 1.0, 2.0, 16.0]:
        var rates = List[Float64]()
        rates.append(_nextafter(value, _neg_inf()))
        rates.append(value)
        rates.append(_nextafter(value, _inf()))
        _check(
            rates,
            _nextafter(32.0, _neg_inf()),
            32.0,
            error.copy(),
        )


def test_a_fixed_exponent_grid_stays_inside_the_bound() raises:
    """A fixed grid of finite rates and samples stays inside the bound."""
    var error_scale = Fraction(4)
    var rate_exp = -9
    while rate_exp <= 9:
        var sample_exp = -90
        while sample_exp <= 90:
            var rate = _pow2(rate_exp)
            var a = _pow2(sample_exp)
            var b = _pow2(-sample_exp)
            var rates = List[Float64]()
            rates.append(rate)
            rates.append(-rate)
            var error = _f(_ulp(rate)) * error_scale
            _check(rates, a, b, error)
            sample_exp += 45
        rate_exp += 3


def test_extreme_domains_are_refused() raises:
    """Values outside the supported domain have no coupled bound."""
    var tiny = bitcast[DType.float64](UInt64(1))
    var small = _pow2(-996)
    var huge = _pow2(1023)
    var wide = _pow2(664)
    _refused(tiny, tiny, Fraction(0), 1.0, 1.0)
    _refused(small, small, Fraction(0), 1.0, 1.0)
    _refused(0.5, 0.5, Fraction(0), huge, -huge)
    _refused(0.5, 0.5, Fraction(0), small, 1.0)
    _refused(wide, wide, Fraction(0), 1.0, 1.0)
    _refused(2.0, 1.0, Fraction(0), 1.0, 1.0)
    _refused(0.0, 1.0, Fraction(-1), 1.0, 1.0)


def test_supported_halves_are_exact() raises:
    """Halving a supported normal is the exact rational half."""
    var small = _min_mag()
    var large = _max_mag()
    var exponent = -400
    while exponent <= 400:
        var value = _pow2(exponent)
        var neighbors = List[Float64]()
        neighbors.append(value)
        neighbors.append(_nextafter(value, _inf()))
        neighbors.append(_nextafter(value, _neg_inf()))
        for item in neighbors:
            if item != 0.0:
                var size = abs(_f(item))
                if size < small or large < size:
                    continue
            for sign in [-1.0, 1.0]:
                var actual = item * sign
                assert_true(_f(actual * 0.5) == _f(actual) / Fraction(2))
        exponent += 13
    for edge in [_rn(small), _rn(large), 0.0]:
        for sign in [-1.0, 1.0]:
            var actual = edge * sign
            if actual != 0.0:
                var size = abs(_f(actual))
                if size < small or large < size:
                    continue
            assert_true(_f(actual * 0.5) == _f(actual) / Fraction(2))


def test_half_of_eta_needs_the_next_subnormal() raises:
    """Half of eta rounds to zero, and the next float encloses eta/2."""
    var eta = _ulp(0.0)
    var exact = _f(eta) / Fraction(2)
    var rounded = eta * 0.5
    assert_equal(rounded, 0.0)
    assert_true(_f(rounded) < exact)
    assert_true(exact <= _f(_nextafter(rounded, _inf())))


def test_sterbenz_subtractions_are_exact() raises:
    """Supported subtractions inside one binade are exact."""
    var small = _min_mag()
    var large = _max_mag()
    var exponent = -399
    while exponent < 400:
        var right = _rn(Fraction(3) * _f(_pow2(exponent - 1)))
        var half = right / 2.0
        var candidates = List[Float64]()
        candidates.append(half)
        candidates.append(_nextafter(half, _inf()))
        candidates.append(_nextafter(right, _neg_inf()))
        candidates.append(right)
        candidates.append(_nextafter(right, _inf()))
        candidates.append(_nextafter(right * 2.0, _neg_inf()))
        candidates.append(right * 2.0)
        for left in candidates:
            var fl = _f(left)
            var fr = _f(right)
            assert_true(
                small <= fl and fl <= large and small <= fr and fr <= large
            )
            assert_true(fr / Fraction(2) <= fl and fl <= Fraction(2) * fr)
            assert_true(_f(left - right) == fl - fr)
        exponent += 17


def test_a_difference_keeps_both_inherited_errors() raises:
    """The inherited errors of a difference add."""
    var one = Fraction(3) / Fraction(2)
    var two = Fraction(1)
    var e1 = Fraction.of(BigInt(1), BigInt.power_of_two(52))
    var e2 = Fraction.of(BigInt(1), BigInt.power_of_two(53))
    var computed = (one + e1) - (two - e2)
    assert_true(abs(computed - (one - two)) == e1 + e2)
    assert_true(e1 - e2 < abs(computed - (one - two)))


def test_the_coupled_identity_keeps_each_term() raises:
    """The eight-term blend identity holds for a fixed rational sample."""
    var state = 5942026
    var step = 0
    while step < 200:
        var sample = List[Fraction]()
        var term = 0
        while term < 8:
            state = (state * 1103515245 + 12345) & 0x7FFFFFFF
            var raw = state % 201 - 100
            sample.append(Fraction(raw) / Fraction(16))
            term += 1
        var rate = sample[0] + sample[4]
        var complement = Fraction(1) - rate + sample[5]
        var first = rate * sample[1] + sample[6]
        var second = complement * sample[2] + sample[7]
        var result = first + second + sample[3]
        var plain = (
            sample[0] * sample[1] + (Fraction(1) - sample[0]) * sample[2]
        )
        var gap = result - plain
        var expected = (
            (sample[1] - sample[2]) * sample[4]
            + sample[2] * sample[5]
            + sample[6]
            + sample[7]
            + sample[3]
        )
        assert_true(gap == expected)
        step += 1


def test_a_wide_interval_contains_subnormal_rates() raises:
    """The bound for [-1, 1] covers a subnormal rate."""
    var eta = _ulp(0.0)
    var limit = _bound(_f(-1.0), _f(1.0), Fraction(0), _f(0.5), _f(-0.5))
    for rate in [-eta, 0.0, eta]:
        var exact = _f(rate) * _f(0.5) + (Fraction(1) - _f(rate)) * _f(-0.5)
        var results = _graphs(rate, 0.5, -0.5)
        for result in results:
            assert_true(abs(_f(result) - exact) <= limit)
    assert_equal(_rn(_f(eta) * _f(0.5)), 0.0)
    var room = _rounding(_f(eta) * _f(0.5))
    assert_true(Fraction(0) < room)


def test_a_wrong_half_factor_is_not_the_identity() raises:
    """Dividing by four is not halving, and a reset drops the inherited error.
    """
    assert_true(Fraction(8) / Fraction(4) != Fraction(8) / Fraction(2))
    var value = Fraction(8)
    var error = Fraction.of(BigInt(1), BigInt.power_of_two(40))
    var computed = abs((value + error) / Fraction(2) - value / Fraction(2))
    assert_true(computed == error / Fraction(2))
    assert_true(Fraction(0) < error / Fraction(2))


def main() raises:
    """Run the stored blend proof tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
