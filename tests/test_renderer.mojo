# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.mesh` and `renderers.renderer`."""

from cameras.perspective_camera import PerspectiveCamera
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.sphere import sphere
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, face_normal
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METRE

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
        Length(0.1, METRE),
        Length(100.0, METRE),
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
    scene.update()
    return scene^


def count_background(image: Framebuffer, background: Color) raises -> Int:
    """Return how many pixels still hold the clear colour.

    Args:
        image: The rendered image.
        background: The colour it was cleared to.

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
    var mesh = Mesh(cube(Length(1.0, METRE)), Color(1, 2, 3), 4)
    assert_equal(mesh.node, 4)
    assert_equal(mesh.color.r, UInt8(1))
    assert_equal(mesh.geometry.triangle_count(), 12)


def test_a_mesh_must_name_a_node() raises:
    with assert_raises():
        _ = Mesh(cube(Length(1.0, METRE)), Color(1, 2, 3), -1)


# --- Renderer ---------------------------------------------------------------


def test_a_renderer_needs_a_positive_size() raises:
    with assert_raises():
        _ = Renderer(0, 10)
    with assert_raises():
        _ = Renderer(10, -1)


def test_a_face_turned_towards_the_light_keeps_its_colour() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var lit = renderer.shade(Color(200, 100, 50), renderer.light)
    assert_equal(lit.r, UInt8(200))


def test_a_face_turned_away_keeps_only_the_ambient_share() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var away = Vector3(-renderer.light.x, -renderer.light.y, -renderer.light.z)
    var dim = renderer.shade(Color(200, 100, 50), away)
    # A quarter of 200, the default ambient.
    assert_equal(dim.r, UInt8(50))


def test_a_fully_lit_white_face_clamps_rather_than_wrapping() raises:
    # Rounding pushes 255 to 255.5, which must clamp rather than overflow.
    var renderer = Renderer(WIDTH, HEIGHT)
    var lit = renderer.shade(Color(255, 255, 255), renderer.light)
    assert_equal(lit.r, UInt8(255))
    assert_equal(lit.g, UInt8(255))


def test_shading_preserves_alpha() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var shaded = renderer.shade(Color(200, 100, 50, 128), renderer.light)
    assert_equal(shaded.a, UInt8(128))


def test_the_light_can_be_pointed_somewhere_else() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_light(Vector3(0, 0, 5), 0.0)
    # Given as length five, stored as a unit vector.
    assert_almost_equal(renderer.light.length(), Float32(1), atol=TOLERANCE)
    var facing = renderer.shade(Color(200, 0, 0), Vector3(0, 0, 1))
    assert_equal(facing.r, UInt8(200))
    var away = renderer.shade(Color(200, 0, 0), Vector3(0, 0, -1))
    assert_equal(away.r, UInt8(0))


def test_a_light_with_no_direction_is_rejected() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    with assert_raises():
        renderer.set_light(Vector3(0, 0, 0), 0.5)


def test_ambient_outside_zero_to_one_is_rejected() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    with assert_raises():
        renderer.set_light(Vector3(0, 1, 0), -0.1)
    with assert_raises():
        renderer.set_light(Vector3(0, 1, 0), 1.5)


def test_an_empty_scene_renders_pure_background() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var image = renderer.render(Scene(), List[Mesh](), a_camera())
    assert_equal(image.width, WIDTH)
    assert_equal(image.height, HEIGHT)
    assert_equal(count_background(image, renderer.background), WIDTH * HEIGHT)


def test_a_mesh_actually_covers_some_pixels() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = scene_with_node_at(0)
    var meshes = List[Mesh]()
    meshes.append(Mesh(cube(Length(1.0, METRE)), Color(255, 0, 0), 0))
    var image = renderer.render(scene, meshes, a_camera())
    assert_true(count_background(image, renderer.background) < WIDTH * HEIGHT)


def test_the_background_colour_is_used() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(7, 8, 9))
    var image = renderer.render(Scene(), List[Mesh](), a_camera())
    assert_equal(image.get_pixel(0, 0).r, UInt8(7))
    assert_equal(image.get_pixel(0, 0).b, UInt8(9))


def test_a_nearer_mesh_hides_a_further_one_whatever_the_order() raises:
    # The whole point of rendering with depth rather than painting in order.
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = Scene()
    var near = Object3D()
    near.set_position(0, 0, 1)
    var near_node = scene.add(near^)
    var far = Object3D()
    far.set_position(0, 0, -1)
    var far_node = scene.add(far^)
    scene.update()

    var near_first = List[Mesh]()
    near_first.append(
        Mesh(cube(Length(1.0, METRE)), Color(255, 0, 0), near_node)
    )
    near_first.append(
        Mesh(cube(Length(1.0, METRE)), Color(0, 255, 0), far_node)
    )

    var far_first = List[Mesh]()
    far_first.append(Mesh(cube(Length(1.0, METRE)), Color(0, 255, 0), far_node))
    far_first.append(
        Mesh(cube(Length(1.0, METRE)), Color(255, 0, 0), near_node)
    )

    var a = renderer.render(scene, near_first, a_camera())
    var b = renderer.render(scene, far_first, a_camera())
    # The centre pixel belongs to the near cube either way, and both images
    # must agree everywhere.
    var centre = a.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_true(centre.r > centre.g)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(a.get_pixel(x, y).r, b.get_pixel(x, y).r)


def test_the_scene_transform_is_what_places_a_mesh() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = Scene()
    var node = Object3D()
    node.set_position(-6, 0, 0)
    _ = scene.add(node^)
    scene.update()
    var meshes = List[Mesh]()
    meshes.append(Mesh(cube(Length(0.5, METRE)), Color(255, 0, 0), 0))
    # Moved well off to the side, it leaves the frame entirely.
    var image = renderer.render(scene, meshes, a_camera())
    assert_equal(count_background(image, renderer.background), WIDTH * HEIGHT)


def test_a_mesh_with_no_vertices_draws_nothing() raises:
    # A geometry can exist before its data does, and rendering one must be a
    # no-op rather than an error.
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = scene_with_node_at(0)
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    var meshes = List[Mesh]()
    meshes.append(Mesh(empty^, Color(255, 0, 0), 0))
    var image = renderer.render(scene, meshes, a_camera())
    assert_equal(count_background(image, renderer.background), WIDTH * HEIGHT)


def test_a_mesh_naming_a_node_that_is_not_there_is_rejected() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var meshes = List[Mesh]()
    meshes.append(Mesh(cube(Length(1.0, METRE)), Color(255, 0, 0), 3))
    with assert_raises():
        _ = renderer.render(Scene(), meshes, a_camera())


def test_a_geometry_without_normals_shades_flat() raises:
    # No normal attribute, so each face supplies its own and the triangle
    # takes one colour throughout.
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = scene_with_node_at(0)
    var plain = BufferGeometry()
    var data = List[Float32]()
    for value in [-1.0, -1.0, 0.0, 1.0, -1.0, 0.0, 0.0, 1.0, 0.0]:
        data.append(Float32(value))
    plain.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    var meshes = List[Mesh]()
    meshes.append(Mesh(plain^, Color(200, 200, 200), 0))
    var image = renderer.render(scene, meshes, a_camera())
    assert_true(count_background(image, renderer.background) < WIDTH * HEIGHT)


def test_a_sphere_shades_smoothly_across_a_triangle() raises:
    # Per-vertex normals mean neighbouring pixels differ, where a flat face
    # would hold one colour.
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = scene_with_node_at(0)
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(sphere(Length(1.0, METRE), 16, 12), Color(200, 200, 200), 0)
    )
    var image = renderer.render(scene, meshes, a_camera())
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
    # The camera sits inside a large cube. Without clipping, corners behind
    # the camera project through the origin and smear across the image.
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = scene_with_node_at(0)
    var meshes = List[Mesh]()
    meshes.append(Mesh(cube(Length(8.0, METRE)), Color(255, 140, 40), 0))
    var image = renderer.render(scene, meshes, a_camera())
    # Every pixel belongs to the cube's inside surface, and every one of them
    # is a real shade rather than a projection artefact.
    assert_true(count_background(image, renderer.background) < 100)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
