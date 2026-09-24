# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.reflector`, `objects.water` and `objects.water2`:
the objects that render the scene again from a virtual camera.

The matrices come from three.js 0.180 run under Node with a renderer that
renders nothing: `assets/scene_objects/reference.mjs` writes them to
`reference.json`. The renders are checked against what the virtual camera
must see.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.layers import Layers
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import box
from geometries.plane import plane
from loaders.json import JsonDocument, parse_json
from materials.material import BASIC, MaterialId, Material, Side
from math.bounds import Plane
from math.matrix4 import Matrix4
from math.projection import perspective
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.reflector import (
    Reflector,
    Refractor,
    VirtualCamera,
    default_virtual_camera,
    projective_matrix,
    refractor_plane,
    replace_texture,
    texture_bias,
    view_renderer,
)
from objects.water import Water
from objects.water2 import Water2, water2_fragment
from render.framebuffer import Color, Framebuffer
from render.raster_state import REVERSED_DEPTH
from render.target import RenderTarget
from render.rasterizer import SHADE_LIT
from render.texture import CLAMP, REPEAT, Texture, data_texture
from render.texture_store import NO_TEXTURE, TextureId
from renderers.renderer import Renderer
from std.math import inf, nan, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Angle,
    DEGREE,
    Duration,
    Frequency,
    Length,
    METER,
    PER_SECOND,
    RADIAN,
    SECOND,
)

comptime SIZE = 24


def meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


def reference() raises -> JsonDocument:
    """Return three.js's answers."""
    return parse_json(
        String(
            StringSlice(
                unsafe_from_utf8=open(
                    "assets/scene_objects/reference.json", "r"
                ).read_bytes()
            )
        )
    )


def assert_matrix(
    doc: JsonDocument, node: Int, key: String, got: Matrix4, atol: Float64
) raises:
    """Assert a matrix equals three.js's, element for element."""
    var want = doc.get(node, key)
    for index in range(16):
        assert_almost_equal(
            Float64(got.elements[index]),
            doc.number(doc.at(want, index)),
            atol=atol,
        )


def reference_camera() raises -> PerspectiveCamera:
    """Return the camera `reference.mjs` looks through."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1.25, meters(0.1), meters(100)
    )
    camera.place(Vector3(1, 2, 3), Vector3(0.2, -0.3, 0.1))
    return camera^


def reference_node(mut scene: Scene) raises -> NodeId:
    """Add the node `reference.mjs` places each object at."""
    var node = Object3D()
    node.set_position(0.3, -0.5, 0.2)
    node.set_euler(
        Angle(Float32(-pi / 2 + 0.2), RADIAN),
        Angle(0.1, RADIAN),
        Angle(0.3, RADIAN),
    )
    return scene.add(node^)


def square(mut assets: Assets, side: Float32) raises -> GeometryId:
    """Add a square of the given side, facing +z."""
    return assets.geometries.add(plane(meters(side), meters(side)))


def red_box(
    mut assets: Assets,
    mut scene: Scene,
    at: Vector3,
    color: Color = Color(255, 0, 0),
) raises -> NodeId:
    """Add a small unlit box at a point."""
    var node = Object3D()
    node.set_position(at.x, at.y, at.z)
    var id = scene.add(node^)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(box(meters(0.8), meters(0.8), meters(0.8))),
            assets.materials.add(Material(color, kind=BASIC)),
            id,
        )
    )
    return id


def floor_node(mut scene: Scene, height: Float32 = 0) raises -> NodeId:
    """Add a node whose +z faces up, at a height."""
    var node = Object3D()
    node.set_position(0, height, 0)
    node.set_euler(Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE))
    return scene.add(node^)


def high_camera() raises -> PerspectiveCamera:
    """Return a camera above a floor, looking down at it."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, meters(0.1), meters(100)
    )
    camera.place(Vector3(0, 2.5, 4), Vector3(0, -0.5, 0))
    return camera^


def is_red(image: Framebuffer, x: Int, y: Int) raises -> Bool:
    """Return True if a pixel is mostly red."""
    var c = image.get_pixel(x, y)
    return c.r > 150 and c.g < 80 and c.b < 80


