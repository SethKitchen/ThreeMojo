# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the screen-space passes: the depth view against the camera
that drew it, SSAO, SAO, SSR and the outline against worked-out answers,
and all four in the composer."""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.layers import Layers
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import box
from geometries.plane import plane
from lights.light import directional_light
from materials.material import Material
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.composer import (
    OUTLINE,
    SAO,
    SSAO,
    SSR,
    EffectComposer,
    Pass,
    PassKind,
    check_pass,
    outline_pass,
    render_pass,
    sao_pass,
    ssao_pass,
    ssr_pass,
)
from postprocessing.screen_space import (
    BEAUTY_OUTPUT,
    BLUR_OUTPUT,
    DEFAULT_OUTPUT,
    DEPTH_OUTPUT,
    EFFECT_OUTPUT,
    NORMAL_OUTPUT,
    DepthView,
    OutlineSettings,
    SaoSettings,
    ScreenSpaceOutput,
    SsaoSettings,
    SsrSettings,
    blur_weights,
    check_outline,
    check_sao,
    check_ssao,
    check_ssr,
    depth_limited_blur,
    glsl_rand,
    multiply_light,
    outline_light,
    outline_mask,
    sao_light,
    sao_occlusion,
    sao_sample_occlusion,
    ssao_blur,
    ssao_kernel,
    ssao_light,
    ssao_noise,
    ssao_occlusion,
    ssr_blur,
    ssr_light,
    ssr_reflections,
)
from render.framebuffer import Color, FloatColor
from render.target import RenderTarget
from renderers.renderer import Renderer
from std.math import exp, inf, nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, METER, SECOND

comptime WIDTH = 32
comptime HEIGHT = 24
comptime BLACK = Color(0, 0, 0)
comptime TOLERANCE = Float64(1e-4)


def meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


def a_camera() raises -> PerspectiveCamera:
    """Return a camera looking into the corner of the room from the front."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        meters(0.1),
        meters(20.0),
    )
    camera.place(Vector3(0, 0.6, 3), Vector3(0, -0.2, 0))
    return camera^


def a_flat_camera() raises -> OrthographicCamera:
    """Return an orthographic camera looking into the room from the front."""
    var camera = OrthographicCamera(
        meters(-2),
        meters(2),
        meters(1.5),
        meters(-1.5),
        meters(0.1),
        meters(20),
    )
    camera.place(Vector3(0, 0.6, 3), Vector3(0, -0.2, 0))
    return camera^


def room(mut assets: Assets) raises -> Scene:
    """Return a floor, a back wall, a box on the floor on layers zero and
    one, and a post on layer zero alone in front of the box's right side,
    under a lamp over the camera."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 2, 3)
    var lamp_node = scene.add(lamp^)
    scene.add_light(
        directional_light(Color(255, 255, 255), lamp_node, Float32(pi))
    )
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    var red = assets.materials.add(Material(Color(255, 40, 40)))
    var sheet = assets.geometries.add(plane(meters(4), meters(4)))
    var floor = Object3D()
    floor.set_position(0, -0.5, 0)
    floor.rotate_x(Angle(-90.0, DEGREE))
    scene.add_mesh(Mesh(sheet, paint, scene.add(floor^)))
    var wall = Object3D()
    wall.set_position(0, 0, -1)
    scene.add_mesh(Mesh(sheet, paint, scene.add(wall^)))
    var cube = assets.geometries.add(box(meters(0.6), meters(0.6), meters(0.6)))
    var block = Object3D()
    block.set_position(0, -0.2, 0)
    block.layers.enable(1)
    scene.add_mesh(Mesh(cube, red, scene.add(block^)))
    var stick = assets.geometries.add(box(meters(0.1), meters(1), meters(0.1)))
    var post = Object3D()
    post.set_position(0.25, -0.2, 0.6)
    scene.add_mesh(Mesh(stick, paint, scene.add(post^)))
    scene.update()
    return scene^


def a_renderer() raises -> Renderer:
    """Return a renderer of the test size on a black background."""
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(BLACK)
    return renderer^


def drawn(camera: PerspectiveCamera) raises -> RenderTarget:
    """Return the room drawn through `camera`."""
    var renderer = a_renderer()
    var assets = Assets()
    var scene = room(assets)
    var target = RenderTarget(WIDTH, HEIGHT, BLACK)
    renderer.render_into(target, scene, assets, camera)
    return target^


def view_of(
    target: RenderTarget, camera: PerspectiveCamera
) raises -> DepthView:
    """Return a target's depth through the camera that drew it."""
    return DepthView(
        target.depth,
        target.width,
        target.height,
        camera.projection_matrix(),
        meters(camera.near_distance()),
        meters(camera.far_distance()),
    )


def flat_view(
    width: Int, height: Int, depth: List[Float32]
) raises -> DepthView:
    """Return a hand-built depth through the orthographic camera."""
    var camera = a_flat_camera()
    return DepthView(
        depth,
        width,
        height,
        camera.projection_matrix(),
        meters(0.1),
        meters(20),
    )


def total_light(frame: RenderTarget) -> Float32:
    """Return the sum of every channel of every pixel but alpha."""
    var sum = Float32(0)
    for color in frame.colors:
        sum += color.r + color.g + color.b
    return sum


def same(a: Color, b: Color) -> Bool:
    """Return True if two colors match in every channel."""
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a


