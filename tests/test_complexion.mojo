# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the skin's, the hair's and the iris's pigment and maps."""

from extensions.humanoid.genome import (
    FRECKLES,
    Expression,
    Genome,
    HAIR_MELANIN,
    HAIR_REDNESS,
    IRIS_MELANIN,
    MELANIN,
    UNDERTONE,
)
from extensions.humanoid.skeleton.complexion import (
    EYE_IRIS,
    EYE_PUPIL,
    MAX_MAP,
    MIN_MAP,
    Tone,
    check_map_size,
    hair_albedo,
    hair_pixels,
    hair_tone,
    iris_albedo,
    iris_pixels,
    iris_tone,
    skin_albedo_pixels,
    skin_glow,
    skin_relief,
    skin_relief_pixels,
    skin_tone,
    value_noise,
)
from core.assets import Assets
from extensions.humanoid.skeleton.look import (
    add_complexion,
    skin_scatter,
    eye_physical,
    hair_phong,
    hair_physical,
    skin_albedo,
    skin_phong,
    skin_physical,
)
from render.srgb import LINEAR, SRGB
from render.texture_store import TextureId, NO_TEXTURE
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _with(gene_value: Float32) raises -> Genome:
    return Genome().with_gene(MELANIN, Expression(gene_value))


def _luma(r: UInt8, g: UInt8, b: UInt8) -> Int:
    return Int(r) + Int(g) + Int(b)


def _broken() -> Genome:
    var genome = Genome()
    genome.expressions[0] = 9
    return genome


def test_skin_tone_darkens_with_melanin() raises:
    var fair = skin_tone(_with(-1))
    var middle = skin_tone(Genome())
    var dark = skin_tone(_with(1))
    assert_true(
        _luma(fair.r, fair.g, fair.b) > _luma(middle.r, middle.g, middle.b)
    )
    assert_true(
        _luma(middle.r, middle.g, middle.b) > _luma(dark.r, dark.g, dark.b)
    )
    assert_true(fair.r > 240 and dark.r < 90)
    # A warm undertone is yellower than a cool one.
    var warm = skin_tone(Genome().with_gene(UNDERTONE, Expression(1)))
    var cool = skin_tone(Genome().with_gene(UNDERTONE, Expression(-1)))
    assert_true(Int(warm.g) - Int(warm.b) > Int(cool.g) - Int(cool.b))
    with assert_raises(contains="skin"):
        _ = skin_tone(_broken())
    var glow = skin_glow(Genome())
    assert_true(glow.r > glow.g and glow.g >= glow.b)
    assert_true(skin_glow(_with(1)).r < skin_glow(_with(-1)).r)
    with assert_raises(contains="skin"):
        _ = skin_glow(_broken())


def test_hair_and_iris_tones() raises:
    var blond = hair_tone(Genome().with_gene(HAIR_MELANIN, Expression(-1)))
    var black = hair_tone(Genome().with_gene(HAIR_MELANIN, Expression(1)))
    assert_true(_luma(blond.r, blond.g, blond.b) > 450)
    assert_true(_luma(black.r, black.g, black.b) < 80)
    var red = hair_tone(Genome().with_gene(HAIR_REDNESS, Expression(1)))
    var plain = hair_tone(Genome())
    assert_true(Int(red.r) - Int(red.b) > Int(plain.r) - Int(plain.b))
    with assert_raises(contains="hair"):
        _ = hair_tone(_broken())
    var blue = iris_tone(Genome().with_gene(IRIS_MELANIN, Expression(-1)))
    var brown = iris_tone(Genome().with_gene(IRIS_MELANIN, Expression(1)))
    assert_true(blue.b > blue.r)
    assert_true(brown.r > brown.b)
    with assert_raises(contains="eye"):
        _ = iris_tone(_broken())


def test_tones_mix() raises:
    var a = Tone(0, 100, 200)
    var b = Tone(100, 100, 0)
    var m = a.mix(b, 0.5)
    assert_equal(m.r, 50)
    assert_equal(m.b, 100)
    var c = Tone(-10, 300, 127.6).color()
    assert_equal(c.r, 0)
    assert_equal(c.g, 255)
    assert_equal(c.b, 128)


def test_value_noise_tiles() raises:
    for step in range(5):  # pragma: no branch
        var y = Float32(step) * 0.7
        var a = value_noise(0.0, y, 4, 3)
        var b = value_noise(4.0, y, 4, 3)
        assert_true(abs(a - b) < 1e-5)
        var c = value_noise(y, 0.0, 4, 3, 8)
        var d = value_noise(y, 8.0, 4, 3, 8)
        assert_true(abs(c - d) < 1e-5)
    var v = value_noise(-1.3, -2.7, 4, 3)
    assert_true(v >= 0 and v <= 1)


