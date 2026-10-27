# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The selection contract path and the predecessor messages stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools._selection_labels import selection_labels


def test_selection_labels_keep_the_contract_path() raises:
    """The contract path stays with the predecessor and selector messages."""
    var doc = PyJson.parse(selection_labels())
    assert_equal(doc.length(doc.root), 5)
    assert_equal(doc.key(doc.root, 0), "contract")
    assert_equal(doc.key(doc.root, 1), "producer_set")
    assert_equal(doc.key(doc.root, 2), "predecessor")
    assert_equal(doc.key(doc.root, 3), "body")
    assert_equal(
        doc.text(doc.at(doc.root, "contract")),
        "tools/carla_lane_oracle/selection-finiteness-contract.json",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "producer_set")),
        "Wrong selection producer set",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "predecessor")),
        "Wrong selection predecessor module",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "body")),
        "Selection complete successor body changed",
    )
    assert_equal(doc.key(doc.root, 4), "scalar")
    assert_equal(
        doc.text(doc.at(doc.root, "scalar")),
        "Missing or ambiguous selector constant",
    )


def main() raises:
    """Run the selection label tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
