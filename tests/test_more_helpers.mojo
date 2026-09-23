# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the arrow, polar grid, plane, skeleton, light and vertex
helpers, and the segment list they are built with."""

from cameras.orthographic_camera import OrthographicCamera, centered
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, NORMAL, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from helpers.arrow import DEFAULT_ARROW_COLOR, arrow_helper
from helpers.light import (
    directional_light_helper,
    hemisphere_light_helper,
    point_light_helper,
    rect_area_light_helper,
    spot_light_helper,
)
from helpers.material import helper_material
from helpers.normals import (
    DEFAULT_NORMALS_COLOR,
    DEFAULT_TANGENTS_COLOR,
    TANGENT,
    vertex_normals_helper,
    vertex_tangents_helper,
)
from helpers.plane import DEFAULT_PLANE_COLOR, plane_helper
from helpers.polar_grid import (
    DEFAULT_POLAR_COLOR1,
    DEFAULT_POLAR_COLOR2,
    polar_grid_helper,
)
from helpers.segments import Segments
from helpers.skeleton import skeleton_helper
from lights.light import (
    LightKind,
    directional_light,
    hemisphere_light,
    point_light,
    rect_area_light,
    spot_light,
)
from math.bounds import Plane
from math.matrix4 import Matrix4, scaling, translation
from math.vector3 import Vector3
from objects.line import Line, SEGMENTS, segment_count
from objects.skeleton import bind_skeleton
from render.framebuffer import Color, FloatColor
from renderers.renderer import Renderer
from std.math import cos, pi, sin, sqrt, tan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-4)
comptime WIDTH = 16
comptime HEIGHT = 16


def point_of(geometry: BufferGeometry, index: Int) raises -> Vector3:
    """Return one position of a helper."""
    return geometry.attribute_view(String(POSITION)).vector3(index)


def color_of(geometry: BufferGeometry, index: Int) raises -> Vector3:
    """Return one color of a helper, its three linear floats as a vector."""
    return geometry.attribute_view(String(COLOR)).vector3(index)


def assert_near(
    actual: Vector3,
    x: Float32,
    y: Float32,
    z: Float32,
    tolerance: Float64 = TOLERANCE,
) raises:
    """Assert a vector's three components to a tolerance."""
    assert_almost_equal(Float64(actual.x), Float64(x), atol=tolerance)
    assert_almost_equal(Float64(actual.y), Float64(y), atol=tolerance)
    assert_almost_equal(Float64(actual.z), Float64(z), atol=tolerance)


def assert_linear(actual: Vector3, authored: Color) raises:
    """Assert a helper color is `authored` decoded to linear light."""
    var expected = FloatColor(srgb=authored)
    assert_near(actual, expected.r, expected.g, expected.b)


def meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


# --- segments ----------------------------------------------------------------


def test_segments_gather_points_and_colors() raises:
    var segments = Segments()
    assert_equal(segments.count(), 0)
    var red = FloatColor(1, 0, 0)
    var blue = FloatColor(0, 0, 1)
    segments.add(Vector3(0, 0, 0), Vector3(1, 0, 0), red)
    segments.add_blend(Vector3(0, 1, 0), Vector3(0, 2, 0), red, blue)
    # A strip of one point has no segment; a strip of three has two.
    segments.add_strip([Vector3(5, 5, 5)], Matrix4(), red)
    assert_equal(segments.count(), 2)
    segments.add_strip(
        [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0)],
        translation(0, 0, 1),
        blue,
    )
    assert_equal(segments.count(), 4)
    var geometry = segments.geometry()
    assert_equal(geometry.vertex_count(), 8)
    assert_near(point_of(geometry, 1), 1, 0, 0)
    assert_near(color_of(geometry, 2), 1, 0, 0)
    assert_near(color_of(geometry, 3), 0, 0, 1)
    assert_near(point_of(geometry, 4), 0, 0, 1)
    assert_near(point_of(geometry, 5), 1, 0, 1)
    assert_near(point_of(geometry, 6), 1, 0, 1)
    assert_near(point_of(geometry, 7), 1, 1, 1)


# --- arrow -------------------------------------------------------------------