def count_red(image: Framebuffer) raises -> Int:
    """Return how many pixels are mostly red."""
    var total = 0
    for y in range(SIZE):
        for x in range(SIZE):
            if is_red(image, x, y):
                total += 1
    return total


# --- the virtual camera ---------------------------------------------------------


def test_a_virtual_camera_is_its_matrices() raises:
    var view = Matrix4()
    view.elements[12] = 2
    var projection = perspective(-1, 1, 1, -1, 1, 10)
    var camera = VirtualCamera(view, projection, 1, 10, Layers())
    var scene = Scene()
    assert_true(camera.view_matrix() == view)
    assert_true(camera.view_matrix_in(scene) == view)
    assert_true(camera.projection_matrix() == projection)
    assert_equal(camera.near_distance(), 1)
    assert_equal(camera.far_distance(), 10)
    assert_true(camera.visible_layers() == Layers())
    var screen = camera.view_to_screen_matrix(4, 2)
    var center = screen.transform_point(Vector3(0, 0, -5))
    assert_almost_equal(center.x, 2, atol=1e-5)
    assert_almost_equal(center.y, 1, atol=1e-5)
    with assert_raises():
        _ = camera.view_to_screen_matrix(0, 2)
    var fresh = default_virtual_camera()
    assert_almost_equal(fresh.near_distance(), 0.1)
    assert_equal(fresh.far_distance(), 2000)


def test_the_bias_maps_clip_space_onto_the_texture() raises:
    var bias = texture_bias()
    var low = bias.transform_point(Vector3(-1, -1, -1))
    var high = bias.transform_point(Vector3(1, 1, 1))
    assert_equal(low.x, 0)
    assert_equal(low.z, 0)
    assert_equal(high.y, 1)
    var camera = default_virtual_camera()
    assert_true(projective_matrix(camera) == bias)


# --- the reflector ----------------------------------------------------------------


def test_a_reflector_places_its_camera_as_three_js_does() raises:
    var doc = reference()
    var assets = Assets()
    var scene = Scene()
    var node = reference_node(scene)
    var mirror = Reflector(
        assets, square(assets, 2), node, texture_width=8, texture_height=8
    )
    scene.add_mesh(mirror.mesh)
    scene.update()
    var renderer = Renderer(8, 8)
    assert_true(mirror.update(renderer, scene, assets, reference_camera()))
    var want = doc.get(doc.root(), "reflector")
    assert_matrix(doc, want, "view", mirror.camera.view, 2e-5)
    assert_matrix(doc, want, "texture_matrix", mirror.texture_matrix, 2e-5)
    # The shader's uniform stops at world space.
    var world = projective_matrix(mirror.camera)
    world.multiply(scene.world_matrix(node))
    assert_true(world == mirror.texture_matrix)
    ref program = assets.programs.get(mirror.program)
    assert_equal(
        program.uniform("textureMatrix")[0],
        projective_matrix(mirror.camera).elements[0],
    )


def mirror_scene(mut assets: Assets, mut scene: Scene) raises -> Reflector:
    """Return a mirror on the floor with a red box above it."""
    var mirror = Reflector(
        assets,
        square(assets, 6),
        floor_node(scene),
        texture_width=SIZE,
        texture_height=SIZE,
    )
    scene.add_mesh(mirror.mesh)
    _ = red_box(assets, scene, Vector3(0, 1, 0))
    scene.update()
    return mirror^


def test_a_mirror_shows_the_mirrored_scene() raises:
    var assets = Assets()
    var scene = Scene()
    var mirror = mirror_scene(assets, scene)
    var renderer = Renderer(SIZE, SIZE)
    var camera = high_camera()
    assert_true(mirror.update(renderer, scene, assets, camera))
    var image = renderer.render(scene, assets, camera)
    # The same camera sees the box itself and a box mirrored below the
    # floor. Draw both boxes with no mirror: the red pixels must agree.
    var plain_assets = Assets()
    var plain = Scene()
    _ = red_box(plain_assets, plain, Vector3(0, 1, 0))
    _ = red_box(plain_assets, plain, Vector3(0, -1, 0))
    plain.update()
    var expected = renderer.render(plain, plain_assets, camera)
    var differ = 0
    for y in range(SIZE):
        for x in range(SIZE):
            if is_red(image, x, y) != is_red(expected, x, y):
                differ += 1
    assert_true(count_red(expected) > 40)
    # The texture is sampled between its texels, so an edge can move by
    # a pixel.
    assert_true(differ <= 12)
    # The mirror's color darkens what is not red: the overlay of a dark
    # background is darker still.
    var floor = image.get_pixel(1, SIZE - 2)
    assert_true(floor.r < 16)


