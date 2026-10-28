# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The selection producers keep ordered theta and a finite phase bound."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import stored_scalar, token_sha256
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _Y_RECORD = "tools/carla_lane_oracle/grouped-y-successor-record.json"
"""The grouped module that the selection proof admits."""
comptime _RECORD = "tools/carla_lane_oracle/selection-finiteness-contract.json"
"""The reviewed selection predecessor record."""
comptime _RECORD_SHA256 = (
    "dcd2c780640775e29a566491679dc6fbf5ab1afa43fbfbae86cb778433cf92e8"
)
"""The SHA-256 of that record."""
comptime _GROUPED_PATH = "extensions/carla/spiral_grouped_roundoff_proof.mojo"
"""The grouped selection producer."""
comptime _ROUNDOFF_PATH = "extensions/carla/spiral_roundoff_proof.mojo"
"""The plain selection producer."""
comptime _INTERVAL = "extensions/carla/curve_interval.mojo"
"""The ordered interval arithmetic."""
comptime _TRIG = "extensions/carla/curve_trig.mojo"
"""The selector constants."""
comptime _GROUPED = (
    "a8f3beca23c8d6a84d01f5eebecb0a01cd2102aad4e226ed6a782722733a86b7"
)
"""The token digest of the grouped producer."""
comptime _ROUNDOFF = (
    "634c4f0f448b472301a42ad6065655f60cf78121f12bafa64085a1e67108fc0f"
)
"""The token digest of the plain producer."""
comptime _INTERVAL_TOKEN = (
    "e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11"
)
"""The token digest of the interval module."""


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


def _replace_all(text: String, before: String, after: String) raises -> String:
    """Replace every occurrence of `before`.

    Args:
        text: The source.
        before: The original fragment.
        after: The replacement.

    Returns:
        The changed source.

    Raises:
        Error: `before` is missing.
    """
    if text.find(before) < 0:
        raise Error("missing selection fragment")
    var out = String()
    var rest = text
    while True:
        var at = rest.find(before)
        if at < 0:
            out += rest
            break
        var head = String(rest[byte=:at])
        var tail = String(rest[byte = at + before.byte_length() :])
        out += head + after
        rest = tail
    return out


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
        raise Error("missing selection fragment")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _grouped() raises -> String:
    """Return the grouped producer the selection proof admits.

    Returns:
        The recorded module.

    Raises:
        Error: The module digest changed.
    """
    var doc = PyJson.parse(Path(_Y_RECORD).read_text())
    var text = _field(doc, doc.root, "before_complete_module")
    if token_sha256(text) != _GROUPED:
        raise Error(
            "Selection producer/input/error/phase graph changed: "
            + _GROUPED_PATH
        )
    return text


def _admit(
    grouped: String, roundoff: String, interval: String, trig: String
) raises:
    """Require both producers, the interval, and the selector bounds.

    Args:
        grouped: The grouped producer.
        roundoff: The plain producer.
        interval: The interval module.
        trig: The selector constants.

    Raises:
        Error: A graph, the interval arithmetic, or a selector bound changed.
    """
    if token_sha256(grouped) != _GROUPED:
        raise Error(
            "Selection producer/input/error/phase graph changed: "
            + _GROUPED_PATH
        )
    if token_sha256(roundoff) != _ROUNDOFF:
        raise Error(
            "Selection producer/input/error/phase graph changed: "
            + _ROUNDOFF_PATH
        )
    if token_sha256(interval) != _INTERVAL_TOKEN:
        raise Error("Ordering or nonnegative-error arithmetic changed")
    var scale = stored_scalar(trig, "_INV_HALF_PI")
    var limit = stored_scalar(trig, "_PHASE_LIMIT")
    if not (scale > 0.0 and scale <= 1.0):
        raise Error("Selector multiplier bound")
    if not (limit > 0.0 and limit <= 1048576.0):
        raise Error("Finite phase bound")


def _module(doc: PyJson, path: String) raises -> Int:
    """Return one recorded producer.

    Args:
        doc: The selection record.
        path: The producer path.

    Returns:
        The module object.

    Raises:
        Error: The module is absent.
    """
    return doc.at(doc.at(doc.root, "modules"), path)


def _predecessor(
    producer: String, after: String, before: String, expected: String
) raises -> String:
    """Splice the recorded predecessor function into one producer.

    Args:
        producer: The admitted producer.
        after: The recorded successor function.
        before: The recorded predecessor function.
        expected: The predecessor token digest.

    Returns:
        The restored module.

    Raises:
        Error: The successor body or the restored digest changed.
    """
    if producer.find(after) < 0:
        raise Error("Selection complete successor body changed")
    var restored = _replace_first(producer, after, before)
    if restored.find(after) >= 0:
        raise Error("Selection complete successor body changed")
    if token_sha256(restored) != expected:
        raise Error("Selection predecessor reconstruction failed")
    return restored


def _declaration(text: String, name: String) raises -> String:
    """Return one one-line `Float64` selector declaration.

    Args:
        text: The trig module.
        name: The constant name.

    Returns:
        The declaration, through its closing parenthesis.

    Raises:
        Error: The declaration is missing.
    """
    var mark = "comptime " + name + " = Float64("
    var start = text.find(mark)
    if start < 0:
        raise Error("missing selector declaration")
    var line_end = text.find("\n", start)
    if line_end < start:
        line_end = text.byte_length()
    var line = String(text[byte=start:line_end])
    var close = -1
    var bytes = line.as_bytes()
    for index in range(mark.byte_length(), len(bytes)):
        if bytes[index] == 41:
            close = index
    if close < mark.byte_length():
        raise Error("missing selector declaration")
    return String(line[byte = : close + 1])


