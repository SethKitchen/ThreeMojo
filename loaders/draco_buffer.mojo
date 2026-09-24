# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The bit streams of a Draco file, from Draco 1.5.6.

The decoder that three.js's `DRACOLoader` runs is Draco compiled to
WebAssembly. This module ports the parts of it that read bytes and bits:

- `core/decoder_buffer` and `core/varint_decoding.h`: `DracoBuffer`, a
  cursor over the bytes of a file, with little-endian values, LEB128
  varints and a bit reader.
- `compression/entropy/ans.h`, `rans_symbol_decoder.h` and
  `symbol_decoding.cc`: `decode_symbols`, the tagged and raw rANS symbol
  streams.
- `compression/bit_coders`: `RAnsBitDecoder`, `DirectBitDecoder` and
  `FoldedBitDecoder`.

Draco is Copyright 2016 The Draco Authors, under the Apache License 2.0.
See THIRD-PARTY-NOTICES.md.

**Integers.** Draco does this arithmetic in 32-bit unsigned integers. The
port keeps it in `Int` and masks a result to 32 bits where the C++ can
wrap.

**What is refused.** Draco returns `false` from each of these readers
when the bytes do not suffice or do not make sense. Each reader here
raises an `Error` in the same places.
"""

from std.memory import bitcast

# The low 32 bits of an `Int`.
comptime MASK32 = 0xFFFFFFFF

# The lower bound of the state of the binary rANS coder.
comptime _L_BASE = 4096
# The bytes the rANS coders read and write at a time.
comptime _IO_BASE = 256


def draco_require(ok: Bool, what: String) raises:
    """Raise unless a condition holds.

    Draco checks its input in many places and fails the decoding in each.
    This helper is the one place that raises for them.

    Args:
        ok: The condition.
        what: What is wrong when it does not hold.

    Raises:
        Error: `Draco: <what>` when `ok` is False.
    """
    if not ok:
        raise Error("Draco: " + what)


def draco_version(major: Int, minor: Int) -> Int:
    """Return a bitstream version as Draco packs it.

    Args:
        major: The major version.
        minor: The minor version.

    Returns:
        `major * 256 + minor`, so versions compare as numbers.
    """
    return major * 256 + minor


def to_int32(value: Int) -> Int:
    """Return the low 32 bits of a value read as a signed 32-bit integer.

    Args:
        value: Any integer.

    Returns:
        The value that a C++ `int32_t` holds after a cast from `value`.
    """
    var low = value & MASK32
    if low >= 0x80000000:
        return low - 0x100000000
    return low


def symbol_to_signed(symbol: Int) -> Int:
    """Return the signed integer that a zigzag symbol stands for.

    Draco's `ConvertSymbolToSignedInt`: an even symbol is `symbol / 2`,
    an odd one is `-(symbol + 1) / 2`.

    Args:
        symbol: An unsigned 32-bit symbol.

    Returns:
        The signed value.
    """
    if symbol & 1 == 0:
        return symbol >> 1
    return -(symbol >> 1) - 1


def most_significant_bit(value: Int) -> Int:
    """Return the index of the highest set bit of a positive value.

    Args:
        value: A value of one or more.

    Returns:
        `floor(log2(value))`.
    """
    var bit = 0
    var rest = value >> 1
    while rest > 0:
        bit += 1
        rest >>= 1
    return bit


def truncated_divide(a: Int, b: Int) -> Int:
    """Divide two integers and round toward zero, as C++ does.

    Mojo's `//` rounds toward negative infinity. Draco's divisions of
    signed values round toward zero.

    Args:
        a: The dividend.
        b: The divisor, not zero.

    Returns:
        The quotient rounded toward zero.
    """
    var q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        return -q
    return q


struct DracoBuffer(Copyable, Movable):
    """A cursor over the bytes of a Draco file.

    Draco's `DecoderBuffer`. It reads little-endian values and varints,
    and it has a bit mode that reads bits from the least significant bit
    of each byte up. The bit mode starts at the cursor and reads to the
    end of the file. When it ends, the cursor moves past every byte it
    touched.
    """

    var data: List[UInt8]
    """The bytes of the file."""
    var pos: Int
    """The next byte to read."""
    var version: Int
    """The bitstream version, as `draco_version` packs it."""
    var bit_start: Int
    """The byte the bit mode started at."""
    var bit_offset: Int
    """The bits the bit mode has read."""

    def __init__(out self, var data: List[UInt8]):
        """Start a cursor at the first byte of a file.

        Args:
            data: The bytes of the file.
        """
        self.data = data^
        self.pos = 0
        self.version = 0
        self.bit_start = 0
        self.bit_offset = 0

    def remaining(self) -> Int:
        """Return the bytes from the cursor to the end.

        Returns:
            The count of bytes left.
        """
        return len(self.data) - self.pos

    def need(self, count: Int) raises:
        """Raise unless the file has `count` bytes more.

        Args:
            count: The bytes a read needs.

        Raises:
            Error: If fewer bytes are left.
        """
        draco_require(
            count >= 0 and count <= self.remaining(), "the file ends early"
        )

    def advance(mut self, count: Int) raises:
        """Move the cursor past bytes.

        Args:
            count: The bytes to skip.

        Raises:
            Error: If fewer bytes are left.
        """
        self.need(count)
        self.pos += count

    def read_unsigned(mut self, size: Int) raises -> Int:
        """Read a little-endian unsigned integer.

        Args:
            size: Its bytes, from one to eight.

        Returns:
            The value.

        Raises:
            Error: If fewer bytes are left.
        """
        self.need(size)
        var value = 0
        for k in range(size):
            value |= Int(self.data[self.pos + k]) << (8 * k)
        self.pos += size
        return value

    def u8(mut self) raises -> Int:
        """Read an unsigned byte.

        Returns:
            The value.

        Raises:
            Error: If the file ends.
        """
        return self.read_unsigned(1)

    def i8(mut self) raises -> Int:
        """Read a signed byte.

        Returns:
            The value, from -128 to 127.

        Raises:
            Error: If the file ends.
        """
        var value = self.read_unsigned(1)
        if value >= 128:
            return value - 256
        return value

    def u16(mut self) raises -> Int:
        """Read an unsigned 16-bit integer.

        Returns:
            The value.

        Raises:
            Error: If the file ends.
        """
        return self.read_unsigned(2)

    def u32(mut self) raises -> Int:
        """Read an unsigned 32-bit integer.

        Returns:
            The value.

        Raises:
            Error: If the file ends.
        """
        return self.read_unsigned(4)

    def i32(mut self) raises -> Int:
        """Read a signed 32-bit integer.

        Returns:
            The value.

        Raises:
            Error: If the file ends.
        """
        return to_int32(self.read_unsigned(4))

    def f32(mut self) raises -> Float32:
        """Read a 32-bit float.

        Returns:
            The value.

        Raises:
            Error: If the file ends.
        """
        return bitcast[DType.float32](UInt32(self.read_unsigned(4)))

    def bytes(mut self, count: Int) raises -> List[UInt8]:
        """Read bytes.

        Args:
            count: The bytes to read.

        Returns:
            A copy of them.

        Raises:
            Error: If fewer bytes are left.
        """
        self.need(count)
        var out = List[UInt8](capacity=count)
        for k in range(count):
            out.append(self.data[self.pos + k])
        self.pos += count
        return out^

    def varint(mut self, max_bytes: Int) raises -> Int:
        """Read an unsigned LEB128 varint.

        Draco's `DecodeVarint`: seven bits a byte, least significant
        first, with the high bit set on every byte but the last.

        Args:
            max_bytes: The most bytes the value can take: five for a
                32-bit value, ten for a 64-bit one.

        Returns:
            The value, with the bits past the type's width dropped.

        Raises:
            Error: If the file ends or the value takes more bytes.
        """
        var value = 0
        var shift = 0
        for _ in range(max_bytes):  # pragma: no branch
            var byte = self.u8()
            # The tenth byte, the last, shifts by 63: the bits past the
            # 64th fall off, as they do from Draco's `uint64_t`.
            value |= (byte & 0x7F) << shift
            shift += 7
            if byte < 0x80:
                if max_bytes == 5:
                    return value & MASK32
                return value
        raise Error("Draco: a varint is too long")

    def varint32(mut self) raises -> Int:
        """Read an unsigned 32-bit varint.

        Returns:
            The value.

        Raises:
            Error: If the file ends or the varint is too long.
        """
        return self.varint(5)

    def varint64(mut self) raises -> Int:
        """Read an unsigned 64-bit varint.

        Returns:
            The value.

        Raises:
            Error: If the file ends or the varint is too long.
        """
        return self.varint(10)

    def signed_varint32(mut self) raises -> Int:
        """Read a signed 32-bit varint, stored as a zigzag symbol.

        Returns:
            The value.

        Raises:
            Error: If the file ends or the varint is too long.
        """
        return symbol_to_signed(self.varint(5))

    def start_bits(mut self, decode_size: Bool) raises -> Int:
        """Start the bit mode at the cursor.

        Args:
            decode_size: True to read a 64-bit varint first, the size in
                bytes of what follows.

        Returns:
            The size read, or zero.

        Raises:
            Error: If the size cannot be read.
        """
        var size = 0
        if decode_size:
            size = self.varint64()
        self.bit_start = self.pos
        self.bit_offset = 0
        return size

    def bits(mut self, count: Int) raises -> Int:
        """Read bits in the bit mode, least significant first.

        A bit past the end of the file reads as zero, as Draco reads it.

        Args:
            count: The bits to read, from zero to 32.

        Returns:
            The value.

        Raises:
            Error: If `count` is above 32.
        """
        draco_require(count <= 32, "a bit field is wider than 32 bits")
        var value = 0
        for bit in range(count):
            var at = self.bit_offset
            var byte = self.bit_start + (at >> 3)
            if byte < len(self.data):
                value |= ((Int(self.data[byte]) >> (at & 7)) & 1) << bit
                self.bit_offset = at + 1
        return value

    def end_bits(mut self):
        """End the bit mode, and move the cursor past the bytes it read."""
        self.pos = self.bit_start + (self.bit_offset + 7) // 8


struct RAnsSymbolDecoder(Copyable, Movable):
    """A stream of symbols coded with rANS.

    Draco's `RAnsSymbolDecoder` and `RAnsDecoder`: a table of symbol
    probabilities, then the coded bytes, which are read from the end.
    """

    var precision: Int
    """The sum of the probabilities, a power of two."""
    var probabilities: List[Int]
    """The probability of each symbol."""
    var starts: List[Int]
    """The sum of the probabilities before each symbol."""
    var coded: List[UInt8]
    """The coded bytes."""
    var offset: Int
    """The coded bytes not read yet."""
    var state: Int
    """The state of the decoder."""

    def __init__(out self, symbol_bits: Int):
        """Make a decoder for symbols of up to `symbol_bits` bits.

        Args:
            symbol_bits: The bits of the widest symbol. The precision is
                2 to the power `3 * symbol_bits / 2`, kept from 12 to 20.
        """
        var bits = min(max((3 * symbol_bits) // 2, 12), 20)
        self.precision = 1 << bits
        self.probabilities = List[Int]()
        self.starts = List[Int]()
        self.coded = List[UInt8]()
        self.offset = 0
        self.state = 0

    def create(mut self, mut buffer: DracoBuffer) raises:
        """Read the table of probabilities.

        Each probability is one byte whose low two bits give the extra
        bytes that follow it. Three in those bits starts a run of zero
        probabilities instead.

        Args:
            buffer: The cursor, at the table.

        Raises:
            Error: If the table ends early, or its probabilities do not
                sum to the precision.
        """
        var count = buffer.varint32()
        draco_require(
            count // 64 <= buffer.remaining(), "a symbol table is too long"
        )
        self.probabilities = List[Int](length=count, fill=0)
        var i = 0
        while i < count:
            var data = buffer.u8()
            var token = data & 3
            if token == 3:
                var run = data >> 2
                draco_require(i + run < count, "a run of zeros is too long")
                i += run + 1
                continue
            var probability = data >> 2
            for b in range(token):
                probability |= buffer.u8() << (8 * (b + 1) - 2)
            self.probabilities[i] = probability
            i += 1
        self.starts = List[Int](capacity=count)
        var sum = 0
        for probability in self.probabilities:
            self.starts.append(sum)
            sum += probability
            draco_require(
                sum <= self.precision, "the probabilities are too large"
            )
        draco_require(
            count == 0 or sum == self.precision,
            "the probabilities do not sum to the precision",
        )

    def start(mut self, mut buffer: DracoBuffer) raises:
        """Read the coded bytes and start the decoder.

        Args:
            buffer: The cursor, at the size of the coded bytes.

        Raises:
            Error: If the bytes end early or their last bytes do not start
                a state.
        """
        var size = buffer.varint64()
        self.coded = buffer.bytes(size)
        draco_require(size >= 1, "a rANS stream is empty")
        var last = Int(self.coded[size - 1])
        var kind = last >> 6
        var l_base = self.precision * 4
        draco_require(size > kind, "a rANS stream is too short")
        self.offset = size - 1 - kind
        var state = 0
        for k in range(kind + 1):  # pragma: no branch
            state |= Int(self.coded[self.offset + k]) << (8 * k)
        var masks: List[Int] = [0x3F, 0x3FFF, 0x3FFFFF, 0x3FFFFFFF]
        self.state = (state & masks[kind]) + l_base
        draco_require(
            self.state < l_base * _IO_BASE, "a rANS state is too large"
        )

    def count(self) -> Int:
        """Return the symbols the table holds.

        Returns:
            The count.
        """
        return len(self.probabilities)

    def read(mut self) -> Int:
        """Read the next symbol.

        Returns:
            The symbol.
        """
        var l_base = self.precision * 4
        while self.state < l_base and self.offset > 0:
            self.offset -= 1
            self.state = self.state * _IO_BASE + Int(self.coded[self.offset])
        var quotient = self.state // self.precision
        var rest = self.state % self.precision
        var symbol = self._find(rest)
        self.state = (
            quotient * self.probabilities[symbol] + rest - self.starts[symbol]
        )
        return symbol

    def _find(self, rest: Int) -> Int:
        """Return the last symbol whose start is at or below `rest`."""
        var low = 0
        var high = len(self.starts) - 1
        while low < high:
            var middle = (low + high + 1) // 2
            if self.starts[middle] <= rest:
                low = middle
            else:
                high = middle - 1
        return low


def decode_symbols(
    mut buffer: DracoBuffer, count: Int, components: Int
) raises -> List[Int]:
    """Read a stream of unsigned symbols.

    Draco's `DecodeSymbols`. A scheme byte picks one of two codings:

    - Tagged (0): an rANS stream of bit lengths, one for each group of
      `components` values, then each value as that many raw bits.
    - Raw (1): the bits of the widest symbol, from 1 to 18, then an rANS
      stream of the values themselves.

    Args:
        buffer: The cursor, at the scheme byte.
        count: The values to read.
        components: The values in each tagged group.

    Returns:
        The values.

    Raises:
        Error: If the scheme is not known, or the streams are not valid.
    """
    var out = List[Int](capacity=count)
    if count == 0:
        return out^
    var scheme = buffer.u8()
    if scheme == 0:
        var tags = RAnsSymbolDecoder(5)
        tags.create(buffer)
        tags.start(buffer)
        draco_require(tags.count() > 0, "a tag table is empty")
        _ = buffer.start_bits(False)
        var i = 0
        while i < count:
            var length = tags.read()
            for _ in range(components):  # pragma: no branch
                out.append(buffer.bits(length))
            i += components
        buffer.end_bits()
        return out^
    draco_require(scheme == 1, "a symbol coding is not known")
    var bits = buffer.u8()
    draco_require(
        bits >= 1 and bits <= 18, "a symbol width is not from 1 to 18"
    )
    var values = RAnsSymbolDecoder(bits)
    values.create(buffer)
    draco_require(values.count() > 0, "a symbol table is empty")
    values.start(buffer)
    for _ in range(count):  # pragma: no branch
        out.append(values.read())
    return out^


struct RAnsBitDecoder(Copyable, Movable):
    """A stream of bits coded with binary rANS.

    Draco's `RAnsBitDecoder`: a byte, the probability of a zero in 256ths,
    then the coded bytes, which are read from the end.
    """

    var zero: Int
    """The probability of a zero, in 256ths."""
    var coded: List[UInt8]
    """The coded bytes."""
    var offset: Int
    """The coded bytes not read yet."""
    var state: Int
    """The state of the decoder."""

    def __init__(out self):
        """Make a decoder that reads zeros until it starts."""
        self.zero = 0
        self.coded = List[UInt8]()
        self.offset = 0
        self.state = 0

    def start(mut self, mut buffer: DracoBuffer) raises:
        """Read the probability and the coded bytes.

        Args:
            buffer: The cursor, at the probability byte.

        Raises:
            Error: If the bytes end early or do not start a state.
        """
        self.zero = buffer.u8()
        var size = buffer.varint32()
        self.coded = buffer.bytes(size)
        draco_require(size >= 1, "a bit stream is empty")
        var last = Int(self.coded[size - 1])
        var kind = last >> 6
        draco_require(kind < 3 and size > kind, "a bit stream is too short")
        self.offset = size - 1 - kind
        var state = 0
        for k in range(kind + 1):  # pragma: no branch
            state |= Int(self.coded[self.offset + k]) << (8 * k)
        var masks: List[Int] = [0x3F, 0x3FFF, 0x3FFFFF]
        self.state = (state & masks[kind]) + _L_BASE
        draco_require(
            self.state < _L_BASE * _IO_BASE, "a bit stream state is too large"
        )

    def bit(mut self) -> Bool:
        """Read the next bit.

        Draco's `rabs_desc_read`. The probability of a one is kept in a
        byte, so a zero probability of a zero reads zeros only, as it does
        in Draco.

        Returns:
            The bit.
        """
        var one = (256 - self.zero) & 0xFF
        if self.state < _L_BASE and self.offset > 0:
            self.offset -= 1
            self.state = self.state * _IO_BASE + Int(self.coded[self.offset])
        var x = self.state
        var quotient = x >> 8
        var rest = x & 0xFF
        var xn = quotient * one
        if rest < one:
            self.state = xn + rest
            return True
        self.state = x - xn - one
        return False

    def bits(mut self, count: Int) -> Int:
        """Read bits, most significant first.

        Args:
            count: The bits to read.

        Returns:
            The value.
        """
        var value = 0
        for _ in range(count):
            value = (value << 1) + Int(self.bit())
        return value


struct DirectBitDecoder(Copyable, Movable):
    """A stream of raw bits in 32-bit words, most significant bit first.

    Draco's `DirectBitDecoder`.
    """

    var words: List[Int]
    """The words."""
    var index: Int
    """The word being read."""
    var used: Int
    """The bits of that word already read."""

    def __init__(out self):
        """Make a decoder that holds no bits."""
        self.words = List[Int]()
        self.index = 0
        self.used = 0

    def start(mut self, mut buffer: DracoBuffer) raises:
        """Read the words.

        Args:
            buffer: The cursor, at the 32-bit size in bytes.

        Raises:
            Error: If the size is zero, not a multiple of four, or larger
                than what is left.
        """
        var size = buffer.u32()
        draco_require(
            size != 0 and size & 3 == 0, "a bit block size is not valid"
        )
        buffer.need(size)
        self.words = List[Int](capacity=size // 4)
        for _ in range(size // 4):  # pragma: no branch
            self.words.append(buffer.u32())
        self.index = 0
        self.used = 0

    def bit(mut self) -> Bool:
        """Read the next bit.

        Returns:
            The bit, or False when the words are all read.
        """
        if self.index >= len(self.words):
            return False
        var value = (self.words[self.index] >> (31 - self.used)) & 1
        self.used += 1
        if self.used == 32:
            self.index += 1
            self.used = 0
        return value == 1

    def bits(mut self, count: Int) raises -> Int:
        """Read bits, most significant first.

        Args:
            count: The bits to read, from 1 to 32.

        Returns:
            The value.

        Raises:
            Error: If the words run out.
        """
        var left = 32 - self.used
        if count <= left:
            draco_require(self.index < len(self.words), "the bits run out")
            var value = ((self.words[self.index] << self.used) & MASK32) >> (
                32 - count
            )
            self.used += count
            if self.used == 32:
                self.index += 1
                self.used = 0
            return value
        draco_require(self.index + 1 < len(self.words), "the bits run out")
        var high = (self.words[self.index] << self.used) & MASK32
        self.used = count - left
        self.index += 1
        var low = self.words[self.index] >> (32 - self.used)
        return (high >> (32 - count)) | low


struct FoldedBitDecoder(Copyable, Movable):
    """Numbers coded one bit position to a stream.

    Draco's `FoldedBit32Decoder<RAnsBitDecoder>`: 32 binary rANS streams,
    one for each bit of a number from the most significant down, then one
    more stream.
    """

    var folds: List[RAnsBitDecoder]
    """The stream of each bit position."""
    var last: RAnsBitDecoder
    """The stream after them, which a folded number does not read."""

    def __init__(out self):
        """Make a decoder that reads zeros until it starts."""
        self.folds = List[RAnsBitDecoder]()
        self.last = RAnsBitDecoder()

    def start(mut self, mut buffer: DracoBuffer) raises:
        """Read the 33 streams.

        Args:
            buffer: The cursor, at the first stream.

        Raises:
            Error: If a stream is not valid.
        """
        self.folds = List[RAnsBitDecoder](capacity=32)
        for _ in range(32):  # pragma: no branch
            var fold = RAnsBitDecoder()
            fold.start(buffer)
            self.folds.append(fold^)
        self.last.start(buffer)

    def bits(mut self, count: Int) -> Int:
        """Read a number, one bit from each stream.

        Args:
            count: The bits of the number.

        Returns:
            The value.
        """
        var value = 0
        for i in range(count):
            value = (value << 1) + Int(self.folds[i].bit())
        return value
