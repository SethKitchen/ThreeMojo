# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Basis Universal UASTC LDR 4x4 blocks decoded to RGBA bytes, ported from
`unpack_uastc` in Binomial's `basisu_transcoder.cpp` (Apache-2.0).

A KTX 2.0 file with the UASTC color model holds one 16-byte block for
each 4x4 texels. three.js transcodes these blocks to a GPU format with
the Basis Universal WebAssembly transcoder. Here they decode on the host
to the same RGBA bytes that transcoder gives for its `RGBA32` target.

**A block is a subset of ASTC.** The first bits are a prefix code for one
of nineteen modes. A mode fixes everything else: how many subsets and
planes, how many components, the endpoint and weight ranges, and how
many hint bits a transcoder to BC1, ETC1 and ETC2 reads. Those hints do
not change the decoded texels, so they are skipped.

    solid        mode 8: four 8-bit channels, one color for the block
    subsets      modes 2, 3, 4, 7, 9, 16: a partition from a fixed table
    dual plane   modes 6, 11, 13, 17: one channel takes a second weight
    components   3 is RGB, 4 is RGBA, 2 is luminance and alpha

**Endpoints are integer sequences.** A range with trits or quints stores
those digits first, packed base three or base five into whole numbers,
then each value's low bits. This is simpler than ASTC's own packing.
Each value unquantizes to eight bits as the ASTC specification says.