def count_changed(a: RenderTarget, b: RenderTarget) -> Int:
    """Return how many pixels differ in light between two targets."""
    var count = 0
    for slot in range(len(a.colors)):
        if a.colors[slot] != b.colors[slot]:
            count += 1
    return count


# --- the kinds, the builders and the checks ----------------------------------


def test_the_four_new_kinds_and_their_builders() raises:
    assert_true(SSAO.is_valid())
    assert_true(SAO.is_valid())
    assert_true(SSR.is_valid())
    assert_true(OUTLINE.is_valid())
    assert_false(PassKind(19).is_valid())
    var ssao = ssao_pass()
    assert_equal(ssao.kind, SSAO)
    assert_equal(ssao.ssao.kernel_radius.value, Float32(8))
    assert_equal(ssao.ssao.kernel_size, 32)
    assert_almost_equal(ssao.ssao.min_distance, Float32(0.005))
    assert_almost_equal(ssao.ssao.max_distance, Float32(0.1))
    assert_equal(ssao.ssao.output, DEFAULT_OUTPUT)
    var sao = sao_pass()
    assert_equal(sao.kind, SAO)
    assert_almost_equal(sao.sao.bias, Float32(0.5))
    assert_almost_equal(sao.sao.intensity, Float32(0.18))
    assert_equal(sao.sao.scale, Float32(1))
    assert_equal(sao.sao.kernel_radius, Float32(100))
    assert_equal(sao.sao.min_resolution, Float32(0))
    assert_true(sao.sao.blur)
    assert_equal(sao.sao.blur_radius, 8)
    assert_equal(sao.sao.blur_std_dev, Float32(4))
    assert_almost_equal(sao.sao.blur_depth_cutoff, Float32(0.01))
    var ssr = ssr_pass()
    assert_equal(ssr.kind, SSR)
    assert_equal(ssr.ssr.opacity, Float32(0.5))
    assert_equal(ssr.ssr.max_distance.value, Float32(180))
    assert_almost_equal(ssr.ssr.thickness.value, Float32(0.018))
    assert_false(ssr.ssr.infinite_thick)
    assert_true(ssr.ssr.distance_attenuation)
    assert_true(ssr.ssr.fresnel)
    assert_true(ssr.ssr.blur)
    var outline = outline_pass(Layers(UInt32(2)))
    assert_equal(outline.kind, OUTLINE)
    assert_equal(outline.outline.selection, Layers(UInt32(2)))
    assert_equal(outline.outline.edge_strength, Float32(3))
    assert_equal(outline.outline.edge_thickness, Float32(1))
    assert_equal(outline.outline.edge_glow, Float32(0))
    assert_almost_equal(outline.outline.hidden_edge_color.g, Float32(0.04))
    assert_equal(OutlineSettings().selection.mask, UInt32(0))
    # Each builder takes its settings.
    assert_equal(ssao_pass(meters(2), 0.01, 0.2).ssao.kernel_radius.value, 2)
    assert_false(sao_pass(0.5, 2, 20, False).sao.blur)
    assert_equal(ssr_pass(1, meters(5), meters(0.1)).ssr.opacity, 1)
    assert_equal(outline_pass(Layers(), 1, 2).outline.edge_thickness, 2)


def test_the_six_outputs_are_valid_and_a_seventh_is_not() raises:
    assert_true(DEFAULT_OUTPUT.is_valid())
    assert_true(EFFECT_OUTPUT.is_valid())
    assert_true(BLUR_OUTPUT.is_valid())
    assert_true(BEAUTY_OUTPUT.is_valid())
    assert_true(DEPTH_OUTPUT.is_valid())
    assert_true(NORMAL_OUTPUT.is_valid())
    assert_false(ScreenSpaceOutput(6).is_valid())


def test_ssao_settings_no_pass_could_run_are_refused() raises:
    check_ssao(SsaoSettings())
    var bad = SsaoSettings()
    bad.output = ScreenSpaceOutput(6)
    with assert_raises():
        check_ssao(bad)
    bad = SsaoSettings()
    bad.kernel_radius = meters(inf[DType.float32]())
    with assert_raises():
        check_ssao(bad)
    bad = SsaoSettings()
    bad.min_distance = nan[DType.float32]()
    with assert_raises():
        check_ssao(bad)
    bad = SsaoSettings()
    bad.max_distance = nan[DType.float32]()
    with assert_raises():
        check_ssao(bad)
    bad = SsaoSettings()
    bad.kernel_radius = meters(-1)
    with assert_raises():
        check_ssao(bad)
    bad = SsaoSettings()
    bad.min_distance = -1
    with assert_raises():
        check_ssao(bad)
    bad = SsaoSettings()
    bad.max_distance = -1
    with assert_raises():
        check_ssao(bad)
    bad = SsaoSettings()
    bad.kernel_size = 0
    with assert_raises():
        check_ssao(bad)
    # The composer asks too.
    var step = ssao_pass()
    step.ssao.kernel_size = 0
    with assert_raises():
        check_pass(step)
    with assert_raises():
        _ = ssao_pass(meters(-1))


