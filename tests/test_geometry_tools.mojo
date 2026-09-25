# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.curves` and `cameras.camera_utils`.

`assets/geometry_tools/three.json` holds what three.js r180's
`GeometryUtils` and `CameraUtils.frameCorners` give, and `coaster.json` what
its `RollerCoaster.js` builds, run in Node by `three_tools.mjs` beside them.
"""

from cameras.camera_utils import frame_corners
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import box
from geometries.convex_object_breaker import (
    BreakableObject,
    ConvexObjectBreaker,
)
from geometries.curves import gosper, hilbert2d, hilbert3d
from geometries.plane import plane
from geometries.tube_painter import TubePainter
from helpers.uvs_debug import UVS_BACKGROUND, UVS_LINE, uvs_debug
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, UV
from geometries.roller_coaster import (
    roller_coaster_geometry,
    roller_coaster_lifters_geometry,
    roller_coaster_shadow_geometry,
    sky_geometry,
    trees_geometry,
)
from materials.material import Material
from math.space_curve import Point3, SpaceCurve, chord_tangent, point3
from math.utils import SeededRandom
from objects.mesh import Mesh
from render.framebuffer import Color
from std.math import cos, pi, sin
from loaders.json import JsonDocument, parse_json
from math.vector3 import Vector3
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from math.bounds import Plane
from math.quaternion import Quaternion
from units.si import Angle, DEGREE, KILOGRAM, Length, METER, Mass, RADIAN

comptime TOLERANCE = Float64(1e-4)


def _reference() raises -> JsonDocument:
    """Return what three.js gave."""
    return parse_json(Path("assets/geometry_tools/three.json").read_text())


def _assert_points(got: List[Vector3], doc: JsonDocument, want: Int) raises:
    """Assert points match a flat list of the reference."""
    assert_equal(len(got) * 3, doc.length(want))
    for at in range(len(got)):
        assert_almost_equal(
            Float64(got[at].x), doc.number(doc.at(want, 3 * at)), atol=TOLERANCE
        )
        assert_almost_equal(
            Float64(got[at].y),
            doc.number(doc.at(want, 3 * at + 1)),
            atol=TOLERANCE,
        )
        assert_almost_equal(
            Float64(got[at].z),
            doc.number(doc.at(want, 3 * at + 2)),
            atol=TOLERANCE,
        )


# --- the curves -------------------------------------------------------------


def test_a_hilbert_square_matches_three_js() raises:
    var doc = _reference()
    var section = doc.get(doc.root(), "hilbert2d")
    _assert_points(hilbert2d(), doc, doc.get(section, "plain"))
    _assert_points(
        hilbert2d(Vector3(1, 2, 3), Length(4.0, METER), 2, [1, 2, 3, 0]),
        doc,
        doc.get(section, "moved"),
    )


def test_a_hilbert_cube_matches_three_js() raises:
    var doc = _reference()
    var section = doc.get(doc.root(), "hilbert3d")
    _assert_points(hilbert3d(), doc, doc.get(section, "plain"))
    _assert_points(
        hilbert3d(
            Vector3(-1, 0, 2),
            Length(6.0, METER),
            2,
            [7, 6, 5, 4, 3, 2, 1, 0],
        ),
        doc,
        doc.get(section, "moved"),
    )


def test_a_hilbert_curve_refuses_a_bad_order() raises:
    with assert_raises(contains="negative iteration"):
        _ = hilbert2d(iterations=-1)
    with assert_raises(contains="negative iteration"):
        _ = hilbert3d(iterations=-1)
    with assert_raises(contains="every corner"):
        _ = hilbert2d(order=[0, 1, 2])
    with assert_raises(contains="each corner once"):
        _ = hilbert3d(order=[0, 1, 2, 3, 4, 5, 6, 6])
    # No iteration is the one cell's corners.
    assert_equal(len(hilbert2d(iterations=0)), 4)


def test_a_gosper_curve_matches_three_js() raises:
    var doc = _reference()
    var section = doc.get(doc.root(), "gosper")
    var path = gosper(Length(2.0, METER))
    var count = doc.integer(doc.get(section, "count"))
    assert_equal(len(path), count * 3)
    var samples = doc.get(section, "samples")
    for at in range(0, doc.length(samples), 4):
        var point = doc.integer(doc.at(samples, at))
        for axis in range(3):
            assert_almost_equal(
                Float64(path[3 * point + axis]),
                doc.number(doc.at(samples, at + 1 + axis)),
                atol=1e-3,
            )


# --- frame corners ----------------------------------------------------------


def _camera() raises -> PerspectiveCamera:
    """Return three.js's camera: 50 degrees, 1.5 wide, at (1, 2, 10)."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.5, Length(0.5, METER), Length(50.0, METER)
    )
    camera.position = Vector3(1, 2, 10)
    return camera^


