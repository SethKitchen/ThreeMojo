# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.mesh` and `renderers.renderer`."""

from cameras.camera import Camera
from cameras.orthographic_camera import OrthographicCamera, centered
from render.rasterizer import RasterVertex
from core.geometry_store import GeometryId
from core.object3d import NodeId
from cameras.perspective_camera import PerspectiveCamera
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    COLOR,
    NORMAL,
    POSITION,
    UV,
    UV1,
)
from core.object3d import Object3D
from geometries.plane import plane
from core.assets import Assets
from materials.material import (
    BACK_SIDE,
    BLEND,
    Blending,
    MaterialId,
    OPAQUE,
    DOUBLE_SIDE,
    FRONT_SIDE,
    Material,
)
from lights.light import point_light
from materials.material import (
    BASIC,
    DEPTH,
    LAMBERT,
    MATCAP,
    NORMALS,
    PHONG,
    PHYSICAL,
    STANDARD,
    TOON,
    depth_material,
    line_dashed_material,
    matcap_material,
    normal_material,
    phong_material,
    physical_material,
    points_material,
    shadow_material,
    sprite_material,
    standard_material,
    toon_material,
)
from render.cube_texture import CubeTexture
from render.cube_texture_store import SCENE_ENVIRONMENT
from core.scene import Scene
from lights.light import (
    ambient_light,
    directional_light,
    rect_area_light,
    spot_light,
)
from lights.ltc import LtcTables, load_ltc_tables
from core.layers import Layers
from lights.lighting import Lighting
from lights.shadow import (
    BASIC_SHADOW_MAP,
    PCF_SHADOW_MAP,
    PCF_SOFT_SHADOW_MAP,
    VSM_SHADOW_MAP,
    ShadowMapType,
)
from core.fog import FogKind, exp2_fog, linear_fog, no_fog
from render.tonemap import (
    LINEAR_TONE_MAPPING,
    NO_TONE_MAPPING,
    REINHARD_TONE_MAPPING,
    ToneMapping,
)
from units.si import InverseLength, PER_METER
from geometries.box import cube
from geometries.sphere import sphere
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.instanced_mesh import BatchedMesh, InstancedMesh
from objects.lod import Lod
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SkinnedMesh
from objects.sprite import Sprite
from objects.line import Line
from objects.points import Points
from math.matrix4 import Matrix4
from render.framebuffer import Color, FloatColor, Framebuffer
from render.rasterizer import SHADE_LIT, SHADE_TEXTURE, SHADE_UV, ShadeMode
from geometries.polyhedron import octahedron
from render.srgb import LINEAR, SRGB, ColorSpace
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    Alpha,
    IGNORED,
    NEAREST,
    REPEAT,
    Texture,
    UV_CHANNEL_1,
    UvChannel,
    checkerboard,
    texture_of,
)
from render.texture_store import NO_TEXTURE, TextureId
from renderers.renderer import (
    Renderer,
    available_workers,
    camera_position,
    camera_up,
    face_normal,
    toward_camera,
)
from std.math import inf, nan, pi

# The intensity that lights a white surface square on to full white: three.js
# divides every lit term by pi, and so does `Lighting`. See tests/test_light.
comptime FULL = Float32(pi)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


def rendered[
    C: Camera
](
    renderer: Renderer,
    mut scene: Scene,
    assets: Assets,
    meshes: List[Mesh],
    camera: C,
) raises -> Framebuffer:
    """Render `meshes` in `scene`, the way this suite was written to.

    Meshes live in the scene now, as lights do, and the renderer takes only
    the scene. These tests were written passing a list alongside it, and
    several render one scene with two different lists to compare them, which
    is exactly what assigning `scene.meshes` here preserves.

    Args:
        renderer: The renderer to draw with.
        scene: The scene to draw; its mesh list is replaced.
        assets: The geometry, materials and textures the meshes name.
        meshes: What to draw.
        camera: The camera to project through.

    Returns:
        The rendered image.

    Raises:
        Error: If the render fails.
    """
    scene.meshes = meshes.copy()
    return renderer.render(scene, assets, camera)


def rendered_new[
    C: Camera
](
    renderer: Renderer,
    var scene: Scene,
    assets: Assets,
    meshes: List[Mesh],
    camera: C,
) raises -> Framebuffer:
    """`rendered`, for a scene built in the call itself.

    Args:
        renderer: The renderer to draw with.
        scene: The scene to draw, consumed.
        assets: The geometry, materials and textures the meshes name.
        meshes: What to draw.
        camera: The camera to project through.

    Returns:
        The rendered image.

    Raises:
        Error: If the render fails.
    """
    scene.meshes = meshes.copy()
    return renderer.render(scene, assets, camera)


def prepared[
    C: Camera
](
    renderer: Renderer,
    mut scene: Scene,
    assets: Assets,
    meshes: List[Mesh],
    camera: C,
) raises -> List[RasterVertex]:
    """`Renderer.prepare` with a mesh list, as `rendered` is for `render`.

    Args:
        renderer: The renderer to prepare with.
        scene: The scene to draw; its mesh list is replaced.
        assets: The geometry, materials and textures the meshes name.
        meshes: What to draw.
        camera: The camera to project through.

    Returns:
        Raster vertices, three per triangle.

    Raises:
        Error: If preparation fails.
    """
    scene.meshes = meshes.copy()
    return renderer.prepare(scene, assets, camera)


def light_from(
    mut scene: Scene,
    x: Float32,
    y: Float32,
    z: Float32,
    ambient: Float32,
) raises:
    """Add a white lamp at a point, plus white ambient, matching the old fixed
    light exactly.

    `Renderer.set_light(direction, ambient)` gave every surface
    `ambient + (1 - ambient) * lambert`. For a white lamp that is an additive
    ambient of `ambient` plus a directional of `1 - ambient`, so the tests
    below expect the colors they always did.
    """
    var lamp = Object3D()
    lamp.set_position(x, y, z)
    var node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), ambient * FULL))
    scene.add_light(
        directional_light(Color(255, 255, 255), node, (1 - ambient) * FULL)
    )


def light_the(mut scene: Scene) raises:
    """Add the lighting these tests were written against.

    White ambient at a quarter plus a white directional at three quarters,
    from up and to the right. That is exactly the fixed light `Renderer` used
    to carry -- its `0.25 + 0.75 * lambert` is what an additive quarter and
    three quarters come to for a white lamp -- so every expected color in
    this file is unchanged by lights becoming scene objects. A color that
    moves here is a bug, not the redesign.

    Adds the lamp's node last, so the node ids meshes already name still
    point at the same nodes.
    """
    var lamp = Object3D()
    lamp.set_position(0.4, 0.8, 0.5)
    var node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25 * FULL))
    scene.add_light(directional_light(Color(255, 255, 255), node, 0.75 * FULL))


comptime TOLERANCE = Float64(1e-5)
# Small on purpose. These tests cover the renderer's logic, not its output at
# any particular size, and every covered pixel costs a probe record when the
# coverage tool instruments the rasterizer. A 60x48 viewport made the
# instrumented run minutes long; this is the same code paths for a fraction of
# the work.
comptime WIDTH = 24
comptime HEIGHT = 18


def a_camera() raises -> PerspectiveCamera:
    """Return a camera looking at the origin from along +z.

    Returns:
        The camera.

    Raises:
        Error: If its parameters are invalid.
    """
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def scene_with_node_at(z: Float32) raises -> Scene:
    """Return a scene holding one node at the given depth.

    Args:
        z: Where to put the node along z.

    Returns:
        The updated scene.

    Raises:
        Error: If the scene is invalid.
    """
    var scene = Scene()
    var node = Object3D()
    node.set_position(0, 0, z)
    _ = scene.add(node^)
    light_the(scene)
    scene.update()
    return scene^


def count_background(image: Framebuffer, background: Color) raises -> Int:
    """Return how many pixels still hold the clear color.

    Args:
        image: The rendered image.
        background: The color it was cleared to.

    Returns:
        The number of untouched pixels.

    Raises:
        Error: If a coordinate is out of bounds.
    """
    var untouched = 0
    for y in range(image.height):
        for x in range(image.width):
            var pixel = image.get_pixel(x, y)
            if (
                pixel.r == background.r
                and pixel.g == background.g
                and pixel.b == background.b
            ):
                untouched += 1
    return untouched


# --- face_normal ------------------------------------------------------------


def test_a_counter_clockwise_triangle_faces_the_viewer() raises:
    var normal = face_normal(
        Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
    )
    assert_almost_equal(normal.z, Float32(1), atol=TOLERANCE)
    assert_almost_equal(normal.x, Float32(0), atol=TOLERANCE)


def test_reversing_the_winding_reverses_the_normal() raises:
    var normal = face_normal(
        Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0)
    )
    assert_almost_equal(normal.z, Float32(-1), atol=TOLERANCE)


def test_the_normal_is_a_unit_vector() raises:
    var normal = face_normal(
        Vector3(0, 0, 0), Vector3(7, 0, 0), Vector3(0, 3, 0)
    )
    assert_almost_equal(normal.length(), Float32(1), atol=TOLERANCE)


def test_a_degenerate_triangle_has_no_normal() raises:
    # Collinear corners give a zero cross product; normalize leaves it alone
    # rather than dividing by zero.
    var normal = face_normal(
        Vector3(0, 0, 0), Vector3(1, 1, 1), Vector3(2, 2, 2)
    )
    assert_equal(normal.length(), Float32(0))


# --- Mesh -------------------------------------------------------------------


def test_a_mesh_binds_geometry_to_a_node() raises:
    var assets = Assets()
    var mesh = Mesh(
        assets.geometries.add(cube(Length(1.0, METER))),
        assets.materials.add(Material(Color(1, 2, 3))),
        NodeId(4),
    )
    assert_equal(mesh.node, NodeId(4))
    assert_equal(assets.materials.get(mesh.material).color.r, UInt8(1))
    assert_equal(assets.geometries.get(mesh.geometry).triangle_count(), 12)


def test_a_mesh_must_name_a_node() raises:
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    with assert_raises():
        _ = Mesh(
            box,
            assets.materials.add(Material(Color(1, 2, 3))),
            NodeId(-1),
        )


def test_a_mesh_must_name_a_geometry() raises:
    var assets = Assets()
    var paint = assets.materials.add(Material(Color(1, 2, 3)))
    with assert_raises():
        _ = Mesh(GeometryId(-1), paint, NodeId(0))


def test_a_mesh_must_name_a_material() raises:
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    with assert_raises():
        _ = Mesh(box, MaterialId(-1), NodeId(0))


def test_a_mesh_naming_a_material_that_is_not_there_is_rejected() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var meshes = List[Mesh]()
    meshes.append(Mesh(box, MaterialId(7), NodeId(0)))
    with assert_raises():
        _ = rendered_new(
            renderer, scene_with_node_at(0), assets, meshes, a_camera()
        )


def test_a_mesh_naming_a_geometry_that_is_not_there_is_rejected() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            GeometryId(7),
            assets.materials.add(Material(Color(255, 0, 0))),
            NodeId(0),
        )
    )
    with assert_raises():
        _ = rendered_new(
            renderer, scene_with_node_at(0), assets, meshes, a_camera()
        )


def test_two_meshes_can_share_one_geometry() raises:
    # The whole reason the store exists. One box, added once, drawn at two
    # different nodes in two different colors — and the geometry is borrowed
    # by both rather than copied into either.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    assert_equal(assets.geometries.count(), 1)

    var scene = Scene()
    var left = Object3D()
    left.set_position(-1.2, 0, 0)
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(1.2, 0, 0)
    var right_node = scene.add(right^)
    light_the(scene)
    scene.update()

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(box, assets.materials.add(Material(Color(255, 0, 0))), left_node)
    )
    meshes.append(
        Mesh(box, assets.materials.add(Material(Color(0, 0, 255))), right_node)
    )
    # Still one geometry after two meshes named it.
    assert_equal(assets.geometries.count(), 1)

    var image = rendered(renderer, scene, assets, meshes, a_camera())
    # Both boxes drew, on their own sides, in their own colors.
    var reds = 0
    var blues = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if pixel.r > pixel.b:
                reds += 1
            elif pixel.b > pixel.r:
                blues += 1
    assert_true(reds > 0, "the left box drew nothing")
    assert_true(blues > 0, "the right box drew nothing")


def test_a_geometry_id_that_is_out_of_range_is_rejected() raises:
    var assets = Assets()
    assert_equal(assets.geometries.count(), 0)
    with assert_raises():
        _ = assets.geometries.get(GeometryId(0))
    with assert_raises():
        _ = assets.geometries.get(GeometryId(-1))


# --- Renderer ---------------------------------------------------------------


def test_a_renderer_needs_a_positive_size() raises:
    with assert_raises():
        _ = Renderer(0, 10)
    with assert_raises():
        _ = Renderer(10, -1)


def test_an_empty_scene_renders_pure_background() raises:
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    var image = rendered_new(
        renderer, Scene(), assets, List[Mesh](), a_camera()
    )
    assert_equal(image.width, WIDTH)
    assert_equal(image.height, HEIGHT)
    assert_equal(count_background(image, renderer.background), WIDTH * HEIGHT)


def test_a_mesh_actually_covers_some_pixels() raises:
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = scene_with_node_at(0)
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(cube(Length(1.0, METER))),
            assets.materials.add(Material(Color(255, 0, 0))),
            NodeId(0),
        )
    )
    var image = rendered(renderer, scene, assets, meshes, a_camera())
    assert_true(count_background(image, renderer.background) < WIDTH * HEIGHT)


def test_the_background_color_is_used() raises:
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(7, 8, 9))
    var image = rendered_new(
        renderer, Scene(), assets, List[Mesh](), a_camera()
    )
    assert_equal(image.get_pixel(0, 0).r, UInt8(7))
    assert_equal(image.get_pixel(0, 0).b, UInt8(9))


def test_a_nearer_mesh_hides_a_further_one_whatever_the_order() raises:
    var assets = Assets()
    # The whole point of rendering with depth rather than painting in order.
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = Scene()
    var near = Object3D()
    near.set_position(0, 0, 1)
    var near_node = scene.add(near^)
    var far = Object3D()
    far.set_position(0, 0, -1)
    var far_node = scene.add(far^)
    light_the(scene)
    scene.update()

    var near_first = List[Mesh]()
    near_first.append(
        Mesh(
            assets.geometries.add(cube(Length(1.0, METER))),
            assets.materials.add(Material(Color(255, 0, 0))),
            near_node,
        )
    )
    near_first.append(
        Mesh(
            assets.geometries.add(cube(Length(1.0, METER))),
            assets.materials.add(Material(Color(0, 255, 0))),
            far_node,
        )
    )

    var far_first = List[Mesh]()
    far_first.append(
        Mesh(
            assets.geometries.add(cube(Length(1.0, METER))),
            assets.materials.add(Material(Color(0, 255, 0))),
            far_node,
        )
    )
    far_first.append(
        Mesh(
            assets.geometries.add(cube(Length(1.0, METER))),
            assets.materials.add(Material(Color(255, 0, 0))),
            near_node,
        )
    )

    var a = rendered(renderer, scene, assets, near_first, a_camera())
    var b = rendered(renderer, scene, assets, far_first, a_camera())
    # The center pixel belongs to the near cube either way, and both images
    # must agree everywhere.
    var center = a.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_true(center.r > center.g)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(a.get_pixel(x, y).r, b.get_pixel(x, y).r)


def test_the_scene_transform_is_what_places_a_mesh() raises:
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = Scene()
    var node = Object3D()
    node.set_position(-6, 0, 0)
    _ = scene.add(node^)
    light_the(scene)
    scene.update()
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(cube(Length(0.5, METER))),
            assets.materials.add(Material(Color(255, 0, 0))),
            NodeId(0),
        )
    )
    # Moved well off to the side, it leaves the frame entirely.
    var image = rendered(renderer, scene, assets, meshes, a_camera())
    assert_equal(count_background(image, renderer.background), WIDTH * HEIGHT)


def test_a_mesh_with_no_vertices_draws_nothing() raises:
    var assets = Assets()
    # A geometry can exist before its data does, and rendering one must be a
    # no-op rather than an error.
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = scene_with_node_at(0)
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    var nothing = assets.geometries.add(empty^)
    var paint = assets.materials.add(Material(Color(255, 0, 0)))
    # Its bounding sphere is empty, so the frustum test leaves it out
    # before a vertex is read.
    var culled = List[Mesh]()
    culled.append(Mesh(nothing, paint, NodeId(0)))
    var image = rendered(renderer, scene, assets, culled, a_camera())
    assert_equal(count_background(image, renderer.background), WIDTH * HEIGHT)
    # Opted out of that test, it goes through the whole of `prepare` with
    # zero vertices, which must be a no-op rather than an error.
    var kept = List[Mesh]()
    kept.append(Mesh(nothing, paint, NodeId(0), frustum_culled=False))
    var unculled = rendered(renderer, scene, assets, kept, a_camera())
    assert_equal(
        count_background(unculled, renderer.background), WIDTH * HEIGHT
    )


def test_a_mesh_naming_a_node_that_is_not_there_is_rejected() raises:
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(cube(Length(1.0, METER))),
            assets.materials.add(Material(Color(255, 0, 0))),
            NodeId(3),
        )
    )
    with assert_raises():
        _ = rendered_new(renderer, Scene(), assets, meshes, a_camera())


def test_a_geometry_without_normals_shades_flat() raises:
    var assets = Assets()
    # No normal attribute, so each face supplies its own and the triangle
    # takes one color throughout.
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = scene_with_node_at(0)
    var plain = BufferGeometry()
    var data = List[Float32]()
    for value in [-1.0, -1.0, 0.0, 1.0, -1.0, 0.0, 0.0, 1.0, 0.0]:
        data.append(Float32(value))
    plain.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(plain^),
            assets.materials.add(Material(Color(200, 200, 200))),
            NodeId(0),
        )
    )
    var image = rendered(renderer, scene, assets, meshes, a_camera())
    assert_true(count_background(image, renderer.background) < WIDTH * HEIGHT)


def test_a_sphere_shades_smoothly_across_a_triangle() raises:
    var assets = Assets()
    # Per-vertex normals mean neighboring pixels differ, where a flat face
    # would hold one color.
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = scene_with_node_at(0)
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(sphere(Length(1.0, METER), 16, 12)),
            assets.materials.add(Material(Color(200, 200, 200))),
            NodeId(0),
        )
    )
    var image = rendered(renderer, scene, assets, meshes, a_camera())
    var shades = 0
    var seen = List[UInt8]()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var value = image.get_pixel(x, y).r
            var known = False
            for index in range(len(seen)):
                if seen[index] == value:
                    known = True
                    break
            if not known:
                seen.append(value)
                shades += 1
    # A flat-shaded sphere would show one value per triangle band; smooth
    # shading gives a distinct value almost everywhere.
    assert_true(shades > 10)


def test_geometry_crossing_the_near_plane_is_clipped_not_mangled() raises:
    var assets = Assets()
    # The camera sits inside a large cube. Without clipping, corners behind
    # the camera project through the origin and smear across the image.
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = scene_with_node_at(0)
    var meshes = List[Mesh]()
    # Every surface visible from inside a closed mesh is a back face, so a
    # FrontSide material would correctly discard the whole cube and leave
    # nothing to judge the clipping by.
    meshes.append(
        Mesh(
            assets.geometries.add(cube(Length(8.0, METER))),
            assets.materials.add(
                Material(Color(255, 140, 40), NO_TEXTURE, DOUBLE_SIDE)
            ),
            NodeId(0),
        )
    )
    var image = rendered(renderer, scene, assets, meshes, a_camera())
    # Every pixel belongs to the cube's inside surface, and every one of them
    # is a real shade rather than a projection artifact.
    assert_true(count_background(image, renderer.background) < 100)


def test_geometry_beyond_the_far_plane_is_not_drawn() raises:
    var assets = Assets()
    # The depth buffer will not catch this on its own: it clears to infinity,
    # and a point past the far plane still projects to a finite NDC depth, so
    # it would pass the test and be drawn outside the promised frustum.
    var renderer = Renderer(WIDTH, HEIGHT)
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(10.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    # Twenty meters from a camera four meters out is well past a far plane of
    # ten, and big enough to fill the image if it were drawn at all.
    var scene = scene_with_node_at(-20)
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(cube(Length(6.0, METER))),
            assets.materials.add(Material(Color(255, 140, 40))),
            NodeId(0),
        )
    )
    var image = rendered(renderer, scene, assets, meshes, camera)
    assert_equal(count_background(image, renderer.background), WIDTH * HEIGHT)


def test_geometry_inside_the_far_plane_is_still_drawn() raises:
    var assets = Assets()
    # The other side of the same check: moving the far plane out past the cube
    # brings it back, so the test above is measuring the plane and not simply
    # a cube that was never visible.
    var renderer = Renderer(WIDTH, HEIGHT)
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var scene = scene_with_node_at(-20)
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(cube(Length(6.0, METER))),
            assets.materials.add(Material(Color(255, 140, 40))),
            NodeId(0),
        )
    )
    var image = rendered(renderer, scene, assets, meshes, camera)
    assert_true(count_background(image, renderer.background) < WIDTH * HEIGHT)


def test_a_non_uniform_scale_still_shades_the_true_surface() raises:
    var assets = Assets()
    # A flat triangle whose vertex normals are its own geometric normal. Get
    # the normal transform right and smooth shading must agree exactly with
    # flat shading from the *scaled* triangle's geometry — the surface has
    # only one normal either way. Carry the normal with the world matrix
    # instead and the two disagree, which is the bug this guards.
    var renderer = Renderer(WIDTH, HEIGHT)
    var a = Vector3(-1, -1, 0)
    var b = Vector3(1, -1, 0)
    var c = Vector3(0, 1, 1)
    var normal = face_normal(a, b, c)

    var positions = List[Float32]()
    var normals = List[Float32]()
    var corners = List[Vector3]()
    corners.append(a)
    corners.append(b)
    corners.append(c)
    for corner in range(3):
        positions.append(corners[corner].x)
        positions.append(corners[corner].y)
        positions.append(corners[corner].z)
        normals.append(normal.x)
        normals.append(normal.y)
        normals.append(normal.z)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))

    # Different factors on every axis, so the naive transform tilts the
    # normal the wrong way rather than merely rescaling it.
    var scene = Scene()
    var node = Object3D()
    node.set_scale(2.0, 0.5, 1.5)
    _ = scene.add(node^)
    light_the(scene)
    scene.update()

    var base = Color(255, 200, 120)
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(geometry^),
            assets.materials.add(Material(base)),
            NodeId(0),
        )
    )
    var image = rendered(renderer, scene, assets, meshes, a_camera())

    # What the scaled triangle's own geometry says its color must be.
    var world = scene.world_matrix(NodeId(0))
    var expected = (
        Lighting(scene)
        .shade(
            base,
            face_normal(
                world.transform_point(a),
                world.transform_point(b),
                world.transform_point(c),
            ),
            Vector3(0, 0, 0),
        )
        .encode()
    )

    var checked = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if (
                pixel.r != renderer.background.r
                or pixel.g != renderer.background.g
                or pixel.b != renderer.background.b
            ):
                assert_equal(pixel.r, expected.r)
                assert_equal(pixel.g, expected.g)
                assert_equal(pixel.b, expected.b)
                checked += 1
    assert_true(checked > 0, "the scaled triangle covered no pixels")


def test_a_smooth_geometry_with_no_vertices_draws_nothing() raises:
    # A geometry that declares normals but holds no vertices: the shading pass
    # must cope with running zero times rather than assuming at least one.
    # Opted out of frustum culling, which would otherwise spare it the pass.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    empty.set_attribute(String(NORMAL), BufferAttribute(List[Float32](), 3))
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(empty^),
            assets.materials.add(Material(Color(255, 0, 0))),
            NodeId(0),
            frustum_culled=False,
        )
    )
    var image = rendered_new(
        renderer, scene_with_node_at(0), assets, meshes, a_camera()
    )
    assert_equal(count_background(image, renderer.background), WIDTH * HEIGHT)


# --- backface culling -------------------------------------------------------


def test_a_front_side_material_hides_the_inside_of_a_cube() raises:
    # From inside a closed mesh every visible surface faces away, so the
    # default FrontSide leaves nothing at all. That is the honest consequence
    # of the default, and the reason `side` has to exist.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(cube(Length(8.0, METER))),
            assets.materials.add(Material(Color(255, 140, 40))),
            NodeId(0),
        )
    )
    var image = rendered_new(
        renderer, scene_with_node_at(0), assets, meshes, a_camera()
    )
    assert_equal(count_background(image, renderer.background), WIDTH * HEIGHT)


def test_culling_does_not_change_a_solid_seen_from_outside() raises:
    # The point of the optimization: on a closed mesh the faces it discards
    # are exactly the ones the depth buffer was already hiding, so the image
    # must come out identical either way.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(box, assets.materials.add(Material(Color(255, 0, 0))), NodeId(0))
    )
    var scene = scene_with_node_at(0)

    var culled = rendered(renderer, scene, assets, meshes, a_camera())
    var both = List[Mesh]()
    both.append(
        Mesh(
            box,
            assets.materials.add(
                Material(Color(255, 0, 0), NO_TEXTURE, DOUBLE_SIDE)
            ),
            NodeId(0),
        )
    )
    var complete = rendered(renderer, scene, assets, both, a_camera())

    var drawn = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(culled.get_pixel(x, y).r, complete.get_pixel(x, y).r)
            assert_equal(culled.get_pixel(x, y).g, complete.get_pixel(x, y).g)
            if culled.get_pixel(x, y).r != renderer.background.r:
                drawn += 1
    assert_true(drawn > 0, "the cube drew nothing, so nothing was compared")


def test_culling_halves_the_triangles_of_a_closed_mesh() raises:
    # Roughly: a convex solid shows half its faces. Measured on the prepared
    # triangles rather than on timings, which is the part that is actually a
    # property of the renderer.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(1.0, METER), 16, 12))
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            ball,
            assets.materials.add(Material(Color(200, 200, 200))),
            NodeId(0),
        )
    )
    var scene = scene_with_node_at(0)

    var kept = prepared(renderer, scene, assets, meshes, a_camera())
    var both = List[Mesh]()
    both.append(
        Mesh(
            ball,
            assets.materials.add(
                Material(Color(200, 200, 200), NO_TEXTURE, DOUBLE_SIDE)
            ),
            NodeId(0),
        )
    )
    var everything = prepared(renderer, scene, assets, both, a_camera())

    assert_true(len(kept) > 0)
    assert_true(len(kept) < len(everything))
    # Comfortably inside "about half", without pinning an exact count.
    assert_true(len(kept) * 3 < len(everything) * 2)


