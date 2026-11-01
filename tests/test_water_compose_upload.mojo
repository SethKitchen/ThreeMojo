# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The arrays that a GPU composes the water of a frame from: they are made
only when the scene has new ones, and they count each time."""

from cameras.perspective_camera import PerspectiveCamera
from extensions.water.frame import WaterScene, _ComposePlan, _compose_plan
from extensions.water.pebbles import PebbleBed
from extensions.water.resolution import SpectrumResolution
from extensions.water.upload import (
    COMPOSE_WORDS,
    WORD_CAUSTIC_TABLE,
    WORD_GRID_HEIGHT,
    WORD_GRID_WIDTH,
    WORD_HEIGHT,
    WORD_PEBBLE_TABLE,
    WORD_RIPPLE_SIDE,
    WORD_STEP,
    WORD_SURFACE_TABLE,
    WORD_WIDTH,
    ComposeUpload,
    _words,
    grid_samples,
)
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import cos, sin
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length

comptime WIDTH = 29
comptime HEIGHT = 17


def _bed() raises -> PebbleBed:
    """Return a photograph of 6 by 4 pixels."""
    var pixels = List[Float32](length=6 * 4 * 3, fill=0.0)
    for i in range(len(pixels)):
        pixels[i] = Float32((i * 37) % 23) / 23.0
    return PebbleBed(6, 4, pixels^)


def _scene() raises -> WaterScene:
    """Return a small water scene whose pixels are shaded on a grid of two."""
    var scene = WaterScene(
        SpectrumResolution(16),
        4,
        8,
        SpectrumResolution(4),
        Duration(5.0, SECOND),
    )
    scene.shade_step = 2
    return scene^


def _plan() raises -> _ComposePlan:
    """Return the plan of a camera that looks down at the still water."""
    var camera = PerspectiveCamera(
        Angle(64.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.01, METER),
        Length(1000.0, METER),
    )
    var pitch = Float32(-0.72)
    camera.place(
        Vector3(0, 1.55, 0), Vector3(0, 1.55 + sin(pitch), -cos(pitch))
    )
    var image = Framebuffer(WIDTH, HEIGHT, Color(0, 0, 0))
    return _compose_plan(
        image,
        camera.projection_matrix(),
        camera.view_matrix(),
        Length(0.0, METER),
    )


def test_a_side_has_a_sample_on_each_step_and_one_on_the_last_pixel() raises:
    assert_equal(grid_samples(1, 2), 1)
    assert_equal(grid_samples(2, 2), 2)
    assert_equal(grid_samples(48, 2), 25)
    assert_equal(grid_samples(49, 4), 13)
    assert_equal(grid_samples(5, 8), 2)
    assert_equal(grid_samples(WIDTH, 2), 15)


def test_the_first_refresh_makes_every_array() raises:
    var scene = _scene()
    var upload = ComposeUpload()
    assert_equal(len(upload.words), COMPOSE_WORDS)
    assert_equal(upload.surface_made, 0)
    upload.refresh(scene, _plan(), _bed(), WIDTH, HEIGHT)
    assert_equal(upload.surface_made, 1)
    assert_equal(upload.ripple_made, 1)
    assert_equal(upload.bed_made, 1)
    assert_true(len(upload.surface) > 0)
    assert_true(len(upload.ripple) > 0)
    assert_true(len(upload.caustic) > 0)
    assert_true(len(upload.pebble) > 0)
    # The words hold the sizes, and the tables of levels, two words an entry.
    assert_equal(Int(upload.words[WORD_WIDTH]), WIDTH)
    assert_equal(Int(upload.words[WORD_HEIGHT]), HEIGHT)
    assert_equal(Int(upload.words[WORD_STEP]), 2)
    assert_equal(Int(upload.words[WORD_GRID_WIDTH]), grid_samples(WIDTH, 2))
    assert_equal(Int(upload.words[WORD_GRID_HEIGHT]), grid_samples(HEIGHT, 2))
    assert_equal(Int(upload.words[WORD_RIPPLE_SIDE]), scene._ripples.n)
    # Each level table holds the count of levels, then the side and the
    # start of each level, two words an entry. The words between stay zero.
    ref surface = scene._surface_kept.value()
    ref caustics = scene._caustics_kept.value()
    assert_equal(
        Int(upload.words[WORD_SURFACE_TABLE]), surface.surface_levels()
    )
    assert_equal(
        Int(upload.words[WORD_SURFACE_TABLE + 2]), surface.surface_side(0)
    )
    assert_equal(upload.words[WORD_SURFACE_TABLE + 4], 0)
    assert_true(upload.words[WORD_SURFACE_TABLE + 6] > 0)
    assert_equal(upload.words[WORD_SURFACE_TABLE + 1], 0)
    assert_equal(upload.words[WORD_SURFACE_TABLE + 3], 0)
    assert_equal(
        Int(upload.words[WORD_CAUSTIC_TABLE]), caustics.caustic_levels()
    )
    assert_equal(
        Int(upload.words[WORD_CAUSTIC_TABLE + 2]), caustics.caustic_side(0)
    )
    assert_equal(upload.words[WORD_CAUSTIC_TABLE + 4], 0)
    assert_true(upload.words[WORD_PEBBLE_TABLE] > 0)
    assert_equal(upload.words[WORD_PEBBLE_TABLE + 1], 0)


def test_a_refresh_packs_only_what_changed() raises:
    var scene = _scene()
    var upload = ComposeUpload()
    var plan = _plan()
    var bed = _bed()
    upload.refresh(scene, plan, bed, WIDTH, HEIGHT)
    # Every frame finds a new surface, and the ripples have not moved.
    upload.refresh(scene, plan, bed, WIDTH, HEIGHT)
    assert_equal(upload.surface_made, 2)
    assert_equal(upload.ripple_made, 1)
    assert_equal(upload.bed_made, 1)
    # A step of the ripples changes them. The photograph stays packed.
    scene.advance(Duration(0.02, SECOND), True)
    upload.refresh(scene, plan, bed, WIDTH, HEIGHT)
    assert_equal(upload.surface_made, 3)
    assert_equal(upload.ripple_made, 2)
    assert_equal(upload.bed_made, 1)
    # A scene that is reset has new ripples.
    scene.reset()
    upload.refresh(scene, plan, bed, WIDTH, HEIGHT)
    assert_equal(upload.ripple_made, 3)
    assert_equal(upload.bed_made, 1)


def test_a_surface_that_is_kept_is_not_packed_again() raises:
    var scene = _scene()
    scene.refresh_every = 3
    var upload = ComposeUpload()
    var plan = _plan()
    var bed = _bed()
    # The first call finds a surface. The next two keep it, the fourth
    # finds the next one, and the fifth shows it.
    upload.refresh(scene, plan, bed, WIDTH, HEIGHT)
    assert_equal(upload.surface_made, 1)
    for _ in range(3):
        upload.refresh(scene, plan, bed, WIDTH, HEIGHT)
        assert_equal(upload.surface_made, 1)
    upload.refresh(scene, plan, bed, WIDTH, HEIGHT)
    assert_equal(upload.surface_made, 2)


def test_a_scene_that_cannot_be_composed_is_refused_and_leaves_the_arrays() raises:
    var scene = _scene()
    var upload = ComposeUpload()
    var plan = _plan()
    var bed = _bed()
    upload.refresh(scene, plan, bed, WIDTH, HEIGHT)
    var words = upload.words.copy()
    scene.shade_step = 1
    with assert_raises(contains="shade step from 2 to 64"):
        upload.refresh(scene, plan, bed, WIDTH, HEIGHT)
    scene.shade_step = 65
    with assert_raises(contains="shade step from 2 to 64"):
        upload.refresh(scene, plan, bed, WIDTH, HEIGHT)
    scene.shade_step = 2
    scene.refresh_every = 0
    with assert_raises(contains="refresh"):
        upload.refresh(scene, plan, bed, WIDTH, HEIGHT)
    assert_equal(upload.surface_made, 1)
    assert_true(upload.words == words)


def test_a_table_that_does_not_fit_is_refused() raises:
    var words = List[UInt32](length=COMPOSE_WORDS, fill=0)
    var table = List[Int64]()
    for k in range(32):
        table.append(Int64(k + 1))
    # Thirty-two entries of two words fill the room of 64 exactly.
    _words(words, WORD_SURFACE_TABLE, 64, table)
    assert_equal(Int(words[WORD_SURFACE_TABLE + 62]), 32)
    table.append(33)
    with assert_raises(contains="longer than the words kept for it"):
        _words(words, WORD_SURFACE_TABLE, 64, table)
    # An empty table writes nothing.
    var none = List[UInt32](length=COMPOSE_WORDS, fill=0)
    _words(none, WORD_SURFACE_TABLE, 64, List[Int64]())
    assert_equal(Int(none[WORD_SURFACE_TABLE]), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
