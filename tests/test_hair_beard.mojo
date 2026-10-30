# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for facial hair: beards and mustaches as solids on the face."""

from core.buffer_geometry import POSITION
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.hair.beard import (
    BEARD_COUNT,
    CHIN_STRAP,
    CLEAN_SHAVEN,
    FULL_BEARD,
    GOATEE,
    MOUTH_Y,
    MOUTH_Z,
    MUSTACHE,
    MUTTON_CHOPS,
    NOSE_BASE_Y,
    SHORT_BEARD,
    SIDEBURN_Y,
    Beard,
    BeardShape,
    beard_bottom,
    beard_label,
    beard_mesh,
    beard_named,
    beard_top,
    require_beard,
)
from extensions.humanoid.skeleton.head.skin.dimensions import HeadSkinField
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, FOOT, Angle, Length


def test_beards_are_named() raises:
    for k in range(BEARD_COUNT):
        var beard = Beard(k)
        assert_true(beard.is_valid())
        assert_equal(beard_named(beard_label(beard)), beard)
    assert_equal(beard_label(FULL_BEARD), "full beard")
    assert_equal(beard_label(Beard(9)), "beard")
    assert_false(Beard(-1).is_valid())
    assert_false(Beard(BEARD_COUNT).is_valid())
    require_beard(CLEAN_SHAVEN)
    with assert_raises(contains="named style"):
        require_beard(Beard(9))
    with assert_raises(contains="No beard"):
        _ = beard_named("sideburns")


def test_a_beard_line_runs_from_the_mouth_to_the_sideburn() raises:
    # Under the nose at the front, down to the corners of the mouth, up
    # across the cheek to the sideburn.
    assert_almost_equal(beard_top(Angle(0.0, DEGREE)), NOSE_BASE_Y)
    assert_almost_equal(beard_top(Angle(-10.0, DEGREE)), NOSE_BASE_Y)
    assert_almost_equal(beard_top(Angle(24.0, DEGREE)), 64.4)
    assert_true(
        beard_top(Angle(19.0, DEGREE)) < NOSE_BASE_Y
        and beard_top(Angle(19.0, DEGREE)) > 64.4
    )
    assert_almost_equal(beard_top(Angle(80.0, DEGREE)), SIDEBURN_Y)
    assert_almost_equal(beard_top(Angle(90.0, DEGREE)), SIDEBURN_Y)
    # Above the larynx at the front, under the jaw, up to the ear's lobe.
    assert_almost_equal(beard_bottom(Angle(0.0, DEGREE)), 57.2)
    assert_almost_equal(beard_bottom(Angle(-50.0, DEGREE)), 58.0)
    assert_true(beard_bottom(Angle(80.0, DEGREE)) > 58.0)