def test_a_mirror_seen_from_behind_renders_nothing() raises:
    var assets = Assets()
    var scene = Scene()
    var mirror = mirror_scene(assets, scene)
    var renderer = Renderer(SIZE, SIZE)
    var below = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, meters(0.1), meters(100)
    )
    below.place(Vector3(0, -2, 4), Vector3(0, 0, 0))
    assert_false(mirror.update(renderer, scene, assets, below))
    assert_true(mirror.texture_matrix == Matrix4())
    # Forced, it renders once, and the flag clears.
    mirror.force_update = True
    assert_true(mirror.update(renderer, scene, assets, below))
    assert_false(mirror.force_update)
    assert_false(mirror.update(renderer, scene, assets, below))


def test_the_mirror_is_hidden_only_while_its_view_is_drawn() raises:
    var assets = Assets()
    var scene = Scene()
    var mirror = mirror_scene(assets, scene)
    var renderer = Renderer(SIZE, SIZE)
    _ = mirror.update(renderer, scene, assets, high_camera())
    assert_true(scene.get(mirror.mesh.node).visible)
    assert_false(scene.is_stale())
    # A hidden mirror stays hidden.
    var held = scene.get(mirror.mesh.node)
    held.visible = False
    scene.set(mirror.mesh.node, held^)
    scene.update()
    _ = mirror.update(renderer, scene, assets, high_camera())
    assert_false(scene.get(mirror.mesh.node).visible)
    # A render that raises shows the mirror again before it passes the
    # error on.
    held = scene.get(mirror.mesh.node)
    held.visible = True
    scene.set(mirror.mesh.node, held^)
    scene.add_mesh(Mesh(GeometryId(99), MaterialId(0), mirror.mesh.node))
    var other = Object3D()
    var broken = scene.add(other^)
    scene.add_mesh(Mesh(GeometryId(99), MaterialId(0), broken))
    scene.update()
    with assert_raises():
        _ = mirror.update(renderer, scene, assets, high_camera())
    assert_true(scene.get(mirror.mesh.node).visible)


def test_the_plane_cuts_what_lies_behind_the_mirror() raises:
    var assets = Assets()
    var scene = Scene()
    var mirror = mirror_scene(assets, scene)
    # A blue box under the floor: the mirror must not show it.
    _ = red_box(assets, scene, Vector3(2, -1, 0), Color(0, 0, 255))
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    var camera = high_camera()
    _ = mirror.update(renderer, scene, assets, camera)
    ref seen = assets.textures.get(mirror.texture)
    var blue = 0
    for y in range(SIZE):
        for x in range(SIZE):
            var texel = seen.sample(
                (Float32(x) + 0.5) / SIZE, (Float32(y) + 0.5) / SIZE
            )
            if texel.b > 0.5 and texel.r < 0.1:
                blue += 1
    assert_equal(blue, 0)
    # A bias of a meter and a half keeps it.
    mirror.clip_bias = meters(1.5)
    _ = mirror.update(renderer, scene, assets, camera)
    ref biased = assets.textures.get(mirror.texture)
    for y in range(SIZE):
        for x in range(SIZE):
            var texel = biased.sample(
                (Float32(x) + 0.5) / SIZE, (Float32(y) + 0.5) / SIZE
            )
            if texel.b > 0.5 and texel.r < 0.1:
                blue += 1
    assert_true(blue > 0)


# --- the refractor --------------------------------------------------------------


