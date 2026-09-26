# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A DirectDraw Surface file read into its compressed levels, from three.js
`examples/jsm/loaders/DDSLoader.js`.

`read(bytes)` returns a `CompressedImage`: every level of every face as
block bytes, the format, and the dimensions. `CompressedImage.texture`
decodes one level of one face into a `Texture`.

**The header.** Four magic bytes, `DDS `, and a 124-byte header of
little-endian words: the height, the width, the level count, a pixel
format, and the capability flags that mark a cube. The pixel format names
the block layout by a four-character code. The code `DX10` adds a
twenty-byte header after the first, which names the layout by its DXGI
number instead.

**The data.** For each face, each level in turn, largest first: the
blocks that cover the level, rounded up to whole blocks. A cube holds all
six faces, +x, -x, +y, -y, +z, -z.

| Code | DXGI | Format |
|---|---|---|
| `DXT1` | 71, 72 | BC1: `RGB_S3TC_DXT1_FORMAT` from a code, `RGBA_S3TC_DXT1_FORMAT` from DXGI |
| `DXT3` | 74, 75 | BC2: `RGBA_S3TC_DXT3_FORMAT` |
| `DXT5` | 77, 78 | BC3: `RGBA_S3TC_DXT5_FORMAT` |
| `ATI1`, `BC4U` | 80 | BC4: `RED_RGTC1_FORMAT` |
| `BC4S` | 81 | `SIGNED_RED_RGTC1_FORMAT` |
| `ATI2`, `BC5U` | 83 | BC5: `RED_GREEN_RGTC2_FORMAT` |
| `BC5S` | 84 | `SIGNED_RED_GREEN_RGTC2_FORMAT` |
| | 95 | BC6H: `RGB_BPTC_UNSIGNED_FORMAT` |
| | 96 | `RGB_BPTC_SIGNED_FORMAT` |
| | 98, 99 | BC7: `RGBA_BPTC_FORMAT` |
| `ETC1` | | `RGB_ETC1_FORMAT` |

The second DXGI number of each pair is the sRGB form, and the image's
color space is `SRGB` only for those. A four-character code does not say,
so its image is `LINEAR`, as three.js leaves it.

**Uncompressed files.** A code that names none of these is read as three.js
reads it: by the pixel format's bit count and masks. Thirty-two bits with a
red, a green, a blue and an alpha mask is `RGBA_FORMAT`, read from bytes in
blue, green, red, alpha order. Twenty-four bits with the three color masks
is `RGBA_FORMAT` too, read from blue, green, red, with an opaque alpha. As in
three.js, a mask only has to overlap its byte, and the bytes are read in
that order whatever the masks say. The format flags are not read: a known
code is a block format even when the flags say RGB, as in three.js.
"""

from render.compressed_texture import (
    RED_GREEN_RGTC2_FORMAT,
    RED_RGTC1_FORMAT,
    RGB_BPTC_SIGNED_FORMAT,
    RGB_BPTC_UNSIGNED_FORMAT,
    RGB_ETC1_FORMAT,
    RGB_S3TC_DXT1_FORMAT,
    RGBA_BPTC_FORMAT,
    RGBA_S3TC_DXT1_FORMAT,
    RGBA_S3TC_DXT3_FORMAT,
    RGBA_FORMAT,
    RGBA_S3TC_DXT5_FORMAT,
    SIGNED_RED_GREEN_RGTC2_FORMAT,
    SIGNED_RED_RGTC1_FORMAT,
    CompressedFormat,
    CompressedImage,
    chain_length,
    check_decoded_size,
    level_bytes,
)
from render.srgb import LINEAR, SRGB, ColorSpace

# The header's size, which a file states and must state correctly.
comptime HEADER_BYTES = 124
# The DX10 header's size.
comptime DX10_HEADER_BYTES = 20
# `dwFlags`: the level count is set.
comptime DDSD_MIPMAPCOUNT = 0x20000
# `dwCaps2`: a cube, and its six faces.
comptime DDSCAPS2_CUBEMAP = 0x200
comptime DDSCAPS2_ALL_FACES = 0xFC00
# The DX10 header's `miscFlag` for a cube.
comptime DDS_RESOURCE_MISC_TEXTURECUBE = 0x4


def four_cc(code: String) -> Int:
    """Return a four-character code as the little-endian word a file holds.

    Args:
        code: Four ASCII characters.

    Returns:
        The word: the first character in the low byte.
    """
    var bytes = code.as_bytes()
    return (
        Int(bytes[0])
        | (Int(bytes[1]) << 8)
        | (Int(bytes[2]) << 16)
        | (Int(bytes[3]) << 24)
    )


def _u32(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian word at `at`; the caller has checked the
    length."""
    return (
        Int(bytes[at])
        | (Int(bytes[at + 1]) << 8)
        | (Int(bytes[at + 2]) << 16)
        | (Int(bytes[at + 3]) << 24)
    )