def test_each_style_grows_where_it_should() raises:
    var dims = head_muscle_dimensions(HumanoidSpec(Length(6, FOOT), MALE))
    var skin = HeadSkinField(dims)
    var mustache = BeardShape(dims, MUSTACHE, skin)
    # The mouth's own point maps to the template's.
    var mouth = mustache.template(mustache.mouth)
    assert_almost_equal(mouth.y, MOUTH_Y, atol=1e-4)
    assert_almost_equal(mouth.z, MOUTH_Z, atol=1e-4)
    var upper_lip = Vector3(0, 66.2, 10.7)
    var chin = Vector3(0, 61.9, 9.9)
    var cheek = Vector3(5.0, 63.0, 6.0)
    var brow = Vector3(5.0, 69.5, 6.0)
    var behind = Vector3(5.0, 63.0, -9.0)
    var lips = Vector3(0, MOUTH_Y, 10.4)
    assert_true(mustache.zone(upper_lip) < 0)
    assert_true(mustache.zone(chin) > 0)
    assert_true(mustache.zone(lips) > 0)
    var goatee = BeardShape(dims, GOATEE, skin)
    assert_true(goatee.zone(upper_lip) < 0)
    assert_true(goatee.zone(chin) < 0)
    assert_true(goatee.zone(cheek) > 0)
    assert_true(goatee.zone(lips) > 0)
    var short = BeardShape(dims, SHORT_BEARD, skin)
    assert_true(short.zone(cheek) < 0)
    assert_true(short.zone(chin) < 0)
    assert_true(short.zone(brow) > 0)
    assert_true(short.zone(behind) > 0)
    assert_true(short.zone(lips) > 0)
    # A chin strap runs along the jaw, under the chin, and not up the
    # cheek or over the lip.
    var strap = BeardShape(dims, CHIN_STRAP, skin)
    var under_jaw = Vector3(0, 58.5, 8.0)
    assert_true(strap.zone(under_jaw) < 0)
    assert_true(strap.zone(cheek) > 0)
    assert_true(strap.zone(upper_lip) > 0)
    # Mutton chops grow on the cheek but not on the chin or the lip.
    var chops = BeardShape(dims, MUTTON_CHOPS, skin)
    assert_true(chops.zone(cheek) < 0)
    assert_true(chops.zone(chin) > 0)
    assert_true(chops.zone(upper_lip) > 0)
    # A full beard is deeper at the chin than on the cheek; the others
    # are as deep at either.
    var full = BeardShape(dims, FULL_BEARD, skin)
    var inside = Float32(-2)
    assert_true(full.depth(chin, inside) > 1.3 * full.depth(cheek, inside))
    assert_almost_equal(
        short.depth(chin, inside), short.depth(cheek, inside), atol=1e-6
    )
    # It thins toward the zone's edge.
    assert_true(short.depth(cheek, 0) < short.depth(cheek, inside))


def test_a_beard_stands_on_the_skin() raises:
    var dims = head_muscle_dimensions(HumanoidSpec(Length(6, FOOT), MALE))
    var skin = HeadSkinField(dims)
    var h = dims.head.copy()
    var short = BeardShape(dims, SHORT_BEARD, skin)
    # Just off the skin of the chin: inside the beard. Far in front of it,
    # and inside the head: outside.
    var chin = h.at(0, 61.9, 9.95)
    var out = chin + Vector3(0, 0, h.cm(0.15))
    assert_true(short.distance(out) < 0)
    assert_true(short.distance(h.at(0, 61.9, 14.0)) > 0)
    assert_true(short.distance(h.at(0, 61.9, 4.0)) > 0)
    # A full beard hangs a mass below the chin, in front of the neck.
    var full = BeardShape(dims, FULL_BEARD, skin)
    var under = h.at(0, 57.0, 8.5)
    assert_true(full.distance(under) < 0)
    assert_true(short.distance(under) > 0)
    # A clean-shaven face grows nothing.
    var bare = BeardShape(dims, CLEAN_SHAVEN, skin)
    assert_true(bare.distance(out) > 0)
    with assert_raises(contains="named style"):
        _ = BeardShape(dims, Beard(9), skin)


def test_a_mustache_is_meshed() raises:
    var dims = head_muscle_dimensions(HumanoidSpec(Length(6, FOOT), MALE))
    assert_true(beard_mesh(dims, MUSTACHE, 16).triangle_count() > 0)


def test_a_full_beard_is_meshed_without_its_inner_face() raises:
    var dims = head_muscle_dimensions(HumanoidSpec(Length(6, FOOT), MALE))
    var skin = HeadSkinField(dims)
    var mesh = beard_mesh(dims, FULL_BEARD, 16)
    assert_true(mesh.triangle_count() > 0)
    # No triangle lies wholly under the skin.
    ref placed = mesh.attribute_view(String(POSITION))
    var h = dims.head.copy()
    for t in range(mesh.triangle_count()):
        var shown = False
        for c in range(3):
            var p = placed.vector3(mesh.corner_index(t, c))
            if skin.distance(p) >= -h.cm(0.04):
                shown = True
        assert_true(shown)
    with assert_raises(contains="no beard to mesh"):
        _ = beard_mesh(dims, CLEAN_SHAVEN)
    with assert_raises(contains="named style"):
        _ = beard_mesh(dims, Beard(9))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
