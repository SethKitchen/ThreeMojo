# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""TSL's integer functions on a `NodeGraph`: 32-bit words, `hash`, the
bitcasts, the bit counts, the float packings and the packed 4x8 integers.

three.js: `src/nodes/math/Hash.js`, `BitcastNode.js`, `BitcountNode.js`,
`PackFloatNode.js`, `UnpackFloatNode.js` and `Packed4x8IntegerNode.js`.

**Why a word is two halves.** A node's value is a float, and a float holds
a whole number exactly only up to 2 ** 24. A `uint` of three.js holds 32
bits. So this module holds a 32-bit word as a `NodeWord`: a `vec2` node of
its low 16 bits and its high 16 bits, each a whole number from 0 to 65535.
Each operation on a word works on the halves, and cuts a product into bytes
first, so that no value it computes passes 2 ** 24. The bit operations of
`NodeGraph` are exact on a half. So a word is exact on both backends, and
`hash` gives three.js's bits.

Every function builds nodes of the existing bytecode. None adds an
instruction, so the CPU and the GPU run it with the one interpreter.

**Where this differs from three.js.** A bitcast of a float and the packings
of halves flush a subnormal to zero, as a GPU that flushes subnormals does.
A NaN gives no fixed word. The bit counts read a `float` or a vector of
whole numbers, which a float holds exactly up to 2 ** 24. A word is one
`uint`: a vector of words is a list of `NodeWord`s.
"""

from materials.nodes import (
    NODE_FLOAT,
    NODE_VEC2,
    NODE_VEC4,
    NodeGraph,
    NodeRef,
    ValueType,
)

# The smallest normal float, 2 ** -126, and the largest finite one.
comptime _SMALLEST_NORMAL = Float32(1.1754943508222875e-38)
comptime _LARGEST_FLOAT = Float32(3.4028234663852886e38)
# 2 ** -23, 2 ** 23, 2 ** -24 and 2 ** 24, and 2 ** -32 for `hash`.
comptime _TWO_TO_MINUS_23 = Float32(1.1920928955078125e-07)
comptime _TWO_TO_23 = Float32(8388608)
comptime _TWO_TO_MINUS_24 = Float32(5.960464477539063e-08)
comptime _TWO_TO_24 = Float32(16777216)
comptime _TWO_TO_MINUS_32 = Float32(2.3283064365386963e-10)
# The smallest normal half, 2 ** -14, and the first magnitude that rounds to
# a half's infinity: halfway past 65504, the largest finite half.
comptime _SMALLEST_NORMAL_HALF = Float32(6.103515625e-05)
comptime _HALF_OVERFLOW = Float32(65520)
comptime _HALF_INFINITY = Float32(31744)


@fieldwise_init
struct NodeWord(ImplicitlyCopyable, Movable, Writable):
    """A 32-bit word in a `NodeGraph`: the bits of TSL's `uint` or `int`.

    The node is a `vec2`. Its `x` is the low 16 bits and its `y` the high
    16 bits, each a whole number from 0 to 65535. A float holds a whole
    number exactly only up to 2 ** 24, so one float cannot hold the word.
    """

    var halves: NodeRef

    def is_valid(self) -> Bool:
        """Return True if the halves can name a node: the ref is not
        negative.

        Returns:
            Whether the halves' ref is zero or more.
        """
        return self.halves.is_valid()


def _expect(g: NodeGraph, node: NodeRef, type: ValueType, what: String) raises:
    """Refuse a node that is not of the type a function reads.

    Raises:
        Error: If the node is not of this graph or not of `type`.
    """
    var got = g.type_of(node)
    if got != type:
        raise Error(what + " reads a " + type.name() + ", not a " + got.name())


def _check_word(g: NodeGraph, word: NodeWord, what: String) raises:
    """Refuse a word that names no `vec2` of this graph.

    Raises:
        Error: If the word's ref is negative, or names no `vec2` here.
    """
    if not word.is_valid():
        raise Error(what + " reads a word that names no node")
    _expect(g, word.halves, NODE_VEC2, what)


def _power_of_two(exponent: Int) -> Float32:
    """Return 2 ** `exponent` for an exponent of 0 to 64, exactly."""
    var result = Float32(1)
    for _ in range(exponent):
        result *= 2
    return result


def _low(mut g: NodeGraph, word: NodeWord) raises -> NodeRef:
    """Return a word's low 16 bits, a `float`."""
    return g.swizzle(word.halves, "x")


def _high(mut g: NodeGraph, word: NodeWord) raises -> NodeRef:
    """Return a word's high 16 bits, a `float`."""
    return g.swizzle(word.halves, "y")


def _word_of(mut g: NodeGraph, low: NodeRef, high: NodeRef) raises -> NodeWord:
    """Return the word of two halves."""
    return NodeWord(g.join([low, high]))


def _mod(mut g: NodeGraph, x: NodeRef, by: Float32) raises -> NodeRef:
    """Return `mod(x, by)` of a constant."""
    return g.mod(x, g.float(by))


def _bytes(mut g: NodeGraph, word: NodeWord) raises -> NodeRef:
    """Return a word's four bytes, low first, a `vec4`."""
    var spread = g.div(g.swizzle(word.halves, "xxyy"), g.vec4(1, 256, 1, 256))
    return _mod(g, g.floor(spread), 256)


