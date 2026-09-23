# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Basis Universal UASTC HDR 4x4 blocks decoded to RGBA floats, ported
from `unpack_block` and `decode_block` in Binomial's
`basisu_astc_helpers.h` (Apache-2.0), Basis Universal 1.50.

A KTX 2.0 file with the UASTC HDR color model holds one 16-byte block for
each 4x4 texels. three.js transcodes these blocks with the Basis Universal
WebAssembly transcoder: to BC6H if the GPU takes it, and otherwise to
`RGBA_HALF`, four half floats a texel. Here they decode on the host to
the texels of that `RGBA_HALF` target, widened to floats.

**A UASTC HDR block is an ASTC 4x4 block.** The transcoder decodes it
with a whole ASTC decoder, and so does this module. Every ASTC feature
that fits a 4x4 block is read:

    void extent   one color for the block, LDR or HDR
    weight grid   2x2 to 4x4 weights, interpolated up to the 4x4 texels
    dual plane    one channel takes a second weight
    partitions    one to four, from ASTC's partition hash
    endpoints     all sixteen color endpoint modes, LDR and HDR

**Values are bounded integer sequences.** A range with trits or quints
packs five trits into eight bits or three quints into seven, spread
between the values' low bits, as the ASTC specification defines. The
endpoints run forward from the block's configuration, and the weights
run backward from its top bit.

**The output is half floats.** An HDR endpoint interpolates in ASTC's
logarithmic encoding and becomes a half through `qlog16_to_half`. An LDR
endpoint interpolates in sixteen bits and becomes a half by truncation,
as ASTC's decode to half floats requires. A result that is an infinity
or a NaN becomes the largest finite half, as the transcoder writes it.

