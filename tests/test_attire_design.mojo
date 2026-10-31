# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for designs woven or embroidered over a garment's dyes."""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from extensions.attire.design import (
    BRAID_TILE,
    CREAM,
    DESIGN_TEXELS,
    GROUND,
    DesignMaps,
    braid_shade,
    braid_texture,
    colored_shade,
    colored_texture,
    contrast,
    design_dyes,
    design_parts,
    design_tile,
    tonal_shade,
    tonal_texture,
    worn_design,
)
from extensions.attire.dye import DYE, with_channel
from extensions.attire.kinds import (
    ACCENT_DYE,
    BROCADE,
    CHECK,
    DAMASK,
    DESIGN_COUNT,
    DIAPER,
    FELT,
    FLORAL,
    FUR,
    HERRINGBONE,
    HIDE,
    LEATHER,
    LINEN,
    MAIL,
    PADDING,
    PINSTRIPE,
    PLAIN,
    PLATE,
    PRIMARY_DYE,
    SCALE,
    SECONDARY_DYE,
    SILK,
    STRAW,
    TARTAN,
    TRIM_DYE,
    VELVET,
    WOOL,
    Design,
    DyeChannel,
    FabricKind,
)
from extensions.attire.mesh_ops import merge
from extensions.humanoid.rig.joints import HIPS
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB
from render.texture_store import NO_TEXTURE
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import tube

comptime CRIMSON = Color(150, 20, 30)
comptime GOLD = Color(214, 170, 64)
comptime GREEN = Color(30, 90, 40)


def _colored() -> List[Design]:
    """Return the designs in colors."""
    return [BROCADE, TARTAN, PINSTRIPE, DIAPER, FLORAL, CHECK]


def _tonal() -> List[Design]:
    """Return the tonal designs."""
    return [DAMASK, HERRINGBONE, HIDE]


def test_each_design_tiles_at_its_own_size() raises:
    for k in range(1, DESIGN_COUNT):
        var tile = design_tile(Design(k))
        assert_true(tile >= 0.04 and tile <= 0.25)
    assert_almost_equal(design_tile(BROCADE), 0.12, atol=1e-6)
    assert_almost_equal(design_tile(HIDE), 0.25, atol=1e-6)
    with assert_raises(contains="plain"):
        _ = design_tile(PLAIN)
    with assert_raises(contains="design must"):
        _ = design_tile(Design(40))


def test_a_tonal_design_shades_its_dye() raises:
    for design in _tonal():
        var low = Float32(1)
        var high = Float32(0)
        for y in range(16):
            for x in range(16):
                var shade = tonal_shade(
                    design, Float32(x) / 16 + 0.01, Float32(y) / 16 + 0.01
                )
                low = min(low, shade)
                high = max(high, shade)
        assert_true(low >= 0 and high <= 1)
        # Each shows: light and dark both lie on it.
        assert_true(high - low > 0.1)
    # Damask's ground is darker than its rosettes.
    assert_true(tonal_shade(DAMASK, 0.5, 0.5) >= GROUND)
    for design in _colored():
        with assert_raises(contains="tonal"):
            _ = tonal_shade(design, 0.5, 0.5)
    var texture = tonal_texture(DAMASK)
    assert_equal(texture.width, DESIGN_TEXELS)
    assert_true(texture.color_space == LINEAR)
    assert_almost_equal(texture.repeat.x, 1 / design_tile(DAMASK), atol=1e-4)


