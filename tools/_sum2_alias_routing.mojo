# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live Sum2 alias routing.

Four caller modules keep the road-info alias. Restoring that alias matches
the pinned routing. A bare import or a changed routing is refused.
"""

from std.pathlib import Path

from tools._python_json import PY_STR, PyJson
from tools._sum2_guard_callers import _routing


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _ALIAS = (
    "from extensions.carla.road_info import _info_index_si as info_index\n"
)
comptime _BARE = "from extensions.carla.road_info import info_index\n"


def _fail(message: String) raises:
    """Raise an alias-routing error.

    Args:
        message: The failure text.

    Raises:
        Error: The live alias routing changed.
    """
    raise Error(message)


def _message(module: String) -> String:
    """Return the routing failure for `module`.

    Args:
        module: The caller module.

    Returns:
        The failure text.
    """
    return "Sum2 guard import/declaration routing changed: " + module


def _count(text: String, needle: String) -> Int:
    """Return how many times `needle` occurs in `text`.

    Args:
        text: The source.
        needle: The exact byte sequence.

    Returns:
        The number of non-overlapping matches.
    """
    var count = 0
    var offset = 0
    var size = text.byte_length()
    var step = needle.byte_length()
    while offset < size:
        var rest = String(text[byte=offset:])
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        offset += at + step
    return count


def _modules() -> List[String]:
    """Return the caller modules whose routing keeps the road-info alias.

    Returns:
        The module names.
    """
    var names = List[String]()
    names.append("curve_bounds")
    names.append("spiral_domain_proof")
    names.append("curve_sample_dispatch")
    names.append("spiral_grouped_lane")
    return names^


def sum2_alias_routing(root: String) raises:
    """Require the live Sum2 alias routing.

    Args:
        root: The repository root.

    Raises:
        Error: A road-info alias or a pinned routing changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    var callers = doc.at(doc.root, "callers")
    var modules = _modules()
    var index = 0
    while index < len(modules):
        var module = modules[index]
        var record = doc.at(callers, module)
        var routing = doc.at(record, "routing")
        if doc.kind(routing) != PY_STR:
            _fail(_message(module))
        var path = base + "/extensions/carla/" + module + ".mojo"
        var source = Path(path).read_text()
        if _count(source, _ALIAS) != 1:
            _fail(_message(module))
        var restored = source.replace(_ALIAS, _BARE)
        if _routing(restored) != doc.text(routing):
            _fail(_message(module))
        index += 1
