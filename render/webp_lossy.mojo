# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""WebP's lossy bitstream, a VP8 key frame: libwebp 1.6.0's `vp8_dec.c`,
`tree_dec.c`, `quant_dec.c`, `frame_dec.c`, `dsp/dec.c` and its RGBA
output with fancy upsampling.

**What a key frame holds.** Luma at full size and two chroma planes at
half size, in macroblocks of 16 by 16 luma pixels. Each macroblock is
predicted from its decoded neighbors, as one 16 by 16 block or as sixteen
4 by 4 blocks each with its own mode, and a residual is added: quantized
DCT coefficients, with the 16 DC terms of a whole-block prediction
coded apart through a Walsh-Hadamard transform. A boolean arithmetic
coder reads every bit. The first partition holds the headers and the
modes, and one to eight more hold the coefficients, a row of macroblocks
each in turn.

**After the frame.** A loop filter smooths the edges between blocks, by
a strength a segment and a mode. The planes then become RGB: libwebp's
fancy upsampling interpolates each chroma sample between its neighbors,
and its fixed-point conversion turns each YUV triple into RGB.

**Bit for bit.** Every step is integer arithmetic, and this port does it
as libwebp does, including where libwebp departs from the letter of the
specification: its sign bits, its 16-bit coefficients, and its reader's
end of data.

**Errors.** A frame that is not a key frame, is not shown, has an unknown
profile, a zero size or a first partition past its data, or runs out of
data where libwebp checks for it, is refused.
"""

from render.webp_lossy_tables import (
    AC_TABLE,
    BMODES_PROBA,
    COEFFS_PROBA0,
    COEFFS_UPDATE_PROBA,
    DC_TABLE,
)

# The 4x4 modes, then the 16x16 and chroma ones, as libwebp numbers them.
comptime _B_DC = 0
comptime _B_TM = 1
comptime _B_VE = 2
comptime _B_HE = 3
comptime _B_RD = 4
comptime _B_VR = 5
comptime _B_LD = 6
comptime _B_VL = 7
comptime _B_HD = 8
comptime _B_HU = 9
comptime _DC_NO_TOP = 4
comptime _DC_NO_LEFT = 5
comptime _DC_NO_TOP_LEFT = 6

# The work buffer: 32 bytes a row, luma with a row above and columns to
# the left, then the two chroma blocks side by side.
comptime _BPS = 32
comptime _Y_OFF = _BPS + 8
comptime _U_OFF = _Y_OFF + _BPS * 16 + _BPS
comptime _V_OFF = _U_OFF + 16
comptime _YUV_SIZE = _BPS * 17 + _BPS * 9

comptime _ZIGZAG: List[Int] = [
    0,
    1,
    4,
    8,
    5,
    2,
    3,
    6,
    9,
    12,
    13,
    10,
    7,
    11,
    14,
    15,
]
comptime _BANDS: List[Int] = [0, 1, 2, 3, 6, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 0]
comptime _CAT3: List[Int] = [173, 148, 140]
comptime _CAT4: List[Int] = [176, 155, 140, 135]
comptime _CAT5: List[Int] = [180, 157, 141, 134, 130]
comptime _CAT6: List[Int] = [
    254,
    254,
    243,
    230,
    196,
    177,
    153,
    140,
    133,
    130,
    129,
]


def _log2(value: Int) -> Int:
    """Return the highest set bit's position."""
    var v = value
    var n = -1
    while v > 0:
        v >>= 1
        n += 1
    return n


struct _BoolReader(Movable):
    """libwebp's `VP8BitReader`: the boolean decoder, with its range kept
    less one and its end of data marked once, on the first load past it."""

    var data: List[UInt8]
    var pos: Int
    var value: UInt64
    var bits: Int
    var range: Int
    var eof: Bool

    def __init__(out self, var data: List[UInt8]):
        self.data = data^
        self.pos = 0
        self.value = 0
        self.bits = -8
        self.range = 255 - 1
        self.eof = False
        self.load()

    def load(mut self):
        """Load a byte, or mark the end: libwebp's `VP8LoadFinalBytes`."""
        if self.pos < len(self.data):
            self.bits += 8
            self.value = UInt64(self.data[self.pos]) | (self.value << 8)
            self.pos += 1
        elif not self.eof:
            self.value <<= 8
            self.bits += 8
            self.eof = True
        else:
            self.bits = 0

    def bit(mut self, prob: Int) -> Int:
        """Read a bit that is zero with probability `prob` / 256."""
        var range = self.range
        if self.bits < 0:
            self.load()
        var pos = self.bits
        var split = (range * prob) >> 8
        var value = Int((self.value >> UInt64(pos)) & 0xFFFFFFFF)
        var bit: Int
        if value > split:
            range -= split
            self.value -= UInt64(split + 1) << UInt64(pos)
            bit = 1
        else:
            range = split + 1
            bit = 0
        var shift = 7 ^ _log2(range)
        range <<= shift
        self.bits -= shift
        self.range = range - 1
        return bit

    def signed(mut self, v: Int) -> Int:
        """Read a sign for `v`: libwebp's `VP8GetSigned`, which splits the
        range in half and always moves one bit on."""
        if self.bits < 0:
            self.load()
        var pos = self.bits
        var split = self.range >> 1
        var value = Int((self.value >> UInt64(pos)) & 0xFFFFFFFF)
        self.bits -= 1
        if value > split:
            self.range = (self.range - 1) | 1
            self.value -= UInt64(split + 1) << UInt64(pos)
            return -v
        self.range = self.range | 1
        return v

    def value_of(mut self, count: Int) -> Int:
        """Read an unsigned number of `count` bits, highest first."""
        var v = 0
        for b in range(count - 1, -1, -1):  # pragma: no branch
            v |= self.bit(0x80) << b
        return v

    def signed_value(mut self, count: Int) -> Int:
        """Read a magnitude, then its sign."""
        var v = self.value_of(count)
        return -v if self.value_of(1) == 1 else v


def _i16(value: Int) -> Int:
    """Wrap to 16 bits, as libwebp's `int16_t` coefficients wrap."""
    return Int(Int16(value & 0xFFFF))


def _clip8(value: Int) -> UInt8:
    """Clamp to 0 to 255."""
    return UInt8(min(max(value, 0), 255))


def _mul1(a: Int) -> Int:
    return ((a * 20091) >> 16) + a


def _mul2(a: Int) -> Int:
    return (a * 35468) >> 16


def _store(mut buf: List[UInt8], at: Int, v: Int):
    """Add a transform's output, over 8, to a pixel."""
    buf[at] = _clip8(Int(buf[at]) + (v >> 3))


def _transform(coeffs: List[Int], c: Int, mut buf: List[UInt8], dst: Int):
    """The inverse DCT of one 4x4 block: libwebp's `TransformOne_C`."""
    var tmp = List[Int](length=16, fill=0)
    for i in range(4):  # pragma: no branch
        var a = coeffs[c + i] + coeffs[c + i + 8]
        var b = coeffs[c + i] - coeffs[c + i + 8]
        var cc = _mul2(coeffs[c + i + 4]) - _mul1(coeffs[c + i + 12])
        var d = _mul1(coeffs[c + i + 4]) + _mul2(coeffs[c + i + 12])
        tmp[i * 4] = a + d
        tmp[i * 4 + 1] = b + cc
        tmp[i * 4 + 2] = b - cc
        tmp[i * 4 + 3] = a - d
    for i in range(4):  # pragma: no branch
        var dc = tmp[i] + 4
        var a = dc + tmp[i + 8]
        var b = dc - tmp[i + 8]
        var cc = _mul2(tmp[i + 4]) - _mul1(tmp[i + 12])
        var d = _mul1(tmp[i + 4]) + _mul2(tmp[i + 12])
        var row = dst + i * _BPS
        _store(buf, row, a + d)
        _store(buf, row + 1, b + cc)
        _store(buf, row + 2, b - cc)
        _store(buf, row + 3, a - d)


