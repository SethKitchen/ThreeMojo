# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Block-compressed images decoded on the host, from three.js
`src/textures/CompressedTexture.js`.

A GPU samples a compressed texture as it is, decoding a block per fetch in
hardware. This project's textures are bytes read by two rasterizers that
share their arithmetic, and neither has a block decoder in its hot path.
So a compressed image is decoded once, here, into an ordinary `Texture`,
and sampled like any other. What is kept is the *file*: a DDS or KTX
payload lands as the texture it encodes, without an image decoder for a
format that was never meant to be decoded outside a GPU.

**The two S3TC formats, and nothing else yet.** BC1, three.js's
`RGB_S3TC_DXT1_Format` and `RGBA_S3TC_DXT1_Format`, packs a 4x4 block into
eight bytes: two colors in RGB565 and a two-bit index per texel that picks
one of them or one of two blends between them. Which two blends depends on
which color sorts first, and the other order trades one blend for a
transparent black, which is the one-bit alpha the RGBA variant reads and
the RGB variant reads as black. BC3, `RGBA_S3TC_DXT5_Format`, puts a
second eight bytes in front: two alpha bytes and a three-bit index per
texel over six blends, or four blends and the two ends. Its color half is
always read in the four-color order, whatever the two colors' sort.

The 565 channels widen to eight bits the way the hardware does, by copying
the top bits into the bottom: `(r << 3) | (r >> 2)`. The blends round to
nearest, as the reference decoder rounds them.

