# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the renderer's hooks, its override material, its sorts, its
automatic clear, its `info` and its custom tone mapping, and for the
material flags as the renderer hands them on: three.js's `WebGLRenderer`,
`Object3D` and `Material` fields of issue #170."""

from cameras.array_camera import ArrayCamera
from cameras.orthographic_camera import OrthographicCamera, centered
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import ambient_light, directional_light, point_light
from materials.material import (
    BACK_SIDE,
    BASIC,
    DOUBLE_SIDE,
    FRONT_SIDE,
    Material,
    MaterialId,
    NORMALS,
    PointSize,
    line_dashed_material,
    line_material,
    normal_material,
    physical_material,
    points_material,
    sprite_material,
)
from materials.nodes import NO_NODES, NodeGraph, NodeProgramId, OUTPUT_NODE
from math.vector3 import Vector3
from objects.line import Line, SEGMENTS
from objects.line_segments2 import LineSegments2, line_segments_geometry
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import Sprite
from render.framebuffer import Color, FloatColor, Framebuffer
from render.raster_state import REPLACE_STENCIL_OP
from render.rasterizer import (
    DRAW_POINTS,
    DRAW_SEGMENTS,
    DRAW_TRIANGLES,
    SHADE_TEXTURE,
    SHADE_UV,
)
from render.rect import Rect
from render.target import (
    OUTPUT_COLOR,
    OUTPUT_NORMAL,
    RenderTarget,
    TargetOutput,
    UNSIGNED_BYTE_TARGET,
)
from render.tonemap import CUSTOM_TONE_MAPPING, NO_TONE_MAPPING
from renderers.renderer import NoHooks, RenderHooks, RenderItem, Renderer
from std.math import inf, pi
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 16
comptime BLACK = Color(0, 0, 0)
comptime RED = Color(255, 0, 0)
comptime GREEN = Color(0, 255, 0)
comptime BLUE = Color(0, 0, 255)
comptime FULL = Float32(pi)