def exp2_whole(mut g: NodeGraph, exponent: NodeRef) raises -> NodeRef:
    """Return 2 ** `exponent` for a whole exponent from -126 to 127,
    exactly on both backends.

    `exp2` of a hardware GPU is an approximation. This multiplies 2 ** -126
    by one power of two for each bit of `exponent + 126`, and each product
    of powers of two is exact.

    Args:
        g: The graph to build the nodes in.
        exponent: A `float` or a vector of whole numbers from -126 to 127.

    Returns:
        The node, of the exponent's type.

    Raises:
        Error: If `exponent` is not a `float` or a vector of this graph.
    """
    var k = g.add(exponent, g.float(126))
    var result = g.float(_SMALLEST_NORMAL)
    for bit in range(7):  # pragma: no branch
        var factor = g.select(
            g.bit_and(k, g.float(_power_of_two(bit))),
            g.float(_power_of_two(1 << bit)),
            g.float(1),
        )
        result = g.mul(result, factor)
    # 2 ** 128 is past a float, so bit seven is 2 ** 64 twice.
    var top = g.select(
        g.bit_and(k, g.float(128)), g.float(_power_of_two(64)), g.float(1)
    )
    return g.mul(g.mul(result, top), top)


# --- words --------------------------------------------------------------------


def word(mut g: NodeGraph, x: NodeRef) raises -> NodeWord:
    """Return a whole number as a word, TSL's `uint(x)` and `x.toUint()`.

    The fraction is dropped toward zero. A negative number wraps up by
    2 ** 32, as `NodeGraph.unsigned` does. A float holds a whole number
    exactly only up to 2 ** 24.

    Args:
        g: The graph to build the nodes in.
        x: A `float`.

    Returns:
        The word.

    Raises:
        Error: If `x` is not a `float` of this graph.
    """
    _expect(g, x, NODE_FLOAT, "uint")
    var whole = g.trunc(x)
    var halves = g.join([whole, g.floor(g.div(whole, g.float(65536)))])
    return NodeWord(_mod(g, halves, 65536))


def word_constant(mut g: NodeGraph, value: UInt32) -> NodeWord:
    """Return a constant word, TSL's `uint(value)` of a number.

    Args:
        g: The graph to build the nodes in.
        value: The 32 bits.

    Returns:
        The word.
    """
    return NodeWord(
        g.vec2(Float32(Int(value & 0xFFFF)), Float32(Int(value >> 16)))
    )


def word_to_uint(mut g: NodeGraph, word: NodeWord) raises -> NodeRef:
    """Return a word read as an unsigned number, TSL's `toFloat()` of a
    `uint`: rounded to the nearest float once, as a GPU converts it.

    Args:
        g: The graph to build the nodes in.
        word: The word.

    Returns:
        A `float` from 0 to 2 ** 32.

    Raises:
        Error: If `word` names no `vec2` of this graph.
    """
    _check_word(g, word, "A word's value")
    return g.add(g.mul(_high(g, word), g.float(65536)), _low(g, word))


def word_to_int(mut g: NodeGraph, word: NodeWord) raises -> NodeRef:
    """Return a word read as a two's complement number, TSL's `toFloat()`
    of an `int`.

    Args:
        g: The graph to build the nodes in.
        word: The word.

    Returns:
        A `float` from -2 ** 31 to 2 ** 31.

    Raises:
        Error: If `word` names no `vec2` of this graph.
    """
    _check_word(g, word, "A word's signed value")
    var high = _high(g, word)
    var signed = g.select(
        g.greater_than_equal(high, g.float(32768)),
        g.sub(high, g.float(65536)),
        high,
    )
    return g.add(g.mul(signed, g.float(65536)), _low(g, word))


def word_add(mut g: NodeGraph, a: NodeWord, b: NodeWord) raises -> NodeWord:
    """Return `a + b`, modulo 2 ** 32, as a GPU adds two `uint`s.

    Args:
        g: The graph to build the nodes in.
        a: A word.
        b: A word.

    Returns:
        The word.

    Raises:
        Error: If either names no `vec2` of this graph.
    """
    _check_word(g, a, "A word's add")
    _check_word(g, b, "A word's add")
    var sum = g.add(a.halves, b.halves)
    var low = g.swizzle(sum, "x")
    var carry = g.floor(g.div(low, g.float(65536)))
    var high = _mod(g, g.add(g.swizzle(sum, "y"), carry), 65536)
    return _word_of(g, _mod(g, low, 65536), high)


