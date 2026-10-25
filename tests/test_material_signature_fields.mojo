# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Every stored material field participates in the batch signature."""

from std.collections import Set
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true


def _slice(text: String, begin: String, end: String) raises -> String:
    """Return the text after `begin` and before `end`.

    Args:
        text: The source.
        begin: The opening marker.
        end: The closing marker.

    Returns:
        The text between the markers.

    Raises:
        Error: If a marker is absent.
    """
    var start = text.find(begin)
    if start < 0:
        raise Error("missing " + begin)
    var rest = String(text[byte = start + begin.byte_length() :])
    var stop = rest.find(end)
    if stop < 0:
        raise Error("missing " + end)
    return String(rest[byte=:stop])


def _is_name(byte: Int) -> Bool:
    """Return whether `byte` can continue an identifier."""
    var letter = (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
    var digit = byte >= 48 and byte <= 57
    return letter or digit or byte == 95


def _fields(body: String) -> Set[String]:
    """Return each `var` name declared at the struct's indent."""
    var found = Set[String]()
    var line = String()
    var bytes = body.as_bytes()
    var index = 0
    while index <= len(bytes):
        var done = index == len(bytes) or bytes[index] == 10
        if done:
            if line.startswith("    var "):
                var name = String()
                var cursor = 8
                var raw = line.as_bytes()
                while cursor < len(raw) and _is_name(Int(raw[cursor])):
                    name += chr(Int(raw[cursor]))
                    cursor += 1
                if (
                    cursor < len(raw)
                    and raw[cursor] == 58
                    and name.byte_length() > 0
                ):
                    found.add(name)
            line = String()
        else:
            line += chr(Int(bytes[index]))
        index += 1
    return found^


def _mentioned(signature: String) -> Set[String]:
    """Return each identifier that follows `material.`."""
    var found = Set[String]()
    var needle = "material."
    var bytes = signature.as_bytes()
    var index = 0
    while index < len(bytes):
        var matched = True
        var offset = 0
        while offset < needle.byte_length():
            if (
                index + offset >= len(bytes)
                or bytes[index + offset] != needle.as_bytes()[offset]
            ):
                matched = False
                break
            offset += 1
        if matched:
            var cursor = index + needle.byte_length()
            var name = String()
            while cursor < len(bytes) and _is_name(Int(bytes[cursor])):
                name += chr(Int(bytes[cursor]))
                cursor += 1
            if name.byte_length() > 0:
                found.add(name)
            index = cursor
            continue
        index += 1
    return found^


def test_every_material_field_is_in_the_batch_signature() raises:
    """A new material field must join `material_signature`."""
    var material = Path("materials/material.mojo").read_text()
    var body = _slice(
        material,
        "struct Material(ImplicitlyCopyable):",
        "    def __init__",
    )
    var optimizer = Path("core/scene_optimizer.mojo").read_text()
    var signature = _slice(
        optimizer, "def material_signature(", "def attributes_signature("
    )
    var fields = _fields(body)
    var represented = _mentioned(signature)
    assert_equal(len(fields), len(represented))
    for name in fields:
        assert_true(name in represented, name)
    for component in [
        "line_width.world_units",
        "scattering.map",
        "scattering.power",
        "env_map_rotation.order.first",
        "color.a",
    ]:
        assert_true(signature.find("material." + component) >= 0, component)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
