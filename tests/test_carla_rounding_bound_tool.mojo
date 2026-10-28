# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The rounding report matches the Python town-lane forward analysis."""

from std.os.path import realpath
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._sha256 import sha256_hex
from tools._lane_reports import (
    _floor_log10,
    _min_fixed,
    _place_digits,
    _strip_zeros,
    isqrt,
    nstr,
    output_directory,
    repository_root,
)
from tools.carla_rounding_bound import (
    Bound,
    add_bounds,
    divide_bounds,
    divide_constant,
    from_fraction,
    from_int,
    from_interval,
    mul_bounds,
    poly,
    publish,
    reports,
    sincos,
    sub_bound,
    sum2_terms,
    _axis_lower,
    _ceil_div,
    _ceil_shift,
    _coefficients,
    _fraction_text,
    _max_abs,
    _min_abs,
    _parse_rational,
    _radius,
    _require,
    _sum2_error,
    _up,
    _upper,
)


comptime _FILE = (
    "68e51ffed9950e91995e53165a43fb41683a28b38f486cdcab02f6e5c23298db"
)
"""SHA-256 of `rounding-results.json` from `rounding.py`."""
comptime _STDOUT = (
    "db0244a794ddb092e78ba8288af78ae543583126ebdfea2690e01db8fa351773"
)
"""SHA-256 of the summary `rounding.py` prints."""


def _grid(value: Int) -> BigInt:
    """Return value * 2^160."""
    return BigInt(value) << 160


def test_integer_addition_and_negation_match_outward_rounding() raises:
    var total = add_bounds(from_int(1), from_int(2))
    assert_equal(total.lo, _grid(3))
    assert_equal(total.hi, _grid(3))
    assert_equal(total.e.to_string(), "486777830487640090174734030864385")
    var negated = sub_bound(from_int(0), from_int(5))
    assert_equal(negated.lo, -_grid(5))
    assert_equal(negated.hi, -_grid(5))
    assert_equal(negated.e, (BigInt(5) << 107) + BigInt(1))


def test_zero_product_and_negative_product_keep_an_error() raises:
    var product = mul_bounds(from_int(0), from_int(3))
    assert_equal(product.lo, BigInt(0))
    assert_equal(product.hi, BigInt(0))
    assert_equal(product.e, BigInt(1))
    var negative = mul_bounds(from_int(-2), from_int(3))
    assert_true(negative.hi < BigInt(0))
    assert_equal(_max_abs(BigInt(1), BigInt(-3)), BigInt(3))
    assert_equal(_max_abs(BigInt(-4), BigInt(2)), BigInt(4))
    assert_equal(_min_abs(BigInt(4), BigInt(-2)), BigInt(2))
    assert_equal(_min_abs(BigInt(-1), BigInt(5)), BigInt(1))
    assert_equal(_ceil_shift(BigInt(5), 1), BigInt(3))
    assert_equal(_ceil_shift(BigInt(4), 1), BigInt(2))
    assert_equal(_ceil_div(BigInt(5), BigInt(2)), BigInt(3))
    assert_equal(_ceil_div(BigInt(4), BigInt(2)), BigInt(2))


def test_division_matches_the_snapped_quotient() raises:
    var numer = add_bounds(from_int(1), from_int(1))
    var quot = divide_bounds(numer, from_int(2))
    assert_equal(quot.lo, _grid(1))
    assert_equal(quot.hi, _grid(1))
    assert_equal(quot.e.to_string(), "324518553658426744797554530058241")
    var domain = from_interval(
        Fraction(0), Fraction.of(BigInt(1), BigInt(10) ** 12)
    )
    var step = divide_constant(domain, 1)
    assert_equal(step.e.to_string(), "162259276829213363392")
    with assert_raises(contains="division domain contains zero"):
        _ = divide_bounds(from_int(1), from_interval(Fraction(-1), Fraction(1)))
    var reached = Bound(_grid(1), _grid(2), _grid(1))
    with assert_raises(contains="division error reaches zero"):
        _ = divide_bounds(from_int(1), reached)
    with assert_raises(contains="nonpositive divisor"):
        _ = divide_constant(from_int(1), 0)