def test_the_arrow_helper_is_a_shaft_and_the_edges_of_a_cone() raises:
    # Straight up from (1, 2, 3), two meters long: the head is a fifth of
    # that, and its base a fifth of the head across.
    var arrow = arrow_helper(Vector3(0, 1, 0), Vector3(1, 2, 3), meters(2))
    assert_equal(arrow.vertex_count(), 22)
    assert_equal(segment_count(SEGMENTS, arrow.vertex_count()), 11)
    assert_near(point_of(arrow, 0), 1, 2, 3)
    assert_near(point_of(arrow, 1), 1, 3.6, 3)
    # The base's first corner is on +z, at half the head's width.
    assert_near(point_of(arrow, 2), 1, 3.6, 3.04)
    var theta = Float32(2 * pi / 5)
    assert_near(
        point_of(arrow, 3), 1 + 0.04 * sin(theta), 3.6, 3 + 0.04 * cos(theta)
    )
    # The edges to the tip.
    assert_near(point_of(arrow, 12), 1, 3.6, 3.04)
    assert_near(point_of(arrow, 13), 1, 4, 3)
    assert_near(point_of(arrow, 21), 1, 4, 3)
    for point in range(22):
        assert_linear(color_of(arrow, point), DEFAULT_ARROW_COLOR)


def test_the_arrow_helper_turns_up_onto_its_direction() raises:
    # Straight down: a half turn about x, three.js's special case.
    var down = arrow_helper(Vector3(0, -2, 0))
    assert_near(point_of(down, 1), 0, -0.8, 0)
    assert_near(point_of(down, 2), 0, -0.8, -0.02)
    assert_near(point_of(down, 13), 0, -1, 0)
    # Along x: a quarter turn about -z.
    var side = arrow_helper(Vector3(1, 0, 0))
    assert_near(point_of(side, 1), 0.8, 0, 0)
    assert_near(point_of(side, 2), 0.8, 0, 0.02)
    assert_near(point_of(side, 13), 1, 0, 0)
    # three.js's default direction is +z.
    var ahead = arrow_helper()
    assert_near(point_of(ahead, 13), 0, 0, 1)


def test_the_arrow_helper_takes_a_head_of_any_size() raises:
    # A head as long as the arrow leaves three.js's shortest shaft.
    var arrow = arrow_helper(
        Vector3(0, 1, 0),
        length=meters(1),
        color=Color(0, 255, 0),
        head_length=meters(1),
        head_width=meters(0.5),
    )
    assert_near(point_of(arrow, 1), 0, 0.0001, 0)
    assert_near(point_of(arrow, 2), 0, 0, 0.25)
    assert_linear(color_of(arrow, 0), Color(0, 255, 0))


def test_the_arrow_helper_refuses_an_arrow_that_is_not_one() raises:
    with assert_raises(contains="direction with some length"):
        _ = arrow_helper(Vector3(0, 0, 0))
    with assert_raises(contains="positive length"):
        _ = arrow_helper(Vector3(0, 1, 0), length=meters(0))
    with assert_raises(contains="head of positive size"):
        _ = arrow_helper(Vector3(0, 1, 0), head_length=meters(0))
    with assert_raises(contains="head of positive size"):
        _ = arrow_helper(Vector3(0, 1, 0), head_width=meters(-1))


# --- polar grid --------------------------------------------------------------


def test_the_polar_grid_is_spokes_then_rings() raises:
    var grid = polar_grid_helper()
    # Sixteen spokes and eight rings of sixty-four segments.
    assert_equal(grid.vertex_count(), 2 * (16 + 8 * 64))
    assert_near(point_of(grid, 0), 0, 0, 0)
    assert_near(point_of(grid, 1), 0, 0, 10)
    var spoke = Float32(pi / 8)
    assert_near(point_of(grid, 3), 10 * sin(spoke), 0, 10 * cos(spoke))
    # The first spoke takes the second color, the next the first.
    assert_linear(color_of(grid, 0), DEFAULT_POLAR_COLOR2)
    assert_linear(color_of(grid, 2), DEFAULT_POLAR_COLOR1)
    # The outer ring starts on +z; the next is an eighth further in.
    var step = Float32(2 * pi / 64)
    assert_near(point_of(grid, 32), 0, 0, 10)
    assert_near(point_of(grid, 33), 10 * sin(step), 0, 10 * cos(step))
    assert_linear(color_of(grid, 32), DEFAULT_POLAR_COLOR2)
    assert_near(point_of(grid, 160), 0, 0, 8.75)
    assert_linear(color_of(grid, 160), DEFAULT_POLAR_COLOR1)


