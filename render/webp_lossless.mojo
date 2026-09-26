# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""WebP's lossless bitstream, VP8L: libwebp 1.6.0's `vp8l_dec.c`.

**What VP8L holds.** An image of 32-bit ARGB pixels, coded with up to
four transforms and then entropy coded. Decoding reads the transforms,
decodes the coded pixels, and undoes the transforms in reverse order.

**The transforms.** A *predictor* transform stores each pixel as its
difference from one of fourteen predictions made from its neighbors, one
prediction a tile. A *cross-color* transform stores red and blue less
what green and red predict of them, with multipliers a tile. *Subtract
green* stores red and blue less green. *Color indexing* stores an index
into a palette of up to 256 colors, several indices a pixel when the
palette is small.

**The entropy code.** Each pixel is a literal, a backward copy of earlier
pixels, or an entry of a cache of recent colors. Five canonical Huffman
codes read them: green with the copy lengths and the cache, red, blue,
alpha, and the copy distance. An image can hold several groups of five
codes, and a subsampled image of group numbers says which group codes
which tile.

**Errors.** A code that is not complete, a copy from before the first
pixel or past the last, a transform named twice, and data that ends too
soon are refused, as libwebp refuses them.
"""

# The first byte of a VP8L stream.
comptime VP8L_SIGNATURE = 0x2F
# A code's longest length, and how many bits the fast table reads.
comptime _MAX_LENGTH = 15
comptime _FAST_BITS = 8
comptime _LITERALS = 256
comptime _LENGTH_CODES = 24
comptime _DISTANCE_CODES = 40
comptime _MAX_CACHE_BITS = 11
# The order in which the code-length code's lengths are stored.
comptime _CODE_LENGTH_ORDER: List[Int] = [
    17,
    18,
    0,
    1,
    2,
    3,
    4,
    5,
    16,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
]
# Short distances: (dy, 8 - dx) packed as a byte, the 120 closest
# neighbors in the order the format ranks them.
comptime _PLANE: List[Int] = [
    0x18,
    0x07,
    0x17,
    0x19,
    0x28,
    0x06,
    0x27,
    0x29,
    0x16,
    0x1A,
    0x26,
    0x2A,
    0x38,
    0x05,
    0x37,
    0x39,
    0x15,
    0x1B,
    0x36,
    0x3A,
    0x25,
    0x2B,
    0x48,
    0x04,
    0x47,
    0x49,
    0x14,
    0x1C,
    0x35,
    0x3B,
    0x46,
    0x4A,
    0x24,
    0x2C,
    0x58,
    0x45,
    0x4B,
    0x34,
    0x3C,
    0x03,
    0x57,
    0x59,
    0x13,
    0x1D,
    0x56,
    0x5A,
    0x23,
    0x2D,
    0x44,
    0x4C,
    0x55,
    0x5B,
    0x33,
    0x3D,
    0x68,
    0x02,
    0x67,
    0x69,
    0x12,
    0x1E,
    0x66,
    0x6A,
    0x22,
    0x2E,
    0x54,
    0x5C,
    0x43,
    0x4D,
    0x65,
    0x6B,
    0x32,
    0x3E,
    0x78,
    0x01,
    0x77,
    0x79,
    0x53,
    0x5D,
    0x11,
    0x1F,
    0x64,
    0x6C,
    0x42,
    0x4E,
    0x76,
    0x7A,
    0x21,
    0x2F,
    0x75,
    0x7B,
    0x31,
    0x3F,
    0x63,
    0x6D,
    0x52,
    0x5E,
    0x00,
    0x74,
    0x7C,
    0x41,
    0x4F,
    0x10,
    0x20,
    0x62,
    0x6E,
    0x30,
    0x73,
    0x7D,
    0x51,
    0x5F,
    0x40,
    0x72,
    0x7E,
    0x61,
    0x6F,
    0x50,
    0x71,
    0x7F,
    0x60,
    0x70,
]


@fieldwise_init
struct WebpTransform(Equatable, ImplicitlyCopyable, Writable):
    """Which of VP8L's four transforms, as a type rather than a bare int.

    `apply_inverse` stops `WebpTransform(9)` with `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four transforms.

        Returns:
            Whether it is `PREDICTOR_TRANSFORM`, `CROSS_COLOR_TRANSFORM`,
            `SUBTRACT_GREEN_TRANSFORM` or `COLOR_INDEXING_TRANSFORM`.
        """
        return self.value >= 0 and self.value <= 3


# Each pixel less a prediction from its neighbors.
comptime PREDICTOR_TRANSFORM = WebpTransform(0)
# Red and blue less what green and red predict of them.
comptime CROSS_COLOR_TRANSFORM = WebpTransform(1)
# Red and blue less green.
comptime SUBTRACT_GREEN_TRANSFORM = WebpTransform(2)
# Indices into a palette.
comptime COLOR_INDEXING_TRANSFORM = WebpTransform(3)


struct _Bits(Movable):
    """VP8L's bit reader: bits are read from each byte's low end first."""

    var data: List[UInt8]
    var pos: Int
    var end: Int

    def __init__(out self, var data: List[UInt8]):
        self.end = len(data) * 8
        self.data = data^
        self.pos = 0

    def peek(self, n: Int) -> Int:
        """Return the next `n` bits, zeros past the end, without reading
        them."""
        var value = 0
        var got = 0
        var at = self.pos
        while got < n:
            var index = at >> 3
            if index >= len(self.data):
                break
            var shift = at & 7
            var take = min(8 - shift, n - got)
            var byte = Int(self.data[index]) >> shift
            value |= (byte & ((1 << take) - 1)) << got
            got += take
            at += take
        return value

    def skip(mut self, n: Int) raises:
        """Read `n` bits, which must be there."""
        if self.pos + n > self.end:
            raise Error("WebP: the lossless data ends too soon")
        self.pos += n

    def read(mut self, n: Int) raises -> Int:
        """Read an `n`-bit number."""
        var value = self.peek(n)
        self.skip(n)
        return value


struct _Code(Copyable, Movable):
    """A canonical Huffman code, as VP8L stores one: its first bit read is
    the code's highest."""

    # The one symbol of a code with one, which takes no bits; else -1.
    var single: Int
    # How many codes of each length, and the symbols by length.
    var counts: List[Int]
    var symbols: List[Int]
    # Each of the next `_FAST_BITS` bits' code: its length and symbol, or
    # a length of 0 when the code is longer.
    var fast_length: List[Int]
    var fast_symbol: List[Int]

    def __init__(out self, lengths: List[Int]) raises:
        """Build the code of a list of lengths, and refuse one that is not
        complete, as libwebp's `BuildHuffmanTable` refuses it."""
        self.counts = List[Int](length=_MAX_LENGTH + 1, fill=0)
        self.symbols = List[Int]()
        self.fast_length = List[Int](length=1 << _FAST_BITS, fill=0)
        self.fast_symbol = List[Int](length=1 << _FAST_BITS, fill=0)
        self.single = -1
        var used = 0
        var last = 0
        for symbol in range(len(lengths)):  # pragma: no branch
            if lengths[symbol] > 0:
                self.counts[lengths[symbol]] += 1
                used += 1
                last = symbol
        if used == 0:
            raise Error("WebP: a Huffman code has no symbols")
        if used == 1:
            self.single = last
            return
        # Every branch of the tree must end in a symbol.
        var open = 1
        for length in range(1, _MAX_LENGTH + 1):  # pragma: no branch
            open = open * 2 - self.counts[length]
            if open < 0:
                raise Error("WebP: a Huffman code is over-subscribed")
        if open != 0:
            raise Error("WebP: a Huffman code is not complete")
        for length in range(1, _MAX_LENGTH + 1):  # pragma: no branch
            for symbol in range(len(lengths)):  # pragma: no branch
                if lengths[symbol] == length:
                    self.symbols.append(symbol)
        # The canonical codes, reversed into the order the bits arrive.
        var code = 0
        var index = 0
        for length in range(1, _FAST_BITS + 1):  # pragma: no branch
            for _ in range(self.counts[length]):
                var reversed = 0
                for b in range(length):  # pragma: no branch
                    reversed |= ((code >> b) & 1) << (length - 1 - b)
                for fill in range(
                    1 << (_FAST_BITS - length)
                ):  # pragma: no branch
                    var slot = reversed | (fill << length)
                    self.fast_length[slot] = length
                    self.fast_symbol[slot] = self.symbols[index]
                code += 1
                index += 1
            code <<= 1

    def read(self, mut bits: _Bits) raises -> Int:
        """Read one symbol."""
        if self.single >= 0:
            return self.single
        var peeked = bits.peek(_FAST_BITS)
        var length = self.fast_length[peeked]
        if length > 0:
            bits.skip(length)
            return self.fast_symbol[peeked]
        # A code longer than the table: one bit at a time. A complete code
        # ends by its longest length.
        var code = 0
        var first = 0
        var index = 0
        for length in range(1, _MAX_LENGTH):  # pragma: no branch
            code |= bits.read(1)
            var count = self.counts[length]
            if code - count < first:
                return self.symbols[index + code - first]
            index += count
            first = (first + count) << 1
            code <<= 1
        code |= bits.read(1)
        return self.symbols[index + code - first]


def _code_lengths(
    mut bits: _Bits, lengths_code: _Code, size: Int
) raises -> List[Int]:
    """Read a code's lengths with the code-length code: libwebp's
    `ReadHuffmanCodeLengths`."""
    var lengths = List[Int](length=size, fill=0)
    var max_symbol = size
    if bits.read(1) == 1:
        var width = 2 + 2 * bits.read(3)
        max_symbol = 2 + bits.read(width)
        if max_symbol > size:
            raise Error("WebP: a code has more lengths than symbols")
    var symbol = 0
    var previous = 8
    while symbol < size:
        if max_symbol == 0:
            break
        max_symbol -= 1
        var length = lengths_code.read(bits)
        if length < 16:
            lengths[symbol] = length
            symbol += 1
            if length != 0:
                previous = length
            continue
        # 16 repeats the last length that was not zero, 17 and 18 zero.
        var repeat: Int
        var value = 0
        if length == 16:
            repeat = 3 + bits.read(2)
            value = previous
        elif length == 17:
            repeat = 3 + bits.read(3)
        else:
            repeat = 11 + bits.read(7)
        if symbol + repeat > size:
            raise Error("WebP: a code's lengths run past its symbols")
        for _ in range(repeat):  # pragma: no branch
            lengths[symbol] = value
            symbol += 1
    return lengths^


def _read_code(mut bits: _Bits, size: Int) raises -> _Code:
    """Read one Huffman code of `size` symbols: libwebp's
    `ReadHuffmanCode`."""
    var lengths = List[Int](length=size, fill=0)
    if bits.read(1) == 1:
        # A simple code: one or two symbols, stored whole. A symbol past
        # the alphabet is dropped, as libwebp's table ignores it.
        var count = bits.read(1) + 1
        var first = bits.read(8 if bits.read(1) == 1 else 1)
        if first < size:
            lengths[first] = 1
        if count == 2:
            var second = bits.read(8)
            if second < size:
                lengths[second] = 1
        return _Code(lengths)
    var count = bits.read(4) + 4
    var lengths_lengths = List[Int](length=19, fill=0)
    var order = materialize[_CODE_LENGTH_ORDER]()
    for i in range(count):  # pragma: no branch
        lengths_lengths[order[i]] = bits.read(3)
    var lengths_code = _Code(lengths_lengths)
    return _Code(_code_lengths(bits, lengths_code, size))


struct _Group(Copyable, Movable):
    """The five codes of one group: green with lengths and the cache,
    red, blue, alpha, and distance."""

    var green: _Code
    var red: _Code
    var blue: _Code
    var alpha: _Code
    var distance: _Code

    def __init__(out self, mut bits: _Bits, cache_size: Int) raises:
        self.green = _read_code(bits, _LITERALS + _LENGTH_CODES + cache_size)
        self.red = _read_code(bits, _LITERALS)
        self.blue = _read_code(bits, _LITERALS)
        self.alpha = _read_code(bits, _LITERALS)
        self.distance = _read_code(bits, _DISTANCE_CODES)


def subsample(size: Int, bits: Int) -> Int:
    """Return how many tiles of `1 << bits` cover `size`: libwebp's
    `VP8LSubSampleSize`.

    Args:
        size: A width or a height.
        bits: The tile's size, as a power of two.

    Returns:
        The number of tiles.
    """
    return (size + (1 << bits) - 1) >> bits


def _prefix(symbol: Int, mut bits: _Bits) raises -> Int:
    """Return a copy length or distance code from its prefix symbol and
    extra bits."""
    if symbol < 4:
        return symbol + 1
    var extra = (symbol - 2) >> 1
    var offset = (2 + (symbol & 1)) << extra
    return offset + bits.read(extra) + 1


def _distance(width: Int, code: Int, plane: List[Int]) -> Int:
    """Turn a distance code into a distance in pixels: the first 120 are
    nearby pixels in two dimensions."""
    if code > 120:
        return code - 120
    var packed = plane[code - 1]
    var distance = (packed >> 4) * width + 8 - (packed & 0xF)
    return distance if distance >= 1 else 1


def _decode_pixels(
    mut bits: _Bits, width: Int, height: Int, allow_meta: Bool
) raises -> List[UInt32]:
    """Read an entropy-coded image: its color cache, its codes and its
    pixels. libwebp's `DecodeImageStream` after the transforms, and
    `DecodeImageData`."""
    var cache_bits = 0
    if bits.read(1) == 1:
        cache_bits = bits.read(4)
        if cache_bits < 1 or cache_bits > _MAX_CACHE_BITS:
            raise Error("WebP: a color cache of that size is not allowed")
    var cache_size = (1 << cache_bits) if cache_bits > 0 else 0
    # The group of each tile, when the image has more than one group.
    var meta_bits = 0
    var meta_width = 0
    var meta = List[Int]()
    var group_count = 1
    if allow_meta and bits.read(1) == 1:
        meta_bits = bits.read(3) + 2
        meta_width = subsample(width, meta_bits)
        var tiles = _decode_pixels(
            bits, meta_width, subsample(height, meta_bits), False
        )
        for pixel in tiles:  # pragma: no branch
            var group = Int((pixel >> 8) & 0xFFFF)
            meta.append(group)
            group_count = max(group_count, group + 1)
    var groups = List[_Group]()
    for _ in range(group_count):  # pragma: no branch
        groups.append(_Group(bits, cache_size))
    var cache = List[UInt32](length=max(cache_size, 1), fill=0)
    var shift = UInt32(32 - cache_bits)
    var plane = materialize[_PLANE]()
    var total = width * height
    var out = List[UInt32](length=total, fill=0)
    var pos = 0
    var col = 0
    var row = 0
    var group = 0
    # Pixels up to here are in the cache.
    var cached = 0
    while pos < total:
        if len(meta) > 0:
            group = meta[(row >> meta_bits) * meta_width + (col >> meta_bits)]
        ref codes = groups[group]
        var code = codes.green.read(bits)
        if code < _LITERALS + _LENGTH_CODES and code >= _LITERALS:
            var length = _prefix(code - _LITERALS, bits)
            var distance = _distance(
                width, _prefix(codes.distance.read(bits), bits), plane
            )
            if pos < distance or total - pos < length:
                raise Error("WebP: a copy reaches outside the image")
            for i in range(length):  # pragma: no branch
                out[pos + i] = out[pos + i - distance]
            pos += length
            col += length
            while col >= width:
                col -= width
                row += 1
        else:
            if code < _LITERALS:
                var red = codes.red.read(bits)
                var blue = codes.blue.read(bits)
                var alpha = codes.alpha.read(bits)
                out[pos] = UInt32(
                    (alpha << 24) | (red << 16) | (code << 8) | blue
                )
            else:
                # A cache entry: the cache holds every pixel before it.
                out[pos] = cache[code - _LITERALS - _LENGTH_CODES]
            pos += 1
            col += 1
            if col >= width:
                col = 0
                row += 1
        if cache_size > 0:
            while cached < pos:
                var argb = out[cached]
                cache[Int((argb * 0x1E35A7BD) >> shift)] = argb
                cached += 1
    return out^


struct _Transform(Copyable, Movable):
    """One transform, and the width of the image it applies to."""

    var kind: WebpTransform
    var bits: Int
    var width: Int
    var data: List[UInt32]

    def __init__(
        out self,
        kind: WebpTransform,
        bits: Int,
        width: Int,
        var data: List[UInt32],
    ):
        self.kind = kind
        self.bits = bits
        self.width = width
        self.data = data^


def _average2(a: UInt32, b: UInt32) -> UInt32:
    """Average each channel of two pixels, rounding down."""
    return (((a ^ b) & 0xFEFEFEFE) >> 1) + (a & b)


def _clip255(value: Int) -> UInt32:
    """Clamp to 0 to 255."""
    return UInt32(min(max(value, 0), 255))


def _channel(pixel: UInt32, shift: Int) -> Int:
    return Int((pixel >> UInt32(shift)) & 0xFF)


def _add_subtract_full(a: UInt32, b: UInt32, c: UInt32) -> UInt32:
    """Return a + b - c a channel, clamped: predictor 12."""
    var out = UInt32(0)
    for shift in range(0, 32, 8):  # pragma: no branch
        var v = _channel(a, shift) + _channel(b, shift) - _channel(c, shift)
        out |= _clip255(v) << UInt32(shift)
    return out


def _add_subtract_half(a: UInt32, b: UInt32, c: UInt32) -> UInt32:
    """Return the average of a and b moved half its distance from c, a
    channel, clamped: predictor 13. The halving rounds toward zero, as C
    divides."""
    var average = _average2(a, b)
    var out = UInt32(0)
    for shift in range(0, 32, 8):  # pragma: no branch
        var x = _channel(average, shift)
        var d = x - _channel(c, shift)
        var half = d // 2 if d >= 0 else -((-d) // 2)
        out |= _clip255(x + half) << UInt32(shift)
    return out


def _select(top: UInt32, left: UInt32, top_left: UInt32) -> UInt32:
    """Return whichever of top and left is nearer the gradient guess:
    predictor 11."""
    var sum = 0
    for shift in range(0, 32, 8):  # pragma: no branch
        var c = _channel(top_left, shift)
        sum += abs(_channel(left, shift) - c) - abs(_channel(top, shift) - c)
    return top if sum <= 0 else left


def _predict(
    mode: Int, left: UInt32, top: UInt32, top_left: UInt32, top_right: UInt32
) -> UInt32:
    """Return one of the fourteen predictions; 14 and 15 are black, as
    libwebp pads its table."""
    if mode == 1:
        return left
    if mode == 2:
        return top
    if mode == 3:
        return top_right
    if mode == 4:
        return top_left
    if mode == 5:
        return _average2(_average2(left, top_right), top)
    if mode == 6:
        return _average2(left, top_left)
    if mode == 7:
        return _average2(left, top)
    if mode == 8:
        return _average2(top_left, top)
    if mode == 9:
        return _average2(top, top_right)
    if mode == 10:
        return _average2(_average2(left, top_left), _average2(top, top_right))
    if mode == 11:
        return _select(top, left, top_left)
    if mode == 12:
        return _add_subtract_full(left, top, top_left)
    if mode == 13:
        return _add_subtract_half(left, top, top_left)
    return 0xFF000000


def _add_pixels(a: UInt32, b: UInt32) -> UInt32:
    """Add two pixels a channel, each wrapping."""
    var high = (a & 0xFF00FF00) + (b & 0xFF00FF00)
    var low = (a & 0x00FF00FF) + (b & 0x00FF00FF)
    return (high & 0xFF00FF00) | (low & 0x00FF00FF)


def _undo_predictor(t: _Transform, mut pixels: List[UInt32], height: Int):
    """Undo a predictor transform: the top left pixel is predicted black,
    the rest of the top row from the left, the left column from the top,
    and every other pixel by its tile's mode."""
    var width = t.width
    var tiles = subsample(width, t.bits)
    pixels[0] = _add_pixels(pixels[0], 0xFF000000)
    for x in range(1, width):
        pixels[x] = _add_pixels(pixels[x], pixels[x - 1])
    for y in range(1, height):
        var at = y * width
        pixels[at] = _add_pixels(pixels[at], pixels[at - width])
        var modes = (y >> t.bits) * tiles
        for x in range(1, width):
            var mode = Int((t.data[modes + (x >> t.bits)] >> 8) & 0xF)
            var i = at + x
            # The top right of the last pixel is the row's first pixel,
            # which is where it lies in memory.
            var prediction = _predict(
                mode,
                pixels[i - 1],
                pixels[i - width],
                pixels[i - width - 1],
                pixels[i - width + 1],
            )
            pixels[i] = _add_pixels(pixels[i], prediction)


def _delta(multiplier: UInt32, color: UInt32) -> Int:
    """Return a signed 8-bit multiplier times a signed 8-bit color, over
    32."""
    var m = Int(Int8(UInt8(multiplier & 0xFF)))
    var c = Int(Int8(UInt8(color & 0xFF)))
    return (m * c) >> 5


def _undo_cross_color(t: _Transform, mut pixels: List[UInt32], height: Int):
    """Undo a cross-color transform: add back what green predicts of red,
    and what green and the new red predict of blue."""
    var tiles = subsample(t.width, t.bits)
    for y in range(height):  # pragma: no branch
        for x in range(t.width):  # pragma: no branch
            var code = t.data[(y >> t.bits) * tiles + (x >> t.bits)]
            var i = y * t.width + x
            var argb = pixels[i]
            var green = argb >> 8
            var red = (Int((argb >> 16) & 0xFF) + _delta(code, green)) & 0xFF
            var blue = Int(argb & 0xFF) + _delta(code >> 8, green)
            blue = (blue + _delta(code >> 16, UInt32(red))) & 0xFF
            pixels[i] = (argb & 0xFF00FF00) | UInt32(red << 16) | UInt32(blue)


def _undo_subtract_green(mut pixels: List[UInt32]):
    """Add green back to red and blue."""
    for i in range(len(pixels)):  # pragma: no branch
        var argb = pixels[i]
        var green = (argb >> 8) & 0xFF
        var red_blue = (
            (argb & 0x00FF00FF) + ((green << 16) | green)
        ) & 0x00FF00FF
        pixels[i] = (argb & 0xFF00FF00) | red_blue


def _undo_color_indexing(
    t: _Transform, pixels: List[UInt32], height: Int
) -> List[UInt32]:
    """Look each index up in the palette, unpacking several a pixel when
    the palette is small. An index past the palette is transparent
    black."""
    var packed_width = subsample(t.width, t.bits)
    var per_pixel = 8 >> t.bits
    var mask = (1 << per_pixel) - 1
    var out = List[UInt32](length=t.width * height, fill=0)
    for y in range(height):  # pragma: no branch
        for x in range(t.width):  # pragma: no branch
            var packed = Int(
                (pixels[y * packed_width + (x >> t.bits)] >> 8) & 0xFF
            )
            var index = (
                packed >> ((x & ((1 << t.bits) - 1)) * per_pixel)
            ) & mask
            # The palette is padded to the most indices a pixel holds.
            out[y * t.width + x] = t.data[index]
    return out^


def apply_inverse(
    kind: WebpTransform,
    bits: Int,
    width: Int,
    data: List[UInt32],
    var pixels: List[UInt32],
    height: Int,
) raises -> List[UInt32]:
    """Undo one transform on a whole image.

    Args:
        kind: The transform.
        bits: Its tile size as a power of two, or for color indexing how
            many indices a pixel packs, as a power of two.
        width: The width of the image it gives back.
        data: Its tiles' modes or multipliers, or its palette.
        pixels: The transformed image.
        height: The image's height.

    Returns:
        The image before the transform.

    Raises:
        If the kind is not one of the four.
    """
    if not kind.is_valid():
        raise Error("WebP: a transform that is not known")
    var t = _Transform(kind, bits, width, data.copy())
    if kind == PREDICTOR_TRANSFORM:
        _undo_predictor(t, pixels, height)
    elif kind == CROSS_COLOR_TRANSFORM:
        _undo_cross_color(t, pixels, height)
    elif kind == SUBTRACT_GREEN_TRANSFORM:
        _undo_subtract_green(pixels)
    else:
        return _undo_color_indexing(t, pixels, height)
    return pixels^


def _palette(var colors: List[UInt32], bits: Int) -> List[UInt32]:
    """Undo the palette's own delta coding, and pad it with transparent
    black to the most indices a pixel can hold."""
    var size = 1 << (8 >> bits)
    var out = List[UInt32](length=max(size, len(colors)), fill=0)
    # A palette has at least one color.
    out[0] = colors[0]
    for i in range(1, len(colors)):
        out[i] = _add_pixels(colors[i], out[i - 1])
    out.resize(size, 0)
    return out^


def decode_lossless_stream(
    var data: List[UInt8], width: Int, height: Int
) raises -> List[UInt32]:
    """Decode VP8L's transforms and image, without its header: what the
    alpha of a lossy image stores. libwebp's `DecodeImageStream` at the
    top level, then the inverse transforms.

    Args:
        data: The stream.
        width: The image's width.
        height: The image's height.

    Returns:
        The ARGB pixels, row by row from the top.

    Raises:
        If the stream is malformed.
    """
    var bits = _Bits(data^)
    return _decode_stream(bits, width, height)


def _decode_stream(
    mut bits: _Bits, width: Int, height: Int
) raises -> List[UInt32]:
    """Read the transforms and the image, and undo the transforms."""
    var transforms = List[_Transform]()
    var seen = 0
    var coded_width = width
    while bits.read(1) == 1:
        var kind = WebpTransform(bits.read(2))
        if seen & (1 << kind.value) != 0:
            raise Error("WebP: a transform is named twice")
        seen |= 1 << kind.value
        if kind == PREDICTOR_TRANSFORM or kind == CROSS_COLOR_TRANSFORM:
            var tile_bits = bits.read(3) + 2
            var tiles = _decode_pixels(
                bits,
                subsample(coded_width, tile_bits),
                subsample(height, tile_bits),
                False,
            )
            transforms.append(_Transform(kind, tile_bits, coded_width, tiles^))
        elif kind == COLOR_INDEXING_TRANSFORM:
            var count = bits.read(8) + 1
            var index_bits = 0
            if count <= 2:
                index_bits = 3
            elif count <= 4:
                index_bits = 2
            elif count <= 16:
                index_bits = 1
            var colors = _decode_pixels(bits, count, 1, False)
            transforms.append(
                _Transform(
                    kind, index_bits, coded_width, _palette(colors^, index_bits)
                )
            )
            coded_width = subsample(coded_width, index_bits)
        else:
            transforms.append(_Transform(kind, 0, coded_width, List[UInt32]()))
    var pixels = _decode_pixels(bits, coded_width, height, True)
    for k in range(len(transforms) - 1, -1, -1):
        ref t = transforms[k]
        pixels = apply_inverse(t.kind, t.bits, t.width, t.data, pixels^, height)
    return pixels^


struct LosslessImage(Movable):
    """A decoded VP8L image."""

    var width: Int
    var height: Int
    # The header's hint that some pixel is not opaque.
    var has_alpha: Bool
    # ARGB, row by row from the top.
    var pixels: List[UInt32]

    def __init__(
        out self,
        width: Int,
        height: Int,
        has_alpha: Bool,
        var pixels: List[UInt32],
    ):
        """Hold a decoded image.

        Args:
            width: Its width.
            height: Its height.
            has_alpha: The header's alpha hint.
            pixels: ARGB, row by row from the top.
        """
        self.width = width
        self.height = height
        self.has_alpha = has_alpha
        self.pixels = pixels^


def decode_lossless(var data: List[UInt8]) raises -> LosslessImage:
    """Decode a VP8L stream, header and all: libwebp's `VP8LDecodeHeader`
    and `VP8LDecodeImage`.

    Args:
        data: The `VP8L` chunk's payload.

    Returns:
        The image.

    Raises:
        If the signature or the version is wrong, or the stream is
        malformed.
    """
    if len(data) < 5 or Int(data[0]) != VP8L_SIGNATURE or data[4] >> 5 != 0:
        raise Error("WebP: not a VP8L stream")
    var bits = _Bits(data^)
    bits.skip(8)
    var width = bits.read(14) + 1
    var height = bits.read(14) + 1
    var has_alpha = bits.read(1) == 1
    bits.skip(3)
    var pixels = _decode_stream(bits, width, height)
    return LosslessImage(width, height, has_alpha, pixels^)
