# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Leaves in clumps: chords, the light through a crown, leaf meshes and
the foliage program."""

from core.buffer_geometry import COLOR, NORMAL, POSITION
from extensions.vegetation.foliage import (
    SKYLIT,
    SKY_RAYS,
    SUNLIT,
    Clump,
    LeafMesh,
    chord,
    foliage_program,
    sky_rays,
    sky_through,
    sun_through,
)
from materials.nodes import (
    AO_NODE,
    NORMAL_NODE,
    POSITION_NODE,
    RECEIVED_SHADOW_NODE,
)
from math.vector3 import Vector3
from std.math import exp
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _ball() -> Clump:
    """Return a clump of radius one at the origin."""
    return Clump(Vector3(0, 0, 0), 1)


def test_a_chord_measures_the_ray_inside_a_clump() raises:
    """A ray through the middle runs the diameter; one from the middle
    runs the radius; one that misses or points away runs nothing."""
    var up = Vector3(0, 1, 0)
    assert_almost_equal(chord(Vector3(0, -5, 0), up, _ball()), 2, atol=1e-5)
    assert_almost_equal(chord(Vector3(0, 0, 0), up, _ball()), 1, atol=1e-5)
    assert_almost_equal(chord(Vector3(0, 0.5, 0), up, _ball()), 0.5, atol=1e-5)
    assert_almost_equal(chord(Vector3(3, -5, 0), up, _ball()), 0)
    assert_almost_equal(chord(Vector3(0, 5, 0), up, _ball()), 0)
    var grazing = chord(Vector3(0.6, -5, 0), up, _ball())
    assert_almost_equal(grazing, 1.6, atol=1e-5)


def test_light_falls_off_by_beers_law() raises:
    """Light through clumps falls as `exp(-density * length)`. With no
    clump nothing dims it."""
    var clumps: List[Clump] = [_ball(), Clump(Vector3(0, 3, 0), 0.5)]
    var lit = sun_through(Vector3(0, -5, 0), Vector3(0, 1, 0), clumps, 2)
    assert_almost_equal(lit, exp(Float32(-2 * 3)), atol=1e-6)
    var open = sun_through(
        Vector3(0, -5, 0), Vector3(0, 1, 0), List[Clump](), 2
    )
    assert_almost_equal(open, 1)


def test_the_sky_rays_rise_and_average() raises:
    """The sky's rays are unit length and point up. A point under a clump
    sees less sky than one beside it, and no ray sees all of it."""
    var rays = sky_rays()
    assert_equal(len(rays), SKY_RAYS)
    for index in range(len(rays)):
        assert_almost_equal(rays[index].length(), 1, atol=1e-6)
        assert_true(rays[index].y > 0.7)
    var clumps: List[Clump] = [Clump(Vector3(0, 2, 0), 1)]
    var under = sky_through(Vector3(0, 0, 0), rays, clumps, 3)
    var beside = sky_through(Vector3(8, 0, 0), rays, clumps, 3)
    assert_true(under < beside)
    assert_almost_equal(beside, 1, atol=1e-6)
    assert_almost_equal(
        sky_through(Vector3(0, 0, 0), List[Vector3](), clumps, 3), 1
    )


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
