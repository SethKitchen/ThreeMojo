# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The frozen runtime-pin labels stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._frozen_pin_labels import frozen_pin_labels
from tools._python_json import PyJson


def test_frozen_pin_labels_keep_the_public_message() raises:
    """The premise text names the runtime pin file, and the public message stays.
    """
    var doc = PyJson.parse(frozen_pin_labels())
    assert_equal(doc.length(doc.root), 11)
    assert_equal(
        doc.text(doc.at(doc.root, "premise")),
        (
            "full-audit cleanup successor: unchanged premise, record or fixture"
            " changed: tools/carla_lane_oracle/runtime-source-pins.json"
        ),
    )
    assert_equal(
        doc.text(doc.at(doc.root, "expected_error_prefix")),
        "unreviewed complete successor: ",
    )
    assert_equal(doc.text(doc.at(doc.root, "stage_error")), "error")
    assert_equal(doc.text(doc.at(doc.root, "stage_cause")), "cause")
    assert_equal(doc.text(doc.at(doc.root, "decision_cause")), "cause")
    assert_equal(doc.text(doc.at(doc.root, "decision_relabel")), "relabel")
    assert_equal(
        doc.text(doc.at(doc.root, "public")),
        "frozen ARC producer contract: unreviewed runtime pin successor",
    )
    assert_equal(doc.text(doc.at(doc.root, "guard")), "guard")
    assert_equal(doc.text(doc.at(doc.root, "after")), "after")
    assert_equal(doc.text(doc.at(doc.root, "before")), "before")
    assert_equal(doc.text(doc.at(doc.root, "groups")), "groups")


def main() raises:
    """Run the frozen runtime-pin label tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
