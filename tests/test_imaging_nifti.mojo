# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""NIfTI-1 volumes and label maps, read against nibabel's own files."""

from extensions.imaging.ids import LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap, threshold
from extensions.imaging.nifti import (
    encode_nifti,
    encode_nifti_labels,
    labels_from_volume,
    parse_nifti,
    read_nifti,
)
from extensions.sdf.vector import V3, v3
from std.math import nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER


def _mm(p: V3) -> V3:
    return p * 1000.0


def _near(a: V3, b: V3, tolerance: Float64) raises:
    assert_almost_equal(a.x, b.x, atol=tolerance)
    assert_almost_equal(a.y, b.y, atol=tolerance)
    assert_almost_equal(a.z, b.z, atol=tolerance)


# nibabel 5.3.2 reports these RAS points, in each file's unit, and values
# for voxel (1, 2, 1). See assets/nifti/expected.txt.


def test_little_endian_sform() raises:
    var volume = read_nifti("assets/nifti/le_sform.nii")
    assert_equal(volume.nx, 4)
    assert_equal(volume.ny, 3)
    assert_equal(volume.nz, 2)
    _near(_mm(volume.patient_point(1, 2, 1)), v3(-4.0, 18.0, 34.0), 1e-9)
    assert_almost_equal(volume.get(1, 2, 1), 50.5)
    assert_almost_equal(volume.spacing_y.to(MILLIMETER64), 3.0, atol=1e-12)
    _near(volume.axis_x, v3(0, -1, 0), 1e-12)
    assert_equal(volume.window_center, 50)
    assert_equal(volume.window_width, 100)


def test_big_endian_qform_with_a_flip() raises:
    var volume = read_nifti("assets/nifti/be_qform.nii")
    _near(
        _mm(volume.patient_point(1, 2, 1)),
        v3(6.200961878900882, -11.080127022568123, 6.5),
        1e-5,
    )
    assert_equal(volume.get(1, 2, 1), 121)
    assert_almost_equal(volume.spacing_z.to(MILLIMETER64), 0.5, atol=1e-12)


def test_voxel_sizes_alone_in_microns() raises:
    var volume = read_nifti("assets/nifti/pixdim_micron.nii")
    _near(_mm(volume.patient_point(1, 2, 1)), v3(-0.5, -0.5, 1.0), 1e-12)
    assert_equal(volume.get(1, 2, 1), 61)
    assert_equal(volume.get(0, 0, 0), -60)
    assert_almost_equal(volume.spacing_y.to(MILLIMETER64), 0.25, atol=1e-12)


def test_gzip_labels() raises:
    var volume = read_nifti("assets/nifti/labels.nii.gz")
    var labels = labels_from_volume(volume)
    assert_true(labels.get(1, 2, 1) == LabelId(2))
    assert_equal(labels.voxels(LabelId(6)), 3)


def _turned() raises -> ImageVolume:
    var spacing = Length64(2.5, MILLIMETER64)
    var volume = ImageVolume(3, 2, 2, spacing, spacing.scaled(2), spacing)
    for index in range(volume.count()):
        volume.values[index] = Float32(index) * 0.75 - 3
    volume.axis_x = v3(0, 1, 0)
    volume.axis_y = v3(-1, 0, 0)
    volume.origin = v3(0.01, -0.02, 0.03)
    volume.window_center = 2
    volume.window_width = 8
    return volume^


def test_round_trips() raises:
    var volume = _turned()
    for compress in [False, True]:
        var back = parse_nifti(encode_nifti(volume, compress))
        for index in range(volume.count()):
            assert_equal(back.values[index], volume.values[index])
        _near(back.patient_point(2, 1, 1), volume.patient_point(2, 1, 1), 1e-9)
        assert_almost_equal(back.window_center, 2, atol=1e-6)
        assert_almost_equal(back.window_width, 8, atol=1e-6)
    var map = threshold(volume, 0, 100, LabelId(9))
    for compress in [False, True]:
        var labels = labels_from_volume(
            parse_nifti(encode_nifti_labels(map, volume, compress))
        )
        assert_equal(labels.voxels(LabelId(9)), map.voxels(LabelId(9)))