def test_sum2_refuses_the_unreviewed_range_and_snaps_the_bound() raises:
    var inherited = Fraction.of(BigInt(1), BigInt(8))
    var snapped = _up_error(Fraction(3), inherited, 4)
    assert_equal(
        snapped.to_string(), "182687704666363351553291091730111940950778446149"
    )
    assert_true(_sum2_error(Fraction(0), Fraction(5), 4) == Fraction(5))
    assert_true(_sum2_error(Fraction(3), inherited, 1) == inherited)
    with assert_raises(contains="unsupported Sum2 count"):
        _ = _sum2_error(Fraction(1), Fraction(0), 0)
    with assert_raises(contains="unsupported Sum2 count"):
        _ = _sum2_error(Fraction(1), Fraction(0), (1 << 30) + 1)
    with assert_raises(contains="unsupported Sum2 majorant"):
        _ = _sum2_error(Fraction(-1), Fraction(0), 2)
    with assert_raises(contains="unsupported Sum2 majorant"):
        _ = _sum2_error(Fraction(1), Fraction(-1), 2)
    var too_big = Fraction(BigInt.power_of_two(900)) + Fraction(1)
    with assert_raises(contains="unsupported Sum2 majorant"):
        _ = _sum2_error(too_big, Fraction(0), 2)
    var terms = List[Bound]()
    with assert_raises(contains="empty Sum2 term sequence"):
        _ = sum2_terms(terms)
    terms.append(from_int(4))
    var total = sum2_terms(terms)
    assert_equal(total.lo, _grid(4))
    assert_equal(total.e, BigInt(0))


def _up_error(
    magnitude: Fraction, inherited: Fraction, count: Int
) raises -> BigInt:
    """Snap one Sum2 majorant onto the grid."""
    return _up(_sum2_error(magnitude, inherited, count))


def test_decimal_text_matches_mpmath_nstr() raises:
    assert_equal(nstr(Fraction(0), 45), "0.0")
    assert_equal(nstr(Fraction.of(BigInt(1), BigInt(2)), 45), "0.5")
    assert_equal(nstr(-Fraction.of(BigInt(1), BigInt(2)), 45), "-0.5")
    assert_equal(nstr(Fraction(100), 45), "100.0")
    assert_equal(nstr(Fraction.of(BigInt(7), BigInt(4)), 45), "1.75")
    assert_equal(
        nstr(Fraction.of(BigInt(1), BigInt.power_of_two(53)), 45),
        "1.1102230246251565404236316680908203125e-16",
    )
    assert_equal(
        nstr(Fraction.of(BigInt(1), BigInt.power_of_two(1075)), 45),
        "2.47032822920623272088284396434110686182529901e-324",
    )
    assert_equal(
        nstr(Fraction.of(BigInt(1), BigInt(10) ** 12), 45), "0.000000000001"
    )
    assert_equal(nstr(Fraction(BigInt(10) ** 50), 45), "1.0e+50")
    assert_equal(nstr(Fraction(BigInt(10) ** 10), 45), "10000000000.0")
    var carried = Fraction(1) - Fraction.of(BigInt(5), BigInt(10) ** 46)
    assert_equal(nstr(carried, 45), "1.0")
    assert_equal(nstr(-carried, 45), "-1.0")
    assert_equal(
        nstr(Fraction.of(BigInt(2), BigInt(3)), 45),
        "0.666666666666666666666666666666666666666666667",
    )
    assert_equal(_min_fixed(45), -15)
    assert_equal(_min_fixed(2), -5)
    var longer = _place_digits("123456", 4, 2)
    assert_equal(longer[0], "1234")
    assert_equal(longer[1], 4)
    var shorter = _place_digits("12", 4, 2)
    assert_equal(shorter[0], "0012")
    assert_equal(shorter[1], 2)
    var same = _place_digits("1234", 4, 2)
    assert_equal(same[0], "1234")
    assert_equal(same[1], 2)
    assert_equal(_strip_zeros("000"), "0")
    assert_equal(_strip_zeros("100."), "100.0")
    assert_equal(_strip_zeros("0.50"), "0.5")
    assert_equal(_floor_log10(BigInt(100), BigInt(1)), 2)
    assert_equal(_floor_log10(BigInt(1), BigInt(1000)), -3)
    assert_equal(
        _radius(
            BigInt(4) * BigInt(5) * (BigInt(10) ** 14),
            (BigInt(10) ** 11) * BigInt.parse("181329999999999"),
        ),
        "0.0000105021971582011173602600787284758148821656177",
    )
    assert_equal(
        _radius(BigInt(16) * BigInt(1000), BigInt.parse("912499999999998")),
        "0.00000418739138072171421723292040790778079674546282",
    )
    assert_equal(isqrt(BigInt(0)), BigInt(0))
    assert_equal(isqrt(BigInt(9)), BigInt(3))
    with assert_raises(contains="square root of a negative integer"):
        _ = isqrt(BigInt(-1))


