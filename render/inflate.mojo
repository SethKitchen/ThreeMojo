# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""DEFLATE decompression, RFC 1951, with no compression library.

`render.png` writes PNGs using only DEFLATE's *stored* block type, which needs
no compression at all. Reading a PNG someone else wrote is the other half of
that bargain and does not get the same shortcut: every encoder in the world
uses the compressed block types, so a decoder that only understood stored
blocks could not open a single real file.

So this is the whole format. Three block types:

    stored    raw bytes after a length, byte-aligned
    fixed     Huffman codes from a table the specification fixes
    dynamic   Huffman codes described by a third Huffman code, at the front

and, inside the two compressed types, LZ77: a symbol either is a literal byte
or says "copy `length` bytes from `distance` back in what you have already
produced". That back-reference may overlap the output's own end — a run of
identical bytes is encoded as one byte and a distance of one — so the copy has
to be byte at a time rather than a block move. Copying a slice captured up
front gives the wrong answer, and is the classic way to get this wrong.

**Bits run low to high within a byte, but Huffman codes are packed high bit
first.** Those two facts fight each other and are the other classic error. The
length and distance *extra* bits are ordinary little-endian integers; the
Huffman codes are read one bit at a time, most significant first, which is
what `Huffman.decode` walks.

Decoding is the canonical `puff` approach: keep how many codes exist of each
length, and the symbols sorted by code, then walk lengths from one upwards
comparing against the first code of each length. No table is built, so nothing
is allocated per symbol, and a malformed stream runs out of lengths rather
than reading off the end of anything.
"""

from render.checksum import adler32

# Let a stream produce whatever it likes. Only safe for one you wrote.
comptime NO_LIMIT = 0x7FFFFFFFFFFFFFF

# The end-of-block symbol. Everything below it is a literal byte.
comptime END_OF_BLOCK = 256
# The longest Huffman code DEFLATE allows.
comptime MAX_BITS = 15


def _code_length_order() -> List[Int]:
    """Return which code length each header entry describes.

    Ordered so the lengths most likely to be zero come last and can be
    omitted from the stream entirely.
    """
    return [
        16,
        17,
        18,
        0,
        8,
        7,
        9,
        6,
        10,
        5,
        11,
        4,
        12,
        3,
        13,
        2,
        14,
        1,
        15,
    ]


def _length_base() -> List[Int]:
    """Return the smallest match length each length symbol stands for."""
    return [
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        13,
        15,
        17,
        19,
        23,
        27,
        31,
        35,
        43,
        51,
        59,
        67,
        83,
        99,
        115,
        131,
        163,
        195,
        227,
        258,
    ]


def _length_extra() -> List[Int]:
    """Return how many extra bits each length symbol carries."""
    return [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        1,
        1,
        1,
        2,
        2,
        2,
        2,
        3,
        3,
        3,
        3,
        4,
        4,
        4,
        4,
        5,
        5,
        5,
        5,
        0,
    ]


def _distance_base() -> List[Int]:
    """Return the smallest distance each distance symbol stands for."""
    return [
        1,
        2,
        3,
        4,
        5,
        7,
        9,
        13,
        17,
        25,
        33,
        49,
        65,
        97,
        129,
        193,
        257,
        385,
        513,
        769,
        1025,
        1537,
        2049,
        3073,
        4097,
        6145,
        8193,
        12289,
        16385,
        24577,
    ]


def _distance_extra() -> List[Int]:
    """Return how many extra bits each distance symbol carries."""
    return [
        0,
        0,
        0,
        0,
        1,
        1,
        2,
        2,
        3,
        3,
        4,
        4,
        5,
        5,
        6,
        6,
        7,
        7,
        8,
        8,
        9,
        9,
        10,
        10,
        11,
        11,
        12,
        12,
        13,
        13,
    ]


struct BitReader(Movable):
    """A little-endian bit stream over a byte list.

    DEFLATE packs its fields from the least significant bit of each byte
    upwards, and moves to the next byte when one runs out. A Huffman code is
    the exception and is read a bit at a time by `Huffman.decode`, most
    significant bit of the *code* first, which is why `read_bit` is public
    rather than only `read_bits`.
    """

    var bytes: List[UInt8]
    var position: Int
    var bit: Int

    def __init__(out self, bytes: List[UInt8], start: Int):
        """Start reading at byte `start`."""
        self.bytes = bytes.copy()
        self.position = start
        self.bit = 0

    def read_bit(mut self) raises -> Int:
        """Return the next bit, advancing.

        Raises:
            Error: If the stream has run out, which means it was truncated.
        """
        if self.position >= len(self.bytes):
            raise Error("Compressed stream ended in the middle of a code")
        var value = Int((self.bytes[self.position] >> UInt8(self.bit)) & 1)
        self.bit += 1
        if self.bit == 8:
            self.bit = 0
            self.position += 1
        return value

    def read_bits(mut self, count: Int) raises -> Int:
        """Return the next `count` bits as an integer, least significant first.

        Args:
            count: How many bits to take. Zero is allowed and reads nothing,
                which is what a symbol with no extra bits wants.

        Returns:
            The value.

        Raises:
            Error: If the stream runs out.
        """
        var value = 0
        for index in range(count):
            value |= self.read_bit() << index
        return value

    def align(mut self):
        """Skip to the next byte boundary, as a stored block's header needs."""
        if self.bit != 0:
            self.bit = 0
            self.position += 1


