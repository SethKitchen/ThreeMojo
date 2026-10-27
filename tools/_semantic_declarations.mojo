# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read every semantic declaration in one group.

The caller supplies each function and its module text. This check returns
the declarations with postfix move sigils removed.
"""

from tests._python_expr import require_fragment_checks
from tests._python_tokens import semantic_declaration
from tools._python_json import MISSING, PyJson
from tools._semantic_edges import semantic_edge_payload


def semantic_declarations(payload: String) raises -> String:
    """Return one declaration for each requested function.

    Args:
        payload: A JSON list. Each item has `key`, `name`, and `source`.

    Returns:
        A JSON object. Each key is the item key and each value is its
        declaration text.

    Raises:
        Error: A function is missing, or a `^` is not a move sigil.
    """
    var doc = PyJson.parse(payload)
    var out = PyJson()
    var result = out.new_dict()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        var key = doc.text(doc.at(item, "key"))
        out.set(
            result,
            key,
            out.new_str(
                semantic_declaration(
                    doc.text(doc.at(item, "source")),
                    doc.text(doc.at(item, "name")),
                )
            ),
        )
        index += 1
    out.root = result
    return out.dumps()


def _require_labels(
    doc: PyJson,
    declared: PyJson,
    root: Int,
    labels: Int,
    prefix: String,
) raises:
    """Require each labeled declaration to have source text.

    Args:
        doc: The step document.
        declared: The declaration document.
        root: The declaration object.
        labels: A list of `key` and `label`.
        prefix: The contract prefix.

    Raises:
        Error: A declaration is missing. The text is `prefix` plus `label`.
    """
    var count = doc.length(labels)
    var index = 0
    while index < count:
        var item = doc.item(labels, index)
        var key = doc.text(doc.at(item, "key"))
        var node = declared.get(root, key)
        if node == MISSING:
            raise Error(prefix + doc.text(doc.at(item, "label")))
        if declared.text(declared.at(node, "source")) == "":
            raise Error(prefix + doc.text(doc.at(item, "label")))
        index += 1


def semantic_step(payload: String) raises -> String:
    """Bind one group's declarations and check its edges.

    Args:
        payload: JSON with `group`, `items`, `prior`, `bind_labels`,
            `checks`, `edges`, and `prefix`. Each item has `key`, `name`,
            and `source`. `prior` holds declarations from earlier groups.

    Returns:
        A JSON object of the new declaration texts.

    Raises:
        Error: A function is missing, a labeled source is absent, or an
            edge fragment changed.
    """
    var doc = PyJson.parse(payload)
    var items = doc.at(doc.root, "items")
    var declared = PyJson()
    var declared_root = declared.new_dict()
    var count = doc.length(items)
    var index = 0
    while index < count:
        var item = doc.item(items, index)
        var key = doc.text(doc.at(item, "key"))
        var name = doc.text(doc.at(item, "name"))
        var row = declared.new_dict()
        declared.set(row, "name", declared.new_str(name))
        declared.set(
            row,
            "source",
            declared.new_str(
                semantic_declaration(doc.text(doc.at(item, "source")), name)
            ),
        )
        declared.set(declared_root, key, row)
        index += 1
    var prior = doc.at(doc.root, "prior")
    var prior_count = doc.length(prior)
    index = 0
    while index < prior_count:
        var key = doc.key(prior, index)
        if declared.get(declared_root, key) == MISSING:
            var node = doc.at(prior, key)
            var row = declared.new_dict()
            declared.set(
                row, "name", declared.new_str(doc.text(doc.at(node, "name")))
            )
            declared.set(
                row,
                "source",
                declared.new_str(doc.text(doc.at(node, "source"))),
            )
            declared.set(declared_root, key, row)
        index += 1
    var prefix = doc.text(doc.at(doc.root, "prefix"))
    _require_labels(
        doc, declared, declared_root, doc.at(doc.root, "bind_labels"), prefix
    )
    _require_labels(
        doc, declared, declared_root, doc.at(doc.root, "checks"), prefix
    )
    var edges = doc.at(doc.root, "edges")
    var edge_doc = PyJson()
    var edge_root = edge_doc.new_dict()
    var edge_count = doc.length(edges)
    index = 0
    while index < edge_count:
        var key = doc.text(doc.item(edges, index))
        var node = declared.at(declared_root, key)
        var row = edge_doc.new_dict()
        edge_doc.set(
            row,
            "name",
            edge_doc.new_str(declared.text(declared.at(node, "name"))),
        )
        edge_doc.set(
            row,
            "source",
            edge_doc.new_str(declared.text(declared.at(node, "source"))),
        )
        edge_doc.set(edge_root, key, row)
        index += 1
    edge_doc.root = edge_root
    require_fragment_checks(
        semantic_edge_payload(
            doc.text(doc.at(doc.root, "group")), edge_doc.dumps()
        )
    )
    var out = PyJson()
    var result = out.new_dict()
    index = 0
    while index < count:
        var item = doc.item(items, index)
        var key = doc.text(doc.at(item, "key"))
        var node = declared.at(declared_root, key)
        out.set(
            result,
            key,
            out.new_str(declared.text(declared.at(node, "source"))),
        )
        index += 1
    out.root = result
    return out.dumps()
