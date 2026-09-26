# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Baseline TIFF, from three.js `examples/jsm/loaders/TIFFLoader.js`.

three.js reads a TIFF with UTIF: `decode` reads the image file
directories, `decodeImage` the first image's samples, and `toRGBA8` turns
them into RGBA bytes. `read_tiff` does the same for baseline TIFF, with
UTIF's arithmetic, and returns the texture `TIFFLoader` makes: flipped,
filtered linearly, with a chain of levels.

**What is read.** The first image of either byte order, in strips or
tiles. Uncompressed, LZW, Deflate and PackBits data, with or without the
horizontal predictor. Samples of 1, 2, 4, 8, 16 and 32 bits, 16-bit
samples of either byte order.

**How samples become color, as UTIF's `toRGBA8` makes it.**

- White is zero (0) and black is zero (1): gray at 1, 4, 8 and 16 bits,
  and 1, 2, 8, 16 and 32-bit float bits, UTIF's sets. A 16-bit sample
  keeps its high byte. A float is scaled to a byte and rounded, and
  wraps as a byte.
- RGB (2): 8-bit one, three, or four and more samples; 16-bit three or
  four samples, each keeping its high byte; 32-bit floats, clamped,
  encoded with sRGB's curve through UTIF's table of 65536 steps, and
  byte-swapped first when one is negative, as UTIF guesses the order.
- Palette (3): 1, 2, 4 and 8 bits, each color's high byte, with an alpha
  sample when an extra sample says so.
- CMYK (5): UTIF's formula, with a fifth sample as alpha. Without one,
  UTIF reads a fifth sample anyway, times zero; past the end of the data
  that is NaN, so the last pixel is transparent.

**Where UTIF's quirks are kept.** 4-bit black-is-zero gray, 2-bit
white-is-zero gray and RGB of other sample counts are left transparent
black, as `toRGBA8` leaves them. An uncompressed image of one strip is
read as long as the image, whatever its byte count says. A Deflate strip
that does not fit is dropped.

**What is refused.** What three.js throws on: UTIF's build of three.js
throws wherever UTIF logs, so an unknown compression, an unknown
photometric form, planar configuration 2 and an unknown tag type are
refused, and so are 32-bit black-is-zero samples that are not floats,
RGB of other sample sizes, and a palette of other sample sizes. And what
this port does not decode: CCITT, JPEG, the camera and raw formats and
YCbCr. Strips that cover fewer rows than the image: UTIF cuts the data
short, and each photometric form reads the missing bytes differently.
And an LZW code past the table right after a clear code, which UTIF
reads from a table it shares between decodes, so that its output depends
on what was decoded before.

**Where UTIF is followed.** Any other LZW code past the table is read as
the next code.
"""

from render.inflate import inflate
from render.srgb import LINEAR
from render.texture import BILINEAR, CLAMP, COVERAGE, Texture
from std.math import floor, isnan, trunc
from std.memory import bitcast

# The largest image this port decodes, in pixels.
comptime MAX_TIFF_PIXELS = 1 << 26


struct _Reader:
    """A TIFF's bytes and byte order."""

    var bytes: List[UInt8]
    var little: Bool

    def __init__(out self, var bytes: List[UInt8], little: Bool):
        """Hold the file.

        Args:
            bytes: The file.
            little: True for `II`, False for `MM`.
        """
        self.bytes = bytes^
        self.little = little

    def byte(self, at: Int) -> Int:
        """Return a byte, zero past the end as UTIF's `undefined` reads in
        its shifts.

        Args:
            at: The byte.

        Returns:
            The byte.
        """
        if at >= len(self.bytes):
            return 0
        return Int(self.bytes[at])

    def u16(self, at: Int) -> Int:
        """Return an unsigned short in the file's order.

        Args:
            at: Where it starts.

        Returns:
            The value.
        """
        if self.little:
            return self.byte(at) | (self.byte(at + 1) << 8)
        return (self.byte(at) << 8) | self.byte(at + 1)

    def u32(self, at: Int) -> Int:
        """Return an unsigned long in the file's order.

        Args:
            at: Where it starts.

        Returns:
            The value.
        """
        if self.little:
            return self.u16(at) | (self.u16(at + 2) << 16)
        return (self.u16(at) << 16) | self.u16(at + 2)


