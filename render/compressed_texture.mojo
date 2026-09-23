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
and sampled like any other.

**This is a block decoder; the containers are elsewhere.** The caller
supplies the width, the height, the format and exactly one level's block
bytes. `render.dds`, `render.ktx` and `render.ktx2` read the three
container files three.js reads, and hand one level of one face here
through `CompressedImage`.

**It saves storage and not memory.** The asset stays small on disk, and
`compressed_texture` expands it into an ordinary `Texture` at load time,
so nothing downstream pays less bandwidth for it than for any other
image. Sampling compressed blocks on the device would be a different
feature, and it would need the block rule in both rasterizers.

Because the dimensions come from outside, the decoders bound what they
will allocate; see `MAX_DECODED_BYTES`.

**The S3TC formats.** BC1, three.js's `RGB_S3TC_DXT1_Format` and
`RGBA_S3TC_DXT1_Format`, packs a 4x4 block into eight bytes: two colors
in RGB565 and a two-bit index per texel that picks one of them or one of
two blends between them. Which two blends depends on which color sorts
first, and the other order trades one blend for a transparent black,
which is the one-bit alpha the RGBA variant reads and the RGB variant
reads as black. BC2, `RGBA_S3TC_DXT3_Format`, puts eight bytes of
explicit four-bit alphas in front of a color block. BC3,
`RGBA_S3TC_DXT5_Format`, puts two alpha bytes and a three-bit index per
texel over six blends, or four blends and the two ends. The color half of
BC2 and BC3 is always read in the four-color order, whatever the two
colors' sort.

The 565 channels widen to eight bits the way the hardware does, by copying
the top bits into the bottom: `(r << 3) | (r >> 2)`. The blends round to
nearest, as the reference decoder rounds them.

**The RGTC formats are BC3's alpha block as a channel.** BC4,
`RED_RGTC1_Format`, is one such block and gives red; BC5,
`RED_GREEN_RGTC2_Format`, is two and gives red and green. Blue is zero
and alpha one, as WebGL samples a red or a red-green texture. The signed
forms read the two ends as signed bytes, -128 as -127, and give floats
from -1 to 1, which no byte holds.

**BPTC, ETC and EAC are in their own modules.** `render.bptc` decodes
BC6H and BC7, and `render.etc` decodes ETC1, ETC2 and EAC. Formats whose
texels a byte cannot hold -- BC6H, the signed RGTC forms and the
eleven-bit EAC forms -- decode to floats, and their texture is a float
texture. See `CompressedFormat.is_float`.

