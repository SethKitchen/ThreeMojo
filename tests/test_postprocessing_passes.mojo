# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the passes that draw the frame anew, GTAO, and the shader and
save passes: `postprocessing.render_passes`, `postprocessing.gtao`,
`postprocessing.shader_pass`, and their builders in the composer."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.layers import Layers
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import box
from geometries.plane import plane
from lights.light import ambient_light
from materials.glsl import compile_shader_material
from materials.material import Material
from materials.nodes import (
    AT_FRAGMENT,
    AT_RIGHT,
    AT_UP,
    COLOR_NODE,
    CORNER_A,
    CORNER_B,
    CORNER_C,
    MASK_NODE,
    NO_NODES,
    OPACITY_NODE,
    OUTPUT_NODE,
    NodeGraph,
    NodeProgram,
    NodeProgramId,
)
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.composer import (
    CUBE_TEXTURE,
    GTAO,
    RENDER_PIXELATED,
    RENDER_TRANSITION,
    SAVE,
    SHADER,
    EffectComposer,
    Pass,
    check_pass,
    copy_pass,
    cube_texture_pass,
    draw_scene,
    frame_outputs,
    gtao_pass,
    reads_frame_as_light,
    render_pass,
    render_pixelated_pass,
    render_transition,
    render_transition_pass,
    save_pass,
    shader_pass,
    sized_renderer,
)
from postprocessing.gtao import (
    GtaoSettings,
    check_gtao,
    denoise_disk,
    denoise_noise,
    gtao_denoise,
    gtao_light,
    gtao_noise,
    gtao_occlusion,
    magic_square,
)
from postprocessing.render_passes import (
    PixelatedSettings,
    PixelatedTexels,
    TransitionSettings,
    check_pixelated,
    check_transition,
    cube_overlay,
    cube_texture_light,
    pixelated_light,
    pixelated_size,
    pixelated_strength,
    transition_light,
    transition_pixel,
)
from postprocessing.sampling import LightView, Untracked, u_of, v_of
from postprocessing.screen_space import (
    BEAUTY_OUTPUT,
    BLUR_OUTPUT,
    DEFAULT_OUTPUT,
    DEPTH_OUTPUT,
    EFFECT_OUTPUT,
    NORMAL_OUTPUT,
    DepthView,
    ScreenSpaceOutput,
)
from postprocessing.shader_pass import (
    INPUT_SLOT,
    SAVED_SLOT,
    SCREEN_VERTEX_SHADER,
    HostScreenNodes,
    ScreenNodes,
    ShaderSettings,
    check_shader,
    reads_assets,
    screen_code,
    screen_pixel,
    shader_light,
)
from render.cube_texture import CubeTexture
from render.cube_texture_store import NO_CUBE_TEXTURE, CubeTextureId
from render.framebuffer import Color, FloatColor
from render.srgb import SRGB
from render.target import OUTPUT_COLOR, OUTPUT_NORMAL, RenderTarget
from render.texture import CLAMP, NEAREST, Texture, checkerboard
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from renderers.renderer import Renderer
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime BLACK = Color(0, 0, 0)
comptime SIZE = 8


def meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


def near(a: Float32, b: Float32, tolerance: Float32 = 1e-5) raises:
    """Assert two floats agree."""
    assert_almost_equal(a, b, atol=Float64(tolerance))


def same_color(a: FloatColor, b: FloatColor, tolerance: Float32 = 1e-5) raises:
    """Assert two colors agree in every channel."""
    near(a.r, b.r, tolerance)
    near(a.g, b.g, tolerance)
    near(a.b, b.b, tolerance)
    near(a.a, b.a, tolerance)


def a_camera() raises -> PerspectiveCamera:
    """Return a camera looking into the corner of a room."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, meters(0.1), meters(20.0)
    )
    camera.place(Vector3(0, 0.6, 3), Vector3(0, -0.2, 0))
    return camera^


def room(mut assets: Assets) raises -> Scene:
    """Return a floor, a back wall and a box on layer one, lit evenly."""
    var scene = Scene()
    scene.add_light(ambient_light(Color(255, 255, 255), 1))
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
    block.layers.set(1)
    scene.add_mesh(Mesh(cube, red, scene.add(block^)))
    scene.update()
    return scene^


def a_renderer() raises -> Renderer:
    """Return a renderer of the test size on a black background."""
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    return renderer^


def a_face(color: Color) raises -> Texture:
    """Return a 2x2 face of one color."""
    var pixels = List[UInt8]()
    for _ in range(4):
        pixels.append(color.r)
        pixels.append(color.g)
        pixels.append(color.b)
        pixels.append(255)
    return Texture(2, 2, pixels^, CLAMP, NEAREST, SRGB, False)


def a_cube() raises -> CubeTexture:
    """Return a cube of six flat faces."""
    var faces = List[Texture]()
    for color in [
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 255, 0),
        Color(0, 255, 255),
        Color(255, 0, 255),
    ]:
        faces.append(a_face(color))
    return CubeTexture(faces^)


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


def hand_texels(
    depths: List[Float32], normals: List[Vector3], width: Int, height: Int
) raises -> RenderTarget:
    """Return a target with given window depths and normals."""
    var target = RenderTarget(
        width, height, BLACK, outputs=[OUTPUT_COLOR, OUTPUT_NORMAL]
    )
    for slot in range(width * height):
        target.depth[slot] = depths[slot] * 2 - 1
        target.normals[slot] = normals[slot]
        target.colors[slot] = FloatColor(0.5, 0.25, 1, 1)
    return target^


def hand_view(target: RenderTarget) raises -> DepthView:
    """Return a hand-built target's depth."""
    return view_of(target, a_camera())


