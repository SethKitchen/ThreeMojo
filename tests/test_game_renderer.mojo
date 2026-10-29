# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The game renderer: its agreement with `Renderer`, its shadows, its
clipping, its faces, its vertex data, its skins and what it refuses."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import color_background, cube_background
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    UV,
    BufferGeometry,
    MaterialIndex,
)
from core.fog import exp2_fog, linear_fog
from core.interleaved_buffer import InterleavedBuffer
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import (
    ambient_light,
    directional_light,
    hemisphere_light,
    point_light,
    spot_light,
)
from lights.sun_light import SunLight
from materials.nodes import NORMAL_NODE, NodeGraph, NodeProgramId
from materials.material import (
    BACK_SIDE,
    BASIC,
    DOUBLE_SIDE,
    PHONG,
    PHYSICAL,
    STANDARD,
    TOON,
    Material,
    MaterialId,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.skeleton import bind_skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from render.cube_texture import CubeTexture
from render.framebuffer import Color, Framebuffer
from render.srgb import SRGB
from render.texture import CLAMP, NEAREST, Texture
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.game_renderer import (
    CACHED_SHADOWS,
    FULL_SHADOWS,
    GameRenderer,
    GameShading,
    NO_SHADOWS,
    STILL_SHADOWS,
    ShadowMode,
    SwayMotion,
)
from renderers.renderer import Renderer
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import (
    DEGREE,
    METER,
    PER_METER,
    SECOND,
    Angle,
    Duration,
    InverseLength,
    Length,
)

comptime WIDTH = 80
comptime HEIGHT = 50
comptime NOW = Duration(1.5, SECOND)


def _camera(eye: Vector3, target: Vector3) raises -> PerspectiveCamera:
    """Return a camera at `eye` that looks at `target`."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(eye, target)
    return camera^


def _above() raises -> PerspectiveCamera:
    """Return a camera above the floor, looking down at its middle."""
    return _camera(Vector3(0, 6, 4), Vector3(0, 0, 0))


def _lying() raises -> Object3D:
    """Return a node turned so a plane lies flat, facing up."""
    var node = Object3D()
    node.set_euler(Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE))
    return node^


def _sunlit(mut scene: Scene) raises:
    """Light a scene with a dim ambient light and a sun from up and left."""
    scene.add_light(ambient_light(Color(255, 255, 255), 0.3))
    var lamp = Object3D()
    lamp.set_position(-2, 5, 1)
    var lamp_node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 1.5))


def _floor_scene(mut assets: Assets, paint: Material) raises -> Scene:
    """Return a floor 8 meters on a side under the sun, on a sky-blue
    background."""
    var scene = Scene()
    var ground = scene.add(_lying())
    var floor = assets.geometries.add(
        plane(Length(8.0, METER), Length(8.0, METER), 4, 4)
    )
    var id = assets.materials.add(paint)
    scene.add_mesh(Mesh(floor, id, ground, receive_shadow=True))
    _sunlit(scene)
    scene.background = color_background(Color(120, 170, 230))
    scene.update()
    return scene^


def _program(mut assets: Assets) raises -> NodeProgramId:
    """Return a stored node program that gives the normal as it is."""
    var graph = NodeGraph()
    graph.set_output(NORMAL_NODE, graph.normal_world())
    return assets.programs.add(graph.compile())


def _pixel(image: Framebuffer, x: Int, y: Int) -> SIMD[DType.int32, 4]:
    """Return a pixel's bytes."""
    var at = (y * image.width + x) * 4
    return SIMD[DType.int32, 4](
        Int32(image.pixels[at]),
        Int32(image.pixels[at + 1]),
        Int32(image.pixels[at + 2]),
        Int32(image.pixels[at + 3]),
    )


def _near(
    a: SIMD[DType.int32, 4], b: SIMD[DType.int32, 4], within: Int32
) -> Bool:
    """Return whether two pixels differ by at most `within` in each
    channel."""
    var d = a - b
    return (d.le(within) & d.ge(-within)).reduce_and()


def _reference(
    scene: Scene, assets: Assets, camera: PerspectiveCamera
) raises -> Framebuffer:
    """Return the general renderer's picture, tone mapped as the game
    renderer tone maps."""
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_tone_mapping(ACES_FILMIC_TONE_MAPPING, 1)
    return renderer.render(scene, assets, camera)


def _brightness(p: SIMD[DType.int32, 4]) -> Int32:
    """Return the sum of a pixel's red, green and blue."""
    return p[0] + p[1] + p[2]


def test_a_lit_floor_matches_the_general_renderer() raises:
    var assets = Assets()
    var paints: List[Material] = [
        Material(Color(180, 160, 140)),
        Material(Color(180, 160, 140), kind=STANDARD),
        Material(Color(180, 160, 140), kind=BASIC),
    ]
    for paint in paints:
        var scene = _floor_scene(assets, paint)
        var camera = _above()
        var fast = GameRenderer(WIDTH, HEIGHT)
        var image = fast.render(scene, assets, camera, NOW)
        var want = _reference(scene, assets, camera)
        # The floor, flat and evenly lit, and the sky above it.
        for spot in [(40, 30), (20, 40), (60, 45), (40, 2)]:
            var x = spot[0]
            var y = spot[1]
            assert_true(_near(_pixel(image, x, y), _pixel(want, x, y), 2))
        assert_true(image.depth[30 * WIDTH + 40] < 1)
        assert_equal(image.depth[2 * WIDTH + 40], inf[DType.float32]())
        assert_true(fast.triangles > 0)
        assert_true(fast.drawn > 0)
        assert_equal(fast.draw_count, 1)
        assert_equal(len(fast.timings), 8)


def test_a_phong_floor_shines_and_an_emissive_one_glows() raises:
    var assets = Assets()
    var camera = _camera(Vector3(2, 3, 3), Vector3(0, 0, 0))
    var dull = _floor_scene(assets, Material(Color(100, 100, 100)))
    var shiny = _floor_scene(
        assets,
        Material(
            Color(100, 100, 100),
            kind=PHONG,
            specular=Color(255, 255, 255),
            shininess=8,
        ),
    )
    var glowing = _floor_scene(
        assets, Material(Color(100, 100, 100), emissive=Color(90, 0, 0))
    )
    var fast = GameRenderer(WIDTH, HEIGHT)
    var plain = fast.render(dull, assets, camera, NOW)
    var bright = fast.render(shiny, assets, camera, NOW)
    var red = fast.render(glowing, assets, camera, NOW)
    var brighter = 0
    for y in range(20, HEIGHT):
        for x in range(WIDTH):
            if _brightness(_pixel(bright, x, y)) > _brightness(
                _pixel(plain, x, y)
            ):
                brighter += 1
    assert_true(brighter > 100)
    assert_true(_pixel(red, 40, 40)[0] > _pixel(plain, 40, 40)[0] + 10)


def _blocked_scene(mut assets: Assets) raises -> Scene:
    """Return the floor with a block 1 meter on a side above its middle,
    which casts on it."""
    var scene = _floor_scene(assets, Material(Color(200, 200, 200)))
    var lift = Object3D()
    lift.set_position(0, 1.0, 0)
    var lift_node = scene.add(lift^)
    var block = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(200, 60, 60)))
    scene.add_mesh(
        Mesh(block, paint, lift_node, cast_shadow=True, receive_shadow=True)
    )
    scene.update()
    return scene^


