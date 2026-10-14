# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""SHA-1, as FIPS 180-4 defines it, for the project tools.

Git names a file's content by the SHA-1 of `blob <size>`, a zero byte, and
the content. `git_blob_sha1` gives that name. SHA-1 is not safe against a
chosen collision, so a tool that checks a download also checks its SHA-256.
`sha1_hex` gives the same lowercase hexadecimal text as Python's
`hashlib.sha1(...).hexdigest()`.
"""

comptime _H0: Array[UInt32, 5] = [
    0x67452301,
    0xEFCDAB89,
    0x98BADCFE,
    0x10325476,
    0xC3D2E1F0,
]
comptime _HEX = "0123456789abcdef"
comptime BLOCK = 64
"""The SHA-1 block size in bytes."""


@always_inline
def _rotl(x: UInt32, n: UInt32) -> UInt32:
    """Rotate left."""
    return (x << n) | (x >> (32 - n))


struct Sha1(Movable):
    """A SHA-1 computation over data that arrives in parts."""

    var state: Array[UInt32, 5]
    """The five working hash values."""
    var pending: List[UInt8]
    """Bytes that do not yet fill a block."""
    var length: UInt64
    """The number of bytes so far."""

    def __init__(out self):
        """Start a hash over nothing."""
        self.state = materialize[_H0]()
        self.pending = List[UInt8](capacity=BLOCK)
        self.length = 0

    def _compress(mut self, block: Span[UInt8, _]):
        """Fold one 64-byte block into the state."""
        var w = Array[UInt32, 80](fill=0)
        for t in range(16):
            w[t] = (
                UInt32(block[4 * t]) << 24
                | UInt32(block[4 * t + 1]) << 16
                | UInt32(block[4 * t + 2]) << 8
                | UInt32(block[4 * t + 3])
            )
        for t in range(16, 80):
            w[t] = _rotl(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1)
        var a = self.state[0]
        var b = self.state[1]
        var c = self.state[2]
        var d = self.state[3]
        var e = self.state[4]
        for t in range(80):
            var f: UInt32
            var k: UInt32
            if t < 20:
                f = (b & c) | (~b & d)
                k = 0x5A827999
            elif t < 40:
                f = b ^ c ^ d
                k = 0x6ED9EBA1
            elif t < 60:
                f = (b & c) | (b & d) | (c & d)
                k = 0x8F1BBCDC
            else:
                f = b ^ c ^ d
                k = 0xCA62C1D6
            var temp = _rotl(a, 5) + f + e + k + w[t]
            e = d
            d = c
            c = _rotl(b, 30)
            b = a
            a = temp
        self.state[0] += a
        self.state[1] += b
        self.state[2] += c
        self.state[3] += d
        self.state[4] += e

    def update(mut self, data: Span[UInt8, _]):
        """Add the next bytes.

        Args:
            data: The bytes, in order.
        """
        self.length += UInt64(len(data))
        var i = 0
        if len(self.pending) > 0:
            while i < len(data) and len(self.pending) < BLOCK:
                self.pending.append(data[i])
                i += 1
            if len(self.pending) < BLOCK:
                return
            var block = self.pending.copy()
            self._compress(Span(block))
            self.pending.clear()
        while i + BLOCK <= len(data):
            self._compress(data[i : i + BLOCK])
            i += BLOCK
        while i < len(data):
            self.pending.append(data[i])
            i += 1

    def digest(var self) -> Array[UInt8, 20]:
        """Pad the data, finish the hash and return its 20 bytes.

        Returns:
            The digest, most significant byte first.
        """
        var bits = self.length * 8
        var padding = List[UInt8]()
        padding.append(0x80)
        var used = (len(self.pending) + 1) % BLOCK
        var zeros = (BLOCK + 56 - used) % BLOCK
        for _ in range(zeros):
            padding.append(0)
        for shift in range(7, -1, -1):
            padding.append(UInt8((bits >> UInt64(8 * shift)) & 0xFF))
        var length = self.length
        self.update(Span(padding))
        self.length = length
        var out = Array[UInt8, 20](fill=0)
        for i in range(5):
            out[4 * i] = UInt8(self.state[i] >> 24)
            out[4 * i + 1] = UInt8((self.state[i] >> 16) & 0xFF)
            out[4 * i + 2] = UInt8((self.state[i] >> 8) & 0xFF)
            out[4 * i + 3] = UInt8(self.state[i] & 0xFF)
        return out^

    def hexdigest(var self) -> String:
        """Finish the hash and return it as 40 lowercase hex digits.

        Returns:
            The digest as Python's `hexdigest` writes it.
        """
        var digest = self^.digest()
        var out = String()
        for byte in digest:
            out += chr(Int(_HEX.as_bytes()[Int(byte >> 4)]))
            out += chr(Int(_HEX.as_bytes()[Int(byte & 15)]))
        return out^


def sha1_hex(data: Span[UInt8, _]) -> String:
    """Return the SHA-1 of `data` as 40 lowercase hex digits.

    Args:
        data: The bytes to hash.

    Returns:
        The digest, as `hashlib.sha1(data).hexdigest()` writes it.
    """
    var hash = Sha1()
    hash.update(data)
    return hash^.hexdigest()


def git_blob_sha1(data: Span[UInt8, _]) -> String:
    """Return the name git gives a file's content.

    Args:
        data: The file's bytes.

    Returns:
        The SHA-1 of `blob <size>`, a zero byte and `data`, as 40 lowercase
        hex digits.
    """
    var hash = Sha1()
    var prefix = String("blob ") + String(len(data))
    hash.update(prefix.as_bytes())
    var zero = List[UInt8]()
    zero.append(0)
    hash.update(Span(zero))
    hash.update(data)
    return hash^.hexdigest()
