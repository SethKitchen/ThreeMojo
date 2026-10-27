# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The optional-runtime contract messages stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._optional_runtime_messages import optional_runtime_messages
from tools._python_json import PyJson


def test_optional_runtime_contract_messages_stay_reviewed() raises:
    """The prefix and the fresh-guard fragment keep their exact text."""
    var doc = PyJson.parse(optional_runtime_messages())
    assert_equal(
        doc.text(doc.at(doc.root, "prefix")), "optional runtime contract: "
    )
    assert_equal(
        doc.text(doc.at(doc.root, "move")), "unsupported move-token placement"
    )
    assert_equal(
        doc.text(doc.at(doc.root, "fragment")), "invalid checker fragment:"
    )
    assert_equal(
        doc.text(doc.at(doc.root, "fresh_fragment")),
        "if not _sum2_supported_environment():\n    return None",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "fresh_label")),
        "fresh invocation guard missing or moved: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "paths")),
        "optional runtime contract: production path set changed",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "models")),
        "optional runtime contract: model name set changed",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "frontier")),
        "one original search frontier loop",
    )


def main() raises:
    """Run the optional-runtime message tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