def test_sao_settings_no_pass_could_run_are_refused() raises:
    check_sao(SaoSettings())
    var bad = SaoSettings()
    bad.output = ScreenSpaceOutput(-1)
    with assert_raises():
        check_sao(bad)
    var names: List[Int] = [0, 1, 2, 3, 4, 5, 6]
    for which in names:
        bad = SaoSettings()
        var wrong = nan[DType.float32]()
        if which == 0:
            bad.bias = wrong
        elif which == 1:
            bad.intensity = wrong
        elif which == 2:
            bad.scale = wrong
        elif which == 3:
            bad.kernel_radius = wrong
        elif which == 4:
            bad.min_resolution = wrong
        elif which == 5:
            bad.blur_std_dev = wrong
        else:
            bad.blur_depth_cutoff = wrong
        with assert_raises():
            check_sao(bad)
    bad = SaoSettings()
    bad.intensity = -1
    with assert_raises():
        check_sao(bad)
    bad = SaoSettings()
    bad.min_resolution = -1
    with assert_raises():
        check_sao(bad)
    bad = SaoSettings()
    bad.blur_radius = -1
    with assert_raises():
        check_sao(bad)
    bad = SaoSettings()
    bad.blur_depth_cutoff = -1
    with assert_raises():
        check_sao(bad)
    bad = SaoSettings()
    bad.scale = 0
    with assert_raises():
        check_sao(bad)
    bad = SaoSettings()
    bad.kernel_radius = 0
    with assert_raises():
        check_sao(bad)
    bad = SaoSettings()
    bad.blur_std_dev = 0
    with assert_raises():
        check_sao(bad)
    # A negative bias is a setting three.js's controls offer.
    bad = SaoSettings()
    bad.bias = -0.5
    check_sao(bad)
    with assert_raises():
        _ = sao_pass(-1)


def test_ssr_settings_no_pass_could_run_are_refused() raises:
    check_ssr(SsrSettings())
    var bad = SsrSettings()
    bad.output = ScreenSpaceOutput(6)
    with assert_raises():
        check_ssr(bad)
    bad = SsrSettings()
    bad.opacity = nan[DType.float32]()
    with assert_raises():
        check_ssr(bad)
    bad = SsrSettings()
    bad.max_distance = meters(inf[DType.float32]())
    with assert_raises():
        check_ssr(bad)
    bad = SsrSettings()
    bad.thickness = meters(nan[DType.float32]())
    with assert_raises():
        check_ssr(bad)
    bad = SsrSettings()
    bad.opacity = -0.1
    with assert_raises():
        check_ssr(bad)
    bad = SsrSettings()
    bad.opacity = 1.1
    with assert_raises():
        check_ssr(bad)
    bad = SsrSettings()
    bad.thickness = meters(-0.1)
    with assert_raises():
        check_ssr(bad)
    bad = SsrSettings()
    bad.max_distance = meters(0)
    with assert_raises():
        check_ssr(bad)
    with assert_raises():
        _ = ssr_pass(2)


def test_outline_settings_no_pass_could_run_are_refused() raises:
    check_outline(OutlineSettings())
    var bad = OutlineSettings()
    bad.visible_edge_color = FloatColor(nan[DType.float32](), 1, 1, 1)
    with assert_raises():
        check_outline(bad)
    bad = OutlineSettings()
    bad.hidden_edge_color = FloatColor(0, -1, 0, 1)
    with assert_raises():
        check_outline(bad)
    bad = OutlineSettings()
    bad.pulse_period = Duration(-1.0, SECOND)
    with assert_raises():
        check_outline(bad)
    bad = OutlineSettings()
    bad.edge_thickness = 0
    with assert_raises():
        check_outline(bad)
    with assert_raises():
        _ = outline_pass(Layers(), -1)


# --- the depth view ----------------------------------------------------------


def test_a_depth_view_reads_window_depth_and_refuses_what_it_cannot() raises:
    var camera = a_camera()
    var projection = camera.projection_matrix()
    var depth: List[Float32] = [-1, 0, 1, inf[DType.float32]()]
    var view = DepthView(depth, 2, 2, projection, meters(0.1), meters(20))
    assert_equal(view.depth[0], Float32(0))
    assert_equal(view.depth[1], Float32(0.5))
    assert_equal(view.depth[2], Float32(1))
    assert_equal(view.depth[3], Float32(1))
    assert_true(view.perspective)
    assert_false(flat_view(2, 2, depth).perspective)
    with assert_raises():
        _ = DepthView(depth, 0, 4, projection, meters(0.1), meters(20))
    with assert_raises():
        _ = DepthView(depth, 4, 0, projection, meters(0.1), meters(20))
    with assert_raises():
        _ = DepthView(depth, 3, 2, projection, meters(0.1), meters(20))
    with assert_raises():
        _ = DepthView(
            depth, 2, 2, projection, meters(nan[DType.float32]()), meters(20)
        )
    with assert_raises():
        _ = DepthView(
            depth, 2, 2, projection, meters(0.1), meters(inf[DType.float32]())
        )
    with assert_raises():
        _ = DepthView(depth, 2, 2, projection, meters(20), meters(0.1))
    var flat = Matrix4()
    flat.elements[10] = 0
    with assert_raises():
        _ = DepthView(depth, 2, 2, flat, meters(0.1), meters(20))