def _shadowed(image: Framebuffer, lit: Framebuffer) -> Int:
    """Return how many floor pixels are darker in `image` than in `lit`."""
    var darker = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if _brightness(_pixel(image, x, y)) + 20 < _brightness(
                _pixel(lit, x, y)
            ):
                darker += 1
    return darker


def test_the_sun_casts_shadows_in_each_mode() raises:
    var assets = Assets()
    var scene = _blocked_scene(assets)
    var camera = _above()
    var fast = GameRenderer(WIDTH, HEIGHT)
    fast.shadow_reach = 8
    fast.moving_reach = 4
    fast.moving_size = 100
    var lit = fast.render(scene, assets, camera, NOW)
    fast.set_shadows(STILL_SHADOWS, 256)
    var still = fast.render(scene, assets, camera, NOW)
    assert_true(_shadowed(still, lit) > 20)
    # The still map is kept: the next frame draws the same shadow.
    var again = fast.render(scene, assets, camera, NOW)
    assert_equal(_shadowed(again, lit), _shadowed(still, lit))
    # A moving block casts only into the moving map.
    fast.set_moving(scene, [NodeId(scene.count() - 1)])
    var gone = fast.render(scene, assets, camera, NOW)
    assert_true(_shadowed(gone, lit) < 5)
    fast.set_shadows(CACHED_SHADOWS, 256)
    var cached = fast.render(scene, assets, camera, NOW)
    assert_true(_shadowed(cached, lit) > 20)
    fast.set_shadows(FULL_SHADOWS, 128)
    fast.refresh_shadows()
    var full = fast.render(scene, assets, camera, NOW)
    assert_true(_shadowed(full, lit) > 20)
    # A floor that does not receive is lit everywhere.
    scene.meshes[0].receive_shadow = False
    scene.meshes[1].receive_shadow = False
    var bare = fast.render(scene, assets, camera, NOW)
    assert_true(_shadowed(bare, lit) < 5)


def test_a_frame_of_an_odd_width_shows_the_sky_to_its_edge() raises:
    # 77 pixels: the last run of sixteen in a row is partly past the edge.
    var assets = Assets()
    var scene = _floor_scene(assets, Material(Color(180, 160, 140)))
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        77.0 / 45.0,
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 6, 4), Vector3(0, 0, 0))
    var fast = GameRenderer(77, 45)
    fast.sky_step = 1
    var image = fast.render(scene, assets, camera, NOW)
    var renderer = Renderer(77, 45)
    renderer.set_tone_mapping(ACES_FILMIC_TONE_MAPPING, 1)
    var want = renderer.render(scene, assets, camera)
    for x in [0, 64, 76]:
        assert_true(_near(_pixel(image, x, 0), _pixel(want, x, 0), 2))
        assert_true(_near(_pixel(image, x, 44), _pixel(want, x, 44), 2))


