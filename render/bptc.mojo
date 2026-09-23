# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""BC6H and BC7 blocks decoded on the host, as the Direct3D 11 and
Khronos specifications define them.

three.js uploads these as `RGB_BPTC_UNSIGNED_Format`,
`RGB_BPTC_SIGNED_Format` and `RGBA_BPTC_Format`. `render.compressed_texture`
calls the block decoders here and lays the blocks out in an image.

**A BPTC block is sixteen bytes read as one 128-bit little-endian
number.** Its lowest bits name a mode. The mode fixes how many subsets
the block has, how many bits each endpoint keeps, and how many bits each
index takes. A subset is a group of texels that shares two endpoints. A
partition number picks which texels go in which subset, from a table the
specification fixes. Each texel's index picks a weight, and the texel
is the two endpoints blended by that weight.

**BC7 is eight-bit RGBA.** Eight modes: some keep alpha, some keep a
parity bit per endpoint, and two keep a separate index for alpha and can
swap alpha with one color channel. The blend is exact integer arithmetic,
`((64 - w) * e0 + w * e1 + 32) >> 6`, so every decoder agrees on every
texel. A first byte of zero names no mode, and its block decodes to
transparent black, as the specification says.

**BC6H is half-float RGB.** Fourteen modes. Most keep a full first
endpoint and the others as differences from it, and each mode scatters
the endpoint bits in its own order. The endpoints are unquantized to
sixteen bits, blended, scaled by 31/64 or 31/32 and read as a half's
bits. The signed form keeps a sign. Four reserved mode numbers decode to
black. This module returns the halves widened to floats, since a
`Texture` holds floats and not halves.
"""

from render.exr import half_to_float


def bptc_partitions2() -> List[Int]:
    """Return the sixty-four two-subset partitions.

    Returns:
        One sixteen-bit mask per partition: bit `i` is texel `i`'s subset,
        texels numbered row-major.
    """
    return [
        0xCCCC, 0x8888, 0xEEEE, 0xECC8, 0xC880, 0xFEEC, 0xFEC8, 0xEC80,
        0xC800, 0xFFEC, 0xFE80, 0xE800, 0xFFE8, 0xFF00, 0xFFF0, 0xF000,
        0xF710, 0x008E, 0x7100, 0x08CE, 0x008C, 0x7310, 0x3100, 0x8CCE,
        0x088C, 0x3110, 0x6666, 0x366C, 0x17E8, 0x0FF0, 0x718E, 0x399C,
        0xAAAA, 0xF0F0, 0x5A5A, 0x33CC, 0x3C3C, 0x55AA, 0x9696, 0xA55A,
        0x73CE, 0x13C8, 0x324C, 0x3BDC, 0x6996, 0xC33C, 0x9966, 0x0660,
        0x0272, 0x04E4, 0x4E40, 0x2720, 0xC936, 0x936C, 0x39C6, 0x639C,
        0x9336, 0x9CC6, 0x817E, 0xE718, 0xCCF0, 0x0FCC, 0x7744, 0xEE22,
    ]  # fmt: skip


def bptc_anchors2() -> List[Int]:
    """Return the second subset's anchor texel for each two-subset
    partition.

    Returns:
        Sixty-four texel numbers.
    """
    return [
        15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
        15, 2, 8, 2, 2, 8, 8, 15, 2, 8, 2, 2, 8, 8, 2, 2,
        15, 15, 6, 8, 2, 8, 15, 15, 2, 8, 2, 2, 2, 15, 15, 6,
        6, 2, 6, 8, 15, 15, 2, 2, 15, 15, 15, 15, 15, 2, 2, 15,
    ]  # fmt: skip


def bptc_partitions3() -> List[Int]:
    """Return the sixty-four three-subset partitions.

    Returns:
        One thirty-two-bit word per partition: bits `2i` and `2i + 1` are
        texel `i`'s subset.
    """
    return [
        0xAA685050, 0x6A5A5040, 0x5A5A4200, 0x5450A0A8,
        0xA5A50000, 0xA0A05050, 0x5555A0A0, 0x5A5A5050,
        0xAA550000, 0xAA555500, 0xAAAA5500, 0x90909090,
        0x94949494, 0xA4A4A4A4, 0xA9A59450, 0x2A0A4250,
        0xA5945040, 0x0A425054, 0xA5A5A500, 0x55A0A0A0,
        0xA8A85454, 0x6A6A4040, 0xA4A45000, 0x1A1A0500,
        0x0050A4A4, 0xAAA59090, 0x14696914, 0x69691400,
        0xA08585A0, 0xAA821414, 0x50A4A450, 0x6A5A0200,
        0xA9A58000, 0x5090A0A8, 0xA8A09050, 0x24242424,
        0x00AA5500, 0x24924924, 0x24499224, 0x50A50A50,
        0x500AA550, 0xAAAA4444, 0x66660000, 0xA5A0A5A0,
        0x50A050A0, 0x69286928, 0x44AAAA44, 0x66666600,
        0xAA444444, 0x54A854A8, 0x95809580, 0x96969600,
        0xA85454A8, 0x80959580, 0xAA141414, 0x96960000,
        0xAAAA1414, 0xA05050A0, 0xA0A5A5A0, 0x96000000,
        0x40804080, 0xA9A8A9A8, 0xAAAAAA44, 0x2A4A5254,
    ]  # fmt: skip


def bptc_anchors3() -> List[Int]:
    """Return the second and third subsets' anchor texels for each
    three-subset partition.

    Returns:
        A hundred and twenty-eight texel numbers: the second subset's
        sixty-four, then the third's.
    """
    return [
        3, 3, 15, 15, 8, 3, 15, 15, 8, 8, 6, 6, 6, 5, 3, 3,
        3, 3, 8, 15, 3, 3, 6, 10, 5, 8, 8, 6, 8, 5, 15, 15,
        8, 15, 3, 5, 6, 10, 8, 15, 15, 3, 15, 5, 15, 15, 15, 15,
        3, 15, 5, 5, 5, 8, 5, 10, 5, 10, 8, 13, 15, 12, 3, 3,
        15, 8, 8, 3, 15, 15, 3, 8, 15, 15, 15, 15, 15, 15, 15, 8,
        15, 8, 15, 3, 15, 8, 15, 8, 3, 15, 6, 10, 15, 15, 10, 8,
        15, 3, 15, 10, 10, 8, 9, 10, 6, 15, 8, 15, 3, 6, 6, 8,
        15, 3, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 3, 15, 15, 8,
    ]  # fmt: skip


def bptc_weights() -> List[Int]:
    """Return the blend weights for two-, three- and four-bit indices.

    Returns:
        Forty-eight weights out of 64: sixteen per index width, from two
        bits at `[0]`, padded with zeros.
    """
    return [
        0, 21, 43, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 9, 18, 27, 37, 46, 55, 64, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64,
    ]  # fmt: skip


def bc7_modes() -> List[Int]:
    """Return the eight BC7 modes' fields.

    Returns:
        Ten numbers a mode: subsets, partition bits, rotation bits, index
        selection bits, color bits, alpha bits, a parity bit per endpoint,
        a parity bit per subset, index bits, and second index bits.
    """
    return [
        3, 4, 0, 0, 4, 0, 1, 0, 3, 0,
        2, 6, 0, 0, 6, 0, 0, 1, 3, 0,
        3, 6, 0, 0, 5, 0, 0, 0, 2, 0,
        2, 6, 0, 0, 7, 0, 1, 0, 2, 0,
        1, 0, 2, 1, 5, 6, 0, 0, 2, 3,
        1, 0, 2, 0, 7, 8, 0, 0, 2, 2,
        1, 0, 0, 0, 7, 7, 1, 0, 4, 0,
        2, 6, 0, 0, 5, 5, 1, 0, 2, 0,
    ]  # fmt: skip


def bc6h_modes() -> List[Int]:
    """Return the BC6H modes' fields, by mode number.

    A mode number is the block's low two bits, or its low five when the
    low two are `10` or `11`. Numbers that name no mode have an endpoint
    width of zero.

    Returns:
        Six numbers for each of thirty-two mode numbers: whether the
        other endpoints are differences, partition bits, endpoint bits,
        and red, green and blue difference bits.
    """
    var modes = List[Int](length=32 * 6, fill=0)
    var rows: List[Int] = [
        0, 1, 5, 10, 5, 5, 5,
        1, 1, 5, 7, 6, 6, 6,
        2, 1, 5, 11, 5, 4, 4,
        3, 0, 0, 10, 10, 10, 10,
        6, 1, 5, 11, 4, 5, 4,
        7, 1, 0, 11, 9, 9, 9,
        10, 1, 5, 11, 4, 4, 5,
        11, 1, 0, 12, 8, 8, 8,
        14, 1, 5, 9, 5, 5, 5,
        15, 1, 0, 16, 4, 4, 4,
        18, 1, 5, 8, 6, 5, 5,
        22, 1, 5, 8, 5, 6, 5,
        26, 1, 5, 8, 5, 5, 6,
        30, 0, 5, 6, 6, 6, 6,
    ]  # fmt: skip
    for row in range(14):  # pragma: no branch
        for field in range(6):  # pragma: no branch
            modes[rows[row * 7] * 6 + field] = rows[row * 7 + 1 + field]
    return modes^


# BC6H endpoint slots: red 0 to 3, green 4 to 7, blue 8 to 11, the first
# subset's two endpoints and then the second's.
comptime _R0 = 0
comptime _R1 = 1
comptime _R2 = 2
comptime _R3 = 3
comptime _G0 = 4
comptime _G1 = 5
comptime _G2 = 6
comptime _G3 = 7
comptime _B0 = 8
comptime _B1 = 9
comptime _B2 = 10
comptime _B3 = 11


def bc6h_layout(mode: Int) -> List[Int]:
    """Return where a BC6H mode puts its endpoint bits, in stream order.

    Args:
        mode: A mode number that names a mode.

    Returns:
        Triples of endpoint slot, the shift in that endpoint, and how many
        bits: red 0 to 3, green 4 to 7, blue 8 to 11.
    """
    if mode == 0:
        return [
            _G2, 4, 1, _B2, 4, 1, _B3, 4, 1, _R0, 0, 10, _G0, 0, 10,
            _B0, 0, 10, _R1, 0, 5, _G3, 4, 1, _G2, 0, 4, _G1, 0, 5,
            _B3, 0, 1, _G3, 0, 4, _B1, 0, 5, _B3, 1, 1, _B2, 0, 4,
            _R2, 0, 5, _B3, 2, 1, _R3, 0, 5, _B3, 3, 1,
        ]  # fmt: skip
    if mode == 1:
        return [
            _G2, 5, 1, _G3, 4, 1, _G3, 5, 1, _R0, 0, 7, _B3, 0, 1,
            _B3, 1, 1, _B2, 4, 1, _G0, 0, 7, _B2, 5, 1, _B3, 2, 1,
            _G2, 4, 1, _B0, 0, 7, _B3, 3, 1, _B3, 5, 1, _B3, 4, 1,
            _R1, 0, 6, _G2, 0, 4, _G1, 0, 6, _G3, 0, 4, _B1, 0, 6,
            _B2, 0, 4, _R2, 0, 6, _R3, 0, 6,
        ]  # fmt: skip
    if mode == 2:
        return [
            _R0, 0, 10, _G0, 0, 10, _B0, 0, 10, _R1, 0, 5, _R0, 10, 1,
            _G2, 0, 4, _G1, 0, 4, _G0, 10, 1, _B3, 0, 1, _G3, 0, 4,
            _B1, 0, 4, _B0, 10, 1, _B3, 1, 1, _B2, 0, 4, _R2, 0, 5,
            _B3, 2, 1, _R3, 0, 5, _B3, 3, 1,
        ]  # fmt: skip
    if mode == 3:
        return [
            _R0, 0, 10, _G0, 0, 10, _B0, 0, 10, _R1, 0, 10, _G1, 0, 10,
            _B1, 0, 10,
        ]  # fmt: skip
    if mode == 6:
        return [
            _R0, 0, 10, _G0, 0, 10, _B0, 0, 10, _R1, 0, 4, _R0, 10, 1,
            _G3, 4, 1, _G2, 0, 4, _G1, 0, 5, _G0, 10, 1, _G3, 0, 4,
            _B1, 0, 4, _B0, 10, 1, _B3, 1, 1, _B2, 0, 4, _R2, 0, 4,
            _B3, 0, 1, _B3, 2, 1, _R3, 0, 4, _G2, 4, 1, _B3, 3, 1,
        ]  # fmt: skip
    if mode == 7:
        return [
            _R0, 0, 10, _G0, 0, 10, _B0, 0, 10, _R1, 0, 9, _R0, 10, 1,
            _G1, 0, 9, _G0, 10, 1, _B1, 0, 9, _B0, 10, 1,
        ]  # fmt: skip
    if mode == 10:
        return [
            _R0, 0, 10, _G0, 0, 10, _B0, 0, 10, _R1, 0, 4, _R0, 10, 1,
            _B2, 4, 1, _G2, 0, 4, _G1, 0, 4, _G0, 10, 1, _B3, 0, 1,
            _G3, 0, 4, _B1, 0, 5, _B0, 10, 1, _B2, 0, 4, _R2, 0, 4,
            _B3, 1, 1, _B3, 2, 1, _R3, 0, 4, _B3, 4, 1, _B3, 3, 1,
        ]  # fmt: skip
    if mode == 11:
        return [
            _R0, 0, 10, _G0, 0, 10, _B0, 0, 10, _R1, 0, 8, _R0, 11, 1,
            _R0, 10, 1, _G1, 0, 8, _G0, 11, 1, _G0, 10, 1, _B1, 0, 8,
            _B0, 11, 1, _B0, 10, 1,
        ]  # fmt: skip
    if mode == 14:
        return [
            _R0, 0, 9, _B2, 4, 1, _G0, 0, 9, _G2, 4, 1, _B0, 0, 9,
            _B3, 4, 1, _R1, 0, 5, _G3, 4, 1, _G2, 0, 4, _G1, 0, 5,
            _B3, 0, 1, _G3, 0, 4, _B1, 0, 5, _B3, 1, 1, _B2, 0, 4,
            _R2, 0, 5, _B3, 2, 1, _R3, 0, 5, _B3, 3, 1,
        ]  # fmt: skip
    if mode == 15:
        # The top six bits of each first endpoint are stored reversed.
        return [
            _R0, 0, 10, _G0, 0, 10, _B0, 0, 10,
            _R1, 0, 4, _R0, 15, 1, _R0, 14, 1, _R0, 13, 1, _R0, 12, 1,
            _R0, 11, 1, _R0, 10, 1,
            _G1, 0, 4, _G0, 15, 1, _G0, 14, 1, _G0, 13, 1, _G0, 12, 1,
            _G0, 11, 1, _G0, 10, 1,
            _B1, 0, 4, _B0, 15, 1, _B0, 14, 1, _B0, 13, 1, _B0, 12, 1,
            _B0, 11, 1, _B0, 10, 1,
        ]  # fmt: skip
    if mode == 18:
        return [
            _R0, 0, 8, _G3, 4, 1, _B2, 4, 1, _G0, 0, 8, _B3, 2, 1,
            _G2, 4, 1, _B0, 0, 8, _B3, 3, 1, _B3, 4, 1, _R1, 0, 6,
            _G2, 0, 4, _G1, 0, 5, _B3, 0, 1, _G3, 0, 4, _B1, 0, 5,
            _B3, 1, 1, _B2, 0, 4, _R2, 0, 6, _R3, 0, 6,
        ]  # fmt: skip
    if mode == 22:
        return [
            _R0, 0, 8, _B3, 0, 1, _B2, 4, 1, _G0, 0, 8, _G2, 5, 1,
            _G2, 4, 1, _B0, 0, 8, _G3, 5, 1, _B3, 4, 1, _R1, 0, 5,
            _G3, 4, 1, _G2, 0, 4, _G1, 0, 6, _G3, 0, 4, _B1, 0, 5,
            _B3, 1, 1, _B2, 0, 4, _R2, 0, 5, _B3, 2, 1, _R3, 0, 5,
            _B3, 3, 1,
        ]  # fmt: skip
    if mode == 26:
        return [
            _R0, 0, 8, _B3, 1, 1, _B2, 4, 1, _G0, 0, 8, _B2, 5, 1,
            _G2, 4, 1, _B0, 0, 8, _B3, 5, 1, _B3, 4, 1, _R1, 0, 5,
            _G3, 4, 1, _G2, 0, 4, _G1, 0, 5, _B3, 0, 1, _G3, 0, 4,
            _B1, 0, 6, _B2, 0, 4, _R2, 0, 5, _B3, 2, 1, _R3, 0, 5,
            _B3, 3, 1,
        ]  # fmt: skip
    # Mode 30, the last there is.
    return [
        _R0, 0, 6, _G3, 4, 1, _B3, 0, 1, _B3, 1, 1, _B2, 4, 1,
        _G0, 0, 6, _G2, 5, 1, _B2, 5, 1, _B3, 2, 1, _G2, 4, 1,
        _B0, 0, 6, _G3, 5, 1, _B3, 3, 1, _B3, 5, 1, _B3, 4, 1,
        _R1, 0, 6, _G2, 0, 4, _G1, 0, 6, _G3, 0, 4, _B1, 0, 6,
        _B2, 0, 4, _R2, 0, 6, _R3, 0, 6,
    ]  # fmt: skip


struct BptcTables(Movable):
    """The fixed tables every BPTC block reads, built once per image
    rather than once per block."""

    var partitions2: List[Int]
    """See `bptc_partitions2`."""
    var anchors2: List[Int]
    """See `bptc_anchors2`."""
    var partitions3: List[Int]
    """See `bptc_partitions3`."""
    var anchors3: List[Int]
    """See `bptc_anchors3`."""
    var weights: List[Int]
    """See `bptc_weights`."""
    var bc7: List[Int]
    """See `bc7_modes`."""
    var bc6h: List[Int]
    """See `bc6h_modes`."""
    var layouts: List[List[Int]]
    """`bc6h_layout` for each of the thirty-two mode numbers, empty where
    the number names no mode."""

    def __init__(out self):
        """Build the tables."""
        self.partitions2 = bptc_partitions2()
        self.anchors2 = bptc_anchors2()
        self.partitions3 = bptc_partitions3()
        self.anchors3 = bptc_anchors3()
        self.weights = bptc_weights()
        self.bc7 = bc7_modes()
        self.bc6h = bc6h_modes()
        self.layouts = List[List[Int]]()
        for mode in range(32):  # pragma: no branch
            if self.bc6h[mode * 6 + 2] == 0:
                self.layouts.append(List[Int]())
            else:
                self.layouts.append(bc6h_layout(mode))


struct _Bits(Movable):
    """A 128-bit block read from its lowest bit up."""

    var bytes: List[UInt8]
    var position: Int

    def __init__(out self, data: List[UInt8], at: Int, position: Int):
        """Read the block at `at` from bit `position`."""
        self.bytes = List[UInt8](capacity=16)
        for byte in range(16):  # pragma: no branch
            self.bytes.append(data[at + byte])
        self.position = position

    def peek(self, offset: Int, count: Int) -> Int:
        """Return `count` bits from `offset` past the position, low first."""
        var value = 0
        for bit in range(count):
            var index = self.position + offset + bit
            var byte = Int(self.bytes[index >> 3])
            value |= ((byte >> (index & 7)) & 1) << bit
        return value

    def read(mut self, count: Int) -> Int:
        """Return the next `count` bits, low first, and move past them."""
        var value = self.peek(0, count)
        self.position += count
        return value


def _expand(value: Int, bits: Int) -> Int:
    """Return a `bits`-wide BC7 endpoint as eight bits, top bits copied
    down."""
    var shifted = value << (8 - bits)
    return (shifted | (shifted >> bits)) & 0xFF


def _subset(
    tables: BptcTables, subsets: Int, partition: Int, texel: Int
) -> Tuple[Int, Int]:
    """Return a texel's subset, and that subset's anchor texel.

    Args:
        tables: The partition tables.
        subsets: One, two or three.
        partition: The block's partition number.
        texel: The texel, row-major.

    Returns:
        The subset, and the texel whose index is one bit shorter in it.
    """
    if subsets == 1:
        return (0, 0)
    if subsets == 2:
        var two = (tables.partitions2[partition] >> texel) & 1
        return (two, two * tables.anchors2[partition])
    var three = (tables.partitions3[partition] >> (2 * texel)) & 3
    var anchor = 0
    if three > 0:
        anchor = tables.anchors3[(three - 1) * 64 + partition]
    return (three, anchor)


def _lerp(e0: Int, e1: Int, weight: Int) -> Int:
    """Return two endpoints blended by a weight out of 64, BPTC's exact
    integer blend."""
    return ((64 - weight) * e0 + weight * e1 + 32) >> 6


def bc7_block(data: List[UInt8], at: Int, tables: BptcTables) -> List[UInt8]:
    """Return one BC7 block as RGBA bytes.

    Args:
        data: The payload.
        at: Where the block's sixteen bytes begin.
        tables: The partition, weight and mode tables.

    Returns:
        Sixty-four bytes, row-major from the block's top left. A block
        that names no mode is transparent black.
    """
    var out = List[UInt8](length=64, fill=0)
    var first = Int(data[at])
    if first == 0:
        return out^
    # The mode is the number of zero bits below the first one.
    var mode = 0
    while (first >> mode) & 1 == 0:
        mode += 1
    var bits = _Bits(data, at, mode + 1)
    var m = mode * 10
    var subsets = tables.bc7[m]
    var partition = bits.read(tables.bc7[m + 1])
    var rotation = bits.read(tables.bc7[m + 2])
    var selection = bits.read(tables.bc7[m + 3])
    var color_bits = tables.bc7[m + 4]
    var alpha_bits = tables.bc7[m + 5]
    var endpoint_parity = tables.bc7[m + 6]
    var shared_parity = tables.bc7[m + 7]
    var index_bits = tables.bc7[m + 8]
    var second_bits = tables.bc7[m + 9]
    var parity = endpoint_parity | shared_parity
    var ends = subsets * 2
    # Four channels of up to six endpoints each.
    var ep = List[Int](length=24, fill=0xFF)
    for channel in range(3):  # pragma: no branch
        for end in range(ends):  # pragma: no branch
            ep[channel * 6 + end] = bits.read(color_bits) << parity
    if alpha_bits > 0:
        for end in range(ends):  # pragma: no branch
            ep[18 + end] = bits.read(alpha_bits) << parity
    if endpoint_parity == 1:
        for end in range(ends):  # pragma: no branch
            var p = bits.read(1)
            for channel in range(4):  # pragma: no branch
                ep[channel * 6 + end] |= p
    elif shared_parity == 1:
        for subset in range(subsets):  # pragma: no branch
            var p = bits.read(1)
            for channel in range(4):  # pragma: no branch
                ep[channel * 6 + subset * 2] |= p
                ep[channel * 6 + subset * 2 + 1] |= p
    for end in range(ends):  # pragma: no branch
        for channel in range(3):  # pragma: no branch
            ep[channel * 6 + end] = _expand(
                ep[channel * 6 + end], color_bits + parity
            )
        if alpha_bits > 0:
            ep[18 + end] = _expand(ep[18 + end], alpha_bits + parity)
    # The second index set, where there is one, follows the first: sixteen
    # indices a subset, each subset's anchor one bit short.
    var offsets = [0, subsets * (16 * index_bits - 1)]
    for texel in range(16):  # pragma: no branch
        var found = _subset(tables, subsets, partition, texel)
        var short = Int(texel == found[1])
        var primary = bits.peek(offsets[0], index_bits - short)
        offsets[0] += index_bits - short
        var color_weight = tables.weights[(index_bits - 2) * 16 + primary]
        var alpha_weight = color_weight
        if second_bits > 0:
            var secondary = bits.peek(offsets[1], second_bits - short)
            offsets[1] += second_bits - short
            alpha_weight = tables.weights[(second_bits - 2) * 16 + secondary]
            if selection == 1:
                var swap = color_weight
                color_weight = alpha_weight
                alpha_weight = swap
        var e = found[0] * 2
        var rgba: List[Int] = [
            _lerp(ep[e], ep[e + 1], color_weight),
            _lerp(ep[6 + e], ep[6 + e + 1], color_weight),
            _lerp(ep[12 + e], ep[12 + e + 1], color_weight),
            _lerp(ep[18 + e], ep[18 + e + 1], alpha_weight),
        ]
        if rotation > 0:
            var swap = rgba[3]
            rgba[3] = rgba[rotation - 1]
            rgba[rotation - 1] = swap
        for channel in range(4):  # pragma: no branch
            out[texel * 4 + channel] = UInt8(rgba[channel])
    return out^


def _sign_extend(value: Int, bits: Int) -> Int:
    """Return a `bits`-wide two's-complement field as an integer."""
    return value - (((value >> (bits - 1)) & 1) << bits)