def _patch16(mut bytes: List[UInt8], at: Int, value: Int):
    bytes[at] = UInt8(value & 0xFF)
    bytes[at + 1] = UInt8((value >> 8) & 0xFF)


def _patch32(mut bytes: List[UInt8], at: Int, value: Int):
    _patch16(bytes, at, value & 0xFFFF)
    _patch16(bytes, at + 2, (value >> 16) & 0xFFFF)


def _patch_float(mut bytes: List[UInt8], at: Int, value: Float64):
    _patch32(bytes, at, Int(bitcast[DType.uint32](Float32(value))))


def _plain(nx: Int) raises -> List[UInt8]:
    """A file of nx by 1 by 1 voxels of 1 mm, valued 0, 1, 2, ..."""
    var spacing = Length64(1, MILLIMETER64)
    var volume = ImageVolume(nx, 1, 1, spacing, spacing, spacing)
    for index in range(nx):
        volume.values[index] = Float32(index)
    return encode_nifti(volume, False)


def _typed(datatype: Int, data: List[UInt8]) raises -> List[UInt8]:
    var bytes = _plain(2)
    _patch16(bytes, 70, datatype)
    var out = List[UInt8]()
    for index in range(352):
        out.append(bytes[index])
    out.extend(data.copy())
    return out^


def test_every_datatype() raises:
    var unsigned8 = parse_nifti(_typed(2, [200, 7]))
    assert_equal(unsigned8.values[0], 200)
    var signed8 = parse_nifti(_typed(256, [200, 7]))
    assert_equal(signed8.values[0], -56)
    var unsigned16 = parse_nifti(_typed(512, [0xFF, 0xFF, 1, 0]))
    assert_equal(unsigned16.values[0], 65535)
    var signed16 = parse_nifti(_typed(4, [0xFF, 0xFF, 1, 0]))
    assert_equal(signed16.values[0], -1)
    var bytes32: List[UInt8] = [0xFE, 0xFF, 0xFF, 0xFF, 5, 0, 0, 0]
    assert_equal(parse_nifti(_typed(768, bytes32)).values[0], 4294967294)
    assert_equal(parse_nifti(_typed(8, bytes32)).values[0], -2)
    var double: List[UInt8] = [0, 0, 0, 0, 0, 0, 0xF8, 0x3F]
    double.extend(double.copy())
    assert_equal(parse_nifti(_typed(64, double)).values[1], 1.5)
    with assert_raises(contains="datatype 128 is not supported"):
        _ = parse_nifti(_typed(128, [1, 2, 3, 4, 5, 6]))


def test_scaling_units_and_dimensions() raises:
    var bytes = _plain(2)
    _patch_float(bytes, 112, 2)
    _patch_float(bytes, 116, 3)
    assert_equal(parse_nifti(bytes).values[1], 5)
    # A slope of zero, a slope that is not finite, or an intercept that is
    # not finite means no scaling.
    _patch_float(bytes, 112, 0)
    assert_equal(parse_nifti(bytes).values[1], 1)
    _patch_float(bytes, 112, nan[DType.float64]())
    assert_equal(parse_nifti(bytes).values[1], 1)
    _patch_float(bytes, 112, 2)
    _patch_float(bytes, 116, nan[DType.float64]())
    assert_equal(parse_nifti(bytes).values[1], 1)
    # Units: unknown is millimeters; meters; microns.
    var units = _plain(1)
    _patch16(units, 254, 0)
    units[123] = 0
    assert_almost_equal(parse_nifti(units).spacing_x.to(MILLIMETER64), 1)
    units[123] = 1
    assert_almost_equal(parse_nifti(units).spacing_x.to(METER), 1)
    units[123] = 3
    assert_almost_equal(parse_nifti(units).spacing_x.to(MILLIMETER64), 0.001)
    units[123] = 4
    with assert_raises(contains="spatial unit"):
        _ = parse_nifti(units)
    # A two-dimensional file has one slice.
    var flat = _plain(2)
    _patch16(flat, 40, 2)
    assert_equal(parse_nifti(flat).nz, 1)
    # No display range: the window fits the values.
    var plain = _plain(3)
    _patch_float(plain, 124, 0)
    _patch_float(plain, 128, 0)
    var fitted = parse_nifti(plain)
    assert_equal(fitted.window_center, 1)
    assert_equal(fitted.window_width, 2)


