# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""DEFLATE compression, RFC 1951, as fflate 0.8.2 writes it: the other
half of `render.inflate`.

three.js's exporters compress with fflate, the library in
`examples/jsm/libs/fflate.module.js`. `zlib_deflate` is its `zlibSync`
and `deflate` is its `deflateSync`. They give the same bytes as fflate,
not only a stream that expands to the same data. So a file that this
project exports is the file that three.js exports.

**How fflate compresses.** At a level from one to nine, fflate finds
matches with a hash of three bytes and a chain of earlier places with
the same hash. The level sets how long a match must be to stop the
search, and how far down the chain it looks. A block ends after 7,000
matches or 24,576 symbols. Each block is written in the smallest of the
three block types: stored, fixed or dynamic. The dynamic codes come from
fflate's Huffman tree, cut to 15 bits by the method of UZIP.js. At level
zero, the data is cut into stored blocks of 65,535 bytes.

The hash table has `2 ** bits` entries. fflate sets `bits` from the
natural log of the data's length: `ceil(max(8, min(13, ln(n))) * 1.5)`.
"""

from std.math import ceil, log

from render.checksum import adler32

# The largest number of symbols in a block, and the size of the list
# that holds them.
comptime _SYMBOL_ROOM = 25000
# A frequency above any count of symbols: the tree's end marker.
comptime _MAX_FREQUENCY = 25001
# A symbol that is a length and a distance, not a literal byte.
comptime _MATCH_FLAG = 268435456


def _fixed_length_extra() -> List[Int]:
    """Return fflate's `fleb`: the extra bits of each length code."""
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
        0,
        0,
        0,
    ]


def _fixed_distance_extra() -> List[Int]:
    """Return fflate's `fdeb`: the extra bits of each distance code."""
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
        0,
        0,
    ]


def _code_length_order() -> List[Int]:
    """Return fflate's `clim`: the order of the code length codes."""
    return [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]


def _bases(extra: List[Int], first: Int) -> List[Int]:
    """Return fflate's `freb(...).b`: the first length or distance of each
    code, from the extra bits of each.

    Args:
        extra: The extra bits of each code.
        first: The base of the first code, less one.
    """
    var bases = List[Int]()
    var start = first
    # There are 31 codes. The loop always runs.
    for i in range(31):  # pragma: no branch
        # `1 << undefined` is one in JavaScript.
        start += 1 << (extra[i - 1] if i > 0 else 0)
        bases.append(start & 0xFFFF)
    return bases^


def _code_of(value: Int, bases: List[Int]) -> Int:
    """Return fflate's `freb(...).r` of a length or distance: its code in
    the low five bits, and how far it is past the code's base above them.

    fflate fills a table from code one, so a value below the base of code
    one is code zero with nothing past it.
    """
    if value < bases[1]:
        return 0
    # The last code from one to 29 whose base is not above the value.
    var low = 1
    var high = 29
    while low < high:
        var middle = (low + high + 1) // 2
        if bases[middle] <= value:
            low = middle
        else:
            high = middle - 1
    return ((value - bases[low]) << 5) | low


def _reverse(value: Int) -> Int:
    """Return fflate's `rev`: a 15-bit value with its bits reversed."""
    var x = ((value & 0xAAAA) >> 1) | ((value & 0x5555) << 1)
    x = ((x & 0xCCCC) >> 2) | ((x & 0x3333) << 2)
    x = ((x & 0xF0F0) >> 4) | ((x & 0x0F0F) << 4)
    return (((x & 0xFF00) >> 8) | ((x & 0x00FF) << 8)) >> 1


def _at(values: List[Int], i: Int) -> Int:
    """Return a value, or zero past the end: JavaScript's `undefined`
    where a bit operation reads it."""
    if i >= len(values):
        return 0
    return values[i]


def _code_map(lengths: List[Int], max_bits: Int) -> List[Int]:
    """Return fflate's `hMap(cd, mb, 0)`: the reversed code of each
    symbol, from the length of each.

    Args:
        lengths: The code length of each symbol.
        max_bits: The longest code.
    """
    var count = List[Int](length=max_bits, fill=0)
    for length in lengths:
        if length != 0:
            count[length - 1] += 1
    var next = List[Int](length=max_bits, fill=0)
    for i in range(1, max_bits):
        next[i] = ((next[i - 1] + count[i - 1]) << 1) & 0xFFFF
    var codes = List[Int](length=len(lengths), fill=0)
    for i in range(len(lengths)):
        var length = lengths[i]
        if length != 0:
            codes[i] = _reverse(next[length - 1]) >> (15 - length)
            next[length - 1] = (next[length - 1] + 1) & 0xFFFF
    return codes^


