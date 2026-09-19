# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `helpers`: the axes, grid, box and camera helpers, and the
material they are drawn with."""

from cameras.orthographic_camera import OrthographicCamera, centered
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from helpers.axes import DEFAULT_AXES_SIZE, axes_helper
from helpers.box import DEFAULT_BOX_COLOR, box_helper
from helpers.camera import (
    DEFAULT_CONE_COLOR,
    DEFAULT_CROSS_COLOR,
    DEFAULT_FRUSTUM_COLOR,
    DEFAULT_TARGET_COLOR,
    DEFAULT_UP_COLOR,
    camera_helper,
)
from helpers.grid import (
    DEFAULT_CENTER_COLOR,
    DEFAULT_GRID_COLOR,
    DEFAULT_GRID_DIVISIONS,
    DEFAULT_GRID_SIZE,
    grid_helper,
)
from helpers.material import helper_material
from materials.material import BASIC, BLEND, Material
from math.bounds import Box3
from math.vector3 import Vector3
from objects.line import Line, SEGMENTS, segment_count
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-5)
comptime WIDTH = 16
comptime HEIGHT = 16


def point_of(geometry: BufferGeometry, index: Int) raises -> Vector3:
    """Return one position of a helper."""
    return geometry.attribute_view(String(POSITION)).vector3(index)


def color_of(geometry: BufferGeometry, index: Int) raises -> Vector3:
    """Return one color of a helper, its three linear floats as a vector."""
    return geometry.attribute_view(String(COLOR)).vector3(index)


def assert_vector(actual: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a vector's three components to the tolerance."""
    assert_almost_equal(Float64(actual.x), Float64(x), atol=TOLERANCE)
    assert_almost_equal(Float64(actual.y), Float64(y), atol=TOLERANCE)
    assert_almost_equal(Float64(actual.z), Float64(z), atol=TOLERANCE)


def assert_linear(actual: Vector3, authored: Color) raises:
    """Assert a helper color is `authored` decoded to linear light."""
    var expected = FloatColor(srgb=authored)
    assert_vector(actual, expected.r, expected.g, expected.b)


def lit_pixels(
    scene: Scene, assets: Assets, camera: OrthographicCamera
) raises -> Int:
    """Return how many pixels a scene lights when rendered small."""
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, camera)
    var count = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if pixel.r > 0 or pixel.g > 0 or pixel.b > 0:
                count += 1
    return count


def a_top_camera() raises -> OrthographicCamera:
    """Return a camera looking straight down at a four-meter square."""
    var camera = centered(
        Length(4.0, METER), 1.0, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 5, 0), Vector3(0, 0, 0))
    return camera^


# --- the material ------------------------------------------------------------


def test_the_helper_material_is_white_unlit_and_tinted_by_the_geometry() raises:
    var paint = helper_material()
    assert_true(paint.kind == BASIC)
    assert_true(paint.vertex_colors)
    assert_equal(paint.color.r, 255)
    assert_equal(paint.color.g, 255)
    assert_equal(paint.color.b, 255)
    assert_false(paint.is_transparent())
    var faint = helper_material(opacity=0.5, transparent=True)
    assert_true(faint.is_transparent())
    assert_almost_equal(faint.opacity, Float32(0.5), atol=1e-6)
    var stated = helper_material(blending=BLEND)
    assert_true(stated.is_transparent())


def test_the_helper_material_refuses_what_a_material_refuses() raises:
    with assert_raises(contains="Opacity"):
        _ = helper_material(opacity=2)


# --- axes --------------------------------------------------------------------


