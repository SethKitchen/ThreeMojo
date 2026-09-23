# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""ETC1, ETC2 and EAC blocks decoded on the host, as the Khronos Data
Format Specification defines them.

three.js uploads these as `RGB_ETC1_Format`, `RGB_ETC2_Format`,
`RGBA_ETC2_EAC_Format`, `R11_EAC_Format`, `SIGNED_R11_EAC_Format`,
`RG11_EAC_Format` and `SIGNED_RG11_EAC_Format`. `render.compressed_texture`
calls the block decoders here and lays the blocks out in an image.

**An ETC color block is two halves or one of three special modes.** Eight
bytes, read big-endian. The two halves of the block each have a base
color and a table of four offsets, and a two-bit index per texel picks
one offset to add to all three channels. The halves sit side by side, or
one above the other when the flip bit is set. The base colors are stored
as two 4-bit colors, or as a 5-bit color and a 3-bit signed difference.

ETC2 reuses the difference encodings that overflow. A red that overflows
selects the T mode, a green the H mode, and a blue the planar mode. T
and H hold two 4-bit colors and a distance, and give four paint colors.
Planar holds three 6-7-6 colors, at the block's corner and one step
right and down, and blends them across the block. An ETC1 block never
overflows, so the ETC2 decoder reads ETC1 as well.

**An EAC block is one channel.** Eight bytes: a base, a multiplier, one
of sixteen tables of eight offsets, and a three-bit index per texel. The
eight-bit form is ETC2's alpha. The eleven-bit forms, R11 and RG11, keep
three more bits, which is why they decode here to floats.

**Texels are column-major.** Every ETC and EAC block numbers its texels
down the first column, then the second. The decoders return them
row-major, as the rest of the project stores an image.
"""


def etc_modifiers() -> List[Int]:
    """Return the ETC1 offset tables, a small and a large offset per code.

    Returns:
        Sixteen offsets: code `c` has `[2c]` and `[2c + 1]`.
    """
    return [2, 8, 5, 17, 9, 29, 13, 42, 18, 60, 24, 80, 33, 106, 47, 183]


def etc_distances() -> List[Int]:
    """Return the distances of ETC2's T and H modes.

    Returns:
        Eight distances, indexed by the block's three-bit distance code.
    """
    return [3, 6, 11, 16, 23, 32, 41, 64]


def eac_modifiers() -> List[Int]:
    """Return the sixteen EAC offset tables.

    Returns:
        A hundred and twenty-eight offsets: table `t` is `[8t]` to
        `[8t + 7]`.
    """
    return [
        -3, -6, -9, -15, 2, 5, 8, 14,
        -3, -7, -10, -13, 2, 6, 9, 12,
        -2, -5, -8, -13, 1, 4, 7, 12,
        -2, -4, -6, -13, 1, 3, 5, 12,
        -3, -6, -8, -12, 2, 5, 7, 11,
        -3, -7, -9, -11, 2, 6, 8, 10,
        -4, -7, -8, -11, 3, 6, 7, 10,
        -3, -5, -8, -11, 2, 4, 7, 10,
        -2, -6, -8, -10, 1, 5, 7, 9,
        -2, -5, -8, -10, 1, 4, 7, 9,
        -2, -4, -8, -10, 1, 3, 7, 9,
        -2, -5, -7, -10, 1, 4, 6, 9,
        -3, -4, -7, -10, 2, 3, 6, 9,
        -1, -2, -3, -10, 0, 1, 2, 9,
        -4, -6, -8, -9, 3, 5, 7, 8,
        -3, -5, -7, -9, 2, 4, 6, 8,
    ]  # fmt: skip


struct EtcTables(Movable):
    """The fixed tables every ETC and EAC block reads, built once per
    image rather than once per block."""

    var modifiers: List[Int]
    """See `etc_modifiers`."""
    var distances: List[Int]
    """See `etc_distances`."""
    var eac: List[Int]
    """See `eac_modifiers`."""

    def __init__(out self):
        """Build the three tables."""
        self.modifiers = etc_modifiers()
        self.distances = etc_distances()
        self.eac = eac_modifiers()


def _clamp(value: Int, low: Int, high: Int) -> Int:
    """Return `value` held to `[low, high]`."""
    return min(max(value, low), high)


def _widen4(bits: Int) -> Int:
    """Return a four-bit channel as eight bits: `bits * 17`."""
    return (bits << 4) | bits


def _widen5(bits: Int) -> Int:
    """Return a five-bit channel as eight bits, top bits copied down."""
    return (bits << 3) | (bits >> 2)


def _widen6(bits: Int) -> Int:
    """Return a six-bit channel as eight bits, top bits copied down."""
    return (bits << 2) | (bits >> 4)


def _widen7(bits: Int) -> Int:
    """Return a seven-bit channel as eight bits, top bits copied down."""
    return (bits << 1) | (bits >> 6)


def _signed3(bits: Int) -> Int:
    """Return a three-bit two's-complement field as an integer."""
    return bits - ((bits & 4) << 1)