**A malformed block is refused.** The transcoder fails the whole image
when one block does not unpack, and three.js throws. Here the decode
raises.
"""

from render.exr import half_to_float
from render.uastc import UASTC_BLOCK_BYTES, bise_ranges, unquantize_endpoint

# The largest weight grid a 4x4 block can use, and the most endpoints.
comptime MAX_GRID_WEIGHTS = 64
comptime MAX_ENDPOINT_VALUES = 18
# The lowest endpoint range ASTC allows, and the highest weight range.
comptime FIRST_ENDPOINT_RANGE = 4
comptime LAST_WEIGHT_RANGE = 11
# The half floats of one and of the largest finite number.
comptime HALF_ONE = 0x3C00
comptime HALF_MAX = 0x7BFF


@fieldwise_init
struct EndpointMode(Equatable, ImplicitlyCopyable, Writable):
    """An ASTC color endpoint mode, as a type rather than a bare int.

    `is_valid` is True for ASTC's sixteen modes, 0 to 15. Modes 2, 3, 7,
    11, 14 and 15 are HDR; the rest are LDR.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for one of the sixteen modes."""
        return self.value >= 0 and self.value <= 15

    def is_ldr(self) -> Bool:
        """Return True for an LDR mode, whose endpoints are eight bits."""
        var v = self.value
        return v != 2 and v != 3 and v != 7 and v != 11 and v < 14

    def values(self) -> Int:
        """Return how many values the mode stores: two per channel."""
        return 2 + 2 * (self.value >> 2)

    def write_to(self, mut writer: Some[Writer]):
        """Write the mode's number.

        Args:
            writer: Where to write it.
        """
        writer.write("EndpointMode(", self.value, ")")


# The HDR mode whose alpha stays LDR beside HDR color, and the one whose
# alpha is HDR too.
comptime HDR_RGB_LDR_ALPHA = EndpointMode(14)
comptime HDR_RGB_HDR_ALPHA = EndpointMode(15)


def _trits() -> List[Int]:
    """Return the five trits each value of eight bits packs, as one number
    in base three, lowest trit first."""
    return [
        0, 1, 2, 18, 3, 4, 5, 19, 6, 7, 8, 20, 24, 25, 26, 20,
        9, 10, 11, 21, 12, 13, 14, 22, 15, 16, 17, 23, 216, 217, 218, 234,
        27, 28, 29, 45, 30, 31, 32, 46, 33, 34, 35, 47, 51, 52, 53, 47,
        36, 37, 38, 48, 39, 40, 41, 49, 42, 43, 44, 50, 219, 220, 221, 235,
        54, 55, 56, 72, 57, 58, 59, 73, 60, 61, 62, 74, 78, 79, 80, 74,
        63, 64, 65, 75, 66, 67, 68, 76, 69, 70, 71, 77, 222, 223, 224, 236,
        162, 163, 164, 180, 165, 166, 167, 181, 168, 169, 170, 182, 186, 187, 188, 182,
        171, 172, 173, 183, 174, 175, 176, 184, 177, 178, 179, 185, 240, 241, 242, 236,
        81, 82, 83, 99, 84, 85, 86, 100, 87, 88, 89, 101, 105, 106, 107, 101,
        90, 91, 92, 102, 93, 94, 95, 103, 96, 97, 98, 104, 225, 226, 227, 237,
        108, 109, 110, 126, 111, 112, 113, 127, 114, 115, 116, 128, 132, 133, 134, 128,
        117, 118, 119, 129, 120, 121, 122, 130, 123, 124, 125, 131, 228, 229, 230, 238,
        135, 136, 137, 153, 138, 139, 140, 154, 141, 142, 143, 155, 159, 160, 161, 155,
        144, 145, 146, 156, 147, 148, 149, 157, 150, 151, 152, 158, 231, 232, 233, 239,
        189, 190, 191, 207, 192, 193, 194, 208, 195, 196, 197, 209, 213, 214, 215, 209,
        198, 199, 200, 210, 201, 202, 203, 211, 204, 205, 206, 212, 240, 241, 242, 239,
    ]  # fmt: skip


def _quints() -> List[Int]:
    """Return the three quints each value of seven bits packs, as one
    number in base five, lowest quint first."""
    return [
        0, 1, 2, 3, 4, 20, 24, 124, 5, 6, 7, 8, 9, 21, 49, 124,
        10, 11, 12, 13, 14, 22, 74, 124, 15, 16, 17, 18, 19, 23, 99, 124,
        25, 26, 27, 28, 29, 45, 104, 120, 30, 31, 32, 33, 34, 46, 109, 121,
        35, 36, 37, 38, 39, 47, 114, 122, 40, 41, 42, 43, 44, 48, 119, 123,
        50, 51, 52, 53, 54, 70, 102, 103, 55, 56, 57, 58, 59, 71, 107, 108,
        60, 61, 62, 63, 64, 72, 112, 113, 65, 66, 67, 68, 69, 73, 117, 118,
        75, 76, 77, 78, 79, 95, 100, 101, 80, 81, 82, 83, 84, 96, 105, 106,
        85, 86, 87, 88, 89, 97, 110, 111, 90, 91, 92, 93, 94, 98, 115, 116,
    ]  # fmt: skip


def _rows() -> List[Int]:
    """Return the eleven numbers of each of ASTC's ten block mode layouts:
    where the dual plane bit and the precision bit are, where the grid
    width and height bits are and how many there are, the width and height
    they add to, and where the three range bits are. -1 is a bit the
    layout does not have."""
    return [
        10, 9, 7, 2, 5, 2, 4, 2, 4, 0, 1,
        10, 9, 7, 2, 5, 2, 8, 2, 4, 0, 1,
        10, 9, 5, 2, 7, 2, 2, 8, 4, 0, 1,
        10, 9, 5, 2, 7, 1, 2, 6, 4, 0, 1,
        10, 9, 7, 1, 5, 2, 2, 2, 4, 0, 1,
        10, 9, 0, 0, 5, 2, 12, 2, 4, 2, 3,
        10, 9, 5, 2, 0, 0, 2, 12, 4, 2, 3,
        10, 9, 0, 0, 0, 0, 6, 10, 4, 2, 3,
        10, 9, 0, 0, 0, 0, 10, 6, 4, 2, 3,
        -1, -1, 5, 2, 9, 2, 6, 6, 4, 2, 3,
    ]  # fmt: skip


def _row_of_low_bits() -> List[Int]:
    """Return the layout of a block whose two lowest bits are not zero, by
    bits 2, 3 and 8."""
    return [0, 1, 2, 3, 0, 1, 2, 4]


def _row_of_high_bits() -> List[Int]:
    """Return the layout of a block whose two lowest bits are zero, by bits
    5 to 8. The last two are the reserved and void-extent patterns, which
    are read before a layout is."""
    return [5, 5, 5, 5, 6, 6, 6, 6, 9, 9, 9, 9, 7, 8, 9, 9]


def sequence_bits(count: Int, quant: Int, ranges: List[Int]) -> Int:
    """Return how many bits `count` values of an ASTC range take.

    Args:
        count: How many values.
        quant: The ASTC range, 0 to 20.
        ranges: The bits, trits and quints of each range; see
            `render.uastc.bise_ranges`.

    Returns:
        The bits, with a last group of trits or quints rounded up.
    """
    return (
        ranges[quant * 3] * count
        + (ranges[quant * 3 + 1] * 8 * count + 4) // 5
        + (ranges[quant * 3 + 2] * 7 * count + 2) // 3
    )


def unquantize_weight(value: Int, quant: Int, ranges: List[Int]) -> Int:
    """Return an ASTC weight as a number out of 64.

    A range of bits only repeats the bits down to six. A range with a trit
    or a quint combines that digit, the constant `C` and the bit pattern
    `B` of the range, as the ASTC specification defines. A result above 32
    moves up one, so the largest is 64.

    Args:
        value: The stored value: its digit above its low bits.
        quant: The ASTC range, 0 to 11.
        ranges: The bits, trits and quints of each range.

    Returns:
        The weight, 0 to 64.
    """
    var bits = ranges[quant * 3]
    var digits = ranges[quant * 3 + 1] + ranges[quant * 3 + 2]
    var result: Int
    if digits == 0:
        # Bits only: repeat them down to six.
        result = 0
        var shift = 6 - bits
        while shift > -bits:
            result |= value << shift if shift >= 0 else value >> -shift
            shift -= bits
    elif bits == 0:
        # A lone trit or quint.
        var three: List[Int] = [0, 32, 63]
        var five: List[Int] = [0, 16, 32, 47, 63]
        result = three[value] if ranges[quant * 3 + 1] == 1 else five[value]
    else:
        var low = value & ((1 << bits) - 1)
        var digit = value >> bits
        var index = bits * 2 + ranges[quant * 3 + 2]
        var constants: List[Int] = [50, 28, 23, 13, 11]
        var b_bit = (low >> 1) & 1
        var c_bit = (low >> 2) & 1
        var patterns: List[Int] = [
            0,
            0,
            (b_bit << 6) | (b_bit << 2) | b_bit,
            (b_bit << 6) | (b_bit << 1),
            (c_bit << 6) | (b_bit << 5) | (c_bit << 1) | b_bit,
        ]
        var a = 0x7F if (low & 1) == 1 else 0
        var mixed = (digit * constants[index - 2] + patterns[index - 2]) ^ a
        result = (a & 0x20) | (mixed >> 2)
    return result + 1 if result > 32 else result


def qlog16_to_half(value: Int) -> Int:
    """Return an ASTC HDR value, sixteen bits of its logarithmic encoding,
    as a half float's bits.

    Args:
        value: The interpolated value, 0 to 0xFFFF.

    Returns:
        The half's bits: the top five bits are the exponent, and the
        mantissa is mapped piecewise linearly.
    """
    var exponent = (value & 0xF800) >> 11
    var mantissa = value & 0x7FF
    var mapped = 3 * mantissa if mantissa < 512 else (
        5 * mantissa - 2048 if mantissa >= 1536 else 4 * mantissa - 512
    )
    return (exponent << 10) + (mapped >> 3)


def unorm16_to_half(value: Int) -> Int:
    """Return a sixteen-bit LDR value, out of 65536, as a half float
    truncated toward zero, as ASTC's decode to half floats requires.

    The transcoder converts `value / 65536` through a float. That float is
    exact, and its truncation to a half is computed here in integers.

    Args:
        value: The value, 0 to 0xFFFE; the caller maps 0xFFFF to one.

    Returns:
        The half's bits.
    """
    if value < 4:
        # Below 2^-14: a subnormal half, the value times 2^8.
        return value << 8
    var top = 2
    while (value >> (top + 1)) > 0:
        top += 1
    var fraction = value - (1 << top)
    var mantissa = fraction << (10 - top) if top <= 10 else fraction >> (
        top - 10
    )
    return ((top - 1) << 10) | mantissa


def _hash52(seed: UInt32) -> UInt32:
    """Return ASTC's partition hash of a seed."""
    var p = seed
    p ^= p >> 15
    p -= p << 17
    p += p << 7
    p += p << 4
    p ^= p >> 5
    p += p << 16
    p ^= p >> 7
    p ^= p >> 3
    p ^= p << 6
    p ^= p >> 17
    return p