# --- the shading mode -------------------------------------------------------


def test_uv_mode_draws_texture_coordinates_instead_of_lighting() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var scene = scene_with_node_at(0)
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(box, assets.materials.add(Material(Color(255, 0, 0))), NodeId(0))
    )

    var lit = rendered(renderer, scene, assets, meshes, a_camera())
    renderer.set_shading(SHADE_UV)
    var mapped = rendered(renderer, scene, assets, meshes, a_camera())

    # A box face runs uv from (0,0) to (1,1), so the mapped image has both a
    # red and a green gradient where the lit one has neither.
    var differing = 0
    var any_green = False
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var one = lit.get_pixel(x, y)
            var two = mapped.get_pixel(x, y)
            if one.r != two.r or one.g != two.g or one.b != two.b:
                differing += 1
            if two.g > 0 and two.b == 0:
                any_green = True
    assert_true(differing > 0, "the shading mode changed nothing")
    assert_true(any_green, "no texture coordinate reached the image")


def test_every_known_shading_mode_is_accepted() raises:
    # Each operand of the check has to be able to decide the outcome alone.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_shading(SHADE_UV)
    assert_equal(renderer.shading, SHADE_UV)
    renderer.set_shading(SHADE_LIT)
    assert_equal(renderer.shading, SHADE_LIT)
    renderer.set_shading(SHADE_TEXTURE)
    assert_equal(renderer.shading, SHADE_TEXTURE)


def test_a_mapped_geometry_with_no_vertices_draws_nothing() raises:
    # A geometry that declares texture coordinates but holds no vertices: the
    # uv-gathering pass must cope with running zero times. Opted out of
    # frustum culling, which would otherwise spare it the pass.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_shading(SHADE_UV)
    var assets = Assets()
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    empty.set_attribute(String(UV), BufferAttribute(List[Float32](), 2))
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(empty^),
            assets.materials.add(Material(Color(255, 0, 0))),
            NodeId(0),
            frustum_culled=False,
        )
    )
    var image = rendered_new(
        renderer, scene_with_node_at(0), assets, meshes, a_camera()
    )
    assert_equal(count_background(image, renderer.background), WIDTH * HEIGHT)


def test_a_geometry_without_uv_maps_to_the_texture_origin() raises:
    # No uv attribute means zeroes rather than whatever was lying around.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_shading(SHADE_UV)
    var assets = Assets()
    var plain = BufferGeometry()
    var data = List[Float32]()
    for value in [
        Float32(-1),
        Float32(-1),
        Float32(0),
        Float32(1),
        Float32(-1),
        Float32(0),
        Float32(0),
        Float32(1),
        Float32(0),
    ]:
        data.append(value)
    plain.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(plain^),
            assets.materials.add(Material(Color(200, 200, 200))),
            NodeId(0),
        )
    )
    var image = rendered_new(
        renderer, scene_with_node_at(0), assets, meshes, a_camera()
    )
    var drawn = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if (
                pixel.r != renderer.background.r
                or pixel.g != renderer.background.g
                or pixel.b != renderer.background.b
            ):
                drawn += 1
                assert_equal(pixel.r, UInt8(0))
                assert_equal(pixel.g, UInt8(0))
    assert_true(drawn > 0, "the triangle drew nothing")


# --- mirrored transforms ----------------------------------------------------


def lone_triangle(with_normals: Bool) raises -> BufferGeometry:
    """Return one counter-clockwise triangle facing +z.

    Args:
        with_normals: Whether to give each vertex the triangle's own normal.

    Returns:
        The geometry.

    Raises:
        Error: If the attributes are malformed, which they are not.
    """
    var data = List[Float32]()
    for value in [
        Float32(-1),
        Float32(-1),
        Float32(0),
        Float32(1),
        Float32(-1),
        Float32(0),
        Float32(0),
        Float32(1),
        Float32(0),
    ]:
        data.append(value)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    if with_normals:
        var normals = List[Float32]()
        for _ in range(3):
            normals.append(0)
            normals.append(0)
            normals.append(1)
        geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    return geometry^


def scaled_scene(x: Float32, y: Float32, z: Float32) raises -> Scene:
    """Return a scene with one node scaled by the given factors."""
    var scene = Scene()
    var node = Object3D()
    node.set_scale(x, y, z)
    _ = scene.add(node^)
    light_the(scene)
    scene.update()
    return scene^


def rendered_triangle(
    renderer: Renderer, mut scene: Scene, with_normals: Bool
) raises -> Framebuffer:
    """Render the lone triangle through `scene`'s only node.

    Args:
        renderer: The renderer to draw with.
        scene: A scene whose node zero carries the transform.
        with_normals: Whether the geometry supplies normals.

    Returns:
        The rendered image.

    Raises:
        Error: If the render fails.
    """
    var assets = Assets()
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(lone_triangle(with_normals)),
            assets.materials.add(Material(Color(200, 200, 200))),
            NodeId(0),
        )
    )
    return rendered(renderer, scene, assets, meshes, a_camera())


def rendered_triangle_in(
    renderer: Renderer, var scene: Scene, with_normals: Bool
) raises -> Framebuffer:
    """`rendered_triangle` for a scene built in the call itself.

    Args:
        renderer: The renderer to draw with.
        scene: The scene to draw, consumed.
        with_normals: Whether the geometry supplies normals.

    Returns:
        The rendered image.

    Raises:
        Error: If the render fails.
    """
    return rendered_triangle(renderer, scene, with_normals)


def test_a_mirrored_mesh_is_not_culled_away() raises:
    # A negative scale reverses winding, so the front face reads as a back
    # face and culling removed it entirely. The first version of this drew
    # nothing at all.
    var renderer = Renderer(WIDTH, HEIGHT)
    var plain = rendered_triangle_in(renderer, scaled_scene(1, 1, 1), False)
    var mirrored = rendered_triangle_in(renderer, scaled_scene(-1, 1, 1), False)
    var drawn = WIDTH * HEIGHT - count_background(plain, renderer.background)
    var reflected = WIDTH * HEIGHT - count_background(
        mirrored, renderer.background
    )
    assert_true(drawn > 0, "the unmirrored triangle drew nothing")
    # Symmetric about x, so mirroring covers exactly as much.
    assert_equal(reflected, drawn)


def test_a_reflection_inherited_from_a_parent_counts_too() raises:
    # The determinant has to come from the world matrix. A node with no scale
    # of its own is still mirrored if a parent reflects it.
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = Scene()
    var parent = Object3D()
    parent.set_scale(-1, 1, 1)
    var root = scene.add(parent^)
    _ = scene.attach(Object3D(), root)
    light_the(scene)
    scene.update()

    var assets = Assets()
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(lone_triangle(False)),
            assets.materials.add(Material(Color(200, 200, 200))),
            NodeId(1),
        )
    )
    var image = rendered(renderer, scene, assets, meshes, a_camera())
    assert_true(
        count_background(image, renderer.background) < WIDTH * HEIGHT,
        "an inherited reflection culled the mesh away",
    )


def test_two_reflections_cancel() raises:
    # Determinant positive again, so the ordinary convention applies. An
    # implementation that looked at any negative scale factor rather than the
    # determinant would get this backwards.
    var renderer = Renderer(WIDTH, HEIGHT)
    var plain = rendered_triangle_in(renderer, scaled_scene(1, 1, 1), False)
    var twice = rendered_triangle_in(renderer, scaled_scene(-1, -1, 1), False)
    var drawn = WIDTH * HEIGHT - count_background(plain, renderer.background)
    var both = WIDTH * HEIGHT - count_background(twice, renderer.background)
    assert_true(drawn > 0)
    assert_equal(both, drawn)


def test_a_mirrored_mesh_shades_the_same_with_and_without_normals() raises:
    # The two normal paths must mean the same side. Carried through the
    # inverse transpose a supplied normal does not flip; the cross product of
    # the mirrored triangle's world edges does. Left alone they disagreed,
    # and an object shaded differently purely for having normals.
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = scaled_scene(-1, 1, 1)
    var supplied = rendered_triangle(renderer, scene, True)
    var derived = rendered_triangle(renderer, scene, False)
    var compared = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var one = supplied.get_pixel(x, y)
            var two = derived.get_pixel(x, y)
            if one.r != renderer.background.r:
                compared += 1
            assert_equal(one.r, two.r)
            assert_equal(one.g, two.g)
            assert_equal(one.b, two.b)
    assert_true(compared > 0, "nothing was drawn, so nothing was compared")


def test_an_unmirrored_mesh_still_agrees_between_the_normal_paths() raises:
    # The other side of the same check, so the fix cannot have been to flip
    # the fallback unconditionally.
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = scaled_scene(1, 1, 1)
    var supplied = rendered_triangle(renderer, scene, True)
    var derived = rendered_triangle(renderer, scene, False)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(supplied.get_pixel(x, y).r, derived.get_pixel(x, y).r)


# --- textures ---------------------------------------------------------------


def test_a_material_without_a_map_shades_as_plain_color() raises:
    # The blank texture samples as white and white is the identity for
    # modulation, so a material with no map costs nothing and needs no branch:
    # following the material and ignoring every texture agree exactly.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var paint = assets.materials.add(Material(Color(220, 160, 80)))
    var scene = scene_with_node_at(0)
    var meshes = List[Mesh]()
    meshes.append(Mesh(box, paint, NodeId(0)))

    var followed = rendered(renderer, scene, assets, meshes, a_camera())
    renderer.set_shading(SHADE_LIT)
    var ignored = rendered(renderer, scene, assets, meshes, a_camera())
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(followed.get_pixel(x, y).r, ignored.get_pixel(x, y).r)
            assert_equal(followed.get_pixel(x, y).g, ignored.get_pixel(x, y).g)


def test_a_map_changes_what_a_mesh_looks_like() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var scene = scene_with_node_at(0)

    var plain_meshes = List[Mesh]()
    plain_meshes.append(
        Mesh(
            box, assets.materials.add(Material(Color(255, 255, 255))), NodeId(0)
        )
    )
    var board = assets.textures.add(
        checkerboard(8, 4, Color(255, 255, 255), Color(20, 20, 20))
    )
    var mapped_meshes = List[Mesh]()
    mapped_meshes.append(
        Mesh(
            box,
            assets.materials.add(Material(Color(255, 255, 255), board)),
            NodeId(0),
        )
    )

    var plain = rendered(renderer, scene, assets, plain_meshes, a_camera())
    var patterned = rendered(renderer, scene, assets, mapped_meshes, a_camera())

    var differing = 0
    var dark = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var one = plain.get_pixel(x, y)
            var two = patterned.get_pixel(x, y)
            if one.r != two.r:
                differing += 1
            # The dark squares of the board, not the background.
            if two.r < one.r and one.r != renderer.background.r:
                dark += 1
    assert_true(differing > 0, "the texture changed nothing")
    assert_true(dark > 0, "no dark square reached the image")


def test_two_meshes_can_carry_different_textures() raises:
    # The thing `Material` was built for, and the thing a texture on the
    # renderer made impossible: one scene, two images. Before this the whole
    # scene shared a single texture and this test could not be written.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(0.8, METER)))
    var reds = assets.textures.add(
        checkerboard(8, 2, Color(255, 40, 40), Color(90, 10, 10))
    )
    var blues = assets.textures.add(
        checkerboard(8, 2, Color(40, 40, 255), Color(10, 10, 90))
    )

    var scene = Scene()
    var left = Object3D()
    left.set_position(-0.9, 0, 0)
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(0.9, 0, 0)
    var right_node = scene.add(right^)
    light_the(scene)
    scene.update()

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            box,
            assets.materials.add(Material(Color(255, 255, 255), reds)),
            left_node,
        )
    )
    meshes.append(
        Mesh(
            box,
            assets.materials.add(Material(Color(255, 255, 255), blues)),
            right_node,
        )
    )
    # One geometry, two materials, two textures.
    assert_equal(assets.geometries.count(), 1)
    assert_equal(assets.materials.count(), 2)
    assert_equal(assets.textures.count(), 2)

    var image = rendered(renderer, scene, assets, meshes, a_camera())
    var reddish = 0
    var bluish = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if pixel.r > pixel.b and pixel.r != renderer.background.r:
                reddish += 1
            if pixel.b > pixel.r and pixel.b != renderer.background.b:
                bluish += 1
    assert_true(reddish > 0, "the red-mapped cube did not draw")
    assert_true(bluish > 0, "the blue-mapped cube did not draw")


def test_lit_shading_ignores_every_map() raises:
    # The override. Two separate decisions: what image a material names, and
    # whether the renderer is reading any at all.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_shading(SHADE_LIT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var board = assets.textures.add(
        checkerboard(8, 4, Color(255, 255, 255), Color(20, 20, 20))
    )
    var scene = scene_with_node_at(0)

    var plain = List[Mesh]()
    plain.append(
        Mesh(
            box, assets.materials.add(Material(Color(255, 255, 255))), NodeId(0)
        )
    )
    var mapped = List[Mesh]()
    mapped.append(
        Mesh(
            box,
            assets.materials.add(Material(Color(255, 255, 255), board)),
            NodeId(0),
        )
    )

    var without = rendered(renderer, scene, assets, plain, a_camera())
    var with_map = rendered(renderer, scene, assets, mapped, a_camera())
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(without.get_pixel(x, y).r, with_map.get_pixel(x, y).r)


def test_a_renderer_follows_materials_by_default() raises:
    assert_equal(Renderer(WIDTH, HEIGHT).shading, SHADE_TEXTURE)


def test_texture_shading_is_a_known_mode() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_shading(SHADE_TEXTURE)
    assert_equal(renderer.shading, SHADE_TEXTURE)


def test_a_back_side_material_draws_what_front_side_hides() raises:
    # BackSide is the third state a Bool could not express: it draws *only*
    # the faces pointing away. On a closed cube seen from outside that is the
    # far half, so something is drawn, and it is not what FrontSide drew.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var scene = scene_with_node_at(0)

    var front = List[Mesh]()
    front.append(
        Mesh(box, assets.materials.add(Material(Color(255, 0, 0))), NodeId(0))
    )
    var back = List[Mesh]()
    back.append(
        Mesh(
            box,
            assets.materials.add(
                Material(Color(255, 0, 0), NO_TEXTURE, BACK_SIDE)
            ),
            NodeId(0),
        )
    )

    var outside = rendered(renderer, scene, assets, front, a_camera())
    var inside = rendered(renderer, scene, assets, back, a_camera())
    var drawn_front = WIDTH * HEIGHT - count_background(
        outside, renderer.background
    )
    var drawn_back = WIDTH * HEIGHT - count_background(
        inside, renderer.background
    )
    assert_true(drawn_front > 0, "FrontSide drew nothing")
    assert_true(drawn_back > 0, "BackSide drew nothing")

    # Same silhouette, different surfaces: the two images must differ.
    var differing = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if outside.get_pixel(x, y).r != inside.get_pixel(x, y).r:
                differing += 1
    assert_true(differing > 0, "BackSide drew the same faces as FrontSide")


def test_a_back_side_material_shows_the_inside_of_a_cube() raises:
    # From within a closed mesh every visible surface faces away, so BackSide
    # sees all of it where FrontSide sees none.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(cube(Length(8.0, METER))),
            assets.materials.add(
                Material(Color(255, 140, 40), NO_TEXTURE, BACK_SIDE)
            ),
            NodeId(0),
        )
    )
    var image = rendered_new(
        renderer, scene_with_node_at(0), assets, meshes, a_camera()
    )
    assert_true(count_background(image, renderer.background) < 100)


def test_a_back_side_surface_is_lit_on_its_back() raises:
    # three.js's `flipSided` is `side === BackSide`, and its
    # `defaultnormal_vertex` negates the normal under `FLIP_SIDED` beside
    # turning the winding round. So a triangle whose authored normal is
    # +z, seen from -z with the light shining along -z, faces the light
    # square-on and is fully lit. This once kept the authored normal,
    # which left it dark; the shader says otherwise.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var tri = assets.geometries.add(lone_triangle(True))
    var paint = assets.materials.add(
        Material(Color(255, 255, 255), NO_TEXTURE, BACK_SIDE)
    )
    var scene = Scene()
    _ = scene.add(Object3D())
    light_from(scene, 0, 0, -1, 0.0)
    scene.update()
    var meshes = List[Mesh]()
    meshes.append(Mesh(tri, paint, NodeId(0)))

    var behind = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    behind.place(Vector3(0, 0, -4), Vector3(0, 0, 0))
    var image = rendered(renderer, scene, assets, meshes, behind)

    var drawn = 0
    var brightest = UInt8(0)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if pixel.r != renderer.background.r:
                drawn += 1
                if pixel.r > brightest:
                    brightest = pixel.r
    assert_true(drawn > 0, "BackSide drew nothing to light")
    # Ambient is zero and the flipped normal faces the light square-on.
    assert_equal(brightest, UInt8(255))


def test_a_back_side_surface_is_dark_on_its_authored_side() raises:
    # The other direction, so the rule cannot have been to light both
    # sides. Same geometry, light now on the side the authored normal
    # faces, which is the side nobody is looking at: the flipped normal
    # points away from it, and three.js leaves it dark.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var tri = assets.geometries.add(lone_triangle(True))
    var paint = assets.materials.add(
        Material(Color(255, 255, 255), NO_TEXTURE, BACK_SIDE)
    )
    var scene = Scene()
    _ = scene.add(Object3D())
    light_from(scene, 0, 0, 1, 0.0)
    scene.update()
    var meshes = List[Mesh]()
    meshes.append(Mesh(tri, paint, NodeId(0)))

    var behind = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    behind.place(Vector3(0, 0, -4), Vector3(0, 0, 0))
    var image = rendered(renderer, scene, assets, meshes, behind)

    var drawn = 0
    var brightest = UInt8(0)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if pixel.r != renderer.background.r or (
                pixel.g != renderer.background.g
            ):
                drawn += 1
                if pixel.r > brightest:
                    brightest = pixel.r
    assert_true(drawn > 0, "BackSide drew nothing to light")
    # Ambient is zero and the flipped normal points away from the light.
    assert_equal(brightest, UInt8(0))


def test_a_double_side_surface_lights_each_half_on_its_own_side() raises:
    # DoubleSide keeps both, so within one mesh some triangles are seen from
    # the front and some from behind, and each must use its own side's
    # lighting. A geometry with no normals exercises the fallback path.
    var renderer = Renderer(WIDTH, HEIGHT)
    # The camera sits inside a ten-meter cube, four meters from the center,
    # so every visible surface is the *inside* of a wall -- a back face. The
    # light is behind the camera, shining at the far wall's visible side.
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(10.0, METER)))
    var paint = assets.materials.add(
        Material(Color(255, 255, 255), NO_TEXTURE, DOUBLE_SIDE)
    )
    var meshes = List[Mesh]()
    meshes.append(Mesh(box, paint, NodeId(0)))
    var scene = Scene()
    _ = scene.add(Object3D())
    light_from(scene, 0, 0, 1, 0.0)
    scene.update()
    var image = rendered(renderer, scene, assets, meshes, a_camera())
    # The far wall's visible side faces the light square-on, so with no
    # ambient it is fully lit. Using the authored outward normal instead
    # would light the side facing away and leave it black.
    var brightest = UInt8(0)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if image.get_pixel(x, y).r > brightest:
                brightest = image.get_pixel(x, y).r
    assert_equal(brightest, UInt8(255))


def test_a_material_naming_a_texture_that_is_not_there_is_rejected() raises:
    # A material is built without the store in reach, so a positive id naming
    # nothing is only detectable once both are together.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(
        Material(Color(255, 255, 255), TextureId(3))
    )
    var meshes = List[Mesh]()
    meshes.append(Mesh(box, paint, NodeId(0)))
    with assert_raises():
        _ = rendered_new(
            renderer, scene_with_node_at(0), assets, meshes, a_camera()
        )


# --- transparency -----------------------------------------------------------


def test_a_translucent_mesh_lets_the_one_behind_it_show() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var solid = assets.materials.add(Material(Color(0, 255, 0)))
    var glass = assets.materials.add(
        Material(
            Color(255, 0, 0), NO_TEXTURE, FRONT_SIDE, 0.5, transparent=True
        )
    )

    var scene = Scene()
    var back = Object3D()
    back.set_position(0, 0, -0.8)
    var back_node = scene.add(back^)
    var front = Object3D()
    front.set_position(0, 0, 0.8)
    var front_node = scene.add(front^)
    light_the(scene)
    scene.update()

    var meshes = List[Mesh]()
    meshes.append(Mesh(box, solid, back_node))
    meshes.append(Mesh(box, glass, front_node))
    var image = rendered(renderer, scene, assets, meshes, a_camera())

    var center = image.get_pixel(WIDTH // 2, HEIGHT // 2)
    # Both the red pane and the green box behind it are in the result.
    assert_true(center.r > 0, "the translucent box did not draw")
    assert_true(center.g > 0, "the solid box behind it was hidden")


def test_an_opaque_mesh_hides_what_is_behind_it() raises:
    # The same scene with the front box made solid, so the difference is the
    # opacity and nothing else.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var solid = assets.materials.add(Material(Color(0, 255, 0)))
    var front_solid = assets.materials.add(Material(Color(255, 0, 0)))

    var scene = Scene()
    var back = Object3D()
    back.set_position(0, 0, -0.8)
    var back_node = scene.add(back^)
    var front = Object3D()
    front.set_position(0, 0, 0.8)
    var front_node = scene.add(front^)
    light_the(scene)
    scene.update()

    var meshes = List[Mesh]()
    meshes.append(Mesh(box, solid, back_node))
    meshes.append(Mesh(box, front_solid, front_node))
    var image = rendered(renderer, scene, assets, meshes, a_camera())
    assert_equal(image.get_pixel(WIDTH // 2, HEIGHT // 2).g, UInt8(0))


def test_translucent_meshes_are_drawn_after_opaque_ones() raises:
    # Blending is not commutative, so the order is not the caller's. Here the
    # translucent pane is submitted *first* and the solid box second; drawing
    # in that order would blend the pane with the background and then paint
    # the box over it, hiding the pane entirely.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var glass = assets.materials.add(
        Material(
            Color(255, 0, 0), NO_TEXTURE, FRONT_SIDE, 0.5, transparent=True
        )
    )
    var solid = assets.materials.add(Material(Color(0, 255, 0)))

    var scene = Scene()
    var front = Object3D()
    front.set_position(0, 0, 0.8)
    var front_node = scene.add(front^)
    var back = Object3D()
    back.set_position(0, 0, -0.8)
    var back_node = scene.add(back^)
    light_the(scene)
    scene.update()

    var meshes = List[Mesh]()
    meshes.append(Mesh(box, glass, front_node))
    meshes.append(Mesh(box, solid, back_node))
    var image = rendered(renderer, scene, assets, meshes, a_camera())
    var center = image.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_true(center.r > 0, "the translucent pane was painted over")
    assert_true(center.g > 0, "the solid box did not draw")


def test_translucent_meshes_are_sorted_back_to_front() raises:
    # Two panes, submitted near-first. Drawn in that order the far one would
    # blend over the near one, which is visibly wrong; sorted, the near one
    # dominates. Comparing the two orders is what shows the sort happened.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var red = assets.materials.add(
        Material(
            Color(255, 0, 0), NO_TEXTURE, FRONT_SIDE, 0.5, transparent=True
        )
    )
    var blue = assets.materials.add(
        Material(
            Color(0, 0, 255), NO_TEXTURE, FRONT_SIDE, 0.5, transparent=True
        )
    )

    var scene = Scene()
    var near = Object3D()
    near.set_position(0, 0, 0.9)
    var near_node = scene.add(near^)
    var far = Object3D()
    far.set_position(0, 0, -0.9)
    var far_node = scene.add(far^)
    light_the(scene)
    scene.update()

    var near_first = List[Mesh]()
    near_first.append(Mesh(box, red, near_node))
    near_first.append(Mesh(box, blue, far_node))
    var far_first = List[Mesh]()
    far_first.append(Mesh(box, blue, far_node))
    far_first.append(Mesh(box, red, near_node))

    var one = rendered(renderer, scene, assets, near_first, a_camera())
    var two = rendered(renderer, scene, assets, far_first, a_camera())
    # Sorting makes submission order irrelevant.
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(one.get_pixel(x, y).r, two.get_pixel(x, y).r)
            assert_equal(one.get_pixel(x, y).b, two.get_pixel(x, y).b)
    # And the nearer red pane dominates, as the last thing blended in.
    var center = one.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_true(center.r > center.b)


def test_opacity_outside_zero_to_one_is_rejected() raises:
    with assert_raises():
        _ = Material(Color(1, 2, 3), NO_TEXTURE, FRONT_SIDE, -0.1)
    with assert_raises():
        _ = Material(Color(1, 2, 3), NO_TEXTURE, FRONT_SIDE, 1.5)


def test_a_material_is_opaque_by_default() raises:
    assert_false(Material(Color(1, 2, 3)).is_transparent())
    # An opacity below one changes nothing on its own, as in three.js: the
    # material has to say it is transparent.
    assert_false(
        Material(Color(1, 2, 3), NO_TEXTURE, FRONT_SIDE, 0.5).is_transparent()
    )
    assert_true(
        Material(
            Color(1, 2, 3), NO_TEXTURE, FRONT_SIDE, 0.5, transparent=True
        ).is_transparent()
    )


def test_a_translucent_base_color_sorts_and_rasterizes_the_same_way() raises:
    # One material, one answer. A base color with alpha but an opacity of one
    # used to sort as opaque and rasterize as blended: it did not write depth,
    # so whatever was submitted after it painted straight over the top, and
    # the image depended on submission order.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var red = assets.materials.add(
        Material(Color(255, 0, 0, 128), transparent=True)
    )
    var blue = assets.materials.add(Material(Color(0, 0, 255)))
    assert_true(
        assets.materials.get(red).is_transparent(),
        "a transparent material must count as transparent",
    )

    var scene = Scene()
    var front = Object3D()
    front.set_position(0, 0, 0.9)
    var front_node = scene.add(front^)
    var back = Object3D()
    back.set_position(0, 0, -0.9)
    var back_node = scene.add(back^)
    light_from(scene, 0, 0, 1, 1.0)
    scene.update()

    var red_first = List[Mesh]()
    red_first.append(Mesh(box, red, front_node))
    red_first.append(Mesh(box, blue, back_node))
    var blue_first = List[Mesh]()
    blue_first.append(Mesh(box, blue, back_node))
    blue_first.append(Mesh(box, red, front_node))

    var one = rendered(renderer, scene, assets, red_first, a_camera())
    var two = rendered(renderer, scene, assets, blue_first, a_camera())
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(one.get_pixel(x, y).r, two.get_pixel(x, y).r)
            assert_equal(one.get_pixel(x, y).b, two.get_pixel(x, y).b)
    # And the translucent red really is mixed with the blue behind it.
    var center = one.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_true(center.r > 0 and center.b > 0)