def _transform_ac3(coeffs: List[Int], c: Int, mut buf: List[UInt8], dst: Int):
    """The inverse DCT of a block with only coefficients 0, 1 and 4:
    libwebp's `TransformAC3_C`."""
    var a = coeffs[c] + 4
    var c4 = _mul2(coeffs[c + 4])
    var d4 = _mul1(coeffs[c + 4])
    var c1 = _mul2(coeffs[c + 1])
    var d1 = _mul1(coeffs[c + 1])
    var rows: List[Int] = [a + d4, a + c4, a - c4, a - d4]
    for y in range(4):  # pragma: no branch
        var row = dst + y * _BPS
        _store(buf, row, rows[y] + d1)
        _store(buf, row + 1, rows[y] + c1)
        _store(buf, row + 2, rows[y] - c1)
        _store(buf, row + 3, rows[y] - d1)


def _transform_dc(coeffs: List[Int], c: Int, mut buf: List[UInt8], dst: Int):
    """The inverse DCT of a block with only its DC term."""
    var dc = coeffs[c] + 4
    for y in range(4):  # pragma: no branch
        for x in range(4):  # pragma: no branch
            _store(buf, dst + y * _BPS + x, dc)


def _do_transform(
    bits: UInt32, coeffs: List[Int], c: Int, mut buf: List[UInt8], dst: Int
):
    """Pick the transform that a block's two bits of coefficients need."""
    var kind = bits >> 30
    if kind == 3:
        _transform(coeffs, c, buf, dst)
    elif kind == 2:
        _transform_ac3(coeffs, c, buf, dst)
    elif kind == 1:
        _transform_dc(coeffs, c, buf, dst)


def _do_uv_transform(
    bits: UInt32, coeffs: List[Int], c: Int, mut buf: List[UInt8], dst: Int
):
    """Transform a chroma plane's four blocks: in full when any has an AC
    coefficient, else only the DC terms that are not zero."""
    if bits & 0xFF == 0:
        return
    var offsets: List[Int] = [0, 4, 4 * _BPS, 4 * _BPS + 4]
    if bits & 0xAA != 0:
        for k in range(4):  # pragma: no branch
            _transform(coeffs, c + k * 16, buf, dst + offsets[k])
        return
    for k in range(4):  # pragma: no branch
        if coeffs[c + k * 16] != 0:
            _transform_dc(coeffs, c + k * 16, buf, dst + offsets[k])


def _wht(dc: List[Int], mut out: List[Int]):
    """The inverse Walsh-Hadamard transform of the 16 DC terms, into each
    block's first coefficient: libwebp's `TransformWHT_C`."""
    var tmp = List[Int](length=16, fill=0)
    for i in range(4):  # pragma: no branch
        var a0 = dc[i] + dc[12 + i]
        var a1 = dc[4 + i] + dc[8 + i]
        var a2 = dc[4 + i] - dc[8 + i]
        var a3 = dc[i] - dc[12 + i]
        tmp[i] = a0 + a1
        tmp[8 + i] = a0 - a1
        tmp[4 + i] = a3 + a2
        tmp[12 + i] = a3 - a2
    for i in range(4):  # pragma: no branch
        var dcv = tmp[i * 4] + 3
        var a0 = dcv + tmp[3 + i * 4]
        var a1 = tmp[1 + i * 4] + tmp[2 + i * 4]
        var a2 = tmp[1 + i * 4] - tmp[2 + i * 4]
        var a3 = dcv - tmp[3 + i * 4]
        out[i * 64] = _i16((a0 + a1) >> 3)
        out[i * 64 + 16] = _i16((a3 + a2) >> 3)
        out[i * 64 + 32] = _i16((a0 - a1) >> 3)
        out[i * 64 + 48] = _i16((a3 - a2) >> 3)


# --- prediction -------------------------------------------------------------


def _avg3(a: Int, b: Int, c: Int) -> UInt8:
    return UInt8((a + 2 * b + c + 2) >> 2)


def _avg2(a: Int, b: Int) -> UInt8:
    return UInt8((a + b + 1) >> 1)


def _true_motion(mut buf: List[UInt8], dst: Int, size: Int):
    """Predict each pixel as left plus above less above left."""
    var corner = Int(buf[dst - _BPS - 1])
    for y in range(size):  # pragma: no branch
        var left = Int(buf[dst + y * _BPS - 1])
        for x in range(size):  # pragma: no branch
            buf[dst + y * _BPS + x] = _clip8(
                Int(buf[dst - _BPS + x]) + left - corner
            )


def _fill(mut buf: List[UInt8], dst: Int, size: Int, value: Int):
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            buf[dst + y * _BPS + x] = UInt8(value)


def _predict_large(mut buf: List[UInt8], dst: Int, mode: Int, size: Int):
    """Predict a 16x16 luma or an 8x8 chroma block: DC, true motion,
    vertical, horizontal, or DC without the top, the left, or both."""
    var shift = 5 if size == 16 else 4
    if mode == _B_DC:
        var dc = size
        for j in range(size):  # pragma: no branch
            dc += Int(buf[dst - 1 + j * _BPS]) + Int(buf[dst + j - _BPS])
        _fill(buf, dst, size, dc >> shift)
    elif mode == _B_TM:
        _true_motion(buf, dst, size)
    elif mode == _B_VE:
        for y in range(size):  # pragma: no branch
            for x in range(size):  # pragma: no branch
                buf[dst + y * _BPS + x] = buf[dst - _BPS + x]
    elif mode == _B_HE:
        for y in range(size):  # pragma: no branch
            for x in range(size):  # pragma: no branch
                buf[dst + y * _BPS + x] = buf[dst + y * _BPS - 1]
    elif mode == _DC_NO_TOP:
        var dc = size >> 1
        for j in range(size):  # pragma: no branch
            dc += Int(buf[dst - 1 + j * _BPS])
        _fill(buf, dst, size, dc >> (shift - 1))
    elif mode == _DC_NO_LEFT:
        var dc = size >> 1
        for j in range(size):  # pragma: no branch
            dc += Int(buf[dst + j - _BPS])
        _fill(buf, dst, size, dc >> (shift - 1))
    else:
        _fill(buf, dst, size, 0x80)


def _put(mut buf: List[UInt8], dst: Int, x: Int, y: Int, v: UInt8):
    buf[dst + x + y * _BPS] = v