def _overflows(base: Int, delta: Int) -> Bool:
    """Return True if a five-bit base plus a difference leaves `[0, 31]`:
    the sign ETC2 reads as a different mode."""
    return base + delta < 0 or base + delta > 31


def _index(bits: Int, texel: Int) -> Int:
    """Return a texel's two-bit ETC index from the block's low word.

    Args:
        bits: Bytes four to seven, big-endian.
        texel: The texel's column-major number, `x * 4 + y`.

    Returns:
        The high bit from the top half, the low bit from the bottom half.
    """
    return (((bits >> (texel + 16)) & 1) << 1) | ((bits >> texel) & 1)


def _put(mut out: List[UInt8], x: Int, y: Int, r: Int, g: Int, b: Int):
    """Store one opaque texel, clamped, at its row-major slot."""
    var slot = (y * 4 + x) * 4
    out[slot] = UInt8(_clamp(r, 0, 255))
    out[slot + 1] = UInt8(_clamp(g, 0, 255))
    out[slot + 2] = UInt8(_clamp(b, 0, 255))
    out[slot + 3] = 255


def _halves(
    first: List[Int],
    second: List[Int],
    codes: Tuple[Int, Int],
    flip: Bool,
    bits: Int,
    tables: EtcTables,
) -> List[UInt8]:
    """Return a block read in its two halves, ETC1's own mode.

    Args:
        first: The first half's base color, eight bits a channel.
        second: The second half's.
        codes: Each half's table code.
        flip: True if the halves are the top and the bottom rather than
            the left and the right.
        bits: Bytes four to seven, big-endian.
        tables: The offset tables.

    Returns:
        Sixty-four bytes, row-major.
    """
    var out = List[UInt8](length=64, fill=0)
    for x in range(4):  # pragma: no branch
        for y in range(4):  # pragma: no branch
            var half = x >> 1
            if flip:
                half = y >> 1
            var index = _index(bits, x * 4 + y)
            var code = codes[0]
            if half == 1:
                code = codes[1]
            # Index bit zero picks the large offset, bit one negates it.
            var offset = tables.modifiers[code * 2 + (index & 1)]
            if index >= 2:
                offset = -offset
            if half == 0:
                _put(
                    out, x, y, first[0] + offset, first[1] + offset,
                    first[2] + offset,
                )  # fmt: skip
            else:
                _put(
                    out, x, y, second[0] + offset, second[1] + offset,
                    second[2] + offset,
                )  # fmt: skip
    return out^


def _painted(paint: List[Int], bits: Int) -> List[UInt8]:
    """Return a T- or H-mode block: each index names a paint color.

    Args:
        paint: Four colors, three channels each, unclamped.
        bits: Bytes four to seven, big-endian.

    Returns:
        Sixty-four bytes, row-major.
    """
    var out = List[UInt8](length=64, fill=0)
    for x in range(4):  # pragma: no branch
        for y in range(4):  # pragma: no branch
            var index = _index(bits, x * 4 + y)
            _put(
                out, x, y, paint[index * 3], paint[index * 3 + 1],
                paint[index * 3 + 2],
            )  # fmt: skip
    return out^


def _t_mode(data: List[UInt8], at: Int, tables: EtcTables) -> List[UInt8]:
    """Return an ETC2 T-mode block: one color, and a second color with the
    distance added and taken away."""
    var b0 = Int(data[at])
    var b1 = Int(data[at + 1])
    var b2 = Int(data[at + 2])
    var b3 = Int(data[at + 3])
    var r1 = _widen4((((b0 >> 3) & 3) << 2) | (b0 & 3))
    var g1 = _widen4(b1 >> 4)
    var bl1 = _widen4(b1 & 0xF)
    var r2 = _widen4(b2 >> 4)
    var g2 = _widen4(b2 & 0xF)
    var bl2 = _widen4(b3 >> 4)
    var d = tables.distances[(((b3 >> 2) & 3) << 1) | (b3 & 1)]
    var paint: List[Int] = [
        r1, g1, bl1,
        r2 + d, g2 + d, bl2 + d,
        r2, g2, bl2,
        r2 - d, g2 - d, bl2 - d,
    ]  # fmt: skip
    return _painted(paint, _low_word(data, at))


