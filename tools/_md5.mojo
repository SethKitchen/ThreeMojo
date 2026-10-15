# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""MD5, as RFC 1321 defines it, for the project tools.

Poly Haven's API gives each file's MD5 sum. The tool that pins its files
compares each download with that sum before it records the file's SHA-256.
MD5 is not safe against a chosen collision, so the manifest keeps the
SHA-256. `md5_hex` gives the same lowercase hexadecimal text as Python's
`hashlib.md5(...).hexdigest()`.
"""

comptime _HEX = "0123456789abcdef"
comptime _SHIFTS: Array[UInt32, 64] = [
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
]
comptime _K: Array[UInt32, 64] = [
    0xD76AA478,
    0xE8C7B756,
    0x242070DB,
    0xC1BDCEEE,
    0xF57C0FAF,
    0x4787C62A,
    0xA8304613,
    0xFD469501,
    0x698098D8,
    0x8B44F7AF,
    0xFFFF5BB1,
    0x895CD7BE,
    0x6B901122,
    0xFD987193,
    0xA679438E,
    0x49B40821,
    0xF61E2562,
    0xC040B340,
    0x265E5A51,
    0xE9B6C7AA,
    0xD62F105D,
    0x02441453,
    0xD8A1E681,
    0xE7D3FBC8,
    0x21E1CDE6,
    0xC33707D6,
    0xF4D50D87,
    0x455A14ED,
    0xA9E3E905,
    0xFCEFA3F8,
    0x676F02D9,
    0x8D2A4C8A,
    0xFFFA3942,
    0x8771F681,
    0x6D9D6122,
    0xFDE5380C,
    0xA4BEEA44,
    0x4BDECFA9,
    0xF6BB4B60,
    0xBEBFBC70,
    0x289B7EC6,
    0xEAA127FA,
    0xD4EF3085,
    0x04881D05,
    0xD9D4D039,
    0xE6DB99E5,
    0x1FA27CF8,
    0xC4AC5665,
    0xF4292244,
    0x432AFF97,
    0xAB9423A7,
    0xFC93A039,
    0x655B59C3,
    0x8F0CCC92,
    0xFFEFF47D,
    0x85845DD1,
    0x6FA87E4F,
    0xFE2CE6E0,
    0xA3014314,
    0x4E0811A1,
    0xF7537E82,
    0xBD3AF235,
    0x2AD7D2BB,
    0xEB86D391,
]
comptime BLOCK = 64
"""The MD5 block size in bytes."""


@always_inline
def _rotl(x: UInt32, n: UInt32) -> UInt32:
    """Rotate left."""
    return (x << n) | (x >> (32 - n))


struct Md5(Movable):
    """An MD5 computation over data that arrives in parts."""

    var state: Array[UInt32, 4]
    """The four working values."""
    var pending: List[UInt8]
    """Bytes that do not yet fill a block."""
    var length: UInt64
    """The number of bytes so far."""

    def __init__(out self):
        """Start a hash over nothing."""
        self.state = Array[UInt32, 4](fill=0)
        self.state[0] = 0x67452301
        self.state[1] = 0xEFCDAB89
        self.state[2] = 0x98BADCFE
        self.state[3] = 0x10325476
        self.pending = List[UInt8](capacity=BLOCK)
        self.length = 0

    def _compress(mut self, block: Span[UInt8, _]):
        """Fold one 64-byte block into the state."""
        var m = Array[UInt32, 16](fill=0)
        for t in range(16):
            m[t] = (
                UInt32(block[4 * t])
                | UInt32(block[4 * t + 1]) << 8
                | UInt32(block[4 * t + 2]) << 16
                | UInt32(block[4 * t + 3]) << 24
            )
        var a = self.state[0]
        var b = self.state[1]
        var c = self.state[2]
        var d = self.state[3]
        comptime shifts = _SHIFTS
        comptime constants = _K
        for i in range(64):
            var f: UInt32
            var g: Int
            if i < 16:
                f = (b & c) | (~b & d)
                g = i
            elif i < 32:
                f = (d & b) | (~d & c)
                g = (5 * i + 1) % 16
            elif i < 48:
                f = b ^ c ^ d
                g = (3 * i + 5) % 16
            else:
                f = c ^ (b | ~d)
                g = (7 * i) % 16
            f = f + a + materialize[constants]()[i] + m[g]
            a = d
            d = c
            c = b
            b = b + _rotl(f, materialize[shifts]()[i])
        self.state[0] += a
        self.state[1] += b
        self.state[2] += c
        self.state[3] += d

    def update(mut self, data: Span[UInt8, _]):
        """Add bytes to the hash.

        Args:
            data: The bytes.
        """
        self.length += UInt64(len(data))
        var at = 0
        if len(self.pending) > 0:
            while at < len(data) and len(self.pending) < BLOCK:
                self.pending.append(data[at])
                at += 1
            if len(self.pending) < BLOCK:
                return
            var block = self.pending.copy()
            self._compress(Span(block))
            self.pending.clear()
        while at + BLOCK <= len(data):
            self._compress(data[at : at + BLOCK])
            at += BLOCK
        while at < len(data):
            self.pending.append(data[at])
            at += 1

    def hexdigest(var self) -> String:
        """Finish the hash and return it as 32 lowercase hex digits.

        Returns:
            The digest, as `hashlib.md5(...).hexdigest()` writes it.
        """
        var bits = self.length * 8
        var tail = self.pending.copy()
        tail.append(0x80)
        while len(tail) % BLOCK != 56:
            tail.append(0)
        for index in range(8):
            tail.append(UInt8((bits >> UInt64(8 * index)) & 0xFF))
        var at = 0
        while at < len(tail):
            self._compress(Span(tail)[at : at + BLOCK])
            at += BLOCK
        var out = String()
        for word in range(4):
            var value = self.state[word]
            for index in range(4):
                var byte = Int((value >> UInt32(8 * index)) & 0xFF)
                out += chr(Int(_HEX.as_bytes()[byte >> 4]))
                out += chr(Int(_HEX.as_bytes()[byte & 15]))
        return out^


def md5_hex(data: Span[UInt8, _]) -> String:
    """Return the MD5 of `data` as 32 lowercase hex digits.

    Args:
        data: The bytes to hash.

    Returns:
        The digest, as `hashlib.md5(data).hexdigest()` writes it.
    """
    var hash = Md5()
    hash.update(data)
    return hash^.hexdigest()