def test_the_polar_grid_draws_what_its_counts_ask_for() raises:
    # One sector draws no spoke, as in three.js.
    var ring = polar_grid_helper(
        meters(1), 1, 1, 4, Color(255, 0, 0), Color(0, 0, 255)
    )
    assert_equal(ring.vertex_count(), 8)
    assert_near(point_of(ring, 0), 0, 0, 1)
    assert_near(point_of(ring, 1), 1, 0, 0)
    assert_linear(color_of(ring, 0), Color(0, 0, 255))
    # Nothing to draw is an empty helper, not an error.
    assert_equal(polar_grid_helper(meters(1), 0, 0, 4).vertex_count(), 0)
    assert_equal(polar_grid_helper(meters(1), 0, 2, 0).vertex_count(), 0)


def test_the_polar_grid_refuses_a_grid_that_is_not_one() raises:
    with assert_raises(contains="positive radius"):
        _ = polar_grid_helper(meters(0))
    with assert_raises(contains="negative count"):
        _ = polar_grid_helper(meters(1), -1)
    with assert_raises(contains="negative count"):
        _ = polar_grid_helper(meters(1), 2, -1)
    with assert_raises(contains="negative count"):
        _ = polar_grid_helper(meters(1), 2, 2, -1)


# --- plane -------------------------------------------------------------------


def test_the_plane_helper_is_a_square_and_its_diagonals_on_the_plane() raises:
    # The plane z = 2, facing +z: the square is centered on (0, 0, 2).
    var square = plane_helper(Plane(Vector3(0, 0, 1), -2), meters(4))
    assert_equal(square.vertex_count(), 14)
    assert_near(point_of(square, 0), 2, -2, 2)
    assert_near(point_of(square, 1), -2, 2, 2)
    assert_near(point_of(square, 2), -2, 2, 2)
    assert_near(point_of(square, 3), -2, -2, 2)
    assert_near(point_of(square, 12), 2, -2, 2)
    assert_near(point_of(square, 13), 2, 2, 2)
    for point in range(14):
        assert_linear(color_of(square, point), DEFAULT_PLANE_COLOR)


def test_the_plane_helper_lies_on_the_ground_plane() raises:
    # A normal along +y is three.js's up, which `lookAt` nudges off; the
    # square still lies flat, a half unit each way.
    var ground = plane_helper(
        Plane(Vector3(0, 3, 0), 0), color=Color(0, 0, 255)
    )
    for point in range(14):
        assert_almost_equal(
            Float64(point_of(ground, point).y), 0, atol=TOLERANCE
        )
    assert_near(point_of(ground, 0), 0.5, 0, 0.5)
    assert_linear(color_of(ground, 0), Color(0, 0, 255))
    with assert_raises(contains="positive size"):
        _ = plane_helper(Plane(Vector3(0, 1, 0), 0), meters(0))


# --- skeleton ----------------------------------------------------------------


def a_rig(mut scene: Scene) raises -> List[NodeId]:
    """Return three bones in a chain under a node that is not a bone."""
    var root = scene.add(Object3D())
    var hip = Object3D()
    hip.set_position(0, 1, 0)
    var first = scene.attach(hip^, root)
    var knee = Object3D()
    knee.set_position(0, 1, 0)
    var second = scene.attach(knee^, first)
    var foot = Object3D()
    foot.set_position(1, 0, 0)
    var third = scene.attach(foot^, second)
    scene.update()
    return [first, second, third]


def test_the_skeleton_helper_joins_each_bone_to_its_parent_bone() raises:
    var scene = Scene()
    var bones = a_rig(scene)
    var placed = List[Matrix4]()
    for bone in bones:
        placed.append(scene.world_matrix(bone))
    var skeleton = bind_skeleton(bones, placed)
    var lines = skeleton_helper(skeleton, scene)
    # The first bone's parent is not a bone, so it has no segment.
    assert_equal(lines.vertex_count(), 4)
    assert_near(point_of(lines, 0), 0, 2, 0)
    assert_near(point_of(lines, 1), 0, 1, 0)
    assert_near(point_of(lines, 2), 1, 2, 0)
    assert_near(point_of(lines, 3), 0, 2, 0)
    assert_near(color_of(lines, 0), 0, 0, 1)
    assert_near(color_of(lines, 1), 0, 1, 0)
    var painted = skeleton_helper(
        skeleton, scene, Color(255, 0, 0), Color(255, 255, 255)
    )
    assert_near(color_of(painted, 0), 1, 0, 0)
    assert_near(color_of(painted, 1), 1, 1, 1)


