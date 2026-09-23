# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Zstandard decompression, RFC 8878, with no compression library.

A KTX 2.0 file can store each level as a Zstandard frame, and
`render.ktx2` reads it through `zstd_decompress`. The decoder is the
whole format except dictionaries.

**A stream is frames.** A Zstandard frame starts with the magic number
`0xFD2FB528`, then a header that can give the content size and asks for a
checksum. Blocks follow. A skippable frame, magic `0x184D2A5?`, is skipped.
The frames' contents are joined.

**A block is raw, RLE or compressed.** A raw block is its bytes. An RLE
block is one byte repeated. A compressed block has a literals section and
a sequences section:

    literals    raw, one byte repeated, or Huffman-coded in one or four
                streams, with a new table or the previous block's
    sequences   (literal length, match offset, match length) triples,
                each coded with a finite state entropy (FSE) table that is
                predefined, one symbol, described in the block, or the
                previous block's

A sequence copies its literals, then copies the match from `offset` bytes
back. A match can overlap its own output, so the copy runs byte by byte.
The three most recent offsets are kept, and an offset code of one to
three repeats one of them.

**Two bit orders.** An FSE table description reads forward, low bit first.
A Huffman stream and the sequences stream read backward from their last
byte, whose highest set bit marks where the data starts. The backward
reader gives zeros below the start of its stream, and each stream checks
where it ends, so a short stream fails that check rather than reading
outside its bytes.