def _check_frame(
    camera: PerspectiveCamera, doc: JsonDocument, which: Int
) raises:
    """Assert a camera's projection, view and field of view match a case."""
    var want = doc.at(doc.get(doc.root(), "frame_corners"), which)
    var projection = camera.projection_matrix()
    var view = camera.view_matrix()
    for at in range(16):
        assert_almost_equal(
            Float64(projection.elements[at]),
            doc.number(doc.at(doc.get(want, "projection"), at)),
            atol=TOLERANCE,
        )
        assert_almost_equal(
            Float64(view.elements[at]),
            doc.number(doc.at(doc.get(want, "view"), at)),
            atol=TOLERANCE,
        )
    assert_almost_equal(
        Float64(camera.fov.to(DEGREE)),
        doc.number(doc.get(want, "fov")),
        atol=TOLERANCE,
    )


def test_a_camera_frames_a_rectangle_square_on() raises:
    var camera = _camera()
    frame_corners(
        camera, Vector3(-2, -1, 0), Vector3(3, -1, 0), Vector3(-2, 2, 0)
    )
    _check_frame(camera, _reference(), 0)
    assert_true(Bool(camera.projection_override))


def test_a_camera_frames_a_tilted_rectangle_and_estimates_its_view() raises:
    var camera = _camera()
    frame_corners(
        camera,
        Vector3(0, 0, -1),
        Vector3(2, 1, -2),
        Vector3(0, 3, -1),
        estimate_view_frustum=True,
    )
    _check_frame(camera, _reference(), 1)


def test_a_frame_refuses_corners_it_cannot_frame() raises:
    var camera = _camera()
    with assert_raises(contains="not on one line"):
        frame_corners(
            camera, Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0)
        )
    with assert_raises(contains="not on one line"):
        frame_corners(
            camera, Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 0)
        )
    with assert_raises(contains="not on one line"):
        frame_corners(
            camera, Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)
        )
    with assert_raises(contains="own plane"):
        frame_corners(
            camera, Vector3(0, 0, 10), Vector3(1, 0, 10), Vector3(0, 1, 10)
        )
    assert_false(Bool(camera.projection_override))


# --- the roller coaster ----------------------------------------------------


@fieldwise_init
struct _Track(SpaceCurve):
    """The curve of three.js's roller coaster example."""

    def point3(self, t: Float64) raises -> Point3:
        """Return the point at `t`.

        Args:
            t: Where on the curve.

        Returns:
            The point.

        Raises:
            Error: Never.
        """
        var a = t * pi * 2
        var x = sin(a * 3) * cos(a * 4) * 50
        var y = sin(a * 10) * 2 + cos(a * 17) * 2 + 5
        var z = sin(a) * sin(a * 4) * 50
        return point3(x * 2, y * 2, z * 2)

    def tangent3(self, t: Float64) raises -> Point3:
        """Return three.js's base tangent at `t`.

        Args:
            t: Where on the curve.

        Returns:
            The direction.

        Raises:
            Error: Never.
        """
        return chord_tangent(self, t)


def _assert_attributes(
    geometry: BufferGeometry, doc: JsonDocument, want: Int
) raises:
    """Assert every attribute of a geometry matches the reference's."""
    for at in range(doc.length(want)):
        var name = doc.key(want, at)
        var list = doc.get(want, name)
        ref data = geometry.attribute_view(name).data
        assert_equal(len(data), doc.length(list))
        for index in range(len(data)):
            var expected = doc.number(doc.at(list, index))
            assert_almost_equal(
                Float64(data[index]),
                expected,
                atol=1e-4 * max(abs(expected), 1.0),
            )


