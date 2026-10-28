# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Successor digests are compared before the dispatch migration record."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._dispatch_source import texts_match_then_migration
from tools._python_json import PyJson


def test_a_missing_text_fails_before_the_migration_record() raises:
    """A pair without text fails before the dispatch record is read."""
    with assert_raises(contains="KeyError: 'actual'"):
        _ = texts_match_then_migration("[{}]")


def test_a_mismatch_skips_the_migration_record() raises:
    """One unequal digest returns flags and does not read the record."""
    var doc = PyJson.parse(
        texts_match_then_migration('[{"actual":"aa","expected":"bb"}]')
    )
    assert_equal(doc.key(doc.root, 0), "flags")
    assert_equal(doc.key(doc.root, 1), "matched")
    assert_equal(doc.flag(doc.at(doc.root, "matched")), False)
    assert_equal(doc.text(doc.item(doc.at(doc.root, "flags"), 0)), "false")


def test_matching_digests_read_the_dispatch_record() raises:
    """Equal digests keep the dispatch migration record last."""
    var doc = PyJson.parse(
        texts_match_then_migration(
            '[{"actual":"aa","expected":"aa"},{"actual":"bb","expected":"bb"}]'
        )
    )
    assert_equal(doc.key(doc.root, 0), "flags")
    assert_equal(doc.key(doc.root, 1), "matched")
    assert_equal(doc.key(doc.root, 2), "migration")
    assert_equal(doc.flag(doc.at(doc.root, "matched")), True)
    assert_equal(
        doc.text(doc.at(doc.at(doc.root, "migration"), "path")),
        "tools/carla_lane_oracle/curve-support-dispatch-migration.json",
    )


def main() raises:
    """Run the digest and dispatch-migration tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
