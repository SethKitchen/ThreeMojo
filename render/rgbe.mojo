# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A Radiance RGBE reader, three.js's `RGBELoader` (now `HDRLoader`).

A `.hdr` file is a text header and then the pixels, four bytes each: a
mantissa for red, green and blue, and one exponent the three share. One
exponent is what lets four bytes hold light from a candle to the sun: a
channel is its byte over 255, times two to the exponent less 128.

    #?RADIANCE
    FORMAT=32-bit_rle_rgbe

    -Y 512 +X 1024

The header's first line is `#?` and a program name. Lines after it are
comments, `GAMMA=`, `EXPOSURE=`, `FORMAT=` and anything else, until a line
names the image size. The pixels follow, one scanline at a time from the
top: each either as it stands, or run-length encoded one channel after
another.

**The arithmetic is three.js's.** A channel is `byte * 2^(e - 128) / 255`,
worked in doubles and stored as a float, as three.js's `FloatType` output
stores it, and alpha is one. three.js's default output is `HalfFloatType`,
which rounds each channel to a half and clamps it at 65504; this reader
keeps the float, which holds every value the file can spell. `GAMMA` and
`EXPOSURE` are read past and not applied, as three.js does not apply them.

**Where it differs from three.js, it refuses rather than guesses.** three.js
takes any `FORMAT` and reads XYZE pixels as if they were RGB; this reader
refuses anything but `32-bit_rle_rgbe`. three.js stops at the end of the
file and leaves the rows it did not reach black; this reader refuses a
file cut short. Only the `-Y height +X width` orientation is read, as
three.js reads only it, and the old Radiance run-length scheme, which
three.js does not read either, is not read.
"""

from render.float_image import FloatImage
from render.png import MAX_PIXELS

# The only pixel format this reader reads: RGB mantissas and a shared
# exponent, run-length encoded or not. XYZE shares the layout and not the
# meaning, so it is refused rather than shown as RGB.
comptime RGBE_FORMAT = "32-bit_rle_rgbe"
# A scanline is run-length encoded only if it is at least this wide and
# at most `MAX_RLE_WIDTH` wide: its width must fit the fifteen bits of
# the scanline header.
comptime MIN_RLE_WIDTH = 8
comptime MAX_RLE_WIDTH = 0x7FFF
# A run-length count above this is a run of one byte repeated, and the
# excess is its length; at or below, it is that many bytes as they stand.
comptime RUN_FLAG = 128
# The longest number of digits a dimension may spell. Nine keeps the
# product of two in range and is far past `MAX_PIXELS` already.
comptime MAX_DIGITS = 9


def _is_space(byte: UInt8) -> Bool:
    """Return True for a space, a tab or a carriage return."""
    return byte == 0x20 or byte == 0x09 or byte == 0x0D


def _text(bytes: List[UInt8], start: Int, end: Int) -> String:
    """Return the bytes from `start` to `end` as text, one byte a
    character."""
    var out = String()
    for at in range(start, end):
        out += chr(Int(bytes[at]))
    return out^


def _words(line: String) -> List[String]:
    """Return a line split at runs of spaces, tabs and carriage returns."""
    var out = List[String]()
    var word = String()
    for byte in line.as_bytes():
        if _is_space(byte):
            if word.byte_length() > 0:
                out.append(word)
                word = String()
            continue
        word += chr(Int(byte))
    if word.byte_length() > 0:
        out.append(word)
    return out^


def _dimension(word: String) raises -> Int:
    """Return a dimension written in decimal digits.

    Raises:
        Error: If the word is longer than `MAX_DIGITS` or holds anything
            but digits.
    """
    # A word is never empty: `_words` keeps none.
    if word.byte_length() > MAX_DIGITS:
        raise Error("RGBE: an image size must be at most nine digits")
    var value = 0
    for byte in word.as_bytes():  # pragma: no branch
        if byte < 0x30 or byte > 0x39:
            raise Error("RGBE: an image size must be decimal digits")
        value = value * 10 + Int(byte - 0x30)
    return value


@fieldwise_init
struct RgbeHeader(ImplicitlyCopyable):
    """How big a `.hdr` file's image is, and where its pixels begin."""

    var width: Int
    var height: Int
    # The offset of the first pixel byte.
    var start: Int


