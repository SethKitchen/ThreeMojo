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
from tools._python_json import MISSING, PyJson
from tools._roundoff_name import roundoff_envelope_name
from tools.carla_selection_record_gate import selection_record, selection_restored


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
            `body_message`, `text`, `after`, `before`, and `token`.
            `name` is optional. When it is absent, the roundoff envelope
            name is chosen from `path`.

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
    var name_node = doc.get(doc.root, "name")
    var name = roundoff_envelope_name(path)
    if name_node != MISSING:
        name = doc.text(name_node)
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


def _selection_module(record: String, path: String) raises -> Int:
    """Return the record entry for `path`.

    Args:
        record: The selection predecessor record.
        path: The producer path.

    Returns:
        The JSON node for that module. The parsed document is not returned;
        the caller parses `record` again.

    Raises:
        Error: The record digest changed, or `path` is not in the record.
            The digest is checked before the path.
    """
    selection_record(record.as_bytes())
    var doc = PyJson.parse(record)
    var modules = doc.at(doc.root, "modules")
    var index = 0
    var count = doc.length(modules)
    while index < count:
        if doc.key(modules, index) == path:
            return modules
        index += 1
    raise Error("KeyError: " + path)


def selection_record_path(record: String, path: String) raises:
    """Require `path` to be in the selection record.

    Args:
        record: The selection predecessor record.
        path: The producer path.

    Raises:
        Error: The record digest changed, or `path` is not in the record.
            The digest is checked before the path.
    """
    _ = _selection_module(record, path)


def selection_from_record(record: String, path: String, text: String) raises -> String:
    """Restore one producer from the selection record.

    Args:
        record: The selection predecessor record.
        path: The producer path.
        text: The live producer source.

    Returns:
        The producer text after the recorded function replaces the live one.

    Raises:
        Error: The record digest changed, `path` is absent, the declaration
            changed, or the restored token changed. The digest is checked
            before the path.
    """
    _ = _selection_module(record, path)
    var doc = PyJson.parse(record)
    var modules = doc.at(doc.root, "modules")
    var item = doc.at(modules, path)
    var payload = PyJson()
    var root = payload.new_dict()
    payload.set(root, "path", payload.new_str(path))
    var names = payload.new_list()
    payload.append(
        names,
        payload.new_str("extensions/carla/spiral_grouped_roundoff_proof.mojo"),
    )
    payload.append(
        names, payload.new_str("extensions/carla/spiral_roundoff_proof.mojo")
    )
    payload.set(root, "names", names)
    var record_names = payload.new_list()
    var index = 0
    var count = doc.length(modules)
    while index < count:
        payload.append(record_names, payload.new_str(doc.key(modules, index)))
        index += 1
    payload.set(root, "record_names", record_names)
    payload.set(
        root, "message", payload.new_str("Wrong selection predecessor module")
    )
    payload.set(
        root,
        "body_message",
        payload.new_str("Selection complete successor body changed"),
    )
    payload.set(root, "text", payload.new_str(text))
    payload.set(
        root,
        "after",
        payload.new_str(doc.text(doc.at(item, "after_complete_function"))),
    )
    payload.set(
        root,
        "before",
        payload.new_str(doc.text(doc.at(item, "before_complete_function"))),
    )
    payload.set(
        root,
        "token",
        payload.new_str(doc.text(doc.at(item, "before_token_sha256"))),
    )
    payload.root = root
    return selection_predecessor(payload.dumps())
