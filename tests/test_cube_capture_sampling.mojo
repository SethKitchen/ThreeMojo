# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cube captures have one sampling owner and average linear light, #397."""

from cameras.cube_camera import CubeCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from materials.material import DOUBLE_SIDE, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.antialias import SUPERSAMPLE, downsample
from render.cube_texture import FACE_COUNT, face_forward, face_up
from render.framebuffer import Color, FloatColor
from render.layered_target import cube_render_target
from render.rect import Rect
from render.srgb import SRGB
from render.target import FLOAT_TARGET, RenderTarget, sample_grid
from render.texture import FLOAT_TYPE
from render.tonemap import REINHARD_TONE_MAPPING
from renderers.renderer import Renderer
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import Length, METER

comptime SIZE = 8
comptime CLEAR = Color(0, 0, 0)


def _camera(size: Int = SIZE) raises -> CubeCamera:
    """Return six face cameras centered at the origin."""
    return CubeCamera(Length(0.1, METER), Length(10, METER), size)


def _triangles(mut assets: Assets, radiance: Float32 = 1) raises -> Scene:
    """Put a slanted emissive triangle wholly inside each face's view."""
    var scene = Scene()
    var paint = assets.materials.add(
        Material(
            CLEAR,
            emissive=Color(255, 255, 255),
            emissive_intensity=radiance,
            side=DOUBLE_SIDE,
        )
    )
    for face in range(FACE_COUNT):
        var forward = face_forward(face)
        var up = face_up(face)
        var right = forward
        right.cross(up)
        var positions = List[Float32]()
        for point in [
            Vector3(-1.6, -1.4, 2),
            Vector3(1.3, -0.9, 2),
            Vector3(-1.2, 1.5, 2),
        ]:
            var world = right * point.x + up * point.y + forward * point.z
            positions.append(world.x)
            positions.append(world.y)
            positions.append(world.z)
        var geometry = BufferGeometry()
        geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
        scene.add_mesh(
            Mesh(assets.geometries.add(geometry^), paint, scene.add(Object3D()))
        )
    scene.update()
    return scene^


def _samples(
    scene: Scene, assets: Assets, face: Int, grid: Int
) raises -> RenderTarget:
    """Draw an explicit large face with no renderer or target sampling."""
    var renderer = Renderer(SIZE * grid, SIZE * grid)
    renderer.background = CLEAR
    var target = RenderTarget(SIZE * grid, SIZE * grid, CLEAR, FLOAT_TARGET)
    renderer.render_into(
        target, scene, assets, _camera().face_camera(face, scene)
    )
    return target^


def _average(
    target: RenderTarget, x: Int, y: Int, grid: Int
) raises -> FloatColor:
    """Average an opaque fixture's samples without either resolve helper."""
    var sum = Float32(0)
    for dy in range(grid):
        for dx in range(grid):
            sum += target.color_at(x * grid + dx, y * grid + dy).r
    var value = sum / Float32(grid * grid)
    return FloatColor(value, value, value, 1)


def _assert_color(got: Color, expected: Color) raises:
    """Compare all four stored channels without a color-space conversion."""
    assert_equal(got.r, expected.r)
    assert_equal(got.g, expected.g)
    assert_equal(got.b, expected.b)
    assert_equal(got.a, expected.a)


def test_byte_cube_uses_renderer_antialias_on_every_face() raises:
    var assets = Assets()
    var scene = _triangles(assets)
    # Capture size and bounds belong to the camera, not this renderer.
    var renderer = Renderer(19, 11)
    renderer.background = CLEAR
    renderer.viewport = Rect(1, 2, 3, 4)
    renderer.scissor = Rect(1, 1, 1, 1)
    renderer.scissor_test = True
    for enabled in [False, True]:
        renderer.antialias = enabled
        var cube = renderer.render_cube(scene, assets, _camera())
        assert_equal(cube.size, SIZE)
        var grid = 1
        if enabled:
            grid = SUPERSAMPLE
        for face in range(FACE_COUNT):
            var drawn = _samples(scene, assets, face, grid)
            var between = 0
            for y in range(SIZE):
                for x in range(SIZE):
                    var expected = _average(drawn, x, y, grid).encode()
                    var got = cube.face(face).texel(x, y)
                    _assert_color(got, expected)
                    if got.r > 0 and got.r < 255:
                        between += 1
            assert_equal(cube.face(face).color_space, SRGB)
            if enabled:
                assert_true(between > 0, "the face has no sampled edge")
            else:
                assert_equal(between, 0)
        assert_equal(renderer.antialias, enabled)
        assert_equal(renderer.viewport, Rect(1, 2, 3, 4))
        assert_equal(renderer.scissor, Rect(1, 1, 1, 1))
        assert_true(renderer.scissor_test)
        assert_equal(renderer.render_scale, 1)
        assert_equal(renderer.info().frame, 0)


