# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The rounded line singleton keeps its recorded modules and consumers."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import token_sha256
from tools._python_json import MISSING, PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = (
    "tools/carla_lane_oracle/rounded-line-singleton-migration.json"
)
"""The reviewed singleton record."""
comptime _RECORD_SHA256 = (
    "e4a0eb6c9e527dd66b2b803ee69754334feecc9bea33ce001cdf584d3a693506"
)
"""The SHA-256 of that record."""
comptime _SELECTOR = (
    "tools/carla_lane_oracle/rounded-line-selector-migration.json"
)
"""The successor used when the line module has already moved."""
comptime _LINE = "extensions/carla/curve_rounded_line.mojo"
"""The singleton line module."""
comptime _TRIG = "extensions/carla/curve_trig.mojo"
"""The live trig module the record still admits."""
comptime _SUM2 = "extensions/carla/curve_sum2.mojo"
"""The live Sum2 module the record still admits."""


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
        raise Error("missing singleton fragment")
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


def _record() raises -> PyJson:
    """Return the singleton record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error(
            "rounded LINE singleton contract: unreviewed migration record"
        )
    return PyJson.parse(Path(_RECORD).read_text())


def _admitted(doc: PyJson, module: String, needle: String) raises -> String:
    """Return the admitted text that contains `needle`.

    Args:
        doc: The singleton record.
        module: The module stem under `extensions/carla`.
        needle: The fragment the edit replaces.

    Returns:
        The recorded module, declaration, or import scope.

    Raises:
        Error: No admitted text contains `needle`.
    """
    var path = "extensions/carla/" + module + ".mojo"
    var modules = doc.at(doc.root, "modules")
    if doc.get(modules, path) != MISSING:
        var source = _field(doc, doc.at(modules, path), "source")
        if source.find(needle) >= 0:
            return source
    var declarations = doc.at(doc.root, "declarations")
    for index in range(doc.length(declarations)):
        var item = doc.item(declarations, index)
        if _field(doc, item, "path") == path:
            var source = _field(doc, item, "source")
            if source.find(needle) >= 0:
                return source
    var scopes = doc.at(doc.root, "import_scopes")
    if doc.get(scopes, path) != MISSING:
        var scope = doc.text(doc.at(scopes, path))
        if scope.find(needle) >= 0:
            return scope
    if path == _LINE:
        var selector = PyJson.parse(Path(_SELECTOR).read_text())
        var after = _field(selector, selector.root, "after_source")
        if after.find(needle) >= 0:
            return after
    raise Error("missing singleton fragment")


def test_the_singleton_modules_and_live_guards_stay_bound() raises:
    """The recorded modules keep their digests, and the live guards match."""
    var doc = _record()
    assert_equal(_field(doc, doc.root, "schema"), "1")
    var modules = doc.at(doc.root, "modules")
    assert_equal(doc.length(modules), 6)
    var paths = List[String]()
    paths.append(_LINE)
    paths.append("extensions/carla/curve_rounded_arc.mojo")
    paths.append(_TRIG)
    paths.append("extensions/carla/polynomial.mojo")
    paths.append("extensions/carla/road_info.mojo")
    paths.append(_SUM2)
    for index in range(len(paths)):
        var item = doc.at(modules, paths[index])
        var source = _field(doc, item, "source")
        assert_equal(token_sha256(source), _field(doc, item, "token_sha256"))
    assert_equal(
        token_sha256(Path(_TRIG).read_text()),
        token_sha256(_field(doc, doc.at(modules, _TRIG), "source")),
    )
    assert_equal(
        token_sha256(Path(_SUM2).read_text()),
        token_sha256(_field(doc, doc.at(modules, _SUM2), "source")),
    )
    var declarations = doc.at(doc.root, "declarations")
    for index in range(doc.length(declarations)):
        var item = doc.item(declarations, index)
        if _field(doc, item, "name") == "_reference_rounded_line_axis_context":
            var source = _field(doc, item, "source")
            assert_equal(
                _count(Path(_field(doc, item, "path")).read_text(), source), 1
            )


def test_singleton_edits_and_a_changed_record_are_refused() raises:
    """A module, consumer, or reference edit changes its digest."""
    var doc = _record()
    var cases = List[String]()
    cases.append("curve_rounded_arc")
    cases.append("return Self.bounds(value, value)")
    cases.append("return Self.bounds(value, value + 1.0)")
    cases.append("curve_rounded_arc")
    cases.append("_rounded_add(self.high, other.high)")
    cases.append("_rounded_add(self.high, other.high) + 1.0")
    cases.append("curve_rounded_arc")
    cases.append("var d = _rounded_multiply(self.high, other.high)")
    cases.append("var d = _rounded_multiply(self.high, other.high) + 1.0")
    cases.append("curve_rounded_arc")
    cases.append("return self + (-other)")
    cases.append("return self.hull(other)")
    cases.append("curve_rounded_arc")
    cases.append("return Self(-self.high, -self.low, self.known)")
    cases.append("return Self(-self.low, self.high, self.known)")
    cases.append("curve_rounded_arc")
    cases.append("return _RoundedBox.point(polynomial.a)")
    cases.append("return _RoundedBox.bounds(polynomial.a, polynomial.a + 1.0)")
    cases.append("curve_rounded_arc")
    cases.append("@no_inline\ndef _rounded_add")
    cases.append("def _rounded_add")
    cases.append("curve_rounded_arc")
    cases.append("@no_inline\ndef _rounded_multiply")
    cases.append("def _rounded_multiply")
    cases.append("curve_rounded_arc")
    cases.append("from std.math import fma, isfinite")
    cases.append("from fake_math import fma, isfinite")
    cases.append("curve_rounded_arc")
    cases.append("and low <= high")
    cases.append("and True")
    cases.append("curve_rounded_arc")
    cases.append("abs(value) >= low")
    cases.append("abs(value) > 0.0")
    cases.append("curve_rounded_line")
    cases.append("if not lane_offset.known or not elevation.known:")
    cases.append("if not lane_offset.known:")
    cases.append("curve_rounded_line")
    cases.append("if not offset.known:")
    cases.append("if False:")
    cases.append("curve_rounded_line")
    cases.append("if not width.known:")
    cases.append("if False:")
    cases.append("curve_rounded_line")
    cases.append("min(max(d.high, 0.0), length)")
    cases.append("max(d.high, length)")
    cases.append("curve_rounded_line")
    cases.append("or length < 0.0:")
    cases.append("or length > 0.0:")
    cases.append("curve_rounded_line")
    cases.append("from extensions.carla.curve_rounded_arc import (")
    cases.append("from extensions.carla.fake_rounded_arc import (")
    cases.append("curve_rounded_line")
    cases.append("def _rounded_line_axis_context(")
    cases.append("def _unreviewed_line_axis_context(")
    cases.append("curve_rounded_line")
    cases.append("cosine != 0.0")
    cases.append("True")
    cases.append("curve_rounded_line")
    cases.append("sine != 0.0")
    cases.append("True")
    cases.append("curve_trig")
    cases.append(
        "from std.math import atan, atan2, cos, floor, inf, isfinite,"
        " isnan, sin"
    )
    cases.append(
        "from fake_math import atan, atan2, cos, floor, inf, isfinite,"
        " isnan, sin"
    )
    cases.append("road_info")
    cases.append("def info_index[")
    cases.append("def changed_info_index[")
    cases.append("road")
    cases.append("def _check_lane(")
    cases.append("def _unchecked_lane(")
    cases.append("lane_refinement")
    cases.append(
        "from extensions.carla.curve_sum2 import _require_sum2_environment"
    )
    cases.append("from fake_environment import _require_sum2_environment")
    cases.append("lane_refinement")
    cases.append("_require_sum2_environment()")
    cases.append("pass")
    cases.append("curve_sum2")
    cases.append("def _sum2_supported_environment()")
    cases.append("def _unchecked_environment()")
    cases.append("lane_refinement")
    cases.append("terms += 1\n    var context = _rounded_line_axis_context")
    cases.append("terms += 0\n    var context = _rounded_line_axis_context")
    cases.append("polynomial")
    cases.append("var a: Float64")
    cases.append("var a: Float32")
    var index = 0
    while index < len(cases):
        var text = _admitted(doc, cases[index], cases[index + 1])
        var changed = _replace_all(text, cases[index + 1], cases[index + 2])
        assert_true(token_sha256(changed) != token_sha256(text))
        index += 3
    var declarations = doc.at(doc.root, "declarations")
    var reference = String()
    for slot in range(doc.length(declarations)):
        var item = doc.item(declarations, slot)
        if _field(doc, item, "name") == "_reference_rounded_line_axis_context":
            reference = _field(doc, item, "source")
    var edited = _replace_all(reference, "offset.low != offset.high", "False")
    assert_true(token_sha256(edited) != token_sha256(reference))
    var spaced = Path(_RECORD).read_bytes()
    spaced.append(UInt8(32))
    var refused = False
    try:
        if sha256_hex(spaced) != _RECORD_SHA256:
            raise Error(
                "rounded LINE singleton contract: unreviewed migration record"
            )
    except error:
        refused = True
        assert_true(String(error).find("unreviewed migration") >= 0)
    assert_true(refused)


def main() raises:
    """Run the rounded line singleton record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