def test_a_skeleton_of_one_bone_has_nothing_to_draw() raises:
    var scene = Scene()
    var bones = a_rig(scene)
    var skeleton = bind_skeleton([bones[0]], [scene.world_matrix(bones[0])])
    assert_equal(skeleton_helper(skeleton, scene).vertex_count(), 0)


# --- light helpers -----------------------------------------------------------


def a_node(
    mut scene: Scene, x: Float32, y: Float32, z: Float32
) raises -> NodeId:
    """Return a new root node at a position."""
    var node = Object3D()
    node.set_position(x, y, z)
    return scene.add(node^)


def test_the_directional_light_helper_faces_its_target() raises:
    var scene = Scene()
    var lamp = a_node(scene, 0, 0, 5)
    var aim = a_node(scene, 3, 0, 5)
    scene.update()
    var light = directional_light(Color(255, 0, 0), lamp)
    var outline = directional_light_helper(light, scene)
    assert_equal(outline.vertex_count(), 10)
    # Facing the origin down -z, the square's +x is the world's -x.
    assert_near(point_of(outline, 0), 1, 1, 5)
    assert_near(point_of(outline, 1), -1, 1, 5)
    assert_near(point_of(outline, 3), -1, -1, 5)
    assert_near(point_of(outline, 8), 0, 0, 5)
    assert_near(point_of(outline, 9), 0, 0, 0)
    assert_linear(color_of(outline, 0), Color(255, 0, 0))
    # A named target, a larger square, and a color of its own.
    var aimed = directional_light(Color(255, 0, 0), lamp, target=aim)
    var other = directional_light_helper(
        aimed, scene, meters(2), Color(0, 255, 0)
    )
    assert_near(point_of(other, 9), 3, 0, 5)
    assert_near(point_of(other, 0), 0, 2, 7)
    assert_linear(color_of(other, 9), Color(0, 255, 0))


def test_a_light_helper_refuses_the_wrong_light() raises:
    var scene = Scene()
    var lamp = a_node(scene, 0, 1, 0)
    scene.update()
    var bulb = point_light(Color(255, 255, 255), lamp)
    with assert_raises(contains="needs a directional light"):
        _ = directional_light_helper(bulb, scene)
    var broken = directional_light(Color(255, 255, 255), lamp)
    broken.kind = LightKind(99)
    with assert_raises(contains="needs a directional light"):
        _ = directional_light_helper(broken, scene)
    var dark = directional_light(Color(255, 255, 255), lamp)
    dark.intensity = -1
    with assert_raises(contains="intensity"):
        _ = directional_light_helper(dark, scene)
    with assert_raises(contains="positive size"):
        _ = directional_light_helper(
            directional_light(Color(255, 255, 255), lamp), scene, meters(0)
        )
    var sun = directional_light(Color(255, 255, 255), lamp)
    with assert_raises(contains="needs a point light"):
        _ = point_light_helper(sun, scene)
    with assert_raises(contains="needs a hemisphere light"):
        _ = hemisphere_light_helper(sun, scene)
    with assert_raises(contains="needs a spot light"):
        _ = spot_light_helper(sun, scene)
    with assert_raises(contains="needs a rect area light"):
        _ = rect_area_light_helper(sun, scene)
    with assert_raises(contains="positive size"):
        _ = point_light_helper(bulb, scene, meters(0))
    var sky = hemisphere_light(Color(0, 0, 255), Color(0, 255, 0), lamp)
    with assert_raises(contains="positive size"):
        _ = hemisphere_light_helper(sky, scene, meters(-1))


def test_the_point_light_helper_is_an_octahedron_on_the_light() raises:
    var scene = Scene()
    var node = Object3D()
    node.set_position(1, 2, 3)
    node.set_scale(2, 2, 2)
    var lamp = scene.add(node^)
    scene.update()
    var bulb = point_light(Color(0, 0, 255), lamp)
    var sphere = point_light_helper(bulb, scene, meters(0.5))
    assert_equal(sphere.vertex_count(), 24)
    # The node's whole world matrix applies, its scale of two included.
    assert_near(point_of(sphere, 0), 1, 3, 3)
    assert_near(point_of(sphere, 1), 0, 2, 3)
    assert_near(point_of(sphere, 8), 0, 2, 3)
    assert_near(point_of(sphere, 9), 1, 2, 4)
    assert_near(point_of(sphere, 16), 0, 2, 3)
    assert_near(point_of(sphere, 17), 1, 1, 3)
    assert_linear(color_of(sphere, 0), Color(0, 0, 255))
    var painted = point_light_helper(bulb, scene, color=Color(255, 0, 0))
    assert_linear(color_of(painted, 23), Color(255, 0, 0))