**Dictionaries are refused.** A frame that names a dictionary cannot be
decoded without that dictionary. A KTX 2.0 file never names one.
"""

# A decoder that knows the size it expects passes it as the limit.
comptime NO_LIMIT = 0x7FFFFFFFFFFFFFF
# The magic numbers of a frame and of a skippable frame.
comptime FRAME_MAGIC = 0xFD2FB528
comptime SKIPPABLE_MAGIC = 0x184D2A50
# The largest block, compressed or decompressed.
comptime MAX_BLOCK = 128 * 1024
# The largest accuracy of each FSE table, and of the Huffman weights' table.
comptime LITERAL_LENGTH_LOG = 9
comptime MATCH_LENGTH_LOG = 9
comptime OFFSET_LOG = 8
comptime WEIGHT_LOG = 6
# The largest symbol of each code.
comptime LITERAL_LENGTH_SYMBOLS = 35
comptime MATCH_LENGTH_SYMBOLS = 52
comptime OFFSET_SYMBOLS = 31
comptime WEIGHT_SYMBOLS = 11
# The longest Huffman code.
comptime MAX_HUFFMAN_BITS = 11


def _highbit(value: Int) -> Int:
    """Return the position of the highest set bit, or -1 for zero."""
    var bit = -1
    var rest = value
    while rest > 0:
        rest >>= 1
        bit += 1
    return bit


def _outside(at: Int, count: Int, end: Int) -> Bool:
    """Return True if `count` bytes from `at` run past `end`."""
    return count < 0 or at + count > end


def _need(at: Int, count: Int, end: Int) raises:
    """Raise if `count` bytes from `at` run past `end`."""
    if _outside(at, count, end):
        raise Error("zstd: the stream is cut short")


def _room(produced: Int, more: Int, limit: Int) raises:
    """Raise if `more` bytes would take the output past `limit`."""
    if more > limit - produced:
        raise Error("zstd: the stream expands to more than was expected")


def _le(bytes: List[UInt8], at: Int, count: Int) -> Int:
    """Return the little-endian number of `count` bytes at `at`."""
    var value = 0
    for index in range(count):
        value |= Int(bytes[at + index]) << (index * 8)
    return value


def _byte_or_zero(data: List[UInt8], at: Int) -> Int:
    """Return the byte at `at`, or zero past the end."""
    return Int(data[at]) if at < len(data) else 0


struct _Forward(Movable):
    """A little-endian bit reader, low bit first, that gives zeros past the
    end of its bytes."""

    var data: List[UInt8]
    var pos: Int

    def __init__(out self, var data: List[UInt8]):
        self.data = data^
        self.pos = 0

    def peek(self, count: Int) -> Int:
        """Return the next `count` bits without taking them."""
        var byte = self.pos >> 3
        var skip = self.pos & 7
        var acc = 0
        var got = 0
        while got < count + skip:
            acc |= _byte_or_zero(self.data, byte) << got
            got += 8
            byte += 1
        return (acc >> skip) & ((1 << count) - 1)

    def read(mut self, count: Int) -> Int:
        """Return the next `count` bits and take them."""
        var value = self.peek(count)
        self.pos += count
        return value

    def bytes_used(self) -> Int:
        """Return how many whole bytes the bits taken so far span."""
        return (self.pos + 7) >> 3


struct _Backward(Movable):
    """A bit reader that starts at the last byte's marker bit and runs
    toward the first byte, giving zeros below it."""

    var data: List[UInt8]
    var pos: Int
    """How many bits lie below the reading point. Negative once a read
    has run past the start."""

    def __init__(out self, bytes: List[UInt8], start: Int, end: Int) raises:
        if end <= start or bytes[end - 1] == 0:
            raise Error(
                "zstd: a bitstream is empty or does not end with its marker bit"
            )
        self.data = List[UInt8](bytes[start:end])
        self.pos = (end - start - 1) * 8 + _highbit(Int(bytes[end - 1]))

    def peek(self, count: Int) -> Int:
        """Return the `count` bits below the reading point, zeros below the
        start."""
        var top = max(self.pos, 0)
        var low = max(self.pos - count, 0)
        var shift = low - (self.pos - count)
        var byte = low >> 3
        var skip = low & 7
        var acc = 0
        var got = 0
        while got < top - low + skip:
            acc |= Int(self.data[byte]) << got
            got += 8
            byte += 1
        return ((acc >> skip) & ((1 << (top - low)) - 1)) << shift

    def read(mut self, count: Int) -> Int:
        """Return the `count` bits below the reading point and take them."""
        var value = self.peek(count)
        self.pos -= count
        return value


struct _Fse(Copyable, Movable):
    """A finite state entropy decoding table: for each state, the symbol,
    how many bits to read next and the state those bits add to."""

    var log: Int
    var symbols: List[Int]
    var bits: List[Int]
    var base: List[Int]

    def __init__(out self, counts: List[Int], log: Int):
        """Build the table from normalized counts, `-1` for a symbol that is
        less likely than one in the table's size."""
        var size = 1 << log
        self.log = log
        self.symbols = List[Int](length=size, fill=0)
        self.bits = List[Int](length=size, fill=0)
        self.base = List[Int](length=size, fill=0)
        var next = List[Int](length=len(counts), fill=1)
        var high = size - 1
        # Every table names a symbol: a description reads one before its
        # counts can fill the table.
        for symbol in range(len(counts)):  # pragma: no branch
            if counts[symbol] == -1:
                self.symbols[high] = symbol
                high -= 1
        var step = (size >> 1) + (size >> 3) + 3
        var pos = 0
        for symbol in range(len(counts)):  # pragma: no branch
            for _ in range(counts[symbol]):
                self.symbols[pos] = symbol
                pos = (pos + step) & (size - 1)
                while pos > high:
                    pos = (pos + step) & (size - 1)
            next[symbol] = max(counts[symbol], 1)
        for state in range(size):  # pragma: no branch
            var n = next[self.symbols[state]]
            next[self.symbols[state]] = n + 1
            self.bits[state] = log - _highbit(n)
            self.base[state] = (n << self.bits[state]) - size

    @staticmethod
    def rle(symbol: Int) -> _Fse:
        """Return the table of one symbol that reads no bits."""
        var table = _Fse([1], 0)
        table.symbols[0] = symbol
        return table^


def _literal_length_counts() -> List[Int]:
    """Return the predefined literal length distribution."""
    return [
        4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1,
        2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1,
        -1, -1, -1, -1,
    ]  # fmt: skip


def _match_length_counts() -> List[Int]:
    """Return the predefined match length distribution."""
    return [
        1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1,
        -1, -1, -1, -1, -1,
    ]  # fmt: skip


def _offset_counts() -> List[Int]:
    """Return the predefined offset distribution."""
    return [
        1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1,
    ]  # fmt: skip