# --- pixelated -----------------------------------------------------------------


def test_pixelated_settings_are_checked() raises:
    var settings = PixelatedSettings()
    assert_equal(settings.pixel_size, 6)
    near(settings.normal_edge_strength, 0.3)
    near(settings.depth_edge_strength, 0.4)
    check_pixelated(settings)
    settings.pixel_size = 0
    with assert_raises(contains="at least one"):
        check_pixelated(settings)
    var wrong = PixelatedSettings()
    wrong.normal_edge_strength = nan[DType.float32]()
    with assert_raises(contains="finite"):
        check_pixelated(wrong)
    wrong = PixelatedSettings()
    wrong.depth_edge_strength = inf[DType.float32]()
    with assert_raises(contains="finite"):
        check_pixelated(wrong)
    wrong = PixelatedSettings()
    wrong.normal_edge_strength = -1
    with assert_raises(contains="negative"):
        check_pixelated(wrong)
    wrong = PixelatedSettings()
    wrong.depth_edge_strength = -1
    with assert_raises(contains="negative"):
        check_pixelated(wrong)
    assert_equal(pixelated_size(100, 6), 16)
    assert_equal(pixelated_size(4, 6), 1)


def test_a_flat_drawing_has_no_edges() raises:
    var depths = List[Float32](length=9, fill=0.5)
    var normals = List[Vector3](length=9, fill=Vector3(0, 0, 1))
    var drawn = hand_texels(depths, normals, 3, 3)
    var texels = PixelatedTexels(drawn, hand_view(drawn))
    near(pixelated_strength(texels, 1, 1, PixelatedSettings()), 1)
    # Held at the edges: a corner reads itself past the border.
    near(texels.depth_at(-1, 5), texels.depth_at(0, 2))
    near(texels.normal_at(3, -2).z, 1)


def test_a_depth_step_darkens_and_a_normal_step_lightens() raises:
    # The middle texel is in front of all four neighbors: a depth edge.
    var depths = List[Float32](length=9, fill=0.9)
    depths[4] = 0.5
    var normals = List[Vector3](length=9, fill=Vector3(0, 0, 1))
    var drawn = hand_texels(depths, normals, 3, 3)
    var texels = PixelatedTexels(drawn, hand_view(drawn))
    near(pixelated_strength(texels, 1, 1, PixelatedSettings()), 0.6)
    # With no depth strength the depth edge is not asked, and the flat
    # normals draw no normal edge.
    var no_depth = PixelatedSettings()
    no_depth.depth_edge_strength = 0
    near(pixelated_strength(texels, 1, 1, no_depth), 1)
    # A neighbor facing another way, at the same depth, lightens.
    var flat = List[Float32](length=9, fill=0.5)
    var turned = List[Vector3](length=9, fill=Vector3(0, 0, 1))
    turned[5] = Vector3(0, 1, 0)
    var bent = hand_texels(flat, turned, 3, 3)
    var bent_texels = PixelatedTexels(bent, hand_view(bent))
    near(pixelated_strength(bent_texels, 1, 1, PixelatedSettings()), 1.3)
    # With no normal strength the normal edge is not asked.
    var no_normal = PixelatedSettings()
    no_normal.normal_edge_strength = 0
    near(pixelated_strength(bent_texels, 1, 1, no_normal), 1)
    # A texel behind all its neighbors: they are in front, so neither
    # edge is drawn, whatever their normals.
    var behind = List[Float32](length=9, fill=0.5)
    behind[4] = 0.9
    var back = hand_texels(behind, turned, 3, 3)
    var back_texels = PixelatedTexels(back, hand_view(back))
    near(pixelated_strength(back_texels, 1, 1, PixelatedSettings()), 1)


def test_a_drawing_without_normals_reads_minus_one_each_way() raises:
    var drawn = RenderTarget(2, 2, BLACK)
    var texels = PixelatedTexels(drawn, hand_view(drawn))
    near(texels.normal_at(0, 0).x, -1)
    near(texels.normal_at(1, 1).z, -1)


def test_pixelated_light_shows_each_texel_as_a_block() raises:
    var depths: List[Float32] = [0.5, 0.5, 0.5, 0.5]
    var normals = List[Vector3](length=4, fill=Vector3(0, 0, 1))
    var drawn = hand_texels(depths, normals, 2, 2)
    drawn.colors[1] = FloatColor(0, 1, 0, 1)
    drawn.data[1] = True
    var frame = RenderTarget(4, 4, BLACK)
    pixelated_light(frame, drawn, hand_view(drawn), PixelatedSettings())
    # The top right block is the green texel, with its data flag.
    same_color(frame.colors[2], FloatColor(0, 1, 0, 1))
    same_color(frame.colors[7], FloatColor(0, 1, 0, 1))
    assert_true(frame.data[3])
    same_color(frame.colors[0], FloatColor(0.5, 0.25, 1, 1))
    assert_false(frame.data[0])
    near(frame.depth[15], drawn.depth[3])


