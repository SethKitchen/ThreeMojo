# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Image volumes, slice stacks and the head phantom."""

from extensions.imaging.dicom import DicomSlice, parse_dicom
from extensions.imaging.dicom_write import encode_dicom
from extensions.imaging.ids import MONOCHROME1
from extensions.imaging.image_volume import (
    ImageVolume,
    MAX_VOXELS,
    MILLIMETER64,
    require_grid,
    require_spacing,
)
from extensions.imaging.phantom import (
    phantom_value,
    shepp_logan,
    shepp_logan_table,
)
from extensions.imaging.series import stack_slices, volume_slices
from extensions.sdf.vector import v3
from std.math import inf, nan
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


def _linear() raises -> ImageVolume:
    """A 3 by 4 by 5 volume whose value is i + 2j + 3k."""
    var volume = ImageVolume(3, 4, 5, _mm(1), _mm(2), _mm(3))
    for k in range(5):
        for j in range(4):
            for i in range(3):
                volume.set(i, j, k, Float32(i + 2 * j + 3 * k))
    return volume^


def test_grid_and_spacing_refusals() raises:
    require_grid(1, 1, 1)
    with assert_raises(contains="at least one voxel"):
        require_grid(0, 1, 1)
    with assert_raises(contains="at least one voxel"):
        require_grid(1, 0, 1)
    with assert_raises(contains="at least one voxel"):
        require_grid(1, 1, 0)
    with assert_raises(contains="2^28"):
        require_grid(MAX_VOXELS, 2, 1)
    require_spacing(_mm(0.5))
    with assert_raises(contains="spacing must be positive"):
        require_spacing(_mm(0))
    with assert_raises(contains="spacing must be positive"):
        require_spacing(Length64(inf[DType.float64](), METER))


def test_index_and_bounds() raises:
    var volume = _linear()
    assert_equal(volume.count(), 60)
    assert_equal(volume.index(1, 2, 3), 1 + 3 * (2 + 4 * 3))
    assert_equal(volume.get(2, 3, 4), 20)
    assert_true(volume.contains(0, 0, 0))
    assert_false(volume.contains(-1, 0, 0))
    assert_false(volume.contains(0, -1, 0))
    assert_false(volume.contains(0, 0, -1))
    assert_false(volume.contains(3, 0, 0))
    assert_false(volume.contains(0, 4, 0))
    assert_false(volume.contains(0, 0, 5))
    with assert_raises(contains="outside the volume"):
        _ = volume.get(3, 0, 0)
    with assert_raises(contains="outside the volume"):
        volume.set(0, 0, 5, 1)


def test_trilinear_is_exact_for_a_linear_field() raises:
    var volume = _linear()
    assert_almost_equal(volume.trilinear(1.5, 2.25, 3.5), 1.5 + 4.5 + 10.5)
    assert_almost_equal(volume.trilinear(0, 0, 0), 0)
    # Points past the centers take the nearest edge.
    assert_almost_equal(volume.trilinear(-4, -1, 9), 0 + 0 + 12)
    assert_almost_equal(volume.trilinear(2, 3, 4), 20)


def test_range_extent_and_placement() raises:
    var volume = _linear()
    var span = volume.value_range()
    assert_equal(span[0], 0)
    assert_equal(span[1], 20)
    var extent = volume.extent()
    assert_almost_equal(extent.x, 0.002)
    assert_almost_equal(extent.y, 0.006)
    assert_almost_equal(extent.z, 0.012)
    volume.origin = v3(1, 2, 3)
    volume.axis_x = v3(0, 1, 0)
    volume.axis_y = v3(-1, 0, 0)
    var p = volume.patient_point(1, 1, 1)
    assert_almost_equal(p.x, 1 - 0.002)
    assert_almost_equal(p.y, 2 + 0.001)
    assert_almost_equal(p.z, 3 + 0.003)
    volume.fit_window()
    assert_equal(volume.window_center, 10)
    assert_equal(volume.window_width, 20)
    var flat = ImageVolume(2, 2, 2, _mm(1), _mm(1), _mm(1))
    flat.fit_window()
    assert_equal(flat.window_center, 0)
    assert_equal(flat.window_width, 1)