struct _Tree(Movable):
    """The code lengths that fflate's `hTree` gives, and the longest."""

    var lengths: List[Int]
    var max_bits: Int

    def __init__(out self, var lengths: List[Int], max_bits: Int):
        """Hold code lengths and the longest of them."""
        self.lengths = lengths^
        self.max_bits = max_bits


def _stable_sort(mut order: List[Int], key: List[Int]):
    """Sort indices by a key, keeping equal keys in order, as V8's sort
    does."""
    # A tree is sorted when it has two symbols or more. The loop always runs.
    for i in range(1, len(order)):  # pragma: no branch
        var item = order[i]
        var j = i - 1
        while j >= 0 and key[order[j]] > key[item]:
            order[j + 1] = order[j]
            j -= 1
        order[j + 1] = item


def _depths(
    node: Int,
    depth: Int,
    symbol: List[Int],
    left: List[Int],
    right: List[Int],
    mut lengths: List[Int],
) -> Int:
    """Give each leaf under a node its depth, fflate's `ln`, and return
    the greatest depth."""
    if symbol[node] != -1:
        lengths[symbol[node]] = depth
        return depth
    return max(
        _depths(left[node], depth + 1, symbol, left, right, lengths),
        _depths(right[node], depth + 1, symbol, left, right, lengths),
    )


def _branch(
    a: Int,
    b: Int,
    mut symbol: List[Int],
    mut frequency: List[Int],
    mut left: List[Int],
    mut right: List[Int],
) -> Int:
    """Add a node over two others, and return it."""
    symbol.append(-1)
    frequency.append(frequency[a] + frequency[b])
    left.append(a)
    right.append(b)
    return len(symbol) - 1


def _huffman_tree(frequencies: List[Int], limit: Int) -> _Tree:
    """Return the code lengths of fflate's `hTree`, cut to `limit` bits.

    Args:
        frequencies: How often each symbol is used.
        limit: The longest code allowed.
    """
    # The nodes: a leaf has a symbol, a branch has two children.
    var symbol = List[Int]()
    var frequency = List[Int]()
    var left = List[Int]()
    var right = List[Int]()
    var t = List[Int]()
    # A list of frequencies is never empty. The loop always runs.
    for i in range(len(frequencies)):  # pragma: no branch
        if frequencies[i] != 0:
            t.append(len(symbol))
            symbol.append(i)
            frequency.append(frequencies[i])
            left.append(-1)
            right.append(-1)
    var s = len(t)
    var t2 = t.copy()
    if s == 0:
        return _Tree(List[Int](), 0)
    if s == 1:
        var single = List[Int](length=symbol[t[0]] + 1, fill=0)
        single[symbol[t[0]]] = 1
        return _Tree(single^, 1)
    _stable_sort(t, frequency)
    t.append(len(symbol))
    symbol.append(-1)
    frequency.append(_MAX_FREQUENCY)
    left.append(-1)
    right.append(-1)

    var i0 = 0
    var i1 = 1
    var i2 = 2
    t[0] = _branch(t[0], t[1], symbol, frequency, left, right)
    while i1 != s - 1:
        var l: Int
        if frequency[t[i0]] < frequency[t[i2]]:
            l = t[i0]
            i0 += 1
        else:
            l = t[i2]
            i2 += 1
        var r: Int
        if i0 != i1 and frequency[t[i0]] < frequency[t[i2]]:
            r = t[i0]
            i0 += 1
        else:
            r = t[i2]
            i2 += 1
        t[i1] = _branch(l, r, symbol, frequency, left, right)
        i1 += 1
    var max_symbol = symbol[t2[0]]
    # There are two symbols or more here. The loop always runs.
    for i in range(1, s):  # pragma: no branch
        max_symbol = max(max_symbol, symbol[t2[i]])
    var tr = List[Int](length=max_symbol + 1, fill=0)
    var mbt = _depths(t[i1 - 1], 0, symbol, left, right, tr)
    if mbt > limit:
        # UZIP.js's way to cut the longest codes and pay the debt back.
        var i = 0
        var debt = 0
        var lft = mbt - limit
        var cost = 1 << lft
        # Longest code first, then the least used, as fflate sorts.
        # There are two symbols or more here. The loop always runs.
        for a in range(1, s):  # pragma: no branch
            var item = t2[a]
            var j = a - 1
            while j >= 0 and (
                tr[symbol[t2[j]]] < tr[symbol[item]]
                or (
                    tr[symbol[t2[j]]] == tr[symbol[item]]
                    and frequency[t2[j]] > frequency[item]
                )
            ):
                t2[j + 1] = t2[j]
                j -= 1
            t2[j + 1] = item
        # fflate stops at the end of the symbols too, but the shortest code
        # is never over the limit.
        while tr[symbol[t2[i]]] > limit:
            var sym = symbol[t2[i]]
            debt += cost - (1 << (mbt - tr[sym]))
            tr[sym] = limit
            i += 1
        debt >>= lft
        while debt > 0:
            var sym = symbol[t2[i]]
            if tr[sym] < limit:
                debt -= 1 << (limit - tr[sym] - 1)
                tr[sym] += 1
            else:
                i += 1
        # Back from `i` to the first symbol while there is debt: fflate's
        # `for (; i >= 0 && dt; --i)`. A code was cut, so `i` is one or
        # more. The loop always runs.
        for k in range(i, -1, -1):  # pragma: no branch
            if debt == 0:
                break
            var sym = symbol[t2[k]]
            if tr[sym] == limit:
                tr[sym] -= 1
                debt += 1
        mbt = limit
    return _Tree(tr^, mbt)