**Weights blend as ASTC blends.** A weight becomes a number out of 64,
the endpoints widen to sixteen bits, and the blend rounds back to eight.
The first texel of each subset stores one weight bit fewer.
"""

# The number of UASTC LDR modes; a prefix code of a higher number is
# reserved.
comptime UASTC_MODES = 19
# The mode that stores one color for the block.
comptime SOLID_MODE = 8
# The bytes of one block.
comptime UASTC_BLOCK_BYTES = 16
# The numbers `_mode_table` gives each mode.
comptime MODE_COLUMNS = 8


def _modes_of_prefix() -> List[Int]:
    """Return the mode each value of the first seven bits names."""
    return [
        11, 0, 10, 3, 11, 15, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9,
        11, 0, 10, 4, 11, 16, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13,
        11, 0, 10, 3, 11, 17, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9,
        11, 0, 10, 4, 11, 1, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13,
        11, 0, 10, 3, 11, 19, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9,
        11, 0, 10, 4, 11, 16, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13,
        11, 0, 10, 3, 11, 17, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9,
        11, 0, 10, 4, 11, 1, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13,
    ]  # fmt: skip


def _mode_table() -> List[Int]:
    """Return eight numbers per mode: the prefix code's length, the hint
    bits, the weight bits, the endpoint range, the components, the subsets,
    the planes, and the channel the second plane weights: -1 when the block
    stores it, 4 for none."""
    return [
        4, 15, 4, 19, 3, 1, 1, 4,
        6, 15, 2, 20, 3, 1, 1, 4,
        5, 15, 3, 8, 3, 2, 1, 4,
        5, 15, 2, 7, 3, 3, 1, 4,
        5, 15, 2, 12, 3, 2, 1, 4,
        5, 15, 3, 20, 3, 1, 1, 4,
        5, 15, 2, 18, 3, 1, 2, -1,
        5, 15, 2, 12, 3, 2, 1, 4,
        5, 0, 0, 0, 4, 1, 1, 4,
        5, 23, 2, 8, 4, 2, 1, 4,
        3, 17, 4, 13, 4, 1, 1, 4,
        2, 17, 2, 13, 4, 1, 2, -1,
        3, 17, 3, 19, 4, 1, 1, 4,
        5, 23, 1, 20, 4, 1, 2, -1,
        5, 23, 2, 20, 4, 1, 1, 4,
        7, 23, 4, 20, 2, 1, 1, 4,
        6, 23, 2, 20, 2, 2, 1, 4,
        6, 23, 2, 20, 2, 1, 2, 3,
        4, 15, 5, 11, 3, 1, 1, 4,
    ]  # fmt: skip


def _bise_ranges() -> List[Int]:
    """Return the bits, trits and quints of each of the 21 ASTC ranges."""
    return [
        1, 0, 0, 0, 1, 0, 2, 0, 0, 0, 0, 1, 1, 1, 0, 3, 0, 0, 1, 0, 1,
        2, 1, 0, 4, 0, 0, 2, 0, 1, 3, 1, 0, 5, 0, 0, 3, 0, 1, 4, 1, 0,
        6, 0, 0, 4, 0, 1, 5, 1, 0, 7, 0, 0, 5, 0, 1, 6, 1, 0, 8, 0, 0,
    ]  # fmt: skip


def _unquant_c() -> List[Int]:
    """Return the ASTC endpoint unquantization constant `C` of each range,
    zero for a range of bits only or one UASTC does not use."""
    return [
        0, 0, 0, 0, 204, 0, 113, 93, 0, 54, 44, 0, 26, 22, 0, 13, 11, 0, 6,
        5, 0,
    ]  # fmt: skip


def _unquant_b() -> List[List[Int]]:
    """Return the ASTC endpoint unquantization bit pattern `B` of each
    range, highest bit first: the stored bit each position copies, or -1
    for a zero."""
    return [
        [],
        [],
        [],
        [],
        [-1, -1, -1, -1, -1, -1, -1, -1, -1],
        [],
        [-1, -1, -1, -1, -1, -1, -1, -1, -1],
        [1, -1, -1, -1, 1, -1, 1, 1, -1],
        [],
        [1, -1, -1, -1, -1, 1, 1, -1, -1],
        [2, 1, -1, -1, -1, 2, 1, 2, 1],
        [],
        [2, 1, -1, -1, -1, -1, 2, 1, 2],
        [3, 2, 1, -1, -1, -1, 3, 2, 1],
        [],
        [3, 2, 1, -1, -1, -1, -1, 3, 2],
        [4, 3, 2, 1, -1, -1, -1, 4, 3],
        [],
        [4, 3, 2, 1, -1, -1, -1, -1, 4],
        [5, 4, 3, 2, 1, -1, -1, -1, 5],
        [],
    ]  # fmt: skip


def _patterns2() -> List[Int]:
    """Return the thirty two-subset partitions UASTC shares with BC7, each
    sixteen subsets row-major."""
    return [
        0,0,1,1,0,0,1,1,0,0,1,1,0,0,1,1, 0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,
        1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0, 0,0,0,1,0,0,1,1,0,0,1,1,0,1,1,1,
        1,1,1,1,1,1,1,0,1,1,1,0,1,1,0,0, 0,0,1,1,0,1,1,1,0,1,1,1,1,1,1,1,
        1,1,1,0,1,1,0,0,1,0,0,0,0,0,0,0, 1,1,1,1,1,1,1,0,1,1,0,0,1,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,1,0,0,1,1, 1,1,0,0,1,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,1,0,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,0,1,0,0,0,
        1,1,1,0,1,0,0,0,0,0,0,0,0,0,0,0, 1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,
        0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,
        1,0,0,0,1,1,1,0,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,0,1,1,1,0,0,0,1,
        0,1,1,1,0,0,1,1,0,0,0,1,0,0,0,0, 0,0,1,1,0,0,0,1,0,0,0,0,0,0,0,0,
        0,0,0,0,1,0,0,0,1,1,0,0,1,1,1,0, 1,1,1,1,1,1,1,1,0,1,1,1,0,0,1,1,
        1,0,0,0,1,1,0,0,1,1,0,0,1,1,1,0, 0,0,1,1,0,0,0,1,0,0,0,1,0,0,0,0,
        1,1,1,1,0,1,1,1,0,1,1,1,0,0,1,1, 0,1,1,0,0,1,1,0,0,1,1,0,0,1,1,0,
        1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1, 1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0,
        1,1,1,1,0,0,0,0,1,1,1,1,0,0,0,0, 1,0,0,1,0,0,1,1,0,1,1,0,1,1,0,0,
    ]  # fmt: skip


def _anchors2() -> List[Int]:
    """Return each two-subset partition's anchor texels, three apiece."""
    return [
        0, 2, 0, 0, 3, 0, 1, 0, 0, 0, 3, 0, 7, 0, 0, 0, 2, 0, 3, 0, 0,
        7, 0, 0, 0, 11, 0, 2, 0, 0, 0, 7, 0, 11, 0, 0, 3, 0, 0, 8, 0, 0,
        0, 4, 0, 12, 0, 0, 1, 0, 0, 8, 0, 0, 0, 1, 0, 0, 2, 0, 0, 4, 0,
        8, 0, 0, 1, 0, 0, 0, 2, 0, 4, 0, 0, 0, 1, 0, 4, 0, 0, 1, 0, 0,
        4, 0, 0, 1, 0, 0,
    ]  # fmt: skip


