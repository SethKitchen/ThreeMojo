# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `generators.street_furniture` and `generators.sidewalk`,
three.js's street furniture generators and `SidewalkGenerator`.

The vertex counts follow from three.js's primitives: a closed cylinder of
`r` segments has `6 r + 4` vertices, an open one `2 r + 2`, a box 24, a
sphere `(w + 1)(h + 1)` and a ring `(t + 1)(p + 1)`. The welded
icosahedra of the basket's mound and the tree's clumps are counted by
the port's `icosahedron` and `merge_vertices`, which their own suites
compare with three.js. The extents are read off three.js's placements.
"""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from generators.sidewalk import SidewalkGenerator, extrude_up, rounded_rect
from generators.street_furniture import (
    BenchGenerator,
    HydrantGenerator,
    StreetTreeGenerator,
    StreetlightGenerator,
    TrafficlightGenerator,
    TrashcanGenerator,
    clump_hash,
    leaf_clump,
    unit_vectors_turn,
)
from generators.utils import PART_ID, PartId, Vec3d, part
from geometries.box import box
from geometries.polyhedron import icosahedron
from geometries.utils import merge_vertices
from math.matrix4 import Matrix4
from std.math import cos, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def _part_at(geometry: BufferGeometry, vertex: Int) raises -> Int:
    """Return the part code of a vertex."""
    return Int(geometry.attribute_view(String(PART_ID)).component(vertex, 0))


def _two() -> List[Matrix4]:
    """Return two placements."""
    var second = Matrix4()
    second.elements[12] = 5
    return [Matrix4(), second]


def test_part_tags_and_welds() raises:
    """A part is tagged on every vertex; one without an index is welded
    first, and a code out of range is refused."""
    var tagged = part(
        box(Length(1, METER), Length(1, METER), Length(1, METER)), PartId(3)
    )
    assert_equal(tagged.vertex_count(), 24)
    assert_equal(_part_at(tagged, 23), 3)
    var ball = icosahedron(Length(1, METER), 0)
    var welded = part(ball, PartId(0))
    assert_true(welded.is_indexed())
    assert_equal(welded.vertex_count(), merge_vertices(ball).vertex_count())
    with assert_raises(contains="part code"):
        _ = part(ball, PartId(9))
    with assert_raises(contains="part code"):
        _ = part(ball, PartId(-1))
    assert_true(PartId(8).is_valid())
    assert_false(PartId(9).is_valid())


def test_streetlight_matches_three() raises:
    """Two cylinders, two struts and two boxes; the lens is last."""
    var generator = StreetlightGenerator()
    var geometry = generator.geometry()
    assert_equal(geometry.vertex_count(), 52 + 52 + 40 + 40 + 24 + 24)
    assert_equal(_part_at(geometry, 0), 0)
    assert_equal(_part_at(geometry, geometry.vertex_count() - 1), 1)
    var bounds = geometry.bounding_box()
    assert_almost_equal(bounds.min.y, 0, atol=1e-6)
    assert_almost_equal(bounds.max.z, 2.4 + 0.2 + 0.35, atol=1e-5)
    var lights = generator.build(_two())
    assert_equal(lights.name, "Streetlights")
    assert_equal(lights.count(), 2)
    assert_true(lights.visible())
    assert_true(lights.cast_shadow)
    assert_false(lights.receive_shadow)
    assert_false(generator.build(List[Matrix4]()).visible())


def test_traffic_signal_matches_three() raises:
    """A pole, an arm, a drop, two boxes and three lenses."""
    var generator = TrafficlightGenerator()
    var geometry = generator.geometry()
    assert_equal(geometry.vertex_count(), 52 * 3 + 40 + 24 * 2 + 76 * 3)
    var last = geometry.vertex_count() - 1
    assert_equal(_part_at(geometry, last), 3)
    assert_equal(_part_at(geometry, last - 76), 2)
    assert_equal(_part_at(geometry, last - 152), 1)
    var bounds = geometry.bounding_box()
    assert_almost_equal(bounds.max.z, 5.5, atol=1e-5)
    assert_almost_equal(bounds.max.y, 6.5, atol=1e-5)
    var signals = generator.build(_two())
    assert_equal(signals.name, "Trafficlights")
    assert_true(signals.receive_shadow)


def test_trashcan_matches_three() raises:
    """An open drum, two rims, a bag and a welded mound."""
    var generator = TrashcanGenerator()
    var geometry = generator.geometry()
    var mound = merge_vertices(icosahedron(Length(0.28 * 0.82, METER), 1))
    assert_equal(
        geometry.vertex_count(), 34 + 100 + 100 + 76 + mound.vertex_count()
    )
    assert_equal(_part_at(geometry, 0), 0)
    assert_equal(_part_at(geometry, 34), 1)
    assert_equal(_part_at(geometry, geometry.vertex_count() - 1), 2)
    var bounds = geometry.bounding_box()
    assert_almost_equal(bounds.min.y, 0, atol=1e-6)
    assert_equal(generator.build(_two()).name, "Trashcans")


def test_bench_matches_three() raises:
    """Twelve iron boxes, then five seat slats and three back slats."""
    var generator = BenchGenerator()
    var geometry = generator.geometry()
    assert_equal(geometry.vertex_count(), 20 * 24)
    assert_equal(_part_at(geometry, 0), 1)
    assert_equal(_part_at(geometry, 12 * 24), 0)
    var bounds = geometry.bounding_box()
    assert_almost_equal(bounds.max.x, 0.83 + 0.03, atol=1e-5)
    assert_almost_equal(bounds.min.y, 0, atol=1e-6)
    # The top back slat, centered at 0.85 and reclined by 0.18 radians.
    assert_almost_equal(
        bounds.max.y,
        Float32(0.85 + 0.045 * cos(0.18) + 0.0125 * sin(0.18)),
        atol=1e-5,
    )
    assert_equal(generator.build(_two()).name, "Benches")


def test_hydrant_matches_three() raises:
    """Nine body parts, a dome among them, then four bare caps."""
    var generator = HydrantGenerator()
    var geometry = generator.geometry()
    assert_equal(geometry.vertex_count(), 76 * 5 + 55 + 52 * 3 + 52 * 3 + 40)
    assert_equal(_part_at(geometry, 0), 0)
    assert_equal(_part_at(geometry, geometry.vertex_count() - 1), 1)
    var bounds = geometry.bounding_box()
    assert_almost_equal(bounds.max.y, 0.905, atol=1e-5)
    assert_almost_equal(bounds.max.z, 0.13 + 0.102 + 0.0125, atol=1e-5)
    assert_equal(generator.build(_two()).name, "Hydrants")


def test_street_tree_matches_three() raises:
    """Soil, a grate, the wood and six clumps."""
    var generator = StreetTreeGenerator()
    var geometry = generator.geometry()
    var clumps = 0
    var radii: List[Float64] = [2.15, 1.5, 1.45, 1.3, 1.25, 1.1]
    for i in range(6):
        clumps += leaf_clump(radii[i], 0, 0, 0).vertex_count()
    assert_equal(geometry.vertex_count(), 64 + 85 + 52 * 2 + 34 * 4 + clumps)
    assert_equal(_part_at(geometry, 0), 0)
    assert_equal(_part_at(geometry, 64), 2)
    assert_equal(_part_at(geometry, 64 + 85), 0)
    assert_equal(_part_at(geometry, geometry.vertex_count() - 1), 1)
    var bounds = geometry.bounding_box()
    assert_almost_equal(bounds.min.y, 0, atol=1e-6)
    assert_true(bounds.max.y > 5.5)
    assert_equal(generator.build(_two()).name, "StreetTrees")


def test_a_clump_blends_toward_the_crown() raises:
    """A clump at the crown's center has normals that point out of it,
    and every normal is unit length."""
    var clump = leaf_clump(2.15, 0, 3.9, 0.1)
    ref n = clump.attribute_view(String(NORMAL))
    ref p = clump.attribute_view(String(POSITION))
    for i in range(clump.vertex_count()):
        var normal = n.vector3(i)
        assert_almost_equal(normal.length(), 1, atol=1e-5)
        var out = p.vector3(i)
        out.y -= 3.9
        out.z -= 0.1
        assert_true(normal.dot(out) > 0)
    assert_almost_equal(
        clump_hash(0.1, 0.2, 0.3), 0.9140054186032103, atol=1e-9
    )


def test_turning_one_unit_vector_onto_another() raises:
    """The turn from one direction to another, and to its opposite."""
    var up = Vec3d(0, 1, 0)
    var m = unit_vectors_turn(up, Vec3d(0, 0, 1))
    var turned = m.transform_direction(up.vector3())
    assert_almost_equal(turned.z, 1, atol=1e-6)
    var flipped = unit_vectors_turn(up, Vec3d(0, -1, 0))
    assert_almost_equal(
        flipped.transform_direction(up.vector3()).y, -1, atol=1e-6
    )
    var side = Vec3d(1, 0, 0)
    assert_almost_equal(
        unit_vectors_turn(side, Vec3d(-1, 0, 0))
        .transform_direction(side.vector3())
        .x,
        -1,
        atol=1e-6,
    )


def test_sidewalk_matches_three() raises:
    """A rounded slab and a curb with the slab's outline cut out."""
    var generator = SidewalkGenerator()
    var slab = generator.slab_geometry()
    var curb = generator.curb_geometry()
    assert_equal(slab.vertex_count(), 2 * 26 * 3 + 28 * 6)
    assert_equal(curb.vertex_count(), 2 * 56 * 3 + 56 * 6)
    var bounds = slab.bounding_box()
    assert_almost_equal(bounds.max.x, 45 - 0.13 + 0.03, atol=1e-4)
    assert_almost_equal(bounds.max.y, 0.5, atol=1e-5)
    assert_almost_equal(bounds.min.y, 0, atol=1e-5)
    var rim = curb.bounding_box()
    assert_almost_equal(rim.max.x, 45, atol=1e-4)
    assert_almost_equal(rim.max.z, 30, atol=1e-4)
    assert_almost_equal(rim.max.y, 0.51, atol=1e-5)
    var sidewalk = generator.build(_two())
    assert_equal(sidewalk.slab.count(), 2)
    assert_equal(sidewalk.curb.count(), 2)
    assert_false(sidewalk.slab.cast_shadow)
    assert_false(sidewalk.curb.cast_shadow)
    assert_true(sidewalk.curb.receive_shadow)


def test_a_tight_corner_is_clamped() raises:
    """A corner radius past half a side is cut to half the side, and a
    small radius leaves a half-meter floor on the inner corner."""
    var shape = rounded_rect(4, 2, 5)
    var points = shape.outline_points(6)
    assert_almost_equal(points[0].x, -1, atol=1e-6)
    # The sides of no length are left out, as three.js's `getPoints`
    # skips the repeated point: two lines and four curves of six.
    assert_equal(len(points), 1 + 2 + 4 * 6)
    var generator = SidewalkGenerator()
    generator.radius = Length(0.1, METER)
    var slab = generator.slab_geometry()
    assert_equal(slab.vertex_count(), 2 * 26 * 3 + 28 * 6)
    var up = extrude_up(rounded_rect(4, 2, 0.5), 1)
    assert_almost_equal(up.bounding_box().max.y, 1, atol=1e-5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