def test_a_design_in_colors_lays_its_dyes() raises:
    for design in _colored():
        var grounds = 0
        var motifs = 0
        for y in range(32):
            for x in range(32):
                var color = colored_shade(
                    design,
                    CRIMSON,
                    GOLD,
                    GREEN,
                    (Float32(x) + 0.5) / 32,
                    (Float32(y) + 0.5) / 32,
                )
                if color == CRIMSON:
                    grounds += 1
                elif color == GOLD:
                    motifs += 1
        # The ground shows, and the motif shows on it.
        assert_true(grounds > 32 * 32 // 6)
        assert_true(motifs > 0 or design == BROCADE or design == PINSTRIPE)
    # Tartan's bands and a flower's heart take the third dye.
    var thirds = 0
    for y in range(64):
        for x in range(64):
            var u = (Float32(x) + 0.5) / 64
            var v = (Float32(y) + 0.5) / 64
            if colored_shade(TARTAN, CRIMSON, GOLD, GREEN, u, v) == GREEN:
                thirds += 1
            if colored_shade(FLORAL, CRIMSON, GOLD, GREEN, u, v) == GREEN:
                thirds += 1
    assert_true(thirds > 0)
    for design in _tonal():
        with assert_raises(contains="colors"):
            _ = colored_shade(design, CRIMSON, GOLD, GREEN, 0.5, 0.5)
    var texture = colored_texture(BROCADE, CRIMSON, GOLD, GREEN)
    assert_true(texture.color_space == SRGB)
    assert_almost_equal(texture.repeat.y, 1 / design_tile(BROCADE), atol=1e-4)


def test_a_braid_is_a_cable_of_two_strands() raises:
    var low = Float32(1)
    var high = Float32(0)
    for y in range(32):
        var shade = braid_shade(0.25, (Float32(y) + 0.5) / 32)
        low = min(low, shade)
        high = max(high, shade)
    assert_true(low >= 0.7 and high <= 1)
    assert_true(high - low > 0.2)
    var texture = braid_texture()
    assert_true(texture.color_space == LINEAR)
    assert_almost_equal(texture.repeat.x, 1 / BRAID_TILE, atol=1e-3)


def test_each_texture_is_made_once() raises:
    var assets = Assets()
    var maps = DesignMaps()
    var damask = maps.tonal(assets, DAMASK)
    assert_equal(maps.tonal(assets, DAMASK), damask)
    var brocade = maps.colored(assets, BROCADE, CRIMSON, GOLD, GREEN)
    assert_equal(maps.colored(assets, BROCADE, CRIMSON, GOLD, GREEN), brocade)
    # Other dyes are another texture.
    assert_true(maps.colored(assets, BROCADE, GREEN, GOLD, GREEN) != brocade)
    var braid = maps.braid(assets)
    assert_equal(maps.braid(assets), braid)
    assert_equal(assets.textures.count(), 4)
    # A garment's designed part.
    var dyes: List[Color] = [CRIMSON, GREEN, GOLD, GOLD]
    assert_equal(maps.designed(assets, PLAIN, dyes), NO_TEXTURE)
    assert_equal(maps.designed(assets, DAMASK, dyes), damask)
    assert_equal(maps.designed(assets, BROCADE, dyes), brocade)
    with assert_raises(contains="four dyes"):
        _ = maps.designed(assets, BROCADE, [CRIMSON])
    with assert_raises(contains="design must"):
        _ = maps.designed(assets, Design(40), dyes)


def test_each_fabric_wears_the_design_it_can() raises:
    var cloth: List[FabricKind] = [LINEN, WOOL, SILK, VELVET, PADDING, FELT]
    for kind in cloth:
        assert_equal(worn_design(BROCADE, kind), BROCADE)
        assert_equal(worn_design(PLAIN, kind), PLAIN)
    # Leather wears hide when it is plain.
    assert_equal(worn_design(PLAIN, LEATHER), HIDE)
    assert_equal(worn_design(DAMASK, LEATHER), DAMASK)
    var hard: List[FabricKind] = [MAIL, PLATE, SCALE, FUR, STRAW]
    for kind in hard:
        assert_equal(worn_design(TARTAN, kind), PLAIN)
    with assert_raises(contains="design must"):
        _ = worn_design(Design(40), SILK)
    with assert_raises(contains="fabric"):
        _ = worn_design(PLAIN, FabricKind(40))


def test_a_motif_shows_on_its_ground() raises:
    # A motif far from its ground is kept.
    assert_true(contrast(CRIMSON, GOLD, 0.4) == GOLD)
    # One near a dark ground is a lighter shade of it.
    var near = Color(152, 22, 30)
    var light = contrast(CRIMSON, near, 0.5)
    assert_true(light.r > CRIMSON.r and light.g > CRIMSON.g)
    assert_true(light.r < CREAM.r)
    # One near a light ground is a darker shade.
    var pale = Color(230, 228, 220)
    var dark = contrast(pale, pale, 0.5)
    assert_true(dark.r < pale.r and dark.b < pale.b)


def test_a_design_in_colors_paints_its_region_white() raises:
    var dyes: List[Color] = [CRIMSON, GREEN, GOLD, GOLD]
    var painted = design_dyes(BROCADE, dyes)
    assert_true(painted[PRIMARY_DYE.value] == Color(255, 255, 255))
    assert_true(painted[SECONDARY_DYE.value] == GREEN)
    var kept = design_dyes(DAMASK, dyes)
    assert_true(kept[PRIMARY_DYE.value] == CRIMSON)
    with assert_raises(contains="four dyes"):
        _ = design_dyes(BROCADE, [CRIMSON])
    with assert_raises(contains="design must"):
        _ = design_dyes(Design(40), dyes)


def _dyed(channels: List[DyeChannel]) raises -> BufferGeometry:
    """Return a stack of tubes, one band per channel, each wholly in it."""
    var stack = with_channel(tube(0, 0, 0.2, 1, 0.9, HIPS, 1, 8), channels[0])
    for k in range(1, len(channels)):
        var top = 1 - Float32(k) * 0.1
        stack = merge(
            stack,
            with_channel(
                tube(0, 0, 0.2, top, top - 0.1, HIPS, 1, 8), channels[k]
            ),
        )
    return stack^


def _channels(piece: BufferGeometry) raises -> List[Int]:
    """Return how many vertices each channel holds in a piece."""
    var counts = List[Int](length=4, fill=0)
    ref weights = piece.attribute_view(String(DYE))
    for v in range(weights.count()):
        for c in range(4):
            if weights.component(v, c) > 0.5:
                counts[c] += 1
    return counts^


def test_a_garment_is_cut_into_the_parts_its_design_draws() raises:
    var all: List[DyeChannel] = [
        PRIMARY_DYE,
        SECONDARY_DYE,
        TRIM_DYE,
        ACCENT_DYE,
    ]
    var piece = _dyed(all)
    var whole = piece.triangle_count()
    # Plain, and a tonal design that braids nothing: one part.
    for design in [PLAIN, HERRINGBONE, HIDE]:
        var parts = design_parts(piece, design)
        assert_equal(parts.designed.value().triangle_count(), whole)
        assert_false(Bool(parts.plain) or Bool(parts.braided))
    # Damask lies on all but the trim, which is braided.
    var damask = design_parts(piece, DAMASK)
    var on = _channels(damask.designed.value())
    assert_true(on[0] > 0 and on[1] > 0 and on[3] > 0 and on[2] == 0)
    assert_false(Bool(damask.plain))
    assert_equal(_channels(damask.braided.value())[2], 16)
    # Brocade lies on the primary dye alone.
    var brocade = design_parts(piece, BROCADE)
    on = _channels(brocade.designed.value())
    assert_true(on[0] > 0 and on[1] == 0 and on[2] == 0)
    var rest = _channels(brocade.plain.value())
    assert_true(rest[0] == 0 and rest[1] > 0 and rest[3] > 0 and rest[2] == 0)
    assert_true(Bool(brocade.braided))
    # Tartan braids nothing: the trim is drawn plain.
    var tartan = design_parts(piece, TARTAN)
    assert_true(_channels(tartan.plain.value())[2] > 0)
    assert_false(Bool(tartan.braided))
    # A garment all of the primary dye has no plain part.
    var single: List[DyeChannel] = [PRIMARY_DYE]
    var plain = design_parts(_dyed(single), CHECK)
    assert_false(Bool(plain.plain))
    assert_equal(
        plain.designed.value().triangle_count(),
        _dyed(single).triangle_count(),
    )
    with assert_raises(contains="design must"):
        _ = design_parts(piece, Design(40))


def test_the_parts_drawn_each_take_a_map() raises:
    var assets = Assets()
    var maps = DesignMaps()
    var dyes: List[Color] = [CRIMSON, GREEN, GOLD, GOLD]
    var all: List[DyeChannel] = [PRIMARY_DYE, SECONDARY_DYE, TRIM_DYE]
    var whole = design_parts(_dyed(all), BROCADE)
    var drawn = whole.drawn(maps, assets, BROCADE, dyes)
    assert_equal(len(drawn.pieces), 3)
    assert_equal(drawn.maps[0], maps.designed(assets, BROCADE, dyes))
    assert_equal(drawn.maps[1], NO_TEXTURE)
    assert_equal(drawn.maps[2], maps.braid(assets))
    # A garment with none of its primary dye shown has no designed part.
    var rest: List[DyeChannel] = [SECONDARY_DYE, TRIM_DYE]
    var parted = design_parts(_dyed(rest), BROCADE)
    assert_false(Bool(parted.designed))
    var shown = parted.drawn(maps, assets, BROCADE, dyes)
    assert_equal(len(shown.pieces), 2)
    assert_equal(shown.maps[0], NO_TEXTURE)
    # Taken once: the parts are gone.
    assert_equal(len(parted.drawn(maps, assets, BROCADE, dyes).pieces), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
