# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Every species of the animals extension: each morph, sex and age is
drawn, sculpted and warped, and its painter colors points all over it.

This suite holds the registry, the bear, the boar, the cat and the
cheetah. The other species are in `test_animal_species_*`, which import
`_species` from here, so that the coverage run measures them side by side."""

from extensions.animals.build import Animal, _unwarp, create_animal
from extensions.animals.coat import CoatSample
from extensions.sdf.ids import BoneId
from extensions.animals.options import (
    ADULT,
    AnimalOptions,
    ANY_AGE,
    ANY_SEX,
    CROWD,
    FEMALE,
    JUVENILE,
    MALE,
    Variant,
    animal_options,
    body_random,
)
from extensions.animals.coat import Palette
from extensions.animals.rig import Bone
from extensions.animals.species.bear import _arc_for, _pick
from extensions.animals.species.boar import _tusk_paint
from extensions.animals.traits import Traits
from extensions.animals.species.hoofed import hoofed_bones
from extensions.animals.species.swimmer_rig import (
    Profile,
    fan_rays,
    offset_poly,
    swimmer_bones,
)
from extensions.animals.registry import (
    COW,
    FISH,
    SPECIES_COUNT,
    SpeciesId,
    species_name,
    species_of,
    species_eye,
    species_look,
    species_paint,
    species_palette,
    species_traits,
    species_variants,
)
from extensions.sdf.vector import (
    V3,
    dot,
    length,
    normalize,
)
from std.collections import Dict
from std.math import floor
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


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
    # A wooled sheep has a thousand locks: a spread of about 400 solids
    # covers every region as well as all of them.
    ref m = animal.model
    var stride = max(1, len(m.prims) // 400)
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


def _paint_dense(animal: Animal) raises:
    # Paint every solid all round, as `mesh_animal` paints: toward the 26
    # neighbors of a cube cell, inside it, on its surface and just outside,
    # with the normal facing out, in reference space. Small marks such as
    # a band's gap need the spread.
    ref m = animal.model
    for i in range(len(m.prims)):
        ref p = m.prims[i]
        if p.carve:
            continue
        var reach = max(p.r.x, max(p.r.y, p.r.z))
        for dx in range(-1, 2):
            for dy in range(-1, 2):
                for dz in range(-1, 2):
                    if dx == 0 and dy == 0 and dz == 0:
                        continue
                    var d = normalize(V3(Float64(dx), Float64(dy), Float64(dz)))
                    for f in [0.5, 1.0, 1.25]:
                        var q = p.c + d * (reach * f)
                        var dq = q - p.c
                        var s = CoatSample(
                            _unwarp(animal.traits, q),
                            d,
                            V3(dot(dq, p.ax), dot(dq, p.ay), dot(dq, p.az)),
                            p.tag.value,
                            p.bone.value,
                            p.part,
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


def _check(animal: Animal) raises:
    assert_true(len(animal.model.prims) > 10)
    assert_true(animal.cell > 0.0)
    assert_true(animal.traits.get("size") > 0.0)
    # Every primitive rides a bone the rig has.
    for p in animal.model.prims:
        assert_true(p.bone.value < len(animal.rig.bones))
    _ = animal.rig.bone("head")


def _features(t: Traits) -> List[String]:
    # What sets an individual apart for its sculpt and painter: each flag
    # or category among its traits, and each trait drawn near zero, all
    # qualified by its morph, sex and age.
    var base = String(t.variant) + "|" + String(t.sex.value) + "|"
    base += String(t.age.value) + "|"
    var out: List[String] = [base]
    for i in range(len(t.names)):
        var v = t.values[i]
        if v == floor(v) and abs(v) < 20.0:
            out.append(base + t.names[i] + "=" + String(Int(v)))
        elif v < 0.02:
            out.append(base + t.names[i] + "<0.02")
        elif v < 0.05:
            out.append(base + t.names[i] + "<0.05")
    return out^


def _novel(id: SpeciesId, seeds: Int, cap: Int) raises -> List[AnimalOptions]:
    # Draw the traits of every option over many seeds, which is cheap and
    # reaches the rare draws, with their palettes and eyes. Keep the
    # options of each individual that shows a feature none before it did,
    # to build and paint.
    var morphs = len(species_variants(id))
    var seen = Dict[String, Bool]()
    var out = List[AnimalOptions]()
    for seed in range(1, seeds + 1):
        for v in range(-1, morphs):
            for sex in [ANY_SEX, MALE, FEMALE]:
                for age in [ANY_AGE, ADULT, JUVENILE]:
                    var options = animal_options(
                        seed,
                        quality=CROWD,
                        sex=sex,
                        age=age,
                        variant=Variant(v),
                    )
                    var r = body_random(seed)
                    var t = species_traits(id, r, options)
                    assert_true(t.get("size") > 0.0)
                    _ = species_palette(id, t)
                    _ = species_look(id, t)
                    _ = species_eye(id, t)
                    var new = False
                    for f in _features(t):
                        if not (f in seen):
                            seen[f] = True
                            new = True
                    if new and len(out) < cap:
                        out.append(options)
    # A morph the species does not have is refused.
    var r = body_random(1)
    var refused = False
    try:
        _ = species_traits(id, r, animal_options(1, variant=Variant(morphs)))
    except:
        refused = True
    assert_true(refused, species_name(id) + " drew a morph it does not have")
    return out^


def _species(
    name: String,
    cap: Int = 160,
    first: Int = 0,
    last: Int = -1,
    extras: Bool = True,
) raises:
    # Both sexes of the first morph, one sex of each other morph, a young
    # one, three seeds, and each individual unlike the others among many:
    # enough to reach every branch of the species. A slow species can
    # spread the morphs `first` to `last` and the `extras` over tests.
    var id = species_of(name)
    for options in _novel(id, 300, cap):
        var a = create_animal(id, options)
        _check(a)
        _paint_all(a)
    var morphs = len(species_variants(id))
    var stop = morphs if last < 0 else last + 1
    for v in range(first, stop):
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
    if not extras:
        return
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


def test_shared_rigs_take_any_count() raises:
    # The shared skeletons build what they are asked: a cow with no tail,
    # a fish of one trunk bone, no caudal bones and no jaws.
    var cow = create_animal(COW, animal_options(1, quality=CROWD)).rig.copy()
    cow.bones = List[Bone]()
    hoofed_bones(cow, 0)
    _ = cow.bone("hhoofL")
    with assert_raises(contains="no bone"):
        _ = cow.bone("tail0")
    var fish = create_animal(FISH, animal_options(1, quality=CROWD)).rig.copy()
    fish.bones = List[Bone]()
    swimmer_bones(fish, 1, 0, "spine0", "spine0", jaw=False, upper_jaw=False)
    for name in ["jaw", "upperJaw", "caudal0"]:
        with assert_raises(contains="no bone"):
            _ = fish.bone(name)
    # Empty tables give empty fans and outlines.
    assert_true(len(fan_rays(0, 0, 1, 0, 0.0, 1.0, List[Float64]())) == 0)
    assert_true(len(offset_poly(List[Float64](), 0.1)) == 0)
    assert_true(Profile(List[Float64]()).max_of(1) == 0.0)


def test_helpers_take_their_edge_cases() raises:
    # A draw past the shares is the last entry; no shares pick none.
    var shares: List[Float64] = [0.5, 0.3]
    assert_equal(_pick(shares, 0.95), 1)
    assert_equal(_pick(List[Float64](), 0.5), -1)
    # A claw whose root pitch already drops it far enough keeps that pitch.
    assert_true(_arc_for(0.05, -1.0, 0.3) == 0.3)
    # A boar with no tusks paints a point with no tusk to measure.
    var paint = _tusk_paint(Palette(), Traits(MALE, ADULT, 0), V3(0, 0, 0))
    assert_true(paint.surface.is_valid())


def test_bear() raises:
    _species("bear")


def test_boar() raises:
    _species("boar")


def test_cat() raises:
    _species("cat")


def test_cheetah() raises:
    _species("cheetah")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
