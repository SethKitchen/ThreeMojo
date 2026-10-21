# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Lossless recompression of PNG and APNG image streams.

`optimize` changes the DEFLATE encoding only. Every chunk keeps its
position. Metadata, frame controls, delays, blend and disposal operations,
APNG sequence numbers and the filtered scanline bytes do not change.

A run of `IDAT` chunks, or of `fdAT` chunks after one `fcTL`, holds one
zlib stream. Each stream is decoded and encoded again at level 9. The new
stream goes into the first chunk of its run, and the other chunks of the
run become empty, which PNG allows. A stream that does not get smaller
keeps its original bytes. A file that does not get smaller is returned
unchanged. Decoding stops at that image's scanline bytes.
"""

from render.checksum import Crc32
from render.deflate import zlib_deflate
from render.inflate import NO_LIMIT, zlib_inflate
from render.png import _channels_for, push_be32, push_signature

# Chunk type tags: the four ASCII bytes of the type, read big-endian.
comptime IHDR = UInt32(0x49484452)
comptime IDAT = UInt32(0x49444154)
comptime IEND = UInt32(0x49454E44)
comptime FCTL = UInt32(0x6663544C)
comptime FDAT = UInt32(0x66644154)
# An APNG frame control is 26 bytes. An fdAT chunk starts with a
# four-byte sequence number, which stays outside the zlib stream.
comptime FCTL_SIZE = 26
comptime SEQUENCE_SIZE = 4
# The compression level of the new streams: the smallest.
comptime LEVEL = 9


def _be32(bytes: List[UInt8], at: Int) -> UInt32:
    """Return the big-endian 32-bit value at `at`.

    The caller checks that four bytes are there.
    """
    return (
        UInt32(bytes[at]) << 24
        | UInt32(bytes[at + 1]) << 16
        | UInt32(bytes[at + 2]) << 8
        | UInt32(bytes[at + 3])
    )


def _has_signature(data: List[UInt8]) -> Bool:
    """Return whether `data` starts with the eight-byte PNG signature."""
    var signature = List[UInt8]()
    push_signature(signature)
    if len(data) < len(signature):
        return False
    for i in range(len(signature)):  # pragma: no branch
        if data[i] != signature[i]:
            return False
    return True


def _crc(chunk_type: UInt32, body: Span[UInt8, _]) -> UInt32:
    """Return the CRC of a chunk's type and body."""
    var type_bytes = List[UInt8]()
    push_be32(type_bytes, chunk_type)
    var crc = Crc32()
    crc.update(Span(type_bytes))
    crc.update(body)
    return crc.finish()


struct PngChunks(Movable, Sized):
    """The chunks of one PNG file, in file order."""

    var types: List[UInt32]
    """The type tag of each chunk."""
    var bodies: List[List[UInt8]]
    """The data of each chunk, without its length, type or CRC."""

    def __init__(out self):
        """Make an empty chunk list."""
        self.types = List[UInt32]()
        self.bodies = List[List[UInt8]]()

    def __len__(self) -> Int:
        """Return the number of chunks.

        Returns:
            The chunk count.
        """
        return len(self.types)

    def append(mut self, chunk_type: UInt32, var body: List[UInt8]):
        """Add one chunk at the end.

        Args:
            chunk_type: The type tag.
            body: The chunk data.
        """
        self.types.append(chunk_type)
        self.bodies.append(body^)


def read_chunks(data: List[UInt8]) raises -> PngChunks:
    """Read the CRC-checked chunks of a PNG file.

    Args:
        data: The complete file.

    Returns:
        Every chunk from `IHDR` to `IEND`.

    Raises:
        Error: If the signature is missing, a chunk is truncated or fails
            its CRC, `IEND` has data or bytes follow it, or the file does
            not start with `IHDR` and end with `IEND`.
    """
    if not _has_signature(data):
        raise Error("not a PNG file")
    var chunks = PngChunks()
    var offset = 8
    while offset < len(data):
        if offset + 12 > len(data):
            raise Error("truncated PNG chunk")
        var size = Int(_be32(data, offset))
        var end = offset + 12 + size
        if end > len(data):
            raise Error("truncated PNG chunk data")
        var chunk_type = _be32(data, offset + 4)
        var body = List[UInt8](capacity=size)
        body.extend(Span(data)[offset + 8 : end - 4])
        if _crc(chunk_type, Span(body)) != _be32(data, end - 4):
            raise Error("PNG chunk CRC mismatch")
        offset = end
        if chunk_type == IEND:
            if len(body) != 0 or offset != len(data):
                raise Error("invalid PNG end or trailing data")
            chunks.append(chunk_type, body^)
            break
        chunks.append(chunk_type, body^)
    if (
        len(chunks) == 0
        or chunks.types[0] != IHDR
        or chunks.types[len(chunks) - 1] != IEND
    ):
        raise Error("missing PNG header or end")
    return chunks^


def write_chunks(chunks: PngChunks) -> List[UInt8]:
    """Encode a signature and every chunk with its length and CRC.

    Args:
        chunks: The chunks, in file order.

    Returns:
        The complete file.
    """
    var out = List[UInt8]()
    push_signature(out)
    for i in range(len(chunks)):
        var body = Span(chunks.bodies[i])
        push_be32(out, UInt32(len(body)))
        push_be32(out, chunks.types[i])
        out.extend(body)
        push_be32(out, _crc(chunks.types[i], body))
    return out^


