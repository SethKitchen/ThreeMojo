# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Leaves: the grid that shades them, the light through a crown, leaf
meshes and the foliage program."""

from core.buffer_geometry import COLOR, NORMAL, POSITION
from extensions.vegetation.foliage import (
    SKYLIT,
    SKY_RAYS,
    SUNLIT,
    LeafMesh,
    LeafShade,
    foliage_program,
    sky_rays,
)
from materials.nodes import (
    AO_NODE,
    NORMAL_NODE,
    POSITION_NODE,
    RECEIVED_SHADOW_NODE,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import METER, Length


def _filled(shade: Float32) raises -> LeafShade:
    """Return a grid 10 meters on a side of 1-meter cells, each holding a
    square meter of leaves, finished with `shade`."""
    var grid = LeafShade(
        Vector3(0, 0, 0), Vector3(10, 10, 10), Length(1.0, METER)
    )
    for z in range(grid.nz):
        for y in range(grid.ny):
            for x in range(grid.nx):
                grid.add(
                    Vector3(
                        Float32(x) + 0.5, Float32(y) + 0.5, Float32(z) + 0.5
                    ),
                    1,
                )
    grid.finish(shade)
    return grid^


def test_a_shade_grid_is_checked() raises:
    """A grid covers its box with whole cells. A cell out of range, a box
    of no size, and a grid of too many cells are refused."""
    var grid = LeafShade(
        Vector3(-1, 0, -1), Vector3(1, 3, 1), Length(0.5, METER)
    )
    assert_equal(grid.nx, 5)
    assert_equal(grid.ny, 7)
    assert_equal(grid.nz, 5)
    assert_equal(len(grid.density), 5 * 7 * 5)
    with assert_raises(contains="shade cell"):
        _ = LeafShade(Vector3(0, 0, 0), Vector3(1, 1, 1), Length(0.0, METER))
    with assert_raises(contains="1 millimeter to 1 kilometer"):
        _ = LeafShade(Vector3(0, 0, 0), Vector3(1, 0, 1), Length(0.5, METER))
    with assert_raises(contains="4 million"):
        _ = LeafShade(
            Vector3(0, 0, 0), Vector3(500, 500, 500), Length(0.1, METER)
        )


def test_leaves_are_counted_in_their_cells() raises:
    """A leaf adds its area to its cell, or to the nearest cell if it is
    outside. Finishing divides by the volume, times the shade, and blurs:
    a cell keeps an eighth of itself, and gets a 64th of a corner
    neighbor's. Outside the grid nothing dims the light."""
    var grid = LeafShade(Vector3(0, 0, 0), Vector3(2, 2, 2), Length(1.0, METER))
    grid.add(Vector3(1.5, 1.5, 1.5), 2)
    grid.add(Vector3(-5, -5, -5), 1)
    assert_almost_equal(grid.density[(1 * 3 + 1) * 3 + 1], 2)
    assert_almost_equal(grid.density[0], 1)
    grid.finish(0.5)
    var middle = Float32(0.125 + 0.5 / 64)
    assert_almost_equal(grid.density[(1 * 3 + 1) * 3 + 1], middle)
    assert_almost_equal(grid.dimming(Vector3(1.5, 1.5, 1.5)), middle)
    assert_almost_equal(grid.dimming(Vector3(30, 1, 1)), 0)
    assert_almost_equal(grid.through(Vector3(30, 1, 1), Vector3(0, 1, 0)), 1)


def test_light_falls_off_by_beers_law() raises:
    """Light through the leaves falls as `exp(-sum)`: twice the shade lets
    through the square of the light. An empty grid dims nothing."""
    var right = Vector3(1, 0, 0)
    var start = Vector3(5.5, 5.5, 5.5)
    var thin = _filled(0.5).through(start, right)
    var thick = _filled(1.0).through(start, right)
    assert_true(thin < 0.5)
    assert_true(thin > 0)
    assert_almost_equal(thick, thin * thin, atol=1e-6)
    var empty = LeafShade(
        Vector3(0, 0, 0), Vector3(4, 4, 4), Length(1.0, METER)
    )
    empty.finish(0.5)
    assert_almost_equal(empty.through(Vector3(2, 2, 2), right), 1)


