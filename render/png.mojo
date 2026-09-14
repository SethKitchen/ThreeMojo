# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""PNG encoding with no compression library.

PNG normally implies zlib, which would be a dependency. It is avoidable: the
DEFLATE specification (RFC 1951) defines a *stored* block type that holds raw
bytes, so a completely valid zlib stream can be built from a two-byte header,
a run of stored blocks, and an Adler-32 checksum. Nothing here compresses, so
the files are larger than a real encoder's and byte-for-byte legal everywhere.

That buys RGBA with true alpha, and a file that previews in VS Code, browsers,
and every image viewer — which PPM does not.

Byte order is big-endian throughout, as PNG requires, except inside DEFLATE's
own stored-block lengths, which are little-endian.
"""

from render.framebuffer import Framebuffer
from render.inflate import zlib_inflate

comptime CRC_POLYNOMIAL = UInt32(0xEDB88320)
comptime ADLER_MODULUS = UInt32(65521)
# The largest payload a single stored DEFLATE block can carry.
comptime MAX_STORED_BLOCK = 65535
# Color type 6 is truecolor with alpha; 8 bits per channel.
comptime COLOR_TYPE_RGBA = UInt8(6)
comptime BIT_DEPTH = UInt8(8)


def _crc32(bytes: List[UInt8]) -> UInt32:
    """Return the PNG CRC-32 of `bytes`.

    Computed bitwise rather than from a lookup table. Mojo has no global
    variables, so a table would have to be rebuilt on every call — a fixed
    2048 iterations whatever the input size. Chunks here are small enough that
    the bitwise loop is cheaper, and far cheaper under coverage
    instrumentation, where every iteration costs a write to stderr.
    """
    var crc = UInt32(0xFFFFFFFF)
    # Every chunk checksums at least its four-byte type, so never empty.
    for index in range(len(bytes)):  # pragma: no branch
        crc ^= UInt32(bytes[index])
        for _ in range(8):  # pragma: no branch
            if (crc & UInt32(1)) != 0:
                crc = (crc >> 1) ^ CRC_POLYNOMIAL
            else:
                crc = crc >> 1
    return crc ^ UInt32(0xFFFFFFFF)


def _adler32(bytes: List[UInt8]) -> UInt32:
    """Return the Adler-32 checksum zlib requires over the raw data."""
    var low = UInt32(1)
    var high = UInt32(0)
    for index in range(len(bytes)):
        low = (low + UInt32(bytes[index])) % ADLER_MODULUS
        high = (high + low) % ADLER_MODULUS
    return (high << 16) | low


def push_be32(mut out: List[UInt8], value: UInt32):
    """Append `value` as four big-endian bytes."""
    out.append(UInt8((value >> 24) & 0xFF))
    out.append(UInt8((value >> 16) & 0xFF))
    out.append(UInt8((value >> 8) & 0xFF))
    out.append(UInt8(value & 0xFF))


def _push_ascii(mut out: List[UInt8], text: String):
    """Append the bytes of an ASCII string such as a chunk type."""
    var bytes = text.as_bytes()
    # A chunk type is always four characters.
    for index in range(len(bytes)):  # pragma: no branch
        out.append(bytes[index])


def push_chunk(mut out: List[UInt8], kind: String, data: List[UInt8]) raises:
    """Append one PNG chunk: length, type, data, CRC.

    The CRC covers the type and the data but not the length, which is why the
    two are gathered before checksumming.

    Args:
        out: Destination byte list.
        kind: Four-character chunk type, e.g. "IHDR".
        data: The chunk payload.

    Raises:
        Error: Never; present to match its callers.
    """
    push_be32(out, UInt32(len(data)))
    var checked = List[UInt8]()
    _push_ascii(checked, kind)
    for index in range(len(data)):
        checked.append(data[index])
    # `checked` holds the type as well as the data, so at least four bytes.
    for index in range(len(checked)):  # pragma: no branch
        out.append(checked[index])
    push_be32(out, _crc32(checked))


def raw_scanlines(buffer: Framebuffer) raises -> List[UInt8]:
    """Return the buffer's rows, each prefixed with a filter-type byte.

    Filter 0 means "None": the row is stored as-is. Real encoders pick a filter
    per row to help compression, which is pointless when nothing compresses.
    """
    var raw = List[UInt8]()
    # A Framebuffer always has positive dimensions, so this cannot run zero
    # times.
    for y in range(buffer.height):  # pragma: no branch
        raw.append(0)
        var start = y * buffer.width * Framebuffer.CHANNELS
        # A Framebuffer always has a positive width.
        for offset in range(
            buffer.width * Framebuffer.CHANNELS
        ):  # pragma: no branch
            raw.append(buffer.pixels[start + offset])
    return raw^


def zlib_stream(
    raw: List[UInt8], max_block: Int = MAX_STORED_BLOCK
) -> List[UInt8]:
    """Wrap `raw` in a zlib stream built from stored DEFLATE blocks.

    `max_block` exists so the multi-block path can be tested with a handful of
    bytes instead of the 64 KiB a real split would need. Brute-forcing that
    boundary would be slow to run and, under coverage instrumentation where
    every loop iteration emits a probe record, unusably so.

    Args:
        raw: The bytes to carry.
        max_block: Largest payload per stored block; the DEFLATE maximum
            unless a test lowers it.

    Returns:
        A complete zlib stream, header and Adler-32 included.
    """
    var out = List[UInt8]()
    # CMF: deflate, 32K window. FLG chosen so (CMF << 8 | FLG) % 31 == 0.
    out.append(0x78)
    out.append(0x01)

    var position = 0
    # An empty input still needs one final block, so this runs at least once.
    while True:
        var remaining = len(raw) - position
        var size = remaining
        if size > max_block:
            size = max_block
        var final = size == remaining

        # Block header: BFINAL in bit 0, BTYPE 00 (stored) in bits 1-2.
        out.append(1) if final else out.append(0)
        # LEN then its one's complement, both little-endian.
        out.append(UInt8(size & 0xFF))
        out.append(UInt8((size >> 8) & 0xFF))
        out.append(UInt8((~size) & 0xFF))
        out.append(UInt8(((~size) >> 8) & 0xFF))
        for offset in range(size):
            out.append(raw[position + offset])

        position += size
        if final:
            break

    push_be32(out, _adler32(raw))
    return out^


def push_signature(mut out: List[UInt8]):
    """Append the 8-byte PNG signature.

    The CR, LF and EOF bytes in the middle are there to catch a file mangled
    by a transfer that rewrote line endings.
    """
    out.append(137)
    out.append(80)
    out.append(78)
    out.append(71)
    out.append(13)
    out.append(10)
    out.append(26)
    out.append(10)


def push_ihdr(mut out: List[UInt8], width: Int, height: Int) raises:
    """Append the IHDR chunk describing an 8-bit RGBA image.

    Args:
        out: Destination byte list.
        width: Image width in pixels.
        height: Image height in pixels.

    Raises:
        Error: Never; present to match push_chunk.
    """
    var header = List[UInt8]()
    push_be32(header, UInt32(width))
    push_be32(header, UInt32(height))
    header.append(BIT_DEPTH)
    header.append(COLOR_TYPE_RGBA)
    header.append(0)  # compression method: deflate
    header.append(0)  # filter method: adaptive
    header.append(0)  # interlace method: none
    push_chunk(out, String("IHDR"), header)


def frame_data(buffer: Framebuffer) raises -> List[UInt8]:
    """Return one frame's pixels as a finished zlib stream."""
    return zlib_stream(raw_scanlines(buffer))


