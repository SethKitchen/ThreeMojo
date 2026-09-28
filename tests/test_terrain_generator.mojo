# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `generators.terrain`, three.js's `TerrainGenerator`.

The expected numbers were computed from three.js r186's
`examples/jsm/generators/TerrainGenerator.js` and `ImprovedNoise.js`,
step for step in `Float64`, with the heights rounded to `Float32` where
three.js stores them. The grids are small, twelve cells a side, so the
suite stays fast.
"""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from generators.terrain import (
    TerrainGenerator,
    TerrainParameters,
    thermal_erode,
)
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import InverseLength, Length, METER, PER_METER


def _terrain(segments: Int = 12) -> TerrainParameters:
    """Return three.js's default terrain on a small grid."""
    var p = TerrainParameters()
    p.segments = segments
    return p^


def _normal(
    geometry: BufferGeometry, index: Int, x: Float32, y: Float32, z: Float32
) raises:
    """Assert the normal of one vertex."""
    var n = geometry.attribute_view(String(NORMAL)).vector3(index)
    assert_almost_equal(n.x, x, atol=1e-6)
    assert_almost_equal(n.y, y, atol=1e-6)
    assert_almost_equal(n.z, z, atol=1e-6)


def test_defaults_are_three() raises:
    """The parameters default to three.js's."""
    var p = TerrainParameters()
    assert_equal(p.seed, 1)
    assert_equal(p.size.to(METER), 200)
    assert_equal(p.segments, 192)
    assert_equal(p.height_scale.to(METER), 65)
    assert_almost_equal(p.frequency.to(PER_METER), 0.01)
    assert_equal(p.octaves, 5)
    assert_equal(p.lacunarity, 1.97)
    assert_equal(p.talus_passes, 12)
    var generator = TerrainGenerator()
    assert_equal(generator.grid_size, 0)


def test_small_terrain_matches_three() raises:
    """Heights, normals, bounds and samples follow three.js."""
    var generator = TerrainGenerator(_terrain())
    var geometry = generator.build()
    assert_equal(generator.grid_size, 13)
    assert_equal(geometry.vertex_count(), 169)
    assert_equal(len(geometry.index), 12 * 12 * 6)
    assert_almost_equal(generator.min_y.to(METER), 2.742187738418579, atol=1e-5)
    assert_almost_equal(generator.max_y.to(METER), 37.121307373046875, atol=1e-5)
    assert_almost_equal(generator.heights[0], 37.121307373046875, atol=1e-4)
    assert_almost_equal(generator.heights[84], 22.182085037231445, atol=1e-4)
    assert_almost_equal(generator.heights[168], 14.970646858215332, atol=1e-4)
    var corner = geometry.attribute_view(String(POSITION)).vector3(0)
    assert_equal(corner.x, -100)
    assert_equal(corner.z, -100)
    _normal(geometry, 0, 0.43631829, 0.86561365, 0.24564072)
    _normal(geometry, 84, -0.01904448, 0.98422480, -0.17589444)
    _normal(geometry, 168, -0.31741371, 0.94655735, 0.05725138)
    assert_almost_equal(
        generator.height_at(13.3, -40.7), 12.870032464324954, atol=1e-4
    )
    assert_almost_equal(
        generator.slope_at(13.3, -40.7), 0.9895700358497522, atol=1e-6
    )
    var h = generator.sample_height(Length(0, METER), Length(0, METER))
    assert_almost_equal(h.to(METER), 22.182085037231445, atol=1e-4)
    assert_almost_equal(
        generator.sample_slope(Length(0, METER), Length(0, METER)),
        0.9842247984076578,
        atol=1e-6,
    )
    # Off the patch, the nearest edge is read, and it is flat across.
    assert_almost_equal(
        generator.height_at(150, 150), 14.970646858215332, atol=1e-4
    )
    assert_almost_equal(generator.slope_at(150, 150), 1.0, atol=1e-9)


