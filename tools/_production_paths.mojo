# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the production files scanned for containing-model consumers.

The first path part must stay out of the non-production roots. Any hidden
part, including the file name, is left out.
"""

from tools._python_json import PyJson


def _parts(path: String) -> List[String]:
    """Split `path` on `/`, as `str.split` does.

    Args:
        path: A relative path. A leading slash yields an empty first part.

    Returns:
        The parts. An empty path yields one empty part.
    """
    var parts = List[String]()
    var data = path.as_bytes()
    var start = 0
    var index = 0
    while index < len(data):
        if data[index] == 47:
            parts.append(String(path[byte=start:index]))
            start = index + 1
        index += 1
    parts.append(String(path[byte = start : path.byte_length()]))
    return parts^


def _in_roots(part: String, roots: List[String]) -> Bool:
    """Return whether `part` is one of `roots`.

    Args:
        part: One path part.
        roots: The non-production directory names.

    Returns:
        True when `part` equals a root.
    """
    for root in roots:
        if root == part:
            return True
    return False


def _hidden(parts: List[String]) -> Bool:
    """Return whether any part starts with `.`.

    Args:
        parts: The path parts.

    Returns:
        True when a part is hidden.
    """
    for part in parts:
        if part.startswith("."):
            return True
    return False


def keep_production(path: String, roots: List[String]) -> Bool:
    """Return whether one relative path stays in the production scan.

    Args:
        path: A path relative to the repository root.
        roots: The non-production top-level names.

    Returns:
        False when the first part is a non-production root or any part is
        hidden. True otherwise.
    """
    var parts = _parts(path)
    if _in_roots(parts[0], roots) or _hidden(parts):
        return False
    return True


def production_paths(payload: String) raises -> String:
    """Return which relative paths stay in the production scan.

    Args:
        payload: JSON with `roots` and `paths`.

    Returns:
        A JSON list of booleans, one per path, in the same order.

    Raises:
        Error: `roots` or `paths` is missing.
    """
    var doc = PyJson.parse(payload)
    var root_node = doc.at(doc.root, "roots")
    var path_node = doc.at(doc.root, "paths")
    var roots = List[String]()
    var root_count = doc.length(root_node)
    var index = 0
    while index < root_count:
        roots.append(doc.text(doc.item(root_node, index)))
        index += 1
    var out = PyJson()
    var rows = out.new_list()
    var count = doc.length(path_node)
    index = 0
    while index < count:
        var path = doc.text(doc.item(path_node, index))
        var kept = keep_production(path, roots)
        var flag = out.new_bool(kept)
        out.append(rows, flag)
        index += 1
    out.root = rows
    return out.dumps()