def encode(buffer: Framebuffer) raises -> List[UInt8]:
    """Return `buffer` encoded as a complete PNG file.

    Args:
        buffer: The RGBA pixels to encode.

    Returns:
        The bytes of a valid PNG, alpha preserved.

    Raises:
        Error: Never; present to match the helpers it calls.
    """
    var out = List[UInt8]()
    push_signature(out)
    push_ihdr(out, buffer.width, buffer.height)
    push_chunk(out, String("IDAT"), frame_data(buffer))
    push_chunk(out, String("IEND"), List[UInt8]())
    return out^


# --- Decoding ---------------------------------------------------------------
#
# Reading a PNG is not the mirror image of writing one. Writing gets to choose
# the easiest legal encoding -- filter 0 on every row, stored DEFLATE blocks --
# and a reader has to accept whatever some other encoder chose, which in
# practice is always compressed and usually filtered per row. So decoding
# needs the whole of `render.inflate` and all five filters, and this is much
# the larger half of the format.


def _be32(bytes: List[UInt8], at: Int) raises -> Int:
    """Return the big-endian 32-bit integer at `at`.

    The caller has already checked there are four bytes there: the chunk loop
    will not start a chunk without eight bytes of header, and will not reach a
    CRC it has not confirmed is present. A guard here would be a branch no
    file could take -- coverage says so.
    """
    return (
        Int(bytes[at]) << 24
        | Int(bytes[at + 1]) << 16
        | Int(bytes[at + 2]) << 8
        | Int(bytes[at + 3])
    )


