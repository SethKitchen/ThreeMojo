# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A runtime pin document refuses a repeated key."""

from std.testing import TestSuite, assert_raises

from tools._duplicate_pin_keys import reject_duplicate_pin_keys


def test_unique_pin_documents_are_accepted() raises:
    """Objects, arrays, strings, and literals with unique keys pass."""
    var samples = List[String]()
    samples.append("{}")
    samples.append("[]")
    samples.append("[1, 2]")
    samples.append('{"a":[1, true, false, null]}')
    samples.append('"text"')
    samples.append("0")
    samples.append("-2.5e+10")
    samples.append(
        '"\\b\\f\\n\\r\\t\\"\\\\\\/\\u0039\\u004A\\u004a"'
    )
    samples.append("{\"a\": 1}\n")
    samples.append("\t[1]\r\n")
    samples.append(String("\"") + "\\" + "/" + "\"")
    samples.append(String("\"") + "\\" + "\"" + "\"")
    samples.append(String("\"") + "\\" + "\\" + "\"")
    for sample in samples:
        reject_duplicate_pin_keys(sample.as_bytes())


def test_a_repeated_key_keeps_its_name() raises:
    """A repeated key is named, including a key inside an array."""
    with assert_raises(contains="duplicate runtime source pin key: a"):
        reject_duplicate_pin_keys(String('{"a":1,"a":2}').as_bytes())
    with assert_raises(contains="duplicate runtime source pin key: b"):
        reject_duplicate_pin_keys(
            String('[{"b":1,"b":2}]').as_bytes()
        )


def test_invalid_pin_json_uses_the_parser_text() raises:
    """Invalid JSON and trailing bytes use the parser text."""
    with assert_raises(
        contains=(
            "Expecting property name enclosed in double quotes: line 1"
            " column 2 (char 1)"
        )
    ):
        reject_duplicate_pin_keys("{".as_bytes())
    with assert_raises(contains="Extra data"):
        reject_duplicate_pin_keys("{}x".as_bytes())
    with assert_raises(contains="Expecting"):
        reject_duplicate_pin_keys('{"a" 1}'.as_bytes())
    with assert_raises(contains="Invalid"):
        reject_duplicate_pin_keys('"\\q"'.as_bytes())
    with assert_raises(contains="Invalid"):
        reject_duplicate_pin_keys('"\\u12"'.as_bytes())
    with assert_raises(contains="Invalid"):
        reject_duplicate_pin_keys('"\\u00GG"'.as_bytes())
    with assert_raises(contains="Unterminated"):
        reject_duplicate_pin_keys('"abc'.as_bytes())
    with assert_raises(contains="Expecting"):
        reject_duplicate_pin_keys("[1 2]".as_bytes())
    with assert_raises(contains="Expecting"):
        reject_duplicate_pin_keys("[1,".as_bytes())
    with assert_raises(contains="Expecting"):
        reject_duplicate_pin_keys('{"a":'.as_bytes())
    with assert_raises(contains="Expecting"):
        reject_duplicate_pin_keys(String("").as_bytes())


def main() raises:
    """Run the duplicate pin-key tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