def test_the_composer_draws_a_pixelated_scene() raises:
    var assets = Assets()
    var scene = room(assets)
    var camera = a_camera()
    var renderer = a_renderer()
    var step = render_pixelated_pass(2, 0.5, 0.25)
    assert_true(step.kind == RENDER_PIXELATED)
    assert_equal(step.pixelated.pixel_size, 2)
    near(step.pixelated.normal_edge_strength, 0.5)
    near(step.pixelated.depth_edge_strength, 0.25)
    assert_false(reads_frame_as_light(RENDER_PIXELATED))
    var composer = EffectComposer()
    composer.add_pass(step^)
    var image = composer.render(renderer, scene, assets, camera)
    # Each two by two block is one color.
    for y in range(0, SIZE, 2):
        for x in range(0, SIZE, 2):
            var a = image.get_pixel(x, y)
            var b = image.get_pixel(x + 1, y + 1)
            assert_equal(Int(a.r), Int(b.r))
            assert_equal(Int(a.g), Int(b.g))
    with assert_raises(contains="at least one"):
        _ = render_pixelated_pass(0)


def test_a_sized_renderer_keeps_the_settings() raises:
    var renderer = a_renderer()
    renderer.set_antialias(True)
    renderer.tone_mapping_exposure = 2
    var small = sized_renderer(renderer, 3, 2)
    assert_equal(small.width, 3)
    assert_equal(small.height, 2)
    assert_true(small.antialias)
    near(small.tone_mapping_exposure, 2)
    with assert_raises():
        _ = sized_renderer(renderer, 0, 2)


# --- transition ---------------------------------------------------------------


def test_transition_settings_are_checked() raises:
    var settings = TransitionSettings()
    near(settings.mix_ratio, 0)
    near(settings.threshold, 0.1)
    assert_true(settings.use_texture)
    check_transition(settings)
    settings.mix_ratio = nan[DType.float32]()
    with assert_raises(contains="finite"):
        check_transition(settings)
    settings = TransitionSettings()
    settings.threshold = inf[DType.float32]()
    with assert_raises(contains="finite"):
        check_transition(settings)
    settings = TransitionSettings()
    settings.threshold = 0
    with assert_raises(contains="positive"):
        check_transition(settings)


def test_a_transition_pixel_mixes_evenly_or_by_the_texture() raises:
    var first = FloatColor(1, 0, 0, 1)
    var second = FloatColor(0, 0, 1, 0.5)
    var settings = TransitionSettings()
    settings.use_texture = False
    settings.mix_ratio = 0.25
    # `mix(second, first, mixRatio)`.
    same_color(
        transition_pixel(first, second, FloatColor(0, 0, 0, 0), settings),
        FloatColor(0.25, 0, 0.75, 0.625),
    )
    settings.use_texture = True
    settings.mix_ratio = 0.5
    # The threshold sweeps to 0.5: a red of 0.55 is half a threshold
    # above it, so the mix is half way.
    same_color(
        transition_pixel(first, second, FloatColor(0.55, 0, 0, 1), settings),
        FloatColor(0.5, 0, 0.5, 0.75),
    )
    # Far below the threshold: the first scene; far above: the second.
    same_color(
        transition_pixel(first, second, FloatColor(0, 0, 0, 1), settings), first
    )
    same_color(
        transition_pixel(first, second, FloatColor(1, 0, 0, 1), settings),
        second,
    )


def test_transition_light_mixes_two_targets() raises:
    var first = RenderTarget(2, 1, Color(255, 0, 0))
    var second = RenderTarget(2, 1, Color(0, 0, 255))
    first.depth[0] = 0.25
    var frame = RenderTarget(2, 1, BLACK)
    frame.data[0] = True
    var settings = TransitionSettings()
    settings.use_texture = False
    settings.mix_ratio = 1
    transition_light(frame, first, second, List[FloatColor](), settings)
    same_color(frame.colors[1], first.light_at(1))
    assert_false(frame.data[0])
    near(frame.depth[0], 0.25)
    # Half way, a texel of one shows the second and one of zero the first.
    settings.use_texture = True
    settings.mix_ratio = 0.5
    var texels: List[FloatColor] = [
        FloatColor(1, 0, 0, 1),
        FloatColor(0, 0, 0, 1),
    ]
    transition_light(frame, first, second, texels, settings)
    same_color(frame.colors[0], second.light_at(0))
    same_color(frame.colors[1], first.light_at(1))


