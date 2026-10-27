# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Stored-moment operation blocks match their pins in one check."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import selected_block
from tools._moment_blocks import moment_blocks
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


def _item(
    mut doc: PyJson,
    rows: Int,
    name: String,
    source: String,
    begin: String,
    end: String,
    expected: String,
) raises:
    """Append one block pin.

    Args:
        doc: The document.
        rows: The list.
        name: The block name.
        source: The module source.
        begin: The opening marker.
        end: The closing marker.
        expected: The pinned normalized block.

    Raises:
        Error: The item cannot be stored.
    """
    var item = doc.new_dict()
    doc.set(item, "name", doc.new_str(name))
    doc.set(item, "source", doc.new_str(source))
    doc.set(item, "begin", doc.new_str(begin))
    doc.set(item, "end", doc.new_str(end))
    doc.set(item, "expected", doc.new_str(expected))
    doc.set(item, "digest", doc.new_str(sha256_hex(expected.as_bytes())))
    doc.append(rows, item)


def test_two_operation_blocks_match_their_pins() raises:
    """Both blocks are returned when their pins match."""
    var source = "def a():\n    return 1\ndef b():\n    return 2\n"
    var expected = selected_block(source, "def a():", "def b():")
    var doc = PyJson()
    var rows = doc.new_list()
    _item(doc, rows, "first", source, "def a():", "def b():", expected)
    doc.root = rows
    var result = PyJson.parse(moment_blocks(doc.dumps()))
    assert_equal(result.text(result.at(result.root, "first")), expected)


def test_a_changed_operation_block_is_refused() raises:
    """A different normalized block is refused by name."""
    var source = "def a():\n    return 1\ndef b():\n    return 2\n"
    var doc = PyJson()
    var rows = doc.new_list()
    _item(doc, rows, "first", source, "def a():", "def b():", "def a():\n")
    doc.root = rows
    with assert_raises(contains="operation graph changed: first"):
        _ = moment_blocks(doc.dumps())


def main() raises:
    """Run the moment block tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
