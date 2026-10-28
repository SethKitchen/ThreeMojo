# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Stored-moment operation blocks match their pins in one check."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import selected_block
from tools._moment_blocks import (
    moment_blocks,
    moment_blocks_and_digests,
    moment_scalars_and_blocks,
)
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


def _scalar_payload(
    scalar_source: String,
    block_source: String,
    block_expected: String,
    digest: String,
) raises -> String:
    """Return one scalar check, one block, and one route digest.

    Args:
        scalar_source: The scalar module.
        block_source: The block module.
        block_expected: The pinned normalized block.
        digest: The pinned routing digest.

    Returns:
        JSON with `scalars`, `blocks`, and `digests`.

    Raises:
        Error: The payload cannot be written.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    var scalars = doc.new_dict()
    var items = doc.new_list()
    var scalar = doc.new_dict()
    doc.set(scalar, "name", doc.new_str("_PHASE_LIMIT"))
    doc.set(scalar, "source", doc.new_str(scalar_source))
    doc.set(scalar, "expected", doc.new_str("0x3FF0000000000000"))
    doc.set(
        scalar,
        "message",
        doc.new_str("stored scalar word changed: _PHASE_LIMIT"),
    )
    doc.append(items, scalar)
    doc.set(scalars, "items", items)
    doc.set(scalars, "overflow", doc.new_str("binary64 overflow"))
    doc.set(root, "scalars", scalars)
    var blocks = doc.new_list()
    _item(
        doc,
        blocks,
        "first",
        block_source,
        "def a():",
        "def b():",
        block_expected,
    )
    doc.set(root, "blocks", blocks)
    var digests = doc.new_list()
    var route = doc.new_dict()
    doc.set(route, "text", doc.new_str("pin"))
    doc.set(route, "digest", doc.new_str(digest))
    doc.set(route, "message", doc.new_str("inconsistent routing pin: first"))
    doc.append(digests, route)
    doc.set(root, "digests", digests)
    doc.root = root
    return doc.dumps()


def test_a_missing_scalar_fails_before_the_block() raises:
    """A missing scalar fails before a changed block is checked."""
    var source = "def a():\n    return 1\ndef b():\n    return 2\n"
    with assert_raises(contains="stored scalar literal: _PHASE_LIMIT"):
        _ = moment_scalars_and_blocks(
            _scalar_payload(
                "comptime OTHER = Float64(1.0)\n",
                source,
                "def a():\n",
                "0000000000000000000000000000000000000000000000000000000000000000",
            )
        )


def test_a_matching_scalar_still_checks_the_block_and_digest() raises:
    """A matching scalar still refuses a different route digest."""
    var source = "def a():\n    return 1\ndef b():\n    return 2\n"
    var expected = selected_block(source, "def a():", "def b():")
    with assert_raises(contains="inconsistent routing pin: first"):
        _ = moment_scalars_and_blocks(
            _scalar_payload(
                "comptime _PHASE_LIMIT = Float64(1.0)\n",
                source,
                expected,
                "0000000000000000000000000000000000000000000000000000000000000000",
            )
        )


def test_scalars_blocks_and_digests_return_the_block() raises:
    """A matching scalar, block, and digest return the block."""
    var source = "def a():\n    return 1\ndef b():\n    return 2\n"
    var expected = selected_block(source, "def a():", "def b():")
    var result = PyJson.parse(
        moment_scalars_and_blocks(
            _scalar_payload(
                "comptime _PHASE_LIMIT = Float64(1.0)\n",
                source,
                expected,
                sha256_hex(String("pin").as_bytes()),
            )
        )
    )
    assert_equal(result.text(result.at(result.root, "first")), expected)


def main() raises:
    """Run the moment block tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