def partition_of(seed: Int, x: Int, y: Int, partitions: Int) -> Int:
    """Return which partition a texel of a 4x4 block is in.

    ASTC's `compute_texel_partition` for a block of fewer than 31 texels,
    which doubles the texel's coordinates.

    Args:
        seed: The block's ten-bit partition index.
        x: The texel's column, 0 to 3.
        y: Its row, 0 to 3.
        partitions: How many partitions, 2 to 4.

    Returns:
        The partition, 0 to `partitions - 1`.
    """
    var full = UInt32(seed + 1024 * (partitions - 1))
    var number = _hash52(full)
    # The seeds that weigh a third coordinate are left out: a 2D block's
    # is zero.
    var seeds = List[Int]()
    for shift in range(0, 32, 4):  # pragma: no branch
        var nibble = Int((number >> UInt32(shift)) & 0xF)
        seeds.append(nibble * nibble)
    var sh_a = 4 if (full & 2) != 0 else 5
    var sh_b = 6 if partitions == 3 else 5
    var sh1 = sh_a if (full & 1) != 0 else sh_b
    var sh2 = sh_b if (full & 1) != 0 else sh_a
    var px = x << 1
    var py = y << 1
    var r = Int(number)
    var a = 0x3F & ((seeds[0] >> sh1) * px + (seeds[1] >> sh2) * py + (r >> 14))
    var b = 0x3F & ((seeds[2] >> sh1) * px + (seeds[3] >> sh2) * py + (r >> 10))
    var c = 0x3F & ((seeds[4] >> sh1) * px + (seeds[5] >> sh2) * py + (r >> 6))
    var d = 0x3F & ((seeds[6] >> sh1) * px + (seeds[7] >> sh2) * py + (r >> 2))
    c = c if partitions >= 3 else 0
    d = d if partitions >= 4 else 0
    return 0 if (a >= b and a >= c and a >= d) else (
        1 if (b >= c and b >= d) else (2 if c >= d else 3)
    )


struct AstcTables(Movable):
    """The fixed tables every ASTC block reads, built once per image
    rather than once per block."""

    var ranges: List[Int]
    """The bits, trits and quints of each ASTC range."""
    var trits: List[Int]
    """The trits of each packed value of eight bits, in base three."""
    var quints: List[Int]
    """The quints of each packed value of seven bits, in base five."""
    var endpoints: List[List[Int]]
    """Each endpoint range's values unquantized to eight bits; empty below
    range 4."""
    var weights: List[List[Int]]
    """Each weight range's values unquantized to a number out of 64."""
    var rows: List[Int]
    """The ten block mode layouts; see `_rows`."""

    def __init__(out self):
        """Build the tables."""
        self.ranges = bise_ranges()
        self.trits = _trits()
        self.quints = _quints()
        self.rows = _rows()
        self.endpoints = List[List[Int]]()
        self.weights = List[List[Int]]()
        for quant in range(21):  # pragma: no branch
            var levels = (
                1
                + 2 * self.ranges[quant * 3 + 1]
                + 4 * self.ranges[quant * 3 + 2]
            ) << self.ranges[quant * 3]
            var endpoint_values = List[Int]()
            var weight_values = List[Int]()
            for value in range(levels):  # pragma: no branch
                if quant >= FIRST_ENDPOINT_RANGE:
                    endpoint_values.append(unquantize_endpoint(value, quant))
                if quant <= LAST_WEIGHT_RANGE:
                    weight_values.append(
                        unquantize_weight(value, quant, self.ranges)
                    )
            self.endpoints.append(endpoint_values^)
            self.weights.append(weight_values^)