def test_the_axes_helper_is_three_sticks_from_the_origin() raises:
    var axes = axes_helper()
    assert_almost_equal(DEFAULT_AXES_SIZE.to(METER), Float32(1), atol=1e-6)
    assert_equal(axes.vertex_count(), 6)
    assert_equal(segment_count(SEGMENTS, axes.vertex_count()), 3)
    assert_vector(point_of(axes, 0), 0, 0, 0)
    assert_vector(point_of(axes, 1), 1, 0, 0)
    assert_vector(point_of(axes, 2), 0, 0, 0)
    assert_vector(point_of(axes, 3), 0, 1, 0)
    assert_vector(point_of(axes, 4), 0, 0, 0)
    assert_vector(point_of(axes, 5), 0, 0, 1)
    # three.js's colors, written as linear floats: each axis fades toward
    # a paler tint at its end.
    assert_vector(color_of(axes, 0), 1, 0, 0)
    assert_vector(color_of(axes, 1), 1, 0.6, 0)
    assert_vector(color_of(axes, 2), 0, 1, 0)
    assert_vector(color_of(axes, 3), 0.6, 1, 0)
    assert_vector(color_of(axes, 4), 0, 0, 1)
    assert_vector(color_of(axes, 5), 0, 0.6, 1)
    var longer = axes_helper(Length(2.5, METER))
    assert_vector(point_of(longer, 5), 0, 0, 2.5)


def test_the_axes_helper_needs_a_positive_size() raises:
    with assert_raises(contains="positive size"):
        _ = axes_helper(Length(0.0, METER))
    with assert_raises(contains="positive size"):
        _ = axes_helper(Length(-1.0, METER))


# --- grid --------------------------------------------------------------------


def test_the_grid_helper_is_a_square_of_lines_each_way() raises:
    var grid = grid_helper()
    assert_almost_equal(DEFAULT_GRID_SIZE.to(METER), Float32(10), atol=1e-6)
    assert_equal(DEFAULT_GRID_DIVISIONS, 10)
    # Eleven lines along x and eleven along z, two points each.
    assert_equal(grid.vertex_count(), 44)
    assert_equal(segment_count(SEGMENTS, grid.vertex_count()), 22)
    # The first step: a line along x at z = -5, then a line along z at
    # x = -5, as three.js writes them.
    assert_vector(point_of(grid, 0), -5, 0, -5)
    assert_vector(point_of(grid, 1), 5, 0, -5)
    assert_vector(point_of(grid, 2), -5, 0, -5)
    assert_vector(point_of(grid, 3), -5, 0, 5)
    # The last step is at the far edge.
    assert_vector(point_of(grid, 40), -5, 0, 5)
    assert_vector(point_of(grid, 41), 5, 0, 5)
    assert_vector(point_of(grid, 43), 5, 0, 5)


def test_the_grid_helper_colors_the_two_center_lines_apart() raises:
    var grid = grid_helper()
    # The sixth step of ten is the center, and both its lines take the
    # center color; every other line takes the grid color. Both are
    # decoded to linear light.
    for point in range(44):
        var step = point // 4
        if step == 5:
            assert_linear(color_of(grid, point), DEFAULT_CENTER_COLOR)
        else:
            assert_linear(color_of(grid, point), DEFAULT_GRID_COLOR)
    var painted = grid_helper(
        Length(2.0, METER), 2, Color(255, 0, 0), Color(0, 0, 255)
    )
    assert_linear(color_of(painted, 4), Color(255, 0, 0))
    assert_linear(color_of(painted, 0), Color(0, 0, 255))
    assert_vector(point_of(painted, 4), -1, 0, 0)
    assert_vector(point_of(painted, 5), 1, 0, 0)


def test_an_odd_grid_has_no_center_line() raises:
    # three.js compares the step to `divisions / 2`, a float no integer
    # step reaches when the count is odd, so no line takes the center
    # color; the lines straddle the origin.
    var grid = grid_helper(Length(3.0, METER), 3)
    assert_equal(grid.vertex_count(), 16)
    for point in range(16):
        assert_linear(color_of(grid, point), DEFAULT_GRID_COLOR)
    assert_vector(point_of(grid, 4), -1.5, 0, -0.5)


def test_the_grid_helper_refuses_a_grid_that_is_not_one() raises:
    with assert_raises(contains="positive size"):
        _ = grid_helper(Length(0.0, METER))
    with assert_raises(contains="at least one division"):
        _ = grid_helper(Length(1.0, METER), 0)