def _predict4(mut buf: List[UInt8], dst: Int, mode: Int):
    """Predict a 4x4 luma block by one of its ten modes: libwebp's
    `VP8PredLuma4`."""
    var top = dst - _BPS
    if mode == _B_DC:
        var dc = 4
        for i in range(4):  # pragma: no branch
            dc += Int(buf[top + i]) + Int(buf[dst - 1 + (i) * _BPS])
        _fill(buf, dst, 4, dc >> 3)
    elif mode == _B_TM:
        _true_motion(buf, dst, 4)
    elif mode == _B_VE:
        var vals: List[UInt8] = [
            _avg3(Int(buf[top - 1]), Int(buf[top + 0]), Int(buf[top + 1])),
            _avg3(Int(buf[top + 0]), Int(buf[top + 1]), Int(buf[top + 2])),
            _avg3(Int(buf[top + 1]), Int(buf[top + 2]), Int(buf[top + 3])),
            _avg3(Int(buf[top + 2]), Int(buf[top + 3]), Int(buf[top + 4])),
        ]
        for y in range(4):  # pragma: no branch
            for x in range(4):  # pragma: no branch
                _put(buf, dst, x, y, vals[x])
    elif mode == _B_HE:
        var a = Int(buf[top - 1])
        var b = Int(buf[dst - 1 + (0) * _BPS])
        var c = Int(buf[dst - 1 + (1) * _BPS])
        var d = Int(buf[dst - 1 + (2) * _BPS])
        var e = Int(buf[dst - 1 + (3) * _BPS])
        var vals: List[UInt8] = [
            _avg3(a, b, c),
            _avg3(b, c, d),
            _avg3(c, d, e),
            _avg3(d, e, e),
        ]
        for y in range(4):  # pragma: no branch
            for x in range(4):  # pragma: no branch
                _put(buf, dst, x, y, vals[y])
    elif mode == _B_RD:
        var i = Int(buf[dst - 1 + (0) * _BPS])
        var j = Int(buf[dst - 1 + (1) * _BPS])
        var k = Int(buf[dst - 1 + (2) * _BPS])
        var ll = Int(buf[dst - 1 + (3) * _BPS])
        var x0 = Int(buf[top - 1])
        var a = Int(buf[top + 0])
        var b = Int(buf[top + 1])
        var c = Int(buf[top + 2])
        var d = Int(buf[top + 3])
        # Each value runs down a diagonal, x - y constant.
        var diag: List[UInt8] = [
            _avg3(j, k, ll),
            _avg3(i, j, k),
            _avg3(x0, i, j),
            _avg3(a, x0, i),
            _avg3(b, a, x0),
            _avg3(c, b, a),
            _avg3(d, c, b),
        ]
        for y in range(4):  # pragma: no branch
            for x in range(4):  # pragma: no branch
                _put(buf, dst, x, y, diag[x - y + 3])
    elif mode == _B_LD:
        var vals = List[Int]()
        for n in range(8):  # pragma: no branch
            vals.append(Int(buf[top + n]))
        # Each value runs along an antidiagonal, x + y constant.
        for y in range(4):  # pragma: no branch
            for x in range(4):  # pragma: no branch
                var s = x + y
                var v: UInt8
                if s == 6:
                    v = _avg3(vals[6], vals[7], vals[7])
                else:
                    v = _avg3(vals[s], vals[s + 1], vals[s + 2])
                _put(buf, dst, x, y, v)
    elif mode == _B_VR:
        var i = Int(buf[dst - 1 + (0) * _BPS])
        var j = Int(buf[dst - 1 + (1) * _BPS])
        var k = Int(buf[dst - 1 + (2) * _BPS])
        var x0 = Int(buf[top - 1])
        var a = Int(buf[top + 0])
        var b = Int(buf[top + 1])
        var c = Int(buf[top + 2])
        var d = Int(buf[top + 3])
        _put(buf, dst, 0, 0, _avg2(x0, a))
        _put(buf, dst, 1, 2, _avg2(x0, a))
        _put(buf, dst, 1, 0, _avg2(a, b))
        _put(buf, dst, 2, 2, _avg2(a, b))
        _put(buf, dst, 2, 0, _avg2(b, c))
        _put(buf, dst, 3, 2, _avg2(b, c))
        _put(buf, dst, 3, 0, _avg2(c, d))
        _put(buf, dst, 0, 3, _avg3(k, j, i))
        _put(buf, dst, 0, 2, _avg3(j, i, x0))
        _put(buf, dst, 0, 1, _avg3(i, x0, a))
        _put(buf, dst, 1, 3, _avg3(i, x0, a))
        _put(buf, dst, 1, 1, _avg3(x0, a, b))
        _put(buf, dst, 2, 3, _avg3(x0, a, b))
        _put(buf, dst, 2, 1, _avg3(a, b, c))
        _put(buf, dst, 3, 3, _avg3(a, b, c))
        _put(buf, dst, 3, 1, _avg3(b, c, d))
    elif mode == _B_VL:
        var a = Int(buf[top + 0])
        var b = Int(buf[top + 1])
        var c = Int(buf[top + 2])
        var d = Int(buf[top + 3])
        var e = Int(buf[top + 4])
        var f = Int(buf[top + 5])
        var g = Int(buf[top + 6])
        var h = Int(buf[top + 7])
        _put(buf, dst, 0, 0, _avg2(a, b))
        _put(buf, dst, 1, 0, _avg2(b, c))
        _put(buf, dst, 0, 2, _avg2(b, c))
        _put(buf, dst, 2, 0, _avg2(c, d))
        _put(buf, dst, 1, 2, _avg2(c, d))
        _put(buf, dst, 3, 0, _avg2(d, e))
        _put(buf, dst, 2, 2, _avg2(d, e))
        _put(buf, dst, 0, 1, _avg3(a, b, c))
        _put(buf, dst, 1, 1, _avg3(b, c, d))
        _put(buf, dst, 0, 3, _avg3(b, c, d))
        _put(buf, dst, 2, 1, _avg3(c, d, e))
        _put(buf, dst, 1, 3, _avg3(c, d, e))
        _put(buf, dst, 3, 1, _avg3(d, e, f))
        _put(buf, dst, 2, 3, _avg3(d, e, f))
        _put(buf, dst, 3, 2, _avg3(e, f, g))
        _put(buf, dst, 3, 3, _avg3(f, g, h))
    elif mode == _B_HD:
        var i = Int(buf[dst - 1 + (0) * _BPS])
        var j = Int(buf[dst - 1 + (1) * _BPS])
        var k = Int(buf[dst - 1 + (2) * _BPS])
        var ll = Int(buf[dst - 1 + (3) * _BPS])
        var x0 = Int(buf[top - 1])
        var a = Int(buf[top + 0])
        var b = Int(buf[top + 1])
        var c = Int(buf[top + 2])
        _put(buf, dst, 0, 0, _avg2(i, x0))
        _put(buf, dst, 2, 1, _avg2(i, x0))
        _put(buf, dst, 0, 1, _avg2(j, i))
        _put(buf, dst, 2, 2, _avg2(j, i))
        _put(buf, dst, 0, 2, _avg2(k, j))
        _put(buf, dst, 2, 3, _avg2(k, j))
        _put(buf, dst, 0, 3, _avg2(ll, k))
        _put(buf, dst, 3, 0, _avg3(a, b, c))
        _put(buf, dst, 2, 0, _avg3(x0, a, b))
        _put(buf, dst, 1, 0, _avg3(i, x0, a))
        _put(buf, dst, 3, 1, _avg3(i, x0, a))
        _put(buf, dst, 1, 1, _avg3(j, i, x0))
        _put(buf, dst, 3, 2, _avg3(j, i, x0))
        _put(buf, dst, 1, 2, _avg3(k, j, i))
        _put(buf, dst, 3, 3, _avg3(k, j, i))
        _put(buf, dst, 1, 3, _avg3(ll, k, j))
    else:
        var i = Int(buf[dst - 1 + (0) * _BPS])
        var j = Int(buf[dst - 1 + (1) * _BPS])
        var k = Int(buf[dst - 1 + (2) * _BPS])
        var ll = Int(buf[dst - 1 + (3) * _BPS])
        _put(buf, dst, 0, 0, _avg2(i, j))
        _put(buf, dst, 2, 0, _avg2(j, k))
        _put(buf, dst, 0, 1, _avg2(j, k))
        _put(buf, dst, 2, 1, _avg2(k, ll))
        _put(buf, dst, 0, 2, _avg2(k, ll))
        _put(buf, dst, 1, 0, _avg3(i, j, k))
        _put(buf, dst, 3, 0, _avg3(j, k, ll))
        _put(buf, dst, 1, 1, _avg3(j, k, ll))
        _put(buf, dst, 3, 1, _avg3(k, ll, ll))
        _put(buf, dst, 1, 2, _avg3(k, ll, ll))
        for x in range(4):  # pragma: no branch
            _put(buf, dst, x, 3, UInt8(ll))
        _put(buf, dst, 2, 2, UInt8(ll))
        _put(buf, dst, 3, 2, UInt8(ll))


# --- loop filter ------------------------------------------------------------