def test_the_hemisphere_light_helper_turns_its_sky_side_to_the_sky() raises:
    var scene = Scene()
    var lamp = a_node(scene, 0, 5, 0)
    scene.update()
    var light = hemisphere_light(Color(0, 0, 255), Color(0, 255, 0), lamp)
    var shape = hemisphere_light_helper(light, scene)
    assert_equal(shape.vertex_count(), 48)
    # The sky corner points up from the light; `lookAt` nudges the axis
    # a ten-thousandth off +y, which the tolerance allows for.
    var nudged = Float64(1e-3)
    assert_near(point_of(shape, 0), 0, 5, 1, nudged)
    assert_near(point_of(shape, 1), 1, 5, 0, nudged)
    assert_near(point_of(shape, 3), 0, 6, 0, nudged)
    assert_near(point_of(shape, 24), 0, 5, 1, nudged)
    assert_near(point_of(shape, 27), 0, 4, 0, nudged)
    for point in range(48):
        if point < 24:
            assert_linear(color_of(shape, point), Color(0, 0, 255))
        else:
            assert_linear(color_of(shape, point), Color(0, 255, 0))
    var one = hemisphere_light_helper(light, scene, meters(2), Color(255, 0, 0))
    assert_near(point_of(one, 3), 0, 7, 0, nudged)
    assert_linear(color_of(one, 0), Color(255, 0, 0))
    assert_linear(color_of(one, 47), Color(255, 0, 0))


def test_the_spot_light_helper_is_a_cone_to_the_target() raises:
    var scene = Scene()
    var lamp = a_node(scene, 0, 0, 2)
    scene.update()
    var light = spot_light(
        Color(255, 255, 0), lamp, distance=4, angle=Angle(45.0, DEGREE)
    )
    var cone = spot_light_helper(light, scene)
    assert_equal(cone.vertex_count(), 74)
    assert_near(point_of(cone, 0), 0, 0, 2)
    assert_near(point_of(cone, 1), 0, 0, -2)
    # Four meters out and four across, the cone's +x the world's -x.
    assert_near(point_of(cone, 3), -4, 0, -2)
    assert_near(point_of(cone, 7), 0, 4, -2)
    assert_near(point_of(cone, 10), -4, 0, -2)
    var step = Float32(2 * pi / 32)
    assert_near(point_of(cone, 11), -4 * cos(step), 4 * sin(step), -2)
    assert_near(point_of(cone, 73), -4, 0, -2)
    assert_linear(color_of(cone, 0), Color(255, 255, 0))
    # With no cutoff it reaches a thousand meters, toward a named target.
    var aim = a_node(scene, 0, 0, 10)
    scene.update()
    var far = spot_light(Color(255, 255, 0), lamp, target=aim)
    var long = spot_light_helper(far, scene, Color(0, 255, 255))
    assert_near(point_of(long, 1), 0, 0, 1002, 1e-2)
    var width = 1000 * tan(Float32(pi / 3))
    assert_near(point_of(long, 3), width, 0, 1002, 1e-1)
    assert_linear(color_of(long, 0), Color(0, 255, 255))


def test_the_rect_area_light_helper_outlines_the_rectangle() raises:
    var scene = Scene()
    var node = Object3D()
    node.set_position(1, 2, 3)
    node.set_scale(2, 2, 2)
    node.rotate_y(Angle(90.0, DEGREE))
    var lamp = scene.add(node^)
    scene.update()
    var light = rect_area_light(
        Color(255, 255, 255), lamp, width=meters(4), height=meters(2)
    )
    var outline = rect_area_light_helper(light, scene)
    assert_equal(outline.vertex_count(), 8)
    # Turned by the node, placed by it, and not scaled by it.
    assert_near(point_of(outline, 0), 1, 3, 1)
    assert_near(point_of(outline, 1), 1, 3, 5)
    assert_near(point_of(outline, 3), 1, 1, 5)
    assert_near(color_of(outline, 0), 1, 1, 1)
    # A bright light keeps its hue: scaled down so no channel passes one.
    var bright = rect_area_light(Color(255, 128, 0), lamp, intensity=4)
    var kept = rect_area_light_helper(bright, scene)
    var orange = FloatColor(srgb=Color(255, 128, 0))
    assert_near(color_of(kept, 0), 1, orange.g, 0)
    var painted = rect_area_light_helper(bright, scene, Color(0, 0, 255))
    assert_linear(color_of(painted, 0), Color(0, 0, 255))


