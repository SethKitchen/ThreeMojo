# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the production files scanned for containing-model consumers.

The first path part must stay out of the non-production roots. Any hidden
part, including the file name, is left out.
"""

from std.os import listdir
from std.os.path import isdir, islink

from tools._optional_runtime_messages import optional_runtime_messages
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


def _path_before(left: String, right: String) -> Bool:
    """Return whether `left` sorts before `right` by path parts.

    Args:
        left: A relative path.
        right: A relative path.

    Returns:
        True when the part sequence of `left` is less than `right`.
    """
    var left_parts = _parts(left)
    var right_parts = _parts(right)
    var count = len(left_parts)
    if len(right_parts) < count:
        count = len(right_parts)
    var index = 0
    while index < count:
        if left_parts[index] < right_parts[index]:
            return True
        if right_parts[index] < left_parts[index]:
            return False
        index += 1
    return len(left_parts) < len(right_parts)


def _sort_paths(var items: List[String]) -> List[String]:
    """Sort paths by their parts.

    Args:
        items: The paths, consumed by this call.

    Returns:
        The same paths, in part order.
    """
    for i in range(1, len(items)):
        var j = i
        while j > 0 and _path_before(items[j], items[j - 1]):
            items.swap_elements(j, j - 1)
            j -= 1
    return items^


def _root_names() raises -> List[String]:
    """Return the non-production top-level names.

    Returns:
        The reviewed root names.

    Raises:
        Error: The root list cannot be read.
    """
    var doc = PyJson.parse(nonproduction_roots())
    var roots = List[String]()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        roots.append(doc.text(doc.item(doc.root, index)))
        index += 1
    return roots^


def _collect_production(
    root: String, relative: String, roots: List[String], mut paths: List[String]
) raises:
    """Append kept `.mojo` files below `relative`.

    Args:
        root: The directory being scanned.
        relative: The directory to read, relative to `root`.
        roots: The non-production top-level names.
        paths: The collected paths, appended by this call.

    Raises:
        Error: A directory cannot be read.
    """
    var full = root if relative == "" else root + "/" + relative
    var names = listdir(full)
    for name in names:
        if name == "." or name == "..":
            continue
        var child = full + "/" + name
        var path = name if relative == "" else relative + "/" + name
        if islink(child) and isdir(child):
            continue
        if isdir(child):
            if name.startswith("."):
                continue
            if relative == "" and _in_roots(name, roots):
                continue
            _collect_production(root, path, roots, paths)
        elif path.endswith(".mojo"):
            var parts = _parts(path)
            if _hidden(parts) or _in_roots(parts[0], roots):
                continue
            paths.append(path)


def production_scan(root: String) raises -> String:
    """List the kept production Mojo files in path-part order.

    Args:
        root: The directory to scan.

    Returns:
        A JSON list of relative paths. A directory link is not followed.
        A hidden part or a non-production top-level name is left out.

    Raises:
        Error: A directory cannot be read.
    """
    var paths = List[String]()
    _collect_production(root, "", _root_names(), paths)
    var ordered = _sort_paths(paths^)
    var out = PyJson()
    var rows = out.new_list()
    var index = 0
    while index < len(ordered):
        out.append(rows, out.new_str(ordered[index]))
        index += 1
    out.root = rows
    return out.dumps()


def nonproduction_roots() -> String:
    """Return the non-production top-level names.

    Returns:
        A JSON list in the reviewed order.
    """
    return (
        '["tests","examples","bench","tools","docs","assets","out","coverage",'
        + '"cache","build","node_modules"]'
    )


def reviewed_production_paths(
    paths_json: String, expected: Int
) raises -> String:
    """Read the non-production roots, then choose the production paths.

    Args:
        paths_json: A JSON list of relative paths.
        expected: The number of paths the caller sent.

    Returns:
        A JSON list of booleans, one per path.

    Raises:
        Error: The path list cannot be read, or the flag count differs
            from `expected`. The roots are read before the paths.
    """
    var roots = nonproduction_roots()
    var flags = production_paths(
        '{"roots":' + roots + ',"paths":' + paths_json + "}"
    )
    var doc = PyJson.parse(flags)
    if doc.length(doc.root) != expected:
        var messages = PyJson.parse(optional_runtime_messages())
        raise Error(messages.text(messages.at(messages.root, "paths")))
    return flags