struct _Bits(Movable):
    """The 128 bits of one block, lowest first, read forward or from the
    top down."""

    var bits: List[Int]
    var reversed: Bool

    def __init__(out self, data: List[UInt8], at: Int, reversed: Bool):
        self.bits = List[Int](capacity=128)
        self.reversed = reversed
        for index in range(128):  # pragma: no branch
            var bit = 127 - index if reversed else index
            self.bits.append((Int(data[at + (bit >> 3)]) >> (bit & 7)) & 1)

    def get(self, offset: Int, count: Int) -> Int:
        """Return `count` bits from `offset`, the first the lowest."""
        var value = 0
        for index in range(count):
            value |= self.bits[offset + index] << index
        return value


def _decode_values(
    bits: _Bits,
    offset: Int,
    count: Int,
    quant: Int,
    tables: AstcTables,
) -> List[Int]:
    """Return `count` values of an ASTC range, stored from `offset`.

    Values come in groups of five with trits or three with quints. Each
    value's low bits come first, then some bits of the group's packed
    digits: two, two, one, two and one for trits, and three, two and two
    for quints. A range of bits only has no groups.

    Args:
        bits: The block's bits, forward for endpoints and reversed for
            weights.
        offset: Where the first value starts.
        count: How many values to read.
        quant: The ASTC range.
        tables: The fixed tables.

    Returns:
        The values, each its digit above its low bits.
    """
    var low_bits = tables.ranges[quant * 3]
    var trits = tables.ranges[quant * 3 + 1] == 1
    var quints = tables.ranges[quant * 3 + 2] == 1
    var group = 5 if trits else (3 if quints else 1)
    var base = 3 if trits else 5
    var digit_bits: List[Int] = [2, 2, 1, 2, 1] if trits else [3, 2, 2]
    var at = offset
    var out = List[Int]()
    var first = 0
    while first < count:
        var size = min(group, count - first)
        var lows = List[Int]()
        var packed = 0
        var packed_at = 0
        for index in range(size):  # pragma: no branch
            lows.append(bits.get(at, low_bits))
            at += low_bits
            if group > 1:
                packed |= bits.get(at, digit_bits[index]) << packed_at
                at += digit_bits[index]
                packed_at += digit_bits[index]
        var digits = 0
        if trits:
            digits = tables.trits[packed]
        elif quints:
            digits = tables.quints[packed]
        for index in range(size):  # pragma: no branch
            out.append(((digits % base) << low_bits) | lows[index])
            digits //= base
        first += size
    return out^


def _bit_transfer_signed(a: Int, b: Int) -> Tuple[Int, Int]:
    """Return ASTC's `bit_transfer_signed`: `b` takes the top bit of `a`,
    and `a` becomes a signed six-bit offset."""
    var new_b = (b >> 1) | (a & 0x80)
    var new_a = (a >> 1) & 0x3F
    return (new_a - 0x40 if (new_a & 0x20) != 0 else new_a, new_b)


def _clamp(value: Int, top: Int) -> Int:
    """Return a value clamped to 0 to `top`."""
    return max(0, min(top, value))


def _sign_extend(value: Int, bits: Int) -> Int:
    """Return the low `bits` bits of a value as a signed number."""
    var low = value & ((1 << bits) - 1)
    return low - ((low >> (bits - 1)) & 1) * (1 << bits)


def _when(mask: Int, value: Int) -> Int:
    """Return `value` if `mask` is not zero, and zero if it is."""
    return value if mask != 0 else 0


def _blue_contract(r: Int, g: Int, b: Int, a: Int) -> List[Int]:
    """Return ASTC's blue contraction of a color: red and green averaged
    with blue."""
    return [(r + b) >> 1, (g + b) >> 1, b, a]


def _endpoint_pair(low: List[Int], high: List[Int]) -> List[Int]:
    """Return two RGBA endpoints as eight numbers, each channel's low
    endpoint at its index and its high one four past it."""
    var out = low.copy()
    out.extend(high.copy())
    return out^


def _clamped_pair(low: List[Int], high: List[Int]) -> List[Int]:
    """Return two RGBA endpoints clamped to eight bits."""
    var out = List[Int]()
    for value in _endpoint_pair(low, high):  # pragma: no branch
        out.append(_clamp(value, 0xFF))
    return out^