**Sizes need not be multiples of four.** A block grid covers the image and
the last row and column of blocks hang off the edge; the texels past the
edge are decoded and dropped, as a GPU stores and never shows them.
"""

from render.bptc import BptcTables, bc6h_block, bc7_block
from render.etc import (
    EtcTables,
    eac_alpha_block,
    eac_r11_block,
    etc2_color_block,
)
from render.srgb import LINEAR, SRGB, ColorSpace
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    FLOAT_TYPE,
    UNSIGNED_BYTE_TYPE,
    Alpha,
    Filter,
    TexelType,
    Texture,
    Wrap,
    float_texture,
)

# The most bytes a decode may produce: one gibibyte, which is a 16384 by
# 16384 RGBA image. The width and the height come from a file, and the
# decoded size is their product -- a header that says a hundred thousand
# each asks for forty gigabytes, and the honest answer is to refuse it by
# name rather than to fail inside an allocator. Well past any texture a
# GPU will take: `GL_MAX_TEXTURE_SIZE` is 16384 on current desktop parts.
comptime MAX_DECODED_BYTES = 1 << 30


@fieldwise_init
struct CompressedFormat(Equatable, ImplicitlyCopyable, Writable):
    """Which block layout a compressed payload has, as a type rather than a
    bare int.

    See `core.object3d.NodeId` for why these are wrapped. The type does
    not stop `CompressedFormat(99)`, so `compressed_texture` asks
    `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the eighteen formats there are."""
        return self.value >= 0 and self.value <= 17

    def is_s3tc(self) -> Bool:
        """Return True for BC1, BC2 and BC3, the formats `decode_s3tc`
        reads."""
        return self.value >= 0 and self.value <= 3

    def is_float(self) -> Bool:
        """Return True if a byte cannot hold this format's texels, so it
        decodes to floats: BC6H, the signed RGTC forms and every
        eleven-bit EAC form."""
        return (
            self == SIGNED_RED_RGTC1_FORMAT
            or self == SIGNED_RED_GREEN_RGTC2_FORMAT
            or self == RGB_BPTC_UNSIGNED_FORMAT
            or self == RGB_BPTC_SIGNED_FORMAT
            or (self.value >= 14 and self.value <= 17)
        )

    def is_color(self) -> Bool:
        """Return True if this format holds bytes of color, the formats an
        sRGB file can hold: S3TC, BC7 and ETC."""
        return self.is_s3tc() or (self.value >= 10 and self.value <= 13)

    def block_bytes(self) -> Int:
        """Return how many bytes one 4x4 block takes: eight for BC1, BC4,
        ETC1, ETC2 RGB and R11, sixteen for the rest, including a format
        that is none of these, which `compressed_texture` has refused
        before asking."""
        if self._half_block():
            return 8
        return 16

    def _half_block(self) -> Bool:
        """Return True for the formats whose block is eight bytes."""
        return (
            self == RGB_S3TC_DXT1_FORMAT
            or self == RGBA_S3TC_DXT1_FORMAT
            or self == RED_RGTC1_FORMAT
            or self == SIGNED_RED_RGTC1_FORMAT
            or self == RGB_ETC1_FORMAT
            or self == RGB_ETC2_FORMAT
            or self == R11_EAC_FORMAT
            or self == SIGNED_R11_EAC_FORMAT
        )

    def write_to(self, mut writer: Some[Writer]):
        """Write the format's three.js name.

        Args:
            writer: Where to write it.
        """
        var names: List[String] = [
            "RGB_S3TC_DXT1_Format",
            "RGBA_S3TC_DXT1_Format",
            "RGBA_S3TC_DXT5_Format",
            "RGBA_S3TC_DXT3_Format",
            "RED_RGTC1_Format",
            "SIGNED_RED_RGTC1_Format",
            "RED_GREEN_RGTC2_Format",
            "SIGNED_RED_GREEN_RGTC2_Format",
            "RGB_BPTC_UNSIGNED_Format",
            "RGB_BPTC_SIGNED_Format",
            "RGBA_BPTC_Format",
            "RGB_ETC1_Format",
            "RGB_ETC2_Format",
            "RGBA_ETC2_EAC_Format",
            "R11_EAC_Format",
            "SIGNED_R11_EAC_Format",
            "RG11_EAC_Format",
            "SIGNED_RG11_EAC_Format",
        ]
        if self.is_valid():
            writer.write(names[self.value])
        else:
            writer.write("CompressedFormat(", self.value, ")")


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
# BC2: sixteen explicit four-bit alphas before each color block:
# three.js's `RGBA_S3TC_DXT3_Format`.
comptime RGBA_S3TC_DXT3_FORMAT = CompressedFormat(3)
# BC4: one BC3 alpha block, read as red: `RED_RGTC1_Format`.
comptime RED_RGTC1_FORMAT = CompressedFormat(4)
# BC4 signed, as floats: `SIGNED_RED_RGTC1_Format`.
comptime SIGNED_RED_RGTC1_FORMAT = CompressedFormat(5)
# BC5: two BC3 alpha blocks, red then green: `RED_GREEN_RGTC2_Format`.
comptime RED_GREEN_RGTC2_FORMAT = CompressedFormat(6)
# BC5 signed, as floats: `SIGNED_RED_GREEN_RGTC2_Format`.
comptime SIGNED_RED_GREEN_RGTC2_FORMAT = CompressedFormat(7)
# BC6H unsigned half-float RGB, as floats: `RGB_BPTC_UNSIGNED_Format`.
comptime RGB_BPTC_UNSIGNED_FORMAT = CompressedFormat(8)
# BC6H signed half-float RGB, as floats: `RGB_BPTC_SIGNED_Format`.
comptime RGB_BPTC_SIGNED_FORMAT = CompressedFormat(9)
# BC7 eight-bit RGBA: `RGBA_BPTC_Format`.
comptime RGBA_BPTC_FORMAT = CompressedFormat(10)
# ETC1 RGB: `RGB_ETC1_Format`.
comptime RGB_ETC1_FORMAT = CompressedFormat(11)
# ETC2 RGB, with the T, H and planar modes: `RGB_ETC2_Format`.
comptime RGB_ETC2_FORMAT = CompressedFormat(12)
# An eight-bit EAC alpha block before each ETC2 color block:
# `RGBA_ETC2_EAC_Format`.
comptime RGBA_ETC2_EAC_FORMAT = CompressedFormat(13)
# One eleven-bit EAC block, as a float red: `R11_EAC_Format`.
comptime R11_EAC_FORMAT = CompressedFormat(14)
# The same, signed: `SIGNED_R11_EAC_Format`.
comptime SIGNED_R11_EAC_FORMAT = CompressedFormat(15)
# Two eleven-bit EAC blocks, red then green: `RG11_EAC_Format`.
comptime RG11_EAC_FORMAT = CompressedFormat(16)
# The same, signed: `SIGNED_RG11_EAC_Format`.
comptime SIGNED_RG11_EAC_FORMAT = CompressedFormat(17)

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
            whatever the two colors' sort, as BC2's and BC3's color half
            is read.

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


def _alpha_indices(data: List[UInt8], at: Int) -> Int:
    """Return the forty-eight bits of three-bit indices of a BC3 alpha or
    an RGTC block, least significant first."""
    var bits = 0
    for byte in range(6):  # pragma: no branch
        bits |= Int(data[at + 2 + byte]) << (byte * 8)
    return bits


def _alpha_block(data: List[UInt8], at: Int) -> List[UInt8]:
    """Return the sixteen alphas of one BC3 alpha block, or the sixteen
    reds or greens of an unsigned RGTC block.

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
    var bits = _alpha_indices(data, at)
    var out = List[UInt8]()
    for texel in range(BLOCK * BLOCK):  # pragma: no branch
        out.append(palette[(bits >> (texel * 3)) & 7])
    return out^


def _signed_byte(byte: UInt8) -> Int:
    """Return a byte read as a signed RGTC end: -128 is read as -127."""
    var value = Int(byte) - ((Int(byte) & 0x80) << 1)
    return max(value, -127)


def signed_rgtc_block(data: List[UInt8], at: Int) -> List[Float32]:
    """Return the sixteen values of one signed RGTC block, from -1 to 1.

    The two ends are signed bytes. If the first is above the second there
    are six blends between them; if not, four blends and then -1 and 1.
    The blends are worked in floats, as the specification works them.

    Args:
        data: The payload.
        at: Where the block's eight bytes begin.

    Returns:
        Sixteen floats, row-major from the block's top left.
    """
    var r0 = Float32(_signed_byte(data[at])) / 127
    var r1 = Float32(_signed_byte(data[at + 1])) / 127
    var palette: List[Float32] = [r0, r1]
    if r0 > r1:
        for step in range(1, 7):  # pragma: no branch
            palette.append((r0 * Float32(7 - step) + r1 * Float32(step)) / 7)
    else:
        for step in range(1, 5):  # pragma: no branch
            palette.append((r0 * Float32(5 - step) + r1 * Float32(step)) / 5)
        palette.append(-1)
        palette.append(1)
    var bits = _alpha_indices(data, at)
    var out = List[Float32]()
    for texel in range(BLOCK * BLOCK):  # pragma: no branch
        out.append(palette[(bits >> (texel * 3)) & 7])
    return out^


def _explicit_alpha_block(data: List[UInt8], at: Int) -> List[UInt8]:
    """Return the sixteen alphas of one BC2 alpha block: four bits each,
    widened by copying, the first texel in the low half of the first byte.
    """
    var out = List[UInt8]()
    for texel in range(BLOCK * BLOCK):  # pragma: no branch
        var nibble = (Int(data[at + texel // 2]) >> ((texel & 1) * 4)) & 0xF
        out.append(UInt8(nibble * 17))
    return out^


struct _Tables(Movable):
    """Every fixed table a block decoder reads, built once per image."""

    var etc: EtcTables
    var bptc: BptcTables

    def __init__(out self):
        """Build the tables."""
        self.etc = EtcTables()
        self.bptc = BptcTables()


def _byte_block(
    data: List[UInt8], at: Int, format: CompressedFormat, tables: _Tables
) -> List[UInt8]:
    """Return one block of a byte format as RGBA bytes.

    Args:
        data: The payload.
        at: Where the block begins.
        format: A valid format whose `is_float` is False.
        tables: The fixed tables.

    Returns:
        Sixty-four bytes, row-major from the block's top left.
    """
    if format == RGB_S3TC_DXT1_FORMAT:
        var colors = _color_block(data, at, False)
        # The transparent index is opaque black here.
        for texel in range(BLOCK * BLOCK):  # pragma: no branch
            colors[texel * 4 + 3] = 255
        return colors^
    if format == RGBA_S3TC_DXT1_FORMAT:
        return _color_block(data, at, False)
    if format == RGBA_S3TC_DXT5_FORMAT or format == RGBA_S3TC_DXT3_FORMAT:
        var alphas: List[UInt8]
        if format == RGBA_S3TC_DXT5_FORMAT:
            alphas = _alpha_block(data, at)
        else:
            alphas = _explicit_alpha_block(data, at)
        var colors = _color_block(data, at + 8, True)
        for texel in range(BLOCK * BLOCK):  # pragma: no branch
            colors[texel * 4 + 3] = alphas[texel]
        return colors^
    if format == RED_RGTC1_FORMAT or format == RED_GREEN_RGTC2_FORMAT:
        var out = List[UInt8](length=64, fill=0)
        var red = _alpha_block(data, at)
        var green = List[UInt8](length=16, fill=0)
        if format == RED_GREEN_RGTC2_FORMAT:
            green = _alpha_block(data, at + 8)
        for texel in range(BLOCK * BLOCK):  # pragma: no branch
            out[texel * 4] = red[texel]
            out[texel * 4 + 1] = green[texel]
            out[texel * 4 + 3] = 255
        return out^
    if format == RGBA_BPTC_FORMAT:
        return bc7_block(data, at, tables.bptc)
    if format == RGBA_ETC2_EAC_FORMAT:
        var alphas = eac_alpha_block(data, at, tables.etc)
        var colors = etc2_color_block(data, at + 8, tables.etc)
        for texel in range(BLOCK * BLOCK):  # pragma: no branch
            colors[texel * 4 + 3] = alphas[texel]
        return colors^
    # ETC1 and ETC2 RGB: an ETC1 block is an ETC2 block that never
    # overflows.
    return etc2_color_block(data, at, tables.etc)


def _float_block(
    data: List[UInt8], at: Int, format: CompressedFormat, tables: _Tables
) -> List[Float32]:
    """Return one block of a float format as RGBA floats.

    Args:
        data: The payload.
        at: Where the block begins.
        format: A valid format whose `is_float` is True.
        tables: The fixed tables.

    Returns:
        Sixty-four floats, row-major from the block's top left.
    """
    if format == RGB_BPTC_UNSIGNED_FORMAT or format == RGB_BPTC_SIGNED_FORMAT:
        return bc6h_block(
            data, at, format == RGB_BPTC_SIGNED_FORMAT, tables.bptc
        )
    var red: List[Float32]
    var green = List[Float32](length=16, fill=0)
    if (
        format == SIGNED_RED_RGTC1_FORMAT
        or format == SIGNED_RED_GREEN_RGTC2_FORMAT
    ):
        red = signed_rgtc_block(data, at)
        if format == SIGNED_RED_GREEN_RGTC2_FORMAT:
            green = signed_rgtc_block(data, at + 8)
    else:
        var signed = (
            format == SIGNED_R11_EAC_FORMAT or format == SIGNED_RG11_EAC_FORMAT
        )
        red = eac_r11_block(data, at, signed, tables.etc)
        if format == RG11_EAC_FORMAT or format == SIGNED_RG11_EAC_FORMAT:
            green = eac_r11_block(data, at + 8, signed, tables.etc)
    var out = List[Float32](length=64, fill=0)
    for texel in range(BLOCK * BLOCK):  # pragma: no branch
        out[texel * 4] = red[texel]
        out[texel * 4 + 1] = green[texel]
        out[texel * 4 + 3] = 1
    return out^


struct DecodedBlocks(Movable):
    """A compressed payload decoded to RGBA: bytes or floats.

    A format whose `is_float` is True fills `floats`; any other fills
    `pixels`. The other list is empty.
    """

    var width: Int
    """The image's width in texels."""
    var height: Int
    """Its height."""
    var texel_type: TexelType
    """`UNSIGNED_BYTE_TYPE` or `FLOAT_TYPE`."""
    var pixels: List[UInt8]
    """Row-major RGBA bytes from the top, for a byte format."""
    var floats: List[Float32]
    """Row-major RGBA floats from the top, for a float format."""

    def __init__(out self, width: Int, height: Int, texel_type: TexelType):
        """Make an empty decode of the given size and texel type.

        Args:
            width: The image's width in texels.
            height: Its height.
            texel_type: `UNSIGNED_BYTE_TYPE` or `FLOAT_TYPE`.
        """
        self.width = width
        self.height = height
        self.texel_type = texel_type
        self.pixels = List[UInt8]()
        self.floats = List[Float32]()

    def take_pixels(deinit self) -> List[UInt8]:
        """Return the bytes, ending the decode.

        Returns:
            `pixels`.
        """
        return self.pixels^

    def take_floats(deinit self) -> List[Float32]:
        """Return the floats, ending the decode.

        Returns:
            `floats`.
        """
        return self.floats^


def check_decoded_size(width: Int, height: Int, floats: Bool) raises:
    """Refuse positive dimensions that would decode to more than
    `MAX_DECODED_BYTES`.

    Divided rather than multiplied, so that the check itself cannot be
    the thing that overflows. The containers call it on the sizes a
    header states, before they multiply them.

    Args:
        width: The image's width in texels, positive.
        height: Its height, positive.
        floats: True if the image decodes to four floats a texel rather
            than four bytes.

    Raises:
        Error: If the decoded image would be too large.
    """
    var texel_bytes = 4
    if floats:
        texel_bytes = 16
    if width > MAX_DECODED_BYTES // texel_bytes // height:
        raise Error(
            "A compressed image would decode to more than"
            " MAX_DECODED_BYTES: the dimensions are refused rather than"
            " allocated"
        )


def _check_payload(
    width: Int, height: Int, data: List[UInt8], format: CompressedFormat
) raises:
    """Refuse dimensions, a format or a payload that cannot be decoded.

    Args:
        width: The image's width in texels.
        height: Its height.
        data: The blocks.
        format: The format.

    Raises:
        Error: If the dimensions are not positive, their product would
            decode to more than `MAX_DECODED_BYTES`, the format is none of
            the named ones, or the payload's length is not the block
            grid's.
    """
    if width <= 0 or height <= 0:
        raise Error("Texture dimensions must be positive")
    if not format.is_valid():
        raise Error(
            "A compressed format must be one of the named formats, not "
            + String(format)
        )
    check_decoded_size(width, height, format.is_float())
    var across = (width + BLOCK - 1) // BLOCK
    var down = (height + BLOCK - 1) // BLOCK
    if len(data) != across * down * format.block_bytes():
        raise Error("Compressed payload length does not match the dimensions")


def decode_compressed(
    width: Int, height: Int, data: List[UInt8], format: CompressedFormat
) raises -> DecodedBlocks:
    """Return a block-compressed payload as RGBA bytes or floats.

    Args:
        width: The image's width in texels; need not be a multiple of four.
        height: Its height.
        data: The blocks, row-major, `format.block_bytes()` each, covering
            the image rounded up to whole blocks.
        format: Which layout.

    Returns:
        The texels, in `pixels` for a byte format and `floats` for a float
        one.

    Raises:
        Error: If the dimensions are not positive, their product would
            decode to more than `MAX_DECODED_BYTES`, the format is none of
            the named ones, or the payload's length is not the block grid's.
    """
    _check_payload(width, height, data, format)
    var tables = _Tables()
    var across = (width + BLOCK - 1) // BLOCK
    var down = (height + BLOCK - 1) // BLOCK
    var result: DecodedBlocks
    if format.is_float():
        result = DecodedBlocks(width, height, FLOAT_TYPE)
        result.floats = List[Float32](length=width * height * 4, fill=0)
    else:
        result = DecodedBlocks(width, height, UNSIGNED_BYTE_TYPE)
        result.pixels = List[UInt8](length=width * height * 4, fill=0)
    for block_row in range(down):  # pragma: no branch
        for block_column in range(across):  # pragma: no branch
            var at = (block_row * across + block_column) * format.block_bytes()
            var texels_f = List[Float32]()
            var texels_b = List[UInt8]()
            if format.is_float():
                texels_f = _float_block(data, at, format, tables)
            else:
                texels_b = _byte_block(data, at, format, tables)
            for row in range(BLOCK):  # pragma: no branch
                var y = block_row * BLOCK + row
                if y >= height:
                    continue
                for column in range(BLOCK):  # pragma: no branch
                    var x = block_column * BLOCK + column
                    if x >= width:
                        continue
                    var texel = (row * BLOCK + column) * 4
                    var slot = (y * width + x) * 4
                    for channel in range(4):  # pragma: no branch
                        if format.is_float():
                            result.floats[slot + channel] = texels_f[
                                texel + channel
                            ]
                        else:
                            result.pixels[slot + channel] = texels_b[
                                texel + channel
                            ]
    return result^


def decode_s3tc(
    width: Int, height: Int, data: List[UInt8], format: CompressedFormat
) raises -> List[UInt8]:
    """Return a BC1, BC2 or BC3 payload as RGBA bytes, row-major from the
    top.

    Args:
        width: The image's width in texels; need not be a multiple of four.
        height: Its height.
        data: The blocks, row-major, `format.block_bytes()` each, covering
            the image rounded up to whole blocks.
        format: Which of the four S3TC layouts.

    Returns:
        `width * height * 4` bytes.

    Raises:
        Error: If the format is not an S3TC one, and everything
            `decode_compressed` raises.
    """
    if not format.is_s3tc():
        raise Error(
            "decode_s3tc reads RGB_S3TC_DXT1_FORMAT, RGBA_S3TC_DXT1_FORMAT,"
            " RGBA_S3TC_DXT3_FORMAT or RGBA_S3TC_DXT5_FORMAT; use"
            " decode_compressed for the others"
        )
    return decode_compressed(width, height, data, format).take_pixels()


def compressed_texture(
    width: Int,
    height: Int,
    data: List[UInt8],
    format: CompressedFormat,
    wrap: Wrap = CLAMP,
    filter: Filter = BILINEAR,
    color_space: Optional[ColorSpace] = None,
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

    A color format is `SRGB` unless you say `LINEAR`. Every other format
    holds data, not color, and is `LINEAR`. A float format gives a float
    texture.

    Args:
        width: The image's width in texels.
        height: Its height.
        data: The blocks; see `decode_compressed`.
        format: One of the named formats.
        wrap: How coordinates outside the unit square are resolved.
        filter: `NEAREST` or `BILINEAR`.
        color_space: `SRGB` or `LINEAR`, or nothing for the format's own:
            `SRGB` for a color format, `LINEAR` for the rest.
        mipmapped: Build the chain of halved copies from the decoded image.
        alpha: `COVERAGE` or `IGNORED`; see `render.texture`.

    Returns:
        The texture.

    Raises:
        Error: Everything `decode_compressed` raises; `SRGB` for a format
            that is not a color format; or a wrap, filter, color space or
            alpha mode that is none of the named values.
    """
    var decoded = decode_compressed(width, height, data, format)
    var space = LINEAR
    if format.is_color():
        space = SRGB
    if Bool(color_space):
        space = color_space.value()
    if space == SRGB and not format.is_color():
        raise Error(
            String(format)
            + " holds data, not color: its texture must be LINEAR, not SRGB"
        )
    if format.is_float():
        return float_texture(
            width,
            height,
            decoded^.take_floats(),
            wrap,
            filter,
            mipmapped,
            alpha,
        )
    return Texture(
        width,
        height,
        decoded^.take_pixels(),
        wrap,
        filter,
        space,
        mipmapped,
        alpha,
    )


def level_bytes(width: Int, height: Int, format: CompressedFormat) -> Int:
    """Return how many bytes the blocks of one level take.

    Args:
        width: The level's width in texels.
        height: Its height.
        format: The block layout.

    Returns:
        The block grid's size in bytes, rounded up to whole blocks.
    """
    return (
        ((width + BLOCK - 1) // BLOCK)
        * ((height + BLOCK - 1) // BLOCK)
        * format.block_bytes()
    )


def chain_length(width: Int, height: Int) -> Int:
    """Return how many levels a full chain of an image has: one for each
    halving of the longer side, down to one texel.

    A container that names more levels than this is malformed.

    Args:
        width: The first level's width, positive.
        height: Its height, positive.

    Returns:
        `floor(log2(max(width, height))) + 1`.
    """
    var longest = max(width, height)
    var count = 1
    while longest > 1:
        longest >>= 1
        count += 1
    return count


struct CompressedImage(Movable):
    """A compressed container's contents: every level of every face, as
    block bytes, and what the file says about them.

    What `render.dds.read` and `render.ktx.read` return, three.js's
    `CompressedTextureLoader` result: `mipmaps`, `width`, `height`,
    `format` and `isCubemap`. The levels are face-major:
    `mipmaps[face * levels + level]`.
    """

    var width: Int
    """The first level's width in texels."""
    var height: Int
    """Its height."""
    var format: CompressedFormat
    """The block layout."""
    var color_space: ColorSpace
    """`SRGB` if the file names an sRGB format, `LINEAR` if not."""
    var faces: Int
    """Six for a cube, one otherwise."""
    var levels: Int
    """How many levels each face has."""
    var mipmaps: List[List[UInt8]]
    """Each level's block bytes, face-major."""

    def __init__(
        out self,
        width: Int,
        height: Int,
        format: CompressedFormat,
        color_space: ColorSpace,
        faces: Int,
        levels: Int,
    ):
        """Make an image with no levels read yet.

        Args:
            width: The first level's width.
            height: Its height.
            format: The block layout.
            color_space: What the file says.
            faces: Six for a cube, one otherwise.
            levels: How many levels each face has.
        """
        self.width = width
        self.height = height
        self.format = format
        self.color_space = color_space
        self.faces = faces
        self.levels = levels
        self.mipmaps = List[List[UInt8]]()

    def level_width(self, level: Int) -> Int:
        """Return a level's width: halved per level, never below one.

        Args:
            level: The level, zero the largest.

        Returns:
            The width in texels.
        """
        return max(1, self.width >> level)

    def level_height(self, level: Int) -> Int:
        """Return a level's height: halved per level, never below one.

        Args:
            level: The level, zero the largest.

        Returns:
            The height in texels.
        """
        return max(1, self.height >> level)

    def texture(
        self,
        face: Int = 0,
        level: Int = 0,
        wrap: Wrap = CLAMP,
        filter: Filter = BILINEAR,
        mipmapped: Bool = False,
        alpha: Alpha = COVERAGE,
    ) raises -> Texture:
        """Return one level of one face as a texture, in the file's color
        space.

        Args:
            face: Zero, or up to five for a cube: +x, -x, +y, -y, +z, -z.
            level: Which level, zero the largest.
            wrap: How coordinates outside the unit square are resolved.
            filter: `NEAREST` or `BILINEAR`.
            mipmapped: Build the chain of halved copies from this level.
            alpha: `COVERAGE` or `IGNORED`; see `render.texture`.

        Returns:
            The texture.

        Raises:
            Error: If there is no such face or level, and everything
                `compressed_texture` raises.
        """
        if face < 0 or face >= self.faces:
            raise Error("This image has no face " + String(face))
        if level < 0 or level >= self.levels:
            raise Error("This image has no level " + String(level))
        return compressed_texture(
            self.level_width(level),
            self.level_height(level),
            self.mipmaps[face * self.levels + level],
            self.format,
            wrap,
            filter,
            self.color_space,
            mipmapped,
            alpha,
        )