def _patterns3() -> List[Int]:
    """Return the eleven three-subset partitions."""
    return [
        0,0,0,0,0,0,0,0,1,1,2,2,1,1,2,2, 1,1,1,1,1,1,1,1,0,0,0,0,2,2,2,2,
        1,1,1,1,0,0,0,0,0,0,0,0,2,2,2,2, 1,1,1,1,2,2,2,2,0,0,0,0,0,0,0,0,
        1,1,2,0,1,1,2,0,1,1,2,0,1,1,2,0, 0,1,1,2,0,1,1,2,0,1,1,2,0,1,1,2,
        0,2,1,1,0,2,1,1,0,2,1,1,0,2,1,1, 2,0,0,0,2,0,0,0,2,1,1,1,2,1,1,1,
        2,0,1,2,2,0,1,2,2,0,1,2,2,0,1,2, 1,1,1,1,0,0,0,0,2,2,2,2,1,1,1,1,
        0,0,2,2,0,0,1,1,0,0,1,1,0,0,2,2,
    ]  # fmt: skip


def _anchors3() -> List[Int]:
    """Return each three-subset partition's anchor texels."""
    return [
        0, 8, 10, 8, 0, 12, 4, 0, 12, 8, 0, 4, 3, 0, 2, 0, 1, 3, 0, 2, 1,
        1, 9, 0, 1, 2, 0, 4, 0, 8, 0, 6, 2,
    ]  # fmt: skip


def _patterns7() -> List[Int]:
    """Return the nineteen two-subset partitions of mode 7, which come
    from BC7's three-subset partitions."""
    return [
        0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0, 0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,
        1,1,0,0,1,1,0,0,1,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,1,0,0,1,1,0,0,1,1,
        1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1, 0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,
        0,0,0,1,0,0,1,1,1,1,1,1,1,1,1,1, 0,1,1,1,0,0,1,1,0,0,1,1,0,0,1,1,
        1,1,0,0,0,0,0,0,0,0,1,1,1,1,0,0, 0,1,1,1,0,1,1,1,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,1,1,1,0,1,1,1,0, 1,1,0,0,0,0,0,0,0,0,0,0,1,1,0,0,
        0,1,1,1,0,0,1,1,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,0, 1,1,0,0,1,1,0,0,1,1,0,0,1,0,0,0,
        1,1,1,1,1,1,1,1,1,0,0,0,1,0,0,0, 0,0,1,1,0,1,1,0,1,1,0,0,1,0,0,0,
        1,1,1,1,0,1,1,1,0,0,0,0,0,0,0,0,
    ]  # fmt: skip


def _anchors7() -> List[Int]:
    """Return each mode 7 partition's anchor texels."""
    return [
        0, 4, 0, 0, 2, 0, 2, 0, 0, 0, 7, 0, 8, 0, 0, 0, 1, 0, 0, 3, 0,
        0, 1, 0, 2, 0, 0, 0, 1, 0, 0, 8, 0, 2, 0, 0, 0, 1, 0, 0, 7, 0,
        12, 0, 0, 2, 0, 0, 9, 0, 0, 0, 2, 0, 4, 0, 0,
    ]  # fmt: skip


def _weights() -> List[List[Int]]:
    """Return the weight, out of 64, of each value of one to five bits."""
    return [
        [0, 64],
        [0, 21, 43, 64],
        [0, 9, 18, 27, 37, 46, 55, 64],
        [0, 4, 8, 12, 17, 21, 25, 29, 35, 39, 43, 47, 52, 56, 60, 64],
        [
            0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30,
            34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54, 56, 58, 60, 62, 64,
        ],
    ]  # fmt: skip


def unquantize_endpoint(value: Int, quant: Int) -> Int:
    """Return an ASTC endpoint value as eight bits.

    A range of bits only repeats the bits down to eight. A range with a
    trit or a quint combines that digit, the constant `C` and the bit
    pattern `B` of the range, as the ASTC specification defines.

    Args:
        value: The stored value: its digit above its low bits.
        quant: The ASTC range, 0 to 20.

    Returns:
        The endpoint, 0 to 255.
    """
    var table = _bise_ranges()
    var bits = table[quant * 3]
    var low = value & ((1 << bits) - 1)
    var digit = value >> bits
    var c = _unquant_c()[quant]
    if c == 0:
        var result = 0
        var left = 8
        while left > 0:
            var n = min(left, bits)
            result |= (low >> (bits - n)) << (left - n)
            left -= n
        return result
    var b = 0
    for source in _unquant_b()[quant]:  # pragma: no branch
        b <<= 1
        if source >= 0:
            b |= (low >> source) & 1
    var a = 511 if (low & 1) == 1 else 0
    var result = (digit * c + b) ^ a
    return (a & 0x80) | (result >> 2)


