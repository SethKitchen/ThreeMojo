# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Stored-moment routes keep their digests and pins."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import strip_try_only_routing
from tools._moment_route import moment_route_current
from tools._moment_routes import (
    moment_route_accepts,
    moment_route_checked,
    moment_route_currents,
    moment_route_digests,
)
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


def _digest_item(
    mut doc: PyJson, rows: Int, text: String, digest: String, message: String
) raises:
    """Append one digest pin.

    Args:
        doc: The payload document.
        rows: The list that receives the pin.
        text: The pinned routing document.
        digest: The pinned SHA-256.
        message: The failure text.

    Raises:
        Error: The item cannot be written.
    """
    var item = doc.new_dict()
    doc.set(item, "text", doc.new_str(text))
    doc.set(item, "digest", doc.new_str(digest))
    doc.set(item, "message", doc.new_str(message))
    doc.append(rows, item)


def test_route_digests_currents_and_pins_agree() raises:
    """Two small modules keep their digest, current document, and pin."""
    var first = "def f():\n    return 1\n"
    var second = "def g():\n    return 2\n"
    var first_route = moment_route_current(first)
    var second_route = moment_route_current(second)
    var digests = PyJson()
    var digest_rows = digests.new_list()
    _digest_item(
        digests,
        digest_rows,
        first_route,
        sha256_hex(first_route.as_bytes()),
        "inconsistent routing pin: first",
    )
    _digest_item(
        digests,
        digest_rows,
        second_route,
        sha256_hex(second_route.as_bytes()),
        "inconsistent routing pin: second",
    )
    digests.root = digest_rows
    moment_route_digests(digests.dumps())
    var sources = PyJson()
    var source_rows = sources.new_list()
    var first_item = sources.new_dict()
    sources.set(first_item, "name", sources.new_str("first"))
    sources.set(first_item, "source", sources.new_str(first))
    sources.append(source_rows, first_item)
    var second_item = sources.new_dict()
    sources.set(second_item, "name", sources.new_str("second"))
    sources.set(second_item, "source", sources.new_str(second))
    sources.append(source_rows, second_item)
    sources.root = source_rows
    var currents = PyJson.parse(moment_route_currents(sources.dumps()))
    assert_equal(
        currents.text(currents.at(currents.root, "first")), first_route
    )
    assert_equal(
        currents.text(currents.at(currents.root, "second")), second_route
    )
    var accepts = PyJson()
    var accept_rows = accepts.new_list()
    var accept_first = accepts.new_dict()
    accepts.set(accept_first, "current", accepts.new_str(first_route))
    accepts.set(accept_first, "expected", accepts.new_str(first_route))
    accepts.set(
        accept_first,
        "message",
        accepts.new_str("source routing changed: first"),
    )
    accepts.set(accept_first, "strip", accepts.new_bool(False))
    accepts.append(accept_rows, accept_first)
    var accept_second = accepts.new_dict()
    accepts.set(accept_second, "current", accepts.new_str(second_route))
    accepts.set(accept_second, "expected", accepts.new_str(second_route))
    accepts.set(
        accept_second,
        "message",
        accepts.new_str("source routing changed: second"),
    )
    accepts.set(accept_second, "strip", accepts.new_bool(False))
    accepts.append(accept_rows, accept_second)
    accepts.root = accept_rows
    moment_route_accepts(accepts.dumps())


def test_the_first_bad_route_digest_is_reported() raises:
    """A later pin does not hide the first digest failure."""
    var route = moment_route_current("def f():\n    return 1\n")
    var digests = PyJson()
    var rows = digests.new_list()
    _digest_item(
        digests,
        rows,
        route,
        "0000000000000000000000000000000000000000000000000000000000000000",
        "inconsistent routing pin: first",
    )
    _digest_item(
        digests,
        rows,
        route,
        "1111111111111111111111111111111111111111111111111111111111111111",
        "inconsistent routing pin: second",
    )
    digests.root = rows
    with assert_raises(contains="inconsistent routing pin: first"):
        moment_route_digests(digests.dumps())


