# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The CARLA renderer's light passes and sky readers, on the inputs they
refuse and the edges they return early at.

The passes themselves are drawn by the whole frames of
`test_carla_render_scene`; this suite holds what a frame never hands
them: a frame with no normals, lists of the wrong length, a strength out
of range, a stride of zero, a fog with nothing in it, a sun below the
horizon, and byte textures where float ones belong.
"""

from cameras.perspective_camera import PerspectiveCamera
from extensions.carla.render_light import (
    DaylightSplit,
    ambient_occlusion,
    apply_ambient_occlusion,
    apply_cloud_shadows,
    direct_shares,
    fog_light_shafts,
    shaft_share,
    sun_maps,
    town_gtao,
)
from extensions.carla.render_post import ViewRays
from extensions.carla.render_sky import (
    cloud_shadow_density,
    hdri_sun_azimuth,
    hemisphere_illuminance,
)
from extensions.carla.render_weather import height_fog
from extensions.carla.weather import weather_preset
from lights.shadow import ShadowMap
from math.matrix4 import Matrix4
from math.noise import ImprovedNoise
from math.vector3 import Vector3
from postprocessing.screen_space import DepthView
from render.cube_texture import cube_texture_from
from render.framebuffer import Color
from render.png import DecodedImage, decode as decode_png
from render.srgb import LINEAR
from render.target import RenderTarget
from render.texture import BILINEAR, IGNORED, REPEAT, Texture
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, Angle, Length


def _frame() raises -> RenderTarget:
    """A frame of four pixels with no normals."""
    return RenderTarget(2, 2, Color(0, 0, 0))


def _rays() -> ViewRays:
    return ViewRays(2, 2, Matrix4(), Matrix4())


def _light() -> DaylightSplit:
    return DaylightSplit(1, 2, 3, Vector3(0, 1, 0))


def test_a_daylight_split_writes_its_parts() raises:
    assert_true(String(_light()).startswith("DaylightSplit(sun=1"))


def test_the_sun_keeps_its_own_maps() raises:
    var depths: List[Float32] = [1.0]
    var map = ShadowMap(0, 1, SIMD[DType.float32, 16](0), depths^, 0, 0, 1)
    var maps = List[ShadowMap]()
    maps.append(map^)
    var sun: List[Int] = [0]
    assert_equal(len(sun_maps(maps, sun)), 1)
    assert_equal(len(sun_maps(maps, List[Int]())), 0)
    assert_equal(len(sun_maps(List[ShadowMap](), sun)), 0)


def test_the_passes_refuse_what_they_cannot_read() raises:
    var frame = _frame()
    var rays = _rays()
    with assert_raises(contains="normals"):
        _ = direct_shares(frame, rays, List[ShadowMap](), _light())
    var camera = PerspectiveCamera(
        Angle(60, DEGREE), 1, Length(0.1, METER), Length(100, METER)
    )
    var depth = DepthView(
        List[Float32](length=4, fill=0.5),
        2,
        2,
        camera.projection_matrix(),
        Length(0.1, METER),
        Length(100, METER),
    )
    with assert_raises(contains="normals"):
        _ = ambient_occlusion(frame, depth, town_gtao())
    var four = List[Float32](length=4, fill=1.0)
    var one = List[Float32](length=1, fill=1.0)
    with assert_raises(contains="one value per pixel"):
        apply_ambient_occlusion(frame, one, four, 0.5)
    with assert_raises(contains="one value per pixel"):
        apply_ambient_occlusion(frame, four, one, 0.5)
    with assert_raises(contains="strength"):
        apply_ambient_occlusion(frame, four, four, 2)
    with assert_raises(contains="one share per pixel"):
        apply_cloud_shadows(
            frame, rays, one, ImprovedNoise(), Vector3(0, 1, 0), 0.5
        )
    var weather = weather_preset("ClearNoon")
    with assert_raises(contains="stride"):
        _ = fog_light_shafts(
            frame,
            rays,
            height_fog(weather),
            List[ShadowMap](),
            Vector3(0, 1, 0),
            stride=0,
        )


def test_a_fog_with_nothing_in_it_lets_the_sun_through() raises:
    var weather = weather_preset("ClearNoon")
    weather.fog_density = 0
    var share = shaft_share(
        _rays(),
        List[ShadowMap](),
        height_fog(weather),
        0,
        0,
        0.5,
        Vector3(0, 1, 0),
        4,
    )
    assert_almost_equal(share, 1, atol=1e-6)


def test_the_sky_readers_refuse_byte_textures() raises:
    # No cloud stands between a point and a sun below the horizon.
    assert_equal(
        cloud_shadow_density(
            ImprovedNoise(), Vector3(0, 0, 0), Vector3(0, -1, 0), 0.5
        ),
        0,
    )
    var faces = List[DecodedImage]()
    for _ in range(6):
        faces.append(decode_png(Path("assets/gltf/checker.png").read_bytes()))
    var cube = cube_texture_from(faces^)
    with assert_raises(contains="float textures"):
        _ = hemisphere_illuminance(cube)
    var texel: List[UInt8] = [0, 0, 0, 255]
    var panorama = Texture(
        1, 1, texel^, REPEAT, BILINEAR, LINEAR, False, IGNORED
    )
    with assert_raises(contains="float texture"):
        _ = hdri_sun_azimuth(panorama)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