struct Huffman(Movable):
    """A canonical Huffman code, held as counts per length and sorted symbols.

    Built from nothing but a code length per symbol, because that is all
    DEFLATE ever transmits: the codes themselves are implied by the rule that
    shorter codes come first and, within a length, symbols ascend.
    """

    # How many codes are this many bits long. Index 0 is unused.
    var counts: List[Int]
    # Every symbol that has a code, ordered by the code it was given.
    var symbols: List[Int]

    def __init__(out self, lengths: List[Int]) raises:
        """Build the code described by one length per symbol.

        Args:
            lengths: Bit length per symbol; zero means the symbol is absent.

        Raises:
            Error: If the lengths describe an over-subscribed code — one that
                claims more codes of some length than that length has room
                for, which no valid stream contains.
        """
        self.counts = List[Int](length=MAX_BITS + 1, fill=0)
        self.symbols = List[Int]()
        for symbol in range(len(lengths)):  # pragma: no branch
            self.counts[lengths[symbol]] += 1
        # Absent symbols are not a code length.
        self.counts[0] = 0

        # A code of length n has room for twice what length n-1 left over.
        var left = 1
        for length in range(1, MAX_BITS + 1):  # pragma: no branch
            left <<= 1
            left -= self.counts[length]
            if left < 0:
                raise Error("Over-subscribed Huffman code")

        var offsets = List[Int](length=MAX_BITS + 2, fill=0)
        for length in range(1, MAX_BITS + 1):  # pragma: no branch
            offsets[length + 1] = offsets[length] + self.counts[length]
        self.symbols = List[Int](length=offsets[MAX_BITS + 1], fill=0)
        for symbol in range(len(lengths)):  # pragma: no branch
            if lengths[symbol] != 0:
                self.symbols[offsets[lengths[symbol]]] = symbol
                offsets[lengths[symbol]] += 1

    def decode(self, mut reader: BitReader) raises -> Int:
        """Return the next symbol, reading one bit at a time.

        Walks lengths upwards holding the code built so far and the first code
        of the current length. If the code is within that length's run, the
        symbol is at the matching offset. No lookup table is built, so a
        malformed stream simply exhausts the lengths.

        Args:
            reader: The bit stream, positioned at a code.

        Returns:
            The symbol.

        Raises:
            Error: If no code of any length matches, which means the stream is
                corrupt.
        """
        var code = 0
        var first = 0
        var index = 0
        for length in range(1, MAX_BITS + 1):  # pragma: no branch
            code |= reader.read_bit()
            var count = self.counts[length]
            if code - first < count:
                return self.symbols[index + code - first]
            index += count
            first = (first + count) << 1
            code <<= 1
        raise Error("No Huffman code matches the bits read")


def _fixed_literals() -> List[Int]:
    """Return the literal code lengths the specification fixes."""
    var lengths = List[Int](length=288, fill=8)
    for symbol in range(144, 256):  # pragma: no branch
        lengths[symbol] = 9
    for symbol in range(256, 280):  # pragma: no branch
        lengths[symbol] = 7
    return lengths^


