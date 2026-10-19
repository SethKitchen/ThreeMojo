# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.castle.wind`.

The references are EN 1991-1-4 evaluated by hand, a fine integration of the
wind profile, the Euler-Bernoulli cantilever frequency, and the finite
element modal analysis of `extensions.structure` for the same section.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.building.material import brick
from extensions.building.model import rectangle
from extensions.castle.kinds import CONE, PARAPET, ROUND, SQUARE
from extensions.castle.masonry import Masonry, clay_brick_masonry
from extensions.castle.plan import PlanPoint, Tower, wijnendale
from extensions.castle.wind import (
    BaseCheck,
    CATEGORY_II,
    CATEGORY_III,
    Wind,
    cantilever_frequency,
    check_tower_base,
    flanders_wind,
    peak_velocity_pressure,
    ring_inertia,
    tower_wind_load,
)
from extensions.structure.ids import NodeId
from extensions.structure.kinds import RX, RY, UZ
from extensions.structure.modal import solve_modes
from extensions.structure.model import StructuralModel
from generators.utils import Vec3d
from std.math import log, nan, pi, pow, sqrt
from units.si import (
    Density64,
    Force64,
    KILONEWTON,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    METER_PER_SECOND,
    Moment64,
    PASCAL,
    PER_SECOND,
    Pressure64,
    Velocity64,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _keep() raises -> Tower:
    return wijnendale().towers[0].copy()


def _qp(speed: Float64, z0: Float64, z: Float64) -> Float64:
    """EN 1991-1-4 by hand, with a density of 1.25 kg/m3."""
    var kr = 0.19 * pow(z0 / 0.05, 0.07)
    var mean = kr * log(max(z, 2.0) / z0) * speed
    var intensity = 1.0 / log(max(z, 2.0) / z0)
    return (1.0 + 7.0 * intensity) * 0.5 * 1.25 * mean * mean


def test_peak_pressure_matches_the_eurocode_by_hand() raises:
    var w = flanders_wind()
    # kr = 0.19, vm = 26.17 m/s and Iv = 0.1887 at 10 m, so qp = 0.994 kPa.
    assert_almost_equal(
        peak_velocity_pressure(w, _m(10.0)).to(PASCAL),
        _qp(26.0, 0.05, 10.0),
        atol=1e-9,
    )
    assert_almost_equal(
        peak_velocity_pressure(w, _m(10.0)).to(PASCAL), 993.8, atol=0.5
    )
    assert_almost_equal(
        peak_velocity_pressure(w, _m(28.0)).to(PASCAL),
        _qp(26.0, 0.05, 28.0),
        atol=1e-9,
    )


def test_peak_pressure_is_the_same_below_two_meters() raises:
    var w = flanders_wind()
    var at_two = peak_velocity_pressure(w, _m(2.0)).value
    assert_almost_equal(peak_velocity_pressure(w, _m(0.5)).value, at_two)
    assert_true(peak_velocity_pressure(w, _m(3.0)).value > at_two)


def test_rougher_terrain_slows_the_wind_near_the_ground() raises:
    var w = flanders_wind()
    var rough = Wind(
        w.basic_speed, _m(CATEGORY_III), w.air_density, w.force_coefficient
    )
    assert_almost_equal(
        peak_velocity_pressure(rough, _m(10.0)).to(PASCAL),
        _qp(26.0, CATEGORY_III, 10.0),
        atol=1e-9,
    )
    assert_true(
        peak_velocity_pressure(rough, _m(10.0)).value
        < peak_velocity_pressure(w, _m(10.0)).value
    )
    assert_almost_equal(CATEGORY_II, 0.05)


def test_peak_pressure_refuses_bad_input() raises:
    var w = flanders_wind()
    var bad = w
    bad.basic_speed = Velocity64(0.0)
    with assert_raises(contains="A basic wind speed must be positive"):
        _ = peak_velocity_pressure(bad, _m(10.0))
    bad = w
    bad.roughness = _m(0.0)
    with assert_raises(contains="A roughness length must be positive"):
        _ = peak_velocity_pressure(bad, _m(10.0))
    bad = w
    bad.air_density = Density64(-1.0)
    with assert_raises(contains="An air density must be positive"):
        _ = peak_velocity_pressure(bad, _m(10.0))
    with assert_raises(contains="A height must be positive"):
        _ = peak_velocity_pressure(w, _m(0.0))
    bad = w
    bad.roughness = _m(3.0)
    with assert_raises(contains="above the roughness length"):
        _ = peak_velocity_pressure(bad, _m(1.0))


def test_wind_load_matches_a_fine_integration() raises:
    var w = flanders_wind()
    var keep = _keep()
    var load = tower_wind_load(w, keep)
    var n = 4000
    var force = 0.0
    var moment = 0.0
    var h = keep.height.value
    var width = 2.0 * keep.radius.value
    for k in range(n):
        var z = h * (Float64(k) + 0.5) / Float64(n)
        var strip = (
            w.force_coefficient * _qp(26.0, 0.05, z) * width * h / Float64(n)
        )
        force += strip
        moment += strip * z
    assert_almost_equal(load.force.value / force, 1.0, atol=2e-3)
    assert_almost_equal(load.moment.value / moment, 1.0, atol=2e-3)
    assert_true(load.moment.value > load.force.value * h * 0.4)
    assert_true(load.moment.value < load.force.value * h * 0.6)


def test_square_and_round_towers_of_one_width_have_one_wind_load() raises:
    var round = _keep()
    var square = _keep()
    square.shape = SQUARE
    var a = tower_wind_load(flanders_wind(), round)
    var b = tower_wind_load(flanders_wind(), square)
    assert_almost_equal(a.force.value, b.force.value)
    assert_almost_equal(a.moment.value, b.moment.value)


def test_wind_load_refuses_bad_input() raises:
    var w = flanders_wind()
    w.force_coefficient = 0.0
    with assert_raises(contains="A force coefficient must be positive"):
        _ = tower_wind_load(w, _keep())
    var t = _keep()
    t.radius = _m(0.0)
    with assert_raises(contains="A tower radius must be positive"):
        _ = tower_wind_load(flanders_wind(), t)


def test_ring_inertia_of_round_and_square_shafts() raises:
    var keep = _keep()
    # pi/4 (R^4 - r^4) for R = 3.6 and r = 2.4.
    assert_almost_equal(
        ring_inertia(keep).value, pi / 4.0 * (3.6**4 - 2.4**4), atol=1e-9
    )
    var square = _keep()
    square.shape = SQUARE
    square.radius = _m(2.0)
    square.wall = _m(0.5)
    # Outer side 4 and inner side 3: (256 - 81) / 12.
    assert_almost_equal(ring_inertia(square).value, (256.0 - 81.0) / 12.0)


def test_cantilever_frequency_matches_the_beam_formula() raises:
    var keep = _keep()
    var m = clay_brick_masonry()
    var area = pi * (3.6**2 - 2.4**2)
    var inertia = pi / 4.0 * (3.6**4 - 2.4**4)
    var expected = (
        1.8751**2
        * sqrt(m.modulus.value * inertia / (m.density.value * area * 28.0**4))
        / (2.0 * pi)
    )
    assert_almost_equal(
        cantilever_frequency(keep, m).value, expected, atol=1e-9
    )
    # A stiff masonry tower is well above one hertz.
    assert_true(cantilever_frequency(keep, m).value > 1.0)


def test_cantilever_frequency_agrees_with_the_finite_element_model() raises:
    # A square hollow shaft has the area and the second moment of a solid
    # rectangle of width sqrt(S^2 + s^2) and the depth that gives the area.
    var tower = Tower(
        "square",
        SQUARE,
        PlanPoint(_m(0), _m(0)),
        _m(2.0),
        _m(0.5),
        _m(30.0),
        PARAPET,
        _m(0.0),
    )
    var masonry = clay_brick_masonry()
    var area = 16.0 - 9.0
    var width = sqrt(16.0 + 9.0)
    var depth = area / width
    var material = brick()
    material.density = masonry.density
    material.elastic_modulus = masonry.modulus
    var model = StructuralModel()
    var pieces = 8
    for i in range(pieces + 1):
        var node = model.add_node(
            Vec3d(30.0 * Float64(i) / Float64(pieces), 0, 0)
        )
        model.add_support(node, [UZ, RX, RY])
    for i in range(pieces):
        _ = model.add_member(
            NodeId(i),
            NodeId(i + 1),
            rectangle(_m(width), _m(depth)),
            material.copy(),
            Vec3d(0, 0, 1),
        )
    model.fix(NodeId(0))
    var modes = solve_modes(model, 1)
    var by_fe = modes.frequencies[0].to(PER_SECOND)
    var by_formula = cantilever_frequency(tower, masonry).value
    # The element mass includes the rotary inertia of the section. It lowers
    # the frequency of a stocky shaft by about half a percent, which the
    # Euler-Bernoulli formula leaves out.
    assert_almost_equal(by_fe / by_formula, 1.0, atol=1e-2)
    assert_true(by_fe < by_formula)


def test_base_check_of_the_keep() raises:
    var keep = _keep()
    var m = clay_brick_masonry()
    var roof = Force64(300.0, KILONEWTON)
    var check = check_tower_base(keep, m, flanders_wind(), roof, 2.2)
    var load = tower_wind_load(flanders_wind(), keep)
    var area = pi * (3.6**2 - 2.4**2)
    var weight = m.unit_weight().value * area * 28.0 + roof.value
    assert_almost_equal(check.normal.value, weight, atol=1e-6)
    assert_almost_equal(check.moment.value, load.moment.value)
    var inertia = pi / 4.0 * (3.6**4 - 2.4**4)
    var section = inertia / 3.6
    assert_almost_equal(
        check.leeward.value,
        weight / area + load.moment.value / section,
        atol=1e-6,
    )
    assert_almost_equal(
        check.windward.value,
        weight / area - load.moment.value / section,
        atol=1e-6,
    )
    assert_almost_equal(check.eccentricity.value, load.moment.value / weight)
    # The kern radius of a ring is (R^2 + r^2) / (4 R).
    assert_almost_equal(check.kern.value, (3.6**2 + 2.4**2) / (4.0 * 3.6))
    assert_almost_equal(
        check.utilization, check.leeward.value / (m.compressive.value / 2.2)
    )
    assert_almost_equal(
        check.equ_ratio, 0.9 * weight * 3.6 / (1.5 * load.moment.value)
    )
    assert_true(check.windward.value > 0.0)
    assert_true(check.passes())


def test_a_slender_tower_fails_its_base_check() raises:
    var thin = Tower(
        "needle",
        ROUND,
        PlanPoint(_m(0), _m(0)),
        _m(1.2),
        _m(0.2),
        _m(60.0),
        CONE,
        _m(4.0),
    )
    var check = check_tower_base(
        thin, clay_brick_masonry(), flanders_wind(), Force64(0.0), 2.2
    )
    assert_false(check.passes())
    assert_true(check.windward.value < 0.0)


def test_passes_needs_every_limit() raises:
    var good = BaseCheck(
        Force64(1.0),
        Moment64(1.0),
        Pressure64(1.0),
        Pressure64(1.0),
        _m(0.5),
        _m(1.0),
        0.5,
        2.0,
    )
    assert_true(good.passes())
    var outside_kern = good
    outside_kern.eccentricity = _m(1.5)
    assert_false(outside_kern.passes())
    var crushed = good
    crushed.utilization = 1.5
    assert_false(crushed.passes())
    var tipping = good
    tipping.equ_ratio = 0.5
    assert_false(tipping.passes())


def test_base_check_refuses_a_bad_roof_weight() raises:
    var keep = _keep()
    var m = clay_brick_masonry()
    with assert_raises(contains="A roof weight must be zero or more"):
        _ = check_tower_base(keep, m, flanders_wind(), Force64(-1.0), 2.2)
    with assert_raises(contains="A roof weight must be zero or more"):
        _ = check_tower_base(keep, m, flanders_wind(), Force64(1.0e13), 2.2)
    with assert_raises(contains="A partial factor must be 1 or more"):
        _ = check_tower_base(keep, m, flanders_wind(), Force64(0.0), 0.5)
    var bad = m.copy()
    bad.density = Density64(0.0)
    with assert_raises(contains="A masonry density must be positive"):
        _ = cantilever_frequency(keep, bad)


def test_frequency_refuses_an_invalid_tower() raises:
    var t = _keep()
    t.height = _m(0.0)
    with assert_raises(contains="A tower height must be positive"):
        _ = cantilever_frequency(t, clay_brick_masonry())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
