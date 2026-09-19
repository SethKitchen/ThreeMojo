# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The two checksums PNG and zlib carry.

Separate from both because both ends need them and they must not import each
other: `render.png` writes an Adler-32 and checks chunk CRCs, while
`render.inflate` checks the Adler-32 a zlib stream ends with. Keeping one copy
means the writer and the reader cannot disagree about what the checksum of the
same bytes is, which is the only interesting property a checksum has.

**Both are the frame's largest fixed cost after the pixels themselves.** An
animated PNG carries every frame uncompressed, so at 260 by 200 each frame is
two hundred kilobytes and each checksum walks all of them. The bitwise CRC --
eight shifts a byte -- and an Adler-32 that took two modulos a byte together
cost more than rasterizing a lit, textured cube on every core. So the CRC
steps eight bytes at a time through eight tables, Sarwate's table method
sliced by eight as zlib does it, and the Adler-32 takes its modulo once per
run of `ADLER_RUN` bytes, which is as far as its two sums can go before one
of them could overflow.

**The tables are built when they pay for themselves.** Mojo has no globals,
so a table has to be built by whoever needs it, and building eight of them
is 3840 steps. Below `CRC_TABLE_WORTH` bytes the bitwise loop is cheaper,
and a PNG's header, animation and frame-control chunks are all below it, so
`Crc32` starts bitwise and builds its tables the first time it is given a
span long enough to earn them. Under coverage instrumentation, where every
step is a write to stderr, that keeps the checksum of a ten-byte chunk as
cheap as it always was.
"""

comptime CRC_POLYNOMIAL = UInt32(0xEDB88320)
comptime ADLER_MODULUS = UInt32(65521)
# The most bytes Adler-32's running sums can take before either can pass
# 2^32: zlib's NMAX. The modulo is taken once per run of this many rather
# than twice per byte, and the sums hold the same values either way.
comptime ADLER_RUN = 5552
# How many bytes one step of the table CRC consumes, and so how many tables
# there are: one per byte of the step.
comptime CRC_SLICES = 8
comptime CRC_TABLE_SIZE = 256 * CRC_SLICES
# The length at which building the tables costs what the bitwise loop would:
# the tables take 256 * 8 shifts and 7 * 256 lookups, and the loop takes
# eight shifts a byte.
comptime CRC_TABLE_WORTH = CRC_TABLE_SIZE * 15 // 8 // 8
comptime _CRC_START = UInt32(0xFFFFFFFF)


def _crc_bitwise(crc: UInt32, bytes: Span[UInt8, _]) -> UInt32:
    """Advance a running CRC over `bytes`, eight shifts a byte.

    The definition itself, and what the tables are built from. The running
    value is inverted, as CRC-32 keeps it between the start and the end.

    Args:
        crc: The running value.
        bytes: The bytes to fold in.

    Returns:
        The running value after them.
    """
    var running = crc
    for index in range(len(bytes)):
        running ^= UInt32(bytes[index])
        for _ in range(8):  # pragma: no branch
            if (running & UInt32(1)) != 0:
                running = (running >> 1) ^ CRC_POLYNOMIAL
            else:
                running = running >> 1
    return running


def _crc_sliced(
    crc: UInt32, bytes: Span[UInt8, _], tables: Array[UInt32, CRC_TABLE_SIZE]
) -> UInt32:
    """Advance a running CRC over `bytes`, eight bytes a step.

    Slicing by eight: the first four bytes are folded into the running
    value and the eight bytes are looked up in their own tables, whose
    entries are the CRC of that byte followed by the zeros that many
    positions later, so the eight lookups combine with exclusive or. The
    tail shorter than a step is finished one byte at a time from the first
    table, which is Sarwate's original method.

    Args:
        crc: The running value.
        bytes: The bytes to fold in.
        tables: The eight tables, from `_crc_tables`.

    Returns:
        The running value after them.
    """
    var running = crc
    var index = 0
    var count = len(bytes)
    while index + CRC_SLICES <= count:
        var word = running ^ (
            UInt32(bytes[index])
            | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16)
            | (UInt32(bytes[index + 3]) << 24)
        )
        running = (
            tables[7 * 256 + Int(word & 0xFF)]
            ^ tables[6 * 256 + Int((word >> 8) & 0xFF)]
            ^ tables[5 * 256 + Int((word >> 16) & 0xFF)]
            ^ tables[4 * 256 + Int(word >> 24)]
            ^ tables[3 * 256 + Int(bytes[index + 4])]
            ^ tables[2 * 256 + Int(bytes[index + 5])]
            ^ tables[256 + Int(bytes[index + 6])]
            ^ tables[Int(bytes[index + 7])]
        )
        index += CRC_SLICES
    while index < count:
        running = (running >> 8) ^ tables[
            Int((running ^ UInt32(bytes[index])) & 0xFF)
        ]
        index += 1
    return running


def _crc_tables() -> Array[UInt32, CRC_TABLE_SIZE]:
    """Return the eight lookup tables `_crc_sliced` steps through.

    The first is the CRC of each single byte, from the bitwise definition.
    Each table after it is the one before shifted one byte further along:
    the CRC of the same byte followed by one more zero.

    Returns:
        The tables, end to end, the first one first.
    """
    var tables = Array[UInt32, CRC_TABLE_SIZE](fill=UInt32(0))
    for byte in range(256):  # pragma: no branch
        var one = List[UInt8]()
        one.append(UInt8(byte))
        tables[byte] = _crc_bitwise(UInt32(0), Span(one))
    for slice in range(1, CRC_SLICES):  # pragma: no branch
        for byte in range(256):  # pragma: no branch
            var previous = tables[(slice - 1) * 256 + byte]
            tables[slice * 256 + byte] = (previous >> 8) ^ tables[
                Int(previous & 0xFF)
            ]
    return tables^


struct Crc32(Movable):
    """A PNG CRC-32 in progress, fed one span at a time.

    A chunk's CRC covers its type and its data, and they sit in two
    different places; feeding them in turn is what saves joining them
    first, which copied every frame once more than it had to be.

    Bitwise until it is worth building the tables -- see the module
    docstring -- and through the tables from then on, for every span,
    however short.
    """

    var running: UInt32
    var tables: Array[UInt32, CRC_TABLE_SIZE]
    var built: Bool

    def __init__(out self):
        """Start a CRC over nothing."""
        self.running = _CRC_START
        self.tables = Array[UInt32, CRC_TABLE_SIZE](fill=UInt32(0))
        self.built = False

    def update(mut self, bytes: Span[UInt8, _]):
        """Fold `bytes` into the CRC.

        Args:
            bytes: The next bytes, in order.
        """
        if not self.built and len(bytes) >= CRC_TABLE_WORTH:
            self.tables = _crc_tables()
            self.built = True
        if self.built:
            self.running = _crc_sliced(self.running, bytes, self.tables)
        else:
            self.running = _crc_bitwise(self.running, bytes)

    def finish(self) -> UInt32:
        """Return the CRC of everything fed so far.

        Returns:
            The checksum PNG writes after a chunk.
        """
        return self.running ^ _CRC_START


def crc32(bytes: List[UInt8]) -> UInt32:
    """Return the PNG CRC-32 of `bytes`.

    Args:
        bytes: The bytes to checksum.

    Returns:
        The checksum.
    """
    var crc = Crc32()
    crc.update(Span(bytes))
    return crc.finish()


def adler32(bytes: List[UInt8]) -> UInt32:
    """Return the Adler-32 checksum zlib requires over the raw data.

    The two sums grow for a run of `ADLER_RUN` bytes and are reduced once
    at its end, which is the same answer as reducing them after every byte
    and a small fraction of the divisions.

    Args:
        bytes: The bytes to checksum.

    Returns:
        The checksum.
    """
    var low = UInt32(1)
    var high = UInt32(0)
    var index = 0
    var count = len(bytes)
    while index < count:
        var stop = index + ADLER_RUN
        if stop > count:
            stop = count
        while index < stop:
            low += UInt32(bytes[index])
            high += low
            index += 1
        low %= ADLER_MODULUS
        high %= ADLER_MODULUS
    return (high << 16) | low