def bc6h_unquantize(value: Int, bits: Int, signed: Bool) -> Int:
    """Return a BC6H endpoint widened to sixteen bits.

    The specification's `unquantize`: zero stays zero, the largest value
    becomes the largest sixteen-bit one, and everything between scales
    with rounding. A signed endpoint scales its magnitude.

    Args:
        value: The endpoint, signed if `signed`.
        bits: The mode's endpoint width.
        signed: True for the signed format.

    Returns:
        The endpoint, 0 to 65535 or -32767 to 32767.
    """
    if not signed:
        if bits >= 15:
            return value
        if value == 0:
            return 0
        if value == (1 << bits) - 1:
            return 0xFFFF
        return ((value << 16) + 0x8000) >> bits
    if bits >= 16:
        return value
    var magnitude = abs(value)
    var result: Int
    if magnitude == 0:
        result = 0
    elif magnitude >= (1 << (bits - 1)) - 1:
        result = 0x7FFF
    else:
        result = ((magnitude << 15) + 0x4000) >> (bits - 1)
    if value < 0:
        return -result
    return result


def bc6h_finish(value: Int, signed: Bool) -> Float32:
    """Return a blended BC6H value scaled to a half and widened to a
    float.

    Args:
        value: The blend of two unquantized endpoints.
        signed: True for the signed format.

    Returns:
        The float the half's bits spell.
    """
    if not signed:
        return half_to_float(UInt16((value * 31) >> 6))
    if value < 0:
        return half_to_float(UInt16(0x8000 | (((-value) * 31) >> 5)))
    return half_to_float(UInt16((value * 31) >> 5))