struct UastcTables(Movable):
    """The fixed tables every UASTC block reads, built once per image
    rather than once per block."""

    var prefix: List[Int]
    """The mode of each value of a block's first seven bits."""
    var modes: List[Int]
    """Eight numbers per mode; see `_mode_table`."""
    var ranges: List[Int]
    """The bits, trits and quints of each ASTC range."""
    var unquantized: List[List[Int]]
    """Each ASTC range's endpoint values unquantized to eight bits."""
    var patterns: List[List[Int]]
    """The two-subset, three-subset and mode 7 partitions."""
    var anchors: List[List[Int]]
    """Their anchor texels, three per partition."""
    var weights: List[List[Int]]
    """The weight out of 64 of each value of one to five bits."""

    def __init__(out self):
        """Build the tables."""
        self.prefix = _modes_of_prefix()
        self.modes = _mode_table()
        self.ranges = _bise_ranges()
        self.unquantized = List[List[Int]](length=21, fill=List[Int]())
        # Only the ranges some mode uses: ASTC gives no constant `C` for
        # the ranges of a lone trit or quint.
        for mode in range(UASTC_MODES):  # pragma: no branch
            var quant = self.modes[mode * MODE_COLUMNS + 3]
            if len(self.unquantized[quant]) == 0:
                var levels = (
                    1
                    + 2 * self.ranges[quant * 3 + 1]
                    + 4 * self.ranges[quant * 3 + 2]
                ) << self.ranges[quant * 3]
                for value in range(levels):  # pragma: no branch
                    self.unquantized[quant].append(
                        unquantize_endpoint(value, quant)
                    )
        self.patterns = [_patterns2(), _patterns3(), _patterns7()]
        self.anchors = [_anchors2(), _anchors3(), _anchors7()]
        self.weights = _weights()


struct _Reader(Movable):
    """A reader of one 16-byte block from its lowest bit up."""

    var bytes: List[UInt8]
    var position: Int

    def __init__(out self, data: List[UInt8], at: Int):
        self.bytes = List[UInt8](data[at : at + UASTC_BLOCK_BYTES])
        self.position = 0

    def read(mut self, count: Int) -> Int:
        """Return the next `count` bits, low first, and move past them."""
        var value = 0
        for bit in range(count):
            var index = self.position + bit
            value |= ((Int(self.bytes[index >> 3]) >> (index & 7)) & 1) << bit
        self.position += count
        return value


def _interpolate(low: Int, high: Int, weight: Int) -> Int:
    """Return two 8-bit endpoints blended by a weight out of 64, widened to
    sixteen bits as an ASTC decoder in its linear mode widens them."""
    var blend = (low * 257 * (64 - weight) + high * 257 * weight + 32) >> 6
    return blend >> 8


def _endpoints(
    mut reader: _Reader, count: Int, quant: Int, tables: UastcTables
) -> List[Int]:
    """Read `count` endpoint values of an ASTC range and unquantize them.

    The trit or quint digits come first, five trits to eight bits or
    three quints to seven, with a shorter last group. Then come each
    value's low bits.
    """
    var bits = tables.ranges[quant * 3]
    var trits = tables.ranges[quant * 3 + 1]
    var quints = tables.ranges[quant * 3 + 2]
    var base = 3 if trits == 1 else 5
    var group = 5 if trits == 1 else 3
    # The bits of a group of one to five trits, or one to three quints.
    var group_bits: List[Int] = [0, 3, 5, 7]
    if trits == 1:
        group_bits = [0, 2, 4, 5, 7, 8]
    var groups = 0
    if trits + quints > 0:
        groups = (count + group - 1) // group
    var digits = List[Int]()
    for index in range(groups):
        var size = min(group, count - index * group)
        var packed = reader.read(group_bits[size])
        for _ in range(size):  # pragma: no branch
            digits.append(packed % base)
            packed //= base
    var values = List[Int]()
    for index in range(count):  # pragma: no branch
        var value = reader.read(bits)
        if groups > 0:
            value |= digits[index] << bits
        values.append(tables.unquantized[quant][value])
    return values^


