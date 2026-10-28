# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The frozen ARC producer keeps its recorded operation graph."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import def_token_sha256, token_sha256
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/frozen-arc-producer-migration.json"
"""The reviewed frozen ARC producer record."""
comptime _RECORD_SHA256 = (
    "70091e23400193257514363570187b47890e3c08c352fe79eb08bf291737cc9f"
)
"""The SHA-256 of that record."""
comptime _CLEANUP = "tools/carla_lane_oracle/reviewed-cleanup-migration.json"
"""The three-file cleanup record this producer extends."""
comptime _WINNER = "tools/carla_lane_oracle/winner-sign-query-migration.json"
"""The winner record whose canonical map stays at 112 entries."""
comptime _ARC = "extensions/carla/curve_rounded_arc.mojo"
"""The rounded ARC producer."""
comptime _FROZEN = "extensions/carla/curve_frozen_arc.mojo"
"""The frozen ARC successor."""
comptime _REFERENCE = "tests/test_carla_frozen_arc_producer_contract.mojo"
"""The native reference function."""
comptime _TRIG = "extensions/carla/curve_trig.mojo"
"""The trig premise whose live tokens still match."""


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
        raise Error("missing frozen ARC fragment")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _indent(source: String) -> String:
    """Indent each occupied line of `source` by four spaces.

    Args:
        source: A dedented function.

    Returns:
        The function as it sits inside `_RoundedBox`.
    """
    var out = String()
    var rest = source
    var started = False
    while True:
        var at = rest.find("\n")
        if at < 0:
            if rest.byte_length() > 0:
                if started:
                    out += "\n"
                out += "    " + rest
            return out
        var line = String(rest[byte=:at])
        var tail = String(rest[byte = at + 1 :])
        if started:
            out += "\n"
        if line.byte_length() > 0:
            out += "    " + line
        started = True
        rest = tail


def _present(text: String, source: String) -> Bool:
    """Return whether `source` is one exact function in `text`.

    Args:
        text: A module.
        source: A recorded function, dedented.

    Returns:
        True when the function occurs once, at column zero or indented.
    """
    if _count(text, source) == 1:
        return True
    return _count(text, _indent(source)) == 1


