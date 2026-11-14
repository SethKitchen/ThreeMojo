# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The DICOM reader and writer, and the imaging ids."""

from extensions.imaging.dicom import (
    DicomSlice,
    EXPLICIT_LITTLE_UID,
    parse_dicom,
    read_dicom,
)
from extensions.imaging.dicom_write import (
    DicomWriter,
    ds_text,
    encode_dicom,
    stored_value,
)
from extensions.imaging.ids import (
    BACKGROUND,
    COMPOSITE,
    EXPLICIT_LITTLE,
    I_AXIS,
    IMPLICIT_LITTLE,
    ISOSURFACE,
    K_AXIS,
    LabelId,
    MAXIMUM_INTENSITY,
    MONOCHROME1,
    MONOCHROME2,
    Photometric,
    PixelRepresentation,
    RenderMode,
    SIGNED_PIXELS,
    SliceAxis,
    TransferSyntax,
    UNSIGNED_PIXELS,
    require_axis,
    require_label,
    require_mode,
    require_photometric,
    require_representation,
    require_syntax,
)
from extensions.imaging.image_volume import MILLIMETER64
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
from tests.test_scratch import TestScratch, temporary_path
from units.si import Length64


def _sample() raises -> DicomSlice:
    """A two-row, three-column CT slice with every element set."""
    var image = DicomSlice(2, 3)
    image.modality = "MR"
    image.instance_number = 7
    image.slope = 0.5
    image.intercept = -1024.0
    image.row_spacing = Length64(0.75, MILLIMETER64)
    image.column_spacing = Length64(0.5, MILLIMETER64)
    image.thickness = Length64(2.5, MILLIMETER64)
    image.position = v3(-0.1, 0.02, 0.0375)
    image.row_direction = v3(0, 1, 0)
    image.column_direction = v3(0, 0, -1)
    image.has_position = True
    image.has_orientation = True
    image.has_spacing = True
    image.window_center = 40.0
    image.window_width = 400.0
    image.has_window = True
    image.photometric = MONOCHROME1
    var values: List[Float32] = [-1024, -1000.5, 0, 40, 1000, 2047.5]
    for index in range(6):
        image.values[index] = values[index]
    return image^


def _same_slice(a: DicomSlice, b: DicomSlice) raises:
    assert_equal(a.rows, b.rows)
    assert_equal(a.columns, b.columns)
    assert_equal(a.modality, b.modality)
    assert_equal(a.instance_number, b.instance_number)
    assert_equal(a.slope, b.slope)
    assert_equal(a.intercept, b.intercept)
    assert_almost_equal(
        a.row_spacing.to(MILLIMETER64), b.row_spacing.to(MILLIMETER64)
    )
    assert_almost_equal(
        a.column_spacing.to(MILLIMETER64), b.column_spacing.to(MILLIMETER64)
    )
    assert_almost_equal(
        a.thickness.to(MILLIMETER64), b.thickness.to(MILLIMETER64)
    )
    assert_almost_equal(a.position.x, b.position.x, atol=1e-12)
    assert_almost_equal(a.position.y, b.position.y, atol=1e-12)
    assert_almost_equal(a.position.z, b.position.z, atol=1e-12)
    assert_true(a.row_direction == b.row_direction)
    assert_true(a.column_direction == b.column_direction)
    assert_equal(a.has_window, b.has_window)
    assert_equal(a.window_center, b.window_center)
    assert_equal(a.window_width, b.window_width)
    assert_true(a.photometric == b.photometric)
    for index in range(len(a.values)):
        assert_equal(a.values[index], b.values[index])


def test_round_trip_explicit() raises:
    var image = _sample()
    var back = parse_dicom(encode_dicom(image))
    _same_slice(image, back)
    assert_true(back.syntax == EXPLICIT_LITTLE)
    assert_true(back.has_position and back.has_orientation)
    assert_true(back.has_spacing)
    assert_equal(back.bits_allocated, 16)
    assert_equal(back.bits_stored, 16)
    assert_true(back.representation == SIGNED_PIXELS)
    var normal = back.normal()
    assert_true(normal == v3(-1, 0, 0))


def test_round_trip_implicit_eight_bits() raises:
    var image = DicomSlice(1, 3)
    image.syntax = IMPLICIT_LITTLE
    image.bits_allocated = 8
    image.bits_stored = 8
    image.representation = UNSIGNED_PIXELS
    image.values[0] = 0
    image.values[1] = 128
    image.values[2] = 300
    var bytes = encode_dicom(image)
    # Three 8-bit values are padded to an even length.
    var back = parse_dicom(bytes)
    assert_true(back.syntax == IMPLICIT_LITTLE)
    assert_equal(back.modality, "CT")
    assert_equal(back.values[0], 0)
    assert_equal(back.values[1], 128)
    # A value past the stored range is held at its top.
    assert_equal(back.values[2], 255)
    assert_false(back.has_position)
    assert_false(back.has_orientation)
    assert_false(back.has_spacing)
    assert_false(back.has_window)
    assert_true(back.photometric == MONOCHROME2)


