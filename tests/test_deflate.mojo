# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`render.deflate` against fflate 0.8.2, the library three.js exports
with.

`assets/deflate/fflate.json` holds what fflate's `zlibSync` and
`deflateSync` give for generated data: small data at each level, and
large data, zlib only, at the levels that reach its paths: the length and
CRC-32 of each stream, and the bytes of the short ones. The data comes
from a xorshift generator that is the same here and in node.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from loaders.json import JsonDocument, parse_json
from render.checksum import crc32
from render.deflate import _huffman_tree, deflate, hash_bits, zlib_deflate
from render.inflate import inflate, zlib_inflate


struct _Random(Movable):
    """The xorshift generator of the fixture's script."""

    var x: UInt32

    def __init__(out self, seed: Int):
        self.x = UInt32(seed)

    def next(mut self) -> Int:
        self.x ^= self.x << 13
        self.x ^= self.x >> 17
        self.x ^= self.x << 5
        return Int(self.x)


def _generate(
    n: Int, seed: Int, alpha: Int, copy: Int, step: Int = 1
) -> List[UInt8]:
    """Return literals and copies of earlier runs, as the script does."""
    var random = _Random(seed)
    var out = List[UInt8](length=n, fill=0)
    var p = 0
    while p < n:
        var r = random.next()
        if p > 0 and r % 100 < copy:
            var length = 3 + random.next() % 300
            var distance = 1 + random.next() % min(p, 40000)
            var k = 0
            while k < length and p < n:
                out[p] = out[p - distance]
                k += 1
                p += 1
        else:
            out[p] = UInt8(random.next() % alpha * step)
            p += 1
    return out^


def _fibonacci(seed: Int) -> List[UInt8]:
    """Return symbols used as often as the Fibonacci numbers, shuffled:
    a code longer than 15 bits before it is cut."""
    var symbols = List[UInt8]()
    var a = 1
    var b = 1
    for s in range(21):
        for _ in range(a):
            symbols.append(UInt8(s * 12))
        var c = a + b
        a = b
        b = c
    var random = _Random(seed)
    var i = len(symbols) - 1
    while i > 0:
        var j = random.next() % (i + 1)
        var t = symbols[i]
        symbols[i] = symbols[j]
        symbols[j] = t
        i -= 1
    return symbols^


def _debruijn_step(t: Int, p: Int, mut a: List[Int], mut sequence: List[UInt8]):
    """One step of the script's de Bruijn sequence of order three over
    eight symbols."""
    if t > 3:
        if 3 % p == 0:
            for j in range(1, p + 1):
                sequence.append(UInt8(a[j] * 30))
        return
    a[t] = a[t - p]
    _debruijn_step(t + 1, p, a, sequence)
    for j in range(a[t - p] + 1, 8):
        a[t] = j
        _debruijn_step(t + 1, t, a, sequence)


def _debruijn() -> List[UInt8]:
    """Return the script's `debruijn`: no three bytes repeat."""
    var a = List[Int](length=24, fill=0)
    var sequence = List[UInt8]()
    _debruijn_step(1, 1, a, sequence)
    return sequence^


def test_streams_match_fflate() raises:
    var text = String(
        StringSlice(
            unsafe_from_utf8=open(
                "assets/deflate/fflate.json", "r"
            ).read_bytes()
        )
    )
    var doc = parse_json(text)
    var root = doc.root()
    for c in range(doc.length(root)):
        var entry = doc.at(root, c)
        var data: List[UInt8]
        var kind = doc.string(doc.get(entry, "kind"))
        if kind == "gen":
            data = _generate(
                doc.integer(doc.get(entry, "n")),
                doc.integer(doc.get(entry, "seed")),
                doc.integer(doc.get(entry, "alpha")),
                doc.integer(doc.get(entry, "copy")),
                doc.integer(doc.get(entry, "step")),
            )
        elif kind == "debruijn":
            data = _debruijn()
        else:
            data = _fibonacci(doc.integer(doc.get(entry, "seed")))
        assert_equal(len(data), doc.integer(doc.get(entry, "length")))
        assert_equal(Int(crc32(data)), doc.integer(doc.get(entry, "input_crc")))
        var level = doc.integer(doc.get(entry, "level"))
        var z = zlib_deflate(data, level)
        var zlib = doc.get(entry, "zlib")
        assert_equal(len(z), doc.integer(doc.get(zlib, "length")))
        assert_equal(Int(crc32(z)), doc.integer(doc.get(zlib, "crc")))
        var bytes = doc.get(zlib, "bytes")
        for i in range(doc.length(bytes)):
            assert_equal(Int(z[i]), doc.integer(doc.at(bytes, i)))
        # The streams expand to the data again.
        assert_true(zlib_inflate(z) == data)
        var raw = doc.get(entry, "raw")
        if doc.is_null(raw):
            continue
        var r = deflate(data, level)
        assert_equal(len(r), doc.integer(doc.get(raw, "length")))
        assert_equal(Int(crc32(r)), doc.integer(doc.get(raw, "crc")))
        assert_true(inflate(r) == data)


def test_trees_match_fflate() raises:
    # Frequencies whose longest codes are cut, and whose debt is paid
    # back past zero, with the code lengths of fflate's `hTree`.
    var text = String(
        unsafe_from_utf8=open("assets/deflate/trees.json", "r").read_bytes()
    )
    var doc = parse_json(text)
    var root = doc.root()
    for c in range(doc.length(root)):
        var entry = doc.at(root, c)
        var frequencies = List[Int]()
        var list = doc.get(entry, "frequencies")
        for i in range(doc.length(list)):
            frequencies.append(doc.integer(doc.at(list, i)))
        var tree = _huffman_tree(
            frequencies, doc.integer(doc.get(entry, "limit"))
        )
        var lengths = doc.get(entry, "lengths")
        assert_equal(len(tree.lengths), doc.length(lengths))
        for i in range(len(tree.lengths)):
            assert_equal(tree.lengths[i], doc.integer(doc.at(lengths, i)))
        assert_equal(tree.max_bits, doc.integer(doc.get(entry, "max")))


def test_defaults_and_refusals() raises:
    var data = _generate(1000, 13, 8, 20)
    assert_true(zlib_deflate(data) == zlib_deflate(data, 6))
    assert_true(deflate(data) == deflate(data, 6))
    with assert_raises(contains="from 0 to 9"):
        _ = deflate(data, 10)
    with assert_raises(contains="from 0 to 9"):
        _ = zlib_deflate(data, -1)
    assert_equal(hash_bits(0), 12)
    assert_equal(hash_bits(100000), 18)
    assert_equal(hash_bits(10000000), 20)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
