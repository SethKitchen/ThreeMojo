# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The dispatch path, choice names, and premise messages stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._dispatch_labels import dispatch_labels
from tools._python_json import PyJson


def test_dispatch_labels_keep_their_trailing_spaces() raises:
    """Each premise message keeps the space before the path or the name."""
    var doc = PyJson.parse(dispatch_labels())
    assert_equal(doc.length(doc.root), 13)
    assert_equal(doc.key(doc.root, 0), "dispatch_path")
    assert_equal(
        doc.text(doc.at(doc.root, "dispatch_path")),
        "extensions/carla/curve_sample_dispatch.mojo",
    )
    assert_equal(doc.text(doc.at(doc.root, "current")), "current")
    assert_equal(doc.text(doc.at(doc.root, "restore")), "restore")
    assert_equal(
        doc.text(doc.at(doc.root, "unreviewed")),
        "curve support/dispatch contract: unreviewed source successor: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "successor_operations")),
        "successor operations changed: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "premise_modules")),
        "interval/environment premise changed: ",
    )
    assert_equal(doc.text(doc.at(doc.root, "seed")), "seed")
    assert_equal(
        doc.text(doc.at(doc.root, "seed_message")),
        "reviewed Map caller premise changed: ",
    )
    assert_equal(doc.text(doc.at(doc.root, "lane")), "lane")
    assert_equal(
        doc.text(doc.at(doc.root, "lane_message")),
        "reviewed lane caller premise changed: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "premise_function")),
        "index or guarded caller premise changed: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "reference")),
        "native predecessor reference changed: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "complete")), "complete successor changed: "
    )


def main() raises:
    """Run the dispatch label tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
