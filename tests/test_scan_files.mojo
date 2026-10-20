# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.files`, the reader of every scan format.

Each format is told apart by its mark or its name, and read by its own
reader: the splats must be the ones that reader gives.
"""

from extensions.scan.compressed_ply import read_compressed_ply
from extensions.scan.files import (
    SCAN_COMPRESSED_PLY,
    SCAN_KSPLAT,
    SCAN_PLY,
    SCAN_SOG,
    SCAN_SOG_FOLDER,
    SCAN_SPLAT,
    SCAN_SPZ,
    ScanFormat,
    parse_scan,
    read_scan,
    scan_format,
)
from extensions.scan.scene import SPLAT_DEFAULT
from extensions.scan.sog import read_sog
from loaders.gaussian_splat_ply import read_gaussian_splat_ply
from loaders.ksplat import read_ksplat
from loaders.splat import read_splat
from loaders.spz import read_spz
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._splat_same import same_splats


def _format(path: String) raises -> ScanFormat:
    """Return the format of a file, from its name and its bytes."""
    return scan_format(path, Path(path).read_bytes())


def test_the_formats_have_their_names_and_axes() raises:
    """Each format has its name, and only SPZ holds y up."""
    var names: List[String] = [
        "sog",
        "sog-folder",
        "compressed-ply",
        "ply",
        "spz",
        "ksplat",
        "splat",
    ]
    for value in range(7):
        assert_equal(ScanFormat(value).name(), names[value])
        assert_equal(ScanFormat(value).y_down(), ScanFormat(value) != SCAN_SPZ)
    assert_equal(ScanFormat(7).name(), "unknown")
    assert_false(ScanFormat(7).y_down())
    assert_false(ScanFormat(-1).is_valid())


def test_marks_tell_the_formats_apart() raises:
    """The first bytes name the format, whatever the name says."""
    assert_true(_format("assets/sog/sh1.sog") == SCAN_SOG)
    assert_true(
        _format("assets/compressed_ply/sh1.compressed.ply")
        == SCAN_COMPRESSED_PLY
    )
    assert_true(_format("assets/compressed_ply/sh1_restored.ply") == SCAN_PLY)
    assert_true(_format("assets/gaussian_splat/v2.spz") == SCAN_SPZ)
    assert_true(_format("assets/gaussian_splat/v4.spz") == SCAN_SPZ)
    var gzip: List[UInt8] = [0x1F, 0x8B, 8]
    assert_true(scan_format("a.splat", gzip) == SCAN_SPZ)


def test_names_tell_the_formats_with_no_mark() raises:
    """A SOG text, a KSPLAT file and a SPLAT file are told by their names."""
    var none = List[UInt8]()
    assert_true(scan_format("scan/meta.json", none) == SCAN_SOG_FOLDER)
    assert_true(_format("assets/gaussian_splat/level0.ksplat") == SCAN_KSPLAT)
    assert_true(_format("assets/gaussian_splat/four.splat") == SCAN_SPLAT)
    var short: List[UInt8] = [0x50]
    with assert_raises(contains="the format of 'scan.bin' is not known"):
        _ = scan_format("scan.bin", short)


def test_each_format_is_read_by_its_reader() raises:
    """`read_scan` gives what each format's own reader gives."""
    same_splats(
        read_scan("assets/sog/sh1.sog").geometry,
        read_sog("assets/sog/sh1.sog").geometry,
    )
    same_splats(
        read_scan("assets/sog/flat/meta.json").geometry,
        read_sog("assets/sog/flat/meta.json").geometry,
    )
    same_splats(
        read_scan("assets/compressed_ply/sh2.compressed.ply").geometry,
        read_compressed_ply(
            "assets/compressed_ply/sh2.compressed.ply"
        ).geometry,
    )
    var plain = read_scan("assets/compressed_ply/sh2_restored.ply")
    same_splats(
        plain.geometry,
        read_gaussian_splat_ply("assets/compressed_ply/sh2_restored.ply"),
    )
    assert_true(plain.model == SPLAT_DEFAULT)
    same_splats(
        read_scan("assets/gaussian_splat/v2.spz").geometry,
        read_spz("assets/gaussian_splat/v2.spz"),
    )
    same_splats(
        read_scan("assets/gaussian_splat/level1.ksplat").geometry,
        read_ksplat("assets/gaussian_splat/level1.ksplat"),
    )
    same_splats(
        read_scan("assets/gaussian_splat/four.splat").geometry,
        read_splat("assets/gaussian_splat/four.splat"),
    )


def test_formats_that_parse_cannot_read_are_refused() raises:
    """A SOG folder needs its files, and a format must be valid."""
    var bytes = Path("assets/sog/flat/meta.json").read_bytes()
    with assert_raises(contains="read it with read_scan"):
        _ = parse_scan(bytes, SCAN_SOG_FOLDER)
    with assert_raises(contains="0 to 6, not 7"):
        _ = parse_scan(bytes, ScanFormat(7))
    with assert_raises(contains="is not known"):
        _ = read_scan("assets/building_scans/manifest.json")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