def test_a_depth_view_reads_the_nearest_pixel_held_at_the_edges() raises:
    var depth: List[Float32] = [0, 0.2, 0.4, 0.6, 0.8, -0.2]
    var view = flat_view(3, 2, depth)
    # The top row is the higher v.
    assert_equal(view.slot_at(0.1, 0.9), 0)
    assert_equal(view.slot_at(0.5, 0.9), 1)
    assert_equal(view.slot_at(0.9, 0.1), 5)
    assert_equal(view.slot_at(-3, 0.9), 0)
    assert_equal(view.slot_at(4, -2), 5)
    assert_equal(view.slot_at(1, 1), 2)
    assert_almost_equal(view.depth_at(0.5, 0.1), Float32(0.9))


def test_a_depth_view_undoes_the_projection() raises:
    var camera = a_camera()
    var projection = camera.projection_matrix()
    var depth = List[Float32](length=4, fill=0)
    var view = DepthView(depth, 2, 2, projection, meters(0.1), meters(20))
    var point = Vector3(0.3, -0.2, -2.5)
    var ndc = projection.transform_point(point)
    var back = view.position(
        ndc.x * 0.5 + 0.5, ndc.y * 0.5 + 0.5, ndc.z * 0.5 + 0.5
    )
    assert_almost_equal(back.x, point.x, atol=TOLERANCE)
    assert_almost_equal(back.y, point.y, atol=TOLERANCE)
    assert_almost_equal(back.z, point.z, atol=TOLERANCE)
    assert_almost_equal(view.view_z(ndc.z * 0.5 + 0.5), point.z, atol=TOLERANCE)
    assert_almost_equal(view.linear_depth(-0.1), Float32(0), atol=TOLERANCE)
    assert_almost_equal(view.linear_depth(-20), Float32(1), atol=TOLERANCE)
    assert_almost_equal(view.view_z(0), Float32(-0.1), atol=TOLERANCE)
    assert_almost_equal(view.view_z(1), Float32(-20), atol=1e-2)


def test_normals_from_depth_face_the_camera_and_follow_the_surface() raises:
    # A flat sheet square on to an orthographic camera faces straight back.
    var depth = List[Float32](length=25, fill=0.3)
    var normal = flat_view(5, 5, depth).normal_at(2, 2)
    assert_almost_equal(normal.z, Float32(1), atol=TOLERANCE)
    # The room's floor faces up, turned by the camera's view.
    var camera = a_camera()
    var target = drawn(camera)
    var view = view_of(target, camera)
    var up = camera.view_matrix().transform_direction(Vector3(0, 1, 0))
    var floor = view.normal_at(3, HEIGHT - 2)
    assert_almost_equal(floor.dot(up), Float32(1), atol=1e-2)
    # The wall faces the camera's z.
    var back = camera.view_matrix().transform_direction(Vector3(0, 0, 1))
    var wall = view.normal_at(2, 1)
    assert_almost_equal(wall.dot(back), Float32(1), atol=1e-2)
    # Beside a step, the slope comes from the side the pixel is on.
    var step = List[Float32](length=25, fill=0.9)
    for y in range(5):
        for x in range(3, 5):
            step[y * 5 + x] = -0.9
        step[y * 5 + 2] = 0.9
    var stepped = flat_view(5, 5, step)
    assert_almost_equal(stepped.normal_at(2, 2).z, Float32(1), atol=TOLERANCE)
    assert_almost_equal(stepped.normal_at(3, 2).z, Float32(1), atol=TOLERANCE)
    var rows = List[Float32](length=25, fill=0.9)
    for x in range(5):
        rows[x] = -0.9
        rows[5 + x] = -0.9
    var ridged = flat_view(5, 5, rows)
    assert_almost_equal(ridged.normal_at(2, 1).z, Float32(1), atol=TOLERANCE)
    assert_almost_equal(ridged.normal_at(2, 2).z, Float32(1), atol=TOLERANCE)
    assert_equal(len(ridged.normals()), 25)


# --- SSAO --------------------------------------------------------------------


def test_the_ssao_kernel_crowds_toward_the_surface_above_it() raises:
    var kernel = ssao_kernel(16, 7)
    assert_equal(len(kernel), 16)
    assert_almost_equal(kernel[0].length(), Float32(0.1), atol=TOLERANCE)
    for index in range(16):
        var scale = Float32(index) / 16
        var expected = 0.1 + 0.9 * scale * scale
        assert_almost_equal(kernel[index].length(), expected, atol=TOLERANCE)
        assert_true(kernel[index].z >= 0)
    # The same seed gives the same kernel; another gives another.
    assert_equal(ssao_kernel(16, 7)[5].x, kernel[5].x)
    assert_true(ssao_kernel(16, 8)[5].x != kernel[5].x)
    with assert_raises():
        _ = ssao_kernel(0, 7)
    var noise = ssao_noise(3)
    assert_equal(len(noise), 16)
    for value in noise:
        assert_true(value >= -1 and value < 1)


def test_ssao_darkens_the_corner_and_leaves_the_background() raises:
    var camera = a_camera()
    var target = drawn(camera)
    var view = view_of(target, camera)
    var normals = view.normals()
    var occlusion = ssao_occlusion(
        view,
        normals,
        ssao_kernel(32, 1),
        ssao_noise(1),
        meters(0.5),
        0.0005,
        0.1,
    )
    var darkest = Float32(1)
    var background = 0
    for slot in range(WIDTH * HEIGHT):
        darkest = min(darkest, occlusion[slot])
        if view.depth[slot] == 1:
            assert_equal(occlusion[slot], Float32(1))
            background += 1
        assert_true(occlusion[slot] >= 0 and occlusion[slot] <= 1)
    assert_true(darkest < 0.7, "Nothing was occluded")
    # A noise of zero cannot turn the kernel, and three.js's divide by zero
    # occludes nothing.
    var still = ssao_occlusion(
        view,
        normals,
        ssao_kernel(8, 1),
        List[Float32](length=16, fill=0),
        meters(0.5),
        0.0005,
        0.1,
    )
    for value in still:
        assert_equal(value, Float32(1))