def _h_mode(data: List[UInt8], at: Int, tables: EtcTables) -> List[UInt8]:
    """Return an ETC2 H-mode block: two colors, each with the distance
    added and taken away."""
    var b0 = Int(data[at])
    var b1 = Int(data[at + 1])
    var b2 = Int(data[at + 2])
    var b3 = Int(data[at + 3])
    var r1 = (b0 >> 3) & 0xF
    var g1 = ((b0 & 7) << 1) | ((b1 >> 4) & 1)
    var bl1 = (b1 & 8) | ((b1 & 3) << 1) | (b2 >> 7)
    var r2 = (b2 >> 3) & 0xF
    var g2 = ((b2 & 7) << 1) | (b3 >> 7)
    var bl2 = (b3 >> 3) & 0xF
    # The distance's lowest bit is not stored: it is whether the first
    # color, as a twelve-bit number, is at least the second.
    var low = Int((r1 << 8) | (g1 << 4) | bl1 >= (r2 << 8) | (g2 << 4) | bl2)
    var d = tables.distances[(b3 & 4) | ((b3 & 1) << 1) | low]
    var c1: List[Int] = [_widen4(r1), _widen4(g1), _widen4(bl1)]
    var c2: List[Int] = [_widen4(r2), _widen4(g2), _widen4(bl2)]
    var paint: List[Int] = [
        c1[0] + d, c1[1] + d, c1[2] + d,
        c1[0] - d, c1[1] - d, c1[2] - d,
        c2[0] + d, c2[1] + d, c2[2] + d,
        c2[0] - d, c2[1] - d, c2[2] - d,
    ]  # fmt: skip
    return _painted(paint, _low_word(data, at))


def _planar(data: List[UInt8], at: Int) -> List[UInt8]:
    """Return an ETC2 planar block: three colors blended across the block."""
    var b0 = Int(data[at])
    var b1 = Int(data[at + 1])
    var b2 = Int(data[at + 2])
    var b3 = Int(data[at + 3])
    var b4 = Int(data[at + 4])
    var b5 = Int(data[at + 5])
    var b6 = Int(data[at + 6])
    var b7 = Int(data[at + 7])
    # The origin, the color one step right, and the color one step down.
    var ro = _widen6((b0 >> 1) & 0x3F)
    var go = _widen7(((b0 & 1) << 6) | ((b1 >> 1) & 0x3F))
    var bo = _widen6(
        ((b1 & 1) << 5) | (((b2 >> 3) & 3) << 3) | ((b2 & 3) << 1) | (b3 >> 7)
    )
    var rh = _widen6((((b3 >> 2) & 0x1F) << 1) | (b3 & 1))
    var gh = _widen7(b4 >> 1)
    var bh = _widen6(((b4 & 1) << 5) | (b5 >> 3))
    var rv = _widen6(((b5 & 7) << 3) | (b6 >> 5))
    var gv = _widen7(((b6 & 0x1F) << 2) | (b7 >> 6))
    var bv = _widen6(b7 & 0x3F)
    var out = List[UInt8](length=64, fill=0)
    for y in range(4):  # pragma: no branch
        for x in range(4):  # pragma: no branch
            _put(
                out,
                x,
                y,
                (x * (rh - ro) + y * (rv - ro) + 4 * ro + 2) >> 2,
                (x * (gh - go) + y * (gv - go) + 4 * go + 2) >> 2,
                (x * (bh - bo) + y * (bv - bo) + 4 * bo + 2) >> 2,
            )
    return out^


def _low_word(data: List[UInt8], at: Int) -> Int:
    """Return bytes four to seven of a block as one big-endian word."""
    return (
        (Int(data[at + 4]) << 24)
        | (Int(data[at + 5]) << 16)
        | (Int(data[at + 6]) << 8)
        | Int(data[at + 7])
    )