def test_blending_can_be_named_against_what_the_color_suggests() raises:
    # A texture's own alpha cannot be inferred from the material, so the
    # policy has to be sayable. Both directions, so neither is the only path.
    var opaque_looking = Material(
        Color(255, 255, 255), NO_TEXTURE, FRONT_SIDE, 1.0, BLEND
    )
    assert_true(opaque_looking.is_transparent())
    var clear_looking = Material(
        Color(255, 255, 255, 10), NO_TEXTURE, FRONT_SIDE, 0.2, OPAQUE
    )
    assert_false(clear_looking.is_transparent())


# --- workers ----------------------------------------------------------------


def test_opaque_meshes_are_drawn_nearest_first() raises:
    # The image does not depend on it; the work does. A hidden fragment that
    # fails the depth test is skipped before it is shaded, so the near mesh
    # goes first and the far one's covered pixels are never lit.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    var scene = Scene()
    var far = Object3D()
    far.set_position(0, 0, -1.5)
    var far_node = scene.add(far^)
    var near = Object3D()
    near.set_position(0, 0, 1.5)
    var near_node = scene.add(near^)
    light_the(scene)
    scene.update()
    # Far first, so an unsorted renderer would prepare it first.
    var meshes = List[Mesh]()
    meshes.append(Mesh(box, paint, far_node))
    meshes.append(Mesh(box, paint, near_node))
    var corners = prepared(renderer, scene, assets, meshes, a_camera())
    assert_true(len(corners) >= 6)
    # NDC depth grows with distance, so the first triangle prepared must be
    # nearer than the last.
    assert_true(corners[0].z < corners[len(corners) - 1].z)


def test_a_geometry_whose_index_points_past_its_vertices_is_refused() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var geometry = BufferGeometry()
    var positions = List[Float32]()
    for value in [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0]:
        positions.append(Float32(value))
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    var index = List[Int]()
    for entry in [0, 1, 7]:
        index.append(entry)
    geometry.set_index(index^)
    var scene = scene_with_node_at(0)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(geometry^),
            assets.materials.add(Material(Color(255, 0, 0))),
            NodeId(0),
        )
    )
    with assert_raises():
        _ = renderer.render(scene, assets, a_camera())


def test_available_workers_is_at_least_one() raises:
    # One per logical core, and every machine has a core.
    assert_true(available_workers() >= 1)
    _ = Renderer(WIDTH, HEIGHT, workers=available_workers())


def test_workers_must_be_at_least_one() raises:
    with assert_raises():
        _ = Renderer(WIDTH, HEIGHT, workers=0)
    var renderer = Renderer(WIDTH, HEIGHT)
    with assert_raises():
        renderer.set_workers(-3)
    renderer.set_workers(4)
    assert_equal(renderer.workers, 4)


def test_several_workers_draw_the_same_image_as_one() raises:
    # Bands own their rows and draw in submission order, so the image must be
    # byte for byte the same however many threads share it. Textured,
    # translucent and opaque surfaces together, so blending and sampling
    # both cross band boundaries.
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var solid = assets.materials.add(Material(Color(255, 255, 255)))
    var glass = assets.materials.add(
        Material(
            Color(255, 80, 80), NO_TEXTURE, DOUBLE_SIDE, 0.5, transparent=True
        )
    )
    var scene = Scene()
    var back = Object3D()
    back.set_position(0, 0, -0.8)
    var back_node = scene.add(back^)
    var front = Object3D()
    front.set_position(0.3, 0.2, 0.8)
    var front_node = scene.add(front^)
    light_the(scene)
    scene.update()
    scene.add_mesh(Mesh(box, solid, back_node))
    scene.add_mesh(Mesh(box, glass, front_node))

    var alone = Renderer(WIDTH, HEIGHT)
    var crowd = Renderer(WIDTH, HEIGHT, workers=3)
    # More workers than rows: one band per row, the most the image allows.
    var mob = Renderer(WIDTH, HEIGHT, workers=HEIGHT + 5)
    var one = alone.render(scene, assets, a_camera())
    var many = crowd.render(scene, assets, a_camera())
    var most = mob.render(scene, assets, a_camera())
    assert_true(count_background(one, alone.background) < WIDTH * HEIGHT)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var here = one.get_pixel(x, y)
            var there = many.get_pixel(x, y)
            var yonder = most.get_pixel(x, y)
            var spot = "pixel " + String(x) + "," + String(y)
            assert_equal(here.r, there.r, spot)
            assert_equal(here.g, there.g, spot)
            assert_equal(here.b, there.b, spot)
            assert_equal(here.a, there.a, spot)
            assert_equal(one.depth_at(x, y), many.depth_at(x, y), spot)
            assert_equal(here.r, yonder.r, spot)
            assert_equal(here.g, yonder.g, spot)
            assert_equal(here.b, yonder.b, spot)
            assert_equal(here.a, yonder.a, spot)
            assert_equal(one.depth_at(x, y), most.depth_at(x, y), spot)


def test_more_workers_than_rows_still_renders() raises:
    var assets = Assets()
    var renderer = Renderer(WIDTH, 3, workers=64)
    var scene = scene_with_node_at(0)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(cube(Length(1.0, METER))),
            assets.materials.add(Material(Color(255, 0, 0))),
            NodeId(0),
        )
    )
    var image = renderer.render(scene, assets, a_camera())
    assert_true(count_background(image, renderer.background) < WIDTH * 3)


def test_an_empty_scene_renders_with_several_workers() raises:
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT, workers=3)
    var image = renderer.render(Scene(), assets, a_camera())
    assert_equal(count_background(image, renderer.background), WIDTH * HEIGHT)


# --- cameras on nodes, point lights, unlit materials -------------------------


