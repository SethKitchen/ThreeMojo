# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Universal newlines become `\\n` and other bytes stay."""

from std.testing import TestSuite, assert_equal

from tools._universal_newlines import universal_newlines


def test_universal_newlines_become_line_feeds() raises:
    """`\\n`, `\\r\\n`, and a lone `\\r` all become `\\n`."""
    assert_equal(universal_newlines(""), "")
    assert_equal(universal_newlines("a\nb"), "a\nb")
    assert_equal(universal_newlines("a\r\nb"), "a\nb")
    assert_equal(universal_newlines("a\rb"), "a\nb")
    assert_equal(universal_newlines("a\r\n\r\nb"), "a\n\nb")
    assert_equal(universal_newlines("\r\n"), "\n")
    assert_equal(universal_newlines("\n\r"), "\n\n")
    assert_equal(universal_newlines("é\r\n"), "é\n")
    assert_equal(universal_newlines("\r"), "\n")


def main() raises:
    """Run the universal newline tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