def _series(count: Int) raises -> List[DicomSlice]:
    """Axial slices 2.5 mm apart, from z = -10 mm, each with a window."""
    var out = List[DicomSlice]()
    for n in range(count):
        var image = DicomSlice(2, 3)
        image.has_position = True
        image.has_orientation = True
        image.has_spacing = True
        image.row_spacing = _mm(0.8)
        image.column_spacing = _mm(0.6)
        image.position = v3(-0.01, -0.02, -0.01 + Float64(n) * 0.0025)
        image.window_center = Float64(40 + n)
        image.window_width = 400
        image.has_window = True
        for index in range(6):
            image.values[index] = Float32(n * 10 + index)
        out.append(image^)
    return out^


def test_stack_sorts_along_the_normal() raises:
    var slices = _series(3)
    # Shuffle: the stack must not depend on the order of the files.
    var shuffled = List[DicomSlice]()
    shuffled.append(slices[2].copy())
    shuffled.append(slices[0].copy())
    shuffled.append(slices[1].copy())
    var volume = stack_slices(shuffled)
    assert_equal(volume.nx, 3)
    assert_equal(volume.ny, 2)
    assert_equal(volume.nz, 3)
    assert_almost_equal(volume.spacing_x.to(MILLIMETER64), 0.6)
    assert_almost_equal(volume.spacing_y.to(MILLIMETER64), 0.8)
    assert_almost_equal(volume.spacing_z.to(MILLIMETER64), 2.5)
    assert_almost_equal(volume.origin.z, -0.01)
    assert_equal(volume.get(1, 1, 2), 24)
    assert_true(volume.axis_z == v3(0, 0, 1))
    # The window comes from the first sorted slice.
    assert_equal(volume.window_center, 40)


def test_stack_window_choices() raises:
    var slices = _series(2)
    slices[0].has_window = False
    var volume = stack_slices(slices)
    assert_equal(volume.window_center, 41)
    slices[1].has_window = False
    volume = stack_slices(slices)
    assert_equal(volume.window_center, 7.5)
    assert_equal(volume.window_width, 15)


def test_single_slice_spacing() raises:
    var slices = _series(1)
    var volume = stack_slices(slices)
    assert_almost_equal(volume.spacing_z.to(MILLIMETER64), 0.6)
    slices[0].thickness = _mm(5)
    slices[0].photometric = MONOCHROME1
    volume = stack_slices(slices)
    assert_almost_equal(volume.spacing_z.to(MILLIMETER64), 5)
    assert_true(volume.photometric == MONOCHROME1)


def test_stack_refusals() raises:
    with assert_raises(contains="at least one slice"):
        _ = stack_slices(List[DicomSlice]())
    var slices = _series(2)
    slices[1].has_position = False
    with assert_raises(contains="image position"):
        _ = stack_slices(slices)
    slices = _series(2)
    slices[1].has_orientation = False
    with assert_raises(contains="image orientation"):
        _ = stack_slices(slices)
    slices = _series(2)
    slices[1].has_spacing = False
    with assert_raises(contains="pixel spacing"):
        _ = stack_slices(slices)
    slices = _series(2)
    slices[1].rows = 3
    with assert_raises(contains="one size"):
        _ = stack_slices(slices)
    slices = _series(2)
    slices[1].columns = 4
    with assert_raises(contains="one size"):
        _ = stack_slices(slices)
    slices = _series(2)
    slices[1].row_spacing = _mm(0.9)
    with assert_raises(contains="one pixel spacing"):
        _ = stack_slices(slices)
    slices = _series(2)
    slices[1].column_spacing = _mm(0.7)
    with assert_raises(contains="one pixel spacing"):
        _ = stack_slices(slices)
    slices = _series(2)
    slices[1].row_direction = v3(0, 1, 0)
    slices[1].column_direction = v3(-1, 0, 0)
    with assert_raises(contains="one orientation"):
        _ = stack_slices(slices)
    slices = _series(2)
    slices[1].column_direction = v3(0, 0, 1)
    with assert_raises(contains="one orientation"):
        _ = stack_slices(slices)