def _literal_length_base() -> List[Int]:
    """Return the smallest literal length of each code."""
    return [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 0x80, 0x100, 0x200, 0x400,
        0x800, 0x1000, 0x2000, 0x4000, 0x8000, 0x10000,
    ]  # fmt: skip


def _literal_length_bits() -> List[Int]:
    """Return how many extra bits each literal length code reads."""
    return [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12,
        13, 14, 15, 16,
    ]  # fmt: skip


def _match_length_base() -> List[Int]:
    """Return the smallest match length of each code."""
    return [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
        19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34,
        35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 0x83, 0x103, 0x203,
        0x403, 0x803, 0x1003, 0x2003, 0x4003, 0x8003, 0x10003,
    ]  # fmt: skip


def _match_length_bits() -> List[Int]:
    """Return how many extra bits each match length code reads."""
    return [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11,
        12, 13, 14, 15, 16,
    ]  # fmt: skip


def _read_fse(
    bytes: List[UInt8], at: Int, end: Int, max_log: Int, max_symbol: Int
) raises -> Tuple[_Fse, Int]:
    """Read an FSE table description.

    Args:
        bytes: The block.
        at: Where the description starts.
        end: Where its section ends.
        max_log: The largest accuracy the table can have.
        max_symbol: The largest symbol it can name.

    Returns:
        The table, and where the description ends, byte aligned.

    Raises:
        Error: If the accuracy is too high, the counts do not fill the
            table, it names too many symbols, or it runs past `end`.
    """
    var reader = _Forward(List[UInt8](bytes[at:end]))
    var log = reader.read(4) + 5
    if log > max_log:
        raise Error("zstd: an FSE table's accuracy is too high")
    var remaining = 1 << log
    var counts = List[Int]()
    while remaining > 0:
        var bits = _highbit(remaining + 1) + 1
        var value = reader.peek(bits)
        var low_mask = (1 << (bits - 1)) - 1
        var threshold = (1 << bits) - 1 - (remaining + 1)
        if (value & low_mask) < threshold:
            value &= low_mask
            reader.pos += bits - 1
        else:
            reader.pos += bits
            if value > low_mask:
                value -= threshold
        var count = value - 1
        remaining -= abs(count)
        counts.append(count)
        if count == 0:
            # A zero count is followed by two-bit repeat flags: that many
            # more zeros, and three means another flag follows.
            var repeat = 3
            while repeat == 3:
                repeat = reader.read(2)
                for _ in range(repeat):
                    counts.append(0)
    if _misfit(remaining, len(counts), max_symbol):
        raise Error(
            "zstd: an FSE table's counts do not fill it, or it names too"
            " many symbols"
        )
    if reader.bytes_used() > end - at:
        raise Error("zstd: an FSE table description runs past its section")
    return (_Fse(counts, log), at + reader.bytes_used())


def _misfit(remaining: Int, symbols: Int, max_symbol: Int) -> Bool:
    """Return True if the counts overfill the table or name too many
    symbols."""
    return remaining != 0 or symbols > max_symbol + 1


struct _Huffman(Copyable, Movable):
    """A Huffman decoding table indexed by the next `max_bits` bits."""

    var max_bits: Int
    var symbols: List[UInt8]
    var bits: List[Int]

    def __init__(out self):
        self.max_bits = 0
        self.symbols = List[UInt8]()
        self.bits = List[Int]()

    def __init__(out self, weights: List[Int]) raises:
        """Build the table from every symbol's weight but the last, which
        the others imply."""
        var total = 0
        # A description gives at least one weight.
        for weight in weights:  # pragma: no branch
            if weight > 0:
                total += 1 << (weight - 1)
        self.max_bits = _highbit(total) + 1
        if self.max_bits > MAX_HUFFMAN_BITS:
            raise Error("zstd: a Huffman code is longer than eleven bits")
        var left = (1 << self.max_bits) - total
        if not _completes(total, left):
            raise Error("zstd: Huffman weights do not complete a code")
        var all = weights.copy()
        all.append(_highbit(left) + 1)
        var size = 1 << self.max_bits
        self.symbols = List[UInt8](length=size, fill=0)
        self.bits = List[Int](length=size, fill=0)
        # Codes of the most bits, the lowest weight, come first.
        var start = List[Int](length=self.max_bits + 2, fill=0)
        var position = 0
        for weight in range(1, self.max_bits + 1):  # pragma: no branch
            start[weight] = position
            for symbol in range(len(all)):  # pragma: no branch
                if all[symbol] == weight:
                    position += 1 << (weight - 1)
        for symbol in range(len(all)):  # pragma: no branch
            var weight = all[symbol]
            if weight > 0:
                var span = 1 << (weight - 1)
                for entry in range(  # pragma: no branch
                    start[weight], start[weight] + span
                ):
                    self.symbols[entry] = UInt8(symbol)
                    self.bits[entry] = self.max_bits + 1 - weight
                start[weight] += span


