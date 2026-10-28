# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Reference tokens are checked before the grouped proof identity."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_json import PyJson
from tools.carla_dispatch_gate import declaration_tokens_then_identity
from tools.carla_grouped_gate import grouped_table_identity


def test_missing_items_fail_before_the_identity() raises:
    """The token list is required before the grouped identity is read."""
    with assert_raises(contains="KeyError: 'items'"):
        _ = declaration_tokens_then_identity("{}")


def test_empty_tokens_read_the_grouped_identity() raises:
    """An empty declaration list still returns the grouped identity."""
    var doc = PyJson.parse(declaration_tokens_then_identity('{"items":[]}'))
    var identity = PyJson.parse(grouped_table_identity())
    assert_equal(doc.key(doc.root, 0), "module")
    assert_equal(
        doc.text(doc.at(doc.root, "module")),
        identity.text(identity.at(identity.root, "module")),
    )
    assert_equal(
        doc.text(doc.at(doc.root, "token")),
        identity.text(identity.at(identity.root, "token")),
    )


def main() raises:
    """Run the declaration-token and grouped-identity tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