def _record() raises -> PyJson:
    """Return the frozen ARC record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error("frozen ARC producer contract: unreviewed migration record")
    return PyJson.parse(Path(_RECORD).read_text())


def test_the_frozen_arc_producer_and_reference_stay_bound() raises:
    """The record, live successor, sixteen functions, and reference stay bound.
    """
    var doc = _record()
    assert_equal(_field(doc, doc.root, "schema"), "1")
    assert_equal(
        _field(doc, doc.at(doc.root, "source_successor"), "path"), _FROZEN
    )
    assert_equal(
        sha256_hex(Path(_CLEANUP).read_bytes()),
        _field(doc, doc.root, "previous_cleanup_migration_sha256"),
    )
    var cleanup = PyJson.parse(Path(_CLEANUP).read_text())
    var sources = cleanup.at(cleanup.root, "sources")
    assert_equal(cleanup.length(sources), 3)
    assert_equal(
        _field(cleanup, cleanup.root, "runtime_pins_after_sha256"),
        _field(doc, doc.root, "runtime_pins_before_sha256"),
    )
    var winner = PyJson.parse(Path(_WINNER).read_text())
    var canonical = winner.at(winner.root, "canonical_source_unchanged")
    assert_equal(winner.length(canonical), 112)
    assert_equal(winner.length(canonical) - cleanup.length(sources), 109)
    var frozen = Path(_FROZEN).read_text()
    var successor = doc.at(doc.root, "source_successor")
    assert_equal(
        sha256_hex(frozen.as_bytes()), _field(doc, successor, "after_sha256")
    )
    assert_equal(
        token_sha256(frozen), _field(doc, successor, "after_token_sha256")
    )
    var reference = Path(_REFERENCE).read_text()
    assert_equal(
        def_token_sha256(reference, "_reference_frozen_arc_context"),
        _field(doc, doc.root, "frozen_reference_token_sha256"),
    )
    var premises = doc.at(doc.root, "premise_dependencies")
    assert_equal(doc.length(premises), 4)
    assert_equal(
        token_sha256(Path(_TRIG).read_text()),
        _field(doc, doc.at(premises, _TRIG), "token_sha256"),
    )
    var transitions = doc.at(doc.root, "runtime_token_successors")
    assert_equal(doc.length(transitions), 3)
    var groups = String()
    for index in range(doc.length(transitions)):
        var item = doc.item(transitions, index)
        assert_equal(_field(doc, item, "path"), _FROZEN)
        assert_true(_field(doc, item, "before") != _field(doc, item, "after"))
        groups += _field(doc, item, "group") + "\n"
    assert_true(groups.find("eligibility\n") >= 0)
    assert_true(groups.find("optional_runtime\n") >= 0)
    assert_true(groups.find("translation\n") >= 0)
    var functions = doc.at(doc.root, "function_sources")
    assert_equal(doc.length(functions), 17)
    var admitted = 0
    var arc = Path(_ARC).read_text()
    for index in range(doc.length(functions)):
        var item = doc.item(functions, index)
        var name = _field(doc, item, "name")
        var source = _field(doc, item, "source")
        var path = _field(doc, item, "path")
        var live = arc
        if path == _FROZEN:
            live = frozen
        var owner = doc.at(item, "owner")
        if name == "_rounded_constant":
            assert_equal(doc.length(owner), 0)
            assert_equal(_count(live, source), 0)
            assert_true(def_token_sha256(live, name) != token_sha256(source))
            assert_equal(_count(live, "not _rounded_operand(polynomial.s)"), 1)
        elif doc.length(owner) == 0:
            assert_equal(_count(live, source), 1)
            assert_equal(def_token_sha256(live, name), token_sha256(source))
            admitted += 1
        else:
            assert_equal(doc.text(doc.item(owner, 0)), "_RoundedBox")
            assert_true(_present(live, source))
            admitted += 1
    assert_equal(admitted, 16)


def test_producer_edits_and_a_changed_record_are_refused() raises:
    """A producer edit changes its file digest, and a changed record is refused.
    """
    var doc = _record()
    var arc = Path(_ARC).read_text()
    var frozen = Path(_FROZEN).read_text()
    var cases = List[String]()
    cases.append(_ARC)
    cases.append("return Self.bounds(value, value)")
    cases.append("return Self.bounds(value, value + 1.0)")
    cases.append(_ARC)
    cases.append("return Self(0.0, 0.0, False)")
    cases.append("return Self(0.0, 0.0, True)")
    cases.append(_ARC)
    cases.append("return Self(low, high, valid)")
    cases.append("return Self(low, high, True)")
    cases.append(_ARC)
    cases.append("return Self(-self.high, -self.low, self.known)")
    cases.append("return Self(-self.high, -self.low, True)")
    cases.append(_ARC)
    cases.append("_rounded_add(self.high, other.high)")
    cases.append("_rounded_add(self.high, other.high) + 1.0")
    cases.append(_ARC)
    cases.append("return self + (-other)")
    cases.append("return self + other")
    cases.append(_ARC)
    cases.append("return separate.hull(_RoundedBox.bounds(low, high))")
    cases.append("return separate")
    cases.append(_ARC)
    cases.append("var d = _rounded_multiply(self.high, other.high)")
    cases.append("var d = _rounded_fma(self.high, other.high, 1.0)")
    cases.append(_ARC)
    cases.append("@no_inline\ndef _rounded_add(")
    cases.append("def _rounded_add(")
    cases.append(_ARC)
    cases.append("    return a + b\n")
    cases.append("    return fma(1.0, a, b)\n")
    cases.append(_ARC)
    cases.append("    return a * b\n")
    cases.append("    return fma(a, b, 1.0)\n")
    cases.append(_ARC)
    cases.append("    return 1.0 / value\n")
    cases.append("    return value\n")
    cases.append(_ARC)
    cases.append("return _RoundedBox.point(polynomial.a)")
    cases.append("return _RoundedBox.bounds(polynomial.a, polynomial.a + 1.0)")
    cases.append(_ARC)
    cases.append("if not lane_offset.known or not elevation.known:")
    cases.append("if False:")
    cases.append(_ARC)
    cases.append("if not width.known:")
    cases.append("if False:")
    cases.append(_ARC)
    cases.append(
        "if not curvature.known or curvature.low == 0.0 or not offset.known:"
    )
    cases.append("if curvature.low == 0.0:")
    cases.append(_ARC)
    cases.append(
        "if not (speed.known and x.known and y.known and start.known):"
    )
    cases.append("if False:")
    cases.append(_ARC)
    cases.append("var speed = (radius + offset) * curvature")
    cases.append(
        "var speed = _rounded_madd(radius + offset, curvature,"
        " _RoundedBox.point(0.0))"
    )
    cases.append(_ARC)
    cases.append(
        "start, record.geometry.length, curvature, speed, x, y, elevation"
    )
    cases.append(
        "start, record.geometry.length, curvature, speed, y, x, elevation"
    )
    cases.append(_ARC)
    cases.append("var start: _RoundedBox\n    var length: Float64")
    cases.append("var length: Float64\n    var start: _RoundedBox")
    cases.append(_FROZEN)
    cases.append(
        "var found = _rounded_arc_context(road, section, lane, low, high)"
    )
    cases.append(
        "var found = other_arc_context(road, section, lane, low, high)"
    )
    cases.append(_FROZEN)
    cases.append("if not found:")
    cases.append("if False:")
    cases.append(_FROZEN)
    cases.append("not distance.known")
    cases.append("False")
    cases.append(_FROZEN)
    cases.append("or distance.low <= 0.0")
    cases.append("or False")
    cases.append(_FROZEN)
    cases.append("or distance.high >= model.length")
    cases.append("or False")
    cases.append(_FROZEN)
    cases.append("    return model\n")
    cases.append("    model.start = _RoundedBox.unknown()\n    return model\n")
    var functions = doc.at(doc.root, "function_sources")
    var index = 0
    while index < len(cases):
        var path = cases[index]
        var before = cases[index + 1]
        var after = cases[index + 2]
        var live = arc
        if path == _FROZEN:
            live = frozen
        if _count(live, before) != 1:
            raise Error(
                "frozen ARC producer contract: complete producer/Box function"
                " changed"
            )
        var changed = _replace_first(live, before, after)
        assert_true(token_sha256(changed) != token_sha256(live))
        for slot in range(doc.length(functions)):
            var item = doc.item(functions, slot)
            if _field(doc, item, "path") != path:
                continue
            var source = _field(doc, item, "source")
            if source.find(before) < 0 or not _present(live, source):
                continue
            if _present(changed, source):
                raise Error(
                    "frozen ARC producer contract: complete producer/Box"
                    " function changed: "
                    + _field(doc, item, "name")
                )
        index += 3
    var raw = Path(_RECORD).read_bytes()
    raw.append(UInt8(32))
    var refused = False
    try:
        if sha256_hex(raw) != _RECORD_SHA256:
            raise Error(
                "frozen ARC producer contract: unreviewed migration record"
            )
    except error:
        refused = True
        assert_true(String(error).find("unreviewed migration") >= 0)
    assert_true(refused)


def main() raises:
    """Run the frozen ARC producer record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