def test_the_shadow_settings_are_checked() raises:
    var fast = GameRenderer(16, 16)
    with assert_raises(contains="shadow mode"):
        fast.set_shadows(ShadowMode(7), 256)
    with assert_raises(contains="64 to 8,192"):
        fast.set_shadows(NO_SHADOWS, 32)
    with assert_raises(contains="64 to 8,192"):
        fast.set_shadows(NO_SHADOWS, 10000)
    var assets = Assets()
    var scene = _floor_scene(assets, Material(Color(200, 200, 200)))
    fast.shadows = ShadowMode(9)
    with assert_raises(contains="shadow mode"):
        _ = fast.render(scene, assets, _above(), NOW)
    with assert_raises(contains="positive"):
        _ = GameRenderer(0, 16)
    with assert_raises(contains="positive"):
        _ = GameRenderer(16, -1)


def test_a_floor_through_the_near_plane_is_clipped() raises:
    var assets = Assets()
    var scene = _floor_scene(assets, Material(Color(150, 150, 150)))
    var fast = GameRenderer(WIDTH, HEIGHT)
    # The eye stands just above the floor: its near triangles cross the
    # near plane, and some lie behind the eye.
    var low = _camera(Vector3(0, 0.05, 3.9), Vector3(0, 0.05, -4))
    var image = fast.render(scene, assets, low, NOW)
    assert_true(_brightness(_pixel(image, 40, HEIGHT - 1)) < 700)
    assert_true(image.depth[(HEIGHT - 1) * WIDTH + 40] < 1)
    var want = _reference(scene, assets, low)
    assert_true(
        _near(_pixel(image, 40, HEIGHT - 1), _pixel(want, 40, HEIGHT - 1), 3)
    )


def test_a_back_face_is_drawn_as_its_side_says() raises:
    var assets = Assets()
    # From below, the floor shows its back.
    var under = _camera(Vector3(0, -6, 4), Vector3(0, 0, 0))
    var fast = GameRenderer(WIDTH, HEIGHT)
    var front = _floor_scene(assets, Material(Color(200, 200, 200)))
    assert_equal(
        fast.render(front, assets, under, NOW).depth[30 * WIDTH + 40],
        inf[DType.float32](),
    )
    var back = _floor_scene(
        assets, Material(Color(200, 200, 200), side=BACK_SIDE)
    )
    var seen = fast.render(back, assets, under, NOW)
    assert_true(seen.depth[30 * WIDTH + 40] < 1)
    # A back-side floor seen from below faces away from the sun above, as
    # the general renderer lights it.
    var want = _reference(back, assets, under)
    assert_true(_near(_pixel(seen, 40, 30), _pixel(want, 40, 30), 2))
    assert_equal(
        fast.render(back, assets, _above(), NOW).depth[30 * WIDTH + 40],
        inf[DType.float32](),
    )
    # Both faces: the back is lit as a back, facing away from the sun.
    var both = _floor_scene(
        assets, Material(Color(200, 200, 200), side=DOUBLE_SIDE)
    )
    var top = fast.render(both, assets, _above(), NOW)
    var bottom = fast.render(both, assets, under, NOW)
    assert_true(
        _brightness(_pixel(bottom, 40, 30)) < _brightness(_pixel(top, 40, 30))
    )
    # A two-sided program lights the back as its front.
    var program = _program(assets)
    fast.register(program.value, GameShading(True, "", "", None))
    var paint = Material(Color(200, 200, 200), side=DOUBLE_SIDE)
    paint.nodes = program
    var twice = _floor_scene(assets, paint)
    var lit_back = fast.render(twice, assets, under, NOW)
    assert_true(
        _brightness(_pixel(lit_back, 40, 30))
        > _brightness(_pixel(bottom, 40, 30))
    )


def _triangle_geometry() raises -> BufferGeometry:
    """Return two triangles side by side, unindexed, in the xy plane."""
    var geometry = BufferGeometry()
    var positions: List[Float32] = [
        -2,
        -1,
        0,
        0,
        -1,
        0,
        -1,
        1,
        0,
        0,
        -1,
        0,
        2,
        -1,
        0,
        1,
        1,
        0,
    ]
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    return geometry^


def _facing_scene(
    mut assets: Assets, var geometry: BufferGeometry, materials: List[Material]
) raises -> Scene:
    """Return a scene that shows a geometry in the xy plane, facing the
    camera, under the sun."""
    var scene = Scene()
    var node = scene.add(Object3D())
    var id = assets.geometries.add(geometry^)
    var ids = List[MaterialId]()
    for m in materials:
        ids.append(assets.materials.add(m))
    if len(ids) == 1:
        scene.add_mesh(Mesh(id, ids[0], node))
    else:
        scene.add_mesh(Mesh(id, ids, node))
    _sunlit(scene)
    scene.update()
    return scene^


def _facing() raises -> PerspectiveCamera:
    """Return a camera on +z that looks at the origin."""
    return _camera(Vector3(0, 0, 5), Vector3(0, 0, 0))


