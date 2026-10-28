# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Stored-moment operation blocks match their pins in one check."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import selected_block
from tools._moment_blocks import moment_blocks, moment_blocks_and_digests
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


def _checked_payload(
    mut doc: PyJson,
    source: String,
    expected: String,
    digest_text: String,
    digest: String,
    message: String,
) raises -> String:
    """Return one block check and one route digest.

    Args:
        doc: The document.
        source: The module source.
        expected: The pinned normalized block.
        digest_text: The pinned routing text.
        digest: The pinned routing digest.
        message: The digest failure text.

    Returns:
        JSON with `blocks` and `digests`.

    Raises:
        Error: The payload cannot be written.
    """
    var root = doc.new_dict()
    var blocks = doc.new_list()
    _item(doc, blocks, "first", source, "def a():", "def b():", expected)
    doc.set(root, "blocks", blocks)
    var digests = doc.new_list()
    var route = doc.new_dict()
    doc.set(route, "text", doc.new_str(digest_text))
    doc.set(route, "digest", doc.new_str(digest))
    doc.set(route, "message", doc.new_str(message))
    doc.append(digests, route)
    doc.set(root, "digests", digests)
    doc.root = root
    return doc.dumps()


def test_blocks_and_digests_return_the_block() raises:
    """A matching block is returned after its route digest matches."""
    var source = "def a():\n    return 1\ndef b():\n    return 2\n"
    var expected = selected_block(source, "def a():", "def b():")
    var doc = PyJson()
    var result = PyJson.parse(
        moment_blocks_and_digests(
            _checked_payload(
                doc,
                source,
                expected,
                "pin",
                sha256_hex(String("pin").as_bytes()),
                "inconsistent routing pin: first",
            )
        )
    )
    assert_equal(result.text(result.at(result.root, "first")), expected)


def test_a_changed_block_fails_before_the_route_digest() raises:
    """A bad block fails before a bad route digest is checked."""
    var source = "def a():\n    return 1\ndef b():\n    return 2\n"
    var doc = PyJson()
    with assert_raises(contains="operation graph changed: first"):
        _ = moment_blocks_and_digests(
            _checked_payload(
                doc,
                source,
                "def a():\n",
                "pin",
                "0000000000000000000000000000000000000000000000000000000000000000",
                "inconsistent routing pin: first",
            )
        )


def test_a_bad_route_digest_fails_after_the_block() raises:
    """A matching block still refuses a different route digest."""
    var source = "def a():\n    return 1\ndef b():\n    return 2\n"
    var expected = selected_block(source, "def a():", "def b():")
    var doc = PyJson()
    with assert_raises(contains="inconsistent routing pin: first"):
        _ = moment_blocks_and_digests(
            _checked_payload(
                doc,
                source,
                expected,
                "pin",
                "0000000000000000000000000000000000000000000000000000000000000000",
                "inconsistent routing pin: first",
            )
        )


def main() raises:
    """Run the moment block tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
