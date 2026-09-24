# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The byte and bit writers of Draco's encoder, from Draco 1.5.6.

three.js's `DRACOExporter` runs Draco's encoder, compiled to WebAssembly.
This module ports the parts of it that write bytes and bits, the other
half of `loaders.draco_buffer`:

- `core/encoder_buffer` and `core/varint_encoding.h`: `DracoWriter`,
  with little-endian values and LEB128 varints, and `DracoBitWriter`.
- `compression/entropy/ans.h`, `rans_symbol_encoder.h`,
  `shannon_entropy.cc` and `symbol_encoding.cc`: `encode_symbols`, which
  writes the tagged or the raw rANS symbol stream, whichever Draco's
  estimate of their sizes picks.
- `compression/bit_coders`: `RAnsBitEncoder`, `DirectBitEncoder` and
  `FoldedBitEncoder`.

Draco is Copyright 2016 The Draco Authors, under the Apache License 2.0.
See THIRD-PARTY-NOTICES.md.

**Integers.** Draco does this arithmetic in 32-bit unsigned integers.
The port keeps it in `Int` and masks a result to 32 bits where the C++
can wrap. A division of a value that can be negative rounds toward zero,
as it does in C++.

**Estimates.** The size estimates sum logarithms in doubles. They take
musl's `log2`, which the WebAssembly encoder links, from
`exporters.draco_log2`, and each product is rounded before a sum uses
it, as WebAssembly rounds it. Draco counts symbols in arrays as long as
the largest symbol; the port counts them in a `Dict`, and sums in the
same order. The WebAssembly encoder runs out of memory where a symbol is
near 2^31, and the port does not.
"""

from exporters.draco_log2 import musl_log2
from loaders.draco_buffer import (
    MASK32,
    draco_require,
    most_significant_bit,
    truncated_divide,
)
from loaders.vrml_geometry import product
from std.collections import Dict
from std.math import ceil, floor
from std.memory import bitcast

# The lower bound of the state of the binary rANS coder.
comptime _L_BASE = 4096
# The bytes the rANS coders write at a time.
comptime _IO_BASE = 256
# The widest symbol the raw coding takes, in bits.
comptime _MAX_RAW_BITS = 18
# The bit lengths the tagged coding counts.
comptime _MAX_TAG_BITS = 32
# The compression level that Draco's symbol coding takes by default.
comptime DEFAULT_SYMBOL_LEVEL = 7


@fieldwise_init
struct DracoSymbolCoding(Equatable, ImplicitlyCopyable, Writable):
    """How a stream of symbols is coded, as a type rather than a bare int.

    `encode_symbols_with` refuses one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for the tagged and the raw coding.

        Returns:
            True for the two codings there are.
        """
        return self == DRACO_TAGGED_SYMBOLS or self == DRACO_RAW_SYMBOLS


# A bit length for each group of values, coded; then the raw bits.
comptime DRACO_TAGGED_SYMBOLS = DracoSymbolCoding(0)
# The values themselves, coded.
comptime DRACO_RAW_SYMBOLS = DracoSymbolCoding(1)


def signed_to_symbol(value: Int) -> Int:
    """Return the zigzag symbol that stands for a signed 32-bit integer.

    Draco's `ConvertSignedIntToSymbol`: `2v` for `v >= 0`, and
    `2(-v - 1) + 1` below zero.

    Args:
        value: A signed 32-bit integer.

    Returns:
        The unsigned symbol.
    """
    if value >= 0:
        return (value << 1) & MASK32
    return (((-(value + 1)) << 1) | 1) & MASK32


struct DracoWriter(Movable):
    """The bytes of a Draco file as they are written.

    Draco's `EncoderBuffer`, without its bit mode: see `DracoBitWriter`.
    """

    var bytes: List[UInt8]
    """The bytes written so far."""

    def __init__(out self):
        """Start with no bytes."""
        self.bytes = List[UInt8]()

    def unsigned(mut self, value: Int, size: Int):
        """Write the low bytes of a value, least significant first.

        Args:
            value: The value. Its two's complement is written.
            size: The bytes to write.
        """
        # Every value is one byte or more: the loop runs.
        for k in range(size):  # pragma: no branch
            self.bytes.append(UInt8((value >> (8 * k)) & 0xFF))

    def u8(mut self, value: Int):
        """Write a byte.

        Args:
            value: The value; its low eight bits are written.
        """
        self.unsigned(value, 1)

    def u16(mut self, value: Int):
        """Write a 16-bit integer.

        Args:
            value: The value.
        """
        self.unsigned(value, 2)

    def u32(mut self, value: Int):
        """Write a 32-bit integer, signed or not.

        Args:
            value: The value.
        """
        self.unsigned(value, 4)

    def f32(mut self, value: Float32):
        """Write a 32-bit float.

        Args:
            value: The value.
        """
        self.u32(Int(bitcast[DType.uint32](value)))

    def varint(mut self, value: Int):
        """Write an unsigned LEB128 varint.

        Draco's `EncodeVarint` for an unsigned type: seven bits a byte,
        least significant first, with the high bit set on every byte but
        the last.

        Args:
            value: The value, zero or more.
        """
        var rest = value
        while rest >= 0x80:
            self.u8((rest & 0x7F) | 0x80)
            rest >>= 7
        self.u8(rest)

    def append(mut self, bytes: List[UInt8]):
        """Write bytes.

        Args:
            bytes: The bytes.
        """
        self.bytes.extend(bytes.copy())


struct DracoBitWriter(Movable):
    """Bits packed from the least significant bit of each byte up.

    Draco's `EncoderBuffer` in its bit mode. `end` writes the bytes the
    bits fill, with their count first when the reader needs it.
    """

    var bytes: List[UInt8]
    """The bytes the bits fill."""
    var count: Int
    """The bits written."""

    def __init__(out self):
        """Start with no bits."""
        self.bytes = List[UInt8]()
        self.count = 0

    def put(mut self, bits: Int, value: Int):
        """Write the low bits of a value, least significant first.

        Draco's `EncodeLeastSignificantBits32`.

        Args:
            bits: The bits to write, up to 32.
            value: The value.
        """
        # Every field is one bit or more: the loop runs.
        for bit in range(bits):  # pragma: no branch
            if self.count % 8 == 0:
                self.bytes.append(0)
            if (value >> bit) & 1 != 0:
                self.bytes[self.count // 8] |= UInt8(1 << (self.count % 8))
            self.count += 1

    def end(self, mut out: DracoWriter, write_size: Bool):
        """Write the bytes the bits fill.

        Draco's `EndBitEncoding`.

        Args:
            out: Where to write them.
            write_size: True to write their count first, as a varint.
        """
        if write_size:
            out.varint(len(self.bytes))
        out.append(self.bytes)


def _rabs_write(
    mut state: Int, mut out: List[UInt8], bit: Bool, zero_probability: Int
):
    """Draco's `rabs_desc_write`: code one bit into the binary state."""
    var one = 256 - zero_probability
    var share = one if bit else zero_probability
    if state >= _L_BASE * share:
        out.append(UInt8(state % _IO_BASE))
        state //= _IO_BASE
    var add = 0 if bit else one
    state = (state // share) * 256 + state % share + add


def _write_state(mut out: List[UInt8], state: Int):
    """Draco's `ans_write_end` and `RAnsEncoder::write_end`: the final
    state, less its base, in one to four bytes with the count on top."""
    if state < 1 << 6:
        out.append(UInt8(state))
    elif state < 1 << 14:
        var value = (1 << 14) + state
        out.append(UInt8(value & 0xFF))
        out.append(UInt8(value >> 8))
    elif state < 1 << 22:
        var value = (2 << 22) + state
        out.append(UInt8(value & 0xFF))
        out.append(UInt8((value >> 8) & 0xFF))
        out.append(UInt8(value >> 16))
    else:
        var value = (3 << 30) + state
        out.append(UInt8(value & 0xFF))
        out.append(UInt8((value >> 8) & 0xFF))
        out.append(UInt8((value >> 16) & 0xFF))
        out.append(UInt8(value >> 24))


struct RAnsBitEncoder(Copyable, Movable):
    """A stream of bits coded with binary rANS.

    Draco's `RAnsBitEncoder`: the bits are kept, and `end` codes them
    with the probability of a zero that they show.
    """

    var bits: List[Bool]
    """The bits, in order."""
    var zeros: Int
    """The zeros among them."""

    def __init__(out self):
        """Start with no bits."""
        self.bits = List[Bool]()
        self.zeros = 0

    def encode_bit(mut self, bit: Bool):
        """Add a bit.

        Args:
            bit: The bit.
        """
        self.bits.append(bit)
        if not bit:
            self.zeros += 1

    def encode_bits(mut self, count: Int, value: Int):
        """Add the low bits of a value, most significant first.

        Draco's `EncodeLeastSignificantBits32`.

        Args:
            count: The bits, from 1 to 32.
            value: The value.
        """
        # Every number is one bit or more: the loop runs.
        for i in range(count):  # pragma: no branch
            self.encode_bit((value >> (count - 1 - i)) & 1 != 0)

    def end(self, mut out: DracoWriter):
        """Code the bits and write them.

        Draco's `EndEncoding`: the probability of a zero in 256ths, then
        the coded bytes with their count first.

        Args:
            out: Where to write them.
        """
        var total = max(len(self.bits), 1)
        var raw = Int(
            product(Float64(self.zeros) / Float64(total), 256.0) + 0.5
        )
        var zero_probability = min(raw, 255)
        if zero_probability == 0:
            zero_probability = 1
        var coded = List[UInt8]()
        var state = _L_BASE
        var i = len(self.bits) - 1
        while i >= 0:
            _rabs_write(state, coded, self.bits[i], zero_probability)
            i -= 1
        _write_state(coded, state - _L_BASE)
        out.u8(zero_probability)
        out.varint(len(coded))
        out.append(coded)


struct DirectBitEncoder(Copyable, Movable):
    """A stream of raw bits in 32-bit words, most significant bit first.

    Draco's `DirectBitEncoder`.
    """

    var bits: List[Bool]
    """The bits, in order."""

    def __init__(out self):
        """Start with no bits."""
        self.bits = List[Bool]()

    def encode_bit(mut self, bit: Bool):
        """Add a bit.

        Args:
            bit: The bit.
        """
        self.bits.append(bit)

    def encode_bits(mut self, count: Int, value: Int):
        """Add the low bits of a value, most significant first.

        Args:
            count: The bits, from 1 to 32.
            value: The value.
        """
        # Every number is one bit or more: the loop runs.
        for i in range(count):  # pragma: no branch
            self.encode_bit((value >> (count - 1 - i)) & 1 != 0)

    def end(self, mut out: DracoWriter):
        """Write the words: their size in bytes, then each word.

        Draco writes the last word even when it holds no bits.

        Args:
            out: Where to write them.
        """
        var words = len(self.bits) // 32 + 1
        out.u32(words * 4)
        # There is always a last word: the loop runs.
        for w in range(words):  # pragma: no branch
            var word = 0
            for b in range(32):  # pragma: no branch
                var at = w * 32 + b
                if at < len(self.bits) and self.bits[at]:
                    word |= 1 << (31 - b)
            out.u32(word)


struct FoldedBitEncoder(Movable):
    """Numbers coded one bit position to a stream.

    Draco's `FoldedBit32Encoder<RAnsBitEncoder>`: 32 binary rANS streams,
    one for each bit of a number from the most significant down, and one
    more stream, which a number does not use.
    """

    var folds: List[RAnsBitEncoder]
    """The stream of each bit position."""
    var last: RAnsBitEncoder
    """The stream after them."""

    def __init__(out self):
        """Start with empty streams."""
        self.folds = List[RAnsBitEncoder]()
        for _ in range(_MAX_TAG_BITS):  # pragma: no branch
            self.folds.append(RAnsBitEncoder())
        self.last = RAnsBitEncoder()

    def encode_bits(mut self, count: Int, value: Int):
        """Add a number of `count` bits, one bit to each stream.

        Args:
            count: The bits, from 1 to 32.
            value: The value.
        """
        # Every number is one bit or more: the loop runs.
        for i in range(count):  # pragma: no branch
            self.folds[i].encode_bit((value >> (count - 1 - i)) & 1 != 0)

    def end(self, mut out: DracoWriter):
        """Write the 33 streams.

        Args:
            out: Where to write them.
        """
        for fold in self.folds:  # pragma: no branch
            fold.end(out)
        self.last.end(out)


def rans_table_bits(max_value: Int, unique: Int) -> Int:
    """Return Draco's estimate of the size of a table of probabilities.

    `ApproximateRAnsFrequencyTableBits`.

    Args:
        max_value: The symbols the table spans.
        unique: The symbols that occur.

    Returns:
        The bits.
    """
    var zero_bits = 8 * (unique + truncated_divide(max_value - unique, 64))
    return 8 * unique + zero_bits


def shannon_bits(symbols: List[Int]) raises -> Tuple[Int, Int]:
    """Return Draco's estimate of the bits of a stream of symbols.

    `ComputeShannonEntropy`: the sum, over the symbols from the smallest,
    of each count times the logarithm of its share.

    Args:
        symbols: The symbols.

    Returns:
        The bits, rounded toward zero, and the count of distinct symbols.

    Raises:
        Error: Never; the logarithms are of positive shares.
    """
    var counts = Dict[Int, Int]()
    # Draco writes no stream of no symbols: the loop runs.
    for s in symbols:  # pragma: no branch
        counts[s] = counts.get(s, 0) + 1
    var keys = List[Int]()
    # Draco writes no stream of no symbols: the loop runs.
    for key in counts.keys():  # pragma: no branch
        keys.append(key)
    sort(keys)
    var total = 0.0
    var n = Float64(len(symbols))
    # Draco writes no stream of no symbols: the loop runs.
    for key in keys:  # pragma: no branch
        var count = counts[key]
        total += product(Float64(count), musl_log2(Float64(count) / n))
    return (Int(-total), len(keys))


def binary_entropy(values: Int, trues: Int) raises -> Float64:
    """Return the entropy of a stream of bits, in bits a bit.

    Draco's `ComputeBinaryShannonEntropy`.

    Args:
        values: The bits.
        trues: The ones among them.

    Returns:
        The entropy; zero when every bit is the same.

    Raises:
        Error: Never; the logarithms are of shares between zero and one.
    """
    if values == 0 or trues == 0 or values == trues:
        return 0.0
    var true_share = Float64(trues) / Float64(values)
    var false_share = 1.0 - true_share
    return -(
        product(true_share, musl_log2(true_share))
        + product(false_share, musl_log2(false_share))
    )


@fieldwise_init
struct EntropyData(Copyable, ImplicitlyCopyable, Movable):
    """What `EntropyTracker` knows of the symbols so far.

    Draco's `ShannonEntropyTracker::EntropyData`.
    """

    var norm: Float64
    """The sum of `n log2 n` over the count `n` of each symbol."""
    var values: Int
    """The symbols."""
    var max_symbol: Int
    """The largest symbol."""
    var unique: Int
    """The distinct symbols."""


struct EntropyTracker(Movable):
    """The entropy of a stream of symbols, as symbols join it.

    Draco's `ShannonEntropyTracker`.
    """

    var counts: Dict[Int, Int]
    """The count of each symbol."""
    var data: EntropyData
    """The entropy so far."""

    def __init__(out self):
        """Start with no symbols."""
        self.counts = Dict[Int, Int]()
        self.data = EntropyData(0.0, 0, 0, 0)

    def _update(mut self, symbols: List[Int], keep: Bool) raises -> EntropyData:
        """Draco's `UpdateSymbols`: the entropy with `symbols` added, kept
        or not."""
        var out = self.data
        out.values += len(symbols)
        # A value has components: the loop runs.
        for symbol in symbols:  # pragma: no branch
            var count = self.counts.get(symbol, 0)
            var old = 0.0
            if count > 1:
                old = product(Float64(count), musl_log2(Float64(count)))
            elif count == 0:
                out.unique += 1
                if symbol > out.max_symbol:
                    out.max_symbol = symbol
            count += 1
            self.counts[symbol] = count
            var new = product(Float64(count), musl_log2(Float64(count)))
            out.norm += new - old
        if keep:
            self.data = out
        else:
            # A value has components: the loop runs.
            for symbol in symbols:  # pragma: no branch
                self.counts[symbol] = self.counts[symbol] - 1
        return out

    def peek(mut self, symbols: List[Int]) raises -> EntropyData:
        """Return the entropy with symbols added, and keep it as it was.

        Args:
            symbols: The symbols.

        Returns:
            The entropy they would give.

        Raises:
            Error: Never; the logarithms are of counts of one or more.
        """
        return self._update(symbols, False)

    def push(mut self, symbols: List[Int]) raises:
        """Add symbols.

        Args:
            symbols: The symbols.

        Raises:
            Error: Never; the logarithms are of counts of one or more.
        """
        _ = self._update(symbols, True)


def entropy_data_bits(data: EntropyData) raises -> Int:
    """Return Draco's estimate of the bits of the symbols themselves.

    `ShannonEntropyTracker::GetNumberOfDataBits`.

    Args:
        data: The entropy.

    Returns:
        `ceil(n log2 n - norm)`, or zero for fewer than two symbols.

    Raises:
        Error: Never; the logarithm is of two or more.
    """
    if data.values < 2:
        return 0
    var n = Float64(data.values)
    return Int(ceil(product(n, musl_log2(n)) - data.norm))


def entropy_table_bits(data: EntropyData) -> Int:
    """Return Draco's estimate of the bits of the symbols' table.

    `ShannonEntropyTracker::GetNumberOfRAnsTableBits`.

    Args:
        data: The entropy.

    Returns:
        The bits.
    """
    return rans_table_bits(data.max_symbol + 1, data.unique)


def _precision_bits(symbol_bits: Int) -> Int:
    """Draco's `ComputeRAnsPrecisionFromUniqueSymbolsBitLength`."""
    return min(max((3 * symbol_bits) // 2, 12), 20)


struct RAnsSymbolEncoder(Movable):
    """A stream of symbols coded with rANS.

    Draco's `RAnsSymbolEncoder`: a table of probabilities, scaled from
    the counts of the symbols, then the symbols coded from the last.
    """

    var precision: Int
    """The sum of the probabilities, a power of two."""
    var probabilities: List[Int]
    """The probability of each symbol."""
    var starts: List[Int]
    """The sum of the probabilities before each symbol."""
    var coded: List[UInt8]
    """The coded bytes."""
    var state: Int
    """The state of the coder."""

    def __init__(out self, symbol_bits: Int):
        """Make an encoder for a table of up to `2^symbol_bits` symbols.

        Args:
            symbol_bits: The bits of the count of distinct symbols.
        """
        self.precision = 1 << _precision_bits(symbol_bits)
        self.probabilities = List[Int]()
        self.starts = List[Int]()
        self.coded = List[UInt8]()
        self.state = 4 * self.precision

    def create(mut self, counts: List[Int], mut out: DracoWriter) raises:
        """Scale the counts to probabilities, and write the table.

        Draco's `Create` and `EncodeTable`. Each probability is the share
        of its symbol times the precision, rounded, and at least one for
        a symbol that occurs. Then the most likely symbols give up or
        take the difference from the precision.

        Args:
            counts: The count of each symbol.
            out: Where to write the table.

        Raises:
            Error: If the probabilities cannot sum to the precision.
        """
        var total = 0
        var last = 0
        # Draco writes no stream of no symbols: the loop runs.
        for i in range(len(counts)):  # pragma: no branch
            total += counts[i]
            if counts[i] > 0:
                last = i
        var symbols = last + 1
        var precision = Float64(self.precision)
        var sum = 0
        # Draco writes no stream of no symbols: the loop runs.
        for i in range(symbols):  # pragma: no branch
            var share = Float64(counts[i]) / Float64(total)
            var probability = Int(product(share, precision) + 0.5)
            if probability == 0 and counts[i] > 0:
                probability = 1
            self.probabilities.append(probability)
            sum += probability
        if sum != self.precision:
            # A stable sort by probability: ties keep their order.
            var keys = List[Int](capacity=symbols)
            # Draco writes no stream of no symbols: the loop runs.
            for i in range(symbols):  # pragma: no branch
                keys.append((self.probabilities[i] << 32) | i)
            sort(keys)
            var order = List[Int](capacity=symbols)
            # Draco writes no stream of no symbols: the loop runs.
            for key in keys:  # pragma: no branch
                order.append(key & MASK32)
            if sum < self.precision:
                self.probabilities[order[symbols - 1]] += self.precision - sum
            else:
                self._shrink(order, sum)
        sum = 0
        # Draco writes no stream of no symbols: the loop runs.
        for i in range(symbols):  # pragma: no branch
            self.starts.append(sum)
            sum += self.probabilities[i]
        self._write_table(out)

    def _shrink(mut self, order: List[Int], var sum: Int) raises:
        """Draco's loop that takes probability from the most likely
        symbols until the probabilities sum to the precision."""
        var error = sum - self.precision
        var symbols = len(order)
        while error > 0:
            var ratio = Float64(self.precision) / Float64(sum)
            # The probabilities overshoot only with two symbols or more: the
            # loop runs.
            for j in range(symbols - 1, 0, -1):  # pragma: no branch
                var symbol = order[j]
                var probability = self.probabilities[symbol]
                if probability <= 1:
                    draco_require(
                        j != symbols - 1,
                        "a symbol table cannot reach its precision",
                    )
                    break
                var scaled = Int(floor(product(ratio, Float64(probability))))
                # Draco's three clamps: at least one, less than the
                # probability, and no more than the excess.
                var fix = max(probability - scaled, 1)
                fix = min(min(fix, probability - 1), error)
                self.probabilities[symbol] -= fix
                sum -= fix
                error -= fix
                if sum == self.precision:
                    break

    def _write_table(self, mut out: DracoWriter):
        """Draco's `EncodeTable`: each probability in one to three bytes,
        and each run of zeros as one byte."""
        out.varint(len(self.probabilities))
        var i = 0
        while i < len(self.probabilities):
            var probability = self.probabilities[i]
            if probability == 0:
                var offset = 0
                while offset < 63:
                    if self.probabilities[i + offset + 1] > 0:
                        break
                    offset += 1
                out.u8((offset << 2) | 3)
                i += offset + 1
                continue
            var extra = 0
            if probability >= 1 << 6:
                extra = 1
                if probability >= 1 << 14:
                    extra = 2
            out.u8(((probability << 2) | extra) & 0xFF)
            for b in range(extra):
                out.u8((probability >> (8 * (b + 1) - 2)) & 0xFF)
            i += 1

    def encode(mut self, symbol: Int):
        """Code a symbol. Draco codes them from the last to the first.

        Args:
            symbol: The symbol.
        """
        var p = self.probabilities[symbol]
        while self.state >= 4 * _IO_BASE * p:
            self.coded.append(UInt8(self.state % _IO_BASE))
            self.state //= _IO_BASE
        self.state = (
            (self.state // p) * self.precision
            + self.state % p
            + self.starts[symbol]
        )

    def end(mut self, mut out: DracoWriter):
        """Write the coded bytes, with their count first.

        Args:
            out: Where to write them.
        """
        _write_state(self.coded, self.state - 4 * self.precision)
        out.varint(len(self.coded))
        out.append(self.coded)


def _bit_lengths(symbols: List[Int], components: Int) -> List[Int]:
    """Draco's `ComputeBitLengths`: the bits of the largest value of each
    group of `components` values."""
    var out = List[Int]()
    var i = 0
    while i < len(symbols):
        var largest = symbols[i]
        # A `for` loop over `range(1, components)` here crashes Mojo 1.1's
        # dead argument elimination.
        var j = 1
        while j < components:
            largest = max(largest, symbols[i + j])
            j += 1
        var msb = 0
        if largest > 0:
            msb = most_significant_bit(largest)
        out.append(msb + 1)
        i += components
    return out^


def encode_symbols(
    mut out: DracoWriter, symbols: List[Int], components: Int, level: Int
) raises:
    """Write a stream of unsigned 32-bit symbols as Draco codes it.

    Draco's `EncodeSymbols`: the tagged coding when its estimated size is
    below the raw coding's, or when a symbol is wider than 18 bits; the
    raw coding otherwise. Nothing is written for no symbols.

    Args:
        out: Where to write them.
        symbols: The symbols.
        components: The values in each group of the tagged coding.
        level: The compression level, from 0 to 10, which widens or
            narrows the raw coding's precision.

    Raises:
        Error: If the raw coding cannot code the symbols, as Draco fails.
    """
    if len(symbols) == 0:
        return
    var lengths = _bit_lengths(symbols, components)
    var total_length = 0
    # Draco writes no stream of no symbols: the loop runs.
    for length in lengths:  # pragma: no branch
        total_length += length
    var tag_estimate = shannon_bits(lengths)
    var tagged_bits = (
        tag_estimate[0]
        + rans_table_bits(tag_estimate[1], tag_estimate[1])
        + total_length * components
    )
    var largest = 0
    # Draco writes no stream of no symbols: the loop runs.
    for s in symbols:  # pragma: no branch
        largest = max(largest, s)
    var raw_estimate = shannon_bits(symbols)
    var raw_bits = raw_estimate[0] + rans_table_bits(largest, raw_estimate[1])
    var width = most_significant_bit(max(1, largest)) + 1
    var coding = DRACO_RAW_SYMBOLS
    if tagged_bits < raw_bits or width > _MAX_RAW_BITS:
        coding = DRACO_TAGGED_SYMBOLS
    encode_symbols_with(
        out, symbols, components, level, coding, lengths, raw_estimate[1]
    )


def encode_symbols_with(
    mut out: DracoWriter,
    symbols: List[Int],
    components: Int,
    level: Int,
    coding: DracoSymbolCoding,
    lengths: List[Int],
    unique: Int,
) raises:
    """Write a stream of symbols in a coding already chosen.

    Args:
        out: Where to write them.
        symbols: The symbols.
        components: The values in each group of the tagged coding.
        level: The compression level, for the raw coding.
        coding: `DRACO_TAGGED_SYMBOLS` or `DRACO_RAW_SYMBOLS`.
        lengths: The bit length of each group, for the tagged coding.
        unique: The distinct symbols, for the raw coding.

    Raises:
        Error: If the coding is not valid, or the raw coding has too many
            distinct symbols.
    """
    draco_require(coding.is_valid(), "a symbol coding is not known")
    out.u8(coding.value)
    if coding == DRACO_TAGGED_SYMBOLS:
        _encode_tagged(out, symbols, components, lengths)
        return
    _encode_raw(out, symbols, level, unique)


def _encode_tagged(
    mut out: DracoWriter,
    symbols: List[Int],
    components: Int,
    lengths: List[Int],
) raises:
    """Draco's `EncodeTaggedSymbols`: the bit lengths coded, then the raw
    bits of the values."""
    var counts = List[Int](length=_MAX_TAG_BITS, fill=0)
    # Draco writes no stream of no symbols: the loop runs.
    for length in lengths:  # pragma: no branch
        counts[length] += 1
    var tags = RAnsSymbolEncoder(5)
    tags.create(counts, out)
    var values = DracoBitWriter()
    var groups = len(lengths)
    var g = groups - 1
    while g >= 0:
        tags.encode(lengths[g])
        g -= 1
    # Draco writes no stream of no symbols: the loop runs.
    for group in range(groups):  # pragma: no branch
        for c in range(components):  # pragma: no branch
            values.put(lengths[group], symbols[group * components + c])
    tags.end(out)
    values.end(out, False)


def _encode_raw(
    mut out: DracoWriter, symbols: List[Int], level: Int, unique: Int
) raises:
    """Draco's `EncodeRawSymbols`: a precision from the count of distinct
    symbols and the compression level, then the symbols coded."""
    var symbol_bits = most_significant_bit(unique) + 1
    draco_require(
        symbol_bits <= _MAX_RAW_BITS, "there are too many distinct symbols"
    )
    if level < 4:
        symbol_bits -= 2
    elif level < 6:
        symbol_bits -= 1
    elif level > 9:
        symbol_bits += 2
    elif level > 7:
        symbol_bits += 1
    symbol_bits = min(max(1, symbol_bits), _MAX_RAW_BITS)
    out.u8(symbol_bits)
    var largest = 0
    # Draco writes no stream of no symbols: the loop runs.
    for s in symbols:  # pragma: no branch
        largest = max(largest, s)
    var counts = List[Int](length=largest + 1, fill=0)
    # Draco writes no stream of no symbols: the loop runs.
    for s in symbols:  # pragma: no branch
        counts[s] += 1
    var encoder = RAnsSymbolEncoder(symbol_bits)
    encoder.create(counts, out)
    var i = len(symbols) - 1
    while i >= 0:
        encoder.encode(symbols[i])
        i -= 1
    encoder.end(out)
