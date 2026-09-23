# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.line_segments2`, `line_material` and the wide-line
path through `Renderer.prepare` and `Raycaster.intersect_wide_line`.

The camera is orthographic and sees two meters across sixteen pixels, so a
world coordinate lands on a pixel by arithmetic: eight pixels a meter, the
origin on the corner between pixels (7, 7) and (8, 8).
"""

from cameras.orthographic_camera import OrthographicCamera, centered
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from core.geometry_store import GeometryId
from core.layers import Layers
from core.object3d import NodeId, Object3D
from core.raycaster import HitKind, Raycaster, WIDE_LINE_HIT
from core.scene import Scene
from materials.material import (
    BASIC,
    DEFAULT_LINE_WIDTH,
    LAMBERT,
    LineWidth,
    Material,
    MaterialId,
    NO_DASH,
    line_material,
)
from math.vector3 import Vector3
from objects.line import Line
from objects.line_segments2 import (
    Line2,
    LineSegments2,
    MAX_CAP_STEPS,
    MIN_CAP_STEPS,
    cap_steps,
    dash_spans,
    line_geometry,
    line_segments_geometry,
)
from render.cube_texture_store import SCENE_ENVIRONMENT
from render.framebuffer import Color, FloatColor, Framebuffer
from render.texture import checkerboard
from render.texture_store import NO_TEXTURE
from renderers.renderer import Renderer
from std.math import inf, nan
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
comptime SIZE = 16
comptime RED = Color(255, 0, 0)


def a_camera() raises -> OrthographicCamera:
    """Return a camera looking down -z at a two-meter square of world."""
    var camera = centered(
        Length(2.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def a_perspective() raises -> PerspectiveCamera:
    """Return a camera four meters back, looking down -z at the origin."""
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1.0, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def a_scene() raises -> Scene:
    """Return a scene holding one node at the origin, updated."""
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    return scene^


def sticks(var numbers: List[Float32]) raises -> BufferGeometry:
    """Return a geometry holding `numbers` as positions, three per point."""
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(numbers^, 3))
    return geometry^


def lit(image: Framebuffer, x: Int, y: Int) raises -> Bool:
    """Return True if the pixel is mostly red."""
    return image.get_pixel(x, y).r > 128


def draw(
    points: List[Vector3], material: Material, antialias: Bool = False
) raises -> Framebuffer:
    """Render one wide line through `points`, in pairs, on the camera."""
    var assets = Assets()
    var geometry = assets.geometries.add(line_segments_geometry(points))
    var paint = assets.materials.add(material)
    var scene = a_scene()
    scene.add_wide_line(LineSegments2(geometry, paint, NodeId(0)))
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    renderer.set_antialias(antialias)
    return renderer.render(scene, assets, a_camera())


def across_x() -> List[Vector3]:
    """Return one stick from -0.5 to 0.5 along x: pixels 4 to 12."""
    return [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0)]


def rows_lit(image: Framebuffer, x: Int) raises -> Int:
    """Return how many pixels of one column are lit."""
    var count = 0
    for y in range(SIZE):
        if lit(image, x, y):
            count += 1
    return count


# The material.


def test_a_line_width_is_positive_and_finite() raises:
    assert_true(LineWidth(pixels=1).is_valid())
    assert_true(LineWidth(world=Length(0.2, METER)).is_valid())
    assert_false(LineWidth(pixels=0).is_valid())
    assert_false(LineWidth(pixels=-2).is_valid())
    assert_false(LineWidth(pixels=inf[DType.float32]()).is_valid())
    assert_false(LineWidth(pixels=nan[DType.float32]()).is_valid())


def test_line_material_carries_three_js_defaults() raises:
    var material = line_material()
    assert_true(material.kind == BASIC)
    assert_true(material.line_width == DEFAULT_LINE_WIDTH)
    assert_false(material.line_width.world_units)
    assert_equal(material.line_width.size, 1)
    assert_true(material.dash_offset == NO_DASH)
    assert_false(material.is_dashed())
    var world = line_material(
        RED,
        LineWidth(world=Length(0.25, METER)),
        dash_size=Length(0.5, METER),
        gap_size=Length(0.25, METER),
        dash_scale=2,
        dash_offset=Length(0.1, METER),
    )
    assert_true(world.line_width.world_units)
    assert_almost_equal(world.line_width.size, 0.25, atol=TOLERANCE)
    assert_true(world.is_dashed())
    assert_equal(world.dash_scale, 2)


def test_a_material_refuses_a_width_it_cannot_draw() raises:
    with assert_raises(contains="positive, finite"):
        _ = line_material(RED, LineWidth(pixels=0))
    with assert_raises(contains="dash offset must be finite"):
        _ = line_material(RED, dash_offset=Length(inf[DType.float32](), METER))
    with assert_raises(contains="Only a basic material draws a wide line"):
        _ = Material(RED, kind=LAMBERT, line_width=LineWidth(pixels=3))
    with assert_raises(contains="Only a basic material draws a wide line"):
        _ = Material(RED, kind=LAMBERT, dash_offset=Length(1.0, METER))
    with assert_raises(contains="A wireframe is one pixel wide"):
        _ = Material(
            RED, kind=BASIC, wireframe=True, line_width=LineWidth(pixels=3)
        )
    # The defaults are what every other material carries without reading.
    _ = Material(RED, kind=LAMBERT)
    _ = Material(RED, kind=BASIC, wireframe=True)


# The objects and their geometry.


def test_a_wide_line_names_three_ids() raises:
    var line = LineSegments2(GeometryId(1), MaterialId(2), NodeId(3))
    assert_equal(line.geometry.value, 1)
    assert_equal(line.material.value, 2)
    assert_equal(line.node.value, 3)
    assert_true(line.frustum_culled)
    var path = Line2(
        GeometryId(0), MaterialId(0), NodeId(0), frustum_culled=False
    )
    assert_false(path.frustum_culled)
    with assert_raises(contains="scene node"):
        _ = LineSegments2(GeometryId(0), MaterialId(0), NodeId(-1))
    with assert_raises(contains="geometry"):
        _ = LineSegments2(GeometryId(-1), MaterialId(0), NodeId(0))
    with assert_raises(contains="material"):
        _ = LineSegments2(GeometryId(0), MaterialId(-1), NodeId(0))


def test_a_segments_geometry_keeps_its_pairs_and_colors() raises:
    var points: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 1, 1),
    ]
    var plain = line_segments_geometry(points)
    assert_equal(plain.attribute_view(String(POSITION)).count(), 4)
    assert_false(plain.has_attribute(String(COLOR)))
    var colors: List[FloatColor] = [
        FloatColor(1, 0, 0),
        FloatColor(0, 1, 0),
        FloatColor(0, 0, 1),
        FloatColor(1, 1, 1),
    ]
    var tinted = line_segments_geometry(points, colors)
    ref channels = tinted.attribute_view(String(COLOR))
    assert_equal(channels.item_size, 3)
    assert_equal(channels.component(2, 2), 1)
    with assert_raises(contains="pairs of points"):
        _ = line_segments_geometry([Vector3(0, 0, 0)])
    with assert_raises(contains="one color per point"):
        _ = line_segments_geometry(points, [FloatColor(1, 0, 0)])


def test_a_path_geometry_repeats_its_inner_points() raises:
    var points: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(1, 1, 0),
    ]
    var colors: List[FloatColor] = [
        FloatColor(1, 0, 0),
        FloatColor(0, 1, 0),
        FloatColor(0, 0, 1),
    ]
    var path = line_geometry(points, colors)
    ref positions = path.attribute_view(String(POSITION))
    assert_equal(positions.count(), 4)
    assert_equal(positions.vector3(1).x, 1)
    assert_equal(positions.vector3(2).x, 1)
    assert_equal(positions.vector3(3).y, 1)
    ref tints = path.attribute_view(String(COLOR))
    assert_equal(tints.component(1, 1), 1)
    assert_equal(tints.component(2, 1), 1)
    var bare = line_geometry(points)
    assert_false(bare.has_attribute(String(COLOR)))
    # One point is no segment, and no point is none either.
    var lone = line_geometry([Vector3(0, 0, 0)])
    assert_equal(lone.attribute_view(String(POSITION)).count(), 0)
    with assert_raises(contains="one color per point"):
        _ = line_geometry(points, [FloatColor(1, 0, 0)])


def test_a_cap_is_finer_the_bigger_it_is() raises:
    assert_equal(cap_steps(0), MIN_CAP_STEPS)
    assert_equal(cap_steps(-3), MIN_CAP_STEPS)
    assert_equal(cap_steps(4), 7)
    assert_equal(cap_steps(10000), MAX_CAP_STEPS)


def test_dash_spans_follow_the_fold() raises:
    # Solid: the whole segment.
    var solid = dash_spans(0, 5, 1, 0)
    assert_equal(len(solid), 2)
    assert_equal(solid[0], 0)
    assert_equal(solid[1], 1)
    # A dash of one and a gap of one along four units: two dashes.
    var two = dash_spans(0, 4, 1, 1)
    assert_equal(len(two), 4)
    assert_almost_equal(two[0], 0, atol=TOLERANCE)
    assert_almost_equal(two[1], 0.25, atol=TOLERANCE)
    assert_almost_equal(two[2], 0.5, atol=TOLERANCE)
    assert_almost_equal(two[3], 0.75, atol=TOLERANCE)
    # Backward, the same parts from the other end, smaller first.
    var back = dash_spans(4, 0, 1, 1)
    assert_equal(len(back), 4)
    assert_almost_equal(back[0], 0.75, atol=TOLERANCE)
    assert_almost_equal(back[1], 1, atol=TOLERANCE)
    # Below zero the fold still lands inside the period.
    var negative = dash_spans(-1.5, -0.5, 1, 1)
    assert_equal(len(negative), 2)
    assert_almost_equal(negative[0], 0, atol=TOLERANCE)
    assert_almost_equal(negative[1], 0.5, atol=TOLERANCE)
    # A segment whose distance does not change is all dash or all gap.
    assert_equal(len(dash_spans(0.5, 0.5, 1, 1)), 2)
    assert_equal(len(dash_spans(1.5, 1.5, 1, 1)), 0)
    with assert_raises(contains="too fine"):
        _ = dash_spans(0, 10000, 0.5, 0.5)


def test_a_scene_takes_a_wide_line_on_one_of_its_nodes() raises:
    var scene = a_scene()
    scene.add_wide_line(LineSegments2(GeometryId(0), MaterialId(0), NodeId(0)))
    assert_equal(len(scene.wide_lines), 1)
    with assert_raises(contains="node that is in the scene"):
        scene.add_wide_line(
            LineSegments2(GeometryId(0), MaterialId(0), NodeId(4))
        )


# Drawing.


def test_a_line_in_pixels_is_as_wide_as_asked() raises:
    var image = draw(across_x(), line_material(RED, LineWidth(pixels=4)))
    assert_equal(rows_lit(image, 8), 4)
    assert_true(lit(image, 8, 6))
    assert_true(lit(image, 8, 9))
    assert_false(lit(image, 8, 5))
    # The round cap reaches two pixels past each end.
    assert_true(lit(image, 13, 7))
    assert_true(lit(image, 2, 8))
    assert_false(lit(image, 14, 7))
    # A corner of the square around the cap is left out.
    assert_false(lit(image, 13, 6))


def test_a_supersampled_line_keeps_its_width_in_output_pixels() raises:
    var image = draw(
        across_x(), line_material(RED, LineWidth(pixels=4)), antialias=True
    )
    assert_equal(rows_lit(image, 8), 4)


def test_a_line_in_the_world_is_as_wide_as_asked() raises:
    var image = draw(
        across_x(), line_material(RED, LineWidth(world=Length(0.5, METER)))
    )
    assert_equal(rows_lit(image, 8), 4)
    assert_true(lit(image, 13, 7))


def test_a_dashed_line_is_cut_and_has_no_caps() raises:
    var points: List[Vector3] = [Vector3(-0.75, 0, 0), Vector3(0.75, 0, 0)]
    var image = draw(
        points,
        line_material(
            RED,
            LineWidth(pixels=4),
            dash_size=Length(0.25, METER),
            gap_size=Length(0.25, METER),
        ),
    )
    assert_true(lit(image, 2, 8))
    assert_true(lit(image, 3, 8))
    assert_false(lit(image, 4, 8))
    assert_false(lit(image, 5, 8))
    assert_true(lit(image, 6, 8))
    assert_false(lit(image, 1, 8))
    # Slid a quarter meter, the dashes and the gaps change places.
    var slid = draw(
        points,
        line_material(
            RED,
            LineWidth(pixels=4),
            dash_size=Length(0.25, METER),
            gap_size=Length(0.25, METER),
            dash_offset=Length(0.25, METER),
        ),
    )
    assert_false(lit(slid, 2, 8))
    assert_true(lit(slid, 4, 8))
    # Scaled by two, each dash covers half as many pixels.
    var scaled = draw(
        points,
        line_material(
            RED,
            LineWidth(pixels=4),
            dash_size=Length(0.25, METER),
            gap_size=Length(0.25, METER),
            dash_scale=2,
        ),
    )
    assert_true(lit(scaled, 2, 8))
    assert_false(lit(scaled, 3, 8))


def test_a_wide_line_carries_its_vertex_colors() raises:
    var assets = Assets()
    var colors: List[FloatColor] = [FloatColor(1, 0, 0), FloatColor(0, 0, 1)]
    var geometry = assets.geometries.add(
        line_segments_geometry(across_x(), colors)
    )
    var paint = assets.materials.add(
        line_material(
            Color(255, 255, 255), LineWidth(pixels=4), vertex_colors=True
        )
    )
    var scene = a_scene()
    scene.add_wide_line(LineSegments2(geometry, paint, NodeId(0)))
    var image = Renderer(SIZE, SIZE).render(scene, assets, a_camera())
    var left = image.get_pixel(4, 8)
    var right = image.get_pixel(11, 8)
    assert_true(left.r > left.b)
    assert_true(right.b > right.r)


def test_a_segment_of_no_length_is_a_round_dot() raises:
    var points: List[Vector3] = [Vector3(0, 0, 0), Vector3(0, 0, 0)]
    var image = draw(points, line_material(RED, LineWidth(pixels=4)))
    assert_true(lit(image, 7, 7))
    assert_true(lit(image, 8, 8))
    assert_false(lit(image, 10, 8))
    var world = draw(
        points, line_material(RED, LineWidth(world=Length(0.5, METER)))
    )
    assert_true(lit(world, 7, 7))
    assert_false(lit(world, 10, 8))


def test_a_segment_pointing_at_the_eye_is_a_disc_in_the_world() raises:
    var points: List[Vector3] = [Vector3(0, 0, 1), Vector3(0, 0, -1)]
    var image = draw(
        points, line_material(RED, LineWidth(world=Length(0.5, METER)))
    )
    assert_true(lit(image, 7, 7))
    assert_true(lit(image, 8, 8))
    assert_true(lit(image, 9, 8))
    assert_false(lit(image, 11, 8))


def test_a_segment_is_cut_at_the_near_plane_and_the_image_edge() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(
        line_segments_geometry(
            [
                # Through the near plane, toward the camera and past it.
                Vector3(0.2, 0, 0),
                Vector3(0.2, 0, 8),
                # Wholly behind the camera.
                Vector3(-0.5, 0, 5),
                Vector3(0.5, 0, 6),
                # Across the whole image and beyond its edges.
                Vector3(-9, -0.5, 0),
                Vector3(9, -0.5, 0),
            ]
        )
    )
    var paint = assets.materials.add(line_material(RED, LineWidth(pixels=3)))
    var scene = a_scene()
    scene.add_wide_line(
        LineSegments2(geometry, paint, NodeId(0), frustum_culled=False)
    )
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, a_perspective())
    assert_true(lit(image, 0, 10))
    assert_true(lit(image, SIZE - 1, 10))
    var corners = renderer.prepare(scene, assets, a_perspective())
    assert_true(len(corners) > 0)
    assert_equal(len(corners) % 3, 0)


def test_a_wide_line_is_sorted_and_culled_like_a_mesh() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(line_segments_geometry(across_x()))
    var far_away = assets.geometries.add(
        line_segments_geometry([Vector3(50, 0, 0), Vector3(51, 0, 0)])
    )
    var paint = assets.materials.add(line_material(RED, LineWidth(pixels=2)))
    var scene = a_scene()
    scene.add_wide_line(LineSegments2(far_away, paint, NodeId(0)))
    var renderer = Renderer(SIZE, SIZE)
    assert_equal(len(renderer.prepare(scene, assets, a_camera())), 0)
    scene.add_wide_line(LineSegments2(geometry, paint, NodeId(0)))
    var shown = len(renderer.prepare(scene, assets, a_camera()))
    assert_true(shown > 0)
    # The wireframe half holds no wide line: it is drawn as triangles.
    assert_equal(len(renderer.prepare_lines(scene, assets, a_camera())), 0)
    var frame = renderer.prepare_frame(scene, assets, a_camera())
    assert_equal(len(frame.draws), 1)
    # A node on a layer the camera does not see contributes nothing.
    var hidden = Layers()
    hidden.set(3)
    scene.node(NodeId(0)).layers = hidden
    scene.update()
    assert_equal(len(renderer.prepare(scene, assets, a_camera())), 0)


def refused(
    assets: Assets, geometry: GeometryId, material: MaterialId, message: String
) raises:
    """Assert that preparing one wide line raises `message`."""
    var scene = a_scene()
    scene.add_wide_line(
        LineSegments2(geometry, material, NodeId(0), frustum_culled=False)
    )
    with assert_raises(contains=message):
        _ = Renderer(SIZE, SIZE).prepare(scene, assets, a_camera())


def test_a_line_with_nothing_to_draw_draws_nothing() raises:
    var assets = Assets()
    var empty = assets.geometries.add(line_segments_geometry(List[Vector3]()))
    var short = assets.geometries.add(
        line_segments_geometry([Vector3(0.3, 0, 0), Vector3(0.4, 0, 0)])
    )
    var dashed = assets.materials.add(
        line_material(
            RED,
            LineWidth(pixels=4),
            dash_size=Length(0.25, METER),
            gap_size=Length(0.25, METER),
            dash_offset=Length(0.3, METER),
        )
    )
    var scene = a_scene()
    # No points at all, and one stick that lies wholly in a gap.
    scene.add_wide_line(
        LineSegments2(empty, dashed, NodeId(0), frustum_culled=False)
    )
    scene.add_wide_line(LineSegments2(short, dashed, NodeId(0)))
    var renderer = Renderer(SIZE, SIZE)
    assert_equal(len(renderer.prepare(scene, assets, a_camera())), 0)
    # A wireframe elsewhere in the assets sends the scene through the
    # wireframe half too, which leaves the wide lines to `prepare`.
    _ = assets.materials.add(Material(RED, kind=BASIC, wireframe=True))
    assert_equal(len(renderer.prepare_lines(scene, assets, a_camera())), 0)


def test_a_wide_line_refuses_what_it_cannot_draw() raises:
    var assets = Assets()
    var good = assets.geometries.add(line_segments_geometry(across_x()))
    var odd = assets.geometries.add(sticks([0.0, 0.0, 0.0]))
    var indexed = sticks([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0])
    indexed.set_index([0, 1, 2])
    var indexed_id = assets.geometries.add(indexed^)
    var board = assets.textures.add(
        checkerboard(4, 2, Color(0, 0, 0), Color(255, 255, 255))
    )
    var fine = assets.materials.add(line_material(RED))
    var lit_kind = assets.materials.add(Material(RED))
    var mapped = assets.materials.add(Material(RED, kind=BASIC, map=board))
    var masked = assets.materials.add(
        Material(RED, kind=BASIC, alpha_map=board)
    )
    var shiny = assets.materials.add(
        Material(RED, kind=BASIC, env_map=SCENE_ENVIRONMENT)
    )
    var wire = assets.materials.add(Material(RED, kind=BASIC, wireframe=True))
    var baked = assets.materials.add(Material(RED, kind=BASIC, ao_map=board))
    var tinted = assets.materials.add(line_material(RED, vertex_colors=True))
    refused(assets, good, lit_kind, "must be BASIC")
    refused(assets, good, mapped, "has no map")
    refused(assets, good, masked, "has no map")
    refused(assets, good, shiny, "has no env map")
    refused(assets, good, baked, "has no ao map or light map")
    refused(assets, good, wire, "cannot be a wireframe")
    refused(assets, indexed_id, fine, "cannot be indexed")
    refused(assets, odd, fine, "pairs of points")
    refused(assets, good, tinted, "vertex colors")


def test_a_one_pixel_line_refuses_a_width_or_an_offset() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(line_segments_geometry(across_x()))
    var wide = assets.materials.add(line_material(RED, LineWidth(pixels=3)))
    var slid = assets.materials.add(
        line_material(RED, dash_offset=Length(0.5, METER))
    )
    var plain = assets.materials.add(line_material(RED))
    var renderer = Renderer(SIZE, SIZE)
    var scene = a_scene()
    scene.add_line(Line(geometry, plain, NodeId(0)))
    assert_true(len(renderer.prepare_lines(scene, assets, a_camera())) > 0)
    scene.lines = List[Line]()
    scene.add_line(Line(geometry, wide, NodeId(0)))
    with assert_raises(contains="one pixel wide"):
        _ = renderer.prepare_lines(scene, assets, a_camera())
    scene.lines = List[Line]()
    scene.add_line(Line(geometry, slid, NodeId(0)))
    with assert_raises(contains="one pixel wide"):
        _ = renderer.prepare_lines(scene, assets, a_camera())


# Picking.


def test_a_wide_line_hit_kind_is_valid() raises:
    assert_true(WIDE_LINE_HIT.is_valid())
    assert_false(HitKind(9).is_valid())


def picked(
    scene: Scene,
    assets: Assets,
    x: Float32,
    y: Float32,
    near: Float32 = 0,
    far: Float32 = 100,
) raises -> Int:
    """Return how many segments a pick through pixel (x, y) strikes."""
    var ray = Raycaster(
        Vector3(0, 0, 0),
        Vector3(0, 0, -1),
        Length(near, METER),
        Length(far, METER),
    )
    ray.set_from_pixel(x, y, SIZE, SIZE, a_perspective(), scene)
    return len(
        ray.intersect_wide_line(scene, assets, 0, a_perspective(), SIZE, SIZE)
    )


def test_a_pick_in_pixels_strikes_within_half_the_width() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(line_segments_geometry(across_x()))
    var paint = assets.materials.add(line_material(RED, LineWidth(pixels=4)))
    var scene = a_scene()
    scene.add_wide_line(LineSegments2(geometry, paint, NodeId(0)))
    assert_equal(picked(scene, assets, 8, 8), 1)
    assert_equal(picked(scene, assets, 8, 9.5), 1)
    assert_equal(picked(scene, assets, 8, 11), 0)
    # Far outside the bound, the ray misses before any segment is asked.
    assert_equal(picked(scene, assets, 0.5, 0.5), 0)
    # The distance is honored as a mesh hit's is.
    assert_equal(picked(scene, assets, 8, 8, far=1), 0)
    assert_equal(picked(scene, assets, 8, 8, near=5), 0)
    var ray = Raycaster(Vector3(0, 0, 0), Vector3(0, 0, -1))
    ray.set_from_pixel(8, 8, SIZE, SIZE, a_perspective(), scene)
    var hits = ray.intersect_wide_line(
        scene, assets, 0, a_perspective(), SIZE, SIZE
    )
    assert_true(hits[0].kind == WIDE_LINE_HIT)
    assert_equal(hits[0].triangle, 0)
    assert_equal(hits[0].instance, -1)
    assert_almost_equal(hits[0].distance, 4, atol=Float64(1e-3))
    assert_almost_equal(hits[0].normal.z, 1, atol=TOLERANCE)


def test_a_pick_in_pixels_trims_a_segment_at_the_near_plane() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(
        line_segments_geometry(
            [
                # From in front of the camera to behind it, both ways. The
                # end in front lands under two pixels from the middle.
                Vector3(0, -0.5, 0),
                Vector3(0, 0, 9),
                Vector3(0, 0, 9),
                Vector3(0, -0.5, 0),
                # Wholly behind the camera.
                Vector3(0, 0, 6),
                Vector3(0, 0, 9),
            ]
        )
    )
    var paint = assets.materials.add(line_material(RED, LineWidth(pixels=4)))
    var scene = a_scene()
    scene.add_wide_line(LineSegments2(geometry, paint, NodeId(0)))
    assert_equal(picked(scene, assets, 8, 8), 2)


def test_a_pick_in_pixels_ignores_a_segment_beyond_the_far_plane() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(
        line_segments_geometry([Vector3(-1, 0, -30), Vector3(1, 0, -30)])
    )
    var paint = assets.materials.add(line_material(RED, LineWidth(pixels=4)))
    var scene = a_scene()
    scene.add_wide_line(LineSegments2(geometry, paint, NodeId(0)))
    assert_equal(picked(scene, assets, 8, 8), 0)


def test_a_pick_in_pixels_measures_a_dot_as_a_point() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(
        line_segments_geometry([Vector3(0, 0, 0), Vector3(0, 0, 0)])
    )
    var paint = assets.materials.add(line_material(RED, LineWidth(pixels=4)))
    var scene = a_scene()
    scene.add_wide_line(LineSegments2(geometry, paint, NodeId(0)))
    assert_equal(picked(scene, assets, 8, 8), 1)


def test_a_pick_in_the_world_strikes_within_half_the_width() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(line_segments_geometry(across_x()))
    var paint = assets.materials.add(
        line_material(RED, LineWidth(world=Length(0.5, METER)))
    )
    var scene = a_scene()
    scene.add_wide_line(LineSegments2(geometry, paint, NodeId(0)))
    var ray = Raycaster(Vector3(0, 0.2, 5), Vector3(0, 0, -1))
    var hits = ray.intersect_wide_line(scene, assets, 0, a_camera(), SIZE, SIZE)
    assert_equal(len(hits), 1)
    assert_almost_equal(hits[0].point.z, 0, atol=TOLERANCE)
    assert_almost_equal(hits[0].distance, 5, atol=TOLERANCE)
    ray.set(Vector3(0, 0.3, 5), Vector3(0, 0, -1))
    assert_equal(
        len(ray.intersect_wide_line(scene, assets, 0, a_camera(), SIZE, SIZE)),
        0,
    )


def test_a_pick_skips_a_hidden_or_empty_line_and_refuses_nonsense() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(line_segments_geometry(across_x()))
    var empty = assets.geometries.add(line_segments_geometry(List[Vector3]()))
    var paint = assets.materials.add(line_material(RED, LineWidth(pixels=4)))
    var scene = a_scene()
    scene.add_wide_line(LineSegments2(empty, paint, NodeId(0)))
    scene.add_wide_line(LineSegments2(geometry, paint, NodeId(0)))
    var ray = Raycaster(Vector3(0, 0, 5), Vector3(0, 0, -1))
    var camera = a_camera()
    assert_equal(
        len(ray.intersect_wide_line(scene, assets, 0, camera, SIZE, SIZE)), 0
    )
    assert_equal(
        len(ray.intersect_wide_line(scene, assets, 1, camera, SIZE, SIZE)), 1
    )
    with assert_raises(contains="No wide line"):
        _ = ray.intersect_wide_line(scene, assets, 2, camera, SIZE, SIZE)
    with assert_raises(contains="No wide line"):
        _ = ray.intersect_wide_line(scene, assets, -1, camera, SIZE, SIZE)
    with assert_raises(contains="positive width and height"):
        _ = ray.intersect_wide_line(scene, assets, 1, camera, 0, SIZE)
    with assert_raises(contains="positive width and height"):
        _ = ray.intersect_wide_line(scene, assets, 1, camera, SIZE, 0)
    var hidden = Layers()
    hidden.set(3)
    scene.node(NodeId(0)).layers = hidden
    scene.update()
    assert_equal(
        len(ray.intersect_wide_line(scene, assets, 1, camera, SIZE, SIZE)), 0
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