def _required(mut writer: DicomWriter, rows: Int, columns: Int):
    writer.short(0x0028, 0x0010, rows)
    writer.short(0x0028, 0x0011, columns)


def _pixels(values: List[Int]) -> List[UInt8]:
    var out = List[UInt8]()
    for value in values:
        out.append(UInt8(value & 0xFF))
        out.append(UInt8((value >> 8) & 0xFF))
    return out^


def test_stored_bits_are_masked_and_signed() raises:
    var writer = DicomWriter(EXPLICIT_LITTLE)
    _required(writer, 1, 3)
    writer.short(0x0028, 0x0100, 16)
    writer.short(0x0028, 0x0101, 12)
    writer.short(0x0028, 0x0103, 1)
    writer.binary(0x7FE0, 0x0010, "OW", _pixels([0xF800, 0x07FF, 0xFFFF]))
    var image = parse_dicom(writer^.finish())
    assert_equal(image.values[0], -2048)
    assert_equal(image.values[1], 2047)
    assert_equal(image.values[2], -1)
    writer = DicomWriter(EXPLICIT_LITTLE)
    _required(writer, 1, 1)
    writer.short(0x0028, 0x0100, 16)
    writer.short(0x0028, 0x0101, 12)
    writer.short(0x0028, 0x0103, 0)
    writer.binary(0x7FE0, 0x0010, "OW", _pixels([0xFFFF]))
    image = parse_dicom(writer^.finish())
    assert_equal(image.values[0], 4095)


def _minimal(syntax: TransferSyntax) raises -> DicomWriter:
    var writer = DicomWriter(syntax)
    _required(writer, 1, 1)
    writer.short(0x0028, 0x0100, 16)
    writer.short(0x0028, 0x0103, 0)
    return writer^


def test_defaults() raises:
    var writer = _minimal(EXPLICIT_LITTLE)
    writer.binary(0x7FE0, 0x0010, "OW", _pixels([5]))
    var image = parse_dicom(writer^.finish())
    assert_equal(image.values[0], 5)
    assert_equal(image.slope, 1.0)
    assert_equal(image.intercept, 0.0)
    assert_equal(image.bits_stored, 16)
    assert_equal(image.modality, "")
    assert_equal(image.instance_number, 0)
    assert_true(image.representation == UNSIGNED_PIXELS)
    assert_almost_equal(image.row_spacing.to(MILLIMETER64), 1.0)


def test_text_padding_and_spaces() raises:
    var writer = DicomWriter(EXPLICIT_LITTLE)
    # All spaces read as empty text.
    writer.text(0x0008, 0x0060, "CS", "  ")
    # A leading space is dropped from an integer string.
    writer.text(0x0020, 0x0013, "IS", " 12")
    _required(writer, 1, 1)
    writer.short(0x0028, 0x0100, 16)
    writer.short(0x0028, 0x0103, 0)
    # An empty element.
    writer.text(0x0028, 0x1050, "DS", "")
    writer.binary(0x7FE0, 0x0010, "OW", _pixels([1]))
    with assert_raises(contains="window center is not a number"):
        _ = parse_dicom(writer^.finish())
    writer = DicomWriter(EXPLICIT_LITTLE)
    writer.text(0x0008, 0x0060, "CS", "  ")
    writer.text(0x0020, 0x0013, "IS", " 12")
    _required(writer, 1, 1)
    writer.short(0x0028, 0x0100, 16)
    writer.short(0x0028, 0x0103, 0)
    writer.binary(0x7FE0, 0x0010, "OW", _pixels([1]))
    var image = parse_dicom(writer^.finish())
    assert_equal(image.modality, "")
    assert_equal(image.instance_number, 12)