struct _Ifd(Movable):
    """The tags of one image file directory, each as numbers."""

    var tags: List[Int]
    var values: List[List[Int]]

    def __init__(out self):
        """Start with no tags."""
        self.tags = List[Int]()
        self.values = List[List[Int]]()

    def get(self, tag: Int) -> Optional[List[Int]]:
        """Return a tag's values.

        Args:
            tag: The tag.

        Returns:
            Its values, or none.
        """
        for k in range(len(self.tags)):  # pragma: no branch
            if self.tags[k] == tag:
                return self.values[k].copy()
        return None

    def first(self, tag: Int, default: Int) -> Int:
        """Return a tag's first value, UTIF's `img[ "t" + tag ][ 0 ]`.

        Args:
            tag: The tag.
            default: What a missing tag gives.

        Returns:
            The value.
        """
        var values = self.get(tag)
        if not Bool(values) or len(values.value()) == 0:
            return default
        return values.value()[0]


def _read_ifd(reader: _Reader, offset: Int) raises -> _Ifd:
    """Read one directory's numeric tags, as UTIF's `_readIFD` reads
    them: a value inside the entry when it fits.

    Args:
        reader: The file.
        offset: Where the directory starts.

    Returns:
        The tags.

    Raises:
        Error: For a tag type UTIF does not know, where it logs and
            three.js's build throws.
    """
    var ifd = _Ifd()
    var count = reader.u16(offset)
    var at = offset + 2
    for _ in range(count):  # pragma: no branch
        var tag = reader.u16(at)
        var type = reader.u16(at + 2)
        var num = reader.u32(at + 4)
        var inline = at + 8
        var pointer = reader.u32(at + 8)
        at += 12
        var values = List[Int]()
        if type == 1 or type == 7:
            var start = inline if num < 5 else pointer
            for k in range(
                min(num, max(len(reader.bytes) - start, 0))
            ):  # pragma: no branch
                values.append(reader.byte(start + k))
        elif type == 3:
            var start = inline if num < 3 else pointer
            for k in range(num):
                values.append(reader.u16(start + 2 * k))
        elif type == 4 or type == 13:
            var start = inline if num < 2 else pointer
            for k in range(num):  # pragma: no branch
                values.append(reader.u32(start + 4 * k))
        elif type == 6 or type < 1 or type > 13:
            # UTIF reads no signed bytes, and no type past 13.
            if num != 0:
                raise Error("TIFF: tag " + String(tag) + " has an unknown type")
        ifd.tags.append(tag)
        ifd.values.append(values^)
    return ifd^


def _pack_bits(
    data: _Reader, offset: Int, length: Int, mut target: List[UInt8], start: Int
):
    """Decode PackBits, UTIF's `_decodePackBits`: a byte past the target
    is dropped, as a typed array drops it.

    Args:
        data: The file.
        offset: Where the chunk starts.
        length: Its bytes.
        target: The image's bytes.
        start: Where the chunk's bytes go.
    """
    var at = offset
    var to = start
    var end = offset + length
    while at < end:
        var n = data.byte(at)
        at += 1
        if n < 128:
            for _ in range(n + 1):  # pragma: no branch
                if to < len(target):
                    target[to] = UInt8(data.byte(at))
                to += 1
                at += 1
        elif n > 128:
            var value = UInt8(data.byte(at))
            for _ in range(257 - n):  # pragma: no branch
                if to < len(target):
                    target[to] = value
                to += 1
            at += 1


def _code(data: _Reader, mut bit: Int, width: Int) -> Int:
    """Return the next LZW code, most significant bit first, and move
    past it. A byte past the end reads zero, as UTIF's `undefined` shifts.

    Args:
        data: The file.
        bit: Where the code starts, in bits.
        width: The code's width.

    Returns:
        The code.
    """
    var at = bit >> 3
    var window = (
        (data.byte(at) << 16) | (data.byte(at + 1) << 8) | data.byte(at + 2)
    )
    var value = (window >> (24 - (bit & 7) - width)) & ((1 << width) - 1)
    bit += width
    return value


