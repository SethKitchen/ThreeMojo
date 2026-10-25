# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The lane-order successor keeps its queue, premises, and references."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import _tokenize, def_token_sha256, token_sha256
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/lane-order-migration.json"
"""The reviewed lane-order record."""
comptime _RECORD_SHA256 = (
    "e0aece69b861bc11a197cae17803e3273cdbd0cfed7ed0ca577ca6c3b4d217b1"
)
"""The SHA-256 of that record."""
comptime _PREDECESSOR_SHA256 = (
    "b607c75982a15122dd8f3de743e48ec66e71f027cb5dd034b459dc46602c5c3e"
)
"""The SHA-256 of the predecessor module stored in the record."""
comptime _MODULE = "extensions/carla/lane_refinement.mojo"
"""The lane successor module."""
comptime _TEST = "tests/test_carla_lane_order_successor.mojo"
"""The frozen reference functions."""
comptime _NAME = 1


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
        raise Error("missing lane-order fragment")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _uses(source: String) raises -> List[String]:
    """Return each lane-search name with its position among names.

    Args:
        source: Mojo source.

    Returns:
        `index:name` for `_run_lane_search` and `lane_refinement`.

    Raises:
        Error: The source cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var found = List[String]()
    var names = 0
    for index in range(len(kinds)):
        if kinds[index] != _NAME:
            continue
        var word = texts[index]
        if word == "_run_lane_search" or word == "lane_refinement":
            found.append(String(names) + ":" + word)
        names += 1
    return found^


def _recorded_uses(doc: PyJson, node: Int) raises -> String:
    """Return the recorded use list as `index:name` lines.

    Args:
        doc: The record.
        node: The use list.

    Returns:
        One use on each line.

    Raises:
        Error: A use is missing.
    """
    var out = String()
    var index = 0
    while index < doc.length(node):
        var pair = doc.item(node, index)
        if index > 0:
            out += "\n"
        out += doc.text(doc.item(pair, 0)) + ":" + doc.text(doc.item(pair, 1))
        index += 1
    return out


def _joined(found: List[String]) -> String:
    """Join use rows with newlines.

    Args:
        found: The `index:name` rows.

    Returns:
        The joined rows.
    """
    var out = String()
    var index = 0
    while index < len(found):
        if index > 0:
            out += "\n"
        out += found[index]
        index += 1
    return out


def _insertions(source: String) raises -> String:
    """Return the queue operations inside `_run_lane_search`.

    Args:
        source: The admitted lane module.

    Returns:
        One stripped operation on each line.

    Raises:
        Error: The function is missing.
    """
    var marker = "def _run_lane_search"
    var at = source.find(marker)
    if at < 0:
        raise Error("missing lane-order function")
    var rest = String(source[byte=at:])
    var next = rest.find("\ndef ")
    var end = source.byte_length()
    if next >= 0:
        end = at + next
    var chunk = String(source[byte=at:end])
    var lines = chunk.split("\n")
    var out = String()
    var started = False
    for line in lines:
        var text = String(line)
        var hit = (
            text.find("pending.append(") >= 0
            or text.find("closed.add(") >= 0
            or text.find("terminal.append(") >= 0
            or text.find("closed.recheck(") >= 0
        )
        if not hit:
            continue
        var trimmed = text
        while trimmed.startswith(" "):
            var tail = String(trimmed[byte=1:])
            trimmed = tail
        if started:
            out += "\n"
        out += trimmed
        started = True
    return out


def _record() raises -> PyJson:
    """Return the lane-order record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error("lane-order record changed")
    return PyJson.parse(Path(_RECORD).read_text())