def _with_sequences(syntax: TransferSyntax) raises -> List[UInt8]:
    var writer = DicomWriter(syntax)
    writer.open_sequence(0x0008, 0x1140)
    writer.open_item()
    writer.text(0x0008, 0x1150, "UI", "1.2.3")
    writer.open_sequence(0x0008, 0x1155)
    writer.open_item()
    writer.close_item()
    writer.close_sequence()
    writer.close_item()
    writer.close_sequence()
    # A sequence of defined length with one item of defined length.
    var item = List[UInt8]()
    item.append(0xFE)
    item.append(0xFF)
    item.append(0x00)
    item.append(0xE0)
    item.append(2)
    item.append(0)
    item.append(0)
    item.append(0)
    item.append(7)
    item.append(7)
    writer.binary(0x0008, 0x1200, "SQ", item)
    writer.open_sequence(0x0008, 0x1250)
    writer.close_sequence()
    # An item of defined length in a sequence of undefined length, then an
    # item of undefined length that holds a stray item tag.
    var stray: List[UInt8] = [0xFE, 0xFF, 0x00, 0xE0, 0, 0, 0, 0]
    writer.open_sequence(0x0008, 0x1260)
    writer.bytes.extend(item.copy())
    writer.open_item()
    writer.bytes.extend(stray^)
    writer.close_item()
    writer.close_sequence()
    writer.text(0x0010, 0x0010, "PN", "Phantom^Head")
    _required(writer, 1, 1)
    writer.short(0x0028, 0x0100, 16)
    writer.short(0x0028, 0x0103, 0)
    writer.binary(0x7FE0, 0x0010, "OW", _pixels([9]))
    return writer^.finish()


def test_sequences_are_skipped() raises:
    var explicit = parse_dicom(_with_sequences(EXPLICIT_LITTLE))
    assert_equal(explicit.values[0], 9)
    var implicit = parse_dicom(_with_sequences(IMPLICIT_LITTLE))
    assert_equal(implicit.values[0], 9)


def test_sequence_refusals() raises:
    var writer = DicomWriter(EXPLICIT_LITTLE)
    writer.open_sequence(0x0008, 0x1140)
    writer.short(0x0028, 0x0010, 1)
    with assert_raises(contains="not an item"):
        _ = parse_dicom(writer^.finish())
    writer = DicomWriter(EXPLICIT_LITTLE)
    writer.open_sequence(0x0008, 0x1140)
    writer.close_item()
    with assert_raises(contains="unknown delimiter"):
        _ = parse_dicom(writer^.finish())
    writer = DicomWriter(EXPLICIT_LITTLE)
    writer.open_sequence(0x0008, 0x1140)
    writer.open_item()
    with assert_raises(contains="ends inside an element"):
        _ = parse_dicom(writer^.finish())
    writer = _minimal(EXPLICIT_LITTLE)
    writer.open_sequence(0x7FE0, 0x0010)
    with assert_raises(contains="Encapsulated"):
        _ = parse_dicom(writer^.finish())


def _replace(
    bytes: List[UInt8], old: String, new: String
) raises -> List[UInt8]:
    var out = bytes.copy()
    var a = old.as_bytes()
    var b = new.as_bytes()
    for start in range(len(out) - len(a) + 1):
        var same = True
        for offset in range(len(a)):
            if out[start + offset] != a[offset]:
                same = False
                break
        if same:
            for offset in range(len(b)):
                out[start + offset] = b[offset]
            return out^
    raise Error("not found")


def _prefix(bytes: List[UInt8], count: Int) -> List[UInt8]:
    var out = List[UInt8]()
    for index in range(count):
        out.append(bytes[index])
    return out^


def test_file_refusals() raises:
    var good = encode_dicom(_sample())
    with assert_raises(contains="128-byte preamble"):
        _ = parse_dicom(_prefix(good, 131))
    var wrong = good.copy()
    wrong[129] = 88
    with assert_raises(contains="DICM after"):
        _ = parse_dicom(wrong)
    var big_endian = _replace(good, EXPLICIT_LITTLE_UID, "1.2.840.10008.1.2.2")
    with assert_raises(contains="1.2.840.10008.1.2.2"):
        _ = parse_dicom(big_endian)
    # Only the preamble: no meta group and no transfer syntax.
    with assert_raises(contains="transfer syntax"):
        _ = parse_dicom(_prefix(good, 132))
    with assert_raises(contains="ends inside an element"):
        _ = parse_dicom(_prefix(good, len(good) - 1))
    # A long-form header cut after its VR.
    var writer = _minimal(EXPLICIT_LITTLE)
    var cut = writer^.finish()
    var head: List[UInt8] = [0xE0, 0x7F, 0x10, 0x00, 79, 87, 0, 0]
    cut.extend(head^)
    with assert_raises(contains="ends inside an element"):
        _ = parse_dicom(cut)
    # A file of only the meta group has no pixel data.
    writer = DicomWriter(EXPLICIT_LITTLE)
    with assert_raises(contains="no pixel data"):
        _ = parse_dicom(writer^.finish())