def test_constants_polynomials_and_endpoint_squares() raises:
    assert_equal(_fraction_text(Fraction(3)), "3")
    assert_equal(_fraction_text(Fraction.of(BigInt(1), BigInt(2))), "1/2")
    assert_true(_parse_rational("0") == Fraction(0))
    assert_true(_parse_rational("-20") == Fraction(-20))
    assert_true(_parse_rational("15/4") == Fraction.of(BigInt(15), BigInt(4)))
    var text = (
        "comptime _SIN_COEFFICIENTS: Array[Float64, 2] = [\n  1.0,\n "
        " -0.5,\n]\n"
    )
    var values = _coefficients(text, "_SIN_COEFFICIENTS")
    assert_equal(len(values), 2)
    assert_true(values[0] == Fraction(1))
    with assert_raises(contains="missing"):
        _ = _coefficients(text, "_COS_COEFFICIENTS")
    with assert_raises(contains="missing"):
        _ = _coefficients(
            "comptime _SIN_COEFFICIENTS no equals", "_SIN_COEFFICIENTS"
        )
    with assert_raises(contains="missing"):
        _ = _coefficients(
            "comptime _SIN_COEFFICIENTS = no", "_SIN_COEFFICIENTS"
        )
    with assert_raises(contains="missing"):
        _ = _coefficients(
            "comptime _SIN_COEFFICIENTS = []", "_SIN_COEFFICIENTS"
        )
    var single = List[Bound]()
    single.append(from_int(3))
    var constant = poly(single, from_int(4))
    assert_equal(constant.lo, _grid(3))
    var linear = List[Bound]()
    linear.append(from_int(1))
    linear.append(from_int(2))
    _ = poly(linear, from_int(3))
    var coeffs = List[Bound]()
    coeffs.append(from_int(1))
    var quadrants = List[Int]()
    quadrants.append(0)
    quadrants.append(1)
    quadrants.append(2)
    quadrants.append(-1)
    for index in range(len(quadrants)):
        _ = sincos(from_int(0), quadrants[index], coeffs, coeffs)
    assert_true(_upper(0) == Fraction.of(BigInt(1), BigInt(10) ** 12))
    assert_true(_upper(22) == Fraction(20))
    var same = Bound(_grid(2), _grid(3), BigInt(0))
    var squared = _axis_lower(same, 0)
    assert_true(squared > Fraction(0))
    var opposite = Bound(-_grid(1), _grid(1), BigInt(0))
    assert_true(_axis_lower(opposite, 0) == Fraction(0))
    var wider = Bound(-_grid(5), -_grid(2), BigInt(0))
    var wide_square = _axis_lower(wider, 0)
    assert_true(wide_square == Fraction(4))
    _require(True, "unused")
    with assert_raises(contains="refused"):
        _require(False, "refused")
    var root = repository_root(realpath("."))
    assert_true(
        Path(root + "/tools/fixtures/carla_lane_constants.json").exists()
    )
    with assert_raises(contains="cannot find"):
        _ = repository_root("/tmp")
    with assert_raises(contains="cannot find"):
        _ = repository_root("missing")
    assert_equal(output_directory(root, ""), root + "/out/carla-lane-oracle")
    assert_equal(output_directory(root, "/tmp/out"), "/tmp/out")
    _ = from_fraction(Fraction.of(BigInt(-20), BigInt(1)))


def test_report_matches_the_python_bytes() raises:
    var root = repository_root(realpath("."))
    var produced = reports(root)
    assert_equal(sha256_hex(produced[0].as_bytes()), _FILE)
    assert_equal(sha256_hex(produced[1].as_bytes()), _STDOUT)
    var written_pair = publish(root, "/tmp/rounding-bound-report")
    assert_equal(written_pair[0], produced[0])
    assert_equal(written_pair[1], produced[1])
    var written = Path(
        "/tmp/rounding-bound-report/rounding-results.json"
    ).read_text()
    assert_equal(written, produced[0])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