def test_the_lane_successor_premises_and_references_stay_bound() raises:
    """The admitted module, live premises, queue, and references stay bound."""
    var doc = _record()
    assert_equal(_field(doc, doc.root, "schema"), "1")
    assert_equal(_field(doc, doc.root, "module"), _MODULE)
    var before = _field(doc, doc.root, "before")
    var after = _field(doc, doc.root, "after")
    assert_equal(sha256_hex(before.as_bytes()), _PREDECESSOR_SHA256)
    assert_equal(
        sha256_hex(before.as_bytes()), _field(doc, doc.root, "before_sha256")
    )
    assert_equal(
        sha256_hex(after.as_bytes()), _field(doc, doc.root, "after_sha256")
    )
    var premises = doc.at(doc.root, "premise_modules")
    assert_equal(doc.length(premises), 3)
    var index = 0
    while index < doc.length(premises):
        var path = doc.key(premises, index)
        var expected = doc.text(doc.value(premises, index))
        assert_equal(
            token_sha256(Path(path).read_text()), token_sha256(expected)
        )
        index += 1
    var pinned = doc.at(doc.root, "immutable_predecessor_records")
    assert_equal(doc.length(pinned), 2)
    index = 0
    while index < doc.length(pinned):
        var path = doc.key(pinned, index)
        assert_equal(
            sha256_hex(Path(path).read_bytes()),
            doc.text(doc.value(pinned, index)),
        )
        index += 1
    var inventory = doc.at(doc.root, "inventory")
    assert_equal(doc.length(inventory), 4)
    var lane = doc.at(inventory, _MODULE)
    assert_equal(
        _joined(_uses(after)), _recorded_uses(doc, doc.at(lane, "uses"))
    )
    var callers = List[String]()
    callers.append("extensions/carla/lane_box_cover.mojo")
    callers.append("extensions/carla/map.mojo")
    for path in callers:
        var item = doc.at(inventory, path)
        assert_equal(
            _joined(_uses(Path(path).read_text())),
            _recorded_uses(doc, doc.at(item, "uses")),
        )
    var recorded = doc.at(doc.root, "insertions")
    var found = _insertions(after)
    var expected_ops = String()
    index = 0
    while index < doc.length(recorded):
        if index > 0:
            expected_ops += "\n"
        expected_ops += _field(doc, doc.item(recorded, index), "operation")
        index += 1
    assert_equal(found, expected_ops)
    var references = doc.at(doc.root, "references")
    var tests = Path(_TEST).read_text()
    assert_equal(doc.length(references), 2)
    index = 0
    while index < doc.length(references):
        var name = doc.key(references, index)
        assert_equal(
            def_token_sha256(tests, name),
            token_sha256(doc.text(doc.value(references, index))),
        )
        index += 1


def test_queue_premise_and_record_edits_are_refused() raises:
    """A queue, premise, reference, or record edit changes its digest."""
    var doc = _record()
    var after = _field(doc, doc.root, "after")
    var cases = List[String]()
    cases.append(_MODULE)
    cases.append(
        "if not (isfinite(low) and isfinite(high) and isfinite(seed)):"
    )
    cases.append("if not isfinite(seed):")
    cases.append(_MODULE)
    cases.append("or cell.high < cell.low")
    cases.append("or cell.high > cell.low")
    cases.append(_MODULE)
    cases.append(
        "return (certificate.low, certificate.high, certificate.depth)"
    )
    cases.append(
        "return (certificate.high, certificate.low, certificate.depth)"
    )
    cases.append(_MODULE)
    cases.append(
        "var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 0)]"
    )
    cases.append(
        "var pending: List[Tuple[Float64, Float64, Int]] = [(high, low, 0)]"
    )
    cases.append(_MODULE)
    cases.append("return low + span * 0.5")
    cases.append("return low - span * 0.5")
    cases.append(_MODULE)
    cases.append("if lo < sampled_cuts.value()[0]")
    cases.append("if lo <= sampled_cuts.value()[0]")
    cases.append(_MODULE)
    cases.append("bitcast[DType.uint64](split_at) - UInt64(1)")
    cases.append("bitcast[DType.uint64](split_at) - UInt64(2)")
    cases.append(_MODULE)
    cases.append("pending.append((lo, middle, task[2] + 1))")
    cases.append("pending.append((middle, lo, task[2] + 1))")
    cases.append("extensions/carla/curve_minimizer_support.mojo")
    cases.append("result.high = min(result.high, limit.high)")
    cases.append("result.high = max(result.high, limit.high)")
    cases.append("extensions/carla/curve_interval.mojo")
    cases.append("bits + 1")
    cases.append("bits + 2")
    cases.append("extensions/carla/curve_sum2.mojo")
    cases.append("raise Error(")
    cases.append("print(")
    cases.append(_TEST)
    cases.append("if lo > 0.0 and isfinite(hi) and hi >= lo:")
    cases.append("if lo > 0.0:")
    var index = 0
    while index < len(cases):
        var path = cases[index]
        var before = cases[index + 1]
        var replacement = cases[index + 2]
        var text = after
        if path != _MODULE:
            text = Path(path).read_text()
        if text.find(before) < 0:
            raise Error("missing lane-order fragment")
        var changed = _replace_first(text, before, replacement)
        assert_true(token_sha256(changed) != token_sha256(text))
        index += 3
    var caller = (
        "from extensions.carla.lane_refinement import _run_lane_search as"
        " unchecked\n"
    )
    var caller_uses = _uses(caller)
    assert_equal(len(caller_uses), 2)
    assert_equal(caller_uses[0], "3:lane_refinement")
    assert_equal(caller_uses[1], "5:_run_lane_search")
    var raw = Path(_RECORD).read_bytes()
    raw.append(UInt8(32))
    var refused = False
    try:
        if sha256_hex(raw) != _RECORD_SHA256:
            raise Error("lane-order record changed")
    except error:
        refused = True
        assert_true(String(error).find("lane-order record changed") >= 0)
    assert_true(refused)


def main() raises:
    """Run the lane-order record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