def _scanline_bytes(
    width: Int, height: Int, bit_depth: Int, color_type: Int
) raises -> Int:
    """Return the filtered scanline bytes of an image.

    One filter byte per row, then the packed samples. This is the most a
    stream for that image may expand to.

    Args:
        width: The image width, in pixels.
        height: The image height, in pixels.
        bit_depth: Bits per sample.
        color_type: The PNG color type.

    Returns:
        The byte count.

    Raises:
        Error: If the color type is not known, or the count does not fit.
    """
    var channels = _channels_for(color_type)
    var sample_bits = width * channels * bit_depth
    var stride = (sample_bits + 7) // 8 + 1
    if height > Int.MAX // stride:
        raise Error("A PNG larger than this decoder will build")
    return height * stride


def recompress(
    stream: List[UInt8], limit: Int = NO_LIMIT
) raises -> List[UInt8]:
    """Return a smaller equivalent zlib stream, or the original bytes.

    Args:
        stream: A complete zlib stream.
        limit: The most bytes the stream may expand to. `NO_LIMIT` keeps
            the old unbound decode for a stream whose image size is not
            known here.

    Returns:
        A level-9 stream of the same data when it is smaller, otherwise a
        copy of `stream`.

    Raises:
        Error: If `stream` is not one complete, valid zlib stream, or it
            expands past `limit`.
    """
    var raw = zlib_inflate(stream, limit)
    # `zlib_inflate` ignores bytes after the Adler-32. Without its last
    # byte, a stream that ends at its checksum loses part of it and fails.
    # So a stream that still decodes without that byte has trailing bytes.
    var shorter = List[UInt8]()
    shorter.extend(Span(stream)[: len(stream) - 1])
    var trailing = True
    try:
        _ = zlib_inflate(shorter, limit)
    except:
        trailing = False
    if trailing:
        raise Error("trailing bytes after a PNG zlib stream")
    var compressed = zlib_deflate(Span(raw), LEVEL)
    if len(compressed) < len(stream):
        return compressed^
    return stream.copy()


def _data_runs(chunks: PngChunks) raises -> List[List[Int]]:
    """Return the chunk indices of each zlib stream, in file order.

    A run is consecutive `IDAT` chunks, or consecutive `fdAT` chunks. An
    `fcTL` chunk ends the current run.
    """
    var runs = List[List[Int]]()
    var current = List[Int]()
    var previous = UInt32(0)
    for i in range(len(chunks)):  # pragma: no branch
        var chunk_type = chunks.types[i]
        if chunk_type == FCTL:
            if len(chunks.bodies[i]) != FCTL_SIZE:
                raise Error("invalid APNG frame control")
            if len(current) > 0:
                runs.append(current^)
                current = List[Int]()
        if chunk_type == IDAT or chunk_type == FDAT:
            if chunk_type == FDAT and len(chunks.bodies[i]) < SEQUENCE_SIZE:
                raise Error("short APNG frame data")
            if len(current) > 0 and chunk_type != previous:
                runs.append(current^)
                current = List[Int]()
            current.append(i)
            previous = chunk_type
    if len(current) > 0:
        runs.append(current^)
    return runs^


def optimize(data: List[UInt8]) raises -> List[UInt8]:
    """Return a no-larger PNG with the same decoded streams and controls.

    Args:
        data: The complete PNG or APNG file.

    Returns:
        The recompressed file when it is smaller, otherwise a copy of
        `data`.

    Raises:
        Error: If the file or one of its zlib streams is not valid, the
            header is too short for a data stream, or a stream expands
            past its image.
    """
    var chunks = read_chunks(data)
    var runs = _data_runs(chunks)
    var limits = List[Int]()
    if len(runs) > 0:
        var header = chunks.bodies[0].copy()
        if len(header) < 13:
            raise Error("A PNG header chunk is the wrong size")
        var bit_depth = Int(header[8])
        var color_type = Int(header[9])
        var idat_limit = _scanline_bytes(
            Int(_be32(header, 0)),
            Int(_be32(header, 4)),
            bit_depth,
            color_type,
        )
        var frame_limit = idat_limit
        var next_run = 0
        for i in range(len(chunks)):  # pragma: no branch
            if chunks.types[i] == FCTL:
                var body = chunks.bodies[i].copy()
                frame_limit = _scanline_bytes(
                    Int(_be32(body, 4)),
                    Int(_be32(body, 8)),
                    bit_depth,
                    color_type,
                )
            if next_run < len(runs) and i == runs[next_run][0]:
                var limit = idat_limit
                if chunks.types[i] == FDAT:
                    limit = frame_limit
                limits.append(limit)
                next_run += 1
    var run_index = 0
    for run in runs:
        var skip = SEQUENCE_SIZE if chunks.types[run[0]] == FDAT else 0
        var stream = List[UInt8]()
        for i in run:  # pragma: no branch
            stream.extend(Span(chunks.bodies[i])[skip:])
        var compressed = recompress(stream, limits[run_index])
        run_index += 1
        if len(compressed) >= len(stream):
            continue
        # Keep chunk positions, metadata and APNG sequence numbers.
        for n in range(len(run)):  # pragma: no branch
            var i = run[n]
            var body = List[UInt8]()
            body.extend(Span(chunks.bodies[i])[:skip])
            if n == 0:
                body.extend(Span(compressed))
            chunks.bodies[i] = body^
    var result = write_chunks(chunks)
    if len(result) < len(data):
        return result^
    return data.copy()