def test_vertex_colors_and_a_map_tint_the_light() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    # No normals: a vertex faces up, as a missing normal reads.
    var plain = _facing_scene(
        assets, _triangle_geometry(), [Material(Color(255, 255, 255))]
    )
    var white = fast.render(plain, assets, _facing(), NOW)
    var colored = _triangle_geometry()
    var reds: List[Float32] = [
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
    ]
    colored.set_attribute(String(COLOR), BufferAttribute(reds^, 3))
    var tinted = _facing_scene(
        assets, colored^, [Material(Color(255, 255, 255), vertex_colors=True)]
    )
    var red = fast.render(tinted, assets, _facing(), NOW)
    assert_true(_pixel(red, 30, 25)[1] < _pixel(white, 30, 25)[1])
    # A green map, read at each vertex.
    var mapped = _triangle_geometry()
    var uvs = List[Float32](length=12, fill=0.5)
    mapped.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    var green = List[UInt8]()
    for _ in range(4):
        green.append(0)
        green.append(255)
        green.append(0)
        green.append(255)
    var texture = assets.textures.add(
        Texture(2, 2, green^, CLAMP, NEAREST, SRGB, False)
    )
    var map_scene = _facing_scene(
        assets, mapped^, [Material(Color(255, 255, 255), map=texture)]
    )
    var greened = fast.render(map_scene, assets, _facing(), NOW)
    assert_true(_pixel(greened, 30, 25)[0] < _pixel(white, 30, 25)[0])


def test_groups_wear_their_materials() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    var geometry = _triangle_geometry()
    var normals: List[Float32] = [
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
    ]
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.add_group(0, 3, MaterialIndex(0))
    geometry.add_group(3, 3, MaterialIndex(1))
    var scene = _facing_scene(
        assets,
        geometry^,
        [
            Material(Color(255, 0, 0), kind=BASIC),
            Material(Color(0, 0, 255), kind=BASIC),
        ],
    )
    var image = fast.render(scene, assets, _facing(), NOW)
    assert_equal(fast.draw_count, 2)
    var left = _pixel(image, 30, 28)
    var right = _pixel(image, 50, 28)
    assert_true(left[0] > left[2])
    assert_true(right[2] > right[0])
    # A group naming a material the mesh lacks is not drawn.
    var short = _triangle_geometry()
    short.add_group(0, 3, MaterialIndex(0))
    short.add_group(3, 3, MaterialIndex(5))
    var missing = _facing_scene(
        assets,
        short^,
        [
            Material(Color(255, 0, 0), kind=BASIC),
            Material(Color(0, 0, 255), kind=BASIC),
        ],
    )
    _ = fast.render(missing, assets, _facing(), NOW)
    assert_equal(fast.draw_count, 1)


def test_an_interleaved_and_a_replaced_geometry_are_read() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    var data: List[Float32] = [
        -2,
        -1,
        0,
        9,
        0,
        -1,
        0,
        9,
        -1,
        1,
        0,
        9,
    ]
    var buffer = InterleavedBuffer(data^, 4)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(buffer, 3, 0))
    var scene = _facing_scene(
        assets, geometry^, [Material(Color(255, 255, 255), kind=BASIC)]
    )
    var image = fast.render(scene, assets, _facing(), NOW)
    assert_true(image.depth[28 * WIDTH + 30] < 1)
    assert_equal(image.depth[28 * WIDTH + 50], inf[DType.float32]())
    # A replaced geometry is read again.
    assets.geometries.replace(scene.meshes[0].geometry, _triangle_geometry())
    var replaced = fast.render(scene, assets, _facing(), NOW)
    assert_true(replaced.depth[28 * WIDTH + 50] < 1)


def _baked_geometry() raises -> BufferGeometry:
    """Return the two triangles with a baked sun and sky: none and full."""
    var geometry = _triangle_geometry()
    geometry.set_attribute(
        "sunlit", BufferAttribute(List[Float32](length=6, fill=0), 1)
    )
    geometry.set_attribute(
        "skylit", BufferAttribute(List[Float32](length=6, fill=1), 1)
    )
    return geometry^


def test_a_baked_light_and_a_sway_shade_as_registered() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    fast.set_shadows(CACHED_SHADOWS, 64)
    var program = _program(assets)
    fast.register(program.value, GameShading(False, "sunlit", "skylit", None))
    var paint = Material(Color(255, 255, 255))
    paint.nodes = program
    var scene = _facing_scene(assets, _baked_geometry(), [paint])
    var dark = fast.render(scene, assets, _facing(), NOW)
    var plain = _facing_scene(
        assets, _triangle_geometry(), [Material(Color(255, 255, 255))]
    )
    var lit = fast.render(plain, assets, _facing(), NOW)
    assert_true(
        _brightness(_pixel(dark, 30, 28)) < _brightness(_pixel(lit, 30, 28))
    )
    # A sway moves the vertices with the time.
    var swaying = _program(assets)
    var motion = SwayMotion(
        0.5,
        0.2,
        0.1,
        2.0,
        5.0,
        SIMD[DType.float32, 4](0.3, 0.1, 0.2, 0),
        SIMD[DType.float32, 4](0.2, 0.3, 0.1, 0),
        1.0,
        1.0,
        1.0,
    )
    fast.register(swaying.value, GameShading(False, "", "", motion))
    var moving_paint = Material(Color(255, 255, 255), kind=BASIC)
    moving_paint.nodes = swaying
    var sway_scene = _facing_scene(assets, _triangle_geometry(), [moving_paint])
    var first = fast.render(
        sway_scene, assets, _facing(), Duration(0.0, SECOND)
    )
    var later = fast.render(
        sway_scene, assets, _facing(), Duration(0.7, SECOND)
    )
    var moved = 0
    for i in range(WIDTH * HEIGHT):
        if (first.depth[i] < 1) != (later.depth[i] < 1):
            moved += 1
    assert_true(moved > 0)
    # A baked light the geometry lacks is refused.
    var lacking = _program(assets)
    fast.register(lacking.value, GameShading(False, "", "nowhere", None))
    var lacking_paint = Material(Color(255, 255, 255))
    lacking_paint.nodes = lacking
    var bare = _facing_scene(assets, _triangle_geometry(), [lacking_paint])
    with assert_raises(contains="nowhere"):
        _ = fast.render(bare, assets, _facing(), NOW)