def _hdr_rgb_base_scale(v: List[Int]) -> List[Int]:
    """Return the endpoints of ASTC's HDR RGB base and scale mode, 7."""
    var v0 = v[0]
    var v1 = v[1]
    var v2 = v[2]
    var v3 = v[3]
    var modeval = ((v0 & 0xC0) >> 6) | ((v1 & 0x80) >> 5) | ((v2 & 0x80) >> 4)
    var majcomp: Int
    var mode: Int
    if (modeval & 0xC) != 0xC:
        majcomp = modeval >> 2
        mode = modeval & 3
    elif modeval != 0xF:
        majcomp = modeval & 3
        mode = 4
    else:
        majcomp = 0
        mode = 5
    var red = v0 & 0x3F
    var green = v1 & 0x1F
    var blue = v2 & 0x1F
    var scale = v3 & 0x1F
    var x0 = (v1 >> 6) & 1
    var x1 = (v1 >> 5) & 1
    var x2 = (v2 >> 6) & 1
    var x3 = (v2 >> 5) & 1
    var x4 = (v3 >> 7) & 1
    var x5 = (v3 >> 6) & 1
    var x6 = (v3 >> 5) & 1
    var ohm = 1 << mode
    green |= _when(ohm & 0x30, x0 << 6)
    green |= _when(ohm & 0x3A, x1 << 5)
    blue |= _when(ohm & 0x30, x2 << 6)
    blue |= _when(ohm & 0x3A, x3 << 5)
    scale |= _when(ohm & 0x3D, x6 << 5)
    scale |= _when(ohm & 0x2D, x5 << 6)
    scale |= _when(ohm & 0x04, x4 << 7)
    red |= _when(ohm & 0x3B, x4 << 6)
    red |= _when(ohm & 0x04, x3 << 6)
    red |= _when(ohm & 0x10, x5 << 7)
    red |= _when(ohm & 0x0F, x2 << 7)
    red |= _when(ohm & 0x05, x1 << 8)
    red |= _when(ohm & 0x0A, x0 << 8)
    red |= _when(ohm & 0x05, x0 << 9)
    red |= _when(ohm & 0x02, x6 << 9)
    red |= _when(ohm & 0x01, x3 << 10)
    red |= _when(ohm & 0x02, x5 << 10)
    var shifts: List[Int] = [1, 1, 2, 3, 4, 5]
    var shift = shifts[mode]
    red <<= shift
    green <<= shift
    blue <<= shift
    scale <<= shift
    if mode != 5:
        green = red - green
        blue = red - blue
    var high: List[Int] = [red, green, blue]
    if majcomp == 1:
        high = [green, red, blue]
    elif majcomp == 2:
        high = [blue, green, red]
    return [
        _clamp(high[0] - scale, 0xFFF),
        _clamp(high[1] - scale, 0xFFF),
        _clamp(high[2] - scale, 0xFFF),
        0x780,
        _clamp(high[0], 0xFFF),
        _clamp(high[1], 0xFFF),
        _clamp(high[2], 0xFFF),
        0x780,
    ]


def _hdr_rgb(v: List[Int]) -> List[Int]:
    """Return the color endpoints of ASTC's HDR RGB direct mode, 11, which
    modes 14 and 15 share; alpha is one."""
    var majcomp = ((v[4] & 0x80) >> 7) | ((v[5] & 0x80) >> 6)
    if majcomp == 3:
        return [
            v[0] << 4,
            v[2] << 4,
            (v[4] & 0x7F) << 5,
            0x780,
            v[1] << 4,
            v[3] << 4,
            (v[5] & 0x7F) << 5,
            0x780,
        ]
    var mode = (
        ((v[1] & 0x80) >> 7) | ((v[2] & 0x80) >> 6) | ((v[3] & 0x80) >> 5)
    )
    var va = v[0] | ((v[1] & 0x40) << 2)
    var vb0 = v[2] & 0x3F
    var vb1 = v[3] & 0x3F
    var vc = v[1] & 0x3F
    var d_bits: List[Int] = [7, 6, 7, 6, 5, 6, 5, 6]
    var vd0 = _sign_extend(v[4] & 0x7F, d_bits[mode])
    var vd1 = _sign_extend(v[5] & 0x7F, d_bits[mode])
    var x0 = (v[2] >> 6) & 1
    var x1 = (v[3] >> 6) & 1
    var x2 = (v[4] >> 6) & 1
    var x3 = (v[5] >> 6) & 1
    var x4 = (v[4] >> 5) & 1
    var x5 = (v[5] >> 5) & 1
    var ohm = 1 << mode
    va |= _when(ohm & 0xA4, x0 << 9)
    va |= _when(ohm & 0x08, x2 << 9)
    va |= _when(ohm & 0x50, x4 << 9)
    va |= _when(ohm & 0x50, x5 << 10)
    va |= _when(ohm & 0xA0, x1 << 10)
    va |= _when(ohm & 0xC0, x2 << 11)
    vc |= _when(ohm & 0x04, x1 << 6)
    vc |= _when(ohm & 0xE8, x3 << 6)
    vc |= _when(ohm & 0x20, x2 << 7)
    vb0 |= _when(ohm & 0x5B, x0 << 6)
    vb1 |= _when(ohm & 0x5B, x1 << 6)
    vb0 |= _when(ohm & 0x12, x2 << 7)
    vb1 |= _when(ohm & 0x12, x3 << 7)
    # A shift of a negative offset, as the transcoder's shift of its
    # two's complement bits.
    var scale = 1 << ((mode >> 1) ^ 3)
    va *= scale
    vb0 *= scale
    vb1 *= scale
    vc *= scale
    vd0 *= scale
    vd1 *= scale
    var low: List[Int] = [
        _clamp(va - vc, 0xFFF),
        _clamp(va - vb0 - vc - vd0, 0xFFF),
        _clamp(va - vb1 - vc - vd1, 0xFFF),
    ]
    var high: List[Int] = [
        _clamp(va, 0xFFF),
        _clamp(va - vb0, 0xFFF),
        _clamp(va - vb1, 0xFFF),
    ]
    # Swap the major component back into red's place.
    var order: List[Int] = [0, 1, 2]
    if majcomp == 1:
        order = [1, 0, 2]
    elif majcomp == 2:
        order = [2, 1, 0]
    return [
        low[order[0]],
        low[order[1]],
        low[order[2]],
        0x780,
        high[order[0]],
        high[order[1]],
        high[order[2]],
        0x780,
    ]


def _hdr_alpha(v6: Int, v7: Int) -> Tuple[Int, Int]:
    """Return the HDR alpha endpoints of ASTC's mode 15."""
    var mode = ((v6 >> 7) & 1) | ((v7 >> 6) & 2)
    var low = v6 & 0x7F
    var high = v7 & 0x7F
    if mode == 3:
        return (low << 5, high << 5)
    low |= (high << (mode + 1)) & 0x780
    high &= 0x3F >> mode
    high ^= 0x20 >> mode
    high -= 0x20 >> mode
    low <<= 4 - mode
    high *= 1 << (4 - mode)
    return (low, _clamp(high + low, 0xFFF))