def _pixel_file(
    allocated: Int, stored: Int, representation: Int
) raises -> List[UInt8]:
    var writer = DicomWriter(EXPLICIT_LITTLE)
    _required(writer, 1, 1)
    writer.short(0x0028, 0x0100, allocated)
    if stored > 0:
        writer.short(0x0028, 0x0101, stored)
    if representation >= 0:
        writer.short(0x0028, 0x0103, representation)
    writer.binary(0x7FE0, 0x0010, "OW", _pixels([3]))
    return writer^.finish()


def test_pixel_layout_refusals() raises:
    with assert_raises(contains="8 or 16 bits"):
        _ = parse_dicom(_pixel_file(32, 0, 0))
    assert_equal(parse_dicom(_pixel_file(8, 0, 0)).values[0], 3)
    with assert_raises(contains="more bits"):
        _ = parse_dicom(_pixel_file(8, 12, 0))
    with assert_raises(contains="pixel representation"):
        _ = parse_dicom(_pixel_file(16, 0, 2))
    with assert_raises(contains="pixel representation"):
        _ = parse_dicom(_pixel_file(16, 0, -1))
    # Pixel data shorter than the image.
    var writer = DicomWriter(EXPLICIT_LITTLE)
    _required(writer, 2, 2)
    writer.short(0x0028, 0x0100, 16)
    writer.short(0x0028, 0x0103, 0)
    writer.binary(0x7FE0, 0x0010, "OW", _pixels([1, 2]))
    with assert_raises(contains="shorter than the image"):
        _ = parse_dicom(writer^.finish())
    # Zero rows.
    writer = DicomWriter(EXPLICIT_LITTLE)
    _required(writer, 0, 2)
    writer.short(0x0028, 0x0100, 16)
    writer.short(0x0028, 0x0103, 0)
    writer.binary(0x7FE0, 0x0010, "OW", _pixels([1, 2]))
    with assert_raises(contains="at least one row"):
        _ = parse_dicom(writer^.finish())


def _element_file(
    group: Int, element: Int, vr: String, value: String
) raises -> List[UInt8]:
    var writer = DicomWriter(EXPLICIT_LITTLE)
    writer.text(group, element, vr, value)
    _required(writer, 1, 1)
    writer.short(0x0028, 0x0100, 16)
    writer.short(0x0028, 0x0103, 0)
    writer.binary(0x7FE0, 0x0010, "OW", _pixels([1]))
    return writer^.finish()


def test_element_refusals() raises:
    with assert_raises(contains="needs two bytes"):
        _ = parse_dicom(_element_file(0x0028, 0x0002, "US", ""))
    var writer = DicomWriter(EXPLICIT_LITTLE)
    writer.short(0x0028, 0x0002, 3)
    with assert_raises(contains="one sample per pixel"):
        _ = parse_dicom(writer^.finish())
    writer = DicomWriter(EXPLICIT_LITTLE)
    writer.short(0x0028, 0x0002, 1)
    _required(writer, 1, 1)
    writer.short(0x0028, 0x0100, 16)
    writer.short(0x0028, 0x0103, 0)
    writer.binary(0x7FE0, 0x0010, "OW", _pixels([1]))
    assert_equal(parse_dicom(writer^.finish()).values[0], 1)
    with assert_raises(contains="RGB"):
        _ = parse_dicom(_element_file(0x0028, 0x0004, "CS", "RGB"))
    assert_true(
        parse_dicom(
            _element_file(0x0028, 0x0004, "CS", "MONOCHROME2")
        ).photometric
        == MONOCHROME2
    )
    with assert_raises(contains="one frame"):
        _ = parse_dicom(_element_file(0x0028, 0x0008, "IS", "2"))
    assert_equal(
        parse_dicom(_element_file(0x0028, 0x0008, "IS", "1")).values[0], 1
    )
    with assert_raises(contains="number of frames is not an integer"):
        _ = parse_dicom(_element_file(0x0028, 0x0008, "IS", "two"))
    with assert_raises(contains="slice thickness is not a number"):
        _ = parse_dicom(_element_file(0x0018, 0x0050, "DS", "thick"))
    with assert_raises(contains="slice thickness is not finite"):
        _ = parse_dicom(_element_file(0x0018, 0x0050, "DS", "1e999"))
    with assert_raises(contains="image position needs 3 values"):
        _ = parse_dicom(_element_file(0x0020, 0x0032, "DS", "1\\2"))


