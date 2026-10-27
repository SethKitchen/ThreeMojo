# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Stored-moment scalar words match their pins in one check."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._moment_scalars import moment_scalars
from tools._python_json import PyJson


def _payload(source: String, expected: String) raises -> String:
    """Return one scalar pin.

    Args:
        source: The module source.
        expected: The pinned `0x` word.

    Returns:
        A JSON object with one scalar.

    Raises:
        Error: The payload cannot be written.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    var rows = doc.new_list()
    var item = doc.new_dict()
    doc.set(item, "name", doc.new_str("_PHASE_LIMIT"))
    doc.set(item, "source", doc.new_str(source))
    doc.set(item, "expected", doc.new_str(expected))
    doc.set(
        item,
        "message",
        doc.new_str("stored scalar word changed: _PHASE_LIMIT"),
    )
    doc.append(rows, item)
    doc.set(root, "items", rows)
    doc.set(root, "overflow", doc.new_str("binary64 overflow"))
    doc.root = root
    return doc.dumps()


def test_one_scalar_word_matches_its_pin() raises:
    """`1.0` becomes its binary64 word."""
    var source = "comptime _PHASE_LIMIT = Float64(1.0)\n"
    var result = PyJson.parse(
        moment_scalars(_payload(source, "0x3FF0000000000000"))
    )
    var words = result.at(result.root, "_PHASE_LIMIT")
    assert_equal(result.length(words), 1)
    assert_equal(result.text(result.item(words, 0)), "4607182418800017408")


def test_a_missing_scalar_names_itself() raises:
    """A missing declaration keeps the scalar name for the caller."""
    var source = "comptime OTHER = Float64(1.0)\n"
    with assert_raises(contains="stored scalar literal: _PHASE_LIMIT"):
        _ = moment_scalars(_payload(source, "0x3FF0000000000000"))


def test_a_changed_scalar_word_is_refused() raises:
    """A different pin is the stored-word failure."""
    var source = "comptime _PHASE_LIMIT = Float64(1.0)\n"
    with assert_raises(contains="stored scalar word changed: _PHASE_LIMIT"):
        _ = moment_scalars(_payload(source, "0x0000000000000000"))


def main() raises:
    """Run the moment scalar tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
