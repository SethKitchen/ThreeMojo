# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.building.scan.catalog`, the scanned buildings of
the manifest as typed entries.

The repository's manifest must read. Every field that the kits, the uses
and the frames refuse is refused here too, by changing one word of a
small manifest.
"""

from extensions.building.kinds import LIVING, MEETING
from extensions.building.kits import CONCRETE_KIT, MASONRY_KIT
from extensions.building.scan.catalog import (
    CATALOG_CACHE,
    CATALOG_MANIFEST,
    ScanCatalog,
    space_use,
)
from extensions.scan.frame import (
    SCALE_DECLARED,
    SCAN_NEGATIVE_Y,
    SCAN_NEGATIVE_Z,
)
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from test_scratch import TestScratch, temporary_path
from units.si import METER

comptime ENTRY = (
    '{"id": "flat-room", "title": "Flat room", "author": "a tester",'
    ' "license": "CC-BY-4.0", "source": "https://example.test/s",'
    ' "kit": "masonry", "use": "living", "frame": {"up": "-y",'
    ' "north": "-z", "unit_m": 2, "scale": "measured"}}'
)


def _manifest(entry: String) -> String:
    """Return a manifest with one entry."""
    return '{"entries": [' + entry + "]}"


def test_the_repository_manifest_reads() raises:
    """The two scenes have their kits, uses and SuperSplat frames."""
    var catalog = ScanCatalog.open(CATALOG_MANIFEST, ".cache/no-such-cache")
    assert_true(len(catalog.entries) >= 2)
    var room = catalog.find("reading-room")
    assert_true(room.kit == CONCRETE_KIT)
    assert_true(room.use == MEETING)
    assert_true(room.frame.up == SCAN_NEGATIVE_Y)
    assert_true(room.frame.north == SCAN_NEGATIVE_Z)
    assert_true(room.frame.scale == SCALE_DECLARED)
    assert_equal(room.license, "CC-BY-4.0")
    assert_true(catalog.find("studio-11").use == LIVING)
    assert_false(Bool(catalog.scene("studio-11")))
    assert_equal(catalog.cache, ".cache/no-such-cache/")
    assert_equal(CATALOG_CACHE, ".cache/building-scans/")


def test_a_cached_scene_is_found_by_its_text() raises:
    """With `meta.json` in the scan's folder, its path is given."""
    var cache = temporary_path("catalog_cache/")
    var catalog = ScanCatalog.parse(_manifest(ENTRY), cache)
    assert_equal(catalog.cache, cache)
    assert_false(Bool(catalog.scene("flat-room")))
    from std.os import makedirs

    makedirs(cache + "flat-room")
    Path(cache + "flat-room/meta.json").write_text("{}")
    assert_equal(
        catalog.scene("flat-room").value(), cache + "flat-room/meta.json"
    )
    var entry = catalog.find("flat-room")
    assert_true(entry.kit == MASONRY_KIT)
    assert_equal(entry.frame.unit.to(METER), 2)
    with assert_raises(contains="no scan 'nope'"):
        _ = catalog.scene("nope")


def test_a_manifest_with_no_entries_has_no_scan() raises:
    """An empty list is a catalog with nothing to find."""
    var catalog = ScanCatalog.parse('{"entries": []}', "c/")
    assert_equal(len(catalog.entries), 0)
    assert_equal(catalog.cache, "c/")
    with assert_raises(contains="no scan 'studio-11'"):
        _ = catalog.find("studio-11")


def test_every_space_use_has_a_name() raises:
    """Each use reads back, and no other word is one."""
    assert_true(space_use("living") == LIVING)
    assert_true(space_use("meeting") == MEETING)
    with assert_raises(contains="'bunker' is not a space use"):
        _ = space_use("bunker")


def test_a_field_that_cannot_be_read_is_refused() raises:
    """A missing list, field or frame, and a wrong kit, use or frame."""
    with assert_raises(contains="the manifest has no entries"):
        _ = ScanCatalog.parse("{}", "c")
    with assert_raises(contains="an entry has no title"):
        _ = ScanCatalog.parse(
            _manifest(String(ENTRY).replace('"title"', '"name"')), "c"
        )
    with assert_raises(contains="'adobe' is not a construction kit"):
        _ = ScanCatalog.parse(
            _manifest(String(ENTRY).replace('"masonry"', '"adobe"')), "c"
        )
    with assert_raises(contains="'bunker' is not a space use"):
        _ = ScanCatalog.parse(
            _manifest(String(ENTRY).replace('"living"', '"bunker"')), "c"
        )
    with assert_raises(contains="an entry has no frame"):
        _ = ScanCatalog.parse(
            _manifest(String(ENTRY).replace('"frame"', '"view"')), "c"
        )
    with assert_raises(contains="'y' is not an axis"):
        _ = ScanCatalog.parse(
            _manifest(String(ENTRY).replace('"-y"', '"y"')), "c"
        )
    with assert_raises(contains="a frame has no unit_m"):
        _ = ScanCatalog.parse(
            _manifest(String(ENTRY).replace('"unit_m"', '"unit"')), "c"
        )
    with assert_raises(contains="the unit must be positive"):
        _ = ScanCatalog.parse(
            _manifest(String(ENTRY).replace('"unit_m": 2', '"unit_m": 0')), "c"
        )
    with assert_raises(contains="'guessed' is not a scale source"):
        _ = ScanCatalog.parse(
            _manifest(String(ENTRY).replace('"measured"', '"guessed"')), "c"
        )
    with assert_raises(contains="up and north must be different axes"):
        _ = ScanCatalog.parse(
            _manifest(String(ENTRY).replace('"-z"', '"+y"')), "c"
        )
    with assert_raises():
        _ = ScanCatalog.open("assets/building_scans/no-such.json", "c")


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