def _skinned_scene(
    mut assets: Assets, bones: List[Float32], weights: List[Float32]
) raises -> Scene:
    """Return the two triangles on a skeleton of one bone, which stands
    one meter right of its bind."""
    var geometry = _triangle_geometry()
    geometry.set_attribute(String(SKIN_INDEX), BufferAttribute(bones.copy(), 4))
    geometry.set_attribute(
        String(SKIN_WEIGHT), BufferAttribute(weights.copy(), 4)
    )
    var scene = Scene()
    var holder = scene.add(Object3D())
    var bone = scene.add(Object3D())
    scene.update()
    var skeleton = bind_skeleton([bone], [scene.world_matrix(bone)])
    scene.node(bone).set_position(1, 0, 0)
    scene.add_skinned_mesh(
        SkinnedMesh(
            assets.geometries.add(geometry^),
            assets.materials.add(Material(Color(255, 255, 255), kind=BASIC)),
            holder,
            skeleton^,
        )
    )
    _sunlit(scene)
    scene.update()
    return scene^


def test_a_skinned_mesh_follows_its_bones() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    var weights = List[Float32]()
    for _ in range(6):
        weights.append(1)
        weights.append(0)
        weights.append(0)
        weights.append(0)
    var scene = _skinned_scene(
        assets, List[Float32](length=24, fill=0), weights
    )
    var image = fast.render(scene, assets, _facing(), NOW)
    # Moved right a meter: the right edge is covered, the left is not.
    var plain = _facing_scene(
        assets,
        _triangle_geometry(),
        [Material(Color(255, 255, 255), kind=BASIC)],
    )
    var still = fast.render(plain, assets, _facing(), NOW)
    var right = 0
    for i in range(WIDTH * HEIGHT):
        if image.depth[i] < 1 and not (still.depth[i] < 1):
            right += 1
    assert_true(right > 20)
    # A bone the skeleton lacks, a negative weight and a missing skin are
    # refused.
    var far = _skinned_scene(assets, List[Float32](length=24, fill=3), weights)
    with assert_raises(contains="bone"):
        _ = fast.render(far, assets, _facing(), NOW)
    var negative = weights.copy()
    negative[0] = -1
    var heavy = _skinned_scene(
        assets, List[Float32](length=24, fill=0), negative
    )
    with assert_raises(contains="weight"):
        _ = fast.render(heavy, assets, _facing(), NOW)


def test_the_sky_the_fog_and_a_cube_background_are_drawn() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    var scene = _floor_scene(assets, Material(Color(180, 180, 180)))
    var sky = Object3D()
    sky.set_position(0, 1, 0)
    var sky_node = scene.add(sky^)
    scene.add_light(
        hemisphere_light(Color(100, 150, 255), Color(80, 60, 40), sky_node, 0.8)
    )
    scene.fog = exp2_fog(Color(200, 200, 200), InverseLength(0.2, PER_METER))
    var faces = List[Texture]()
    for _ in range(6):
        var pixels = List[UInt8]()
        for _ in range(4):
            pixels.append(250)
            pixels.append(20)
            pixels.append(20)
            pixels.append(255)
        faces.append(Texture(2, 2, pixels^, CLAMP, NEAREST, SRGB, False))
    scene.background = cube_background(
        assets.cube_textures.add(CubeTexture(faces^))
    )
    scene.update()
    fast.sky_step = 1
    var image = fast.render(scene, assets, _above(), NOW)
    var top = _pixel(image, 40, 1)
    assert_true(top[0] > top[1])
    var want = _reference(scene, assets, _above())
    assert_true(_near(_pixel(image, 40, 30), _pixel(want, 40, 30), 3))
    # No background: black.
    var dark = _floor_scene(assets, Material(Color(180, 180, 180)))
    dark.background = Scene().background
    assert_equal(
        _brightness(_pixel(fast.render(dark, assets, _above(), NOW), 40, 1)), 0
    )


