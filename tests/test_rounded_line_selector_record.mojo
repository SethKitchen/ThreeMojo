# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The rounded line selector keeps its recorded graph and predecessor."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import token_sha256
from tools._python_json import MISSING, PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = (
    "tools/carla_lane_oracle/rounded-line-selector-migration.json"
)
"""The reviewed selector record."""
comptime _RECORD_SHA256 = (
    "ccb63b640653126b098185b188e33a036b140919a3c48b1ecb1b1541571ef4c4"
)
"""The SHA-256 of that record."""
comptime _PRIOR = (
    "tools/carla_lane_oracle/rounded-line-singleton-migration.json"
)
"""The immediate predecessor record."""
comptime _PRIOR_SHA256 = (
    "e4a0eb6c9e527dd66b2b803ee69754334feecc9bea33ce001cdf584d3a693506"
)
"""The SHA-256 of that predecessor record."""
comptime _LINE = "extensions/carla/curve_rounded_line.mojo"
"""The selector module."""
comptime _TRIG = "extensions/carla/curve_trig.mojo"
"""The live trig module the predecessor still admits."""
comptime _SUM2 = "extensions/carla/curve_sum2.mojo"
"""The live Sum2 module the predecessor still admits."""


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
        raise Error("missing selector fragment")
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


def _selector() raises -> PyJson:
    """Return the selector record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error(
            "rounded LINE selector contract: unreviewed selector migration"
        )
    return PyJson.parse(Path(_RECORD).read_text())


def _prior() raises -> PyJson:
    """Return the predecessor record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_PRIOR).read_bytes()
    if sha256_hex(raw) != _PRIOR_SHA256:
        raise Error("rounded LINE selector contract: prior migration changed")
    return PyJson.parse(Path(_PRIOR).read_text())


def _admitted(
    selector: PyJson, prior: PyJson, module: String, needle: String
) raises -> String:
    """Return the admitted text that contains `needle`.

    Args:
        selector: The selector record.
        prior: The predecessor record.
        module: The module stem under `extensions/carla`.
        needle: The fragment the edit replaces.

    Returns:
        The recorded or live text.

    Raises:
        Error: No admitted text contains `needle`.
    """
    var path = "extensions/carla/" + module + ".mojo"
    if path == _LINE:
        var after = _field(selector, selector.root, "after_source")
        if after.find(needle) >= 0:
            return after
    var modules = prior.at(prior.root, "modules")
    if prior.get(modules, path) != MISSING:
        var source = _field(prior, prior.at(modules, path), "source")
        if source.find(needle) >= 0:
            return source
    var declarations = prior.at(prior.root, "declarations")
    for index in range(prior.length(declarations)):
        var item = prior.item(declarations, index)
        if _field(prior, item, "path") == path:
            var source = _field(prior, item, "source")
            if source.find(needle) >= 0:
                return source
    var scopes = prior.at(prior.root, "import_scopes")
    if prior.get(scopes, path) != MISSING:
        var scope = prior.text(prior.at(scopes, path))
        if scope.find(needle) >= 0:
            return scope
    raise Error("missing selector fragment")


def test_the_selector_successor_and_predecessor_stay_bound() raises:
    """The recorded selector, the predecessor, and the live guards stay bound.
    """
    var selector = _selector()
    var prior = _prior()
    assert_equal(_field(selector, selector.root, "schema"), "1")
    assert_equal(_field(selector, selector.root, "path"), _LINE)
    assert_equal(
        _field(selector, selector.root, "prior_migration_sha256"), _PRIOR_SHA256
    )
    var after = _field(selector, selector.root, "after_source")
    assert_equal(
        token_sha256(after),
        _field(selector, selector.root, "after_token_sha256"),
    )
    var before = _field(selector, selector.root, "before_source")
    var predecessor = _field(
        prior, prior.at(prior.at(prior.root, "modules"), _LINE), "source"
    )
    assert_equal(token_sha256(before), token_sha256(predecessor))
    var modules = prior.at(prior.root, "modules")
    assert_equal(
        token_sha256(Path(_TRIG).read_text()),
        token_sha256(_field(prior, prior.at(modules, _TRIG), "source")),
    )
    assert_equal(
        token_sha256(Path(_SUM2).read_text()),
        token_sha256(_field(prior, prior.at(modules, _SUM2), "source")),
    )
    var reference = selector.at(selector.root, "reference")
    var source = _field(selector, reference, "source")
    assert_equal(
        _count(Path(_field(selector, reference, "path")).read_text(), source), 1
    )