def _run_length_codes(lengths: List[Int]) -> Tuple[List[Int], Int]:
    """Return fflate's `lc`: code lengths with runs as codes 16, 17 and
    18, each packed with its extra bits, and how many lengths are sent.
    """
    # fflate drops the zeros at the end, but the lengths of `hTree` end
    # at their largest symbol, which has a code. An empty list sends one.
    var s = max(len(lengths), 1)
    var out = List[Int]()
    var current = _at(lengths, 0)
    var streak = 1
    # `s` is one or more. The loop always runs.
    for i in range(1, s + 1):  # pragma: no branch
        if i != s and lengths[i] == current:
            streak += 1
            continue
        if current == 0 and streak > 2:
            while streak > 138:
                out.append(32754)
                streak -= 138
            if streak > 2:
                if streak > 10:
                    out.append(((streak - 11) << 5) | 28690)
                else:
                    out.append(((streak - 3) << 5) | 12305)
                streak = 0
        elif streak > 3:
            out.append(current)
            streak -= 1
            while streak > 6:
                out.append(8304)
                streak -= 6
            if streak > 2:
                out.append(((streak - 3) << 5) | 8208)
                streak = 0
        while streak > 0:
            out.append(current)
            streak -= 1
        streak = 1
        current = _at(lengths, i)
    return (out^, s)


def _cost(frequencies: List[Int], lengths: List[Int]) -> Int:
    """Return fflate's `clen`: the bits the symbols take in a code."""
    var total = 0
    for i in range(len(lengths)):
        total += frequencies[i] * lengths[i]
    return total


struct _Writer(Movable):
    """The output of fflate's `dflt`: a zeroed buffer written bit by bit.

    fflate writes to a view of its buffer, which drops a write past the
    view's end. Only zero bits go past the end of the stream, so the
    buffer here has three bytes more instead, which `take` cuts off.
    """

    var out: List[UInt8]
    # Where the stream starts in `out`: fflate's `pre`.
    var start: Int
    # Where the stream stops in `out`: `out` less fflate's `post`.

    def __init__(out self, size: Int, start: Int):
        """Make a zeroed buffer of `size` bytes and three more."""
        self.out = List[UInt8](length=size + 3, fill=0)
        self.start = start

    def take(deinit self, end: Int) -> List[UInt8]:
        """Return the buffer, cut to `end` bytes: fflate's `slc`."""
        var out = self.out^
        out.resize(end, 0)
        return out^

    def set(mut self, at: Int, value: Int):
        """Set a byte of the stream."""
        self.out[self.start + at] = UInt8(value & 255)

    def get(self, at: Int) -> Int:
        """Return a byte of the stream."""
        return Int(self.out[self.start + at])

    def bits(mut self, position: Int, value: Int):
        """Put bits at a bit position: fflate's `wbits16`, which covers
        `wbits` too."""
        var v = value << (position & 7)
        var o = position // 8
        self.set(o, self.get(o) | v)
        self.set(o + 1, self.get(o + 1) | (v >> 8))
        self.set(o + 2, self.get(o + 2) | (v >> 16))

    def stored(mut self, position: Int, data: Span[UInt8, _]) -> Int:
        """Write a stored block's length and bytes: fflate's `wfblk`.

        Returns:
            The bit position after it.
        """
        var s = len(data)
        var o = (position + 2 + 7) // 8
        self.set(o, s & 255)
        self.set(o + 1, s >> 8)
        self.set(o + 2, (s & 255) ^ 255)
        self.set(o + 3, (s >> 8) ^ 255)
        for i in range(s):
            self.set(o + i + 4, Int(data[i]))
        return (o + 4 + s) * 8