def test_a_refractor_places_its_camera_as_three_js_does() raises:
    var doc = reference()
    var assets = Assets()
    var scene = Scene()
    var node = reference_node(scene)
    var pane = Refractor(
        assets, square(assets, 2), node, texture_width=8, texture_height=8
    )
    scene.add_mesh(pane.mesh)
    scene.update()
    var renderer = Renderer(8, 8)
    assert_true(pane.update(renderer, scene, assets, reference_camera()))
    var want = doc.get(doc.root(), "refractor")
    assert_matrix(doc, want, "view", pane.camera.view, 2e-5)
    assert_matrix(doc, want, "texture_matrix", pane.texture_matrix, 2e-5)
    # The plane faces the pane's back, through its center.
    var cut = refractor_plane(scene.world_matrix(node))
    var normal = (
        scene.world_matrix(node)
        .extract_rotation()
        .transform_direction(Vector3(0, 0, 1))
    )
    assert_almost_equal(cut.normal.dot(normal), -1, atol=1e-6)
    assert_almost_equal(
        cut.normal.dot(Vector3(0.3, -0.5, 0.2)) + cut.constant, 0, atol=1e-6
    )


def test_a_refractor_shows_what_lies_behind_it() raises:
    var assets = Assets()
    var scene = Scene()
    # A pane at z = 0 facing the camera, a red box behind it and a blue box
    # in front of it.
    var pane = Refractor(
        assets,
        square(assets, 6),
        scene.add(Object3D()),
        texture_width=SIZE,
        texture_height=SIZE,
    )
    scene.add_mesh(pane.mesh)
    _ = red_box(assets, scene, Vector3(0.8, 0, -1.5))
    _ = red_box(assets, scene, Vector3(-0.8, 0, 1.5), Color(0, 0, 255))
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, meters(0.1), meters(100)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    assert_true(pane.update(renderer, scene, assets, camera))
    ref seen = assets.textures.get(pane.texture)
    var red = 0
    var blue = 0
    for y in range(SIZE):
        for x in range(SIZE):
            var texel = seen.sample(
                (Float32(x) + 0.5) / SIZE, (Float32(y) + 0.5) / SIZE
            )
            if texel.r > 0.5 and texel.b < 0.1:
                red += 1
            if texel.b > 0.5 and texel.r < 0.1:
                blue += 1
    assert_true(red > 0)
    assert_equal(blue, 0)
    # The pane is transparent, and draws what its texture shows.
    assert_true(assets.materials.get(pane.mesh.material).transparent)
    var image = renderer.render(scene, assets, camera)
    assert_true(count_red(image) > 0)
    # From behind the pane there is nothing to refract.
    var behind = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, meters(0.1), meters(100)
    )
    behind.place(Vector3(0, 0, -5), Vector3(0, 0, 0))
    assert_false(pane.update(renderer, scene, assets, behind))


# --- what they share ------------------------------------------------------------


def test_the_view_renderer_draws_as_the_renderer_does() raises:
    var renderer = Renderer(10, 10, workers=2)
    renderer.background = Color(1, 2, 3)
    renderer.shading = SHADE_LIT
    renderer.clipping_planes = [Plane(Vector3(1, 0, 0), 0)]
    renderer.local_clipping_enabled = True
    renderer.depth_mode = REVERSED_DEPTH
    renderer.time = Duration(2.0, SECOND)
    var view = view_renderer(renderer, 4, 3)
    assert_equal(view.width, 4)
    assert_equal(view.height, 3)
    assert_equal(view.workers, 2)
    assert_equal(view.background.hex(), Color(1, 2, 3).hex())
    assert_true(view.shading == SHADE_LIT)
    assert_equal(len(view.clipping_planes), 1)
    assert_true(view.local_clipping_enabled)
    assert_true(view.depth_mode == REVERSED_DEPTH)
    assert_equal(view.time.to(SECOND), 2)


def test_the_objects_refuse_what_they_cannot_draw() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var quad = square(assets, 1)
    with assert_raises(contains="size must be positive"):
        _ = Reflector(assets, quad, node, texture_width=0)
    with assert_raises(contains="size must be positive"):
        _ = Reflector(assets, quad, node, texture_height=-1)
    with assert_raises(contains="bias must be finite"):
        _ = Reflector(
            assets, quad, node, clip_bias=meters(inf[DType.float32]())
        )
    with assert_raises(contains="size must be positive"):
        _ = Refractor(assets, quad, node, texture_width=0)
    with assert_raises(contains="bias must be finite"):
        _ = Refractor(
            assets, quad, node, clip_bias=meters(nan[DType.float32]())
        )
    with assert_raises(contains="GLSL"):
        _ = Reflector(assets, quad, node, fragment_shader="void main() { }")
    with assert_raises():
        replace_texture(assets, TextureId(999), Texture())


