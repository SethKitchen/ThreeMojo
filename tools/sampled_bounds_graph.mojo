# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live curve-bounds reference graph.

The count-loop source keeps the reviewed envelope successor. That successor
is replaced by the historical helper. The proof drops the try-only refusal.
A changed graph is refused.
"""

from std.pathlib import Path

from tests._winner_pin_predecessor import restored_count_bounds
from tools._python_json import PY_STR, loads
from tools._sha256 import sha256_hex
from tools.sampled_module_graphs import reference_module_graph


comptime _RECORD = "tools/carla_lane_oracle/envelope-budget-contract.json"
comptime _RECORD_SHA = (
    "c43aa2bfdfb2a33575745eefb44b2f8ff0714a71a31ad750e8c4c0572fa7f2be"
)
comptime _GRAPH = (
    "51f99d745612d217762d8f39bde1ded5b269d239f05cb765532de631cc64791f"
)
comptime _PARAMETER = "    require_reuse: Bool = False,\n"
comptime _REFUSAL = (
    "    elif require_reuse:\n"
    + "        # Optional callers separately reserve their one original"
    " fallback.\n"
    + "        return _unknown_point()\n"
)


def _fail(message: String) raises:
    """Raise a bounds-graph error.

    Args:
        message: The failure text.

    Raises:
        Error: The graph check failed.
    """
    raise Error(message)


def _count(text: String, needle: String) -> Int:
    """Return the number of non-overlapping matches.

    Args:
        text: The source.
        needle: The span to count.

    Returns:
        The number of matches.
    """
    var count = 0
    var offset = 0
    var size = text.byte_length()
    var step = needle.byte_length()
    if step == 0:
        return 0
    while offset < size:
        var rest = String(text[byte=offset:])
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        offset += at + step
    return count


def _once(
    text: String, needle: String, replacement: String, message: String
) raises -> String:
    """Replace one exact span.

    Args:
        text: The source.
        needle: The span to replace.
        replacement: The replacement text.
        message: The failure text when the span is not unique.

    Returns:
        The edited source.

    Raises:
        Error: The span is missing or repeated.
    """
    if _count(text, needle) != 1:
        _fail(message)
    return text.replace(needle, replacement)


def reviewed_bounds_source(
    source: String, before: String, after: String
) raises -> String:
    """Return the reviewed curve-bounds reference source.

    Args:
        source: The count-loop curve-bounds module.
        before: The historical envelope helper.
        after: The reviewed envelope successor.

    Returns:
        The source whose syntax graph is the reference pin.

    Raises:
        Error: The successor, the try-only parameter, or its refusal changed.
    """
    if _count(source, "require_reuse") != 2:
        _fail("try-only flag has an unreviewed use")
    var swapped = _once(
        source,
        after,
        before,
        "Envelope budget successor function changed",
    )
    var unsigned = _once(swapped, _PARAMETER, "", "try-only parameter changed")
    return _once(
        unsigned,
        _REFUSAL,
        "",
        "try-only refusal missing from reuse/fallback edge",
    )


def _root(root: String) -> String:
    """Return `root` without a trailing slash.

    Args:
        root: The repository root.

    Returns:
        The root used to join the record path.
    """
    if root.byte_length() > 1 and root.endswith("/"):
        var end = root.byte_length() - 1
        return String(root[byte=0:end])
    return root


def _record(root: String) raises -> Tuple[String, String]:
    """Return the historical helper and the reviewed successor.

    Args:
        root: The repository root.

    Returns:
        The before function and the after function.

    Raises:
        Error: The record changed or a function field is missing.
    """
    var path = _root(root) + "/" + _RECORD
    var raw = Path(path).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA:
        _fail("Unreviewed envelope budget predecessor record")
    var doc = loads(raw)
    var before_node = doc.at(doc.root, "before_complete_function")
    var after_node = doc.at(doc.root, "after_complete_function")
    if doc.kind(before_node) != PY_STR or doc.kind(after_node) != PY_STR:
        _fail("Unreviewed envelope budget predecessor record")
    return (doc.text(before_node), doc.text(after_node))


def sampled_bounds_graph(root: String) raises:
    """Require the live curve-bounds reference graph.

    Args:
        root: The repository root. The live module is read from the process
            directory by the count-loop restoration.

    Raises:
        Error: The record, the successor, the refusal, or the graph changed.
    """
    var record = _record(root)
    var reviewed = reviewed_bounds_source(
        restored_count_bounds(), record[0], record[1]
    )
    if reference_module_graph(reviewed) != _GRAPH:
        _fail(
            "reference module changed; renewed review required: "
            + "curve_bounds.mojo"
        )