def _sclip1(v: Int) -> Int:
    return min(max(v, -128), 127)


def _sclip2(v: Int) -> Int:
    return min(max(v, -16), 15)


def _filter2(mut p: List[UInt8], at: Int, step: Int):
    """Adjust the two pixels either side of an edge."""
    var p1 = Int(p[at - 2 * step])
    var p0 = Int(p[at - step])
    var q0 = Int(p[at])
    var q1 = Int(p[at + step])
    var a = 3 * (q0 - p0) + _sclip1(p1 - q1)
    var a1 = _sclip2((a + 4) >> 3)
    var a2 = _sclip2((a + 3) >> 3)
    p[at - step] = _clip8(p0 + a2)
    p[at] = _clip8(q0 - a1)


def _filter4(mut p: List[UInt8], at: Int, step: Int):
    """Adjust the four pixels either side of an inner edge."""
    var p1 = Int(p[at - 2 * step])
    var p0 = Int(p[at - step])
    var q0 = Int(p[at])
    var q1 = Int(p[at + step])
    var a = 3 * (q0 - p0)
    var a1 = _sclip2((a + 4) >> 3)
    var a2 = _sclip2((a + 3) >> 3)
    var a3 = (a1 + 1) >> 1
    p[at - 2 * step] = _clip8(p1 + a3)
    p[at - step] = _clip8(p0 + a2)
    p[at] = _clip8(q0 - a1)
    p[at + step] = _clip8(q1 - a3)


def _filter6(mut p: List[UInt8], at: Int, step: Int):
    """Adjust the six pixels either side of a macroblock edge."""
    var p2 = Int(p[at - 3 * step])
    var p1 = Int(p[at - 2 * step])
    var p0 = Int(p[at - step])
    var q0 = Int(p[at])
    var q1 = Int(p[at + step])
    var q2 = Int(p[at + 2 * step])
    var a = _sclip1(3 * (q0 - p0) + _sclip1(p1 - q1))
    var a1 = (27 * a + 63) >> 7
    var a2 = (18 * a + 63) >> 7
    var a3 = (9 * a + 63) >> 7
    p[at - 3 * step] = _clip8(p2 + a3)
    p[at - 2 * step] = _clip8(p1 + a2)
    p[at - step] = _clip8(p0 + a1)
    p[at] = _clip8(q0 - a1)
    p[at + step] = _clip8(q1 - a2)
    p[at + 2 * step] = _clip8(q2 - a3)


def _hev(p: List[UInt8], at: Int, step: Int, thresh: Int) -> Bool:
    """Return whether the edge has high variance."""
    var p1 = Int(p[at - 2 * step])
    var p0 = Int(p[at - step])
    var q0 = Int(p[at])
    var q1 = Int(p[at + step])
    return abs(p1 - p0) > thresh or abs(q1 - q0) > thresh


def _needs_filter(p: List[UInt8], at: Int, step: Int, t: Int) -> Bool:
    var p1 = Int(p[at - 2 * step])
    var p0 = Int(p[at - step])
    var q0 = Int(p[at])
    var q1 = Int(p[at + step])
    return 4 * abs(p0 - q0) + abs(p1 - q1) <= t


def _needs_filter2(p: List[UInt8], at: Int, step: Int, t: Int, it: Int) -> Bool:
    var p3 = Int(p[at - 4 * step])
    var p2 = Int(p[at - 3 * step])
    var p1 = Int(p[at - 2 * step])
    var p0 = Int(p[at - step])
    var q0 = Int(p[at])
    var q1 = Int(p[at + step])
    var q2 = Int(p[at + 2 * step])
    var q3 = Int(p[at + 3 * step])
    if 4 * abs(p0 - q0) + abs(p1 - q1) > t:
        return False
    return (
        abs(p3 - p2) <= it
        and abs(p2 - p1) <= it
        and abs(p1 - p0) <= it
        and abs(q3 - q2) <= it
        and abs(q2 - q1) <= it
        and abs(q1 - q0) <= it
    )


def _simple(mut p: List[UInt8], at: Int, step: Int, along: Int, thresh: Int):
    """The simple filter across 16 pixels of an edge."""
    var t = 2 * thresh + 1
    for i in range(16):  # pragma: no branch
        if _needs_filter(p, at + i * along, step, t):
            _filter2(p, at + i * along, step)


def _loop(
    mut p: List[UInt8],
    at: Int,
    step: Int,
    along: Int,
    size: Int,
    thresh: Int,
    ithresh: Int,
    hev_thresh: Int,
    inner: Bool,
):
    """The normal filter across `size` pixels of an edge: libwebp's
    `FilterLoop26_C` for a macroblock edge and `FilterLoop24_C` for an
    inner one."""
    var t = 2 * thresh + 1
    for i in range(size):  # pragma: no branch
        var here = at + i * along
        if _needs_filter2(p, here, step, t, ithresh):
            if _hev(p, here, step, hev_thresh):
                _filter2(p, here, step)
            elif inner:
                _filter4(p, here, step)
            else:
                _filter6(p, here, step)


@fieldwise_init
struct _FilterInfo(Copyable, Movable):
    """A macroblock's loop filter: its limit, inner limit, variance
    threshold, and whether its inner edges are filtered."""

    var limit: Int
    var ilevel: Int
    var hev_thresh: Int
    var inner: Bool


struct LossyImage(Movable):
    """A decoded VP8 key frame, as RGBA."""

    var width: Int
    var height: Int
    # Eight-bit RGBA, row by row from the top, opaque.
    var rgba: List[UInt8]

    def __init__(out self, width: Int, height: Int, var rgba: List[UInt8]):
        """Hold a decoded frame.

        Args:
            width: Its width.
            height: Its height.
            rgba: Its pixels.
        """
        self.width = width
        self.height = height
        self.rgba = rgba^


def _slice(bytes: List[UInt8], start: Int, end: Int) -> List[UInt8]:
    var out = List[UInt8](capacity=max(end - start, 0))
    for i in range(start, end):
        out.append(bytes[i])
    return out^


def _clip(v: Int, m: Int) -> Int:
    return min(max(v, 0), m)


def _clip_rgb(value: Int) -> UInt8:
    """Drop six bits of fraction and clamp: libwebp's `VP8Clip8`."""
    if value & ~((256 << 6) - 1) == 0:
        return UInt8(value >> 6)
    return UInt8(0) if value < 0 else UInt8(255)


def _yuv_to_rgb(y: Int, u: Int, v: Int, mut out: List[UInt8], at: Int):
    """Convert one pixel: libwebp's `VP8YuvToRgba`, 14-bit fixed point."""
    var yy = (y * 19077) >> 8
    out[at] = _clip_rgb(yy + ((v * 26149) >> 8) - 14234)
    out[at + 1] = _clip_rgb(yy - ((u * 6419) >> 8) - ((v * 13320) >> 8) + 8708)
    out[at + 2] = _clip_rgb(yy + ((u * 33050) >> 8) - 17685)
    out[at + 3] = 255


def _put_rgb(
    ys: List[UInt8],
    y_stride: Int,
    width: Int,
    mut out: List[UInt8],
    row: Int,
    x: Int,
    u: Int,
    v: Int,
):
    """Convert the pixel at a row and column with the chroma given."""
    _yuv_to_rgb(Int(ys[row * y_stride + x]), u, v, out, (row * width + x) * 4)