def _emit(
    entry: Int,
    mut target: List[UInt8],
    mut out: Int,
    last: List[Int],
    prefix: List[Int],
    size: List[Int],
):
    """Write an LZW entry's bytes, last first, UTIF's `D`: a byte past the
    target is dropped.

    Args:
        entry: The entry.
        target: The image's bytes.
        out: Where the entry's bytes go; moved past them.
        last: Each entry's last byte.
        prefix: Each entry's prefix, -1 for none.
        size: Each entry's length.
    """
    var length = size[entry]
    var at = out + length - 1
    var node = entry
    while node >= 0:
        if at < len(target):
            target[at] = UInt8(last[node])
        at -= 1
        node = prefix[node]
    out += length


def _lzw(
    data: _Reader, offset: Int, length: Int, mut target: List[UInt8], start: Int
) raises:
    """Decode TIFF LZW, as UTIF's `_decodeLZW` does: codes of 9 to 12 bits,
    most significant first, the width growing one code early.

    Args:
        data: The file.
        offset: Where the chunk starts.
        length: Its bytes.
        target: The image's bytes.
        start: Where the chunk's bytes go.

    Raises:
        Error: For a code past the table right after a clear code, which
            UTIF reads from what an earlier decode left.
    """
    # Each entry: its last byte, its prefix entry (-1 for none), its
    # length and its first byte.
    var last = List[Int](length=4096, fill=0)
    var prefix = List[Int](length=4096, fill=-1)
    var size = List[Int](length=4096, fill=1)
    var first = List[Int](length=4096, fill=0)
    for k in range(258):  # pragma: no branch
        last[k] = k
        first[k] = k
    var bit = offset * 8
    var end = (offset + length) * 8
    var width = 9
    var next = 258
    var out = start
    var previous = 0

    while bit < end:
        var value = _code(data, bit, width)
        if value == 257:
            break
        if value == 256:
            width = 9
            next = 258
            value = _code(data, bit, width)
            if value == 257:
                break
            if value >= next:
                raise Error("TIFF: an LZW code past the table after a clear")
            _emit(value, target, out, last, prefix, size)
        else:
            if value < next:
                _emit(value, target, out, last, prefix, size)
                if next < 4096:
                    last[next] = first[value]
                    prefix[next] = previous
                    size[next] = size[previous] + 1
                    first[next] = first[previous]
            else:
                # The code is not in the table yet. UTIF reads any such
                # code as the next one: the last entry and its own first
                # byte. A code is 12 bits at most, so the table is not
                # full here.
                last[next] = first[previous]
                prefix[next] = previous
                size[next] = size[previous] + 1
                first[next] = first[previous]
                _emit(next, target, out, last, prefix, size)
            next += 1
            if next + 1 == 1 << width and width != 12:
                width += 1
        previous = value