def test_the_ssao_blur_averages_five_by_five() raises:
    var values = List[Float32](length=49, fill=1)
    values[24] = 0
    var blurred = ssao_blur(values, 7, 7)
    assert_almost_equal(blurred[24], Float32(24.0 / 25.0), atol=TOLERANCE)
    assert_almost_equal(blurred[0], Float32(1), atol=TOLERANCE)
    # At the edge the nearest pixel is read again.
    var edge = List[Float32](length=49, fill=1)
    edge[0] = 0
    assert_almost_equal(
        ssao_blur(edge, 7, 7)[0], Float32(16.0 / 25.0), atol=TOLERANCE
    )


def test_ssao_light_leaves_each_output() raises:
    var camera = a_camera()
    var target = drawn(camera)
    var view = view_of(target, camera)
    var settings = SsaoSettings()
    settings.kernel_radius = meters(0.5)
    settings.min_distance = 0.0005
    var shaded = drawn(camera)
    ssao_light(shaded, view, settings)
    assert_true(total_light(shaded) < total_light(target))
    # Every output replaces the frame, or keeps it for the beauty.
    settings.output = BEAUTY_OUTPUT
    var kept = drawn(camera)
    ssao_light(kept, view, settings)
    assert_equal(count_changed(kept, target), 0)
    settings.output = EFFECT_OUTPUT
    var raw = drawn(camera)
    ssao_light(raw, view, settings)
    settings.output = BLUR_OUTPUT
    var soft = drawn(camera)
    ssao_light(soft, view, settings)
    assert_true(count_changed(raw, soft) > 0)
    assert_equal(soft.colors[0].a, Float32(1))
    settings.output = DEPTH_OUTPUT
    var deep = drawn(camera)
    ssao_light(deep, view, settings)
    # The background is at the far plane: one minus one.
    assert_almost_equal(deep.colors[0].r, Float32(0), atol=1e-3)
    var middle = (HEIGHT - 2) * WIDTH + 3
    assert_almost_equal(
        deep.colors[middle].r,
        1 - view.linear_depth(view.view_z(view.depth[middle])),
        atol=TOLERANCE,
    )
    settings.output = NORMAL_OUTPUT
    var turned = drawn(camera)
    ssao_light(turned, view, settings)
    var n = view.normal_at(3, HEIGHT - 2)
    assert_almost_equal(
        turned.colors[middle].g, n.y * 0.5 + 0.5, atol=TOLERANCE
    )
    # A frame of another size is refused, either way.
    var wide = RenderTarget(WIDTH + 1, HEIGHT, BLACK)
    with assert_raises():
        ssao_light(wide, view, settings)
    var tall = RenderTarget(WIDTH, HEIGHT + 1, BLACK)
    with assert_raises():
        ssao_light(tall, view, settings)
    settings.kernel_size = 0
    with assert_raises():
        ssao_light(shaded, view, settings)


def test_multiply_light_scales_the_light_and_keeps_alpha() raises:
    var frame = RenderTarget(1, 1, BLACK)
    frame.colors[0] = FloatColor(0.5, 0.4, 0.2, 0.8)
    multiply_light(frame, [Float32(0.5)])
    assert_almost_equal(frame.colors[0].r, Float32(0.25))
    assert_almost_equal(frame.colors[0].a, Float32(0.8))


# --- SAO ---------------------------------------------------------------------


def test_the_sao_hash_and_one_sample_s_occlusion_are_three_js_s() raises:
    for index in range(20):
        var value = glsl_rand(Float32(index) * 0.37, Float32(index) * 0.11)
        assert_true(value >= 0 and value < 1)
    assert_equal(glsl_rand(0.25, 0.5), glsl_rand(0.25, 0.5))
    var center = Vector3(0, 0, -2)
    var up = Vector3(0, 0, 1)
    assert_equal(sao_sample_occlusion(center, up, center, 0.05, 0, 0.5), 0)
    # A sample half a meter out along the normal: the slope over the
    # scaled distance, less the bias, over one plus that distance squared.
    var over = Vector3(0, 0, -1.5)
    var screen = Float32(0.05 * 0.5)
    var expected = (0.5 / screen - 0.5) / (1 + screen * screen)
    assert_almost_equal(
        sao_sample_occlusion(center, up, over, 0.05, 0, 0.5),
        expected,
        atol=1e-3,
    )
    # One behind the surface occludes nothing.
    var under = Vector3(0, 0, -2.5)
    assert_equal(sao_sample_occlusion(center, up, under, 0.05, 0, 0.5), 0)


def test_blur_weights_are_three_js_gaussian() raises:
    var weights = blur_weights(3, 2)
    assert_equal(len(weights), 4)
    for tap in range(4):
        var x = Float32(tap)
        var expected = exp(-(x * x) / 8) / (sqrt(Float32(2 * pi)) * 2)
        assert_almost_equal(weights[tap], expected, atol=TOLERANCE)
    assert_equal(len(blur_weights(0, 1)), 1)