def _upsample(
    ys: List[UInt8],
    y_stride: Int,
    us: List[UInt8],
    vs: List[UInt8],
    uv_stride: Int,
    top_row: Int,
    bottom_row: Int,
    top_uv: Int,
    cur_uv: Int,
    width: Int,
    mut out: List[UInt8],
):
    """Convert a pair of rows, or one, interpolating chroma between the
    two chroma rows they lie between: libwebp's `UpsampleRgbaLinePair_C`.
    A row of -1 is not there."""
    var last_pair = (width - 1) >> 1
    var tl_u = Int(us[top_uv * uv_stride])
    var tl_v = Int(vs[top_uv * uv_stride])
    var l_u = Int(us[cur_uv * uv_stride])
    var l_v = Int(vs[cur_uv * uv_stride])
    _put_rgb(
        ys,
        y_stride,
        width,
        out,
        top_row,
        0,
        (3 * tl_u + l_u + 2) >> 2,
        (3 * tl_v + l_v + 2) >> 2,
    )
    if bottom_row >= 0:
        _put_rgb(
            ys,
            y_stride,
            width,
            out,
            bottom_row,
            0,
            (3 * l_u + tl_u + 2) >> 2,
            (3 * l_v + tl_v + 2) >> 2,
        )
    for x in range(1, last_pair + 1):
        var t_u = Int(us[top_uv * uv_stride + x])
        var t_v = Int(vs[top_uv * uv_stride + x])
        var u = Int(us[cur_uv * uv_stride + x])
        var v = Int(vs[cur_uv * uv_stride + x])
        var avg_u = tl_u + t_u + l_u + u + 8
        var avg_v = tl_v + t_v + l_v + v + 8
        var d12_u = (avg_u + 2 * (t_u + l_u)) >> 3
        var d12_v = (avg_v + 2 * (t_v + l_v)) >> 3
        var d03_u = (avg_u + 2 * (tl_u + u)) >> 3
        var d03_v = (avg_v + 2 * (tl_v + v)) >> 3
        _put_rgb(
            ys,
            y_stride,
            width,
            out,
            top_row,
            2 * x - 1,
            (d12_u + tl_u) >> 1,
            (d12_v + tl_v) >> 1,
        )
        _put_rgb(
            ys,
            y_stride,
            width,
            out,
            top_row,
            2 * x,
            (d03_u + t_u) >> 1,
            (d03_v + t_v) >> 1,
        )
        if bottom_row >= 0:
            _put_rgb(
                ys,
                y_stride,
                width,
                out,
                bottom_row,
                2 * x - 1,
                (d03_u + l_u) >> 1,
                (d03_v + l_v) >> 1,
            )
            _put_rgb(
                ys,
                y_stride,
                width,
                out,
                bottom_row,
                2 * x,
                (d12_u + u) >> 1,
                (d12_v + v) >> 1,
            )
        tl_u = t_u
        tl_v = t_v
        l_u = u
        l_v = v
    if width & 1 == 0:
        _put_rgb(
            ys,
            y_stride,
            width,
            out,
            top_row,
            width - 1,
            (3 * tl_u + l_u + 2) >> 2,
            (3 * tl_v + l_v + 2) >> 2,
        )
        if bottom_row >= 0:
            _put_rgb(
                ys,
                y_stride,
                width,
                out,
                bottom_row,
                width - 1,
                (3 * l_u + tl_u + 2) >> 2,
                (3 * l_v + tl_v + 2) >> 2,
            )