def test_map_sizes_are_checked() raises:
    check_map_size(MIN_MAP, "skin")
    check_map_size(MAX_MAP, "skin")
    with assert_raises(contains="at least eight"):
        check_map_size(MIN_MAP - 1, "skin")
    with assert_raises(contains="cannot exceed"):
        check_map_size(MAX_MAP + 1, "skin")
    with assert_raises(contains="skin"):
        _ = skin_albedo_pixels(16, _broken())
    with assert_raises(contains="eye"):
        _ = iris_pixels(16, _broken())
    with assert_raises(contains="hair"):
        _ = hair_pixels(16, _broken())


def test_skin_maps() raises:
    var pixels = skin_albedo_pixels(32, Genome())
    assert_equal(len(pixels), 32 * 32 * 4)
    var freckled = (
        Genome()
        .with_gene(FRECKLES, Expression(1))
        .with_gene(MELANIN, Expression(-0.8))
    )
    var spotted = skin_albedo_pixels(64, freckled)
    var clear = skin_albedo_pixels(
        64, freckled.with_gene(FRECKLES, Expression(-1))
    )
    var darker = 0
    for index in range(64 * 64):  # pragma: no branch
        if Int(spotted[index * 4 + 2]) + 6 < Int(clear[index * 4 + 2]):
            darker += 1
    assert_true(darker > 20)
    var relief = skin_relief(16)
    assert_equal(relief.width, 16)
    assert_true(relief.color_space == LINEAR)
    var heights = skin_relief_pixels(16)
    assert_equal(heights[0], heights[1])
    var map = skin_albedo(16, _with(0.5))
    assert_true(map.color_space == SRGB)
    with assert_raises(contains="exceed 256"):
        _ = skin_albedo(512)


def test_eye_and_hair_maps() raises:
    var size = 64
    var eye = iris_pixels(size, Genome())
    assert_equal(len(eye), size * size * 4)
    # The bottom row is the front pole: the pupil is black.
    var front = (size - 1) * size * 4
    assert_true(Int(eye[front]) < 20)
    # The top row is the back of the eye: white sclera.
    assert_true(Int(eye[0]) > 150)
    assert_true(EYE_PUPIL < EYE_IRIS)
    assert_equal(iris_albedo(16).width, 16)
    var strands = hair_albedo(16)
    assert_equal(strands.height, 16)
    var hair = hair_pixels(16, Genome())
    assert_equal(len(hair), 16 * 16 * 4)


def test_looks_follow_the_genome() raises:
    var dark = _with(1)
    var tinted = skin_physical(genome=dark, tinted=True)
    assert_true(tinted.vertex_colors)
    assert_true(tinted.color.r < 100)
    assert_false(skin_physical().vertex_colors)
    var mapped = skin_physical(TextureId(0), dark, TextureId(1))
    assert_equal(mapped.color.r, 255)
    assert_true(mapped.bump_map == TextureId(1))
    assert_true(skin_phong(genome=dark, tinted=True).vertex_colors)
    assert_true(skin_phong(TextureId(0)).color.r == 255)
    var black = Genome().with_gene(HAIR_MELANIN, Expression(1))
    assert_true(hair_phong(black).color.r < 40)
    assert_true(hair_physical(black).color.r < 40)
    assert_equal(hair_physical(black, TextureId(2)).color.r, 255)
    assert_true(eye_physical().clearcoat > 0.9)
    assert_true(eye_physical(TextureId(3)).map == TextureId(3))
    assert_true(eye_physical().map == NO_TEXTURE)


def test_a_complexion_is_stored() raises:
    var assets = Assets()
    var head = add_complexion(assets, _with(0.3), size=32)
    var body = add_complexion(assets, _with(0.3), whole_body=True, size=32)
    with assert_raises(contains="skin map"):
        _ = add_complexion(assets, _with(0.3), size=4)
    assert_equal(assets.materials.count(), 6)
    assert_equal(assets.textures.count(), 8)
    var skin = assets.materials.get(head.skin)
    assert_true(skin.vertex_colors)
    assert_true(skin.nodes.value >= 0)
    var tall = assets.materials.get(body.skin)
    assert_true(
        assets.textures.get(tall.map).repeat.y
        > assets.textures.get(skin.map).repeat.y
    )
    assert_true(assets.materials.get(head.eyes).clearcoat > 0.9)
    assert_true(assets.materials.get(body.hair).map != NO_TEXTURE)
    _ = skin_scatter()
    with assert_raises(contains="skin"):
        _ = skin_scatter(_broken())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