def a_camera() raises -> OrthographicCamera:
    """Return a camera looking down -z at a two-meter square of world."""
    var camera = centered(
        Length(2.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def sticks(var numbers: List[Float32]) raises -> BufferGeometry:
    """Return a geometry holding `numbers` as positions, three per point."""
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(numbers^, 3))
    return geometry^


@fieldwise_init
struct Busy(Movable):
    """A scene with one of each kind of object, and its assets."""

    var scene: Scene
    var assets: Assets
    var mesh: NodeId
    var plane_material: MaterialId


def busy(
    mesh: Material,
    line: Material,
    dots: Material,
    sign: Material,
    wide: Material,
) raises -> Busy:
    """Return a scene holding a plane, a line, points, a sprite and a wide
    line, each drawn with its material, and each on its own node."""
    var assets = Assets()
    var scene = Scene()
    var mesh_node = scene.add(Object3D())
    var sheet = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var paint = assets.materials.add(mesh)
    scene.add_mesh(Mesh(sheet, paint, mesh_node))
    var line_node = scene.add(Object3D())
    scene.node(line_node).set_position(0, 0, 0.5)
    var stroke = assets.geometries.add(
        sticks([-0.8, -0.2, 0.0, 0.8, -0.2, 0.0])
    )
    scene.add_line(
        Line(stroke, assets.materials.add(line), line_node, mode=SEGMENTS)
    )
    var dot_node = scene.add(Object3D())
    scene.node(dot_node).set_position(0, 0, 0.6)
    var cloud = assets.geometries.add(sticks([0.5, 0.5, 0.0]))
    scene.add_points(Points(cloud, assets.materials.add(dots), dot_node))
    var sign_node = scene.add(Object3D())
    scene.node(sign_node).set_position(-0.5, 0.5, 0.7)
    scene.add_sprite(Sprite(assets.materials.add(sign), sign_node))
    var wide_node = scene.add(Object3D())
    scene.node(wide_node).set_position(0, 0, 0.8)
    var ribbon = assets.geometries.add(
        line_segments_geometry([Vector3(-0.8, 0.3, 0), Vector3(0.8, 0.3, 0)])
    )
    scene.add_wide_line(
        LineSegments2(ribbon, assets.materials.add(wide), wide_node)
    )
    scene.update()
    return Busy(scene^, assets^, mesh_node, paint)


def a_busy_scene() raises -> Busy:
    """Return `busy` with a visible basic material on everything."""
    return busy(
        Material(RED, kind=BASIC),
        line_material(GREEN),
        points_material(BLUE, size=PointSize(3)),
        sprite_material(Color(255, 255, 0)),
        line_material(Color(255, 255, 255)),
    )


struct Recorder(Movable, RenderHooks):
    """Hooks that write down what ran, in order."""

    var log: List[String]
    var nodes: List[Int]
    var shadow_nodes: List[Int]
    var shadow_lights: List[Int]
    var shadow_materials: List[Int]

    def __init__(out self):
        self.log = List[String]()
        self.nodes = List[Int]()
        self.shadow_nodes = List[Int]()
        self.shadow_lights = List[Int]()
        self.shadow_materials = List[Int]()

    def on_before_scene(mut self, scene: Scene) raises:
        self.log.append("scene")

    def on_after_scene(mut self, scene: Scene) raises:
        self.log.append("done")

    def on_before_render(mut self, scene: Scene, item: RenderItem) raises:
        self.log.append("before")
        self.nodes.append(item.node.value)

    def on_after_render(mut self, scene: Scene, item: RenderItem) raises:
        self.log.append("after")

    def on_before_shadow(
        mut self, scene: Scene, item: RenderItem, light: Int
    ) raises:
        self.log.append("shadow")
        self.shadow_nodes.append(item.node.value)
        self.shadow_lights.append(light)
        self.shadow_materials.append(item.material.value)


struct Refuser(Movable, RenderHooks):
    """Hooks that refuse the frame before it is drawn."""

    def __init__(out self):
        pass

    def on_before_render(mut self, scene: Scene, item: RenderItem) raises:
        raise Error("refused by a hook")


def _count(log: List[String], word: String) -> Int:
    """Return how many entries of a log are `word`."""
    var count = 0
    for entry in log:
        if entry == word:
            count += 1
    return count


# --- hooks and info -------------------------------------------------------


def test_the_hooks_run_around_every_run_in_order() raises:
    var made = a_busy_scene()
    var renderer = Renderer(SIZE, SIZE)
    var hooks = Recorder()
    _ = renderer.render_with(hooks, made.scene, made.assets, a_camera())
    var info = renderer.info()
    assert_equal(info.frame, 1)
    assert_equal(info.calls, 5)
    assert_true(info.triangles >= 4, "the plane and the sprite drew")
    assert_true(info.lines >= 1)
    assert_equal(info.points, 1)
    assert_equal(hooks.log[0], "scene")
    assert_equal(hooks.log[len(hooks.log) - 1], "done")
    assert_equal(_count(hooks.log, "before"), 5)
    assert_equal(_count(hooks.log, "after"), 5)
    # Every before comes before every after: the frame is rasterized
    # between the two.
    assert_equal(hooks.log[5], "before")
    assert_equal(hooks.log[6], "after")
    # The runs name their nodes: the plane's is among them.
    var named = False
    for node in hooks.nodes:
        if node == made.mesh.value:
            named = True
    assert_true(named)
    # The items the frame carries say what drew each run.
    var frame = renderer.prepare_frame(made.scene, made.assets, a_camera())
    assert_equal(len(frame.items), len(frame.draws))
    var sprites = 0
    for index in range(len(frame.items)):
        ref item = frame.items[index]
        assert_true(item.kind == frame.draws[index].kind)
        assert_equal(item.count, frame.draws[index].count)
        if item.geometry.value < 0:
            sprites += 1
    assert_equal(sprites, 1)
    # A hook that raises stops the frame.
    var refuser = Refuser()
    with assert_raises(contains="refused by a hook"):
        _ = renderer.render_with(refuser, made.scene, made.assets, a_camera())


def test_info_counts_frames_and_keeps_counts_when_asked() raises:
    var made = a_busy_scene()
    var renderer = Renderer(SIZE, SIZE)
    assert_equal(renderer.info().frame, 0)
    _ = renderer.render(made.scene, made.assets, a_camera())
    _ = renderer.render(made.scene, made.assets, a_camera())
    assert_equal(renderer.info().frame, 2)
    assert_equal(renderer.info().calls, 5)
    renderer.info_auto_reset = False
    _ = renderer.render(made.scene, made.assets, a_camera())
    assert_equal(renderer.info().calls, 10)
    renderer.reset_info()
    assert_equal(renderer.info().calls, 0)
    assert_equal(renderer.info().triangles, 0)
    assert_equal(renderer.info().frame, 3)
    # A supersampled frame is counted by the renderer asked for it, and
    # its hooks run.
    renderer.info_auto_reset = True
    renderer.set_antialias(True)
    var hooks = Recorder()
    _ = renderer.render_with(hooks, made.scene, made.assets, a_camera())
    assert_equal(renderer.info().frame, 4)
    assert_equal(renderer.info().calls, 5)
    assert_equal(_count(hooks.log, "before"), 5)
    # An array camera is one frame, however many cameras it holds, and
    # its runs add up.
    renderer.set_antialias(False)
    var eye = PerspectiveCamera(
        Angle(60.0, DEGREE), 1.0, Length(0.1, METER), Length(20.0, METER)
    )
    eye.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var array = ArrayCamera()
    array.add(eye, Rect(0, 0, SIZE // 2, SIZE))
    array.add(eye, Rect(SIZE // 2, 0, SIZE // 2, SIZE))
    _ = renderer.render_array(made.scene, made.assets, array)
    assert_equal(renderer.info().frame, 5)
    assert_equal(renderer.info().calls, 10)


# --- visible and the override --------------------------------------------


def test_a_material_that_is_not_visible_draws_nothing() raises:
    var hidden = Material(RED, kind=BASIC)
    hidden.visible = False
    var line = line_material(GREEN)
    line.visible = False
    var dots = points_material(BLUE)
    dots.visible = False
    var sign = sprite_material(Color(255, 255, 0))
    sign.visible = False
    var wide = line_material(Color(255, 255, 255))
    wide.visible = False
    var made = busy(hidden, line, dots, sign, wide)
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    var image = renderer.render(made.scene, made.assets, a_camera())
    assert_equal(renderer.info().calls, 0)
    for y in range(SIZE):
        for x in range(SIZE):
            assert_equal(image.get_pixel(x, y).r, 0)


def test_the_override_material_draws_every_object() raises:
    var made = a_busy_scene()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    var blue = made.assets.materials.add(Material(BLUE, kind=BASIC))
    made.scene.override_material = blue
    var image = renderer.render(made.scene, made.assets, a_camera())
    var corner = image.get_pixel(1, SIZE - 2)
    assert_equal(corner.r, 0)
    assert_equal(corner.b, 255)
    var frame = renderer.prepare_frame(made.scene, made.assets, a_camera())
    for index in range(len(frame.items)):
        assert_equal(frame.items[index].material, blue)
    # A material that does not allow it keeps its own.
    made.assets.materials.materials[
        made.plane_material.value
    ].allow_override = False
    var kept = renderer.render(made.scene, made.assets, a_camera())
    assert_equal(kept.get_pixel(1, SIZE - 2).r, 255)
    # An empty scene has nothing to draw with it.
    var bare = Scene()
    bare.override_material = blue
    _ = renderer.render(bare, made.assets, a_camera())
    # An override a line cannot draw with is refused.
    made.scene.override_material = made.assets.materials.add(normal_material())
    with assert_raises(contains="must be BASIC"):
        _ = renderer.render(made.scene, made.assets, a_camera())


def test_an_override_sorts_by_each_objects_own_material() raises:
    # A translucent object drawn with an opaque override stays in the
    # translucent list, after the opaque one, as three.js keeps its lists.
    var assets = Assets()
    var scene = Scene()
    var near = scene.add(Object3D())
    scene.node(near).set_position(0, 0, 1)
    var far = scene.add(Object3D())
    var sheet = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var glass = assets.materials.add(
        Material(RED, opacity=0.5, kind=BASIC, transparent=True)
    )
    var solid = assets.materials.add(Material(GREEN, kind=BASIC))
    scene.add_mesh(Mesh(sheet, glass, near))
    scene.add_mesh(Mesh(sheet, solid, far))
    scene.update()
    scene.override_material = assets.materials.add(Material(BLUE, kind=BASIC))
    var renderer = Renderer(SIZE, SIZE)
    var frame = renderer.prepare_frame(scene, assets, a_camera())
    assert_equal(frame.items[0].node, far)
    assert_equal(frame.items[1].node, near)


def test_an_opaque_override_leaves_nothing_to_transmit() raises:
    # A frame drawn with an opaque override has no transmissive run, so it
    # has no transmission pass, as three.js skips it under an override.
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var sheet = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var clear = physical_material(Color(255, 255, 255), transmission=1.0)
    scene.add_mesh(Mesh(sheet, assets.materials.add(clear), node))
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    var seen = renderer.transmission_target(scene, assets, a_camera())
    assert_true(seen.image.width > 0)
    scene.override_material = assets.materials.add(Material(RED, kind=BASIC))
    var skipped = renderer.transmission_target(scene, assets, a_camera())
    assert_equal(skipped.image.width, 0)
    _ = renderer.render(scene, assets, a_camera())


# --- sorts ----------------------------------------------------------------


def nearest_first(a: RenderItem, b: RenderItem) -> Bool:
    """Draw the nearer run first."""
    return a.z < b.z


def furthest_first(a: RenderItem, b: RenderItem) -> Bool:
    """Draw the further run first."""
    return a.z > b.z


def sheets(opacity: Float32, transmission: Float32) raises -> Busy:
    """Return three sheets at three depths, in scene order middle, near,
    far, each translucent or transmissive or neither."""
    var assets = Assets()
    var scene = Scene()
    var sheet = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var paint = Material(RED, kind=BASIC)
    if opacity < 1:
        paint = Material(RED, opacity=opacity, kind=BASIC, transparent=True)
    if transmission > 0:
        paint = physical_material(RED, transmission=transmission)
    var id = assets.materials.add(paint)
    var first = NodeId(0)
    for depth in [Float32(0.5), Float32(1.0), Float32(0.0)]:
        var node = scene.add(Object3D())
        scene.node(node).set_position(0, 0, depth)
        scene.add_mesh(Mesh(sheet, id, node))
        first = node
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    scene.update()
    return Busy(scene^, assets^, first, id)


def _depths(frame_items: List[RenderItem]) -> List[Float32]:
    """Return each item's distance ahead of the camera."""
    var out = List[Float32]()
    for item in frame_items:
        out.append(item.z)
    return out^


def test_a_caller_sorts_the_opaque_runs() raises:
    var made = sheets(1, 0)
    var renderer = Renderer(SIZE, SIZE)
    var plain = _depths(
        renderer.prepare_frame(made.scene, made.assets, a_camera()).items
    )
    assert_true(plain[0] < plain[1] and plain[1] < plain[2])
    renderer.set_opaque_sort(furthest_first)
    var turned = _depths(
        renderer.prepare_frame(made.scene, made.assets, a_camera()).items
    )
    assert_true(turned[0] > turned[1] and turned[1] > turned[2])
    renderer.set_opaque_sort(nearest_first)
    var kept = _depths(
        renderer.prepare_frame(made.scene, made.assets, a_camera()).items
    )
    assert_true(kept[0] < kept[1] and kept[1] < kept[2])
    renderer.set_opaque_sort(None)
    _ = renderer.render(made.scene, made.assets, a_camera())


def test_translucent_lines_and_points_join_the_blended_runs() raises:
    var made = busy(
        Material(RED, kind=BASIC),
        line_material(GREEN, opacity=0.5, transparent=True),
        points_material(BLUE, opacity=0.5, transparent=True),
        sprite_material(Color(255, 255, 0)),
        line_material(Color(255, 255, 255)),
    )
    var renderer = Renderer(SIZE, SIZE)
    var frame = renderer.prepare_frame(made.scene, made.assets, a_camera())
    # The opaque plane and wide line first, then the blended runs: the
    # sprite, the line and the points, furthest first.
    assert_true(frame.items[len(frame.items) - 1].kind == DRAW_TRIANGLES)
    var last_kinds = 0
    for index in range(2, len(frame.items)):
        if frame.items[index].kind != DRAW_TRIANGLES:
            last_kinds += 1
    assert_equal(last_kinds, 2)


def test_a_caller_sorts_the_translucent_and_transmissive_runs() raises:
    var renderer = Renderer(SIZE, SIZE)
    for kind in range(2):
        var made = sheets(0.5, 0) if kind == 0 else sheets(1, 0.5)
        var plain = _depths(
            renderer.prepare_frame(made.scene, made.assets, a_camera()).items
        )
        assert_true(plain[0] > plain[1] and plain[1] > plain[2])
        renderer.set_transparent_sort(nearest_first)
        var turned = _depths(
            renderer.prepare_frame(made.scene, made.assets, a_camera()).items
        )
        assert_true(turned[0] < turned[1] and turned[1] < turned[2])
        renderer.set_transparent_sort(None)


# --- the automatic clear --------------------------------------------------


def test_a_frame_clears_only_what_auto_clear_says() raises:
    var made = a_busy_scene()
    var empty = Scene()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    var target = RenderTarget(SIZE, SIZE, BLACK)
    renderer.render_into(target, made.scene, made.assets, a_camera())
    assert_true(target.color_at(1, SIZE - 2).r > 0.5)
    # Off, nothing is cleared.
    renderer.auto_clear = False
    renderer.render_into(target, empty, made.assets, a_camera())
    assert_true(target.color_at(1, SIZE - 2).r > 0.5)
    assert_true(target.depth_at(1, SIZE - 2) < inf[DType.float32]())
    # On, but not the color: the depth is cleared and the color kept.
    renderer.auto_clear = True
    renderer.auto_clear_color = False
    renderer.render_into(target, empty, made.assets, a_camera())
    assert_true(target.color_at(1, SIZE - 2).r > 0.5)
    assert_equal(target.depth_at(1, SIZE - 2), inf[DType.float32]())
    # And the other way round.
    renderer.render_into(target, made.scene, made.assets, a_camera())
    renderer.auto_clear_color = True
    renderer.auto_clear_depth = False
    renderer.render_into(target, empty, made.assets, a_camera())
    assert_equal(target.color_at(1, SIZE - 2).r, 0)
    assert_true(target.depth_at(1, SIZE - 2) < inf[DType.float32]())


def test_the_stencil_is_kept_unless_auto_clear_stencil() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var sheet = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var marking = Material(RED, kind=BASIC)
    marking.stencil_write = True
    marking.stencil_ref = 7
    marking.stencil_z_pass = REPLACE_STENCIL_OP
    scene.add_mesh(Mesh(sheet, assets.materials.add(marking), node))
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    var target = RenderTarget(SIZE, SIZE, BLACK)
    renderer.render_into(target, scene, assets, a_camera())
    assert_equal(target.stencil_at(4, 4), 7)
    renderer.auto_clear_stencil = False
    renderer.render_into(target, Scene(), assets, a_camera())
    assert_equal(target.stencil_at(4, 4), 7)
    renderer.auto_clear_stencil = True
    renderer.render_into(target, Scene(), assets, a_camera())
    assert_equal(target.stencil_at(4, 4), 0)


def test_a_renderer_clears_a_target_by_hand() raises:
    var made = a_busy_scene()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    var target = RenderTarget(SIZE, SIZE, BLACK)
    renderer.render_into(target, made.scene, made.assets, a_camera())
    renderer.clear(target, color=False)
    assert_true(target.color_at(1, SIZE - 2).r > 0.5)
    assert_equal(target.depth_at(1, SIZE - 2), inf[DType.float32]())
    # With the scissor test on, the scissor alone.
    renderer.set_scissor(Rect(0, 0, 4, 4))
    renderer.set_scissor_test(True)
    renderer.clear(target)
    assert_equal(target.color_at(1, SIZE - 2).r, 0)
    assert_true(target.color_at(1, 1).r > 0.5)
    var small = RenderTarget(4, 4, BLACK)
    with assert_raises(contains="renderer's size"):
        renderer.clear(small)
    var short = RenderTarget(SIZE, 4, BLACK)
    with assert_raises(contains="renderer's size"):
        renderer.clear(short)
    # A target's normals go with its color: kept when the color is.
    var outputs: List[TargetOutput] = [OUTPUT_COLOR, OUTPUT_NORMAL]
    var deep = RenderTarget(SIZE, SIZE, BLACK, UNSIGNED_BYTE_TARGET, outputs)
    renderer.set_scissor_test(False)
    renderer.render_into(deep, made.scene, made.assets, a_camera())
    assert_true(deep.normals[SIZE * (SIZE - 2) + 1].length() > 0)
    renderer.clear(deep, color=False)
    assert_true(deep.normals[SIZE * (SIZE - 2) + 1].length() > 0)
    renderer.clear(deep)
    assert_equal(deep.normals[SIZE * (SIZE - 2) + 1].length(), 0)


# --- the custom tone mapping ----------------------------------------------


def test_a_custom_curve_runs_its_program() raises:
    var made = a_busy_scene()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    var plain = renderer.render(made.scene, made.assets, a_camera())
    # With no program, three.js's default custom curve leaves the light
    # as it is.
    renderer.set_tone_mapping(CUSTOM_TONE_MAPPING)
    var same = renderer.render(made.scene, made.assets, a_camera())
    assert_equal(same.get_pixel(1, SIZE - 2).r, plain.get_pixel(1, SIZE - 2).r)
    # A program maps the light: here, to a quarter of it.
    var graph = NodeGraph()
    graph.set_output(OUTPUT_NODE, graph.mul(graph.lit(), graph.float(0.25)))
    renderer.custom_tone_mapping = made.assets.programs.add(graph.compile())
    var dim = renderer.render(made.scene, made.assets, a_camera())
    var red = dim.get_pixel(1, SIZE - 2).r
    assert_true(red > 100 and red < 200, "the curve did not map the light")
    renderer.set_antialias(True)
    var smooth = renderer.render(made.scene, made.assets, a_camera())
    assert_equal(smooth.get_pixel(1, SIZE - 2).r, red)
    renderer.set_antialias(False)
    # The uv view is never tone mapped, whatever the curve.
    renderer.set_shading(SHADE_UV)
    assert_equal(len(renderer.curve_program(made.assets)), 0)
    renderer.set_shading(SHADE_TEXTURE)
    # A program that is not there is refused.
    renderer.custom_tone_mapping = NodeProgramId(9)
    with assert_raises(contains="No node program"):
        _ = renderer.render(made.scene, made.assets, a_camera())
    renderer.custom_tone_mapping = NO_NODES
    renderer.set_tone_mapping(NO_TONE_MAPPING)
    assert_equal(len(renderer.curve_program(made.assets)), 0)


# --- the flags the renderer hands on --------------------------------------


def test_each_primitive_keeps_the_flags_its_three_js_shader_reads() raises:
    var mesh = Material(RED, kind=BASIC)
    var line = line_material(GREEN)
    var dots = points_material(BLUE)
    var sign = sprite_material(Color(255, 255, 0))
    var wide = line_material(Color(255, 255, 255))
    mesh.dithering = True
    mesh.alpha_hash = True
    mesh.premultiplied_alpha = True
    line.dithering = True
    line.premultiplied_alpha = True
    dots.dithering = True
    dots.premultiplied_alpha = True
    sign.dithering = True
    sign.alpha_hash = True
    sign.premultiplied_alpha = True
    wide.dithering = True
    wide.premultiplied_alpha = True
    var made = busy(mesh, line, dots, sign, wide)
    var renderer = Renderer(SIZE, SIZE)
    var frame = renderer.prepare_frame(made.scene, made.assets, a_camera())
    var sprites = 0
    for index in range(len(frame.items)):
        ref item = frame.items[index]
        var first = frame.draws[index].first
        if item.kind == DRAW_POINTS:
            var state = frame.points[first].state
            assert_false(state.dithering)
            assert_true(state.premultiplied_alpha)
        elif item.kind == DRAW_SEGMENTS:
            var state = frame.segments[first * 2].state
            assert_true(state.dithering)
            assert_true(state.premultiplied_alpha)
        elif item.geometry.value < 0:
            var state = frame.corners[first * 3].state
            assert_false(state.dithering)
            assert_true(state.alpha_hash)
            assert_false(state.premultiplied_alpha)
            sprites += 1
        elif item.node == made.mesh:
            var state = frame.corners[first * 3].state
            assert_true(state.dithering)
            assert_true(state.alpha_hash)
            assert_true(state.premultiplied_alpha)
        else:
            var state = frame.corners[first * 3].state
            assert_false(state.dithering)
            assert_false(state.alpha_hash)
            assert_true(state.premultiplied_alpha)
    assert_equal(sprites, 1)
    # A dashed line is three.js's dashed shader, which does not dither;
    # a normal material neither dithers nor hashes.
    var dashed = line_dashed_material(GREEN)
    dashed.dithering = True
    var normals = normal_material()
    normals.dithering = True
    normals.alpha_hash = True
    var plain = busy(normals, dashed, points_material(BLUE), sign, wide)
    var shown = renderer.prepare_frame(plain.scene, plain.assets, a_camera())
    for index in range(len(shown.items)):
        ref item = shown.items[index]
        var first = shown.draws[index].first
        if item.kind == DRAW_SEGMENTS:
            assert_false(shown.segments[first * 2].state.dithering)
        elif item.node == plain.mesh:
            assert_false(shown.corners[first * 3].state.dithering)
            assert_false(shown.corners[first * 3].state.alpha_hash)


# --- shadows --------------------------------------------------------------


def lit_floor(
    light: String,
    cast: Material,
    custom: Optional[Material] = None,
) raises -> Busy:
    """Return a floor at the origin under a caster a meter above it, lit
    from straight above by a casting `"sun"` or `"bulb"`. The caster is a
    horizontal sheet facing down, drawn with `cast`, and drawn into the
    light's map with `custom` when there is one."""
    var assets = Assets()
    var scene = Scene()
    var ground = Object3D()
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var ground_node = scene.add(ground^)
    var lift = Object3D()
    lift.set_position(0, 1.0, 0)
    lift.set_euler(Angle(90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE))
    var lift_node = scene.add(lift^)
    var floor = assets.geometries.add(
        plane(Length(6.0, METER), Length(6.0, METER))
    )
    var sheet = assets.geometries.add(
        plane(Length(1.5, METER), Length(1.5, METER))
    )
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    var caster_paint = assets.materials.add(cast)
    scene.add_mesh(Mesh(floor, paint, ground_node, receive_shadow=True))
    var caster = Mesh(sheet, caster_paint, lift_node, cast_shadow=True)
    var given = Bool(custom)
    if given:
        var id = assets.materials.add(custom.value())
        caster.custom_depth_material = id
        caster.custom_distance_material = id
    scene.add_mesh(caster)
    var lamp = Object3D()
    lamp.set_position(0, 4, 0)
    var node = scene.add(lamp^)
    if light == "bulb":
        var bulb = point_light(Color(255, 255, 255), node, 25 * FULL)
        bulb.cast_shadow = True
        bulb.shadow.map_size = 64
        bulb.shadow.bias = -0.002
        scene.add_light(bulb)
    else:
        var sun = directional_light(Color(255, 255, 255), node, FULL)
        sun.cast_shadow = True
        sun.shadow.map_size = 64
        sun.shadow.bias = -0.002
        scene.add_light(sun)
    scene.update()
    return Busy(scene^, assets^, lift_node, caster_paint)


def shadowed(made: Busy, mut hooks: Recorder) raises -> Bool:
    """Return True if the floor straight under the caster is darker than
    the floor at the edge of the view, seen from above."""
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1.0, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 6, 0.01), Vector3(0, 0, 0))
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    var image = renderer.render_with(hooks, made.scene, made.assets, camera)
    var under = image.get_pixel(SIZE // 2, SIZE // 2).r
    var beside = image.get_pixel(1, SIZE // 2).r
    return Int(under) + 40 < Int(beside)


def test_a_shadow_draws_the_faces_its_shadow_side_names() raises:
    # A sheet facing away from the light draws no front face into the
    # map, and casts nothing; its shadow side draws the faces it names.
    var hooks = Recorder()
    var front = Material(Color(200, 60, 60))
    assert_false(shadowed(lit_floor("sun", front), hooks))
    var both = Material(Color(200, 60, 60))
    both.shadow_side = DOUBLE_SIDE
    assert_true(shadowed(lit_floor("sun", both), hooks))
    var back = Material(Color(200, 60, 60))
    back.shadow_side = BACK_SIDE
    assert_true(shadowed(lit_floor("sun", back), hooks))
    # The side the shadow names, not the one the frame draws.
    var shown_both = Material(Color(200, 60, 60), side=DOUBLE_SIDE)
    shown_both.shadow_side = FRONT_SIDE
    assert_false(shadowed(lit_floor("sun", shown_both), hooks))


def test_the_shadow_hook_sees_each_caster_of_each_light() raises:
    var both = Material(Color(200, 60, 60))
    both.shadow_side = DOUBLE_SIDE
    var sun = lit_floor("sun", both)
    var hooks = Recorder()
    assert_true(shadowed(sun, hooks))
    assert_equal(len(hooks.shadow_nodes), 1)
    assert_equal(hooks.shadow_nodes[0], sun.mesh.value)
    assert_equal(hooks.shadow_lights[0], 0)
    assert_equal(hooks.shadow_materials[0], sun.plane_material.value)
    # Before the frame's runs.
    assert_equal(hooks.log[1], "shadow")
    # A point light's cube calls it once a face that draws the caster.
    var bulb = lit_floor("bulb", both)
    var cube_hooks = Recorder()
    assert_true(shadowed(bulb, cube_hooks))
    assert_true(len(cube_hooks.shadow_nodes) >= 1)


def test_a_custom_depth_or_distance_material_draws_the_shadow() raises:
    var both = Material(Color(200, 60, 60))
    both.shadow_side = DOUBLE_SIDE
    # A custom material that cuts everything away casts nothing, for a
    # sun through its depth material and a bulb through its distance one.
    var cut = Material(Color(200, 60, 60), opacity=0.2, alpha_test=0.5)
    for light in ["sun", "bulb"]:
        var hooks = Recorder()
        var made = lit_floor(light, both, cut)
        assert_false(shadowed(made, hooks))
        assert_true(len(hooks.shadow_materials) >= 1)
        assert_true(hooks.shadow_materials[0] != made.plane_material.value)


def test_a_material_that_is_not_visible_casts_nothing() raises:
    var hidden = Material(Color(200, 60, 60))
    hidden.shadow_side = DOUBLE_SIDE
    hidden.visible = False
    var hooks = Recorder()
    assert_false(
        shadowed(lit_floor("sun", hidden, Material(RED, kind=BASIC)), hooks)
    )
    assert_equal(len(hooks.shadow_nodes), 0)


def test_alpha_to_coverage_casts_through_a_test_at_one_half() raises:
    var faint = Material(Color(200, 60, 60), opacity=0.3)
    faint.shadow_side = DOUBLE_SIDE
    var hooks = Recorder()
    assert_true(shadowed(lit_floor("sun", faint), hooks))
    faint.alpha_to_coverage = True
    assert_false(shadowed(lit_floor("sun", faint), hooks))


def test_an_override_leaves_the_shadow_maps_alone() raises:
    var both = Material(Color(200, 60, 60))
    both.shadow_side = DOUBLE_SIDE
    var made = lit_floor("sun", both)
    made.scene.override_material = made.assets.materials.add(
        Material(RED, kind=BASIC)
    )
    var hooks = Recorder()
    _ = shadowed(made, hooks)
    assert_equal(hooks.shadow_materials[0], made.plane_material.value)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
