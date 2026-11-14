# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read one grayscale image from a DICOM Part 10 file.

A Part 10 file starts with a 128-byte preamble and the letters `DICM`.
The file meta group follows in explicit VR little endian. Its transfer
syntax UID says how the data set after it is encoded. The reader takes
four syntaxes: explicit VR little endian, implicit VR little endian,
deflated explicit VR little endian and RLE Lossless. It refuses big
endian, JPEG and every other compressed syntax.

A deflated file holds the whole data set as one raw DEFLATE stream after
the meta group. An RLE Lossless file holds the pixel data encapsulated:
an offset table item, then the fragments of the frame, then a sequence
delimiter. The frame starts with a 64-byte header: the number of
segments and the offset of each. Each segment holds one byte of every
sample, the most significant byte first, compressed by PackBits.

The reader keeps the elements that place and scale the image: rows,
columns, bits, pixel representation, photometric interpretation, rescale
slope and intercept, pixel spacing, slice thickness, image position,
image orientation, instance number, modality and the first window. It
steps over every other element, sequences of undefined length too.

The pixel values are rescaled: `slope * stored + intercept`. For CT this
gives Hounsfield units. The reader takes one sample per pixel, one frame,
and 8 or 16 bits allocated.
"""

from extensions.imaging.ids import (
    DEFLATED_EXPLICIT,
    EXPLICIT_LITTLE,
    IMPLICIT_LITTLE,
    MONOCHROME1,
    MONOCHROME2,
    Photometric,
    PixelRepresentation,
    RLE_LOSSLESS,
    SIGNED_PIXELS,
    TransferSyntax,
    UNSIGNED_PIXELS,
    require_syntax,
)
from loaders.bytes import bytes_match
from render.inflate import inflate
from extensions.sdf.vector import V3, cross, dot, length, v3
from std.math import isfinite
from std.pathlib import Path
from extensions.imaging.image_volume import MILLIMETER64
from units.si import Length64

comptime EXPLICIT_LITTLE_UID = "1.2.840.10008.1.2.1"
comptime IMPLICIT_LITTLE_UID = "1.2.840.10008.1.2"
comptime DEFLATED_EXPLICIT_UID = "1.2.840.10008.1.2.1.99"
comptime RLE_LOSSLESS_UID = "1.2.840.10008.1.2.5"
# A deflated data set can expand to at most 1 GiB, so that a small,
# hostile file cannot fill the memory.
comptime MAX_INFLATED = 1 << 30
# The bytes of the header of an RLE frame: a count and 15 offsets.
comptime RLE_HEADER = 64
# A row or a column must be a unit vector to this tolerance, and the two
# must be square to it.
comptime ORIENTATION_TOLERANCE = 1.0e-3
# The length field of an element of undefined length.
comptime UNDEFINED_LENGTH = 0xFFFFFFFF
# The group of the item and delimiter tags.
comptime ITEM_GROUP = 0xFFFE
comptime ITEM = 0xE000
comptime ITEM_END = 0xE00D
comptime SEQUENCE_END = 0xE0DD


struct DicomSlice(Copyable, Movable):
    """One grayscale DICOM image and the elements that place it."""

    var rows: Int
    """The image height in pixels."""
    var columns: Int
    """The image width in pixels."""
    var bits_allocated: Int
    """The bits that each stored value takes: 8 or 16."""
    var bits_stored: Int
    """The bits of each stored value that hold data."""
    var representation: PixelRepresentation
    """Whether the stored values have a sign."""
    var photometric: Photometric
    """Whether the lowest value shows as black or as white."""
    var syntax: TransferSyntax
    """How the data set was encoded."""
    var modality: String
    """The modality code, such as `CT` or `MR`. Empty when absent."""
    var instance_number: Int
    """The instance number. Zero when absent."""
    var slope: Float64
    """The rescale slope. One when absent."""
    var intercept: Float64
    """The rescale intercept. Zero when absent."""
    var row_spacing: Length64
    """The distance between the centers of two rows."""
    var column_spacing: Length64
    """The distance between the centers of two columns."""
    var thickness: Length64
    """The slice thickness. Zero when absent."""
    var position: V3
    """The center of the first pixel in patient space, in meters."""
    var row_direction: V3
    """The unit direction along a row, of increasing column."""
    var column_direction: V3
    """The unit direction down a column, of increasing row."""
    var has_position: Bool
    """Whether the file gave an image position."""
    var has_orientation: Bool
    """Whether the file gave an image orientation."""
    var has_spacing: Bool
    """Whether the file gave a pixel spacing."""
    var window_center: Float64
    """The first window center. Zero when absent."""
    var window_width: Float64
    """The first window width. Zero when absent."""
    var has_window: Bool
    """Whether the file gave a window center and width."""
    var values: List[Float32]
    """The rescaled values, row by row from the top."""

    def __init__(out self, rows: Int, columns: Int) raises:
        """Create an image of zeros with the default elements.

        The spacing is one millimeter, the position is the origin, the row
        runs along x and the column along y. The has flags are false.

        Args:
            rows: The image height in pixels.
            columns: The image width in pixels.

        Raises:
            Error: If a size is not from 1 to 65535.
        """
        _require_size(rows, columns)
        self.rows = rows
        self.columns = columns
        self.bits_allocated = 16
        self.bits_stored = 16
        self.representation = SIGNED_PIXELS
        self.photometric = MONOCHROME2
        self.syntax = EXPLICIT_LITTLE
        self.modality = String("")
        self.instance_number = 0
        self.slope = 1.0
        self.intercept = 0.0
        self.row_spacing = Length64(1.0, MILLIMETER64)
        self.column_spacing = Length64(1.0, MILLIMETER64)
        self.thickness = Length64(0.0, MILLIMETER64)
        self.position = v3(0, 0, 0)
        self.row_direction = v3(1, 0, 0)
        self.column_direction = v3(0, 1, 0)
        self.has_position = False
        self.has_orientation = False
        self.has_spacing = False
        self.window_center = 0.0
        self.window_width = 0.0
        self.has_window = False
        self.values = List[Float32](length=rows * columns, fill=0)

    def normal(self) -> V3:
        """Return the direction from this slice toward the next.

        Returns:
            The cross product of the row and the column directions.
        """
        return cross(self.row_direction, self.column_direction)


def _require_size(rows: Int, columns: Int) raises:
    """Refuse an image size that DICOM cannot hold."""
    if rows < 1 or columns < 1:
        raise Error("A DICOM image needs at least one row and one column")
    if rows > 65535 or columns > 65535:
        raise Error("A DICOM image has at most 65535 rows and columns")


@fieldwise_init
struct _Element(ImplicitlyCopyable):
    """The header of one data element."""

    var group: Int
    var element: Int
    var start: Int
    var length: Int
    var undefined: Bool


def _u16(bytes: Span[UInt8, _], at: Int) -> Int:
    """Read a little-endian 16-bit value."""
    return Int(bytes[at]) | (Int(bytes[at + 1]) << 8)


def _u32(bytes: Span[UInt8, _], at: Int) -> Int:
    """Read a little-endian 32-bit value."""
    return _u16(bytes, at) | (_u16(bytes, at + 2) << 16)


def _require_bytes(bytes: Span[UInt8, _], end: Int) raises:
    """Refuse a read that runs past the end of the file."""
    if end > len(bytes):
        raise Error("The DICOM file ends inside an element")


def _long_form(first: UInt8, second: UInt8) -> Bool:
    """Return whether an explicit VR has a 32-bit length.

    These VRs are OB, OD, OF, OL, OV, OW, SQ, SV, UC, UN, UR, UT and UV.
    """
    var code = (Int(first) << 8) | Int(second)
    for long in [
        0x4F42,
        0x4F44,
        0x4F46,
        0x4F4C,
        0x4F56,
        0x4F57,
        0x5351,
        0x5356,
        0x5543,
        0x554E,
        0x5552,
        0x5554,
        0x5556,
    ]:
        if code == long:
            return True
    return False


def _header(bytes: Span[UInt8, _], at: Int, explicit: Bool) raises -> _Element:
    """Read the header of the element that starts at `at`."""
    _require_bytes(bytes, at + 8)
    var group = _u16(bytes, at)
    var element = _u16(bytes, at + 2)
    var start: Int
    var size: Int
    if group == ITEM_GROUP:
        # Items and delimiters have no VR in either syntax.
        start = at + 8
        size = _u32(bytes, at + 4)
    elif explicit:
        if _long_form(bytes[at + 4], bytes[at + 5]):
            _require_bytes(bytes, at + 12)
            start = at + 12
            size = _u32(bytes, at + 8)
        else:
            start = at + 8
            size = _u16(bytes, at + 6)
    else:
        start = at + 8
        size = _u32(bytes, at + 4)
    var undefined = size == UNDEFINED_LENGTH
    if not undefined:
        _require_bytes(bytes, start + size)
    return _Element(group, element, start, size, undefined)


def _skip_sequence(
    bytes: Span[UInt8, _], at: Int, explicit: Bool
) raises -> Int:
    """Return the place after a sequence of undefined length."""
    var place = at
    while True:
        var item = _header(bytes, place, explicit)
        if item.group != ITEM_GROUP:
            raise Error("A DICOM sequence holds an element that is not an item")
        if item.element == SEQUENCE_END:
            return item.start
        if item.element != ITEM:
            raise Error("A DICOM sequence holds an unknown delimiter")
        if item.undefined:
            place = _skip_item(bytes, item.start, explicit)
        else:
            place = item.start + item.length


def _skip_item(bytes: Span[UInt8, _], at: Int, explicit: Bool) raises -> Int:
    """Return the place after an item of undefined length."""
    var place = at
    while True:
        var element = _header(bytes, place, explicit)
        if element.group == ITEM_GROUP and element.element == ITEM_END:
            return element.start
        if element.undefined:
            place = _skip_sequence(bytes, element.start, explicit)
        else:
            place = element.start + element.length


def _text(bytes: Span[UInt8, _], element: _Element) -> String:
    """Return a text value without its padding."""
    var start = element.start
    var end = element.start + element.length
    while end > start and (bytes[end - 1] == 0 or bytes[end - 1] == 32):
        end -= 1
    while start < end and bytes[start] == 32:
        start += 1
    return String(from_utf8_lossy=bytes[start:end])


def _number(text: String, name: String) raises -> Float64:
    """Read one decimal string."""
    var value: Float64
    try:
        value = atof(String(text.strip()))
    except:
        raise Error("The DICOM " + name + " is not a number")
    if not isfinite(value):
        raise Error("The DICOM " + name + " is not finite")
    return value


def _numbers(
    bytes: Span[UInt8, _], element: _Element, count: Int, name: String
) raises -> List[Float64]:
    """Read the first `count` values of a multi-valued decimal string."""
    var parts = _text(bytes, element).split("\\")
    if len(parts) < count:
        raise Error("The DICOM " + name + " needs " + String(count) + " values")
    var out = List[Float64]()
    for index in range(count):  # pragma: no branch
        out.append(_number(String(parts[index]), name))
    return out^


def _integer(
    bytes: Span[UInt8, _], element: _Element, name: String
) raises -> Int:
    """Read one integer string."""
    var text = _text(bytes, element)
    try:
        return atol(text)
    except:
        raise Error("The DICOM " + name + " is not an integer")


def _short(
    bytes: Span[UInt8, _], element: _Element, name: String
) raises -> Int:
    """Read one unsigned 16-bit value."""
    if element.length < 2:
        raise Error("The DICOM " + name + " needs two bytes")
    return _u16(bytes, element.start)


def _direction(values: List[Float64], first: Int) raises -> V3:
    """Return one direction of an image orientation, checked for length."""
    var direction = v3(values[first], values[first + 1], values[first + 2])
    var size = length(direction)
    if abs(size - 1.0) > ORIENTATION_TOLERANCE:
        raise Error("A DICOM image orientation needs unit directions")
    return direction * (1.0 / size)


def _syntax(uid: String) raises -> TransferSyntax:
    """Return the syntax of a transfer syntax UID, or refuse it."""
    if uid == EXPLICIT_LITTLE_UID:
        return EXPLICIT_LITTLE
    if uid == IMPLICIT_LITTLE_UID:
        return IMPLICIT_LITTLE
    if uid == DEFLATED_EXPLICIT_UID:
        return DEFLATED_EXPLICIT
    if uid == RLE_LOSSLESS_UID:
        return RLE_LOSSLESS
    raise Error(
        "The DICOM transfer syntax "
        + uid
        + " is not one of the four that the reader takes"
    )


def syntax_uid(syntax: TransferSyntax) raises -> String:
    """Return the UID of a transfer syntax.

    Args:
        syntax: The syntax.

    Returns:
        The UID that a file meta group gives for it.

    Raises:
        Error: If `syntax` is not valid.
    """
    require_syntax(syntax)
    var uids: List[String] = [
        EXPLICIT_LITTLE_UID,
        IMPLICIT_LITTLE_UID,
        DEFLATED_EXPLICIT_UID,
        RLE_LOSSLESS_UID,
    ]
    return uids[syntax.value]


def _photometric(text: String) raises -> Photometric:
    """Return the photometric interpretation, or refuse a color one."""
    if text == "MONOCHROME2":
        return MONOCHROME2
    if text == "MONOCHROME1":
        return MONOCHROME1
    raise Error("The DICOM image is " + text + ", not a grayscale image")


def parse_dicom(bytes: Span[UInt8, _]) raises -> DicomSlice:
    """Read one grayscale image from the bytes of a Part 10 file.

    Args:
        bytes: The whole file.

    Returns:
        The image and the elements that place and scale it.

    Raises:
        Error: If the bytes are not a Part 10 file, the transfer syntax is
            not one of the four, the image is not one frame of one
            grayscale sample, an element is short or malformed, or the
            compressed data does not decode.
    """
    if len(bytes) < 132:
        raise Error("A DICOM file starts with a 128-byte preamble and DICM")
    if not bytes_match(bytes, 128, len(bytes), "DICM"):
        raise Error("A DICOM file has DICM after its preamble")
    var at = 132
    var uid = String("")
    while at + 2 <= len(bytes) and _u16(bytes, at) == 0x0002:
        var meta = _header(bytes, at, True)
        if meta.element == 0x0010:
            uid = _text(bytes, meta)
        at = meta.start + meta.length
    var syntax = _syntax(uid)
    if syntax == DEFLATED_EXPLICIT:
        var data = inflate(bytes, at, MAX_INFLATED)
        return _parse_data_set(data, 0, syntax)
    return _parse_data_set(bytes, at, syntax)


def _parse_data_set(
    bytes: Span[UInt8, _], start: Int, syntax: TransferSyntax
) raises -> DicomSlice:
    """Read the image from the data set that starts at `start`."""
    var at = start
    var explicit = syntax != IMPLICIT_LITTLE
    var rows = 0
    var columns = 0
    var bits_allocated = 0
    var bits_stored = 0
    var representation = -1
    var pixels = _Element(0, 0, 0, 0, False)
    var has_pixels = False
    # The fragments of an encapsulated frame.
    var frame = List[UInt8]()
    var photometric = MONOCHROME2
    var modality = String("")
    var instance = 0
    var slope = 1.0
    var intercept = 0.0
    var spacing = List[Float64]()
    var thickness = 0.0
    var position = List[Float64]()
    var orientation = List[Float64]()
    var centers = List[Float64]()
    var widths = List[Float64]()
    while at < len(bytes):
        var element = _header(bytes, at, explicit)
        var tag = (element.group << 16) | element.element
        if element.undefined:
            if tag != 0x7FE00010:
                at = _skip_sequence(bytes, element.start, explicit)
                continue
            if syntax != RLE_LOSSLESS:
                raise Error(
                    "Encapsulated DICOM pixel data needs the RLE Lossless"
                    " syntax"
                )
            at = _fragments(bytes, element.start, frame)
            has_pixels = True
            continue
        at = element.start + element.length
        if tag == 0x00080060:
            modality = _text(bytes, element)
        elif tag == 0x00180050:
            thickness = _numbers(bytes, element, 1, "slice thickness")[0]
        elif tag == 0x00200013:
            instance = _integer(bytes, element, "instance number")
        elif tag == 0x00200032:
            position = _numbers(bytes, element, 3, "image position")
        elif tag == 0x00200037:
            orientation = _numbers(bytes, element, 6, "image orientation")
        elif tag == 0x00280002:
            if _short(bytes, element, "samples per pixel") != 1:
                raise Error("A DICOM image must have one sample per pixel")
        elif tag == 0x00280004:
            photometric = _photometric(_text(bytes, element))
        elif tag == 0x00280008:
            if _integer(bytes, element, "number of frames") != 1:
                raise Error("A DICOM image must have one frame")
        elif tag == 0x00280010:
            rows = _short(bytes, element, "rows")
        elif tag == 0x00280011:
            columns = _short(bytes, element, "columns")
        elif tag == 0x00280030:
            spacing = _numbers(bytes, element, 2, "pixel spacing")
        elif tag == 0x00280100:
            bits_allocated = _short(bytes, element, "bits allocated")
        elif tag == 0x00280101:
            bits_stored = _short(bytes, element, "bits stored")
        elif tag == 0x00280103:
            representation = _short(bytes, element, "pixel representation")
        elif tag == 0x00281050:
            centers = _numbers(bytes, element, 1, "window center")
        elif tag == 0x00281051:
            widths = _numbers(bytes, element, 1, "window width")
        elif tag == 0x00281052:
            intercept = _numbers(bytes, element, 1, "rescale intercept")[0]
        elif tag == 0x00281053:
            slope = _numbers(bytes, element, 1, "rescale slope")[0]
        elif tag == 0x7FE00010:
            if syntax == RLE_LOSSLESS:
                raise Error(
                    "RLE Lossless DICOM pixel data must be encapsulated"
                )
            pixels = element
            has_pixels = True
    if not has_pixels:
        raise Error("The DICOM file has no pixel data")
    if bits_allocated != 8 and bits_allocated != 16:
        raise Error("A DICOM image must have 8 or 16 bits allocated")
    if bits_stored == 0:
        bits_stored = bits_allocated
    if bits_stored > bits_allocated:
        raise Error("A DICOM image cannot store more bits than it allocates")
    if representation != 0 and representation != 1:
        raise Error("A DICOM pixel representation must be 0 or 1")
    var image = DicomSlice(rows, columns)
    image.bits_allocated = bits_allocated
    image.bits_stored = bits_stored
    image.representation = PixelRepresentation(representation)
    image.photometric = photometric
    image.syntax = syntax
    image.modality = modality
    image.instance_number = instance
    image.slope = slope
    image.intercept = intercept
    image.thickness = Length64(thickness, MILLIMETER64)
    if len(spacing) == 2:
        if not (spacing[0] > 0) or not (spacing[1] > 0):
            raise Error("A DICOM pixel spacing must be positive")
        image.row_spacing = Length64(spacing[0], MILLIMETER64)
        image.column_spacing = Length64(spacing[1], MILLIMETER64)
        image.has_spacing = True
    if len(position) == 3:
        image.position = v3(
            Length64(position[0], MILLIMETER64).value,
            Length64(position[1], MILLIMETER64).value,
            Length64(position[2], MILLIMETER64).value,
        )
        image.has_position = True
    if len(orientation) == 6:
        var row = _direction(orientation, 0)
        var column = _direction(orientation, 3)
        if abs(dot(row, column)) > ORIENTATION_TOLERANCE:
            raise Error("A DICOM image orientation needs square directions")
        image.row_direction = row
        image.column_direction = column
        image.has_orientation = True
    if len(centers) == 1 and len(widths) == 1:
        image.window_center = centers[0]
        image.window_width = widths[0]
        image.has_window = True
    if syntax == RLE_LOSSLESS:
        var step = bits_allocated // 8
        var samples = decode_rle_frame(frame, rows * columns, step)
        var whole = _Element(0x7FE0, 0x0010, 0, len(samples), False)
        _decode_pixels(samples, whole, image)
    else:
        _decode_pixels(bytes, pixels, image)
    return image^


def _fragments(
    bytes: Span[UInt8, _], at: Int, mut frame: List[UInt8]
) raises -> Int:
    """Append the fragments of encapsulated pixel data to `frame`.

    Returns:
        The place after the sequence delimiter.
    """
    var table = _header(bytes, at, True)
    if table.group != ITEM_GROUP or table.element != ITEM or table.undefined:
        raise Error("Encapsulated DICOM pixel data starts with an offset table")
    var place = table.start + table.length
    while True:
        var item = _header(bytes, place, True)
        if item.group != ITEM_GROUP:
            raise Error("Encapsulated DICOM pixel data holds a non-item")
        if item.element == SEQUENCE_END:
            return item.start
        if item.element != ITEM or item.undefined:
            raise Error("A DICOM pixel fragment needs a defined length")
        frame.extend(bytes[item.start : item.start + item.length])
        place = item.start + item.length


def decode_rle_frame(
    frame: Span[UInt8, _], count: Int, step: Int
) raises -> List[UInt8]:
    """Return the little-endian samples of one RLE Lossless frame.

    Args:
        frame: The frame: its 64-byte header, then its segments.
        count: The samples in the frame, rows times columns.
        step: The bytes of each sample, and so the segments of the frame.

    Returns:
        `count * step` bytes, the samples in order, the low byte first.

    Raises:
        Error: If the header is short, its segment count is not `step`,
            an offset is outside the frame, or a segment does not decode
            to `count` bytes.
    """
    if len(frame) < RLE_HEADER:
        raise Error("An RLE frame is shorter than its 64-byte header")
    if _u32(frame, 0) != step:
        raise Error("An RLE frame needs one segment per byte of a sample")
    var samples = List[UInt8](length=count * step, fill=0)
    for segment in range(step):  # pragma: no branch
        var start = _u32(frame, 4 + 4 * segment)
        var end = len(frame)
        if segment + 1 < step:
            end = _u32(frame, 8 + 4 * segment)
        if start < RLE_HEADER or end < start or end > len(frame):
            raise Error("An RLE segment offset is outside the frame")
        var data = _unpack(frame, start, end, count)
        # Segment 0 holds the most significant byte.
        var place = step - 1 - segment
        for index in range(count):  # pragma: no branch
            samples[index * step + place] = data[index]
    return samples^


def _unpack(
    frame: Span[UInt8, _], start: Int, end: Int, count: Int
) raises -> List[UInt8]:
    """Return the first `count` bytes of one PackBits segment."""
    var out = List[UInt8](capacity=count + 128)
    var at = start
    while at < end and len(out) < count:
        var code = Int(frame[at])
        at += 1
        if code == 128:
            continue
        var literal = code < 128
        var need = code + 1 if literal else 1
        if at + need > end:
            raise Error("An RLE segment ends inside a run")
        if literal:
            out.extend(frame[at : at + need])
        else:
            for _ in range(257 - code):  # pragma: no branch
                out.append(frame[at])
        at += need
    if len(out) < count:
        raise Error("An RLE segment decodes to fewer bytes than the image")
    return out^


def _decode_pixels(
    bytes: Span[UInt8, _], pixels: _Element, mut image: DicomSlice
) raises:
    """Fill the rescaled values from the pixel data."""
    var step = image.bits_allocated // 8
    var count = image.rows * image.columns
    if pixels.length < count * step:
        raise Error("The DICOM pixel data is shorter than the image")
    var mask = (1 << image.bits_stored) - 1
    var sign = 1 << (image.bits_stored - 1)
    var signed = image.representation == SIGNED_PIXELS
    var slope = image.slope
    var intercept = image.intercept
    for index in range(count):  # pragma: no branch
        var at = pixels.start + index * step
        var raw: Int
        if step == 2:
            raw = _u16(bytes, at)
        else:
            raw = Int(bytes[at])
        var stored = raw & mask
        if signed and (stored & sign) != 0:
            stored -= mask + 1
        image.values[index] = Float32(slope * Float64(stored) + intercept)


def read_dicom(path: String) raises -> DicomSlice:
    """Read one grayscale image from a Part 10 file.

    Args:
        path: The file to read.

    Returns:
        The image and the elements that place and scale it.

    Raises:
        Error: If the file cannot be read, or `parse_dicom` refuses it.
    """
    var bytes = Path(path).read_bytes()
    return parse_dicom(bytes)
