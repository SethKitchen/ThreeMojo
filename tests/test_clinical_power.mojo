# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Sample size and power, and the normal quantile.

`assets/power/power_expected.txt` holds the results of scipy 1.18.1,
statsmodels 0.15.0 and lifelines 0.30.3. See `assets/power/make_power.py`.
"""

from extensions.clinical.distributions import normal_quantile
from extensions.clinical.power import (
    freedman_power,
    freedman_size,
    means_power,
    means_size,
    proportions_power,
    proportions_size,
    schoenfeld_events,
)
from std.math import ceil, erfc, inf, log, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)


def _numbers(line: String) raises -> List[Float64]:
    var out = List[Float64]()
    var first = True
    for part in line.split(" "):
        if first:
            first = False
            continue
        out.append(atof(String(part)))
    return out^


def _expected() raises -> List[List[Float64]]:
    var out = List[List[Float64]]()
    var text = open("assets/power/power_expected.txt", "r").read()
    for line in text.splitlines():
        out.append(_numbers(String(line)))
    return out^


def test_normal_quantile() raises:
    ref row = _expected()[0]
    for c in range(11):
        assert_almost_equal(
            normal_quantile(row[2 * c]), row[2 * c + 1], rtol=1e-15, atol=1e-16
        )
    assert_equal(normal_quantile(0.5), 0.0)
    with assert_raises(contains="1e-300 or more"):
        _ = normal_quantile(1e-310)


def test_sizes_and_powers() raises:
    var expected = _expected()
    ref p = expected[1]
    for c in range(2):
        var at = 8 * c
        assert_almost_equal(
            proportions_size(p[at], p[at + 1], p[at + 2], p[at + 3], p[at + 4]),
            p[at + 5],
            rtol=1e-13,
        )
        assert_almost_equal(
            proportions_power(
                p[at], p[at + 1], p[at + 6], p[at + 2], p[at + 4]
            ),
            p[at + 7],
            rtol=1e-13,
        )
    ref m = expected[2]
    for c in range(2):
        var at = 8 * c
        assert_almost_equal(
            means_size(m[at], m[at + 1], m[at + 2], m[at + 3], m[at + 4]),
            m[at + 5],
            rtol=1e-13,
        )
        assert_almost_equal(
            means_power(m[at], m[at + 1], m[at + 6], m[at + 2], m[at + 4]),
            m[at + 7],
            rtol=1e-13,
        )
    ref s = expected[3]
    for c in range(2):
        var at = 5 * c
        assert_almost_equal(
            schoenfeld_events(s[at], s[at + 1], s[at + 2], s[at + 3]),
            s[at + 4],
            rtol=1e-13,
        )
    ref f = expected[4]
    for c in range(2):
        var at = 9 * c
        var size = freedman_size(
            f[at], f[at + 1], f[at + 2], f[at + 3], f[at + 4], f[at + 5]
        )
        assert_equal(ceil(size[0]), f[at + 6])
        assert_equal(ceil(size[1]), f[at + 7])
        assert_almost_equal(
            freedman_power(
                f[at], f[at + 1], f[at + 6], f[at + 7], f[at + 4], f[at + 5]
            ),
            f[at + 8],
            rtol=1e-13,
        )


def test_by_hand() raises:
    # Equal groups, two means, a half deviation apart, at 5 percent and
    # 80 percent: 2 (1.959964 + 0.841621)^2 / 0.25 patients a group.
    var z = 1.959963984540054 + 0.8416212335729143
    assert_almost_equal(
        means_size(0.5, 1.0, 0.05, 0.8, 1.0), 8.0 * z * z, rtol=1e-14
    )
    # At that size the power is 0.8, and the far tail adds the chance of
    # a z beyond 2 z_a + z_b.
    var far = 0.5 * erfc(
        (2.0 * 1.959963984540054 + 0.8416212335729143) / sqrt(2.0)
    )
    assert_almost_equal(
        means_power(0.5, 1.0, 8.0 * z * z, 0.05, 1.0), 0.8 + far, rtol=1e-14
    )
    # Schoenfeld with even groups: 4 z^2 / ln(HR)^2.
    assert_almost_equal(
        schoenfeld_events(0.5, 0.05, 0.8, 0.5),
        4.0 * z * z / (log(0.5) ** 2),
        rtol=1e-14,
    )
    # A power at least as large as the level never needs a size below 0.
    assert_equal(means_size(1.0, 1.0, 0.9, 0.05, 1.0), 0.0)


def test_refusals() raises:
    var levels: List[Float64] = [0.0, 1.0, nan[DType.float64]()]
    for a in levels:
        with assert_raises(contains="level alpha"):
            _ = means_size(1.0, 1.0, a, 0.8, 1.0)
        with assert_raises(contains="The power must"):
            _ = means_size(1.0, 1.0, 0.05, a, 1.0)
    var pairs: List[List[Float64]] = [
        [0.0, 0.5],
        [1.0, 0.5],
        [0.5, 0.0],
        [0.5, 1.0],
        [0.4, 0.4],
    ]
    for q in pairs:
        with assert_raises(contains="Two proportions must differ"):
            _ = proportions_size(q[0], q[1], 0.05, 0.8, 1.0)
    var ratios: List[Float64] = [0.0, inf[DType.float64]()]
    for r in ratios:
        with assert_raises(contains="ratio of the group sizes"):
            _ = proportions_power(0.3, 0.2, 100.0, 0.05, r)
        with assert_raises(contains="ratio of the group sizes"):
            _ = means_size(1.0, 1.0, 0.05, 0.8, r)
        with assert_raises(contains="ratio of the group sizes"):
            _ = freedman_size(0.7, 0.05, 0.8, r, 0.3, 0.3)
    var sizes: List[Float64] = [0.0, inf[DType.float64]()]
    for n in sizes:
        with assert_raises(contains="group size"):
            _ = proportions_power(0.3, 0.2, n, 0.05, 1.0)
        with assert_raises(contains="group size"):
            _ = means_power(1.0, 1.0, n, 0.05, 1.0)
        with assert_raises(contains="group size"):
            _ = freedman_power(0.7, 0.05, n, 10.0, 0.3, 0.3)
        with assert_raises(contains="group size"):
            _ = freedman_power(0.7, 0.05, 10.0, n, 0.3, 0.3)
    var differences: List[Float64] = [0.0, inf[DType.float64]()]
    for d in differences:
        with assert_raises(contains="difference of the means"):
            _ = means_power(d, 1.0, 10.0, 0.05, 1.0)
    var deviations: List[Float64] = [0.0, inf[DType.float64]()]
    for d in deviations:
        with assert_raises(contains="standard deviation"):
            _ = means_size(1.0, d, 0.05, 0.8, 1.0)
    var hazards: List[Float64] = [0.0, 1.0, inf[DType.float64]()]
    for h in hazards:
        with assert_raises(contains="hazard ratio"):
            _ = schoenfeld_events(h, 0.05, 0.8, 0.5)
    var allocations: List[Float64] = [0.0, 1.0]
    for a in allocations:
        with assert_raises(contains="allocation"):
            _ = schoenfeld_events(0.7, 0.05, 0.8, a)
    var chances: List[List[Float64]] = [
        [0.0, 0.5],
        [1.5, 0.5],
        [0.5, 0.0],
        [0.5, 1.5],
    ]
    for c in chances:
        with assert_raises(contains="chance of an event"):
            _ = freedman_size(0.7, 0.05, 0.8, 1.0, c[0], c[1])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