def bc6h_block(
    data: List[UInt8], at: Int, signed: Bool, tables: BptcTables
) -> List[Float32]:
    """Return one BC6H block as opaque RGBA floats.

    Args:
        data: The payload.
        at: Where the block's sixteen bytes begin.
        signed: True for `RGB_BPTC_SIGNED_Format`.
        tables: The partition, weight and mode tables.

    Returns:
        Sixty-four floats, row-major from the block's top left. A block
        with a reserved mode number is black, with an alpha of one.
    """
    var out = List[Float32](length=64, fill=0)
    for texel in range(16):  # pragma: no branch
        out[texel * 4 + 3] = 1
    var bits = _Bits(data, at, 0)
    var mode = bits.read(2)
    if mode >= 2:
        mode |= bits.read(3) << 2
    var m = mode * 6
    var endpoint_bits = tables.bc6h[m + 2]
    if endpoint_bits == 0:
        return out^
    var transformed = tables.bc6h[m] == 1
    var partition_bits = tables.bc6h[m + 1]
    var ep = List[Int](length=12, fill=0)
    var layout = tables.layouts[mode].copy()
    for field in range(len(layout) // 3):  # pragma: no branch
        ep[layout[field * 3]] |= (
            bits.read(layout[field * 3 + 2]) << layout[field * 3 + 1]
        )
    var ends = 2
    if partition_bits > 0:
        ends = 4
    for channel in range(3):  # pragma: no branch
        var base = channel * 4
        var delta_bits = tables.bc6h[m + 3 + channel]
        if signed:
            ep[base] = _sign_extend(ep[base], endpoint_bits)
        for end in range(1, ends):  # pragma: no branch
            if signed or transformed:
                ep[base + end] = _sign_extend(ep[base + end], delta_bits)
            if transformed:
                ep[base + end] = (ep[base + end] + ep[base]) & (
                    (1 << endpoint_bits) - 1
                )
                if signed:
                    ep[base + end] = _sign_extend(ep[base + end], endpoint_bits)
        for end in range(ends):  # pragma: no branch
            ep[base + end] = bc6h_unquantize(
                ep[base + end], endpoint_bits, signed
            )
    var partition = bits.read(partition_bits)
    var subsets = ends // 2
    var index_bits = 4 - (subsets - 1)
    for texel in range(16):  # pragma: no branch
        var found = _subset(tables, subsets, partition, texel)
        var short = Int(texel == found[1])
        var index = bits.read(index_bits - short)
        var weight = tables.weights[(index_bits - 2) * 16 + index]
        var e = found[0] * 2
        for channel in range(3):  # pragma: no branch
            out[texel * 4 + channel] = bc6h_finish(
                _lerp(ep[channel * 4 + e], ep[channel * 4 + e + 1], weight),
                signed,
            )
    return out^
