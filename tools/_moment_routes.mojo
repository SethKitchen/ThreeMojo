# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check every stored-moment route.

The caller checks digests before it reads the sources. It then builds
each live routing document and compares that document with its pin.
"""

from tests._python_tokens import module_routing_json, require_text_digest
from tools._moment_route import _routing_constants, moment_route_accept
from tools._python_json import PyJson


def moment_route_digests(payload: String) raises:
    """Require each pinned routing document to match its digest.

    Args:
        payload: A JSON list. Each item has `text`, `digest`, and
            `message`.

    Raises:
        Error: A digest disagrees. The text is that item's `message`.
    """
    var doc = PyJson.parse(payload)
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        require_text_digest(
            doc.text(doc.at(item, "text")),
            doc.text(doc.at(item, "digest")),
            doc.text(doc.at(item, "message")),
        )
        index += 1


def moment_route_currents(payload: String) raises -> String:
    """Return the live routing document for each source.

    Args:
        payload: A JSON list. Each item has `name` and `source`.

    Returns:
        A JSON object. Each key is a route name and each value is its
        routing document.

    Raises:
        Error: A source routing is unsupported.
    """
    var doc = PyJson.parse(payload)
    var constants = _routing_constants()
    var out = PyJson()
    var result = out.new_dict()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        var name = doc.text(doc.at(item, "name"))
        out.set(
            result,
            name,
            out.new_str(
                module_routing_json(doc.text(doc.at(item, "source")), constants)
            ),
        )
        index += 1
    out.root = result
    return out.dumps()


def moment_route_accepts(payload: String) raises:
    """Require each live routing document to match its pin.

    Args:
        payload: A JSON list. Each item has `current`, `expected`,
            `message`, and `strip`.

    Raises:
        Error: A document differs, or a try-only parameter is not the
            reviewed shape. The text is that item's `message`, or the
            try-only failure.
    """
    var doc = PyJson.parse(payload)
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        moment_route_accept(
            doc.text(doc.at(item, "current")),
            doc.text(doc.at(item, "expected")),
            doc.text(doc.at(item, "message")),
            doc.flag(doc.at(item, "strip")),
        )
        index += 1