def test_selector_edits_and_a_changed_record_are_refused() raises:
    """A selector edit changes its digest, and a changed record is refused."""
    var selector = _selector()
    var prior = _prior()
    var cases = List[String]()
    cases.append("curve_rounded_line")
    cases.append("@always_inline\ndef _select_rounded_line_axis")
    cases.append("def _select_rounded_line_axis")
    cases.append("curve_rounded_line")
    cases.append("def _select_rounded_line_axis(")
    cases.append("def _renamed_rounded_line_selector(")
    cases.append("curve_rounded_line")
    cases.append("def _rounded_line_axis_context(")
    cases.append("def _renamed_rounded_line_context(")
    cases.append("curve_rounded_line")
    cases.append(
        "from extensions.carla.curve_trig import _curve_cos, _curve_sin"
    )
    cases.append("from shadow_trig import _curve_cos, _curve_sin")
    cases.append("curve_rounded_line")
    cases.append("if y.low == y.high and cosine != 0.0:")
    cases.append("if x.low == x.high and cosine != 0.0:")
    cases.append("curve_rounded_line")
    cases.append("cosine != 0.0")
    cases.append("True")
    cases.append("curve_rounded_line")
    cases.append("sine != 0.0")
    cases.append("True")
    cases.append("curve_rounded_line")
    cases.append("return _RoundedLineAxis(0, cosine)")
    cases.append("return _RoundedLineAxis(1, cosine)")
    cases.append("curve_rounded_line")
    cases.append("return _RoundedLineAxis(1, -sine)")
    cases.append("return _RoundedLineAxis(1, sine)")
    cases.append("curve_rounded_line")
    cases.append("_select_rounded_line_axis(x, y, cosine.low, sine.low)")
    cases.append("_select_rounded_line_axis(x, y, sine.low, cosine.low)")
    cases.append("curve_rounded_line")
    cases.append("if not (x.known and y.known):")
    cases.append("if False:")
    cases.append("curve_rounded_line")
    cases.append("from extensions.carla.curve_rounded_arc import (")
    cases.append("from fake_box import (")
    cases.append("curve_rounded_line")
    cases.append(
        "var cosine = _RoundedBox.point(_curve_cos(record.geometry.heading))"
    )
    cases.append("var cosine = _RoundedBox.point(0.0)")
    cases.append("curve_rounded_line")
    cases.append("x = _rounded_madd(offset, sine, x)")
    cases.append("x = offset * sine + x")
    cases.append("curve_rounded_arc")
    cases.append("return Self.bounds(value, value)")
    cases.append("return Self.bounds(value, value + 1.0)")
    cases.append("curve_trig")
    cases.append("if abs(value) > _PHASE_LIMIT:")
    cases.append("if True:")
    cases.append("lane_refinement")
    cases.append("terms += 1\n    var context = _rounded_line_axis_context")
    cases.append("terms += 0\n    var context = _rounded_line_axis_context")
    cases.append("lane_refinement")
    cases.append(
        "from extensions.carla.curve_sum2 import _require_sum2_environment"
    )
    cases.append("from fake_math import _require_sum2_environment")
    cases.append("curve_sum2")
    cases.append("def _sum2_supported_environment()")
    cases.append("def _unchecked_environment()")
    var index = 0
    while index < len(cases):
        var text = _admitted(selector, prior, cases[index], cases[index + 1])
        var changed = _replace_all(text, cases[index + 1], cases[index + 2])
        assert_true(token_sha256(changed) != token_sha256(text))
        index += 3
    var reference = selector.at(selector.root, "reference")
    var source = _field(selector, reference, "source")
    var edited = _replace_all(source, "cosine.low != 0.0", "True")
    assert_true(token_sha256(edited) != token_sha256(source))
    var spaced = Path(_RECORD).read_bytes()
    spaced.append(UInt8(32))
    var refused = False
    try:
        if sha256_hex(spaced) != _RECORD_SHA256:
            raise Error(
                "rounded LINE selector contract: unreviewed selector migration"
            )
    except error:
        refused = True
        assert_true(String(error).find("unreviewed selector migration") >= 0)
    assert_true(refused)
    var prior_bytes = Path(_PRIOR).read_bytes()
    prior_bytes.append(UInt8(32))
    var prior_refused = False
    try:
        if sha256_hex(prior_bytes) != _PRIOR_SHA256:
            raise Error(
                "rounded LINE selector contract: prior migration changed"
            )
    except error:
        prior_refused = True
        assert_true(String(error).find("prior migration changed") >= 0)
    assert_true(prior_refused)


def main() raises:
    """Run the rounded line selector record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