def test_the_depth_limited_blur_stops_at_a_step() raises:
    # Two flat sheets, the left three columns far and the right two near,
    # and the top row with nothing drawn.
    var depth = List[Float32](length=25, fill=-0.5)
    for y in range(5):
        for x in range(3):
            depth[y * 5 + x] = 0.5
    for x in range(5):
        depth[x] = inf[DType.float32]()
    var view = flat_view(5, 5, depth)
    var values = List[Float32](length=25, fill=1)
    for y in range(5):
        for x in range(3, 5):
            values[y * 5 + x] = 0
    var weights = blur_weights(2, 1)
    var across = depth_limited_blur(values, view, weights, 0.5, True)
    # The far sheet never reads the near one, nor the near the far.
    assert_equal(across[2 * 5 + 2], Float32(1))
    assert_equal(across[2 * 5 + 3], Float32(0))
    assert_equal(across[0], Float32(1))
    # With a cutoff past the step, the step blurs.
    var loose = depth_limited_blur(values, view, weights, 100, True)
    assert_true(loose[2 * 5 + 2] < 1)
    var down = depth_limited_blur(values, view, weights, 100, False)
    assert_equal(down[2 * 5 + 2], Float32(1))
    var cut = depth_limited_blur(values, view, weights, 0.5, False)
    assert_equal(cut[1 * 5 + 1], Float32(1))


def test_sao_darkens_the_corner_and_skips_what_has_no_neighbors() raises:
    var camera = a_camera()
    var target = drawn(camera)
    var view = view_of(target, camera)
    var settings = SaoSettings()
    settings.kernel_radius = 8
    settings.intensity = 0.5
    settings.scale = 5
    var occlusion = sao_occlusion(view, view.normals(), settings, 0.3)
    var darkest = Float32(1)
    for slot in range(WIDTH * HEIGHT):
        darkest = min(darkest, occlusion[slot])
        if view.depth[slot] == 1:
            assert_equal(occlusion[slot], Float32(1))
    assert_true(darkest < 1, "Nothing was occluded")
    # One pixel alone in the background: every sample lands on nothing.
    var depth = List[Float32](length=81, fill=inf[DType.float32]())
    depth[40] = 0.2
    var lonely = flat_view(9, 9, depth)
    var alone = sao_occlusion(lonely, lonely.normals(), settings, 0.3)
    assert_equal(alone[40], Float32(1))


def test_sao_light_leaves_each_output() raises:
    var camera = a_camera()
    var target = drawn(camera)
    var view = view_of(target, camera)
    var settings = SaoSettings()
    settings.kernel_radius = 8
    settings.intensity = 0.5
    settings.scale = 5
    var shaded = drawn(camera)
    sao_light(shaded, view, settings, 0.3)
    assert_true(total_light(shaded) < total_light(target))
    settings.output = BEAUTY_OUTPUT
    var kept = drawn(camera)
    sao_light(kept, view, settings, 0.3)
    assert_equal(count_changed(kept, target), 0)
    settings.output = EFFECT_OUTPUT
    var raw = drawn(camera)
    sao_light(raw, view, settings, 0.3)
    settings.output = BLUR_OUTPUT
    var soft = drawn(camera)
    sao_light(soft, view, settings, 0.3)
    assert_true(count_changed(raw, soft) > 0)
    settings.blur = False
    var unblurred = drawn(camera)
    sao_light(unblurred, view, settings, 0.3)
    assert_equal(count_changed(raw, unblurred), 0)
    settings.output = DEPTH_OUTPUT
    var deep = drawn(camera)
    sao_light(deep, view, settings, 0.3)
    assert_almost_equal(deep.colors[0].r, Float32(0), atol=1e-3)
    settings.output = NORMAL_OUTPUT
    var turned = drawn(camera)
    sao_light(turned, view, settings, 0.3)
    assert_true(count_changed(turned, target) > 0)
    var wide = RenderTarget(WIDTH + 1, HEIGHT, BLACK)
    with assert_raises():
        sao_light(wide, view, settings, 0.3)
    var tall = RenderTarget(WIDTH, HEIGHT + 1, BLACK)
    with assert_raises():
        sao_light(tall, view, settings, 0.3)
    settings.scale = 0
    with assert_raises():
        sao_light(shaded, view, settings, 0.3)


# --- SSR ---------------------------------------------------------------------


def test_the_floor_reflects_the_red_box() raises:
    var camera = a_camera()
    var target = drawn(camera)
    var view = view_of(target, camera)
    var settings = SsrSettings()
    settings.opacity = 1
    settings.max_distance = meters(5)
    settings.thickness = meters(0.2)
    var reflections = ssr_reflections(
        view, target.colors, view.normals(), settings
    )
    var reddest = Float32(0)
    for slot in range(WIDTH * HEIGHT):
        var seen = reflections[slot]
        if view.depth[slot] == 1:
            assert_equal(seen.a, Float32(0))
        assert_true(seen.a >= 0 and seen.a <= 1)
        # Only the floor, under the box, reflects the box.
        if seen.a > 0 and seen.r > seen.g * 2:
            reddest = max(reddest, seen.a)
    assert_true(reddest > 0, "The floor reflected no red")
    # Without the fades, a reflection is as strong as the opacity.
    settings.distance_attenuation = False
    settings.fresnel = False
    var plain = ssr_reflections(view, target.colors, view.normals(), settings)
    var strongest = Float32(0)
    for seen in plain:
        strongest = max(strongest, seen.a)
    assert_equal(strongest, Float32(1))
    # Infinitely thick surfaces are hit by anything that passes behind.
    settings.infinite_thick = True
    settings.thickness = meters(0)
    var thick = ssr_reflections(view, target.colors, view.normals(), settings)
    var hits = 0
    for seen in thick:
        if seen.a > 0:
            hits += 1
    assert_true(hits > 0)
    # A short reach finds nothing.
    settings.max_distance = meters(0.01)
    var short = ssr_reflections(view, target.colors, view.normals(), settings)
    var found = 0
    for seen in short:
        if seen.a > 0:
            found += 1
    assert_true(found < hits)
    # A surface turned away from the camera reflects nothing.
    var away = List[Vector3](length=WIDTH * HEIGHT, fill=Vector3(0, 0, -1))
    var none = ssr_reflections(view, target.colors, away, settings)
    for seen in none:
        assert_equal(seen.a, Float32(0))