def _coaster(doc: JsonDocument, name: String) raises -> Int:
    """Return one entry of the roller coaster reference."""
    return doc.get(doc.get(doc.root(), "roller_coaster"), name)


def _coaster_reference() raises -> JsonDocument:
    """Return the roller coaster three.js built, a file of its own."""
    return parse_json(Path("assets/geometry_tools/coaster.json").read_text())


def test_a_roller_coaster_track_matches_three_js() raises:
    var doc = _coaster_reference()
    _assert_attributes(
        roller_coaster_geometry(_Track(), 8), doc, _coaster(doc, "track")
    )
    _assert_attributes(
        roller_coaster_lifters_geometry(_Track(), 8),
        doc,
        _coaster(doc, "lifters"),
    )
    _assert_attributes(
        roller_coaster_shadow_geometry(_Track(), 8),
        doc,
        _coaster(doc, "shadow"),
    )
    with assert_raises(contains="one division"):
        _ = roller_coaster_geometry(_Track(), 0)


def test_a_sky_and_trees_match_three_js() raises:
    var doc = _coaster_reference()
    # three.js's geometry takes four numbers for its uuid first.
    var clouds = SeededRandom(5)
    for _ in range(4):
        _ = clouds.next()
    _assert_attributes(sky_geometry(clouds), doc, _coaster(doc, "sky"))
    var scene = Scene()
    var assets = Assets()
    var ground = plane(Length(100.0, METER), Length(100.0, METER))
    ground.rotate_x(Angle(-pi / 2, RADIAN))
    ground.translate(Length(0.0, METER), Length(1.5, METER), Length(0.0, METER))
    var shape = assets.geometries.add(ground^)
    var paint = assets.materials.add(Material(Color(255, 255, 255)))
    scene.add_mesh(Mesh(shape, paint, scene.add(Object3D())))
    scene.update()
    var leaves = SeededRandom(9)
    for _ in range(4):
        _ = leaves.next()
    _assert_attributes(
        trees_geometry(scene, assets, leaves), doc, _coaster(doc, "trees")
    )


# --- the tube painter ------------------------------------------------------


def test_a_tube_painter_draws_as_three_js_draws() raises:
    var painter = TubePainter()
    assert_equal(painter.update()[1], 0)
    painter.move_to(Vector3(0, 1, 0))
    painter.line_to(Vector3(0.3, 1.1, 0.2))
    painter.set_size(2)
    painter.line_to(Vector3(0.5, 1.4, -0.1))
    # A stroke to where the pen is draws nothing.
    painter.line_to(Vector3(0.5, 1.4, -0.1))
    painter.line_to(Vector3(0.2, 1.6, 0.4))
    var doc = _reference()
    var want = doc.get(doc.root(), "tube_painter")
    assert_equal(painter.count(), doc.integer(doc.get(want, "count")))
    var drawn = painter.update()
    assert_equal(drawn[0], 0)
    assert_equal(drawn[1], painter.count())
    assert_equal(painter.update()[1], 0)
    var geometry = painter.geometry()
    var names: List[String] = ["position", "normal", "color"]
    for at in range(3):
        ref data = geometry.attribute_view(names[at]).data
        var list = doc.get(want, names[at])
        assert_equal(len(data), doc.length(list))
        for index in range(len(data)):
            assert_almost_equal(
                Float64(data[index]),
                doc.number(doc.at(list, index)),
                atol=1e-5,
            )


# --- the convex object breaker ---------------------------------------------


def _check_piece(
    got: Optional[BreakableObject],
    doc: JsonDocument,
    want: Int,
    near: Float64 = 1e-4,
    exact: Bool = True,
) raises:
    """Assert a piece matches three.js's: its place, its size, its mass and
    whether it can break. A piece of a piece is near three.js's place and
    need not have its corners; see the module docstring."""
    assert_true(Bool(got))
    ref piece = got.value()
    var position = doc.get(want, "position")
    assert_almost_equal(
        Float64(piece.position.x), doc.number(doc.at(position, 0)), atol=near
    )
    assert_almost_equal(
        Float64(piece.position.y), doc.number(doc.at(position, 1)), atol=near
    )
    assert_almost_equal(
        Float64(piece.position.z), doc.number(doc.at(position, 2)), atol=near
    )
    if exact:
        assert_equal(
            len(piece.geometry.attribute_view("position").data) // 3,
            doc.integer(doc.get(want, "count")),
        )
    assert_almost_equal(
        Float64(piece.mass.to(KILOGRAM)),
        doc.number(doc.get(want, "mass")),
        atol=1e-5,
    )
    assert_equal(piece.breakable, doc.boolean(doc.get(want, "breakable")))


