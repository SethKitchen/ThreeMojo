# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The accepted successor keeps its three modules and its pin reconstruction."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import token_sha256
from tools._python_json import PY_DICT, PY_INT, PY_LIST, PY_STR, PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/accepted-successor-migration.json"
"""The reviewed accepted successor record."""
comptime _RECORD_SHA256 = (
    "bb3a7b5e08a0a5400679f410da2c4574b45924294133df2f180f71fd74064d91"
)
"""The SHA-256 of that record."""
comptime _FOLLOWUP = "tools/carla_lane_oracle/coverage-followup-migration.json"
"""The followup record the pin reconstruction must reach."""
comptime _ORACLE = "tools/carla_lane_oracle/"
"""The directory that holds the component records and the pin files."""
comptime _LINE = "extensions/carla/curve_rounded_line.mojo"
"""The rounded line successor."""
comptime _DOMAIN = "extensions/carla/spiral_domain_proof.mojo"
"""The domain successor."""
comptime _GROUPED = "extensions/carla/spiral_grouped_roundoff_proof.mojo"
"""The grouped roundoff successor."""
comptime _LINE_LIVE_SHA256 = (
    "22b70ec9febc6f3d21a8a4d9f1a74650d676e34782fab2812004a1a3aadeb698"
)
"""The file digest of the live rounded line module."""
comptime _DOMAIN_LIVE_SHA256 = (
    "a641d554b2c2a3fe5d64bbfed9c4d5b10ac71858e13cd3c35c9619a7766720e9"
)
"""The file digest of the live domain module."""
comptime _LIVE_IMPORT = (
    "from extensions.carla.road_info import _info_index_si as info_index\n"
)
"""The live import the admitted modules do not use."""
comptime _ADMITTED_IMPORT = (
    "from extensions.carla.road_info import info_index\n"
)
"""The import the admitted modules use."""


def _field(doc: PyJson, node: Int, name: String) raises -> String:
    """Return one string field.

    Args:
        doc: The document.
        node: The object.
        name: The field name.

    Returns:
        The field text.

    Raises:
        Error: The field is absent.
    """
    return doc.text(doc.at(node, name))


def _count(text: String, needle: String) -> Int:
    """Return how many times `needle` occurs.

    Args:
        text: The source.
        needle: The fragment.

    Returns:
        The number of matches.
    """
    var count = 0
    var rest = text
    while True:
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        var tail = String(rest[byte = at + needle.byte_length() :])
        rest = tail


def _replace_first(
    text: String, before: String, after: String
) raises -> String:
    """Replace the first occurrence of `before`.

    Args:
        text: The source.
        before: The original fragment.
        after: The replacement.

    Returns:
        The changed source.

    Raises:
        Error: `before` is missing.
    """
    var at = text.find(before)
    if at < 0:
        raise Error("missing accepted successor fragment")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _byte(mut out: List[UInt8], value: Int):
    """Append one ASCII byte.

    Args:
        out: The bytes being written.
        value: The byte value.
    """
    out.append(UInt8(value))


def _text(mut out: List[UInt8], text: String):
    """Append the bytes of `text`.

    Args:
        out: The bytes being written.
        text: The ASCII text.
    """
    var data = text.as_bytes()
    for byte in data:
        out.append(byte)


def _hex(mut out: List[UInt8], unit: Int):
    """Append four lowercase hex digits.

    Args:
        out: The bytes being written.
        unit: A value from 0 through 65535.
    """
    var digits = "0123456789abcdef".as_bytes()
    var shift = 12
    while shift >= 0:
        out.append(digits[(unit >> shift) & 15])
        shift -= 4


def _quote(mut out: List[UInt8], text: String) raises:
    """Append `text` as `json.dumps` writes a string.

    Args:
        out: The bytes being written.
        text: The string.

    Raises:
        Error: `text` contains a byte outside ASCII.
    """
    _byte(out, 34)
    var data = text.as_bytes()
    for byte in data:
        var value = Int(byte)
        if value == 34 or value == 92:
            _byte(out, 92)
            _byte(out, value)
        elif value == 8:
            _text(out, "\\b")
        elif value == 12:
            _text(out, "\\f")
        elif value == 10:
            _text(out, "\\n")
        elif value == 13:
            _text(out, "\\r")
        elif value == 9:
            _text(out, "\\t")
        elif value < 32 or value > 126:
            if value > 127:
                raise Error("accepted source successor: non-ASCII pin text")
            _text(out, "\\u")
            _hex(out, value)
        else:
            _byte(out, value)
    _byte(out, 34)


def _pad(mut out: List[UInt8], level: Int):
    """Append `level` indent steps of two spaces.

    Args:
        out: The bytes being written.
        level: The nesting depth.
    """
    var index = 0
    while index < level:
        _byte(out, 32)
        _byte(out, 32)
        index += 1


