# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A Truevision TGA reader, three.js's `TGALoader`, beside the PNG and
JPEG readers.

A TGA file is an eighteen-byte header, an optional image id, an optional
color map and the pixels, row by row, either as they stand or in
run-length packets. It has no signature: the header's image type says
what the pixels are, and the header's descriptor byte says which corner
the first pixel is. The reader follows three.js's `TGALoader`: color-mapped
pixels of eight bits through a map of 24-bit entries, true color of 24
or 32 bits, gray of eight bits or eight bits and an alpha, plain or
run-length encoded, from any of the four corners. It returns what the
PNG reader returns, a `DecodedImage` from the top row down.

**Where it differs from three.js, it refuses rather than guesses.**
three.js reads a pixel past the file, a packet past the image and an
index past the color map as whatever the array holds there. This reader
refuses each by name. It also honors the header's first color-map entry
index, which three.js ignores, and it refuses 16-bit true color, which
three.js reads with its attribute bit inverted from what writers mean.

TGA carries no color space of its own. What a paint program writes is
sRGB, and so does this reader assume: a decoded TGA is `SRGB`.
"""

from render.framebuffer import Color
from render.png import MAX_PIXELS, DecodedImage
from render.srgb import SRGB

# How long the fixed header is.
comptime HEADER_SIZE = 18
# The largest color map three.js reads: one entry per eight-bit index.
comptime MAX_MAP_ENTRIES = 256
# The only color-map entry size three.js reads: blue, green and red.
comptime MAP_ENTRY_BITS = 24
# The descriptor bits that say where the first pixel is: bit four set
# means it is on the right, bit five set means it is at the top.
comptime RIGHT_TO_LEFT = 0x10
comptime TOP_TO_BOTTOM = 0x20
# A run-length packet's header: the top bit says it repeats one pixel,
# and the low seven bits hold its length less one.
comptime REPEAT_PACKET = 0x80
comptime PACKET_LENGTH = 0x7F


@fieldwise_init
struct TgaImageType(Equatable, ImplicitlyCopyable, Writable):
    """What a TGA file's pixels are, as a type rather than a bare int: the
    header's image type byte."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the six types this reader reads.

        Returns:
            Whether the type is color-mapped, true color or gray, plain
            or run-length encoded. Type zero, no image, and the
            Huffman-coded types are not.
        """
        return (
            self == COLOR_MAPPED
            or self == TRUE_COLOR
            or self == GRAYSCALE
            or self == RLE_COLOR_MAPPED
            or self == RLE_TRUE_COLOR
            or self == RLE_GRAYSCALE
        )

    def is_color_mapped(self) -> Bool:
        """Return True if the pixels are indices into a color map.

        Returns:
            Whether the type is color-mapped, plain or run-length.
        """
        return self == COLOR_MAPPED or self == RLE_COLOR_MAPPED

    def is_gray(self) -> Bool:
        """Return True if the pixels are gray levels.

        Returns:
            Whether the type is gray, plain or run-length.
        """
        return self == GRAYSCALE or self == RLE_GRAYSCALE

    def is_run_length(self) -> Bool:
        """Return True if the pixels arrive in run-length packets.

        Returns:
            Whether the type is one of the three run-length ones.
        """
        return (
            self == RLE_COLOR_MAPPED
            or self == RLE_TRUE_COLOR
            or self == RLE_GRAYSCALE
        )


comptime COLOR_MAPPED = TgaImageType(1)
comptime TRUE_COLOR = TgaImageType(2)
comptime GRAYSCALE = TgaImageType(3)
comptime RLE_COLOR_MAPPED = TgaImageType(9)
comptime RLE_TRUE_COLOR = TgaImageType(10)
comptime RLE_GRAYSCALE = TgaImageType(11)


def _le16(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian sixteen-bit number at `at`, which the
    header's length check has already found in the file."""
    return Int(bytes[at]) | (Int(bytes[at + 1]) << 8)


def unpack_pixels(
    kind: TgaImageType,
    bytes: List[UInt8],
    start: Int,
    count: Int,
    pixel_bytes: Int,
) raises -> List[UInt8]:
    """Return a TGA file's pixel bytes in file order, as they stand or
    expanded from run-length packets.

    A packet is a header byte and then either one pixel, repeated as many
    times as the header says, or that many pixels as they stand. A packet
    can cross from one row into the next.

    Args:
        kind: The image type, which says whether the pixels are packed.
        bytes: The file.
        start: Where the pixels begin.
        count: How many pixels the image has.
        pixel_bytes: How many bytes a pixel has.

    Returns:
        `count` times `pixel_bytes` bytes.

    Raises:
        Error: If `kind` is not a type this reader reads, the file ends
            before the last pixel, or a packet runs past the image.
    """
    if not kind.is_valid():
        raise Error("A TGA image type this reader does not read")
    var size = count * pixel_bytes
    if not kind.is_run_length():
        if start + size > len(bytes):
            raise Error("A TGA file ended inside its pixels")
        var plain = List[UInt8](capacity=size)
        for index in range(size):
            plain.append(bytes[start + index])
        return plain^
    var out = List[UInt8](capacity=size)
    var at = start
    var done = 0
    while done < count:
        if at >= len(bytes):
            raise Error("A TGA file ended inside its pixels")
        var header = Int(bytes[at])
        at += 1
        var run = (header & PACKET_LENGTH) + 1
        if done + run > count:
            raise Error("A TGA run-length packet runs past the image")
        if header & REPEAT_PACKET != 0:
            if at + pixel_bytes > len(bytes):
                raise Error("A TGA file ended inside its pixels")
            for _ in range(run):  # pragma: no branch
                for index in range(pixel_bytes):  # pragma: no branch
                    out.append(bytes[at + index])
            at += pixel_bytes
        else:
            if at + run * pixel_bytes > len(bytes):
                raise Error("A TGA file ended inside its pixels")
            for index in range(run * pixel_bytes):  # pragma: no branch
                out.append(bytes[at + index])
            at += run * pixel_bytes
        done += run
    return out^