struct _Tables(Movable):
    """fflate's constant tables."""

    var length_extra: List[Int]
    var distance_extra: List[Int]
    var order: List[Int]
    var length_bases: List[Int]
    var distance_bases: List[Int]
    var fixed_lengths: List[Int]
    var fixed_distances: List[Int]
    var fixed_length_map: List[Int]
    var fixed_distance_map: List[Int]

    def __init__(out self):
        """Build the tables."""
        self.length_extra = _fixed_length_extra()
        self.distance_extra = _fixed_distance_extra()
        self.order = _code_length_order()
        self.length_bases = _bases(self.length_extra, 2)
        self.distance_bases = _bases(self.distance_extra, 0)
        self.fixed_lengths = List[Int](length=288, fill=8)
        # A fixed range. The loop always runs.
        for i in range(144, 256):  # pragma: no branch
            self.fixed_lengths[i] = 9
        # A fixed range. The loop always runs.
        for i in range(256, 280):  # pragma: no branch
            self.fixed_lengths[i] = 7
        self.fixed_distances = List[Int](length=32, fill=5)
        self.fixed_length_map = _code_map(self.fixed_lengths, 9)
        self.fixed_distance_map = _code_map(self.fixed_distances, 5)


def _write_block(
    data: Span[UInt8, _],
    mut w: _Writer,
    final: Int,
    symbols: List[Int],
    mut lf: List[Int],
    df: List[Int],
    extra_bits: Int,
    count: Int,
    block_start: Int,
    block_length: Int,
    position: Int,
    tables: _Tables,
) -> Int:
    """Write one block in the smallest of the three types: fflate's
    `wblk`.

    Returns:
        The bit position after it.
    """
    var p = position
    w.bits(p, final)
    p += 1
    lf[256] += 1
    var lt = _huffman_tree(lf, 15)
    var dt = _huffman_tree(df, 15)
    var lcl = _run_length_codes(lt.lengths)
    var lcd = _run_length_codes(dt.lengths)
    var lcfreq = List[Int](length=19, fill=0)
    # One length at least is sent. The loop always runs.
    for code in lcl[0]:  # pragma: no branch
        lcfreq[code & 31] += 1
    # One length at least is sent. The loop always runs.
    for code in lcd[0]:  # pragma: no branch
        lcfreq[code & 31] += 1
    var ct = _huffman_tree(lcfreq, 7)
    var nlcc = 19
    # fflate stops at four too, but the end of block always has a code,
    # so a length from one to 15 is sent and the count stays above four.
    while _at(ct.lengths, tables.order[nlcc - 1]) == 0:
        nlcc -= 1
    var flen = (block_length + 5) << 3
    var ftlen = (
        _cost(lf, tables.fixed_lengths)
        + _cost(df, tables.fixed_distances)
        + extra_bits
    )
    var dtlen = (
        _cost(lf, lt.lengths)
        + _cost(df, dt.lengths)
        + extra_bits
        + 14
        + 3 * nlcc
        + _cost(lcfreq, ct.lengths)
        + 2 * lcfreq[16]
        + 3 * lcfreq[17]
        + 7 * lcfreq[18]
    )
    # fflate also asks that the block's start is known, which it always
    # is here: the data is not a stream.
    if flen <= ftlen and flen <= dtlen:
        return w.stored(p, data[block_start : block_start + block_length])
    var dynamic = dtlen < ftlen
    w.bits(p, 2 if dynamic else 1)
    p += 2
    var lm: List[Int]
    var ll: List[Int]
    var dm: List[Int]
    var dl: List[Int]
    if dynamic:
        lm = _code_map(lt.lengths, lt.max_bits)
        ll = lt.lengths.copy()
        dm = _code_map(dt.lengths, dt.max_bits)
        dl = dt.lengths.copy()
        var llm = _code_map(ct.lengths, ct.max_bits)
        w.bits(p, lcl[1] - 257)
        w.bits(p + 5, lcd[1] - 1)
        w.bits(p + 10, nlcc - 4)
        p += 14
        # Five or more are sent. The loop always runs.
        for i in range(nlcc):  # pragma: no branch
            w.bits(p + 3 * i, _at(ct.lengths, tables.order[i]))
        p += 3 * nlcc
        # Two lists. The loop always runs.
        for codes in [lcl[0].copy(), lcd[0].copy()]:  # pragma: no branch
            # One length at least is sent. The loop always runs.
            for code in codes:  # pragma: no branch
                var length = code & 31
                w.bits(p, llm[length])
                p += ct.lengths[length]
                if length > 15:
                    w.bits(p, (code >> 5) & 127)
                    p += code >> 12
    else:
        lm = tables.fixed_length_map.copy()
        ll = tables.fixed_lengths.copy()
        dm = tables.fixed_distance_map.copy()
        dl = tables.fixed_distances.copy()
    for i in range(count):
        var sym = symbols[i]
        if sym > 255:
            var length = (sym >> 18) & 31
            w.bits(p, lm[length + 257])
            p += ll[length + 257]
            if length > 7:
                w.bits(p, (sym >> 23) & 31)
                p += tables.length_extra[length]
            var distance = sym & 31
            w.bits(p, dm[distance])
            p += dl[distance]
            if distance > 3:
                w.bits(p, (sym >> 5) & 8191)
                p += tables.distance_extra[distance]
        else:
            w.bits(p, lm[sym])
            p += ll[sym]
    w.bits(p, lm[256])
    return p + ll[256]


