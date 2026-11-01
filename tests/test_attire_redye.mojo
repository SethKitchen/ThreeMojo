# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for painting a dressed outfit in new dyes."""

from core.assets import Assets
from core.buffer_geometry import COLOR
from core.scene import Scene
from extensions.attire.apparel import fur_mantle
from extensions.attire.cover import Cover
from extensions.attire.garment import Garment, hose, shirt
from extensions.attire.kinds import (
    LINEN,
    OVER_LAYER,
    TORSO_SLOT,
    BROCADE,
    PRIMARY_DYE,
    SECONDARY_DYE,
    TRIM_DYE,
)
from extensions.attire.outfit import Outfit, dress
from extensions.attire.redye import redye
from extensions.attire.tailor import doublet
from render.framebuffer import Color
from render.texture_store import NO_TEXTURE
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._attire_people import coarse_person


def _outfit(green: Bool) raises -> Outfit:
    """Return a shirt, hose, a brocade doublet and a fur mantle, in one of
    two sets of dyes."""
    var outfit = Outfit()
    outfit.add(shirt())
    outfit.add(hose())
    var coat = doublet()
    coat.design = BROCADE
    var mantle = fur_mantle()
    if green:
        coat.dyes[PRIMARY_DYE.value] = Color(20, 90, 40)
        coat.dyes[TRIM_DYE.value] = Color(220, 200, 120)
        coat.dyes[SECONDARY_DYE.value] = Color(230, 226, 214)
        mantle.dyes[PRIMARY_DYE.value] = Color(220, 220, 215)
    outfit.add(coat^)
    outfit.add(mantle^)
    return outfit^


def test_a_redyed_outfit_matches_one_dressed_in_its_dyes() raises:
    var scene = Scene()
    var assets = Assets()
    var first = coarse_person(scene, assets)
    var second = coarse_person(scene, assets)
    var redyed = dress(scene, assets, first, _outfit(False))
    var fresh = dress(scene, assets, second, _outfit(True))
    redye(scene, assets, redyed, _outfit(True))
    for g in range(len(fresh.parts)):
        assert_equal(len(redyed.parts[g]), len(fresh.parts[g]))
        for k in range(len(fresh.parts[g])):
            ref a = scene.skinned_meshes[redyed.parts[g][k]]
            ref b = scene.skinned_meshes[fresh.parts[g][k]]
            ref painted = assets.geometries.get(a.geometry).attribute_view(
                String(COLOR)
            )
            ref wanted = assets.geometries.get(b.geometry).attribute_view(
                String(COLOR)
            )
            assert_equal(painted.count(), wanted.count())
            for v in range(painted.count()):
                for c in range(3):
                    assert_almost_equal(
                        painted.component(v, c),
                        wanted.component(v, c),
                        atol=1e-5,
                    )
            var look = assets.materials.get(a.material)
            var want = assets.materials.get(b.material)
            assert_true(look.sheen_color == want.sheen_color)
            # A design's texture is drawn in the new dyes.
            if want.map != NO_TEXTURE:
                ref drawn = assets.textures.get(look.map)
                ref made = assets.textures.get(want.map)
                assert_equal(drawn.width, made.width)
                for i in range(0, len(made.pixels), 97):
                    assert_equal(drawn.pixels[i], made.pixels[i])
    # The fur mantle stood in shells, and they were painted again too.
    assert_true(len(redyed.parts[3]) > 1)


def test_only_the_garments_dressed_can_be_redyed() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var dressed = dress(scene, assets, person, _outfit(False))
    var fewer = Outfit()
    fewer.add(shirt())
    with assert_raises(contains="garments it was dressed in"):
        redye(scene, assets, dressed, fewer)
    # A garment that draws nothing has no part to paint.
    var other = coarse_person(scene, assets)
    var hidden = Outfit()
    hidden.add(shirt())
    hidden.add(
        Garment(
            "nothing", TORSO_SLOT, OVER_LAYER, LINEN, Cover(), Color(9, 9, 9)
        )
    )
    var bare = dress(scene, assets, other, hidden)
    assert_equal(len(bare.parts[1]), 0)
    redye(scene, assets, bare, hidden)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