def format_of_four_cc(code: Int) raises -> CompressedFormat:
    """Return the format a pixel format's four-character code names.

    Args:
        code: The code, as the file's word.

    Returns:
        The format.

    Raises:
        Error: If the code names a format this reader does not decode.
    """
    if code == four_cc("DXT1"):
        return RGB_S3TC_DXT1_FORMAT
    if code == four_cc("DXT3"):
        return RGBA_S3TC_DXT3_FORMAT
    if code == four_cc("DXT5"):
        return RGBA_S3TC_DXT5_FORMAT
    if code == four_cc("ATI1") or code == four_cc("BC4U"):
        return RED_RGTC1_FORMAT
    if code == four_cc("BC4S"):
        return SIGNED_RED_RGTC1_FORMAT
    if code == four_cc("ATI2") or code == four_cc("BC5U"):
        return RED_GREEN_RGTC2_FORMAT
    if code == four_cc("BC5S"):
        return SIGNED_RED_GREEN_RGTC2_FORMAT
    if code == four_cc("ETC1"):
        return RGB_ETC1_FORMAT
    raise Error(
        "DDS: the pixel format's four-character code "
        + hex(code)
        + " is not one this reader decodes; premultiplied DXT2 and DXT4,"
        " and other codes, are not ported"
    )


def uncompressed_bytes(bytes: List[UInt8]) -> Int:
    """Return how many bytes a texel of an uncompressed file takes, as
    three.js's `DDSLoader` tells by the pixel format's bit count and masks.

    Args:
        bytes: The file, its header whole.

    Returns:
        Four for 32-bit BGRA, three for 24-bit BGR, or zero for neither.
    """
    var bits = _u32(bytes, 88)
    var red = (_u32(bytes, 92) & 0xFF0000) != 0
    var green = (_u32(bytes, 96) & 0xFF00) != 0
    var blue = (_u32(bytes, 100) & 0xFF) != 0
    var alpha = (_u32(bytes, 104) & 0xFF000000) != 0
    var color = red and green and blue
    if bits == 32 and color and alpha:
        return 4
    if bits == 24 and color:
        return 3
    return 0


def format_of_dxgi(dxgi: Int) raises -> Tuple[CompressedFormat, ColorSpace]:
    """Return the format and color space a DX10 header's DXGI number names.

    Args:
        dxgi: The `DXGI_FORMAT` number.

    Returns:
        The format, and `SRGB` for an sRGB form or `LINEAR` otherwise.

    Raises:
        Error: If the number names a format this reader does not decode.
    """
    if dxgi == 71 or dxgi == 72:
        return (RGBA_S3TC_DXT1_FORMAT, _space(dxgi == 72))
    if dxgi == 74 or dxgi == 75:
        return (RGBA_S3TC_DXT3_FORMAT, _space(dxgi == 75))
    if dxgi == 77 or dxgi == 78:
        return (RGBA_S3TC_DXT5_FORMAT, _space(dxgi == 78))
    if dxgi == 80:
        return (RED_RGTC1_FORMAT, LINEAR)
    if dxgi == 81:
        return (SIGNED_RED_RGTC1_FORMAT, LINEAR)
    if dxgi == 83:
        return (RED_GREEN_RGTC2_FORMAT, LINEAR)
    if dxgi == 84:
        return (SIGNED_RED_GREEN_RGTC2_FORMAT, LINEAR)
    if dxgi == 95:
        return (RGB_BPTC_UNSIGNED_FORMAT, LINEAR)
    if dxgi == 96:
        return (RGB_BPTC_SIGNED_FORMAT, LINEAR)
    if dxgi == 98 or dxgi == 99:
        return (RGBA_BPTC_FORMAT, _space(dxgi == 99))
    raise Error(
        "DDS: DXGI format "
        + String(dxgi)
        + " is not one this reader decodes; only the block-compressed"
        " BC1 to BC7 formats are ported"
    )


def _space(srgb: Bool) -> ColorSpace:
    """Return `SRGB` if `srgb`, `LINEAR` otherwise."""
    if srgb:
        return SRGB
    return LINEAR