def decode_endpoints(
    endpoint_mode: EndpointMode, v: List[Int]
) raises -> List[Int]:
    """Return one partition's two RGBA endpoints from its values.

    ASTC's `decode_endpoint`. An LDR mode gives eight-bit endpoints. An
    HDR mode gives twelve-bit ones in ASTC's logarithmic encoding, and an
    alpha of 0x780, which decodes to one, unless the mode stores alpha.

    Args:
        endpoint_mode: The color endpoint mode.
        v: The partition's values, unquantized to eight bits: as many as
            the mode's `values`.

    Returns:
        Eight numbers: each channel's low endpoint, red to alpha, then its
        high one.

    Raises:
        Error: If the mode is not one of the sixteen, or `v` is not its
            number of values.
    """
    if not endpoint_mode.is_valid():
        raise Error("UASTC HDR: " + String(endpoint_mode) + " is not a mode")
    if len(v) != endpoint_mode.values():
        raise Error("UASTC HDR: a mode's values are the wrong count")
    var mode = endpoint_mode.value
    if mode == 0:
        return _endpoint_pair(
            [v[0], v[0], v[0], 0xFF], [v[1], v[1], v[1], 0xFF]
        )
    if mode == 1:
        var l0 = (v[0] >> 2) | (v[1] & 0xC0)
        var l1 = min(0xFF, l0 + (v[1] & 0x3F))
        return _endpoint_pair([l0, l0, l0, 0xFF], [l1, l1, l1, 0xFF])
    if mode == 2:
        var y0 = v[0] << 4
        var y1 = v[1] << 4
        if v[1] < v[0]:
            y0 = (v[1] << 4) + 8
            y1 = (v[0] << 4) - 8
        return _endpoint_pair([y0, y0, y0, 0x780], [y1, y1, y1, 0x780])
    if mode == 3:
        var y0: Int
        var d: Int
        if (v[0] & 0x80) != 0:
            y0 = ((v[1] & 0xE0) << 4) | ((v[0] & 0x7F) << 2)
            d = (v[1] & 0x1F) << 2
        else:
            y0 = ((v[1] & 0xF0) << 4) | ((v[0] & 0x7F) << 1)
            d = (v[1] & 0x0F) << 1
        var y1 = min(0xFFF, y0 + d)
        return _endpoint_pair([y0, y0, y0, 0x780], [y1, y1, y1, 0x780])
    if mode == 4:
        return _endpoint_pair(
            [v[0], v[0], v[0], v[2]], [v[1], v[1], v[1], v[3]]
        )
    if mode == 5:
        var lum = _bit_transfer_signed(v[1], v[0])
        var alpha = _bit_transfer_signed(v[3], v[2])
        var l0 = lum[1]
        var l1 = lum[1] + lum[0]
        return _clamped_pair(
            [l0, l0, l0, alpha[1]], [l1, l1, l1, alpha[1] + alpha[0]]
        )
    if mode == 6 or mode == 10:
        var a0 = 0xFF if mode == 6 else v[4]
        var a1 = 0xFF if mode == 6 else v[5]
        return _endpoint_pair(
            [(v[0] * v[3]) >> 8, (v[1] * v[3]) >> 8, (v[2] * v[3]) >> 8, a0],
            [v[0], v[1], v[2], a1],
        )
    if mode == 7:
        return _hdr_rgb_base_scale(v)
    if mode == 8 or mode == 12:
        var a0 = 0xFF if mode == 8 else v[6]
        var a1 = 0xFF if mode == 8 else v[7]
        if v[1] + v[3] + v[5] >= v[0] + v[2] + v[4]:
            return _endpoint_pair(
                [v[0], v[2], v[4], a0], [v[1], v[3], v[5], a1]
            )
        return _endpoint_pair(
            _blue_contract(v[1], v[3], v[5], a1),
            _blue_contract(v[0], v[2], v[4], a0),
        )
    if mode == 9 or mode == 13:
        var r = _bit_transfer_signed(v[1], v[0])
        var g = _bit_transfer_signed(v[3], v[2])
        var b = _bit_transfer_signed(v[5], v[4])
        var a = (0, 0xFF)
        if mode == 13:
            a = _bit_transfer_signed(v[7], v[6])
        if r[0] + g[0] + b[0] >= 0:
            return _clamped_pair(
                [r[1], g[1], b[1], a[1]],
                [r[1] + r[0], g[1] + g[0], b[1] + b[0], a[1] + a[0]],
            )
        return _clamped_pair(
            _blue_contract(r[1] + r[0], g[1] + g[0], b[1] + b[0], a[1] + a[0]),
            _blue_contract(r[1], g[1], b[1], a[1]),
        )
    var out = _hdr_rgb(v)
    if endpoint_mode == HDR_RGB_LDR_ALPHA:
        out[3] = v[6]
        out[7] = v[7]
    elif endpoint_mode == HDR_RGB_HDR_ALPHA:
        var alpha = _hdr_alpha(v[6], v[7])
        out[3] = alpha[0]
        out[7] = alpha[1]
    return out^


