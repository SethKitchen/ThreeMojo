# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The reviewed Sum2 helper and caller texts keep their checkpoint bytes."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools._sum2_checkpoints import sum2_checkpoints


def _tail(text: String, size: Int) -> String:
    """Return the last `size` bytes.

    Args:
        text: The checkpoint.
        size: The number of bytes.

    Returns:
        The suffix.
    """
    var count = text.byte_length()
    return String(text[byte = count - size : count])


def test_the_four_checkpoints_keep_their_bytes() raises:
    """Each reviewed text keeps its length, opening, and closing bytes."""
    var doc = PyJson.parse(sum2_checkpoints())
    var helper = doc.text(doc.at(doc.root, "helper"))
    var scalar = doc.text(doc.at(doc.root, "scalar"))
    var envelope = doc.text(doc.at(doc.root, "envelope"))
    var eligibility = doc.text(doc.at(doc.root, "eligibility"))
    assert_equal(helper.byte_length(), 1741)
    assert_equal(scalar.byte_length(), 1661)
    assert_equal(envelope.byte_length(), 1059)
    assert_equal(eligibility.byte_length(), 3141)
    assert_equal(String(helper[byte=0:6]), "\nfrom ")
    assert_equal(String(scalar[byte=0:5]), "\ndef ")
    assert_equal(String(envelope[byte=0:5]), "\ndef ")
    assert_equal(String(eligibility[byte=0:5]), "\ndef ")
    assert_equal(_tail(helper, 7), ").high\n")
    assert_equal(_tail(scalar, 8), "    )\n\n\n")
    assert_equal(_tail(envelope, 8), "error\n\n\n")
    assert_equal(_tail(eligibility, 19), "(x_error, y_error)\n")
    assert_equal(doc.key(doc.root, 0), "eligibility")


def main() raises:
    """Run the Sum2 checkpoint tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
