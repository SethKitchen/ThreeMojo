# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Python's `random.Random`, so a ported generator draws the same cases.

`PythonRandom(seed)` is `random.Random(seed)` for an integer seed: the
MT19937 generator, seeded by `init_by_array` from the seed's 32-bit words.
`getrandbits`, `randrange` and `random` give the values CPython 3.12 gives.
"""

from tools._bigint import BigInt

comptime N = 624
comptime M = 397


struct PythonRandom(Movable):
    """The Mersenne Twister, as CPython's `random.Random` runs it."""

    var state: List[UInt32]
    """The 624 state words."""
    var index: Int
    """The next word to use; 624 means the state must be generated."""

    def __init__(out self, seed: Int):
        """Seed as `random.Random(seed)` does for an integer.

        Args:
            seed: The seed. Only its absolute value is used.
        """
        self.state = List[UInt32](length=N, fill=0)
        self.index = N
        var key = List[UInt32]()
        var magnitude = UInt64(seed) if seed >= 0 else UInt64(0) - UInt64(seed)
        while magnitude != 0:
            key.append(UInt32(magnitude & 0xFFFFFFFF))
            magnitude >>= 32
        if len(key) == 0:
            key.append(0)
        self._init_by_array(key)

    def _init_genrand(mut self, seed: UInt32):
        """Seed the state from one word."""
        self.state[0] = seed
        for i in range(1, N):
            var previous = self.state[i - 1]
            self.state[i] = UInt32(1812433253) * (
                previous ^ (previous >> 30)
            ) + UInt32(i)
        self.index = N

    def _init_by_array(mut self, key: List[UInt32]):
        """Seed the state from words, as `init_by_array` does."""
        self._init_genrand(19650218)
        var i = 1
        var j = 0
        var k = max(N, len(key))
        while k > 0:
            var previous = self.state[i - 1]
            self.state[i] = (
                (
                    self.state[i]
                    ^ ((previous ^ (previous >> 30)) * UInt32(1664525))
                )
                + key[j]
                + UInt32(j)
            )
            i += 1
            j += 1
            if i >= N:
                self.state[0] = self.state[N - 1]
                i = 1
            if j >= len(key):
                j = 0
            k -= 1
        k = N - 1
        while k > 0:
            var previous = self.state[i - 1]
            self.state[i] = (
                self.state[i]
                ^ ((previous ^ (previous >> 30)) * UInt32(1566083941))
            ) - UInt32(i)
            i += 1
            if i >= N:
                self.state[0] = self.state[N - 1]
                i = 1
            k -= 1
        self.state[0] = 0x80000000

    def _generate(mut self):
        """Make the next 624 words."""
        for k in range(N):
            var y = (self.state[k] & 0x80000000) | (
                self.state[(k + 1) % N] & 0x7FFFFFFF
            )
            var value = self.state[(k + M) % N] ^ (y >> 1)
            if y & 1 == 1:
                value ^= 0x9908B0DF
            self.state[k] = value
        self.index = 0

    def next_word(mut self) -> UInt32:
        """Return the next tempered 32-bit word, as `genrand_uint32` does.

        Returns:
            The word.
        """
        if self.index >= N:
            self._generate()
        var y = self.state[self.index]
        self.index += 1
        y ^= y >> 11
        y ^= (y << 7) & 0x9D2C5680
        y ^= (y << 15) & 0xEFC60000
        y ^= y >> 18
        return y

    def getrandbits(mut self, bits: Int) -> BigInt:
        """Return a random integer of `bits` bits, as `getrandbits` does.

        Args:
            bits: The number of bits, at least 0.

        Returns:
            An integer in [0, 2**bits).
        """
        if bits <= 0:
            return BigInt(0)
        if bits <= 32:
            return BigInt(Int(self.next_word() >> UInt32(32 - bits)))
        var limbs = List[UInt32]()
        var rest = bits
        while rest > 0:
            var word = self.next_word()
            if rest < 32:
                word >>= UInt32(32 - rest)
            limbs.append(word)
            rest -= 32
        return BigInt._make(False, limbs^)

    def randbelow(mut self, bound: BigInt) -> BigInt:
        """Return a random integer in [0, bound), as `_randbelow` does.

        Args:
            bound: A positive bound.

        Returns:
            The integer.
        """
        var bits = bound.bit_length()
        var value = self.getrandbits(bits)
        while value >= bound:
            value = self.getrandbits(bits)
        return value^

    def randrange(mut self, start: BigInt, stop: BigInt) -> BigInt:
        """Return a random integer in [start, stop), as `randrange` does
        with a step of one.

        Args:
            start: The lowest value.
            stop: One past the highest value.

        Returns:
            The integer.
        """
        return start + self.randbelow(stop - start)

    def random(mut self) -> Float64:
        """Return a random double in [0, 1), as `random()` does.

        Returns:
            The double, from 53 random bits.
        """
        var a = Float64(self.next_word() >> 5)
        var b = Float64(self.next_word() >> 6)
        return (a * 67108864.0 + b) * (1.0 / 9007199254740992.0)
