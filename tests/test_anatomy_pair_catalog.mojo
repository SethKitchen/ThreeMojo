# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Canonical pair placement, catalog completeness and batch preflight."""

from extensions.humanoid.skeleton.leg.tibia.dimensions import TibiaField
from extensions.humanoid.skeleton.leg.fibula.dimensions import FibulaField
from extensions.humanoid.skeleton.leg.patella.dimensions import PatellaField
from extensions.humanoid.skeleton.leg.knee.dimensions import CartilageField
from extensions.humanoid.skeleton.leg.knee.dimensions import MeniscusField
from extensions.humanoid.skeleton.leg.knee.dimensions import CollateralField
from extensions.humanoid.skeleton.leg.muscles.dimensions import MuscleField
from extensions.humanoid.skeleton.foot.muscles.dimensions import FootMuscleField
from extensions.humanoid.skeleton.foot.ligaments.dimensions import (
    FootLigamentField,
)
from extensions.humanoid.skeleton.leg.vessels.dimensions import VesselField
from extensions.humanoid.skeleton.foot.vessels.dimensions import FootVesselField
from extensions.humanoid.skeleton.leg.nerves.dimensions import NerveField
from extensions.humanoid.skeleton.foot.nerves.dimensions import FootNerveField
from extensions.humanoid.skeleton.leg.lymph.dimensions import LymphField
from extensions.humanoid.skeleton.foot.lymph.dimensions import FootLymphField
from tools.anatomy_pairs import _components, _Component, _batch, _work
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import RIGHT, LEFT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.leg.femur.dimensions import FemurField
from extensions.humanoid.skeleton.foot.bones.dimensions import FootBoneField
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    foot_muscle_dimensions,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_true,
    assert_raises,
)
from units.si import Length


def test_catalog_is_complete_canonical_and_in_one_frame() raises:
    var spec = HumanoidSpec(Length(1.8288), MALE)
    for side in [RIGHT, LEFT]:
        var parts = _components(spec, side)
        assert_equal(len(parts), 134)
        var pose = assemble_leg(spec, side)
        var families: List[String] = [
            "bone",
            "knee",
            "muscle",
            "ligament",
            "vascular",
            "nerve",
            "lymphatic",
        ]
        var expected: List[Int] = [30, 5, 49, 10, 19, 13, 8]
        for f in range(len(families)):
            var count = 0
            for i in range(len(parts)):
                if parts[i].family == families[f]:
                    count += 1
            assert_equal(count, expected[f])
        for i in range(len(parts)):
            for j in range(i + 1, len(parts)):
                assert_true(parts[i].identity != parts[j].identity)
            if parts[i].identity.startswith("foot/"):
                assert_almost_equal(parts[i].origin.x, pose.ankle_center().x)
                assert_almost_equal(parts[i].origin.y, pose.ankle_center().y)
                assert_almost_equal(parts[i].origin.z, pose.ankle_center().z)
            elif parts[i].family != "bone":
                assert_almost_equal(parts[i].origin.length(), 0)
            # Every Variant dispatch arm is exercised at an asymmetric point.
            var point = (parts[i].low + parts[i].high) * 0.5
            var local = point - parts[i].origin
            var placed = parts[i].distance(point)
            if parts[i].solid.isa[FemurField]():
                assert_almost_equal(
                    placed, parts[i].solid[FemurField].distance(local)
                )
            if parts[i].solid.isa[TibiaField]():
                assert_almost_equal(
                    placed, parts[i].solid[TibiaField].distance(local)
                )
            if parts[i].solid.isa[FibulaField]():
                assert_almost_equal(
                    placed, parts[i].solid[FibulaField].distance(local)
                )
            if parts[i].solid.isa[PatellaField]():
                assert_almost_equal(
                    placed, parts[i].solid[PatellaField].distance(local)
                )
            if parts[i].solid.isa[CartilageField]():
                assert_almost_equal(
                    placed, parts[i].solid[CartilageField].distance(local)
                )
            if parts[i].solid.isa[MeniscusField]():
                assert_almost_equal(
                    placed, parts[i].solid[MeniscusField].distance(local)
                )
            if parts[i].solid.isa[CollateralField]():
                assert_almost_equal(
                    placed, parts[i].solid[CollateralField].distance(local)
                )
            if parts[i].solid.isa[FootBoneField]():
                assert_almost_equal(
                    placed, parts[i].solid[FootBoneField].distance(local)
                )
            if parts[i].solid.isa[MuscleField]():
                assert_almost_equal(
                    placed, parts[i].solid[MuscleField].distance(local)
                )
            if parts[i].solid.isa[FootMuscleField]():
                assert_almost_equal(
                    placed, parts[i].solid[FootMuscleField].distance(local)
                )
            if parts[i].solid.isa[FootLigamentField]():
                assert_almost_equal(
                    placed, parts[i].solid[FootLigamentField].distance(local)
                )
            if parts[i].solid.isa[VesselField]():
                assert_almost_equal(
                    placed, parts[i].solid[VesselField].distance(local)
                )
            if parts[i].solid.isa[FootVesselField]():
                assert_almost_equal(
                    placed, parts[i].solid[FootVesselField].distance(local)
                )
            if parts[i].solid.isa[NerveField]():
                assert_almost_equal(
                    placed, parts[i].solid[NerveField].distance(local)
                )
            if parts[i].solid.isa[FootNerveField]():
                assert_almost_equal(
                    placed, parts[i].solid[FootNerveField].distance(local)
                )
            if parts[i].solid.isa[LymphField]():
                assert_almost_equal(
                    placed, parts[i].solid[LymphField].distance(local)
                )
            if parts[i].solid.isa[FootLymphField]():
                assert_almost_equal(
                    placed, parts[i].solid[FootLymphField].distance(local)
                )


def test_batch_rejects_indices_and_aggregate_work_before_sampling() raises:
    var spec = HumanoidSpec(Length(1.8288), MALE)
    var parts = _components(spec, RIGHT)
    for request in [
        "0",
        "0:1",
        "-1:0:1",
        "0:0:1",
        "0:1:1",
        "0:1:135",
        "134:135:136",
    ]:
        with assert_raises():
            _batch(parts, request, Length(0.02))
    # Every single pair is below two million cells, but the full batch
    # exceeds it. Invalid sampled field values cannot mask that budget.
    for i in range(4):
        parts[i].low = Vector3(0, 0, 0)
        parts[i].high = Vector3(0.2, 0.2, 0.2)
    assert_true(_work(parts[0], parts[1], Length(0.002)) <= 2_000_000)
    with assert_raises(contains="batch exceeds"):
        _batch(parts, "0:1:4", Length(0.002))
    with assert_raises():
        _batch(parts, "0:1:2", Length(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