def test_ssr_through_an_orthographic_camera() raises:
    var camera = a_flat_camera()
    var renderer = a_renderer()
    var assets = Assets()
    var scene = room(assets)
    var target = RenderTarget(WIDTH, HEIGHT, BLACK)
    renderer.render_into(target, scene, assets, camera)
    var view = DepthView(
        target.depth,
        WIDTH,
        HEIGHT,
        camera.projection_matrix(),
        meters(0.1),
        meters(20),
    )
    assert_false(view.perspective)
    var settings = SsrSettings()
    settings.opacity = 1
    settings.max_distance = meters(5)
    settings.thickness = meters(0.2)
    var reflections = ssr_reflections(
        view, target.colors, view.normals(), settings
    )
    var hits = 0
    for seen in reflections:
        if seen.a > 0:
            hits += 1
    assert_true(hits > 0)


def test_a_hit_farther_from_the_surface_than_the_reach_is_not_reflected() raises:
    # One far pixel whose surface turns the view to the right, and a near
    # wall across the rest of the row facing back at it.
    var depth: List[Float32] = [0.5, -0.9, -0.9, -0.9, -0.9, -0.9, -0.9, -0.9]
    var view = flat_view(8, 1, depth)
    var normals = List[Vector3](length=8, fill=Vector3(-1, 0, 0))
    normals[0] = Vector3(Float32(sqrt(0.5)), 0, Float32(sqrt(0.5)))
    var colors = List[FloatColor](length=8, fill=FloatColor(1, 1, 1, 1))
    var settings = SsrSettings()
    settings.infinite_thick = True
    # The wall is about ten meters from the surface's plane.
    settings.max_distance = meters(1)
    var near = ssr_reflections(view, colors, normals, settings)
    assert_equal(near[0].a, Float32(0))
    settings.max_distance = meters(100)
    var far = ssr_reflections(view, colors, normals, settings)
    assert_true(far[0].a > 0)


