# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.marching_cubes`.

The reference surfaces come from three.js 0.180's `MarchingCubes` run under
Node on the same fields: `assets/scene_objects/reference.mjs` writes them
to `reference.json`. Each vertex, normal, color and coordinate must be the
same float.
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry, COLOR, NORMAL, POSITION, UV
from geometries.box import cube
from loaders.json import JsonDocument, parse_json
from objects.marching_cubes import MarchingCubes
from render.framebuffer import FloatColor
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


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


def assert_floats(
    doc: JsonDocument, node: Int, key: String, got: List[Float32]
) raises:
    """Assert a list of floats equals three.js's, float for float."""
    var want = doc.get(node, key)
    assert_equal(len(got), doc.length(want))
    for index in range(len(got)):
        assert_equal(got[index], Float32(doc.number(doc.at(want, index))))


def assert_surface(doc: JsonDocument, key: String, cubes: MarchingCubes) raises:
    """Assert a surface equals three.js's, vertex for vertex."""
    var node = doc.get(doc.root(), key)
    assert_equal(cubes.count, doc.integer(doc.get(node, "count")))
    assert_floats(doc, node, "position", cubes.positions)
    assert_floats(doc, node, "normal", cubes.normals)
    if doc.has(node, "uv"):
        assert_floats(doc, node, "uv", cubes.uvs)
        assert_floats(doc, node, "color", cubes.colors)


def balls() raises -> MarchingCubes:
    """Return the first reference field, as `reference.mjs` builds it."""
    var cubes = MarchingCubes(10, enable_uvs=True, enable_colors=True)
    cubes.reset()
    cubes.add_ball(0.45, 0.5, 0.52, 0.5, 12)
    cubes.add_ball(0.62, 0.55, 0.43, 0.35, 12, FloatColor(1, 0.25, 0, 1))
    cubes.add_plane_y(2, 12)
    return cubes^


def test_metaballs_and_a_wall_match_three_js() raises:
    var doc = reference()
    var cubes = balls()
    cubes.update()
    assert_surface(doc, "balls", cubes)
    # Without a reset, the first field's normals stay cached.
    cubes.add_ball(0.4, 0.4, 0.4, 0.3, 12)
    cubes.update()
    assert_surface(doc, "cached", cubes)


def test_flat_normals_walls_and_a_blur_match_three_js() raises:
    var doc = reference()
    var cubes = MarchingCubes(8)
    cubes.flat_shading = True
    cubes.isolation = 60
    cubes.add_ball(0.5, 0.5, 0.5, 0.9, 10)
    cubes.add_ball(0.55, 0.45, 0.5, -0.2, 20)
    cubes.add_plane_x(1.5, 10)
    cubes.add_plane_z(1.5, 10)
    cubes.set_cell(4, 4, 4, 300)
    cubes.blur(0.5)
    cubes.update()
    assert_surface(doc, "flat", cubes)
    var node = doc.get(doc.root(), "flat")
    assert_equal(
        cubes.get_cell(3, 4, 4), Float32(doc.number(doc.get(node, "cell")))
    )


def test_the_geometry_holds_the_surface() raises:
    var cubes = balls()
    cubes.update()
    var surface = cubes.geometry()
    assert_equal(surface.vertex_count(), cubes.count)
    assert_false(surface.is_indexed())
    assert_true(surface.has_attribute(String(UV)))
    assert_true(surface.has_attribute(String(COLOR)))
    var plain = MarchingCubes(8)
    plain.add_ball(0.5, 0.5, 0.5, 0.5, 12)
    plain.update()
    var bare = plain.geometry()
    assert_true(bare.has_attribute(String(POSITION)))
    assert_true(bare.has_attribute(String(NORMAL)))
    assert_false(bare.has_attribute(String(UV)))
    assert_false(bare.has_attribute(String(COLOR)))
    # The surface replaces a stored geometry in place.
    var assets = Assets()
    var id = assets.geometries.add(cube(Length(1.0, METER)))
    plain.replace_geometry(assets, id)
    assert_equal(assets.geometries.get(id).vertex_count(), plain.count)


def test_an_empty_field_has_no_surface() raises:
    var cubes = MarchingCubes(8)
    cubes.update()
    assert_equal(cubes.count, 0)
    with assert_raises(contains="no triangle"):
        _ = cubes.geometry()
    # A cube too small for an inner cell has nothing to march.
    var tiny = MarchingCubes(2)
    tiny.update()
    assert_equal(tiny.count, 0)


