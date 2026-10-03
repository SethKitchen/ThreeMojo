# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The animals' limb muscles and gait timing: each muscle's action, its
architecture in SI units, and the stride dynamic similarity gives."""

from extensions.anatomy.locomotion import (
    TROT_FROUDE,
    WALK_FROUDE,
    froude,
    speed_at,
    stride_frequency,
    stride_length,
)
from extensions.animals.anatomy.body import (
    ANURAN,
    BIRD,
    MAMMAL,
    SERPENT,
    TELEOST,
    BodyPlan,
)
from extensions.animals.anatomy.muscles import (
    BICEPS_FEMORIS_SHARE,
    AnimalMuscle,
    animal_muscles,
    plan_muscles,
)
from extensions.animals.build import create_animal
from extensions.animals.gait import walk_pose
from extensions.animals.options import ADULT, CROWD, MALE, animal_options
from extensions.animals.registry import RAT, WOLF, species_of
from extensions.animals.rig import Rig
from extensions.sdf.vector import V3
from std.math import pow, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    KILOGRAM,
    METER,
    METER_PER_SECOND,
    STANDARD_GRAVITY,
    Length,
    Mass,
    Velocity,
)


def test_froude_scaling() raises:
    var hip = Length(1.2, METER)
    var u = speed_at(WALK_FROUDE, hip)
    assert_almost_equal(
        Float64(u.value), sqrt(0.25 * Float64(STANDARD_GRAVITY.value) * 1.2)
    )
    assert_almost_equal(froude(u, hip), 0.25, rtol=1e-6)
    assert_almost_equal(
        Float64(stride_length(1.0, hip).value), 2.3 * 1.2, rtol=1e-6
    )
    var f = stride_frequency(TROT_FROUDE, hip)
    var expect = Float64(speed_at(TROT_FROUDE, hip).value) / (
        2.3 * pow(0.5, 0.3) * 1.2
    )
    assert_almost_equal(Float64(f.value), expect, rtol=1e-5)
    # A small animal takes more strides a second at the same Froude number.
    assert_true(stride_frequency(0.25, Length(0.07, METER)) > f)
    for bad in [0.0, -1.0, 1e40 * 1e300]:
        with assert_raises(contains="hip"):
            _ = froude(Velocity(1, METER_PER_SECOND), Length(Float32(bad)))
    var inf = 1e300 * 1e300
    for fr in [-0.1, inf]:
        with assert_raises(contains="Froude"):
            _ = speed_at(fr, hip)
    for fr in [0.0, inf]:
        with assert_raises(contains="Froude"):
            _ = stride_length(fr, hip)


def test_walk_takes_the_dynamically_similar_stride() raises:
    var wolf = create_animal(WOLF, animal_options(3))
    var slow = walk_pose(wolf.rig, 0.1, 0.1)
    var fast = walk_pose(wolf.rig, 0.1, 0.4)
    assert_equal(len(slow.local), len(fast.local))
    with assert_raises(contains="Froude"):
        _ = walk_pose(wolf.rig, 0.1, 0.0)


def test_plans_have_their_muscles() raises:
    assert_equal(len(plan_muscles(MAMMAL)), 10)
    assert_equal(len(plan_muscles(BIRD)), 2)
    assert_equal(len(plan_muscles(ANURAN)), 3)
    assert_equal(len(plan_muscles(TELEOST)), 0)
    assert_equal(len(plan_muscles(SERPENT)), 0)
    with assert_raises(contains="plan"):
        _ = plan_muscles(BodyPlan(8))
    for spec in plan_muscles(MAMMAL):
        assert_true(spec.share > 0.0 and spec.share < 0.05)
        assert_true(spec.share_source.evidence.is_valid())
        assert_true(spec.fiber_ratio > 0.0 and spec.fiber_ratio < 1.0)


def _find(
    muscles: List[AnimalMuscle], name: String, side: String
) raises -> Int:
    for i in range(len(muscles)):
        if muscles[i].name == name and muscles[i].side == side:
            return i
    raise Error("no muscle " + name)


def test_mammal_muscles_act_as_they_should() raises:
    var rat = create_animal(
        RAT, animal_options(2, quality=CROWD, sex=MALE, age=ADULT)
    )
    var body = Mass(0.3, KILOGRAM)
    var muscles = animal_muscles(rat.rig, MAMMAL, body)
    assert_equal(len(muscles), 20)
    var world = rat.bind_pose().world(rat.rig)
    # Hip extensor and knee flexor; knee extensor; hock extensor and
    # flexor; elbow extensor. Positive turns a distal bone backward.
    var expect: List[Tuple[String, Int, Bool]] = [
        ("biceps femoris", 0, True),
        ("biceps femoris", 1, True),
        ("rectus femoris", 1, False),
        ("vastus lateralis", 0, False),
        ("gastrocnemius", 1, True),
        ("tibialis anterior", 0, False),
        ("triceps brachii", 1, True),
    ]
    for side in ["L", "R"]:
        for e in expect:
            var m = muscles[_find(muscles, e[0], side)].copy()
            var arm = m.moment_arms(rat.rig, world)[e[1]]
            assert_true((arm.value > 0.0) == e[2], e[0] + " " + side)
    var bf = muscles[_find(muscles, "biceps femoris", "L")].copy()
    assert_almost_equal(
        Float64(bf.arch.mass.value), 0.3 * BICEPS_FEMORIS_SHARE, rtol=1e-6
    )
    # The fibers are optimal standing: the unit is fibers plus tendon.
    assert_almost_equal(
        Float64(bf.unit_length(world).value),
        Float64(bf.arch.fiber_length.value + bf.arch.tendon_slack.value),
        rtol=1e-5,
    )
    var right = muscles[_find(muscles, "biceps femoris", "R")].copy()
    assert_almost_equal(
        Float64(right.unit_length(world).value),
        Float64(bf.unit_length(world).value),
        rtol=1e-5,
    )
    with assert_raises(contains="mass"):
        _ = animal_muscles(rat.rig, MAMMAL, Mass(0))
    var fish = create_animal(species_of("fish"), animal_options(2))
    with assert_raises():
        _ = animal_muscles(fish.rig, MAMMAL, body)
    # A fish's muscles are axial, not in the limb tables.
    assert_equal(len(animal_muscles(fish.rig, TELEOST, body)), 0)


def test_bird_wing_muscles_beat_the_wing() raises:
    var crow = create_animal(
        species_of("crow"), animal_options(2, quality=CROWD)
    )
    var muscles = animal_muscles(crow.rig, BIRD, Mass(0.45, KILOGRAM))
    var world = crow.bind_pose().world(crow.rig)
    for side in ["L", "R"]:
        var down = muscles[_find(muscles, "pectoralis", side)].copy()
        var up = muscles[_find(muscles, "supracoracoideus", side)].copy()
        var a = down.moment_arms(crow.rig, world)[0]
        var b = up.moment_arms(crow.rig, world)[0]
        assert_true(a.value * b.value < 0.0)
        # The tendon's turn over its pulley lengthens the path.
        var p = up.path(world)
        assert_true(up.unit_length(world).value > Float32(0.0))
        assert_true(p[1].y > p[0].y)


def _frog_rig(fold: Bool, turned: Bool) raises -> Rig:
    var rig = Rig()
    rig.set("lumbosacral", V3(0, 1, 0))
    rig.set("tailBase", V3(0, 1, -0.5))
    for side in ["L", "R"]:
        var x = 0.2 if side == "L" else -0.2
        var hip = V3(x, 1, 0)
        rig.set("hip" + side, hip)
        rig.set("root" + side, hip)
        var knee = hip + (V3(0, 0, -1) if fold else V3(0, -0.5, 0.3))
        rig.set("knee" + side, knee)
        var hock = knee + (V3(0, 0, 5) if fold else V3(0, -0.4, -0.3))
        rig.set("hock" + side, hock)
        rig.set("mtp" + side, hock + V3(0, -0.1, 0.2))
    _ = rig.add_bone("pelvis", "lumbosacral", "tailBase", "")
    for side in ["L", "R"]:
        var s = String(side)
        var head = String("hip") if turned else String("root")
        _ = rig.add_bone("femur" + s, head + s, "knee" + s, "pelvis")
        _ = rig.add_bone("tibia" + s, "knee" + s, "hock" + s, "femur" + s)
        _ = rig.add_bone("metatarsus" + s, "hock" + s, "mtp" + s, "tibia" + s)
    return rig^


def test_frog_muscles_and_bad_rigs() raises:
    var mass = Mass(0.3, KILOGRAM)
    var ok = animal_muscles(_frog_rig(False, True), ANURAN, mass)
    assert_equal(len(ok), 6)
    # A leg folded back on itself leaves a muscle no room for its fibers.
    with assert_raises(contains="shorter than its fibers"):
        _ = animal_muscles(_frog_rig(True, True), ANURAN, mass)
    # A hip that no bone turns at.
    with assert_raises(contains="No bone turns"):
        _ = animal_muscles(_frog_rig(False, False), ANURAN, mass)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