def test_the_composer_mixes_two_sets_of_layers() raises:
    var assets = Assets()
    var scene = room(assets)
    var camera = a_camera()
    var renderer = a_renderer()
    # The camera sees layer zero: the room without the box.
    var room_only = Layers()
    var box_only = Layers()
    box_only.set(1)
    var step = render_transition_pass(room_only, box_only, mix_ratio=1)
    assert_true(step.kind == RENDER_TRANSITION)
    assert_false(step.transition.use_texture)
    assert_false(reads_frame_as_light(RENDER_TRANSITION))
    var composer = EffectComposer()
    composer.add_pass(step^)
    var image = composer.render(renderer, scene, assets, camera)
    var plain = renderer.render(scene, assets, camera)
    for y in range(SIZE):
        for x in range(SIZE):
            assert_equal(
                Int(image.get_pixel(x, y).r), Int(plain.get_pixel(x, y).r)
            )
    # With a texture: white everywhere leads to the second view at a ratio
    # of zero.
    var white = assets.textures.add(
        checkerboard(4, 1, Color(255, 255, 255), Color(255, 255, 255))
    )
    var led = EffectComposer()
    led.add_pass(render_transition_pass(room_only, box_only, white, 0))
    var boxed = led.render(renderer, scene, assets, camera)
    var alone = EffectComposer()
    alone.add_pass(render_transition_pass(box_only, box_only, mix_ratio=0))
    var expected = alone.render(renderer, scene, assets, camera)
    for y in range(SIZE):
        for x in range(SIZE):
            assert_equal(
                Int(boxed.get_pixel(x, y).g), Int(expected.get_pixel(x, y).g)
            )
    var bad = Pass(RENDER_TRANSITION)
    with assert_raises(contains="texture"):
        check_pass(bad)
    with assert_raises(contains="threshold"):
        var zero = Pass(RENDER_TRANSITION)
        zero.transition.threshold = 0
        check_pass(zero)


def test_render_transition_draws_two_scenes_through_two_cameras() raises:
    var assets = Assets()
    var scene = room(assets)
    var empty = Scene()
    var camera = a_camera()
    var renderer = a_renderer()
    var settings = TransitionSettings()
    settings.use_texture = False
    settings.mix_ratio = 1
    var image = render_transition(
        renderer, scene, camera, empty, camera, assets, settings
    )
    var plain = renderer.render(scene, assets, camera)
    assert_equal(Int(image.get_pixel(4, 6).r), Int(plain.get_pixel(4, 6).r))
    # A black texture keeps the first scene at a ratio of one.
    var dark = assets.textures.add(checkerboard(4, 1, BLACK, BLACK))
    settings.use_texture = True
    var led = render_transition(
        renderer, scene, camera, empty, camera, assets, settings, dark
    )
    assert_equal(Int(led.get_pixel(4, 6).r), Int(plain.get_pixel(4, 6).r))
    settings.threshold = -1
    with assert_raises(contains="threshold"):
        _ = render_transition(
            renderer, scene, camera, empty, camera, assets, settings
        )


def test_draw_scene_draws_as_a_render_pass_does() raises:
    var assets = Assets()
    var scene = room(assets)
    var camera = a_camera()
    var renderer = a_renderer()
    var frame = RenderTarget(SIZE, SIZE, BLACK)
    draw_scene(frame, renderer, scene, assets, camera)
    var expected = RenderTarget(SIZE, SIZE, BLACK)
    renderer.render_into(expected, scene, assets, camera)
    for slot in range(SIZE * SIZE):
        same_color(frame.colors[slot], expected.colors[slot])


# --- cube texture -------------------------------------------------------------


def test_a_cube_texture_pass_draws_the_cube_the_camera_faces() raises:
    var assets = Assets()
    var scene = Scene()
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1, meters(0.1), meters(10)
    )
    camera.place(Vector3(5, 5, 5), Vector3(5, 5, 4))
    var sky = assets.cube_textures.add(a_cube())
    var overlay = cube_overlay(
        assets.cube_textures.get(sky), camera, scene, 4, 4
    )
    # Looking down -z: the magenta face, wherever the camera stands.
    same_color(overlay[5], FloatColor(1, 0, 1, 1), 1e-3)
    var frame = RenderTarget(4, 4, Color(0, 255, 0))
    frame.data[0] = True
    cube_texture_light(frame, overlay, 1)
    same_color(frame.colors[0], overlay[0])
    assert_false(frame.data[0])
    var half = RenderTarget(4, 4, BLACK)
    cube_texture_light(half, overlay, 0.5)
    same_color(half.colors[5], FloatColor(0.5, 0, 0.5, 1), 1e-3)
    var step = cube_texture_pass(sky, 0.5)
    assert_true(step.kind == CUBE_TEXTURE)
    near(step.strength, 0.5)
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(step^)
    var image = composer.render(a_renderer(), scene, assets, camera)
    assert_true(Int(image.get_pixel(1, 1).r) > 0)
    with assert_raises(contains="cube texture"):
        _ = cube_texture_pass(NO_CUBE_TEXTURE)
    with assert_raises():
        _ = cube_texture_pass(sky, -1)


# --- GTAO -------------------------------------------------------------------


