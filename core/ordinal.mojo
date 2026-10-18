# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whether an integer names an entry in a closed range.

A named id stores an integer. Zero is the first name. `last` is the
last name. A value outside that range is not a name. Each id keeps its
own type. `index_in_count` is true from zero through one below a count.
`require_index_in_count` refuses an index outside that range.
`require_non_negative` refuses an integer, a Float32, or a Float64 below zero.
Callers keep their own error text. `require_draw_ids` refuses a negative
node, geometry, and material, and builds the three messages from one label.
`ordinal_label` returns a name from a list, or a fallback when the
value is not valid. `require_valid` refuses a false validity flag.
"""


def ordinal_valid(value: Int, last: Int) -> Bool:
    """Return True when `value` names an entry from zero through `last`.

    Args:
        value: The stored ordinal.
        last: The value of the last named entry. A count is one past this.

    Returns:
        True when `value` is from zero through `last`.
    """
    if value < 0:
        return False
    return value <= last


def index_in_count(index: Int, count: Int) -> Bool:
    """Return True when `index` is from zero through one below `count`.

    Args:
        index: The place to test.
        count: How many entries the list holds.

    Returns:
        True when `index` is at least zero and below `count`.

    Raises:
        Error: Never.
    """
    return index >= 0 and index < count


def require_index_in_count(index: Int, count: Int, message: String) raises:
    """Refuse an index that does not name an entry.

    Args:
        index: The place to test.
        count: How many entries the list holds.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when `index` names an entry.

    Raises:
        Error: If `index` is negative or not less than `count`.
    """
    if not index_in_count(index, count):
        raise Error(message)


def require_non_negative(value: Int, message: String) raises:
    """Refuse a value below zero.

    Args:
        value: The stored integer.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when `value` is zero or more.

    Raises:
        Error: If `value` is below zero.
    """
    if value < 0:
        raise Error(message)


def require_non_negative(value: Float32, message: String) raises:
    """Refuse a Float32 below zero.

    Args:
        value: The stored number.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when `value` is zero or more.

    Raises:
        Error: If `value` is below zero.
    """
    if value < 0:
        raise Error(message)


def require_non_negative(value: Float64, message: String) raises:
    """Refuse a Float64 below zero.

    Args:
        value: The stored number.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when `value` is zero or more.

    Raises:
        Error: If `value` is below zero.
    """
    if value < 0:
        raise Error(message)


def require_draw_ids(
    node: Int, geometry: Int, material: Int, label: String
) raises:
    """Refuse a negative node, geometry, or material id.

    Args:
        node: The scene node id.
        geometry: The geometry id.
        material: The material id.
        label: The words that start each message, such as `A line`.

    Returns:
        Nothing. The call returns when every id is zero or more.

    Raises:
        Error: If `node`, `geometry`, or `material` is below zero.
    """
    require_non_negative(node, label + " must name a scene node")
    require_non_negative(geometry, label + " must name a geometry")
    require_non_negative(material, label + " must name a material")


def ordinal_label(
    valid: Bool, value: Int, names: List[String], fallback: String
) -> String:
    """Return the name at `value`, or `fallback` when `valid` is false.

    Args:
        valid: Whether `value` names an entry of `names`.
        value: The index into `names` when `valid` is true.
        names: The names, in order.
        fallback: The name when `valid` is false.

    Returns:
        `names[value]` when `valid` is true, and `fallback` otherwise.

    Raises:
        Error: Never.
    """
    if not valid:
        return fallback
    return names[value]


def require_valid(valid: Bool, message: String) raises:
    """Refuse a false validity flag.

    Args:
        valid: Whether the value is one of the named ones.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when `valid` is true.

    Raises:
        Error: If `valid` is false.
    """
    if not valid:
        raise Error(message)