def word_mul(mut g: NodeGraph, a: NodeWord, b: NodeWord) raises -> NodeWord:
    """Return `a * b`, modulo 2 ** 32, as a GPU multiplies two `uint`s.

    `a` is cut into bytes, so each partial product is less than 2 ** 24
    and exact. The product of the low halves carries into the high half.

    Args:
        g: The graph to build the nodes in.
        a: A word.
        b: A word.

    Returns:
        The word.

    Raises:
        Error: If either names no `vec2` of this graph.
    """
    _check_word(g, a, "A word's multiply")
    _check_word(g, b, "A word's multiply")
    var bytes = _bytes(g, a)
    var b_low = _low(g, b)
    var b_high = _high(g, b)
    # Each byte of `a` times the low half of `b`, and the low two bytes of
    # `a` times the high half of `b`: the rest is past 32 bits.
    var by_low = g.mul(bytes, b_low)
    var by_high = g.mul(g.swizzle(bytes, "xy"), b_high)
    var p = g.swizzle(by_low, "x")
    var q = g.swizzle(by_low, "y")
    var low = g.add(_mod(g, p, 65536), g.mul(_mod(g, q, 256), g.float(256)))
    var carry = g.add(
        g.add(
            g.floor(g.div(p, g.float(65536))), g.floor(g.div(q, g.float(256)))
        ),
        g.floor(g.div(low, g.float(65536))),
    )
    var cross_low = g.add(
        g.swizzle(by_low, "z"),
        g.mul(_mod(g, g.swizzle(by_low, "w"), 256), g.float(256)),
    )
    var cross_high = g.add(
        g.swizzle(by_high, "x"),
        g.mul(_mod(g, g.swizzle(by_high, "y"), 256), g.float(256)),
    )
    var high = g.add(
        g.add(_mod(g, cross_low, 65536), _mod(g, cross_high, 65536)), carry
    )
    return _word_of(g, _mod(g, low, 65536), _mod(g, high, 65536))


def word_bit_and(mut g: NodeGraph, a: NodeWord, b: NodeWord) raises -> NodeWord:
    """Return `a & b`, TSL's `bitAnd` of two `uint`s.

    Args:
        g: The graph to build the nodes in.
        a: A word.
        b: A word.

    Returns:
        The word.

    Raises:
        Error: If either names no `vec2` of this graph.
    """
    _check_word(g, a, "A word's bitAnd")
    _check_word(g, b, "A word's bitAnd")
    return NodeWord(g.bit_and(a.halves, b.halves))


def word_bit_or(mut g: NodeGraph, a: NodeWord, b: NodeWord) raises -> NodeWord:
    """Return `a | b`, TSL's `bitOr` of two `uint`s.

    Args:
        g: The graph to build the nodes in.
        a: A word.
        b: A word.

    Returns:
        The word.

    Raises:
        Error: If either names no `vec2` of this graph.
    """
    _check_word(g, a, "A word's bitOr")
    _check_word(g, b, "A word's bitOr")
    return NodeWord(g.bit_or(a.halves, b.halves))


def word_bit_xor(mut g: NodeGraph, a: NodeWord, b: NodeWord) raises -> NodeWord:
    """Return `a ^ b`, TSL's `bitXor` of two `uint`s.

    Args:
        g: The graph to build the nodes in.
        a: A word.
        b: A word.

    Returns:
        The word.

    Raises:
        Error: If either names no `vec2` of this graph.
    """
    _check_word(g, a, "A word's bitXor")
    _check_word(g, b, "A word's bitXor")
    return NodeWord(g.bit_xor(a.halves, b.halves))


def word_shift_right(
    mut g: NodeGraph, a: NodeWord, count: NodeRef
) raises -> NodeWord:
    """Return `a >> count`, a logical shift, TSL's `shiftRight` of a `uint`.

    The count's low five bits are read, as a GPU reads them.

    Args:
        g: The graph to build the nodes in.
        a: A word.
        count: A `float`, a whole number.

    Returns:
        The word.

    Raises:
        Error: If `a` names no `vec2` or `count` no `float` of this graph.
    """
    _check_word(g, a, "A word's shiftRight")
    _expect(g, count, NODE_FLOAT, "A word's shiftRight count")
    var s = g.bit_and(count, g.float(31))
    var shifted = g.shift_right(a.halves, s)
    # Under 16: the high half's low `s` bits move down into the low half.
    var keep = g.sub(g.shift_left(g.float(1), s), g.float(1))
    var moved = g.shift_left(
        g.bit_and(_high(g, a), keep), g.sub(g.float(16), s)
    )
    var small_low = g.bit_or(g.swizzle(shifted, "x"), moved)
    # From 16: only the high half is left, in the low half.
    var big_low = g.shift_right(_high(g, a), g.sub(s, g.float(16)))
    var small = g.less_than(s, g.float(16))
    return _word_of(
        g,
        g.select(small, small_low, big_low),
        g.select(small, g.swizzle(shifted, "y"), g.float(0)),
    )


def word_shift_left(
    mut g: NodeGraph, a: NodeWord, count: NodeRef
) raises -> NodeWord:
    """Return `a << count`, modulo 2 ** 32, TSL's `shiftLeft` of a `uint`.

    The count's low five bits are read, as a GPU reads them. Each half is
    cut to the bits that stay before it is shifted, so no value passes
    2 ** 16.

    Args:
        g: The graph to build the nodes in.
        a: A word.
        count: A `float`, a whole number.

    Returns:
        The word.

    Raises:
        Error: If `a` names no `vec2` or `count` no `float` of this graph.
    """
    _check_word(g, a, "A word's shiftLeft")
    _expect(g, count, NODE_FLOAT, "A word's shiftLeft count")
    var s = g.bit_and(count, g.float(31))
    # Under 16: the low `16 - s` bits of each half stay, and the low
    # half's top `s` bits move up into the high half.
    var keep = g.sub(
        g.shift_left(g.float(1), g.sub(g.float(16), s)), g.float(1)
    )
    var kept = g.shift_left(g.bit_and(a.halves, keep), s)
    var moved = g.shift_right(_low(g, a), g.sub(g.float(16), s))
    var small_high = g.bit_or(g.swizzle(kept, "y"), moved)
    # From 16: only the low half is left, in the high half.
    var t = g.sub(s, g.float(16))
    var keep_big = g.sub(
        g.shift_left(g.float(1), g.sub(g.float(16), t)), g.float(1)
    )
    var big_high = g.shift_left(g.bit_and(_low(g, a), keep_big), t)
    var small = g.less_than(s, g.float(16))
    return _word_of(
        g,
        g.select(small, g.swizzle(kept, "x"), g.float(0)),
        g.select(small, small_high, big_high),
    )


