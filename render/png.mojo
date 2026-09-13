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
