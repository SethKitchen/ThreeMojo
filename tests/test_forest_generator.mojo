# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `generators.forest`, three.js's `ForestGenerator`.

The expected numbers were computed from three.js r186's
`examples/jsm/generators/ForestGenerator.js`, step for step in `Float64`,
on three.js's default terrain baked twelve cells a side.
"""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from generators.forest import (
    AO,
    ForestGenerator,
    ForestParameters,
    blob_geometry,
    blob_noise,
    smooth_blend,
)
from generators.terrain import TerrainGenerator, TerrainParameters
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import InverseLength, Length, METER, PER_METER


def _terrain() raises -> TerrainGenerator:
    """Return three.js's default terrain, baked twelve cells a side."""
    var p = TerrainParameters()
    p.segments = 12
    var terrain = TerrainGenerator(p^)
    _ = terrain.build()
    return terrain^


def _forest(count: Int) -> ForestParameters:
    """Return the forest the reference was computed for."""
    var p = ForestParameters()
    p.count = count
    p.density_frequency = InverseLength(0.05, PER_METER)
    return p^


def _matrix(m: Matrix4, expected: List[Float32]) raises:
    """Assert a matrix, its elements in column-major order."""
    for i in range(16):
        assert_almost_equal(m.elements[i], expected[i], atol=2e-5)


def test_blob_matches_three() raises:
    """The blob welds to twelve vertices, squashed as three.js does."""
    var geometry = blob_geometry(ForestParameters())
    assert_equal(geometry.vertex_count(), 12)
    assert_equal(len(geometry.index), 60)
    assert_equal(geometry.index[0], 0)
    assert_equal(geometry.index[1], 1)
    assert_equal(geometry.index[2], 2)
    assert_equal(geometry.index[3], 1)
    var p = geometry.attribute_view(String(POSITION)).vector3(0)
    assert_almost_equal(p.x, -0.8903305, atol=1e-5)
    assert_almost_equal(p.y, 2.0, atol=1e-5)
    assert_almost_equal(p.z, 0.5502545, atol=1e-5)
    var n = geometry.attribute_view(String(NORMAL)).vector3(11)
    assert_almost_equal(n.x, 0.6909784, atol=1e-6)
    assert_almost_equal(n.y, 0.7228754, atol=1e-6)
    assert_almost_equal(n.z, 0.0, atol=1e-6)
    var last = geometry.attribute_view(String(POSITION)).vector3(11)
    assert_almost_equal(last.x, 0.4159872, atol=1e-5)
    assert_almost_equal(last.y, 0.2986984, atol=1e-5)
    assert_almost_equal(
        geometry.attribute_view(String(AO)).component(11, 0),
        0.0746746,
        atol=1e-6,
    )


def test_helpers_match_three() raises:
    """The blend and the lump are three.js's."""
    assert_equal(smooth_blend(0, 1, 0.5), 0.5)
    assert_equal(smooth_blend(0, 1, -1), 0)
    assert_equal(smooth_blend(1, 0, -1), 1)
    assert_almost_equal(
        blob_noise(0.1, 0.2, 0.3), -0.0024723304851889394, atol=1e-12
    )


def test_forest_matches_three() raises:
    """Twenty trees stand where three.js plants them."""
    var terrain = _terrain()
    var forest = ForestGenerator(_forest(20)).build(terrain)
    assert_equal(forest.instances.count(), 20)
    assert_equal(forest.attempts, 256)
    assert_equal(forest.instances.name, "Forest")
    assert_equal(forest.instances.item_size, 4)
    assert_equal(len(forest.instances.values), 80)
    assert_equal(len(forest.region), 20)
    _matrix(
        forest.instances.matrices[0],
        [
            -0.2182779,
            -0.0265286,
            1.1737572,
            0,
            -0.0019502,
            1.1979062,
            0.0267118,
            0,
            -1.0504148,
            0.0026444,
            -0.1952808,
            0,
            96.2101935,
            13.9669520,
            93.6755796,
            1,
        ],
    )
    _matrix(
        forest.instances.matrices[19],
        [
            -0.1202563,
            0.0176441,
            -1.1134509,
            0,
            -0.0003821,
            1.1176013,
            0.0177511,
            0,
            1.0812943,
            0.0022241,
            -0.1167480,
            0,
            97.9592666,
            14.6426076,
            38.4064488,
            1,
        ],
    )
    assert_almost_equal(forest.instances.values[3], 0.5346625, atol=1e-6)
    assert_almost_equal(forest.instances.values[79], 0.1451809, atol=1e-6)
    assert_almost_equal(forest.region[0], 0.5506339, atol=1e-6)
    assert_almost_equal(forest.region[19], 0.5573054, atol=1e-6)
    assert_false(forest.cast_shadow)
    assert_false(forest.receive_shadow)


def test_steep_ground_stays_bare() raises:
    """With a flatness above any ground, nothing is planted and the draw
    gives up after fourteen tries a tree."""
    var terrain = _terrain()
    var p = ForestParameters()
    p.count = 2
    p.min_slope = 0.99
    p.cast_shadow = True
    var forest = ForestGenerator(p^).build(terrain)
    assert_equal(forest.instances.count(), 0)
    assert_equal(forest.attempts, 28)
    assert_true(forest.cast_shadow)
    assert_true(forest.receive_shadow)


def test_no_tree_asked_for_none_planted() raises:
    """A count of zero draws nothing."""
    var terrain = _terrain()
    var forest = ForestGenerator(_forest(0)).build(terrain)
    assert_equal(forest.instances.count(), 0)
    assert_equal(forest.attempts, 0)


def test_the_cull_thins_far_trees() raises:
    """A tree is drawn while its threshold is at least its place in the
    band between the start and the end of the cull."""
    var terrain = _terrain()
    var forest = ForestGenerator(_forest(20)).build(terrain)
    var at = Vector3(96.2101935, 13.9669520, 93.6755796)
    assert_true(forest.keeps(0, at))
    var far = Vector3(96.2101935 + 1000, 13.9669520, 93.6755796)
    assert_false(forest.keeps(0, far))
    # Halfway through the band: 0.53 is kept, 0.15 is not.
    var halfway = Vector3(96.2101935, 13.9669520 + 460, 93.6755796)
    assert_true(forest.keeps(0, halfway))
    var other = Vector3(97.9592666, 14.6426076 + 460, 38.4064488)
    assert_false(forest.keeps(19, other))
    with assert_raises(contains="no tree"):
        _ = forest.keeps(-1, at)
    with assert_raises(contains="no tree"):
        _ = forest.keeps(20, at)


def test_forest_parameters_are_checked() raises:
    """A forest refuses what it cannot plant."""
    var terrain = _terrain()
    var p = ForestParameters()
    p.count = -1
    with assert_raises(contains="count"):
        _ = ForestGenerator(p^).build(terrain)
    p = ForestParameters()
    p.detail = -1
    with assert_raises(contains="detail"):
        _ = ForestGenerator(p^).build(terrain)
    p = ForestParameters()
    p.to_distance = Length(300, METER)
    with assert_raises(contains="cull"):
        _ = ForestGenerator(p^).build(terrain)
    p = ForestParameters()
    p.max_scale = nan[DType.float64]()
    with assert_raises(contains="scale"):
        _ = ForestGenerator(p^).build(terrain)
    with assert_raises(contains="built terrain"):
        _ = ForestGenerator().build(TerrainGenerator())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
