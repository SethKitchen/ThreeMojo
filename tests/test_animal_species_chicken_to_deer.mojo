# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Four species of the animals extension, each drawn and painted.

The chicken, cow, crow and deer are drawn in each morph, sex and age. They
share `test_animal_species`'s check, and live in a suite of their own so
that the coverage run measures them beside the others."""

from extensions.animals.build import create_animal
from extensions.animals.coat import Palette
from extensions.animals.options import (
    ADULT,
    CROWD,
    FEMALE,
    JUVENILE,
    MALE,
    animal_options,
)
from extensions.animals.parts import TAIL
from extensions.animals.registry import CROW
from extensions.animals.rig import Bone, Rig
from extensions.animals.species.bird_rig import (
    RECTRIX,
    Feather,
    FeatherFrame,
    WingPose,
    bird_bones,
    card_outline,
    card_point,
    feather_fins,
    feather_frame,
    feather_frames,
    feather_joints,
    neck_chain,
    plume,
    rectrix_frame,
    star_union,
    tail_fan,
    tail_frame,
)
from extensions.animals.species.chicken import _Stack, _flight_color, _tri
from extensions.animals.species.crow import _feathers
from extensions.animals.species.deer import (
    R_BODY,
    _b,
    _fawn_spot,
    _paint_coat,
    deer_palette,
)
from extensions.animals.traits import Traits
from extensions.sdf.field import SdfModel
from extensions.sdf.vector import V3, length
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_raises,
    assert_true,
)
from test_animal_species import _species


def test_bird_rig_takes_its_edge_cases() raises:
    var crow = create_animal(CROW, animal_options(1, quality=CROWD))
    var feathers = _feathers()
    # Untwisted feathers keep their plane.
    var f = feathers[0]
    f.twist = 0.0
    var o = V3(0, 0, 0)
    var fr = feather_frame(o, V3(1, 0, 0), V3(0, 1, 0), 0.1, 1.0, f, 0.0, False)
    assert_almost_equal(length(fr.normal), 1.0, atol=1e-9)
    for g in feathers:
        if g.kind == RECTRIX:
            var r = g
            r.twist = 0.0
            var rf = rectrix_frame(
                o, V3(0, 0, -1), V3(0, 1, 0), V3(1, 0, 0), 1.0, r, 0.0
            )
            assert_almost_equal(length(rf.normal), 1.0, atol=1e-9)
    # One neck segment places no joint; a thousand reach the skull's end
    # of the curve.
    var rig = crow.rig.copy()
    neck_chain(rig, 1, V3(0, 1, 0), V3(0, 0, 1), 0.3)
    neck_chain(rig, 1000, V3(0, 1, 0), V3(0, 0, 1), 0.3)
    _ = rig.j("neck999")
    # A tail that points forward already has its normal up.
    var tail = Rig()
    tail.set("tailBase", V3(0, 0, 0))
    tail.set("tailTip", V3(0, 0, 1))
    assert_true(tail_frame(tail)[1].y > 0.0)
    # No feathers give no frames, no joints, no fins and no fan.
    var pose = WingPose(0.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, 0.0)
    var none = List[Feather]()
    var no_frames = List[FeatherFrame]()
    var lengths = V3(0.05, 0.06, 0.07)
    assert_true(
        len(feather_frames(crow.rig, lengths, pose, pose, pose, none, 0.0)) == 0
    )
    feather_joints(rig, none, no_frames)
    var m = SdfModel()
    feather_fins(m, crow.rig, none, no_frames, 0.002, 0.001)
    tail_fan(m, crow.rig, none, no_frames, 0.002, 0.001, TAIL)
    assert_true(len(m.prims) == 0)
    # Coverts, and rectrices left as ellipsoids, sculpt more cards.
    var frames = List[FeatherFrame]()
    for g in feathers:
        frames.append(
            feather_frame(o, V3(1, 0, 0), V3(0, 1, 0), 0.1, 1.0, g, 0.0, False)
        )
    feather_fins(
        m,
        crow.rig,
        feathers,
        frames,
        0.002,
        0.001,
        coverts=V3(0.4, 0.4, 0.4),
        tail_fins=False,
    )
    assert_true(len(m.prims) > len(feathers))
    var hen = Traits(MALE, ADULT, 0)
    _ = _flight_color(Palette(), hen, "primaryCovert", 1.0, 0.5, 0.0, True)
    # A skeleton needs a neck; a bird without flight feathers has one.
    var bare = crow.rig.copy()
    bare.bones = List[Bone]()
    with assert_raises(contains="no bone"):
        bird_bones(bare, 0, none)
    var plain = crow.rig.copy()
    plain.bones = List[Bone]()
    bird_bones(plain, 4, none)
    _ = plain.bone("head")
    # Outlines and unions of nothing are empty.
    assert_true(len(card_outline(f, 0.1, 0.02, -1)) == 0)
    assert_true(len(star_union(List[List[Float64]](), 0.0, 0.0, 0)) == 0)
    assert_true(len(star_union(List[List[Float64]](), 0.0, 0.0, 4)) == 8)
    var empty: List[List[Float64]] = [List[Float64]()]
    assert_true(len(star_union(empty, 0.0, 0.0, 4)) == 8)
    with assert_raises(contains="feather card"):
        _ = card_point("bogus", o, False)
    # Plumage that flows straight up still finds its feathers.
    _ = plume(V3(0.1, 0.2, 0.3), 0.01, V3(0, 1, 0))


def test_the_wing_stack_skips_what_it_cannot_hold() raises:
    # A point off the grid reads nothing; a flat triangle stacks nothing.
    var st = _Stack()
    assert_true(st.near(-1000.0, -1000.0, 1.2) < -1e29)
    _tri(st, V3(0, 0, 1), V3(0, 0, 1), V3(0, 0, 1))
    assert_true(st.near(0.0, 0.0, 1.0) < -1e29)


def test_chicken() raises:
    _species("chicken")


def test_deer_glands_and_fawn_spots() raises:
    # The metatarsal gland, a pale-rimmed tuft outside the hind cannon.
    var buck = Traits(MALE, ADULT, 0)
    var hk = _b(0.074, 0.33, -0.49)
    var p = V3(hk.x, hk.y - 0.12, hk.z + 0.004)
    var c = _paint_coat(
        deer_palette(buck), buck, R_BODY, "metatarsusL", p, V3(1, 0, 0), 1.0
    )
    assert_true(c.x >= 0.0)
    # A fawn's spots run in rows either side of its spine, with gaps.
    var fawn = Traits(FEMALE, JUVENILE, 0)
    for k in range(-12, 13):
        var spot = _fawn_spot(
            fawn, "spine2", V3(0.01 * Float64(k), 0.7, 0.0), V3(0, 1, 0)
        )
        assert_true(spot >= 0.0 and spot <= 1.0)


def test_cow() raises:
    _species("cow")


def test_crow() raises:
    _species("crow")


def test_deer() raises:
    _species("deer")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
