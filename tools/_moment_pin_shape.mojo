# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the stored-moment pin shape before any source is read.

The expected paths and dependency closure come from the caller. This check
only compares the pin document with that specification. The legacy digest
and the projection result pins use the same comparison.
"""

from tools._python_json import PY_INT, PY_LIST, PyJson, py_equal


def _fail(message: String) raises:
    """Raise a pin-shape error.

    Args:
        message: The failure text.

    Raises:
        Error: The pin shape changed.
    """
    raise Error(message)


def _names(doc: PyJson, node: Int) -> List[String]:
    """Return the keys of one object, in stored order.

    Args:
        doc: The document.
        node: An object.

    Returns:
        The keys.
    """
    var out = List[String]()
    var count = doc.length(node)
    var index = 0
    while index < count:
        out.append(doc.key(node, index))
        index += 1
    return out^


def _same_keys(doc: PyJson, node: Int, expected: List[String]) -> Bool:
    """Return whether `node` has exactly the names in `expected`.

    Args:
        doc: The document.
        node: An object.
        expected: The required keys. Duplicates are ignored.

    Returns:
        True when the key sets match.
    """
    var count = doc.length(node)
    if count != len(expected):
        return False
    var index = 0
    while index < count:
        var name = doc.key(node, index)
        var found = False
        var cursor = 0
        while cursor < len(expected):
            if expected[cursor] == name:
                found = True
            cursor += 1
        if not found:
            return False
        index += 1
    return True


def _fixed(text: String) -> List[String]:
    """Return one pipe-separated key list.

    Args:
        text: Keys separated by `|`.

    Returns:
        The keys.
    """
    var out = List[String]()
    var at = 0
    var limit = text.byte_length()
    while at <= limit:
        var bar = text.find("|", at)
        var end = limit
        if bar >= 0:
            end = bar
        out.append(String(text[byte=at:end]))
        if bar < 0:
            at = limit + 1
        else:
            at = bar + 1
    return out^


def _record_keys(
    doc: PyJson, record: Int, expected: String, message: String
) raises:
    """Require one record to have exactly `expected` keys.

    Args:
        doc: The document.
        record: The record object.
        expected: The required keys, separated by `|`.
        message: The failure text.

    Raises:
        Error: The keys differ.
    """
    if not _same_keys(doc, record, _fixed(expected)):
        _fail(message)


def require_moment_pin_shape(payload: String) raises:
    """Require the moment pin document to match its specification.

    Args:
        payload: JSON with `pins` and `spec`. `spec` carries the array,
            scalar, block, routing, and dependency expectations.

    Raises:
        Error: A pin set, schema, path, boundary, or dependency differs.
    """
    var doc = PyJson.parse(payload)
    var pins = doc.at(doc.root, "pins")
    var spec = doc.at(doc.root, "spec")
    if not _same_keys(
        doc,
        pins,
        _fixed(
            "schema|scope|arrays|scalars|blocks|rounded_node_sums|ideal_projection|routing|dependencies"
        ),
    ):
        _fail("wrong top-level pin set")
    var schema = doc.at(pins, "schema")
    if doc.kind(schema) != PY_INT or doc.text(schema) != "3":
        _fail("unsupported pin schema")
    var arrays = doc.at(pins, "arrays")
    var array_spec = doc.at(spec, "arrays")
    if not _same_keys(doc, arrays, _names(doc, array_spec)):
        _fail("wrong constant-array pin set")
    var scalars = doc.at(pins, "scalars")
    var scalar_spec = doc.at(spec, "scalars")
    if not _same_keys(doc, scalars, _names(doc, scalar_spec)):
        _fail("wrong scalar pin set")
    var blocks = doc.at(pins, "blocks")
    var block_paths = doc.at(spec, "block_paths")
    if not _same_keys(doc, blocks, _names(doc, block_paths)):
        _fail("wrong operation-graph pin set")
    var routing = doc.at(pins, "routing")
    var routing_paths = doc.at(spec, "routing_paths")
    if not _same_keys(doc, routing, _names(doc, routing_paths)):
        _fail("wrong routing pin set")
    if not py_equal(
        doc,
        doc.at(pins, "dependencies"),
        doc,
        doc.at(spec, "dependencies"),
    ):
        _fail("wrong dependency closure pin")
    var count = doc.length(arrays)
    var index = 0
    while index < count:
        var name = doc.key(arrays, index)
        var record = doc.value(arrays, index)
        _record_keys(doc, record, "path|words", "wrong array pin keys: " + name)
        var wanted = doc.at(array_spec, name)
        var words = doc.at(record, "words")
        var shape = doc.text(doc.at(record, "path")) != doc.text(
            doc.at(wanted, "path")
        )
        if doc.kind(words) != PY_LIST:
            shape = True
        elif doc.length(words) != Int(doc.text(doc.at(wanted, "size"))):
            shape = True
        if shape:
            _fail("wrong array pin path/shape: " + name)
        index += 1
    var scalar_path = doc.text(doc.at(spec, "scalar_path"))
    count = doc.length(scalars)
    index = 0
    while index < count:
        var name = doc.key(scalars, index)
        var record = doc.value(scalars, index)
        _record_keys(doc, record, "path|word", "wrong scalar pin keys: " + name)
        if doc.text(doc.at(record, "path")) != scalar_path:
            _fail("wrong scalar pin path: " + name)
        index += 1
    var boundaries = doc.at(spec, "boundaries")
    count = doc.length(blocks)
    index = 0
    while index < count:
        var name = doc.key(blocks, index)
        var record = doc.value(blocks, index)
        _record_keys(
            doc,
            record,
            "path|begin|end|normalized_source|sha256",
            "wrong operation pin keys: " + name,
        )
        var boundary = doc.at(boundaries, name)
        if doc.text(doc.at(record, "begin")) != doc.text(
            doc.at(boundary, "begin")
        ) or doc.text(doc.at(record, "end")) != doc.text(
            doc.at(boundary, "end")
        ):
            _fail("wrong source-block boundary pin: " + name)
        if doc.text(doc.at(record, "path")) != doc.text(
            doc.at(block_paths, name)
        ):
            _fail("wrong operation pin path: " + name)
        index += 1
    count = doc.length(routing)
    index = 0
    while index < count:
        var name = doc.key(routing, index)
        var record = doc.value(routing, index)
        _record_keys(
            doc,
            record,
            "path|normalized_tokens|sha256",
            "wrong routing pin keys: " + name,
        )
        if doc.text(doc.at(record, "path")) != doc.text(
            doc.at(routing_paths, name)
        ):
            _fail("wrong routing pin path: " + name)
        index += 1
    if not _same_keys(
        doc,
        doc.at(pins, "ideal_projection"),
        _fixed(
            "legacy_normalized_source|legacy_sha256|helper_projections|rate_half_commutations|projected_ast_sha256|sum2_auxiliary_declarations|sum2_term_definitions|sum2_auxiliary_updates|sum2_error_writes|sum2_environment_guards"
        ),
    ):
        _fail("wrong ideal-projection pin set")


def require_legacy_digest(payload: String) raises:
    """Require the legacy pin digest to match its expected text.

    Args:
        payload: JSON with `actual` and `expected`.

    Raises:
        Error: The digest differs.
    """
    var doc = PyJson.parse(payload)
    if not py_equal(
        doc,
        doc.at(doc.root, "actual"),
        doc,
        doc.at(doc.root, "expected"),
    ):
        _fail("historical ideal pin digest changed")


def require_projection_result(payload: String) raises:
    """Require each projection result pin to match.

    Args:
        payload: JSON with `projection` and `result`. Both objects carry the
            result keys only.

    Raises:
        Error: A result pin differs.
    """
    var doc = PyJson.parse(payload)
    if not py_equal(
        doc,
        doc.at(doc.root, "projection"),
        doc,
        doc.at(doc.root, "result"),
    ):
        _fail("wrong ideal-projection result pins")
