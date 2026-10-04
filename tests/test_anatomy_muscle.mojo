# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The shared Hill-type muscle: Thelen's curves, architecture, the
static solve and moment arms, against closed forms."""

from extensions.anatomy.mode import (
    AnatomyMode,
    ENGINEERING_MODE,
    GAME_MODE,
    require_mode,
)
from extensions.anatomy.muscle import (
    MuscleArchitecture,
    active_force_length,
    activation_rate,
    default_tension,
    force_velocity,
    isometric_equilibrium,
    moment_arm,
    muscle_density,
    passive_force_length,
    tendon_force,
)
from generators.utils import Vec3d
from std.math import cos, exp, inf, nan, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    DEGREE,
    GRAM,
    METER,
    METER_PER_SECOND,
    MILLIMETER,
    Angle,
    Length,
    Mass,
    Velocity,
)


def _arch(pennation: Float64 = 0.0) -> MuscleArchitecture:
    # 100 g, 100 mm fibers, 50 mm tendon.
    return MuscleArchitecture(
        Mass(100, GRAM),
        Length(100, MILLIMETER),
        Angle(Float32(pennation), DEGREE),
        Length(50, MILLIMETER),
        default_tension(),
        muscle_density(),
    )


def test_modes_are_named() raises:
    assert_true(GAME_MODE.is_valid())
    assert_true(ENGINEERING_MODE.is_valid())
    assert_false(AnatomyMode(2).is_valid())
    require_mode(GAME_MODE)
    with assert_raises(contains="mode"):
        require_mode(AnatomyMode(-1))


def test_thelen_curves() raises:
    assert_almost_equal(active_force_length(1.0), 1.0)
    assert_almost_equal(
        active_force_length(0.7), active_force_length(1.3), atol=1e-12
    )
    assert_almost_equal(active_force_length(1.5), exp(-0.25 / 0.45))
    assert_almost_equal(passive_force_length(0.8), 0.0)
    assert_almost_equal(passive_force_length(1.0), 0.0)
    assert_almost_equal(passive_force_length(1.6), 1.0, atol=1e-12)
    assert_almost_equal(force_velocity(-1.5), 0.0)
    assert_almost_equal(force_velocity(-1.0), 0.0)
    assert_almost_equal(force_velocity(0.0), 1.0)
    # Hill's hyperbola: a quarter-speed shortening keeps 3/8 of F0.
    assert_almost_equal(force_velocity(-0.25), 0.75 / 2.0)
    assert_true(force_velocity(0.1) > 1.0)
    assert_true(force_velocity(100.0) < 1.4)
    assert_almost_equal(force_velocity(1e9), 1.4, atol=1e-6)
    assert_almost_equal(tendon_force(-0.01), 0.0)
    assert_almost_equal(tendon_force(0.0), 0.0)
    # The toe meets the line at 0.33 F0, and 4% strain is F0.
    assert_almost_equal(tendon_force(0.609 * 0.04), 0.33, atol=1e-12)
    assert_almost_equal(tendon_force(0.04), 1.0, atol=1e-3)
    assert_true(tendon_force(0.01) < tendon_force(0.02))


def test_activation_rises_faster_than_it_falls() raises:
    var rise = activation_rate(1.0, 0.0)
    var fall = activation_rate(0.0, 1.0)
    # 1 / (0.015 s * 0.5) and -1 / (0.05 s / 2).
    assert_almost_equal(Float64(rise.value), 1.0 / 0.0075, rtol=1e-6)
    assert_almost_equal(Float64(fall.value), -40.0, rtol=1e-6)
    assert_almost_equal(Float64(activation_rate(0.5, 0.5).value), 0.0)


def test_architecture_gives_pcsa_and_force() raises:
    var a = _arch()
    a.check()
    # 0.1 kg / 1060 kg/m^3 / 0.1 m = 9.434e-4 m^2, times 0.3 MPa.
    assert_almost_equal(Float64(a.pcsa().value), 0.1 / 1060 / 0.1, rtol=1e-6)
    assert_almost_equal(
        Float64(a.max_force().value), 0.3e6 * 0.1 / 1060 / 0.1, rtol=1e-6
    )
    var p = _arch(20.0)
    var h = 0.1 * sin(Float64(Angle(20, DEGREE).value))
    assert_almost_equal(p.thickness(), h, rtol=1e-6)
    assert_almost_equal(p.pennation_at(0.1), 20.0 * 0.017453292519943295)
    # A fiber shorter than its spacing stands at a right angle.
    assert_almost_equal(p.pennation_at(h * 0.5), 1.5707963267948966)
    var still = p.fiber_force(1.0, Length(100, MILLIMETER), Velocity(0))
    assert_almost_equal(
        Float64(still.value),
        Float64(p.max_force().value) * cos(Float64(p.pennation.value)),
        rtol=1e-5,
    )
    var fast = a.fiber_force(
        1.0, Length(100, MILLIMETER), Velocity(-0.25, METER_PER_SECOND)
    )
    assert_almost_equal(
        Float64(fast.value), Float64(a.max_force().value) * 0.375, rtol=1e-5
    )
    var idle = a.fiber_force(0.0, Length(160, MILLIMETER), Velocity(0))
    assert_almost_equal(
        Float64(idle.value), Float64(a.max_force().value), rtol=1e-4
    )


def test_architecture_refuses_impossible_values() raises:
    for bad in [nan[DType.float32](), inf[DType.float32]()]:
        var a = _arch()
        a.mass = Mass(bad)
        with assert_raises(contains="finite"):
            a.check()
    var a = _arch()
    a.mass = Mass(0)
    with assert_raises(contains="mass"):
        a.check()
    a = _arch()
    a.fiber_length = Length(-1)
    with assert_raises(contains="fiber"):
        a.check()
    a = _arch()
    a.specific_tension = a.specific_tension.scaled(0)
    with assert_raises(contains="tension"):
        a.check()
    a = _arch()
    a.density = a.density.scaled(-1)
    with assert_raises(contains="density"):
        a.check()
    a = _arch()
    a.tendon_slack = Length(-1)
    with assert_raises(contains="slack"):
        a.check()
    for angle in [-1.0, 61.0]:
        with assert_raises(contains="pennation"):
            _arch(angle).check()


def test_isometric_equilibrium_balances_fibers_and_tendon() raises:
    var a = _arch()
    # At L0 plus a 4%-stretched tendon, fibers and tendon both carry F0.
    var unit = Length(Float32(0.1 + 0.05 * 1.04), METER)
    var e = isometric_equilibrium(a, 1.0, unit)
    var f0 = Float64(a.max_force().value)
    assert_almost_equal(Float64(e.force.value), f0, rtol=2e-3)
    assert_almost_equal(Float64(e.fiber_length.value), 0.1, atol=2e-4)
    assert_almost_equal(
        Float64(e.fiber_length.value + e.tendon_length.value),
        Float64(unit.value),
        atol=1e-6,
    )
    # A pennate muscle: the fiber force along the tendon is the tendon's.
    var p = _arch(25.0)
    var q = isometric_equilibrium(p, 0.6, unit)
    var along = p.fiber_force(0.6, q.fiber_length, Velocity(0))
    assert_almost_equal(Float64(along.value), Float64(q.force.value), rtol=1e-3)
    assert_almost_equal(
        sin(Float64(q.pennation.value)) * Float64(q.fiber_length.value),
        p.thickness(),
        rtol=1e-5,
    )
    # A relaxed muscle at its rest length pulls nothing.
    var rest = isometric_equilibrium(a, 0.0, Length(0.149, METER))
    assert_almost_equal(Float64(rest.force.value), 0.0, atol=1e-6)


def test_isometric_equilibrium_refuses_bad_input() raises:
    var unit = Length(0.2, METER)
    var a = _arch()
    for bad in [-0.1, 1.1, nan[DType.float64]()]:
        with assert_raises(contains="activation"):
            _ = isometric_equilibrium(a, bad, unit)
    with assert_raises(contains="slack"):
        a.tendon_slack = Length(0)
        _ = isometric_equilibrium(a, 1.0, unit)
    with assert_raises(contains="longer"):
        _ = isometric_equilibrium(_arch(), 1.0, Length(0.05, METER))
    var broken = _arch()
    broken.mass = Mass(0)
    with assert_raises(contains="mass"):
        _ = isometric_equilibrium(broken, 1.0, unit)


def test_moment_arm_is_the_lever_across_the_pull() raises:
    var z = Vec3d(0, 0, 1)
    var arm = moment_arm(
        Vec3d(0.05, 1, 0), Vec3d(0.05, 0, 0), Vec3d(0, 0, 0), z
    )
    assert_almost_equal(Float64(arm.value), 0.05, rtol=1e-6)
    var flipped = moment_arm(
        Vec3d(0.05, 1, 0), Vec3d(0.05, 0, 0), Vec3d(0, 0, 0), z * -3.0
    )
    assert_almost_equal(Float64(flipped.value), -0.05, rtol=1e-6)
    with assert_raises(contains="differ"):
        _ = moment_arm(Vec3d(1, 0, 0), Vec3d(1, 0, 0), Vec3d(0, 0, 0), z)
    with assert_raises(contains="axis"):
        _ = moment_arm(
            Vec3d(0, 1, 0), Vec3d(1, 0, 0), Vec3d(0, 0, 0), Vec3d(0, 0, 0)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
