# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.background`: the four kinds, the builders, and what
`validate` refuses. What a renderer draws for each is tested in
`tests/test_environment.mojo`."""

from core.background import (
    COLOR_BACKGROUND,
    CUBE_BACKGROUND,
    NO_BACKGROUND,
    TEXTURE_BACKGROUND,
    Background,
    BackgroundKind,
    color_background,
    cube_background,
    no_background,
    texture_background,
)
from core.scene import Scene
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
)
from render.framebuffer import Color
from render.texture_store import NO_TEXTURE, TextureId
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_a_scene_starts_with_no_background_and_no_environment() raises:
    var scene = Scene()
    assert_equal(scene.background.kind, NO_BACKGROUND)
    assert_false(scene.background.is_set())
    assert_false(scene.background.is_image())
    assert_equal(scene.environment, NO_CUBE_TEXTURE)
    scene.background.validate()


def test_each_builder_fills_in_its_own_field() raises:
    var none = no_background()
    assert_equal(none.kind, NO_BACKGROUND)
    assert_equal(none.texture, NO_TEXTURE)
    assert_equal(none.cube, NO_CUBE_TEXTURE)

    var tinted = color_background(Color(10, 20, 30, 40))
    assert_equal(tinted.kind, COLOR_BACKGROUND)
    assert_equal(tinted.color.r, UInt8(10))
    assert_equal(tinted.color.a, UInt8(40))
    assert_true(tinted.is_set())
    assert_false(tinted.is_image())

    var pictured = texture_background(TextureId(3))
    assert_equal(pictured.kind, TEXTURE_BACKGROUND)
    assert_equal(pictured.texture, TextureId(3))
    assert_true(pictured.is_image())

    var sky = cube_background(CubeTextureId(2))
    assert_equal(sky.kind, CUBE_BACKGROUND)
    assert_equal(sky.cube, CubeTextureId(2))
    assert_true(sky.is_image())
    for each in [none, tinted, pictured, sky]:
        each.validate()


def test_a_scene_takes_a_background_and_an_environment() raises:
    var scene = Scene()
    scene.background = cube_background(CubeTextureId(0))
    scene.environment = CubeTextureId(0)
    assert_equal(scene.background.kind, CUBE_BACKGROUND)
    assert_equal(scene.environment, CubeTextureId(0))


def test_an_image_background_must_name_an_image() raises:
    with assert_raises():
        _ = texture_background(NO_TEXTURE)
    with assert_raises():
        _ = texture_background(TextureId(-5))
    with assert_raises():
        _ = cube_background(NO_CUBE_TEXTURE)
    with assert_raises():
        _ = cube_background(SCENE_ENVIRONMENT)


def test_the_fields_are_open_and_validate_reads_them() raises:
    # The builders refuse a missing id, and so does `validate` of one
    # edited in afterward, since the renderer asks it every frame.
    var pictured = texture_background(TextureId(1))
    pictured.texture = NO_TEXTURE
    with assert_raises():
        pictured.validate()
    var sky = cube_background(CubeTextureId(1))
    sky.cube = CubeTextureId(-3)
    with assert_raises():
        sky.validate()
    # A kind that is none of the four, built straight.
    var odd = Background(BackgroundKind(9))
    assert_false(odd.kind.is_valid())
    with assert_raises():
        odd.validate()
    # A color background with an absent texture is fine: the kind does
    # not read it.
    var tinted = Background(COLOR_BACKGROUND, Color(1, 2, 3), NO_TEXTURE)
    tinted.validate()


def test_every_named_kind_is_valid() raises:
    for kind in [
        NO_BACKGROUND,
        COLOR_BACKGROUND,
        TEXTURE_BACKGROUND,
        CUBE_BACKGROUND,
    ]:
        assert_true(kind.is_valid())
    assert_false(BackgroundKind(4).is_valid())
    assert_false(BackgroundKind(-1).is_valid())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