# --- hash ---------------------------------------------------------------------


def hash(mut g: NodeGraph, seed: NodeRef) raises -> NodeRef:
    """Return three.js's `hash`: a number from zero to one, PCG's hash of a
    whole number.

    three.js: `state = uint(seed) * 747796405 + 2891336453`, then
    `word = ((state >> ((state >> 28) + 4)) ^ state) * 277803737`, and the
    answer is `float((word >> 22) ^ word) / 2 ** 32`. Each step is on a
    `NodeWord`, so the bits are three.js's.

    Args:
        g: The graph to build the nodes in.
        seed: A `float`, a whole number from -2 ** 24 to 2 ** 24.

    Returns:
        A `float` from zero to one.

    Raises:
        Error: If `seed` is not a `float` of this graph.
    """
    _expect(g, seed, NODE_FLOAT, "hash")
    var state = word_add(
        g,
        word_mul(g, word(g, seed), word_constant(g, 747796405)),
        word_constant(g, 2891336453),
    )
    var count = word_add(
        g, word_shift_right(g, state, g.float(28)), word_constant(g, 4)
    )
    var mixed = word_mul(
        g,
        word_bit_xor(g, word_shift_right(g, state, _low(g, count)), state),
        word_constant(g, 277803737),
    )
    var result = word_bit_xor(g, word_shift_right(g, mixed, g.float(22)), mixed)
    return g.mul(word_to_uint(g, result), g.float(_TWO_TO_MINUS_32))


# --- bitcasts -----------------------------------------------------------------


def _negative(mut g: NodeGraph, x: NodeRef) raises -> NodeRef:
    """Return one where `x` has its sign bit set, minus zero included: a
    zero's sign is the sign of one over it."""
    return g.logical_or(
        g.less_than(x, g.float(0)),
        g.less_than(g.div(g.float(1), x), g.float(0)),
    )


def _exponent_of(mut g: NodeGraph, a: NodeRef) raises -> List[NodeRef]:
    """Return `floor(log2(a))` and 2 ** that, exactly, for a positive `a`.

    `log2` can be off by one near a power of two, so the exponent is moved
    by one where the exact power of two says so. The exponent is held
    from -126 to 127 first.
    """
    var guess = g.clamp(g.floor(g.log2(a)), g.float(-126), g.float(127))
    var power = exp2_whole(g, guess)
    var below = g.less_than(a, power)
    var twice = g.mul(power, g.float(2))
    var above = g.greater_than_equal(a, twice)
    var exponent = g.add(g.sub(guess, below), above)
    power = g.select(
        below, g.mul(power, g.float(0.5)), g.select(above, twice, power)
    )
    return [exponent, power]


def float_bits_to_uint(mut g: NodeGraph, x: NodeRef) raises -> NodeWord:
    """Return the IEEE 754 bits of a float, TSL's `floatBitsToUint`.

    Args:
        g: The graph to build the nodes in.
        x: A `float`.

    Returns:
        The word: the sign, eight bits of exponent and 23 of mantissa.

    Raises:
        Error: If `x` is not a `float` of this graph.
    """
    _expect(g, x, NODE_FLOAT, "floatBitsToUint")
    var a = g.abs(x)
    var sign = g.select(_negative(g, x), g.float(32768), g.float(0))
    var found = _exponent_of(g, a)
    var mantissa = g.mul(
        g.sub(g.div(a, found[1]), g.float(1)), g.float(_TWO_TO_23)
    )
    var high = g.add(
        g.add(sign, g.mul(g.add(found[0], g.float(127)), g.float(128))),
        g.floor(g.div(mantissa, g.float(65536))),
    )
    var normal = g.join([_mod(g, mantissa, 65536), high])
    var infinite = g.join([g.float(0), g.add(sign, g.float(32640))])
    var zero = g.join([g.float(0), sign])
    var halves = g.select(
        g.less_than(a, g.float(_SMALLEST_NORMAL)),
        zero,
        g.select(g.greater_than(a, g.float(_LARGEST_FLOAT)), infinite, normal),
    )
    return NodeWord(halves)


def float_bits_to_int(mut g: NodeGraph, x: NodeRef) raises -> NodeWord:
    """Return the IEEE 754 bits of a float, TSL's `floatBitsToInt`.

    The bits are those of `float_bits_to_uint`. `word_to_int` reads them
    as a signed number.

    Args:
        g: The graph to build the nodes in.
        x: A `float`.

    Returns:
        The word.

    Raises:
        Error: If `x` is not a `float` of this graph.
    """
    return float_bits_to_uint(g, x)


