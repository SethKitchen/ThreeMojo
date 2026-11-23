# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the groundwater flow of `extensions.groundwater`.

The references are closed forms of steady flow, from Bear, "Hydraulics
of Groundwater", 1979, chapters 5 and 8, and Fetter, "Applied
Hydrogeology", 4th edition, chapters 4 and 5: Darcy's law in a confined
strip, layers in series, the Dupuit parabola with recharge, and the
Thiem equation of a well.
"""

from std.math import inf, log, nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.groundwater.aquifer import (
    Aquifer,
    HeadOptions,
    default_head_options,
    solve_heads,
)
from extensions.groundwater.kinds import (
    ACTIVE,
    AquiferKind,
    CONFINED,
    CellKind,
    FIXED_HEAD,
    INACTIVE,
    UNCONFINED,
)
from units.si import (
    CUBIC_METER_PER_SECOND,
    Length64,
    METER,
    METER_PER_SECOND,
    Velocity64,
    VolumeFlowRate64,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _k(v: Float64) -> Velocity64:
    return Velocity64(v, METER_PER_SECOND)


def _strip(cells: Int, kind: AquiferKind) raises -> Aquifer:
    """A strip 1 m wide along x, 20 m thick, with K of 1e-4 m/s.

    Its length is 10 m per cell. The two end cells have fixed heads of
    18 m and 12 m.
    """
    var aquifer = Aquifer(
        cells, 1, _m(10 * Float64(cells)), _m(1), kind, _m(0), _m(20), _k(1e-4)
    )
    aquifer.set_fixed_head(0, 0, _m(18))
    aquifer.set_fixed_head(cells - 1, 0, _m(12))
    return aquifer^


def test_kinds() raises:
    assert_true(ACTIVE.is_valid())
    assert_true(FIXED_HEAD.is_valid())
    assert_true(INACTIVE.is_valid())
    assert_false(CellKind(3).is_valid())
    assert_true(CONFINED.is_valid())
    assert_true(UNCONFINED.is_valid())
    assert_false(AquiferKind(-1).is_valid())


def test_confined_strip_is_linear() raises:
    """A confined strip between two fixed heads.

    Reference: Darcy's law. The head is linear between the two fixed
    cells, and the flow is T times the gradient, with T = K b. One
    solution gives the heads.
    """
    var aquifer = _strip(7, CONFINED)
    var result = solve_heads(aquifer, default_head_options())
    assert_equal(result.iterations, 1)
    for i in range(7):
        assert_almost_equal(
            result.head(i, 0).to(METER), 18 - Float64(i), atol=1e-12
        )
    # The flow in at the high head goes out at the low head.
    assert_almost_equal(result.from_fixed, 0.0, atol=1e-15)
    assert_almost_equal(
        result.balance().to(CUBIC_METER_PER_SECOND), 0.0, atol=1e-15
    )


def test_well_at_the_closed_end_of_a_strip() raises:
    """A confined strip with a fixed head at one end and a well at the other.

    Reference: the side of the grid is a no-flow boundary, so all the
    water of the well flows to the fixed head. The head rises by
    Q Δx / T from each cell to the next.
    """
    var aquifer = Aquifer(
        5, 1, _m(50), _m(1), CONFINED, _m(0), _m(20), _k(1e-4)
    )
    aquifer.set_fixed_head(4, 0, _m(12))
    aquifer.add_well(0, 0, VolumeFlowRate64(1e-5, CUBIC_METER_PER_SECOND))
    var result = solve_heads(aquifer, default_head_options())
    for i in range(5):
        var rise = 1e-5 * 10 * Float64(4 - i) / (1e-4 * 20)
        assert_almost_equal(result.head(i, 0).to(METER), 12 + rise, atol=1e-10)
    assert_almost_equal(result.from_fixed, -1e-5, atol=1e-15)


def test_two_zones_in_series() raises:
    """A confined strip whose second half is ten times less permeable.

    Reference: the flow is the head difference over the sum of L / T of
    the two halves. The harmonic mean of the two transmissivities at the
    change makes the finite differences exact.
    """
    var aquifer = _strip(8, CONFINED)
    for i in range(4, 8):
        aquifer.set_conductivity(i, 0, _k(1e-5))
    var result = solve_heads(aquifer, default_head_options())
    # Between the centers of the end cells: 35 m of each zone.
    var flow = 6 / (35 / (1e-4 * 20) + 35 / (1e-5 * 20))
    for i in range(8):
        var x = 10 * Float64(i)
        var head = 18 - flow * min(x, 35.0) / (1e-4 * 20)
        if x > 35:
            head -= flow * (x - 35) / (1e-5 * 20)
        assert_almost_equal(result.head(i, 0).to(METER), head, atol=1e-10)


def test_unconfined_strip_is_the_dupuit_parabola() raises:
    """An unconfined strip with recharge, between two fixed heads.

    Reference: Dupuit, h² = h₁² - (h₁² - h₂²) x / L + (R / K) x (L - x).
    With 41 cells the heads are within 1 mm. The recharge that enters
    leaves through the fixed heads.
    """
    var aquifer = _strip(41, UNCONFINED)
    aquifer.set_recharge(_k(2e-7))
    var result = solve_heads(aquifer, default_head_options())
    assert_true(result.iterations > 3)
    var length = 400.0
    for i in range(41):
        var x = 10 * Float64(i)
        var square = (
            324 - (324 - 144) * x / length + 2e-7 / 1e-4 * x * (length - x)
        )
        assert_almost_equal(
            result.head(i, 0).to(METER), sqrt(square), atol=1e-3
        )
    assert_almost_equal(result.from_recharge, 2e-7 * 10 * 39, atol=1e-18)
    assert_almost_equal(
        result.fixed_head_flow().to(CUBIC_METER_PER_SECOND),
        -2e-7 * 10 * 39,
        atol=1e-12,
    )
    assert_true(abs(result.balance().to(CUBIC_METER_PER_SECOND)) < 1e-12)
    # A layer whose heads are above its top is full, as a confined one.
    var full = Aquifer(7, 1, _m(70), _m(1), UNCONFINED, _m(0), _m(10), _k(1e-4))
    full.set_fixed_head(0, 0, _m(18))
    full.set_fixed_head(6, 0, _m(12))
    var straight = solve_heads(full, default_head_options())
    assert_almost_equal(straight.head(3, 0).to(METER), 15.0, atol=1e-9)


def test_well_meets_the_thiem_equation() raises:
    """A well at the center of a confined square island of 41 by 41 cells.

    Reference: Thiem. Between two radii the head rises by
    Q / (2 π T) ln(r₂ / r₁). Between 5 and 10 cells from the well, along
    a grid line, the difference is within 2%. The fixed heads at the
    sides give the water that the well takes.
    """
    var aquifer = Aquifer(
        41, 41, _m(410), _m(410), CONFINED, _m(0), _m(20), _k(1e-4)
    )
    for k in range(41):
        aquifer.set_fixed_head(k, 0, _m(30))
        aquifer.set_fixed_head(k, 40, _m(30))
        aquifer.set_fixed_head(0, k, _m(30))
        aquifer.set_fixed_head(40, k, _m(30))
    aquifer.add_well(20, 20, VolumeFlowRate64(-0.002, CUBIC_METER_PER_SECOND))
    var result = solve_heads(aquifer, default_head_options())
    var rise = result.head(30, 20).to(METER) - result.head(25, 20).to(METER)
    var thiem = 0.002 / (2 * pi * 1e-4 * 20) * log(2.0)
    assert_true(abs(rise / thiem - 1) < 0.02, String(rise, " ", thiem))
    assert_true(result.head(20, 20).to(METER) < result.head(21, 20).to(METER))
    assert_almost_equal(result.from_wells, -0.002, atol=0)
    assert_almost_equal(result.from_fixed, 0.002, atol=1e-12)
    # The drawdown is the same along x and along y.
    assert_almost_equal(
        result.head(20, 30).to(METER), result.head(30, 20).to(METER), atol=1e-9
    )


def test_inactive_cells_pass_no_water() raises:
    """A confined strip two cells wide, with a wall across one row.

    Reference: the wall of inactive cells closes one row, so all the
    flow goes through the other row, at the flow of a strip half as
    wide.
    """
    var aquifer = Aquifer(
        5, 2, _m(50), _m(2), CONFINED, _m(0), _m(20), _k(1e-4)
    )
    for j in range(2):
        aquifer.set_fixed_head(0, j, _m(18))
        aquifer.set_fixed_head(4, j, _m(14))
    aquifer.set_inactive(2, 1)
    # A well in a cell that is not active has no effect.
    aquifer.add_well(2, 1, VolumeFlowRate64(5, CUBIC_METER_PER_SECOND))
    var result = solve_heads(aquifer, default_head_options())
    assert_almost_equal(result.head(2, 1).to(METER), 0.0, atol=0)
    assert_almost_equal(result.from_wells, 0.0, atol=0)
    assert_true(abs(result.balance().to(CUBIC_METER_PER_SECOND)) < 1e-15)
    # The head is symmetric about the wall, and the open row carries
    # more than half of the flow of two open rows.
    assert_almost_equal(result.head(2, 0).to(METER), 16.0, atol=1e-10)
    assert_true(result.head(1, 1).to(METER) > result.head(1, 0).to(METER))


def test_aquifer_refusals() raises:
    var bad = nan[DType.float64]()
    var k = _k(1e-4)
    with assert_raises(contains="along x"):
        _ = Aquifer(0, 1, _m(1), _m(1), CONFINED, _m(0), _m(1), k)
    with assert_raises(contains="along y"):
        _ = Aquifer(1, 0, _m(1), _m(1), CONFINED, _m(0), _m(1), k)
    with assert_raises(contains="larger"):
        _ = Aquifer(1048577, 1, _m(1), _m(1), CONFINED, _m(0), _m(1), k)
    with assert_raises(contains="larger"):
        _ = Aquifer(2, 1048576, _m(1), _m(1), CONFINED, _m(0), _m(1), k)
    with assert_raises(contains="width"):
        _ = Aquifer(1, 1, _m(0), _m(1), CONFINED, _m(0), _m(1), k)
    with assert_raises(contains="height"):
        _ = Aquifer(1, 1, _m(1), _m(-1), CONFINED, _m(0), _m(1), k)
    with assert_raises(contains="aquifer kind"):
        _ = Aquifer(1, 1, _m(1), _m(1), AquiferKind(2), _m(0), _m(1), k)
    with assert_raises(contains="bottom"):
        _ = Aquifer(1, 1, _m(1), _m(1), CONFINED, _m(bad), _m(1), k)
    with assert_raises(contains="top"):
        _ = Aquifer(1, 1, _m(1), _m(1), CONFINED, _m(0), _m(0), k)
    with assert_raises(contains="top"):
        _ = Aquifer(
            1, 1, _m(1), _m(1), CONFINED, _m(0), _m(inf[DType.float64]()), k
        )
    with assert_raises(contains="conductivity"):
        _ = Aquifer(1, 1, _m(1), _m(1), CONFINED, _m(0), _m(1), _k(0))
    var aquifer = _strip(4, UNCONFINED)
    with assert_raises(contains="out of range"):
        _ = aquifer.cell(-1, 0)
    with assert_raises(contains="out of range"):
        _ = aquifer.cell(4, 0)
    with assert_raises(contains="out of range"):
        _ = aquifer.cell(0, -1)
    with assert_raises(contains="out of range"):
        _ = aquifer.cell(0, 1)
    with assert_raises(contains="conductivity"):
        aquifer.set_conductivity(1, 0, _k(-1))
    with assert_raises(contains="fixed head"):
        aquifer.set_fixed_head(1, 0, _m(bad))
    with assert_raises(contains="out of range"):
        aquifer.set_inactive(9, 0)
    with assert_raises(contains="well rate"):
        aquifer.add_well(1, 0, VolumeFlowRate64(bad, CUBIC_METER_PER_SECOND))
    with assert_raises(contains="recharge"):
        aquifer.set_recharge(_k(bad))
    with assert_raises(contains="tolerance"):
        _ = HeadOptions(_m(0), 5)
    with assert_raises(contains="iteration budget"):
        _ = HeadOptions(_m(1e-6), 0)
    var result = solve_heads(aquifer, default_head_options())
    with assert_raises(contains="out of range"):
        _ = result.head(-1, 0)
    with assert_raises(contains="out of range"):
        _ = result.head(4, 0)
    with assert_raises(contains="out of range"):
        _ = result.head(0, -1)
    with assert_raises(contains="out of range"):
        _ = result.head(0, 1)
    # One solution cannot settle a water table.
    with assert_raises(contains="did not settle"):
        _ = solve_heads(aquifer, HeadOptions(_m(1e-9), 1))
    var free = Aquifer(3, 1, _m(3), _m(1), CONFINED, _m(0), _m(1), k)
    with assert_raises(contains="needs a cell of fixed head"):
        _ = solve_heads(free, default_head_options())
    # A wall cuts the last cell off from the fixed head.
    free.set_fixed_head(0, 0, _m(5))
    free.set_inactive(1, 0)
    with assert_raises(contains="no path"):
        _ = solve_heads(free, default_head_options())
    # A fixed head below the bottom of an unconfined layer is dry.
    var dry = _strip(4, UNCONFINED)
    dry.set_fixed_head(3, 0, _m(-1))
    with assert_raises(contains="dry"):
        _ = solve_heads(dry, default_head_options())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
