# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.line`, `Scene.add_line` and `Renderer.prepare_lines`."""

from cameras.orthographic_camera import OrthographicCamera, centered
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from materials.material import (
    BASIC,
    BLEND,
    DOUBLE_SIDE,
    LAMBERT,
    Material,
    MaterialId,
    NORMALS,
    OPAQUE,
    line_dashed_material,
)
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.line import (
    CONTROL0,
    CONTROL1,
    DIRECTION,
    LOOP,
    Line,
    conditional_discard,
    LineMode,
    SEGMENTS,
    STRIP,
    line_distances,
    segment_count,
    segment_ends,
)
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from render.rasterizer import DRAW_SEGMENTS, DRAW_TRIANGLES, RasterVertex
from render.texture import checkerboard
from render.texture_store import NO_TEXTURE
from renderers.clip import ClipVertex, clip_segment
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
# Small for the reason `tests/test_renderer.mojo` gives: these cover the
# line pass, not the output at any one size, and every covered pixel costs
# a probe record when the rasterizer is instrumented.
comptime WIDTH = 16
comptime HEIGHT = 16


def a_camera() raises -> OrthographicCamera:
    """Return a camera looking down -z at a two-meter square of world.

    An orthographic one, so a world coordinate lands on a pixel by simple
    arithmetic and an expected pixel can be written down rather than
    measured.

    Returns:
        The camera.

    Raises:
        Error: If its parameters are invalid.
    """
    var camera = centered(
        Length(2.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def points(var numbers: List[Float32]) raises -> BufferGeometry:
    """Return a geometry holding `numbers` as positions and nothing else.

    Args:
        numbers: Three per point.

    Returns:
        The geometry.

    Raises:
        Error: If the numbers do not divide into points.
    """
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(numbers^, 3))
    return geometry^


def a_scene_with_one_node() raises -> Scene:
    """Return a scene holding one node at the origin, updated.

    Returns:
        The scene.

    Raises:
        Error: If the scene is invalid.
    """
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    return scene^


def test_a_line_mode_knows_the_three_it_can_be() raises:
    """Only the three named modes are valid."""
    assert_true(STRIP.is_valid())
    assert_true(LOOP.is_valid())
    assert_true(SEGMENTS.is_valid())
    assert_false(LineMode(9).is_valid())
    assert_false(LineMode(-1).is_valid())


def test_a_strip_joins_every_point_to_the_next() raises:
    """A strip of n points makes n - 1 segments, each to the next point."""
    assert_equal(segment_count(STRIP, 4), 3)
    var first = segment_ends(STRIP, 4, 0)
    assert_equal(first[0], 0)
    assert_equal(first[1], 1)
    var last = segment_ends(STRIP, 4, 2)
    assert_equal(last[0], 2)
    assert_equal(last[1], 3)


def test_a_loop_joins_the_last_point_back_to_the_first() raises:
    """A loop of n points makes n segments, the last one wrapping."""
    assert_equal(segment_count(LOOP, 4), 4)
    var closing = segment_ends(LOOP, 4, 3)
    assert_equal(closing[0], 3)
    assert_equal(closing[1], 0)


def test_segments_read_the_points_two_at_a_time() raises:
    """A list of sticks makes half as many segments as it has points."""
    assert_equal(segment_count(SEGMENTS, 6), 3)
    var middle = segment_ends(SEGMENTS, 6, 1)
    assert_equal(middle[0], 2)
    assert_equal(middle[1], 3)


def test_too_few_points_make_no_segment() raises:
    """A path needs two ends, and one point is not two."""
    assert_equal(segment_count(STRIP, 0), 0)
    assert_equal(segment_count(STRIP, 1), 0)
    assert_equal(segment_count(LOOP, 1), 0)
    assert_equal(segment_count(SEGMENTS, 0), 0)


def test_a_point_count_that_does_not_suit_the_mode_is_refused() raises:
    """An odd count of sticks leaves a point with nothing to join."""
    with assert_raises():
        _ = segment_count(SEGMENTS, 5)
    with assert_raises():
        _ = segment_count(STRIP, -1)
    with assert_raises():
        _ = segment_count(LineMode(9), 4)


def test_a_segment_that_is_not_there_is_refused() raises:
    """Asking for the fourth segment of a three-segment strip raises."""
    with assert_raises():
        _ = segment_ends(STRIP, 4, 3)
    with assert_raises():
        _ = segment_ends(STRIP, 4, -1)


def test_a_line_names_three_ids_and_a_mode() raises:
    """The constructor keeps what it is given, and defaults the rest."""
    var line = Line(GeometryId(2), MaterialId(3), NodeId(1))
    assert_equal(line.geometry.value, 2)
    assert_equal(line.material.value, 3)
    assert_equal(line.node.value, 1)
    assert_true(line.mode == STRIP)
    assert_true(line.frustum_culled)
    var loop = Line(
        GeometryId(0), MaterialId(0), NodeId(0), mode=LOOP, frustum_culled=False
    )
    assert_true(loop.mode == LOOP)
    assert_false(loop.frustum_culled)
    assert_equal(loop.segment_count(5), 5)


def test_a_line_refuses_what_cannot_be_an_id_or_a_mode() raises:
    """Negative ids and an unnamed mode are refused outright."""
    with assert_raises():
        _ = Line(GeometryId(0), MaterialId(0), NodeId(-1))
    with assert_raises():
        _ = Line(GeometryId(-1), MaterialId(0), NodeId(0))
    with assert_raises():
        _ = Line(GeometryId(0), MaterialId(-1), NodeId(0))
    with assert_raises():
        _ = Line(GeometryId(0), MaterialId(0), NodeId(0), mode=LineMode(9))


def test_a_scene_takes_lines_beside_its_meshes() raises:
    """`add_line` keeps the line and leaves the transforms current."""
    var scene = a_scene_with_one_node()
    scene.add_line(Line(GeometryId(0), MaterialId(0), NodeId(0)))
    assert_equal(len(scene.lines), 1)
    assert_false(scene.is_stale())
    with assert_raises():
        scene.add_line(Line(GeometryId(0), MaterialId(0), NodeId(7)))


def test_a_segment_wholly_inside_the_range_is_left_alone() raises:
    """Both ends in front of near and this side of far survive as they are."""
    var kept = clip_segment(
        ClipVertex(
            Vector3(0, 0, -1), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        ClipVertex(
            Vector3(1, 0, -2), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        0.5,
        5.0,
    )
    assert_equal(len(kept), 2)
    assert_almost_equal(Float64(kept[0].position.z), -1.0, atol=TOLERANCE)
    assert_almost_equal(Float64(kept[1].position.z), -2.0, atol=TOLERANCE)


def test_a_segment_crossing_a_plane_is_cut_at_it() raises:
    """One end behind the near plane is moved onto it, either way round."""
    var near_first = clip_segment(
        ClipVertex(
            Vector3(0, 0, 1), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        ClipVertex(
            Vector3(0, 0, -3), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        1.0,
        5.0,
    )
    assert_equal(len(near_first), 2)
    assert_almost_equal(Float64(near_first[0].position.z), -1.0, atol=TOLERANCE)
    var near_second = clip_segment(
        ClipVertex(
            Vector3(0, 0, -3), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        ClipVertex(
            Vector3(0, 0, 1), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        1.0,
        5.0,
    )
    assert_equal(len(near_second), 2)
    assert_almost_equal(
        Float64(near_second[1].position.z), -1.0, atol=TOLERANCE
    )
    # And the far plane, which keeps the other side.
    var beyond = clip_segment(
        ClipVertex(
            Vector3(0, 0, -2), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        ClipVertex(
            Vector3(0, 0, -9), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        1.0,
        5.0,
    )
    assert_equal(len(beyond), 2)
    assert_almost_equal(Float64(beyond[1].position.z), -5.0, atol=TOLERANCE)
    var beyond_first = clip_segment(
        ClipVertex(
            Vector3(0, 0, -9), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        ClipVertex(
            Vector3(0, 0, -2), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        1.0,
        5.0,
    )
    assert_equal(len(beyond_first), 2)
    assert_almost_equal(
        Float64(beyond_first[0].position.z), -5.0, atol=TOLERANCE
    )


def test_a_segment_wholly_outside_the_range_is_thrown_away() raises:
    """Both ends behind the camera, or both past the far plane, leave
    nothing."""
    var behind = clip_segment(
        ClipVertex(
            Vector3(0, 0, 1), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        ClipVertex(
            Vector3(0, 0, 2), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        1.0,
        5.0,
    )
    assert_equal(len(behind), 0)
    var away = clip_segment(
        ClipVertex(
            Vector3(0, 0, -6), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        ClipVertex(
            Vector3(0, 0, -7), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        1.0,
        5.0,
    )
    assert_equal(len(away), 0)


def test_a_segment_clipper_refuses_an_inside_out_range() raises:
    """The two planes must be in order. A near plane behind the camera is
    allowed, as an orthographic camera may have one."""
    var a = ClipVertex(
        Vector3(0, 0, -1), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
    )
    var b = ClipVertex(
        Vector3(0, 0, -2), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
    )
    assert_equal(len(clip_segment(a, b, -1.0, 5.0)), 2)
    with assert_raises():
        _ = clip_segment(a, b, 5.0, 5.0)


def test_preparing_a_strip_gives_two_corners_a_segment() raises:
    """Three points in a strip come out as two segments, unlit and
    untextured."""
    var assets = Assets()
    var geometry = assets.geometries.add(
        points([-0.5, 0.0, 0.0, 0.0, 0.5, 0.0, 0.5, 0.0, 0.0])
    )
    var material = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = a_scene_with_one_node()
    scene.add_line(Line(geometry, material, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    var segments = renderer.prepare_lines(scene, assets, a_camera())
    assert_equal(len(segments), 4)
    for end in range(len(segments)):
        assert_true(segments[end].kind == BASIC)
        assert_true(segments[end].texture == NO_TEXTURE)
        assert_true(segments[end].alpha_map == NO_TEXTURE)
        assert_true(segments[end].blend == OPAQUE)
    # The middle point is shared: the first segment ends where the second
    # begins.
    assert_almost_equal(
        Float64(segments[1].x), Float64(segments[2].x), atol=TOLERANCE
    )
    assert_almost_equal(
        Float64(segments[1].y), Float64(segments[2].y), atol=TOLERANCE
    )


def test_a_loop_prepares_one_more_segment_than_a_strip() raises:
    """The closing segment of a loop is prepared like any other."""
    var assets = Assets()
    var geometry = assets.geometries.add(
        points([-0.5, -0.5, 0.0, 0.5, -0.5, 0.0, 0.0, 0.5, 0.0])
    )
    var material = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC)
    )
    var scene = a_scene_with_one_node()
    scene.add_line(Line(geometry, material, NodeId(0), mode=STRIP))
    var renderer = Renderer(WIDTH, HEIGHT)
    assert_equal(len(renderer.prepare_lines(scene, assets, a_camera())), 4)
    scene.lines = List[Line]()
    scene.add_line(Line(geometry, material, NodeId(0), mode=LOOP))
    assert_equal(len(renderer.prepare_lines(scene, assets, a_camera())), 6)


def test_a_line_carries_the_geometry_vertex_colors() raises:
    """An end takes the color of the point it stands on."""
    var assets = Assets()
    var geometry = points([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0])
    geometry.set_attribute(
        String(COLOR), BufferAttribute([1.0, 0.0, 0.0, 0.0, 0.0, 1.0], 3)
    )
    var stored = assets.geometries.add(geometry^)
    var material = assets.materials.add(
        Material(Color(255, 255, 255), vertex_colors=True, kind=BASIC)
    )
    var scene = a_scene_with_one_node()
    scene.add_line(Line(stored, material, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    var segments = renderer.prepare_lines(scene, assets, a_camera())
    assert_equal(len(segments), 2)
    assert_true(segments[0].color.r > segments[0].color.b)
    assert_true(segments[1].color.b > segments[1].color.r)


def test_a_line_outside_the_view_is_left_out_unless_it_says_otherwise() raises:
    """The frustum test and the layer test each leave a line out whole."""
    var assets = Assets()
    var geometry = assets.geometries.add(
        points([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0])
    )
    var material = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC)
    )
    var scene = Scene()
    var far_away = Object3D()
    far_away.set_position(50, 0, 0)
    _ = scene.add(far_away^)
    scene.update()
    var renderer = Renderer(WIDTH, HEIGHT)
    scene.add_line(Line(geometry, material, NodeId(0)))
    assert_equal(len(renderer.prepare_lines(scene, assets, a_camera())), 0)
    # The same line, opting out of the test, is transformed and then cut
    # away whole by the side planes: it is beside the view, and a segment
    # beside the view is no more drawn than one behind the camera.
    scene.lines = List[Line]()
    scene.add_line(Line(geometry, material, NodeId(0), frustum_culled=False))
    assert_equal(len(renderer.prepare_lines(scene, assets, a_camera())), 0)
    # A line on no layer the camera sees is left out before anything is
    # measured for it.
    scene.node(NodeId(0)).layers.disable(0)
    scene.update()
    assert_equal(len(renderer.prepare_lines(scene, assets, a_camera())), 0)


def test_a_line_behind_the_camera_is_clipped_away() raises:
    """A segment wholly beyond the far plane contributes nothing."""
    var assets = Assets()
    var geometry = assets.geometries.add(
        points([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0])
    )
    var material = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC)
    )
    var scene = Scene()
    var behind = Object3D()
    behind.set_position(0, 0, 40)
    _ = scene.add(behind^)
    scene.update()
    scene.add_line(Line(geometry, material, NodeId(0), frustum_culled=False))
    var renderer = Renderer(WIDTH, HEIGHT)
    assert_equal(len(renderer.prepare_lines(scene, assets, a_camera())), 0)


def test_a_line_refuses_a_material_that_does_not_suit_it() raises:
    """A lit kind, a map and an alpha map are each refused outright."""
    var assets = Assets()
    var geometry = assets.geometries.add(
        points([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0])
    )
    var image = assets.textures.add(
        checkerboard(2, 2, Color(255, 255, 255), Color(0, 0, 0))
    )
    var lit = assets.materials.add(Material(Color(255, 255, 255), kind=LAMBERT))
    var data = assets.materials.add(
        Material(Color(255, 255, 255), kind=NORMALS)
    )
    var mapped = assets.materials.add(
        Material(Color(255, 255, 255), map=image, kind=BASIC)
    )
    var masked = assets.materials.add(
        Material(Color(255, 255, 255), alpha_map=image, kind=BASIC)
    )
    var scene = a_scene_with_one_node()
    var renderer = Renderer(WIDTH, HEIGHT)
    var camera = a_camera()
    var refused: List[MaterialId] = [lit, data, mapped, masked]
    for index in range(len(refused)):
        scene.lines = List[Line]()
        scene.add_line(Line(geometry, refused[index], NodeId(0)))
        with assert_raises():
            _ = renderer.prepare_lines(scene, assets, camera)


def test_a_line_refuses_an_indexed_geometry() raises:
    """An index buffer is a triangle index, so it cannot pair points."""
    var assets = Assets()
    var geometry = points([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.5, 0.0])
    geometry.set_index([0, 1, 2])
    var stored = assets.geometries.add(geometry^)
    var material = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC)
    )
    var scene = a_scene_with_one_node()
    scene.add_line(Line(stored, material, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    with assert_raises():
        _ = renderer.prepare_lines(scene, assets, a_camera())


def test_opaque_lines_are_prepared_before_blended_ones() raises:
    """A translucent line mixes into what is already there, so it goes
    last."""
    var assets = Assets()
    var geometry = assets.geometries.add(
        points([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0])
    )
    var solid = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var clear = assets.materials.add(
        Material(Color(0, 0, 255), opacity=0.5, kind=BASIC, transparent=True)
    )
    var scene = Scene()
    var near = Object3D()
    near.set_position(0, 0, 1)
    _ = scene.add(near^)
    var away = Object3D()
    away.set_position(0, 0, -1)
    _ = scene.add(away^)
    scene.update()
    # Added blended first and opaque second, so the order below is the
    # renderer's and not the caller's.
    scene.add_line(Line(geometry, clear, NodeId(0)))
    scene.add_line(Line(geometry, solid, NodeId(1)))
    var renderer = Renderer(WIDTH, HEIGHT)
    var segments = renderer.prepare_lines(scene, assets, a_camera())
    assert_equal(len(segments), 4)
    assert_true(segments[0].blend == OPAQUE)
    assert_true(segments[2].blend == BLEND)


def test_an_opaque_line_behind_a_translucent_pane_stays_behind_it() raises:
    """A blended surface does not claim the depth, so a line drawn after
    everything passed the test and landed on top of the pane it was behind.
    The frame's draw order puts the opaque line first and the pane over it.
    """
    var assets = Assets()
    var stroke = assets.geometries.add(points([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0]))
    var sheet = assets.geometries.add(plane(Length(1, METER), Length(1, METER)))
    var blue = assets.materials.add(Material(Color(0, 0, 255), kind=BASIC))
    var glass = assets.materials.add(
        Material(
            Color(255, 0, 0),
            opacity=0.5,
            kind=BASIC,
            side=DOUBLE_SIDE,
            transparent=True,
        )
    )
    var scene = Scene()
    var near = Object3D()
    near.set_position(0, 0, 1)
    var near_node = scene.add(near^)
    var away = Object3D()
    away.set_position(0, 0, -1)
    var away_node = scene.add(away^)
    scene.update()
    scene.add_mesh(Mesh(sheet, glass, near_node))
    scene.add_line(Line(stroke, blue, away_node))
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var frame = renderer.prepare_frame(scene, assets, a_camera())
    # The line, then the pane over it.
    assert_equal(len(frame.draws), 2)
    assert_true(frame.draws[0].kind == DRAW_SEGMENTS)
    assert_true(frame.draws[1].kind == DRAW_TRIANGLES)
    var image = renderer.render(scene, assets, a_camera())
    var center = image.get_pixel(WIDTH // 2, HEIGHT // 2)
    # Half red over blue: half of each, linear, which encodes to 188.
    assert_equal(center.r, UInt8(188))
    assert_equal(center.b, UInt8(188))


def test_a_wireframe_is_sorted_among_the_lines() raises:
    """An opaque wireframe comes before a blended line, whatever order the
    scene holds them in: it used to be appended after every line."""
    var assets = Assets()
    var stroke = assets.geometries.add(points([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0]))
    var sheet = assets.geometries.add(plane(Length(1, METER), Length(1, METER)))
    var wire = assets.materials.add(
        Material(Color(255, 0, 0), kind=BASIC, wireframe=True)
    )
    var clear = assets.materials.add(
        Material(Color(0, 0, 255), opacity=0.5, kind=BASIC, transparent=True)
    )
    var scene = Scene()
    var near = Object3D()
    near.set_position(0, 0, 1)
    var near_node = scene.add(near^)
    var away = Object3D()
    away.set_position(0, 0, -1)
    var away_node = scene.add(away^)
    scene.update()
    scene.add_line(Line(stroke, clear, away_node))
    scene.add_mesh(Mesh(sheet, wire, near_node))
    var renderer = Renderer(WIDTH, HEIGHT)
    var segments = renderer.prepare_lines(scene, assets, a_camera())
    # Five edges of the wireframe's two triangles, then the one line.
    assert_equal(len(segments), 12)
    assert_true(segments[0].blend == OPAQUE)
    assert_true(segments[10].blend == BLEND)
    var frame = renderer.prepare_frame(scene, assets, a_camera())
    assert_equal(len(frame.draws), 2)
    assert_true(frame.draws[0].kind == DRAW_SEGMENTS)
    assert_equal(frame.draws[0].count, 5)
    assert_equal(frame.draws[1].first, 5)
    assert_equal(frame.draws[1].count, 1)


def test_a_rendered_line_lands_where_the_camera_puts_it() raises:
    """A horizontal line across the middle of the world paints one row."""
    var assets = Assets()
    var geometry = assets.geometries.add(
        points([-0.9, 0.0, 0.0, 0.9, 0.0, 0.0])
    )
    var material = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = a_scene_with_one_node()
    scene.add_line(Line(geometry, material, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, a_camera())
    var painted = 0
    var row = -1
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if image.get_pixel(x, y).r > 128:
                painted += 1
                if row < 0:
                    row = y
                # One pixel wide means one row, whichever row the rule
                # picks for a line lying exactly on a pixel boundary.
                assert_equal(y, row)
    assert_true(painted > 10)
    # And that row is the middle of the image, where the world origin is.
    assert_true(row == HEIGHT // 2 or row == HEIGHT // 2 - 1)


def test_a_line_is_drawn_over_the_surface_it_stands_in_front_of() raises:
    """The line pass runs after the triangles and tests their depth."""
    var assets = Assets()
    var floor = assets.geometries.add(plane(Length(4, METER), Length(4, METER)))
    var strip = assets.geometries.add(points([-0.9, 0.0, 0.5, 0.9, 0.0, 0.5]))
    var surface = assets.materials.add(Material(Color(0, 0, 255), kind=BASIC))
    var ink = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = a_scene_with_one_node()
    scene.add_mesh(Mesh(floor, surface, NodeId(0)))
    scene.add_line(Line(strip, ink, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, a_camera())
    var row = -1
    for y in range(HEIGHT):
        if image.get_pixel(WIDTH // 2, y).r > 128:
            row = y
    assert_true(row >= 0)
    assert_true(image.get_pixel(WIDTH // 2, row + 2).b > 128)
    # And the same line behind the surface is hidden by it.
    scene.lines = List[Line]()
    var buried = assets.geometries.add(
        points([-0.9, 0.0, -0.5, 0.9, 0.0, -0.5])
    )
    scene.add_line(Line(buried, ink, NodeId(0)))
    var covered = renderer.render(scene, assets, a_camera())
    assert_true(covered.get_pixel(WIDTH // 2, row).b > 128)
    assert_true(covered.get_pixel(WIDTH // 2, row).r < 128)


def test_a_line_with_no_points_prepares_nothing() raises:
    """An empty geometry has no point to join, and no segment to draw."""
    var assets = Assets()
    var geometry = assets.geometries.add(points(List[Float32]()))
    var material = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC)
    )
    var scene = a_scene_with_one_node()
    # Opting out of the frustum test, because an empty geometry has an
    # empty bound and the test would leave it out before the point loop.
    scene.add_line(Line(geometry, material, NodeId(0), frustum_culled=False))
    var renderer = Renderer(WIDTH, HEIGHT)
    assert_equal(len(renderer.prepare_lines(scene, assets, a_camera())), 0)


def test_a_wireframe_material_refuses_what_a_line_cannot_draw() raises:
    """A lit kind and a map are each refused where the flag is set."""
    with assert_raises():
        _ = Material(Color(255, 255, 255), kind=LAMBERT, wireframe=True)
    var image = checkerboard(2, 2, Color(255, 255, 255), Color(0, 0, 0))
    var stored = Assets()
    var id = stored.textures.add(image^)
    with assert_raises():
        _ = Material(Color(255, 255, 255), kind=BASIC, map=id, wireframe=True)
    with assert_raises():
        _ = Material(
            Color(255, 255, 255), kind=BASIC, alpha_map=id, wireframe=True
        )
    # And the one that is allowed keeps the flag.
    var wire = Material(Color(255, 255, 255), kind=BASIC, wireframe=True)
    assert_true(wire.wireframe)


def test_a_wireframe_mesh_prepares_lines_and_not_triangles() raises:
    """Each triangle becomes its three edges, and fills nothing."""
    var assets = Assets()
    var quad = assets.geometries.add(plane(Length(1, METER), Length(1, METER)))
    var wire = assets.materials.add(
        Material(Color(255, 0, 0), kind=BASIC, wireframe=True)
    )
    var scene = a_scene_with_one_node()
    scene.add_mesh(Mesh(quad, wire, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    assert_equal(len(renderer.prepare(scene, assets, a_camera())), 0)
    # Two triangles sharing a diagonal: five unique edges, not six, and
    # two ends an edge. `triangle_edges` pairs them, as three.js's
    # `getWireframeAttribute` does, so a blended wireframe is not drawn
    # twice over its own diagonal.
    var segments = renderer.prepare_lines(scene, assets, a_camera())
    assert_equal(len(segments), 10)
    for end in range(len(segments)):
        assert_true(segments[end].kind == BASIC)
        assert_true(segments[end].texture == NO_TEXTURE)


def test_a_wireframe_is_drawn_hollow_beside_a_filled_surface() raises:
    """The outline is painted and the middle is not."""
    var assets = Assets()
    var quad = assets.geometries.add(plane(Length(1, METER), Length(1, METER)))
    var wire = assets.materials.add(
        Material(Color(255, 0, 0), kind=BASIC, wireframe=True)
    )
    var solid = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = a_scene_with_one_node()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    scene.add_mesh(Mesh(quad, solid, NodeId(0)))
    var filled = renderer.render(scene, assets, a_camera())
    scene.meshes = List[Mesh]()
    scene.add_mesh(Mesh(quad, wire, NodeId(0)))
    var hollow = renderer.render(scene, assets, a_camera())
    var filled_pixels = 0
    var hollow_pixels = 0
    # How much of the quad's own patch of the image is still background.
    # None of it when the surface is filled, and some of it when only its
    # edges are drawn: that is the whole of what "wireframe" means.
    var filled_holes = 0
    var hollow_holes = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var inside = (
                x > WIDTH // 4
                and x < WIDTH * 3 // 4
                and y > HEIGHT // 4
                and y < HEIGHT * 3 // 4
            )
            if filled.get_pixel(x, y).r > 128:
                filled_pixels += 1
            elif inside:
                filled_holes += 1
            if hollow.get_pixel(x, y).r > 128:
                hollow_pixels += 1
            elif inside:
                hollow_holes += 1
    assert_true(filled_pixels > 0)
    assert_true(hollow_pixels > 0)
    assert_true(hollow_pixels < filled_pixels)
    assert_equal(filled_holes, 0)
    assert_true(hollow_holes > 0)


def test_a_clipped_wireframe_invents_no_edges() raises:
    """A triangle cut by the near plane keeps its three edges."""
    # Prepared as fill and cut up afterwards, this drew five: the clipper
    # leaves a quadrilateral, fanning it adds a diagonal, and the cut
    # along the near plane itself becomes an edge the mesh never had.
    # Assembling the mesh's own edges and clipping each as a segment
    # cannot invent one.
    var assets = Assets()
    # One vertex behind the near plane, two in front of it.
    var wedge = assets.geometries.add(
        points([0.0, 0.5, 4.5, -0.5, -0.5, 0.0, 0.5, -0.5, 0.0])
    )
    var wire = assets.materials.add(
        Material(Color(255, 0, 0), kind=BASIC, wireframe=True)
    )
    var scene = a_scene_with_one_node()
    scene.add_mesh(Mesh(wedge, wire, NodeId(0), frustum_culled=False))
    var renderer = Renderer(WIDTH, HEIGHT)
    var segments = renderer.prepare_lines(scene, assets, a_camera())
    # Three edges, two ends each. Two of them were cut short by the near
    # plane and are still two.
    assert_equal(len(segments), 6)


def test_a_wireframe_shows_its_far_side() raises:
    """A wireframe is submitted as lines, and a line has no facing."""
    var assets = Assets()
    var quad = assets.geometries.add(plane(Length(1, METER), Length(1, METER)))
    var wire = assets.materials.add(
        Material(Color(255, 0, 0), kind=BASIC, wireframe=True)
    )
    var solid = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = Scene()
    var turned = Object3D()
    # Half a turn, so the plane's front faces away from the camera.
    turned.rotate_y(Angle(180.0, DEGREE))
    _ = scene.add(turned^)
    scene.update()
    var renderer = Renderer(WIDTH, HEIGHT)
    # The filled front-sided surface is culled from behind.
    scene.add_mesh(Mesh(quad, solid, NodeId(0)))
    assert_equal(len(renderer.prepare(scene, assets, a_camera())), 0)
    # The wireframe is not.
    scene.meshes = List[Mesh]()
    scene.add_mesh(Mesh(quad, wire, NodeId(0)))
    assert_equal(len(renderer.prepare_lines(scene, assets, a_camera())), 10)


def test_a_wireframe_with_nothing_to_draw_prepares_nothing() raises:
    """No triangles, and every edge behind the camera, each give none."""
    var assets = Assets()
    var empty = assets.geometries.add(points(List[Float32]()))
    var quad = assets.geometries.add(plane(Length(1, METER), Length(1, METER)))
    var wire = assets.materials.add(
        Material(Color(255, 0, 0), kind=BASIC, wireframe=True)
    )
    var scene = Scene()
    _ = scene.add(Object3D())
    var behind = Object3D()
    behind.set_position(0, 0, 40)
    _ = scene.add(behind^)
    scene.update()
    var renderer = Renderer(WIDTH, HEIGHT)
    scene.add_mesh(Mesh(empty, wire, NodeId(0), frustum_culled=False))
    assert_equal(len(renderer.prepare_lines(scene, assets, a_camera())), 0)
    # And a mesh whose every edge lies beyond the far plane: the edges are
    # there, and the clipper keeps nothing of any of them.
    scene.meshes = List[Mesh]()
    scene.add_mesh(Mesh(quad, wire, NodeId(1), frustum_culled=False))
    assert_equal(len(renderer.prepare_lines(scene, assets, a_camera())), 0)


def test_a_strip_measures_its_distance_from_the_first_point() raises:
    # Points at x = 0, 1 and 3, then one a unit up: distances 0, 1, 3, 4.
    var geometry = points(
        [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 3.0, 0.0, 0.0, 3.0, 1.0, 0.0]
    )
    var along = line_distances(STRIP, geometry.attribute_view(String(POSITION)))
    assert_equal(len(along), 4)
    assert_almost_equal(Float64(along[0]), Float64(0), atol=TOLERANCE)
    assert_almost_equal(Float64(along[1]), Float64(1), atol=TOLERANCE)
    assert_almost_equal(Float64(along[2]), Float64(3), atol=TOLERANCE)
    assert_almost_equal(Float64(along[3]), Float64(4), atol=TOLERANCE)
    # A loop measures as a strip does: the closing segment runs from the
    # last distance back to zero, as three.js's does.
    var around = line_distances(LOOP, geometry.attribute_view(String(POSITION)))
    assert_equal(len(around), 4)
    assert_almost_equal(Float64(around[3]), Float64(4), atol=TOLERANCE)
    # One point has no distance to measure, and none is.
    var alone = line_distances(
        STRIP, points([1.0, 2.0, 3.0]).attribute_view(String(POSITION))
    )
    assert_equal(len(alone), 1)
    assert_equal(alone[0], Float32(0))
    # And no point at all has no distance at all.
    var none = line_distances(
        STRIP, points(List[Float32]()).attribute_view(String(POSITION))
    )
    assert_equal(len(none), 0)


def test_sticks_accumulate_their_distance_across_each_other() raises:
    # Two sticks of two units each, the second starting a unit past the
    # first's end: 0, 2, then 2 and 4. three.js's `LineSegments` carries
    # the first stick's end forward as the second's start, and the empty
    # unit between them measures nothing.
    var geometry = points(
        [0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 3.0, 0.0, 0.0, 5.0, 0.0, 0.0]
    )
    var along = line_distances(
        SEGMENTS, geometry.attribute_view(String(POSITION))
    )
    assert_almost_equal(Float64(along[1]), Float64(2), atol=TOLERANCE)
    assert_almost_equal(Float64(along[2]), Float64(2), atol=TOLERANCE)
    assert_almost_equal(Float64(along[3]), Float64(4), atol=TOLERANCE)
    # Moving the second stick away without changing its length changes
    # nothing: the gap is no line.
    var moved = points(
        [0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 30.0, 0.0, 0.0, 32.0, 0.0, 0.0]
    )
    var same = line_distances(SEGMENTS, moved.attribute_view(String(POSITION)))
    assert_almost_equal(Float64(same[2]), Float64(2), atol=TOLERANCE)
    assert_almost_equal(Float64(same[3]), Float64(4), atol=TOLERANCE)


def test_line_distances_refuse_what_the_mode_refuses() raises:
    var odd = points([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 2.0, 0.0, 0.0])
    with assert_raises(contains="pairs of points"):
        _ = line_distances(SEGMENTS, odd.attribute_view(String(POSITION)))
    with assert_raises(contains="mode that exists"):
        _ = line_distances(LineMode(9), odd.attribute_view(String(POSITION)))
    var flat = BufferGeometry()
    flat.set_attribute(
        String(POSITION), BufferAttribute([0.0, 0.0, 1.0, 0.0], 2)
    )
    with assert_raises(contains="fewer than three"):
        _ = line_distances(STRIP, flat.attribute_view(String(POSITION)))


def test_a_solid_line_prepares_no_distance_and_no_dashes() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(
        points([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0])
    )
    var material = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = a_scene_with_one_node()
    scene.add_line(Line(geometry, material, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    var segments = renderer.prepare_lines(scene, assets, a_camera())
    assert_equal(len(segments), 2)
    for end in range(2):
        assert_equal(segments[end].line_distance, Float32(0))
        assert_equal(segments[end].dash_size, Float32(0))
        assert_equal(segments[end].gap_size, Float32(0))


def test_a_dashed_line_prepares_its_scaled_distance_and_its_dashes() raises:
    # A line of one meter, at a scale of four: the far end is four along.
    # The dash and the gap ride each end unscaled, as three.js's uniforms
    # do, and the geometry's own space is measured, not the world's: the
    # node is doubled and the distance is not.
    var assets = Assets()
    var geometry = assets.geometries.add(
        points([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0])
    )
    var material = assets.materials.add(
        line_dashed_material(
            Color(255, 0, 0),
            dash_size=Length(0.3, METER),
            gap_size=Length(0.2, METER),
            scale=4,
        )
    )
    var scene = Scene()
    var node = Object3D()
    node.set_scale(2, 2, 2)
    _ = scene.add(node^)
    scene.update()
    scene.add_line(Line(geometry, material, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    var segments = renderer.prepare_lines(scene, assets, a_camera())
    assert_equal(len(segments), 2)
    assert_almost_equal(
        Float64(segments[0].line_distance), Float64(0), atol=TOLERANCE
    )
    assert_almost_equal(
        Float64(segments[1].line_distance), Float64(4), atol=TOLERANCE
    )
    for end in range(2):
        assert_almost_equal(
            Float64(segments[end].dash_size), Float64(0.3), atol=TOLERANCE
        )
        assert_almost_equal(
            Float64(segments[end].gap_size), Float64(0.2), atol=TOLERANCE
        )


def test_a_conditional_vertex_is_kept_when_its_controls_agree() raises:
    # A segment along x through the origin, seen head on: the controls
    # above it agree, one above and one below do not.
    var at = Vector3(0, 0, 0)
    var along = Vector3(1, 0, 0)
    var up = Vector3(0, 1, 0)
    assert_equal(
        conditional_discard(Matrix4(), at, along, up, Vector3(0, 2, 0)), 0
    )
    assert_equal(
        conditional_discard(Matrix4(), at, along, up, Vector3(0, -1, 0)), 1
    )
    # A control on the segment's own line is of neither side.
    assert_equal(
        conditional_discard(Matrix4(), at, along, up, Vector3(3, 0, 0)), 1
    )


def _conditional(control1_y: Float32) raises -> BufferGeometry:
    """A conditional segment along x, a control above it and one at
    `control1_y`."""
    var geometry = points([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0])
    var above: List[Float32] = [0, 1, 0, 0, 1, 0]
    var other: List[Float32] = [0, control1_y, 0, 0, control1_y, 0]
    var toward: List[Float32] = [1, 0, 0, 1, 0, 0]
    geometry.set_attribute(String(CONTROL0), BufferAttribute(above^, 3))
    geometry.set_attribute(String(CONTROL1), BufferAttribute(other^, 3))
    geometry.set_attribute(String(DIRECTION), BufferAttribute(toward^, 3))
    return geometry^


def test_a_conditional_line_prepares_its_flags_as_a_dash() raises:
    var assets = Assets()
    var shown = assets.geometries.add(_conditional(1))
    var hidden = assets.geometries.add(_conditional(-1))
    var material = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = a_scene_with_one_node()
    scene.add_line(
        Line(shown, material, NodeId(0), mode=SEGMENTS, conditional=True)
    )
    scene.add_line(
        Line(hidden, material, NodeId(0), mode=SEGMENTS, conditional=True)
    )
    var renderer = Renderer(WIDTH, HEIGHT)
    var segments = renderer.prepare_lines(scene, assets, a_camera())
    assert_equal(len(segments), 4)
    assert_equal(segments[0].line_distance, Float32(0))
    assert_equal(segments[1].line_distance, Float32(0))
    assert_equal(segments[2].line_distance, Float32(1))
    assert_equal(segments[3].line_distance, Float32(1))
    for end in range(4):
        assert_equal(segments[end].dash_size, Float32(0.5))
        assert_equal(segments[end].gap_size, Float32(1))
    # Drawn, the first shows and the second does not.
    var image = renderer.render(scene, assets, a_camera())
    var red = 0
    for x in range(WIDTH):
        for y in range(HEIGHT):
            if image.get_pixel(x, y).r > 200:
                red += 1
    assert_true(red > 0)
    var alone = a_scene_with_one_node()
    alone.add_line(
        Line(hidden, material, NodeId(0), mode=SEGMENTS, conditional=True)
    )
    var none = renderer.render(alone, assets, a_camera())
    for x in range(WIDTH):
        for y in range(HEIGHT):
            assert_true(none.get_pixel(x, y).r < 200)


def test_a_conditional_line_refuses_what_it_cannot_draw() raises:
    var assets = Assets()
    with assert_raises(contains="SEGMENTS"):
        _ = Line(GeometryId(0), MaterialId(0), NodeId(0), conditional=True)
    var bare = assets.geometries.add(points([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0]))
    var plain = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = a_scene_with_one_node()
    scene.add_line(
        Line(bare, plain, NodeId(0), mode=SEGMENTS, conditional=True)
    )
    var renderer = Renderer(WIDTH, HEIGHT)
    with assert_raises(contains="control0"):
        _ = renderer.prepare_lines(scene, assets, a_camera())
    var dashed = assets.materials.add(line_dashed_material(Color(255, 0, 0)))
    var shape = assets.geometries.add(_conditional(1))
    var again = a_scene_with_one_node()
    again.add_line(
        Line(shape, dashed, NodeId(0), mode=SEGMENTS, conditional=True)
    )
    with assert_raises(contains="not dashed"):
        _ = renderer.prepare_lines(again, assets, a_camera())


def test_a_dashed_line_with_no_points_prepares_nothing() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(points(List[Float32]()))
    var material = assets.materials.add(line_dashed_material(Color(255, 0, 0)))
    var scene = a_scene_with_one_node()
    scene.add_line(Line(geometry, material, NodeId(0), frustum_culled=False))
    var renderer = Renderer(WIDTH, HEIGHT)
    assert_equal(len(renderer.prepare_lines(scene, assets, a_camera())), 0)


def test_a_dashed_line_renders_with_gaps_in_it() raises:
    # Two meters of world across sixteen pixels: an eighth of a meter a
    # pixel. A dash of half a meter and a gap of half a meter light four
    # pixels, then leave four, along the whole row.
    var assets = Assets()
    var geometry = assets.geometries.add(
        points([-1.0, 0.0, 0.0, 1.0, 0.0, 0.0])
    )
    var material = assets.materials.add(
        line_dashed_material(
            Color(255, 255, 255),
            dash_size=Length(0.5, METER),
            gap_size=Length(0.5, METER),
        )
    )
    var scene = a_scene_with_one_node()
    scene.add_line(Line(geometry, material, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, a_camera())
    var lit = 0
    var row = -1
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if image.get_pixel(x, y).r > 128:
                lit += 1
                row = y
    assert_equal(lit, 8)
    # The first dash starts at the left edge, whichever way the row runs.
    assert_true(image.get_pixel(0, row).r > 128)
    assert_true(image.get_pixel(3, row).r > 128)
    assert_false(image.get_pixel(4, row).r > 128)
    assert_false(image.get_pixel(7, row).r > 128)
    assert_true(image.get_pixel(8, row).r > 128)
    assert_false(image.get_pixel(15, row).r > 128)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