def uint_bits_to_float(mut g: NodeGraph, bits: NodeWord) raises -> NodeRef:
    """Return the float that a word's bits encode, TSL's `uintBitsToFloat`.

    Args:
        g: The graph to build the nodes in.
        bits: The word.

    Returns:
        A `float`. An exponent of zero gives a zero of the word's sign.

    Raises:
        Error: If `bits` names no `vec2` of this graph.
    """
    _check_word(g, bits, "uintBitsToFloat")
    var high = _high(g, bits)
    var biased = _mod(g, g.floor(g.div(high, g.float(128))), 256)
    var mantissa = g.add(
        g.mul(_mod(g, high, 128), g.float(65536)), _low(g, bits)
    )
    var scale = exp2_whole(
        g, g.clamp(g.sub(biased, g.float(127)), g.float(-126), g.float(127))
    )
    var normal = g.mul(
        g.add(g.float(1), g.mul(mantissa, g.float(_TWO_TO_MINUS_23))), scale
    )
    var special = g.select(
        g.equal(mantissa, g.float(0)),
        g.div(g.float(1), g.float(0)),
        g.div(g.float(0), g.float(0)),
    )
    var magnitude = g.select(
        g.equal(biased, g.float(0)),
        g.float(0),
        g.select(g.equal(biased, g.float(255)), special, normal),
    )
    return g.select(
        g.greater_than_equal(high, g.float(32768)),
        g.negate(magnitude),
        magnitude,
    )


def int_bits_to_float(mut g: NodeGraph, bits: NodeWord) raises -> NodeRef:
    """Return the float that a word's bits encode, TSL's `intBitsToFloat`.

    Args:
        g: The graph to build the nodes in.
        bits: The word.

    Returns:
        A `float`, as `uint_bits_to_float` gives.

    Raises:
        Error: If `bits` names no `vec2` of this graph.
    """
    return uint_bits_to_float(g, bits)


# --- bit counts ---------------------------------------------------------------


def _halves_of(mut g: NodeGraph, x: NodeRef) raises -> List[NodeRef]:
    """Return the low and the high 16 bits of each component's 32-bit two's
    complement integer."""
    var mask = g.float(65535)
    return [
        g.bit_and(x, mask),
        g.bit_and(g.shift_right(x, g.float(16)), mask),
    ]


def _ones16(mut g: NodeGraph, v: NodeRef) raises -> NodeRef:
    """Return how many bits of a 16-bit number are one, by pairs, nibbles
    and bytes, as three.js's fallback does on 32 bits."""
    var fives = g.float(0x5555)
    var threes = g.float(0x3333)
    var x = g.sub(v, g.bit_and(g.shift_right(v, g.float(1)), fives))
    x = g.add(
        g.bit_and(x, threes), g.bit_and(g.shift_right(x, g.float(2)), threes)
    )
    x = g.bit_and(g.add(x, g.shift_right(x, g.float(4))), g.float(0x0F0F))
    return g.add(g.bit_and(x, g.float(255)), g.shift_right(x, g.float(8)))


def _leading16(mut g: NodeGraph, v: NodeRef) raises -> NodeRef:
    """Return the leading zeros of a 16-bit number that is not zero, by
    halving the width as three.js's fallback does."""
    var n = g.float(0)
    var x = v
    for width in [8, 4, 2]:  # pragma: no branch
        var z = g.equal(
            g.shift_right(x, g.float(Float32(16 - width))), g.float(0)
        )
        n = g.add(n, g.mul(z, g.float(Float32(width))))
        x = g.select(z, g.shift_left(x, g.float(Float32(width))), x)
    var last = g.equal(g.shift_right(x, g.float(15)), g.float(0))
    return g.add(n, last)


def _trailing16(mut g: NodeGraph, v: NodeRef) raises -> NodeRef:
    """Return the trailing zeros of a 16-bit number that is not zero, by
    halving the width."""
    var n = g.float(0)
    var x = v
    for width in [8, 4, 2]:  # pragma: no branch
        var mask = g.float(_power_of_two(width) - 1)
        var z = g.equal(g.bit_and(x, mask), g.float(0))
        n = g.add(n, g.mul(z, g.float(Float32(width))))
        x = g.select(z, g.shift_right(x, g.float(Float32(width))), x)
    var last = g.equal(g.bit_and(x, g.float(1)), g.float(0))
    return g.add(n, last)


def count_one_bits(mut g: NodeGraph, x: NodeRef) raises -> NodeRef:
    """Return how many bits are one in each component, TSL's
    `countOneBits`.

    Args:
        g: The graph to build the nodes in.
        x: A `float` or a vector of whole numbers, each a 32-bit integer.

    Returns:
        The node, of `x`'s type, from 0 to 32.

    Raises:
        Error: If `x` is not a `float` or a vector of this graph.
    """
    var halves = _halves_of(g, x)
    return g.add(_ones16(g, halves[0]), _ones16(g, halves[1]))