def _block(
    size: Float32, position: Vector3, turn: Quaternion, mass: Float32
) raises -> BreakableObject:
    """Return a box as a breakable object."""
    var side = Length(size, METER)
    return BreakableObject(
        box(side, side, side),
        position,
        turn,
        Mass(mass, KILOGRAM),
        Vector3(1, 2, 3),
        Vector3(0, 1, 0),
        True,
    )


def test_a_box_is_cut_as_three_js_cuts_it() raises:
    var breaker = ConvexObjectBreaker()
    var turn = Quaternion.from_axis_angle(Vector3(0, 1, 0), Angle(0.3, RADIAN))
    var block = _block(2, Vector3(1, 0, 0), turn, 10)
    var normal = Vector3(1, 0.2, 0)
    normal.normalize()
    var halves = breaker.cut_by_plane(block, Plane(normal, -1.1))
    var doc = _reference()
    var cut = doc.get(doc.get(doc.root(), "breaker"), "cut")
    _check_piece(halves[0], doc, doc.at(cut, 0))
    _check_piece(halves[1], doc, doc.at(cut, 1))
    assert_equal(halves[0].value().velocity.z, 3)
    # A plane that misses leaves one side of nothing.
    var whole = breaker.cut_by_plane(block, Plane(Vector3(1, 0, 0), -10))
    assert_true(Bool(whole[0]))
    assert_false(Bool(whole[1]))
    # A block moved after it was made is cut where it now is.
    var moved = block.copy()
    moved.position = Vector3(5, 0, 0)
    var far = breaker.cut_by_plane(moved, Plane(Vector3(1, 0, 0), -5))
    assert_true(Bool(far[0]) and Bool(far[1]))


def _odd_cube() raises -> BreakableObject:
    """Return an indexed cube of eight shared corners, whose normal array
    starts with minus two and is zero after that."""
    var corners: List[Float32] = [
        -1,
        -1,
        -1,
        1,
        -1,
        -1,
        1,
        1,
        -1,
        -1,
        1,
        -1,
        -1,
        -1,
        1,
        1,
        -1,
        1,
        1,
        1,
        1,
        -1,
        1,
        1,
    ]
    var faces: List[Int] = [
        0,
        2,
        1,
        0,
        3,
        2,
        4,
        5,
        6,
        4,
        6,
        7,
        0,
        1,
        5,
        0,
        5,
        4,
        3,
        7,
        6,
        3,
        6,
        2,
        0,
        4,
        7,
        0,
        7,
        3,
        1,
        2,
        6,
        1,
        6,
        5,
    ]
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(corners^, 3))
    var normals = List[Float32](length=24, fill=0)
    normals[0] = -2
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_index(faces^)
    return BreakableObject(
        geometry^,
        Vector3(0, 0, 0),
        Quaternion.identity(),
        Mass(1, KILOGRAM),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        True,
    )


def test_the_breaker_reads_normals_as_three_js_reads_them() raises:
    # three.js reads a face's normal as the number at its first vertex's
    # index, plus nothing, one and two. Faces whose readings agree count as
    # coplanar, and the edges they share are left out of the cut. The
    # minus two makes pairs that disagree. three.js 0.180 cuts this cube
    # into two halves of eighteen vertices each.
    var breaker = ConvexObjectBreaker()
    var halves = breaker.cut_by_plane(
        _odd_cube(), Plane(Vector3(1, 0, 0), -0.3)
    )
    assert_true(Bool(halves[0]) and Bool(halves[1]))
    assert_equal(halves[0].value().geometry.vertex_count(), 18)
    assert_equal(halves[1].value().geometry.vertex_count(), 18)