def test_the_ssr_blur_weighs_each_neighbor_by_its_strength() raises:
    var source = List[FloatColor](length=9, fill=FloatColor(0, 0, 0, 0))
    source[4] = FloatColor(1, 0.5, 0, 1)
    var blurred = ssr_blur(source, 3, 3)
    # The middle keeps its color at a fifth of its strength.
    assert_almost_equal(blurred[4].r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(blurred[4].a, Float32(0.2), atol=TOLERANCE)
    assert_almost_equal(blurred[1].g, Float32(0.5), atol=TOLERANCE)
    # A corner sees no neighbor that reflects, and stays black.
    assert_true(blurred[0] == FloatColor(0, 0, 0, 0))


def test_ssr_light_leaves_each_output() raises:
    var camera = a_camera()
    var target = drawn(camera)
    var view = view_of(target, camera)
    var settings = SsrSettings()
    settings.opacity = 1
    settings.max_distance = meters(5)
    settings.thickness = meters(0.2)
    var shown = drawn(camera)
    ssr_light(shown, view, settings)
    assert_true(count_changed(shown, target) > 0)
    settings.output = BEAUTY_OUTPUT
    var kept = drawn(camera)
    ssr_light(kept, view, settings)
    assert_equal(count_changed(kept, target), 0)
    settings.output = EFFECT_OUTPUT
    var raw = drawn(camera)
    ssr_light(raw, view, settings)
    assert_true(raw.colors[0] == FloatColor(0, 0, 0, 0))
    settings.output = BLUR_OUTPUT
    var soft = drawn(camera)
    ssr_light(soft, view, settings)
    assert_true(count_changed(raw, soft) > 0)
    settings.blur = False
    var unblurred = drawn(camera)
    ssr_light(unblurred, view, settings)
    assert_equal(count_changed(raw, unblurred), 0)
    settings.output = DEPTH_OUTPUT
    var deep = drawn(camera)
    ssr_light(deep, view, settings)
    assert_almost_equal(deep.colors[0].r, Float32(0), atol=1e-3)
    settings.output = NORMAL_OUTPUT
    var turned = drawn(camera)
    ssr_light(turned, view, settings)
    assert_true(count_changed(turned, target) > 0)
    var wide = RenderTarget(WIDTH + 1, HEIGHT, BLACK)
    with assert_raises():
        ssr_light(wide, view, settings)
    var tall = RenderTarget(WIDTH, HEIGHT + 1, BLACK)
    with assert_raises():
        ssr_light(tall, view, settings)
    settings.opacity = 2
    with assert_raises():
        ssr_light(shown, view, settings)


# --- the outline -------------------------------------------------------------


def test_the_outline_mask_marks_the_selection_and_what_hides_it() raises:
    var all_depth: List[Float32] = [0.5, 0.2, 0.3]
    var chosen: List[Float32] = [inf[DType.float32](), 0.4, 0.3]
    var mask = outline_mask(all_depth, chosen)
    assert_true(mask[0] == FloatColor(1, 1, 1, 1))
    assert_true(mask[1] == FloatColor(0, 1, 1, 1))
    assert_true(mask[2] == FloatColor(0, 0, 1, 1))
    with assert_raises():
        _ = outline_mask(all_depth, [Float32(0)])


def square(size: Int, low: Int, high: Int) -> List[Float32]:
    """Return a depth with a square from `low` up to `high` at 0.5 and
    nothing drawn elsewhere."""
    var depth = List[Float32](length=size * size, fill=inf[DType.float32]())
    for y in range(low, high):
        for x in range(low, high):
            depth[y * size + x] = 0.5
    return depth^


def test_the_outline_glows_around_the_selection_and_not_inside() raises:
    var size = 16
    var chosen = square(size, 5, 11)
    var settings = OutlineSettings()
    settings.selection = Layers(UInt32(2))
    var frame = RenderTarget(size, size, BLACK)
    outline_light(frame, chosen, chosen, settings, Duration(0.0, SECOND))
    # Just outside the square the visible color, white, shows.
    var outside = frame.colors[8 * size + 4]
    assert_true(outside.r > 0)
    assert_almost_equal(outside.r, outside.b, atol=TOLERANCE)
    # Inside, nothing is added; far away, nothing either.
    assert_equal(frame.colors[8 * size + 8].r, Float32(0))
    assert_equal(frame.colors[0].r, Float32(0))
    assert_equal(frame.colors[8 * size + 4].a, Float32(1))
    # Hidden behind something else, the edge takes the hidden color.
    var front = List[Float32](length=size * size, fill=0.1)
    var hidden = RenderTarget(size, size, BLACK)
    outline_light(hidden, front, chosen, settings, Duration(0.0, SECOND))
    var dim = hidden.colors[8 * size + 4]
    assert_true(dim.r > dim.g and dim.g > dim.b and dim.b > 0)
    # A glow adds the wide blur, reaching further.
    settings.edge_glow = 2
    var glowing = RenderTarget(size, size, BLACK)
    outline_light(glowing, chosen, chosen, settings, Duration(0.0, SECOND))
    assert_true(glowing.colors[8 * size + 2].r > frame.colors[8 * size + 2].r)
    # A pulse scales the colors with the time.
    settings.edge_glow = 0
    settings.pulse_period = Duration(1.0, SECOND)
    var pulsed = RenderTarget(size, size, BLACK)
    var time = Duration(Float32(pi) / 10, SECOND)
    outline_light(pulsed, chosen, chosen, settings, time)
    assert_true(pulsed.colors[8 * size + 4].r < outside.r)
    with assert_raises():
        outline_light(pulsed, [Float32(0)], chosen, settings, time)
    settings.edge_thickness = 0
    with assert_raises():
        outline_light(pulsed, chosen, chosen, settings, time)


# --- in the composer ---------------------------------------------------------


def test_the_four_passes_run_in_the_composer() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var scene = room(assets)
    var camera = a_camera()
    var plain = EffectComposer()
    plain.add_pass(render_pass())
    var base = plain.render(renderer, scene, assets, camera)

    var ssao = EffectComposer()
    ssao.add_pass(ssao_pass(meters(0.5), 0.0005, 0.1))
    var occluded = ssao.render(renderer, scene, assets, camera)
    var darker = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if occluded.get_pixel(x, y).r < base.get_pixel(x, y).r:
                darker += 1
    assert_true(darker > 0, "SSAO darkened nothing")

    var sao = EffectComposer()
    sao.add_pass(render_pass())
    sao.add_pass(sao_pass(0.5, 5, 8))
    var seed = sao.passes[1].sao.seed
    _ = sao.render(renderer, scene, assets, camera)
    assert_true(sao.passes[1].sao.seed != seed, "The seed did not advance")

    var ssr = EffectComposer()
    ssr.add_pass(ssr_pass(1, meters(5), meters(0.2)))
    var mirrored = ssr.render(renderer, scene, assets, camera)
    var changed = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if not same(mirrored.get_pixel(x, y), base.get_pixel(x, y)):
                changed += 1
    assert_true(changed > 0, "SSR changed nothing")

    var outline = EffectComposer()
    outline.add_pass(render_pass())
    outline.add_pass(outline_pass(Layers(UInt32(2))))
    var ringed = outline.render(renderer, scene, assets, camera, 0.5)
    assert_almost_equal(outline.passes[1].time, Float32(0.5))
    var brighter = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if ringed.get_pixel(x, y).b > base.get_pixel(x, y).b:
                brighter += 1
    assert_true(brighter > 0, "The outline added nothing")
    # With no layer selected the pass outlines nothing.
    outline.passes[1].outline.selection = Layers(UInt32(0))
    var bare = outline.render(renderer, scene, assets, camera)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_true(same(bare.get_pixel(x, y), base.get_pixel(x, y)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
