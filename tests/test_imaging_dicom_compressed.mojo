# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The RLE Lossless and deflated DICOM syntaxes.

The files in `assets/dicom/` come from pydicom. See
`assets/dicom/make_dicom.py` and `assets/dicom/expected.txt`.
"""

from extensions.imaging.dicom import (
    DicomSlice,
    decode_rle_frame,
    parse_dicom,
    read_dicom,
    syntax_uid,
)
from extensions.imaging.dicom_write import (
    DicomWriter,
    encode_dicom,
    encode_rle_frame,
    pack_bits,
)
from extensions.imaging.ids import (
    DEFLATED_EXPLICIT,
    EXPLICIT_LITTLE,
    IMPLICIT_LITTLE,
    RLE_LOSSLESS,
    SIGNED_PIXELS,
    TransferSyntax,
    UNSIGNED_PIXELS,
)
from extensions.imaging.image_volume import MILLIMETER64
from extensions.sdf.vector import v3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64


def _expected(name: String) raises -> List[Float32]:
    """Return the values that pydicom printed for one file."""
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


def _check_fixture(
    name: String, syntax: TransferSyntax, rows: Int, columns: Int
) raises:
    var image = read_dicom("assets/dicom/" + name)
    assert_true(image.syntax == syntax)
    assert_equal(image.rows, rows)
    assert_equal(image.columns, columns)
    assert_almost_equal(image.row_spacing.to(MILLIMETER64), 0.5)
    assert_almost_equal(image.column_spacing.to(MILLIMETER64), 0.75)
    assert_almost_equal(image.position.x, -0.010, atol=1e-12)
    assert_almost_equal(image.position.y, 0.020, atol=1e-12)
    assert_almost_equal(image.position.z, 0.005, atol=1e-12)
    var expected = _expected(name)
    assert_equal(len(image.values), len(expected))
    for index in range(len(expected)):
        assert_equal(image.values[index], expected[index])


def test_reads_pydicom_files() raises:
    _check_fixture("rle16.dcm", RLE_LOSSLESS, 3, 4)
    _check_fixture("rle8.dcm", RLE_LOSSLESS, 4, 5)
    _check_fixture("deflated.dcm", DEFLATED_EXPLICIT, 3, 4)
    assert_true(
        read_dicom("assets/dicom/rle8.dcm").representation == UNSIGNED_PIXELS
    )
    assert_true(
        read_dicom("assets/dicom/rle16.dcm").representation == SIGNED_PIXELS
    )


def _image(rows: Int, columns: Int, bits: Int) raises -> DicomSlice:
    """An image with runs and literals in every row."""
    var image = DicomSlice(rows, columns)
    image.bits_allocated = bits
    image.bits_stored = bits
    image.representation = SIGNED_PIXELS if bits == 16 else UNSIGNED_PIXELS
    image.row_spacing = Length64(0.5, MILLIMETER64)
    image.has_spacing = True
    image.position = v3(0.01, -0.02, 0.03)
    image.has_position = True
    for index in range(rows * columns):
        var value = (index * 37) % 251
        if index % columns < columns // 2:
            value = 7
        if bits == 16:
            value = value * 129 - 16000
        image.values[index] = Float32(value)
    return image^


def _round_trip(
    image: DicomSlice, syntax: TransferSyntax
) raises -> List[UInt8]:
    var copy = image.copy()
    copy.syntax = syntax
    var bytes = encode_dicom(copy)
    assert_equal(len(bytes) % 2, 0)
    var back = parse_dicom(bytes)
    assert_true(back.syntax == syntax)
    assert_equal(back.rows, image.rows)
    assert_equal(back.columns, image.columns)
    assert_almost_equal(back.position.z, 0.03, atol=1e-12)
    for index in range(len(image.values)):
        assert_equal(back.values[index], image.values[index])
    return bytes^


def test_rle_round_trip() raises:
    var sixteen = _image(5, 300, 16)
    var plain = _round_trip(sixteen, EXPLICIT_LITTLE)
    var packed = _round_trip(sixteen, RLE_LOSSLESS)
    assert_true(len(packed) < len(plain))
    _ = _round_trip(_image(3, 7, 8), RLE_LOSSLESS)
    # One pixel of each size.
    _ = _round_trip(_image(1, 1, 8), RLE_LOSSLESS)
    _ = _round_trip(_image(1, 1, 16), RLE_LOSSLESS)


def test_deflated_round_trip() raises:
    var plain = _round_trip(_image(5, 300, 16), EXPLICIT_LITTLE)
    var deflated = _round_trip(_image(5, 300, 16), DEFLATED_EXPLICIT)
    assert_true(len(deflated) < len(plain))
    # Streams of both parities: one is padded with a zero byte.
    _ = _round_trip(_image(1, 1, 8), DEFLATED_EXPLICIT)
    _ = _round_trip(_image(1, 2, 8), DEFLATED_EXPLICIT)
    _ = _round_trip(_image(1, 3, 8), DEFLATED_EXPLICIT)
    _ = _round_trip(_image(2, 1, 16), DEFLATED_EXPLICIT)
    var cut = List[UInt8]()
    for index in range(len(deflated) - 20):
        cut.append(deflated[index])
    with assert_raises():
        _ = parse_dicom(cut)


def test_syntax_uids() raises:
    assert_equal(syntax_uid(EXPLICIT_LITTLE), "1.2.840.10008.1.2.1")
    assert_equal(syntax_uid(IMPLICIT_LITTLE), "1.2.840.10008.1.2")
    assert_equal(syntax_uid(DEFLATED_EXPLICIT), "1.2.840.10008.1.2.1.99")
    assert_equal(syntax_uid(RLE_LOSSLESS), "1.2.840.10008.1.2.5")
    with assert_raises(contains="transfer syntax must be from 0 to 3"):
        _ = syntax_uid(TransferSyntax(4))


def _bytes(values: List[Int]) -> List[UInt8]:
    var out = List[UInt8]()
    for value in values:
        out.append(UInt8(value))
    return out^


def _unpacked(code: List[UInt8], count: Int) raises -> List[UInt8]:
    """Decode one PackBits segment through a one-segment frame."""
    var frame = List[UInt8]()
    frame.extend(_bytes([1, 0, 0, 0, 64, 0, 0, 0]))
    while len(frame) < 64:
        frame.append(0)
    frame.extend(code.copy())
    return decode_rle_frame(frame, count, 1)


def _same(a: List[UInt8], b: List[UInt8]) raises:
    assert_equal(len(a), len(b))
    for index in range(len(a)):
        assert_equal(a[index], b[index])


def test_pack_bits() raises:
    # A run, a literal at the end, and a literal before a run.
    var data = _bytes([5, 5, 5, 1, 2, 9, 9, 3])
    var code = pack_bits(data)
    _same(code, _bytes([254, 5, 1, 1, 2, 255, 9, 0, 3]))
    _same(_unpacked(code, 8), data)
    # Runs and literals longer than 128 split.
    var long = List[UInt8]()
    for _ in range(300):
        long.append(4)
    for index in range(200):
        long.append(UInt8(index))
    code = pack_bits(long)
    assert_equal(code[0], 129)
    assert_equal(code[2], 129)
    _same(_unpacked(code, 500), long)
    # 128 is a no-op code.
    _same(_unpacked(_bytes([128, 0, 6]), 1), _bytes([6]))
    assert_equal(len(pack_bits(List[UInt8]())), 0)


def test_rle_frames() raises:
    # Fifteen segments fill the header, with no unused offsets.
    var samples = List[UInt8]()
    for index in range(30):
        samples.append(UInt8(index % 4))
    var frame = encode_rle_frame(samples, 15, 1)
    _same(decode_rle_frame(frame, 2, 15), samples)
    # Two rows of three, padded segments.
    var rows = _bytes([1, 2, 3, 3, 3, 3])
    _same(decode_rle_frame(encode_rle_frame(rows, 1, 3), 6, 1), rows)
    with assert_raises(contains="from 1 to 15 segments"):
        _ = encode_rle_frame(rows, 0, 3)
    with assert_raises(contains="from 1 to 15 segments"):
        _ = encode_rle_frame(rows, 16, 3)
    with assert_raises(contains="whole rows"):
        _ = encode_rle_frame(rows, 1, 4)
    with assert_raises(contains="whole rows"):
        _ = encode_rle_frame(rows, 1, 0)


def _header(count: Int, first: Int, second: Int) -> List[UInt8]:
    var frame = _bytes(
        [count, 0, 0, 0, first, 0, 0, 0, second & 0xFF, second >> 8, 0, 0]
    )
    while len(frame) < 64:
        frame.append(0)
    return frame^


def test_rle_frame_refusals() raises:
    with assert_raises(contains="64-byte header"):
        _ = decode_rle_frame(_bytes([1, 0, 0, 0]), 1, 1)
    with assert_raises(contains="one segment per byte"):
        _ = decode_rle_frame(_header(2, 64, 0), 1, 1)
    # An offset inside the header.
    with assert_raises(contains="offset is outside"):
        _ = decode_rle_frame(_header(1, 8, 0), 1, 1)
    # An offset past the end.
    with assert_raises(contains="offset is outside"):
        _ = decode_rle_frame(_header(1, 70, 0), 1, 1)
    # A second offset past the end.
    var frame = _header(2, 64, 300)
    frame.extend(_bytes([0, 1, 0, 2]))
    with assert_raises(contains="offset is outside"):
        _ = decode_rle_frame(frame, 1, 2)
    # A second offset before the first.
    frame = _header(2, 66, 64)
    frame.extend(_bytes([0, 1, 0, 2]))
    with assert_raises(contains="offset is outside"):
        _ = decode_rle_frame(frame, 1, 2)
    with assert_raises(contains="ends inside a run"):
        _ = _unpacked(_bytes([3, 1, 2]), 4)
    with assert_raises(contains="ends inside a run"):
        _ = _unpacked(_bytes([250]), 4)
    with assert_raises(contains="fewer bytes"):
        _ = _unpacked(_bytes([1, 1, 2]), 4)


def _layout(mut writer: DicomWriter, bits: Int):
    writer.short(0x0028, 0x0010, 1)
    writer.short(0x0028, 0x0011, 1)
    writer.short(0x0028, 0x0100, bits)
    writer.short(0x0028, 0x0103, 0)


def _item(mut bytes: List[UInt8], element: Int, size: Int):
    bytes.extend(
        _bytes(
            [
                0xFE,
                0xFF,
                element & 0xFF,
                element >> 8,
                size & 0xFF,
                (size >> 8) & 0xFF,
                (size >> 16) & 0xFF,
                (size >> 24) & 0xFF,
            ]
        )
    )


def _open_pixels(mut bytes: List[UInt8]):
    bytes.extend(
        _bytes([0xE0, 0x7F, 0x10, 0x00, 79, 66, 0, 0, 255, 255, 255, 255])
    )


def test_encapsulated_refusals() raises:
    var writer = DicomWriter(RLE_LOSSLESS)
    _layout(writer, 8)
    writer.binary(0x7FE0, 0x0010, "OB", _bytes([1, 0]))
    with assert_raises(contains="must be encapsulated"):
        _ = parse_dicom(writer^.finish())
    writer = DicomWriter(EXPLICIT_LITTLE)
    _layout(writer, 8)
    writer.encapsulated(encode_rle_frame(_bytes([1]), 1, 1))
    with assert_raises(contains="needs the RLE Lossless"):
        _ = parse_dicom(writer^.finish())
    # An odd frame is padded, and decodes.
    writer = DicomWriter(RLE_LOSSLESS)
    _layout(writer, 8)
    var frame = _header(1, 64, 0)
    frame.extend(_bytes([0, 42, 128]))
    writer.encapsulated(frame)
    var bytes = writer^.finish()
    assert_equal(len(bytes) % 2, 0)
    assert_equal(parse_dicom(bytes).values[0], 42)
    # No offset table: a non-item, a delimiter, an undefined length.
    for case_index in range(3):
        writer = DicomWriter(RLE_LOSSLESS)
        _layout(writer, 8)
        _open_pixels(writer.bytes)
        if case_index == 0:
            writer.short(0x0028, 0x0010, 1)
        elif case_index == 1:
            _item(writer.bytes, 0xE0DD, 0)
        else:
            _item(writer.bytes, 0xE000, 0xFFFFFFFF)
        with assert_raises(contains="offset table"):
            _ = parse_dicom(writer^.finish())
    # Fragments: a non-item, an item delimiter, an undefined length.
    for case_index in range(3):
        writer = DicomWriter(RLE_LOSSLESS)
        _layout(writer, 8)
        _open_pixels(writer.bytes)
        _item(writer.bytes, 0xE000, 0)
        if case_index == 0:
            writer.short(0x0028, 0x0010, 1)
            with assert_raises(contains="non-item"):
                _ = parse_dicom(writer^.finish())
            continue
        if case_index == 1:
            _item(writer.bytes, 0xE00D, 0)
        else:
            _item(writer.bytes, 0xE000, 0xFFFFFFFF)
        with assert_raises(contains="defined length"):
            _ = parse_dicom(writer^.finish())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