def _options(level: Int) raises -> Int:
    """Return fflate's `deo` entry for a level: `(nice << 13) | chain`."""
    var table: List[Int] = [
        65540,
        131080,
        131088,
        131104,
        262176,
        1048704,
        1048832,
        2114560,
        2117632,
    ]
    return table[level - 1]


def hash_bits(length: Int) -> Int:
    """Return the bits of fflate's hash for data of a length: its `mem`
    default, `ceil(max(8, min(13, ln(length))) * 1.5)`.

    Args:
        length: The length of the data, in bytes.

    Returns:
        The bits, from 12 to 20.
    """
    # The log of zero is minus infinity, and the `max` makes it eight.
    var natural = log(Float64(length)) if length > 0 else 0.0
    return Int(ceil(max(8.0, min(13.0, natural)) * 1.5))


def _hash(data: Span[UInt8, _], i: Int, bs1: Int, bs2: Int, mask: Int) -> Int:
    """Return fflate's hash of the three bytes at `i`."""
    var a = Int(data[i])
    var b = Int(data[i + 1])
    var c = Int(data[i + 2])
    return (a ^ (b << bs1) ^ (c << bs2)) & mask


def _compress(
    data: Span[UInt8, _], level: Int, pre: Int, post: Int
) raises -> List[UInt8]:
    """Return fflate's `dflt` for a whole input: the stream, with `pre`
    bytes before it and `post` bytes after it."""
    var s = len(data)
    var size = pre + s + 5 * (1 + (s + 6999) // 7000) + post
    var w = _Writer(size, pre)
    var pos = 0
    if level == 0:
        var i = 0
        while i < s + 1:
            var e = i + 65535
            if e >= s:
                w.set(pos // 8, 1)
                e = s
            pos = w.stored(pos + 1, data[i:e])
            i += 65535
    else:
        var tables = _Tables()
        var opt = _options(level)
        var nice = opt >> 13
        var chain = opt & 8191
        var plvl = hash_bits(s)
        var mask = (1 << plvl) - 1
        var prev = List[Int](length=32768, fill=0)
        var head = List[Int](length=mask + 1, fill=0)
        var bs1 = (plvl + 2) // 3
        var bs2 = 2 * bs1

        var syms = List[Int](length=_SYMBOL_ROOM, fill=0)
        var lf = List[Int](length=288, fill=0)
        var df = List[Int](length=32, fill=0)
        var lc = 0
        var eb = 0
        var i = 0
        var li = 0
        var wi = 0
        var bs = 0
        while i + 2 < s:
            var hv = _hash(data, i, bs1, bs2, mask)
            var imod = i & 32767
            var pimod = head[hv]
            prev[imod] = pimod
            head[hv] = imod
            if wi <= i:
                var rem = s - i
                if (lc > 7000 or li > 24576) and rem > 423:
                    pos = _write_block(
                        data,
                        w,
                        0,
                        syms,
                        lf,
                        df,
                        eb,
                        li,
                        bs,
                        i - bs,
                        pos,
                        tables,
                    )
                    li = 0
                    lc = 0
                    eb = 0
                    bs = i
                    # A fixed range. The loop always runs.
                    for j in range(286):  # pragma: no branch
                        lf[j] = 0
                    # A fixed range. The loop always runs.
                    for j in range(30):  # pragma: no branch
                        df[j] = 0
                var l = 2
                var d = 0
                var ch = chain
                var dif = (imod - pimod) & 32767
                # fflate also asks for three bytes left, which the loop
                # already makes sure of.
                if hv == _hash(data, i - dif, bs1, bs2, mask):
                    var maxn = min(nice, rem) - 1
                    var maxd = min(32767, i)
                    var ml = min(258, rem)
                    while True:
                        if dif > maxd:
                            break
                        ch -= 1
                        if ch == 0 or imod == pimod:
                            break
                        # `l` is below the bytes left: a match of all of
                        # them ends the search, as `maxn` is less.
                        if data[i + l] == data[i + l - dif]:
                            var nl = 0
                            while (
                                nl < ml and data[i + nl] == data[i + nl - dif]
                            ):
                                nl += 1
                            if nl > l:
                                l = nl
                                d = dif
                                if nl > maxn:
                                    break
                                var mmd = min(dif, nl - 2)
                                var md = 0
                                # A match is three bytes or more, one byte back or more. The loop always runs.
                                for j in range(mmd):  # pragma: no branch
                                    var ti = (i - dif + j) & 32767
                                    var pti = prev[ti]
                                    var cd = (ti - pti) & 32767
                                    if cd > md:
                                        md = cd
                                        pimod = ti
                        imod = pimod
                        pimod = prev[imod]
                        dif += (imod - pimod) & 32767
                if d != 0:
                    # fflate sets the code of the longest length by hand.
                    var lcode = 28 if l == 258 else _code_of(
                        l, tables.length_bases
                    )
                    var dcode = _code_of(d, tables.distance_bases)
                    syms[li] = _MATCH_FLAG | (lcode << 18) | dcode
                    li += 1
                    var lin = lcode & 31
                    var din = dcode & 31
                    eb += tables.length_extra[lin] + tables.distance_extra[din]
                    lf[257 + lin] += 1
                    df[din] += 1
                    wi = i + l
                    lc += 1
                else:
                    syms[li] = Int(data[i])
                    li += 1
                    lf[Int(data[i])] += 1
            i += 1
        i = max(i, wi)
        while i < s:
            syms[li] = Int(data[i])
            li += 1
            lf[Int(data[i])] += 1
            i += 1
        pos = _write_block(
            data, w, 1, syms, lf, df, eb, li, bs, i - bs, pos, tables
        )
    return w^.take(pre + (pos + 7) // 8 + post)


def _check_level(level: Int) raises:
    """Refuse a level outside zero to nine."""
    if level < 0 or level > 9:
        raise Error(
            "DEFLATE: a level must be from 0 to 9, not " + String(level)
        )


def deflate(data: Span[UInt8, _], level: Int = 6) raises -> List[UInt8]:
    """Return a raw DEFLATE stream of the data, as fflate's
    `deflateSync` writes it.

    Args:
        data: The bytes to compress.
        level: From 0, stored, to 9, the smallest. fflate's default is 6.

    Returns:
        The stream.

    Raises:
        Error: If the level is not from 0 to 9.
    """
    _check_level(level)
    return _compress(data, level, 0, 0)


def zlib_deflate(data: Span[UInt8, _], level: Int = 6) raises -> List[UInt8]:
    """Return a zlib stream of the data, RFC 1950, as fflate's `zlibSync`
    writes it.

    The header says the level as fflate does, and the Adler-32 of the
    data ends the stream.

    Args:
        data: The bytes to compress.
        level: From 0, stored, to 9, the smallest. fflate's default is 6.

    Returns:
        The stream.

    Raises:
        Error: If the level is not from 0 to 9.
    """
    _check_level(level)
    var out = _compress(data, level, 2, 4)
    var fl = 0 if level == 0 else (1 if level < 6 else (3 if level == 9 else 2))
    out[0] = 120
    var second = fl << 6
    second |= 31 - ((120 << 8) | second) % 31
    out[1] = UInt8(second)
    var bytes = List[UInt8](capacity=len(data))
    for b in data:
        bytes.append(b)
    var sum = Int(adler32(bytes))
    var at = len(out) - 4
    # Four bytes. The loop always runs.
    for k in range(4):  # pragma: no branch
        out[at + k] = UInt8((sum >> (24 - 8 * k)) & 255)
    return out^
