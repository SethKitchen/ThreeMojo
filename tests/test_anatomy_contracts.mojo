# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Adversarial SI contracts and independent physical admissibility checks."""

from extensions.anatomy.inertia import InertiaTally
from extensions.anatomy.locomotion import (
    froude,
    speed_at,
    stride_length,
    stride_frequency,
)
from extensions.anatomy.muscle import (
    MuscleArchitecture,
    active_force_length,
    passive_force_length,
    force_velocity,
    tendon_force,
    activation_rate,
    default_tension,
    muscle_density,
    isometric_equilibrium,
    moment_arm,
)
from generators.utils import Vec3d
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import TestSuite, assert_raises, assert_almost_equal
from units.si import (
    Mass,
    Length,
    Angle,
    Velocity,
    Pressure,
    MomentOfInertia,
    Density,
    DEGREE,
)


def _arch() -> MuscleArchitecture:
    return MuscleArchitecture(
        Mass(0.1),
        Length(0.1),
        Angle(0, DEGREE),
        Length(0.05),
        default_tension(),
        muscle_density(),
    )


def test_force_curves_refuse_nonfinite_and_impossible_state() raises:
    for value in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        with assert_raises():
            _ = active_force_length(value)
        with assert_raises():
            _ = passive_force_length(value)
        with assert_raises():
            _ = force_velocity(value)
        with assert_raises():
            _ = tendon_force(value)
    for value in [
        -0.1,
        nan[DType.float64](),
        -inf[DType.float64](),
        inf[DType.float64](),
        1.1,
    ]:
        with assert_raises(contains="activation"):
            _ = activation_rate(value, 0.5)
        with assert_raises(contains="activation"):
            _ = activation_rate(0.5, value)
        with assert_raises(contains="activation"):
            _ = _arch().fiber_force(value, Length(0.1), Velocity(0))
    with assert_raises():
        _ = active_force_length(-1)
    with assert_raises():
        _ = passive_force_length(-1)
    with assert_raises(contains="finite"):
        _ = passive_force_length(1e308)
    with assert_raises(contains="finite"):
        _ = tendon_force(1e308)
    # The bounded lengthening asymptote stays finite at a huge finite input.
    assert_almost_equal(force_velocity(1e308), 1.4, atol=1e-14)


def test_mutable_architecture_is_checked_at_every_public_calculation() raises:
    var bad = _arch()
    bad.mass = Mass(-1)
    with assert_raises(contains="mass"):
        _ = bad.volume_m3()
    with assert_raises(contains="mass"):
        _ = bad.pcsa()
    with assert_raises(contains="mass"):
        _ = bad.max_force()
    with assert_raises(contains="mass"):
        _ = bad.thickness()
    with assert_raises(contains="mass"):
        _ = bad.pennation_at(0.1)
    with assert_raises(contains="mass"):
        _ = bad.fiber_force(0.5, Length(0.1), Velocity(0))
    var a = _arch()
    for value in [
        Float32(0),
        Float32(-1),
        nan[DType.float32](),
        inf[DType.float32](),
    ]:
        with assert_raises(contains="fiber"):
            _ = a.pennation_at(Float64(value))
        with assert_raises(contains="fiber"):
            _ = a.fiber_force(0.5, Length(value), Velocity(0))
    for value in [nan[DType.float32](), inf[DType.float32]()]:
        with assert_raises(contains="velocity"):
            _ = a.fiber_force(0.5, Length(0.1), Velocity(value))
        with assert_raises():
            _ = isometric_equilibrium(a, 1.0, Length(value))
    a.mass = Mass(1e38)
    a.fiber_length = Length(1e-30)
    with assert_raises(contains="PCSA"):
        _ = a.pcsa()
    a = _arch()
    a.specific_tension = Pressure(1e38)
    a.fiber_length = Length(1e-10)
    with assert_raises(contains="force"):
        _ = a.max_force()


def test_final_force_is_narrowed_only_after_double_precision_product() raises:
    var arch = _arch()
    arch.mass = Mass(1)
    arch.density = Density(1)
    arch.fiber_length = Length(1)
    arch.specific_tension = Pressure(1e38)
    var tiny = arch.fiber_force(1e-50, Length(1), Velocity(0))
    assert_almost_equal(Float64(tiny.value), 1e-12, rtol=1e-6, atol=1e-18)
    arch.specific_tension = Pressure(1e-38)
    var large = arch.fiber_force(0, Length(16), Velocity(0))
    assert_almost_equal(
        Float64(large.value), 1e-38 * passive_force_length(16), rtol=1e-5
    )
    for slack in [Float32(1e-15), Float32(1e-17)]:
        arch = _arch()
        arch.tendon_slack = Length(slack)
        with assert_raises(contains="resolve equilibrium"):
            _ = isometric_equilibrium(arch, 1, Length(0.1))


def test_moment_arm_rejects_nonfinite_geometry() raises:
    var a = Vec3d(0, 1, 0)
    var b = Vec3d(1, 0, 0)
    var c = Vec3d(0, 0, 0)
    var axis = Vec3d(0, 0, 1)
    for value in [nan[DType.float64](), inf[DType.float64]()]:
        for bad in [Vec3d(value, 0, 0), Vec3d(0, value, 0), Vec3d(0, 0, value)]:
            with assert_raises(contains="finite"):
                _ = moment_arm(bad, b, c, axis)
            with assert_raises(contains="finite"):
                _ = moment_arm(a, b, bad, axis)
            with assert_raises(contains="finite"):
                _ = moment_arm(a, b, c, bad)


