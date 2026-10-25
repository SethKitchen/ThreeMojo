# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fallen leaves, twigs and pebbles on a field's bare ground."""

from core.buffer_geometry import COLOR, NORMAL, POSITION
from extensions.vegetation.field import FieldParameters, GrassField, LodBand
from extensions.vegetation.ground import Clearing, Ground
from extensions.vegetation.litter import LitterMesh, _leaf_color, ground_litter
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


def _field(dirt: Float32) raises -> GrassField:
    """Return a small field on ground with `dirt` of it bare."""
    var p = FieldParameters()
    p.span = Length(16.0, METER)
    p.cluster_size = Length(4.0, METER)
    p.density = 10
    p.bands = [LodBand(Length(10.0, METER), 1.0, 3)]
    return GrassField(p^, Ground(dirt=dirt))


def test_a_flat_piece_lies_on_the_ground_facing_up() raises:
    """A leaf or a twig is four vertices and two triangles that face up,
    as long and as wide as asked, with its ends curled up."""
    var mesh = LitterMesh()
    mesh.add_flat(Vector3(1, 0, 2), 0, 0.2, 0.1, Vector3(0.1, 0.05, 0.02))
    assert_equal(mesh.vertex_count(), 4)
    assert_equal(len(mesh.index), 6)
    assert_almost_equal(mesh.positions[6] - mesh.positions[0], 0.2, atol=1e-6)
    assert_almost_equal(mesh.positions[5] - mesh.positions[11], 0.1, atol=1e-6)
    assert_true(mesh.positions[1] > 0)
    for v in range(4):
        assert_almost_equal(mesh.normals[3 * v + 1], 1)
    var a = Vector3(mesh.positions[0], mesh.positions[1], mesh.positions[2])
    var b = Vector3(mesh.positions[3], mesh.positions[4], mesh.positions[5])
    var c = Vector3(mesh.positions[6], mesh.positions[7], mesh.positions[8])
    var u = b - a
    var w = c - a
    assert_true(u.z * w.x - u.x * w.z > 0)


def test_a_pebble_has_eight_faces_facing_out() raises:
    """A pebble is eight triangles of their own vertices, each with a unit
    normal that points away from its middle."""
    var mesh = LitterMesh()
    var middle = Vector3(0, 1, 0)
    mesh.add_pebble(middle, 0.4, 0.1, Vector3(0.1, 0.1, 0.1))
    assert_equal(mesh.vertex_count(), 24)
    assert_equal(len(mesh.index), 24)
    for f in range(8):
        var n = Vector3(
            mesh.normals[9 * f],
            mesh.normals[9 * f + 1],
            mesh.normals[9 * f + 2],
        )
        assert_almost_equal(n.length(), 1, atol=1e-5)
        var p = Vector3(
            mesh.positions[9 * f],
            mesh.positions[9 * f + 1],
            mesh.positions[9 * f + 2],
        )
        var q = Vector3(
            mesh.positions[9 * f + 3],
            mesh.positions[9 * f + 4],
            mesh.positions[9 * f + 5],
        )
        var r = Vector3(
            mesh.positions[9 * f + 6],
            mesh.positions[9 * f + 7],
            mesh.positions[9 * f + 8],
        )
        assert_true(((p + q + r) / 3 - middle).dot(n) > 0)


def test_a_litter_mesh_bakes_one_geometry() raises:
    """The mesh hands over positions, normals, colors and the index; an
    empty one is refused."""
    var mesh = LitterMesh()
    mesh.add_flat(Vector3(0, 0, 0), 1, 0.1, 0.05, Vector3(0.1, 0.05, 0.02))
    mesh.add_pebble(Vector3(1, 0, 0), 0, 0.05, Vector3(0.1, 0.1, 0.1))
    var geometry = mesh^.geometry()
    assert_equal(geometry.vertex_count(), 28)
    assert_true(geometry.has_attribute(String(NORMAL)))
    assert_true(geometry.has_attribute(String(COLOR)))
    var empty = LitterMesh()
    with assert_raises(contains="nothing in it"):
        _ = empty^.geometry()


def test_fallen_leaves_run_from_brown_to_green() raises:
    """A leaf is brown at zero, ochre at a half and green at one."""
    var brown = _leaf_color(0)
    var ochre = _leaf_color(0.5)
    var green = _leaf_color(1)
    assert_true(brown.x > brown.y)
    assert_true(ochre.x > brown.x)
    assert_true(green.y > green.x)


def test_litter_falls_in_the_shade_and_on_the_dirt() raises:
    """A field with neither shade nor dirt has no litter. A clearing
    gathers litter round the tree's foot, of all three kinds. Dirt
    gathers litter too. Every piece lies near the ground. A reach or a
    count out of range is refused."""
    var grassy = _field(0)
    assert_false(ground_litter(grassy, 0, 0, Length(8.0, METER), 4000, 1))
    var shaded = _field(0)
    shaded.clearings = [Clearing(0, 0, 5)]
    var under = ground_litter(shaded, 0, 0, Length(8.0, METER), 4000, 1)
    var geometry = under.take()
    ref p = geometry.attribute_view(String(POSITION))
    var flat = 0
    var stone = 0
    for v in range(p.count()):
        var q = p.vector3(v)
        assert_true(q.x * q.x + q.z * q.z < 5.5 * 5.5)
        assert_true(abs(q.y - shaded.ground.height_at(q.x, q.z)) < 0.2)
    ref n = geometry.attribute_view(String(NORMAL))
    for v in range(n.count()):
        if n.vector3(v).y > 0.999:
            flat += 1
        else:
            stone += 1
    assert_true(flat > 100)
    assert_true(stone > 20)
    var dirty = _field(1)
    assert_true(ground_litter(dirty, 0, 0, Length(8.0, METER), 4000, 1))
    with assert_raises(contains="reach"):
        _ = ground_litter(grassy, 0, 0, Length(0.5, METER), 10, 1)
    with assert_raises(contains="points"):
        _ = ground_litter(grassy, 0, 0, Length(5.0, METER), 0, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