def eye_camera() raises -> PerspectiveCamera:
    """Return a camera three meters up +z, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 3), Vector3(0, 0, 0))
    return camera^


def test_a_camera_riding_a_node_renders_the_same_image() raises:
    # A node three meters up +z with no rotation is exactly the placement
    # `eye_camera` describes, so the two views are the same matrix and the
    # two images the same pixels.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(255, 140, 40)))
    var scene = Scene()
    var block = Object3D()
    block.set_euler(
        Angle(25.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE)
    )
    var node = scene.add(block^)
    light_the(scene)
    var eye = Object3D()
    eye.set_position(0, 0, 3)
    var rig = scene.add(eye^)
    scene.update()
    var meshes = List[Mesh]()
    meshes.append(Mesh(box, paint, node))

    var placed = eye_camera()
    var riding = eye_camera()
    riding.attach(rig)
    var expected = rendered(renderer, scene, assets, meshes, placed)
    var got = rendered(renderer, scene, assets, meshes, riding)
    var drawn = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var want = expected.get_pixel(x, y)
            var have = got.get_pixel(x, y)
            assert_equal(have.r, want.r)
            assert_equal(have.g, want.g)
            assert_equal(have.b, want.b)
            if want.r != renderer.background.r:
                drawn += 1
    assert_true(drawn > 0, "the cube was not drawn")


def test_a_point_light_lights_the_part_of_a_face_nearest_it() raises:
    # A cube seen square-on, one bulb just in front of the right half of its
    # near face, and nothing else. The right half is nearer the bulb and
    # turned towards it; the left half is further. So the right is brighter,
    # which is only possible if each fragment knows where it is in the world.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var white = assets.materials.add(Material(Color(255, 255, 255)))
    var scene = Scene()
    var node = scene.add(Object3D())
    var bulb = Object3D()
    bulb.set_position(0.4, 0, 1.5)
    var lamp = scene.add(bulb^)
    scene.add_light(point_light(Color(255, 255, 255), lamp, 0.25))
    scene.update()
    var meshes = List[Mesh]()
    meshes.append(Mesh(box, white, node))
    var image = rendered(renderer, scene, assets, meshes, eye_camera())
    var left = image.get_pixel(WIDTH // 2 - 3, HEIGHT // 2).r
    var right = image.get_pixel(WIDTH // 2 + 2, HEIGHT // 2).r
    assert_true(left > renderer.background.r, "the face was not lit at all")
    assert_true(right > left, "the side nearer the bulb is not brighter")


def test_a_basic_material_ignores_the_lights() raises:
    # No lights at all: a Lambert surface renders black, a basic one renders
    # its own color, and that is the whole difference between the two.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var lambert = assets.materials.add(Material(Color(200, 100, 50)))
    var basic = assets.materials.add(Material(Color(200, 100, 50), kind=BASIC))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var lit = List[Mesh]()
    lit.append(Mesh(box, lambert, node))
    var unlit = List[Mesh]()
    unlit.append(Mesh(box, basic, node))
    var dark = rendered(renderer, scene, assets, lit, eye_camera())
    var plain = rendered(renderer, scene, assets, unlit, eye_camera())
    var center_dark = dark.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(center_dark.r, UInt8(0))
    var center_plain = plain.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(center_plain.r, UInt8(200))
    assert_equal(center_plain.g, UInt8(100))
    assert_equal(center_plain.b, UInt8(50))


# --- emissive ---------------------------------------------------------------


def count_bright(image: Framebuffer) raises -> Int:
    """Return how many pixels have a red channel above 200."""
    var bright = 0
    for y in range(image.height):
        for x in range(image.width):
            if image.get_pixel(x, y).r > 200:
                bright += 1
    return bright


def unlit_scene_with_a_node() raises -> Scene:
    """Return a scene with one node at the origin and no lights at all."""
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    return scene^


def test_an_emissive_material_shows_in_the_dark() raises:
    # No lights at all: a Lambert surface renders black, and the same
    # surface giving off light renders that light, as authored.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var dull = assets.materials.add(Material(Color(200, 100, 50)))
    var glowing = assets.materials.add(
        Material(Color(200, 100, 50), emissive=Color(60, 120, 180))
    )
    var scene = unlit_scene_with_a_node()
    var dark = List[Mesh]()
    dark.append(Mesh(box, dull, NodeId(0)))
    var lit = List[Mesh]()
    lit.append(Mesh(box, glowing, NodeId(0)))
    var black = rendered(renderer, scene, assets, dark, eye_camera())
    assert_equal(black.get_pixel(WIDTH // 2, HEIGHT // 2).r, UInt8(0))
    var shown = rendered(renderer, scene, assets, lit, eye_camera())
    var glow = shown.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(glow.r, UInt8(60))
    assert_equal(glow.g, UInt8(120))
    assert_equal(glow.b, UInt8(180))


def test_the_emissive_adds_to_the_lit_color() raises:
    # Under the suite's lights, a quarter of white in linear light lands on
    # top of whatever the lights left.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var plain = assets.materials.add(Material(Color(120, 120, 120)))
    var glowing = assets.materials.add(
        Material(
            Color(120, 120, 120),
            emissive=Color(255, 255, 255),
            emissive_intensity=0.25,
        )
    )
    var scene = scene_with_node_at(0)
    var without = List[Mesh]()
    without.append(Mesh(box, plain, NodeId(0)))
    var with_glow = List[Mesh]()
    with_glow.append(Mesh(box, glowing, NodeId(0)))
    var lit = rendered(renderer, scene, assets, without, a_camera())
    var brighter = rendered(renderer, scene, assets, with_glow, a_camera())
    var center = lit.get_pixel(WIDTH // 2, HEIGHT // 2)
    var glow = brighter.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_true(glow.r > center.r, "the glow added nothing")
    var expected = FloatColor(FloatColor(srgb=center).r + 0.25, 0, 0).encode()
    assert_true(abs(Int(glow.r) - Int(expected.r)) <= 2)


def test_emissive_intensity_scales_the_glow() raises:
    # No lights, a white glow at a quarter and at a half: each is that much
    # linear light, which the resolve encodes.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var quarter = assets.materials.add(
        Material(
            Color(0, 0, 0),
            emissive=Color(255, 255, 255),
            emissive_intensity=0.25,
        )
    )
    var half = assets.materials.add(
        Material(
            Color(0, 0, 0),
            emissive=Color(255, 255, 255),
            emissive_intensity=0.5,
        )
    )
    var scene = unlit_scene_with_a_node()
    var dim = List[Mesh]()
    dim.append(Mesh(box, quarter, NodeId(0)))
    var bright = List[Mesh]()
    bright.append(Mesh(box, half, NodeId(0)))
    var low = rendered(renderer, scene, assets, dim, eye_camera()).get_pixel(
        WIDTH // 2, HEIGHT // 2
    )
    var high = rendered(
        renderer, scene, assets, bright, eye_camera()
    ).get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(low.r, FloatColor(0.25, 0.25, 0.25).encode().r)
    assert_equal(high.r, FloatColor(0.5, 0.5, 0.5).encode().r)
    assert_true(high.r > low.r)


def test_an_emissive_map_glows_only_where_it_is_bright() raises:
    # No lights, a white glow through a white-and-black board: the box shows
    # the board where it is light and nothing where it is dark. A black glow
    # through the same board shows nothing at all, because the map
    # multiplies the color, as in three.js.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var board = assets.textures.add(
        checkerboard(8, 4, Color(255, 255, 255), Color(0, 0, 0), alpha=IGNORED)
    )
    var glowing = assets.materials.add(
        Material(
            Color(0, 0, 0), emissive=Color(255, 255, 255), emissive_map=board
        )
    )
    var whole = assets.materials.add(
        Material(Color(0, 0, 0), emissive=Color(255, 255, 255))
    )
    var unlit = assets.materials.add(
        Material(Color(0, 0, 0), emissive_map=board)
    )
    var scene = unlit_scene_with_a_node()
    var mapped = List[Mesh]()
    mapped.append(Mesh(box, glowing, NodeId(0)))
    var plain = List[Mesh]()
    plain.append(Mesh(box, whole, NodeId(0)))
    var black = List[Mesh]()
    black.append(Mesh(box, unlit, NodeId(0)))
    var through = count_bright(
        rendered(renderer, scene, assets, mapped, a_camera())
    )
    var solid = count_bright(
        rendered(renderer, scene, assets, plain, a_camera())
    )
    var nothing = count_bright(
        rendered(renderer, scene, assets, black, a_camera())
    )
    assert_true(through > 0, "the light squares did not glow")
    assert_true(through < solid, "the dark squares glowed")
    assert_equal(nothing, 0)


def test_lit_shading_ignores_the_emissive_map_but_keeps_the_glow() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_shading(SHADE_LIT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var board = assets.textures.add(
        checkerboard(8, 4, Color(255, 255, 255), Color(0, 0, 0), alpha=IGNORED)
    )
    var glowing = assets.materials.add(
        Material(
            Color(0, 0, 0), emissive=Color(255, 255, 255), emissive_map=board
        )
    )
    var whole = assets.materials.add(
        Material(Color(0, 0, 0), emissive=Color(255, 255, 255))
    )
    var scene = unlit_scene_with_a_node()
    var mapped = List[Mesh]()
    mapped.append(Mesh(box, glowing, NodeId(0)))
    var plain = List[Mesh]()
    plain.append(Mesh(box, whole, NodeId(0)))
    var through = rendered(renderer, scene, assets, mapped, a_camera())
    var solid = rendered(renderer, scene, assets, plain, a_camera())
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(through.get_pixel(x, y).r, solid.get_pixel(x, y).r)
    assert_equal(solid.get_pixel(WIDTH // 2, HEIGHT // 2).r, UInt8(255))


def test_a_material_naming_an_emissive_map_that_is_not_there_is_rejected() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var scene = scene_with_node_at(0)
    var lost = assets.materials.add(
        Material(
            Color(0, 0, 0),
            emissive=Color(255, 255, 255),
            emissive_map=TextureId(5),
        )
    )
    var meshes = List[Mesh]()
    meshes.append(Mesh(box, lost, NodeId(0)))
    with assert_raises():
        _ = rendered(renderer, scene, assets, meshes, a_camera())
    # A wrong id is a mistake whatever the color: a black glow, which would
    # never sample the map, does not excuse it.
    var dark = assets.materials.add(
        Material(Color(0, 0, 0), emissive_map=TextureId(5))
    )
    var unlit = List[Mesh]()
    unlit.append(Mesh(box, dark, NodeId(0)))
    with assert_raises():
        _ = rendered(renderer, scene, assets, unlit, a_camera())


def test_an_emissive_map_must_ignore_its_alpha() raises:
    # A map that reads alpha as coverage would darken the glow wherever its
    # alpha is low, so it is refused whatever the shading mode; the same
    # image built to ignore its alpha is accepted.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var coverage = assets.textures.add(
        checkerboard(8, 4, Color(255, 255, 255), Color(0, 0, 0))
    )
    var ignored = assets.textures.add(
        checkerboard(8, 4, Color(255, 255, 255), Color(0, 0, 0), alpha=IGNORED)
    )
    var scene = unlit_scene_with_a_node()
    var wrong = List[Mesh]()
    wrong.append(
        Mesh(
            box,
            assets.materials.add(
                Material(
                    Color(0, 0, 0),
                    emissive=Color(255, 255, 255),
                    emissive_map=coverage,
                )
            ),
            NodeId(0),
        )
    )
    with assert_raises():
        _ = rendered(renderer, scene, assets, wrong, a_camera())
    renderer.set_shading(SHADE_LIT)
    with assert_raises():
        _ = rendered(renderer, scene, assets, wrong, a_camera())
    renderer.set_shading(SHADE_TEXTURE)
    var right = List[Mesh]()
    right.append(
        Mesh(
            box,
            assets.materials.add(
                Material(
                    Color(0, 0, 0),
                    emissive=Color(255, 255, 255),
                    emissive_map=ignored,
                )
            ),
            NodeId(0),
        )
    )
    _ = rendered(renderer, scene, assets, right, a_camera())


def test_an_emissive_maps_alpha_does_not_darken_or_thin_the_glow() raises:
    # A one-texel white map with alpha zero, under either filter: white
    # emission, and the surface's own alpha untouched.
    for filter in [NEAREST, BILINEAR]:
        var renderer = Renderer(WIDTH, HEIGHT)
        var assets = Assets()
        var box = assets.geometries.add(cube(Length(1.0, METER)))
        var pixels = List[UInt8]()
        for value in [UInt8(255), UInt8(255), UInt8(255), UInt8(0)]:
            pixels.append(value)
        var map = assets.textures.add(
            Texture(1, 1, pixels^, filter=filter, alpha=IGNORED)
        )
        var glowing = assets.materials.add(
            Material(
                Color(0, 0, 0), emissive=Color(255, 255, 255), emissive_map=map
            )
        )
        var scene = unlit_scene_with_a_node()
        var meshes = List[Mesh]()
        meshes.append(Mesh(box, glowing, NodeId(0)))
        var shown = rendered(
            renderer, scene, assets, meshes, eye_camera()
        ).get_pixel(WIDTH // 2, HEIGHT // 2)
        assert_equal(shown.r, UInt8(255))
        assert_equal(shown.g, UInt8(255))
        assert_equal(shown.b, UInt8(255))
        assert_equal(shown.a, UInt8(255))


def test_a_camera_draws_only_the_meshes_on_its_layers() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var paint = assets.materials.add(Material(Color(220, 160, 80)))
    var scene = scene_with_node_at(0)
    var meshes = List[Mesh]()
    meshes.append(Mesh(box, paint, NodeId(0)))
    var camera = a_camera()
    var seen = rendered(renderer, scene, assets, meshes, camera)
    var untouched = count_background(seen, renderer.background)
    assert_true(untouched < WIDTH * HEIGHT, "the box did not show")
    # Moved to layer one, the mesh is not drawn by a camera on layer zero.
    scene.node(NodeId(0)).layers.set(1)
    scene.update()
    var hidden = rendered(renderer, scene, assets, meshes, camera)
    assert_equal(count_background(hidden, renderer.background), WIDTH * HEIGHT)
    # Until the camera watches layer one as well.
    camera.layers.enable(1)
    var shown = rendered(renderer, scene, assets, meshes, camera)
    assert_equal(count_background(shown, renderer.background), untouched)
    # A camera watching no layer draws nothing.
    camera.layers.disable_all()
    var nothing = rendered(renderer, scene, assets, meshes, camera)
    assert_equal(count_background(nothing, renderer.background), WIDTH * HEIGHT)


def test_a_camera_lights_only_with_the_lights_on_its_layers() raises:
    # A box lit by a sun straight ahead of it. Moving the sun to a layer the
    # camera does not watch leaves the box black -- the mesh is drawn, the
    # light is not -- until the camera watches that layer too. A bulb and
    # an ambient light on further layers are likewise unseen until asked
    # for, and each brightens the box when they are.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var paint = assets.materials.add(Material(Color(220, 160, 80)))
    var scene = unlit_scene_with_a_node()
    var lamp = Object3D()
    lamp.set_position(0, 0, 5)
    var lamp_node = scene.add(lamp^)
    scene.update()
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, FULL))
    var meshes = List[Mesh]()
    meshes.append(Mesh(box, paint, NodeId(0)))
    var camera = a_camera()
    var lit = rendered(renderer, scene, assets, meshes, camera).get_pixel(
        WIDTH // 2, HEIGHT // 2
    )
    assert_equal(lit.r, UInt8(220))
    # The sun moves to layer one: drawn, but in the dark.
    scene.lights[0].layers.set(1)
    var dark = rendered(renderer, scene, assets, meshes, camera).get_pixel(
        WIDTH // 2, HEIGHT // 2
    )
    assert_equal(dark.r, UInt8(0))
    assert_equal(dark.g, UInt8(0))
    assert_equal(dark.b, UInt8(0))
    camera.layers.enable(1)
    var seen = rendered(renderer, scene, assets, meshes, camera).get_pixel(
        WIDTH // 2, HEIGHT // 2
    )
    assert_equal(seen.r, lit.r)
    # A bulb on layer two, behind the camera's side of the box.
    var bulb = point_light(Color(255, 255, 255), lamp_node, 4.0)
    bulb.layers.set(2)
    scene.add_light(bulb)
    var without_bulb = rendered(
        renderer, scene, assets, meshes, camera
    ).get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(without_bulb.r, lit.r)
    camera.layers.enable(2)
    var with_bulb = rendered(renderer, scene, assets, meshes, camera).get_pixel(
        WIDTH // 2, HEIGHT // 2
    )
    assert_true(with_bulb.r > lit.r, "the bulb did not add light")
    # An ambient light on layer three, with no node at all.
    var fill = ambient_light(Color(255, 255, 255), 0.5)
    fill.layers.set(3)
    scene.add_light(fill)
    var without_fill = rendered(
        renderer, scene, assets, meshes, camera
    ).get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(without_fill.r, with_bulb.r)
    camera.layers.enable(3)
    var with_fill = rendered(renderer, scene, assets, meshes, camera).get_pixel(
        WIDTH // 2, HEIGHT // 2
    )
    assert_true(with_fill.b > with_bulb.b, "the ambient did not add light")


def test_a_child_on_the_cameras_layer_is_drawn_under_a_parent_that_is_not() raises:
    # Layers are each node's own, as in three.js: a parent moved off the
    # camera's layers hides nothing below it, and its child, still on layer
    # zero, is drawn where the parent carried it.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var paint = assets.materials.add(Material(Color(220, 160, 80)))
    var scene = Scene()
    var parent = Object3D()
    parent.layers.set(1)
    var parent_node = scene.add(parent^)
    var child_node = scene.attach(Object3D(), parent_node)
    light_the(scene)
    scene.update()
    var on_child = List[Mesh]()
    on_child.append(Mesh(box, paint, child_node))
    var drawn = rendered(renderer, scene, assets, on_child, a_camera())
    assert_true(
        count_background(drawn, renderer.background) < WIDTH * HEIGHT,
        "the child was not drawn",
    )
    # The same box on the parent itself is not.
    var on_parent = List[Mesh]()
    on_parent.append(Mesh(box, paint, parent_node))
    var hidden = rendered(renderer, scene, assets, on_parent, a_camera())
    assert_equal(count_background(hidden, renderer.background), WIDTH * HEIGHT)


def test_a_texture_sits_the_same_way_up_on_a_sphere_and_a_polyhedron() raises:
    # A texture white on top and black underneath, on a sphere and on an
    # octahedron cut toward a sphere: both show white above the middle and
    # black below, so v runs the same way up on every builder.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var pixels: List[UInt8] = [255, 255, 255, 255, 0, 0, 0, 255]
    var halves = assets.textures.add(Texture(1, 2, pixels^, CLAMP, NEAREST))
    var skin = assets.materials.add(
        Material(Color(255, 255, 255), halves, kind=BASIC)
    )
    var ball = assets.geometries.add(sphere(Length(1.0, METER), 24, 16))
    var gem = assets.geometries.add(octahedron(Length(1.0, METER), 3))
    var scene = unlit_scene_with_a_node()
    for shape in [ball, gem]:
        var meshes = List[Mesh]()
        meshes.append(Mesh(shape, skin, NodeId(0)))
        var image = rendered(renderer, scene, assets, meshes, a_camera())
        var above = image.get_pixel(WIDTH // 2, HEIGHT // 2 - 3)
        var below = image.get_pixel(WIDTH // 2, HEIGHT // 2 + 3)
        assert_true(above.r > 200, "the top of the image did not show")
        assert_true(below.r < 50, "the bottom of the image did not show")


def test_a_blank_emissive_map_is_accepted_and_changes_nothing() raises:
    # A stored blank texture, copied through ignoring_alpha, is a real id
    # that the check accepts and that samples as white: the glow shows as
    # if there were no map at all.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var blank = assets.textures.add(Texture().ignoring_alpha())
    var mapped = assets.materials.add(
        Material(
            Color(0, 0, 0), emissive=Color(60, 120, 180), emissive_map=blank
        )
    )
    var plain = assets.materials.add(
        Material(Color(0, 0, 0), emissive=Color(60, 120, 180))
    )
    var scene = unlit_scene_with_a_node()
    var through = List[Mesh]()
    through.append(Mesh(box, mapped, NodeId(0)))
    var bare = List[Mesh]()
    bare.append(Mesh(box, plain, NodeId(0)))
    var with_blank = rendered(renderer, scene, assets, through, eye_camera())
    var without = rendered(renderer, scene, assets, bare, eye_camera())
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(
                with_blank.get_pixel(x, y).r, without.get_pixel(x, y).r
            )
            assert_equal(
                with_blank.get_pixel(x, y).b, without.get_pixel(x, y).b
            )
    assert_equal(with_blank.get_pixel(WIDTH // 2, HEIGHT // 2).g, UInt8(120))


def test_emission_survives_clipping_and_the_back_side() raises:
    # The camera sits inside a large cube and sees its inside, which is its
    # back side, with no lights: every covered pixel is the glow, clipped at
    # the near plane. Translucent, the glow is blended over the background
    # at the material's opacity; opaque, it is the glow alone.
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(8.0, METER)))
    var glass = assets.materials.add(
        Material(
            Color(0, 0, 0),
            NO_TEXTURE,
            BACK_SIDE,
            0.5,
            emissive=Color(255, 255, 255),
            transparent=True,
        )
    )
    var solid = assets.materials.add(
        Material(
            Color(0, 0, 0),
            NO_TEXTURE,
            BACK_SIDE,
            1.0,
            emissive=Color(255, 255, 255),
        )
    )
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = unlit_scene_with_a_node()
    var through = List[Mesh]()
    through.append(Mesh(box, glass, NodeId(0)))
    var whole = List[Mesh]()
    whole.append(Mesh(box, solid, NodeId(0)))
    var blended = rendered(renderer, scene, assets, through, a_camera())
    var plain = rendered(renderer, scene, assets, whole, a_camera())
    # Half the glow over half the background, in linear light.
    var behind = FloatColor(srgb=renderer.background)
    var half = FloatColor(0.5 + behind.r * 0.5, 0, 0).encode().r
    var covered = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var full = plain.get_pixel(x, y)
            if full.r == renderer.background.r:
                continue
            covered += 1
            assert_equal(full.r, UInt8(255))
            assert_equal(full.a, UInt8(255))
            var seen = blended.get_pixel(x, y)
            assert_true(abs(Int(seen.r) - Int(half)) <= 1)
            assert_equal(seen.a, UInt8(255))
    assert_true(covered > 300, "the cube's inside did not fill the view")


def test_an_unknown_shading_mode_is_refused_by_the_renderer() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    with assert_raises():
        renderer.set_shading(ShadeMode(99))
    renderer.set_shading(SHADE_LIT)


# --- frustum culling --------------------------------------------------------
#
# `a_camera` looks at the origin from four meters up z with a 45-degree
# field of view, so at the origin's depth it sees 1.66 meters up and down
# and 2.21 to either side. A cube of 1.5 meters has a bounding sphere of
# radius 1.3, and the right plane is tilted, so five meters to the right
# is out of view with room to spare and two and a half straddles the edge.


def scene_with_node_placed(
    x: Float32, y: Float32, z: Float32, scale: Float32
) raises -> Scene:
    """Return a lit scene holding one node at a point, scaled uniformly.

    Args:
        x: Where along x.
        y: Where along y.
        z: Where along z.
        scale: The node's scale on every axis.

    Returns:
        The updated scene, its node at `NodeId(0)`.

    Raises:
        Error: If the scene is invalid.
    """
    var scene = Scene()
    var node = Object3D()
    node.set_position(x, y, z)
    node.set_scale(scale, scale, scale)
    _ = scene.add(node^)
    light_the(scene)
    scene.update()
    return scene^


def test_a_mesh_is_frustum_culled_unless_told_otherwise() raises:
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(1, 2, 3)))
    assert_true(Mesh(box, paint, NodeId(0)).frustum_culled)
    assert_false(
        Mesh(box, paint, NodeId(0), frustum_culled=False).frustum_culled
    )


def test_a_mesh_outside_the_view_is_not_prepared() raises:
    # Five meters to the right: every triangle lies past the side planes,
    # so the mesh draws the same nothing with the test and without. With
    # the test it is left out before a vertex is transformed; without it,
    # every triangle is transformed and then cut away whole by the
    # clipper. The output is the same, which is what makes the test a
    # shortcut rather than a rule.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var paint = assets.materials.add(Material(Color(220, 160, 80)))
    var camera = a_camera()
    var scene = scene_with_node_placed(5, 0, 0, 1)
    var culled = List[Mesh]()
    culled.append(Mesh(box, paint, NodeId(0)))
    var kept = List[Mesh]()
    kept.append(Mesh(box, paint, NodeId(0), frustum_culled=False))
    assert_equal(len(prepared(renderer, scene, assets, culled, camera)), 0)
    assert_equal(len(prepared(renderer, scene, assets, kept, camera)), 0)
    assert_equal(
        count_background(
            rendered(renderer, scene, assets, culled, camera),
            renderer.background,
        ),
        WIDTH * HEIGHT,
    )
    assert_equal(
        count_background(
            rendered(renderer, scene, assets, kept, camera),
            renderer.background,
        ),
        WIDTH * HEIGHT,
    )
    # Beyond the far plane, and behind the camera: out on the other axes.
    var beyond = scene_with_node_placed(0, 0, -200, 1)
    assert_equal(len(prepared(renderer, beyond, assets, culled, camera)), 0)
    var behind = scene_with_node_placed(0, 0, 10, 1)
    assert_equal(len(prepared(renderer, behind, assets, culled, camera)), 0)
    var above = scene_with_node_placed(0, 5, 0, 1)
    assert_equal(len(prepared(renderer, above, assets, culled, camera)), 0)


def assert_same_image(tested: Framebuffer, untested: Framebuffer) raises:
    """Assert two images agree in every channel and every depth.

    Args:
        tested: The image with frustum culling on.
        untested: The image with it off.

    Raises:
        Error: If any pixel or depth differs.
    """
    for y in range(tested.height):
        for x in range(tested.width):
            var a = tested.get_pixel(x, y)
            var b = untested.get_pixel(x, y)
            assert_equal(a.r, b.r)
            assert_equal(a.g, b.g)
            assert_equal(a.b, b.b)
            assert_equal(a.a, b.a)
            assert_equal(tested.depth_at(x, y), untested.depth_at(x, y))


def test_a_mesh_near_the_far_plane_is_drawn_with_the_test_and_without() raises:
    # A long lens: one degree of view, a near plane at a tenth of a meter
    # and a far one at five kilometers. Read back off the Float32
    # projection the far plane would sit seven meters short, and a sheet
    # a meter and a half inside the far distance would be culled while
    # the clipper draws it. The two images must agree pixel for pixel and
    # depth for depth, with the camera at the origin and moved, and with
    # the sheet touching the far plane and the near one.
    var renderer = Renderer(64, 64)
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(6.0, METER), Length(6.0, METER))
    )
    var speck = assets.geometries.add(
        plane(Length(0.001, METER), Length(0.001, METER))
    )
    var paint = assets.materials.add(Material(Color(220, 160, 80), kind=BASIC))
    var camera = PerspectiveCamera(
        Angle(1.0, DEGREE),
        1.0,
        Length(0.1, METER),
        Length(5000.0, METER),
    )
    camera.place(Vector3(0, 0, 0), Vector3(0, 0, -1))
    var culled = List[Mesh]()
    culled.append(Mesh(sheet, paint, NodeId(0)))
    var kept = List[Mesh]()
    kept.append(Mesh(sheet, paint, NodeId(0), frustum_culled=False))
    var inside = scene_with_node_placed(0, 0, -4998.5, 1)
    var tested = rendered(renderer, inside, assets, culled, camera)
    assert_true(
        count_background(tested, renderer.background) < 64 * 64,
        "the sheet near the far plane was culled",
    )
    assert_same_image(tested, rendered(renderer, inside, assets, kept, camera))
    # Touching the far plane exactly: the clipper keeps what lies on it.
    var touching = scene_with_node_placed(0, 0, -5000, 1)
    assert_same_image(
        rendered(renderer, touching, assets, culled, camera),
        rendered(renderer, touching, assets, kept, camera),
    )
    # The camera moved four meters up z: the same sheet, the same depth.
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var moved = scene_with_node_placed(0, 0, 4 - 4998.5, 1)
    var followed = rendered(renderer, moved, assets, culled, camera)
    assert_true(
        count_background(followed, renderer.background) < 64 * 64,
        "the sheet was culled after the camera moved",
    )
    assert_same_image(followed, rendered(renderer, moved, assets, kept, camera))
    # A speck a tenth of a millimeter inside the near plane, where the view
    # is two millimeters tall, drawn either way. Not on the plane itself:
    # the clipper's rounding of a vertex exactly on it goes either way,
    # with the test and without alike.
    var near_culled = List[Mesh]()
    near_culled.append(Mesh(speck, paint, NodeId(0)))
    var near_kept = List[Mesh]()
    near_kept.append(Mesh(speck, paint, NodeId(0), frustum_culled=False))
    var grazing = scene_with_node_placed(0, 0, 4 - 0.1001, 1)
    var close = rendered(renderer, grazing, assets, near_culled, camera)
    assert_true(
        count_background(close, renderer.background) < 64 * 64,
        "the speck at the near plane was culled",
    )
    assert_same_image(
        close, rendered(renderer, grazing, assets, near_kept, camera)
    )


def test_an_attached_camera_culls_by_its_nodes_view() raises:
    # The same long lens riding a node under a turned, moved pivot. Its
    # view is the exact inverse of a rotation and a translation, with the
    # bottom row the frustum asks for, and the sheet a meter and a half
    # inside the far plane is drawn with the test and without.
    var renderer = Renderer(64, 64)
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(6.0, METER), Length(6.0, METER))
    )
    var paint = assets.materials.add(Material(Color(220, 160, 80), kind=BASIC))
    var scene = Scene()
    var pivot = Object3D()
    pivot.set_position(1, 2, 3)
    pivot.set_euler(Angle(0.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE))
    var pivot_node = scene.add(pivot^)
    var eye = Object3D()
    eye.set_position(0, 0, 4)
    var eye_node = scene.attach(eye^, pivot_node)
    # The pivot's quarter turn about y takes the eye's -z to world -x, so
    # the sheet stands 4998.5 meters down -x from the eye, facing it.
    var target = Object3D()
    target.set_position(4 - 4998.5 + 1, 2, 3)
    target.set_euler(
        Angle(0.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE)
    )
    var target_node = scene.add(target^)
    light_the(scene)
    scene.update()
    var camera = PerspectiveCamera(
        Angle(1.0, DEGREE),
        1.0,
        Length(0.1, METER),
        Length(5000.0, METER),
    )
    camera.attach(eye_node)
    assert_true(camera.view_matrix_in(scene).is_affine())
    var culled = List[Mesh]()
    culled.append(Mesh(sheet, paint, target_node))
    var kept = List[Mesh]()
    kept.append(Mesh(sheet, paint, target_node, frustum_culled=False))
    var tested = rendered(renderer, scene, assets, culled, camera)
    assert_true(
        count_background(tested, renderer.background) < 64 * 64,
        "the sheet was culled through the attached camera",
    )
    assert_same_image(tested, rendered(renderer, scene, assets, kept, camera))


def test_a_mesh_partly_in_view_is_prepared_whole() raises:
    # Straddling the right edge: the bound crosses the plane, so the mesh
    # is prepared as if there were no test, every triangle of it.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var paint = assets.materials.add(Material(Color(220, 160, 80)))
    var camera = a_camera()
    var scene = scene_with_node_placed(2, 0, 0, 1)
    var culled = List[Mesh]()
    culled.append(Mesh(box, paint, NodeId(0)))
    var kept = List[Mesh]()
    kept.append(Mesh(box, paint, NodeId(0), frustum_culled=False))
    var tested = len(prepared(renderer, scene, assets, culled, camera))
    assert_true(tested > 0, "the straddling cube was culled")
    assert_equal(tested, len(prepared(renderer, scene, assets, kept, camera)))
    var image = rendered(renderer, scene, assets, culled, camera)
    assert_true(
        count_background(image, renderer.background) < WIDTH * HEIGHT,
        "the straddling cube did not show",
    )


def test_a_scaled_mesh_is_culled_by_its_world_bound() raises:
    # The same cube at the same place, out of view at its own size and
    # reaching the axis at three times it: the bound is carried through
    # the node's world matrix, scale and all.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var paint = assets.materials.add(Material(Color(220, 160, 80)))
    var camera = a_camera()
    var meshes = List[Mesh]()
    meshes.append(Mesh(box, paint, NodeId(0)))
    var small = scene_with_node_placed(5, 0, 0, 1)
    assert_equal(len(prepared(renderer, small, assets, meshes, camera)), 0)
    var large = scene_with_node_placed(5, 0, 0, 3)
    assert_true(len(prepared(renderer, large, assets, meshes, camera)) > 0)
    var image = rendered(renderer, large, assets, meshes, camera)
    assert_true(
        count_background(image, renderer.background) < WIDTH * HEIGHT,
        "the scaled cube did not show",
    )


def test_culling_leaves_the_image_unchanged() raises:
    # Cubes all around the view -- in it, straddling it, past each side,
    # and far down the axis -- drawn with the test and without. The images
    # must agree pixel for pixel, and so must the triangles prepared: the
    # test leaves a cube out whole, and the clipper cuts the same cube
    # away whole, so neither can hand the rasterizer a triangle the other
    # does not.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var paint = assets.materials.add(Material(Color(220, 160, 80)))
    var glass = assets.materials.add(
        Material(
            Color(80, 160, 220), NO_TEXTURE, FRONT_SIDE, 0.5, transparent=True
        )
    )
    var camera = a_camera()
    var scene = Scene()
    var places = List[Vector3]()
    places.append(Vector3(0, 0, 0))
    places.append(Vector3(2.5, 0, 0))
    places.append(Vector3(5, 0, 0))
    places.append(Vector3(-5, 0, 0))
    places.append(Vector3(0, 5, 0))
    places.append(Vector3(0, -5, 0))
    places.append(Vector3(0, 0, -20))
    places.append(Vector3(0, 0, -200))
    for index in range(len(places)):
        var node = Object3D()
        node.set_position(places[index].x, places[index].y, places[index].z)
        _ = scene.add(node^)
    light_the(scene)
    scene.update()
    var culled = List[Mesh]()
    var kept = List[Mesh]()
    for index in range(len(places)):
        var material = paint
        if index % 2 == 1:
            material = glass
        culled.append(Mesh(box, material, NodeId(index)))
        kept.append(Mesh(box, material, NodeId(index), frustum_culled=False))
    var fewer = len(prepared(renderer, scene, assets, culled, camera))
    var every = len(prepared(renderer, scene, assets, kept, camera))
    assert_true(fewer > 0, "everything was culled")
    assert_equal(fewer, every)
    var tested = rendered(renderer, scene, assets, culled, camera)
    var untested = rendered(renderer, scene, assets, kept, camera)
    var drawn = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var a = tested.get_pixel(x, y)
            var b = untested.get_pixel(x, y)
            assert_equal(a.r, b.r)
            assert_equal(a.g, b.g)
            assert_equal(a.b, b.b)
            assert_equal(a.a, b.a)
            if a.r != renderer.background.r:
                drawn += 1
    assert_true(drawn > 0, "nothing was drawn, so nothing was compared")


def test_an_orthographic_camera_culls_by_its_box() raises:
    # A parallel view six meters tall and eight wide: a cube ten meters to
    # the right is out of it at any depth, and one on the axis is in it.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var paint = assets.materials.add(Material(Color(220, 160, 80)))
    var camera = centered(
        Length(6.0, METER),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var meshes = List[Mesh]()
    meshes.append(Mesh(box, paint, NodeId(0)))
    var aside = scene_with_node_placed(10, 0, 0, 1)
    assert_equal(len(prepared(renderer, aside, assets, meshes, camera)), 0)
    var ahead = scene_with_node_placed(0, 0, 0, 1)
    assert_true(len(prepared(renderer, ahead, assets, meshes, camera)) > 0)


# --- vertex colors ----------------------------------------------------------


def split_plane(channels: Int, alpha: Float32) raises -> BufferGeometry:
    """Return a plane that fills the view, red on its left and green on its
    right, as a `color` attribute.

    Six meters square in three columns, so that the outer columns are one
    color each and only the middle one ramps between them: from `a_camera`
    the left quarter of the image is pure red and the right quarter pure
    green. The colors are chosen by each vertex's own x rather than by its
    slot, so the test does not depend on the builder's vertex order.

    Args:
        channels: Three floats per color, or four with `alpha` as the
            fourth.
        alpha: The fourth float, when there is one.

    Returns:
        The geometry, six meters square at the origin.

    Raises:
        Error: If the geometry cannot be built.
    """
    var sheet = plane(Length(6.0, METER), Length(6.0, METER), 3, 1)
    var tints = List[Float32]()
    ref positions = sheet.attribute_view(String(POSITION))
    for vertex in range(positions.count()):
        var leftward = positions.vector3(vertex).x < 0
        tints.append(Float32(1) if leftward else Float32(0))
        tints.append(Float32(0) if leftward else Float32(1))
        tints.append(0)
        if channels == 4:
            tints.append(alpha)
    sheet.set_attribute(String(COLOR), BufferAttribute(tints^, channels))
    return sheet^


def test_vertex_colors_multiply_the_material_color() raises:
    # A white unlit sheet, red on the left and green on the right by its
    # vertices: the left of the image is red and the right is green, and
    # the same sheet under a material that does not ask is white all over.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var sheet = assets.geometries.add(split_plane(3, 1))
    var tinted = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, vertex_colors=True)
    )
    var plain = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    var scene = scene_with_node_at(0)
    var colored = List[Mesh]()
    colored.append(Mesh(sheet, tinted, NodeId(0)))
    var image = rendered(renderer, scene, assets, colored, a_camera())
    var left = image.get_pixel(WIDTH // 8, HEIGHT // 2)
    var right = image.get_pixel(WIDTH - WIDTH // 8, HEIGHT // 2)
    assert_true(left.r > 200 and left.g < 60, "the left is not red")
    assert_true(right.g > 200 and right.r < 60, "the right is not green")
    # Between the two the color is interpolated: both channels present.
    var middle = image.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_true(middle.r > 60 and middle.g > 60, "the middle is not mixed")
    var uncolored = List[Mesh]()
    uncolored.append(Mesh(sheet, plain, NodeId(0)))
    var white = rendered(renderer, scene, assets, uncolored, a_camera())
    for x in [WIDTH // 8, WIDTH // 2, WIDTH - WIDTH // 8]:
        var pixel = white.get_pixel(x, HEIGHT // 2)
        assert_equal(pixel.r, UInt8(255))
        assert_equal(pixel.g, UInt8(255))
        assert_equal(pixel.b, UInt8(255))


def test_vertex_colors_multiply_a_nonwhite_material() raises:
    # The material's color decoded from sRGB, times its opacity in alpha,
    # times the vertex's own color: worked out by hand rather than asked of
    # the renderer. Orange (255, 128, 0) at 0.8 decodes to (1, 0.21586, 0,
    # 0.8); a vertex color of (0.5, 0.25, 1, 0.5) leaves (0.5, 0.05397, 0,
    # 0.4) on every corner.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var sheet = plane(Length(1.0, METER), Length(1.0, METER))
    var tints = List[Float32]()
    for _ in range(sheet.vertex_count()):
        for value in [0.5, 0.25, 1.0, 0.5]:
            tints.append(Float32(value))
    sheet.set_attribute(String(COLOR), BufferAttribute(tints^, 4))
    var tinted = assets.geometries.add(sheet^)
    var orange = assets.materials.add(
        Material(
            Color(255, 128, 0),
            opacity=0.8,
            kind=BASIC,
            vertex_colors=True,
            transparent=True,
        )
    )
    var scene = scene_with_node_at(0)
    var meshes = List[Mesh]()
    meshes.append(Mesh(tinted, orange, NodeId(0)))
    var corners = prepared(renderer, scene, assets, meshes, a_camera())
    assert_equal(len(corners), 6)
    for index in range(len(corners)):
        assert_almost_equal(corners[index].color.r, Float32(0.5), atol=1e-4)
        assert_almost_equal(corners[index].color.g, Float32(0.05397), atol=1e-4)
        assert_almost_equal(corners[index].color.b, Float32(0), atol=1e-4)
        assert_almost_equal(corners[index].color.a, Float32(0.4), atol=1e-4)


def assert_some_corner_carries(
    corners: List[RasterVertex], r: Float32, g: Float32, b: Float32, a: Float32
) raises:
    """Assert that at least one prepared corner carries the given color.

    Args:
        corners: The prepared list.
        r: Expected red.
        g: Expected green.
        b: Expected blue.
        a: Expected alpha.

    Raises:
        Error: If no corner matches within a tolerance.
    """
    for index in range(len(corners)):
        var color = corners[index].color
        if (
            abs(color.r - r) < 1e-4
            and abs(color.g - g) < 1e-4
            and abs(color.b - b) < 1e-4
            and abs(color.a - a) < 1e-4
        ):
            return
    raise Error("No corner carries that color")


def test_varying_vertex_colors_survive_the_near_plane() raises:
    # One triangle with a different color and alpha at each corner, one
    # corner behind the near plane: the two cut corners carry the colors
    # mixed four sevenths of the way along the cut edges, exactly as the
    # positions are, and the corners at two depths carry two values of
    # 1 / w. The default camera sits at the origin looking down -z with
    # the near plane one meter out.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var triangle = BufferGeometry()
    var positions = List[Float32]()
    for value in [-1.0, -1.0, -3.0, 1.0, -1.0, -3.0, 0.0, 1.0, 0.5]:
        positions.append(Float32(value))
    triangle.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    var tints = List[Float32]()
    for value in [1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.5, 0.0, 0.0, 1.0, 0.25]:
        tints.append(Float32(value))
    triangle.set_attribute(String(COLOR), BufferAttribute(tints^, 4))
    var shape = assets.geometries.add(triangle^)
    var white = assets.materials.add(
        Material(
            Color(255, 255, 255),
            NO_TEXTURE,
            DOUBLE_SIDE,
            kind=BASIC,
            vertex_colors=True,
        )
    )
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(1.0, METER),
        Length(10.0, METER),
    )
    var scene = scene_with_node_at(0)
    var meshes = List[Mesh]()
    meshes.append(Mesh(shape, white, NodeId(0)))
    var corners = prepared(renderer, scene, assets, meshes, camera)
    # A triangle with one corner cut off is a quad: two triangles.
    assert_equal(len(corners), 6)
    # The uncut corners, as given.
    assert_some_corner_carries(corners, 1, 0, 0, 1)
    assert_some_corner_carries(corners, 0, 1, 0, 0.5)
    # The cuts, at t = (-3 + 1) / (-3 - 0.5) = 4 / 7 from the near corner
    # to the far one.
    var t = Float32(4) / 7
    assert_some_corner_carries(corners, 1 - t, 0, t, 1 - 0.75 * t)
    assert_some_corner_carries(corners, 0, 1 - t, t, 0.5 - 0.25 * t)
    # Nothing else: every corner is one of those four.
    for index in range(len(corners)):
        var color = corners[index].color
        assert_true(
            color.b < 1e-4 or abs(color.b - t) < 1e-4,
            "a corner carries a color that was never given or cut",
        )
    # Two depths, three meters and one, so two values of 1 / w.
    var deep = 0
    var shallow = 0
    for index in range(len(corners)):
        if abs(corners[index].inv_w - 1.0 / 3) < 1e-4:
            deep += 1
        if abs(corners[index].inv_w - 1) < 1e-4:
            shallow += 1
    assert_true(deep > 0 and shallow > 0, "the corners are not at two depths")
    assert_equal(deep + shallow, 6)


def test_a_vertex_alpha_blends_only_when_the_material_does() raises:
    # A fourth float halves the alpha. Over a blended material the sheet
    # shows half the background through, and writes no depth. An opaque
    # material does not blend with what is behind: its fragment replaces
    # the pixel, alpha and all, and claims the depth. So the opaque sheet
    # is full red with an alpha of a half, not an opaque red.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var sheet = assets.geometries.add(split_plane(4, 0.5))
    var scene = scene_with_node_at(0)
    var glass = assets.materials.add(
        Material(
            Color(255, 255, 255),
            kind=BASIC,
            blending=BLEND,
            vertex_colors=True,
        )
    )
    var seen_through = List[Mesh]()
    seen_through.append(Mesh(sheet, glass, NodeId(0)))
    var blended = rendered(renderer, scene, assets, seen_through, a_camera())
    var left = blended.get_pixel(WIDTH // 8, HEIGHT // 2)
    # Half of linear red over black encodes to 188, not 128.
    assert_true(left.r > 180 and left.r < 196, "the alpha did not blend")
    assert_equal(left.g, UInt8(0))
    # Over an opaque background the result is opaque, and a blended
    # fragment leaves the depth as it found it.
    assert_equal(left.a, UInt8(255))
    assert_equal(
        blended.depth_at(WIDTH // 8, HEIGHT // 2), inf[DType.float32]()
    )
    var solid = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, vertex_colors=True)
    )
    var opaque = List[Mesh]()
    opaque.append(Mesh(sheet, solid, NodeId(0)))
    var covered = rendered(renderer, scene, assets, opaque, a_camera())
    var written = covered.get_pixel(WIDTH // 8, HEIGHT // 2)
    assert_equal(written.r, UInt8(255))
    assert_equal(written.g, UInt8(0))
    # Opaque, so written with an alpha of one whatever the vertex said.
    assert_equal(written.a, UInt8(255))
    assert_true(
        covered.depth_at(WIDTH // 8, HEIGHT // 2) < inf[DType.float32](),
        "an opaque fragment did not claim the depth",
    )


def test_vertex_colors_need_a_color_attribute_of_the_right_shape() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var tinted = assets.materials.add(
        Material(Color(255, 255, 255), vertex_colors=True)
    )
    var scene = scene_with_node_at(0)
    # No color attribute at all.
    var bare = assets.geometries.add(cube(Length(1.0, METER)))
    var without = List[Mesh]()
    without.append(Mesh(bare, tinted, NodeId(0)))
    with assert_raises():
        _ = rendered(renderer, scene, assets, without, a_camera())
    # Two floats per vertex is neither three nor four.
    var flat = plane(Length(1.0, METER), Length(1.0, METER))
    var pairs = List[Float32](length=flat.vertex_count() * 2, fill=1.0)
    flat.set_attribute(String(COLOR), BufferAttribute(pairs^, 2))
    var narrow = List[Mesh]()
    narrow.append(Mesh(assets.geometries.add(flat^), tinted, NodeId(0)))
    with assert_raises():
        _ = rendered(renderer, scene, assets, narrow, a_camera())
    # Three floats per vertex, but for one vertex fewer than there are.
    var short = plane(Length(1.0, METER), Length(1.0, METER))
    var few = List[Float32](length=(short.vertex_count() - 1) * 3, fill=1.0)
    short.set_attribute(String(COLOR), BufferAttribute(few^, 3))
    var missing = List[Mesh]()
    missing.append(Mesh(assets.geometries.add(short^), tinted, NodeId(0)))
    with assert_raises():
        _ = rendered(renderer, scene, assets, missing, a_camera())
    # A geometry with no vertices and no colors is not wrong, only empty.
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    empty.set_attribute(String(COLOR), BufferAttribute(List[Float32](), 3))
    var nothing = List[Mesh]()
    nothing.append(
        Mesh(
            assets.geometries.add(empty^),
            tinted,
            NodeId(0),
            frustum_culled=False,
        )
    )
    var blank = rendered(renderer, scene, assets, nothing, a_camera())
    assert_equal(count_background(blank, renderer.background), WIDTH * HEIGHT)


def assert_coordinates_span(
    corners: List[RasterVertex],
    u_min: Float32,
    u_max: Float32,
    v_min: Float32,
    v_max: Float32,
) raises:
    """Assert the prepared corners' texture coordinates run over the given
    ranges, which is what a transform on them shows up as.

    Args:
        corners: What `prepare` returned; at least one.
        u_min: The smallest u expected.
        u_max: The largest.
        v_min: The smallest v expected.
        v_max: The largest.

    Raises:
        Error: If any bound is off.
    """
    var least_u = corners[0].u
    var most_u = corners[0].u
    var least_v = corners[0].v
    var most_v = corners[0].v
    for index in range(len(corners)):
        least_u = min(least_u, corners[index].u)
        most_u = max(most_u, corners[index].u)
        least_v = min(least_v, corners[index].v)
        most_v = max(most_v, corners[index].v)
    assert_almost_equal(least_u, u_min, atol=1e-5)
    assert_almost_equal(most_u, u_max, atol=1e-5)
    assert_almost_equal(least_v, v_min, atol=1e-5)
    assert_almost_equal(most_v, v_max, atol=1e-5)


def test_a_textures_transform_moves_the_coordinates_a_mesh_samples_with() raises:
    # three.js's uv transform, applied in prepare rather than in a vertex
    # shader: a corner at (1, 1) with a repeat of (2, 3) and an offset of
    # (0.5, 0.25) reaches the rasterizer at (2.5, 3.25).
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(1.0, METER), Length(1.0, METER))
    )
    var board = checkerboard(8, 4, Color(255, 255, 255), Color(20, 20, 20))
    board.repeat = Vector2(2, 3)
    board.offset = Vector2(0.5, 0.25)
    var skin = assets.materials.add(
        Material(Color(255, 255, 255), assets.textures.add(board^), kind=BASIC)
    )
    var scene = unlit_scene_with_a_node()
    scene.add_mesh(Mesh(sheet, skin, NodeId(0)))
    var corners = renderer.prepare(scene, assets, a_camera())
    assert_equal(len(corners), 6)
    assert_coordinates_span(corners, 0.5, 2.5, 0.25, 3.25)
    # The uv view shows the same coordinates: the transform is the
    # material's, whatever the shading mode.
    renderer.set_shading(SHADE_UV)
    assert_coordinates_span(
        renderer.prepare(scene, assets, a_camera()), 0.5, 2.5, 0.25, 3.25
    )


def test_a_geometry_without_uv_takes_the_transformed_origin() raises:
    # No uv attribute and an all-zero one name the same place: both go
    # through the texture's transform, so an offset moves both alike.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var board = checkerboard(8, 4, Color(255, 255, 255), Color(20, 20, 20))
    board.offset = Vector2(0.75, 0.25)
    var skin = assets.materials.add(
        Material(Color(255, 255, 255), assets.textures.add(board^), kind=BASIC)
    )
    var scene = unlit_scene_with_a_node()
    for with_zeros in [False, True]:
        var triangle = BufferGeometry()
        var data: List[Float32] = [-1, -1, 0, 1, -1, 0, 0, 1, 0]
        triangle.set_attribute(String(POSITION), BufferAttribute(data^, 3))
        if with_zeros:
            var zeros = List[Float32](length=6, fill=0.0)
            triangle.set_attribute(String(UV), BufferAttribute(zeros^, 2))
        var meshes = List[Mesh]()
        meshes.append(Mesh(assets.geometries.add(triangle^), skin, NodeId(0)))
        scene.meshes = meshes.copy()
        var corners = renderer.prepare(scene, assets, a_camera())
        assert_equal(len(corners), 3)
        assert_coordinates_span(corners, 0.75, 0.75, 0.25, 0.25)


def test_an_emissive_maps_transform_applies_when_there_is_no_map() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(1.0, METER), Length(1.0, METER))
    )
    var glow = checkerboard(
        8, 4, Color(255, 255, 255), Color(0, 0, 0), alpha=IGNORED
    )
    glow.repeat = Vector2(2, 3)
    var skin = assets.materials.add(
        Material(
            Color(0, 0, 0),
            emissive=Color(255, 255, 255),
            emissive_map=assets.textures.add(glow^),
        )
    )
    var scene = unlit_scene_with_a_node()
    scene.add_mesh(Mesh(sheet, skin, NodeId(0)))
    assert_coordinates_span(
        renderer.prepare(scene, assets, a_camera()), 0, 2, 0, 3
    )


def test_a_map_and_an_emissive_map_must_share_one_transform() raises:
    # A fragment samples both at one coordinate, so a pair that disagree
    # is refused; a copy made with ignoring_alpha carries the transform and
    # is accepted.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.5, METER)))
    var board = checkerboard(8, 4, Color(255, 255, 255), Color(0, 0, 0))
    board.repeat = Vector2(2, 2)
    var agreeing = assets.textures.add(board.ignoring_alpha())
    var base = assets.textures.add(board^)
    var differing = assets.textures.add(
        checkerboard(8, 4, Color(255, 255, 255), Color(0, 0, 0), alpha=IGNORED)
    )
    var scene = unlit_scene_with_a_node()
    var fine = List[Mesh]()
    fine.append(
        Mesh(
            box,
            assets.materials.add(
                Material(
                    Color(255, 255, 255),
                    base,
                    emissive=Color(255, 255, 255),
                    emissive_map=agreeing,
                )
            ),
            NodeId(0),
        )
    )
    var image = rendered(renderer, scene, assets, fine, a_camera())
    var drawn = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if (
                pixel.r != renderer.background.r
                or pixel.g != renderer.background.g
                or pixel.b != renderer.background.b
            ):
                drawn += 1
    assert_true(drawn > 0, "the agreeing pair drew nothing")
    var wrong = List[Mesh]()
    wrong.append(
        Mesh(
            box,
            assets.materials.add(
                Material(
                    Color(255, 255, 255),
                    base,
                    emissive=Color(255, 255, 255),
                    emissive_map=differing,
                )
            ),
            NodeId(0),
        )
    )
    with assert_raises():
        _ = rendered(renderer, scene, assets, wrong, a_camera())


def test_a_repeat_tiles_the_texture_and_an_offset_slides_it() raises:
    # A two-square board on a sheet wider than the view, face-on to an
    # orthographic camera. The middle row crosses one square edge as
    # authored, three with the board repeated twice, and one again with
    # the board slid half a period, which swaps the squares.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(4.0, METER), Length(3.0, METER))
    )
    var scene = unlit_scene_with_a_node()
    var camera = centered(
        Length(2.0, METER),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var plain = checkerboard(
        2, 2, Color(255, 255, 255), Color(0, 0, 0), REPEAT, NEAREST
    )
    var tiled = checkerboard(
        2, 2, Color(255, 255, 255), Color(0, 0, 0), REPEAT, NEAREST
    )
    tiled.repeat = Vector2(2, 2)
    var slid = checkerboard(
        2, 2, Color(255, 255, 255), Color(0, 0, 0), REPEAT, NEAREST
    )
    slid.offset = Vector2(0.5, 0)
    var boards: List[TextureId] = [
        assets.textures.add(plain^),
        assets.textures.add(tiled^),
        assets.textures.add(slid^),
    ]
    var edges = List[Int]()
    var left_bright = List[Bool]()
    for index in range(3):
        var skin = assets.materials.add(
            Material(Color(255, 255, 255), boards[index], kind=BASIC)
        )
        var meshes = List[Mesh]()
        meshes.append(Mesh(sheet, skin, NodeId(0)))
        var image = rendered(renderer, scene, assets, meshes, camera)
        var crossings = 0
        for x in range(1, WIDTH):
            var here = image.get_pixel(x, HEIGHT // 2).r > 128
            var before = image.get_pixel(x - 1, HEIGHT // 2).r > 128
            if here != before:
                crossings += 1
        edges.append(crossings)
        left_bright.append(image.get_pixel(WIDTH // 4, HEIGHT // 2).r > 128)
    assert_equal(edges[0], 1)
    assert_equal(edges[1], 3)
    assert_equal(edges[2], 1)
    assert_true(left_bright[0] != left_bright[2], "the offset slid nothing")


# --- fog ----------------------------------------------------------------------


def facing_camera() raises -> PerspectiveCamera:
    """Return a camera five meters out on +z, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera


def test_the_scenes_fog_veils_a_mesh_by_its_depth() raises:
    # A white unlit sheet five meters from the camera. A fog from four to
    # six meters veils it half way; one from ten to twenty does not reach
    # it; a dense exponential fog swallows it; and no fog leaves it white.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(4.0, METER), Length(4.0, METER), 1, 1)
    )
    var white = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var meshes = List[Mesh]()
    meshes.append(Mesh(sheet, white, node))
    var fog_color = Color(40, 60, 90)
    var camera = facing_camera()

    scene.fog = linear_fog(fog_color, Length(4.0, METER), Length(6.0, METER))
    var halfway = rendered(renderer, scene, assets, meshes, camera).get_pixel(
        WIDTH // 2, HEIGHT // 2
    )
    var fog = FloatColor(srgb=fog_color)
    var expected = FloatColor(
        1 + (fog.r - 1) * 0.5, 1 + (fog.g - 1) * 0.5, 1 + (fog.b - 1) * 0.5, 1.0
    ).encode()
    assert_equal(halfway.r, expected.r)
    assert_equal(halfway.g, expected.g)
    assert_equal(halfway.b, expected.b)

    scene.fog = linear_fog(fog_color, Length(10.0, METER), Length(20.0, METER))
    var clear = rendered(renderer, scene, assets, meshes, camera).get_pixel(
        WIDTH // 2, HEIGHT // 2
    )
    assert_equal(clear.r, UInt8(255))
    assert_equal(clear.b, UInt8(255))

    scene.fog = exp2_fog(fog_color, InverseLength(5.0, PER_METER))
    var swallowed = rendered(renderer, scene, assets, meshes, camera).get_pixel(
        WIDTH // 2, HEIGHT // 2
    )
    assert_equal(swallowed.r, fog_color.r)
    assert_equal(swallowed.g, fog_color.g)
    assert_equal(swallowed.b, fog_color.b)

    scene.fog = no_fog()
    var plain = rendered(renderer, scene, assets, meshes, camera).get_pixel(
        WIDTH // 2, HEIGHT // 2
    )
    assert_equal(plain.r, UInt8(255))
    assert_equal(plain.g, UInt8(255))