def _tally() raises -> InertiaTally:
    var out = InertiaTally()
    out.add_cell(2, Vector3(0, 0, 0), Vector3(1, 2, 3))
    return out^


def test_cell_contract_cannot_create_signed_mass_or_nonfinite_moments() raises:
    var t = _tally()
    for value in [Float64(-1), nan[DType.float64](), inf[DType.float64]()]:
        with assert_raises(contains="mass"):
            t.add_cell(value, Vector3(1, 0, 0), Vector3(0, 0, 0))
    for value in [nan[DType.float32](), inf[DType.float32]()]:
        for axis in range(3):
            var p = Vector3(0, 0, 0)
            p.set_component(axis, value)
            with assert_raises(contains="center"):
                t.add_cell(1, p, Vector3(0, 0, 0))
    for value in [Float32(-1), nan[DType.float32](), inf[DType.float32]()]:
        for axis in range(3):
            var w = Vector3(1, 1, 1)
            w.set_component(axis, value)
            with assert_raises(contains="widths"):
                t.add_cell(1, Vector3(0, 0, 0), w)
    # Rejected additions leave the original analytic cuboid unchanged.
    var s = t.result(3)
    assert_almost_equal(s.mass.value, 2.0)
    assert_almost_equal(s.xx.value, 2.0 * (4.0 + 9.0) / 12.0, atol=1e-6)
    assert_almost_equal(s.yy.value, 2.0 * (1.0 + 9.0) / 12.0, atol=1e-6)
    assert_almost_equal(s.zz.value, 2.0 * (1.0 + 4.0) / 12.0, atol=1e-6)


def test_result_refuses_corrupt_sums_and_unrepresentable_si_output() raises:
    for value in [nan[DType.float64](), inf[DType.float64]()]:
        for axis in range(6):
            var t = _tally()
            t.second[axis] = value
            with assert_raises(contains="moments"):
                _ = t.result(1)
        for axis in range(3):
            var t = _tally()
            t.first[axis] = value
            with assert_raises(contains="moments"):
                _ = t.result(1)
    for value in [Float32(-1), nan[DType.float32](), inf[DType.float32]()]:
        with assert_raises(contains="length"):
            _ = _tally().result(value)
    var empty = InertiaTally()
    empty.second[0] = 1
    with assert_raises(contains="zero-mass"):
        _ = empty.result(0)
    var huge = InertiaTally()
    huge.add_cell(1e100, Vector3(0, 0, 0), Vector3(1, 1, 1))
    with assert_raises(contains="mass"):
        _ = huge.result(1)
    var bad = _tally()
    bad.second[0] = -1
    with assert_raises(contains="nonnegative"):
        _ = bad.result(1)
    bad = _tally()
    bad.second[3] = 10
    with assert_raises(contains="admissible"):
        _ = bad.result(1)
    bad = _tally()
    bad.second = SIMD[DType.float64, 8](1, 1, 1, 0.9, 0.9, -0.9, 0, 0)
    with assert_raises(contains="admissible"):
        _ = bad.result(1)


def test_tiny_negative_inertia_diagonal_is_never_exported() raises:
    var bad = InertiaTally()
    bad.mass = 1
    bad.second = SIMD[DType.float64, 8](-1e-11, 0, 1, 0, 0, 0, 0, 0)
    with assert_raises(contains="nonnegative"):
        _ = bad.result(0)


def test_equilibrium_refuses_finite_fiber_that_overflows_si_length() raises:
    var arch = MuscleArchitecture(
        Mass(1e38),
        Length(3e38),
        Angle(60, DEGREE),
        Length(1e36),
        Pressure(1),
        Density(1),
    )
    with assert_raises(contains="Equilibrium fiber"):
        _ = isometric_equilibrium(arch, 1, Length(3e38))


def test_segment_gyration_refuses_nonphysical_mutated_tensor() raises:
    var s = _tally().result(1)
    for value in [Float32(-1), nan[DType.float32](), inf[DType.float32]()]:
        with assert_raises(contains="moment"):
            _ = s.gyration(MomentOfInertia(value))
    s.xx = MomentOfInertia(1)
    s.yy = MomentOfInertia(1)
    s.zz = MomentOfInertia(4)
    with assert_raises(contains="nonnegative"):
        s.check()
    # This positive diagonal matrix violates an inertia triangle inequality.
    with assert_raises(contains="nonnegative"):
        _ = s.gyration(s.xx)


def test_locomotion_refuses_nonfinite_or_unrepresentable_si_values() raises:
    for value in [nan[DType.float32](), inf[DType.float32]()]:
        with assert_raises(contains="speed"):
            _ = froude(Velocity(value), Length(1))
    with assert_raises(contains="speed"):
        _ = speed_at(1e100, Length(1))
    with assert_raises(contains="speed"):
        _ = speed_at(1e-100, Length(1))
    with assert_raises(contains="stride"):
        _ = stride_length(1e200, Length(1))
    with assert_raises(contains="stride"):
        _ = stride_length(1e-300, Length(1e-30))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
