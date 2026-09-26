# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A PowerVR texture file read into its PVRTC levels, from three.js
`examples/jsm/loaders/PVRLoader.js`.

`read(bytes)` returns a `CompressedImage` of PVRTC1 blocks, which
`CompressedImage.texture` decodes with `render.pvrtc`.

**Version 3.** The file starts with the word `PVR\\x03`. Its header is
thirteen little-endian words: the pixel format in the third, the height
and the width in the seventh and eighth, the face count in the eleventh
and the level count in the twelfth. The data starts after 52 bytes and
the metadata's length, the thirteenth word. Pixel formats 0 to 3 are
PVRTC 2 bits RGB, 2 bits RGBA, 4 bits RGB and 4 bits RGBA.

**Version 2.** The twelfth word is `PVR!`. The first word is the
header's length, then the height, the width, the level count less one
and the flags, whose low byte names PVRTC 2 bits (24) or 4 bits (25). An
alpha mask above zero, in the eleventh word, makes it RGBA. The
thirteenth word is the surface count.

**The data.** For each level, each face in turn, largest first: two
blocks across and down at least, as three.js reads them. Six faces make
a cube, as three.js guesses. The image is `LINEAR`, as three.js leaves
it.

**What is refused.** What three.js reads as `undefined` or throws on: a
file shorter than its header, a version that is neither, a pixel format
that is not PVRTC, and a level past the end of the file. And what the
decoder cannot draw: a side that is not a power of two, and more levels
than the size has, which three.js reads as levels of no width.
"""

from render.compressed_texture import (
    RGB_PVRTC_2BPPV1_FORMAT,
    RGB_PVRTC_4BPPV1_FORMAT,
    RGBA_PVRTC_2BPPV1_FORMAT,
    RGBA_PVRTC_4BPPV1_FORMAT,
    CompressedFormat,
    CompressedImage,
    chain_length,
    check_decoded_size,
    level_bytes,
)
from render.srgb import LINEAR

# The header's length in words, which three.js reads whatever the version.
comptime HEADER_WORDS = 13


def _u32(bytes: List[UInt8], at: Int) -> Int:
    """Return a little-endian word.

    Args:
        bytes: The file.
        at: Where the word starts.

    Returns:
        The word.
    """
    return (
        Int(bytes[at])
        | (Int(bytes[at + 1]) << 8)
        | (Int(bytes[at + 2]) << 16)
        | (Int(bytes[at + 3]) << 24)
    )


def read(bytes: List[UInt8]) raises -> CompressedImage:
    """Return every level of every face of a PVR file, three.js's
    `PVRLoader.parse`.

    Args:
        bytes: The whole file.

    Returns:
        The image; see `CompressedImage`.

    Raises:
        Error: For anything the module docstring lists.
    """
    if len(bytes) < HEADER_WORDS * 4:
        raise Error("PVR: the file is shorter than its header")
    var format: CompressedFormat
    var width: Int
    var height: Int
    var faces: Int
    var levels: Int
    var start: Int
    if _u32(bytes, 0) == 0x03525650:
        var pixel_format = _u32(bytes, 8)
        var formats: List[CompressedFormat] = [
            RGB_PVRTC_2BPPV1_FORMAT,
            RGBA_PVRTC_2BPPV1_FORMAT,
            RGB_PVRTC_4BPPV1_FORMAT,
            RGBA_PVRTC_4BPPV1_FORMAT,
        ]
        if pixel_format > 3:
            raise Error(
                "PVR: pixel format " + String(pixel_format) + " is not PVRTC"
            )
        format = formats[pixel_format]
        height = _u32(bytes, 24)
        width = _u32(bytes, 28)
        faces = _u32(bytes, 40)
        levels = _u32(bytes, 44)
        start = 52 + _u32(bytes, 48)
    elif _u32(bytes, 44) == 0x21525650:
        var kind = _u32(bytes, 16) & 0xFF
        var alpha = _u32(bytes, 40) > 0
        if kind == 25:
            format = (
                RGBA_PVRTC_4BPPV1_FORMAT if alpha else RGB_PVRTC_4BPPV1_FORMAT
            )
        elif kind == 24:
            format = (
                RGBA_PVRTC_2BPPV1_FORMAT if alpha else RGB_PVRTC_2BPPV1_FORMAT
            )
        else:
            raise Error("PVR: format " + String(kind) + " is not PVRTC")
        start = _u32(bytes, 0)
        height = _u32(bytes, 4)
        width = _u32(bytes, 8)
        levels = _u32(bytes, 12) + 1
        faces = _u32(bytes, 48)
    else:
        raise Error("PVR: the file is neither version 2 nor version 3")
    if width <= 0 or height <= 0 or faces <= 0:
        raise Error("PVR: the dimensions and the face count must be positive")
    var power = (width & (width - 1)) == 0 and (height & (height - 1)) == 0
    if not power:
        raise Error("PVR: PVRTC's width and height must be powers of two")
    if levels < 1 or levels > chain_length(width, height):
        raise Error("PVR: the file names more levels than its size has")
    check_decoded_size(width, height, False)
    var image = CompressedImage(width, height, format, LINEAR, faces, levels)
    image.mipmaps = List[List[UInt8]](length=faces * levels, fill=List[UInt8]())
    var at = start
    # three.js walks the levels, and each face within a level.
    for level in range(levels):  # pragma: no branch
        var size = level_bytes(
            image.level_width(level), image.level_height(level), format
        )
        for face in range(faces):  # pragma: no branch
            if size > len(bytes) - at:
                raise Error("PVR: the file ends before its last level")
            image.mipmaps[face * levels + level] = List[UInt8](
                bytes[at : at + size]
            )
            at += size
    return image^