def test_the_selection_graph_and_predecessors_stay_bound() raises:
    """The admitted producers, bounds, and both predecessor digests hold."""
    var grouped = _grouped()
    var roundoff = Path(_ROUNDOFF_PATH).read_text()
    var interval = Path(_INTERVAL).read_text()
    var trig = Path(_TRIG).read_text()
    _admit(grouped, roundoff, interval, trig)
    _admit(
        grouped + "\n# comment\n",
        roundoff + "\n# comment\n",
        interval + "\n# comment\n",
        trig + "\n# comment\n",
    )
    var softened = _replace_all(trig, "0.6366197723675814", "0.625")
    _admit(grouped, roundoff, interval, softened)
    var raw = Path(_RECORD).read_bytes()
    assert_equal(sha256_hex(raw), _RECORD_SHA256)
    var doc = PyJson.parse(Path(_RECORD).read_text())
    assert_equal(
        _field(doc, doc.root, "interval_token_sha256"), _INTERVAL_TOKEN
    )
    var paths = List[String]()
    paths.append(_GROUPED_PATH)
    paths.append(_ROUNDOFF_PATH)
    var producers = List[String]()
    producers.append(grouped)
    producers.append(roundoff)
    for index in range(2):
        var item = _module(doc, paths[index])
        assert_equal(
            _field(doc, item, "after_token_sha256"),
            token_sha256(producers[index]),
        )
        _ = _predecessor(
            producers[index],
            _field(doc, item, "after_complete_function"),
            _field(doc, item, "before_complete_function"),
            _field(doc, item, "before_token_sha256"),
        )


def test_producer_and_interval_edits_are_refused() raises:
    """A producer guard edit or an interval edit changes its digest."""
    var grouped = _grouped()
    var roundoff = Path(_ROUNDOFF_PATH).read_text()
    var interval = Path(_INTERVAL).read_text()
    var trig = Path(_TRIG).read_text()
    var producers = List[String]()
    producers.append(grouped)
    producers.append(roundoff)
    var cases = List[String]()
    cases.append("d.error < 0.0")
    cases.append("False")
    cases.append("phase.magnitude() > _PHASE_LIMIT")
    cases.append("False")
    cases.append("floor(selection.low) != 0.0")
    cases.append("False")
    cases.append("floor(selection.high) != 0.0")
    cases.append("False")
    cases.append("var selection =")
    cases.append("theta.error = -1.0\n    var selection =")
    for producer in range(2):
        var index = 0
        while index < len(cases):
            var changed = _replace_all(
                producers[producer], cases[index], cases[index + 1]
            )
            var failed = False
            try:
                if producer == 0:
                    _admit(changed, roundoff, interval, trig)
                else:
                    _admit(grouped, changed, interval, trig)
            except error:
                failed = True
                assert_true(
                    String(error).find(
                        "Selection producer/input/error/phase graph changed"
                    )
                    >= 0
                )
            assert_true(failed)
            index += 2
    var interval_cases = List[String]()
    interval_cases.append("return first.hull(first)")
    interval_cases.append("return one")
    interval_cases.append("var inherited = _next_up(self.error + other.error)")
    interval_cases.append("var inherited = -1.0")
    var cursor = 0
    while cursor < len(interval_cases):
        var changed = _replace_all(
            interval, interval_cases[cursor], interval_cases[cursor + 1]
        )
        var failed = False
        try:
            _admit(grouped, roundoff, changed, trig)
        except error:
            failed = True
            assert_true(
                String(error).find(
                    "Ordering or nonnegative-error arithmetic changed"
                )
                >= 0
            )
        assert_true(failed)
        cursor += 2


def test_selector_decoys_and_a_changed_record_are_refused() raises:
    """A hidden selector, a huge word, or a changed record is refused."""
    var grouped = _grouped()
    var roundoff = Path(_ROUNDOFF_PATH).read_text()
    var interval = Path(_INTERVAL).read_text()
    var trig = Path(_TRIG).read_text()
    var names = List[String]()
    names.append("_INV_HALF_PI")
    names.append("_PHASE_LIMIT")
    for name in names:
        var declaration = _declaration(trig, name)
        var decoys = List[String]()
        decoys.append('"""' + declaration + '"""')
        decoys.append(declaration + " if False else Float64(0.0)")
        decoys.append(declaration + " + Float64(0.0)")
        decoys.append(_replace_all(declaration, "Float64(", "Float64(1e308 + "))
        for decoy in decoys:
            var text = _replace_first(trig, declaration, decoy)
            var failed = False
            try:
                _admit(grouped, roundoff, interval, text)
            except error:
                failed = True
            assert_true(failed)
    var changed = Path(_RECORD).read_bytes()
    changed.append(UInt8(32))
    var refused = False
    try:
        _admit(grouped, roundoff, interval, trig)
        if sha256_hex(changed) != _RECORD_SHA256:
            raise Error("Unreviewed selection predecessor record")
    except error:
        refused = True
        assert_true(
            String(error).find("Unreviewed selection predecessor record") >= 0
        )
    assert_true(refused)


def main() raises:
    """Run the selection finiteness record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