def test_a_grid_is_drawn_by_a_line_with_the_helper_material() raises:
    var assets = Assets()
    var grid = assets.geometries.add(grid_helper(Length(2.0, METER), 2))
    var paint = assets.materials.add(helper_material())
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_line(Line(grid, paint, node, mode=SEGMENTS))
    # Three lines each way, each crossing the image: more than one row's
    # worth of pixels, and fewer than the whole image.
    var lit = lit_pixels(scene, assets, a_top_camera())
    assert_true(lit > WIDTH * 2, "the grid is not drawn")
    assert_true(lit < WIDTH * HEIGHT, "the grid fills the image")


# --- box ---------------------------------------------------------------------


def test_the_box_helper_is_the_twelve_edges_of_a_box() raises:
    var box = Box3(Vector3(-1, -2, -3), Vector3(1, 2, 3))
    var edges = box_helper(box)
    assert_equal(edges.vertex_count(), 24)
    assert_equal(segment_count(SEGMENTS, edges.vertex_count()), 12)
    assert_false(edges.has_attribute(String(COLOR)))
    # three.js's first edge joins corner 0, the largest, to corner 1.
    assert_vector(point_of(edges, 0), 1, 2, 3)
    assert_vector(point_of(edges, 1), -1, 2, 3)
    # Its fifth starts the near square at corner 4.
    assert_vector(point_of(edges, 8), 1, 2, -3)
    assert_vector(point_of(edges, 9), -1, 2, -3)
    # And its last joins corner 3 to corner 7, across the depth.
    assert_vector(point_of(edges, 22), 1, -2, 3)
    assert_vector(point_of(edges, 23), 1, -2, -3)
    # Every edge is axis-aligned and of the right length.
    for edge in range(12):
        var a = point_of(edges, edge * 2)
        var b = point_of(edges, edge * 2 + 1)
        var moved = 0
        if a.x != b.x:
            moved += 1
        if a.y != b.y:
            moved += 1
        if a.z != b.z:
            moved += 1
        assert_equal(moved, 1)
    assert_equal(DEFAULT_BOX_COLOR.r, 255)
    assert_equal(DEFAULT_BOX_COLOR.g, 255)
    assert_equal(DEFAULT_BOX_COLOR.b, 0)


def test_the_box_helper_refuses_an_empty_box() raises:
    with assert_raises(contains="holds something"):
        _ = box_helper(Box3.empty())


def test_a_box_helper_outlines_a_mesh_where_it_stands() raises:
    # A cube of one meter on a node scaled by two and moved: the bounds
    # carried through the node's world matrix are the world bounds,
    # which is what three.js's `BoxHelper` measures.
    var assets = Assets()
    var block = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(255, 255, 0), kind=BASIC))
    var scene = Scene()
    var node = Object3D()
    node.set_position(0.5, 0, 0)
    node.set_scale(2, 2, 2)
    var placed = scene.add(node^)
    var root = scene.add(Object3D())
    scene.update()
    scene.add_mesh(Mesh(block, paint, placed))
    var bounds = assets.geometries.get(block).bounding_box()
    bounds.apply_matrix4(scene.world_matrix(placed))
    assert_vector(bounds.min, -0.5, -1, -1)
    assert_vector(bounds.max, 1.5, 1, 1)
    var edges = assets.geometries.add(box_helper(bounds))
    scene.add_line(Line(edges, paint, root, mode=SEGMENTS))
    assert_true(lit_pixels(scene, assets, a_top_camera()) > 0)


# --- camera ------------------------------------------------------------------


