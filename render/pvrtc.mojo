# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""PVRTC1 decoding, as Imagination's `PVRTDecompress.cpp` decodes it.

three.js hands PVRTC to a GPU that decodes it. This port draws in
software, so it decodes the texels itself, with the reference decoder's
arithmetic: the PowerVR SDK's `PVRTDecompressPVRTC`, which
`assets/pvrtc/make_reference.cpp` runs to make the test's reference.

**The format.** PVRTC stores two low-resolution images, A and B, and a
modulation value for each texel. Each 64-bit word holds one texel of A
and of B, and the modulation of a 4 by 4 block (4 bits a texel) or an 8
by 4 block (2 bits a texel). The words are in Morton order. A texel's
color is A and B, each upscaled bilinearly from the four words around it,
blended by its modulation. A mode bit selects punch-through alpha at 4
bits a texel, and interpolated modulation at 2 bits a texel.

**Sizes.** The width and the height must be powers of two. An image is
decoded at 8 by 8 at least, or 16 by 8 at 2 bits a texel, as the
reference decodes it, and cut to its size. The payload holds two words
across and down at least, as three.js's `PVRLoader` reads it.
"""


def pvrtc_bytes(width: Int, height: Int, two_bit: Bool) -> Int:
    """Return how many bytes a PVRTC level takes, as three.js's
    `PVRLoader` counts them: two blocks across and down at least.

    Args:
        width: The level's width.
        height: Its height.
        two_bit: True for 2 bits a texel, False for 4.

    Returns:
        The payload's length.
    """
    var across = max(width // (8 if two_bit else 4), 2)
    var down = max(height // 4, 2)
    return across * down * 8


def _is_power_of_two(value: Int) -> Bool:
    """Return True for a power of two.

    Args:
        value: The value.

    Returns:
        Whether it is one.
    """
    return value > 0 and (value & (value - 1)) == 0


def _color_a(data: Int) -> List[Int]:
    """Return the reference's `getColorA`: RGB 554 or ARGB 3443, as five
    bits of color and four of alpha.

    Args:
        data: The word's color bits.

    Returns:
        Red, green, blue and alpha.
    """
    if (data & 0x8000) != 0:
        return [
            (data & 0x7C00) >> 10,
            (data & 0x3E0) >> 5,
            (data & 0x1E) | ((data & 0x1E) >> 4),
            0xF,
        ]
    return [
        ((data & 0xF00) >> 7) | ((data & 0xF00) >> 11),
        ((data & 0xF0) >> 3) | ((data & 0xF0) >> 7),
        ((data & 0xE) << 1) | ((data & 0xE) >> 2),
        (data & 0x7000) >> 11,
    ]


def _color_b(data: Int) -> List[Int]:
    """Return the reference's `getColorB`: RGB 555 or ARGB 3444.

    Args:
        data: The word's color bits.

    Returns:
        Red, green, blue and alpha.
    """
    if (data & 0x80000000) != 0:
        return [
            (data & 0x7C000000) >> 26,
            (data & 0x3E00000) >> 21,
            (data & 0x1F0000) >> 16,
            0xF,
        ]
    return [
        ((data & 0xF000000) >> 23) | ((data & 0xF000000) >> 27),
        ((data & 0xF00000) >> 19) | ((data & 0xF00000) >> 23),
        ((data & 0xF0000) >> 15) | ((data & 0xF0000) >> 19),
        (data & 0x70000000) >> 27,
    ]


def _interpolate(
    p: List[Int], q: List[Int], r: List[Int], s: List[Int], two_bit: Bool
) -> List[Int]:
    """Return the reference's `interpolateColors`: four words' colors
    upscaled bilinearly over a word's texels.

    Args:
        p: The top left word's color.
        q: The top right.
        r: The bottom left.
        s: The bottom right.
        two_bit: True for 2 bits a texel.

    Returns:
        Four numbers a texel, `y * width + x`.
    """
    var width = 8 if two_bit else 4
    var height = 4
    var out = List[Int](length=width * height * 4, fill=0)
    var hp = List[Int](capacity=4)
    var hr = List[Int](capacity=4)
    var q_minus_p = List[Int](capacity=4)
    var s_minus_r = List[Int](capacity=4)
    for c in range(4):  # pragma: no branch
        q_minus_p.append(q[c] - p[c])
        s_minus_r.append(s[c] - r[c])
        hp.append(p[c] * width)
        hr.append(r[c] * width)
    # The reference walks x outside and y inside at 2 bits a texel, and
    # the other way round at 4; the sums are the same.
    var outer = width if two_bit else height
    var inner = height if two_bit else width
    for a in range(outer):  # pragma: no branch
        var result = List[Int](capacity=4)
        var dy = List[Int](capacity=4)
        for c in range(4):  # pragma: no branch
            result.append(4 * hp[c])
            dy.append(hr[c] - hp[c])
        for b in range(inner):  # pragma: no branch
            var x = a if two_bit else b
            var y = b if two_bit else a
            var at = (y * width + x) * 4
            for c in range(3):  # pragma: no branch
                if two_bit:
                    out[at + c] = (result[c] >> 7) + (result[c] >> 2)
                else:
                    out[at + c] = (result[c] >> 6) + (result[c] >> 1)
            if two_bit:
                out[at + 3] = (result[3] >> 5) + (result[3] >> 1)
            else:
                out[at + 3] = (result[3] >> 4) + result[3]
            for c in range(4):  # pragma: no branch
                result[c] += dy[c]
        for c in range(4):  # pragma: no branch
            hp[c] += q_minus_p[c]
            hr[c] += s_minus_r[c]
    return out^


def _unpack(
    modulation: Int,
    color: Int,
    offset_x: Int,
    offset_y: Int,
    mut values: List[Int],
    mut modes: List[Int],
    two_bit: Bool,
):
    """Return the reference's `unpackModulations` for one word, into its
    16 by 8 tables, `[first * 8 + second]`.

    At 2 bits a texel the tables are indexed `[x][y]`; at 4 they are
    indexed `[y][x]`, as the reference indexes them.

    Args:
        modulation: The word's modulation bits.
        color: The word's color bits, whose lowest is the mode.
        offset_x: Where the word's texels start across the tables.
        offset_y: Where they start down.
        values: The modulation values.
        modes: The modes, used at 2 bits a texel.
        two_bit: True for 2 bits a texel.
    """
    var mode = color & 1
    var bits = modulation
    if two_bit:
        if mode != 0:
            if (bits & 1) != 0:
                # The centre texel's low bit says which one-way mode.
                mode = 3 if (bits & (1 << 20)) != 0 else 2
                if (bits & (1 << 21)) != 0:
                    bits |= 1 << 20
                else:
                    bits &= ~(1 << 20)
            if (bits & 2) != 0:
                bits |= 1
            else:
                bits &= ~1
            for y in range(4):  # pragma: no branch
                for x in range(8):  # pragma: no branch
                    var at = (x + offset_x) * 8 + y + offset_y
                    modes[at] = mode
                    if ((x ^ y) & 1) == 0:
                        values[at] = bits & 3
                        bits >>= 2
        else:
            for y in range(4):  # pragma: no branch
                for x in range(8):  # pragma: no branch
                    var at = (x + offset_x) * 8 + y + offset_y
                    modes[at] = mode
                    values[at] = 3 if (bits & 1) != 0 else 0
                    bits >>= 1
        return
    for y in range(4):  # pragma: no branch
        for x in range(4):  # pragma: no branch
            var at = (y + offset_y) * 8 + x + offset_x
            var value = bits & 3
            if mode != 0:
                # 1 is 4/8, 3 is 8/8, and 2 is 4/8 with punch-through
                # alpha, marked by adding ten.
                if value == 1:
                    value = 4
                elif value == 2:
                    value = 14
                elif value == 3:
                    value = 8
            else:
                value *= 3
                if value > 3:
                    value -= 1
            values[at] = value
            bits >>= 2


def _modulation(
    values: List[Int], modes: List[Int], x: Int, y: Int, two_bit: Bool
) -> Int:
    """Return the reference's `getModulationValues` at `[x][y]`.

    Args:
        values: The modulation values.
        modes: The modes.
        x: The first index.
        y: The second index.
        two_bit: True for 2 bits a texel.

    Returns:
        The modulation, eighths of B, ten more for punch-through alpha.
    """
    if not two_bit:
        return values[x * 8 + y]
    var rep: List[Int] = [0, 3, 5, 8]
    var mode = modes[x * 8 + y]
    if mode == 0 or ((x ^ y) & 1) == 0:
        return rep[values[x * 8 + y]]
    var up = rep[values[x * 8 + y - 1]]
    var down = rep[values[x * 8 + y + 1]]
    var left = rep[values[(x - 1) * 8 + y]]
    var right = rep[values[(x + 1) * 8 + y]]
    if mode == 1:
        return (up + down + left + right + 2) // 4
    if mode == 2:
        return (left + right + 1) // 2
    return (up + down + 1) // 2


def _twiddle(x_size: Int, y_size: Int, x: Int, y: Int) -> Int:
    """Return the reference's `TwiddleUV`: a word's place in Morton order,
    the longer side's high bits after.

    Args:
        x_size: Words across, a power of two.
        y_size: Words down, a power of two.
        x: The word's column.
        y: Its row.

    Returns:
        Its place.
    """
    var minimum = x_size
    var maximum = y
    if y_size < x_size:
        minimum = y_size
        maximum = x
    var twiddled = 0
    var source = 1
    var destination = 1
    var shift = 0
    while source < minimum:
        if (y & source) != 0:
            twiddled |= destination
        if (x & source) != 0:
            twiddled |= destination << 1
        source <<= 1
        destination <<= 2
        shift += 1
    return twiddled | ((maximum >> shift) << (2 * shift))


def _word(data: List[UInt8], index: Int) -> Int:
    """Return a little-endian 32-bit word.

    Args:
        data: The payload.
        index: Which word.

    Returns:
        The word.
    """
    var at = index * 4
    return (
        Int(data[at])
        | (Int(data[at + 1]) << 8)
        | (Int(data[at + 2]) << 16)
        | (Int(data[at + 3]) << 24)
    )


def decode_pvrtc(
    width: Int, height: Int, data: List[UInt8], two_bit: Bool
) raises -> List[UInt8]:
    """Return a PVRTC1 level as RGBA bytes, as `PVRTDecompressPVRTC`
    decodes it.

    Args:
        width: The level's width, a power of two.
        height: Its height, a power of two.
        data: The payload, `pvrtc_bytes` long.
        two_bit: True for 2 bits a texel, False for 4.

    Returns:
        `width * height * 4` bytes, row-major from the top.

    Raises:
        Error: If a side is not a power of two, or the payload's length
            is not `pvrtc_bytes`.
    """
    if not (_is_power_of_two(width) and _is_power_of_two(height)):
        raise Error("PVRTC: the width and the height must be powers of two")
    if len(data) != pvrtc_bytes(width, height, two_bit):
        raise Error("PVRTC: the payload's length does not match the size")
    var word_width = 8 if two_bit else 4
    var word_height = 4
    var true_width = max(width, 16 if two_bit else 8)
    var true_height = max(height, 8)
    var words_x = true_width // word_width
    var words_y = true_height // word_height
    var full = List[UInt8](length=true_width * true_height * 4, fill=0)
    var values = List[Int](length=16 * 8, fill=0)
    var modes = List[Int](length=16 * 8, fill=0)
    for word_y in range(-1, words_y - 1):  # pragma: no branch
        for word_x in range(-1, words_x - 1):  # pragma: no branch
            var px = (word_x + words_x) % words_x
            var py = (word_y + words_y) % words_y
            var qx = (word_x + 1 + words_x) % words_x
            var ry = (word_y + 1 + words_y) % words_y
            # P, Q, R, S: top left, top right, bottom left, bottom right.
            var xs: List[Int] = [px, qx, px, qx]
            var ys: List[Int] = [py, py, ry, ry]
            var modulation = List[Int]()
            var color = List[Int]()
            for k in range(4):  # pragma: no branch
                var at = _twiddle(words_x, words_y, xs[k], ys[k]) * 2
                modulation.append(_word(data, at))
                color.append(_word(data, at + 1))
            var offsets_x: List[Int] = [0, word_width, 0, word_width]
            var offsets_y: List[Int] = [0, 0, word_height, word_height]
            for k in range(4):  # pragma: no branch
                _unpack(
                    modulation[k],
                    color[k],
                    offsets_x[k],
                    offsets_y[k],
                    values,
                    modes,
                    two_bit,
                )
            var a = _interpolate(
                _color_a(color[0]),
                _color_a(color[1]),
                _color_a(color[2]),
                _color_a(color[3]),
                two_bit,
            )
            var b = _interpolate(
                _color_b(color[0]),
                _color_b(color[1]),
                _color_b(color[2]),
                _color_b(color[3]),
                two_bit,
            )
            var pixels = List[UInt8](
                length=word_width * word_height * 4, fill=0
            )
            for y in range(word_height):  # pragma: no branch
                for x in range(word_width):  # pragma: no branch
                    var mod = _modulation(
                        values,
                        modes,
                        x + word_width // 2,
                        y + word_height // 2,
                        two_bit,
                    )
                    var punch = mod > 10
                    if punch:
                        mod -= 10
                    var at = (y * word_width + x) * 4
                    # The reference writes 4-bit words transposed.
                    var to = at if two_bit else (y + x * word_height) * 4
                    for c in range(4):  # pragma: no branch
                        var value = (
                            a[at + c] * (8 - mod) + b[at + c] * mod
                        ) // 8
                        if c == 3 and punch:
                            value = 0
                        pixels[to + c] = UInt8(value & 0xFF)
            # The reference's `mapDecompressedData`: each quarter of the
            # decoded block to the word it belongs to.
            var half_w = word_width // 2
            var half_h = word_height // 2
            for y in range(half_h):  # pragma: no branch
                for x in range(half_w):  # pragma: no branch
                    var targets: List[Int] = [
                        (
                            (py * word_height + y + half_h) * true_width
                            + px * word_width
                            + x
                            + half_w
                        ),
                        (
                            (py * word_height + y + half_h) * true_width
                            + qx * word_width
                            + x
                        ),
                        (
                            (ry * word_height + y) * true_width
                            + px * word_width
                            + x
                            + half_w
                        ),
                        (
                            (ry * word_height + y) * true_width
                            + qx * word_width
                            + x
                        ),
                    ]
                    var sources: List[Int] = [
                        y * word_width + x,
                        y * word_width + x + half_w,
                        (y + half_h) * word_width + x,
                        (y + half_h) * word_width + x + half_w,
                    ]
                    for k in range(4):  # pragma: no branch
                        for c in range(4):  # pragma: no branch
                            full[targets[k] * 4 + c] = pixels[
                                sources[k] * 4 + c
                            ]
    if true_width == width and true_height == height:
        return full^
    var out = List[UInt8](capacity=width * height * 4)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            for c in range(4):  # pragma: no branch
                out.append(full[(y * true_width + x) * 4 + c])
    return out^