def _dump(doc: PyJson, node: Int, level: Int, mut out: List[UInt8]) raises:
    """Append one value as `json.dumps` writes it with indent 2.

    Args:
        doc: The document.
        node: The value.
        level: The nesting depth.
        out: The bytes being written.

    Raises:
        Error: The value is not an object, a list, a string, or an int.
    """
    var kind = doc.kind(node)
    if kind == PY_DICT or kind == PY_LIST:
        var count = doc.length(node)
        if count == 0:
            _text(out, "{}" if kind == PY_DICT else "[]")
            return
        _byte(out, 123 if kind == PY_DICT else 91)
        var index = 0
        while index < count:
            _byte(out, 10)
            _pad(out, level + 1)
            if kind == PY_DICT:
                _quote(out, doc.key(node, index))
                _text(out, ": ")
                _dump(doc, doc.value(node, index), level + 1, out)
            else:
                _dump(doc, doc.item(node, index), level + 1, out)
            if index + 1 < count:
                _byte(out, 44)
            index += 1
        _byte(out, 10)
        _pad(out, level)
        _byte(out, 125 if kind == PY_DICT else 93)
        return
    if kind == PY_STR:
        _quote(out, doc.text(node))
        return
    if kind == PY_INT:
        _text(out, doc.text(node))
        return
    raise Error("accepted source successor: unsupported pin value")


def _indented(doc: PyJson) raises -> String:
    """Return the document as `json.dumps(value, indent=2)` plus a newline.

    Args:
        doc: The document.

    Returns:
        The file text.

    Raises:
        Error: A value cannot be written.
    """
    var out = List[UInt8]()
    _dump(doc, doc.root, 0, out)
    _byte(out, 10)
    return String(unsafe_from_utf8=Span(out))