def _read_dynamic_lengths(mut reader: BitReader) raises -> List[List[Int]]:
    """Return the literal and distance code lengths a dynamic block declares.

    The lengths are themselves Huffman coded, by a third code whose own
    lengths are three bits each in a fixed order. The two sets are
    transmitted as one run, so a repeat can straddle the boundary between
    them, which is why they are split only at the end.

    Args:
        reader: The bit stream, positioned after the block header.

    Returns:
        Two lists: literal lengths, then distance lengths.

    Raises:
        Error: If a repeat has nothing to repeat or runs past the end.
    """
    var literal_count = reader.read_bits(5) + 257
    var distance_count = reader.read_bits(5) + 1
    var code_count = reader.read_bits(4) + 4

    var order = _code_length_order()
    var code_lengths = List[Int](length=len(order), fill=0)
    for index in range(code_count):  # pragma: no branch
        code_lengths[order[index]] = reader.read_bits(3)
    var code = Huffman(code_lengths)

    var lengths = List[Int]()
    var wanted = literal_count + distance_count
    while len(lengths) < wanted:
        var symbol = code.decode(reader)
        if symbol < 16:
            lengths.append(symbol)
        elif symbol == 16:
            # Repeat the previous length three to six times.
            if len(lengths) == 0:
                raise Error("A length repeat has nothing to repeat")
            var previous = lengths[len(lengths) - 1]
            for _ in range(reader.read_bits(2) + 3):  # pragma: no branch
                lengths.append(previous)
        elif symbol == 17:
            for _ in range(reader.read_bits(3) + 3):  # pragma: no branch
                lengths.append(0)
        else:
            # Symbol 18, the only one left: the alphabet has exactly nineteen
            # symbols, so there is no value here that is not one of the four
            # cases above, and a guard for one would be a branch no stream
            # could ever take.
            for _ in range(reader.read_bits(7) + 11):  # pragma: no branch
                lengths.append(0)
    if len(lengths) > wanted:
        raise Error("A length repeat ran past the end of the table")

    var literals = List[Int]()
    for index in range(literal_count):  # pragma: no branch
        literals.append(lengths[index])
    var distances = List[Int]()
    for index in range(literal_count, wanted):  # pragma: no branch
        distances.append(lengths[index])
    var both = List[List[Int]]()
    both.append(literals^)
    both.append(distances^)
    return both^


def _room_for(produced: Int, more: Int, limit: Int) raises:
    """Raise if producing `more` bytes would take the output past `limit`.

    Checked *before* the bytes are produced, not after. A decompressor that
    expands everything and then compares the length has already done the work
    and already holds the memory: a stream declaring a one-pixel image can
    expand to any size at all, and the mismatch is only discovered once it
    has. A few bytes of arithmetic per block is the whole cost of not being
    at the mercy of the file.

    Args:
        produced: How many bytes have been produced so far.
        more: How many bytes are about to be added.
        limit: The most this stream is allowed to produce.

    Raises:
        Error: If the total would exceed the limit.
    """
    if produced + more > limit:
        raise Error("A compressed stream expands to more than was expected")


def _inflate_block(
    mut reader: BitReader,
    mut out: List[UInt8],
    literals: Huffman,
    distances: Huffman,
    limit: Int,
) raises:
    """Expand one Huffman-coded block into `out`.

    Args:
        reader: The bit stream, positioned at the first symbol.
        out: What has been produced so far; appended to.
        literals: The literal and length code.
        distances: The distance code.
        limit: The most the whole stream may produce.

    Raises:
        Error: If a symbol is unknown, or a back-reference points further back
            than anything produced.
    """
    var length_base = _length_base()
    var length_extra = _length_extra()
    var distance_base = _distance_base()
    var distance_extra = _distance_extra()

    while True:
        var symbol = literals.decode(reader)
        if symbol < END_OF_BLOCK:
            _room_for(len(out), 1, limit)
            out.append(UInt8(symbol))
        elif symbol == END_OF_BLOCK:
            return
        else:
            var index = symbol - END_OF_BLOCK - 1
            if index >= len(length_base):
                raise Error("Unknown length symbol")
            var length = length_base[index] + reader.read_bits(
                length_extra[index]
            )
            var code = distances.decode(reader)
            if code >= len(distance_base):
                raise Error("Unknown distance symbol")
            var distance = distance_base[code] + reader.read_bits(
                distance_extra[code]
            )
            if distance > len(out):
                raise Error("A back-reference points before the start")
            _room_for(len(out), length, limit)
            # One byte at a time, deliberately: the source may overlap the
            # destination, which is how a run of identical bytes is stored.
            var from_index = len(out) - distance
            for step in range(length):  # pragma: no branch
                out.append(out[from_index + step])


def inflate(
    bytes: List[UInt8], start: Int = 0, limit: Int = NO_LIMIT
) raises -> List[UInt8]:
    """Return the bytes a DEFLATE stream expands to.

    Args:
        bytes: The buffer holding the stream.
        start: Where the stream begins in it.
        limit: The most it may produce. `NO_LIMIT` to let it produce whatever
            it likes, which is only safe for a stream you wrote yourself.

    Returns:
        The decompressed bytes.

    Raises:
        Error: If the stream is truncated, uses the reserved block type,
            expands past `limit`, or is otherwise malformed.
    """
    var reader = BitReader(bytes, start)
    return _inflate(reader, limit)