def test_quads_alternate_their_diagonal() raises:
    """An even quad cuts from b to c, an odd one from a to d."""
    var generator = TerrainGenerator(_terrain(2))
    var geometry = generator.build()
    # Quad (0, 0) is even: a c b, b c d with a 0, b 1, c 3, d 4.
    assert_equal(geometry.index[0], 0)
    assert_equal(geometry.index[1], 3)
    assert_equal(geometry.index[2], 1)
    assert_equal(geometry.index[3], 1)
    assert_equal(geometry.index[4], 3)
    assert_equal(geometry.index[5], 4)
    # Quad (1, 0) is odd: a c d, a d b with a 1, b 2, c 4, d 5.
    assert_equal(geometry.index[6], 1)
    assert_equal(geometry.index[7], 4)
    assert_equal(geometry.index[8], 5)
    assert_equal(geometry.index[9], 1)
    assert_equal(geometry.index[10], 5)
    assert_equal(geometry.index[11], 2)


def test_erosion_relaxes_steep_slopes() raises:
    """A low angle of repose moves material as three.js moves it."""
    var p = _terrain()
    p.talus = 0.2
    var generator = TerrainGenerator(p^)
    var geometry = generator.build()
    assert_almost_equal(generator.min_y.to(METER), 10.996254920959473, atol=1e-4)
    assert_almost_equal(generator.max_y.to(METER), 32.98222732543945, atol=1e-4)
    assert_almost_equal(generator.heights[0], 32.38276672363281, atol=1e-4)
    assert_almost_equal(generator.heights[84], 21.677453994750977, atol=1e-4)
    _normal(geometry, 0, 0.19947138, 0.97217977, 0.12279117)
    assert_almost_equal(
        generator.height_at(13.3, -40.7), 15.989714438587189, atol=1e-4
    )


def test_no_erosion_pass_keeps_the_heights() raises:
    """Zero passes leave the baked heights as they are."""
    var p = _terrain()
    p.talus = 0.2
    p.talus_passes = 0
    var generator = TerrainGenerator(p^)
    _ = generator.build()
    assert_almost_equal(generator.heights[0], 37.121307373046875, atol=1e-4)


def test_erosion_conserves_material() raises:
    """A spike sheds to its neighbors and nothing is lost."""
    var h: List[Float32] = [0, 0, 0, 0, 9, 0, 0, 0, 0]
    thermal_erode(h, 3, 1.0, 1.0, 1)
    assert_equal(h[4], 5)
    assert_equal(h[1], 1)
    assert_equal(h[3], 1)
    var total: Float32 = 0
    for i in range(9):
        total += h[i]
    assert_equal(total, 9)
    # A grid of no vertex has nothing to erode.
    var empty = List[Float32]()
    thermal_erode(empty, 0, 1.0, 1.0, 1)
    assert_equal(len(empty), 0)


def test_no_octave_is_flat() raises:
    """With no octave the height is the midpoint everywhere, so there is
    nothing to erode and every normal points up."""
    var p = _terrain()
    p.octaves = 0
    p.seed = 5
    p.talus = 0.2
    var generator = TerrainGenerator(p^)
    var geometry = generator.build()
    assert_almost_equal(generator.min_y.to(METER), 21.97112464904785, atol=1e-5)
    assert_equal(generator.min_y.to(METER), generator.max_y.to(METER))
    _normal(geometry, 84, 0, 1, 0)


def test_sampling_needs_a_build() raises:
    """A terrain is sampled after it is baked."""
    var generator = TerrainGenerator()
    with assert_raises(contains="built"):
        _ = generator.sample_height(Length(0, METER), Length(0, METER))
    with assert_raises(contains="built"):
        _ = generator.sample_slope(Length(0, METER), Length(0, METER))
    with assert_raises(contains="built"):
        _ = generator.height_at(0, 0)
    with assert_raises(contains="built"):
        _ = generator.slope_at(0, 0)


def _refused(var p: TerrainParameters, message: String) raises:
    """Assert that building a terrain is refused."""
    var generator = TerrainGenerator(p^)
    with assert_raises(contains=message):
        _ = generator.build()


def test_terrain_parameters_are_checked() raises:
    """Parameters that bake no grid are refused."""
    var p = _terrain()
    p.size = Length(0, METER)
    _refused(p^, "size")
    p = _terrain()
    p.segments = 0
    _refused(p^, "segment")
    p = _terrain()
    p.octaves = -1
    _refused(p^, "octave")
    p = _terrain()
    p.talus_passes = -1
    _refused(p^, "pass count")
    p = _terrain()
    p.gain = nan[DType.float64]()
    _refused(p^, "noise parameter")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