def _upsample(grid: List[Int], width: Int, height: Int) -> List[Int]:
    """Return a weight grid interpolated up to the 4x4 texels.

    ASTC's bilinear infill, in sixteenths. A 4x4 grid is the texels'
    weights as they are.

    Args:
        grid: The grid's weights out of 64, row-major.
        width: The grid's width, 2 to 4.
        height: Its height, 2 to 4.

    Returns:
        Sixteen weights out of 64.
    """
    if width * height == 16:
        return grid.copy()
    # Past the grid's end, weights the infill multiplies by zero.
    var padded = grid.copy()
    padded.resize(width * height + width + 2, 0)
    # (1024 + 4 / 2) / (4 - 1), the transcoder's scale for a 4x4 block.
    var scale = 342
    var out = List[Int]()
    for y in range(4):  # pragma: no branch
        for x in range(4):  # pragma: no branch
            var gx = (scale * x * (width - 1) + 32) >> 6
            var gy = (scale * y * (height - 1) + 32) >> 6
            var fx = gx & 0xF
            var fy = gy & 0xF
            var w11 = (fx * fy + 8) >> 4
            var at = (gx >> 4) + (gy >> 4) * width
            var total = (
                8
                + padded[at] * (16 - fx - fy + w11)
                + padded[at + 1] * (fx - w11)
                + padded[at + width] * (fy - w11)
                + padded[at + width + 1] * w11
            )
            out.append(total >> 4)
    return out^


def _void_extent(bits: _Bits) raises -> List[Int]:
    """Return the four half floats of a void-extent block's one color.

    Raises:
        Error: If the block sets its reserved bits, names an empty extent,
            or holds an HDR infinity or NaN.
    """
    if bits.get(10, 2) != 3:
        raise Error("UASTC HDR: a void-extent block sets its reserved bits")
    var extents = List[Int]()
    for index in range(4):  # pragma: no branch
        extents.append(bits.get(12 + index * 13, 13))
    if _bad_extent(extents):
        raise Error("UASTC HDR: a void-extent block names an empty extent")
    var halves = List[Int]()
    for channel in range(4):  # pragma: no branch
        halves.append(bits.get(64 + channel * 16, 16))
    if bits.get(9, 1) == 1:
        for channel in range(4):  # pragma: no branch
            if ((halves[channel] >> 10) & 0x1F) == 0x1F:
                raise Error(
                    "UASTC HDR: a void-extent block holds an infinity or a NaN"
                )
        return halves^
    var out = List[Int]()
    for channel in range(4):  # pragma: no branch
        var value = halves[channel]
        out.append(HALF_ONE if value == 0xFFFF else unorm16_to_half(value))
    return out^


def _bad_extent(e: List[Int]) -> Bool:
    """Return True if a void extent is neither all ones nor two ordered
    ranges."""
    var all_ones = (
        e[0] == 0x1FFF and e[1] == 0x1FFF and e[2] == 0x1FFF and e[3] == 0x1FFF
    )
    return not all_ones and (e[0] >= e[1] or e[2] >= e[3])


def _reserved(bits: _Bits) -> Bool:
    """Return True if a block's low bits are a reserved block mode that is
    not the void extent's."""
    return bits.get(0, 2) == 0 and bits.get(6, 3) == 7 and bits.get(2, 4) != 15


def _outside_block(width: Int, height: Int) -> Bool:
    """Return True if a weight grid is larger than a 4x4 block."""
    return width > 4 or height > 4


def _bad_weight_count(count: Int, bits: Int) -> Bool:
    """Return True if a block's weights are more than 64, or take fewer
    than 24 bits or more than 96."""
    return count > MAX_GRID_WEIGHTS or bits < 24 or bits > 96


