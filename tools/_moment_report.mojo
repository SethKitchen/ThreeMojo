# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the stored-moment report from the derived payload and pin bytes.

The payload size and the pin-file count are checked before the report is
returned. Each pin file is hashed as raw bytes.
"""

from tools._json_tools import quote_ascii
from tools._python_json import PY_DICT, PY_LIST, PY_STR, PyJson, py_equal
from tools._sha256 import sha256_hex


comptime _COUNTS = 64
"""The number of stored moment rows."""
comptime _COEFFICIENTS = _COUNTS * 22
"""The number of exact coefficients."""
comptime _WORDS = _COEFFICIENTS * 2
"""The number of stored endpoint words."""
comptime _PAYLOAD_BYTES = _WORDS * 8
"""The derived table payload size, in bytes."""
comptime _ZEROTH_MOMENT = "36028797018963971/36028797018963968"
"""`Fraction(1) + Fraction(3, 1 << 55)`."""


def _fail(message: String) raises:
    """Raise a report error.

    Args:
        message: The failure text.

    Raises:
        Error: The report check failed.
    """
    raise Error(message)


def _dump(doc: PyJson, node: Int) raises -> String:
    """Return JSON in stored key order, with no spaces.

    Args:
        doc: The document.
        node: The value.

    Returns:
        The text `json.dumps` writes with `separators=(',', ':')`.

    Raises:
        Error: A nested list item cannot be read.
    """
    var kind = doc.kind(node)
    if kind == PY_DICT:
        var out = String("{")
        var count = doc.length(node)
        var index = 0
        while index < count:
            if index > 0:
                out += ","
            out += quote_ascii(doc.key(node, index))
            out += ":"
            out += _dump(doc, doc.value(node, index))
            index += 1
        out += "}"
        return out
    if kind == PY_LIST:
        var out = String("[")
        var count = doc.length(node)
        var index = 0
        while index < count:
            if index > 0:
                out += ","
            out += _dump(doc, doc.item(node, index))
            index += 1
        out += "]"
        return out
    if kind == PY_STR:
        return quote_ascii(doc.text(node))
    return doc.text(node)


def moment_report(meta: String, pins: List[List[UInt8]]) raises -> String:
    """Return the stored-moment report.

    Args:
        meta: JSON with `byte_count`, `source_sha256`, `be64_sha256`,
            `root`, `ideal_half_projection`, `dependency_scope`,
            `routing_sha256`, and `source_block_sha256`.
        pins: The three pin files, as raw bytes, in report order.

    Returns:
        The report as compact JSON. Key order matches the historical report.

    Raises:
        Error: The payload size or the pin-file count is wrong.
    """
    var doc = PyJson.parse(meta)
    var count = doc.at(doc.root, "byte_count")
    if not py_equal(doc, count, doc, doc.new_int(_PAYLOAD_BYTES)):
        _fail("wrong derived table shape")
    if len(pins) != 3:
        _fail("wrong derived table shape")
    var report = doc.new_dict()
    doc.set(
        report,
        "scope",
        doc.new_str(
            "fixed-count quadrant-zero ideal stored-polynomial coefficients and"
            " tight endpoints only"
        ),
    )
    doc.set(report, "counts", doc.new_int(_COUNTS))
    doc.set(report, "coefficients", doc.new_int(_COEFFICIENTS))
    doc.set(report, "words", doc.new_int(_WORDS))
    doc.set(report, "payload_bytes", doc.copy_node(count))
    doc.set(report, "zeroth_moment", doc.new_str(_ZEROTH_MOMENT))
    doc.set(
        report,
        "source_sha256",
        doc.copy_node(doc.at(doc.root, "source_sha256")),
    )
    doc.set(
        report,
        "words_be64_sha256",
        doc.copy_node(doc.at(doc.root, "be64_sha256")),
    )
    var labels = List[String]()
    labels.append("pin_file_sha256")
    labels.append("dependency_pin_file_sha256")
    labels.append("environment_guard_pin_sha256")
    var index = 0
    while index < len(pins):
        var label = labels[index]
        var digest = sha256_hex(Span(pins[index]))
        doc.set(report, label, doc.new_str(digest))
        index += 1
    doc.set(
        report,
        "environment_guard_scope",
        doc.new_str(
            "Invocation-local predicate and caller source contracts only; no"
            " native FP-state/codegen qualification"
        ),
    )
    doc.set(
        report, "checked_source_root", doc.copy_node(doc.at(doc.root, "root"))
    )
    doc.set(
        report,
        "ideal_half_projection",
        doc.copy_node(doc.at(doc.root, "ideal_half_projection")),
    )
    doc.set(
        report,
        "dependency_scope",
        doc.copy_node(doc.at(doc.root, "dependency_scope")),
    )
    doc.set(
        report,
        "routing_sha256",
        doc.copy_node(doc.at(doc.root, "routing_sha256")),
    )
    doc.set(
        report,
        "source_block_sha256",
        doc.copy_node(doc.at(doc.root, "source_block_sha256")),
    )
    var omitted = doc.new_list()
    doc.append(omitted, doc.new_str("rounded geometry/error graphs"))
    doc.append(omitted, doc.new_str("branch eligibility"))
    doc.append(omitted, doc.new_str("native execution/codegen"))
    doc.append(omitted, doc.new_str("query correctness/performance"))
    doc.set(report, "not_certified", omitted)
    return _dump(doc, report)


def _copy_sha(mut doc: PyJson, source: Int, dest: Int) raises:
    """Copy each record's `sha256` into `dest`, in stored key order.

    Args:
        doc: The document that holds both objects.
        source: The pin group, keyed by record name.
        dest: The digest object being built.

    Raises:
        Error: A record has no `sha256`. The text is Python's `KeyError`.
    """
    var count = doc.length(source)
    var index = 0
    while index < count:
        var name = doc.key(source, index)
        var record = doc.value(source, index)
        var digest = doc.at(record, "sha256")
        var copied = doc.copy_node(digest)
        doc.set(dest, name, copied)
        index += 1


def moment_meta(payload: String) raises -> String:
    """Return the stored-moment report meta.

    Args:
        payload: JSON with `payload`, `root`, `projection`, `dependencies`,
            `routing`, and `blocks`. `routing` and `blocks` keep their key
            order. Each record contributes its `sha256`.

    Returns:
        Compact JSON for the report meta, in historical field order.

    Raises:
        Error: A required field is missing. The text is Python's `KeyError`.
    """
    var doc = PyJson.parse(payload)
    var source = doc.at(doc.root, "payload")
    var projection = doc.at(doc.root, "projection")
    var meta = doc.new_dict()
    var byte_count = doc.copy_node(doc.at(source, "byte_count"))
    doc.set(meta, "byte_count", byte_count)
    var source_sha = doc.copy_node(doc.at(source, "source_sha256"))
    doc.set(meta, "source_sha256", source_sha)
    var be64_sha = doc.copy_node(doc.at(source, "be64_sha256"))
    doc.set(meta, "be64_sha256", be64_sha)
    var root = doc.copy_node(doc.at(doc.root, "root"))
    doc.set(meta, "root", root)
    var half = doc.new_dict()
    var helpers = doc.copy_node(doc.at(projection, "helper_projections"))
    doc.set(half, "helper_projections", helpers)
    var rates = doc.copy_node(doc.at(projection, "rate_half_commutations"))
    doc.set(half, "rate_half_commutations", rates)
    var projected = doc.copy_node(doc.at(projection, "projected_ast_sha256"))
    doc.set(half, "projected_ast_sha256", projected)
    doc.set(meta, "ideal_half_projection", half)
    var dependencies = doc.copy_node(doc.at(doc.root, "dependencies"))
    doc.set(meta, "dependency_scope", dependencies)
    var routing = doc.new_dict()
    _copy_sha(doc, doc.at(doc.root, "routing"), routing)
    doc.set(meta, "routing_sha256", routing)
    var blocks = doc.new_dict()
    _copy_sha(doc, doc.at(doc.root, "blocks"), blocks)
    doc.set(meta, "source_block_sha256", blocks)
    return _dump(doc, meta)