def _decompress(
    ifd: _Ifd,
    data: _Reader,
    offset: Int,
    length: Int,
    compression: Int,
    mut target: List[UInt8],
    start: Int,
    width: Int,
    height: Int,
) raises:
    """Decode one strip or tile into the image's bytes, UTIF's
    `_decompress`: then swap 16-bit big-endian samples, and undo the
    horizontal predictor.

    Args:
        ifd: The image's tags.
        data: The file.
        offset: Where the chunk starts.
        length: Its bytes.
        compression: The compression.
        target: The bytes.
        start: Where the chunk's bytes go.
        width: The chunk's width in pixels.
        height: Its height in rows.

    Raises:
        Error: For a compression this port does not decode, malformed
            LZW, or Deflate that is malformed.
    """
    if compression == 1:
        for k in range(length):  # pragma: no branch
            if start + k < len(target):
                target[start + k] = UInt8(data.byte(offset + k))
    elif compression == 5:
        _lzw(data, offset, length, target, start)
    elif compression == 8 or compression == 32946:
        # UTIF drops the zlib header and the checksum, and keeps what it
        # inflates only when it fits.
        var stream = List[UInt8](capacity=max(length - 6, 0))
        for k in range(offset + 2, offset + length - 4):  # pragma: no branch
            stream.append(UInt8(data.byte(k)))
        var out = inflate(stream)
        if start + len(out) <= len(target):
            for k in range(len(out)):  # pragma: no branch
                target[start + k] = out[k]
    elif compression == 32773:
        _pack_bits(data, offset, length, target, start)
    else:
        raise Error(
            "TIFF: compression " + String(compression) + " is not decoded"
        )
    var bits = min(32, ifd.first(258, 1))
    var samples = ifd.first(277, 1)
    var pixel = (bits * samples) >> 3
    var line = (bits * samples * width + 7) // 8
    if bits == 16 and not data.little:
        for y in range(height):  # pragma: no branch
            var row = start + y * line
            for x in range(1, line, 2):  # pragma: no branch
                var a = row + x - 1
                if row + x < len(target):
                    var swap = target[row + x]
                    target[row + x] = target[a]
                    target[a] = swap
    if ifd.first(317, 1) == 2:
        for y in range(height):  # pragma: no branch
            var row = start + y * line
            if row + line > len(target):
                break
            if bits == 16:
                for j in range(pixel, line, 2):  # pragma: no branch
                    var sum = (
                        (Int(target[row + j + 1]) << 8) | Int(target[row + j])
                    ) + (
                        (Int(target[row + j - pixel + 1]) << 8)
                        | Int(target[row + j - pixel])
                    )
                    target[row + j] = UInt8(sum & 255)
                    target[row + j + 1] = UInt8((sum >> 8) & 255)
            elif samples == 3:
                for j in range(3, line, 3):  # pragma: no branch
                    for c in range(3):  # pragma: no branch
                        target[row + j + c] = (
                            target[row + j + c] + target[row + j + c - 3]
                        )
            else:
                for j in range(pixel, line):  # pragma: no branch
                    target[row + j] = target[row + j] + target[row + j - pixel]


def _decode_image(ifd: _Ifd, data: _Reader) raises -> List[UInt8]:
    """Return the first image's bytes, UTIF's `decodeImage`.

    Args:
        ifd: The image's tags.
        data: The file.

    Returns:
        The bytes, rows padded to whole bytes.

    Raises:
        Error: If the image has no size, no strips or tiles, planar
            configuration 2, or strips that cover fewer rows than the
            image; and for anything `_decompress` refuses.
    """
    var width = ifd.first(256, -1)
    var height = ifd.first(257, -1)
    if width <= 0 or height <= 0:
        raise Error("TIFF: the image has no size")
    if width * height > MAX_TIFF_PIXELS:
        raise Error("TIFF: the image is larger than this port decodes")
    var compression = ifd.first(259, 1)
    if ifd.first(284, 1) == 2:
        raise Error("TIFF: planar configuration 2 is not read")
    var samples = ifd.first(277, 1)
    var bits = ifd.first(258, 1)
    var per_pixel = bits * samples
    var line_bits = (width * per_pixel + 7) // 8 * 8
    var tiled = Bool(ifd.get(322))
    var offsets = ifd.get(324) if tiled else ifd.get(273)
    if not Bool(offsets):
        raise Error("TIFF: the image has no strips or tiles")
    var starts = offsets.value().copy()
    var counts = List[Int]()
    var stated = ifd.get(325) if tiled else ifd.get(279)
    if compression == 1 and len(starts) == 1:
        counts = [height * (line_bits >> 3)]
    elif Bool(stated):
        counts = stated.value().copy()
    var bytes = List[UInt8](length=height * (line_bits >> 3), fill=0)
    if tiled:
        var tile_width = ifd.first(322, 1)
        var tile_height = ifd.first(323, 1)
        var across = (width + tile_width - 1) // tile_width
        var down = (height + tile_height - 1) // tile_height
        var tile_bytes = (tile_width * tile_height * per_pixel + 7) // 8
        var tile_line = (tile_width * per_pixel + 7) // 8
        var image_line = (width * per_pixel + 7) // 8
        for y in range(down):  # pragma: no branch
            for x in range(across):  # pragma: no branch
                var i = y * across + x
                if i >= len(starts) or i >= len(counts):
                    raise Error("TIFF: a tile has no offset or byte count")
                var tile = List[UInt8](length=tile_bytes, fill=0)
                _decompress(
                    ifd,
                    data,
                    starts[i],
                    counts[i],
                    compression,
                    tile,
                    0,
                    tile_width,
                    tile_height,
                )
                # UTIF's `_copyTile`.
                var x_offset = (x * tile_width * per_pixel + 7) // 8
                var rows = min(tile_height, height - y * tile_height)
                var columns = min(tile_line, image_line - x_offset)
                for row in range(rows):  # pragma: no branch
                    for column in range(columns):  # pragma: no branch
                        bytes[
                            (y * tile_height + row) * image_line
                            + x_offset
                            + column
                        ] = tile[row * tile_line + column]
        return bytes^
    var rows = min(ifd.first(278, height), height)
    var filled = 0
    for i in range(len(starts)):  # pragma: no branch
        if i >= len(counts):
            raise Error("TIFF: a strip has no byte count")
        _decompress(
            ifd,
            data,
            starts[i],
            counts[i],
            compression,
            bytes,
            (filled + 7) // 8,
            width,
            rows,
        )
        filled += line_bits * rows
    if filled < len(bytes) * 8:
        raise Error("TIFF: the strips cover fewer rows than the image")
    return bytes^


