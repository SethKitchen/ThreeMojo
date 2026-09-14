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
"""

comptime CRC_POLYNOMIAL = UInt32(0xEDB88320)
comptime ADLER_MODULUS = UInt32(65521)


def crc32(bytes: List[UInt8]) -> UInt32:
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


def adler32(bytes: List[UInt8]) -> UInt32:
    """Return the Adler-32 checksum zlib requires over the raw data."""
    var low = UInt32(1)
    var high = UInt32(0)
    for index in range(len(bytes)):
        low = (low + UInt32(bytes[index])) % ADLER_MODULUS
        high = (high + low) % ADLER_MODULUS
    return (high << 16) | low
