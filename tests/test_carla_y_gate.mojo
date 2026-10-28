# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed Y-finiteness module fails the token gate."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_json import PyJson
from tools.carla_y_gate import (
    y_finiteness,
    y_identity,
    y_predecessor,
    y_successor,
    y_token_mismatches,
)


def test_a_changed_module_is_refused() raises:
    """Stand-in sources do not have the reviewed digests."""
    with assert_raises(
        contains=(
            "Y-finiteness premise, graph, writes or ordering changed:"
            " extensions/carla/spiral_grouped_roundoff_proof.mojo"
        )
    ):
        _ = y_finiteness(
            "def main():\n    pass\n",
            "def main():\n    pass\n",
            "def main():\n    pass\n",
            "def main():\n    pass\n",
            "def main():\n    pass\n",
        )


def test_a_changed_successor_record_is_refused() raises:
    """Bytes that are not the successor record fail closed."""
    with assert_raises(contains="Unreviewed grouped Y successor record"):
        y_successor(
            String("").as_bytes(),
            String("").as_bytes(),
            String("").as_bytes(),
            "",
            "",
            False,
        )


def test_a_changed_module_token_is_refused() raises:
    """A module token that is not the reviewed digest fails closed."""
    with assert_raises(
        contains="Grouped Y predecessor/successor token identity changed"
    ):
        y_identity(
            "def changed():\n    pass\n",
            "def changed():\n    pass\n",
            "00",
            "00",
        )


def test_mismatches_keep_review_order() raises:
    """A changed module is listed after every earlier match."""
    var stand_in = "def main():\n    pass\n"
    var listed = PyJson.parse(
        y_token_mismatches(stand_in, stand_in, stand_in, stand_in, stand_in)
    )
    assert_equal(listed.length(listed.root), 5)
    assert_equal(
        listed.text(listed.item(listed.root, 0)),
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    assert_equal(
        listed.text(listed.item(listed.root, 4)),
        "extensions/carla/curve_sum2.mojo",
    )
    var grouped = Path(
        "extensions/carla/spiral_grouped_roundoff_proof.mojo"
    ).read_text()
    var partial = PyJson.parse(
        y_token_mismatches(grouped, stand_in, stand_in, stand_in, stand_in)
    )
    assert_equal(partial.length(partial.root), 4)
    assert_equal(
        partial.text(partial.item(partial.root, 0)),
        "extensions/carla/curve_interval.mojo",
    )


def test_the_predecessor_record_returns_the_earlier_module() raises:
    """The record digest is checked before the earlier module is returned."""
    var record = Path(
        "tools/carla_lane_oracle/grouped-y-successor-record.json"
    ).read_text()
    var doc = PyJson.parse(record)
    assert_equal(
        y_predecessor(record),
        doc.text(doc.at(doc.root, "before_complete_module")),
    )
    with assert_raises(contains="Unreviewed grouped Y successor record"):
        _ = y_predecessor(record + " ")


def main() raises:
    """Run the Y-finiteness gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