**Sizes need not be multiples of four.** A block grid covers the image and
the last row and column of blocks hang off the edge; the texels past the
edge are decoded and dropped, as a GPU stores and never shows them.
"""

from render.srgb import SRGB, ColorSpace
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    Alpha,
    Filter,
    Texture,
    Wrap,
)


@fieldwise_init
struct CompressedFormat(Equatable, ImplicitlyCopyable, Writable):
    """Which block layout a compressed payload has, as a type rather than a
    bare int.

    See `core.object3d.NodeId` for why these are wrapped. The type does
    not stop `CompressedFormat(9)`, so `compressed_texture` asks `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three formats there are."""
        return (
            self == RGB_S3TC_DXT1_FORMAT
            or self == RGBA_S3TC_DXT1_FORMAT
            or self == RGBA_S3TC_DXT5_FORMAT
        )

    def block_bytes(self) -> Int:
        """Return how many bytes one 4x4 block takes: eight for BC1,
        sixteen for BC3, and eight for a format that is neither, which
        `compressed_texture` has refused before asking."""
        if self == RGBA_S3TC_DXT5_FORMAT:
            return 16
        return 8


# BC1 with the transparent index read as opaque black: three.js's
# `RGB_S3TC_DXT1_Format`.
comptime RGB_S3TC_DXT1_FORMAT = CompressedFormat(0)
# BC1 with the transparent index read as transparent black: three.js's
# `RGBA_S3TC_DXT1_Format`.
comptime RGBA_S3TC_DXT1_FORMAT = CompressedFormat(1)
# BC3: an eight-byte alpha block before each BC1 color block, and the
# color block always read in its four-color order: three.js's
# `RGBA_S3TC_DXT5_Format`.
comptime RGBA_S3TC_DXT5_FORMAT = CompressedFormat(2)

# A block is four texels square.
comptime BLOCK = 4


def widen5(bits: Int) -> UInt8:
    """Return a five-bit channel as eight bits, top bits copied down."""
    return UInt8((bits << 3) | (bits >> 2))


def widen6(bits: Int) -> UInt8:
    """Return a six-bit channel as eight bits, top bits copied down."""
    return UInt8((bits << 2) | (bits >> 4))


def unpack565(word: Int) -> List[UInt8]:
    """Return an RGB565 word as three eight-bit channels.

    Args:
        word: The sixteen-bit color, red in the top five bits.

    Returns:
        Red, green and blue.
    """
    return [
        widen5((word >> 11) & 0x1F),
        widen6((word >> 5) & 0x3F),
        widen5(word & 0x1F),
    ]


def _blend(a: UInt8, b: UInt8, weight_a: Int, weight_b: Int) -> UInt8:
    """Return `(a * weight_a + b * weight_b) / (weight_a + weight_b)`,
    rounded to nearest, as the reference decoder blends."""
    var total = weight_a + weight_b
    return UInt8((Int(a) * weight_a + Int(b) * weight_b + total // 2) // total)


def _color_block(data: List[UInt8], at: Int, four_colors: Bool) -> List[UInt8]:
    """Return the sixteen texels of one BC1 color block as RGBA bytes.

    Args:
        data: The payload.
        at: Where the block's eight bytes begin.
        four_colors: True to read the block in its four-color order
            whatever the two colors' sort, as BC3's color half is read.

    Returns:
        Sixty-four bytes, row-major from the block's top left.
    """
    var first = Int(data[at]) | (Int(data[at + 1]) << 8)
    var second = Int(data[at + 2]) | (Int(data[at + 3]) << 8)
    var c0 = unpack565(first)
    var c1 = unpack565(second)
    # The palette: the two colors, then their two blends, or one blend
    # and transparent black.
    var palette = List[UInt8]()
    for channel in range(3):  # pragma: no branch
        palette.append(c0[channel])
    palette.append(255)
    for channel in range(3):  # pragma: no branch
        palette.append(c1[channel])
    palette.append(255)
    if four_colors or first > second:
        for channel in range(3):  # pragma: no branch
            palette.append(_blend(c0[channel], c1[channel], 2, 1))
        palette.append(255)
        for channel in range(3):  # pragma: no branch
            palette.append(_blend(c0[channel], c1[channel], 1, 2))
        palette.append(255)
    else:
        for channel in range(3):  # pragma: no branch
            palette.append(_blend(c0[channel], c1[channel], 1, 1))
        palette.append(255)
        for _ in range(4):  # pragma: no branch
            palette.append(0)
    var out = List[UInt8]()
    out.reserve(BLOCK * BLOCK * 4)
    for row in range(BLOCK):  # pragma: no branch
        var bits = Int(data[at + 4 + row])
        for column in range(BLOCK):  # pragma: no branch
            var index = (bits >> (column * 2)) & 3
            for channel in range(4):  # pragma: no branch
                out.append(palette[index * 4 + channel])
    return out^


def _alpha_block(data: List[UInt8], at: Int) -> List[UInt8]:
    """Return the sixteen alphas of one BC3 alpha block.

    Args:
        data: The payload.
        at: Where the block's eight bytes begin.

    Returns:
        Sixteen bytes, row-major from the block's top left.
    """
    var a0 = data[at]
    var a1 = data[at + 1]
    var palette = List[UInt8]()
    palette.append(a0)
    palette.append(a1)
    if a0 > a1:
        for step in range(1, 7):  # pragma: no branch
            palette.append(_blend(a0, a1, 7 - step, step))
    else:
        for step in range(1, 5):  # pragma: no branch
            palette.append(_blend(a0, a1, 5 - step, step))
        palette.append(0)
        palette.append(255)
    # Forty-eight bits of three-bit indices, least significant first.
    var bits = 0
    for byte in range(6):  # pragma: no branch
        bits |= Int(data[at + 2 + byte]) << (byte * 8)
    var out = List[UInt8]()
    for texel in range(BLOCK * BLOCK):  # pragma: no branch
        out.append(palette[(bits >> (texel * 3)) & 7])
    return out^


def decode_s3tc(
    width: Int, height: Int, data: List[UInt8], format: CompressedFormat
) raises -> List[UInt8]:
    """Return a BC1 or BC3 payload as RGBA bytes, row-major from the top.

    Args:
        width: The image's width in texels; need not be a multiple of four.
        height: Its height.
        data: The blocks, row-major, `format.block_bytes()` each, covering
            the image rounded up to whole blocks.
        format: Which of the three layouts.

    Returns:
        `width * height * 4` bytes.

    Raises:
        Error: If the dimensions are not positive, the format is none of
            the three, or the payload's length is not the block grid's.
    """
    if width <= 0 or height <= 0:
        raise Error("Texture dimensions must be positive")
    if not format.is_valid():
        raise Error(
            "A compressed format must be RGB_S3TC_DXT1_FORMAT,"
            " RGBA_S3TC_DXT1_FORMAT or RGBA_S3TC_DXT5_FORMAT"
        )
    var across = (width + BLOCK - 1) // BLOCK
    var down = (height + BLOCK - 1) // BLOCK
    if len(data) != across * down * format.block_bytes():
        raise Error("Compressed payload length does not match the dimensions")
    var pixels = List[UInt8](length=width * height * 4, fill=0)
    for block_row in range(down):  # pragma: no branch
        for block_column in range(across):  # pragma: no branch
            var at = (block_row * across + block_column) * format.block_bytes()
            var colors: List[UInt8]
            var alphas = List[UInt8]()
            if format == RGBA_S3TC_DXT5_FORMAT:
                alphas = _alpha_block(data, at)
                colors = _color_block(data, at + 8, True)
            else:
                colors = _color_block(data, at, False)
            for row in range(BLOCK):  # pragma: no branch
                var y = block_row * BLOCK + row
                if y >= height:
                    continue
                for column in range(BLOCK):  # pragma: no branch
                    var x = block_column * BLOCK + column
                    if x >= width:
                        continue
                    var texel = row * BLOCK + column
                    var slot = (y * width + x) * 4
                    pixels[slot] = colors[texel * 4]
                    pixels[slot + 1] = colors[texel * 4 + 1]
                    pixels[slot + 2] = colors[texel * 4 + 2]
                    var alpha = colors[texel * 4 + 3]
                    if format == RGBA_S3TC_DXT5_FORMAT:
                        alpha = alphas[texel]
                    elif format == RGB_S3TC_DXT1_FORMAT:
                        # The transparent index is opaque black here.
                        alpha = 255
                    pixels[slot + 3] = alpha
    return pixels^


def compressed_texture(
    width: Int,
    height: Int,
    data: List[UInt8],
    format: CompressedFormat,
    wrap: Wrap = CLAMP,
    filter: Filter = BILINEAR,
    color_space: ColorSpace = SRGB,
    mipmapped: Bool = False,
    alpha: Alpha = COVERAGE,
) raises -> Texture:
    """Return a texture decoded from a block-compressed payload, three.js's
    `CompressedTexture` at its defaults.

    The defaults are three.js's own for the class: edges clamped, filtered
    but with no chain, since a compressed file usually carries its own
    levels and three.js does not generate them. Pass `mipmapped=True` to
    build the chain from the decoded image instead; a file's own smaller
    levels are not read.

    Args:
        width: The image's width in texels.
        height: Its height.
        data: The blocks; see `decode_s3tc`.
        format: `RGB_S3TC_DXT1_FORMAT`, `RGBA_S3TC_DXT1_FORMAT` or
            `RGBA_S3TC_DXT5_FORMAT`.
        wrap: How coordinates outside the unit square are resolved.
        filter: `NEAREST` or `BILINEAR`.
        color_space: `SRGB`, the default, or `LINEAR`.
        mipmapped: Build the chain of halved copies from the decoded image.
        alpha: `COVERAGE` or `IGNORED`; see `render.texture`.

    Returns:
        The texture.

    Raises:
        Error: Everything `decode_s3tc` raises, or a wrap, filter, color
            space or alpha mode that is none of the named values.
    """
    return Texture(
        width,
        height,
        decode_s3tc(width, height, data, format),
        wrap,
        filter,
        color_space,
        mipmapped,
        alpha,
    )