def _is_magic(bytes: List[UInt8], start: Int, end: Int) -> Bool:
    """Return True if the line from `start` to `end` is `#?` and a
    program name: three.js's `/^#\\?(\\S+)/`."""
    return (
        end - start >= 3
        and bytes[start] == 0x23
        and bytes[start + 1] == 0x3F
        and not _is_space(bytes[start + 2])
    )


def read_header(bytes: List[UInt8]) raises -> RgbeHeader:
    """Return what a `.hdr` file's header says: three.js's
    `RGBE_ReadHeader`.

    Lines end at a line feed. The first must be `#?` and a program name.
    After it, a line beginning `#` is a comment; a `FORMAT=` line names the
    pixel format; a `-Y height +X width` line names the size. Reading
    stops when both are known, and any other line is read past, `GAMMA`
    and `EXPOSURE` included.

    Args:
        bytes: The whole file.

    Returns:
        The header, with `start` the offset of the first pixel byte.

    Raises:
        Error: If the file has no line, its first line is not `#?` and a
            name, the header ends before the format or the size, the
            format is not `32-bit_rle_rgbe`, the size is malformed or not
            positive, or the image has more pixels than any texture here.
    """
    var header = RgbeHeader(0, 0, 0)
    var at = 0
    var has_format = False
    var has_size = False
    var first = True
    while not (has_format and has_size):
        var end = at
        while end < len(bytes) and bytes[end] != 0x0A:
            end += 1
        if end >= len(bytes):
            if first:
                raise Error("RGBE: no header found")
            if not has_format:
                raise Error("RGBE: the header names no format")
            raise Error("RGBE: the header names no image size")
        var line = _text(bytes, at, end)
        var begun = at
        at = end + 1
        if first:
            first = False
            if not _is_magic(bytes, begun, end):
                raise Error("RGBE: a .hdr file begins with #? and a name")
            continue
        if line.startswith("#"):
            continue
        var words = _words(line)
        if len(words) == 1 and words[0].startswith("FORMAT="):
            if String(words[0][byte=7:]) != RGBE_FORMAT:
                raise Error(
                    "RGBE: only FORMAT=32-bit_rle_rgbe is read; XYZE and"
                    " other formats are not ported"
                )
            has_format = True
            continue
        if len(words) == 4 and words[0] == "-Y" and words[2] == "+X":
            header.height = _dimension(words[1])
            header.width = _dimension(words[3])
            if header.width <= 0 or header.height <= 0:
                raise Error("RGBE: an image must be at least one pixel")
            if header.width * header.height > MAX_PIXELS:
                raise Error("RGBE: the image has more pixels than a texture")
            has_size = True
    header.start = at
    return header^


def _is_flat(bytes: List[UInt8], at: Int, width: Int) -> Bool:
    """Return True if the pixels at `at` are stored as they stand rather
    than run-length encoded: three.js's test, a width outside the encodable
    range or a first scanline that does not begin 2, 2 and a width below
    32768."""
    return (
        width < MIN_RLE_WIDTH
        or width > MAX_RLE_WIDTH
        or len(bytes) - at < 4
        or bytes[at] != 2
        or bytes[at + 1] != 2
        or (bytes[at + 2] & 0x80) != 0
    )


def _is_scanline_start(bytes: List[UInt8], at: Int, width: Int) -> Bool:
    """Return True if the four bytes at `at` are 2, 2 and `width`, the
    header every encoded scanline begins with."""
    return (
        bytes[at] == 2
        and bytes[at + 1] == 2
        and (Int(bytes[at + 2]) << 8 | Int(bytes[at + 3])) == width
    )