def test_a_box_breaks_as_three_js_breaks_it() raises:
    var breaker = ConvexObjectBreaker()
    var block = _block(3, Vector3(0, 0, 0), Quaternion.identity(), 20)
    var random = SeededRandom(3)
    var debris = breaker.subdivide_by_impact(
        block, Vector3(0, 1.5, 0.2), Vector3(0, -1, 0), 2, 1, random
    )
    var doc = _reference()
    var want = doc.get(doc.get(doc.root(), "breaker"), "debris")
    assert_equal(len(debris), doc.length(want))
    # The pieces, their masses and whether each can break are three.js's.
    # A corner that lies within `small_delta` of a cut can fall on the other
    # side here, so a piece's place and corners are near three.js's.
    for at in range(len(debris)):
        _check_piece(
            Optional(debris[at].copy()),
            doc,
            doc.at(want, at),
            near=0.15,
            exact=False,
        )


# --- UVsDebug --------------------------------------------------------------


def _check_uvs(geometry: BufferGeometry, size: Int, name: String) raises:
    """Assert the outlines and the labels match what three.js drew."""
    var drawn = uvs_debug(geometry, size)
    var doc = _reference()
    var want = doc.get(doc.root(), name)
    var path = doc.get(want, "path")
    assert_equal(len(drawn.outlines) * 6, doc.length(path))
    for face in range(len(drawn.outlines)):
        for corner in range(3):
            var at = face * 6 + corner * 2
            assert_almost_equal(
                Float64(drawn.outlines[face][corner].x),
                doc.number(doc.at(path, at)),
                atol=1e-4,
            )
            assert_almost_equal(
                Float64(drawn.outlines[face][corner].y),
                doc.number(doc.at(path, at + 1)),
                atol=1e-4,
            )
    var labels = doc.get(want, "labels")
    assert_equal(len(drawn.labels), doc.length(labels))
    for at in range(len(drawn.labels)):
        var label = doc.at(labels, at)
        ref got = drawn.labels[at]
        assert_equal(got.text, doc.string(doc.at(label, 0)))
        assert_almost_equal(
            Float64(got.x), doc.number(doc.at(label, 1)), atol=1e-4
        )
        assert_almost_equal(
            Float64(got.y), doc.number(doc.at(label, 2)), atol=1e-4
        )
        assert_equal(got.size, doc.integer(doc.at(label, 3)))
        var color = (
            "rgb( "
            + String(got.color.r)
            + ", "
            + String(got.color.g)
            + ", "
            + String(got.color.b)
            + " )"
        )
        assert_equal(color, doc.string(doc.at(label, 4)))


def test_uvs_debug_leaves_what_is_off_the_image() raises:
    # A triangle past every edge: the pen draws only what is on the image.
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(UV),
        BufferAttribute([Float32(-0.5), 0.5, 1.5, -0.5, 0.5, 1.5], 2),
    )
    var drawn = uvs_debug(geometry, 16)
    assert_equal(len(drawn.outlines), 1)
    var inked = 0
    for y in range(16):
        for x in range(16):
            if drawn.image.get_pixel(x, y).r == UVS_LINE.r:
                inked += 1
    assert_true(inked > 0)


def test_uvs_debug_draws_a_box_as_three_js_does() raises:
    var side = Length(1.0, METER)
    var shape = box(side, side, side)
    _check_uvs(shape, 64, "uvs_debug")
    var drawn = uvs_debug(shape, 64)
    # The background is white, and each outline's first corner is a line.
    var corner = drawn.image.get_pixel(63, 63)
    assert_equal(corner.r, UVS_BACKGROUND.r)
    var first = drawn.outlines[0][0]
    var inked = drawn.image.get_pixel(Int(first.x), Int(first.y))
    assert_equal(inked.r, UVS_LINE.r)


def test_uvs_debug_writes_a_label_at_the_edge_twice() raises:
    var edge = BufferGeometry()
    edge.set_attribute(
        String(UV),
        BufferAttribute([Float32(0.9), 0.1, 1, 0.2, 1, 0.9], 2),
    )
    _check_uvs(edge, 32, "uvs_debug_edge")
    with assert_raises(contains="three pixels"):
        _ = uvs_debug(edge, 2)
    with assert_raises(contains="texture coordinates"):
        _ = uvs_debug(BufferGeometry(), 32)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