def test_the_sky_rays_rise_and_average() raises:
    """The sky's rays are unit length and point up, the lowest 10 degrees
    up. A point under a layer of leaves sees less sky than one beside it,
    and with no ray it sees all of it."""
    var rays = sky_rays()
    assert_equal(len(rays), SKY_RAYS)
    for index in range(len(rays)):
        assert_almost_equal(rays[index].length(), 1, atol=1e-6)
        assert_true(rays[index].y > 0.17)
    var grid = LeafShade(
        Vector3(-2, 0, -2), Vector3(2, 4, 2), Length(0.5, METER)
    )
    for x in range(8):
        for z in range(8):
            grid.add(
                Vector3(Float32(x) * 0.5 - 1.75, 3.25, Float32(z) * 0.5 - 1.75),
                3,
            )
    grid.finish(0.5)
    var under = grid.sky(Vector3(0, 0.25, 0), rays)
    var beside = grid.sky(Vector3(8, 0.25, 0), rays)
    assert_true(under < beside)
    assert_almost_equal(beside, 1, atol=1e-6)
    assert_almost_equal(grid.sky(Vector3(0, 0.25, 0), List[Vector3]()), 1)


def test_the_foliage_program_sets_its_three_outputs() raises:
    """The program turns back faces, takes the baked sun as the shadow and
    the baked sky as the occlusion, and moves no vertex."""
    var program = foliage_program()
    assert_true(program.has(NORMAL_NODE))
    assert_true(program.has(RECEIVED_SHADOW_NODE))
    assert_true(program.has(AO_NODE))
    assert_false(program.has(POSITION_NODE))


def test_an_ovate_leaf_is_eight_vertices_and_six_triangles() raises:
    """An ovate leaf spans its length along the midrib, its tip droops,
    and its halves tilt their normals apart. Each vertex keeps the
    leaf's light."""
    var mesh = LeafMesh()
    mesh.add_ovate(
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 0, 1),
        Vector3(0, 1, 0),
        Vector3(0.1, 0.05, 0.02),
        Vector3(0.1, 0.2, 0.05),
        0.7,
        0.4,
    )
    assert_equal(mesh.leaf_count(), 1)
    assert_equal(mesh.vertex_count(), 8)
    assert_equal(mesh.triangle_count(), 6)
    assert_almost_equal(mesh.positions[21], 0.1, atol=1e-6)
    assert_almost_equal(mesh.positions[22], -0.02, atol=1e-6)
    assert_almost_equal(mesh.positions[3 * 4 + 2], 0.025, atol=1e-6)
    assert_true(mesh.normals[3 * 3 + 2] < 0)
    assert_true(mesh.normals[3 * 4 + 2] > 0)
    for v in range(8):
        assert_almost_equal(mesh.sunlit[v], 0.7)
        assert_almost_equal(mesh.skylit[v], 0.4)


def test_a_card_is_a_diamond_and_both_bake_one_geometry() raises:
    """A card is four vertices and two triangles. A mesh of both kinds
    bakes into one geometry with both light attributes; an empty mesh is
    refused."""
    var mesh = LeafMesh()
    mesh.add_card(
        Vector3(0, 0, 0),
        Vector3(0, 0, 1),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0.2, 0.1, 0),
        Vector3(0.1, 0.2, 0.05),
        1,
        1,
    )
    assert_equal(mesh.vertex_count(), 4)
    assert_equal(mesh.triangle_count(), 2)
    assert_almost_equal(mesh.positions[3 * 2 + 2], 0.2, atol=1e-6)
    assert_almost_equal(mesh.positions[3 * 3], 0.05, atol=1e-6)
    mesh.add_ovate(
        Vector3(1, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 0, 1),
        Vector3(0, 1, 0),
        Vector3(0.1, 0.05, 0.02),
        Vector3(0.1, 0.2, 0.05),
        0.5,
        0.5,
    )
    assert_equal(mesh.leaf_count(), 2)
    var geometry = mesh^.geometry()
    assert_equal(geometry.vertex_count(), 12)
    assert_equal(len(geometry.index), 24)
    assert_true(geometry.has_attribute(String(SUNLIT)))
    assert_true(geometry.has_attribute(String(SKYLIT)))
    assert_true(geometry.has_attribute(String(NORMAL)))
    assert_true(geometry.has_attribute(String(COLOR)))
    var empty = LeafMesh()
    with assert_raises(contains="no leaves"):
        _ = empty^.geometry()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
