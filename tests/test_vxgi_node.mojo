# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `VXGINode`: the settings it refuses, the numbers
its pixels read, the occlusion and irradiance it gathers from a drawn
frame, its debug views, and the frame it lays them over."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.light import directional_light
from lights.vxgi_cone_tracer import UNBOUNDED, floats_of, half_rounded
from lights.vxgi_volume import VXGI_PI
from materials.material import Material
from math.bounds import Box3
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.screen_space import DepthView
from postprocessing.vxgi_node import (
    PARAM_CONES,
    PARAM_FRAME,
    PARAM_HEIGHT,
    PARAM_TAN_HALF,
    PARAM_TRACE_DISTANCE,
    PARAM_WORLD,
    VXGINode,
    VXGI_DEBUG_OFF,
    VXGI_DEBUG_OPACITY,
    VXGI_DEBUG_RADIANCE,
    VXGI_PARAMS,
    VxgiDebug,
    VxgiFrame,
    vxgi_light,
    vxgi_pixel,
)
from render.framebuffer import Color, FloatColor
from render.target import (
    FLOAT_TARGET,
    OUTPUT_COLOR,
    OUTPUT_NORMAL,
    RenderTarget,
    TargetOutput,
)
from renderers.renderer import Renderer
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


comptime SIZE = 12
comptime WHITE = Color(255, 255, 255)


def quad(
    a: Vector3, b: Vector3, c: Vector3, d: Vector3
) raises -> BufferGeometry:
    """Return two triangles, `a b c` and `a c d`."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION,
        BufferAttribute(
            [a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, d.x, d.y, d.z], 3
        ),
    )
    geometry.set_index([0, 1, 2, 0, 2, 3])
    return geometry^


def a_camera() raises -> PerspectiveCamera:
    """Return a camera looking into the corner of the floor and the wall."""
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(1.5, 1.2, 1.5), Vector3(-0.2, 0.3, -0.2))
    return camera^


def a_corner(mut assets: Assets) raises -> Scene:
    """Return a white floor and a white wall at x = -0.5, lit by a sun
    overhead."""
    var scene = Scene()
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                quad(
                    Vector3(-1, 0, -1),
                    Vector3(-1, 0, 1),
                    Vector3(1, 0, 1),
                    Vector3(1, 0, -1),
                )
            ),
            assets.materials.add(Material(WHITE)),
            scene.add(Object3D()),
        )
    )
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                quad(
                    Vector3(-0.5, 0, -1),
                    Vector3(-0.5, 1, -1),
                    Vector3(-0.5, 1, 1),
                    Vector3(-0.5, 0, 1),
                )
            ),
            assets.materials.add(Material(WHITE)),
            scene.add(Object3D()),
        )
    )
    var lamp = Object3D()
    lamp.set_position(0, 5, 0)
    scene.add_light(directional_light(WHITE, scene.add(lamp^)))
    scene.update()
    return scene^


def drawn(scene: Scene, assets: Assets) raises -> RenderTarget:
    """Return the scene drawn with its normals."""
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var outputs: List[TargetOutput] = [OUTPUT_COLOR, OUTPUT_NORMAL]
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET, outputs)
    renderer.render_into(target, scene, assets, a_camera())
    return target^


def view_of(target: RenderTarget) raises -> DepthView:
    """Return the target's depth seen through the camera."""
    return DepthView(
        target.depth,
        SIZE,
        SIZE,
        a_camera().projection_matrix(),
        Length(0.1, METER),
        Length(20.0, METER),
        target.depth_mode,
        target.normals,
    )


def world_of() raises -> Matrix4:
    """Return the camera's world matrix."""
    var world = a_camera().view_matrix()
    world.invert()
    return world^


def flat_view(depth: Float32) raises -> DepthView:
    """Return a view of one depth everywhere, facing the camera."""
    var ndc = List[Float32](length=SIZE * SIZE, fill=depth * 2 - 1)
    var normals = List[Vector3](length=SIZE * SIZE, fill=Vector3(0, 0, 1))
    return DepthView(
        ndc,
        SIZE,
        SIZE,
        a_camera().projection_matrix(),
        Length(0.1, METER),
        Length(20.0, METER),
        normals=normals,
    )


def gathered_corner(mut node: VXGINode, frame_id: Int = 0) raises -> VxgiFrame:
    """Return the pass over the corner."""
    var assets = Assets()
    var scene = a_corner(assets)
    var target = drawn(scene, assets)
    return node.render(view_of(target), world_of(), scene, assets, frame_id)


