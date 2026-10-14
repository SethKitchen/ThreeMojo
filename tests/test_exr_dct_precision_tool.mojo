# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The DCT precision probe rounds to half as `struct.pack("<e")` does.

The helper library is not available in CI. The expected bits are what
CPython 3.12 packed.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises

from assets.exr_codecs.check_dct_precision import (
    half_bits,
    half_value,
    lookup,
    ordered,
)


def test_half_bits_round_once_with_ties_to_even() raises:
    var cases: List[Tuple[Float64, Int]] = [
        (0.0, 0),
        (-0.0, 32768),
        (1.0, 15360),
        (-2.0, 49152),
        (1.00146484375, 15362),
        (1.00048828125, 15360),
        # Just past the tie: one rounding goes up, two would tie to even.
        (1.0004882812509095, 15361),
        (65504.0, 31743),
        (6e-08, 1),
        (2.98e-08, 0),
        (2.9802322387695312e-08, 0),
        (2.9802322388562674e-08, 1),
        (5.960464477539063e-08, 1),
        (0.0001, 1678),
        (-1.2345678, 48368),
    ]
    for entry in cases:
        assert_equal(half_bits(entry[0]), entry[1], String(entry[0]))
    with assert_raises():
        _ = half_bits(65520.0)
    assert_equal(half_value(15362), 1.001953125)


def test_ordered_keys_follow_values() raises:
    assert_equal(ordered(0x8001), 0x7FFF)
    assert_equal(ordered(0), 0x8000)
    assert_equal(ordered(1), 0x8001)


def test_lookup_reads_the_named_table() raises:
    var root = mkdtemp()
    var folder = root + "/src/lib/OpenEXR"
    from std.os import makedirs

    makedirs(folder, exist_ok=True)
    Path(folder + "/dwaLookups.h").write_text(
        "x[] = {0x1};\ndwaCompressorToLinear[] = {\n0x0000, 0x3c00,\n0xffff\n};"
        " other[] = {0x2};"
    )
    var table = lookup(root)
    assert_equal(len(table), 3)
    assert_equal(table[1], 0x3C00)
    assert_equal(table[2], 0xFFFF)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
