# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The helper text is required before the stored-half check."""

from std.testing import TestSuite, assert_raises

from tools._moment_projection import checked_helper_projection


def test_a_non_string_fails_before_the_helper_check() raises:
    """A JSON number keeps the caller message."""
    with assert_raises(contains="not a string"):
        checked_helper_projection('{"text":1,"message":"not a string"}')


def test_a_string_reaches_the_stored_half_check() raises:
    """A string passes the text check and then fails the helper check."""
    with assert_raises(contains="unsupported ideal function declaration"):
        checked_helper_projection(
            '{"text":"def f():\\n pass\\n","message":"not a string"}'
        )


def main() raises:
    """Run the helper projection tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
