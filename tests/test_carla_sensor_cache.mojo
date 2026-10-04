# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact sensor-cache invalidation, including direct public-array edits."""

from extensions.carla.sensor_cache import (
    coverage_matches,
    sensor_material_matches,
)
from materials.material import BACK_SIDE, Material
from math.bounds import Plane
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color
from render.srgb import LINEAR
from render.texture import (
    CUBE_REFLECTION_MAPPING,
    FLOAT_TYPE,
    IGNORED,
    MIRROR,
    NEAREST,
    REPEAT,
    UV_CHANNEL_1,
    Texture,
    float_texture,
)
from render.texture_store import NO_TEXTURE, TextureId
from std.testing import TestSuite, assert_false, assert_true
from units.si import Angle, RADIAN


def test_every_texture_sampling_field_invalidates() raises:
    var source = Texture(2, 2, List[UInt8](length=16, fill=255))
    var cached = Texture(copy=source)
    assert_true(coverage_matches(source, cached))
    source.width = 3
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.height = 3
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.texel_type = FLOAT_TYPE
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.wrap_s = REPEAT
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.wrap_t = MIRROR
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.mag_filter = NEAREST
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.min_filter = NEAREST
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.flip_y = False
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.mapping = CUBE_REFLECTION_MAPPING
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.color_space = LINEAR
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.alpha = IGNORED
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.levels = 1
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.offsets = [0, 12]
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.ramp = [Float32(1)]
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.offset = Vector2(0.25, 0)
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.repeat = Vector2(2, 1)
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.rotation = Angle(0.5, RADIAN)
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.center = Vector2(0.5, 0.5)
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.anisotropy = 2
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.channel = UV_CHANNEL_1
    assert_false(coverage_matches(source, cached))


def test_byte_and_float_alpha_and_mip_edits_invalidate() raises:
    var source = Texture(2, 2, List[UInt8](length=16, fill=255))
    var cached = Texture(copy=source)
    # RGB never colors the semantic override, including mip RGB.
    source.pixels[0] = 0
    source.pixels[16] = 0
    assert_true(coverage_matches(source, cached))
    source.pixels[3] = 0
    assert_false(coverage_matches(source, cached))
    source.pixels[3] = 255
    source.pixels[19] = 127
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.pixels.append(255)
    assert_false(coverage_matches(source, cached))
    source = Texture(copy=cached)
    source.data.append(1)
    assert_false(coverage_matches(source, cached))
    source = float_texture(
        2, 2, List[Float32](length=16, fill=1), mipmapped=True
    )
    cached = Texture(copy=source)
    source.data[0] = 0.2
    source.data[16] = 0.3
    assert_true(coverage_matches(source, cached))
    source.data[3] = 0.5
    assert_false(coverage_matches(source, cached))
    source.data[3] = 1
    source.data[19] = 0.75
    assert_false(coverage_matches(source, cached))
    # Float alpha equality is bitwise, including signed zero.
    source.data[19] = 0.0
    cached = Texture(copy=source)
    source.data[19] = -0.0
    assert_false(coverage_matches(source, cached))
    var blank = Texture()
    assert_true(coverage_matches(blank, blank))


def test_every_material_coverage_field_invalidates() raises:
    var source = Material(Color(20, 30, 40))
    var cached = source
    assert_true(sensor_material_matches(source, cached, NO_TEXTURE))
    assert_false(sensor_material_matches(source, cached, TextureId(4)))
    source.side = BACK_SIDE
    assert_false(sensor_material_matches(source, cached, NO_TEXTURE))
    source = cached
    source.opacity = 0.5
    assert_false(sensor_material_matches(source, cached, NO_TEXTURE))
    source = cached
    source.alpha_map = TextureId(4)
    assert_false(sensor_material_matches(source, cached, NO_TEXTURE))
    source = cached
    source.alpha_test = 0.5
    assert_false(sensor_material_matches(source, cached, NO_TEXTURE))
    source = cached
    source.visible = False
    assert_false(sensor_material_matches(source, cached, NO_TEXTURE))
    source = cached
    source.alpha_hash = True
    assert_false(sensor_material_matches(source, cached, NO_TEXTURE))
    source = cached
    source.alpha_to_coverage = True
    assert_false(sensor_material_matches(source, cached, NO_TEXTURE))
    source = cached
    source.clip_plane_count = 1
    assert_false(sensor_material_matches(source, cached, NO_TEXTURE))
    source = cached
    source.clip_intersection = True
    assert_false(sensor_material_matches(source, cached, NO_TEXTURE))
    source = cached
    source.clip_shadows = True
    assert_false(sensor_material_matches(source, cached, NO_TEXTURE))
    source = cached
    source.set_clipping_planes([Plane(Vector3(1, 0, 0), 2)])
    cached.set_clipping_planes([Plane(Vector3(1, 0, 0), 3)])
    assert_false(sensor_material_matches(source, cached, NO_TEXTURE))
    cached = source
    assert_true(sensor_material_matches(source, cached, NO_TEXTURE))
    # These fields cannot affect a flat semantic/depth override.
    source.color = Color(90, 80, 70)
    source.roughness = 0.25
    assert_true(sensor_material_matches(source, cached, NO_TEXTURE))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