def test_fog_does_not_reach_the_background_or_the_uv_view() raises:
    # Only fragments are fogged. Pixels nothing covers stay the clear
    # color, and the uv debug view writes coordinates whatever the fog.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(10, 20, 30))
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(1.0, METER), Length(1.0, METER), 1, 1)
    )
    var white = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.fog = exp2_fog(Color(200, 200, 200), InverseLength(5.0, PER_METER))
    var meshes = List[Mesh]()
    meshes.append(Mesh(sheet, white, node))
    var camera = facing_camera()
    var image = rendered(renderer, scene, assets, meshes, camera)
    var corner = image.get_pixel(0, 0)
    assert_equal(corner.r, UInt8(10))
    assert_equal(corner.b, UInt8(30))
    var center = image.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(center.r, UInt8(200))
    renderer.set_shading(SHADE_UV)
    var coordinates = rendered(renderer, scene, assets, meshes, camera)
    scene.fog = no_fog()
    var unfogged = rendered(renderer, scene, assets, meshes, camera)
    var veiled = coordinates.get_pixel(WIDTH // 2, HEIGHT // 2)
    var plain = unfogged.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(veiled.r, plain.r)
    assert_equal(veiled.g, plain.g)
    assert_equal(veiled.b, UInt8(0))


def test_a_fog_edited_into_nonsense_is_refused_by_render() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    scene.fog = linear_fog(
        Color(0, 0, 0), Length(1.0, METER), Length(2.0, METER)
    )
    scene.fog.far = Length(0.5, METER)
    with assert_raises():
        _ = renderer.render(scene, assets, facing_camera())
    scene.fog = no_fog()
    scene.fog.kind = FogKind(9)
    with assert_raises():
        _ = renderer.render(scene, assets, facing_camera())


# --- tone mapping -------------------------------------------------------------


def test_tone_mapping_compresses_what_the_renderer_shows() raises:
    # A white unlit sheet is white without a curve. Under Reinhard it shows
    # half the light, byte 188. Under the linear curve at a quarter
    # exposure it shows a quarter of it. The background is light in the
    # target too, and goes through the curve with everything else.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(200, 200, 200))
    assert_equal(renderer.tone_mapping, NO_TONE_MAPPING)
    assert_equal(renderer.tone_mapping_exposure, Float32(1))
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(4.0, METER), Length(4.0, METER), 1, 1)
    )
    var white = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var meshes = List[Mesh]()
    meshes.append(Mesh(sheet, white, node))
    var camera = facing_camera()
    var plain = rendered(renderer, scene, assets, meshes, camera)
    assert_equal(plain.get_pixel(WIDTH // 2, HEIGHT // 2).r, UInt8(255))

    renderer.set_tone_mapping(REINHARD_TONE_MAPPING)
    assert_equal(renderer.tone_mapping, REINHARD_TONE_MAPPING)
    var squeezed = rendered(renderer, scene, assets, meshes, camera)
    assert_equal(squeezed.get_pixel(WIDTH // 2, HEIGHT // 2).r, UInt8(188))
    assert_true(
        squeezed.get_pixel(0, 0).b != plain.get_pixel(0, 0).b,
        "the background was not tone mapped",
    )

    renderer.set_tone_mapping(LINEAR_TONE_MAPPING, 0.25)
    assert_equal(renderer.tone_mapping_exposure, Float32(0.25))
    var dim = rendered(renderer, scene, assets, meshes, camera)
    assert_equal(
        dim.get_pixel(WIDTH // 2, HEIGHT // 2).r,
        FloatColor(0.25, 0.25, 0.25, 1.0).encode().r,
    )

    # The uv view is coordinates, not light, and is never tone mapped.
    renderer.set_shading(SHADE_UV)
    var coordinates = rendered(renderer, scene, assets, meshes, camera)
    renderer.set_tone_mapping(NO_TONE_MAPPING)
    var untouched = rendered(renderer, scene, assets, meshes, camera)
    var veiled = coordinates.get_pixel(WIDTH // 2, HEIGHT // 2)
    var raw = untouched.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(veiled.r, raw.r)
    assert_equal(veiled.g, raw.g)


def test_a_tone_mapping_that_is_none_of_the_seven_is_refused() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    with assert_raises():
        renderer.set_tone_mapping(ToneMapping(9))
    with assert_raises():
        renderer.set_tone_mapping(REINHARD_TONE_MAPPING, -0.5)
    assert_equal(renderer.tone_mapping, NO_TONE_MAPPING)
    assert_equal(renderer.tone_mapping_exposure, Float32(1))


def fogged_sheet_through(
    camera: PerspectiveCamera, at: Float32
) raises -> Framebuffer:
    """Render a white sheet at world z `at`, facing +z, through a black
    linear fog from six to ten meters."""
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(40.0, METER), Length(40.0, METER), 1, 1)
    )
    var white = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    var scene = Scene()
    var placed = Object3D()
    placed.set_position(0, 0, at)
    var node = scene.add(placed^)
    scene.update()
    scene.fog = linear_fog(
        Color(0, 0, 0), Length(6.0, METER), Length(10.0, METER)
    )
    var meshes = List[Mesh]()
    meshes.append(Mesh(sheet, white, node))
    return rendered(renderer, scene, assets, meshes, camera)


def test_fog_is_uniform_across_a_flat_sheet_far_from_the_origin() raises:
    # A sheet eight meters in front of a camera a million meters out: every
    # pixel of it is half way into the fog, one byte, and the same bytes as
    # the same sheet eight meters in front of a camera at the origin. The
    # depth is carried from the camera-space position; recovered from a
    # world coordinate, which rounds by a sixteenth out there, it wandered
    # by an eighth of a meter across one flat surface.
    var far = PerspectiveCamera(
        Angle(60.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    far.place(Vector3(0, 0, 1000000), Vector3(0, 0, 999992))
    var out_there = fogged_sheet_through(far, 999992)
    var near = PerspectiveCamera(
        Angle(60.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    near.place(Vector3(0, 0, 0), Vector3(0, 0, -8))
    var at_home = fogged_sheet_through(near, -8)
    var expected = FloatColor(0.5, 0.5, 0.5, 1.0).encode().r
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var theirs = out_there.get_pixel(x, y)
            var ours = at_home.get_pixel(x, y)
            assert_equal(theirs.r, expected)
            assert_equal(theirs.g, expected)
            assert_equal(ours.r, theirs.r)
            assert_equal(ours.b, theirs.b)


def test_set_tone_mapping_refuses_an_exposure_that_is_not_finite() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    with assert_raises():
        renderer.set_tone_mapping(REINHARD_TONE_MAPPING, inf[DType.float32]())
    with assert_raises():
        renderer.set_tone_mapping(REINHARD_TONE_MAPPING, nan[DType.float32]())
    assert_equal(renderer.tone_mapping, NO_TONE_MAPPING)


# --- normal and depth materials ---------------------------------------------


def camera_at(x: Float32, y: Float32, z: Float32) raises -> PerspectiveCamera:
    """Return a camera at a point, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(x, y, z), Vector3(0, 0, 0))
    return camera^


def turned_scene(turn: Angle) raises -> Scene:
    """Return a lit scene whose only node is turned that far about y."""
    var scene = Scene()
    var node = Object3D()
    node.set_euler(Angle(0.0, DEGREE), turn, Angle(0.0, DEGREE))
    _ = scene.add(node^)
    light_the(scene)
    scene.update()
    return scene^


def sheet_of(
    mut assets: Assets, material: MaterialId, node: NodeId = NodeId(0)
) raises -> List[Mesh]:
    """Return one two-meter sheet drawn with `material` at `node`."""
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(
                plane(Length(2.0, METER), Length(2.0, METER))
            ),
            material,
            node,
        )
    )
    return meshes^


def test_a_normal_material_shows_the_normal_the_camera_sees() raises:
    # A sheet square on to the camera is (128, 128, 255), whatever the
    # lights are doing: three.js's `packNormalToRGB` of (0, 0, 1).
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var shown = assets.materials.add(normal_material())
    var scene = scene_with_node_at(0)
    var meshes = sheet_of(assets, shown)
    var square = rendered(renderer, scene, assets, meshes, camera_at(0, 0, 4))
    var center = square.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(center.r, UInt8(128))
    assert_equal(center.g, UInt8(128))
    assert_equal(center.b, UInt8(255))
    # Turned an eighth of a turn about y, the normal leans toward the
    # camera's right: (0.7071, 0, 0.7071) packed.
    var leaning = turned_scene(Angle(45.0, DEGREE))
    var tilted = rendered(renderer, leaning, assets, meshes, camera_at(0, 0, 4))
    var lean = tilted.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(lean.r, UInt8(218))
    assert_equal(lean.g, UInt8(128))
    assert_equal(lean.b, UInt8(218))


def test_a_normal_material_turns_with_the_camera() raises:
    # The normal is in view space, three.js's `vNormal`, so moving the
    # camera changes the color of a sheet that never moved. From up and
    # back at forty-five degrees the sheet's normal reads
    # (0, -0.7071, 0.7071).
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var shown = assets.materials.add(normal_material())
    var scene = scene_with_node_at(0)
    var meshes = sheet_of(assets, shown)
    var above = rendered(renderer, scene, assets, meshes, camera_at(0, 4, 4))
    var center = above.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(center.r, UInt8(128))
    assert_equal(center.g, UInt8(37))
    assert_equal(center.b, UInt8(218))


def test_a_normal_material_flips_a_face_seen_from_behind() raises:
    # A sheet turned right around and drawn double sided: the side being
    # looked at is the one shown, as it is the one lit. Without the flip it
    # would read (128, 128, 0).
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var shown = assets.materials.add(normal_material(DOUBLE_SIDE))
    var scene = turned_scene(Angle(180.0, DEGREE))
    var meshes = sheet_of(assets, shown)
    var behind = rendered(renderer, scene, assets, meshes, camera_at(0, 0, 4))
    var center = behind.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(center.r, UInt8(128))
    assert_equal(center.g, UInt8(128))
    assert_equal(center.b, UInt8(255))


def test_a_normal_material_falls_back_to_the_face_normal() raises:
    # A geometry that never said which way it faces still shows a normal:
    # the face's own, computed in world space and carried into view space
    # like a supplied one.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(lone_triangle(False)),
            assets.materials.add(normal_material()),
            NodeId(0),
        )
    )
    var scene = scene_with_node_at(0)
    var flat = rendered(renderer, scene, assets, meshes, camera_at(0, 0, 4))
    var inside = flat.get_pixel(WIDTH // 2, HEIGHT // 2 + 2)
    assert_equal(inside.r, UInt8(128))
    assert_equal(inside.g, UInt8(128))
    assert_equal(inside.b, UInt8(255))


def test_a_depth_material_is_brighter_near_than_far() raises:
    # One minus the window-space depth, so the near sheet is the paler
    # gray. A camera one to ten meters deep puts a sheet four meters out at
    # two thirds in NDC and one six meters out at 0.8519.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var shown = assets.materials.add(depth_material())
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(1.0, METER),
        Length(10.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var near_scene = scene_with_node_at(0)
    var far_scene = scene_with_node_at(-2)
    var meshes = sheet_of(assets, shown)
    var near = rendered(renderer, near_scene, assets, meshes, camera)
    var far = rendered(renderer, far_scene, assets, meshes, camera)
    var pale = near.get_pixel(WIDTH // 2, HEIGHT // 2)
    var dark = far.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(pale.r, pale.g)
    assert_equal(pale.g, pale.b)
    assert_true(pale.r > dark.r, "the far sheet was not the darker gray")
    assert_true(
        abs(Int(pale.r) - 43) <= 1, "the near sheet is not the expected gray"
    )
    assert_true(
        abs(Int(dark.r) - 19) <= 1, "the far sheet is not the expected gray"
    )


def test_a_data_material_ignores_the_lights_and_the_fog() raises:
    # Neither the lights nor the fog touches a normal or a depth: what the
    # material writes is data, and a veil of light over it would be a lie.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    for material in [normal_material(), depth_material()]:
        var shown = assets.materials.add(material)
        var meshes = sheet_of(assets, shown)
        var scene = scene_with_node_at(0)
        var plain = rendered(
            renderer, scene, assets, meshes, camera_at(0, 0, 4)
        )
        var dark = unlit_scene_with_a_node()
        var unlit = rendered(renderer, dark, assets, meshes, camera_at(0, 0, 4))
        var fogged = scene_with_node_at(0)
        fogged.fog = linear_fog(
            Color(255, 0, 0), Length(0.5, METER), Length(4.5, METER)
        )
        var veiled = rendered(
            renderer, fogged, assets, meshes, camera_at(0, 0, 4)
        )
        for y in range(HEIGHT):
            for x in range(WIDTH):
                var here = plain.get_pixel(x, y)
                assert_equal(unlit.get_pixel(x, y).r, here.r)
                assert_equal(unlit.get_pixel(x, y).g, here.g)
                assert_equal(unlit.get_pixel(x, y).b, here.b)
                assert_equal(veiled.get_pixel(x, y).r, here.r)
                assert_equal(veiled.get_pixel(x, y).g, here.g)
                assert_equal(veiled.get_pixel(x, y).b, here.b)


def test_a_data_material_is_not_tone_mapped_by_the_renderer() raises:
    # The curve compresses light, and the target keeps it off a pixel that
    # holds data. A lit sheet at the same place is compressed.
    var assets = Assets()
    var shown = assets.materials.add(normal_material())
    var white = assets.materials.add(Material(Color(255, 255, 255)))
    var scene = scene_with_node_at(0)
    var plain = Renderer(WIDTH, HEIGHT)
    var curved = Renderer(WIDTH, HEIGHT)
    curved.set_tone_mapping(REINHARD_TONE_MAPPING)
    var meshes = sheet_of(assets, shown)
    var flat = rendered(plain, scene, assets, meshes, camera_at(0, 0, 4))
    var squeezed = rendered(curved, scene, assets, meshes, camera_at(0, 0, 4))
    var here = WIDTH // 2
    assert_equal(
        squeezed.get_pixel(here, HEIGHT // 2).b,
        flat.get_pixel(here, HEIGHT // 2).b,
    )
    var lit_meshes = sheet_of(assets, white)
    var bright = rendered(plain, scene, assets, lit_meshes, camera_at(0, 0, 4))
    var compressed = rendered(
        curved, scene, assets, lit_meshes, camera_at(0, 0, 4)
    )
    assert_true(
        compressed.get_pixel(here, HEIGHT // 2).r
        < bright.get_pixel(here, HEIGHT // 2).r,
        "the curve compressed nothing",
    )


# --- alpha map and alpha test -----------------------------------------------


def a_split_mask() raises -> Texture:
    """Return a two-texel alpha map: opaque on the left, empty on the right.

    Stored as data -- linear, and ignoring its own alpha -- because its
    green channel is a coverage rather than a color.
    """
    var pixels = List[UInt8]()
    for green in [255, 0]:
        pixels.append(0)
        pixels.append(UInt8(green))
        pixels.append(255)
        pixels.append(255)
    return Texture(2, 1, pixels^, REPEAT, NEAREST, LINEAR, False, IGNORED)


def a_flat_mask(green: UInt8) raises -> Texture:
    """Return a one-texel alpha map, stored as data."""
    var pixels = List[UInt8]()
    pixels.append(0)
    pixels.append(green)
    pixels.append(255)
    pixels.append(255)
    return Texture(1, 1, pixels^, REPEAT, NEAREST, LINEAR, False, IGNORED)


def test_an_alpha_map_thins_a_mesh() raises:
    # The map's green channel multiplies the opacity, so a half map over a
    # black background shows half the surface's light.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var mask = assets.textures.add(a_flat_mask(128))
    var thinned = assets.materials.add(
        Material(
            Color(255, 255, 255),
            kind=BASIC,
            alpha_map=mask,
            blending=BLEND,
        )
    )
    var solid = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    var scene = scene_with_node_at(0)
    var faint = rendered(
        renderer, scene, assets, sheet_of(assets, thinned), camera_at(0, 0, 4)
    )
    var full = rendered(
        renderer, scene, assets, sheet_of(assets, solid), camera_at(0, 0, 4)
    )
    var here = faint.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(full.get_pixel(WIDTH // 2, HEIGHT // 2).r, UInt8(255))
    var share = Float32(128) / 255
    assert_equal(here.r, FloatColor(share, share, share, 1.0).encode().r)


def test_an_alpha_test_cuts_a_hole_that_shows_what_is_behind() raises:
    # A near sheet cut in half by its alpha map, over a far red sheet. The
    # thrown-away fragments claim no depth, so the far sheet shows through.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var mask = assets.textures.add(a_split_mask())
    var leaf = assets.materials.add(
        Material(
            Color(255, 255, 255), kind=BASIC, alpha_map=mask, alpha_test=0.5
        )
    )
    var behind = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = Scene()
    var near = Object3D()
    var near_node = scene.add(near^)
    var far = Object3D()
    far.set_position(0, 0, -1)
    var far_node = scene.add(far^)
    scene.update()
    var meshes = sheet_of(assets, leaf, near_node)
    for mesh in sheet_of(assets, behind, far_node):
        meshes.append(mesh)
    var shown = rendered(renderer, scene, assets, meshes, camera_at(0, 0, 4))
    var kept = shown.get_pixel(9, HEIGHT // 2)
    assert_equal(kept.r, UInt8(255))
    assert_equal(kept.g, UInt8(255))
    var hole = shown.get_pixel(15, HEIGHT // 2)
    assert_equal(hole.r, UInt8(255))
    assert_equal(hole.g, UInt8(0))
    assert_equal(hole.b, UInt8(0))


def test_without_the_test_a_thinned_fragment_still_claims_the_depth() raises:
    # The same pair with no alpha test: the near sheet is drawn opaque,
    # white and with an alpha of one whatever the map said, and keeps the
    # depth, so the far sheet is hidden. This is what the test is for.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var mask = assets.textures.add(a_split_mask())
    var thinned = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, alpha_map=mask)
    )
    var behind = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = Scene()
    var near_node = scene.add(Object3D())
    var far = Object3D()
    far.set_position(0, 0, -1)
    var far_node = scene.add(far^)
    scene.update()
    var meshes = sheet_of(assets, thinned, near_node)
    for mesh in sheet_of(assets, behind, far_node):
        meshes.append(mesh)
    var shown = rendered(renderer, scene, assets, meshes, camera_at(0, 0, 4))
    var hole = shown.get_pixel(15, HEIGHT // 2)
    assert_equal(hole.a, UInt8(255))
    assert_equal(hole.r, UInt8(255))
    assert_equal(hole.g, UInt8(255))


def test_a_material_naming_an_alpha_map_that_is_not_there_is_rejected() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var missing = assets.materials.add(
        Material(Color(255, 255, 255), alpha_map=TextureId(0))
    )
    var scene = scene_with_node_at(0)
    var meshes = sheet_of(assets, missing)
    with assert_raises():
        _ = rendered(renderer, scene, assets, meshes, camera_at(0, 0, 4))


def test_an_alpha_map_must_be_stored_as_data() raises:
    # Refused whatever the shading mode: a wrong asset, not a wrong frame.
    var assets = Assets()
    var pixels = List[UInt8]()
    for value in [0, 128, 255, 255]:
        pixels.append(UInt8(value))
    var encoded = assets.textures.add(
        Texture(1, 1, pixels.copy(), REPEAT, NEAREST, SRGB, False, IGNORED)
    )
    var covered = assets.textures.add(
        Texture(1, 1, pixels^, REPEAT, NEAREST, LINEAR, False, COVERAGE)
    )
    var scene = scene_with_node_at(0)
    for slot in [encoded, covered]:
        var wrong = assets.materials.add(
            Material(Color(255, 255, 255), alpha_map=slot)
        )
        var meshes = sheet_of(assets, wrong)
        for mode in [SHADE_TEXTURE, SHADE_LIT]:
            var renderer = Renderer(WIDTH, HEIGHT)
            renderer.set_shading(mode)
            with assert_raises():
                _ = rendered(
                    renderer, scene, assets, meshes, camera_at(0, 0, 4)
                )


def test_every_map_on_one_material_must_share_one_transform() raises:
    # A fragment carries one coordinate pair and samples all three maps
    # with it, so the first map named decides and the others must agree.
    var assets = Assets()
    var base = assets.textures.add(
        checkerboard(4, 2, Color(255, 255, 255), Color(0, 0, 0))
    )
    var moved = checkerboard(4, 2, Color(255, 255, 255), Color(0, 0, 0))
    moved.repeat = Vector2(2, 2)
    var shifted = assets.textures.add(moved^)
    var mask = assets.textures.add(a_flat_mask(255))
    var agreeing = assets.materials.add(
        Material(Color(255, 255, 255), base, alpha_map=mask)
    )
    var disagreeing = assets.materials.add(
        Material(Color(255, 255, 255), shifted, alpha_map=mask)
    )
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = scene_with_node_at(0)
    _ = rendered(
        renderer, scene, assets, sheet_of(assets, agreeing), camera_at(0, 0, 4)
    )
    with assert_raises():
        _ = rendered(
            renderer,
            scene,
            assets,
            sheet_of(assets, disagreeing),
            camera_at(0, 0, 4),
        )
    # An alpha map alone still supplies the transform.
    var alone = assets.materials.add(
        Material(Color(255, 255, 255), alpha_map=mask)
    )
    _ = rendered(
        renderer, scene, assets, sheet_of(assets, alone), camera_at(0, 0, 4)
    )


def test_lit_shading_ignores_the_alpha_map() raises:
    # `SHADE_LIT` ignores every texture, so a map that would empty the
    # surface leaves it whole.
    var assets = Assets()
    var mask = assets.textures.add(a_flat_mask(0))
    var thinned = assets.materials.add(
        Material(
            Color(255, 255, 255), kind=BASIC, alpha_map=mask, alpha_test=0.5
        )
    )
    var scene = scene_with_node_at(0)
    var meshes = sheet_of(assets, thinned)
    var sampled = Renderer(WIDTH, HEIGHT)
    sampled.set_background(Color(0, 0, 0))
    var ignored = Renderer(WIDTH, HEIGHT)
    ignored.set_background(Color(0, 0, 0))
    ignored.set_shading(SHADE_LIT)
    var gone = rendered(sampled, scene, assets, meshes, camera_at(0, 0, 4))
    var whole = rendered(ignored, scene, assets, meshes, camera_at(0, 0, 4))
    # Sampled, the map empties the surface and the test throws it away.
    assert_equal(gone.get_pixel(WIDTH // 2, HEIGHT // 2).r, UInt8(0))
    assert_equal(whole.get_pixel(WIDTH // 2, HEIGHT // 2).r, UInt8(255))


# --- phong ------------------------------------------------------------------


def lamp_scene() raises -> Scene:
    """Return a scene with a node at the origin and one white lamp up the z
    axis, so a sheet facing the camera is lit straight on."""
    var scene = Scene()
    _ = scene.add(Object3D())
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, FULL))
    scene.update()
    return scene^


def test_a_phong_sheet_is_brighter_seen_head_on() raises:
    # Nothing moves but the camera, and a highlight is the one term that
    # answers to where the camera stands. A lambert sheet does not move.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var shiny = assets.materials.add(
        phong_material(Color(0, 0, 0), NO_TEXTURE, Color(128, 128, 128), 30.0)
    )
    var dull = assets.materials.add(Material(Color(120, 120, 120)))
    var scene = lamp_scene()
    var glossy = sheet_of(assets, shiny)
    var plain = sheet_of(assets, dull)
    var head_on = rendered(renderer, scene, assets, glossy, camera_at(0, 0, 4))
    var aside = rendered(renderer, scene, assets, glossy, camera_at(4, 0, 4))
    var bright = head_on.get_pixel(WIDTH // 2, HEIGHT // 2).r
    var dim = aside.get_pixel(WIDTH // 2, HEIGHT // 2).r
    assert_true(bright > dim + 40, "the highlight did not follow the camera")
    assert_true(dim > 0, "the highlight vanished from the side")
    # The same two cameras on a lambert sheet see the same brightness.
    var flat_on = rendered(renderer, scene, assets, plain, camera_at(0, 0, 4))
    var flat_aside = rendered(
        renderer, scene, assets, plain, camera_at(4, 0, 4)
    )
    assert_equal(
        flat_on.get_pixel(WIDTH // 2, HEIGHT // 2).r,
        flat_aside.get_pixel(WIDTH // 2, HEIGHT // 2).r,
    )


def test_a_phong_sphere_shows_a_spot_a_lambert_one_does_not() raises:
    # The same sphere, the same light: the phong one has a bright spot
    # where the normal points half way between the light and the camera.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(1.0, METER), 24, 16))
    var shiny = assets.materials.add(
        phong_material(
            Color(60, 60, 60), NO_TEXTURE, Color(255, 255, 255), 40.0
        )
    )
    var dull = assets.materials.add(Material(Color(60, 60, 60)))
    var scene = lamp_scene()
    var glossy = List[Mesh]()
    glossy.append(Mesh(ball, shiny, NodeId(0)))
    var plain = List[Mesh]()
    plain.append(Mesh(ball, dull, NodeId(0)))
    var spotted = rendered(renderer, scene, assets, glossy, camera_at(0, 0, 4))
    var flat = rendered(renderer, scene, assets, plain, camera_at(0, 0, 4))
    assert_true(
        count_bright(spotted) > count_bright(flat) + 10,
        "the phong sphere had no highlight",
    )
    # And away from the spot the two agree: the diffuse term is the same.
    assert_equal(
        spotted.get_pixel(WIDTH // 2, HEIGHT // 2 - 6).r,
        flat.get_pixel(WIDTH // 2, HEIGHT // 2 - 6).r,
    )


def test_a_phong_material_is_lit_like_a_lambert_one() raises:
    # Its diffuse term is a lambert term, which is what says the highlight
    # is the only thing the kind adds. Head on, with a base reflectance of
    # zero, the Fresnel rim is far below a level and the two images agree
    # exactly; at a grazing angle they do not, and the test below says so.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var dull = assets.materials.add(Material(Color(200, 100, 50), kind=PHONG))
    var lambert = assets.materials.add(Material(Color(200, 100, 50)))
    var scene = scene_with_node_at(0)
    var one = rendered(
        renderer, scene, assets, sheet_of(assets, dull), camera_at(0, 0, 4)
    )
    var two = rendered(
        renderer, scene, assets, sheet_of(assets, lambert), camera_at(0, 0, 4)
    )
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(one.get_pixel(x, y).r, two.get_pixel(x, y).r)
            assert_equal(one.get_pixel(x, y).g, two.get_pixel(x, y).g)


# --- a parallel projection sees every surface from one direction ------------


def flat_ortho(height: Float32) raises -> OrthographicCamera:
    """Return an orthographic camera up the z axis, looking at the origin."""
    var camera = centered(
        Length(height, METER),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def test_a_perspective_camera_has_no_one_direction_toward_it() raises:
    # Its rays converge, so each fragment works its own out from the
    # camera's position. `toward_camera` says so by answering with the
    # zero vector.
    var scene = scene_with_node_at(0)
    var toward = toward_camera(scene, camera_at(0, 0, 4))
    assert_equal(toward.x, Float32(0))
    assert_equal(toward.y, Float32(0))
    assert_equal(toward.z, Float32(0))
    # An orthographic camera answers with its own backward axis, a unit
    # vector, which for one up the z axis is +z.
    var parallel = toward_camera(scene, flat_ortho(4.0))
    assert_almost_equal(parallel.x, Float32(0), atol=TOLERANCE)
    assert_almost_equal(parallel.y, Float32(0), atol=TOLERANCE)
    assert_almost_equal(parallel.z, Float32(1), atol=TOLERANCE)
    assert_almost_equal(parallel.length(), Float32(1), atol=TOLERANCE)
    # One placed off the axis answers with the direction it looks back
    # along, not with where it stands.
    var tilted = centered(
        Length(6.0, METER),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    tilted.place(Vector3(0, 4, 4), Vector3(0, 0, 0))
    var leaning = toward_camera(scene, tilted)
    assert_almost_equal(leaning.y, Float32(0.7071068), atol=TOLERANCE)
    assert_almost_equal(leaning.z, Float32(0.7071068), atol=TOLERANCE)


def test_an_orthographic_highlight_is_even_across_a_flat_sheet() raises:
    # A parallel projection sees every point of a flat sheet from the same
    # direction, so a sheet square on to both the light and the camera
    # reflects evenly. Working the direction out from the camera's position
    # instead puts a bright spot in the middle of it, which is the bug this
    # pins: the corner of the sheet fell from byte 170 to byte 54.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(6.0, METER), Length(6.0, METER), 4, 4)
    )
    var shiny = assets.materials.add(
        phong_material(Color(0, 0, 0), NO_TEXTURE, Color(255, 255, 255), 30.0)
    )
    var scene = lamp_scene()
    var meshes = List[Mesh]()
    meshes.append(Mesh(sheet, shiny, NodeId(0)))
    var shown = rendered(renderer, scene, assets, meshes, flat_ortho(4.0))
    var middle = shown.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_true(middle.r > 200, "the sheet caught no highlight at all")
    # Every covered pixel agrees with the middle, to the level that
    # interpolating the normals across the sheet allows.
    for y in range(2, HEIGHT - 2):
        for x in range(2, WIDTH - 2):
            var here = shown.get_pixel(x, y)
            assert_true(
                abs(Int(here.r) - Int(middle.r)) <= 1,
                "the highlight is not even across a parallel view",
            )


def test_moving_an_orthographic_camera_along_its_axis_changes_nothing() raises:
    # Its rays run parallel, so sliding it back and forth cannot change
    # which way a surface sees it. A perspective camera's highlight does
    # move, which is what makes this a test of the projection.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var shiny = assets.materials.add(
        phong_material(Color(0, 0, 0), NO_TEXTURE, Color(255, 255, 255), 30.0)
    )
    var scene = lamp_scene()
    var meshes = sheet_of(assets, shiny)
    var near = flat_ortho(4.0)
    var far = centered(
        Length(4.0, METER),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    far.place(Vector3(0, 0, 20), Vector3(0, 0, 0))
    var close = rendered(renderer, scene, assets, meshes, near)
    var distant = rendered(renderer, scene, assets, meshes, far)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(close.get_pixel(x, y).r, distant.get_pixel(x, y).r)


# --- a black specular is a base reflectance, not a switch -------------------


def test_a_black_specular_still_differs_from_lambert_at_a_grazing_angle() raises:
    # three.js's Fresnel factor rises toward one whatever the surface
    # reflects head on, so the default phong material is not a lambert one.
    # A sheet with the light and the camera both far off the normal shows
    # the rim; a lambert sheet shows nothing.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var dull = assets.materials.add(Material(Color(0, 0, 0), kind=PHONG))
    var lambert = assets.materials.add(Material(Color(0, 0, 0)))
    var scene = Scene()
    _ = scene.add(Object3D())
    var lamp = Object3D()
    # Eighty degrees off the normal, on the far side from the camera.
    lamp.set_position(5.6713, 0, 1.0)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, 1.0))
    scene.update()
    var camera = camera_at(-5.6713, 0, 1.0)
    var rim = rendered(renderer, scene, assets, sheet_of(assets, dull), camera)
    var none = rendered(
        renderer, scene, assets, sheet_of(assets, lambert), camera
    )
    var here = rim.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(none.get_pixel(WIDTH // 2, HEIGHT // 2).r, UInt8(0))
    assert_true(here.r > 0, "the black specular caught no rim at all")
    assert_true(here.r < 80, "the rim is far brighter than a rim should be")


# --- a toon material, through the renderer ---------------------------------


def a_gradient(
    tones: List[UInt8],
    space: ColorSpace = LINEAR,
    alpha: Alpha = IGNORED,
) raises -> Texture:
    """Return a one-row gradient map whose red channel holds `tones`."""
    var pixels = List[UInt8]()
    for tone in tones:
        pixels.append(tone)
        pixels.append(255)
        pixels.append(0)
        pixels.append(255)
    return Texture(len(tones), 1, pixels^, REPEAT, NEAREST, space, False, alpha)


def ball_of(mut assets: Assets, material: MaterialId) raises -> List[Mesh]:
    """Return one sphere drawn with `material`, whose normals sweep the
    whole ramp."""
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(sphere(Length(0.9, METER), 24, 18)),
            material,
            NodeId(0),
        )
    )
    return meshes^


def band_count(shown: Framebuffer) raises -> Int:
    """Return how many different red levels the image holds, background
    aside."""
    var seen = List[UInt8]()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var here = shown.get_pixel(x, y).r
            var known = False
            for level in seen:
                if level == here:
                    known = True
            if not known:
                seen.append(here)
    return len(seen)


def test_a_toon_sphere_shows_flat_bands_where_a_lambert_one_is_smooth() raises:
    # The whole point of the kind: a lambert sphere fades through dozens of
    # levels and a toon one shows the ramp's tones and the background.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var flat = assets.materials.add(toon_material(Color(255, 255, 255)))
    var smooth = assets.materials.add(Material(Color(255, 255, 255)))
    var scene = lamp_scene()
    var stepped = rendered(
        renderer, scene, assets, ball_of(assets, flat), camera_at(0, 0, 4)
    )
    var faded = rendered(
        renderer, scene, assets, ball_of(assets, smooth), camera_at(0, 0, 4)
    )
    # The background, the fallback's low tone and its full tone: three.
    assert_equal(band_count(stepped), 3)
    assert_true(band_count(faded) > 10, "a lambert sphere did not fade at all")


def test_a_gradient_map_gives_a_toon_sphere_its_own_bands() raises:
    # Four tones in the map, four bands on the sphere. The lamp is off to
    # the side, so the visible half of the sphere is turned through the
    # whole ramp rather than through its top half alone.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var tones: List[UInt8] = [0, 60, 150, 255]
    var ramp = assets.textures.add(a_gradient(tones))
    var stepped = assets.materials.add(
        toon_material(Color(255, 255, 255), NO_TEXTURE, ramp)
    )
    var scene = Scene()
    _ = scene.add(Object3D())
    var lamp = Object3D()
    lamp.set_position(1, 0, 0)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, FULL))
    scene.update()
    var shown = rendered(
        renderer, scene, assets, ball_of(assets, stepped), camera_at(0, 0, 4)
    )
    # The brightest band is white, which says the top tone was reached.
    var brightest = UInt8(0)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var here = shown.get_pixel(x, y).r
            if here > brightest:
                brightest = here
    assert_equal(brightest, UInt8(255))
    # Four tones, and the darkest is black like the background, so four
    # levels in all. The fallback could give neither that black nor four.
    assert_equal(band_count(shown), 4)


def test_a_material_naming_a_gradient_map_that_is_not_there_is_rejected() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var missing = assets.materials.add(
        toon_material(Color(255, 255, 255), NO_TEXTURE, TextureId(3))
    )
    var scene = lamp_scene()
    with assert_raises():
        _ = rendered(
            renderer,
            scene,
            assets,
            ball_of(assets, missing),
            camera_at(0, 0, 4),
        )


def a_toon_sphere_with(var ramp_image: Texture) raises:
    """Render a toon sphere whose ramp is `ramp_image`, and throw the image
    away: what is under test is whether the render is allowed at all."""
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var ramp = assets.textures.add(ramp_image^)
    var stepped = assets.materials.add(
        toon_material(Color(255, 255, 255), NO_TEXTURE, ramp)
    )
    var scene = lamp_scene()
    _ = rendered(
        renderer, scene, assets, ball_of(assets, stepped), camera_at(0, 0, 4)
    )


def test_a_gradient_map_must_be_stored_as_data_in_the_renderer() raises:
    # Refused whatever the shading mode, as a wrong asset rather than a
    # wrong frame -- the rule an alpha map follows.
    var tones: List[UInt8] = [0, 255]
    with assert_raises():
        a_toon_sphere_with(a_gradient(tones, SRGB, IGNORED))
    with assert_raises():
        a_toon_sphere_with(a_gradient(tones, LINEAR, COVERAGE))
    with assert_raises():
        a_toon_sphere_with(a_gradient(tones, SRGB, COVERAGE))
    # A ramp stored as data draws, which is what makes the three above
    # about the storage and not about the ramp.
    a_toon_sphere_with(a_gradient(tones))


def test_a_ramp_is_read_at_no_surface_coordinate() raises:
    # A fragment carries one texture coordinate and samples every map with
    # it, so a material's maps must share one transform. A ramp is not
    # sampled with it at all -- three.js reads it at `vec2(coord, 0.0)` --
    # so its own transform is neither applied nor asked to agree.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var tones: List[UInt8] = [0, 255]
    var moved = a_gradient(tones)
    moved.repeat = Vector2(3, 7)
    moved.offset = Vector2(0.25, 0.5)
    var ramp = assets.textures.add(moved^)
    var board = checkerboard(8, 4, Color(255, 255, 255), Color(0, 0, 0))
    var skin = assets.textures.add(board^)
    var stepped = assets.materials.add(
        toon_material(Color(255, 255, 255), skin, ramp)
    )
    var scene = lamp_scene()
    var shown = rendered(
        renderer, scene, assets, ball_of(assets, stepped), camera_at(0, 0, 4)
    )
    var drawn = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if shown.get_pixel(x, y).r > 0:
                drawn += 1
    assert_true(drawn > 50, "the sphere barely drew anything")


# --- a matcap material, through the renderer -------------------------------


def a_matcap_image(left: Color, right: Color) raises -> Texture:
    """Return a two-texel matcap: `left` on the left, `right` on the
    right."""
    var pixels = List[UInt8]()
    for tint in [left, right]:
        pixels.append(tint.r)
        pixels.append(tint.g)
        pixels.append(tint.b)
        pixels.append(255)
    return Texture(2, 1, pixels^, CLAMP, NEAREST, SRGB, False, IGNORED)


def test_an_upright_camera_looks_up_the_world_y_axis() raises:
    # `camera_up` is the view space +y axis in world coordinates. An
    # upright camera's is world up, whatever it is looking at.
    var scene = scene_with_node_at(0)
    var up = camera_up(scene, camera_at(0, 0, 4))
    assert_almost_equal(up.x, Float32(0), atol=TOLERANCE)
    assert_almost_equal(up.y, Float32(1), atol=TOLERANCE)
    assert_almost_equal(up.z, Float32(0), atol=TOLERANCE)
    assert_almost_equal(up.length(), Float32(1), atol=TOLERANCE)
    # A camera looking down at forty-five degrees has tilted its up axis
    # back by the same forty-five: still square to the way it looks.
    var above = camera_up(scene, camera_at(0, 4, 4))
    assert_almost_equal(above.y, Float32(0.7071068), atol=TOLERANCE)
    assert_almost_equal(above.z, Float32(-0.7071068), atol=TOLERANCE)
    # A parallel projection answers the same way: which way is up does not
    # depend on whether the rays converge.
    var flat = camera_up(scene, flat_ortho(4.0))
    assert_almost_equal(flat.y, Float32(1), atol=TOLERANCE)


def test_a_matcap_sphere_shows_the_image_and_not_the_lights() raises:
    # The left of the sphere leans left and reads the image's left half;
    # the right leans right and reads its right half. The scene's lamp
    # changes nothing, which is what says the surface is unlit.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var ball = assets.textures.add(
        a_matcap_image(Color(255, 0, 0), Color(0, 0, 255))
    )
    var skin = assets.materials.add(matcap_material(ball))
    var scene = lamp_scene()
    var shown = rendered(
        renderer, scene, assets, ball_of(assets, skin), camera_at(0, 0, 4)
    )
    var left = shown.get_pixel(WIDTH // 2 - 4, HEIGHT // 2)
    var right = shown.get_pixel(WIDTH // 2 + 4, HEIGHT // 2)
    assert_equal(left.r, UInt8(255))
    assert_equal(left.b, UInt8(0))
    assert_equal(right.r, UInt8(0))
    assert_equal(right.b, UInt8(255))
    # An unlit scene gives the same image, because no light is read.
    var dark = Scene()
    _ = dark.add(Object3D())
    dark.update()
    var again = rendered(
        renderer, dark, assets, ball_of(assets, skin), camera_at(0, 0, 4)
    )
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(again.get_pixel(x, y).r, shown.get_pixel(x, y).r)
            assert_equal(again.get_pixel(x, y).b, shown.get_pixel(x, y).b)


def unlike(left: Framebuffer, right: Framebuffer, levels: Int) raises -> Int:
    """Return how many pixels differ in red by more than `levels`."""
    var apart = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var here = Int(left.get_pixel(x, y).r)
            var there = Int(right.get_pixel(x, y).r)
            if here - there > levels or there - here > levels:
                apart += 1
    return apart


def test_a_matcap_stays_put_as_the_camera_orbits() raises:
    # The frame a matcap is looked up in is the camera's own, so a sphere's
    # normals fall in the same places in it from wherever the camera
    # stands. Orbit a quarter turn and the image hardly moves. A lambert
    # sphere lit from one side changes completely over the same orbit,
    # which is what makes this a test of the frame.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var ball = assets.textures.add(
        a_matcap_image(Color(255, 0, 0), Color(60, 60, 60))
    )
    var skin = assets.materials.add(matcap_material(ball))
    var plain = assets.materials.add(Material(Color(255, 255, 255)))
    var scene = Scene()
    _ = scene.add(Object3D())
    var lamp = Object3D()
    lamp.set_position(1, 0, 0)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, 1.0))
    scene.update()
    var front = rendered(
        renderer, scene, assets, ball_of(assets, skin), camera_at(0, 0, 4)
    )
    var side = rendered(
        renderer, scene, assets, ball_of(assets, skin), camera_at(4, 0, 0)
    )
    var lit_front = rendered(
        renderer, scene, assets, ball_of(assets, plain), camera_at(0, 0, 4)
    )
    var lit_side = rendered(
        renderer, scene, assets, ball_of(assets, plain), camera_at(4, 0, 0)
    )
    var kept = unlike(front, side, 16)
    var swung = unlike(lit_front, lit_side, 16)
    # The sphere covers about eighty pixels of this small image, so these
    # counts are a large share of it and not a handful of stragglers.
    assert_true(kept < 10, "the matcap moved with the world")
    assert_true(swung > 40, "the lambert sphere did not move at all")
    # And the image really is what the sphere shows: its left half is the
    # matcap's red and its right half the matcap's gray.
    assert_equal(front.get_pixel(WIDTH // 2 - 4, HEIGHT // 2).r, UInt8(255))
    assert_true(front.get_pixel(WIDTH // 2 + 4, HEIGHT // 2).r < 200)


def test_a_matcap_sphere_without_an_image_takes_the_gradient() raises:
    # Dark at the bottom and pale at the top, which reads as a sphere lit
    # from above however the scene is lit.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var skin = assets.materials.add(matcap_material())
    var scene = lamp_scene()
    var shown = rendered(
        renderer, scene, assets, ball_of(assets, skin), camera_at(0, 0, 4)
    )
    var top = shown.get_pixel(WIDTH // 2, HEIGHT // 2 - 4)
    var bottom = shown.get_pixel(WIDTH // 2, HEIGHT // 2 + 4)
    assert_true(top.r > bottom.r, "the gradient did not rise up the sphere")
    assert_true(bottom.r > 0, "the bottom of the gradient reached black")


def test_a_material_naming_a_matcap_that_is_not_there_is_rejected() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var skin = assets.materials.add(matcap_material(TextureId(3)))
    var scene = lamp_scene()
    with assert_raises():
        _ = rendered(
            renderer, scene, assets, ball_of(assets, skin), camera_at(0, 0, 4)
        )


def test_a_matcap_must_ignore_its_alpha_in_the_renderer() raises:
    # Refused whatever the shading mode, as a wrong asset rather than a
    # wrong frame -- the rule the emissive map follows.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var pixels = List[UInt8]()
    for _ in range(2):
        pixels.append(255)
        pixels.append(255)
        pixels.append(255)
        pixels.append(128)
    var weighted = assets.textures.add(
        Texture(2, 1, pixels^, CLAMP, NEAREST, SRGB, False, COVERAGE)
    )
    var skin = assets.materials.add(matcap_material(weighted))
    var scene = lamp_scene()
    with assert_raises():
        _ = rendered(
            renderer, scene, assets, ball_of(assets, skin), camera_at(0, 0, 4)
        )


# --- two output representations cannot share a tone-mapped frame ------------


def mixed_scene(mut assets: Assets, blending: Blending) raises -> List[Mesh]:
    """Return a normal-material sheet and a second sheet of ordinary light
    drawn with `blending`."""
    var sheet = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(sheet, assets.materials.add(normal_material()), NodeId(0))
    )
    meshes.append(
        Mesh(
            sheet,
            assets.materials.add(
                Material(Color(200, 60, 60), blending=blending)
            ),
            NodeId(0),
        )
    )
    return meshes^


def test_a_tone_mapped_frame_refuses_data_beside_a_blended_surface() raises:
    # A blended fragment resolves its pixel as light however faint it is,
    # so it decides the curve for a normal behind it at an alpha too small
    # to move a single channel. No per-pixel rule makes that continuous, so
    # the frame is refused. See `check_output_kinds`.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    renderer.set_tone_mapping(REINHARD_TONE_MAPPING)
    var assets = Assets()
    var scene = lamp_scene()
    with assert_raises():
        _ = rendered(
            renderer,
            scene,
            assets,
            mixed_scene(assets, BLEND),
            camera_at(0, 0, 4),
        )
    # Opaque light beside data is fine: nothing mixes the two.
    var plain = Assets()
    _ = rendered(
        renderer, scene, plain, mixed_scene(plain, OPAQUE), camera_at(0, 0, 4)
    )
    # And with no curve there is nothing to decide, so the blended frame
    # draws. That is what makes the refusal about the curve.
    var off = Renderer(WIDTH, HEIGHT)
    off.set_background(Color(0, 0, 0))
    var third = Assets()
    _ = rendered(
        off, scene, third, mixed_scene(third, BLEND), camera_at(0, 0, 4)
    )


def test_the_uv_view_is_data_throughout_and_is_never_refused() raises:
    # Every pixel of it is coordinates, and it is never tone mapped, so the
    # mixture the refusal guards against cannot arise.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    renderer.set_tone_mapping(REINHARD_TONE_MAPPING)
    renderer.set_shading(SHADE_UV)
    var assets = Assets()
    var scene = lamp_scene()
    _ = rendered(
        renderer, scene, assets, mixed_scene(assets, BLEND), camera_at(0, 0, 4)
    )


# --- standard and physical materials, normal and bump maps -------------------


def a_data_texel(r: UInt8, g: UInt8, b: UInt8) raises -> Texture:
    """Return a one-texel map stored as data: linear, alpha ignored."""
    var pixels = List[UInt8]()
    pixels.append(r)
    pixels.append(g)
    pixels.append(b)
    pixels.append(255)
    return Texture(1, 1, pixels^, REPEAT, NEAREST, LINEAR, False, IGNORED)


def a_split_sky() raises -> CubeTexture:
    """Return a cube whose every face is black on the left and white on
    the right, with a chain, so a rough reflection reads gray."""
    var faces = List[Texture]()
    for _ in range(6):
        var pixels = List[UInt8]()
        for _ in range(2):
            for value in [0, 255]:
                pixels.append(UInt8(value))
                pixels.append(UInt8(value))
                pixels.append(UInt8(value))
                pixels.append(255)
        faces.append(Texture(2, 2, pixels^, CLAMP, NEAREST, SRGB))
    return CubeTexture(faces^)


def lamp_from_x_scene() raises -> Scene:
    """Return a scene with a node at the origin and one white lamp far
    along +x and a little toward the camera, so a sheet facing the camera
    is lit at a grazing angle from its own +u side."""
    var scene = Scene()
    _ = scene.add(Object3D())
    var lamp = Object3D()
    lamp.set_position(1, 0, 0.15)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, FULL))
    scene.update()
    return scene^


def sum_red(image: Framebuffer) raises -> Int:
    """Return the sum of every pixel's red."""
    var total = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            total += Int(image.get_pixel(x, y).r)
    return total


def test_a_standard_sheet_scatters_and_a_metal_one_reflects() raises:
    # Under one lamp straight on, a white chalk sheet is lit white; a red
    # metal sheet scatters nothing and shows a quarter of red from its
    # lobe; and a physical sheet at its defaults is the standard one.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var chalk = assets.materials.add(standard_material(Color(255, 255, 255)))
    var metal = assets.materials.add(
        standard_material(Color(255, 0, 0), metalness=1.0)
    )
    var physical = assets.materials.add(physical_material(Color(255, 255, 255)))
    var scene = lamp_scene()
    var white = rendered(
        renderer, scene, assets, sheet_of(assets, chalk), camera_at(0, 0, 4)
    )
    var center = white.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(center.r, UInt8(255))
    var red = rendered(
        renderer, scene, assets, sheet_of(assets, metal), camera_at(0, 0, 4)
    )
    var spot = red.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_true(spot.r > 100, "the metal's lobe did not show")
    assert_true(spot.r < 200, "the metal scattered like chalk")
    assert_equal(spot.g, UInt8(0))
    var same = rendered(
        renderer, scene, assets, sheet_of(assets, physical), camera_at(0, 0, 4)
    )
    assert_equal(same.get_pixel(WIDTH // 2, HEIGHT // 2).r, center.r)
    # A coat over the black sheet glosses it.
    var coated = assets.materials.add(
        physical_material(Color(0, 0, 0), clearcoat=1.0)
    )
    var glossed = rendered(
        renderer, scene, assets, sheet_of(assets, coated), camera_at(0, 0, 4)
    )
    var bare = assets.materials.add(physical_material(Color(0, 0, 0)))
    var dull = rendered(
        renderer, scene, assets, sheet_of(assets, bare), camera_at(0, 0, 4)
    )
    assert_true(sum_red(glossed) > sum_red(dull), "the coat added no gloss")
    # Lit shading shades a physical surface too.
    renderer.set_shading(SHADE_LIT)
    var lit = rendered(
        renderer, scene, assets, sheet_of(assets, metal), camera_at(0, 0, 4)
    )
    assert_equal(lit.get_pixel(WIDTH // 2, HEIGHT // 2).r, spot.r)


def test_a_physical_sheet_reflects_the_environment_by_its_roughness() raises:
    # A smooth metal sheet square on reflects the +z face sharply: black
    # or white, whichever half the view lands on. A rough one reads the
    # coarsest level, which is the average, gray.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var sky = assets.cube_textures.add(a_split_sky())
    var smooth = assets.materials.add(
        standard_material(
            Color(255, 255, 255), roughness=0.0, metalness=1.0, env_map=sky
        )
    )
    var rough = assets.materials.add(
        standard_material(
            Color(255, 255, 255),
            roughness=1.0,
            metalness=1.0,
            env_map=SCENE_ENVIRONMENT,
        )
    )
    var scene = scene_with_node_at(0)
    scene.environment = sky
    var sharp = rendered(
        renderer, scene, assets, sheet_of(assets, smooth), camera_at(0, 0, 4)
    )
    var blurred = rendered(
        renderer, scene, assets, sheet_of(assets, rough), camera_at(0, 0, 4)
    )
    var soft = blurred.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_true(soft.r > 40, "a rough metal lost the sky")
    assert_true(soft.r < 220, "a rough metal reflected one half alone")
    assert_equal(soft.r, soft.g)
    # The sharp sheet shows both halves somewhere and no gray between.
    var lows = 0
    var highs = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var seen = sharp.get_pixel(x, y).r
            if seen > 220:
                highs += 1
            elif seen < 40:
                lows += 1
    assert_true(highs > 0, "the smooth metal reflected no white")
    assert_true(lows + highs > WIDTH * HEIGHT // 2, "the smooth metal blurred")
    # A dielectric under the same sky scatters its irradiance, so it is
    # lit with no lamp at all.
    var chalk = assets.materials.add(
        standard_material(Color(255, 255, 255), env_map=sky)
    )
    var glow = rendered(
        renderer, scene, assets, sheet_of(assets, chalk), camera_at(0, 0, 4)
    )
    assert_true(
        glow.get_pixel(WIDTH // 2, HEIGHT // 2).r > 40,
        "a white surface under a sky went dark",
    )


def test_a_normal_map_and_a_bump_map_perturb_a_sheet_in_the_renderer() raises:
    # Lit from far along +x, a flat sheet catches little. A one-texel
    # normal map pointing along +u, which the plane lays along +x, tilts
    # every normal toward the lamp and the sheet brightens.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var toward_u = assets.textures.add(a_data_texel(255, 128, 128))
    var flat = assets.materials.add(Material(Color(255, 255, 255)))
    var mapped = assets.materials.add(
        Material(Color(255, 255, 255), normal_map=toward_u)
    )
    var scene = lamp_from_x_scene()
    var plain = rendered(
        renderer, scene, assets, sheet_of(assets, flat), camera_at(0, 0, 4)
    )
    var tilted = rendered(
        renderer, scene, assets, sheet_of(assets, mapped), camera_at(0, 0, 4)
    )
    assert_true(sum_red(tilted) > sum_red(plain) * 2, "the map did not tilt")
    # A bump map whose height rises along +u tilts against the rise, away
    # from the lamp, and the sheet darkens where the height changes.
    var pixels = List[UInt8]()
    for value in [0, 255]:
        pixels.append(UInt8(value))
        pixels.append(UInt8(value))
        pixels.append(UInt8(value))
        pixels.append(255)
    var step = assets.textures.add(
        Texture(2, 1, pixels^, CLAMP, NEAREST, LINEAR, False, IGNORED)
    )
    var bumped = assets.materials.add(
        Material(Color(255, 255, 255), bump_map=step, bump_scale=0.2)
    )
    var ridged = rendered(
        renderer, scene, assets, sheet_of(assets, bumped), camera_at(0, 0, 4)
    )
    assert_true(sum_red(ridged) < sum_red(plain), "the bump did not tilt")
    # Neither is read under lit shading.
    renderer.set_shading(SHADE_LIT)
    var unread = rendered(
        renderer, scene, assets, sheet_of(assets, mapped), camera_at(0, 0, 4)
    )
    assert_equal(sum_red(unread), sum_red(plain))


def test_a_turned_corner_keeps_its_env_map_and_turns_its_frame() raises:
    # A two-sided mirror seen from behind still reflects: the -z face,
    # magenta. Its back once lost the env map on the way through
    # `_turned_around` and drew plain white.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var faces = List[Texture]()
    for color in [
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 255, 0),
        Color(0, 255, 255),
        Color(255, 0, 255),
    ]:
        var pixels = List[UInt8]()
        for _ in range(4):
            pixels.append(color.r)
            pixels.append(color.g)
            pixels.append(color.b)
            pixels.append(255)
        faces.append(Texture(2, 2, pixels^, CLAMP, NEAREST, SRGB, False))
    var sky = assets.cube_textures.add(CubeTexture(faces^))
    var mirror = assets.materials.add(
        Material(
            Color(255, 255, 255), kind=BASIC, side=DOUBLE_SIDE, env_map=sky
        )
    )
    var scene = scene_with_node_at(0)
    var behind = rendered(
        renderer, scene, assets, sheet_of(assets, mirror), camera_at(0, 0, -4)
    )
    var seen = behind.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(seen.r, UInt8(255))
    assert_equal(seen.g, UInt8(0))
    assert_equal(seen.b, UInt8(255))
    # And a normal map on a two-sided sheet seen from behind tilts the far
    # side's normal the far side's way: the map points along +u, the lamp
    # is on the +x side of the camera behind the sheet, and the back's
    # frame is the front's negated, so the back tilts away and darkens.
    var toward_u = assets.textures.add(a_data_texel(255, 128, 128))
    var flat = assets.materials.add(
        Material(Color(255, 255, 255), side=DOUBLE_SIDE)
    )
    var mapped = assets.materials.add(
        Material(Color(255, 255, 255), side=DOUBLE_SIDE, normal_map=toward_u)
    )
    var lit = Scene()
    _ = lit.add(Object3D())
    var lamp = Object3D()
    lamp.set_position(1, 0, -0.15)
    var node = lit.add(lamp^)
    lit.add_light(directional_light(Color(255, 255, 255), node, FULL))
    lit.update()
    var plain = rendered(
        renderer, lit, assets, sheet_of(assets, flat), camera_at(0, 0, -4)
    )
    var turned = rendered(
        renderer, lit, assets, sheet_of(assets, mapped), camera_at(0, 0, -4)
    )
    assert_true(sum_red(plain) > 0, "the back of the sheet was unlit")
    assert_true(sum_red(turned) < sum_red(plain), "the back tilted toward")
    # From the front the same map tilts toward a lamp on the +x side.
    var front = Scene()
    _ = front.add(Object3D())
    var lamp_front = Object3D()
    lamp_front.set_position(1, 0, 0.15)
    var front_node = front.add(lamp_front^)
    front.add_light(directional_light(Color(255, 255, 255), front_node, FULL))
    front.update()
    var facing = rendered(
        renderer, front, assets, sheet_of(assets, mapped), camera_at(0, 0, 4)
    )
    var facing_flat = rendered(
        renderer, front, assets, sheet_of(assets, flat), camera_at(0, 0, 4)
    )
    assert_true(sum_red(facing) > sum_red(facing_flat), "the front tilted away")


def test_a_data_map_must_be_there_and_stored_as_data_in_the_renderer() raises:
    # Each of the four maps: an id naming nothing, a texture encoded as
    # color, and one that reads its alpha as coverage, refused whatever
    # the shading mode. A wrong asset, not a wrong frame.
    var assets = Assets()
    var pixels = List[UInt8]()
    for value in [128, 128, 255, 255]:
        pixels.append(UInt8(value))
    var encoded = assets.textures.add(
        Texture(1, 1, pixels.copy(), REPEAT, NEAREST, SRGB, False, IGNORED)
    )
    var covered = assets.textures.add(
        Texture(1, 1, pixels^, REPEAT, NEAREST, LINEAR, False, COVERAGE)
    )
    var scene = scene_with_node_at(0)
    for slot in [encoded, covered, TextureId(9)]:
        var wrongs = List[MaterialId]()
        wrongs.append(
            assets.materials.add(
                standard_material(Color(255, 255, 255), roughness_map=slot)
            )
        )
        wrongs.append(
            assets.materials.add(
                standard_material(Color(255, 255, 255), metalness_map=slot)
            )
        )
        wrongs.append(
            assets.materials.add(
                Material(Color(255, 255, 255), normal_map=slot)
            )
        )
        wrongs.append(
            assets.materials.add(Material(Color(255, 255, 255), bump_map=slot))
        )
        for index in range(len(wrongs)):
            var meshes = sheet_of(assets, wrongs[index])
            for mode in [SHADE_TEXTURE, SHADE_LIT]:
                var renderer = Renderer(WIDTH, HEIGHT)
                renderer.set_shading(mode)
                with assert_raises():
                    _ = rendered(
                        renderer, scene, assets, meshes, camera_at(0, 0, 4)
                    )
    # A map stored as data draws.
    var proper = assets.textures.add(a_data_texel(128, 128, 255))
    var fine = assets.materials.add(
        standard_material(
            Color(255, 255, 255),
            roughness_map=proper,
            metalness_map=proper,
            normal_map=proper,
        )
    )
    var renderer = Renderer(WIDTH, HEIGHT)
    _ = rendered(
        renderer, scene, assets, sheet_of(assets, fine), camera_at(0, 0, 4)
    )
    # And every map on one material must share one transform, the normal
    # map included.
    var moved = a_data_texel(128, 128, 255)
    moved.repeat = Vector2(2, 2)
    var shifted = assets.textures.add(moved^)
    var disagreeing = assets.materials.add(
        Material(Color(255, 255, 255), proper, normal_map=shifted)
    )
    with assert_raises():
        _ = rendered(
            renderer,
            scene,
            assets,
            sheet_of(assets, disagreeing),
            camera_at(0, 0, 4),
        )


# --- shadows ----------------------------------------------------------------


def shadow_scene(
    mut assets: Assets,
    cast: Bool,
    receive: Bool,
    light: String,
    catcher: Bool = False,
    bias: Float32 = -0.002,
) raises -> Scene:
    """Return a scene with a floor at the origin and a block a meter above
    it under one white light straight above: a `"sun"`, a `"beam"`, a
    `"dark sun"` that casts nothing, a point light `"bulb"` that casts, a
    `"slide"` spot light that projects a red map and casts nothing, or
    `"none"`. The block casts or not,
    the floor receives or not, and is drawn with a shadow material when
    `catcher`."""
    var scene = Scene()
    var ground = Object3D()
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var ground_node = scene.add(ground^)
    var lift = Object3D()
    lift.set_position(0, 1.0, 0)
    var lift_node = scene.add(lift^)
    var floor = assets.geometries.add(
        plane(Length(6.0, METER), Length(6.0, METER))
    )
    var block = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    if catcher:
        paint = assets.materials.add(shadow_material())
    var red = assets.materials.add(Material(Color(200, 60, 60)))
    scene.add_mesh(Mesh(floor, paint, ground_node, receive_shadow=receive))
    scene.add_mesh(Mesh(block, red, lift_node, cast_shadow=cast))
    if light != "none":
        var lamp = Object3D()
        lamp.set_position(-3, 4, 0)
        var node = scene.add(lamp^)
        if light == "beam" or light == "slide":
            var beam = spot_light(
                Color(255, 255, 255), node, 16 * FULL, angle=Angle(50.0, DEGREE)
            )
            beam.cast_shadow = light == "beam"
            beam.shadow.map_size = 64
            beam.shadow.bias = bias
            if light == "slide":
                beam.map = assets.textures.add(
                    texture_of(Framebuffer(2, 2, Color(255, 0, 0)))
                )
            scene.add_light(beam)
        elif light == "bulb":
            var bulb = point_light(Color(255, 255, 255), node, 25 * FULL)
            bulb.cast_shadow = True
            bulb.shadow.map_size = 64
            bulb.shadow.bias = bias
            scene.add_light(bulb)
        else:
            var sun = directional_light(Color(255, 255, 255), node, FULL)
            sun.cast_shadow = light == "sun"
            sun.shadow.map_size = 64
            sun.shadow.bias = bias
            scene.add_light(sun)
    scene.update()
    return scene^


def floor_under_and_beside(image: Framebuffer) raises -> Tuple[UInt8, UInt8]:
    """Return the red of the floor just beside the block on the side away
    from the light, where its shadow falls, and the red of the floor well
    away from it, seen from above and in front."""
    return (
        image.get_pixel(WIDTH * 5 // 8, HEIGHT // 2 - 1).r,
        image.get_pixel(WIDTH // 8, HEIGHT * 3 // 4).r,
    )


def test_a_block_casts_a_shadow_on_the_floor_under_it() raises:
    # Seen from above and a little in front, the floor straight under the
    # block is dark and the floor beside it is lit; without the light
    # casting, without the block casting, or without the floor receiving,
    # the two are alike.
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var camera = camera_at(0, 6, 3)
    var scene = shadow_scene(assets, True, True, "sun")
    var seen = floor_under_and_beside(renderer.render(scene, assets, camera))
    assert_true(seen[1] > 150, "the floor beside the block was dark")
    assert_true(Int(seen[0]) + 100 < Int(seen[1]), "no shadow fell")
    # The shadow maps are what render_into drew, one per casting light.
    var maps = renderer.shadow_maps(scene, assets)
    assert_equal(len(maps), 1)
    assert_equal(maps[0].size, 64)
    assert_equal(maps[0].light, 0)
    var no_cast = shadow_scene(assets, False, True, "sun")
    var unshadowed = floor_under_and_beside(
        renderer.render(no_cast, assets, camera)
    )
    assert_equal(unshadowed[0], unshadowed[1])
    var no_receive = shadow_scene(assets, True, False, "sun")
    var ignored = floor_under_and_beside(
        renderer.render(no_receive, assets, camera)
    )
    assert_equal(ignored[0], ignored[1])
    var dark_sun = shadow_scene(assets, True, True, "dark sun")
    var plain = floor_under_and_beside(
        renderer.render(dark_sun, assets, camera)
    )
    assert_equal(plain[0], plain[1])
    assert_equal(len(renderer.shadow_maps(dark_sun, assets)), 0)


def test_every_shadow_map_type_casts_the_blocks_shadow() raises:
    # three.js's `shadowMap.type`, from every kind of light: each draws
    # the shadow, and each map carries the type it is read with.
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    assert_true(renderer.shadow_map_type == PCF_SHADOW_MAP)
    for kind in [
        BASIC_SHADOW_MAP,
        PCF_SHADOW_MAP,
        PCF_SOFT_SHADOW_MAP,
        VSM_SHADOW_MAP,
    ]:
        renderer.shadow_map_type = kind
        for light in ["sun", "beam", "bulb"]:
            var scene = shadow_scene(assets, True, True, light)
            var seen = floor_under_and_beside(
                renderer.render(scene, assets, camera_at(0, 6, 3))
            )
            assert_true(seen[1] > 100, "the floor beside the block was dark")
            assert_true(Int(seen[0]) + 60 < Int(seen[1]), "no shadow fell")
            var maps = renderer.shadow_maps(scene, assets)
            assert_true(maps[0].shadow_type == kind)
    # A variance map keeps two squares; a point light's cube stays six.
    renderer.shadow_map_type = VSM_SHADOW_MAP
    var sun = shadow_scene(assets, True, True, "sun")
    assert_equal(len(renderer.shadow_maps(sun, assets)[0].depths), 2 * 64 * 64)
    var bulb = shadow_scene(assets, True, True, "bulb")
    assert_equal(len(renderer.shadow_maps(bulb, assets)[0].depths), 6 * 64 * 64)
    # A type that is none of the four is refused before a map is drawn.
    renderer.shadow_map_type = ShadowMapType(4)
    with assert_raises():
        _ = renderer.shadow_maps(sun, assets)
    with assert_raises():
        _ = renderer.render(sun, assets, camera_at(0, 6, 3))


def test_a_variance_map_draws_the_meshes_that_receive() raises:
    # three.js draws every receiver into a variance map: the floor, which
    # receives and does not cast, fills the map under `VSM_SHADOW_MAP`
    # and leaves it empty under the others.
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = shadow_scene(assets, False, True, "sun")
    var middle = 32 * 64 + 32
    var empty = renderer.shadow_maps(scene, assets)[0].depths.copy()
    assert_true(empty[middle] > 1, "a receiver was drawn into a PCF map")
    renderer.shadow_map_type = VSM_SHADOW_MAP
    var full = renderer.shadow_maps(scene, assets)[0].depths.copy()
    assert_true(full[middle] < 1, "the receiver was not drawn")
    # And into a point light's cube as well.
    var lit = shadow_scene(assets, False, True, "bulb")
    var cube = renderer.shadow_maps(lit, assets)[0].depths.copy()
    var drawn = 0
    for texel in range(len(cube)):
        if cube[texel] < 1:
            drawn += 1
    assert_true(drawn > 0, "the receiver was not drawn into the cube")
    # The floor does not shadow itself.
    var seen = floor_under_and_beside(
        renderer.render(scene, assets, camera_at(0, 6, 3))
    )
    assert_equal(seen[0], seen[1])


def test_a_spot_light_casts_a_shadow_through_its_own_camera() raises:
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var scene = shadow_scene(assets, True, True, "beam")
    var seen = floor_under_and_beside(
        renderer.render(scene, assets, camera_at(0, 6, 3))
    )
    assert_true(seen[1] > 100, "the floor beside the block was dark")
    assert_true(Int(seen[0]) + 60 < Int(seen[1]), "no shadow fell")


def test_a_point_light_casts_a_shadow_through_six_faces() raises:
    # The bulb sits where the sun did, and the block's shadow falls on the
    # floor on its far side, drawn into the cube's six faces.
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var scene = shadow_scene(assets, True, True, "bulb")
    var seen = floor_under_and_beside(
        renderer.render(scene, assets, camera_at(0, 6, 3))
    )
    assert_true(seen[1] > 100, "the floor beside the block was dark")
    assert_true(Int(seen[0]) + 60 < Int(seen[1]), "no shadow fell")
    var maps = renderer.shadow_maps(scene, assets)
    assert_equal(len(maps), 1)
    assert_true(maps[0].cube)
    assert_equal(len(maps[0].depths), 6 * 64 * 64)
    assert_equal(maps[0].origin.y, Float32(4))
    assert_equal(maps[0].far, Float32(500))
    # A distance moves the far plane there; the block casts nothing
    # without casting, and a bulb on its node's origin needs no target.
    scene.lights[0].distance = 30
    assert_equal(renderer.shadow_maps(scene, assets)[0].far, Float32(30))
    var no_cast = shadow_scene(assets, False, True, "bulb")
    var plain = floor_under_and_beside(
        renderer.render(no_cast, assets, camera_at(0, 6, 3))
    )
    assert_true(Int(seen[0]) + 60 < Int(plain[0]), "the shadow did not lift")


def test_a_spot_light_projects_its_map_on_what_it_lights() raises:
    # A red picture turns the white beam red where it lands: the floor
    # keeps its red and loses its green.
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var scene = shadow_scene(assets, True, True, "slide")
    var image = renderer.render(scene, assets, camera_at(0, 6, 3))
    var floor = image.get_pixel(WIDTH // 8, HEIGHT * 3 // 4)
    assert_true(floor.r > 100, "the red beam lit nothing")
    assert_equal(floor.g, UInt8(0))
    var maps = renderer.spot_light_maps(scene, assets)
    assert_equal(len(maps), 1)
    assert_equal(maps[0].light, 0)
    assert_equal(maps[0].normal_bias, Float32(0))
    # When the light casts as well, its normal bias moves the surface
    # before it is projected, as it does for the shadow.
    scene.lights[0].cast_shadow = True
    scene.lights[0].shadow.normal_bias = 0.25
    assert_equal(
        renderer.spot_light_maps(scene, assets)[0].normal_bias, Float32(0.25)
    )
    # Without its map the beam is white.
    scene.lights[0].map = NO_TEXTURE
    var white = renderer.render(scene, assets, camera_at(0, 6, 3))
    assert_true(white.get_pixel(WIDTH // 8, HEIGHT * 3 // 4).g > 100)
    assert_equal(len(renderer.spot_light_maps(scene, assets)), 0)


def test_a_spot_light_map_follows_the_layers_and_is_checked() raises:
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = shadow_scene(assets, True, True, "slide")
    var aside = Layers()
    aside.set(3)
    scene.lights[0].layers = aside
    assert_equal(len(renderer.spot_light_maps(scene, assets, Layers())), 0)
    scene.lights[0].layers = Layers()
    # A hidden light projects nothing.
    scene.node(NodeId(2)).visible = False
    scene.update()
    assert_equal(len(renderer.spot_light_maps(scene, assets)), 0)
    scene.node(NodeId(2)).visible = True
    scene.update()
    # A map that is not in the store, or a light on its own target, is
    # refused.
    scene.lights[0].map = TextureId(9)
    with assert_raises():
        _ = renderer.spot_light_maps(scene, assets)
    scene.lights[0].map = TextureId(0)
    scene.lights[0].target = NodeId(2)
    with assert_raises():
        _ = renderer.spot_light_maps(scene, assets)


def test_a_rectangle_of_light_lights_a_standard_sheet_through_the_tables() raises:
    # A two-meter square one meter over a white chalk sheet, seen head on:
    # the sheet takes the square's form factor, about 0.554 of white,
    # once the renderer holds the tables; without them the render is
    # refused; and a lambert sheet is not lit by it at all.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var chalk = assets.materials.add(standard_material(Color(255, 255, 255)))
    var plain = assets.materials.add(Material(Color(255, 255, 255)))
    var scene = Scene()
    _ = scene.add(Object3D())
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(
        rect_area_light(
            Color(255, 255, 255),
            node,
            1.0,
            Length(2.0, METER),
            Length(2.0, METER),
        )
    )
    scene.update()
    assert_false(renderer.ltc_tables().is_loaded())
    with assert_raises():
        _ = rendered(
            renderer, scene, assets, sheet_of(assets, chalk), camera_at(0, 0, 4)
        )
    renderer.set_ltc_tables(load_ltc_tables())
    assert_true(renderer.ltc_tables().is_loaded())
    var lit = rendered(
        renderer, scene, assets, sheet_of(assets, chalk), camera_at(0, 0, 4)
    )
    var center = lit.get_pixel(WIDTH // 2, HEIGHT // 2)
    # 0.554 linear is 195 in sRGB, and the lobe adds a little.
    assert_true(center.r > 190, "the rectangle lit the sheet too little")
    assert_true(center.r < 215, "the rectangle lit the sheet too much")
    assert_equal(center.r, center.b)
    var unlit = rendered(
        renderer, scene, assets, sheet_of(assets, plain), camera_at(0, 0, 4)
    )
    assert_equal(unlit.get_pixel(WIDTH // 2, HEIGHT // 2).r, UInt8(0))
    # The tables can be taken away again.
    renderer.set_ltc_tables(LtcTables())
    with assert_raises():
        _ = rendered(
            renderer, scene, assets, sheet_of(assets, chalk), camera_at(0, 0, 4)
        )


def test_a_shadow_material_catches_the_shadow_and_nothing_else() raises:
    # Over a white background, a shadow material floor is invisible
    # except where the block's shadow falls, which is black.
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(255, 255, 255))
    var scene = shadow_scene(assets, True, True, "sun", True)
    var seen = floor_under_and_beside(
        renderer.render(scene, assets, camera_at(0, 6, 3))
    )
    assert_equal(seen[1], UInt8(255))
    assert_true(seen[0] < 100, "the shadow material caught nothing")
    # With no shadow to catch it shows nothing at all.
    var quiet = shadow_scene(assets, True, True, "dark sun", True)
    var empty = floor_under_and_beside(
        renderer.render(quiet, assets, camera_at(0, 6, 3))
    )
    assert_equal(empty[0], UInt8(255))


def test_a_shadow_is_drawn_under_lit_shading_and_follows_the_layers() raises:
    # Lit shading casts and receives as textured shading does: a shadow is
    # not a texture. And a light on a layer the camera does not watch draws
    # no map.
    var assets = Assets()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    renderer.set_shading(SHADE_LIT)
    var scene = shadow_scene(assets, True, True, "sun")
    var lit = floor_under_and_beside(
        renderer.render(scene, assets, camera_at(0, 6, 3))
    )
    assert_true(Int(lit[0]) + 100 < Int(lit[1]), "no shadow under lit shading")
    var aside = Layers()
    aside.set(3)
    scene.lights[0].layers = aside
    assert_equal(len(renderer.shadow_maps(scene, assets, Layers())), 0)
    assert_equal(len(renderer.shadow_maps(scene, assets)), 1)


def test_a_casting_light_on_its_target_is_refused() raises:
    var assets = Assets()
    var scene = shadow_scene(assets, True, True, "none")
    var sun = directional_light(Color(255, 255, 255), NodeId(0), FULL)
    sun.cast_shadow = True
    scene.add_light(sun)
    scene.update()
    var renderer = Renderer(WIDTH, HEIGHT)
    with assert_raises():
        _ = renderer.shadow_maps(scene, assets)
    with assert_raises():
        _ = renderer.render(scene, assets, camera_at(0, 6, 3))
    # Aimed at a target node it sits on, the same.
    scene.lights[0] = directional_light(
        Color(255, 255, 255), NodeId(1), FULL, target=NodeId(1)
    )
    scene.lights[0].cast_shadow = True
    with assert_raises():
        _ = renderer.shadow_maps(scene, assets)
    # Aimed at a target node it does not sit on, a map is drawn, from the
    # block's node down at the floor's.
    scene.lights[0] = directional_light(
        Color(255, 255, 255), NodeId(1), FULL, target=NodeId(0)
    )
    scene.lights[0].cast_shadow = True
    assert_equal(len(renderer.shadow_maps(scene, assets)), 1)


def test_only_meshes_cast_shadows_yet() raises:
    # A skinned, instanced or batched mesh, an LOD and a sprite are left
    # out of a light's view: the map holds the block alone, the same map
    # the scene draws without them.
    var assets = Assets()
    var scene = shadow_scene(assets, True, True, "sun")
    var renderer = Renderer(WIDTH, HEIGHT)
    var alone = renderer.shadow_maps(scene, assets)
    var block = scene.meshes[1].geometry
    var red = scene.meshes[1].material
    var lift = scene.meshes[1].node
    scene.add_instanced_mesh(InstancedMesh(block, red, lift, 3))
    var batch = BatchedMesh(red, lift)
    _ = batch.add_instance(block)
    scene.add_batched_mesh(batch^)
    var lod = Lod(lift)
    lod.add_level(block, red)
    scene.add_lod(lod^)
    scene.add_sprite(Sprite(red, lift))
    scene.add_skinned_mesh(
        SkinnedMesh(block, red, lift, Skeleton([Bone(lift, Matrix4())]))
    )
    scene.update()
    var crowded = renderer.shadow_maps(scene, assets)
    assert_equal(len(crowded), 1)
    for texel in range(len(alone[0].depths)):
        assert_equal(crowded[0].depths[texel], alone[0].depths[texel])


# --- ambient occlusion and light maps ---------------------------------------


def two_channel_triangle(with_second: Bool = True) raises -> BufferGeometry:
    """Return one triangle whose first coordinates run over the unit
    square and whose second, when asked for, run from two to three."""
    var triangle = BufferGeometry()
    var data: List[Float32] = [-1, -1, 0, 1, -1, 0, 0, 1, 0]
    triangle.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    var first: List[Float32] = [0, 0, 1, 0, 0, 1]
    triangle.set_attribute(String(UV), BufferAttribute(first^, 2))
    if with_second:
        var second: List[Float32] = [2, 2, 3, 2, 2, 3]
        triangle.set_attribute(String(UV1), BufferAttribute(second^, 2))
    return triangle^


def second_span(corners: List[RasterVertex]) -> Tuple[Float32, Float32]:
    """Return the least and the most `u1` the prepared corners carry."""
    var least = corners[0].u1
    var most = corners[0].u1
    for index in range(len(corners)):
        least = min(least, corners[index].u1)
        most = max(most, corners[index].u1)
    return (least, most)


def prepared_with(
    renderer: Renderer,
    mut assets: Assets,
    geometry: GeometryId,
    material: Material,
) raises -> List[RasterVertex]:
    """Return what `prepare` makes of one mesh drawn with `material`."""
    var scene = unlit_scene_with_a_node()
    var skin = assets.materials.add(material)
    scene.add_mesh(Mesh(geometry, skin, NodeId(0)))
    return renderer.prepare(scene, assets, a_camera())


def test_the_baked_maps_ride_a_second_coordinate_pair() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var both = assets.geometries.add(two_channel_triangle())
    var one = assets.geometries.add(two_channel_triangle(False))
    var first_map = a_data_texel(255, 255, 255)
    var second_map = a_data_texel(128, 128, 128)
    second_map.channel = UV_CHANNEL_1
    var on_first = assets.textures.add(first_map^)
    var on_second = assets.textures.add(second_map^)
    # The first channel reads `uv`, as three.js's default does.
    var plain = prepared_with(
        renderer, assets, both, Material(Color(255, 255, 255), ao_map=on_first)
    )
    assert_equal(len(plain), 3)
    var span = second_span(plain)
    assert_almost_equal(span[0], Float32(0), atol=1e-5)
    assert_almost_equal(span[1], Float32(1), atol=1e-5)
    # The second reads `uv1`, and each corner names both maps.
    var baked = prepared_with(
        renderer,
        assets,
        both,
        Material(
            Color(255, 255, 255),
            ao_map=on_second,
            ao_map_intensity=0.5,
            light_map=on_second,
            light_map_intensity=2,
        ),
    )
    span = second_span(baked)
    assert_almost_equal(span[0], Float32(2), atol=1e-5)
    assert_almost_equal(span[1], Float32(3), atol=1e-5)
    assert_equal(baked[0].ao_map, on_second)
    assert_equal(baked[0].light_map, on_second)
    assert_equal(baked[0].ao_map_intensity, Float32(0.5))
    assert_equal(baked[0].light_map_intensity, Float32(2))
    # A geometry with no `uv1` falls back to its `uv`.
    var fallen = prepared_with(
        renderer, assets, one, Material(Color(255, 255, 255), ao_map=on_second)
    )
    span = second_span(fallen)
    assert_almost_equal(span[1], Float32(1), atol=1e-5)
    # The pair has its own transform, apart from the base map's.
    var tiled_map = a_data_texel(128, 128, 128)
    tiled_map.channel = UV_CHANNEL_1
    tiled_map.repeat = Vector2(2, 2)
    var tiled = assets.textures.add(tiled_map^)
    var board = assets.textures.add(
        checkerboard(8, 4, Color(255, 255, 255), Color(0, 0, 0))
    )
    var apart = prepared_with(
        renderer,
        assets,
        both,
        Material(Color(255, 255, 255), board, light_map=tiled),
    )
    span = second_span(apart)
    assert_almost_equal(span[0], Float32(4), atol=1e-5)
    assert_almost_equal(span[1], Float32(6), atol=1e-5)
    assert_coordinates_span(apart, 0, 1, 0, 1)
    # Only textured shading opens either map; the coordinates still ride.
    renderer.set_shading(SHADE_LIT)
    var unopened = prepared_with(
        renderer, assets, both, Material(Color(255, 255, 255), ao_map=tiled)
    )
    assert_equal(unopened[0].ao_map, NO_TEXTURE)
    assert_equal(unopened[0].light_map, NO_TEXTURE)
    span = second_span(unopened)
    assert_almost_equal(span[1], Float32(6), atol=1e-5)


def test_a_baked_map_is_refused_where_it_cannot_be_read() raises:
    var assets = Assets()
    var sheet = assets.geometries.add(two_channel_triangle())
    var proper = assets.textures.add(a_data_texel(128, 128, 128))
    var moved_map = a_data_texel(128, 128, 128)
    moved_map.repeat = Vector2(2, 2)
    var moved = assets.textures.add(moved_map^)
    var second_map = a_data_texel(128, 128, 128)
    second_map.channel = UV_CHANNEL_1
    var second = assets.textures.add(second_map^)
    var odd_map = a_data_texel(128, 128, 128)
    odd_map.channel = UvChannel(5)
    var odd = assets.textures.add(odd_map^)
    var encoded = assets.textures.add(
        Texture(
            1,
            1,
            [UInt8(255), 255, 255, 255],
            REPEAT,
            NEAREST,
            SRGB,
            False,
            IGNORED,
        )
    )
    var covered = assets.textures.add(
        Texture(
            1, 1, [UInt8(255), 255, 255, 255], REPEAT, NEAREST, LINEAR, False
        )
    )
    var white = Color(255, 255, 255)
    var wrongs = List[Material]()
    var reasons = List[String]()
    # The two share a pair, so they share a transform and a channel.
    wrongs.append(Material(white, ao_map=proper, light_map=moved))
    reasons.append("share one transform and one channel")
    wrongs.append(Material(white, ao_map=proper, light_map=second))
    reasons.append("share one transform and one channel")
    # A channel that is neither is refused, and so is the second channel
    # on any other map.
    wrongs.append(Material(white, ao_map=odd))
    reasons.append("channel must be")
    wrongs.append(Material(white, second))
    reasons.append("Only an ao map or a light map")
    # A map that is not there, or not stored the way it is read.
    wrongs.append(Material(white, ao_map=TextureId(40)))
    reasons.append("An ao map is named")
    wrongs.append(Material(white, ao_map=encoded))
    reasons.append("An ao map holds data")
    wrongs.append(Material(white, light_map=TextureId(40)))
    reasons.append("A light map is named")
    wrongs.append(Material(white, light_map=covered))
    reasons.append("A light map must ignore")
    for mode in [SHADE_TEXTURE, SHADE_LIT]:
        var renderer = Renderer(WIDTH, HEIGHT)
        renderer.set_shading(mode)
        for index in range(len(wrongs)):
            with assert_raises(contains=reasons[index]):
                _ = prepared_with(renderer, assets, sheet, wrongs[index])
    # Two maps from one image agree, and a light map may hold sRGB light.
    var renderer = Renderer(WIDTH, HEIGHT)
    _ = prepared_with(
        renderer,
        assets,
        sheet,
        Material(white, ao_map=proper, light_map=proper),
    )
    _ = prepared_with(
        renderer, assets, sheet, Material(white, light_map=encoded)
    )


def test_lines_points_and_sprites_take_no_baked_map() raises:
    # None has an indirect term, so each pass refuses the material rather
    # than carrying a map it would never read.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var gray = assets.textures.add(a_data_texel(128, 128, 128))
    var scene = unlit_scene_with_a_node()
    var bare = BufferGeometry()
    bare.set_attribute(
        String(POSITION),
        BufferAttribute([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.5, 0.0], 3),
    )
    var shape = assets.geometries.add(bare^)
    var dashed = line_dashed_material(Color(255, 255, 255))
    dashed.ao_map = gray
    scene.add_line(Line(shape, assets.materials.add(dashed), NodeId(0)))
    with assert_raises(contains="A line material has no ao map"):
        _ = renderer.render(scene, assets, camera_at(0, 0, 4))
    scene.lines = List[Line]()
    var dots = points_material(Color(255, 255, 255))
    dots.light_map = gray
    scene.add_points(Points(shape, assets.materials.add(dots), NodeId(0)))
    with assert_raises(contains="A points material has no ao map"):
        _ = renderer.render(scene, assets, camera_at(0, 0, 4))
    scene.points = List[Points]()
    var badge = sprite_material()
    badge.ao_map = gray
    scene.add_sprite(Sprite(assets.materials.add(badge), NodeId(0)))
    with assert_raises(contains="A sprite has no ao map"):
        _ = renderer.render(scene, assets, camera_at(0, 0, 4))


def test_an_ao_map_darkens_a_sheet_under_the_ambient_light_alone() raises:
    # Under an ambient light and no lamp, all of a sheet's light is
    # indirect: a black ao map takes it all, and a light map adds its own.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var black = assets.textures.add(a_data_texel(0, 0, 0))
    var red = assets.textures.add(a_data_texel(255, 0, 0))
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.add_light(ambient_light(Color(255, 255, 255), FULL * 0.5))
    scene.update()
    var plain = rendered(
        renderer,
        scene,
        assets,
        sheet_of(assets, assets.materials.add(Material(Color(255, 255, 255)))),
        camera_at(0, 0, 4),
    )
    assert_true(sum_red(plain) > 0, "the ambient light lit nothing")
    var occluded = rendered(
        renderer,
        scene,
        assets,
        sheet_of(
            assets,
            assets.materials.add(Material(Color(255, 255, 255), ao_map=black)),
        ),
        camera_at(0, 0, 4),
    )
    assert_equal(sum_red(occluded), 0)
    var baked = rendered(
        renderer,
        scene,
        assets,
        sheet_of(
            assets,
            assets.materials.add(Material(Color(255, 255, 255), light_map=red)),
        ),
        camera_at(0, 0, 4),
    )
    assert_true(sum_red(baked) > sum_red(plain), "the light map added nothing")


# --- flat shading and specular maps -----------------------------------------


def without_normals(geometry: BufferGeometry) raises -> BufferGeometry:
    """Return `geometry`'s positions, coordinates and index, and no normal."""
    var bare = BufferGeometry()
    bare.set_attribute(
        String(POSITION), geometry.clone_attribute(String(POSITION))
    )
    bare.set_attribute(String(UV), geometry.clone_attribute(String(UV)))
    bare.set_index(geometry.index.copy())
    return bare^


def same_direction(a: Vector3, b: Vector3) -> Bool:
    """Return True if two vectors are equal to the bit."""
    return a.x == b.x and a.y == b.y and a.z == b.z


def turned_ball_scene() raises -> Scene:
    """Return a scene with a node turned so no face is square on, lit by
    `light_the`."""
    var scene = Scene()
    var turned = Object3D()
    turned.set_euler(
        Angle(30.0, DEGREE), Angle(40.0, DEGREE), Angle(0.0, DEGREE)
    )
    _ = scene.add(turned^)
    light_the(scene)
    scene.update()
    return scene^


def test_flat_shading_puts_one_normal_on_every_corner_of_a_face() raises:
    # three.js's `flatShading`: the face's own normal, so every fragment
    # of a triangle is lit alike. Smooth, the corners of a sphere's
    # triangles disagree.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(1.0, METER), 12, 8))
    var scene = turned_ball_scene()
    for flat in [True, False]:
        var meshes = List[Mesh]()
        meshes.append(
            Mesh(
                ball,
                assets.materials.add(
                    Material(Color(200, 200, 200), flat_shading=flat)
                ),
                NodeId(0),
            )
        )
        var corners = prepared(renderer, scene, assets, meshes, a_camera())
        assert_true(len(corners) > 0, "the ball prepared no triangles")
        var shared = 0
        for triangle in range(len(corners) // 3):  # pragma: no branch
            var first = corners[triangle * 3].normal
            var second = corners[triangle * 3 + 1].normal
            var third = corners[triangle * 3 + 2].normal
            if same_direction(first, second) and same_direction(first, third):
                shared += 1
        if flat:
            assert_equal(shared, len(corners) // 3)
        else:
            assert_true(shared < len(corners) // 3, "a smooth ball was flat")


def test_flat_shading_draws_as_a_geometry_without_normals_does() raises:
    # The face normal a geometry with no normals falls back to, on every
    # kind that reads a normal, and under a normal map: the flat ball and
    # the bare ball draw the same pixels, and the smooth ball does not.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var assets = Assets()
    var shape = sphere(Length(1.0, METER), 12, 8)
    var bare = assets.geometries.add(without_normals(shape))
    var ball = assets.geometries.add(shape^)
    var toward_u = assets.textures.add(a_data_texel(255, 128, 128))
    var white = Color(255, 255, 255)
    var scene = turned_ball_scene()
    var materials = List[Material]()
    materials.append(Material(white, kind=LAMBERT))
    materials.append(Material(white, kind=PHONG, specular=white))
    materials.append(Material(white, kind=TOON))
    materials.append(Material(white, kind=MATCAP))
    materials.append(Material(white, kind=STANDARD, roughness=0.4))
    materials.append(
        Material(white, kind=PHYSICAL, roughness=0.3, normal_map=toward_u)
    )
    materials.append(Material(white, kind=NORMALS))
    for index in range(len(materials)):
        var smooth = assets.materials.add(materials[index])
        var flat_material = materials[index]
        flat_material.flat_shading = True
        var flat = assets.materials.add(flat_material)
        # The smooth ball, the flat ball, and the bare ball.
        var images = List[Framebuffer]()
        for which in range(3):
            var meshes = List[Mesh]()
            meshes.append(
                Mesh(
                    bare if which == 2 else ball,
                    flat if which == 1 else smooth,
                    NodeId(0),
                )
            )
            images.append(rendered(renderer, scene, assets, meshes, a_camera()))
        var differ = 0
        for y in range(HEIGHT):
            for x in range(WIDTH):
                var one = images[1].get_pixel(x, y)
                var two = images[2].get_pixel(x, y)
                assert_equal(one.r, two.r)
                assert_equal(one.g, two.g)
                assert_equal(one.b, two.b)
                if images[0].get_pixel(x, y).r != one.r:
                    differ += 1
        assert_true(differ > 0, "flat shading changed nothing")


def test_a_specular_map_is_carried_checked_and_read_in_the_renderer() raises:
    var assets = Assets()
    var white = Color(255, 255, 255)
    var dull = assets.textures.add(a_data_texel(0, 0, 0))
    # A dark surface, so the lamp alone does not saturate the sheet.
    var dark = Color(40, 40, 40)
    var sheen = Color(120, 120, 120)
    var plain = assets.materials.add(
        Material(dark, kind=PHONG, specular=sheen, shininess=5.0)
    )
    var mapped = assets.materials.add(
        Material(
            dark, kind=PHONG, specular=sheen, shininess=5.0, specular_map=dull
        )
    )
    var scene = scene_with_node_at(0)
    light_the(scene)
    scene.update()
    # The corners carry the map under the mode that opens textures, and
    # not under lit shading.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var corners = prepared(
        renderer, scene, assets, sheet_of(assets, mapped), camera_at(0, 0, 4)
    )
    assert_equal(corners[0].specular_map, dull)
    # A map of no red takes the highlight away.
    var shiny = rendered(
        renderer, scene, assets, sheet_of(assets, plain), camera_at(0, 0, 4)
    )
    var matte = rendered(
        renderer, scene, assets, sheet_of(assets, mapped), camera_at(0, 0, 4)
    )
    assert_true(sum_red(matte) < sum_red(shiny), "the map kept the highlight")
    renderer.set_shading(SHADE_LIT)
    var unmapped = prepared(
        renderer, scene, assets, sheet_of(assets, mapped), camera_at(0, 0, 4)
    )
    assert_equal(unmapped[0].specular_map, NO_TEXTURE)
    # A map stored as color, and one that is not there, are refused under
    # either mode, and so is one whose transform the base map disagrees
    # with.
    var encoded = a_data_texel(255, 255, 255)
    encoded.color_space = SRGB
    var wrong = assets.textures.add(encoded^)
    var colored = assets.materials.add(
        Material(white, kind=PHONG, specular_map=wrong)
    )
    var absent = assets.materials.add(
        Material(white, kind=PHONG, specular_map=TextureId(99))
    )
    var moved = a_data_texel(255, 0, 0)
    moved.repeat = Vector2(2, 2)
    var shifted = assets.textures.add(moved^)
    var disagreeing = assets.materials.add(
        Material(white, dull, kind=PHONG, specular_map=shifted)
    )
    for material in [colored, absent, disagreeing]:
        for mode in [SHADE_TEXTURE, SHADE_LIT]:
            var strict = Renderer(WIDTH, HEIGHT)
            strict.set_shading(mode)
            with assert_raises():
                _ = rendered(
                    strict,
                    scene,
                    assets,
                    sheet_of(assets, material),
                    camera_at(0, 0, 4),
                )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