def test_what_the_game_renderer_cannot_draw_is_refused() raises:
    var assets = Assets()
    var fast = GameRenderer(16, 16)
    var toon = _floor_scene(assets, Material(Color(180, 180, 180), kind=TOON))
    with assert_raises(contains="kind"):
        _ = fast.render(toon, assets, _above(), NOW)
    var unknown = Material(Color(180, 180, 180))
    unknown.nodes = _program(assets)
    var programmed = _floor_scene(assets, unknown)
    with assert_raises(contains="no shading"):
        _ = fast.render(programmed, assets, _above(), NOW)
    var two_skies = _floor_scene(assets, Material(Color(180, 180, 180)))
    two_skies.add_light(
        hemisphere_light(Color(1, 1, 1), Color(1, 1, 1), NodeId(0))
    )
    two_skies.add_light(
        hemisphere_light(Color(1, 1, 1), Color(1, 1, 1), NodeId(0))
    )
    with assert_raises(contains="hemisphere"):
        _ = fast.render(two_skies, assets, _above(), NOW)
    var two_suns = _floor_scene(assets, Material(Color(180, 180, 180)))
    var other = Object3D()
    other.set_position(3, 2, 0)
    var other_node = two_suns.add(other^)
    two_suns.add_light(directional_light(Color(255, 255, 255), other_node))
    two_suns.update()
    with assert_raises(contains="one directional"):
        _ = fast.render(two_suns, assets, _above(), NOW)
    var bulb = _floor_scene(assets, Material(Color(180, 180, 180)))
    bulb.add_light(point_light(Color(255, 255, 255), NodeId(0)))
    with assert_raises(contains="point"):
        _ = fast.render(bulb, assets, _above(), NOW)
    var misty = _floor_scene(assets, Material(Color(180, 180, 180)))
    misty.fog = linear_fog(
        Color(1, 1, 1), Length(1.0, METER), Length(10.0, METER)
    )
    with assert_raises(contains="exponential"):
        _ = fast.render(misty, assets, _above(), NOW)


