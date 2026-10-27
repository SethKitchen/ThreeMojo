# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check stored-moment counts, names, and output paths.

The caller resolves paths and supplies the counts. This check compares
those values and does not read the repository.
"""

from tools._python_json import PyJson, py_equal


def _fail(message: String) raises:
    """Raise a guard error.

    Args:
        message: The failure text.

    Raises:
        Error: The guard failed.
    """
    raise Error(message)


def _contains(doc: PyJson, node: Int, name: String) raises -> Bool:
    """Return whether a JSON list contains `name`.

    Args:
        doc: The document.
        node: A list of strings.
        name: The name to find.

    Returns:
        True when one item equals `name`.

    Raises:
        Error: An item cannot be read.
    """
    var count = doc.length(node)
    var index = 0
    while index < count:
        if doc.text(doc.item(node, index)) == name:
            return True
        index += 1
    return False


def _same_names(doc: PyJson, actual: Int, expected: Int) raises -> Bool:
    """Return whether two lists hold the same names.

    Duplicate names count once, as a Python set comparison does.

    Args:
        doc: The document.
        actual: The names that were found.
        expected: The names that are required.

    Returns:
        True when the unique names match.

    Raises:
        Error: An item cannot be read.
    """
    var count = doc.length(actual)
    var index = 0
    while index < count:
        if not _contains(doc, expected, doc.text(doc.item(actual, index))):
            return False
        index += 1
    count = doc.length(expected)
    index = 0
    while index < count:
        if not _contains(doc, actual, doc.text(doc.item(expected, index))):
            return False
        index += 1
    return True


def require_same_count(payload: String) raises:
    """Require two counts to be equal.

    Args:
        payload: JSON with `left`, `right`, and `message`.

    Raises:
        Error: The counts differ. The text is `message`.
    """
    var doc = PyJson.parse(payload)
    if not py_equal(
        doc, doc.at(doc.root, "left"), doc, doc.at(doc.root, "right")
    ):
        _fail(doc.text(doc.at(doc.root, "message")))


def require_name_set(payload: String) raises:
    """Require two name lists to hold the same names.

    Args:
        payload: JSON with `names`, `expected`, and `message`.

    Raises:
        Error: The names differ. The text is `message`.
    """
    var doc = PyJson.parse(payload)
    if not _same_names(
        doc, doc.at(doc.root, "names"), doc.at(doc.root, "expected")
    ):
        _fail(doc.text(doc.at(doc.root, "message")))


def require_member(payload: String) raises:
    """Require one name to be in a list.

    Args:
        payload: JSON with `name`, `names`, and `message`.

    Raises:
        Error: `name` is absent. The text is `message`.
    """
    var doc = PyJson.parse(payload)
    if not _contains(
        doc, doc.at(doc.root, "names"), doc.text(doc.at(doc.root, "name"))
    ):
        _fail(doc.text(doc.at(doc.root, "message")))


def require_separate_output(payload: String) raises:
    """Require every output path to stay outside the repository inputs.

    Args:
        payload: JSON with `destinations` and `protected`. Both are lists of
            resolved path strings.

    Raises:
        Error: One destination is a protected path.
    """
    var doc = PyJson.parse(payload)
    var destinations = doc.at(doc.root, "destinations")
    var protected = doc.at(doc.root, "protected")
    var count = doc.length(destinations)
    var index = 0
    while index < count:
        var destination = doc.text(doc.item(destinations, index))
        var cursor = 0
        var limit = doc.length(protected)
        while cursor < limit:
            if doc.text(doc.item(protected, cursor)) == destination:
                _fail(
                    "generation cannot overwrite repository source; use a"
                    " separate output directory"
                )
            cursor += 1
        index += 1
