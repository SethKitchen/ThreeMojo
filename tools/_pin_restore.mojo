# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Rebuild one reviewed pin predecessor.

The caller supplies the active pin bytes and the request. This module does
not read the repository.
"""

from tools._carla_assets import dumps_indent
from tools._duplicate_pin_keys import reject_duplicate_pin_keys
from tools._python_json import PyJson, loads
from tools._sha256 import sha256_hex


def _prefixed(prefix: String, message: String) raises:
    """Raise one prefixed pin failure.

    Args:
        prefix: The contract prefix, including the colon and the space.
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error(prefix + message)


def _joined_pointer(request: PyJson, pointer: Int) raises -> String:
    """Join one pointer into a single lookup key.

    Args:
        request: The predecessor request.
        pointer: The pointer list.

    Returns:
        The parts separated by newlines.

    Raises:
        Error: A pointer part cannot be read.
    """
    var key = String("")
    var count = request.length(pointer)
    var index = 0
    while index < count:
        if index > 0:
            key += "\n"
        key += request.text(request.item(pointer, index))
        index += 1
    return key


def _pin_at(pins: PyJson, request: PyJson, pointer: Int) raises -> String:
    """Return the string at one pin pointer.

    Args:
        pins: The active pin document.
        request: The predecessor request.
        pointer: The pointer list.

    Returns:
        The current string at that pointer.

    Raises:
        Error: A pointer key is absent.
    """
    var node = pins.root
    var count = request.length(pointer)
    var index = 0
    while index < count:
        node = pins.at(node, request.text(request.item(pointer, index)))
        index += 1
    return pins.text(node)


def _require_pin_places(
    pins: PyJson, request: PyJson, transitions: Int, prefix: String
) raises:
    """Require each pin placement to be unique and current.

    Args:
        pins: The active pin document.
        request: The predecessor request.
        transitions: The transition list in `request`.
        prefix: The contract prefix, including the colon and the space.

    Raises:
        Error: A placement is repeated, its current value changed, or a
            pointer key is absent.
    """
    var seen = List[String]()
    var duplicates = List[Bool]()
    var actuals = List[String]()
    var expecteds = List[String]()
    var count = request.length(transitions)
    var index = 0
    while index < count:
        var change = request.item(transitions, index)
        var pointer = request.at(change, "pointer")
        var key = _joined_pointer(request, pointer)
        var duplicate = False
        var seen_index = 0
        while seen_index < len(seen):
            if seen[seen_index] == key:
                duplicate = True
            seen_index += 1
        var actual = String("")
        if not duplicate:
            actual = _pin_at(pins, request, pointer)
            seen.append(key)
        duplicates.append(duplicate)
        actuals.append(actual)
        expecteds.append(request.text(request.at(change, "after")))
        index += 1
    index = 0
    while index < len(duplicates):
        if duplicates[index]:
            _prefixed(prefix, "duplicate pin placement")
        if actuals[index] != expecteds[index]:
            _prefixed(prefix, "active pin placement mismatch")
        index += 1


def _write_pin_transitions(
    mut pins: PyJson, request: PyJson, transitions: Int
) raises:
    """Write each transition's historical value back into the pins.

    Args:
        pins: The active pin document.
        request: The predecessor request.
        transitions: The transition list in `request`.

    Raises:
        Error: A pointer is empty or a pointer key is absent.
    """
    var count = request.length(transitions)
    var index = 0
    while index < count:
        var change = request.item(transitions, index)
        var pointer = request.at(change, "pointer")
        var parts = request.length(pointer)
        if parts == 0:
            raise Error("pin transition pointer is empty")
        var parent = pins.root
        var cursor = 0
        while cursor < parts - 1:
            parent = pins.at(
                parent, request.text(request.item(pointer, cursor))
            )
            cursor += 1
        pins.set(
            parent,
            request.text(request.item(pointer, parts - 1)),
            pins.adopt(request, request.at(change, "before")),
        )
        index += 1


def restore_reviewed_pin(
    payload: Span[UInt8, _],
    request: String,
    prefix: String,
    before_failure: String,
) raises -> String:
    """Rebuild one reviewed pin predecessor.

    Args:
        payload: The active pin bytes.
        request: JSON with `after`, `before`, `label`, and `transitions`.
        prefix: The contract prefix, including the colon and the space.
        before_failure: The restored-digest failure, without the prefix.

    Returns:
        The predecessor as `json.dumps` writes it with `indent=2`, plus a
        newline.

    Raises:
        Error: The digest, a repeated key, a placement, or the restored
            bytes changed. The digest is checked before a repeated key. A
            repeated key is refused before the pin is placed. The restored
            digest is checked after the placements.
    """
    var spec = PyJson.parse(request)
    var after = spec.text(spec.at(spec.root, "after"))
    var label = spec.text(spec.at(spec.root, "label"))
    if sha256_hex(payload) != after:
        _prefixed(prefix, "unreviewed runtime pin successor: " + label)
    reject_duplicate_pin_keys(payload)
    var pins = loads(payload)
    var transitions = spec.at(spec.root, "transitions")
    _require_pin_places(pins, spec, transitions, prefix)
    _write_pin_transitions(pins, spec, transitions)
    var predecessor = dumps_indent(pins, pins.root, 2) + "\n"
    var before = spec.text(spec.at(spec.root, "before"))
    if sha256_hex(predecessor.as_bytes()) != before:
        _prefixed(prefix, before_failure)
    return predecessor
