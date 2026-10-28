# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The lane-control successor keeps its declarations and guarded premises."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import def_token_sha256, token_sha256
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/lane-control-migration.json"
"""The reviewed lane-control record."""
comptime _RECORD_SHA256 = (
    "73d95d594e740205bad4cd900288a68d9f82897474fdc33e4d6043a156790170"
)
"""The SHA-256 of that record."""
comptime _PREDECESSOR_SHA256 = (
    "33d33ba0e481e3eca3b17ae0d02457ab53bae906430b0dca58abcfa876756315"
)
"""The SHA-256 of the predecessor module stored in the record."""
comptime _ORDER_PREDECESSOR_SHA256 = (
    "b607c75982a15122dd8f3de743e48ec66e71f027cb5dd034b459dc46602c5c3e"
)
"""The SHA-256 of the lane-order predecessor, which is this successor."""
comptime _MODULE = "extensions/carla/lane_refinement.mojo"
"""The lane module both records name."""
comptime _TEST = "tests/test_carla_lane_control_successor.mojo"
"""The frozen reference functions."""


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
        raise Error("missing lane-control fragment")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _record() raises -> PyJson:
    """Return the lane-control record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error("lane-control migration record changed")
    return PyJson.parse(Path(_RECORD).read_text())


def test_the_control_successor_declarations_and_premises_stay_bound() raises:
    """The successor, its declarations, premises, and references stay bound."""
    var doc = _record()
    assert_equal(_field(doc, doc.root, "schema"), "1")
    assert_equal(_field(doc, doc.root, "module"), _MODULE)
    var before = _field(doc, doc.root, "before_source")
    var after = _field(doc, doc.root, "after_source")
    assert_equal(sha256_hex(before.as_bytes()), _PREDECESSOR_SHA256)
    assert_equal(
        sha256_hex(before.as_bytes()), _field(doc, doc.root, "before_sha256")
    )
    assert_equal(sha256_hex(after.as_bytes()), _ORDER_PREDECESSOR_SHA256)
    assert_equal(
        sha256_hex(after.as_bytes()), _field(doc, doc.root, "after_sha256")
    )
    var declarations = doc.at(doc.root, "declarations")
    assert_equal(doc.length(declarations), 2)
    var tests = Path(_TEST).read_text()
    var index = 0
    while index < doc.length(declarations):
        var item = doc.item(declarations, index)
        var name = _field(doc, item, "name")
        assert_equal(_field(doc, item, "path"), _MODULE)
        assert_equal(doc.length(doc.at(item, "owner")), 0)
        var earlier = _field(doc, item, "before")
        var later = _field(doc, item, "after")
        assert_equal(def_token_sha256(before, name), token_sha256(earlier))
        assert_equal(def_token_sha256(after, name), token_sha256(later))
        var renamed = _replace_first(
            earlier, "def " + name + "(", "def _reference" + name + "("
        )
        assert_equal(
            def_token_sha256(tests, "_reference" + name), token_sha256(renamed)
        )
        assert_true(token_sha256(earlier) != token_sha256(later))
        var raised = _replace_first(earlier, "return", "raise")
        assert_true(token_sha256(raised) != token_sha256(earlier))
        index += 1
    var premises = doc.at(doc.root, "premises")
    assert_equal(doc.length(premises), 5)
    index = 0
    while index < doc.length(premises):
        var item = doc.item(premises, index)
        var path = _field(doc, item, "path")
        var name = _field(doc, item, "name")
        assert_equal(
            def_token_sha256(Path(path).read_text(), name),
            token_sha256(_field(doc, item, "source")),
        )
        index += 1
    var producers = doc.at(doc.root, "producer_modules")
    assert_equal(doc.length(producers), 2)
    index = 0
    while index < doc.length(producers):
        var path = doc.key(producers, index)
        assert_equal(
            token_sha256(Path(path).read_text()),
            token_sha256(doc.text(doc.value(producers, index))),
        )
        index += 1


def test_control_premise_and_record_edits_are_refused() raises:
    """A premise edit or a changed record changes its digest."""
    var doc = _record()
    var after = _field(doc, doc.root, "after_source")
    var cases = List[String]()
    cases.append("after")
    cases.append("if task[2] >= max_depth:")
    cases.append("if task[2] > max_depth:")
    cases.append("after")
    cases.append("if lo < sampled_cuts.value()[0]")
    cases.append("if lo <= sampled_cuts.value()[0]")
    cases.append("after")
    cases.append("bitcast[DType.uint64](split_at) - UInt64(1)")
    cases.append("bitcast[DType.uint64](split_at) - UInt64(2)")
    cases.append("after")
    cases.append("    _require_sum2_environment()")
    cases.append("    pass")
    cases.append("extensions/carla/curve_interval.mojo")
    cases.append("bits + 1")
    cases.append("bits + 2")
    cases.append("extensions/carla/curve_sum2.mojo")
    cases.append("raise Error(")
    cases.append("print(")
    cases.append(_TEST)
    cases.append("if interior > low and interior < high:")
    cases.append("if interior > low or interior < high:")
    var index = 0
    while index < len(cases):
        var path = cases[index]
        var before = cases[index + 1]
        var replacement = cases[index + 2]
        var text = after
        if path != "after":
            text = Path(path).read_text()
        if text.find(before) < 0:
            raise Error("missing lane-control fragment")
        var changed = _replace_first(text, before, replacement)
        assert_true(token_sha256(changed) != token_sha256(text))
        index += 3
    var record = Path(_RECORD).read_text()
    var edited = _replace_first(
        record, "Five redundant predicates", "Four redundant predicates"
    )
    assert_true(sha256_hex(edited.as_bytes()) != _RECORD_SHA256)
    var raw = Path(_RECORD).read_bytes()
    raw.append(UInt8(32))
    var refused = False
    try:
        if sha256_hex(raw) != _RECORD_SHA256:
            raise Error("lane-control migration record changed")
    except error:
        refused = True
        assert_true(String(error).find("migration record changed") >= 0)
    assert_true(refused)


def main() raises:
    """Run the lane-control record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
