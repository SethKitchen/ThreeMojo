# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Feature-off traits, caller-supplied painter inputs and empty helper inputs.

Traits and the registry's sculpt and paint functions are public. Values
drawn by a species are defaults, not validation of later caller changes.
These checks build reference sculpts and sample painters without meshing.
"""

from extensions.animals.coat import CoatSample, Palette
from extensions.animals.options import (
    ADULT,
    CROWD,
    FEMALE,
    JUVENILE,
    MALE,
    Age,
    Sex,
    Variant,
    animal_options,
    body_random,
)
from extensions.animals.parts import BODY, EAR, LIMB
from extensions.animals.registry import (
    COW,
    CROW,
    DEER,
    FROG,
    GOAT,
    PIG,
    SHEEP,
    SNAKE,
    SpeciesId,
    species_rig,
    species_sculpt,
    species_traits,
)
from extensions.animals.species.bird_rig import (
    Feather,
    FeatherFrame,
    feather_fins,
    rectrix,
)
from extensions.animals.species.cat import _dist_line
from extensions.animals.species.chicken import _inside
from extensions.animals.species.deer import _catmull
from extensions.animals.species.fish import GOLDFISH, fish_paint
from extensions.animals.species.frog import HEAD_O, frog_paint
from extensions.animals.species.goat import ALPINE, M_EARS, _hl, _mark_sd
from extensions.animals.species.shark import _scaled, _trail_dist
from extensions.animals.species.snake import RATTLESNAKE, _segments
from extensions.animals.traits import Traits
from extensions.sdf.field import SdfModel
from extensions.sdf.ids import CONE, ELLIPSOID, BoneId
from extensions.sdf.sculpt import cone_or_ball
from extensions.sdf.vector import V3, length
from std.testing import TestSuite, assert_equal, assert_true


def _draw(
    species: SpeciesId,
    sex: Sex = FEMALE,
    age: Age = ADULT,
    variant: Int = 0,
) raises -> Traits:
    var options = animal_options(
        1, quality=CROWD, sex=sex, age=age, variant=Variant(variant)
    )
    var r = body_random(options.seed)
    return species_traits(species, r, options)


def _sculpt(species: SpeciesId, t: Traits) raises -> SdfModel:
    var rig = species_rig(species, t)
    var m = SdfModel()
    species_sculpt(species, m, rig, t)
    return m^


def _count(m: SdfModel, tag: String) -> Int:
    var count = 0
    for p in m.prims:
        if m.tags[p.tag.value] == tag:
            count += 1
    return count


def test_a_caller_can_disable_the_cows_dewlap() raises:
    var t = _draw(COW)
    for dewlap in [-0.01, 0.0, 0.02, 0.03]:
        t.set("dewlap", dewlap)
        var m = _sculpt(COW, t)
        assert_equal(_count(m, "dewlap"), 1 if dewlap > 0.02 else 0)


def test_a_calf_remains_a_calf_after_adjusting_bull_traits() raises:
    var t = _draw(COW, MALE, JUVENILE)
    t.set("bull", 1.0)
    var m = _sculpt(COW, t)
    assert_true(_count(m, "sheath") > 0)
    assert_equal(_count(m, "scrotum"), 0)


def test_a_does_udder_can_be_disabled() raises:
    var t = _draw(GOAT)
    for udder in [0.0, 0.05, 0.2]:
        t.set("udder", udder)
        var m = _sculpt(GOAT, t)
        assert_true((_count(m, "udder") > 0) == (udder > 0.05))
        assert_true((_count(m, "teat") > 0) == (udder > 0.05))


def test_a_bucks_mane_can_be_disabled() raises:
    var t = _draw(GOAT, MALE)
    for mane in [0.0, 0.05, 0.4]:
        t.set("mane", mane)
        var m = _sculpt(GOAT, t)
        assert_true((_count(m, "mane") > 0) == (mane > 0.05))


def test_an_ewes_udder_can_be_disabled() raises:
    var t = _draw(SHEEP)
    t.set("wool", 0.0)
    for udder in [0.0, 0.05, 0.2]:
        t.set("udder", udder)
        var m = _sculpt(SHEEP, t)
        assert_true((_count(m, "udder") > 0) == (udder > 0.05))
        assert_true((_count(m, "teat") > 0) == (udder > 0.05))


def test_erect_ear_markings_do_not_leak_onto_custom_lop_ears() raises:
    var t = Traits(FEMALE, ADULT, ALPINE)
    t.set("lop", 1.0)
    t.set("earLift", 0.0)
    var pal = Palette()
    pal.set("patches", V3(0, 0, 0))
    var p = _hl(V3(0.2, -0.015, -0.02))
    var h = V3(0.2, -0.015, -0.02)
    var n = V3(1, 0, 0)
    var plain = _mark_sd(pal, t, 0, 5, "ear", "earL", 0.0, h, p, n)
    var lop = _mark_sd(pal, t, M_EARS, 5, "ear", "earL", 0.0, h, p, n)
    assert_true(abs(plain - lop) < 1e-12)
    t.set("lop", 0.0)
    var erect = _mark_sd(pal, t, M_EARS, 5, "ear", "earL", 0.0, h, p, n)
    assert_true(erect < plain)


def test_unknown_frog_limb_suffixes_skip_bands_safely() raises:
    var t = _draw(FROG)
    var first = Palette()
    var second = Palette()
    first.set("band", V3(0.1, 0.2, 0.3))
    second.set("band", V3(0.8, 0.6, 0.4))
    for bone in [String("humerusX"), "radiusQ", "femur", "tibiaZ"]:
        var s = CoatSample(
            V3(0.02, 0.03, 0.02), V3(0, 1, 0), V3(0, 0, 0), 0, 0, LIMB
        )
        var a = frog_paint(first, t, "leg", bone, s)
        var b = frog_paint(second, t, "leg", bone, s)
        assert_true(length(a.color - b.color) < 1e-12)
        assert_true(a.surface.is_valid())
    # The same band palette still affects an actual limb of the rig.
    var band_seen = False
    for i in range(24):
        var s = CoatSample(
            V3(0.02, 0.02 + 0.001 * Float64(i), 0.02),
            V3(0, 1, 0),
            V3(0, 0, 0),
            0,
            0,
            LIMB,
        )
        var a = frog_paint(first, t, "leg", "humerusL", s)
        var b = frog_paint(second, t, "leg", "humerusL", s)
        band_seen = band_seen or length(a.color - b.color) > 1e-8
    assert_true(band_seen)


def test_frog_neck_bones_keep_the_head_paint_region() raises:
    var t = _draw(FROG)
    var rig = species_rig(FROG, t)
    var pal = Palette()
    pal.set("belly", V3(0.1, 0.2, 0.3))
    pal.set("throatF", V3(0.8, 0.1, 0.05))
    var s = CoatSample(
        HEAD_O + V3(0, -0.04, -0.04),
        V3(0, -1, 0),
        V3(0, 0, 0),
        0,
        0,
        BODY,
    )
    var head = frog_paint(pal, t, "skin", "head", s)
    for bone in [String("neck1"), "neck2"]:
        _ = rig.bone(bone)
        var neck = frog_paint(pal, t, "skin", bone, s)
        assert_true(length(neck.color - head.color) < 1e-12)


def test_goldfish_patch_palette_only_changes_patch_regions() raises:
    var t = Traits(FEMALE, ADULT, GOLDFISH)
    t.set("morph", 2.0)
    var first = Palette()
    var second = Palette()
    first.set("spot", V3(0.05, 0.1, 0.15))
    second.set("spot", V3(0.8, 0.6, 0.4))
    var patch_seen = False
    for i in range(9):
        for j in range(9):
            var s = CoatSample(
                V3(0.01, 0.01 * Float64(i), -0.04 + 0.01 * Float64(j)),
                V3(1, 0, 0),
                V3(0, 0, 0),
                0,
                0,
                BODY,
            )
            for tag in [String("adipose"), "earflap"]:
                var a = fish_paint(first, t, tag, "spine0", s)
                var b = fish_paint(second, t, tag, "spine0", s)
                assert_true(length(a.color - b.color) < 1e-12)
            var a = fish_paint(first, t, "body", "spine0", s)
            var b = fish_paint(second, t, "body", "spine0", s)
            patch_seen = patch_seen or length(a.color - b.color) > 1e-8
    assert_true(patch_seen)


def test_zero_feature_counts_are_reachable_traits() raises:
    var pig = _draw(PIG)
    pig.set("teats", 0.0)
    var pm = _sculpt(PIG, pig)
    assert_equal(_count(pm, "teat"), 0)
    var snake = _draw(SNAKE, FEMALE, ADULT, RATTLESNAKE)
    snake.set("rattleSegs", 0.0)
    var sm = _sculpt(SNAKE, snake)
    assert_equal(_count(sm, "rattle"), 0)
    assert_true(_count(sm, "button") > 0)
    var deer = _draw(DEER, MALE)
    deer.set("antlers", 1.0)
    deer.set("spike", 0.0)
    deer.set("tines", 0.0)
    var dm = _sculpt(DEER, deer)
    assert_true(_count(dm, "beam") > 0)
    assert_equal(_count(dm, "tine"), 0)


def test_empty_helpers_keep_their_existing_empty_results() raises:
    # Characterize callable empty/degenerate inputs. These are no-op helper
    # behaviors, not a promise that the inputs describe valid animal geometry.
    var floats = List[Float64]()
    var points = List[V3]()
    assert_true(not _inside(floats, 0.0, 0.0))
    assert_true(_dist_line(V3(0, 0, 0), V3(0, 1, 0), points, floats) > 1e8)
    assert_equal(len(_scaled(floats, 1.0, 1.0)), 0)
    assert_true(_trail_dist(floats, 0.0, 0.0) > 1e8)
    # Supplied outlines may list the lower tip before the upper tip.
    var reversed_tips: List[Float64] = [0.0, -1.0, 1.0, 1.0]
    assert_true(_trail_dist(reversed_tips, 0.0, 0.0) > 1e8)
    assert_equal(len(_segments(0, 1.0, 0.5)), 0)
    assert_equal(len(_catmull(points, -1)), 0)


def test_a_negative_feather_arc_can_leave_no_pieces() raises:
    # Characterize the existing empty path for a caller-supplied arc, without
    # asserting that a negative arc is a supported biological shape.
    var t = _draw(CROW)
    var rig = species_rig(CROW, t)
    var feathers: List[Feather] = [
        rectrix(0, 1, 0.0, 0.1, 0.02, 0.0, 0.0, arc=-30.0)
    ]
    var frames: List[FeatherFrame] = [
        FeatherFrame(V3(0, 0, 0), V3(1, 0, 0), V3(0, 1, 0))
    ]
    var m = SdfModel()
    feather_fins(m, rig, feathers, frames, 0.002, 0.001, tail_fins=False)
    assert_equal(len(m.prims), 0)


def test_cone_or_ball_preserves_part_for_both_shapes() raises:
    var m = SdfModel()
    var bone = BoneId(0)
    _ = cone_or_ball(
        m,
        "ear",
        bone,
        V3(0, 0, 0),
        V3(0, 0, 1),
        0.2,
        0.1,
        0.0,
        thin=True,
        part=EAR,
    )
    _ = cone_or_ball(
        m,
        "ear",
        bone,
        V3(0, 0, 0),
        V3(0, 0, 0.1),
        0.1,
        0.5,
        0.0,
        thin=True,
        part=EAR,
    )
    assert_equal(m.prims[0].kind, CONE)
    assert_equal(m.prims[1].kind, ELLIPSOID)
    for p in m.prims:
        assert_true(p.part == EAR)
        assert_true(p.thin)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
