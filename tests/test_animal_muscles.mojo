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
    species_body,
)
from extensions.animals.anatomy.engineering import calibrate, calibrated_animal
from extensions.animals.anatomy.muscles import (
    BICEPS_FEMORIS_SHARE,
    AnimalMuscle,
    MuscleSpec,
    animal_muscles,
    plan_muscles,
    species_muscles,
    species_specs,
    species_table,
)
from extensions.animals.build import Animal, create_animal
from extensions.animals.gait import walk_pose
from extensions.animals.options import (
    ADULT,
    CROWD,
    MALE,
    Variant,
    animal_options,
)
from extensions.animals.registry import (
    CAT,
    CHEETAH,
    CHICKEN,
    DOG,
    FISH,
    HORSE,
    RAT,
    SPECIES_COUNT,
    WOLF,
    SpeciesId,
    species_of,
)
from extensions.animals.rig import Rig
from extensions.sdf.vector import V3
from std.math import cos, max, pow, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    DEGREE,
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
    # The fibers are optimal standing: the unit is the fibers' reach
    # along it plus the tendon.
    assert_almost_equal(Float64(bf.arch.pennation.to(DEGREE)), 3.6, rtol=1e-5)
    assert_almost_equal(
        Float64(bf.unit_length(world).value),
        Float64(bf.arch.fiber_length.value)
        * cos(Float64(bf.arch.pennation.value))
        + Float64(bf.arch.tendon_slack.value),
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


def _spec(specs: List[MuscleSpec], name: String) raises -> MuscleSpec:
    for s in specs:
        if s.name == name:
            return s.copy()
    raise Error("no muscle " + name)


def test_species_tables_replace_the_plan() raises:
    # Every row names a muscle of its species' plan, from a source read.
    var rows = 0
    for i in range(SPECIES_COUNT):
        var id = SpeciesId(i)
        var plan = plan_muscles(species_body(id).plan)
        for row in species_table(id):
            _ = _spec(plan, row.name)
            assert_true(row.source.evidence.is_measured())
            assert_true(row.mass_kg > 0.0 and row.source_kg > 0.0)
            rows += 1
    assert_equal(rows, 34)
    with assert_raises(contains="species"):
        _ = species_table(SpeciesId(SPECIES_COUNT))
    var dog = species_specs(DOG)
    var bf = _spec(dog, "biceps femoris")
    assert_almost_equal(bf.share, 0.485 / 31.8)
    assert_almost_equal(bf.source_kg, 31.8)
    # A fiber length scales with the cube root of mass.
    assert_almost_equal(bf.fiber_length(1.0, 8.0 * 31.8), 0.286)
    # The greyhound's soleus row has no pennation: the plan's stays.
    assert_almost_equal(_spec(dog, "soleus").pennation_degrees, 3.9)
    # The fore limb has no row: its fiber is a share of the bone.
    var fore = _spec(dog, "biceps brachii")
    assert_equal(fore.source_kg, 0.0)
    assert_almost_equal(fore.fiber_length(0.2, 30.0), fore.fiber_ratio * 0.2)
    # A bird's row changes the mass only.
    var hen = _spec(species_specs(CHICKEN), "pectoralis")
    assert_almost_equal(hen.share, 10.6 * 8.78 / 12.28 / 200.0)
    assert_almost_equal(hen.fiber_ratio, 0.8)
    assert_equal(hen.source_kg, 0.0)
    # A species without a table keeps its plan's muscles.
    var cat = species_specs(CAT)
    var mammal = plan_muscles(MAMMAL)
    assert_equal(len(cat), len(mammal))
    for k in range(len(cat)):
        assert_almost_equal(cat[k].share, mammal[k].share)
    assert_equal(len(species_specs(FISH)), 0)


def _real(id: SpeciesId) raises -> Animal:
    var cal = calibrate(id, Variant(-1))
    var body = species_body(id)
    var a = create_animal(
        id,
        animal_options(
            1,
            quality=CROWD,
            sex=MALE,
            age=ADULT,
            variant=Variant(max(body.variant, 0)),
        ),
    )
    return calibrated_animal(a, cal)


def _fits(id: SpeciesId) raises:
    var a = _real(id)
    var body = species_body(id)
    var muscles = species_muscles(a.rig, id, body.male_mass)
    assert_equal(len(muscles), 20)
    var specs = species_specs(id)
    var bf = muscles[_find(muscles, "biceps femoris", "L")].copy()
    assert_almost_equal(
        Float64(bf.arch.mass.value),
        _spec(specs, "biceps femoris").share * Float64(body.male_mass.value),
        rtol=1e-5,
    )
    for m in muscles:
        assert_true(m.arch.tendon_slack.value > 0.0, m.name)
        m.arch.check()


def test_horse_and_cheetah_muscles_fit_their_skeletons() raises:
    _fits(HORSE)
    _fits(CHEETAH)


def test_dog_and_rat_muscles_fit_their_skeletons() raises:
    _fits(DOG)
    _fits(RAT)
    var rat = create_animal(RAT, animal_options(2, quality=CROWD))
    with assert_raises(contains="species"):
        _ = species_muscles(rat.rig, SpeciesId(-1), Mass(0.3, KILOGRAM))


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
