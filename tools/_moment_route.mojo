# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check one stored-moment routing document.

The route uses the reviewed array and scalar names. The ideal caller can
strip its try-only parameter after the caller has checked that refusal.
"""

from tests._python_tokens import (
    module_routing_json,
    require_same_text,
    strip_try_only_routing,
)
from tools._moment_pin_spec import moment_pin_spec
from tools._python_json import PyJson


def _routing_constants() raises -> String:
    """Return the sorted array and scalar names.

    Returns:
        A JSON list of comptime names, in Python's sorted order.

    Raises:
        Error: The pin specification cannot be built.
    """
    var spec = PyJson.parse(moment_pin_spec('{"dependencies":{}}'))
    var names = List[String]()
    var groups = List[String]()
    groups.append("arrays")
    groups.append("scalars")
    for group in groups:
        var node = spec.at(spec.root, group)
        var count = spec.length(node)
        var index = 0
        while index < count:
            var name = spec.key(node, index)
            var place = 0
            while place < len(names) and names[place] < name:
                place += 1
            names.insert(place, name)
            index += 1
    var doc = PyJson()
    var rows = doc.new_list()
    for name in names:
        doc.append(rows, doc.new_str(name))
    doc.root = rows
    return doc.dumps()


def moment_route_current(source: String) raises -> String:
    """Return the live routing document for the reviewed constant names.

    Args:
        source: The live module.

    Returns:
        The canonical routing document for `source`.

    Raises:
        Error: The source routing is unsupported.
    """
    return module_routing_json(source, _routing_constants())


def moment_route_accept(
    current: String, expected: String, message: String, strip: Bool
) raises:
    """Require the live routing document to match its pin.

    Args:
        current: The live routing document.
        expected: The pinned routing document.
        message: The mismatch text.
        strip: When true, remove the try-only parameter before the comparison.

    Raises:
        Error: The texts differ, or the try-only parameter is not the reviewed
            shape.
    """
    var text = current
    if strip:
        text = strip_try_only_routing(current)
    require_same_text(text, expected, message)