def test_a_changed_route_pin_is_refused() raises:
    """The accept check reports the first different document."""
    var route = moment_route_current("def f():\n    return 1\n")
    var accepts = PyJson()
    var rows = accepts.new_list()
    var item = accepts.new_dict()
    accepts.set(item, "current", accepts.new_str(route))
    accepts.set(item, "expected", accepts.new_str(route + " "))
    accepts.set(
        item, "message", accepts.new_str("source routing changed: first")
    )
    accepts.set(item, "strip", accepts.new_bool(False))
    accepts.append(rows, item)
    accepts.root = rows
    with assert_raises(contains="source routing changed: first"):
        moment_route_accepts(accepts.dumps())


def test_the_try_only_parameter_is_removed_before_the_pin() raises:
    """The ideal caller pin is the document after the try-only parameter."""
    var source = (
        "def _lane_jet_model_proof[capture: Bool](require_reuse: Bool = False,)"
        " -> Int:\n"
        + "    return 1\n"
    )
    var current = moment_route_current(source)
    var expected = strip_try_only_routing(current)
    var accepts = PyJson()
    var rows = accepts.new_list()
    var item = accepts.new_dict()
    accepts.set(item, "current", accepts.new_str(current))
    accepts.set(item, "expected", accepts.new_str(expected))
    accepts.set(
        item, "message", accepts.new_str("source routing changed: ideal")
    )
    accepts.set(item, "strip", accepts.new_bool(True))
    accepts.append(rows, item)
    accepts.root = rows
    moment_route_accepts(accepts.dumps())


def _proof() -> String:
    """Return one reviewed try-only refusal.

    Returns:
        A small lane-proof module.
    """
    return (
        "def _lane_jet_model_proof[capture: Bool](\n"
        + "    ideal_translation: Bool = False,\n"
        + "    require_reuse: Bool = False,\n"
        + ") -> Int:\n"
        + "    if reused:\n"
        + "        point = reused.value()\n"
        + "    elif require_reuse:\n"
        + "        return _unknown_point()\n"
        + "    else:\n"
        + "        point = 1\n"
        + "    return point\n"
    )


def _checked(source: String, expected: String) raises -> String:
    """Return one refusal check and one route pin.

    Args:
        source: The projected ideal-caller module. An empty string omits it.
        expected: The pinned routing document.

    Returns:
        JSON with `accepts` and, when `source` is not empty, `source`.

    Raises:
        Error: The payload cannot be written.
    """
    var route = moment_route_current("def f():\n    return 1\n")
    var doc = PyJson()
    var root = doc.new_dict()
    var accepts = doc.new_list()
    var item = doc.new_dict()
    doc.set(item, "current", doc.new_str(route))
    doc.set(item, "expected", doc.new_str(expected))
    doc.set(item, "message", doc.new_str("source routing changed: first"))
    doc.set(item, "strip", doc.new_bool(False))
    doc.append(accepts, item)
    doc.set(root, "accepts", accepts)
    if source.byte_length() > 0:
        doc.set(root, "source", doc.new_str(source))
    doc.root = root
    return doc.dumps()


def test_the_try_only_refusal_is_checked_before_the_route_pin() raises:
    """A missing lane proof fails before a wrong route pin."""
    with assert_raises(
        contains="spiral moment try: missing or ambiguous function"
    ):
        moment_route_checked(_checked("def f():\n    return 1\n", "nope"))


def test_a_matching_refusal_still_checks_the_route_pin() raises:
    """A reviewed refusal still refuses a different route pin."""
    with assert_raises(contains="source routing changed: first"):
        moment_route_checked(_checked(_proof(), "nope"))


def test_a_matching_refusal_and_route_pin_pass() raises:
    """A reviewed refusal and its route pin both match."""
    var route = moment_route_current("def f():\n    return 1\n")
    moment_route_checked(_checked(_proof(), route))


def test_an_absent_refusal_still_checks_the_route_pin() raises:
    """An absent ideal caller still refuses a different route pin."""
    with assert_raises(contains="source routing changed: first"):
        moment_route_checked(_checked("", "nope"))


def main() raises:
    """Run the moment route batch tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