def count_leading_zeros(mut g: NodeGraph, x: NodeRef) raises -> NodeRef:
    """Return how many bits are zero above the highest one in each
    component, TSL's `countLeadingZeros`. Zero has 32.

    Args:
        g: The graph to build the nodes in.
        x: A `float` or a vector of whole numbers, each a 32-bit integer.

    Returns:
        The node, of `x`'s type, from 0 to 32.

    Raises:
        Error: If `x` is not a `float` or a vector of this graph.
    """
    var halves = _halves_of(g, x)
    var low = halves[0]
    var high = halves[1]
    var zero = g.float(0)
    var count = g.select(
        g.not_equal(high, zero),
        _leading16(g, high),
        g.add(g.float(16), _leading16(g, low)),
    )
    var none = g.logical_and(g.equal(high, zero), g.equal(low, zero))
    return g.select(none, g.float(32), count)


def count_trailing_zeros(mut g: NodeGraph, x: NodeRef) raises -> NodeRef:
    """Return how many bits are zero below the lowest one in each
    component, TSL's `countTrailingZeros`. Zero has 32.

    Args:
        g: The graph to build the nodes in.
        x: A `float` or a vector of whole numbers, each a 32-bit integer.

    Returns:
        The node, of `x`'s type, from 0 to 32.

    Raises:
        Error: If `x` is not a `float` or a vector of this graph.
    """
    var halves = _halves_of(g, x)
    var low = halves[0]
    var high = halves[1]
    var zero = g.float(0)
    var count = g.select(
        g.not_equal(low, zero),
        _trailing16(g, low),
        g.add(g.float(16), _trailing16(g, high)),
    )
    var none = g.logical_and(g.equal(high, zero), g.equal(low, zero))
    return g.select(none, g.float(32), count)


# --- float packing ------------------------------------------------------------


def _half_bits(mut g: NodeGraph, v: NodeRef) raises -> NodeRef:
    """Return the IEEE 754 half-precision bits of each component, rounded
    to the nearest, a tie to the even."""
    var a = g.abs(v)
    var found = _exponent_of(g, a)
    var mantissa = g.round(
        g.mul(g.sub(g.div(a, found[1]), g.float(1)), g.float(1024))
    )
    var normal = g.add(
        g.mul(g.add(found[0], g.float(15)), g.float(1024)), mantissa
    )
    # A subnormal half counts in steps of 2 ** -24. A mantissa that rounds
    # up to 1024 is the smallest normal half's bits.
    var tiny = g.round(g.mul(a, g.float(_TWO_TO_24)))
    var bits = g.select(
        g.less_than(a, g.float(_SMALLEST_NORMAL_HALF)), tiny, normal
    )
    bits = g.select(
        g.greater_than_equal(a, g.float(_HALF_OVERFLOW)),
        g.float(_HALF_INFINITY),
        bits,
    )
    return g.add(bits, g.select(_negative(g, v), g.float(32768), g.float(0)))


def _half_value(mut g: NodeGraph, h: NodeRef) raises -> NodeRef:
    """Return the float that each component's half-precision bits encode."""
    var exponent = _mod(g, g.floor(g.div(h, g.float(1024))), 32)
    var mantissa = _mod(g, h, 1024)
    var normal = g.mul(
        g.add(g.float(1), g.div(mantissa, g.float(1024))),
        exp2_whole(g, g.sub(exponent, g.float(15))),
    )
    var subnormal = g.mul(mantissa, g.float(_TWO_TO_MINUS_24))
    var special = g.select(
        g.equal(mantissa, g.float(0)),
        g.div(g.float(1), g.float(0)),
        g.div(g.float(0), g.float(0)),
    )
    var magnitude = g.select(
        g.equal(exponent, g.float(0)),
        subnormal,
        g.select(g.equal(exponent, g.float(31)), special, normal),
    )
    return g.select(
        g.greater_than_equal(h, g.float(32768)), g.negate(magnitude), magnitude
    )


def _two_complement(
    mut g: NodeGraph, x: NodeRef, modulus: Float32
) raises -> NodeRef:
    """Return a whole number wrapped up by `modulus` where it is negative."""
    return g.select(g.less_than(x, g.float(0)), g.add(x, g.float(modulus)), x)


def _signed(mut g: NodeGraph, x: NodeRef, modulus: Float32) raises -> NodeRef:
    """Return a whole number from 0 to `modulus` read as two's complement."""
    return g.select(
        g.greater_than_equal(x, g.float(modulus / 2)),
        g.sub(x, g.float(modulus)),
        x,
    )


def _pack_bytes(mut g: NodeGraph, bytes: NodeRef) raises -> NodeWord:
    """Return the word of four bytes, the first in the low bits."""
    var low = g.add(
        g.swizzle(bytes, "x"), g.mul(g.swizzle(bytes, "y"), g.float(256))
    )
    var high = g.add(
        g.swizzle(bytes, "z"), g.mul(g.swizzle(bytes, "w"), g.float(256))
    )
    return _word_of(g, low, high)


def pack_snorm_2x16(mut g: NodeGraph, v: NodeRef) raises -> NodeWord:
    """Return two numbers from minus one to one packed as 16-bit signed
    fixed point, TSL's `packSnorm2x16`: `round(clamp(c, -1, 1) * 32767)`.

    Args:
        g: The graph to build the nodes in.
        v: A `vec2`. `x` goes in the low bits.

    Returns:
        The word.

    Raises:
        Error: If `v` is not a `vec2` of this graph.
    """
    _expect(g, v, NODE_VEC2, "packSnorm2x16")
    var fixed = g.round(
        g.mul(g.clamp(v, g.float(-1), g.float(1)), g.float(32767))
    )
    return NodeWord(_two_complement(g, fixed, 65536))