def decode_lossy(var data: List[UInt8]) raises -> LossyImage:
    """Decode a VP8 key frame to RGBA: libwebp's `VP8GetInfo`,
    `VP8GetHeaders` and `VP8Decode`, then its RGBA output with fancy
    upsampling.

    Args:
        data: The `VP8 ` chunk's payload.

    Returns:
        The frame, opaque.

    Raises:
        If the frame is not a shown key frame of a known profile and a
        size, or its data is short or malformed where libwebp checks.
    """
    var size = len(data)
    if size < 10:
        raise Error("WebP: the VP8 frame header is too short")
    var tag = Int(data[0]) | (Int(data[1]) << 8) | (Int(data[2]) << 16)
    if Int(data[3]) != 0x9D or Int(data[4]) != 0x01 or Int(data[5]) != 0x2A:
        raise Error("WebP: the VP8 start code is wrong")
    if tag & 1 != 0:
        raise Error("WebP: a VP8 frame that is not a key frame")
    if (tag >> 1) & 7 > 3:
        raise Error("WebP: a VP8 profile that is not known")
    if (tag >> 4) & 1 == 0:
        raise Error("WebP: a VP8 frame that is not shown")
    var partition_length = tag >> 5
    if partition_length >= size:
        raise Error("WebP: the first partition runs past the frame")
    var width = (Int(data[6]) | (Int(data[7]) << 8)) & 0x3FFF
    var height = (Int(data[8]) | (Int(data[9]) << 8)) & 0x3FFF
    if width == 0 or height == 0:
        raise Error("WebP: a VP8 frame with no size")
    if partition_length > size - 10:
        raise Error("WebP: the first partition runs past the frame")
    var mb_w = (width + 15) >> 4
    var mb_h = (height + 15) >> 4
    var br = _BoolReader(_slice(data, 10, 10 + partition_length))
    _ = br.value_of(1)  # color space
    _ = br.value_of(1)  # clamping type

    # Segments.
    var use_segment = br.value_of(1) == 1
    var update_map = False
    var absolute_delta = True
    var quantizer = List[Int](length=4, fill=0)
    var filter_strength = List[Int](length=4, fill=0)
    var segment_proba = List[Int](length=3, fill=255)
    if use_segment:
        update_map = br.value_of(1) == 1
        if br.value_of(1) == 1:
            absolute_delta = br.value_of(1) == 1
            for s in range(4):  # pragma: no branch
                quantizer[s] = br.signed_value(7) if br.value_of(1) == 1 else 0
            for s in range(4):  # pragma: no branch
                filter_strength[s] = (
                    br.signed_value(6) if br.value_of(1) == 1 else 0
                )
        if update_map:
            for s in range(3):  # pragma: no branch
                segment_proba[s] = (
                    br.value_of(8) if br.value_of(1) == 1 else 255
                )
    if br.eof:
        raise Error("WebP: cannot parse the VP8 segment header")

    # The loop filter.
    var simple = br.value_of(1) == 1
    var level = br.value_of(6)
    var sharpness = br.value_of(3)
    var use_lf_delta = br.value_of(1) == 1
    var ref_lf_delta = List[Int](length=4, fill=0)
    var mode_lf_delta = List[Int](length=4, fill=0)
    if use_lf_delta and br.value_of(1) == 1:
        for i in range(4):  # pragma: no branch
            if br.value_of(1) == 1:
                ref_lf_delta[i] = br.signed_value(6)
        for i in range(4):  # pragma: no branch
            if br.value_of(1) == 1:
                mode_lf_delta[i] = br.signed_value(6)
    var filter_type = 0 if level == 0 else (1 if simple else 2)
    if br.eof:
        raise Error("WebP: cannot parse the VP8 filter header")

    # The token partitions.
    var rest = 10 + partition_length
    var parts_minus_one = (1 << br.value_of(2)) - 1
    var left = size - rest
    if left < 3 * parts_minus_one:
        raise Error("WebP: the partition sizes run past the frame")
    var part_start = rest + parts_minus_one * 3
    left -= parts_minus_one * 3
    var parts = List[_BoolReader]()
    for p in range(parts_minus_one):
        var at = rest + p * 3
        var psize = (
            Int(data[at]) | (Int(data[at + 1]) << 8) | (Int(data[at + 2]) << 16)
        )
        psize = min(psize, left)
        parts.append(_BoolReader(_slice(data, part_start, part_start + psize)))
        part_start += psize
        left -= psize
    parts.append(_BoolReader(_slice(data, part_start, part_start + left)))
    if part_start >= size:
        raise Error("WebP: the last partition is empty")

    # The quantizers.
    var base_q0 = br.value_of(7)
    var deltas = List[Int]()
    for _ in range(5):  # pragma: no branch
        deltas.append(br.signed_value(4) if br.value_of(1) == 1 else 0)
    # Per segment: y1 DC and AC, y2 DC and AC, uv DC and AC.
    var dq = List[Int](length=24, fill=0)
    var dc_table = materialize[DC_TABLE]()
    var ac_table = materialize[AC_TABLE]()
    for s in range(4):  # pragma: no branch
        var q: Int
        if use_segment:
            q = quantizer[s]
            if not absolute_delta:
                q += base_q0
        else:
            q = base_q0
        dq[s * 6] = dc_table[_clip(q + deltas[0], 127)]
        dq[s * 6 + 1] = ac_table[_clip(q, 127)]
        dq[s * 6 + 2] = dc_table[_clip(q + deltas[1], 127)] * 2
        dq[s * 6 + 3] = max(
            (ac_table[_clip(q + deltas[2], 127)] * 101581) >> 16, 8
        )
        dq[s * 6 + 4] = dc_table[_clip(q + deltas[3], 117)]
        dq[s * 6 + 5] = ac_table[_clip(q + deltas[4], 127)]

    # The token probabilities.
    _ = br.value_of(1)  # update_proba, ignored
    var update = materialize[COEFFS_UPDATE_PROBA]()
    var proba = materialize[COEFFS_PROBA0]()
    for i in range(len(proba)):  # pragma: no branch
        if br.bit(update[i]) == 1:
            proba[i] = br.value_of(8)
    var use_skip = br.value_of(1) == 1
    var skip_p = br.value_of(8) if use_skip else 0

    # The filter strengths, by segment and whether the block is 4x4.
    var strengths = List[_FilterInfo]()
    for s in range(4):  # pragma: no branch
        var base_level: Int
        if use_segment:
            base_level = filter_strength[s]
            if not absolute_delta:
                base_level += level
        else:
            base_level = level
        for i4x4 in range(2):  # pragma: no branch
            var lv = base_level
            if use_lf_delta:
                lv += ref_lf_delta[0]
                if i4x4 == 1:
                    lv += mode_lf_delta[0]
            lv = _clip(lv, 63)
            if lv > 0:
                var ilevel = lv
                if sharpness > 0:
                    ilevel >>= 2 if sharpness > 4 else 1
                    ilevel = min(ilevel, 9 - sharpness)
                ilevel = max(ilevel, 1)
                var hev = 2 if lv >= 40 else (1 if lv >= 15 else 0)
                strengths.append(
                    _FilterInfo(2 * lv + ilevel, ilevel, hev, i4x4 == 1)
                )
            else:
                strengths.append(_FilterInfo(0, 0, 0, i4x4 == 1))

    # The frame.
    var y_stride = mb_w * 16
    var uv_stride = mb_w * 8
    var ys = List[UInt8](length=y_stride * mb_h * 16, fill=0)
    var us = List[UInt8](length=uv_stride * mb_h * 8, fill=0)
    var vs = List[UInt8](length=uv_stride * mb_h * 8, fill=0)
    var top_y = List[UInt8](length=mb_w * 16, fill=0)
    var top_u = List[UInt8](length=mb_w * 8, fill=0)
    var top_v = List[UInt8](length=mb_w * 8, fill=0)
    var intra_t = List[Int](length=4 * mb_w, fill=_B_DC)
    var intra_l = List[Int](length=4, fill=_B_DC)
    var top_nz = List[Int](length=mb_w, fill=0)
    var top_nz_dc = List[Int](length=mb_w, fill=0)
    var bmodes = materialize[BMODES_PROBA]()
    var zigzag = materialize[_ZIGZAG]()
    var bands = materialize[_BANDS]()
    var cats: List[List[Int]] = [
        materialize[_CAT3](),
        materialize[_CAT4](),
        materialize[_CAT5](),
        materialize[_CAT6](),
    ]
    var infos = List[_FilterInfo]()
    var buf = List[UInt8](length=_YUV_SIZE, fill=0)
    var coeffs = List[Int](length=384, fill=0)
    # One row's modes, parsed before its residuals.
    var segments = List[Int](length=mb_w, fill=0)
    var skips = List[Int](length=mb_w, fill=0)
    var is_i4 = List[Bool](length=mb_w, fill=False)
    var imodes = List[Int](length=16 * mb_w, fill=0)
    var uvmodes = List[Int](length=mb_w, fill=0)

    for mb_y in range(mb_h):  # pragma: no branch
        # The modes of the row: libwebp's `VP8ParseIntraModeRow`.
        for i in range(4):  # pragma: no branch
            intra_l[i] = _B_DC
        for mb_x in range(mb_w):  # pragma: no branch
            if update_map:
                if br.bit(segment_proba[0]) == 0:
                    segments[mb_x] = br.bit(segment_proba[1])
                else:
                    segments[mb_x] = br.bit(segment_proba[2]) + 2
            else:
                segments[mb_x] = 0
            if use_skip:
                skips[mb_x] = br.bit(skip_p)
            is_i4[mb_x] = br.bit(145) == 0
            if not is_i4[mb_x]:
                var ymode: Int
                if br.bit(156) == 1:
                    ymode = _B_TM if br.bit(128) == 1 else _B_HE
                else:
                    ymode = _B_VE if br.bit(163) == 1 else _B_DC
                imodes[mb_x * 16] = ymode
                for i in range(4):  # pragma: no branch
                    intra_t[mb_x * 4 + i] = ymode
                    intra_l[i] = ymode
            else:
                for y in range(4):  # pragma: no branch
                    var ymode = intra_l[y]
                    for x in range(4):  # pragma: no branch
                        var prob = (intra_t[mb_x * 4 + x] * 10 + ymode) * 9
                        if br.bit(bmodes[prob]) == 0:
                            ymode = _B_DC
                        elif br.bit(bmodes[prob + 1]) == 0:
                            ymode = _B_TM
                        elif br.bit(bmodes[prob + 2]) == 0:
                            ymode = _B_VE
                        elif br.bit(bmodes[prob + 3]) == 0:
                            if br.bit(bmodes[prob + 4]) == 0:
                                ymode = _B_HE
                            elif br.bit(bmodes[prob + 5]) == 0:
                                ymode = _B_RD
                            else:
                                ymode = _B_VR
                        elif br.bit(bmodes[prob + 6]) == 0:
                            ymode = _B_LD
                        elif br.bit(bmodes[prob + 7]) == 0:
                            ymode = _B_VL
                        elif br.bit(bmodes[prob + 8]) == 0:
                            ymode = _B_HD
                        else:
                            ymode = _B_HU
                        intra_t[mb_x * 4 + x] = ymode
                        imodes[mb_x * 16 + y * 4 + x] = ymode
                    intra_l[y] = ymode
            if br.bit(142) == 0:
                uvmodes[mb_x] = _B_DC
            elif br.bit(114) == 0:
                uvmodes[mb_x] = _B_VE
            else:
                uvmodes[mb_x] = _B_TM if br.bit(183) == 1 else _B_HE
        if br.eof:
            raise Error("WebP: the first partition ends too soon")

        # The residuals and the pixels.
        ref token = parts[mb_y & parts_minus_one]
        var left_nz = 0
        var left_nz_dc = 0
        for mb_x in range(mb_w):  # pragma: no branch
            var segment = segments[mb_x]
            var i4 = is_i4[mb_x]
            var skip = skips[mb_x] if use_skip else 0
            var non_zero_y = UInt32(0)
            var non_zero_uv = UInt32(0)
            if skip == 0:
                # libwebp's `ParseResiduals`.
                for i in range(384):  # pragma: no branch
                    coeffs[i] = 0
                var first: Int
                var ac_type: Int
                var q = segment * 6
                if not i4:
                    var dc = List[Int](length=16, fill=0)
                    var ctx = top_nz_dc[mb_x] + left_nz_dc
                    var nz = _coeffs(
                        token,
                        proba,
                        bands,
                        zigzag,
                        cats,
                        1,
                        ctx,
                        dq[q + 2],
                        dq[q + 3],
                        0,
                        dc,
                        0,
                    )
                    var flag = 1 if nz > 0 else 0
                    top_nz_dc[mb_x] = flag
                    left_nz_dc = flag
                    if nz > 1:
                        _wht(dc, coeffs)
                    else:
                        var dc0 = _i16((dc[0] + 3) >> 3)
                        for i in range(0, 256, 16):  # pragma: no branch
                            coeffs[i] = dc0
                    first = 1
                    ac_type = 0
                else:
                    first = 0
                    ac_type = 3
                var tnz = top_nz[mb_x] & 0x0F
                var lnz = left_nz & 0x0F
                var at = 0
                for _ in range(4):  # pragma: no branch
                    var l = lnz & 1
                    var nz_coeffs = UInt32(0)
                    for _ in range(4):  # pragma: no branch
                        var ctx = l + (tnz & 1)
                        var nz = _coeffs(
                            token,
                            proba,
                            bands,
                            zigzag,
                            cats,
                            ac_type,
                            ctx,
                            dq[q],
                            dq[q + 1],
                            first,
                            coeffs,
                            at,
                        )
                        l = 1 if nz > first else 0
                        tnz = (tnz >> 1) | (l << 7)
                        nz_coeffs = _nz_bits(nz_coeffs, nz, coeffs[at] != 0)
                        at += 16
                    tnz >>= 4
                    lnz = (lnz >> 1) | (l << 7)
                    non_zero_y = (non_zero_y << 8) | nz_coeffs
                var out_t = tnz
                var out_l = lnz >> 4
                for ch in range(0, 4, 2):  # pragma: no branch
                    var nz_coeffs = UInt32(0)
                    tnz = top_nz[mb_x] >> (4 + ch)
                    lnz = left_nz >> (4 + ch)
                    for _ in range(2):  # pragma: no branch
                        var l = lnz & 1
                        for _ in range(2):  # pragma: no branch
                            var ctx = l + (tnz & 1)
                            var nz = _coeffs(
                                token,
                                proba,
                                bands,
                                zigzag,
                                cats,
                                2,
                                ctx,
                                dq[q + 4],
                                dq[q + 5],
                                0,
                                coeffs,
                                at,
                            )
                            l = 1 if nz > 0 else 0
                            tnz = (tnz >> 1) | (l << 3)
                            nz_coeffs = _nz_bits(nz_coeffs, nz, coeffs[at] != 0)
                            at += 16
                        tnz >>= 2
                        lnz = (lnz >> 1) | (l << 5)
                    non_zero_uv |= nz_coeffs << UInt32(4 * ch)
                    out_t |= (tnz << 4) << ch
                    out_l |= (lnz & 0xF0) << ch
                top_nz[mb_x] = out_t
                left_nz = out_l
                skip = 1 if (non_zero_y | non_zero_uv) == 0 else 0
            else:
                top_nz[mb_x] = 0
                left_nz = 0
                if not i4:
                    top_nz_dc[mb_x] = 0
                    left_nz_dc = 0
            if token.eof:
                raise Error("WebP: a token partition ends too soon")
            var info = strengths[segment * 2 + (1 if i4 else 0)].copy()
            info.inner = info.inner or skip == 0
            infos.append(info^)

            # libwebp's `ReconstructRow`, one macroblock at a time.
            _reconstruct(
                buf,
                mb_x,
                mb_y,
                mb_w,
                mb_h,
                i4,
                imodes,
                uvmodes[mb_x],
                non_zero_y,
                non_zero_uv,
                coeffs,
                top_y,
                top_u,
                top_v,
                ys,
                us,
                vs,
                y_stride,
                uv_stride,
            )

    # The loop filter, in raster order over the whole frame.
    if filter_type > 0:
        for mb_y in range(mb_h):  # pragma: no branch
            for mb_x in range(mb_w):  # pragma: no branch
                ref info = infos[mb_y * mb_w + mb_x]
                if info.limit == 0:
                    continue
                var yat = mb_y * 16 * y_stride + mb_x * 16
                var limit = info.limit
                if filter_type == 1:
                    if mb_x > 0:
                        _simple(ys, yat, 1, y_stride, limit + 4)
                    if info.inner:
                        for k in range(1, 4):  # pragma: no branch
                            _simple(ys, yat + 4 * k, 1, y_stride, limit)
                    if mb_y > 0:
                        _simple(ys, yat, y_stride, 1, limit + 4)
                    if info.inner:
                        for k in range(1, 4):  # pragma: no branch
                            _simple(
                                ys, yat + 4 * k * y_stride, y_stride, 1, limit
                            )
                    continue
                var uvat = mb_y * 8 * uv_stride + mb_x * 8
                var il = info.ilevel
                var hev = info.hev_thresh
                if mb_x > 0:
                    _loop(ys, yat, 1, y_stride, 16, limit + 4, il, hev, False)
                    _loop(us, uvat, 1, uv_stride, 8, limit + 4, il, hev, False)
                    _loop(vs, uvat, 1, uv_stride, 8, limit + 4, il, hev, False)
                if info.inner:
                    for k in range(1, 4):  # pragma: no branch
                        _loop(
                            ys,
                            yat + 4 * k,
                            1,
                            y_stride,
                            16,
                            limit,
                            il,
                            hev,
                            True,
                        )
                    _loop(us, uvat + 4, 1, uv_stride, 8, limit, il, hev, True)
                    _loop(vs, uvat + 4, 1, uv_stride, 8, limit, il, hev, True)
                if mb_y > 0:
                    _loop(ys, yat, y_stride, 1, 16, limit + 4, il, hev, False)
                    _loop(us, uvat, uv_stride, 1, 8, limit + 4, il, hev, False)
                    _loop(vs, uvat, uv_stride, 1, 8, limit + 4, il, hev, False)
                if info.inner:
                    for k in range(1, 4):  # pragma: no branch
                        _loop(
                            ys,
                            yat + 4 * k * y_stride,
                            y_stride,
                            1,
                            16,
                            limit,
                            il,
                            hev,
                            True,
                        )
                    _loop(
                        us,
                        uvat + 4 * uv_stride,
                        uv_stride,
                        1,
                        8,
                        limit,
                        il,
                        hev,
                        True,
                    )
                    _loop(
                        vs,
                        uvat + 4 * uv_stride,
                        uv_stride,
                        1,
                        8,
                        limit,
                        il,
                        hev,
                        True,
                    )

    # RGBA, by libwebp's `EmitFancyRGB` over the whole frame.
    var rgba = List[UInt8](length=width * height * 4, fill=0)
    _upsample(ys, y_stride, us, vs, uv_stride, 0, -1, 0, 0, width, rgba)
    var y = 1
    while y + 1 < height:
        _upsample(
            ys,
            y_stride,
            us,
            vs,
            uv_stride,
            y,
            y + 1,
            (y - 1) >> 1,
            (y + 1) >> 1,
            width,
            rgba,
        )
        y += 2
    if height & 1 == 0:
        var last = (height - 1) >> 1
        _upsample(
            ys,
            y_stride,
            us,
            vs,
            uv_stride,
            height - 1,
            -1,
            last,
            last,
            width,
            rgba,
        )
    return LossyImage(width, height, rgba^)


