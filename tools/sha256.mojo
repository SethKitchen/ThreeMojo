# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""SHA-256, as FIPS 180-4 defines it, for the project tools.

The Python tools used `hashlib.sha256(...).hexdigest()` to pin fixtures,
cache keys and converted assets. `sha256_hex` gives the same lowercase
hexadecimal text. `Sha256` hashes data that arrives in parts.
"""

# The first 32 bits of the fractional parts of the cube roots of the first
# 64 primes.
comptime _K: Array[UInt32, 64] = [
    0x428A2F98,
    0x71374491,
    0xB5C0FBCF,
    0xE9B5DBA5,
    0x3956C25B,
    0x59F111F1,
    0x923F82A4,
    0xAB1C5ED5,
    0xD807AA98,
    0x12835B01,
    0x243185BE,
    0x550C7DC3,
    0x72BE5D74,
    0x80DEB1FE,
    0x9BDC06A7,
    0xC19BF174,
    0xE49B69C1,
    0xEFBE4786,
    0x0FC19DC6,
    0x240CA1CC,
    0x2DE92C6F,
    0x4A7484AA,
    0x5CB0A9DC,
    0x76F988DA,
    0x983E5152,
    0xA831C66D,
    0xB00327C8,
    0xBF597FC7,
    0xC6E00BF3,
    0xD5A79147,
    0x06CA6351,
    0x14292967,
    0x27B70A85,
    0x2E1B2138,
    0x4D2C6DFC,
    0x53380D13,
    0x650A7354,
    0x766A0ABB,
    0x81C2C92E,
    0x92722C85,
    0xA2BFE8A1,
    0xA81A664B,
    0xC24B8B70,
    0xC76C51A3,
    0xD192E819,
    0xD6990624,
    0xF40E3585,
    0x106AA070,
    0x19A4C116,
    0x1E376C08,
    0x2748774C,
    0x34B0BCB5,
    0x391C0CB3,
    0x4ED8AA4A,
    0x5B9CCA4F,
    0x682E6FF3,
    0x748F82EE,
    0x78A5636F,
    0x84C87814,
    0x8CC70208,
    0x90BEFFFA,
    0xA4506CEB,
    0xBEF9A3F7,
    0xC67178F2,
]
# The first 32 bits of the fractional parts of the square roots of the
# first eight primes.
comptime _H0: Array[UInt32, 8] = [
    0x6A09E667,
    0xBB67AE85,
    0x3C6EF372,
    0xA54FF53A,
    0x510E527F,
    0x9B05688C,
    0x1F83D9AB,
    0x5BE0CD19,
]
comptime _HEX = "0123456789abcdef"
comptime BLOCK = 64
"""The SHA-256 block size in bytes."""


@always_inline
def _rotr(x: UInt32, n: UInt32) -> UInt32:
    """Rotate right."""
    return (x >> n) | (x << (32 - n))


struct Sha256(Movable):
    """A SHA-256 computation over data that arrives in parts."""

    var state: Array[UInt32, 8]
    """The eight working hash values."""
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
        var w = Array[UInt32, 64](fill=0)
        for t in range(16):
            w[t] = (
                UInt32(block[4 * t]) << 24
                | UInt32(block[4 * t + 1]) << 16
                | UInt32(block[4 * t + 2]) << 8
                | UInt32(block[4 * t + 3])
            )
        for t in range(16, 64):
            var s0 = (
                _rotr(w[t - 15], 7) ^ _rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
            )
            var s1 = (
                _rotr(w[t - 2], 17) ^ _rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
            )
            w[t] = w[t - 16] + s0 + w[t - 7] + s1
        var a = self.state[0]
        var b = self.state[1]
        var c = self.state[2]
        var d = self.state[3]
        var e = self.state[4]
        var f = self.state[5]
        var g = self.state[6]
        var h = self.state[7]
        var k = materialize[_K]()
        for t in range(64):
            var big1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25)
            var choose = (e & f) ^ (~e & g)
            var t1 = h + big1 + choose + k[t] + w[t]
            var big0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22)
            var majority = (a & b) ^ (a & c) ^ (b & c)
            var t2 = big0 + majority
            h = g
            g = f
            f = e
            e = d + t1
            d = c
            c = b
            b = a
            a = t1 + t2
        self.state[0] += a
        self.state[1] += b
        self.state[2] += c
        self.state[3] += d
        self.state[4] += e
        self.state[5] += f
        self.state[6] += g
        self.state[7] += h

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

    def digest(var self) -> Array[UInt8, 32]:
        """Pad the data, finish the hash and return its 32 bytes.

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
        var out = Array[UInt8, 32](fill=0)
        for i in range(8):
            out[4 * i] = UInt8(self.state[i] >> 24)
            out[4 * i + 1] = UInt8((self.state[i] >> 16) & 0xFF)
            out[4 * i + 2] = UInt8((self.state[i] >> 8) & 0xFF)
            out[4 * i + 3] = UInt8(self.state[i] & 0xFF)
        return out^

    def hexdigest(var self) -> String:
        """Finish the hash and return it as 64 lowercase hex digits.

        Returns:
            The digest as Python's `hexdigest` writes it.
        """
        var digest = self^.digest()
        var out = String()
        for byte in digest:
            out += chr(Int(_HEX.as_bytes()[Int(byte >> 4)]))
            out += chr(Int(_HEX.as_bytes()[Int(byte & 15)]))
        return out^


def sha256_hex(data: Span[UInt8, _]) -> String:
    """Return the SHA-256 of `data` as 64 lowercase hex digits.

    Args:
        data: The bytes to hash.

    Returns:
        The digest, as `hashlib.sha256(data).hexdigest()` writes it.
    """
    var hash = Sha256()
    hash.update(data)
    return hash^.hexdigest()
