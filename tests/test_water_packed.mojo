# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Packed water textures shade exactly as the fields they copy."""

from extensions.water.frame import WaterScene, camera_look, lit_radiance
from extensions.water.optics import sun_direction
from extensions.water.packed import WaterPack
from extensions.water.pebbles import PebbleBed
from extensions.water.resolution import SpectrumResolution
from std.testing import TestSuite, assert_equal, assert_true
from units.si import RADIAN, SECOND, Angle, Duration


def _bed() raises -> PebbleBed:
    # A 6 by 4 photograph has three levels of uneven mips.
    var pixels = List[Float32](length=6 * 4 * 3, fill=0.0)
    for i in range(len(pixels)):
        pixels[i] = Float32((i * 37) % 23) / 23.0
    return PebbleBed(6, 4, pixels^)


def _scene() raises -> WaterScene:
    # A 64-texel window lets the center tap raise real ripples.
    var scene = WaterScene(
        SpectrumResolution(64),
        8,
        32,
        SpectrumResolution(4),
        Duration(5.0, SECOND),
    )
    for step in range(6):
        scene.advance(Duration(0.02, SECOND), step % 2 == 0)
    return scene^


def test_pack_copies_every_level() raises:
    var scene = _scene()
    var bed = _bed()
    var surface = scene._surface()
    var caustics = scene._caustics(surface)
    var pack = WaterPack(surface, scene._ripples, caustics, bed)
    var view = pack.surface_view()
    assert_equal(view.surface_levels(), surface.surface_levels())
    assert_true(surface.surface_levels() > 0)
    for level in range(surface.surface_levels() + 1):
        var side = surface.surface_side(level)
        assert_equal(view.surface_side(level), side)
        var a = view.surface_texel(level, side - 1, side - 1)
        var b = surface.surface_texel(level, side - 1, side - 1)
        assert_equal(a.height, b.height)
        assert_equal(a.slope_sq, b.slope_sq)
    var light = pack.caustic_view()
    assert_true(caustics.caustic_levels() > 0)
    assert_equal(light.caustic_levels(), caustics.caustic_levels())
    for level in range(caustics.caustic_levels() + 1):
        var side = caustics.caustic_side(level)
        assert_equal(light.caustic_side(level), side)
        assert_equal(
            light.caustic_channel(level, side - 1, 0, 2),
            caustics.caustic_channel(level, side - 1, 0, 2),
        )
    var stones = pack.pebble_view()
    assert_equal(stones.pebble_levels(), 2)
    for level in range(3):
        var w = bed.pebble_width(level)
        var h = bed.pebble_height(level)
        assert_equal(stones.pebble_width(level), w)
        assert_equal(stones.pebble_height(level), h)
        assert_equal(
            stones.pebble_texel(level, w - 1, h - 1).g,
            bed.pebble_texel(level, w - 1, h - 1).g,
        )
    var waves = pack.ripple_view()
    assert_equal(waves.ripple_side(), 64)
    var raised = 0
    var differ = 0
    for i in range(len(scene._ripples.normal)):
        if waves.ripple_normal(i) != scene._ripples.normal[i]:
            differ += 1
        if scene._ripples.normal[i] != 0.0:
            raised += 1
    assert_equal(differ, 0)
    assert_true(raised > 0)
    # A view does not keep its pack alive. Mojo ends a value at its last
    # use, so use the pack after the last read through a view.
    _ = pack.ripple_side


def test_packed_views_shade_every_pixel_alike() raises:
    # The arithmetic is the same. The compiler can fuse a multiply and an
    # add differently in each instantiation, so the last bits can differ.
    var scene = _scene()
    var bed = _bed()
    var surface = scene._surface()
    var caustics = scene._caustics(surface)
    var pack = WaterPack(surface, scene._ripples, caustics, bed)
    var sun = sun_direction()
    var worst = Float32(0.0)
    # A steep and a grazing pitch reach fine and coarse mip levels.
    for pitch in [Float32(-1.2), Float32(-0.25)]:
        var look = camera_look(scene.clock, True, Angle(pitch, RADIAN))
        var width = 24
        var height = 16
        var aspect = Float32(width) / Float32(height)
        for y in range(height):
            for x in range(width):
                var ndc_x = ((Float32(x) + 0.5) / Float32(width)) * 2.0 - 1.0
                var ndc_y = 1.0 - ((Float32(y) + 0.5) / Float32(height)) * 2.0
                var a = lit_radiance(
                    look,
                    ndc_x,
                    ndc_y,
                    aspect,
                    surface,
                    scene._ripples,
                    caustics,
                    bed,
                    scene.clock,
                    2.0 / Float32(width),
                    2.0 / Float32(height),
                    sun,
                )
                var b = lit_radiance(
                    look,
                    ndc_x,
                    ndc_y,
                    aspect,
                    pack.surface_view(),
                    pack.ripple_view(),
                    pack.caustic_view(),
                    pack.pebble_view(),
                    scene.clock,
                    2.0 / Float32(width),
                    2.0 / Float32(height),
                    sun,
                )
                for c in range(3):
                    var left = a.x if c == 0 else (a.y if c == 1 else a.z)
                    var right = b.x if c == 0 else (b.y if c == 1 else b.z)
                    worst = max(worst, abs(left - right) / max(abs(left), 1e-3))
    assert_true(worst < 1e-5, String("relative difference ", worst))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