def test_gtao_settings_are_three_js_s_and_checked() raises:
    var settings = GtaoSettings()
    near(settings.radius.value, 0.25)
    assert_equal(settings.samples, 16)
    near(settings.denoise_radius, 8)
    check_gtao(settings)
    var bad = GtaoSettings()
    bad.output = ScreenSpaceOutput(6)
    with assert_raises(contains="six"):
        check_gtao(bad)
    for field in range(12):
        var wrong = GtaoSettings()
        var value = Float32(nan[DType.float32]())
        if field == 0:
            wrong.radius = meters(value)
        elif field == 1:
            wrong.distance_exponent = value
        elif field == 2:
            wrong.thickness = meters(value)
        elif field == 3:
            wrong.distance_fall_off = value
        elif field == 4:
            wrong.scale = value
        elif field == 5:
            wrong.blend_intensity = value
        elif field == 6:
            wrong.luma_phi = value
        elif field == 7:
            wrong.depth_phi = value
        elif field == 8:
            wrong.normal_phi = value
        elif field == 9:
            wrong.denoise_radius = value
        elif field == 10:
            wrong.denoise_rings = value
        else:
            wrong.denoise_radius_exponent = value
        with assert_raises(contains="finite"):
            check_gtao(wrong)
    for field in range(6):
        var wrong = GtaoSettings()
        if field == 0:
            wrong.radius = meters(0)
        elif field == 1:
            wrong.thickness = meters(0)
        elif field == 2:
            wrong.scale = 0
        elif field == 3:
            wrong.luma_phi = 0
        elif field == 4:
            wrong.depth_phi = 0
        else:
            wrong.normal_phi = 0
        with assert_raises(contains="positive"):
            check_gtao(wrong)
    var low = GtaoSettings()
    low.distance_fall_off = -0.1
    with assert_raises(contains="fall-off"):
        check_gtao(low)
    var high = GtaoSettings()
    high.distance_fall_off = 1.1
    with assert_raises(contains="fall-off"):
        check_gtao(high)
    for field in range(3):
        var wrong = GtaoSettings()
        if field == 0:
            wrong.blend_intensity = -1
        elif field == 1:
            wrong.distance_exponent = -1
        else:
            wrong.denoise_radius_exponent = -1
        with assert_raises(contains="negative"):
            check_gtao(wrong)
    var few = GtaoSettings()
    few.samples = 1
    with assert_raises(contains="two samples"):
        check_gtao(few)
    few = GtaoSettings()
    few.denoise_samples = 1
    with assert_raises(contains="two samples"):
        check_gtao(few)
    var tight = GtaoSettings()
    tight.denoise_radius = 0.5
    with assert_raises(contains="one pixel"):
        check_gtao(tight)


def test_the_magic_square_and_the_noises() raises:
    var square = magic_square(3)
    assert_equal(len(square), 9)
    var seen = List[Bool](length=10, fill=False)
    for index in range(9):
        seen[square[index]] = True
    for number in range(1, 10):
        assert_true(seen[number])
    for row in range(3):
        assert_equal(
            square[row * 3] + square[row * 3 + 1] + square[row * 3 + 2], 15
        )
    # An even size is made the odd size above it.
    assert_equal(len(magic_square(4)), 25)
    var noise = gtao_noise()
    assert_equal(len(noise), 25)
    for index in range(25):
        var x = noise[index].r * 2 - 1
        var y = noise[index].g * 2 - 1
        near(sqrt(x * x + y * y), 1, 0.02)
        near(noise[index].b, Float32(127) / 255)
    var denoise = denoise_noise(3, 4)
    assert_equal(len(denoise), 16)
    for index in range(16):
        assert_true(denoise[index] >= 0 and denoise[index] <= 1)
    var same = denoise_noise(3, 4)
    near(same[7], denoise[7])
    var disk = denoise_disk(4, 1, 1)
    assert_equal(len(disk), 4)
    near(disk[0].z, 0)
    near(disk[3].z, 1)
    near(disk[1].x, 0, 1e-5)
    near(disk[1].y, 1)


def drawn_room() raises -> RenderTarget:
    """Return the room drawn with its normals."""
    var assets = Assets()
    var scene = room(assets)
    var target = RenderTarget(
        SIZE, SIZE, BLACK, outputs=[OUTPUT_COLOR, OUTPUT_NORMAL]
    )
    a_renderer().render_into(target, scene, assets, a_camera())
    return target^


def test_gtao_occlusion_is_one_on_the_sky_and_below_one_in_a_corner() raises:
    var target = drawn_room()
    var view = view_of(target, a_camera())
    var normals = view.normals()
    var noise = gtao_noise()
    var settings = GtaoSettings()
    settings.radius = meters(1)
    var total = Float32(0)
    for y in range(SIZE):
        for x in range(SIZE):
            var value = gtao_occlusion(view, normals, noise, x, y, settings)
            assert_true(value >= 0 and value <= 1)
            total += value
    assert_true(total < Float32(SIZE * SIZE))
    # The screen-space radius and five slices take their own paths.
    settings.screen_space_radius = True
    settings.samples = 30
    for y in range(SIZE):
        var value = gtao_occlusion(view, normals, noise, 4, y, settings)
        assert_true(value >= 0 and value <= 1)
    # Nothing drawn: one.
    var sky = DepthView(
        List[Float32](length=4, fill=1),
        2,
        2,
        a_camera().projection_matrix(),
        meters(0.1),
        meters(20),
    )
    var up = List[Vector3](length=4, fill=Vector3(0, 0, 1))
    near(gtao_occlusion(sky, up, noise, 0, 0, settings), 1)
    # A noise texel of 0.5, 0.5 names no direction. three.js normalizes a
    # zero vector there and reads NaN; the port samples the pixel itself,
    # which raises no horizon, so only the normal's cosine is left. An
    # identity projection keeps the trip to the screen and back exact.
    var wall = DepthView(
        List[Float32](length=4, fill=-0.5),
        2,
        2,
        Matrix4(),
        meters(0.1),
        meters(20),
    )
    var still: List[FloatColor] = [FloatColor(0.5, 0.5, 0, 1)]
    var center = wall.position(0.25, 0.75, wall.depth[0])
    var facing = (-center).dot(Vector3(0, 0, 1)) / center.length()
    assert_true(facing > 0.5)
    near(gtao_occlusion(wall, up, still, 0, 0, GtaoSettings()), facing)


