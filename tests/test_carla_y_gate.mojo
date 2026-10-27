# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed Y-finiteness module fails the token gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_y_gate import y_finiteness, y_identity, y_successor


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


def main() raises:
    """Run the Y-finiteness gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