def test_spacing_refusals() raises:
    var slices = _series(3)
    slices[2].position = slices[1].position
    with assert_raises(contains="share one position"):
        _ = stack_slices(slices)
    slices = _series(3)
    slices[2].position = v3(-0.01, -0.02, 0.0)
    with assert_raises(contains="not evenly spaced"):
        _ = stack_slices(slices)
    slices = _series(3)
    slices[1].position = v3(-0.009, -0.02, -0.0075)
    with assert_raises(contains="shifted sideways"):
        _ = stack_slices(slices)


def test_volume_slices_round_trip() raises:
    var volume = _linear()
    volume.origin = v3(0.1, -0.2, 0.05)
    var slices = volume_slices(volume, 0.5, -3)
    assert_equal(len(slices), 5)
    assert_equal(slices[4].instance_number, 5)
    var files = List[DicomSlice]()
    for slice in slices:
        files.append(parse_dicom(encode_dicom(slice)))
    var back = stack_slices(files)
    assert_equal(back.nx, 3)
    assert_equal(back.ny, 4)
    assert_equal(back.nz, 5)
    assert_almost_equal(back.spacing_z.to(MILLIMETER64), 3)
    assert_almost_equal(back.origin.x, 0.1)
    for index in range(volume.count()):
        assert_equal(back.values[index], volume.values[index])
    with assert_raises(contains="finite slope"):
        _ = volume_slices(volume, 0, 0)
    with assert_raises(contains="finite slope"):
        _ = volume_slices(volume, inf[DType.float64](), 0)
    with assert_raises(contains="finite slope"):
        _ = volume_slices(volume, 1, nan[DType.float64]())


def test_phantom_values() raises:
    assert_equal(len(shepp_logan_table()), 10)
    # The brain, a ventricle, the skull and the air outside.
    assert_almost_equal(phantom_value(0, 0, 0), 0.2)
    assert_almost_equal(phantom_value(0.22, 0, 0), 0.0, atol=1e-12)
    assert_almost_equal(phantom_value(0, 0.9, 0), 1.0)
    assert_equal(phantom_value(0.95, 0, 0), 0.0)
    var volume = shepp_logan(9, Length64(0.18, METER), 1)
    assert_almost_equal(volume.get(4, 4, 4), 0.2, atol=1e-6)
    assert_equal(volume.get(0, 0, 0), 0)
    assert_almost_equal(volume.spacing_x.to(METER), 0.02)
    assert_almost_equal(volume.origin.x, -0.08)
    assert_equal(volume.window_center, 0.25)


def test_phantom_partial_volume() raises:
    var sharp = shepp_logan(5, Length64(0.2, METER), 1)
    var smooth = shepp_logan(5, Length64(0.2, METER), 3)
    var between = 0
    for value in smooth.values:
        if value > 0.25 and value < 0.95:
            between += 1
    # Point samples take one side of each edge; the mean of 27 points
    # gives edge voxels a value between the sides.
    var sharp_between = 0
    for value in sharp.values:
        if value > 0.25 and value < 0.95:
            sharp_between += 1
    assert_true(between > sharp_between)
    with assert_raises(contains="from 1 to 4 samples"):
        _ = shepp_logan(4, Length64(0.2, METER), 0)
    with assert_raises(contains="from 1 to 4 samples"):
        _ = shepp_logan(4, Length64(0.2, METER), 5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
