# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for garments, the wardrobe, and how plate follows the bones."""

from core.buffer_geometry import BufferGeometry
from extensions.attire.cover import cover_of
from extensions.attire.garment import (
    MAX_LAMES,
    NO_ANCHOR,
    Garment,
    belt,
    boots,
    breeches,
    cuirass,
    fauld,
    gauntlets,
    gorget,
    gown,
    greaves,
    hood,
    jerkin,
    robe,
    sabatons,
    surcoat,
    wardrobe,
)
from extensions.attire.kinds import (
    ARMOR_LAYER,
    COWLED,
    FITTED,
    FLEXIBLE,
    LAMED,
    PARTY,
    PLATE,
    RIGID,
    SHOD,
    SKIRTED,
    TORSO_SLOT,
    Articulation,
    DyePattern,
    FabricKind,
    Form,
    Layer,
    Slot,
)
from extensions.attire.plates import (
    anchor_weights,
    articulate,
    lames,
    ride_covered,
    share_with,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HIPS,
    JOINT_COUNT,
    RIGHT_SHIN,
    SPINE,
    Joint,
)
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from render.framebuffer import Color
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import empty_mesh, strip
from units.si import Length, METER


def _plate(
    articulation: Articulation, anchor: Joint, count: Int
) raises -> Garment:
    """Return a plate on the chest, spine and hips."""
    return Garment(
        "plate",
        TORSO_SLOT,
        ARMOR_LAYER,
        PLATE,
        cover_of([CHEST, SPINE]),
        Color(200, 200, 200),
        articulation=articulation,
        anchor=anchor,
        lames=count,
    )


def _shared(
    joint_a: Joint, a: Float32, joint_b: Joint, b: Float32
) raises -> BufferGeometry:
    """Return a strip whose every vertex is shared by two joints."""
    var mesh = strip(0, 4, joint_a)
    var bones = mesh.clone_attribute(String(SKIN_INDEX))
    var weights = mesh.clone_attribute(String(SKIN_WEIGHT))
    for v in range(bones.count()):
        bones.set_component(v, 0, Float32(joint_a.value))
        bones.set_component(v, 1, Float32(joint_b.value))
        weights.set_component(v, 0, a)
        weights.set_component(v, 1, b)
    mesh.set_attribute(String(SKIN_INDEX), bones^)
    mesh.set_attribute(String(SKIN_WEIGHT), weights^)
    return mesh^


def test_the_wardrobe_checks() raises:
    var all = wardrobe()
    assert_equal(len(all), 24)
    for garment in all:
        garment.check()
        assert_true(garment.name != "")
    assert_equal(surcoat().pattern, PARTY)
    assert_true(surcoat().dyes[0] != surcoat().dyes[1])
    assert_equal(cuirass().anchor, CHEST)
    assert_equal(fauld().articulation, LAMED)
    assert_equal(greaves().anchor, NO_ANCHOR)
    assert_true(hood().cover.face_open)
    assert_true(hood().ease.value > 0)
    assert_true(boots().drape > 0)
    assert_equal(boots().form, SHOD)
    assert_equal(surcoat().form, SKIRTED)
    assert_true(surcoat().flare > 0)
    # The long garments fall to the ankles; a gown spreads wider than a
    # robe.
    assert_equal(gown().form, SKIRTED)
    assert_true(gown().flare > robe().flare)
    assert_true(gown().cover.covers(RIGHT_SHIN))
    assert_equal(jerkin().form, SKIRTED)
    assert_equal(sabatons().form, SHOD)
    assert_equal(sabatons().articulation, RIGID)
    assert_equal(gorget().anchor, CHEST)
    assert_equal(gauntlets().articulation, RIGID)
    assert_true(breeches().ease.value > 0)
    assert_equal(belt().form, FITTED)
    assert_equal(hood().form, COWLED)


def test_a_garment_refuses_what_cannot_be_made() raises:
    var good = _plate(FLEXIBLE, NO_ANCHOR, 0)
    good.check()
    var bad = good.copy()
    bad.slot = Slot(99)
    with assert_raises(contains="named slot"):
        bad.check()
    bad = good.copy()
    bad.layer = Layer(-1)
    with assert_raises(contains="named layer"):
        bad.check()
    bad = good.copy()
    bad.fabric = FabricKind(99)
    with assert_raises(contains="named kind"):
        bad.check()
    bad = good.copy()
    bad.articulation = Articulation(9)
    with assert_raises(contains="named one"):
        bad.check()
    bad = good.copy()
    bad.pattern = DyePattern(9)
    with assert_raises(contains="named pattern"):
        bad.check()
    bad = good.copy()
    bad.anchor = Joint(JOINT_COUNT)
    with assert_raises(contains="named joint"):
        bad.check()
    with assert_raises(contains="need an anchor"):
        _plate(LAMED, NO_ANCHOR, 3).check()
    with assert_raises(contains="two through twelve"):
        _plate(LAMED, HIPS, 1).check()
    with assert_raises(contains="two through twelve"):
        _plate(LAMED, HIPS, MAX_LAMES + 1).check()
    _plate(LAMED, HIPS, MAX_LAMES).check()
    bad = good.copy()
    _ = bad.dyes.pop()
    with assert_raises(contains="four dyes"):
        bad.check()
    bad = good.copy()
    bad.drape = -2
    with assert_raises(contains="A drape"):
        bad.check()
    bad = good.copy()
    bad.ease = Length(-0.1, METER)
    with assert_raises(contains="An ease"):
        bad.check()
    bad.ease = Length(2, METER)
    with assert_raises(contains="An ease"):
        bad.check()
    bad.ease = Length(nan[DType.float32](), METER)
    with assert_raises(contains="An ease"):
        bad.check()
    bad = good.copy()
    bad.form = Form(5)
    with assert_raises(contains="form must"):
        bad.check()
    bad = good.copy()
    bad.flare = -0.1
    with assert_raises(contains="A flare"):
        bad.check()
    bad.flare = 1.5
    with assert_raises(contains="A flare"):
        bad.check()
    bad.flare = nan[DType.float32]()
    with assert_raises(contains="A flare"):
        bad.check()