def test_gtao_denoise_is_one_without_a_surface() raises:
    var target = drawn_room()
    var view = view_of(target, a_camera())
    var normals = view.normals()
    var ao = List[FloatColor](
        length=SIZE * SIZE, fill=FloatColor(0.5, 0.5, 0.5, 1)
    )
    var ao_view = LightView(ao, SIZE, SIZE)
    var noise = denoise_noise(1, 4)
    var disk = denoise_disk(4, 2, 1)
    var settings = GtaoSettings()
    # A flat occlusion denoises to itself.
    near(gtao_denoise(ao_view, view, normals, noise, disk, 4, 6, settings), 0.5)
    var none = List[Vector3](length=SIZE * SIZE, fill=Vector3(0, 0, 0))
    near(gtao_denoise(ao_view, view, none, noise, disk, 4, 6, settings), 1)
    var sky = DepthView(
        List[Float32](length=SIZE * SIZE, fill=1),
        SIZE,
        SIZE,
        a_camera().projection_matrix(),
        meters(0.1),
        meters(20),
    )
    near(gtao_denoise(ao_view, sky, normals, noise, disk, 4, 6, settings), 1)
    _ = ao^


def test_gtao_light_leaves_each_output() raises:
    var target = drawn_room()
    var view = view_of(target, a_camera())
    var normals = view.normals()
    for value in range(6):
        var frame = drawn_room()
        var settings = GtaoSettings()
        settings.output = ScreenSpaceOutput(value)
        settings.denoise_samples = 4
        gtao_light(frame, view, normals, settings)
        if settings.output == BEAUTY_OUTPUT:
            for slot in range(SIZE * SIZE):
                same_color(frame.colors[slot], target.colors[slot])
        elif settings.output == DEFAULT_OUTPUT:
            for slot in range(SIZE * SIZE):
                assert_true(
                    frame.colors[slot].r <= target.colors[slot].r + 1e-6
                )
        else:
            assert_true(
                settings.output == EFFECT_OUTPUT
                or settings.output == BLUR_OUTPUT
                or settings.output == DEPTH_OUTPUT
                or settings.output == NORMAL_OUTPUT
            )


def test_the_composer_runs_gtao_and_draws_its_normals() raises:
    var assets = Assets()
    var scene = room(assets)
    var camera = a_camera()
    var renderer = a_renderer()
    var step = gtao_pass(meters(0.5), 0.5)
    assert_true(step.kind == GTAO)
    near(step.gtao.radius.value, 0.5)
    near(step.gtao.blend_intensity, 0.5)
    var steps = List[Pass]()
    steps.append(step.copy())
    assert_equal(len(frame_outputs(steps)), 2)
    steps[0].enabled = False
    assert_equal(len(frame_outputs(steps)), 1)
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    step.gtao.denoise_samples = 4
    composer.add_pass(step^)
    var image = composer.render(renderer, scene, assets, camera)
    var plain = renderer.render(scene, assets, camera)
    for y in range(SIZE):
        for x in range(SIZE):
            assert_true(
                Int(image.get_pixel(x, y).r) <= Int(plain.get_pixel(x, y).r)
            )
    with assert_raises(contains="positive"):
        _ = gtao_pass(meters(0))


# --- save and shader -----------------------------------------------------------


comptime FRAGMENT = """
uniform sampler2D tDiffuse;
uniform sampler2D tSaved;
uniform float amount;
varying vec2 vUv;
void main() {
    vec4 now = texture2D(tDiffuse, vUv);
    vec4 kept = texture2D(tSaved, vUv);
    gl_FragColor = vec4(mix(now.rgb, kept.rgb, amount), 0.5);
}
"""


def test_shader_settings_are_checked() raises:
    var settings = ShaderSettings()
    assert_true(settings.program == NO_NODES)
    assert_equal(settings.input, "tDiffuse")
    assert_equal(settings.saved, "")
    assert_equal(settings.saved_pass, -1)
    with assert_raises(contains="node program"):
        check_shader(settings)
    settings.program = NodeProgramId(0)
    check_shader(settings)
    settings.saved = "tSaved"
    with assert_raises(contains="save pass"):
        check_shader(settings)
    settings.saved_pass = 0
    check_shader(settings)
    with assert_raises(contains="node program"):
        _ = shader_pass(NO_NODES)
    with assert_raises(contains="node program"):
        check_pass(Pass(SHADER))


