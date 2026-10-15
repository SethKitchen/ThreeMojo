# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The DWA variant builder rewrites the committed variant files.

OpenEXR is not available in CI. The native Huffman decoder's AC tokens
come back from the committed `deflate` variant, whose AC stream is those
tokens under zlib.
"""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tools.exr_variants import (
    Block,
    ac_stream,
    file_bytes,
    header,
    needs_tokens,
    single_channel,
    stored,
    stream_variant,
)
from render.inflate import zlib_inflate

comptime FOLDER = "assets/exr_codecs"


def _file(name: String) raises -> List[UInt8]:
    """Decode a committed hex file."""
    var out = List[UInt8]()
    var high = -1
    for byte in Path(FOLDER + "/" + name + ".exr.hex").read_text().as_bytes():
        var value = Int(byte)
        var digit = (
            value - ord("0") if value <= ord("9") else value - ord("a") + 10
        )
        if value == ord("\n"):
            continue
        if high < 0:
            high = digit
        else:
            out.append(UInt8(high * 16 + digit))
            high = -1
    return out^


def _u(data: List[UInt8], at: Int, count: Int) -> Int:
    var value = 0
    for index in range(count):
        value |= Int(data[at + index]) << (8 * index)
    return value


def _blocks(data: List[UInt8], start: Int) -> List[Block]:
    """Return the first two chunks."""
    var blocks = List[Block]()
    for index in range(2):
        var at = _u(data, start + index * 8, 8)
        var length = _u(data, at + 4, 4)
        blocks.append(
            Block(
                _u(data, at, 4),
                List[UInt8](Span(data)[at + 8 : at + 8 + length]),
            )
        )
    return blocks^


def _tokens(codec: Int, index: Int) raises -> List[UInt16]:
    """Return a chunk's AC tokens from the committed deflate variant."""
    var data = _file("c" + String(codec) + "_deflate")
    var block = _blocks(data, header(data)[1])[index].copy()
    var raw = zlib_inflate(ac_stream(block)[0])
    var out = List[UInt16]()
    for at in range(0, len(raw), 2):
        out.append(UInt16(Int(raw[at]) | (Int(raw[at + 1]) << 8)))
    return out^


def test_every_variant_matches_the_committed_file() raises:
    for codec in [8, 9]:
        var data = _file("c" + String(codec) + "_s0")
        var parsed = header(data)
        var blocks = _blocks(data, parsed[1])
        # The writer reproduces the source file from its own parts.
        assert_true(file_bytes(parsed[0], blocks) == data)
        for variant in [
            "deflate",
            "legacy0",
            "legacy1",
            "insensitive",
            "rule_shadow",
        ]:
            var converted = List[Block]()
            for index in range(2):
                var tokens = List[UInt16]()
                if needs_tokens(variant) and not stored(codec, blocks[index]):
                    tokens = _tokens(codec, index)
                converted.append(
                    stream_variant(codec, variant, blocks[index], tokens)
                )
            var name = "c" + String(codec) + "_" + variant
            assert_true(file_bytes(parsed[0], converted) == _file(name), name)
        for variant in [
            "unknown",
            "rle",
            "uppercase_rule",
            "incomplete_csc",
            "incomplete_rle",
        ]:
            var single = single_channel(parsed[0], variant)
            var chunks: List[Block] = [Block(0, single[1].copy())]
            var name = "c" + String(codec) + "_" + variant
            assert_true(file_bytes(single[0], chunks) == _file(name), name)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