def _nz_bits(nz_coeffs: UInt32, nz: Int, dc_nz: Bool) -> UInt32:
    """Append a block's two bits: 3 for more than three coefficients, 2
    for two or three, else whether its DC is not zero."""
    var code = 3 if nz > 3 else (2 if nz > 1 else (1 if dc_nz else 0))
    return (nz_coeffs << 2) | UInt32(code)


def _large(
    mut br: _BoolReader, proba: List[Int], p: Int, cats: List[List[Int]]
) -> Int:
    """Read a coefficient of 2 or more: libwebp's `GetLargeValue`."""
    if br.bit(proba[p + 3]) == 0:
        if br.bit(proba[p + 4]) == 0:
            return 2
        return 3 + br.bit(proba[p + 5])
    if br.bit(proba[p + 6]) == 0:
        if br.bit(proba[p + 7]) == 0:
            return 5 + br.bit(159)
        var v = 7 + 2 * br.bit(165)
        return v + br.bit(145)
    var bit1 = br.bit(proba[p + 8])
    var bit0 = br.bit(proba[p + 9 + bit1])
    var cat = 2 * bit1 + bit0
    var v = 0
    for prob in cats[cat]:  # pragma: no branch
        v += v + br.bit(prob)
    return v + 3 + (8 << cat)


