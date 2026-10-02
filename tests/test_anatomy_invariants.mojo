# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Geometric and input invariants shared by the anatomical templates."""

from extensions.humanoid.sex import MALE, FEMALE
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import DistanceField, flip_x
from extensions.humanoid.skeleton.leg.femur.dimensions import (
    FemurField,
    femur_dimensions,
)
from extensions.humanoid.skeleton.leg.fibula.dimensions import (
    FibulaField,
    fibula_dimensions,
)
from extensions.humanoid.skeleton.leg.tibia.dimensions import (
    TibiaField,
    tibia_dimensions,
)
from extensions.humanoid.skeleton.leg.knee.dimensions import (
    MeniscusField,
    knee_dimensions,
    MEDIAL_MENISCUS,
    LATERAL_MENISCUS,
)
from extensions.humanoid.skeleton.leg.patella.dimensions import (
    PatellaField,
    patella_dimensions,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleField,
    muscle_dimensions,
    GLUTEUS_MEDIUS,
)
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    foot_muscle_dimensions,
)
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    pelvis_muscle_dimensions,
)
from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    torso_muscle_dimensions,
)
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_raises,
    assert_true,
)
from units.si import Length, FOOT, METER


def _reflection[
    F: DistanceField
](right: F, left: F, low: Vector3, high: Vector3) raises:
    """Compare full fields, not just mirrored landmarks."""
    for ix in range(9):
        for iy in range(17):
            for iz in range(9):
                var p = Vector3(
                    low.x + (high.x - low.x) * Float32(ix) / 8,
                    low.y + (high.y - low.y) * Float32(iy) / 16,
                    low.z + (high.z - low.z) * Float32(iz) / 8,
                )
                assert_almost_equal(
                    right.distance(p), left.distance(flip_x(p)), atol=1.0e-6
                )


def test_left_fields_reflect_the_complete_right_solid() raises:
    var h = Length(6.0, FOOT)
    for sex in [MALE, FEMALE]:
        var fr = FibulaField(fibula_dimensions(h, sex, RIGHT))
        var fl = FibulaField(fibula_dimensions(h, sex, LEFT))
        _reflection(fr, fl, fr.low, fr.high)
        var tr = TibiaField(tibia_dimensions(h, sex, RIGHT))
        var tl = TibiaField(tibia_dimensions(h, sex, LEFT))
        _reflection(tr, tl, tr.low, tr.high)
        for part in [MEDIAL_MENISCUS, LATERAL_MENISCUS]:
            var mr = MeniscusField(knee_dimensions(h, sex, RIGHT), part)
            var ml = MeniscusField(knee_dimensions(h, sex, LEFT), part)
            _reflection(mr, ml, mr.low, mr.high)


def _contains(low: Vector3, high: Vector3, p: Vector3) raises:
    """Require an interior station to lie strictly inside its sample box."""
    assert_true(p.x > low.x and p.x < high.x)
    assert_true(p.y > low.y and p.y < high.y)
    assert_true(p.z > low.z and p.z < high.z)


def test_edited_bows_remain_in_the_field_bounds() raises:
    var h = Length(6.0, FOOT)
    var femur = femur_dimensions(h, MALE)
    femur.anterior_bow = Length(0.1, METER)
    var f = FemurField(femur)
    _contains(f.low, f.high, f.s2 + Vector3(0, 0, f.ap2))
    var tibia = tibia_dimensions(h, MALE)
    tibia.anterior_bow = Length(0.1, METER)
    var t = TibiaField(tibia)
    _contains(t.low, t.high, t.s2 + Vector3(0, 0, max(t.ml2, t.ap2)))
    for side in [RIGHT, LEFT]:
        var fibula = fibula_dimensions(h, MALE, side)
        fibula.lateral_bow = Length(0.1, METER)
        var b = FibulaField(fibula)
        _contains(b.low, b.high, b.s2)


def test_gluteal_ap_extent_is_not_clipped() raises:
    var field = MuscleField(
        muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE)), GLUTEUS_MEDIUS
    )
    for ix in range(11):
        for iy in range(11):
            var x = (
                field.low.x + (field.high.x - field.low.x) * Float32(ix) / 10
            )
            var y = (
                field.low.y + (field.high.y - field.low.y) * Float32(iy) / 10
            )
            assert_true(field.distance(Vector3(x, y, field.low.z)) >= 0)
            assert_true(field.distance(Vector3(x, y, field.high.z)) >= 0)


def test_patellar_facets_affect_the_solid() raises:
    var field = PatellaField(patella_dimensions(Length(6.0, FOOT), MALE))
    var moved = Vector3(0.1, 0, 0)
    assert_true(field.distance(moved) > 0)
    field.lateral = moved
    assert_true(field.distance(moved) < 0)
    field.medial = moved * -1
    assert_true(field.distance(moved * -1) < 0)


def test_muscle_dimensions_reject_non_finite_scalars() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    for bad in [nan[DType.float32](), inf[DType.float32]()]:
        var leg = muscle_dimensions(person)
        leg.scale = bad
        with assert_raises():
            leg.validate()
        leg.scale = 1
        leg.k = bad
        with assert_raises():
            leg.validate()
        leg.k = 0.01
        leg.epsilon = bad
        with assert_raises():
            leg.validate()
        var foot = foot_muscle_dimensions(person)
        foot.scale = bad
        with assert_raises():
            foot.validate()
        foot = foot_muscle_dimensions(person)
        foot.k = bad
        with assert_raises(contains="blend radius"):
            foot.validate()
        foot = foot_muscle_dimensions(person)
        foot.epsilon = bad
        with assert_raises(contains="gradient step"):
            foot.validate()
        var pelvis = pelvis_muscle_dimensions(person)
        pelvis.scale = bad
        with assert_raises():
            pelvis.validate()
        pelvis = pelvis_muscle_dimensions(person)
        pelvis.k = bad
        with assert_raises(contains="blend radius"):
            pelvis.validate()
        pelvis = pelvis_muscle_dimensions(person)
        pelvis.epsilon = bad
        with assert_raises(contains="gradient step"):
            pelvis.validate()
        var torso = torso_muscle_dimensions(person)
        torso.scale = bad
        with assert_raises():
            torso.validate()
    var leg = muscle_dimensions(person)
    leg.bellies[2] = -1
    with assert_raises():
        leg.validate()
    leg.bellies[2] = 0
    leg.bellies[0] = nan[DType.float32]()
    with assert_raises():
        leg.validate()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
