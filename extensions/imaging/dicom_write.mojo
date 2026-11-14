# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write grayscale DICOM Part 10 files.

`DicomWriter` writes a preamble, `DICM`, a file meta group and then the
elements that the caller adds, in the order of the calls. DICOM needs
the tags in increasing order. The caller keeps that order.

`encode_dicom` writes one `DicomSlice` as a CT image. It stores each
value as `round((value - intercept) / slope)`, held in the range of the
stored bits.
"""

from extensions.imaging.dicom import (
    DicomSlice,
    EXPLICIT_LITTLE_UID,
    IMPLICIT_LITTLE_UID,
    ITEM,
    ITEM_END,
    ITEM_GROUP,
    SEQUENCE_END,
    UNDEFINED_LENGTH,
)
from extensions.imaging.ids import (
    EXPLICIT_LITTLE,
    MONOCHROME1,
    SIGNED_PIXELS,
    TransferSyntax,
    require_syntax,
)
from loaders.js_number import js_to_fixed
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

    def __init__(out self, syntax: TransferSyntax) raises:
        """Start a file with its preamble and its file meta group.

        Args:
            syntax: How the data set after the meta group is encoded.

        Raises:
            Error: If `syntax` is not valid.
        """
        require_syntax(syntax)
        self.explicit = syntax == EXPLICIT_LITTLE
        var uid = String(IMPLICIT_LITTLE_UID)
        if self.explicit:
            uid = String(EXPLICIT_LITTLE_UID)
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

    def finish(deinit self) -> List[UInt8]:
        """Return the bytes of the file and end the writer.

        Returns:
            The file.
        """
        return self.bytes^

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
    if len(data) % 2 == 1:
        data.append(0)
    var vr = String("OB")
    if image.bits_allocated == 16:
        vr = "OW"
    writer.binary(0x7FE0, 0x0010, vr, data)
    return writer^.finish()