def _paeth(left: Int, above: Int, corner: Int) -> Int:
    """Return whichever neighbour the Paeth predictor picks.

    The one filter that is not a plain subtraction: it estimates the current
    byte as `left + above - corner` and then answers with whichever of the
    three that estimate is nearest to. Ties go to `left`, then `above`, and
    getting that order wrong corrupts only some images, which is why it is
    worth stating.
    """
    var estimate = left + above - corner
    var from_left = abs(estimate - left)
    var from_above = abs(estimate - above)
    var from_corner = abs(estimate - corner)
    if from_left <= from_above and from_left <= from_corner:
        return left
    if from_above <= from_corner:
        return above
    return corner


def _unfilter(
    var raw: List[UInt8], width: Int, height: Int, stride: Int, step: Int
) raises -> List[UInt8]:
    """Undo the per-row filters, returning the rows with no filter bytes.

    Each row is prefixed by the filter it was encoded with, and every filter
    predicts a byte from its neighbours: the one `step` bytes to the left, the
    one directly above, and the one above-left. Bytes off the top or left edge
    count as zero.

    `step` is the distance to the byte that holds the *same channel* of the
    previous pixel, which is the pixel size in bytes -- not one. Using one
    gives an image that looks almost right and smears colour sideways.

    Args:
        raw: The decompressed rows, each with its filter byte.
        width: Image width in pixels.
        height: Image height in pixels.
        stride: Bytes per row, not counting the filter byte.
        step: Bytes per pixel, at least one.

    Returns:
        The unfiltered rows, `stride * height` bytes.

    Raises:
        Error: If the data is the wrong size or names an unknown filter.
    """
    if len(raw) != (stride + 1) * height:
        raise Error("A PNG's pixel data is the wrong size for its header")
    var out = List[UInt8](length=stride * height, fill=0)
    for y in range(height):  # pragma: no branch
        var filter = Int(raw[y * (stride + 1)])
        var source = y * (stride + 1) + 1
        var target = y * stride
        for index in range(stride):  # pragma: no branch
            var value = Int(raw[source + index])
            var left = 0
            if index >= step:
                left = Int(out[target + index - step])
            var above = 0
            if y > 0:
                above = Int(out[target + index - stride])
            var corner = 0
            if y > 0 and index >= step:
                corner = Int(out[target + index - stride - step])
            if filter == 0:
                pass
            elif filter == 1:
                value += left
            elif filter == 2:
                value += above
            elif filter == 3:
                # The average of the two neighbours, rounded down.
                value += (left + above) // 2
            elif filter == 4:
                value += _paeth(left, above, corner)
            else:
                raise Error("Unknown PNG row filter")
            out[target + index] = UInt8(value & 0xFF)
    _ = raw^
    return out^


