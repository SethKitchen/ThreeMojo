# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the wind on the donjon.

The reference numbers were worked by hand from the formulas of EN 1991-1-4
(clauses 4.3 to 4.5, 6.3, 7.9, 7.13 and Annexes B, E and F), in a separate
calculation. The tower is the donjon: 6.86 m across, with a 1.2 m wall, 29.28 m
high, standing 2.29 m below the ground round it, in category II terrain at a
basic wind velocity of 26 m/s.
"""

from extensions.castle.plan import Tower
from extensions.castle.wijnendale import wijnendale_plan
from extensions.castle.wind import (
    BRICKWORK_ROUGHNESS,
    base_check,
    cylinder_force_coefficient,
    donjon_shaft,
    effective_slenderness,
    end_effect_factor,
    reynolds_number,
    shaft_frequency_beam,
    shaft_frequency_en,
    shaft_frequency_fe,
    structural_factor,
    terrain_category_ii,
    terrain_category_iii,
    tower_wind,
    wijnendale_wind_site,
)
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Density64,
    Force64,
    Frequency64,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    METER_PER_SECOND,
    Moment64,
    PER_SECOND,
    Velocity64,
)


def _meters(value: Float64) -> Length64:
    return Length64(value, METER)


def _hertz(value: Float64) -> Frequency64:
    return Frequency64(value, PER_SECOND)


def test_the_pressure_follows_the_profile_of_the_standard() raises:
    var site = wijnendale_wind_site()
    # At 26.99 m: vm = 31.0785 m/s, Iv = 0.158952, qp = 1275.356 Pa.
    assert_almost_equal(
        site.mean_velocity(_meters(26.99)).value, 31.07852, atol=1.0e-4
    )
    assert_almost_equal(
        site.turbulence_intensity(_meters(26.99)), 0.158952, atol=1.0e-6
    )
    assert_almost_equal(
        site.peak_pressure(_meters(26.99)).value, 1275.356, atol=0.01
    )
    # Below zmin the profile is flat.
    assert_almost_equal(
        site.peak_pressure(_meters(1.0)).value, 601.396, atol=0.01
    )
    assert_almost_equal(
        site.peak_pressure(_meters(2.0)).value, 601.396, atol=0.01
    )
    # At 10 m the roughness factor is cr = 1.00668 and qp = 993.84 Pa.
    assert_almost_equal(
        site.roughness_factor(_meters(10.0)), 1.0066803, atol=1.0e-6
    )
    assert_almost_equal(
        site.peak_pressure(_meters(10.0)).value, 993.8425, atol=0.01
    )


def test_a_rougher_terrain_blows_less_at_height() raises:
    var open = terrain_category_ii(Velocity64(26.0, METER_PER_SECOND))
    var woods = terrain_category_iii(Velocity64(26.0, METER_PER_SECOND))
    var near = woods.peak_pressure(_meters(26.99)).value
    assert_almost_equal(near, 1014.1686, atol=0.01)
    assert_true(near < open.peak_pressure(_meters(26.99)).value)
    assert_almost_equal(woods.roughness_length.value, 0.3, atol=1.0e-12)
    assert_almost_equal(woods.minimum_height.value, 5.0, atol=1.0e-12)
    assert_almost_equal(open.roughness_length.value, 0.05, atol=1.0e-12)
    assert_almost_equal(open.minimum_height.value, 2.0, atol=1.0e-12)
    assert_almost_equal(open.air_density.value, 1.25, atol=1.0e-12)
    assert_almost_equal(woods.turbulence_factor, 1.0, atol=1.0e-12)


def test_a_wind_site_is_checked() raises:
    var good = wijnendale_wind_site()
    var weak = good
    weak.basic_velocity = Velocity64(0.0, METER_PER_SECOND)
    with assert_raises(contains="positive finite"):
        weak.check()
    var buried = good
    buried.minimum_height = _meters(0.01)
    with assert_raises(contains="over the roughness length"):
        buried.check()
    with assert_raises(contains="zero or more"):
        _ = good.peak_pressure(_meters(-1.0))
    with assert_raises(contains="positive finite"):
        _ = weak.peak_pressure(_meters(10.0))
    var thin = good
    thin.air_density = Density64(0.0, KILOGRAM_PER_CUBIC_METER)
    with assert_raises(contains="positive finite"):
        _ = thin.turbulence_intensity(_meters(10.0))


def test_the_reynolds_number_is_the_diameter_times_the_speed_over_the_viscosity() raises:
    var re = reynolds_number(
        _meters(6.86), Velocity64(45.172666, METER_PER_SECOND)
    )
    assert_almost_equal(re, 2.0658966e7, atol=100.0)
    with assert_raises(contains="positive"):
        _ = reynolds_number(_meters(0.0), Velocity64(1.0, METER_PER_SECOND))
    with assert_raises(contains="positive"):
        _ = reynolds_number(_meters(1.0), Velocity64(0.0, METER_PER_SECOND))


def test_the_force_coefficient_follows_figure_7_28() raises:
    var roughness = Length64(BRICKWORK_ROUGHNESS)
    # Subcritical flow: 1.2.
    assert_almost_equal(
        cylinder_force_coefficient(1.0e5, roughness, _meters(6.86)),
        1.2,
        atol=1.0e-12,
    )
    # The falling branch, 0.11 / (Re / 1e6)^1.4, when it is over the rough
    # formula: a smooth cylinder at 3e5.
    assert_almost_equal(
        cylinder_force_coefficient(3.0e5, _meters(1.0e-5), _meters(1.0)),
        0.5935030,
        atol=1.0e-6,
    )
    # The same Reynolds number and k/b of 1e-3: the rough formula governs.
    assert_almost_equal(
        cylinder_force_coefficient(3.0e5, _meters(1.0e-3), _meters(1.0)),
        0.7447927,
        atol=1.0e-6,
    )
    # A worked example of the standard: k/b = 8e-5, Re = 5.1e6, 0.7655.
    assert_almost_equal(
        cylinder_force_coefficient(5.1e6, _meters(0.0002), _meters(2.5)),
        0.7655249,
        atol=1.0e-6,
    )
    # The donjon, a brick wall at 2e7.
    assert_almost_equal(
        cylinder_force_coefficient(2.0e7, roughness, _meters(6.86)),
        0.9206964,
        atol=1.0e-6,
    )
    # The roughness ratio is held to the range of the figure.
    assert_almost_equal(
        cylinder_force_coefficient(1.0e6, _meters(1.0e-6), _meters(1.0)),
        0.48,
        atol=1.0e-9,
    )
    assert_almost_equal(
        cylinder_force_coefficient(1.0e6, _meters(0.5), _meters(1.0)),
        1.02,
        atol=1.0e-9,
    )
    # The floor of 0.4.
    assert_almost_equal(
        cylinder_force_coefficient(4.5e5, _meters(1.0e-6), _meters(1.0)),
        0.4,
        atol=1.0e-9,
    )
    with assert_raises(contains="positive"):
        _ = cylinder_force_coefficient(0.0, roughness, _meters(1.0))
    with assert_raises(contains="positive"):
        _ = cylinder_force_coefficient(1.0e6, _meters(0.0), _meters(1.0))
    with assert_raises(contains="positive"):
        _ = cylinder_force_coefficient(1.0e6, roughness, _meters(0.0))


def test_the_effective_slenderness_follows_table_7_16() raises:
    # 50 m or more: 0.7 l / b.
    assert_almost_equal(
        effective_slenderness(_meters(60.0), _meters(2.0)), 21.0, atol=1.0e-12
    )
    # Under 15 m: l / b.
    assert_almost_equal(
        effective_slenderness(_meters(10.0), _meters(2.0)), 5.0, atol=1.0e-12
    )
    # Between: the two values at 15 m and 50 m are interpolated.
    assert_almost_equal(
        effective_slenderness(_meters(30.0), _meters(3.0)),
        7.857142857,
        atol=1.0e-8,
    )
    assert_almost_equal(
        effective_slenderness(_meters(26.99), _meters(6.86)),
        3.1853394,
        atol=1.0e-6,
    )
    # At most 70, in every branch.
    assert_almost_equal(
        effective_slenderness(_meters(100.0), _meters(1.0)), 70.0, atol=1.0e-12
    )
    assert_almost_equal(
        effective_slenderness(_meters(14.0), _meters(0.1)), 70.0, atol=1.0e-12
    )
    assert_almost_equal(
        effective_slenderness(_meters(20.0), _meters(0.1)), 70.0, atol=1.0e-12
    )
    with assert_raises(contains="positive"):
        _ = effective_slenderness(_meters(0.0), _meters(1.0))
    with assert_raises(contains="positive"):
        _ = effective_slenderness(_meters(1.0), _meters(0.0))


def test_the_end_effect_factor_follows_figure_7_36() raises:
    assert_almost_equal(end_effect_factor(0.5), 0.6, atol=1.0e-12)
    assert_almost_equal(end_effect_factor(1.0), 0.6, atol=1.0e-12)
    # A worked example of the standard reads 0.65 at 2.4.
    assert_almost_equal(end_effect_factor(2.4), 0.6380211, atol=1.0e-6)
    assert_almost_equal(end_effect_factor(3.1853394), 0.6503156, atol=1.0e-6)
    assert_almost_equal(end_effect_factor(10.0), 0.7, atol=1.0e-12)
    assert_almost_equal(end_effect_factor(30.0), 0.8242065, atol=1.0e-6)
    assert_almost_equal(end_effect_factor(70.0), 0.92, atol=1.0e-9)
    assert_almost_equal(end_effect_factor(100.0), 0.9471798, atol=1.0e-6)
    assert_almost_equal(end_effect_factor(200.0), 1.0, atol=1.0e-12)
    assert_almost_equal(end_effect_factor(300.0), 1.0, atol=1.0e-12)
    with assert_raises(contains="positive"):
        _ = end_effect_factor(0.0)


def test_the_donjon_is_a_hollow_round_shaft() raises:
    var shaft = donjon_shaft(wijnendale_plan())
    assert_almost_equal(shaft.outer_diameter.value, 6.86, atol=1.0e-12)
    assert_almost_equal(shaft.inner_diameter().value, 4.46, atol=1.0e-12)
    assert_almost_equal(shaft.height.value, 29.28, atol=1.0e-9)
    assert_almost_equal(shaft.base_below_ground.value, 2.29, atol=1.0e-9)
    assert_almost_equal(shaft.area().value, 21.3377, atol=1.0e-3)
    assert_almost_equal(shaft.inertia().value, 89.2865, atol=1.0e-3)
    assert_almost_equal(shaft.mass_per_length(), 38407.855, atol=0.01)
    assert_almost_equal(shaft.weight().value / 1.0e6, 11.02838, atol=1.0e-4)
    # (Do^2 + Di^2) / (8 Do) for the core of a ring.
    assert_almost_equal(shaft.core_radius().value, 1.21996, atol=1.0e-4)


def test_a_shaft_is_checked() raises:
    var good = donjon_shaft(wijnendale_plan())
    var thin = good.copy()
    thin.outer_diameter = _meters(0.0)
    with assert_raises(contains="positive finite size"):
        thin.check()
    var hollow = good.copy()
    hollow.wall_thickness = _meters(3.5)
    with assert_raises(contains="thinner than its radius"):
        hollow.check()
    var buried = good.copy()
    buried.base_below_ground = _meters(40.0)
    with assert_raises(contains="below the ground"):
        buried.check()
    var raised = good.copy()
    raised.base_below_ground = _meters(-1.0)
    with assert_raises(contains="below the ground"):
        raised.check()
    var pulled = good.copy()
    pulled.top_load = Force64(-1.0)
    with assert_raises(contains="top load"):
        pulled.check()
    var plan = wijnendale_plan()
    plan.towers = List[Tower]()
    with assert_raises(contains="tower"):
        _ = donjon_shaft(plan)


def test_the_three_frequencies_are_computed() raises:
    var shaft = donjon_shaft(wijnendale_plan())
    # F.3: 700 b / h^2 for a masonry chimney, 5.60 Hz.
    assert_almost_equal(
        shaft_frequency_en(shaft).to(PER_SECOND), 5.601186, atol=1.0e-5
    )
    # The Euler-Bernoulli cantilever, with E of 1000 f_k.
    var beam = shaft_frequency_beam(shaft).to(PER_SECOND)
    assert_almost_equal(beam, 2.4162543, atol=1.0e-6)
    # The finite element model agrees with the beam, to within the shear
    # deformation of a short member and the error of the mesh.
    var fe = shaft_frequency_fe(shaft, 12).to(PER_SECOND)
    assert_almost_equal(fe, 2.398977, atol=1.0e-5)
    assert_true(abs(fe / beam - 1.0) < 0.01)
    # A finer mesh gives the same frequency to a part in 1e5.
    var fine = shaft_frequency_fe(shaft, 16).to(PER_SECOND)
    assert_true(abs(fine / fe - 1.0) < 1.0e-5)
    with assert_raises(contains="2 to 16"):
        _ = shaft_frequency_fe(shaft, 1)
    with assert_raises(contains="2 to 16"):
        _ = shaft_frequency_fe(shaft, 17)


def test_the_structural_factor_follows_annex_b() raises:
    var site = wijnendale_wind_site()
    var factor = structural_factor(
        site,
        _meters(26.99),
        _meters(6.86),
        _hertz(2.398977),
        0.5994135,
        38407.855,
        0.03,
    )
    assert_almost_equal(factor.reference_height.value, 16.194, atol=1.0e-9)
    assert_almost_equal(factor.length_scale.value, 81.136610, atol=1.0e-5)
    assert_almost_equal(factor.background, 0.6583846, atol=1.0e-6)
    assert_almost_equal(factor.resonance, 0.1725472, atol=1.0e-6)
    assert_almost_equal(factor.peak_factor, 3.7682647, atol=1.0e-5)
    assert_almost_equal(factor.log_decrement, 0.0307965, atol=1.0e-6)
    assert_almost_equal(factor.value, 0.9898249, atol=1.0e-6)
    # Under 1: the 1 that clause 6.2(1)d allows is safe.
    assert_true(factor.value < 1.0)
    # A short, light structure at a low frequency has a low up-crossing
    # frequency, which is held at 0.08 Hz, a peak factor of 3.
    var slow = structural_factor(
        site,
        _meters(5.0),
        _meters(1.0),
        _hertz(0.01),
        1.0,
        10.0,
        0.03,
    )
    assert_almost_equal(slow.up_crossing.to(PER_SECOND), 0.08, atol=1.0e-12)
    assert_almost_equal(slow.peak_factor, 3.0, atol=1.0e-12)
    with assert_raises(contains="positive finite"):
        _ = structural_factor(
            site, _meters(0.0), _meters(1.0), _hertz(1.0), 1.0, 1.0, 0.03
        )
    var bad = site
    bad.basic_velocity = Velocity64(0.0, METER_PER_SECOND)
    with assert_raises(contains="positive finite"):
        _ = structural_factor(
            bad, _meters(10.0), _meters(1.0), _hertz(1.0), 1.0, 1.0, 0.03
        )


def test_the_wind_on_the_donjon_matches_the_hand_calculation() raises:
    var shaft = donjon_shaft(wijnendale_plan())
    var site = wijnendale_wind_site()
    var wind = tower_wind(site, shaft, _hertz(2.398977))
    assert_almost_equal(wind.peak_pressure.value, 1275.356, atol=0.01)
    assert_almost_equal(wind.reynolds, 2.0658966e7, atol=100.0)
    assert_almost_equal(wind.cf0, 0.9217271, atol=1.0e-6)
    assert_almost_equal(wind.slenderness, 3.1853394, atol=1.0e-6)
    assert_almost_equal(wind.end_effect, 0.6503156, atol=1.0e-6)
    assert_almost_equal(wind.cf, 0.5994135, atol=1.0e-6)
    assert_almost_equal(wind.structural.value, 0.9898249, atol=1.0e-6)
    # cscd is taken as 1 where the detailed value is lower.
    assert_almost_equal(wind.cscd, 1.0, atol=1.0e-12)
    assert_almost_equal(wind.base_shear.value, 118996.757, atol=0.5)
    assert_almost_equal(wind.base_moment.value, 1964687.87, atol=50.0)
    # The simple rule, with qp at the top over the whole area, is higher.
    assert_almost_equal(wind.simple_force.value, 153551.18, atol=0.5)
    assert_true(wind.simple_force.value > wind.base_shear.value)
    # Annex E: v_crit = b n1 / 0.18, 45.7 m/s at 2.4 Hz, over 1.25 vm. The
    # shaft is also under 6 diameters high.
    assert_almost_equal(
        wind.critical_velocity.value, 6.86 * 2.398977 / 0.18, atol=1.0e-6
    )
    assert_false(wind.vortex_check_needed)
    with assert_raises(contains="frequency"):
        _ = tower_wind(site, shaft, _hertz(0.0))


def test_a_slender_flexible_shaft_needs_the_vortex_check() raises:
    var shaft = donjon_shaft(wijnendale_plan())
    shaft.outer_diameter = _meters(2.0)
    shaft.wall_thickness = _meters(0.4)
    shaft.height = _meters(29.28)
    var site = wijnendale_wind_site()
    # 29.28 m over 2 m is 13 diameters. At 0.4 Hz the critical velocity is
    # 4.4 m/s, far under the mean wind speed.
    var slender = tower_wind(site, shaft, _hertz(0.4))
    assert_true(slender.vortex_check_needed)
    # At 20 Hz it is 222 m/s, over 1.25 vm, so the check is not needed.
    var stiff = tower_wind(site, shaft, _hertz(20.0))
    assert_false(stiff.vortex_check_needed)


def test_the_base_of_the_donjon_carries_the_wind() raises:
    var shaft = donjon_shaft(wijnendale_plan())
    var wind = tower_wind(wijnendale_wind_site(), shaft, _hertz(2.398977))
    var check = base_check(shaft, wind)
    assert_almost_equal(check.moment.value, 1.5 * 1964687.87, atol=100.0)
    assert_almost_equal(check.shear.value, 1.5 * 118996.757, atol=1.0)
    # sigma = 1.35 N / A + M / W, and 0.9 N / A - M / W.
    assert_almost_equal(check.maximum_stress.value, 810959.6, atol=200.0)
    assert_almost_equal(check.minimum_stress.value, 351952.6, atol=200.0)
    assert_almost_equal(check.design_strength.value, 2357901.6, atol=1.0)
    assert_almost_equal(check.compression_utilization, 0.343933, atol=1.0e-4)
    assert_true(check.tension_free)
    assert_true(check.eccentricity.value < check.core_radius.value)
    assert_almost_equal(check.eccentricity.value, 0.296914, atol=1.0e-4)
    assert_almost_equal(check.overturning_utilization, 0.0865638, atol=1.0e-4)
    assert_true(check.shear_utilization < 0.2)
    assert_almost_equal(check.shear_stress.value, 16730.5, atol=5.0)
    assert_almost_equal(check.shear_resistance.value, 154426.4, atol=50.0)


def test_a_great_moment_opens_the_joint() raises:
    var shaft = donjon_shaft(wijnendale_plan())
    var wind = tower_wind(wijnendale_wind_site(), shaft, _hertz(2.398977))
    wind.base_moment = Moment64(40.0e6)
    var check = base_check(shaft, wind)
    assert_false(check.tension_free)
    assert_true(check.minimum_stress.value < 0.0)
    assert_true(check.overturning_utilization > 1.0)


def test_a_number_that_is_not_a_number_is_refused_everywhere() raises:
    var no = nan[DType.float64]()
    var site = wijnendale_wind_site()
    var lost = site
    lost.basic_velocity = Velocity64(no, METER_PER_SECOND)
    with assert_raises(contains="positive finite"):
        lost.check()
    with assert_raises(contains="zero or more"):
        _ = site.peak_pressure(_meters(no))
    var speed = Velocity64(1.0, METER_PER_SECOND)
    with assert_raises(contains="positive"):
        _ = reynolds_number(_meters(no), speed)
    with assert_raises(contains="positive"):
        _ = reynolds_number(_meters(1.0), Velocity64(no, METER_PER_SECOND))
    var rough = _meters(1.0e-3)
    with assert_raises(contains="positive"):
        _ = cylinder_force_coefficient(no, rough, _meters(1.0))
    with assert_raises(contains="positive"):
        _ = cylinder_force_coefficient(1.0e6, _meters(no), _meters(1.0))
    with assert_raises(contains="positive"):
        _ = cylinder_force_coefficient(1.0e6, rough, _meters(no))
    with assert_raises(contains="positive"):
        _ = effective_slenderness(_meters(no), _meters(1.0))
    with assert_raises(contains="positive"):
        _ = effective_slenderness(_meters(1.0), _meters(no))
    with assert_raises(contains="positive"):
        _ = end_effect_factor(no)
    var good = donjon_shaft(wijnendale_plan())
    var size = good.copy()
    size.outer_diameter = _meters(no)
    with assert_raises(contains="positive finite size"):
        size.check()
    var base = good.copy()
    base.base_below_ground = _meters(no)
    with assert_raises(contains="below the ground"):
        base.check()
    var load = good.copy()
    load.top_load = Force64(no)
    with assert_raises(contains="top load"):
        load.check()
    var hertz = _hertz(1.0)
    with assert_raises(contains="positive finite"):
        _ = structural_factor(
            site, _meters(10.0), _meters(1.0), _hertz(no), 1.0, 1.0, 0.03
        )
    with assert_raises(contains="positive finite"):
        _ = structural_factor(
            site, _meters(no), _meters(1.0), hertz, 1.0, 1.0, 0.03
        )
    with assert_raises(contains="frequency"):
        _ = tower_wind(site, good, _hertz(no))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