# --- water ------------------------------------------------------------------------


def normals_map() raises -> Texture:
    """Return a small flat normal map: every normal straight up."""
    var data = List[Float32]()
    for _ in range(16):
        data.append(0.5)
        data.append(0.5)
        data.append(1)
        data.append(1)
    var map = data_texture(4, 4, data, wrap=REPEAT)
    return map^


def test_a_water_places_its_camera_as_three_js_does() raises:
    var doc = reference()
    var assets = Assets()
    var scene = Scene()
    var node = reference_node(scene)
    var water = Water(
        assets,
        square(assets, 2),
        node,
        assets.textures.add(normals_map()),
        texture_width=8,
        texture_height=8,
    )
    scene.add_mesh(water.mesh)
    scene.update()
    var renderer = Renderer(8, 8)
    assert_true(water.update(renderer, scene, assets, reference_camera()))
    var want = doc.get(doc.root(), "water")
    assert_matrix(doc, want, "texture_matrix", water.texture_matrix, 2e-5)
    var eye = assets.programs.get(water.program).uniform("eye")
    var wanted = doc.get(want, "eye")
    for k in range(3):
        assert_almost_equal(
            Float64(eye[k]), doc.number(doc.at(wanted, k)), atol=1e-5
        )


def water_scene(mut assets: Assets, mut scene: Scene) raises -> Water:
    """Return a water on the floor with a red box above it."""
    var water = Water(
        assets,
        square(assets, 6),
        floor_node(scene),
        assets.textures.add(normals_map()),
        texture_width=SIZE,
        texture_height=SIZE,
        distortion_scale=0,
        fog=True,
    )
    scene.add_mesh(water.mesh)
    _ = red_box(assets, scene, Vector3(0, 1, 0))
    scene.update()
    return water^


def test_a_water_reflects_the_scene() raises:
    var assets = Assets()
    var scene = Scene()
    var water = water_scene(assets, scene)
    assert_true(assets.materials.get(water.mesh.material).fog)
    var renderer = Renderer(SIZE, SIZE)
    var camera = high_camera()
    assert_true(water.update(renderer, scene, assets, camera))
    var image = renderer.render(scene, assets, camera)
    # The box and its reflection, which the Fresnel term tints.
    var reflected = 0
    for y in range(SIZE // 2, SIZE):
        for x in range(SIZE):
            var c = image.get_pixel(x, y)
            if c.r > c.g + 30:
                reflected += 1
    assert_true(reflected > 10)
    # From below the water there is nothing to reflect.
    var below = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, meters(0.1), meters(100)
    )
    below.place(Vector3(0, -2, 4), Vector3(0, 0, 0))
    assert_false(water.update(renderer, scene, assets, below))


def test_a_water_keeps_its_time() raises:
    var assets = Assets()
    var scene = Scene()
    var water = water_scene(assets, scene)
    water.set_time(assets, Duration(3.5, SECOND))
    assert_equal(assets.programs.get(water.program).uniform("time")[0], 3.5)
    with assert_raises(contains="finite"):
        water.set_time(assets, Duration(inf[DType.float32](), SECOND))


def test_a_water_refuses_what_it_cannot_draw() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var quad = square(assets, 1)
    var map = assets.textures.add(normals_map())
    with assert_raises(contains="side"):
        _ = Water(assets, quad, node, map, side=Side(5))
    with assert_raises(contains="finite"):
        _ = Water(assets, quad, node, map, alpha=nan[DType.float32]())
    with assert_raises(contains="finite"):
        _ = Water(
            assets, quad, node, map, time=Duration(inf[DType.float32](), SECOND)
        )
    with assert_raises(contains="finite"):
        _ = Water(
            assets, quad, node, map, distortion_scale=inf[DType.float32]()
        )
    with assert_raises(contains="size must be positive"):
        _ = Water(assets, quad, node, map, texture_width=0)
    with assert_raises(contains="bias must be finite"):
        _ = Water(
            assets, quad, node, map, clip_bias=meters(nan[DType.float32]())
        )
    with assert_raises():
        _ = Water(assets, quad, node, NO_TEXTURE)


