# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the first and last place of a value in a list."""

from core.search import first_match, last_match
from std.testing import TestSuite, assert_equal


def test_string_places() raises:
    var names = List[String]()
    assert_equal(first_match(names, String("a")), -1)
    assert_equal(last_match(names, String("a")), -1)
    names.append(String("a"))
    names.append(String("b"))
    names.append(String("a"))
    assert_equal(first_match(names, String("a")), 0)
    assert_equal(first_match(names, String("b")), 1)
    assert_equal(first_match(names, String("c")), -1)
    assert_equal(last_match(names, String("a")), 2)
    assert_equal(last_match(names, String("b")), 1)
    assert_equal(last_match(names, String("c")), -1)


def test_int_places() raises:
    var keys = List[Int]()
    assert_equal(first_match(keys, 4), -1)
    assert_equal(last_match(keys, 4), -1)
    keys.append(4)
    keys.append(7)
    keys.append(4)
    assert_equal(first_match(keys, 4), 0)
    assert_equal(first_match(keys, 7), 1)
    assert_equal(first_match(keys, 9), -1)
    assert_equal(last_match(keys, 4), 2)
    assert_equal(last_match(keys, 7), 1)
    assert_equal(last_match(keys, 9), -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