def pack_unorm_2x16(mut g: NodeGraph, v: NodeRef) raises -> NodeWord:
    """Return two numbers from zero to one packed as 16-bit unsigned fixed
    point, TSL's `packUnorm2x16`: `round(clamp(c, 0, 1) * 65535)`.

    Args:
        g: The graph to build the nodes in.
        v: A `vec2`. `x` goes in the low bits.

    Returns:
        The word.

    Raises:
        Error: If `v` is not a `vec2` of this graph.
    """
    _expect(g, v, NODE_VEC2, "packUnorm2x16")
    return NodeWord(g.round(g.mul(g.saturate(v), g.float(65535))))


def pack_half_2x16(mut g: NodeGraph, v: NodeRef) raises -> NodeWord:
    """Return two numbers packed as IEEE 754 half-precision floats, TSL's
    `packHalf2x16`, each rounded to the nearest half.

    Args:
        g: The graph to build the nodes in.
        v: A `vec2`. `x` goes in the low bits.

    Returns:
        The word. A magnitude from 65520 is infinity.

    Raises:
        Error: If `v` is not a `vec2` of this graph.
    """
    _expect(g, v, NODE_VEC2, "packHalf2x16")
    return NodeWord(_half_bits(g, v))


def pack_snorm_4x8(mut g: NodeGraph, v: NodeRef) raises -> NodeWord:
    """Return four numbers from minus one to one packed as 8-bit signed
    fixed point, TSL's `packSnorm4x8`: `round(clamp(c, -1, 1) * 127)`.

    Args:
        g: The graph to build the nodes in.
        v: A `vec4`. `x` goes in the lowest byte.

    Returns:
        The word.

    Raises:
        Error: If `v` is not a `vec4` of this graph.
    """
    _expect(g, v, NODE_VEC4, "packSnorm4x8")
    var fixed = g.round(
        g.mul(g.clamp(v, g.float(-1), g.float(1)), g.float(127))
    )
    return _pack_bytes(g, _two_complement(g, fixed, 256))


def pack_unorm_4x8(mut g: NodeGraph, v: NodeRef) raises -> NodeWord:
    """Return four numbers from zero to one packed as 8-bit unsigned fixed
    point, TSL's `packUnorm4x8`: `round(clamp(c, 0, 1) * 255)`.

    Args:
        g: The graph to build the nodes in.
        v: A `vec4`. `x` goes in the lowest byte.

    Returns:
        The word.

    Raises:
        Error: If `v` is not a `vec4` of this graph.
    """
    _expect(g, v, NODE_VEC4, "packUnorm4x8")
    return _pack_bytes(g, g.round(g.mul(g.saturate(v), g.float(255))))


def unpack_snorm_2x16(mut g: NodeGraph, packed: NodeWord) raises -> NodeRef:
    """Return two numbers from a word of 16-bit signed fixed point, TSL's
    `unpackSnorm2x16`: `clamp(c / 32767, -1, 1)`.

    Args:
        g: The graph to build the nodes in.
        packed: The word.

    Returns:
        A `vec2`, the low bits in `x`.

    Raises:
        Error: If `packed` names no `vec2` of this graph.
    """
    _check_word(g, packed, "unpackSnorm2x16")
    var signed = _signed(g, packed.halves, 65536)
    return g.clamp(g.div(signed, g.float(32767)), g.float(-1), g.float(1))


def unpack_unorm_2x16(mut g: NodeGraph, packed: NodeWord) raises -> NodeRef:
    """Return two numbers from a word of 16-bit unsigned fixed point, TSL's
    `unpackUnorm2x16`: `c / 65535`.

    Args:
        g: The graph to build the nodes in.
        packed: The word.

    Returns:
        A `vec2`, the low bits in `x`.

    Raises:
        Error: If `packed` names no `vec2` of this graph.
    """
    _check_word(g, packed, "unpackUnorm2x16")
    return g.div(packed.halves, g.float(65535))


def unpack_half_2x16(mut g: NodeGraph, packed: NodeWord) raises -> NodeRef:
    """Return two numbers from a word of IEEE 754 half-precision floats,
    TSL's `unpackHalf2x16`.

    Args:
        g: The graph to build the nodes in.
        packed: The word.

    Returns:
        A `vec2`, the low bits in `x`.

    Raises:
        Error: If `packed` names no `vec2` of this graph.
    """
    _check_word(g, packed, "unpackHalf2x16")
    return _half_value(g, packed.halves)


def unpack_snorm_4x8(mut g: NodeGraph, packed: NodeWord) raises -> NodeRef:
    """Return four numbers from a word of 8-bit signed fixed point, TSL's
    `unpackSnorm4x8`: `clamp(c / 127, -1, 1)`.

    Args:
        g: The graph to build the nodes in.
        packed: The word.

    Returns:
        A `vec4`, the lowest byte in `x`.

    Raises:
        Error: If `packed` names no `vec2` of this graph.
    """
    _check_word(g, packed, "unpackSnorm4x8")
    var signed = _signed(g, _bytes(g, packed), 256)
    return g.clamp(g.div(signed, g.float(127)), g.float(-1), g.float(1))