def read_pixels(
    bytes: List[UInt8], start: Int, width: Int, height: Int
) raises -> List[UInt8]:
    """Return the RGBE bytes of every pixel, four a pixel from the top:
    three.js's `RGBE_ReadPixels_RLE`.

    Each scanline is run-length encoded when the image is eight to 32767
    pixels wide and the first scanline begins 2, 2; otherwise every
    scanline is stored as it stands. An encoded scanline is four runs of
    bytes, one per channel: a count above 128 repeats the next byte that
    count less 128 times, and any other count copies that many bytes.

    Args:
        bytes: The whole file.
        start: Where the pixels begin, `RgbeHeader.start`.
        width: The image's width in pixels.
        height: Its height.

    Returns:
        Red, green and blue mantissas and the shared exponent, per pixel.

    Raises:
        Error: If the pixels are cut short, a scanline's header is not 2,
            2 and the width, or a run is empty or overflows its scanline.
    """
    var count = width * height * 4
    if _is_flat(bytes, start, width):
        if len(bytes) - start < count:
            raise Error("RGBE: the pixels are cut short")
        return List[UInt8](bytes[start : start + count])
    var out = List[UInt8](capacity=count)
    var line = width * 4
    var scan = List[UInt8](length=line, fill=0)
    var at = start
    # The image is at least one row tall: the loop always runs.
    for _ in range(height):  # pragma: no branch
        if len(bytes) - at < 4:
            raise Error("RGBE: a scanline is cut short")
        if not _is_scanline_start(bytes, at, width):
            raise Error("RGBE: a scanline must begin 2, 2 and its width")
        at += 4
        var filled = 0
        while filled < line:
            if at >= len(bytes):
                raise Error("RGBE: a scanline is cut short")
            var run = Int(bytes[at])
            at += 1
            var repeats = run > RUN_FLAG
            if repeats:
                run -= RUN_FLAG
            if run == 0 or filled + run > line:
                raise Error("RGBE: a run is empty or overflows its scanline")
            if repeats:
                if at >= len(bytes):
                    raise Error("RGBE: a scanline is cut short")
                for _ in range(run):  # pragma: no branch
                    scan[filled] = bytes[at]
                    filled += 1
                at += 1
                continue
            if len(bytes) - at < run:
                raise Error("RGBE: a scanline is cut short")
            for step in range(run):  # pragma: no branch
                scan[filled] = bytes[at + step]
                filled += 1
            at += run
        # Channel after channel in the scanline, pixel after pixel out.
        for x in range(width):  # pragma: no branch
            out.append(scan[x])
            out.append(scan[x + width])
            out.append(scan[x + 2 * width])
            out.append(scan[x + 3 * width])
    return out^


def rgbe_to_float(
    red: UInt8, green: UInt8, blue: UInt8, exponent: UInt8
) -> SIMD[DType.float32, 4]:
    """Return one RGBE pixel as linear light: three.js's
    `RGBEByteToRGBFloat`.

    Each mantissa over 255, times two to the exponent less 128, worked in
    doubles as JavaScript works it and then stored as a float. Alpha is
    one. An exponent of zero is not special-cased, as three.js does not
    special-case it: a zero mantissa is zero, and anything else is a
    tiny positive number.

    Args:
        red: The red mantissa.
        green: The green mantissa.
        blue: The blue mantissa.
        exponent: The shared exponent, biased by 128.

    Returns:
        Red, green, blue and an alpha of one.
    """
    # Two to a whole power is exact in a double, from 2^-128 to 2^127.
    var scale = (Float64(2) ** (Float64(Int(exponent)) - 128)) / 255
    return SIMD[DType.float32, 4](
        Float32(Float64(Int(red)) * scale),
        Float32(Float64(Int(green)) * scale),
        Float32(Float64(Int(blue)) * scale),
        1,
    )


def decode(bytes: List[UInt8]) raises -> FloatImage:
    """Return the image a `.hdr` file holds, as linear floats.

    Args:
        bytes: The whole file.

    Returns:
        The image, row-major from the top, alpha one.

    Raises:
        Error: Everything `read_header` and `read_pixels` raise.
    """
    var header = read_header(bytes)
    var rgbe = read_pixels(bytes, header.start, header.width, header.height)
    var pixels = List[Float32](capacity=len(rgbe))
    # The image is at least one pixel: the loop always runs.
    for at in range(0, len(rgbe), 4):  # pragma: no branch
        var light = rgbe_to_float(
            rgbe[at], rgbe[at + 1], rgbe[at + 2], rgbe[at + 3]
        )
        pixels.append(light[0])
        pixels.append(light[1])
        pixels.append(light[2])
        pixels.append(light[3])
    return FloatImage(header.width, header.height, pixels^)