def test_geometry_refusals() raises:
    with assert_raises(contains="pixel spacing must be positive"):
        _ = parse_dicom(_element_file(0x0028, 0x0030, "DS", "0\\1"))
    with assert_raises(contains="pixel spacing must be positive"):
        _ = parse_dicom(_element_file(0x0028, 0x0030, "DS", "1\\0"))
    with assert_raises(contains="unit directions"):
        _ = parse_dicom(_element_file(0x0020, 0x0037, "DS", "2\\0\\0\\0\\1\\0"))
    with assert_raises(contains="square directions"):
        _ = parse_dicom(_element_file(0x0020, 0x0037, "DS", "1\\0\\0\\1\\0\\0"))


def test_window_needs_both_values() raises:
    var only_center = parse_dicom(_element_file(0x0028, 0x1050, "DS", "40"))
    assert_false(only_center.has_window)
    var only_width = parse_dicom(_element_file(0x0028, 0x1051, "DS", "400"))
    assert_false(only_width.has_window)


def test_read_dicom_from_a_file() raises:
    var path = temporary_path("slice.dcm")
    Path(path).write_bytes(encode_dicom(_sample()))
    _same_slice(_sample(), read_dicom(path))


def test_slice_size_refusals() raises:
    with assert_raises(contains="at least one row"):
        _ = DicomSlice(0, 1)
    with assert_raises(contains="at least one row"):
        _ = DicomSlice(1, 0)
    with assert_raises(contains="at most 65535"):
        _ = DicomSlice(65536, 1)
    with assert_raises(contains="at most 65535"):
        _ = DicomSlice(1, 65536)


def test_ds_text() raises:
    assert_equal(ds_text(12.0), "12")
    assert_equal(ds_text(-0.5), "-0.5")
    assert_equal(ds_text(0.0), "0")
    assert_equal(ds_text(-0.0000001), "0")
    assert_equal(ds_text(-99999999.999999), "-99999999.999999")
    with assert_raises(contains="below 1e8"):
        _ = ds_text(1.0e8)
    with assert_raises(contains="below 1e8"):
        _ = ds_text(Float64.MAX * 10)


def test_encode_refusals() raises:
    var image = _sample()
    image.slope = 0
    with assert_raises(contains="slope cannot be zero"):
        _ = encode_dicom(image)
    image = _sample()
    image.bits_allocated = 12
    with assert_raises(contains="8 or 16 bits"):
        _ = encode_dicom(image)
    image = _sample()
    image.bits_allocated = 8
    image.bits_stored = 8
    assert_true(len(encode_dicom(image)) > 132)
    image.bits_stored = 0
    with assert_raises(contains="from 1 bit"):
        _ = encode_dicom(image)
    image.bits_stored = 9
    with assert_raises(contains="from 1 bit"):
        _ = encode_dicom(image)
    image = _sample()
    image.syntax = TransferSyntax(2)
    with assert_raises(contains="transfer syntax must be 0 or 1"):
        _ = encode_dicom(image)
    var writer = DicomWriter(EXPLICIT_LITTLE)
    writer.numbers(0x0028, 0x1050, List[Float64]())
    with assert_raises(contains="below 1e8"):
        writer.numbers(0x0028, 0x1051, [1.0e9])


def test_stored_value_range() raises:
    var image = DicomSlice(1, 1)
    image.bits_stored = 8
    image.representation = SIGNED_PIXELS
    assert_equal(stored_value(image, 1000), 127)
    assert_equal(stored_value(image, -1000), -128)
    image.representation = UNSIGNED_PIXELS
    assert_equal(stored_value(image, -5), 0)
    assert_equal(stored_value(image, 300), 255)
    image.slope = 2
    image.intercept = 10
    assert_equal(stored_value(image, 30), 10)


def test_ids() raises:
    assert_true(EXPLICIT_LITTLE.is_valid())
    assert_false(TransferSyntax(2).is_valid())
    require_syntax(IMPLICIT_LITTLE)
    with assert_raises(contains="transfer syntax"):
        require_syntax(TransferSyntax(-1))
    require_photometric(MONOCHROME1)
    with assert_raises(contains="photometric"):
        require_photometric(Photometric(2))
    require_representation(SIGNED_PIXELS)
    with assert_raises(contains="pixel representation"):
        require_representation(PixelRepresentation(2))
    require_axis(K_AXIS)
    require_axis(I_AXIS)
    with assert_raises(contains="slice axis"):
        require_axis(SliceAxis(3))
    require_mode(COMPOSITE)
    require_mode(MAXIMUM_INTENSITY)
    require_mode(ISOSURFACE)
    with assert_raises(contains="render mode"):
        require_mode(RenderMode(3))
    require_label(BACKGROUND)
    require_label(LabelId(255))
    with assert_raises(contains="label must be from 0 to 255"):
        require_label(LabelId(256))


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