def test_a_rigid_plate_rides_one_bone() raises:
    var mesh = _shared(HIPS, 0.6, CHEST, 0.4)
    assert_almost_equal(anchor_weights(mesh, CHEST)[0], 0.4)
    assert_equal(anchor_weights(mesh, SPINE)[0], 0)
    var anchored = articulate(mesh.clone(), _plate(RIGID, CHEST, 0))
    ref bones = anchored.attribute_view(String(SKIN_INDEX))
    ref weights = anchored.attribute_view(String(SKIN_WEIGHT))
    assert_equal(Int(bones.component(3, 0)), CHEST.value)
    assert_equal(weights.component(3, 0), 1)
    # Without an anchor, a vertex rides the heaviest bone the plate
    # covers, even when a bone it does not cover weighs more.
    var riding = articulate(mesh.clone(), _plate(RIGID, NO_ANCHOR, 0))
    assert_equal(
        Int(riding.attribute_view(String(SKIN_INDEX)).component(0, 0)),
        CHEST.value,
    )
    # Of two covered bones, the heavier.
    var both = _shared(CHEST, 0.6, SPINE, 0.4)
    ride_covered(both, _plate(RIGID, NO_ANCHOR, 0))
    assert_equal(
        Int(both.attribute_view(String(SKIN_INDEX)).component(0, 0)),
        CHEST.value,
    )
    var lighter = _shared(SPINE, 0.3, CHEST, 0.7)
    ride_covered(lighter, _plate(RIGID, NO_ANCHOR, 0))
    assert_equal(
        Int(lighter.attribute_view(String(SKIN_INDEX)).component(0, 0)),
        CHEST.value,
    )
    # No covered bone: the heaviest.
    var bare = _shared(HIPS, 0.3, HIPS, 0.7)
    ride_covered(bare, _plate(RIGID, NO_ANCHOR, 0))
    assert_equal(
        Int(bare.attribute_view(String(SKIN_INDEX)).component(0, 0)),
        HIPS.value,
    )
    # A flexible garment keeps its weights.
    var kept = articulate(mesh.clone(), _plate(FLEXIBLE, NO_ANCHOR, 0))
    assert_almost_equal(
        kept.attribute_view(String(SKIN_WEIGHT)).component(0, 0), 0.6
    )
    var refused = _plate(RIGID, NO_ANCHOR, 0)
    refused.layer = Layer(77)
    with assert_raises(contains="named layer"):
        _ = articulate(mesh.clone(), refused)


def test_lames_step_from_the_anchor() raises:
    var mesh = _shared(CHEST, 1, SPINE, 0)
    # Share none: the anchor holds wholly. Share all: the old weights.
    var none = mesh.clone()
    share_with(none, HIPS, 0)
    assert_equal(
        Int(none.attribute_view(String(SKIN_INDEX)).component(0, 0)),
        HIPS.value,
    )
    var all = mesh.clone()
    share_with(all, HIPS, 1)
    assert_equal(
        Int(all.attribute_view(String(SKIN_INDEX)).component(0, 0)),
        CHEST.value,
    )
    # The anchor's weight falls down the strip, so the lames step down it.
    var falling = strip(0, 4, CHEST)
    var bones = falling.clone_attribute(String(SKIN_INDEX))
    var weights = falling.clone_attribute(String(SKIN_WEIGHT))
    for v in range(10):
        var on_hips = 1 - Float32(v // 2) / 4
        bones.set_component(v, 0, Float32(HIPS.value))
        bones.set_component(v, 1, Float32(CHEST.value))
        weights.set_component(v, 0, on_hips)
        weights.set_component(v, 1, 1 - on_hips)
    falling.set_attribute(String(SKIN_INDEX), bones^)
    falling.set_attribute(String(SKIN_WEIGHT), weights^)
    var bands = lames(falling, HIPS, 3)
    # Each lame is a separate piece: more vertices than the strip had.
    assert_true(bands.vertex_count() > 10)
    assert_true(bands.triangle_count() >= 8)
    var lamed = articulate(falling.clone(), _plate(LAMED, HIPS, 3))
    assert_equal(lamed.vertex_count(), bands.vertex_count())
    with assert_raises(contains="two or more"):
        _ = lames(falling, HIPS, 1)


def test_an_empty_garment_rides_and_bands_as_nothing() raises:
    var empty = empty_mesh()
    assert_equal(len(anchor_weights(empty, HIPS)), 0)
    ride_covered(empty, greaves())
    share_with(empty, HIPS, 0.5)
    assert_equal(empty.vertex_count(), 0)
    var banded = lames(empty, HIPS, 3)
    assert_equal(banded.vertex_count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
