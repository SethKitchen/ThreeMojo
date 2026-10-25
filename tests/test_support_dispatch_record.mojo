# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The support and dispatch successor keeps its recorded operation graph."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import def_token_sha256, token_sha256
from tools._python_json import MISSING, PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = (
    "tools/carla_lane_oracle/curve-support-dispatch-migration.json"
)
"""The reviewed support and dispatch record."""
comptime _RECORD_SHA256 = (
    "1a6d7794bf0869a1e717685e556d8400e075ab97917ce8d855da6bd61c3ee19f"
)
"""The SHA-256 of that record."""
comptime _FROZEN = "tools/carla_lane_oracle/frozen-arc-producer-migration.json"
"""The frozen-arc record whose bytes stay on the pin."""
comptime _REFERENCE = "tests/test_carla_support_dispatch_successor.mojo"
"""The native reference functions."""


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
        raise Error("missing support fragment")
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
    """Return the support record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error(
            "curve support/dispatch contract: unreviewed migration record"
        )
    return PyJson.parse(Path(_RECORD).read_text())


def _bound_texts(
    doc: PyJson, module: String, needle: String
) raises -> List[String]:
    """Return each admitted text that contains `needle`.

    Args:
        doc: The support record.
        module: The module stem under `extensions/carla`.
        needle: The fragment the edit replaces.

    Returns:
        The recorded or live texts that contain `needle`.

    Raises:
        Error: No admitted text contains `needle`.
    """
    var path = "extensions/carla/" + module + ".mojo"
    var found = List[String]()
    var sources = doc.at(doc.root, "sources")
    if doc.get(sources, path) != MISSING:
        var after = _field(doc, doc.at(sources, path), "after_source")
        if after.find(needle) >= 0:
            found.append(after)
    var premises = doc.at(doc.root, "premise_modules")
    if doc.get(premises, path) != MISSING:
        var live = Path(path).read_text()
        if live.find(needle) >= 0:
            found.append(live)
    var functions = doc.at(doc.root, "premise_functions")
    for index in range(doc.length(functions)):
        var item = doc.item(functions, index)
        if _field(doc, item, "path") == path:
            var source = _field(doc, item, "source")
            if source.find(needle) >= 0:
                found.append(source)
    if len(found) == 0:
        raise Error("missing support fragment")
    return found^


def test_the_support_successor_and_references_stay_bound() raises:
    """The recorded modules, live premises, and reference functions stay bound.
    """
    var doc = _record()
    assert_equal(_field(doc, doc.root, "schema"), "1")
    var sources = doc.at(doc.root, "sources")
    assert_equal(doc.length(sources), 2)
    var minimizer = "extensions/carla/curve_minimizer_support.mojo"
    var dispatch = "extensions/carla/curve_sample_dispatch.mojo"
    var paths = List[String]()
    paths.append(minimizer)
    paths.append(dispatch)
    for index in range(len(paths)):
        var item = doc.at(sources, paths[index])
        var after = _field(doc, item, "after_source")
        assert_equal(
            token_sha256(after), _field(doc, item, "after_token_sha256")
        )
    assert_equal(
        sha256_hex(Path(minimizer).read_bytes()),
        _field(doc, doc.at(sources, minimizer), "after_sha256"),
    )
    var premises = doc.at(doc.root, "premise_modules")
    assert_equal(doc.length(premises), 2)
    var interval = "extensions/carla/curve_interval.mojo"
    var environment = "extensions/carla/curve_sum2.mojo"
    var premise_paths = List[String]()
    premise_paths.append(interval)
    premise_paths.append(environment)
    for index in range(len(premise_paths)):
        var source = _field(
            doc, doc.at(premises, premise_paths[index]), "source"
        )
        assert_equal(
            token_sha256(Path(premise_paths[index]).read_text()),
            token_sha256(source),
        )
    var functions = doc.at(doc.root, "premise_functions")
    var present = List[String]()
    present.append("_sample_index")
    present.append("_refine_lane_certificate")
    present.append("_continue_lane_certificate")
    for index in range(doc.length(functions)):
        var item = doc.item(functions, index)
        var name = _field(doc, item, "name")
        var keep = False
        for slot in range(len(present)):
            if present[slot] == name:
                keep = True
        if keep:
            var live = Path(_field(doc, item, "path")).read_text()
            assert_equal(_count(live, _field(doc, item, "source")), 1)
    var references = doc.at(doc.root, "reference_functions")
    assert_equal(doc.length(references), 4)
    var reference = Path(_REFERENCE).read_text()
    for index in range(doc.length(references)):
        var item = doc.item(references, index)
        assert_equal(
            def_token_sha256(reference, _field(doc, item, "name")),
            _field(doc, item, "token_sha256"),
        )
    var pins = doc.at(doc.root, "historical_pins")
    assert_equal(doc.length(pins), 3)
    assert_equal(
        sha256_hex(Path(_FROZEN).read_bytes()), _field(doc, pins, _FROZEN)
    )


def test_operation_edits_and_a_changed_record_are_refused() raises:
    """An operation edit changes its admitted digest, and a changed record is refused.
    """
    var doc = _record()
    var cases = List[String]()
    cases.append("curve_minimizer_support")
    cases.append("or best < low")
    cases.append("or False")
    cases.append("curve_minimizer_support")
    cases.append("or domain.error < 0.0")
    cases.append("or False")
    cases.append("curve_minimizer_support")
    cases.append("domain.second.low > 0.0")
    cases.append("domain.second.low >= 0.0")
    cases.append("curve_minimizer_support")
    cases.append("_Interval.point(2.0) *")
    cases.append("_Interval.point(-2.0) *")
    cases.append("curve_minimizer_support")
    cases.append("_Interval.point(4.0) *")
    cases.append("_Interval.point(-4.0) *")
    cases.append("curve_minimizer_support")
    cases.append("result.high = min(result.high, limit.high)")
    cases.append("result.high = min(result.high, limit.low)")
    cases.append("curve_minimizer_support")
    cases.append("result.low = max(result.low, limit.low)")
    cases.append("result.low = max(result.low, limit.high)")
    cases.append("curve_sample_dispatch")
    cases.append("if count < 1 or count > 2:")
    cases.append("if count < 0 or count > 2:")
    cases.append("curve_sample_dispatch")
    cases.append("first + i + 1")
    cases.append("first + i")
    cases.append("curve_sample_dispatch")
    cases.append("if station > high:")
    cases.append("if station < high:")
    cases.append("curve_sample_dispatch")
    cases.append("after_index != threshold_at")
    cases.append("after_index == threshold_at")
    cases.append("curve_sample_dispatch")
    cases.append("var node_reserve = 3 * count + 2")
    cases.append("var node_reserve = count")
    cases.append("curve_sample_dispatch")
    cases.append("terms += extra")
    cases.append("terms += 1")
    cases.append("curve_sample_dispatch")
    cases.append("local >= length")
    cases.append("local > length")
    cases.append("curve_interval")
    cases.append("Self(_next_down(low), _next_up(high))")
    cases.append("Self(low, high)")
    cases.append("curve_interval")
    cases.append("return Self(-self.high, -self.low)")
    cases.append("return Self(-self.low, -self.high)")
    cases.append("curve_interval")
    cases.append("if other.contains(0.0):")
    cases.append("if False:")
    cases.append("curve_interval")
    cases.append("if self.low < 0.0:")
    cases.append("if self.low > 0.0:")
    cases.append("curve_bounds")
    cases.append("var high = len(geometry.samples) - 1")
    cases.append("var high = len(geometry.samples)")
    cases.append("curve_bounds")
    cases.append("geometry.samples[middle].s < d")
    cases.append("geometry.samples[middle].s <= d")
    cases.append("map")
    cases.append("_require_sum2_environment()")
    cases.append("pass")
    cases.append("lane_refinement")
    cases.append("_require_sum2_environment()")
    cases.append("pass")
    cases.append("curve_sum2")
    cases.append("def _sum2_supported_environment()")
    cases.append("def _unchecked_environment()")
    var index = 0
    while index < len(cases):
        var texts = _bound_texts(doc, cases[index], cases[index + 1])
        for text in texts:
            var changed = _replace_all(text, cases[index + 1], cases[index + 2])
            assert_true(token_sha256(changed) != token_sha256(text))
        index += 3
    var changed = Path(_RECORD).read_bytes()
    changed.append(UInt8(32))
    var refused = False
    try:
        if sha256_hex(changed) != _RECORD_SHA256:
            raise Error(
                "curve support/dispatch contract: unreviewed migration record"
            )
    except error:
        refused = True
        assert_true(String(error).find("unreviewed migration") >= 0)
    assert_true(refused)


def main() raises:
    """Run the support and dispatch record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
