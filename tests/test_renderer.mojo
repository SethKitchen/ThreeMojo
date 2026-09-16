# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.mesh` and `renderers.renderer`."""

from cameras.camera import Camera
from render.rasterizer import RasterVertex
from core.geometry_store import GeometryId
from core.object3d import NodeId
from cameras.perspective_camera import PerspectiveCamera
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from core.object3d import Object3D
from core.assets import Assets
from materials.material import (
    BACK_SIDE,
    BLEND,
    MaterialId,
    OPAQUE,
    DOUBLE_SIDE,
    FRONT_SIDE,
    Material,
)
from lights.light import point_light
from materials.material import BASIC
from core.scene import Scene
from lights.light import ambient_light, directional_light
from lights.lighting import Lighting
from geometries.box import cube
from geometries.sphere import sphere
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor, Framebuffer
from render.rasterizer import SHADE_LIT, SHADE_TEXTURE, SHADE_UV, ShadeMode
from geometries.polyhedron import octahedron
from render.texture import (
    BILINEAR,
    CLAMP,
    IGNORED,
    NEAREST,
    Texture,
    checkerboard,
)
from render.texture_store import NO_TEXTURE, TextureId
from renderers.renderer import Renderer, available_workers, face_normal
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
    scene.add_light(ambient_light(Color(255, 255, 255), ambient))
    scene.add_light(directional_light(Color(255, 255, 255), node, 1 - ambient))


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
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
    scene.add_light(directional_light(Color(255, 255, 255), node, 0.75))


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
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(empty^),
            assets.materials.add(Material(Color(255, 0, 0))),
            NodeId(0),
        )
    )
    var image = rendered(renderer, scene, assets, meshes, a_camera())
    assert_equal(count_background(image, renderer.background), WIDTH * HEIGHT)


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
    # uv-gathering pass must cope with running zero times.
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


def test_a_back_side_surface_is_lit_from_the_side_you_can_see() raises:
    # Culling decides which faces exist; it does not decide which way they
    # face for lighting. A triangle whose authored normal is +z, seen from
    # -z with the light shining along -z, is lit square-on from the camera's
    # side -- and rendered black until the normal was flipped with it.
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
    # Ambient is zero and the surface faces the light square-on.
    assert_equal(brightest, UInt8(255))


def test_a_back_side_surface_lit_from_behind_stays_dark() raises:
    # The other direction, so the fix cannot have been to light both sides.
    # Same geometry, light now on the side nobody is looking at.
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
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if pixel.r != renderer.background.r or (
                pixel.g != renderer.background.g
            ):
                drawn += 1
                assert_equal(pixel.r, UInt8(0))
    assert_true(drawn > 0, "BackSide drew nothing to leave dark")


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
        Material(Color(255, 0, 0), NO_TEXTURE, FRONT_SIDE, 0.5)
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
        Material(Color(255, 0, 0), NO_TEXTURE, FRONT_SIDE, 0.5)
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
        Material(Color(255, 0, 0), NO_TEXTURE, FRONT_SIDE, 0.5)
    )
    var blue = assets.materials.add(
        Material(Color(0, 0, 255), NO_TEXTURE, FRONT_SIDE, 0.5)
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
    assert_true(
        Material(Color(1, 2, 3), NO_TEXTURE, FRONT_SIDE, 0.5).is_transparent()
    )


def test_a_translucent_base_color_sorts_and_rasterizes_the_same_way() raises:
    # One material, one answer. A base color with alpha but an opacity of one
    # used to sort as opaque and rasterize as blended: it did not write depth,
    # so whatever was submitted after it painted straight over the top, and
    # the image depended on submission order.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var red = assets.materials.add(Material(Color(255, 0, 0, 128)))
    var blue = assets.materials.add(Material(Color(0, 0, 255)))
    assert_true(
        assets.materials.get(red).is_transparent(),
        "a base color with alpha must count as transparent",
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
        Material(Color(255, 80, 80), NO_TEXTURE, DOUBLE_SIDE, 0.5)
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