def test_qform_without_a_flip() raises:
    var bytes = _plain(2)
    _patch16(bytes, 254, 0)
    _patch16(bytes, 252, 1)
    # A quarter turn about z: b = c = 0, d = sin(45 degrees).
    _patch_float(bytes, 264, 0.7071067811865476)
    _patch_float(bytes, 268, 1)
    var volume = parse_nifti(bytes)
    # RAS +y becomes LPS -y.
    _near(volume.axis_x, v3(0, -1, 0), 1e-6)
    _near(_mm(volume.origin), v3(-1, 0, 0), 1e-9)


def test_refusals() raises:
    var good = _plain(2)
    var short = List[UInt8]()
    for index in range(300):
        short.append(good[index])
    with assert_raises(contains="header of 348 bytes"):
        _ = parse_nifti(short)
    var bad = good.copy()
    _patch32(bad, 0, 123)
    with assert_raises(contains="not NIfTI-1"):
        _ = parse_nifti(bad)
    _patch32(bad, 0, 540)
    with assert_raises(contains="NIfTI-2"):
        _ = parse_nifti(bad)
    var pair = good.copy()
    pair[345] = 105
    with assert_raises(contains="header and image pair"):
        _ = parse_nifti(pair)
    pair[345] = 120
    with assert_raises(contains="magic n+1"):
        _ = parse_nifti(pair)
    var dims = good.copy()
    _patch16(dims, 40, 0)
    with assert_raises(contains="from 1 to 7 dimensions"):
        _ = parse_nifti(dims)
    _patch16(dims, 40, 8)
    with assert_raises(contains="from 1 to 7 dimensions"):
        _ = parse_nifti(dims)
    _patch16(dims, 40, 0xFFFF)
    with assert_raises(contains="from 1 to 7 dimensions"):
        _ = parse_nifti(dims)
    with assert_raises(contains="header of 348 bytes"):
        _ = parse_nifti([31])
    var sheared = good.copy()
    _patch_float(sheared, 284, 1)
    with assert_raises(contains="not square"):
        _ = parse_nifti(sheared)
    var early = good.copy()
    _patch_float(early, 108, 100)
    with assert_raises(contains="shorter than its data"):
        _ = parse_nifti(early)
    var cut = List[UInt8]()
    for index in range(355):
        cut.append(good[index])
    with assert_raises(contains="shorter than its data"):
        _ = parse_nifti(cut)
    with assert_raises(contains="gzip"):
        _ = parse_nifti([31, 139, 0, 0])


def test_label_and_grid_refusals() raises:
    var spacing = Length64(1, MILLIMETER64)
    var volume = ImageVolume(2, 1, 1, spacing, spacing, spacing)
    volume.values[1] = 1.5
    with assert_raises(contains="whole number"):
        _ = labels_from_volume(volume)
    volume.values[1] = 300
    with assert_raises(contains="from 0 to 255"):
        _ = labels_from_volume(volume)
    var wide = ImageVolume(32768, 1, 1, spacing, spacing, spacing)
    with assert_raises(contains="32767 voxels"):
        _ = encode_nifti(wide, False)
    with assert_raises(contains="32767 voxels"):
        _ = encode_nifti_labels(LabelMap(wide), wide, False)
    with assert_raises(contains="different grids"):
        _ = encode_nifti_labels(LabelMap(wide), volume, False)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