def decode(bytes: List[UInt8]) raises -> Framebuffer:
    """Return the image a PNG file holds, as RGBA.

    Handles the five colour types at eight bits per channel — greyscale, RGB,
    palette, greyscale with alpha, and RGBA — with or without a `tRNS`
    transparency chunk, and every row filter. Everything is widened to RGBA,
    because that is what a `Framebuffer` and a `Texture` both hold and it
    means one shape reaches the renderer rather than five.

    Chunk CRCs are checked. A corrupt file that is not checked does not fail,
    it produces a plausible wrong image, and tracking that back to a bad byte
    later is far harder than refusing it here.

    Args:
        bytes: The complete file.

    Returns:
        The image.

    Raises:
        Error: If the signature, structure, a CRC or the end marker is wrong
            or missing, or the file uses
            a feature this decoder does not have: sixteen bits per channel, a
            sub-byte palette, or Adam7 interlacing. Each is refused by name
            rather than mis-decoded.
    """
    var signature = [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
    ]
    if len(bytes) < 8:
        raise Error("Too short to be a PNG")
    for index in range(8):  # pragma: no branch
        if bytes[index] != signature[index]:
            raise Error("Not a PNG: the signature does not match")

    var width = 0
    var height = 0
    var color_type = -1
    var palette = List[UInt8]()
    var alphas = List[UInt8]()
    var keyed = False
    var key = List[Int]()
    var compressed = List[UInt8]()
    var seen_header = False
    var seen_end = False

    var at = 8
    while at + 8 <= len(bytes):
        var length = _be32(bytes, at)
        var kind = String()
        for index in range(4):  # pragma: no branch
            kind += chr(Int(bytes[at + 4 + index]))
        var start = at + 8
        if start + length + 4 > len(bytes):
            raise Error("A PNG chunk runs past the end of the file")

        var body = List[UInt8]()
        for index in range(length):  # pragma: no branch
            body.append(bytes[start + index])

        # The CRC covers the type and the data, not the length.
        var checked = List[UInt8]()
        for index in range(4):  # pragma: no branch
            checked.append(bytes[at + 4 + index])
        for index in range(length):  # pragma: no branch
            checked.append(body[index])
        if UInt32(_be32(bytes, start + length)) != _crc32(checked):
            raise Error("A PNG chunk failed its CRC")

        if kind == "IHDR":
            if length != 13:
                raise Error("A PNG header chunk is the wrong size")
            width = _be32(body, 0)
            height = _be32(body, 4)
            if width <= 0 or height <= 0:
                raise Error("A PNG's dimensions must be positive")
            if Int(body[8]) == 16:
                raise Error("Sixteen bits per channel is not supported")
            if Int(body[8]) != 8:
                raise Error("Only eight bits per channel is supported")
            color_type = Int(body[9])
            if Int(body[10]) != 0:
                raise Error("Unknown PNG compression method")
            if Int(body[11]) != 0:
                raise Error("Unknown PNG filter method")
            if Int(body[12]) != 0:
                raise Error("Interlaced PNGs are not supported")
            seen_header = True
        elif kind == "PLTE":
            palette = body.copy()
        elif kind == "tRNS":
            if color_type == 3:
                alphas = body.copy()
            else:
                # One colour is transparent, given as a channel per component
                # at the file's bit depth -- so the low byte of each pair.
                keyed = True
                key = List[Int]()
                for index in range(len(body) // 2):  # pragma: no branch
                    key.append(Int(body[index * 2 + 1]))
        elif kind == "IDAT":
            for index in range(length):  # pragma: no branch
                compressed.append(body[index])
        elif kind == "IEND":
            seen_end = True
            break

        at = start + length + 4

    if not seen_header:
        raise Error("A PNG needs a header chunk")
    # A file can hold every pixel and still be truncated: lose the last chunk
    # and the image data is all there, so a decoder that stops when it runs
    # out of chunks accepts it silently. The end marker is what says the file
    # is whole.
    if not seen_end:
        raise Error("A PNG is missing its end marker; the file is truncated")
    if len(compressed) == 0:
        raise Error("A PNG needs pixel data")

    var channels: Int
    if color_type == 0:
        channels = 1
    elif color_type == 2:
        channels = 3
    elif color_type == 3:
        channels = 1
    elif color_type == 4:
        channels = 2
    elif color_type == 6:
        channels = 4
    else:
        raise Error("Unknown PNG colour type")
    if color_type == 3 and len(palette) == 0:
        raise Error("A palette PNG needs a palette")

    var rows = _unfilter(
        zlib_inflate(compressed),
        width,
        height,
        width * channels,
        channels,
    )

    var pixels = List[UInt8]()
    for index in range(width * height):  # pragma: no branch
        var at_source = index * channels
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a = UInt8(255)
        if color_type == 0:
            r = rows[at_source]
            g = r
            b = r
            if keyed and Int(r) == key[0]:
                a = 0
        elif color_type == 2:
            r = rows[at_source]
            g = rows[at_source + 1]
            b = rows[at_source + 2]
            if (
                keyed
                and Int(r) == key[0]
                and Int(g) == key[1]
                and Int(b) == key[2]
            ):
                a = 0
        elif color_type == 3:
            var slot = Int(rows[at_source])
            if slot * 3 + 2 >= len(palette):
                raise Error("A palette index is outside the palette")
            r = palette[slot * 3]
            g = palette[slot * 3 + 1]
            b = palette[slot * 3 + 2]
            # A tRNS shorter than the palette leaves the rest opaque.
            if slot < len(alphas):
                a = alphas[slot]
        elif color_type == 4:
            r = rows[at_source]
            g = r
            b = r
            a = rows[at_source + 1]
        else:
            r = rows[at_source]
            g = rows[at_source + 1]
            b = rows[at_source + 2]
            a = rows[at_source + 3]
        pixels.append(r)
        pixels.append(g)
        pixels.append(b)
        pixels.append(a)

    return Framebuffer(width, height, pixels^)
