# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Extreme SI values exercise public guards without biological claims."""

from extensions.anatomy.evidence import (
    DESIGN,
    FROM_ABSTRACT,
    FROM_TEXT,
    CROSS_CHECKED,
    UNVERIFIED,
    Evidence,
    evidence_label,
)
from extensions.anatomy.inertia import InertiaTally, SegmentInertia
from extensions.anatomy.muscle import (
    MuscleArchitecture,
    MuscleEquilibrium,
    default_tension,
    muscle_density,
    isometric_equilibrium,
    moment_arm,
    tendon_force,
    active_force_length,
)
from extensions.anatomy.locomotion import (
    speed_at,
    stride_frequency,
    stride_length,
)
from generators.utils import Vec3d
from math.vector3 import Vector3
from std.math import inf, nan, sqrt, isfinite
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
    assert_raises,
)
from units.si import (
    Mass,
    Length,
    Density,
    Pressure,
    Angle,
    MomentOfInertia,
    Velocity,
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


def _tally() raises -> InertiaTally:
    var t = InertiaTally()
    t.add_cell(2, Vector3(0, 0, 0), Vector3(1, 2, 3))
    return t^


def test_evidence_enumeration_covers_real_and_invalid_values() raises:
    for grade in [FROM_ABSTRACT, FROM_TEXT, CROSS_CHECKED, UNVERIFIED, DESIGN]:
        assert_true(grade.is_valid())
        assert_true(evidence_label(grade).byte_length() > 0)
        assert_equal(grade.is_measured(), grade.value <= 2)
    for value in [-1, 5]:
        assert_equal(Evidence(value).is_valid(), False)
        assert_equal(Evidence(value).is_measured(), False)
        with assert_raises(contains="grade"):
            _ = evidence_label(Evidence(value))


def test_point_mass_and_empty_tally_contracts() raises:
    var t = InertiaTally()
    with assert_raises(contains="positive mass"):
        _ = t.result(0)
    t.add_cell(2, Vector3(0, 0, 0), Vector3(0, 0, 0))
    var point = t.result(0)
    assert_equal(point.xx.value, 0.0)
    assert_equal(point.yy.value, 0.0)
    assert_equal(point.zz.value, 0.0)
    assert_equal(point.gyration(point.xx).value, 0.0)
    # Off the origin, a point mass's central moments are rounding noise.
    # Each component uses its own raw cancellation bound.
    for m in [Float64(0.3), Float64(2), Float64(75)]:
        for i in range(-3, 4):
            for j in range(-3, 4):
                var p = Vector3(
                    Float32(0.137 * Float64(i) + 0.011),
                    Float32(-0.091 * Float64(j) + 0.023),
                    Float32(0.053 * Float64(i * j) - 0.017),
                )
                var single = InertiaTally()
                single.add_cell(m, p, Vector3(0, 0, 0))
                var r = single.result(0)
                var reach = m * Float64(p.dot(p))
                for value in [r.xx.value, r.yy.value, r.zz.value]:
                    assert_true(abs(Float64(value)) <= 1e-9 * reach)


def test_center_offset_cannot_hide_invalid_central_tensor() raises:
    # A COM-centered tensor must pass the same check at every origin.
    # Izz > Ixx + Iyy is impossible at both centers.
    for center in [Vector3(0, 0, 0), Vector3(1e12, 0, 0)]:
        var invalid = SegmentInertia(
            Mass(1),
            center,
            MomentOfInertia(1),
            MomentOfInertia(1),
            MomentOfInertia(3),
            MomentOfInertia(0),
            MomentOfInertia(0),
            MomentOfInertia(0),
            Length(1),
        )
        with assert_raises(contains="nonnegative"):
            invalid.check()


def test_segment_guard_validates_mutable_si_state_and_extreme_gyration() raises:
    var s = _tally().result(1)
    assert_almost_equal(
        Float64(s.gyration(MomentOfInertia(4)).value), sqrt(2.0), rtol=1e-6
    )
    s.mass = Mass(0)
    with assert_raises(contains="mass"):
        s.check()
    for value in [Float32(-1), nan[DType.float32](), inf[DType.float32]()]:
        s = _tally().result(1)
        s.length = Length(value)
        with assert_raises(contains="length"):
            s.check()
    for value in [nan[DType.float32](), inf[DType.float32]()]:
        for axis in range(3):
            s = _tally().result(1)
            s.center.set_component(axis, value)
            with assert_raises(contains="finite"):
                s.check()
        s = _tally().result(1)
        s.xy = MomentOfInertia(value)
        with assert_raises(contains="finite"):
            s.check()
    s = _tally().result(1)
    s.mass = Mass(1e-44)
    with assert_raises(contains="gyration"):
        _ = s.gyration(MomentOfInertia(1e38))


def test_architecture_outputs_reject_underflow_and_final_force_overflow() raises:
    var a = _arch()
    a.mass = Mass(1e-40)
    a.density = Density(1e38)
    a.fiber_length = Length(1e38)
    with assert_raises(contains="PCSA"):
        _ = a.pcsa()
    a = _arch()
    a.mass = Mass(1e-40)
    a.density = Density(1)
    a.fiber_length = Length(1)
    a.specific_tension = Pressure(1e-40)
    with assert_raises(contains="force"):
        _ = a.max_force()
    a = _arch()
    with assert_raises(contains="finite SI"):
        _ = a.fiber_force(0, Length(1.6), Velocity(0))
    with assert_raises(contains="finite SI"):
        _ = a.fiber_force(1e-100, Length(0.1), Velocity(0))
    assert_equal(a.fiber_force(0, Length(0.1), Velocity(0)).value, 0.0)


def test_equilibrium_refuses_unrepresentable_force_and_collapsed_tendon() raises:
    var a = _arch()
    a.mass = Mass(1e-44)
    a.density = Density(1)
    a.specific_tension = Pressure(1)
    with assert_raises(contains="Equilibrium force"):
        _ = isometric_equilibrium(a, 0, Length(0.151))
    a = _arch()
    a.tendon_slack = Length(1e-40)
    with assert_raises(contains="Equilibrium tendon"):
        _ = isometric_equilibrium(a, 0, Length(0.1))
    # A small allowed residual must not permit a zero SI fiber length.
    a = _arch()
    a.mass = Mass(1e-35)
    a.fiber_length = Length(1e-40)
    a.tendon_slack = Length(1e-35)
    var unit = Length(1.000001e-35)
    var strain = (
        Float64(unit.value) - Float64(a.tendon_slack.value)
    ) / Float64(a.tendon_slack.value)
    var activation = (tendon_force(strain) + 5e-9) / active_force_length(0.0)
    with assert_raises(contains="Equilibrium fiber"):
        _ = isometric_equilibrium(a, activation, unit)


def test_finite_points_can_still_have_unrepresentable_levers() raises:
    var zero = Vec3d(0, 0, 0)
    var axis = Vec3d(0, 0, 1)
    with assert_raises(contains="differ"):
        _ = moment_arm(Vec3d(1e308, 0, 0), Vec3d(-1e308, 0, 0), zero, axis)
    with assert_raises(contains="axis"):
        _ = moment_arm(
            Vec3d(1, 1, 0), Vec3d(1, 0, 0), zero, Vec3d(1.5e308, 1.5e308, 0)
        )
    with assert_raises(contains="finite SI"):
        _ = moment_arm(Vec3d(1e40, 1, 0), Vec3d(1e40, 0, 0), zero, axis)


def test_zero_froude_and_frequency_overflow_have_distinct_contracts() raises:
    assert_equal(speed_at(0, Length(1)).value, 0.0)
    with assert_raises(contains="frequency"):
        _ = stride_frequency(1e100, Length(1e-40))
    # Couple the two calculations at the smallest accepted speed and
    # largest height, where the positive-frequency bound is tightest.
    var largest = Length(bitcast[DType.float32](UInt32(0x7F7FFFFF)))
    var least = bitcast[DType.float32](UInt32(1))
    with assert_raises(contains="speed"):
        _ = stride_frequency(1e-130, largest)
    for fr in [Float64(1.5e-130), Float64(3e-130), Float64(1e-129)]:
        assert_equal(speed_at(fr, largest).value, least)
        assert_true(stride_length(fr, largest).value > 0.0)
        assert_equal(stride_frequency(fr, largest).value, least)


def test_extreme_finite_scales_either_resolve_or_reject() raises:
    var accepted = 0
    var refused = 0
    for scale in [
        Float32(1e-35),
        Float32(1e-5),
        Float32(0.1),
        Float32(1e5),
        Float32(1e35),
    ]:
        for ratio in [Float32(1e-20), Float32(1), Float32(1e20)]:
            for extension in [
                Float32(1.000001),
                Float32(1.5),
                Float32(3),
                Float32(100),
            ]:
                for activation in [0.0, 1e-12, 0.5, 1.0]:
                    var a = _arch()
                    a.fiber_length = Length(scale)
                    a.tendon_slack = Length(scale * ratio)
                    var e: MuscleEquilibrium
                    try:
                        e = isometric_equilibrium(
                            a, activation, Length(scale * ratio * extension)
                        )
                    except:
                        refused += 1
                        continue
                    # Assertions are outside the rejection handler: a bad
                    # returned value must fail rather than count as refused.
                    assert_true(isfinite(e.force.value) and e.force.value >= 0)
                    assert_true(
                        isfinite(e.fiber_length.value)
                        and e.fiber_length.value > 0
                    )
                    assert_true(
                        isfinite(e.tendon_length.value)
                        and e.tendon_length.value > 0
                    )
                    assert_true(isfinite(e.pennation.value))
                    accepted += 1
    assert_true(accepted > 0)
    assert_true(refused > 0)
    assert_equal(accepted + refused, 5 * 3 * 4 * 4)


def test_fixed_component_guards_preserve_active_lanes_and_padding() raises:
    for value in [nan[DType.float32](), inf[DType.float32]()]:
        for axis in range(6):
            var segment = _tally().result(1)
            var invalid = MomentOfInertia(value)
            if axis == 0:
                segment.xx = invalid
            elif axis == 1:
                segment.yy = invalid
            elif axis == 2:
                segment.zz = invalid
            elif axis == 3:
                segment.xy = invalid
            elif axis == 4:
                segment.xz = invalid
            else:
                segment.yz = invalid
            with assert_raises(contains="finite"):
                segment.check()
    for axis in range(3):
        var empty = InertiaTally()
        empty.first[axis] = 1
        with assert_raises(contains="zero-mass tally cannot hold first"):
            _ = empty.result(0)
    for axis in range(6):
        var empty = InertiaTally()
        empty.second[axis] = 1
        with assert_raises(contains="zero-mass tally cannot hold second"):
            _ = empty.result(0)
    # Padding is not a physical component and was never part of the contract.
    var tally = _tally()
    tally.first[3] = nan[DType.float64]()
    tally.second[6] = inf[DType.float64]()
    tally.second[7] = -inf[DType.float64]()
    var measured = tally.result(1)
    var expected = _tally().result(1)
    assert_equal(measured.mass.value, expected.mass.value)
    assert_equal(measured.center.x, expected.center.x)
    assert_equal(measured.center.y, expected.center.y)
    assert_equal(measured.center.z, expected.center.z)
    assert_equal(measured.xx.value, expected.xx.value)
    assert_equal(measured.yy.value, expected.yy.value)
    assert_equal(measured.zz.value, expected.zz.value)


def test_fixed_cell_axes_keep_original_error_precedence() raises:
    var tally = _tally()
    var bad = nan[DType.float32]()
    with assert_raises(contains="cell mass"):
        tally.add_cell(-1, Vector3(bad, bad, bad), Vector3(-1, -1, -1))
    with assert_raises(contains="cell center"):
        tally.add_cell(1, Vector3(bad, 0, 0), Vector3(-1, 1, 1))
    with assert_raises(contains="Cell widths"):
        tally.add_cell(1, Vector3(0, bad, 0), Vector3(-1, 1, 1))
    with assert_raises(contains="cell center"):
        tally.add_cell(1, Vector3(0, bad, 0), Vector3(1, -1, 1))
    with assert_raises(contains="Cell widths"):
        tally.add_cell(1, Vector3(0, 0, bad), Vector3(1, -1, 1))
    assert_equal(tally.result(1).mass.value, 2.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
