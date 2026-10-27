# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The cleanup premise lists stay in historical order."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises

from tools._cleanup_premises import prepare_cleanup_premises
from tools._python_json import PyJson


def test_the_five_premise_lists_stay_in_order() raises:
    """Each declaration is written with its reviewed fragments."""
    var directory = mkdtemp(prefix="cleanup-premise-")
    Path(directory + "/sources.json").write_text(
        '{"line":"LINE","arc":"ARC","bounds":"BOUNDS","center":"CENTER","outward":"OUT"}'
    )
    prepare_cleanup_premises(directory)
    assert_equal(Path(directory + "/0.mojo").read_text(), "LINE")
    assert_equal(Path(directory + "/4.mojo").read_text(), "OUT")
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    assert_equal(doc.length(doc.root), 5)
    assert_equal(
        doc.text(doc.at(doc.item(doc.root, 0), "label")),
        "LINE singleton/domain/low lookup and multi-record profile premises",
    )
    assert_equal(doc.length(doc.at(doc.item(doc.root, 0), "fragments")), 7)
    assert_equal(doc.length(doc.at(doc.item(doc.root, 1), "fragments")), 9)
    assert_equal(doc.length(doc.at(doc.item(doc.root, 2), "fragments")), 3)
    assert_equal(doc.length(doc.at(doc.item(doc.root, 3), "fragments")), 4)
    assert_equal(doc.length(doc.at(doc.item(doc.root, 4), "fragments")), 8)
    assert_equal(
        doc.text(doc.item(doc.at(doc.item(doc.root, 3), "fragments"), 1)),
        (
            "var selector = _rounded_madd(half,"
            " _RoundedBox.point(_INV_HALF_PI), _RoundedBox.point(0.5))"
        ),
    )


def test_a_missing_premise_declaration_is_refused() raises:
    """A sources object without `outward` is refused."""
    var directory = mkdtemp(prefix="cleanup-premise-missing-")
    Path(directory + "/sources.json").write_text(
        '{"line":"L","arc":"A","bounds":"B","center":"C"}'
    )
    with assert_raises(contains="KeyError: 'outward'"):
        prepare_cleanup_premises(directory)


def main() raises:
    """Run the cleanup premise tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