# --- flowing water ---------------------------------------------------------------


def flowing(
    mut assets: Assets,
    mut scene: Scene,
    node: NodeId,
    flow_map: TextureId = NO_TEXTURE,
) raises -> Water2:
    """Return a flowing water with flat normal maps."""
    var first = assets.textures.add(normals_map())
    var second = assets.textures.add(normals_map())
    assets.textures.textures[first.value].wrap_s = CLAMP
    return Water2(
        assets,
        square(assets, 2),
        node,
        first,
        second,
        texture_width=8,
        texture_height=8,
        flow_speed=Frequency(0.04, PER_SECOND),
        flow_map=flow_map,
    )


def test_a_flowing_water_flows_as_three_js_does() raises:
    var doc = reference()
    var assets = Assets()
    var scene = Scene()
    var node = reference_node(scene)
    var water = flowing(assets, scene, node)
    scene.add_mesh(water.mesh)
    scene.update()
    # three.js's normal maps repeat.
    var map = assets.programs.get(water.program).uniform("tNormalMap0")[0]
    assert_true(assets.textures.get(TextureId(Int(map))).wrap_s == REPEAT)
    var renderer = Renderer(8, 8)
    var want = doc.get(doc.get(doc.root(), "water2"), "configs")
    var deltas: List[Float32] = [0, 0, 0.7, 2.5, 0.9, 0]
    for frame in range(len(deltas)):
        water.update(
            renderer,
            scene,
            assets,
            reference_camera(),
            Duration(deltas[frame], SECOND),
        )
        var config = assets.programs.get(water.program).uniform("config")
        var row = doc.at(want, frame)
        for k in range(4):
            assert_almost_equal(
                Float64(config[k]), doc.number(doc.at(row, k)), atol=1e-6
            )
    assert_matrix(
        doc,
        doc.get(doc.root(), "water2"),
        "texture_matrix",
        water.texture_matrix,
        2e-5,
    )
    # Both targets were drawn.
    assert_true(water.reflector.texture_matrix != Matrix4())
    assert_true(water.refractor.texture_matrix != Matrix4())
    var image = renderer.render(scene, assets, reference_camera())
    assert_equal(image.width, 8)


def test_a_flow_map_steers_the_flow() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var steer = assets.textures.add(normals_map())
    var water = flowing(assets, scene, node, steer)
    ref program = assets.programs.get(water.program)
    assert_equal(program.uniform("tFlowMap")[0], Float32(steer.value))
    with assert_raises(contains="flowDirection"):
        _ = program.uniform("flowDirection")
    assert_true("tFlowMap" in water2_fragment(True))
    assert_false("tFlowMap" in water2_fragment(False))


def test_a_flowing_water_refuses_what_it_cannot_draw() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var quad = square(assets, 1)
    var map = assets.textures.add(normals_map())
    with assert_raises(contains="finite"):
        _ = Water2(
            assets,
            quad,
            node,
            map,
            map,
            flow_direction=Vector2(nan[DType.float32](), 0),
        )
    with assert_raises(contains="finite"):
        _ = Water2(
            assets,
            quad,
            node,
            map,
            map,
            flow_direction=Vector2(0, inf[DType.float32]()),
        )
    with assert_raises(contains="finite"):
        _ = Water2(
            assets,
            quad,
            node,
            map,
            map,
            flow_speed=Frequency(inf[DType.float32](), PER_SECOND),
        )
    with assert_raises(contains="finite"):
        _ = Water2(
            assets, quad, node, map, map, reflectivity=nan[DType.float32]()
        )
    with assert_raises(contains="finite"):
        _ = Water2(assets, quad, node, map, map, scale=inf[DType.float32]())
    with assert_raises():
        _ = Water2(assets, quad, node, TextureId(99), map)
    with assert_raises():
        _ = Water2(assets, quad, node, map, map, flow_map=TextureId(99))
    var water = flowing(assets, scene, node)
    with assert_raises(contains="not negative"):
        water.flow(Duration(-1.0, SECOND))
    with assert_raises(contains="not negative"):
        water.flow(Duration(nan[DType.float32](), SECOND))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