def etc2_color_block(
    data: List[UInt8], at: Int, tables: EtcTables
) -> List[UInt8]:
    """Return one ETC1 or ETC2 color block as opaque RGBA bytes.

    Args:
        data: The payload.
        at: Where the block's eight bytes begin.
        tables: The offset tables.

    Returns:
        Sixty-four bytes, row-major from the block's top left.
    """
    var b0 = Int(data[at])
    var b1 = Int(data[at + 1])
    var b2 = Int(data[at + 2])
    var b3 = Int(data[at + 3])
    var codes = (b3 >> 5, (b3 >> 2) & 7)
    var flip = (b3 & 1) == 1
    var bits = _low_word(data, at)
    if (b3 & 2) == 0:
        # Individual: two four-bit colors.
        var first: List[Int] = [
            _widen4(b0 >> 4),
            _widen4(b1 >> 4),
            _widen4(b2 >> 4),
        ]
        var second: List[Int] = [
            _widen4(b0 & 0xF),
            _widen4(b1 & 0xF),
            _widen4(b2 & 0xF),
        ]
        return _halves(first, second, codes, flip, bits, tables)
    # Differential: a five-bit color and a three-bit signed difference.
    var r = b0 >> 3
    var g = b1 >> 3
    var b = b2 >> 3
    var dr = _signed3(b0 & 7)
    var dg = _signed3(b1 & 7)
    var db = _signed3(b2 & 7)
    if _overflows(r, dr):
        return _t_mode(data, at, tables)
    if _overflows(g, dg):
        return _h_mode(data, at, tables)
    if _overflows(b, db):
        return _planar(data, at)
    var first: List[Int] = [_widen5(r), _widen5(g), _widen5(b)]
    var second: List[Int] = [_widen5(r + dr), _widen5(g + dg), _widen5(b + db)]
    return _halves(first, second, codes, flip, bits, tables)


def _eac_fields(data: List[UInt8], at: Int) -> Tuple[Int, Int, Int, Int]:
    """Return an EAC block's base byte, multiplier, table and indices.

    Args:
        data: The payload.
        at: Where the block's eight bytes begin.

    Returns:
        The base as an unsigned byte, the four-bit multiplier, the table
        number, and the forty-eight index bits.
    """
    var indices = 0
    for byte in range(2, 8):  # pragma: no branch
        indices = (indices << 8) | Int(data[at + byte])
    return (
        Int(data[at]),
        Int(data[at + 1]) >> 4,
        Int(data[at + 1]) & 0xF,
        indices,
    )


def _eac_index(indices: Int, x: Int, y: Int) -> Int:
    """Return a texel's three-bit EAC index; the first texel is the top
    three bits."""
    return (indices >> (45 - 3 * (x * 4 + y))) & 7


def eac_alpha_block(
    data: List[UInt8], at: Int, tables: EtcTables
) -> List[UInt8]:
    """Return one eight-bit EAC block, ETC2's alpha, as sixteen bytes.

    Each texel is `base + offset * multiplier`, clamped to a byte.

    Args:
        data: The payload.
        at: Where the block's eight bytes begin.
        tables: The offset tables.

    Returns:
        Sixteen bytes, row-major from the block's top left.
    """
    var fields = _eac_fields(data, at)
    var out = List[UInt8](length=16, fill=0)
    for y in range(4):  # pragma: no branch
        for x in range(4):  # pragma: no branch
            var offset = tables.eac[fields[2] * 8 + _eac_index(fields[3], x, y)]
            out[y * 4 + x] = UInt8(
                _clamp(fields[0] + offset * fields[1], 0, 255)
            )
    return out^


def eac_r11_block(
    data: List[UInt8], at: Int, signed: Bool, tables: EtcTables
) -> List[Float32]:
    """Return one eleven-bit EAC block, R11 or signed R11, as floats.

    Unsigned, a texel is `base * 8 + 4 + offset * multiplier * 8` held to
    `[0, 2047]`, over 2047. Signed, the base is a signed byte, with -128
    read as -127, the four is dropped, and the sum is held to
    `[-1023, 1023]`, over 1023. A multiplier of zero adds the offset once,
    not eight times.

    Args:
        data: The payload.
        at: Where the block's eight bytes begin.
        signed: True for `SIGNED_R11_EAC_Format`.
        tables: The offset tables.

    Returns:
        Sixteen floats, row-major from the block's top left.
    """
    var fields = _eac_fields(data, at)
    var scale = fields[1] * 8
    if scale == 0:
        scale = 1
    var base = fields[0] * 8 + 4
    var low = 0
    var high = 2047
    if signed:
        var byte = fields[0] - ((fields[0] & 0x80) << 1)
        base = max(byte, -127) * 8
        low = -1023
        high = 1023
    var out = List[Float32](length=16, fill=0)
    for y in range(4):  # pragma: no branch
        for x in range(4):  # pragma: no branch
            var offset = tables.eac[fields[2] * 8 + _eac_index(fields[3], x, y)]
            out[y * 4 + x] = Float32(
                _clamp(base + offset * scale, low, high)
            ) / Float32(high)
    return out^