def test_a_debug_view_is_one_of_three() raises:
    assert_true(VXGI_DEBUG_OFF.is_valid())
    assert_true(VXGI_DEBUG_RADIANCE.is_valid())
    assert_true(VXGI_DEBUG_OPACITY.is_valid())
    assert_false(VxgiDebug(3).is_valid())


def test_a_pass_refuses_settings_it_cannot_use() raises:
    var node = VXGINode()
    node.validate()
    node.cone_count = 0
    with assert_raises(contains="at least one cone"):
        node.validate()
    var apertures: List[Float32] = [0, 180, nan[DType.float32]()]
    for aperture in apertures:
        node = VXGINode()
        node.cone_angle = Angle(aperture, DEGREE)
        with assert_raises(contains="between 0 and 180"):
            node.validate()
    for field in range(5):
        node = VXGINode()
        var bad = nan[DType.float32]()
        if field == 0:
            node.gi_intensity = bad
        elif field == 1:
            node.ao_intensity = bad
        elif field == 2:
            node.ao_min_visibility = bad
        elif field == 3:
            node.normal_offset = bad
        else:
            node.debug_level = bad
        with assert_raises(contains="must be finite"):
            node.validate()
    node = VXGINode()
    node.ao_distance = Length(-1.0, METER)
    with assert_raises(contains="occlusion distance"):
        node.validate()
    node.ao_distance = Length(nan[DType.float32](), METER)
    with assert_raises(contains="occlusion distance"):
        node.validate()
    node = VXGINode()
    node.debug = VxgiDebug(3)
    with assert_raises(contains="none of the three"):
        node.validate()


def test_the_numbers_hold_the_matrices_and_the_settings() raises:
    var node = VXGINode()
    var world = world_of()
    var params = node.params(flat_view(0.5), world, 65)
    assert_equal(len(params), VXGI_PARAMS)
    assert_equal(params[PARAM_WORLD + 12], world.elements[12])
    assert_equal(params[PARAM_CONES], 3)
    # tan(20 degrees).
    assert_almost_equal(params[PARAM_TAN_HALF], 0.36397023, atol=1e-6)
    # The noise cycles over 64 frames.
    assert_equal(params[PARAM_FRAME], 1)
    assert_equal(params[PARAM_TRACE_DISTANCE], UNBOUNDED)
    assert_equal(params[PARAM_HEIGHT], SIZE)
    node.use_temporal_filtering = False
    assert_equal(node.params(flat_view(0.5), world, 65)[PARAM_FRAME], 0)


def test_an_empty_volume_leaves_the_light_open_and_dark() raises:
    var node = VXGINode(8)
    var scene = Scene()
    scene.update()
    var frame = node.render(flat_view(0.5), world_of(), scene, Assets())
    assert_equal(len(frame.ao), SIZE * SIZE)
    for slot in range(SIZE * SIZE):
        assert_equal(frame.ao[slot], 1)
        assert_equal(frame.gi[slot].r, 0)
        assert_equal(frame.gi[slot].a, 1)


def test_a_pixel_with_no_surface_keeps_the_white_clear() raises:
    var node = VXGINode(8)
    var scene = Scene()
    scene.update()
    var frame = node.render(flat_view(1), world_of(), scene, Assets())
    assert_equal(frame.ao[0], 1)
    assert_equal(frame.gi[0].r, 1)
    assert_equal(frame.gi[0].b, 1)


def test_the_corner_gathers_light_bounced_from_the_floor() raises:
    var node = VXGINode(8)
    var frame = gathered_corner(node)
    var lit = 0
    for slot in range(SIZE * SIZE):
        var ao = frame.ao[slot]
        assert_true(ao >= 0 and ao <= 1)
        var gi = frame.gi[slot].r
        if gi > 0.01 and gi < 1:
            lit += 1
    assert_true(lit > 10)
    # Some occlusion where the floor meets the wall.
    var darkest = Float32(1)
    for slot in range(SIZE * SIZE):
        darkest = min(darkest, frame.ao[slot])
    assert_true(darkest < 0.9)