def test_layered_cube_samples_are_independent_of_renderer_antialias() raises:
    var assets = Assets()
    var scene = _triangles(assets)
    var renderer = Renderer(19, 11)
    renderer.background = CLEAR
    renderer.viewport = Rect(1, 2, 3, 4)
    renderer.scissor = Rect(1, 1, 1, 1)
    renderer.scissor_test = True
    for samples in [0, 1, 4, 9, 16]:
        var grid = sample_grid(samples)
        for enabled in [False, True]:
            renderer.antialias = enabled
            var cube = cube_render_target(SIZE, CLEAR, FLOAT_TARGET, samples)
            # This camera size deliberately differs from the target size.
            renderer.render_cube_into(cube, scene, assets, _camera(SIZE + 3))
            for face in range(FACE_COUNT):
                var drawn = _samples(scene, assets, face, grid)
                var between = 0
                ref image = cube.image(face)
                assert_equal(image.samples, samples)
                assert_equal(image.width, SIZE)
                assert_equal(image.type, FLOAT_TARGET)
                for y in range(SIZE):
                    for x in range(SIZE):
                        var expected = _average(drawn, x, y, grid)
                        var got = image.color_at(x, y)
                        assert_almost_equal(got.r, expected.r, atol=1e-6)
                        assert_almost_equal(got.g, expected.g, atol=1e-6)
                        assert_almost_equal(got.b, expected.b, atol=1e-6)
                        assert_equal(got.a, expected.a)
                        var nearest = inf[DType.float32]()
                        for dy in range(grid):
                            for dx in range(grid):
                                nearest = min(
                                    nearest,
                                    drawn.depth_at(
                                        x * grid + dx, y * grid + dy
                                    ),
                                )
                        assert_equal(image.depth_at(x, y), nearest)
                        if got.r > 0 and got.r < 1:
                            between += 1
                if samples > 1:
                    assert_true(between > 0, "the face has no sampled edge")
                else:
                    assert_equal(between, 0)
            assert_equal(renderer.antialias, enabled)
            assert_equal(renderer.viewport, Rect(1, 2, 3, 4))
            assert_equal(renderer.scissor, Rect(1, 1, 1, 1))
            assert_true(renderer.scissor_test)
            assert_equal(renderer.render_scale, 1)
            assert_equal(renderer.info().frame, 0)


def test_cube_sampling_fixture_distinguishes_an_extra_sampling_pass() raises:
    var assets = Assets()
    var scene = _triangles(assets)
    # A comparison with the requested grid must fail if antialias doubles it.
    for grid in [1, 2, 3, 4]:
        var drawn = _samples(scene, assets, 0, grid)
        var doubled = _samples(scene, assets, 0, grid * SUPERSAMPLE)
        var changed = 0
        for y in range(SIZE):
            for x in range(SIZE):
                if _average(drawn, x, y, grid) != _average(
                    doubled, x, y, grid * SUPERSAMPLE
                ):
                    changed += 1
        assert_true(changed > 0, "the fixture cannot detect double sampling")


def test_both_cube_apis_average_hdr_light_before_display_conversion() raises:
    var assets = Assets()
    var scene = _triangles(assets, radiance=4)
    var renderer = Renderer(SIZE, SIZE)
    renderer.background = CLEAR
    renderer.antialias = True
    renderer.tone_mapping = REINHARD_TONE_MAPPING
    renderer.tone_mapping_exposure = 7
    var bytes = renderer.render_cube(scene, assets, _camera())
    var target = cube_render_target(SIZE, CLEAR, FLOAT_TARGET, samples=4)
    renderer.render_cube_into(target, scene, assets, _camera())
    var floats = target.cube_texture()
    for face in range(FACE_COUNT):
        var drawn = _samples(scene, assets, face, SUPERSAMPLE)
        var encoded_first = downsample(drawn.resolve(), SUPERSAMPLE)
        var quarter_covered = 0
        var hdr = 0
        for y in range(SIZE):
            for x in range(SIZE):
                var expected = _average(drawn, x, y, SUPERSAMPLE)
                assert_true(target.image(face).color_at(x, y) == expected)
                _assert_color(bytes.face(face).texel(x, y), expected.encode())
                if expected.r == 1:
                    quarter_covered += 1
                    assert_equal(bytes.face(face).texel(x, y).r, UInt8(255))
                    assert_equal(encoded_first.get_pixel(x, y).r, UInt8(137))
                if expected.r > 1:
                    hdr += 1
        assert_true(quarter_covered > 0, "no four-to-one HDR sample")
        assert_true(hdr > 0, "the capture did not retain HDR light")
        assert_equal(floats.face(face).texel_type, FLOAT_TYPE)
        # Float texture readback also retains the resolved HDR light.
        for at in range(SIZE * SIZE):
            assert_equal(
                floats.face(face).data[at * 4], target.image(face).colors[at].r
            )
    assert_equal(renderer.tone_mapping, REINHARD_TONE_MAPPING)
    assert_equal(renderer.tone_mapping_exposure, Float32(7))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
