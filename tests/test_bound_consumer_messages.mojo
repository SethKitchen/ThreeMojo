# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The render-actor and runtime-boundary refusal messages stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._bound_consumer_messages import bound_consumer_messages
from tools._python_json import PyJson


def test_bound_consumer_messages_keep_their_trailing_spaces() raises:
    """Each refusal message keeps the space before the path."""
    var doc = PyJson.parse(bound_consumer_messages())
    assert_equal(doc.length(doc.root), 4)
    assert_equal(doc.key(doc.root, 0), "render_consumer")
    assert_equal(doc.key(doc.root, 1), "render_test")
    assert_equal(doc.key(doc.root, 2), "runtime_consumer")
    assert_equal(doc.key(doc.root, 3), "runtime_test")
    assert_equal(
        doc.text(doc.at(doc.root, "render_consumer")),
        "unreviewed render actor consumer: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "render_test")),
        "bound render actor test changed: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "runtime_consumer")),
        "unreviewed runtime boundary consumer: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "runtime_test")),
        "bound runtime boundary test changed: ",
    )


def main() raises:
    """Run the bound consumer message tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