def uastc_block(
    data: List[UInt8], at: Int, tables: UastcTables
) raises -> List[UInt8]:
    """Return one UASTC block as sixty-four RGBA bytes, row-major.

    Args:
        data: The blocks.
        at: Where this block starts; sixteen bytes must follow.
        tables: The fixed tables.

    Returns:
        The sixteen texels, red, green, blue and alpha each.

    Raises:
        Error: If the block names the reserved mode, or a partition its
            mode does not have.
    """
    var reader = _Reader(data, at)
    var mode = tables.prefix[Int(data[at]) & 127]
    if mode >= UASTC_MODES:
        raise Error("UASTC: a block uses the reserved mode 19")
    var row = mode * MODE_COLUMNS
    reader.position = tables.modes[row]
    var out = List[UInt8](length=64, fill=0)
    if mode == SOLID_MODE:
        var color = List[Int]()
        for _ in range(4):  # pragma: no branch
            color.append(reader.read(8))
        for texel in range(16):  # pragma: no branch
            for channel in range(4):  # pragma: no branch
                out[texel * 4 + channel] = UInt8(color[channel])
        return out^
    reader.position += tables.modes[row + 1]
    var weight_bits = tables.modes[row + 2]
    var quant = tables.modes[row + 3]
    var comps = tables.modes[row + 4]
    var subsets = tables.modes[row + 5]
    var planes = tables.modes[row + 6]
    # Which partition table: none, two subsets, three, or mode 7's.
    var table = subsets - 2
    if mode == 7:
        table = 2
    var partition = 0
    if subsets > 1:
        partition = reader.read(7 - subsets)
        if partition * 16 >= len(tables.patterns[table]):
            raise Error(
                "UASTC: a block names a partition its mode does not have"
            )
    var ccs = tables.modes[row + 7]
    if ccs < 0:
        ccs = reader.read(2)
    var values = _endpoints(reader, comps * 2 * subsets, quant, tables)
    var subset = List[Int](length=16, fill=0)
    var anchor = List[Bool](length=16, fill=False)
    anchor[0] = True
    if subsets > 1:
        for texel in range(16):  # pragma: no branch
            subset[texel] = tables.patterns[table][partition * 16 + texel]
        for index in range(3):  # pragma: no branch
            anchor[tables.anchors[table][partition * 3 + index]] = True
    var weights = List[Int]()
    for index in range(16 * planes):  # pragma: no branch
        var texel = index // planes
        weights.append(reader.read(weight_bits - Int(anchor[texel])))
    # Each subset's endpoints as RGBA: RGB, RGBA, or luminance and alpha.
    var ends = List[Int]()
    for index in range(subsets):  # pragma: no branch
        var e = List[Int](values[index * comps * 2 : (index + 1) * comps * 2])
        if comps == 2:
            ends.extend([e[0], e[0], e[0], e[2], e[1], e[1], e[1], e[3]])
        elif comps == 3:
            ends.extend([e[0], e[2], e[4], 255, e[1], e[3], e[5], 255])
        else:
            ends.extend([e[0], e[2], e[4], e[6], e[1], e[3], e[5], e[7]])
    var steps = tables.weights[weight_bits - 1].copy()
    for texel in range(16):  # pragma: no branch
        var first = subset[texel] * 8
        for channel in range(4):  # pragma: no branch
            var weight = weights[texel * planes]
            if channel == ccs:
                weight = weights[texel * 2 + 1]
            out[texel * 4 + channel] = UInt8(
                _interpolate(
                    ends[first + channel],
                    ends[first + 4 + channel],
                    steps[weight],
                )
            )
    return out^


def uastc_image(
    width: Int, height: Int, data: List[UInt8]
) raises -> List[UInt8]:
    """Return an image of UASTC blocks as RGBA bytes, row-major.

    Args:
        width: The image's width in texels.
        height: Its height.
        data: The blocks, row by row, sixteen bytes each.

    Returns:
        `width * height * 4` bytes; texels past the edge of a block row or
        column are dropped.

    Raises:
        Error: If `data` is not one block per four by four texels, or a
            block is malformed; see `uastc_block`.
    """
    var across = (width + 3) // 4
    var down = (height + 3) // 4
    if len(data) != across * down * UASTC_BLOCK_BYTES:
        raise Error("UASTC: the data is not one block per 4x4 texels")
    var tables = UastcTables()
    var out = List[UInt8](length=width * height * 4, fill=0)
    for by in range(down):  # pragma: no branch
        for bx in range(across):  # pragma: no branch
            var block = uastc_block(
                data, (by * across + bx) * UASTC_BLOCK_BYTES, tables
            )
            for y in range(min(4, height - by * 4)):  # pragma: no branch
                for x in range(min(4, width - bx * 4)):  # pragma: no branch
                    var to = ((by * 4 + y) * width + bx * 4 + x) * 4
                    for channel in range(4):  # pragma: no branch
                        out[to + channel] = block[(y * 4 + x) * 4 + channel]
    return out^