def unpack_unorm_4x8(mut g: NodeGraph, packed: NodeWord) raises -> NodeRef:
    """Return four numbers from a word of 8-bit unsigned fixed point, TSL's
    `unpackUnorm4x8`: `c / 255`.

    Args:
        g: The graph to build the nodes in.
        packed: The word.

    Returns:
        A `vec4`, the lowest byte in `x`.

    Raises:
        Error: If `packed` names no `vec2` of this graph.
    """
    _check_word(g, packed, "unpackUnorm4x8")
    return g.div(_bytes(g, packed), g.float(255))


# --- packed 4x8 integers ------------------------------------------------------


def pack4x_u8(mut g: NodeGraph, v: NodeRef) raises -> NodeWord:
    """Return the low byte of each of four whole numbers packed in a word,
    TSL's `pack4xU8`.

    Args:
        g: The graph to build the nodes in.
        v: A `vec4` of whole numbers, TSL's `uvec4`. `x` goes in the lowest
            byte.

    Returns:
        The word.

    Raises:
        Error: If `v` is not a `vec4` of this graph.
    """
    _expect(g, v, NODE_VEC4, "pack4xU8")
    return _pack_bytes(g, g.bit_and(v, g.float(255)))


def pack4x_i8(mut g: NodeGraph, v: NodeRef) raises -> NodeWord:
    """Return the low byte of each of four two's complement integers packed
    in a word, TSL's `pack4xI8`.

    Args:
        g: The graph to build the nodes in.
        v: A `vec4` of whole numbers, TSL's `ivec4`. `x` goes in the lowest
            byte.

    Returns:
        The word.

    Raises:
        Error: If `v` is not a `vec4` of this graph.
    """
    _expect(g, v, NODE_VEC4, "pack4xI8")
    return _pack_bytes(g, g.bit_and(v, g.float(255)))


def pack4x_u8_clamp(mut g: NodeGraph, v: NodeRef) raises -> NodeWord:
    """Return four whole numbers held from 0 to 255 and packed in a word,
    TSL's `pack4xU8Clamp`.

    Args:
        g: The graph to build the nodes in.
        v: A `vec4` of whole numbers. `x` goes in the lowest byte.

    Returns:
        The word.

    Raises:
        Error: If `v` is not a `vec4` of this graph.
    """
    _expect(g, v, NODE_VEC4, "pack4xU8Clamp")
    return pack4x_u8(g, g.clamp(v, g.float(0), g.float(255)))


def pack4x_i8_clamp(mut g: NodeGraph, v: NodeRef) raises -> NodeWord:
    """Return four whole numbers held from -128 to 127 and packed in a word,
    TSL's `pack4xI8Clamp`.

    Args:
        g: The graph to build the nodes in.
        v: A `vec4` of whole numbers. `x` goes in the lowest byte.

    Returns:
        The word.

    Raises:
        Error: If `v` is not a `vec4` of this graph.
    """
    _expect(g, v, NODE_VEC4, "pack4xI8Clamp")
    return pack4x_i8(g, g.clamp(v, g.float(-128), g.float(127)))


def unpack4x_u8(mut g: NodeGraph, packed: NodeWord) raises -> NodeRef:
    """Return the four bytes of a word, TSL's `unpack4xU8`.

    Args:
        g: The graph to build the nodes in.
        packed: The word.

    Returns:
        A `vec4` from 0 to 255, the lowest byte in `x`.

    Raises:
        Error: If `packed` names no `vec2` of this graph.
    """
    _check_word(g, packed, "unpack4xU8")
    return _bytes(g, packed)


def unpack4x_i8(mut g: NodeGraph, packed: NodeWord) raises -> NodeRef:
    """Return the four bytes of a word, each sign-extended, TSL's
    `unpack4xI8`.

    Args:
        g: The graph to build the nodes in.
        packed: The word.

    Returns:
        A `vec4` from -128 to 127, the lowest byte in `x`.

    Raises:
        Error: If `packed` names no `vec2` of this graph.
    """
    _check_word(g, packed, "unpack4xI8")
    return _signed(g, _bytes(g, packed), 256)


def dot4_u8_packed(
    mut g: NodeGraph, a: NodeWord, b: NodeWord
) raises -> NodeRef:
    """Return the dot product of the bytes of two words, TSL's
    `dot4U8Packed`.

    Args:
        g: The graph to build the nodes in.
        a: A word.
        b: A word.

    Returns:
        A `float`, a whole number from 0 to 260100.

    Raises:
        Error: If either names no `vec2` of this graph.
    """
    return g.dot(unpack4x_u8(g, a), unpack4x_u8(g, b))


def dot4_i8_packed(
    mut g: NodeGraph, a: NodeWord, b: NodeWord
) raises -> NodeRef:
    """Return the dot product of the sign-extended bytes of two words, TSL's
    `dot4I8Packed`.

    Args:
        g: The graph to build the nodes in.
        a: A word.
        b: A word.

    Returns:
        A `float`, a whole number from -65024 to 65536.

    Raises:
        Error: If either names no `vec2` of this graph.
    """
    return g.dot(unpack4x_i8(g, a), unpack4x_i8(g, b))