def test_screen_code_binds_the_samplers_and_the_time() raises:
    var program = compile_shader_material(SCREEN_VERTEX_SHADER, FRAGMENT)
    var settings = ShaderSettings(NodeProgramId(0))
    var unbound = screen_code(program, settings, 2.5)
    near(unbound[18], 2.5)
    settings.saved = "tSaved"
    settings.saved_pass = 0
    var code = screen_code(program, settings, 0)
    var found_input = False
    var found_saved = False
    for index in range(len(program.uniform_names)):
        var at = program.uniform_offsets[index]
        if program.uniform_names[index] == "tDiffuse":
            near(code[at], Float32(INPUT_SLOT))
            found_input = True
        elif program.uniform_names[index] == "tSaved":
            near(code[at], Float32(SAVED_SLOT))
            near(unbound[at], program.code[at])
            found_saved = True
    assert_true(found_input and found_saved)
    # Only a sampler that is neither bound reads the assets.
    assert_false(reads_assets(program, settings))
    assert_true(reads_assets(program, ShaderSettings(NodeProgramId(0))))


def test_a_program_without_uniforms_binds_nothing_and_reads_nothing() raises:
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.color(Color(0, 255, 0)))
    var program = graph.compile()
    assert_equal(len(program.uniform_names), 0)
    assert_equal(len(program.textures), 0)
    var settings = ShaderSettings(NodeProgramId(0))
    settings.saved = "tSaved"
    settings.saved_pass = 0
    var code = screen_code(program, settings, 1.5)
    assert_equal(len(code), len(program.code))
    near(code[18], 1.5)
    assert_false(reads_assets(program, settings))
    var frame = RenderTarget(2, 2, Color(255, 0, 0))
    shader_light(
        frame, program, settings, List[FloatColor](), TextureStore(), 0
    )
    same_color(frame.colors[0], FloatColor(0, 1, 0, 1))


def test_a_screen_source_reads_the_quad() raises:
    var colors: List[FloatColor] = [
        FloatColor(0.5, 0, 0, 0.5),
        FloatColor(0, 1, 0, 1),
        FloatColor(0, 0, 1, 1),
        FloatColor(1, 1, 1, 1),
    ]
    var kept: List[FloatColor] = [FloatColor(0.2, 0.2, 0.2, 1)]
    var code: List[Float32] = [7, 8]
    var pointer = (
        code.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked]()
    )
    var screen = ScreenNodes(
        pointer, LightView(colors, 2, 2), LightView(kept, 1, 1), 0, 0
    )
    near(screen.word(1), 8)
    same_color(screen.sample(INPUT_SLOT, 0.25, 0.75), FloatColor(1, 0, 0, 0.5))
    same_color(
        screen.sample(SAVED_SLOT, 0.5, 0.5), FloatColor(0.2, 0.2, 0.2, 1)
    )
    same_color(screen.sample(3, 0.5, 0.5), FloatColor(1, 1, 1, 1))
    var here = screen.shares(AT_FRAGMENT)
    near(here[1], 0.25)
    near(here[2], 0.75)
    near(here[0], 0)
    near(screen.shares(AT_RIGHT)[1], 0.75)
    near(screen.shares(AT_UP)[2], 1.25)
    var a = screen.corner(CORNER_A)
    var b = screen.corner(CORNER_B)
    var c = screen.corner(CORNER_C)
    near(a.position.x, -1)
    near(b.u, 1)
    near(b.position.x, 1)
    near(c.v, 1)
    near(c.position.y, 1)
    near(a.normal.z, 1)
    var store = TextureStore()
    _ = store.add(checkerboard(2, 1, Color(255, 0, 0), Color(255, 0, 0)))
    var host = HostScreenNodes(screen, Pointer(to=store))
    near(host.word(0), 7)
    near(host.sample(0, 0.5, 0.5).r, 1)
    near(host.sample(0, 0.5, 0.5).g, 0)
    same_color(host.sample(INPUT_SLOT, 0.25, 0.75), FloatColor(1, 0, 0, 0.5))
    near(host.shares(AT_UP)[2], 1.25)
    near(host.corner(CORNER_B).u, 1)
    _ = colors^
    _ = kept^
    _ = code^


def program_of(var graph: NodeGraph) raises -> NodeProgram:
    """Return a compiled graph."""
    return graph.compile()


def run(
    program: NodeProgram, view: LightView, color: FloatColor
) raises -> FloatColor:
    """Return one pixel of a program on the screen quad."""
    var code = program.code.copy()
    var pointer = (
        code.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked]()
    )
    var result = screen_pixel(
        ScreenNodes(pointer, view, view, 0, 0), color, 0.25, 0.75
    )
    _ = code^
    return result