def test_the_noise_moves_with_the_frame_and_cycles() raises:
    var node = VXGINode(8)
    var first = gathered_corner(node, 0)
    var cycled = gathered_corner(node, 64)
    var moved = gathered_corner(node, 5)
    var differs = 0
    for slot in range(SIZE * SIZE):
        assert_equal(first.gi[slot].r, cycled.gi[slot].r)
        if first.gi[slot].r != moved.gi[slot].r:
            differs += 1
    assert_true(differs > 0)
    node.use_temporal_filtering = False
    var still = gathered_corner(node, 5)
    for slot in range(SIZE * SIZE):
        assert_equal(first.gi[slot].r, still.gi[slot].r)


def test_the_debug_views_show_the_voxels_along_the_view() raises:
    var node = VXGINode(8)
    node.debug = VXGI_DEBUG_RADIANCE
    var frame = gathered_corner(node)
    # The floor's voxels hold the light over pi, times a half, stored as
    # a half float and read back over their half.
    var floor = half_rounded(Float32(1) / VXGI_PI * 0.5) / 0.5
    var seen = 0
    for slot in range(SIZE * SIZE):
        assert_equal(frame.ao[slot], 1)
        if abs(frame.gi[slot].r - floor) < 1e-3:
            seen += 1
    assert_true(seen > 5)
    node.debug = VXGI_DEBUG_OPACITY
    frame = gathered_corner(node)
    var opaque = 0
    for slot in range(SIZE * SIZE):
        if frame.gi[slot].g == 1:
            opaque += 1
    assert_true(opaque > 5)


def test_a_debug_view_of_a_volume_elsewhere_is_black() raises:
    var node = VXGINode(8)
    node.debug = VXGI_DEBUG_OPACITY
    node.volume.bounds = Box3(Vector3(10, 10, 10), Vector3(11, 11, 11))
    var frame = gathered_corner(node)
    var assets = Assets()
    var scene = a_corner(assets)
    var target = drawn(scene, assets)
    for slot in range(SIZE * SIZE):
        if target.depth[slot] < 1:
            assert_equal(frame.gi[slot].r, 0)


def test_a_pixel_through_a_flat_matrix_keeps_its_point() raises:
    # A camera matrix of zeros gives w of zero: the point is not divided.
    var node = VXGINode(8)
    var scene = Scene()
    scene.update()
    node.volume.update(scene, Assets())
    var params = node.params(flat_view(0.5), Matrix4(), 0)
    for at in range(16):
        params[PARAM_WORLD + at] = 0
    var pixel = vxgi_pixel(
        node.volume.grid,
        floats_of(node.volume.opacity),
        floats_of(node.volume.radiance),
        floats_of(params),
        0.5,
        Vector3(0, 0, 1),
        1,
        1,
    )
    assert_equal(pixel[3], 1)
    _ = params^
    _ = node^


def test_a_pass_needs_one_normal_a_pixel() raises:
    var node = VXGINode(8)
    with assert_raises(contains="one normal a pixel"):
        _ = node.gather(flat_view(0.5), List[Vector3](), world_of(), 0)


def test_the_pass_is_laid_over_the_frame() raises:
    var frame = RenderTarget(2, 2, Color(0, 0, 0), FLOAT_TARGET)
    frame.colors[0] = FloatColor(0.4, 0.2, 0.1, 1)
    var gathered = VxgiFrame(2, 2)
    for _ in range(4):
        gathered.add(SIMD[DType.float32, 4](VXGI_PI, 0, 0, 0.5))
    var diffuse = List[FloatColor](length=4, fill=FloatColor(1, 1, 1, 1))
    vxgi_light(frame, gathered, diffuse)
    var pixel = frame.colors[0]
    assert_almost_equal(pixel.r, 1.2, atol=1e-6)
    assert_almost_equal(pixel.g, 0.1, atol=1e-6)
    assert_almost_equal(pixel.b, 0.05, atol=1e-6)
    assert_equal(pixel.a, 1)


def test_a_pass_of_another_size_is_refused() raises:
    var frame = RenderTarget(2, 2, Color(0, 0, 0), FLOAT_TARGET)
    var diffuse = List[FloatColor](length=4, fill=FloatColor(1, 1, 1, 1))
    with assert_raises(contains="frame's size"):
        vxgi_light(frame, VxgiFrame(3, 2), diffuse)
    with assert_raises(contains="frame's size"):
        vxgi_light(frame, VxgiFrame(2, 3), diffuse)
    with assert_raises(contains="one diffuse color a pixel"):
        vxgi_light(frame, VxgiFrame(2, 2), List[FloatColor]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
