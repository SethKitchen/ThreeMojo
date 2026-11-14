# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Multi-frame DICOM files with functional groups.

`assets/dicom/enhanced.dcm` and `enhanced_rle.dcm` come from pydicom. See
`assets/dicom/make_dicom.py` and `assets/dicom/expected.txt`.
"""

from extensions.imaging.dicom import (
    DicomSlice,
    parse_dicom,
    parse_dicom_frames,
    read_dicom_frames,
)
from extensions.imaging.dicom_write import (
    DicomWriter,
    encode_dicom_frames,
    encode_rle_frame,
)
from extensions.imaging.ids import (
    DEFLATED_EXPLICIT,
    EXPLICIT_LITTLE,
    IMPLICIT_LITTLE,
    MONOCHROME1,
    PixelRepresentation,
    RLE_LOSSLESS,
    SIGNED_PIXELS,
    TransferSyntax,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.series import stack_slices, volume_slices
from extensions.sdf.vector import v3
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length64


def _expected(name: String) raises -> List[Float32]:
    var text = open("assets/dicom/expected.txt", "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        if parts[0] != name:
            continue
        var values = List[Float32]()
        for index in range(2, len(parts)):
            values.append(Float32(atol(parts[index])))
        return values^
    raise Error("no expected values for " + name)


def _check_enhanced(name: String, syntax: TransferSyntax) raises:
    var frames = read_dicom_frames("assets/dicom/" + name)
    assert_equal(len(frames), 3)
    var stored = _expected(name)
    for f in range(3):
        ref frame = frames[f]
        assert_true(frame.syntax == syntax)
        assert_equal(frame.rows, 4)
        assert_equal(frame.columns, 5)
        # The shared groups give the rescale, the spacing and the
        # orientation. Each frame's own groups give its position and window.
        assert_equal(frame.slope, 2)
        assert_equal(frame.intercept, -1024)
        assert_almost_equal(frame.row_spacing.to(MILLIMETER64), 0.5)
        assert_almost_equal(frame.column_spacing.to(MILLIMETER64), 0.75)
        assert_almost_equal(frame.thickness.to(MILLIMETER64), 2.5)
        assert_true(frame.has_orientation)
        assert_almost_equal(frame.position.z, 0.005 + 0.0025 * Float64(f))
        assert_almost_equal(frame.position.x, -0.01)
        assert_true(frame.has_window)
        assert_equal(frame.window_width, 400 + 100 * Float64(f))
        for index in range(20):
            assert_equal(frame.values[index], 2 * stored[20 * f + index] - 1024)
    var volume = stack_slices(frames)
    assert_equal(volume.nz, 3)
    assert_almost_equal(volume.spacing_z.to(MILLIMETER64), 2.5)


def test_reads_pydicom_enhanced_files() raises:
    _check_enhanced("enhanced.dcm", EXPLICIT_LITTLE)
    _check_enhanced("enhanced_rle.dcm", RLE_LOSSLESS)
    with assert_raises(contains="one frame"):
        _ = parse_dicom(Path("assets/dicom/enhanced.dcm").read_bytes())


def _volume() raises -> ImageVolume:
    var volume = ImageVolume(
        6,
        5,
        4,
        Length64(0.5, MILLIMETER64),
        Length64(0.75, MILLIMETER64),
        Length64(2.0, MILLIMETER64),
    )
    for index in range(volume.count()):
        volume.values[index] = Float32((index * 53) % 400 - 100)
    volume.origin = v3(0.01, -0.02, 0.03)
    volume.window_center = 50
    volume.window_width = 300
    return volume^


def _round_trip(syntax: TransferSyntax) raises:
    var volume = _volume()
    var frames = volume_slices(volume, 1.0, -1024.0)
    for index in range(len(frames)):
        frames[index].syntax = syntax
    var back = parse_dicom_frames(encode_dicom_frames(frames))
    assert_equal(len(back), 4)
    for f in range(4):
        assert_true(back[f].syntax == syntax)
        assert_almost_equal(
            back[f].position.z, frames[f].position.z, atol=1e-12
        )
        assert_equal(back[f].window_width, 300)
        assert_equal(back[f].intercept, -1024)
        for index in range(30):
            assert_equal(back[f].values[index], frames[f].values[index])
    var again = stack_slices(back)
    for index in range(volume.count()):
        assert_equal(again.values[index], volume.values[index])
    assert_almost_equal(again.spacing_z.to(MILLIMETER64), 2.0)


def test_round_trips() raises:
    _round_trip(EXPLICIT_LITTLE)
    _round_trip(IMPLICIT_LITTLE)
    _round_trip(RLE_LOSSLESS)
    _round_trip(DEFLATED_EXPLICIT)


def test_a_frame_without_placement() raises:
    # A frame with no position, orientation, spacing or window, in 8 bits.
    var image = DicomSlice(2, 3)
    image.bits_allocated = 8
    image.bits_stored = 8
    image.representation = PixelRepresentation(0)
    image.photometric = MONOCHROME1
    for index in range(6):
        image.values[index] = Float32(index * 40)
    var back = parse_dicom_frames(encode_dicom_frames([image.copy()]))
    assert_equal(len(back), 1)
    assert_false(back[0].has_position)
    assert_false(back[0].has_window)
    assert_true(back[0].photometric == MONOCHROME1)
    assert_equal(back[0].values[5], 200)


def test_frames_must_match() raises:
    with assert_raises(contains="needs a frame"):
        _ = encode_dicom_frames(List[DicomSlice]())
    var first = DicomSlice(2, 2)
    for change in range(7):
        var other = DicomSlice(2, 2)
        if change == 0:
            other = DicomSlice(3, 2)
        elif change == 1:
            other = DicomSlice(2, 3)
        elif change == 2:
            other.bits_allocated = 8
            other.bits_stored = 8
        elif change == 3:
            other.bits_stored = 12
        elif change == 4:
            other.representation = PixelRepresentation(0)
        elif change == 5:
            other.photometric = MONOCHROME1
        else:
            other.syntax = IMPLICIT_LITTLE
        with assert_raises(contains="share their layout"):
            _ = encode_dicom_frames([first.copy(), other^])
    var bad = DicomSlice(2, 2)
    bad.slope = 0
    with assert_raises(contains="slope cannot be zero"):
        _ = encode_dicom_frames([bad^])


def _layout(mut writer: DicomWriter, frames: String):
    writer.short(0x0028, 0x0002, 1)
    writer.text(0x0028, 0x0008, "IS", frames)
    writer.short(0x0028, 0x0010, 1)
    writer.short(0x0028, 0x0011, 1)
    writer.short(0x0028, 0x0100, 8)
    writer.short(0x0028, 0x0103, 0)


def test_frame_refusals() raises:
    # Two frames, but one RLE fragment.
    var writer = DicomWriter(RLE_LOSSLESS)
    _layout(writer, "2")
    writer.encapsulated(encode_rle_frame([7], 1, 1))
    with assert_raises(contains="one fragment per frame"):
        _ = parse_dicom_frames(writer^.finish())
    # Three native frames of one byte, but two bytes of pixels.
    writer = DicomWriter(EXPLICIT_LITTLE)
    _layout(writer, "3")
    writer.binary(0x7FE0, 0x0010, "OB", [7, 0])
    with assert_raises(contains="shorter than the image"):
        _ = parse_dicom_frames(writer^.finish())
    writer = DicomWriter(EXPLICIT_LITTLE)
    _layout(writer, "0")
    writer.binary(0x7FE0, 0x0010, "OB", [7, 0])
    with assert_raises(contains="from 1 to 65535 frames"):
        _ = parse_dicom_frames(writer^.finish())
    writer = DicomWriter(EXPLICIT_LITTLE)
    _layout(writer, "70000")
    writer.binary(0x7FE0, 0x0010, "OB", [7, 0])
    with assert_raises(contains="from 1 to 65535 frames"):
        _ = parse_dicom_frames(writer^.finish())
    # A functional group sequence that holds a bare element, and one that
    # holds an item delimiter where an item belongs.
    writer = DicomWriter(EXPLICIT_LITTLE)
    writer.open_sequence(0x5200, 0x9230)
    writer.short(0x0028, 0x0010, 1)
    with assert_raises(contains="not an item"):
        _ = parse_dicom_frames(writer^.finish())
    writer = DicomWriter(EXPLICIT_LITTLE)
    writer.open_sequence(0x5200, 0x9230)
    writer.close_item()
    with assert_raises(contains="unknown delimiter"):
        _ = parse_dicom_frames(writer^.finish())


def test_functional_group_shapes() raises:
    var writer = DicomWriter(EXPLICIT_LITTLE)
    # Of two elements with one tag, the first wins.
    writer.text(0x0008, 0x0060, "CS", "MR")
    writer.text(0x0008, 0x0060, "CS", "CT")
    _layout(writer, "1")
    # Shared groups: two items with a pixel spacing each, and an empty item.
    writer.open_sequence(0x5200, 0x9229)
    for spacing in [0.5, 0.9]:
        writer.open_item()
        writer.open_sequence(0x0028, 0x9110)
        writer.open_item()
        writer.numbers(0x0028, 0x0030, [spacing, spacing])
        writer.close_item()
        writer.close_sequence()
        writer.close_item()
    writer.open_item()
    writer.close_item()
    writer.close_sequence()
    writer.open_sequence(0x5200, 0x9230)
    writer.open_item()
    # A sequence the reader does not open, an empty group and an empty item.
    writer.open_sequence(0x0008, 0x9124)
    writer.open_item()
    writer.text(0x0008, 0x0100, "SH", "X")
    writer.close_item()
    writer.close_sequence()
    writer.open_sequence(0x0020, 0x9113)
    writer.close_sequence()
    writer.open_sequence(0x0020, 0x9116)
    writer.open_item()
    writer.close_item()
    writer.close_sequence()
    # A window in its group, then a second window center outside it.
    writer.open_sequence(0x0028, 0x9132)
    writer.open_item()
    writer.numbers(0x0028, 0x1050, [40.0])
    writer.numbers(0x0028, 0x1051, [400.0])
    writer.close_item()
    writer.close_sequence()
    writer.numbers(0x0028, 0x1050, [99.0])
    # A group of two items: the first slope wins.
    writer.open_sequence(0x0028, 0x9145)
    for slope in [2.0, 3.0]:
        writer.open_item()
        writer.numbers(0x0028, 0x1053, [slope])
        writer.close_item()
    writer.close_sequence()
    writer.close_item()
    writer.close_sequence()
    writer.binary(0x7FE0, 0x0010, "OB", [5, 0])
    var frame = parse_dicom_frames(writer^.finish())[0].copy()
    assert_equal(frame.modality, "MR")
    assert_almost_equal(frame.row_spacing.to(MILLIMETER64), 0.5)
    assert_equal(frame.window_center, 40)
    assert_equal(frame.slope, 2)
    assert_equal(frame.values[0], 10)
    assert_false(frame.has_position)


def test_stray_delimiter_and_empty_fragments() raises:
    var writer = DicomWriter(EXPLICIT_LITTLE)
    writer.open_sequence(0x5200, 0x9230)
    writer.open_item()
    writer.close_sequence()
    with assert_raises(contains="stray delimiter"):
        _ = parse_dicom_frames(writer^.finish())
    # An empty shared group sequence changes nothing.
    writer = DicomWriter(EXPLICIT_LITTLE)
    _layout(writer, "1")
    writer.open_sequence(0x5200, 0x9229)
    writer.close_sequence()
    writer.binary(0x7FE0, 0x0010, "OB", [4, 0])
    assert_equal(parse_dicom_frames(writer^.finish())[0].values[0], 4)
    writer = DicomWriter(RLE_LOSSLESS)
    _layout(writer, "1")
    writer.encapsulated_frames(List[List[UInt8]]())
    with assert_raises(contains="64-byte header"):
        _ = parse_dicom_frames(writer^.finish())


def test_an_odd_frame_is_padded() raises:
    var image = DicomSlice(1, 3)
    image.bits_allocated = 8
    image.bits_stored = 8
    image.representation = PixelRepresentation(0)
    image.modality = "MR"
    image.values[2] = 9
    var bytes = encode_dicom_frames([image.copy()])
    assert_equal(len(bytes) % 2, 0)
    var back = parse_dicom_frames(bytes)
    assert_equal(back[0].values[2], 9)
    assert_equal(back[0].modality, "MR")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