def decode(bytes: List[UInt8]) raises -> DecodedImage:
    """Return the image a TGA file holds, as RGBA from the top row down.

    Color-mapped pixels are looked up in the map, whose entries are blue,
    green and red. True-color pixels are blue, green, red and, at 32 bits,
    alpha. Gray pixels are a level and, at 16 bits, an alpha. Every
    other pixel is opaque. The descriptor's origin bits say which corner
    the first pixel is in; its attribute bits are not read, as three.js
    does not read them.

    Args:
        bytes: The complete file.

    Returns:
        The image, `SRGB`, since a TGA declares nothing else.

    Raises:
        Error: If the header is short, names a type this reader does not
            read, a color map that does not fit the type, a pixel size the
            type does not have, or no pixels; if the file ends before its
            color map or its pixels; if a packet runs past the image; or
            if a pixel names a color-map entry the map does not have.
    """
    if len(bytes) < HEADER_SIZE:
        raise Error("A TGA file is shorter than its header")
    var id_length = Int(bytes[0])
    var map_type = Int(bytes[1])
    var kind = TgaImageType(Int(bytes[2]))
    var map_first = _le16(bytes, 3)
    var map_length = _le16(bytes, 5)
    var map_bits = Int(bytes[7])
    var width = _le16(bytes, 12)
    var height = _le16(bytes, 14)
    var pixel_bits = Int(bytes[16])
    var descriptor = Int(bytes[17])
    if not kind.is_valid():
        raise Error(
            "A TGA image type must be color-mapped, true color or gray,"
            " plain or run-length encoded"
        )
    if kind.is_color_mapped():
        if map_type != 1:
            raise Error("A color-mapped TGA must carry a color map")
        if map_bits != MAP_ENTRY_BITS or map_length > MAX_MAP_ENTRIES:
            raise Error(
                "A TGA color map must hold at most 256 entries of 24 bits"
            )
        if pixel_bits != 8:
            raise Error("A color-mapped TGA's pixels must be 8-bit indices")
    else:
        if map_type != 0:
            raise Error("A TGA whose pixels are colors must carry no map")
        if kind.is_gray():
            if pixel_bits != 8 and pixel_bits != 16:
                raise Error("A gray TGA must be 8 or 16 bits a pixel")
        elif pixel_bits != 24 and pixel_bits != 32:
            raise Error(
                "A true-color TGA must be 24 or 32 bits a pixel: 16-bit"
                " true color is not supported"
            )
    if width == 0 or height == 0:
        raise Error("A TGA file must have a width and a height")
    if width * height > MAX_PIXELS:
        raise Error("Image has too many pixels")

    var at = HEADER_SIZE + id_length
    var palette = List[Color]()
    if kind.is_color_mapped():
        if at + map_length * 3 > len(bytes):
            raise Error("A TGA file ended inside its color map")
        for entry in range(map_length):
            var base = at + entry * 3
            palette.append(
                Color(bytes[base + 2], bytes[base + 1], bytes[base], 255)
            )
        at += map_length * 3
    var pixel_bytes = pixel_bits // 8
    var data = unpack_pixels(kind, bytes, at, width * height, pixel_bytes)

    var right_to_left = descriptor & RIGHT_TO_LEFT != 0
    var top_to_bottom = descriptor & TOP_TO_BOTTOM != 0
    var pixels = List[UInt8](
        length=width * height * DecodedImage.CHANNELS, fill=0
    )
    for index in range(width * height):  # pragma: no branch
        var source = index * pixel_bytes
        var color: Color
        if kind.is_color_mapped():
            var entry = Int(data[source]) - map_first
            if entry < 0 or entry >= map_length:
                raise Error("A TGA pixel names an entry its map does not have")
            color = palette[entry]
        elif kind.is_gray():
            var alpha = UInt8(255)
            if pixel_bytes == 2:
                alpha = data[source + 1]
            color = Color(data[source], data[source], data[source], alpha)
        else:
            var alpha = UInt8(255)
            if pixel_bytes == 4:
                alpha = data[source + 3]
            color = Color(
                data[source + 2], data[source + 1], data[source], alpha
            )
        var x = index % width
        var y = index // width
        if right_to_left:
            x = width - 1 - x
        if not top_to_bottom:
            y = height - 1 - y
        var target = (y * width + x) * DecodedImage.CHANNELS
        pixels[target] = color.r
        pixels[target + 1] = color.g
        pixels[target + 2] = color.b
        pixels[target + 3] = color.a
    return DecodedImage(width, height, pixels^, SRGB)
