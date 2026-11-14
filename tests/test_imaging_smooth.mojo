# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Welding, Taubin smoothing, areas and volumes of label surfaces."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from extensions.imaging.ids import LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap, label_surface
from extensions.imaging.smooth import (
    enclosed_volume,
    smooth_surface,
    surface_area,
    weld_surface,
)
from geometries.box import box
from std.math import pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import CUBIC_METER, Length, Length64, METER, SQUARE_METER


comptime RADIUS = 5.0
comptime CENTER = 7.5


def _sphere() raises -> BufferGeometry:
    """The label surface of a ball of radius 5 voxels, 1 mm voxels."""
    var volume = ImageVolume(
        16,
        16,
        16,
        Length64(1.0, MILLIMETER64),
        Length64(1.0, MILLIMETER64),
        Length64(1.0, MILLIMETER64),
    )
    var map = LabelMap(volume)
    for k in range(16):
        for j in range(16):
            for i in range(16):
                var dx = Float64(i) - CENTER
                var dy = Float64(j) - CENTER
                var dz = Float64(k) - CENTER
                if dx * dx + dy * dy + dz * dz <= RADIUS * RADIUS:
                    map.set(i, j, k, LabelId(1))
    return label_surface(map, LabelId(1))


def _radial(mesh: BufferGeometry) raises -> Tuple[Float64, Float64]:
    """The mean radius and the RMS deviation from it, in voxels."""
    ref points = mesh.attribute_view(POSITION)
    var total = 0.0
    var count = points.count()
    var radii = List[Float64]()
    for vertex in range(count):
        var p = points.vector3(vertex)
        var dx = Float64(p.x) * 1000.0 - CENTER
        var dy = Float64(p.y) * 1000.0 - CENTER
        var dz = Float64(p.z) * 1000.0 - CENTER
        var r = sqrt(dx * dx + dy * dy + dz * dz)
        radii.append(r)
        total += r
    var mean = total / Float64(count)
    var square = 0.0
    for r in radii:
        square += (r - mean) * (r - mean)
    return (mean, sqrt(square / Float64(count)))


def test_weld_closes_the_label_surface() raises:
    var raw = _sphere()
    var welded = weld_surface(raw)
    assert_equal(welded.triangle_count(), raw.triangle_count())
    assert_true(welded.vertex_count() < raw.vertex_count())
    # A closed surface of genus zero: V - E + F = 2, with E = 3F / 2.
    var faces = welded.triangle_count()
    assert_equal(welded.vertex_count() - faces * 3 // 2 + faces, 2)
    # Welding moves no point.
    assert_almost_equal(
        surface_area(welded).to(SQUARE_METER),
        surface_area(raw).to(SQUARE_METER),
        atol=1e-12,
    )
    assert_almost_equal(
        enclosed_volume(welded).to(CUBIC_METER),
        enclosed_volume(raw).to(CUBIC_METER),
        atol=1e-15,
    )
    # The faces turn outward.
    assert_true(enclosed_volume(raw).to(CUBIC_METER) > 0)
    assert_true(welded.has_attribute(NORMAL))
    assert_true(welded.has_attribute(UV))


def test_taubin_rounds_and_keeps_volume() raises:
    var raw = _sphere()
    var before = _radial(weld_surface(raw))
    var smooth = smooth_surface(raw, 20)
    var after = _radial(smooth)
    # The steps of the voxels go: the spread of the radius falls by more
    # than a third, and the mean radius stays within 1 percent.
    assert_true(after[1] < 0.65 * before[1])
    assert_almost_equal(after[0], before[0], rtol=0.01)
    # The area falls toward the area of a smooth ball, and the volume
    # stays within 2 percent.
    var raw_area = surface_area(raw).to(SQUARE_METER)
    assert_true(surface_area(smooth).to(SQUARE_METER) < 0.9 * raw_area)
    assert_almost_equal(
        enclosed_volume(smooth).to(CUBIC_METER),
        enclosed_volume(raw).to(CUBIC_METER),
        rtol=0.02,
    )
    # Zero passes only weld.
    assert_equal(smooth_surface(raw, 0).vertex_count(), smooth.vertex_count())


def test_box_measures() raises:
    var cube = box(Length(2, METER), Length(2, METER), Length(2, METER))
    var welded = weld_surface(cube)
    assert_equal(welded.vertex_count(), 8)
    assert_equal(welded.triangle_count(), 12)
    assert_almost_equal(surface_area(cube).to(SQUARE_METER), 24.0)
    assert_almost_equal(enclosed_volume(cube).to(CUBIC_METER), 8.0)
    var split = box(
        Length(2, METER), Length(2, METER), Length(2, METER), 2, 2, 2
    )
    # Three by three by three points, less the one in the middle.
    assert_equal(weld_surface(split).vertex_count(), 26)


def _triangles(
    positions: List[Float32], index: List[Int]
) raises -> BufferGeometry:
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(positions.copy(), 3))
    geometry.set_index(index.copy())
    return geometry^


def test_degenerate_triangles_drop() raises:
    var positions: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    # One triangle with area, and three with two corners at one place.
    var mesh = _triangles(positions, [0, 1, 2, 0, 0, 1, 0, 1, 1, 1, 0, 1])
    var welded = weld_surface(mesh)
    assert_equal(welded.triangle_count(), 1)
    assert_equal(welded.vertex_count(), 3)
    # No texture coordinates give zeros, and the normal is +z.
    ref uv = welded.attribute_view(UV)
    assert_equal(uv.component(2, 1), 0)
    ref normal = welded.attribute_view(NORMAL)
    assert_almost_equal(normal.component(0, 2), 1.0)
    with assert_raises(contains="one triangle with area"):
        _ = weld_surface(_triangles(positions, [0, 0, 1]))
    with assert_raises(contains="one triangle with area"):
        _ = smooth_surface(_triangles(positions, [2, 1, 2]), 1)


def test_a_mesh_without_triangles() raises:
    var geometry = BufferGeometry()
    var two: List[Float32] = [0, 0, 0, 1, 0, 0]
    geometry.set_attribute(POSITION, BufferAttribute(two^, 3))
    assert_equal(surface_area(geometry).to(SQUARE_METER), 0)
    assert_equal(enclosed_volume(geometry).to(CUBIC_METER), 0)
    with assert_raises(contains="one triangle with area"):
        _ = weld_surface(geometry)
    with assert_raises(contains="no attribute named position"):
        _ = surface_area(BufferGeometry())


def test_smoothing_refusals() raises:
    var positions: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    var mesh = _triangles(positions, [0, 1, 2])
    with assert_raises(contains="cannot be negative"):
        _ = smooth_surface(mesh, -1)
    with assert_raises(contains="shrink factor"):
        _ = smooth_surface(mesh, 1, 0.0)
    with assert_raises(contains="shrink factor"):
        _ = smooth_surface(mesh, 1, 1.5)
    with assert_raises(contains="inflate factor"):
        _ = smooth_surface(mesh, 1, 0.5, -0.4)
    with assert_raises(contains="inflate factor"):
        _ = smooth_surface(mesh, 1, 0.5, -1.5)
    # A lone triangle shrinks toward its centroid and back.
    var moved = smooth_surface(mesh, 1, 0.9, -1.0)
    assert_equal(moved.vertex_count(), 3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