def _completes(total: Int, left: Int) -> Bool:
    """Return True if weights summing to `total` leave a power of two."""
    return total > 0 and (left & (left - 1)) == 0


def _huffman_weights(
    bytes: List[UInt8], at: Int, end: Int
) raises -> Tuple[List[Int], Int]:
    """Read a Huffman tree description: its weights, direct or through an
    FSE table.

    Args:
        bytes: The block.
        at: Where the description starts.
        end: Where the literals section ends.

    Returns:
        The weights of every symbol but the last, and where the
        description ends.

    Raises:
        Error: If the description runs past `end`, or its FSE table or
            stream is malformed.
    """
    _need(at, 1, end)
    var header = Int(bytes[at])
    var weights = List[Int]()
    if header >= 128:
        # Four bits a weight, high nibble first.
        var count = header - 127
        _need(at + 1, (count + 1) // 2, end)
        for index in range(count):  # pragma: no branch
            var byte = Int(bytes[at + 1 + index // 2])
            weights.append((byte >> 4) if index % 2 == 0 else (byte & 15))
        return (weights^, at + 1 + (count + 1) // 2)
    _need(at + 1, header, end)
    var stop = at + 1 + header
    var read = _read_fse(bytes, at + 1, stop, WEIGHT_LOG, WEIGHT_SYMBOLS)
    var table = read[0].copy()
    var stream = _Backward(bytes, read[1], stop)
    var first = stream.read(table.log)
    var second = stream.read(table.log)
    # Two states take turns until the stream is overread; the other
    # state's symbol is then the last weight.
    while True:
        if len(weights) > 252:
            raise Error("zstd: a Huffman tree has more than 255 weights")
        weights.append(table.symbols[first])
        first = table.base[first] + stream.read(table.bits[first])
        if stream.pos < 0:
            weights.append(table.symbols[second])
            break
        weights.append(table.symbols[second])
        second = table.base[second] + stream.read(table.bits[second])
        if stream.pos < 0:
            weights.append(table.symbols[first])
            break
    return (weights^, stop)


struct _FrameState(Movable):
    """What one block of a frame leaves for the next: the Huffman table,
    the three FSE tables and the recent offsets."""

    var huffman: _Huffman
    var has_huffman: Bool
    var tables: List[_Fse]
    var has_table: List[Bool]
    var recent: List[Int]

    def __init__(out self):
        self.huffman = _Huffman()
        self.has_huffman = False
        self.tables = [_Fse.rle(0), _Fse.rle(0), _Fse.rle(0)]
        self.has_table = [False, False, False]
        self.recent = [1, 4, 8]


def _huffman_stream(
    bytes: List[UInt8],
    start: Int,
    end: Int,
    count: Int,
    table: _Huffman,
    mut out: List[UInt8],
) raises:
    """Decode `count` literals from one Huffman stream.

    Args:
        bytes: The block.
        start: Where the stream starts.
        end: Where it ends.
        count: How many literals it holds.
        table: The Huffman table.
        out: The literals; appended to.

    Raises:
        Error: If the stream is empty, has no marker bit or does not end
            where its size says.
    """
    var stream = _Backward(bytes, start, end)
    for _ in range(count):
        var index = stream.peek(table.max_bits)
        out.append(table.symbols[index])
        stream.pos -= table.bits[index]
    if stream.pos != 0:
        raise Error("zstd: a Huffman stream does not end where its size says")


def _literals(
    bytes: List[UInt8], mut state: _FrameState
) raises -> Tuple[List[UInt8], Int]:
    """Read a compressed block's literals section.

    Args:
        bytes: The block.
        state: The frame's state; its Huffman table is read or replaced.

    Returns:
        The literals, and where the sequences section starts.

    Raises:
        Error: If the section runs past the block, a treeless section has
            no earlier table, or a Huffman stream is malformed.
    """
    _need(0, 1, len(bytes))
    var kind = Int(bytes[0]) & 3
    var format = (Int(bytes[0]) >> 2) & 3
    if kind < 2:
        # Raw or RLE: a header of one, two or three bytes.
        var header = 1 + (format & 1) * (1 + (format >> 1))
        _need(0, header, len(bytes))
        var size = _le(bytes, 0, header) >> (3 + min(header - 1, 1))
        if kind == 0:
            _need(header, size, len(bytes))
            return (List[UInt8](bytes[header : header + size]), header + size)
        _need(header, 1, len(bytes))
        return (List[UInt8](length=size, fill=bytes[header]), header + 1)
    # Compressed or treeless: one stream with a three-byte header, or four
    # with a header of three, four or five bytes.
    var header = max(3, format + 2)
    _need(0, header, len(bytes))
    var width = max(10, format * 4 + 6)
    var sizes = _le(bytes, 0, header) >> 4
    var regenerated = sizes & ((1 << width) - 1)
    var end = header + (sizes >> width)
    _need(0, end, len(bytes))
    var at = header
    if kind == 2:
        var read = _huffman_weights(bytes, at, end)
        state.huffman = _Huffman(read[0])
        state.has_huffman = True
        at = read[1]
    elif not state.has_huffman:
        raise Error(
            "zstd: a treeless literals section has no earlier Huffman table"
        )
    var literals = List[UInt8]()
    if format == 0:
        _huffman_stream(bytes, at, end, regenerated, state.huffman, literals)
    else:
        # A jump table gives the first three streams' sizes; each stream
        # but the last holds a quarter of the literals, rounded up.
        _need(at, 6, end)
        var quarter = (regenerated + 3) // 4
        var from_at = at + 6
        for index in range(4):  # pragma: no branch
            var size = end - from_at
            var count = regenerated - 3 * quarter
            if index < 3:
                size = _le(bytes, at + index * 2, 2)
                count = quarter
            _huffman_stream(
                bytes,
                from_at,
                min(from_at + size, end),
                count,
                state.huffman,
                literals,
            )
            from_at += size
    if len(literals) != regenerated:
        raise Error("zstd: a literals section holds too few literals")
    return (literals^, end)


def _table(
    bytes: List[UInt8],
    at: Int,
    end: Int,
    mode: Int,
    which: Int,
    mut state: _FrameState,
) raises -> Int:
    """Read or pick one of the three FSE tables of a sequences section.

    Args:
        bytes: The block.
        at: Where the table's description would start.
        end: Where the block ends.
        mode: 0 predefined, 1 one symbol, 2 described, 3 the previous.
        which: 0 literal lengths, 1 offsets, 2 match lengths.
        state: The frame's state; the table is put in it.

    Returns:
        Where the next description starts.

    Raises:
        Error: If a single symbol is out of range, a description is
            malformed, or a repeat has no earlier table.
    """
    var logs: List[Int] = [LITERAL_LENGTH_LOG, OFFSET_LOG, MATCH_LENGTH_LOG]
    var most: List[Int] = [
        LITERAL_LENGTH_SYMBOLS,
        OFFSET_SYMBOLS,
        MATCH_LENGTH_SYMBOLS,
    ]
    var next = at
    if mode == 0:
        var counts = [
            _literal_length_counts(),
            _offset_counts(),
            _match_length_counts(),
        ]
        var predefined_logs: List[Int] = [6, 5, 6]
        state.tables[which] = _Fse(counts[which], predefined_logs[which])
    elif mode == 1:
        _need(at, 1, end)
        if Int(bytes[at]) > most[which]:
            raise Error("zstd: a single-symbol table names no such symbol")
        state.tables[which] = _Fse.rle(Int(bytes[at]))
        next = at + 1
    elif mode == 2:
        var read = _read_fse(bytes, at, end, logs[which], most[which])
        state.tables[which] = read[0].copy()
        next = read[1]
    elif not state.has_table[which]:
        raise Error("zstd: a repeated table has no earlier table")
    state.has_table[which] = True
    return next


def _offset(value: Int, literals: Int, mut recent: List[Int]) raises -> Int:
    """Return a sequence's offset and update the three recent offsets.

    Args:
        value: The offset value the stream gives: above three a new
            offset plus three, one to three a repeat.
        literals: The sequence's literal length, which shifts a repeat.
        recent: The three most recent offsets, newest first.

    Returns:
        The offset.

    Raises:
        Error: If a repeat gives an offset of zero.
    """
    if value > 3:
        recent[2] = recent[1]
        recent[1] = recent[0]
        recent[0] = value - 3
        return recent[0]
    var index = value - 1 + (1 if literals == 0 else 0)
    if index == 0:
        return recent[0]
    var offset = recent[0] - 1
    if index < 3:
        offset = recent[index]
    if offset == 0:
        raise Error("zstd: a repeated offset is zero")
    if index >= 2:
        recent[2] = recent[1]
    recent[1] = recent[0]
    recent[0] = offset
    return offset


def _sequences(
    bytes: List[UInt8],
    at: Int,
    literals: List[UInt8],
    mut out: List[UInt8],
    frame_start: Int,
    mut state: _FrameState,
    limit: Int,
) raises:
    """Read a compressed block's sequences section and run it.

    Args:
        bytes: The block.
        at: Where the section starts.
        literals: The block's literals.
        out: The output; appended to.
        frame_start: Where this frame's output starts in `out`.
        state: The frame's state.
        limit: The most the whole stream can produce.

    Raises:
        Error: If the section is malformed, a sequence takes more literals
            than there are, or a match reaches before the frame.
    """
    var end = len(bytes)
    _need(at, 1, end)
    var first = Int(bytes[at])
    var count = first
    var next = at + 1
    if first == 255:
        _need(at, 3, end)
        count = _le(bytes, at + 1, 2) + 0x7F00
        next = at + 3
    elif first >= 128:
        _need(at, 2, end)
        count = ((first - 128) << 8) + Int(bytes[at + 1])
        next = at + 2
    var used = 0
    if count > 0:
        _need(next, 1, end)
        var modes = Int(bytes[next])
        if modes & 3 != 0:
            raise Error("zstd: a sequences section sets its reserved bits")
        next += 1
        next = _table(bytes, next, end, modes >> 6, 0, state)
        next = _table(bytes, next, end, (modes >> 4) & 3, 1, state)
        next = _table(bytes, next, end, (modes >> 2) & 3, 2, state)
        used = _run(
            bytes, next, count, literals, out, frame_start, state, limit
        )
    elif next != end:
        raise Error("zstd: bytes follow a block that has no sequences")
    _room(len(out), len(literals) - used, limit)
    out.extend(Span(literals)[used:])


def _run(
    bytes: List[UInt8],
    at: Int,
    count: Int,
    literals: List[UInt8],
    mut out: List[UInt8],
    frame_start: Int,
    mut state: _FrameState,
    limit: Int,
) raises -> Int:
    """Decode and run `count` sequences from the bitstream at `at`.

    Args:
        bytes: The block.
        at: Where the bitstream starts; it runs to the block's end.
        count: How many sequences there are.
        literals: The block's literals.
        out: The output; appended to.
        frame_start: Where this frame's output starts in `out`.
        state: The frame's state, with its three tables chosen.
        limit: The most the whole stream can produce.

    Returns:
        How many literals the sequences took.

    Raises:
        Error: If the bitstream is malformed or does not end where the
            block does, a sequence takes more literals than there are,
            or a match reaches before the frame.
    """
    var ll_base = _literal_length_base()
    var ll_bits = _literal_length_bits()
    var ml_base = _match_length_base()
    var ml_bits = _match_length_bits()
    var ll = state.tables[0].copy()
    var of = state.tables[1].copy()
    var ml = state.tables[2].copy()
    var stream = _Backward(bytes, at, len(bytes))
    var ll_state = stream.read(ll.log)
    var of_state = stream.read(of.log)
    var ml_state = stream.read(ml.log)
    var used = 0
    for index in range(count):  # pragma: no branch
        var of_code = of.symbols[of_state]
        var ll_code = ll.symbols[ll_state]
        var ml_code = ml.symbols[ml_state]
        var value = (1 << of_code) + stream.read(of_code)
        var matched = ml_base[ml_code] + stream.read(ml_bits[ml_code])
        var length = ll_base[ll_code] + stream.read(ll_bits[ll_code])
        if index + 1 < count:
            ll_state = ll.base[ll_state] + stream.read(ll.bits[ll_state])
            ml_state = ml.base[ml_state] + stream.read(ml.bits[ml_state])
            of_state = of.base[of_state] + stream.read(of.bits[of_state])
        var offset = _offset(value, length, state.recent)
        if length > len(literals) - used:
            raise Error("zstd: a sequence takes more literals than there are")
        _room(len(out), length + matched, limit)
        out.extend(Span(literals)[used : used + length])
        used += length
        if offset > len(out) - frame_start:
            raise Error("zstd: a match reaches before the start of its frame")
        # Byte by byte: the match can overlap what it writes.
        var source = len(out) - offset
        for step in range(matched):  # pragma: no branch
            out.append(out[source + step])
    if stream.pos != 0:
        raise Error("zstd: a sequences bitstream does not end with its block")
    return used


def _rotl(value: UInt64, bits: UInt64) -> UInt64:
    """Rotate a 64-bit word left."""
    return (value << bits) | (value >> (64 - bits))


def _u64(bytes: List[UInt8], at: Int) -> UInt64:
    """Return the little-endian 64-bit word at `at`."""
    var value = UInt64(0)
    for index in range(8):  # pragma: no branch
        value |= UInt64(bytes[at + index]) << UInt64(index * 8)
    return value


def _round(acc: UInt64, lane: UInt64) -> UInt64:
    """Return one XXH64 accumulator round."""
    comptime P1 = UInt64(0x9E3779B185EBCA87)
    comptime P2 = UInt64(0xC2B2AE3D27D4EB4F)
    return _rotl(acc + lane * P2, 31) * P1


def xxh64(bytes: List[UInt8], start: Int, end: Int) -> UInt64:
    """Return the XXH64 hash, seed zero, of `bytes[start:end]`.

    A Zstandard frame's checksum is the low four bytes of it.

    Args:
        bytes: The buffer.
        start: The first byte hashed.
        end: One past the last.

    Returns:
        The hash.
    """
    comptime P1 = UInt64(0x9E3779B185EBCA87)
    comptime P2 = UInt64(0xC2B2AE3D27D4EB4F)
    comptime P3 = UInt64(0x165667B19E3779F9)
    comptime P4 = UInt64(0x85EBCA77C2B2AE63)
    comptime P5 = UInt64(0x27D4EB2F165667C5)
    var at = start
    var hash = P5
    if end - start >= 32:
        var lanes: List[UInt64] = [P1 + P2, P2, 0, UInt64(0) - P1]
        while end - at >= 32:
            for lane in range(4):  # pragma: no branch
                lanes[lane] = _round(lanes[lane], _u64(bytes, at + lane * 8))
            at += 32
        hash = (
            _rotl(lanes[0], 1)
            + _rotl(lanes[1], 7)
            + _rotl(lanes[2], 12)
            + _rotl(lanes[3], 18)
        )
        for lane in range(4):  # pragma: no branch
            hash = (hash ^ _round(0, lanes[lane])) * P1 + P4
    hash += UInt64(end - start)
    while end - at >= 8:
        hash ^= _round(0, _u64(bytes, at))
        hash = _rotl(hash, 27) * P1 + P4
        at += 8
    if end - at >= 4:
        hash ^= UInt64(_le(bytes, at, 4)) * P1
        hash = _rotl(hash, 23) * P2 + P3
        at += 4
    while at < end:
        hash ^= UInt64(bytes[at]) * P5
        hash = _rotl(hash, 11) * P1
        at += 1
    hash ^= hash >> 33
    hash *= P2
    hash ^= hash >> 29
    hash *= P3
    hash ^= hash >> 32
    return hash


def _frame(
    bytes: List[UInt8], start: Int, mut out: List[UInt8], limit: Int
) raises -> Int:
    """Decode one frame, after its magic number, onto `out`.

    Args:
        bytes: The stream.
        start: Where the frame header descriptor is.
        out: The output; appended to.
        limit: The most the whole stream can produce.

    Returns:
        Where the frame ends.

    Raises:
        Error: If the header sets its reserved bit or names a dictionary,
            a block is malformed or too large, the content is not the size
            the header states, or the checksum does not match.
    """
    var end = len(bytes)
    _need(start, 1, end)
    var descriptor = Int(bytes[start])
    if (descriptor >> 3) & 1 != 0:
        raise Error("zstd: a frame header sets its reserved bit")
    var single = (descriptor >> 5) & 1
    var at = start + 1 + (1 - single)
    var id_sizes: List[Int] = [0, 1, 2, 4]
    var id_bytes = id_sizes[descriptor & 3]
    _need(at, id_bytes, end)
    if _le(bytes, at, id_bytes) != 0:
        raise Error("zstd: a frame that needs a dictionary cannot be read")
    at += id_bytes
    var size_sizes: List[Int] = [single, 2, 4, 8]
    var size_bytes = size_sizes[descriptor >> 6]
    _need(at, size_bytes, end)
    var content = _le(bytes, at, size_bytes) + (256 if size_bytes == 2 else 0)
    at += size_bytes
    if size_bytes > 0:
        # A content size with its top bit set is negative here.
        _room(len(out), content if content >= 0 else limit + 1, limit)
    var first = len(out)
    var state = _FrameState()
    var last = 0
    while last == 0:
        _need(at, 3, end)
        var header = _le(bytes, at, 3)
        last = header & 1
        var kind = (header >> 1) & 3
        var size = header >> 3
        at += 3
        if size > MAX_BLOCK:
            raise Error("zstd: a block is larger than 128 KiB")
        if kind == 0:
            _need(at, size, end)
            _room(len(out), size, limit)
            out.extend(Span(bytes)[at : at + size])
            at += size
        elif kind == 1:
            _need(at, 1, end)
            _room(len(out), size, limit)
            for _ in range(size):
                out.append(bytes[at])
            at += 1
        elif kind == 2:
            _need(at, size, end)
            var block = List[UInt8](bytes[at : at + size])
            var read = _literals(block, state)
            _sequences(block, read[1], read[0], out, first, state, limit)
            at += size
        else:
            raise Error("zstd: a block has the reserved type")
    if size_bytes > 0 and len(out) - first != content:
        raise Error("zstd: a frame is not the size its header states")
    if (descriptor >> 2) & 1 == 1:
        _need(at, 4, end)
        var hash = Int(xxh64(out, first, len(out)) & 0xFFFFFFFF)
        if _le(bytes, at, 4) != hash:
            raise Error("zstd: a frame's checksum does not match its content")
        at += 4
    return at


def zstd_decompress(
    bytes: List[UInt8], limit: Int = NO_LIMIT
) raises -> List[UInt8]:
    """Return the bytes a Zstandard stream decompresses to.

    Args:
        bytes: The stream: one or more frames, and skippable frames.
        limit: The most it can produce. `NO_LIMIT` lets it produce any
            size, which is only safe for a stream you wrote.

    Returns:
        The frames' contents, joined.

    Raises:
        Error: If the stream is empty or cut short, a frame does not start
            with a magic number, needs a dictionary or is malformed, or the
            stream expands past `limit`.
    """
    if len(bytes) == 0:
        raise Error("zstd: the stream is empty")
    var out = List[UInt8]()
    var at = 0
    while at < len(bytes):
        _need(at, 4, len(bytes))
        var magic = _le(bytes, at, 4)
        if magic == FRAME_MAGIC:
            at = _frame(bytes, at + 4, out, limit)
        elif (magic & 0xFFFFFFF0) == SKIPPABLE_MAGIC:
            _need(at + 4, 4, len(bytes))
            var size = _le(bytes, at + 4, 4)
            _need(at + 8, size, len(bytes))
            at += 8 + size
        else:
            raise Error("zstd: a frame does not start with a magic number")
    return out^