def test_the_camera_helper_outlines_a_perspective_frustum() raises:
    # A right angle of view at an aspect of one: the near rectangle is a
    # square of half-width equal to the near distance, and the far one
    # of half-width equal to the far distance.
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(1.0, METER), Length(10.0, METER)
    )
    var outline = camera_helper(camera)
    assert_equal(outline.vertex_count(), 50)
    assert_equal(segment_count(SEGMENTS, outline.vertex_count()), 25)
    # near: n1 n2, n2 n4, n4 n3, n3 n1
    assert_vector(point_of(outline, 0), -1, -1, -1)
    assert_vector(point_of(outline, 1), 1, -1, -1)
    assert_vector(point_of(outline, 3), 1, 1, -1)
    assert_vector(point_of(outline, 5), -1, 1, -1)
    # far: f1 f2
    assert_vector(point_of(outline, 8), -10, -10, -10)
    assert_vector(point_of(outline, 9), 10, -10, -10)
    # sides: n1 f1
    assert_vector(point_of(outline, 16), -1, -1, -1)
    assert_vector(point_of(outline, 17), -10, -10, -10)
    # cone: p n1. The apex is clip space's origin carried back, which
    # under perspective is between the planes: -2nf / (f + n).
    assert_vector(point_of(outline, 24), 0, 0, -20.0 / 11.0)
    assert_vector(point_of(outline, 25), -1, -1, -1)
    # up: u1 u2, u2 u3
    assert_vector(point_of(outline, 32), 0.7, 1.1, -1)
    assert_vector(point_of(outline, 33), -0.7, 1.1, -1)
    assert_vector(point_of(outline, 35), 0, 2, -1)
    # target: c t
    assert_vector(point_of(outline, 38), 0, 0, -1)
    assert_vector(point_of(outline, 39), 0, 0, -10)
    # cross: cn1 cn2, and the last, cf3 cf4
    assert_vector(point_of(outline, 42), -1, 0, -1)
    assert_vector(point_of(outline, 43), 1, 0, -1)
    assert_vector(point_of(outline, 48), 0, -10, -10)
    assert_vector(point_of(outline, 49), 0, 10, -10)


def test_the_camera_helper_outlines_an_orthographic_volume() raises:
    # Parallel rays: the near and far rectangles are the same size, and
    # the apex is halfway between the planes.
    var camera = centered(
        Length(2.0, METER), 2.0, Length(1.0, METER), Length(5.0, METER)
    )
    var outline = camera_helper(camera)
    assert_vector(point_of(outline, 0), -2, -1, -1)
    assert_vector(point_of(outline, 8), -2, -1, -5)
    assert_vector(point_of(outline, 24), 0, 0, -3)


def test_the_camera_helper_paints_each_part_its_own_color() raises:
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1.5, Length(0.5, METER), Length(4.0, METER)
    )
    var outline = camera_helper(camera)
    for point in range(50):
        var line = point // 2
        var color = color_of(outline, point)
        if line < 12:
            assert_linear(color, DEFAULT_FRUSTUM_COLOR)
        elif line < 16:
            assert_linear(color, DEFAULT_CONE_COLOR)
        elif line < 19:
            assert_linear(color, DEFAULT_UP_COLOR)
        elif line < 20:
            assert_linear(color, DEFAULT_TARGET_COLOR)
        else:
            assert_linear(color, DEFAULT_CROSS_COLOR)
    var painted = camera_helper(
        camera,
        frustum_color=Color(255, 0, 0),
        cone_color=Color(0, 255, 0),
        up_color=Color(0, 0, 255),
        target_color=Color(255, 255, 0),
        cross_color=Color(0, 255, 255),
    )
    assert_linear(color_of(painted, 0), Color(255, 0, 0))
    assert_linear(color_of(painted, 24), Color(0, 255, 0))
    assert_linear(color_of(painted, 32), Color(0, 0, 255))
    assert_linear(color_of(painted, 38), Color(255, 255, 0))
    assert_linear(color_of(painted, 40), Color(0, 255, 255))


def test_a_camera_helper_rides_the_node_its_camera_rides() raises:
    # A second camera on a node, aimed at the origin, and its outline on
    # the same node: seen from above, the frustum is drawn where the
    # camera looks.
    var assets = Assets()
    var watched = PerspectiveCamera(
        Angle(60.0, DEGREE), 1.0, Length(0.3, METER), Length(1.5, METER)
    )
    var outline = assets.geometries.add(camera_helper(watched))
    var paint = assets.materials.add(helper_material())
    var scene = Scene()
    var perch = Object3D()
    perch.set_position(1.5, 0, 0)
    var node = scene.add(perch^)
    scene.update()
    scene.look_at(node, Vector3(0, 0, 0), camera=True)
    watched.attach(node)
    scene.update()
    scene.add_line(Line(outline, paint, node, mode=SEGMENTS))
    assert_true(lit_pixels(scene, assets, a_top_camera()) > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
