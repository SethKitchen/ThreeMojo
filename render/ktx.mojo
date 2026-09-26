# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A KTX 1 file read into its compressed levels, from three.js
`examples/jsm/loaders/KTXLoader.js`.

`read(bytes)` returns a `CompressedImage`: every level of every face as
block bytes, the format, and the dimensions. `CompressedImage.texture`
decodes one level of one face into a `Texture`.

**The header.** Twelve identifier bytes, an endianness word, and twelve
words: the OpenGL type, format and internal format, the size, the array
length, the face count, the level count and the length of the key and
value data. The endianness word says whether the words are little- or
big-endian, and both are read. The internal format names the block layout.

**The data.** For each level, largest first: a word with one face's
size, then each face's blocks, each padded to four bytes. A cube holds all
six faces, +x, -x, +y, -y, +z, -z.

As in three.js, only compressed 2D files are read: an OpenGL type other
than zero, a depth, or an array is refused. The image's color space is
`SRGB` when the internal format is an sRGB one, and `LINEAR` otherwise.
"""

from render.compressed_texture import (
    R11_EAC_FORMAT,
    RED_GREEN_RGTC2_FORMAT,
    RED_RGTC1_FORMAT,
    RG11_EAC_FORMAT,
    RGB_BPTC_SIGNED_FORMAT,
    RGB_BPTC_UNSIGNED_FORMAT,
    RGB_ETC1_FORMAT,
    RGB_ETC2_FORMAT,
    RGB_PVRTC_2BPPV1_FORMAT,
    RGB_PVRTC_4BPPV1_FORMAT,
    RGBA_PVRTC_2BPPV1_FORMAT,
    RGBA_PVRTC_4BPPV1_FORMAT,
    RGB_S3TC_DXT1_FORMAT,
    RGBA_BPTC_FORMAT,
    RGBA_ETC2_EAC_FORMAT,
    RGBA_S3TC_DXT1_FORMAT,
    RGBA_S3TC_DXT3_FORMAT,
    RGBA_S3TC_DXT5_FORMAT,
    SIGNED_R11_EAC_FORMAT,
    SIGNED_RED_GREEN_RGTC2_FORMAT,
    SIGNED_RED_RGTC1_FORMAT,
    SIGNED_RG11_EAC_FORMAT,
    CompressedFormat,
    CompressedImage,
    chain_length,
    check_decoded_size,
    level_bytes,
)
from render.srgb import LINEAR, SRGB, ColorSpace

# The identifier, then the endianness word and twelve more.
comptime HEADER_BYTES = 64
# The endianness word as a little-endian file holds it.
comptime SAME_ENDIAN = 0x04030201
# And as a big-endian file holds it, read little-endian.
comptime SWAPPED_ENDIAN = 0x01020304


def identifier() -> List[UInt8]:
    """Return the twelve bytes every KTX 1 file starts with, «KTX 11».

    Returns:
        The identifier.
    """
    return [
        0xAB,
        0x4B,
        0x54,
        0x58,
        0x20,
        0x31,
        0x31,
        0xBB,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
    ]


def _word(bytes: List[UInt8], at: Int, big_endian: Bool) -> Int:
    """Return the word at `at` in the file's byte order; the caller has
    checked the length."""
    var b0 = Int(bytes[at])
    var b1 = Int(bytes[at + 1])
    var b2 = Int(bytes[at + 2])
    var b3 = Int(bytes[at + 3])
    if big_endian:
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)


def format_of_gl(internal: Int) raises -> Tuple[CompressedFormat, ColorSpace]:
    """Return the format and color space an OpenGL internal format names.

    Args:
        internal: The `glInternalFormat` word.

    Returns:
        The format, and `SRGB` for an sRGB form or `LINEAR` otherwise.

    Raises:
        Error: If the word names a format this reader does not decode:
            ASTC, ETC2 with punch-through alpha, or anything else.
    """
    # S3TC, and its sRGB forms from EXT_texture_sRGB.
    if internal == 0x83F0:
        return (RGB_S3TC_DXT1_FORMAT, LINEAR)
    if internal == 0x83F1:
        return (RGBA_S3TC_DXT1_FORMAT, LINEAR)
    if internal == 0x83F2:
        return (RGBA_S3TC_DXT3_FORMAT, LINEAR)
    if internal == 0x83F3:
        return (RGBA_S3TC_DXT5_FORMAT, LINEAR)
    if internal == 0x8C4C:
        return (RGB_S3TC_DXT1_FORMAT, SRGB)
    if internal == 0x8C4D:
        return (RGBA_S3TC_DXT1_FORMAT, SRGB)
    if internal == 0x8C4E:
        return (RGBA_S3TC_DXT3_FORMAT, SRGB)
    if internal == 0x8C4F:
        return (RGBA_S3TC_DXT5_FORMAT, SRGB)
    # RGTC.
    if internal == 0x8DBB:
        return (RED_RGTC1_FORMAT, LINEAR)
    if internal == 0x8DBC:
        return (SIGNED_RED_RGTC1_FORMAT, LINEAR)
    if internal == 0x8DBD:
        return (RED_GREEN_RGTC2_FORMAT, LINEAR)
    if internal == 0x8DBE:
        return (SIGNED_RED_GREEN_RGTC2_FORMAT, LINEAR)
    # BPTC.
    if internal == 0x8E8C:
        return (RGBA_BPTC_FORMAT, LINEAR)
    if internal == 0x8E8D:
        return (RGBA_BPTC_FORMAT, SRGB)
    if internal == 0x8E8E:
        return (RGB_BPTC_SIGNED_FORMAT, LINEAR)
    if internal == 0x8E8F:
        return (RGB_BPTC_UNSIGNED_FORMAT, LINEAR)
    # ETC1, ETC2 and EAC.
    if internal == 0x8D64:
        return (RGB_ETC1_FORMAT, LINEAR)
    if internal == 0x9274:
        return (RGB_ETC2_FORMAT, LINEAR)
    if internal == 0x9275:
        return (RGB_ETC2_FORMAT, SRGB)
    if internal == 0x9278:
        return (RGBA_ETC2_EAC_FORMAT, LINEAR)
    if internal == 0x9279:
        return (RGBA_ETC2_EAC_FORMAT, SRGB)
    if internal == 0x9270:
        return (R11_EAC_FORMAT, LINEAR)
    if internal == 0x9271:
        return (SIGNED_R11_EAC_FORMAT, LINEAR)
    if internal == 0x9272:
        return (RG11_EAC_FORMAT, LINEAR)
    if internal == 0x9273:
        return (SIGNED_RG11_EAC_FORMAT, LINEAR)
    # PVRTC1, from IMG_texture_compression_pvrtc.
    if internal == 0x8C00:
        return (RGB_PVRTC_4BPPV1_FORMAT, LINEAR)
    if internal == 0x8C01:
        return (RGB_PVRTC_2BPPV1_FORMAT, LINEAR)
    if internal == 0x8C02:
        return (RGBA_PVRTC_4BPPV1_FORMAT, LINEAR)
    if internal == 0x8C03:
        return (RGBA_PVRTC_2BPPV1_FORMAT, LINEAR)
    raise Error(
        "KTX: internal format "
        + hex(internal)
        + " is not one this reader decodes; ASTC and ETC2 with"
        " punch-through alpha are not ported"
    )


def read(bytes: List[UInt8]) raises -> CompressedImage:
    """Return every level of every face of a KTX 1 file, as block bytes.

    Args:
        bytes: The whole file.

    Returns:
        The image; see `CompressedImage`, whose levels are face-major
        although the file stores them level-major.

    Raises:
        Error: If the identifier or the endianness word is wrong; the file
            is not compressed, is 3D or 1D or an array, or has a face
            count other than one or six; the size would decode to more
            than `MAX_DECODED_BYTES`; the internal format is one this
            reader does not decode; there are more levels than the size
            has; a face's stated size is not its block grid's; or the file
            ends early.
    """
    if len(bytes) < HEADER_BYTES:
        raise Error("KTX: the file is shorter than its header")
    var magic = identifier()
    for index in range(12):  # pragma: no branch
        if bytes[index] != magic[index]:
            raise Error(
                "KTX: the file does not start with the KTX 1 identifier"
            )
    var order = _word(bytes, 12, False)
    var big_endian = order == SWAPPED_ENDIAN
    if order != SAME_ENDIAN and not big_endian:
        raise Error("KTX: the endianness word is neither order")
    if _word(bytes, 16, big_endian) != 0:
        raise Error(
            "KTX: only compressed files are ported; this one has an OpenGL type"
        )
    var named = format_of_gl(_word(bytes, 28, big_endian))
    var width = _word(bytes, 36, big_endian)
    var height = _word(bytes, 40, big_endian)
    if width <= 0 or height <= 0:
        raise Error(
            "KTX: only 2D textures are ported; the size must be positive"
        )
    if _word(bytes, 44, big_endian) != 0:
        raise Error("KTX: only 2D textures are ported; this one has a depth")
    if _word(bytes, 48, big_endian) != 0:
        raise Error("KTX: texture arrays are not ported")
    var faces = _word(bytes, 52, big_endian)
    if faces != 1 and faces != 6:
        raise Error("KTX: a file must have one face or six")
    check_decoded_size(width, height, named[0].is_float())
    var levels = max(1, _word(bytes, 56, big_endian))
    if levels > chain_length(width, height):
        raise Error("KTX: the file names more levels than its size has")
    var image = CompressedImage(
        width, height, named[0], named[1], faces, levels
    )
    for _ in range(faces * levels):  # pragma: no branch
        image.mipmaps.append(List[UInt8]())
    var at = HEADER_BYTES + _word(bytes, 60, big_endian)
    for level in range(levels):  # pragma: no branch
        if at > len(bytes) - 4:
            raise Error("KTX: the file ends before its last level")
        var size = _word(bytes, at, big_endian)
        at += 4
        var expected = level_bytes(
            image.level_width(level), image.level_height(level), named[0]
        )
        if size != expected:
            raise Error(
                "KTX: a level's stated size does not match its block grid"
            )
        for face in range(faces):  # pragma: no branch
            if size > len(bytes) - at:
                raise Error("KTX: the file ends before its last level")
            image.mipmaps[face * levels + level] = List[UInt8](
                bytes[at : at + size]
            )
            # Every block format's level is a multiple of eight bytes, so
            # the face and level padding to four is always zero.
            at += size
    return image^
