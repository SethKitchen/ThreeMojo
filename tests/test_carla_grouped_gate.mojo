# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed grouped consumer fails the token gate."""

from std.testing import TestSuite, assert_raises, assert_true

from tests._python_tokens import token_sha256
from tools._python_json import PyJson
from tools.carla_grouped_gate import grouped_checked, grouped_table


def test_a_changed_module_is_refused() raises:
    """Stand-in sources do not have the reviewed digest."""
    with assert_raises(contains="Reviewed grouped consumer graph changed"):
        _ = grouped_table("def main():\n    pass\n", "def main():\n    pass\n")


def test_a_different_digest_returns_before_the_bounds() raises:
    """A different digest requests a predecessor before the stored bounds."""
    var parsed = PyJson.parse(
        grouped_checked(
            "def main():\n    pass\n", "def main():\n    pass\n", "00"
        )
    )
    assert_true(parsed.flag(parsed.at(parsed.root, "restore")))


def test_a_matching_digest_reaches_the_grouped_token() raises:
    """A matching digest still refuses a module that is not the reviewed proof.
    """
    var source = "def main():\n    pass\n"
    with assert_raises(contains="Reviewed grouped consumer graph changed"):
        _ = grouped_checked(
            source, "def main():\n    pass\n", token_sha256(source)
        )


def main() raises:
    """Run the grouped-gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