def _gamma(x: Float64) -> Float64:
    """Return UTIF's `gamma`: sRGB's curve.

    Args:
        x: Linear light, zero to one.

    Returns:
        The encoded value.
    """
    if x < 0.0031308:
        return 12.92 * x
    return 1.055 * (x ** (1.0 / 2.4)) - 0.055


def _to_byte(value: Float64) -> UInt8:
    """Return `~~value` stored in a `Uint8Array`: truncated, wrapped, NaN
    zero.

    Args:
        value: The value.

    Returns:
        The byte.
    """
    if isnan(value):
        return 0
    var t = Int(trunc(value))
    return UInt8(t & 255)


def _float(data: List[UInt8], index: Int) -> Float64:
    """Return a little-endian 32-bit float of the bytes.

    Args:
        data: The bytes.
        index: Which float.

    Returns:
        The float.
    """
    var at = index * 4
    var bits = (
        UInt32(data[at])
        | (UInt32(data[at + 1]) << 8)
        | (UInt32(data[at + 2]) << 16)
        | (UInt32(data[at + 3]) << 24)
    )
    return Float64(bitcast[DType.float32](bits))


def _to_rgba8(ifd: _Ifd, var data: List[UInt8]) raises -> List[UInt8]:
    """Return the image's bytes as RGBA, UTIF's `toRGBA8`.

    Args:
        ifd: The image's tags.
        data: The image's bytes.

    Returns:
        Four bytes a pixel.

    Raises:
        Error: Where UTIF throws: 32-bit black-is-zero samples that are
            not floats, RGB of other sample sizes, RGB floats of other
            sample counts, a palette of other sample sizes, and a
            photometric form UTIF does not know or this port does not
            read.
    """
    var w = ifd.first(256, 0)
    var h = ifd.first(257, 0)
    var area = w * h
    var img = List[UInt8](length=area * 4, fill=0)
    var bits = min(32, ifd.first(258, 1))
    var intp = ifd.first(262, 2)
    if not Bool(ifd.get(262)) and bits == 1:
        intp = 0
    var defaults: List[Int] = [1, 1, 3, 1, 1, 4, 3]
    var smpls = 1
    if Bool(ifd.get(277)):
        smpls = ifd.first(277, 1)
    elif Bool(ifd.get(258)):
        smpls = len(ifd.get(258).value())
    elif intp < len(defaults):
        smpls = defaults[intp]
    var format = ifd.first(339, -1)
    if intp == 1 and bits == 32 and format != 3:
        raise Error("TIFF: 32-bit gray that is not float")
    var bpl = (smpls * bits * w + 7) // 8
    if intp == 0:
        for y in range(h):  # pragma: no branch
            var off = y * bpl
            for i in range(w):  # pragma: no branch
                var qi = (y * w + i) * 4
                var value = -1
                if bits == 1:
                    value = (
                        1 - ((Int(data[off + (i >> 3)]) >> (7 - (i & 7))) & 1)
                    ) * 255
                elif bits == 4:
                    var px = (
                        Int(data[off + (i >> 1)]) >> (4 - 4 * (i & 1))
                    ) & 15
                    value = (15 - px) * 17
                elif bits == 8:
                    value = 255 - Int(data[off + i])
                elif bits == 16:
                    var o = off + 2 * i
                    var px = (Int(data[o + 1]) << 8) | Int(data[o])
                    value = min(255, 255 - (px >> 8))
                if value >= 0:
                    for c in range(3):  # pragma: no branch
                        img[qi + c] = UInt8(value)
                    img[qi + 3] = 255
    elif intp == 1:
        for y in range(h):  # pragma: no branch
            var off = y * bpl
            for i in range(w):  # pragma: no branch
                var qi = (y * w + i) * 4
                var value: UInt8 = 0
                var set = True
                if bits == 1:
                    value = UInt8(
                        ((Int(data[off + (i >> 3)]) >> (7 - (i & 7))) & 1) * 255
                    )
                elif bits == 2:
                    value = UInt8(
                        ((Int(data[off + (i >> 2)]) >> (6 - 2 * (i & 3))) & 3)
                        * 85
                    )
                elif bits == 8:
                    value = data[off + i * smpls]
                elif bits == 16:
                    var o = off + 2 * i
                    value = UInt8(
                        min(255, ((Int(data[o + 1]) << 8) | Int(data[o])) >> 8)
                    )
                elif bits == 32:
                    # The rows are whole bytes, so the data is whole floats.
                    value = _to_byte(0.5 + 255 * _float(data, (off >> 2) + i))
                else:
                    set = False
                if set:
                    for c in range(3):  # pragma: no branch
                        img[qi + c] = value
                    img[qi + 3] = 255
    elif intp == 2:
        if bits == 8:
            for i in range(area):  # pragma: no branch
                var qi = i * 4
                if smpls == 1:
                    for c in range(3):  # pragma: no branch
                        img[qi + c] = data[i]
                    img[qi + 3] = 255
                elif smpls == 3:
                    for c in range(3):  # pragma: no branch
                        img[qi + c] = data[i * 3 + c]
                    img[qi + 3] = 255
                elif smpls >= 4:
                    for c in range(4):  # pragma: no branch
                        img[qi + c] = data[i * smpls + c]
        elif bits == 16:
            for i in range(area):  # pragma: no branch
                var qi = i * 4
                if smpls == 4:
                    for c in range(4):  # pragma: no branch
                        img[qi + c] = data[i * 8 + 1 + 2 * c]
                elif smpls == 3:
                    for c in range(3):  # pragma: no branch
                        img[qi + c] = data[i * 6 + 1 + 2 * c]
                    img[qi + 3] = 255
        elif bits == 32:
            if smpls != 3 and smpls != 4:
                raise Error(
                    "TIFF: float RGB of other than three or four samples"
                )
            var count = len(data) // 4
            var low = Float64(0)
            for i in range(count):  # pragma: no branch
                low = min(low, _float(data, i))
            if low < 0:
                # UTIF guesses the samples are the other byte order.
                for i in range(0, count * 4, 4):  # pragma: no branch
                    var a = data[i]
                    data[i] = data[i + 3]
                    data[i + 3] = a
                    var b = data[i + 1]
                    data[i + 1] = data[i + 2]
                    data[i + 2] = b
            var table = List[Float32](capacity=65536)
            for i in range(65536):  # pragma: no branch
                table.append(Float32(_gamma(Float64(i) / 65535)))
            for i in range(area):  # pragma: no branch
                var qi = i * 4
                for c in range(smpls):  # pragma: no branch
                    var v = _float(data, i * smpls + c)
                    var cv = max(0.0, min(1.0, v)) if not isnan(v) else 0.0
                    var mapped = Float64(table[Int(trunc(0.5 + cv * 65535))])
                    img[qi + c] = _to_byte(0.5 + mapped * 255)
                if smpls == 3:
                    img[qi + 3] = 255
        else:
            raise Error("TIFF: RGB of " + String(bits) + "-bit samples")
    elif intp == 3:
        var map = ifd.get(320).or_else(List[Int]())
        var cn = 1 << bits
        var extra = ifd.first(338, 0)
        var alpha = (
            bits == 8 and smpls > 1 and Bool(ifd.get(338)) and extra != 0
        )
        if bits != 1 and bits != 2 and bits != 4 and bits != 8:
            raise Error("TIFF: a palette of " + String(bits) + "-bit samples")
        for y in range(h):  # pragma: no branch
            var dof = y * bpl
            for x in range(w):  # pragma: no branch
                var qi = (y * w + x) * 4
                var mi: Int
                if bits == 1:
                    mi = (Int(data[dof + (x >> 3)]) >> (7 - (x & 7))) & 1
                elif bits == 2:
                    mi = (Int(data[dof + (x >> 2)]) >> (6 - 2 * (x & 3))) & 3
                elif bits == 4:
                    mi = (Int(data[dof + (x >> 1)]) >> (4 - 4 * (x & 1))) & 15
                else:
                    mi = Int(data[dof + x * smpls])
                for c in range(3):  # pragma: no branch
                    var at = c * cn + mi
                    img[qi + c] = (
                        UInt8((map[at] >> 8) & 255) if at < len(map) else 0
                    )
                img[qi + 3] = data[dof + x * smpls + 1] if alpha else 255
    elif intp == 5:
        var got_alpha = smpls > 4
        for i in range(area):  # pragma: no branch
            var qi = i * 4
            var si = i * smpls
            var k = Float64(255 - Int(data[si + 3])) * (1.0 / 255)
            for c in range(3):  # pragma: no branch
                img[qi + c] = _to_byte(
                    Float64(255 - Int(data[si + c])) * k + 0.5
                )
            # UTIF adds the fifth sample times zero when there is none; past
            # the data that is NaN, and the last pixel's alpha is zero.
            if got_alpha:
                img[qi + 3] = data[si + 4]
            else:
                img[qi + 3] = 255 if si + 4 < len(data) else 0
    else:
        raise Error("TIFF: photometric form " + String(intp) + " is not read")
    return img^


def read_tiff(bytes: List[UInt8]) raises -> Texture:
    """Read a TIFF's first image, three.js's `TIFFLoader.parse`.

    Args:
        bytes: The whole file.

    Returns:
        The texture: RGBA bytes, flipped, filtered linearly with a chain
        of levels, and `LINEAR`, as three.js's data texture is.

    Raises:
        Error: If the file is not `II` or `MM`, and for anything the
            module docstring lists.
    """
    if len(bytes) < 8:
        raise Error("TIFF: the file is shorter than its header")
    var little = bytes[0] == 73 and bytes[1] == 73
    var big = bytes[0] == 77 and bytes[1] == 77
    if not (little or big):
        raise Error("TIFF: the file starts with neither II nor MM")
    var reader = _Reader(bytes.copy(), little)
    var ifd = _read_ifd(reader, reader.u32(4))
    var pixels = _to_rgba8(ifd, _decode_image(ifd, reader))
    var texture = Texture(
        ifd.first(256, 0),
        ifd.first(257, 0),
        pixels^,
        CLAMP,
        BILINEAR,
        LINEAR,
        True,
        COVERAGE,
    )
    texture.flip_y = True
    return texture^