def _rgba(bytes: List[UInt8], at: Int, size: Int, texel: Int) -> List[UInt8]:
    """Return an uncompressed level as RGBA bytes, three.js's
    `loadARGBMip` or `loadRGBMip`.

    Args:
        bytes: The file.
        at: Where the level starts.
        size: Its bytes.
        texel: Four for BGRA, three for BGR.

    Returns:
        Red, green, blue and alpha for each texel; an opaque alpha for BGR.
    """
    var out = List[UInt8](capacity=size // texel * 4)
    for k in range(at, at + size, texel):  # pragma: no branch
        out.append(bytes[k + 2])
        out.append(bytes[k + 1])
        out.append(bytes[k])
        out.append(bytes[k + 3] if texel == 4 else 255)
    return out^


def read(bytes: List[UInt8]) raises -> CompressedImage:
    """Return every level of every face of a DDS file, as block bytes, or
    as RGBA bytes for an uncompressed file.

    Args:
        bytes: The whole file.

    Returns:
        The image; see `CompressedImage`.

    Raises:
        Error: If the magic, the header size or the pixel format's size is
            wrong; the dimensions are not positive; the pixel format
            names no format this reader decodes, by its code or by its bit
            masks; the size would decode to more than
            `MAX_DECODED_BYTES`; there are more levels than the size has; a cube
            lacks a face; a DX10 file is an array or is not a 2D texture;
            or the file ends before its last level.
    """
    if len(bytes) < 4 + HEADER_BYTES:
        raise Error("DDS: the file is shorter than its header")
    if _u32(bytes, 0) != four_cc("DDS "):
        raise Error("DDS: the file does not start with the magic 'DDS '")
    if _u32(bytes, 4) != HEADER_BYTES or _u32(bytes, 76) != 32:
        raise Error("DDS: the header or pixel format states the wrong size")
    var height = _u32(bytes, 12)
    var width = _u32(bytes, 16)
    if width <= 0 or height <= 0:
        raise Error("DDS: the dimensions must be positive")
    var levels = 1
    if (_u32(bytes, 8) & DDSD_MIPMAPCOUNT) != 0:
        levels = max(1, _u32(bytes, 28))
    if levels > chain_length(width, height):
        raise Error("DDS: the file names more levels than its size has")
    var faces = 1
    var caps2 = _u32(bytes, 112)
    if (caps2 & DDSCAPS2_CUBEMAP) != 0:
        if (caps2 & DDSCAPS2_ALL_FACES) != DDSCAPS2_ALL_FACES:
            raise Error("DDS: a cube must hold all six faces")
        faces = 6
    var code = _u32(bytes, 84)
    var start = 4 + HEADER_BYTES
    var format: CompressedFormat
    var space = LINEAR
    # Bytes a texel of an uncompressed file, or zero for a block format.
    var texel = 0
    if code == four_cc("DX10"):
        if len(bytes) < start + DX10_HEADER_BYTES:
            raise Error("DDS: the file is shorter than its DX10 header")
        var named = format_of_dxgi(_u32(bytes, start))
        format = named[0]
        space = named[1]
        # D3D10_RESOURCE_DIMENSION_TEXTURE2D is three.
        if _u32(bytes, start + 4) != 3:
            raise Error("DDS: only 2D textures are ported")
        if _u32(bytes, start + 12) != 1:
            raise Error("DDS: texture arrays are not ported")
        if (_u32(bytes, start + 8) & DDS_RESOURCE_MISC_TEXTURECUBE) != 0:
            faces = 6
        start += DX10_HEADER_BYTES
    else:
        try:
            format = format_of_four_cc(code)
        except e:
            texel = uncompressed_bytes(bytes)
            if texel == 0:
                raise e^
            format = RGBA_FORMAT
    check_decoded_size(width, height, format.is_float())
    var image = CompressedImage(width, height, format, space, faces, levels)
    var at = start
    for _ in range(faces):  # pragma: no branch
        for level in range(levels):  # pragma: no branch
            var width_at = image.level_width(level)
            var height_at = image.level_height(level)
            var size = level_bytes(width_at, height_at, format)
            if texel > 0:
                size = width_at * height_at * texel
            if size > len(bytes) - at:
                raise Error("DDS: the file ends before its last level")
            if texel > 0:
                image.mipmaps.append(_rgba(bytes, at, size, texel))
            else:
                image.mipmaps.append(List[UInt8](bytes[at : at + size]))
            at += size
    return image^
