# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Rebuild one selection predecessor from its reviewed declaration.

The caller supplies the producer text and the recorded function. This
check does not read the repository.
"""

from tests._python_tokens import (
    declaration_bounds_json,
    replace_line_span,
    require_same_text,
    significant_json,
)
from tools._moment_guards import require_member, require_name_set
from tools._python_json import PyJson
from tools.carla_selection_record_gate import selection_restored


def _copy_strings(
    mut destination: PyJson, rows: Int, source: PyJson, node: Int
) raises:
    """Copy a JSON list of strings into `rows`.

    Args:
        destination: The document that owns `rows`.
        rows: The destination list.
        source: The document that owns `node`.
        node: A list of strings.

    Raises:
        Error: An item cannot be read.
    """
    var count = source.length(node)
    var index = 0
    while index < count:
        destination.append(
            rows, destination.new_str(source.text(source.item(node, index)))
        )
        index += 1


def _names_payload(
    source: PyJson,
    names: Int,
    expected: Int,
    message: String,
) raises -> String:
    """Return one name-set guard payload.

    Args:
        source: The predecessor document.
        names: The names that were found.
        expected: The names that are required.
        message: The failure text.

    Returns:
        The JSON payload for `require_name_set`.

    Raises:
        Error: A name cannot be read.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    var found = doc.new_list()
    var wanted = doc.new_list()
    _copy_strings(doc, found, source, names)
    _copy_strings(doc, wanted, source, expected)
    doc.set(root, "names", found)
    doc.set(root, "expected", wanted)
    doc.set(root, "message", doc.new_str(message))
    doc.root = root
    return doc.dumps()


def _member_payload(
    name: String, source: PyJson, names: Int, message: String
) raises -> String:
    """Return one membership guard payload.

    Args:
        name: The module path.
        source: The predecessor document.
        names: The allowed module paths.
        message: The failure text.

    Returns:
        The JSON payload for `require_member`.

    Raises:
        Error: A name cannot be read.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    var wanted = doc.new_list()
    _copy_strings(doc, wanted, source, names)
    doc.set(root, "name", doc.new_str(name))
    doc.set(root, "names", wanted)
    doc.set(root, "message", doc.new_str(message))
    doc.root = root
    return doc.dumps()


def selection_predecessor(payload: String) raises -> String:
    """Return the module with one reviewed function restored.

    Args:
        payload: JSON with `path`, `names`, `record_names`, `message`,
            `body_message`, `name`, `text`, `after`, `before`, and `token`.

    Returns:
        The producer text after the recorded function replaces the live one.

    Raises:
        Error: The path is unreviewed, the declaration changed, or the
            restored token changed.
    """
    var doc = PyJson.parse(payload)
    var path = doc.text(doc.at(doc.root, "path"))
    var message = doc.text(doc.at(doc.root, "message"))
    require_member(
        _member_payload(path, doc, doc.at(doc.root, "names"), message)
    )
    require_name_set(
        _names_payload(
            doc,
            doc.at(doc.root, "record_names"),
            doc.at(doc.root, "names"),
            message,
        )
    )
    var text = doc.text(doc.at(doc.root, "text"))
    var name = doc.text(doc.at(doc.root, "name"))
    var owners = List[String]()
    var bounds = PyJson.parse(declaration_bounds_json(text, name, owners))
    var body = bounds.text(bounds.at(bounds.root, "text"))
    require_same_text(
        significant_json(body),
        significant_json(doc.text(doc.at(doc.root, "after"))),
        doc.text(doc.at(doc.root, "body_message")),
    )
    var restored = replace_line_span(
        text,
        Int(bounds.text(bounds.at(bounds.root, "first"))),
        Int(bounds.text(bounds.at(bounds.root, "last"))),
        doc.text(doc.at(doc.root, "before")),
    )
    selection_restored(restored, doc.text(doc.at(doc.root, "token")))
    return restored
