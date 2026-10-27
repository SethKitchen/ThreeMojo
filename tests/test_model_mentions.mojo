# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Watched model names match Python's substring test."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._model_mentions import model_mentions


def test_a_watched_name_matches_a_python_substring() raises:
    """Empty names, longer names, and a later match keep Python's result."""
    assert_equal(model_mentions("[]", "0\n"), "[false]")
    assert_equal(model_mentions('[""]', "0\n"), "[true]")
    assert_equal(model_mentions('["cached_model"]', "4\nabcd"), "[false]")
    assert_equal(
        model_mentions('["cached_model"]', "13\ncached_models"), "[true]"
    )
    assert_equal(
        model_mentions('["aa"]', "4\nabaa"),
        "[true]",
    )
    assert_equal(model_mentions('["zz"]', "4\nabaa"), "[false]")
    assert_equal(
        model_mentions('["nope","cached_model"]', "13\ncached_models"),
        "[true]",
    )
    assert_equal(
        model_mentions('["cached_model","later"]', "13\ncached_models"),
        "[true]",
    )
    assert_equal(model_mentions("[]", ""), "[]")


def test_a_bad_length_line_is_refused() raises:
    """Each malformed length is reported before a text is searched."""
    with assert_raises(contains="invalid model text length"):
        _ = model_mentions("[]", "/\n")
    with assert_raises(contains="invalid model text length"):
        _ = model_mentions("[]", ":\n")
    with assert_raises(contains="invalid model text length"):
        _ = model_mentions("[]", "\n")
    with assert_raises(contains="invalid model text length"):
        _ = model_mentions("[]", "12")
    with assert_raises(contains="invalid model text length"):
        _ = model_mentions("[]", "5\nab")
    with assert_raises(contains="invalid model text length"):
        _ = model_mentions("[]", "1234567890\n")


def main() raises:
    """Run the model mention tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