def test_many_meshes_and_a_large_one_share_the_work() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    var scene = Scene()
    # A floor of 9,800 triangles, more than one task's share, and many
    # small blocks.
    var ground = scene.add(_lying())
    var floor = assets.geometries.add(
        plane(Length(8.0, METER), Length(8.0, METER), 70, 70)
    )
    var paint = assets.materials.add(
        Material(Color(160, 160, 160), kind=PHYSICAL)
    )
    scene.add_mesh(Mesh(floor, paint, ground))
    var block = assets.geometries.add(cube(Length(0.2, METER)))
    for i in range(400):
        var node = Object3D()
        node.set_position(
            Float32(i % 20) * 0.3 - 3, 0.1, Float32(i // 20) * 0.3 - 3
        )
        var id = scene.add(node^)
        scene.add_mesh(Mesh(block, paint, id))
    # A block off to the side, outside the view, is not drawn.
    var away = Object3D()
    away.set_position(0, 0, 60)
    var away_node = scene.add(away^)
    scene.add_mesh(Mesh(block, paint, away_node))
    # A hidden block is not drawn either.
    var hidden = Object3D()
    hidden.visible = False
    var hidden_node = scene.add(hidden^)
    scene.add_mesh(Mesh(block, paint, hidden_node))
    _sunlit(scene)
    scene.update()
    var image = fast.render(scene, assets, _above(), NOW)
    # A cube has a group a face.
    assert_equal(fast.draw_count, 1 + 400 * 6)
    assert_true(fast.vertex_count > 4096)
    assert_true(image.depth[30 * WIDTH + 40] < 1)


def _empty_geometry() raises -> BufferGeometry:
    """Return a geometry with every attribute and no vertex."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION), BufferAttribute(List[Float32](), 3)
    )
    geometry.set_attribute(String(NORMAL), BufferAttribute(List[Float32](), 2))
    geometry.set_attribute(String(COLOR), BufferAttribute(List[Float32](), 3))
    geometry.set_attribute(String(UV), BufferAttribute(List[Float32](), 2))
    geometry.set_attribute("sunlit", BufferAttribute(List[Float32](), 1))
    geometry.set_attribute(
        String(SKIN_INDEX), BufferAttribute(List[Float32](), 4)
    )
    geometry.set_attribute(
        String(SKIN_WEIGHT), BufferAttribute(List[Float32](), 4)
    )
    return geometry^


def test_an_empty_geometry_and_an_empty_scene_draw_nothing() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    var program = _program(assets)
    fast.register(program.value, GameShading(False, "sunlit", "", None))
    var texture = assets.textures.add(
        Texture(
            1, 1, List[UInt8](length=4, fill=255), CLAMP, NEAREST, SRGB, False
        )
    )
    var paint = Material(Color(255, 255, 255), map=texture, vertex_colors=True)
    paint.nodes = program
    var scene = _facing_scene(assets, _empty_geometry(), [paint])
    var bone = scene.add(Object3D())
    scene.update()
    scene.add_skinned_mesh(
        SkinnedMesh(
            assets.geometries.add(_empty_geometry()),
            assets.materials.add(Material(Color(255, 255, 255))),
            NodeId(0),
            bind_skeleton([bone], [scene.world_matrix(bone)]),
        )
    )
    scene.update()
    var image = fast.render(scene, assets, _facing(), NOW)
    assert_equal(fast.triangles, 0)
    assert_equal(image.depth[25 * WIDTH + 40], inf[DType.float32]())
    # No mesh, and no light but the ambient: the background alone.
    var bare = Scene()
    bare.add_light(ambient_light(Color(255, 255, 255), 0.5))
    bare.update()
    fast.set_moving(bare, [])
    _ = fast.render(bare, assets, _facing(), NOW)
    assert_equal(fast.draw_count, 0)


def test_a_triangle_past_the_vertices_is_refused() raises:
    var assets = Assets()
    var fast = GameRenderer(16, 16)
    var geometry = _triangle_geometry()
    geometry.set_index([0, 1, 9])
    var scene = _facing_scene(
        assets, geometry^, [Material(Color(255, 255, 255))]
    )
    with assert_raises(contains="lacks"):
        _ = fast.render(scene, assets, _facing(), NOW)


def test_flat_positions_and_shared_baked_light_are_read() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    # Positions of two numbers each: the third is zero.
    var geometry = BufferGeometry()
    var flat: List[Float32] = [-2, -1, 0, -1, -1, 1]
    geometry.set_attribute(String(POSITION), BufferAttribute(flat^, 2))
    var scene = _facing_scene(
        assets, geometry^, [Material(Color(255, 255, 255), kind=BASIC)]
    )
    var image = fast.render(scene, assets, _facing(), NOW)
    assert_true(image.depth[28 * WIDTH + 30] < 1)
    # Two meshes of one geometry read its baked light once, and a mesh
    # with no sun of its own is lit by the ambient light alone.
    var program = _program(assets)
    fast.register(program.value, GameShading(False, "skylit", "skylit", None))
    var paint = Material(Color(255, 255, 255))
    paint.nodes = program
    var twice = _facing_scene(assets, _baked_geometry(), [paint])
    var copy = twice.add(Object3D())
    twice.update()
    twice.add_mesh(
        Mesh(twice.meshes[0].geometry, twice.meshes[0].material, copy)
    )
    _ = fast.render(twice, assets, _facing(), NOW)
    assert_equal(fast.draw_count, 2)
    var dim = Scene()
    var node = dim.add(Object3D())
    dim.add_mesh(
        Mesh(
            assets.geometries.add(_triangle_geometry()),
            assets.materials.add(Material(Color(255, 255, 255))),
            node,
        )
    )
    dim.add_light(ambient_light(Color(255, 255, 255), 0.5))
    dim.update()
    var ambient = fast.render(dim, assets, _facing(), NOW)
    assert_true(_brightness(_pixel(ambient, 30, 28)) > 0)
    # A flattened node has no normal matrix: its normals are kept.
    var squashed = _facing_scene(
        assets, _triangle_geometry(), [Material(Color(255, 255, 255))]
    )
    squashed.node(NodeId(0)).set_scale(1, 1, 0)
    squashed.update()
    var flattened = fast.render(squashed, assets, _facing(), NOW)
    assert_true(flattened.depth[28 * WIDTH + 30] < 1)


def test_a_skin_is_read_once_and_checked() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    var weights = List[Float32]()
    for _ in range(6):
        weights.append(1)
        weights.append(0)
        weights.append(0)
        weights.append(0)
    var scene = _skinned_scene(
        assets, List[Float32](length=24, fill=0), weights
    )
    # Two groups: two draws of one skin.
    ref skin_geometry = assets.geometries.get(scene.skinned_meshes[0].geometry)
    var grouped = skin_geometry.clone()
    grouped.add_group(0, 3)
    grouped.add_group(3, 3)
    assets.geometries.replace(scene.skinned_meshes[0].geometry, grouped^)
    _ = fast.render(scene, assets, _facing(), NOW)
    assert_equal(fast.draw_count, 2)
    _ = fast.render(scene, assets, _facing(), NOW)
    assert_equal(fast.draw_count, 2)
    # Each skin attribute must be there and cover every vertex.
    var names: List[String] = [String(SKIN_INDEX), String(SKIN_WEIGHT)]
    for name in names:
        var lacking = _skinned_scene(
            assets, List[Float32](length=24, fill=0), weights
        )
        ref held = assets.geometries.get(lacking.skinned_meshes[0].geometry)
        var cut = held.clone()
        cut.delete_attribute(name)
        assets.geometries.replace(lacking.skinned_meshes[0].geometry, cut^)
        with assert_raises(contains="skinIndex and skinWeight"):
            _ = fast.render(lacking, assets, _facing(), NOW)
        var short = _skinned_scene(
            assets, List[Float32](length=24, fill=0), weights
        )
        ref whole = assets.geometries.get(short.skinned_meshes[0].geometry)
        var shortened = whole.clone()
        shortened.set_attribute(
            name, BufferAttribute(List[Float32](length=8, fill=0), 4)
        )
        assets.geometries.replace(short.skinned_meshes[0].geometry, shortened^)
        with assert_raises(contains="every vertex"):
            _ = fast.render(short, assets, _facing(), NOW)


def test_skins_and_the_casters_go_to_their_maps() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    fast.set_shadows(CACHED_SHADOWS, 64)
    fast.moving_size = 64
    var weights = List[Float32]()
    for _ in range(6):
        weights.append(1)
        weights.append(0)
        weights.append(0)
        weights.append(0)
    var scene = _skinned_scene(
        assets, List[Float32](length=24, fill=0), weights
    )
    # A still skin that casts, a moving one that casts, one that does not
    # cast and a hidden one.
    var mover = scene.add(Object3D())
    var hidden = Object3D()
    hidden.visible = False
    var hidden_node = scene.add(hidden^)
    scene.update()
    ref first = scene.skinned_meshes[0]
    var moving = first.copy()
    moving.node = mover
    var unseen = first.copy()
    unseen.node = hidden_node
    var quiet = first.copy()
    quiet.cast_shadow = False
    scene.skinned_meshes[0].cast_shadow = True
    moving.cast_shadow = True
    unseen.cast_shadow = True
    scene.add_skinned_mesh(moving^)
    scene.add_skinned_mesh(unseen^)
    scene.add_skinned_mesh(quiet^)
    # A double-sided block that casts shows the sun both faces.
    var block = assets.geometries.add(cube(Length(0.5, METER)))
    var both = assets.materials.add(
        Material(Color(255, 255, 255), side=DOUBLE_SIDE)
    )
    scene.add_mesh(
        Mesh(block, both, mover, cast_shadow=True, receive_shadow=True)
    )
    # A mover with a child.
    var child = Object3D()
    var child_node = scene.add(child^)
    scene.add(child_node, parent=mover)
    scene.update()
    var leaf = scene.add(Object3D())
    scene.update()
    fast.set_moving(scene, [mover, leaf])
    var image = fast.render(scene, assets, _facing(), NOW)
    assert_true(image.depth[28 * WIDTH + 40] < 1)


def test_a_sun_straight_overhead_and_its_cascades_cast() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    fast.set_shadows(STILL_SHADOWS, 64)
    var scene = Scene()
    var ground = scene.add(_lying())
    var floor = assets.geometries.add(
        plane(Length(8.0, METER), Length(8.0, METER), 2, 2)
    )
    scene.add_mesh(
        Mesh(
            floor,
            assets.materials.add(Material(Color(200, 200, 200))),
            ground,
            cast_shadow=True,
            receive_shadow=True,
        )
    )
    # A sun of cascades, all from straight above, counts once.
    var sun = SunLight(scene)
    scene.update()
    var image = fast.render(scene, assets, _above(), NOW)
    assert_true(_brightness(_pixel(image, 40, 30)) > 0)
    # A plain light from the same way is a second sun.
    var same = Scene()
    var high = same.add(Object3D())
    same.node(high).set_position(0, 1, 0)
    _ = SunLight(same)
    same.add_light(directional_light(Color(255, 255, 255), high))
    same.update()
    with assert_raises(contains="one directional"):
        _ = fast.render(same, assets, _above(), NOW)
    # The cascades of a second sun from elsewhere are a second sun.
    var other = SunLight(scene)
    scene.node(other.node).set_position(1, 1, 0)
    for index in range(len(other.nodes)):
        scene.node(other.nodes[index]).set_position(1, 1, 0)
    scene.update()
    with assert_raises(contains="one directional"):
        _ = fast.render(scene, assets, _above(), NOW)
    _ = sun.node
    var beam = Scene()
    beam.add_light(spot_light(Color(255, 255, 255), beam.add(Object3D())))
    beam.update()
    with assert_raises(contains="spot"):
        _ = fast.render(beam, assets, _above(), NOW)


def test_triangles_past_the_near_and_far_planes_are_cut() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    var scene = Scene()
    var ground = scene.add(_lying())
    var floor = assets.geometries.add(
        plane(Length(60.0, METER), Length(60.0, METER), 30, 30)
    )
    scene.add_mesh(
        Mesh(
            floor,
            assets.materials.add(Material(Color(200, 200, 200), kind=BASIC)),
            ground,
        )
    )
    # A thin sliver that crosses the near plane but covers no pixel
    # center, a degenerate triangle seen from both sides, and triangles
    # that cross the near and the far plane at each corner.
    var odd = BufferGeometry()
    var sliver = BufferGeometry()
    # It lies on the middle column's edge, between two pixel centers.
    var edge: List[Float32] = [0, 1.2, 1, 0, 1.2, -3, 1.0e-5, 1.2, -3]
    sliver.set_attribute(String(POSITION), BufferAttribute(edge^, 3))
    var side_node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(sliver^),
            assets.materials.add(
                Material(Color(255, 0, 0), kind=BASIC, side=DOUBLE_SIDE)
            ),
            side_node,
        )
    )
    var corners: List[Float32] = [
        0,
        1,
        -3,
        0.5,
        1,
        -3,
        1,
        1,
        -3,
        -1,
        1,
        -20,
        1,
        1,
        -20,
        0,
        1,
        -5,
        -1,
        0.5,
        -4,
        1,
        0.5,
        -4,
        0,
        0.5,
        3,
        0,
        0.5,
        3,
        -1,
        0.5,
        -4,
        1,
        0.5,
        -4,
    ]
    odd.set_attribute(String(POSITION), BufferAttribute(corners^, 3))
    var near_node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(odd^),
            assets.materials.add(
                Material(Color(255, 0, 0), kind=BASIC, side=DOUBLE_SIDE)
            ),
            near_node,
        )
    )
    _sunlit(scene)
    scene.update()
    var camera = PerspectiveCamera(
        Angle(70.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.5, METER),
        Length(12.0, METER),
    )
    camera.place(Vector3(0, 1, 0), Vector3(0, 0.5, -5))
    var image = fast.render(scene, assets, camera, NOW)
    assert_true(image.depth[(HEIGHT - 1) * WIDTH + 40] < 1)
    # Past the far plane is sky.
    assert_equal(image.depth[2 * WIDTH + 40], inf[DType.float32]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
