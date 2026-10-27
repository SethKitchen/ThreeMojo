# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The reviewed contract prefixes stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._contract_prefixes import contract_prefixes
from tools._python_json import PyJson


def test_reviewed_contract_prefixes_stay_reviewed() raises:
    """Each checker prefix keeps its trailing space."""
    var doc = PyJson.parse(contract_prefixes())
    assert_equal(
        doc.text(doc.at(doc.root, "cleanup")),
        "reviewed cleanup source contract: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "frozen")), "frozen ARC producer contract: "
    )
    assert_equal(
        doc.text(doc.at(doc.root, "speed")), "reviewed speed parser successor: "
    )
    assert_equal(
        doc.text(doc.at(doc.root, "render")),
        "reviewed render actor reuse successor: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "runtime")),
        "reviewed runtime boundary successor: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "invariant")),
        "coverage invariant successor: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "singleton")),
        "rounded LINE singleton contract: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "dispatch")),
        "curve support/dispatch contract: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "scalar")), "missing or ambiguous scalar: "
    )


def main() raises:
    """Run the contract prefix tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
