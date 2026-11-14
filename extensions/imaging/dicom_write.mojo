# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write grayscale DICOM Part 10 files.

`DicomWriter` writes a preamble, `DICM`, a file meta group and then the
elements that the caller adds, in the order of the calls. DICOM needs
the tags in increasing order. The caller keeps that order. For the
deflated syntax, `finish` compresses the data set.

`encode_dicom` writes one `DicomSlice` as a CT image. It stores each
value as `round((value - intercept) / slope)`, held in the range of the
stored bits. For the RLE Lossless syntax, it encodes the pixel data as
one frame in one fragment, each row of each segment on its own, as
DICOM needs.
"""

from extensions.imaging.dicom import (
    DicomSlice,
    ITEM,
    ITEM_END,
    ITEM_GROUP,
    RLE_HEADER,
    SEQUENCE_END,
    UNDEFINED_LENGTH,
    syntax_uid,
)
from extensions.imaging.ids import (
    DEFLATED_EXPLICIT,
    IMPLICIT_LITTLE,
    MONOCHROME1,
    RLE_LOSSLESS,
    SIGNED_PIXELS,
    TransferSyntax,
)
from loaders.js_number import js_to_fixed
from render.deflate import deflate
from std.math import max, min, round
from extensions.imaging.image_volume import MILLIMETER64

# The SOP class of a CT image.
comptime CT_IMAGE_STORAGE = "1.2.840.10008.5.1.4.1.1.2"


def _push16(mut out: List[UInt8], value: Int):
    """Append a little-endian 16-bit value."""
    out.append(UInt8(value & 0xFF))
    out.append(UInt8((value >> 8) & 0xFF))


def _push32(mut out: List[UInt8], value: Int):
    """Append a little-endian 32-bit value."""
    _push16(out, value & 0xFFFF)
    _push16(out, (value >> 16) & 0xFFFF)


def _push_text(mut out: List[UInt8], text: String):
    """Append the bytes of ASCII text."""
    for byte in text.as_bytes():
        out.append(byte)


def _element(
    mut out: List[UInt8],
    explicit: Bool,
    group: Int,
    element: Int,
    vr: String,
    long_form: Bool,
    size: Int,
):
    """Append the header of one element."""
    _push16(out, group)
    _push16(out, element)
    if not explicit:
        _push32(out, size)
        return
    _push_text(out, vr)
    if long_form:
        _push16(out, 0)
        _push32(out, size)
    else:
        _push16(out, size)


def ds_text(value: Float64) raises -> String:
    """Return a decimal string with six places, without trailing zeros.

    Args:
        value: A finite value whose magnitude is below 1e8.

    Returns:
        The text, such as `0.5` or `-12`. It has at most 16 characters, as
        DICOM's DS needs.

    Raises:
        Error: If `value` is not finite or is 1e8 or more in magnitude.
    """
    if not (abs(value) < 1.0e8):
        raise Error("A DICOM decimal string holds magnitudes below 1e8")
    var text = js_to_fixed(value, 6)
    var bytes = text.as_bytes()
    var end = len(bytes)
    while bytes[end - 1] == 48:
        end -= 1
    if bytes[end - 1] == 46:
        end -= 1
    var out = String(text[byte=:end])
    if out == "-0":
        return String("0")
    return out^


struct DicomWriter(Movable):
    """The bytes of one Part 10 file, built element by element."""

    var bytes: List[UInt8]
    """The file so far."""
    var explicit: Bool
    """Whether the data set is explicit VR."""
    var syntax: TransferSyntax
    """How the data set after the meta group is encoded."""
    var meta_end: Int
    """The place in `bytes` where the data set starts."""

    def __init__(out self, syntax: TransferSyntax) raises:
        """Start a file with its preamble and its file meta group.

        Args:
            syntax: How the data set after the meta group is encoded.

        Raises:
            Error: If `syntax` is not valid.
        """
        var uid = syntax_uid(syntax)
        self.explicit = syntax != IMPLICIT_LITTLE
        self.syntax = syntax
        var meta = List[UInt8]()
        _element(meta, True, 0x0002, 0x0001, "OB", True, 2)
        meta.append(0)
        meta.append(1)
        _meta_text(meta, 0x0002, CT_IMAGE_STORAGE)
        _meta_text(meta, 0x0003, "1.2.826.0.1.3680043.2.1125.1")
        _meta_text(meta, 0x0010, uid)
        self.bytes = List[UInt8](length=128, fill=0)
        _push_text(self.bytes, "DICM")
        _element(self.bytes, True, 0x0002, 0x0000, "UL", False, 4)
        _push32(self.bytes, len(meta))
        self.bytes.extend(meta^)
        self.meta_end = len(self.bytes)

    def text(mut self, group: Int, element: Int, vr: String, value: String):
        """Append a text element, padded to an even length with a space.

        Args:
            group: The group of the tag.
            element: The element of the tag.
            vr: The two-letter value representation, such as `DS`.
            value: The text.
        """
        var data = value
        if len(data.as_bytes()) % 2 == 1:
            data += " "
        _element(
            self.bytes,
            self.explicit,
            group,
            element,
            vr,
            False,
            len(data.as_bytes()),
        )
        _push_text(self.bytes, data)

    def numbers(
        mut self, group: Int, element: Int, values: List[Float64]
    ) raises:
        """Append a decimal string element of one or more values.

        Args:
            group: The group of the tag.
            element: The element of the tag.
            values: The values, joined with backslashes.

        Raises:
            Error: If a value is not finite or is 1e8 or more in magnitude.
        """
        var text = String("")
        for index in range(len(values)):
            if index > 0:
                text += "\\"
            text += ds_text(values[index])
        self.text(group, element, "DS", text)

    def short(mut self, group: Int, element: Int, value: Int):
        """Append an unsigned 16-bit element.

        Args:
            group: The group of the tag.
            element: The element of the tag.
            value: The value, from 0 to 65535.
        """
        _element(self.bytes, self.explicit, group, element, "US", False, 2)
        _push16(self.bytes, value)

    def binary(
        mut self, group: Int, element: Int, vr: String, data: List[UInt8]
    ):
        """Append an element of raw bytes with a 32-bit length.

        Args:
            group: The group of the tag.
            element: The element of the tag.
            vr: The value representation, such as `OW` or `OB`.
            data: The bytes, of even length.
        """
        _element(self.bytes, self.explicit, group, element, vr, True, len(data))
        self.bytes.extend(data.copy())

    def open_sequence(mut self, group: Int, element: Int):
        """Append the header of a sequence of undefined length.

        Args:
            group: The group of the tag.
            element: The element of the tag.
        """
        _element(
            self.bytes,
            self.explicit,
            group,
            element,
            "SQ",
            True,
            UNDEFINED_LENGTH,
        )

    def open_item(mut self):
        """Append the header of an item of undefined length."""
        _push16(self.bytes, ITEM_GROUP)
        _push16(self.bytes, ITEM)
        _push32(self.bytes, UNDEFINED_LENGTH)

    def close_item(mut self):
        """Append the delimiter that ends an item of undefined length."""
        _push16(self.bytes, ITEM_GROUP)
        _push16(self.bytes, ITEM_END)
        _push32(self.bytes, 0)

    def encapsulated(mut self, frame: List[UInt8]):
        """Append pixel data of undefined length that holds one fragment.

        The pixel data holds an empty offset table, `frame` padded to an
        even length with a zero byte, and the sequence delimiter.

        Args:
            frame: The bytes of the one frame.
        """
        _element(self.bytes, True, 0x7FE0, 0x0010, "OB", True, UNDEFINED_LENGTH)
        _push16(self.bytes, ITEM_GROUP)
        _push16(self.bytes, ITEM)
        _push32(self.bytes, 0)
        var size = len(frame) + len(frame) % 2
        _push16(self.bytes, ITEM_GROUP)
        _push16(self.bytes, ITEM)
        _push32(self.bytes, size)
        self.bytes.extend(frame.copy())
        if size > len(frame):
            self.bytes.append(0)
        self.close_sequence()

    def finish(deinit self) raises -> List[UInt8]:
        """Return the bytes of the file and end the writer.

        For the deflated syntax, the data set becomes one raw DEFLATE
        stream, padded to an even length with a zero byte.

        Returns:
            The file.

        Raises:
            Error: If the compressor fails.
        """
        if self.syntax != DEFLATED_EXPLICIT:
            return self.bytes^
        var whole = Span(self.bytes)
        var out = List[UInt8](whole[: self.meta_end])
        out.extend(deflate(whole[self.meta_end :]))
        if len(out) % 2 == 1:
            out.append(0)
        return out^

    def close_sequence(mut self):
        """Append the delimiter that ends a sequence of undefined length."""
        _push16(self.bytes, ITEM_GROUP)
        _push16(self.bytes, SEQUENCE_END)
        _push32(self.bytes, 0)


def _meta_text(mut meta: List[UInt8], element: Int, uid: String):
    """Append a UI element of the meta group, padded with a zero byte."""
    var size = len(uid.as_bytes())
    var padded = size + size % 2
    _element(meta, True, 0x0002, element, "UI", False, padded)
    _push_text(meta, uid)
    if padded > size:
        meta.append(0)


def stored_value(image: DicomSlice, value: Float32) -> Int:
    """Return the stored value that rescales to the nearest of `value`.

    Args:
        image: The image whose slope, intercept and bits apply.
        value: The rescaled value.

    Returns:
        `round((value - intercept) / slope)`, held in the range that the
        stored bits and the pixel representation allow.
    """
    var stored = round((Float64(value) - image.intercept) / image.slope)
    var high = Float64((1 << image.bits_stored) - 1)
    var low = 0.0
    if image.representation == SIGNED_PIXELS:
        high = Float64((1 << (image.bits_stored - 1)) - 1)
        low = -high - 1
    return Int(min(max(stored, low), high))


def encode_dicom(image: DicomSlice) raises -> List[UInt8]:
    """Return the bytes of a Part 10 CT image file.

    The file holds the modality, the slice thickness, the instance
    number, the position, the orientation, the image layout, the pixel
    spacing, the window when the image has one, the rescale and the pixel
    data. The position, orientation and spacing are written when their
    has flags are set.

    Args:
        image: The image to write.

    Returns:
        The file.

    Raises:
        Error: If the image's transfer syntax is not valid, its slope is
            zero, or its bits are not 8 or 16 allocated with 1 or more
            stored.
    """
    if image.slope == 0:
        raise Error("A DICOM rescale slope cannot be zero")
    if image.bits_allocated != 8 and image.bits_allocated != 16:
        raise Error("A DICOM image must have 8 or 16 bits allocated")
    if image.bits_stored < 1 or image.bits_stored > image.bits_allocated:
        raise Error("A DICOM image stores from 1 bit to the bits it allocates")
    var writer = DicomWriter(image.syntax)
    var modality = image.modality
    if modality == "":
        modality = "CT"
    writer.text(0x0008, 0x0060, "CS", modality)
    writer.numbers(0x0018, 0x0050, [image.thickness.to(MILLIMETER64)])
    writer.text(0x0020, 0x0013, "IS", String(image.instance_number))
    if image.has_position:
        var p = image.position
        writer.numbers(
            0x0020,
            0x0032,
            [p.x * 1000.0, p.y * 1000.0, p.z * 1000.0],
        )
    if image.has_orientation:
        var r = image.row_direction
        var c = image.column_direction
        writer.numbers(0x0020, 0x0037, [r.x, r.y, r.z, c.x, c.y, c.z])
    writer.short(0x0028, 0x0002, 1)
    var photometric = String("MONOCHROME2")
    if image.photometric == MONOCHROME1:
        photometric = "MONOCHROME1"
    writer.text(0x0028, 0x0004, "CS", photometric)
    writer.short(0x0028, 0x0010, image.rows)
    writer.short(0x0028, 0x0011, image.columns)
    if image.has_spacing:
        writer.numbers(
            0x0028,
            0x0030,
            [
                image.row_spacing.to(MILLIMETER64),
                image.column_spacing.to(MILLIMETER64),
            ],
        )
    writer.short(0x0028, 0x0100, image.bits_allocated)
    writer.short(0x0028, 0x0101, image.bits_stored)
    writer.short(0x0028, 0x0102, image.bits_stored - 1)
    writer.short(0x0028, 0x0103, image.representation.value)
    if image.has_window:
        writer.numbers(0x0028, 0x1050, [image.window_center])
        writer.numbers(0x0028, 0x1051, [image.window_width])
    writer.numbers(0x0028, 0x1052, [image.intercept])
    writer.numbers(0x0028, 0x1053, [image.slope])
    var data = List[UInt8]()
    var mask = (1 << image.bits_stored) - 1
    # An image holds at least one pixel.
    for value in image.values:  # pragma: no branch
        var stored = stored_value(image, value) & mask
        if image.bits_allocated == 16:
            _push16(data, stored)
        else:
            data.append(UInt8(stored))
    if image.syntax == RLE_LOSSLESS:
        var step = image.bits_allocated // 8
        writer.encapsulated(encode_rle_frame(data, step, image.columns))
        return writer^.finish()
    if len(data) % 2 == 1:
        data.append(0)
    var vr = String("OB")
    if image.bits_allocated == 16:
        vr = "OW"
    writer.binary(0x7FE0, 0x0010, vr, data)
    return writer^.finish()


def pack_bits(data: Span[UInt8, _]) -> List[UInt8]:
    """Return the PackBits code of some bytes, as DICOM's RLE uses it.

    A run of two or more equal bytes, up to 128, becomes the byte
    `257 - length` and the repeated byte. Other bytes become literal runs
    of up to 128: the byte `length - 1` and the bytes.

    Args:
        data: The bytes to encode.

    Returns:
        The code.
    """
    var out = List[UInt8]()
    var at = 0
    while at < len(data):
        var run = _run_length(data, at)
        if run > 1:
            out.append(UInt8(257 - run))
            out.append(data[at])
            at += run
            continue
        var start = at
        at += 1
        while (
            at < len(data) and at - start < 128 and _run_length(data, at) == 1
        ):
            at += 1
        out.append(UInt8(at - start - 1))
        out.extend(data[start:at])
    return out^


def _run_length(data: Span[UInt8, _], at: Int) -> Int:
    """Return how many bytes from `at` equal the byte at `at`, up to 128."""
    var run = 1
    while at + run < len(data) and run < 128 and data[at + run] == data[at]:
        run += 1
    return run


def encode_rle_frame(
    samples: List[UInt8], step: Int, columns: Int
) raises -> List[UInt8]:
    """Return one RLE Lossless frame of little-endian samples.

    Segment `s` holds byte `step - 1 - s` of each sample: the most
    significant byte comes first. Each row of a segment is encoded on its
    own, and each segment is padded to an even length with a zero byte.

    Args:
        samples: The samples in order, `step` bytes each, the low byte
            first.
        step: The bytes of each sample, from 1 to 15.
        columns: The samples in each row.

    Returns:
        The frame: its 64-byte header, then its segments.

    Raises:
        Error: If `step` is not from 1 to 15, or the samples do not fill
            whole rows of `columns`.
    """
    if step < 1 or step > 15:
        raise Error("An RLE frame holds from 1 to 15 segments")
    if columns < 1 or len(samples) % (step * columns) != 0:
        raise Error("RLE samples must fill whole rows")
    var count = len(samples) // step
    var frame = List[UInt8]()
    _push32(frame, step)
    var segments = List[UInt8]()
    # A frame holds at least one segment.
    for segment in range(step):  # pragma: no branch
        _push32(frame, RLE_HEADER + len(segments))
        var row = List[UInt8](capacity=columns)
        for index in range(count):  # pragma: no branch
            row.append(samples[index * step + step - 1 - segment])
            if len(row) == columns:
                segments.extend(pack_bits(row))
                row.clear()
        if len(segments) % 2 == 1:
            segments.append(0)
    while len(frame) < RLE_HEADER:
        _push32(frame, 0)
    frame.extend(segments^)
    return frame^