def uastc_hdr_block(
    data: List[UInt8], at: Int, tables: AstcTables
) raises -> List[Int]:
    """Return one ASTC 4x4 block as sixty-four half floats, row-major.

    `astc_helpers::unpack_block` followed by `decode_block` in its
    `cDecodeModeHDR16` mode, as the transcoder's `RGBA_HALF` target calls
    them.

    Args:
        data: The blocks.
        at: Where this block starts; sixteen bytes must follow.
        tables: The fixed tables.

    Returns:
        The sixteen texels' red, green, blue and alpha, each a half's bits.

    Raises:
        Error: If the block uses a reserved block mode or range, a weight
            grid larger than the block, too few or too many weight bits,
            dual planes with four partitions, more endpoint values than
            fit, or a malformed void extent.
    """
    var bits = _Bits(data, at, False)
    if bits.get(0, 4) == 0 or _reserved(bits):
        raise Error("UASTC HDR: a block uses a reserved block mode")
    var out = List[Int](capacity=64)
    if bits.get(0, 9) == 0x1FC:
        var color = _void_extent(bits)
        for _ in range(16):  # pragma: no branch
            out.extend(color.copy())
        return out^
    var row = (
        _row_of_high_bits()[bits.get(5, 4)] if bits.get(0, 2)
        == 0 else _row_of_low_bits()[bits.get(2, 2) + bits.get(8, 1) * 4]
    ) * 11
    var layout = List[Int](tables.rows[row : row + 11])
    var precision = bits.get(layout[1], 1) if layout[1] >= 0 else 0
    var dual = bits.get(layout[0], 1) == 1 if layout[0] >= 0 else False
    var grid_width = layout[6] + bits.get(layout[2], layout[3])
    var grid_height = layout[7] + bits.get(layout[4], layout[5])
    var range_bits = (
        bits.get(layout[8], 1)
        | (bits.get(layout[9], 1) << 1)
        | (bits.get(layout[10], 1) << 2)
    )
    # The range bits are never below two here: the low bits that would
    # make them so are a reserved block mode, refused above.
    if _outside_block(grid_width, grid_height):
        raise Error("UASTC HDR: a block's weight grid is larger than 4x4")
    var weight_range = range_bits - 2 + precision * 6
    var planes = 2 if dual else 1
    var weight_count = planes * grid_width * grid_height
    var weight_bits = sequence_bits(weight_count, weight_range, tables.ranges)
    if _bad_weight_count(weight_count, weight_bits):
        raise Error("UASTC HDR: a block has too few or too many weight bits")
    var partitions = bits.get(11, 2) + 1
    var modes = List[EndpointMode]()
    var seed = 0
    var extra = 0
    if partitions == 1:
        modes.append(EndpointMode(bits.get(13, 4)))
    else:
        if dual and partitions == 4:
            raise Error("UASTC HDR: a dual-plane block has four partitions")
        seed = bits.get(13, 10)
        var mode_bits = bits.get(23, 6)
        var kind = mode_bits & 3
        if kind == 0:
            for _ in range(partitions):  # pragma: no branch
                modes.append(EndpointMode(mode_bits >> 2))
        else:
            # Each partition's class bit, then its two mode bits: the rest
            # of the six bits, followed by the bits below the weights.
            extra = 3 * partitions - 4
            var stream = (mode_bits >> (2 + partitions)) | (
                bits.get(128 - weight_bits - extra, extra) << (4 - partitions)
            )
            for index in range(partitions):  # pragma: no branch
                var high_class = (mode_bits >> (2 + index)) & 1
                modes.append(
                    EndpointMode(
                        (kind - 1 + high_class) * 4
                        + ((stream >> (index * 2)) & 3)
                    )
                )
    var selector = -1
    if dual:
        extra += 2
        selector = bits.get(128 - weight_bits - extra, 2)
    var config_bits = 17 if partitions == 1 else 29
    var remaining = 128 - config_bits - extra - weight_bits
    if remaining < 0:
        raise Error("UASTC HDR: a block's weights leave no room for colors")
    var value_count = 0
    for mode in modes:  # pragma: no branch
        value_count += mode.values()
    if value_count > MAX_ENDPOINT_VALUES:
        raise Error("UASTC HDR: a block has more than 18 endpoint values")
    var endpoint_range = 0
    for quant in range(20, 0, -1):  # pragma: no branch
        if sequence_bits(value_count, quant, tables.ranges) <= remaining:
            endpoint_range = quant
            break
    if endpoint_range < FIRST_ENDPOINT_RANGE:
        raise Error("UASTC HDR: a block's endpoints use a reserved range")
    var stored = _decode_values(
        bits, config_bits, value_count, endpoint_range, tables
    )
    var reversed = _Bits(data, at, True)
    var grid = _decode_values(reversed, 0, weight_count, weight_range, tables)
    var plane_grids = [List[Int](), List[Int]()]
    for index in range(weight_count):  # pragma: no branch
        plane_grids[index % planes].append(
            tables.weights[weight_range][grid[index]]
        )
    var weights = [
        _upsample(plane_grids[0], grid_width, grid_height),
        _upsample(plane_grids[planes - 1], grid_width, grid_height),
    ]
    var ends = List[List[Int]]()
    var next = 0
    for mode in modes:  # pragma: no branch
        var values = List[Int]()
        for index in range(mode.values()):  # pragma: no branch
            values.append(
                tables.endpoints[endpoint_range][stored[next + index]]
            )
        next += len(values)
        ends.append(decode_endpoints(mode, values))
    for texel in range(16):  # pragma: no branch
        var part = 0
        if partitions > 1:
            part = partition_of(seed, texel & 3, texel >> 2, partitions)
        var mode = modes[part]
        for channel in range(4):  # pragma: no branch
            var weight = weights[Int(channel == selector)][texel]
            var low = ends[part][channel]
            var high = ends[part][channel + 4]
            if mode.is_ldr() or (mode == HDR_RGB_LDR_ALPHA and channel == 3):
                var k = (
                    low * 257 * (64 - weight) + high * 257 * weight + 32
                ) >> 6
                out.append(HALF_ONE if k == 0xFFFF else unorm16_to_half(k))
            else:
                var q = (
                    (low << 4) * (64 - weight) + (high << 4) * weight + 32
                ) >> 6
                var half = qlog16_to_half(q)
                out.append(HALF_MAX if ((half >> 10) & 0x1F) == 0x1F else half)
    return out^


def uastc_hdr_image(
    width: Int, height: Int, data: List[UInt8]
) raises -> List[Float32]:
    """Return an image of UASTC HDR 4x4 blocks as RGBA floats, row-major.

    Args:
        width: The image's width in texels.
        height: Its height.
        data: The blocks, row by row, sixteen bytes each.

    Returns:
        `width * height * 4` floats, each the half the transcoder's
        `RGBA_HALF` target gives, exactly. Texels past the edge of a block
        row or column are dropped.

    Raises:
        Error: If `data` is not one block per four by four texels, or a
            block is malformed; see `uastc_hdr_block`.
    """
    var across = (width + 3) // 4
    var down = (height + 3) // 4
    if len(data) != across * down * UASTC_BLOCK_BYTES:
        raise Error("UASTC HDR: the data is not one block per 4x4 texels")
    var tables = AstcTables()
    var out = List[Float32](length=width * height * 4, fill=0)
    for by in range(down):  # pragma: no branch
        for bx in range(across):  # pragma: no branch
            var block = uastc_hdr_block(
                data, (by * across + bx) * UASTC_BLOCK_BYTES, tables
            )
            for y in range(min(4, height - by * 4)):  # pragma: no branch
                for x in range(min(4, width - bx * 4)):  # pragma: no branch
                    var to = ((by * 4 + y) * width + bx * 4 + x) * 4
                    for channel in range(4):  # pragma: no branch
                        out[to + channel] = half_to_float(
                            UInt16(block[(y * 4 + x) * 4 + channel])
                        )
    return out^