def _record() raises -> PyJson:
    """Return the accepted successor record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error("accepted source successor: unreviewed migration record")
    return PyJson.parse(Path(_RECORD).read_text())


def _admitted(path: String, live_sha: String) raises -> String:
    """Return the successor module for a live file that still has one import.

    Args:
        path: The module path.
        live_sha: The required digest of the live file.

    Returns:
        The module with the admitted import.

    Raises:
        Error: The live file or its import changed.
    """
    var text = Path(path).read_text()
    if (
        sha256_hex(text.as_bytes()) != live_sha
        or _count(text, _LIVE_IMPORT) != 1
    ):
        raise Error(
            "accepted source successor: unreviewed complete successor: " + path
        )
    return _replace_first(text, _LIVE_IMPORT, _ADMITTED_IMPORT)


def _apply(
    record: PyJson, transitions: Int, mut pins: PyJson, only: Int
) raises:
    """Write each transition's `before` value, or only the one at `only`.

    Args:
        record: The successor record.
        transitions: The transition list in `record`.
        pins: The live pin document.
        only: An index to apply alone, or a negative value to apply every one.

    Raises:
        Error: A placement does not hold its `after` value.
    """
    var count = record.length(transitions)
    var index = 0
    while index < count:
        if only >= 0 and index != only:
            index += 1
            continue
        var change = record.item(transitions, index)
        var pointer = record.at(change, "pointer")
        var parts = record.length(pointer)
        if parts < 1:
            raise Error(
                "accepted source successor: active pin placement mismatch"
            )
        var node = pins.root
        var step = 0
        while step + 1 < parts:
            node = pins.at(node, record.text(record.item(pointer, step)))
            step += 1
        var key = record.text(record.item(pointer, step))
        if pins.text(pins.at(node, key)) != _field(record, change, "after"):
            raise Error(
                "accepted source successor: active pin placement mismatch"
            )
        pins.set(node, key, pins.new_str(_field(record, change, "before")))
        index += 1


def _pins(name: String) raises -> PyJson:
    """Return one live pin file after its digest matches the record.

    Args:
        name: The pin file name.

    Returns:
        The parsed pins.

    Raises:
        Error: The file digest changed.
    """
    var text = Path(_ORACLE + name).read_text()
    return PyJson.parse(text)


def test_the_three_successors_and_pin_reconstruction_stay_bound() raises:
    """The modules, component records, and both pin reconstructions stay bound.
    """
    var doc = _record()
    assert_equal(_field(doc, doc.root, "schema"), "1")
    var sources = doc.at(doc.root, "sources")
    assert_equal(doc.length(sources), 3)
    var followup_sha = sha256_hex(Path(_FOLLOWUP).read_bytes())
    assert_equal(
        followup_sha, _field(doc, doc.root, "prior_followup_migration_sha256")
    )
    var components = doc.at(doc.root, "components")
    assert_equal(doc.length(components), 6)
    var index = 0
    while index < doc.length(components):
        var name = doc.key(components, index)
        assert_equal(
            sha256_hex(Path(_ORACLE + name).read_bytes()),
            doc.text(doc.value(components, index)),
        )
        index += 1
    var paths = List[String]()
    paths.append(_LINE)
    paths.append(_DOMAIN)
    paths.append(_GROUPED)
    var gates = List[String]()
    gates.append(_LINE_LIVE_SHA256)
    gates.append(_DOMAIN_LIVE_SHA256)
    gates.append("")
    for slot in range(len(paths)):
        var path = paths[slot]
        var item = doc.at(sources, path)
        var before = _field(doc, item, "before_complete_module")
        assert_equal(
            sha256_hex(before.as_bytes()), _field(doc, item, "before_sha256")
        )
        assert_equal(
            token_sha256(before), _field(doc, item, "before_token_sha256")
        )
        var admitted = Path(path).read_text()
        if path != _GROUPED:
            admitted = _admitted(path, gates[slot])
        assert_equal(
            sha256_hex(admitted.as_bytes()), _field(doc, item, "after_sha256")
        )
        assert_equal(
            token_sha256(admitted), _field(doc, item, "after_token_sha256")
        )
    var edges = doc.at(doc.root, "rounded_line_edges")
    assert_equal(doc.length(edges), 2)
    assert_equal(
        _field(doc, doc.item(edges, 0), "after"),
        _field(doc, doc.item(edges, 1), "before"),
    )
    var followup = PyJson.parse(Path(_FOLLOWUP).read_text())
    var recorded = doc.at(doc.root, "pin_files")
    var prior = followup.at(followup.root, "pin_files")
    var names = List[String]()
    names.append("runtime-source-pins.json")
    names.append("sum2-guard-pins.json")
    var counts = List[Int]()
    counts.append(7)
    counts.append(4)
    for slot in range(len(names)):
        var name = names[slot]
        var raw = Path(_ORACLE + name).read_text()
        var item = doc.at(recorded, name)
        assert_equal(
            sha256_hex(raw.as_bytes()), _field(doc, item, "after_sha256")
        )
        var pins = PyJson.parse(raw)
        assert_equal(_indented(pins), raw)
        var transitions = doc.at(item, "transitions")
        assert_equal(doc.length(transitions), counts[slot])
        _apply(doc, transitions, pins, -1)
        var restored = _indented(pins)
        var digest = sha256_hex(restored.as_bytes())
        assert_equal(digest, _field(doc, item, "before_sha256"))
        assert_equal(
            digest, _field(followup, followup.at(prior, name), "after_sha256")
        )


def test_module_pin_and_record_edits_are_refused() raises:
    """A module, pin placement, component, or record edit changes its digest."""
    var doc = _record()
    var sources = doc.at(doc.root, "sources")
    var paths = List[String]()
    paths.append(_LINE)
    paths.append(_DOMAIN)
    paths.append(_GROUPED)
    var gates = List[String]()
    gates.append(_LINE_LIVE_SHA256)
    gates.append(_DOMAIN_LIVE_SHA256)
    gates.append("")
    for slot in range(len(paths)):
        var path = paths[slot]
        var admitted = Path(path).read_text()
        if path != _GROUPED:
            admitted = _admitted(path, gates[slot])
        var changed = admitted + "\nfrom unreviewed import range\n"
        var item = doc.at(sources, path)
        assert_true(
            token_sha256(changed) != _field(doc, item, "after_token_sha256")
        )
        assert_true(token_sha256(changed) != token_sha256(admitted))
    var recorded = doc.at(doc.root, "pin_files")
    var names = List[String]()
    names.append("runtime-source-pins.json")
    names.append("sum2-guard-pins.json")
    for name in names:
        var item = doc.at(recorded, name)
        var transitions = doc.at(item, "transitions")
        var count = doc.length(transitions)
        var index = 0
        while index < count:
            var pins = _pins(name)
            _apply(doc, transitions, pins, index)
            var changed = _indented(pins)
            assert_true(
                sha256_hex(changed.as_bytes())
                != _field(doc, item, "after_sha256")
            )
            assert_true(
                sha256_hex(changed.as_bytes())
                != _field(doc, item, "before_sha256")
            )
            index += 1
    var components = doc.at(doc.root, "components")
    var index = 0
    while index < doc.length(components):
        var name = doc.key(components, index)
        var raw = Path(_ORACLE + name).read_bytes()
        raw.append(UInt8(32))
        if sha256_hex(raw) == doc.text(doc.value(components, index)):
            raise Error(
                "accepted source successor: component record changed: " + name
            )
        index += 1
    var migration = Path(_RECORD).read_bytes()
    migration.append(UInt8(32))
    var refused = False
    try:
        if sha256_hex(migration) != _RECORD_SHA256:
            raise Error(
                "accepted source successor: unreviewed migration record"
            )
    except error:
        refused = True
        assert_true(String(error).find("unreviewed migration") >= 0)
    assert_true(refused)


def main() raises:
    """Run the accepted successor record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