def test_screen_pixel_follows_each_output() raises:
    var colors = List[FloatColor](
        length=4, fill=FloatColor(0.25, 0.5, 0.75, 0.5)
    )
    var view = LightView(colors, 2, 2)
    var color = FloatColor(0.25, 0.5, 0.75, 0.5)

    # A mask that keeps the fragment and no other output keeps the pixel.
    var none = NodeGraph()
    none.set_output(MASK_NODE, none.float(1))
    same_color(run(none.compile(), view, color), color)
    # The color node: straight, then premultiplied by the kept alpha.
    var tinted = NodeGraph()
    tinted.set_output(COLOR_NODE, tinted.color(Color(255, 0, 0)))
    same_color(run(tinted.compile(), view, color), FloatColor(0.5, 0, 0, 0.5))
    # The output node wins over the color node, and the opacity is its own.
    var both = NodeGraph()
    both.set_output(COLOR_NODE, both.color(Color(255, 0, 0)))
    both.set_output(OUTPUT_NODE, both.color(Color(0, 255, 0)))
    both.set_output(OPACITY_NODE, both.float(0.25))
    same_color(run(both.compile(), view, color), FloatColor(0, 0.25, 0, 0.25))
    # The mask throws the fragment away where it is zero.
    var masked = NodeGraph()
    masked.set_output(COLOR_NODE, masked.color(Color(255, 0, 0)))
    masked.set_output(MASK_NODE, masked.float(0))
    same_color(run(masked.compile(), view, color), color)
    var kept = NodeGraph()
    kept.set_output(COLOR_NODE, kept.color(Color(255, 0, 0)))
    kept.set_output(MASK_NODE, kept.float(1))
    same_color(run(kept.compile(), view, color), FloatColor(0.5, 0, 0, 0.5))
    _ = colors^


def test_shader_light_runs_a_program_over_the_frame() raises:
    var program = compile_shader_material(SCREEN_VERTEX_SHADER, FRAGMENT)
    program.set_uniform("amount", Float32(0.5))
    var settings = ShaderSettings(NodeProgramId(0))
    settings.saved = "tSaved"
    settings.saved_pass = 0
    var frame = RenderTarget(2, 2, Color(255, 0, 0))
    frame.data[0] = True
    var saved = List[FloatColor](length=4, fill=FloatColor(0, 0, 1, 1))
    var store = TextureStore()
    shader_light(frame, program, settings, saved, store, 0)
    same_color(frame.colors[0], FloatColor(0.25, 0, 0.25, 0.5))
    assert_false(frame.data[0])
    # Before a save pass has run its image is transparent black.
    var early = RenderTarget(2, 2, Color(255, 0, 0))
    shader_light(early, program, settings, List[FloatColor](), store, 0)
    same_color(early.colors[3], FloatColor(0.25, 0, 0, 0.5))
    with assert_raises(contains="frame's size"):
        shader_light(
            early,
            program,
            settings,
            List[FloatColor](length=3, fill=FloatColor(0, 0, 0, 0)),
            store,
            0,
        )
    # A program that reads a texture that is not in the store is refused.
    var textured = NodeGraph()
    var sampler = textured.texture_uniform("map", TextureId(0))
    textured.set_output(
        COLOR_NODE,
        textured.swizzle(textured.texture(sampler, textured.uv()), "rgb"),
    )
    var reads = textured.compile()
    with assert_raises(contains="not there"):
        shader_light(
            early, reads, ShaderSettings(NodeProgramId(0)), saved, store, 0
        )
    _ = store.add(checkerboard(2, 1, Color(0, 255, 0), Color(0, 255, 0)))
    shader_light(
        early, reads, ShaderSettings(NodeProgramId(0)), saved, store, 0
    )
    same_color(early.colors[0], FloatColor(0, 0.5, 0, 0.5))


def test_the_composer_saves_the_frame_and_a_shader_reads_it() raises:
    var assets = Assets()
    var scene = room(assets)
    var camera = a_camera()
    var renderer = a_renderer()
    var program = compile_shader_material(SCREEN_VERTEX_SHADER, FRAGMENT)
    program.set_uniform("amount", Float32(1))
    var id = assets.programs.add(program^)
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    var saving = save_pass()
    assert_true(saving.kind == SAVE)
    composer.add_pass(saving^)
    composer.add_pass(copy_pass(0.5))
    var shader = shader_pass(id, "tDiffuse")
    shader.shader.saved = "tSaved"
    shader.shader.saved_pass = 1
    composer.add_pass(shader^)
    assert_equal(len(composer.saved_image(1)), 0)
    var image = composer.render(renderer, scene, assets, camera, 0.5)
    var kept = composer.saved_image(1)
    assert_equal(len(kept), SIZE * SIZE)
    near(composer.passes[3].time, 0.5)
    # The shader shows the saved frame, at half opacity.
    assert_equal(Int(image.get_pixel(4, 6).a), 128)
    with assert_raises(contains="no pass"):
        _ = composer.saved_image(9)
    with assert_raises(contains="no pass"):
        _ = composer.saved_image(-1)
    with assert_raises(contains="Only a save pass"):
        _ = composer.saved_image(0)
    # A save pass put straight into the list has kept nothing yet.
    composer.passes.append(save_pass())
    assert_equal(len(composer.saved_image(4)), 0)
    # A shader with no saved sampler reads nothing saved.
    var plain = EffectComposer()
    plain.add_pass(render_pass())
    plain.add_pass(shader_pass(id))
    _ = plain.render(renderer, scene, assets, camera)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
