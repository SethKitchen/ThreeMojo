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
from tools._optional_runtime_messages import optional_runtime_messages
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


def _item_has_key(doc: PyJson, items: Int, key: String) raises -> Bool:
    """Return whether one step binds `key`.

    Args:
        doc: The steps document.
        items: The step's item list.
        key: The declaration key.

    Returns:
        True when an item uses `key`.

    Raises:
        Error: An item has no `key`.
    """
    var count = doc.length(items)
    var index = 0
    while index < count:
        if doc.text(doc.at(doc.item(items, index), "key")) == key:
            return True
        index += 1
    return False


def semantic_steps(payload: String) raises -> String:
    """Bind each group and check its edges, in order.

    Args:
        payload: JSON with `prefix` and `steps`. Each step has `group`,
            `items`, `bind_labels`, `checks`, and `edges`.

    Returns:
        An empty JSON object. The check raises when a group fails.

    Raises:
        Error: A group fails. Earlier groups are checked first.
    """
    var doc = PyJson.parse(payload)
    var steps = doc.at(doc.root, "steps")
    var prefix = doc.text(doc.at(doc.root, "prefix"))
    var memory = PyJson()
    var memory_root = memory.new_dict()
    memory.root = memory_root
    var count = doc.length(steps)
    var index = 0
    while index < count:
        var step = doc.item(steps, index)
        var items = doc.at(step, "items")
        var step_doc = PyJson()
        var step_root = step_doc.new_dict()
        step_doc.set(
            step_root,
            "group",
            step_doc.new_str(doc.text(doc.at(step, "group"))),
        )
        step_doc.set(step_root, "prefix", step_doc.new_str(prefix))
        var copied_items = step_doc.new_list()
        var item_count = doc.length(items)
        var item_index = 0
        while item_index < item_count:
            var item = doc.item(items, item_index)
            var row = step_doc.new_dict()
            step_doc.set(
                row, "key", step_doc.new_str(doc.text(doc.at(item, "key")))
            )
            step_doc.set(
                row, "name", step_doc.new_str(doc.text(doc.at(item, "name")))
            )
            step_doc.set(
                row,
                "source",
                step_doc.new_str(doc.text(doc.at(item, "source"))),
            )
            step_doc.append(copied_items, row)
            item_index += 1
        step_doc.set(step_root, "items", copied_items)
        var labels = doc.at(step, "bind_labels")
        var copied_labels = step_doc.new_list()
        var label_count = doc.length(labels)
        var label_index = 0
        while label_index < label_count:
            var label = doc.item(labels, label_index)
            var row = step_doc.new_dict()
            step_doc.set(
                row, "key", step_doc.new_str(doc.text(doc.at(label, "key")))
            )
            step_doc.set(
                row, "label", step_doc.new_str(doc.text(doc.at(label, "label")))
            )
            step_doc.append(copied_labels, row)
            label_index += 1
        step_doc.set(step_root, "bind_labels", copied_labels)
        var checks = doc.at(step, "checks")
        var copied_checks = step_doc.new_list()
        var check_count = doc.length(checks)
        var check_index = 0
        while check_index < check_count:
            var check = doc.item(checks, check_index)
            var row = step_doc.new_dict()
            step_doc.set(
                row, "key", step_doc.new_str(doc.text(doc.at(check, "key")))
            )
            step_doc.set(
                row, "label", step_doc.new_str(doc.text(doc.at(check, "label")))
            )
            step_doc.append(copied_checks, row)
            check_index += 1
        step_doc.set(step_root, "checks", copied_checks)
        var edges = doc.at(step, "edges")
        var copied_edges = step_doc.new_list()
        var edge_count = doc.length(edges)
        var edge_index = 0
        var prior = step_doc.new_dict()
        while edge_index < edge_count:
            var key = doc.text(doc.item(edges, edge_index))
            step_doc.append(copied_edges, step_doc.new_str(key))
            if not _item_has_key(doc, items, key):
                var remembered = memory.get(memory_root, key)
                if remembered != MISSING:
                    var row = step_doc.new_dict()
                    step_doc.set(
                        row,
                        "name",
                        step_doc.new_str(
                            memory.text(memory.at(remembered, "name"))
                        ),
                    )
                    step_doc.set(
                        row,
                        "source",
                        step_doc.new_str(
                            memory.text(memory.at(remembered, "source"))
                        ),
                    )
                    step_doc.set(prior, key, row)
            edge_index += 1
        step_doc.set(step_root, "edges", copied_edges)
        step_doc.set(step_root, "prior", prior)
        step_doc.root = step_root
        var declared_text = semantic_step(step_doc.dumps())
        var declared = PyJson.parse(declared_text)
        item_index = 0
        while item_index < item_count:
            var item = doc.item(items, item_index)
            var key = doc.text(doc.at(item, "key"))
            var row = memory.new_dict()
            memory.set(
                row, "name", memory.new_str(doc.text(doc.at(item, "name")))
            )
            memory.set(
                row,
                "source",
                memory.new_str(declared.text(declared.at(declared.root, key))),
            )
            memory.set(memory_root, key, row)
            item_index += 1
        index += 1
    return "{}"


def _prefixed_runtime_error(message: String) raises -> String:
    """Add the contract prefix when a step failure still needs it.

    Args:
        message: The step failure.

    Returns:
        The message callers see after the contract check.

    Raises:
        Error: The contract messages cannot be read.
    """
    var messages = PyJson.parse(optional_runtime_messages())
    var prefix = messages.text(messages.at(messages.root, "prefix"))
    var move = messages.text(messages.at(messages.root, "move"))
    var fragment = messages.text(messages.at(messages.root, "fragment"))
    if message == move:
        return prefix + message
    if message.startswith(fragment) and not message.startswith(prefix):
        return prefix + message
    return message


def semantic_steps_with_contract(payload: String) raises -> String:
    """Read the contract messages, then check the semantic steps.

    Args:
        payload: JSON with `steps`. Each step has `group`, `items`,
            `bind_labels`, `checks`, and `edges`. The contract supplies
            `prefix`.

    Returns:
        An empty JSON object. The check raises when a group fails.

    Raises:
        Error: A group fails. The contract messages are read before the
            steps. A move or fragment failure keeps its contract prefix.
    """
    var messages = PyJson.parse(optional_runtime_messages())
    var doc = PyJson.parse(payload)
    doc.set(
        doc.root,
        "prefix",
        doc.new_str(messages.text(messages.at(messages.root, "prefix"))),
    )
    try:
        return semantic_steps(doc.dumps())
    except error:
        raise Error(_prefixed_runtime_error(String(error)))
