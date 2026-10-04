# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Every species of the animals extension: each morph, sex and age is
drawn, sculpted and warped, and its painter colors points all over it."""

from extensions.animals.build import Animal, create_animal
from extensions.animals.coat import CoatSample
from extensions.sdf.ids import BoneId
from extensions.animals.options import (
    ADULT,
    CROWD,
    FEMALE,
    JUVENILE,
    MALE,
    Variant,
    animal_options,
)
from extensions.animals.registry import (
    SPECIES_COUNT,
    SpeciesId,
    species_name,
    species_of,
    species_paint,
    species_variants,
)
from extensions.sdf.vector import (
    V3,
    length,
)
from std.testing import TestSuite, assert_true


def _directions() -> List[V3]:
    return [
        V3(1, 0, 0),
        V3(-1, 0, 0),
        V3(0, 1, 0),
        V3(0, -1, 0),
        V3(0, 0, 1),
        V3(0, 0, -1),
    ]


def _paint_all(animal: Animal) raises:
    # Paint points around every solid: at its center, and pushed out along
    # each direction to its surface, with the normal facing that way.
    # A wooled sheep has a thousand locks: a spread of about 80 solids
    # covers every region as well as all of them.
    ref m = animal.model
    var stride = max(1, len(m.prims) // 80)
    for i in range(0, len(m.prims), stride):
        ref p = m.prims[i]
        if p.carve:
            continue
        var reach = max(p.r.x, max(p.r.y, p.r.z))
        for d in _directions():
            var q = p.c + d * reach
            var s = CoatSample(
                q, d, d * reach, p.tag.value, p.bone.value, p.part
            )
            var paint = species_paint(
                animal.species,
                animal.palette,
                animal.traits,
                m.tags[p.tag.value],
                animal.rig.bones[p.bone.value].name,
                s,
            )
            assert_true(paint.surface.is_valid())
            assert_true(paint.color.x >= 0.0 and paint.color.x < 4.0)


def _check(animal: Animal) raises:
    assert_true(len(animal.model.prims) > 10)
    assert_true(animal.cell > 0.0)
    assert_true(animal.traits.get("size") > 0.0)
    # Every primitive rides a bone the rig has.
    for p in animal.model.prims:
        assert_true(p.bone.value < len(animal.rig.bones))
    _ = animal.rig.bone("head")


def _species(name: String) raises:
    # Both sexes of the first morph, one sex of each other morph, a young
    # one, and three seeds: enough to reach every branch of the species.
    var id = species_of(name)
    var morphs = len(species_variants(id))
    for v in range(morphs):
        for sex in [MALE, FEMALE]:
            var first = v == 0
            if not first and (sex == MALE) == (v % 2 == 0):
                continue
            var adult = create_animal(
                id,
                animal_options(
                    5 + v,
                    quality=CROWD,
                    sex=sex,
                    age=ADULT,
                    variant=Variant(v),
                ),
            )
            _check(adult)
            _paint_all(adult)
    var young = create_animal(
        id, animal_options(9, quality=CROWD, age=JUVENILE, variant=Variant(0))
    )
    _check(young)
    _paint_all(young)
    var sizes = List[Float64]()
    for seed in range(1, 4):
        var a = create_animal(id, animal_options(seed, quality=CROWD))
        sizes.append(a.traits.get("size"))
    var differ = sizes[1] != sizes[0] or sizes[2] != sizes[0]
    assert_true(differ, name + " draws one size for every seed")


def test_registry_lists_every_species() raises:
    assert_true(SPECIES_COUNT == 24)
    for i in range(SPECIES_COUNT):
        assert_true(species_name(SpeciesId(i)).byte_length() > 0)


def test_bear() raises:
    _species("bear")


def test_boar() raises:
    _species("boar")


def test_cat() raises:
    _species("cat")


def test_cheetah() raises:
    _species("cheetah")


def test_chicken() raises:
    _species("chicken")


def test_cow() raises:
    _species("cow")


def test_crow() raises:
    _species("crow")


def test_deer() raises:
    _species("deer")


def test_dog() raises:
    _species("dog")


def test_eagle() raises:
    _species("eagle")


def test_fish() raises:
    _species("fish")


def test_fox() raises:
    _species("fox")


def test_frog() raises:
    _species("frog")


def test_goat() raises:
    _species("goat")


def test_horse() raises:
    _species("horse")


def test_lion() raises:
    _species("lion")


def test_pig() raises:
    _species("pig")


def test_rabbit() raises:
    _species("rabbit")


def test_rat() raises:
    _species("rat")


def test_shark() raises:
    _species("shark")


def test_sheep() raises:
    _species("sheep")


def test_snake() raises:
    _species("snake")


def test_spider() raises:
    _species("spider")


def test_wolf() raises:
    _species("wolf")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