def test_a_light_helper_is_drawn_by_a_line_with_the_helper_material() raises:
    var assets = Assets()
    var scene = Scene()
    var lamp = a_node(scene, 0, 1, 0)
    var root = scene.add(Object3D())
    scene.update()
    var light = point_light(Color(255, 255, 255), lamp)
    var shape = assets.geometries.add(point_light_helper(light, scene))
    var paint = assets.materials.add(helper_material())
    scene.add_line(Line(shape, paint, root, mode=SEGMENTS))
    var camera = centered(meters(4), 1.0, meters(0.1), meters(20))
    camera.place(Vector3(0, 5, 0), Vector3(0, 0, 0))
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, camera)
    var lit = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if image.get_pixel(x, y).r > 0:
                lit += 1
    assert_true(lit > 0, "the helper is not drawn")


# --- vertex normals and tangents ---------------------------------------------


def two_vertices() raises -> BufferGeometry:
    """Return two vertices, one with a slanted normal and tangent and one
    with neither."""
    var geometry = BufferGeometry()
    var half = Float32(1 / sqrt(Float32(2)))
    geometry.set_attribute(
        String(POSITION), BufferAttribute([0, 0, 0, 1, 0, 0], 3)
    )
    geometry.set_attribute(
        String(NORMAL), BufferAttribute([half, half, 0, 0, 0, 0], 3)
    )
    geometry.set_attribute(
        String(TANGENT), BufferAttribute([1, 1, 0, 1, 0, 0, 0, 1], 4)
    )
    return geometry^


def test_the_vertex_normals_helper_sticks_out_along_each_normal() raises:
    # Stretched along x: the normal matrix leans the normal toward y, as a
    # surface stretched that way does.
    var world = translation(1, 0, 0)
    world.multiply(scaling(2, 1, 1))
    var sticks = vertex_normals_helper(two_vertices(), world, meters(2))
    assert_equal(sticks.vertex_count(), 4)
    var lean = Float32(1 / sqrt(Float32(5)))
    assert_near(point_of(sticks, 0), 1, 0, 0)
    assert_near(point_of(sticks, 1), 1 + 2 * lean, 4 * lean, 0)
    # A normal of no length is a stick of no length.
    assert_near(point_of(sticks, 2), 3, 0, 0)
    assert_near(point_of(sticks, 3), 3, 0, 0)
    assert_linear(color_of(sticks, 0), DEFAULT_NORMALS_COLOR)


def test_the_vertex_tangents_helper_sticks_out_along_each_tangent() raises:
    # A tangent lies along the surface, so the stretch leans it toward x.
    var sticks = vertex_tangents_helper(
        two_vertices(), scaling(2, 1, 1), color=Color(255, 0, 255)
    )
    var lean = Float32(1 / sqrt(Float32(5)))
    assert_near(point_of(sticks, 1), 2 * lean, lean, 0)
    assert_linear(color_of(sticks, 0), Color(255, 0, 255))
    var plain = vertex_tangents_helper(two_vertices(), Matrix4())
    assert_linear(color_of(plain, 0), DEFAULT_TANGENTS_COLOR)


def test_the_vertex_helpers_refuse_what_they_cannot_read() raises:
    var geometry = two_vertices()
    with assert_raises(contains="positive size"):
        _ = vertex_normals_helper(geometry, Matrix4(), meters(0))
    with assert_raises(contains="no normal matrix"):
        _ = vertex_normals_helper(geometry, scaling(0, 1, 1))
    var bare = BufferGeometry()
    bare.set_attribute(String(POSITION), BufferAttribute([0, 0, 0], 3))
    with assert_raises(contains="no attribute named normal"):
        _ = vertex_normals_helper(bare, Matrix4())
    bare.set_attribute(String(NORMAL), BufferAttribute([0, 1, 0, 0, 1, 0], 3))
    with assert_raises(contains="one normal per vertex"):
        _ = vertex_normals_helper(bare, Matrix4())
    bare.set_attribute(String(TANGENT), BufferAttribute([1, 0], 2))
    with assert_raises(contains="fewer than three"):
        _ = vertex_tangents_helper(bare, Matrix4())
    # No vertices is no sticks.
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    empty.set_attribute(String(NORMAL), BufferAttribute(List[Float32](), 3))
    assert_equal(vertex_normals_helper(empty, Matrix4()).vertex_count(), 0)
    assert_false(empty.has_attribute(String(TANGENT)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
