# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `VXGIConeTracer`: the voxel grid and its levels,
the filtered reads, the ray's entry and exit, the cone's march, and the
hash, the noise and the texel formats the VXGI kernels share. The
expected numbers are three.js's formulas worked by hand, or in Python for
the hash and the half floats."""

from lights.vxgi_cone_tracer import (
    Lanes,
    UNBOUNDED,
    VXGI_HEADER,
    VxgiGrid,
    cosine_direction,
    floats_of,
    fract,
    half_rounded,
    interleaved_gradient_noise,
    intersect_volume,
    ints_of,
    pcg_hash,
    sample_level,
    sample_volume,
    tangent_frame,
    trace_cone,
    unorm8,
    voxel_at,
)
from math.vector3 import Vector3
from std.math import inf, isinf, isnan, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)


def a_grid(levels: Int = 1) -> VxgiGrid:
    """Return a grid of four voxels a side, a meter each, from the origin."""
    return VxgiGrid(
        Vector3(0, 0, 0), Vector3(4, 4, 4), 1, 4, 4, 4, levels, 0.5
    )


def filled(grid: VxgiGrid, texel: Lanes) -> List[Float32]:
    """Return a whole chain with every voxel set to one texel."""
    var out = List[Float32]()
    for _ in range(grid.total()):
        out.extend([texel[0], texel[1], texel[2], texel[3]])
    return out^


def test_a_grid_reads_back_from_its_header() raises:
    var grid = VxgiGrid(
        Vector3(-1, -2, -3), Vector3(4, 5, 6), 0.25, 16, 20, 24, 3, 0.75
    )
    var header = grid.header()
    assert_equal(len(header), VXGI_HEADER)
    var back = VxgiGrid(header=floats_of(header))
    assert_true(back.bounds_min == grid.bounds_min)
    assert_true(back.volume_size == grid.volume_size)
    assert_equal(back.voxel_size, 0.25)
    assert_equal(back.size_x, 16)
    assert_equal(back.size_y, 20)
    assert_equal(back.size_z, 24)
    assert_equal(back.levels, 3)
    assert_equal(back.step_scale, 0.75)
    _ = header^


def test_a_grid_s_levels_halve_and_follow_each_other() raises:
    var grid = a_grid(3)
    assert_equal(grid.max_level(), 2)
    assert_equal(grid.level_x(1), 2)
    assert_equal(grid.level_y(2), 1)
    assert_equal(grid.level_z(1), 2)
    assert_equal(grid.level_count(0), 64)
    assert_equal(grid.level_start(0), 0)
    assert_equal(grid.level_start(1), 64)
    assert_equal(grid.level_start(2), 72)
    assert_equal(grid.total(), 73)
    # x fastest, then y, then z, inside the level.
    assert_equal(grid.index(1, 1, 1, 1), 64 + 1 + 2 * (1 + 2 * 1))
    assert_true(grid.center(0, 1, 2) == Vector3(0.5, 1.5, 2.5))


def test_a_level_is_read_trilinear_and_held_at_the_edge() raises:
    var grid = a_grid()
    var values = filled(grid, Lanes(0, 0, 0, 0))
    # The voxel at (1, 0, 0) is one; the rest are zero.
    values[4] = 1
    var volume = floats_of(values)
    assert_equal(voxel_at(volume, 1)[0], 1)
    # At its center, the voxel alone.
    assert_equal(sample_level(volume, grid, Vector3(0.375, 0.125, 0.125), 0)[0], 1)
    # Half way to its neighbor across, half of it.
    assert_almost_equal(
        sample_level(volume, grid, Vector3(0.25, 0.125, 0.125), 0)[0],
        0.5,
        atol=1e-6,
    )
    # Half way along every axis: an eighth.
    assert_almost_equal(
        sample_level(volume, grid, Vector3(0.25, 0.25, 0.25), 0)[0],
        0.125,
        atol=1e-6,
    )
    # Far past the edge the edge voxels are read.
    assert_equal(
        sample_level(volume, grid, Vector3(0.375, -1e20, -1e20), 0)[0], 1
    )
    assert_equal(sample_level(volume, grid, Vector3(1e20, 0.1, 0.1), 0)[0], 0)
    _ = values^


def test_a_level_of_detail_mixes_the_two_levels_around_it() raises:
    var grid = a_grid(2)
    var values = filled(grid, Lanes(1, 1, 1, 1))
    for at in range(grid.level_start(1) * 4, grid.total() * 4):
        values[at] = 3
    var volume = floats_of(values)
    var middle = Vector3(0.5, 0.5, 0.5)
    assert_equal(sample_volume(volume, grid, middle, 0)[0], 1)
    assert_almost_equal(sample_volume(volume, grid, middle, 0.5)[0], 2, atol=1e-6)
    assert_equal(sample_volume(volume, grid, middle, 1)[0], 3)
    # Held inside the chain.
    assert_equal(sample_volume(volume, grid, middle, 7)[0], 3)
    assert_equal(sample_volume(volume, grid, middle, -2)[0], 1)
    _ = values^


def test_a_ray_enters_and_leaves_the_box() raises:
    var grid = a_grid()
    var span = intersect_volume(grid, Vector3(-2, 1, 1), Vector3(1, 0, 0))
    assert_almost_equal(span[0], 2, atol=1e-4)
    assert_almost_equal(span[1], 6, atol=1e-4)
    # From inside, the entry is held at zero.
    span = intersect_volume(grid, Vector3(1, 1, 1), Vector3(0, 0, -1))
    assert_equal(span[0], 0)
    assert_almost_equal(span[1], 1, atol=1e-4)
    # Up the y axis, and a ray that misses: its exit is before its entry.
    span = intersect_volume(grid, Vector3(1, -1, 1), Vector3(0, 1, 0))
    assert_almost_equal(span[0], 1, atol=1e-4)
    span = intersect_volume(grid, Vector3(-2, 9, 1), Vector3(1, 0, 0))
    assert_true(span[1] <= span[0])


def test_a_cone_through_empty_voxels_gathers_nothing() raises:
    var grid = a_grid()
    var empty = filled(grid, Lanes(0, 0, 0, 0))
    var cone = trace_cone(
        grid,
        floats_of(empty),
        floats_of(empty),
        True,
        Vector3(0.5, 0.5, 0.5),
        Vector3(1, 0, 0),
        0.1,
        UNBOUNDED,
        1,
        True,
        128,
    )
    assert_equal(cone.alpha, 0)
    assert_equal(cone.red, 0)
    assert_equal(cone.ao, 0)
    _ = empty^


def test_a_cone_into_solid_voxels_takes_their_light_and_stops() raises:
    var grid = a_grid()
    var solid = filled(grid, Lanes(1, 1, 1, 1))
    var light = filled(grid, Lanes(0.5, 0.25, 0, 0.5))
    var cone = trace_cone(
        grid,
        floats_of(solid),
        floats_of(light),
        True,
        Vector3(0.5, 0.5, 0.5),
        Vector3(1, 0, 0),
        0.1,
        UNBOUNDED,
        1,
        True,
        128,
    )
    # One step: fully opaque, `1 - (1 - 1)^0.5`, so the radiance over its
    # weight is taken whole, at one voxel out.
    assert_equal(cone.alpha, 1)
    assert_almost_equal(cone.red, 1, atol=1e-6)
    assert_almost_equal(cone.green, 0.5, atol=1e-6)
    assert_equal(cone.blue, 0)
    # `1 / (1 + t / aoDistance)` at t of one voxel.
    assert_almost_equal(cone.ao, 0.5, atol=1e-6)
    _ = solid^
    _ = light^


def test_a_cone_s_occlusion_has_no_falloff_at_zero_distance() raises:
    var grid = a_grid()
    var solid = filled(grid, Lanes(1, 1, 1, 1))
    var cone = trace_cone(
        grid,
        floats_of(solid),
        floats_of(solid),
        False,
        Vector3(0.5, 0.5, 0.5),
        Vector3(1, 0, 0),
        0.1,
        UNBOUNDED,
        0,
        True,
        128,
    )
    assert_equal(cone.ao, 1)
    assert_equal(cone.red, 0)
    # Without `occludes`, no occlusion at all.
    cone = trace_cone(
        grid,
        floats_of(solid),
        floats_of(solid),
        False,
        Vector3(0.5, 0.5, 0.5),
        Vector3(1, 0, 0),
        0.1,
        UNBOUNDED,
        1,
        False,
        128,
    )
    assert_equal(cone.ao, 0)
    assert_equal(cone.alpha, 1)
    _ = solid^


def test_a_thin_fog_is_corrected_for_the_step() raises:
    var grid = a_grid()
    var fog = filled(grid, Lanes(0.36, 0.36, 0.36, 1))
    var cone = trace_cone(
        grid,
        floats_of(fog),
        floats_of(fog),
        False,
        Vector3(0.5, 0.5, 0.5),
        Vector3(0, 0, 1),
        0,
        Float32(1.25),
        0,
        False,
        128,
    )
    # A half-texel step keeps `1 - (1 - 0.36)^0.5` = 0.2 of the light at
    # each step. Steps at 1 and 1.5 fall before the 1.25 limit and past
    # it: only the first counts.
    assert_almost_equal(cone.alpha, 0.2, atol=1e-5)
    _ = fog^


def test_a_cone_that_misses_or_takes_no_step_gathers_nothing() raises:
    var grid = a_grid()
    var solid = filled(grid, Lanes(1, 1, 1, 1))
    var cone = trace_cone(
        grid,
        floats_of(solid),
        floats_of(solid),
        True,
        Vector3(-2, 9, 1),
        Vector3(1, 0, 0),
        0.1,
        UNBOUNDED,
        1,
        True,
        128,
    )
    assert_equal(cone.alpha, 0)
    cone = trace_cone(
        grid,
        floats_of(solid),
        floats_of(solid),
        True,
        Vector3(0.5, 0.5, 0.5),
        Vector3(1, 0, 0),
        0.1,
        UNBOUNDED,
        1,
        True,
        0,
    )
    assert_equal(cone.alpha, 0)
    _ = solid^


def test_the_hash_is_three_js_s_pcg_hash() raises:
    # Worked in Python from three.js's `hash`, 32-bit wrapping.
    assert_almost_equal(pcg_hash(0), 0.030199997127056122, atol=1e-7)
    assert_almost_equal(pcg_hash(1), 0.6591631174087524, atol=1e-7)
    assert_almost_equal(pcg_hash(7), 0.49376022815704346, atol=1e-7)
    assert_almost_equal(pcg_hash(12345), 0.9545696377754211, atol=1e-7)


def test_the_noise_is_interleaved_gradient_noise() raises:
    assert_almost_equal(
        interleaved_gradient_noise(0.5, 0.5), 0.9324913024902344, atol=1e-4
    )
    assert_almost_equal(
        interleaved_gradient_noise(10.5, 3.5), 0.4174308776855469, atol=1e-4
    )
    assert_almost_equal(fract(-0.25), 0.75, atol=1e-7)


def test_the_tangent_frame_starts_from_up_or_from_x() raises:
    var frame = tangent_frame(Vector3(0, 0, 1))
    assert_true(frame[0] == Vector3(-1, 0, 0))
    assert_true(frame[1] == Vector3(0, -1, 0))
    frame = tangent_frame(Vector3(0, 1, 0))
    assert_true(frame[0] == Vector3(0, 0, -1))
    assert_true(frame[1] == Vector3(-1, 0, 0))


def test_a_cosine_direction_runs_from_the_pole_to_the_rim() raises:
    var t = Vector3(1, 0, 0)
    var b = Vector3(0, 1, 0)
    var n = Vector3(0, 0, 1)
    var pole = cosine_direction(t, b, n, 0, 0.3)
    assert_almost_equal(pole.z, 1, atol=1e-6)
    var rim = cosine_direction(t, b, n, 1, 0)
    assert_almost_equal(rim.x, 1, atol=1e-6)
    var quarter = cosine_direction(t, b, n, 1, 0.25)
    assert_almost_equal(quarter.y, 1, atol=1e-6)
    # Half way out: 45 degrees from the pole.
    var middle = cosine_direction(t, b, n, 0.5, 0)
    assert_almost_equal(middle.x, middle.z, atol=1e-6)


def test_an_eight_bit_texel_rounds_to_its_step() raises:
    assert_almost_equal(unorm8(0.5), Float32(128) / 255, atol=1e-7)
    assert_almost_equal(unorm8(0.25), Float32(64) / 255, atol=1e-7)
    assert_equal(unorm8(-1), 0)
    assert_equal(unorm8(2), 1)


def test_a_half_float_texel_rounds_to_the_nearest_half() raises:
    # Python's `struct` 'e', which rounds ties to even.
    assert_equal(half_rounded(1.0), 1.0)
    assert_equal(half_rounded(1.0007), 1.0009765625)
    assert_equal(half_rounded(-1.0007), -1.0009765625)
    assert_equal(half_rounded(0.1), 0.0999755859375)
    assert_equal(half_rounded(65519), 65504)
    assert_true(isinf(half_rounded(65520)))
    assert_true(isinf(half_rounded(inf[DType.float32]())))
    assert_true(isnan(half_rounded(nan[DType.float32]())))
    assert_equal(half_rounded(6.103515625e-05), 6.103515625e-05)
    assert_equal(half_rounded(3e-05), 2.9981136322021484e-05)
    # Subnormal halves: whole numbers of 2^-24, ties to even.
    var unit = Float32(5.9604644775390625e-8)
    assert_equal(half_rounded(unit * 1.5), unit * 2)
    assert_equal(half_rounded(unit * 2.5), unit * 2)
    assert_equal(half_rounded(unit * 1.75), unit * 2)
    assert_equal(half_rounded(unit * 1.25), unit)
    assert_equal(half_rounded(-unit * 1.25), -unit)
    assert_equal(half_rounded(unit * 0.25), 0)


def test_a_list_of_integers_is_read_through_a_pointer() raises:
    var values: List[Int32] = [3, 5]
    var at = ints_of(values)
    assert_equal(at[unsafe_offset=1], 5)
    _ = values^


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