def _inflate(mut reader: BitReader, limit: Int) raises -> List[UInt8]:
    """Expand every block, leaving `reader` just past the last one.

    Separate from `inflate` because the zlib wrapper needs to know where the
    compressed data stopped: its Adler-32 sits immediately after, and a
    checker that guesses the position is not checking anything.
    """
    var out = List[UInt8]()
    while True:
        var final = reader.read_bits(1)
        var kind = reader.read_bits(2)
        if kind == 0:
            # Stored: byte aligned, a length and its complement, then raw
            # bytes. This is the only kind `render.png` itself writes.
            reader.align()
            if reader.position + 4 > len(reader.bytes):
                raise Error("A stored block's header is truncated")
            var length = Int(reader.bytes[reader.position]) | (
                Int(reader.bytes[reader.position + 1]) << 8
            )
            var complement = Int(reader.bytes[reader.position + 2]) | (
                Int(reader.bytes[reader.position + 3]) << 8
            )
            if length + complement != 0xFFFF:
                raise Error("A stored block's length is not its complement")
            reader.position += 4
            if reader.position + length > len(reader.bytes):
                raise Error("A stored block runs past the end of the stream")
            _room_for(len(out), length, limit)
            for step in range(length):  # pragma: no branch
                out.append(reader.bytes[reader.position + step])
            reader.position += length
        elif kind == 1:
            _inflate_block(
                reader,
                out,
                Huffman(_fixed_literals()),
                # Thirty-two codes, as the specification says, of which the
                # last two are unused: a stream that names one must reach the
                # guard in `_inflate_block` rather than fail as an unmatched
                # code, which says something different and less true.
                Huffman(List[Int](length=32, fill=5)),
                limit,
            )
        elif kind == 2:
            var tables = _read_dynamic_lengths(reader)
            _inflate_block(
                reader, out, Huffman(tables[0]), Huffman(tables[1]), limit
            )
        else:
            raise Error("Reserved DEFLATE block type")
        if final == 1:
            return out^


def zlib_inflate(
    bytes: List[UInt8], limit: Int = NO_LIMIT
) raises -> List[UInt8]:
    """Return the bytes a zlib stream expands to, checking it throughout.

    zlib (RFC 1950) wraps DEFLATE in a two-byte header and a trailing
    Adler-32 of the *uncompressed* data. All of it is checked here, and the
    checksum is the reason: a PNG's chunk CRC covers the compressed bytes, so
    it catches damage to the file, and says nothing about whether those bytes
    decompress to what the encoder meant. They are two layers and only one of
    them was being checked -- a stream with its Adler-32 removed, or changed,
    decoded happily.

    The window size is checked too. `CINFO` above seven asks for a window
    larger than DEFLATE defines, and a decoder that keeps the whole output, as
    this one does, would quietly ignore it rather than notice the stream is
    not the format it claims.

    Args:
        bytes: The complete zlib stream.
        limit: The most it may produce; see `inflate`.

    Returns:
        The decompressed bytes.

    Raises:
        Error: If the stream is too short, is not DEFLATE, declares an
            impossible window, has a corrupt header check, declares a preset
            dictionary -- which PNG never uses and which there would be no way
            to supply -- expands past `limit`, or ends with a missing or
            wrong Adler-32.
    """
    if len(bytes) < 2:
        raise Error("A zlib stream needs at least a header")
    var method = Int(bytes[0]) & 0x0F
    if method != 8:
        raise Error("A zlib stream must use DEFLATE")
    if (Int(bytes[0]) >> 4) > 7:
        raise Error("A zlib stream declares a window DEFLATE does not have")
    if (Int(bytes[0]) << 8 | Int(bytes[1])) % 31 != 0:
        raise Error("A zlib header failed its check")
    if (Int(bytes[1]) >> 5) & 1 == 1:
        raise Error("A zlib stream with a preset dictionary cannot be read")

    var reader = BitReader(bytes, 2)
    var out = _inflate(reader, limit)

    # The checksum sits on the next byte boundary after the last block.
    reader.align()
    if reader.position + 4 > len(bytes):
        raise Error("A zlib stream is missing its checksum")
    var stated = (
        UInt32(bytes[reader.position]) << 24
        | UInt32(bytes[reader.position + 1]) << 16
        | UInt32(bytes[reader.position + 2]) << 8
        | UInt32(bytes[reader.position + 3])
    )
    if stated != adler32(out):
        raise Error("A zlib stream's checksum does not match its data")
    return out^
