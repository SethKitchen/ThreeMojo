# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Trunk muscles of swimmers and snakes, a spider's flexors, muscle
paths over pulleys, and the static loads of a standing quadruped."""

from extensions.animals.anatomy.axial import (
    FLEXOR_SHARE,
    axial_muscles,
    hemolymph_pressure,
)
from extensions.animals.anatomy.body import (
    ARACHNID,
    MAMMAL,
    SERPENT,
    SHARK_PLAN,
    TELEOST,
    BodyPlan,
    species_body,
)
from extensions.animals.anatomy.engineering import (
    calibrate,
    calibrated_animal,
    calibrated_mass,
)
from extensions.animals.anatomy.mass import sample_mass
from extensions.animals.anatomy.muscles import (
    AnimalMuscle,
    animal_muscles,
    descends,
    spans_of,
)
from extensions.animals.anatomy.stance import standing_loads
from extensions.animals.build import Animal, create_animal
from extensions.animals.options import (
    ADULT,
    CROWD,
    MALE,
    Variant,
    animal_options,
)
from extensions.animals.registry import DOG, RAT, SpeciesId, species_of
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import METER, STANDARD_GRAVITY, Length


def _real(id: SpeciesId) raises -> Animal:
    var body = species_body(id)
    var cal = calibrate(id, Variant(-1), allow_estimates=True)
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


def test_swimmers_and_snakes_bend_with_trunk_muscles() raises:
    for pair in [
        ("fish", 0.60),
        ("shark", 0.53),
        ("snake", 0.30),
    ]:
        var a = create_animal(
            species_of(pair[0]), animal_options(4, quality=CROWD)
        )
        var plan = species_body(a.species).plan
        var step = species_body(a.species).reference_length.scaled(0.05)
        var mass = sample_mass(a, a.bind_pose(), step)
        var muscles = axial_muscles(a.rig, plan, mass)
        assert_true(len(muscles) >= 4)
        var world = a.bind_pose().world(a.rig)
        for m in muscles:
            var child = m.bones[1]
            assert_almost_equal(
                Float64(m.arch.mass.value),
                0.5 * pair[1] * mass.bones[child].mass,
                rtol=1e-5,
            )
            # Each side bends the body toward itself.
            assert_true(m.moment_arms(a.rig, world)[0].value > 0.0)
    var fish = create_animal(species_of("fish"), animal_options(4))
    var fish_mass = sample_mass(fish, fish.bind_pose(), Length(0.03, METER))
    with assert_raises(contains="plan"):
        _ = axial_muscles(fish.rig, BodyPlan(11), fish_mass)
    assert_equal(len(axial_muscles(fish.rig, MAMMAL, fish_mass)), 0)
    # A segment with no flesh has no muscle.
    var before = len(axial_muscles(fish.rig, TELEOST, fish_mass))
    var spine = fish.rig.bone("spine3").value
    fish_mass.bones[spine].mass = 0.0
    assert_equal(len(axial_muscles(fish.rig, TELEOST, fish_mass)), before - 2)
    var rat = create_animal(RAT, animal_options(4, quality=CROWD))
    with assert_raises(contains="another rig"):
        _ = axial_muscles(rat.rig, TELEOST, fish_mass)


def test_spider_legs_flex_and_extend_by_pressure() raises:
    var spider = create_animal(
        species_of("spider"), animal_options(4, quality=CROWD)
    )
    var mass = sample_mass(spider, spider.bind_pose(), Length(0.002, METER))
    var flexors = axial_muscles(spider.rig, ARACHNID, mass)
    assert_equal(len(flexors), 16)
    var world = spider.bind_pose().world(spider.rig)
    var body = Float64(mass.total().mass.value)
    for m in flexors:
        assert_true(m.moment_arms(spider.rig, world)[0].value > 0.0)
        assert_almost_equal(
            Float64(m.arch.mass.value), FLEXOR_SHARE * body, rtol=1e-4
        )
        assert_almost_equal(Float64(m.arch.specific_tension.value), 0.5e6)
    assert_almost_equal(Float64(hemolymph_pressure(True).value), 65000.0)
    assert_almost_equal(Float64(hemolymph_pressure(False).value), 6500.0)


def test_paths_wrap_behind_joints() raises:
    var dog = _real(DOG)
    var muscles = animal_muscles(dog.rig, MAMMAL, species_body(DOG).male_mass)
    var world = dog.bind_pose().world(dog.rig)
    for m in muscles:
        if m.name != "superficial digital flexor":
            continue
        assert_equal(len(m.points), 4)
        # The wrist and the fetlock each use the stretch that spans it.
        assert_equal(m.spans[1], 2)
        assert_equal(m.spans[2], 3)
        var arms = m.moment_arms(dog.rig, world)
        # It flexes the wrist and the fetlock: it holds them up.
        assert_true(arms[1].value > 0.0 and arms[2].value > 0.0)
    var femur = dog.rig.bone("femurL").value
    var tibia = dog.rig.bone("tibiaL").value
    var pelvis = dog.rig.bone("pelvis").value
    assert_true(descends(dog.rig, tibia, femur))
    assert_false(descends(dog.rig, femur, tibia))
    with assert_raises(contains="above"):
        _ = spans_of(dog.rig, [tibia, tibia], [femur])
    with assert_raises(contains="beyond"):
        _ = spans_of(dog.rig, [pelvis, femur], [tibia])


def test_standing_loads_balance_the_weight() raises:
    var id = DOG
    var cal = calibrate(id, Variant(-1), allow_estimates=True)
    var base = create_animal(
        id, animal_options(1, quality=CROWD, sex=MALE, age=ADULT)
    )
    var dog = calibrated_animal(base, cal)
    var mass = calibrated_mass(base, cal, 30.0)
    var total = mass.total()
    var muscles = animal_muscles(dog.rig, MAMMAL, total.mass)
    var loads = standing_loads(dog, mass, muscles)
    assert_equal(len(loads), 8)
    # Two fore and two hind feet carry the weight.
    var weight = Float64(total.mass.value) * Float64(STANDARD_GRAVITY.value)
    var carried = 2.0 * Float64(
        loads[0].reaction.value + loads[4].reaction.value
    )
    assert_almost_equal(carried, weight, rtol=1e-5)
    for l in loads:
        assert_true(l.ground_lever.value >= 0.0)
        if l.held:
            assert_true(l.activation > 0.0 and l.activation <= 1.0)
            assert_almost_equal(
                l.advantage,
                Float64(l.muscle_lever.value / l.ground_lever.value),
                rtol=1e-5,
            )
    # A crouching rat stands on its hind feet alone.
    var rat_cal = calibrate(RAT, Variant(-1), allow_estimates=True)
    var rat0 = create_animal(
        RAT, animal_options(1, quality=CROWD, sex=MALE, age=ADULT)
    )
    var rat = calibrated_animal(rat0, rat_cal)
    var rat_mass = calibrated_mass(rat0, rat_cal, 30.0)
    var rat_loads = standing_loads(
        rat, rat_mass, animal_muscles(rat.rig, MAMMAL, rat_mass.total().mass)
    )
    assert_equal(rat_loads[0].reaction.value, 0.0)
    # Zero fore-foot reaction does not remove the hanging limb's weight.
    assert_true(abs(rat_loads[0].moment.value) > 0.0)
    # Without muscles, only a joint with zero required moment is held.
    for l in standing_loads(rat, rat_mass, List[AnimalMuscle]()):
        assert_equal(l.held, l.moment.value == 0.0)
    # A body whose weight hangs ahead of or behind its feet falls.
    for shift in [10.0, -10.0]:
        var tipped = rat_mass.bones.copy()
        for i in range(len(tipped)):
            # Translate the whole distribution, including second moments.
            # Moving only its first moment is not a realizable mass tensor.
            tipped[i].second[2] += (
                2.0 * shift * tipped[i].first[2]
                + shift * shift * tipped[i].mass
            )
            tipped[i].second[4] += shift * tipped[i].first[0]
            tipped[i].second[5] += shift * tipped[i].first[1]
            tipped[i].first[2] += shift * tipped[i].mass
        var keep = rat_mass.bones.copy()
        rat_mass.bones = tipped^
        with assert_raises(contains="not over the feet"):
            _ = standing_loads(rat, rat_mass, List[AnimalMuscle]())
        rat_mass.bones = keep^
    var fish = create_animal(species_of("fish"), animal_options(1))
    var fish_mass = sample_mass(fish, fish.bind_pose(), Length(0.03, METER))
    with assert_raises(contains="quadruped"):
        _ = standing_loads(fish, fish_mass, muscles)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
