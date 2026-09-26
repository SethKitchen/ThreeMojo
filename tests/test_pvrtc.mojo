# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.pvrtc`: the payloads in `assets/pvrtc/` decoded as
Imagination's `PVRTDecompress.cpp` decodes them, from
`assets/pvrtc/make_reference.cpp`."""

from loaders.json import parse_json
from render.pvrtc import decode_pvrtc, pvrtc_bytes
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises


def test_each_payload_decodes_as_the_reference_decodes_it() raises:
    var doc = parse_json(Path("assets/pvrtc/reference.json").read_text())
    var names: List[String] = [
        "4bpp_8x8",
        "4bpp_16x8",
        "4bpp_32x32",
        "4bpp_4x4",
        "2bpp_16x8",
        "2bpp_32x16",
        "2bpp_8x4",
    ]
    var sizes: List[Int] = [8, 8, 16, 8, 32, 32, 4, 4, 16, 8, 32, 16, 8, 4]
    for k in range(len(names)):
        var name = names[k]
        var data = Path("assets/pvrtc/" + name + ".bin").read_bytes()
        var got = decode_pvrtc(
            sizes[2 * k], sizes[2 * k + 1], data, name.startswith("2bpp")
        )
        var want = doc.get(doc.root(), name)
        assert_equal(len(got), doc.length(want), name)
        for at in range(len(got)):
            assert_equal(Int(got[at]), doc.integer(doc.at(want, at)), name)


def test_the_size_is_checked() raises:
    assert_equal(pvrtc_bytes(4, 4, False), 32)
    assert_equal(pvrtc_bytes(64, 32, True), 8 * 8 * 8)
    with assert_raises(contains="powers of two"):
        _ = decode_pvrtc(12, 8, List[UInt8](length=48, fill=0), False)
    with assert_raises(contains="powers of two"):
        _ = decode_pvrtc(8, 0, List[UInt8](), False)
    # A level smaller than a block decodes the block and keeps its corner.
    var thin = decode_pvrtc(8, 2, List[UInt8](length=32, fill=0), False)
    assert_equal(len(thin), 8 * 2 * 4)
    with assert_raises(contains="does not match"):
        _ = decode_pvrtc(8, 8, List[UInt8](length=8, fill=0), False)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