def test_a_reset_clears_the_field() raises:
    var cubes = balls()
    cubes.update()
    assert_true(cubes.count > 0)
    cubes.reset()
    cubes.update()
    assert_equal(cubes.count, 0)
    assert_equal(cubes.palette[3 * 555], 0)


def test_a_ball_with_no_reach_or_far_away_changes_nothing() raises:
    var cubes = MarchingCubes(8)
    # A negative subtract gives no radius: three.js's loops never run.
    cubes.add_ball(0.5, 0.5, 0.5, 0.5, -12)
    # A ball far outside the cube reaches none of its cells.
    cubes.add_ball(1e300, -1e300, 50, 0.5, 12)
    # One axis in reach and the next not: the inner loops never run.
    cubes.add_ball(0.5, 50, 0.5, 0.5, 12)
    cubes.add_ball(50, 0.5, 0.5, 0.5, 12)
    # A ball of no strength has no reach either.
    cubes.add_ball(0.5, 0.5, 0.5, 0, 12)
    for i in range(len(cubes.field)):
        assert_equal(cubes.field[i], 0)
    # A subtract of zero reaches every cell but the outer layer, which
    # three.js leaves out.
    var whole = MarchingCubes(8)
    whole.add_ball(0.5, 0.5, 0.5, 0.5, 0)
    assert_true(whole.get_cell(1, 1, 1) > 0)
    assert_true(whole.get_cell(6, 6, 6) > 0)
    assert_equal(whole.get_cell(0, 3, 3), 0)
    assert_equal(whole.get_cell(7, 3, 3), 0)
    # So does a wall, and a wall with a negative subtract reaches nothing.
    whole.add_plane_x(0.5, 0)
    whole.add_plane_x(0.5, -1)
    assert_equal(whole.get_cell(0, 3, 3), Float32(0.5 / 0.0001))
    assert_true(whole.get_cell(7, 3, 3) > 0)


def test_the_walls_reach_as_far_as_their_strength() raises:
    var cubes = MarchingCubes(8)
    cubes.add_plane_y(0.001, 1)
    assert_true(cubes.get_cell(3, 0, 3) > 0)
    assert_equal(cubes.get_cell(3, 1, 3), 0)
    cubes.add_plane_z(0.001, 1)
    assert_true(cubes.get_cell(3, 3, 0) > 0)
    # A wall whose share is never positive adds nothing.
    var none = MarchingCubes(8)
    none.add_plane_y(0.0001, 2)
    none.add_plane_z(0.0001, 2)
    none.add_plane_x(0.0001, 2)
    assert_equal(none.get_cell(0, 0, 0), 0)


def test_a_full_buffer_raises() raises:
    var cubes = MarchingCubes(10, max_poly_count=4)
    cubes.add_ball(0.5, 0.5, 0.5, 0.5, 12)
    with assert_raises(contains="max_poly_count"):
        cubes.update()


def test_a_field_refuses_what_it_cannot_hold() raises:
    with assert_raises(contains="positive resolution"):
        _ = MarchingCubes(0)
    with assert_raises(contains="room for a triangle"):
        _ = MarchingCubes(4, max_poly_count=0)
    var cubes = MarchingCubes(4)
    with assert_raises(contains="inside the field"):
        cubes.set_cell(4, 0, 0, 1)
    with assert_raises(contains="inside the field"):
        _ = cubes.get_cell(0, -1, 0)
    with assert_raises(contains="inside the field"):
        _ = cubes.get_cell(0, 0, 4)
    with assert_raises(contains="finite"):
        cubes.add_ball(nan[DType.float64](), 0, 0, 1, 1)
    with assert_raises(contains="finite"):
        cubes.add_ball(0, inf[DType.float64](), 0, 1, 1)
    with assert_raises(contains="finite"):
        cubes.add_ball(0, 0, inf[DType.float64](), 1, 1)
    with assert_raises(contains="finite"):
        cubes.add_ball(0, 0, 0, inf[DType.float64](), 1)
    with assert_raises(contains="finite"):
        cubes.add_ball(0, 0, 0, 1, nan[DType.float64]())
    with assert_raises(contains="finite"):
        cubes.add_plane_x(inf[DType.float64](), 1)
    with assert_raises(contains="finite"):
        cubes.add_plane_y(1, nan[DType.float64]())
    with assert_raises(contains="finite"):
        cubes.add_plane_z(1, inf[DType.float64]())
    with assert_raises(contains="finite"):
        cubes.blur(nan[DType.float64]())
    var assets = Assets()
    var empty = MarchingCubes(4)
    with assert_raises():
        empty.replace_geometry(
            assets, assets.geometries.add(cube(Length(1.0, METER)))
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