def _pidx(t: Int, band: Int, ctx: Int) -> Int:
    """Return where a type, band and context's 11 probabilities start."""
    return ((t * 8 + band) * 3 + ctx) * 11


def _coeffs(
    mut br: _BoolReader,
    proba: List[Int],
    bands: List[Int],
    zigzag: List[Int],
    cats: List[List[Int]],
    t: Int,
    ctx: Int,
    dq_dc: Int,
    dq_ac: Int,
    start: Int,
    mut out: List[Int],
    base: Int,
) -> Int:
    """Read a block's coefficients from `start`, dequantized, and return
    one past the last that is not zero: libwebp's `GetCoeffsFast`."""

    var n = start
    var p = _pidx(t, bands[n], ctx)
    while n < 16:
        if br.bit(proba[p]) == 0:
            return n
        while br.bit(proba[p + 1]) == 0:
            n += 1
            p = _pidx(t, bands[n], 0)
            if n == 16:
                return 16
        var v: Int
        var next_band = bands[n + 1]
        if br.bit(proba[p + 2]) == 0:
            v = 1
            p = _pidx(t, next_band, 1)
        else:
            v = _large(br, proba, p, cats)
            p = _pidx(t, next_band, 2)
        var step = dq_ac if n > 0 else dq_dc
        out[base + zigzag[n]] = _i16(br.signed(v) * step)
        n += 1
    return 16


def _reconstruct(
    mut buf: List[UInt8],
    mb_x: Int,
    mb_y: Int,
    mb_w: Int,
    mb_h: Int,
    i4: Bool,
    imodes: List[Int],
    uvmode: Int,
    non_zero_y: UInt32,
    non_zero_uv: UInt32,
    coeffs: List[Int],
    mut top_y: List[UInt8],
    mut top_u: List[UInt8],
    mut top_v: List[UInt8],
    mut ys: List[UInt8],
    mut us: List[UInt8],
    mut vs: List[UInt8],
    y_stride: Int,
    uv_stride: Int,
):
    """Predict a macroblock in the work buffer, add its residual, and copy
    it into the planes: one step of libwebp's `ReconstructRow`."""
    var y_dst = _Y_OFF
    var u_dst = _U_OFF
    var v_dst = _V_OFF
    if mb_x == 0:
        # A new row: the left column is 129, and the corner too, or all of
        # the top 127 on the first row.
        for j in range(16):  # pragma: no branch
            buf[y_dst + j * _BPS - 1] = 129
        for j in range(8):  # pragma: no branch
            buf[u_dst + j * _BPS - 1] = 129
            buf[v_dst + j * _BPS - 1] = 129
        if mb_y > 0:
            buf[y_dst - 1 - _BPS] = 129
            buf[u_dst - 1 - _BPS] = 129
            buf[v_dst - 1 - _BPS] = 129
        else:
            for i in range(16 + 4 + 1):  # pragma: no branch
                buf[y_dst - _BPS - 1 + i] = 127
            for i in range(8 + 1):  # pragma: no branch
                buf[u_dst - _BPS - 1 + i] = 127
                buf[v_dst - _BPS - 1 + i] = 127
    else:
        # The left column and corner are the last macroblock's right.
        for j in range(-1, 16):  # pragma: no branch
            for i in range(4):  # pragma: no branch
                buf[y_dst + j * _BPS - 4 + i] = buf[y_dst + j * _BPS + 12 + i]
        for j in range(-1, 8):  # pragma: no branch
            for i in range(4):  # pragma: no branch
                buf[u_dst + j * _BPS - 4 + i] = buf[u_dst + j * _BPS + 4 + i]
                buf[v_dst + j * _BPS - 4 + i] = buf[v_dst + j * _BPS + 4 + i]
    if mb_y > 0:
        for i in range(16):  # pragma: no branch
            buf[y_dst - _BPS + i] = top_y[mb_x * 16 + i]
        for i in range(8):  # pragma: no branch
            buf[u_dst - _BPS + i] = top_u[mb_x * 8 + i]
            buf[v_dst - _BPS + i] = top_v[mb_x * 8 + i]
    var bits = non_zero_y
    if i4:
        var top_right = y_dst - _BPS + 16
        if mb_y > 0:
            for i in range(4):  # pragma: no branch
                if mb_x >= mb_w - 1:
                    buf[top_right + i] = top_y[mb_x * 16 + 15]
                else:
                    buf[top_right + i] = top_y[(mb_x + 1) * 16 + i]
        # Blocks on the right take the macroblock's top right.
        for r in range(1, 4):  # pragma: no branch
            for i in range(4):  # pragma: no branch
                buf[top_right + r * 4 * _BPS + i] = buf[top_right + i]
        for n in range(16):  # pragma: no branch
            var dst = y_dst + (n & 3) * 4 + (n >> 2) * 4 * _BPS
            _predict4(buf, dst, imodes[mb_x * 16 + n])
            _do_transform(bits, coeffs, n * 16, buf, dst)
            bits <<= 2
    else:
        var mode = _check_mode(mb_x, mb_y, imodes[mb_x * 16])
        _predict_large(buf, y_dst, mode, 16)
        if bits != 0:
            for n in range(16):  # pragma: no branch
                var dst = y_dst + (n & 3) * 4 + (n >> 2) * 4 * _BPS
                _do_transform(bits, coeffs, n * 16, buf, dst)
                bits <<= 2
    var uv = _check_mode(mb_x, mb_y, uvmode)
    _predict_large(buf, u_dst, uv, 8)
    _predict_large(buf, v_dst, uv, 8)
    _do_uv_transform(non_zero_uv, coeffs, 16 * 16, buf, u_dst)
    _do_uv_transform(non_zero_uv >> 8, coeffs, 20 * 16, buf, v_dst)
    if mb_y < mb_h - 1:
        for i in range(16):  # pragma: no branch
            top_y[mb_x * 16 + i] = buf[y_dst + 15 * _BPS + i]
        for i in range(8):  # pragma: no branch
            top_u[mb_x * 8 + i] = buf[u_dst + 7 * _BPS + i]
            top_v[mb_x * 8 + i] = buf[v_dst + 7 * _BPS + i]
    for j in range(16):  # pragma: no branch
        for i in range(16):  # pragma: no branch
            ys[(mb_y * 16 + j) * y_stride + mb_x * 16 + i] = buf[
                y_dst + j * _BPS + i
            ]
    for j in range(8):  # pragma: no branch
        for i in range(8):  # pragma: no branch
            us[(mb_y * 8 + j) * uv_stride + mb_x * 8 + i] = buf[
                u_dst + j * _BPS + i
            ]
            vs[(mb_y * 8 + j) * uv_stride + mb_x * 8 + i] = buf[
                v_dst + j * _BPS + i
            ]


def _check_mode(mb_x: Int, mb_y: Int, mode: Int) -> Int:
    """Turn DC prediction at the frame's top or left edge into the DC
    that leaves the missing side out."""
    if mode != _B_DC:
        return mode
    if mb_x == 0:
        return _DC_NO_TOP_LEFT if mb_y == 0 else _DC_NO_LEFT
    return _DC_NO_TOP if mb_y == 0 else _B_DC
