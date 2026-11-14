# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Label maps, label statistics, slice overlays and measurements."""

from extensions.imaging.ids import (
    BACKGROUND,
    I_AXIS,
    J_AXIS,
    K_AXIS,
    LabelId,
    MONOCHROME1,
    SliceAxis,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import (
    LabelMap,
    keep_largest,
    label_surface,
    region_grow,
    require_same_grid,
    threshold,
)
from extensions.imaging.measure import label_statistics, voxel_distance
from extensions.imaging.overlay import (
    draw_measurement,
    label_color,
    overlay_labels,
    render_slice,
    slice_size,
)
from extensions.imaging.transfer import Rgba
from extensions.sdf.vector import v3
from render.framebuffer import Framebuffer
from std.math import inf, nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER


def _mm(value: Float64) -> Length64:
    return Length64(value, MILLIMETER64)


def _volume(nx: Int, ny: Int, nz: Int) raises -> ImageVolume:
    return ImageVolume(nx, ny, nz, _mm(1), _mm(2), _mm(3))


def test_label_map_access() raises:
    var volume = _volume(2, 3, 4)
    var map = LabelMap(volume)
    assert_equal(map.count(), 24)
    map.set(1, 2, 3, LabelId(7))
    assert_true(map.get(1, 2, 3) == LabelId(7))
    assert_true(map.get(0, 0, 0) == BACKGROUND)
    assert_equal(map.voxels(LabelId(7)), 1)
    assert_equal(map.voxels(BACKGROUND), 23)
    assert_false(map.contains(-1, 0, 0))
    assert_false(map.contains(0, -1, 0))
    assert_false(map.contains(0, 0, -1))
    assert_false(map.contains(2, 0, 0))
    assert_false(map.contains(0, 3, 0))
    assert_false(map.contains(0, 0, 4))
    with assert_raises(contains="outside the label map"):
        _ = map.get(2, 0, 0)
    with assert_raises(contains="outside the label map"):
        map.set(0, 0, 4, LabelId(1))
    with assert_raises(contains="from 0 to 255"):
        map.set(0, 0, 0, LabelId(300))
    with assert_raises(contains="from 0 to 255"):
        _ = map.voxels(LabelId(-1))


def test_same_grid() raises:
    var map = LabelMap(_volume(2, 3, 4))
    require_same_grid(map, _volume(2, 3, 4))
    with assert_raises(contains="different grids"):
        require_same_grid(map, _volume(3, 3, 4))
    with assert_raises(contains="different grids"):
        require_same_grid(map, _volume(2, 4, 4))
    with assert_raises(contains="different grids"):
        require_same_grid(map, _volume(2, 3, 5))


def _ramp() raises -> ImageVolume:
    """A 5 by 1 by 1 volume of 0, 1, 2, 3, 4."""
    var volume = _volume(5, 1, 1)
    for i in range(5):
        volume.set(i, 0, 0, Float32(i))
    return volume^


def test_threshold() raises:
    var map = threshold(_ramp(), 1, 3, LabelId(2))
    assert_true(map.get(0, 0, 0) == BACKGROUND)
    assert_true(map.get(1, 0, 0) == LabelId(2))
    assert_true(map.get(3, 0, 0) == LabelId(2))
    assert_true(map.get(4, 0, 0) == BACKGROUND)
    with assert_raises(contains="finite ends"):
        _ = threshold(_ramp(), nan[DType.float64](), 3, LabelId(1))
    with assert_raises(contains="finite ends"):
        _ = threshold(_ramp(), 0, inf[DType.float64](), LabelId(1))
    with assert_raises(contains="finite ends"):
        _ = threshold(_ramp(), 3, 1, LabelId(1))
    with assert_raises(contains="other than the background"):
        _ = threshold(_ramp(), 1, 3, BACKGROUND)
    with assert_raises(contains="from 0 to 255"):
        _ = threshold(_ramp(), 1, 3, LabelId(256))


def test_region_grow_stays_connected() raises:
    # Two bright blocks on a line, apart: 5 5 0 5 5 5.
    var volume = _volume(6, 1, 1)
    for i in range(6):
        volume.set(i, 0, 0, 5)
    volume.set(2, 0, 0, 0)
    var map = region_grow(volume, 4, 0, 0, 4, 6, LabelId(1))
    assert_equal(map.voxels(LabelId(1)), 3)
    assert_true(map.get(1, 0, 0) == BACKGROUND)
    # In a cube every voxel connects through faces.
    var cube = _volume(3, 3, 3)
    var full = region_grow(cube, 1, 1, 1, -1, 1, LabelId(4))
    assert_equal(full.voxels(LabelId(4)), 27)
    # Growth stops below the range and above it.
    var ramp = region_grow(_ramp(), 2, 0, 0, 1, 2, LabelId(1))
    assert_equal(ramp.voxels(LabelId(1)), 2)
    assert_true(ramp.get(3, 0, 0) == BACKGROUND)
    # A grid of one voxel has no neighbors.
    var one = region_grow(_volume(1, 1, 1), 0, 0, 0, 0, 0, LabelId(1))
    assert_equal(one.voxels(LabelId(1)), 1)
    with assert_raises(contains="seed is outside"):
        _ = region_grow(volume, 6, 0, 0, 4, 6, LabelId(1))
    with assert_raises(contains="seed's value"):
        _ = region_grow(volume, 2, 0, 0, 4, 6, LabelId(1))
    with assert_raises(contains="seed's value"):
        _ = region_grow(volume, 0, 0, 0, 0, 1, LabelId(1))


def test_keep_largest() raises:
    var volume = _volume(7, 1, 1)
    var map = LabelMap(volume)
    # Pieces of two, one and three voxels, and another label.
    for i in [0, 1, 3, 5, 6]:
        map.set(i, 0, 0, LabelId(1))
    map.set(4, 0, 0, LabelId(2))
    var kept = keep_largest(map, LabelId(1))
    assert_equal(kept.voxels(LabelId(1)), 2)
    assert_true(kept.get(0, 0, 0) == LabelId(1))
    assert_true(kept.get(4, 0, 0) == LabelId(2))
    # Of two pieces of one size, the first stays.
    var tie = LabelMap(volume)
    tie.set(1, 0, 0, LabelId(3))
    tie.set(5, 0, 0, LabelId(3))
    var first = keep_largest(tie, LabelId(3))
    assert_true(first.get(1, 0, 0) == LabelId(3))
    assert_true(first.get(5, 0, 0) == BACKGROUND)
    with assert_raises(contains="no voxels"):
        _ = keep_largest(map, LabelId(9))
    with assert_raises(contains="other than the background"):
        _ = keep_largest(map, BACKGROUND)
    # A map of one voxel has no neighbors.
    var single = LabelMap(_volume(1, 1, 1))
    single.labels[0] = 1
    assert_equal(keep_largest(single, LabelId(1)).voxels(LabelId(1)), 1)
    # A cube connects in every direction.
    var cube = LabelMap(_volume(2, 2, 2))
    for index in range(8):
        cube.labels[index] = 1
    assert_equal(keep_largest(cube, LabelId(1)).voxels(LabelId(1)), 8)


def test_label_surface_is_halfway() raises:
    var volume = _volume(3, 3, 3)
    var map = LabelMap(volume)
    map.set(1, 1, 1, LabelId(5))
    var mesh = label_surface(map, LabelId(5))
    assert_true(mesh.triangle_count() > 0)
    var box = mesh.bounding_box()
    assert_almost_equal(box.min.x, 0.0005, atol=1e-7)
    assert_almost_equal(box.max.x, 0.0015, atol=1e-7)
    assert_almost_equal(box.min.y, 0.001, atol=1e-7)
    assert_almost_equal(box.max.z, 0.0045, atol=1e-7)
    with assert_raises(contains="no voxels"):
        _ = label_surface(map, LabelId(6))
    with assert_raises(contains="other than the background"):
        _ = label_surface(map, BACKGROUND)


def test_label_statistics() raises:
    var volume = _volume(4, 4, 4)
    var map = LabelMap(volume)
    volume.set(1, 2, 3, 10)
    volume.set(3, 0, 1, 30)
    map.set(1, 2, 3, LabelId(1))
    map.set(3, 0, 1, LabelId(1))
    var stats = label_statistics(map, volume, LabelId(1))
    assert_equal(stats.voxels, 2)
    # One voxel is 1 mm by 2 mm by 3 mm.
    assert_almost_equal(stats.volume.value, 2 * 6e-9)
    assert_almost_equal(stats.centroid.x, 0.002)
    assert_almost_equal(stats.centroid.y, 0.002)
    assert_almost_equal(stats.centroid.z, 0.006)
    assert_equal(stats.low_i, 1)
    assert_equal(stats.high_i, 3)
    assert_equal(stats.low_j, 0)
    assert_equal(stats.high_j, 2)
    assert_equal(stats.low_k, 1)
    assert_equal(stats.high_k, 3)
    assert_equal(stats.mean, 20)
    assert_equal(stats.minimum, 10)
    assert_equal(stats.maximum, 30)
    with assert_raises(contains="different grids"):
        _ = label_statistics(map, _volume(4, 4, 5), LabelId(1))
    with assert_raises(contains="from 0 to 255"):
        _ = label_statistics(map, volume, LabelId(256))
    with assert_raises(contains="other than the background"):
        _ = label_statistics(map, volume, BACKGROUND)
    with assert_raises(contains="no voxels"):
        _ = label_statistics(map, volume, LabelId(2))


def test_ellipsoid_volume_and_centroid() raises:
    # An ellipsoid with semi-axes of 9, 6 and 4 voxels, centered at
    # (12, 10, 8) on a 1 by 2 by 3 mm grid. Its voxels give the volume of
    # the ellipsoid to within four percent: 879 voxels for 904.8.
    var volume = _volume(24, 20, 16)
    for k in range(16):
        for j in range(20):
            for i in range(24):
                var x = (Float64(i) - 12) / 9
                var y = (Float64(j) - 10) / 6
                var z = (Float64(k) - 8) / 4
                if x * x + y * y + z * z <= 1:
                    volume.set(i, j, k, 1)
    var map = threshold(volume, 0.5, 1.5, LabelId(1))
    var stats = label_statistics(map, volume, LabelId(1))
    var exact = 4.0 / 3.0 * pi * (9 * 0.001) * (6 * 0.002) * (4 * 0.003)
    assert_true(abs(stats.volume.value - exact) < 0.04 * exact)
    assert_almost_equal(stats.centroid.x, 0.012, atol=1e-9)
    assert_almost_equal(stats.centroid.y, 0.020, atol=1e-9)
    assert_almost_equal(stats.centroid.z, 0.024, atol=1e-9)
    var span = voxel_distance(volume, v3(0, 0, 0), v3(3, 4, 0))
    assert_almost_equal(span.to(METER), sqrt(0.003**2 + 0.008**2))


def test_slice_sizes() raises:
    assert_true(slice_size(2, 3, 4, K_AXIS) == (2, 3))
    assert_true(slice_size(2, 3, 4, J_AXIS) == (2, 4))
    assert_true(slice_size(2, 3, 4, I_AXIS) == (3, 4))
    with assert_raises(contains="slice axis"):
        _ = slice_size(2, 3, 4, SliceAxis(3))


def _coded() raises -> ImageVolume:
    """A 2 by 3 by 4 volume whose value is 100 i + 10 j + k."""
    var volume = _volume(2, 3, 4)
    for k in range(4):
        for j in range(3):
            for i in range(2):
                volume.set(i, j, k, Float32(100 * i + 10 * j + k))
    volume.window_center = 127.5
    volume.window_width = 255
    return volume^


def test_render_slice_on_each_axis() raises:
    var volume = _coded()
    var axial = render_slice(volume, K_AXIS, 2)
    assert_equal(axial.width, 2)
    assert_equal(axial.height, 3)
    assert_equal(Int(axial.get_pixel(1, 2).r), 122)
    var coronal = render_slice(volume, J_AXIS, 1)
    assert_equal(coronal.height, 4)
    assert_equal(Int(coronal.get_pixel(1, 3).g), 113)
    var sagittal = render_slice(volume, I_AXIS, 1)
    assert_equal(sagittal.width, 3)
    assert_equal(Int(sagittal.get_pixel(2, 3).b), 123)
    volume.photometric = MONOCHROME1
    var inverted = render_slice(volume, K_AXIS, 2)
    assert_equal(Int(inverted.get_pixel(1, 2).r), 255 - 122)
    with assert_raises(contains="slice index"):
        _ = render_slice(volume, K_AXIS, 4)
    with assert_raises(contains="slice index"):
        _ = render_slice(volume, I_AXIS, -1)
    with assert_raises(contains="slice axis"):
        _ = render_slice(volume, SliceAxis(-1), 0)
    volume.window_width = 0
    with assert_raises(contains="width must be positive"):
        _ = render_slice(volume, J_AXIS, 0)


def test_label_colors() raises:
    assert_equal(label_color(BACKGROUND).a, 0)
    var red = label_color(LabelId(1))
    assert_equal(red.a, 1)
    assert_true(label_color(LabelId(9)) == red)
    with assert_raises(contains="from 0 to 255"):
        _ = label_color(LabelId(256))


def test_overlay_labels() raises:
    var volume = _coded()
    var map = LabelMap(volume)
    map.set(0, 0, 2, LabelId(1))
    var image = render_slice(volume, K_AXIS, 2)
    var before = image.get_pixel(1, 1)
    overlay_labels(image, map, K_AXIS, 2, 1)
    var labeled = image.get_pixel(0, 0)
    assert_equal(Int(labeled.r), 230)
    assert_equal(Int(labeled.g), 26)
    assert_true(image.get_pixel(1, 1) == before)
    var half = render_slice(volume, K_AXIS, 2)
    overlay_labels(half, map, K_AXIS, 2, 0)
    assert_equal(Int(half.get_pixel(0, 0).r), 2)
    with assert_raises(contains="opacity"):
        overlay_labels(image, map, K_AXIS, 2, -0.5)
    with assert_raises(contains="opacity"):
        overlay_labels(image, map, K_AXIS, 2, 1.5)
    var wide = Framebuffer(3, 3, List[UInt8](length=36, fill=0))
    with assert_raises(contains="size of the slice"):
        overlay_labels(wide, map, K_AXIS, 2, 1)
    var tall = Framebuffer(2, 4, List[UInt8](length=32, fill=0))
    with assert_raises(contains="size of the slice"):
        overlay_labels(tall, map, K_AXIS, 2, 1)
    with assert_raises(contains="slice index"):
        overlay_labels(image, map, K_AXIS, 9, 1)


def _blank(size: Int) raises -> Framebuffer:
    return Framebuffer(size, size, List[UInt8](length=size * size * 4, fill=0))


def _lit(image: Framebuffer, x: Int, y: Int) raises -> Bool:
    return image.get_pixel(x, y).r > 0


def test_measurement_lines() raises:
    var yellow = Rgba(1, 1, 0, 1)
    var image = _blank(9)
    draw_measurement(image, K_AXIS, v3(1, 1, 0), v3(7, 4, 0), yellow)
    assert_true(_lit(image, 1, 1))
    assert_true(_lit(image, 7, 4))
    assert_true(_lit(image, 4, 2) or _lit(image, 4, 3))
    # Crosses at the ends.
    assert_true(_lit(image, 0, 1))
    assert_true(_lit(image, 8, 4))
    # A steep line drawn backward, on the coronal axis.
    var steep = _blank(9)
    draw_measurement(steep, J_AXIS, v3(5, 0, 8), v3(4, 0, 1), yellow)
    assert_true(_lit(steep, 5, 8))
    assert_true(_lit(steep, 4, 1))
    # A line off every edge draws only what is inside.
    var clipped = _blank(4)
    draw_measurement(clipped, I_AXIS, v3(0, -2, -2), v3(0, 6, 6), yellow)
    assert_true(_lit(clipped, 2, 2))
    var upright = _blank(4)
    draw_measurement(upright, K_AXIS, v3(2, -2, 0), v3(2, 6, 0), yellow)
    assert_true(_lit(upright, 2, 0))
    assert_true(_lit(upright, 2, 3))
    with assert_raises(contains="finite points"):
        draw_measurement(
            clipped, K_AXIS, v3(nan[DType.float64](), 0, 0), v3(1, 1, 0), yellow
        )
    with assert_raises(contains="finite points"):
        draw_measurement(clipped, K_AXIS, v3(0, 0, 0), v3(1, 1e12, 0), yellow)
    with assert_raises(contains="slice axis"):
        draw_measurement(
            clipped, SliceAxis(4), v3(0, 0, 0), v3(1, 1, 0), yellow
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
