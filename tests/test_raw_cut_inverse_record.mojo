# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The raw-cut successor keeps its recorded inverse and environment guard."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import token_sha256
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/raw-cut-inverse-migration.json"
"""The reviewed raw-cut inverse record."""
comptime _RECORD_SHA256 = (
    "4f4eb051d9c1f9194796d3073fcadfa9f49dda4c44a851da0a3409ba09587dd0"
)
"""The SHA-256 of that record."""
comptime _PATH = "extensions/carla/curve_sample_dispatch.mojo"
"""The dispatch module the record admits."""
comptime _ENVIRONMENT = "extensions/carla/curve_sum2.mojo"
"""The environment guard the record admits."""
comptime _PREDECESSOR = (
    "tools/carla_lane_oracle/curve-support-dispatch-migration.json"
)
"""The predecessor migration the successor is bound to."""
comptime _FIXTURE = "tests/test_carla_raw_cut_successor.mojo"
"""The native fixture whose token digest is recorded."""
comptime _REFERENCE = "tests/test_carla_support_dispatch_successor.mojo"
"""The file that holds the recorded reference function."""


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
        raise Error("missing raw-cut fragment")
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
    """Return the raw-cut record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error("raw cut inverse contract: unreviewed migration record")
    return PyJson.parse(Path(_RECORD).read_text())


def _admit(doc: PyJson) raises:
    """Require the recorded successor, guard, predecessor, and reference.

    Args:
        doc: The raw-cut record.

    Raises:
        Error: A recorded source, the guard, the predecessor, or the reference changed.
    """
    var dispatch = _field(doc, doc.root, "after_source")
    var environment = _field(doc, doc.root, "environment_source")
    if token_sha256(dispatch) != _field(doc, doc.root, "after_token_sha256"):
        raise Error(
            "raw cut inverse contract: complete raw inverse successor changed"
        )
    if token_sha256(_field(doc, doc.root, "before_source")) != _field(
        doc, doc.root, "before_token_sha256"
    ):
        raise Error("raw cut inverse contract: recorded source/token mismatch")
    if token_sha256(Path(_ENVIRONMENT).read_text()) != token_sha256(
        environment
    ):
        raise Error(
            "raw cut inverse contract: environment guard premise changed"
        )
    var predecessor = Path(_PREDECESSOR).read_bytes()
    if sha256_hex(predecessor) != _field(
        doc, doc.root, "predecessor_migration_sha256"
    ):
        raise Error(
            "raw cut inverse contract: historical predecessor record changed"
        )
    var prior = PyJson.parse(Path(_PREDECESSOR).read_text())
    var sources = prior.at(prior.root, "sources")
    var item = prior.at(sources, _PATH)
    if _field(prior, item, "after_token_sha256") != _field(
        doc, doc.root, "before_token_sha256"
    ):
        raise Error(
            "raw cut inverse contract: successor is not bound to accepted"
            " predecessor"
        )
    if token_sha256(Path(_FIXTURE).read_text()) != _field(
        doc, doc.root, "native_fixture_token_sha256"
    ):
        raise Error(
            "raw cut inverse contract: independent exact-word native fixture"
            " changed"
        )
    var reference = _field(doc, doc.root, "native_reference_source")
    if _count(Path(_REFERENCE).read_text(), reference) != 1:
        raise Error(
            "raw cut inverse contract: native predecessor reference changed"
        )


def _refuse_dispatch(dispatch: String, doc: PyJson) raises:
    """Require a changed dispatch module to leave the recorded digest.

    Args:
        dispatch: The edited successor.
        doc: The raw-cut record.

    Raises:
        Error: The edited module still matches the record.
    """
    if token_sha256(dispatch) == _field(doc, doc.root, "after_token_sha256"):
        raise Error(
            "raw cut inverse contract: raw inverse operation graph changed"
        )


def test_the_recorded_raw_cut_successor_stays_bound() raises:
    """The record, the live guard, the predecessor, and the reference stay bound.
    """
    var doc = _record()
    assert_equal(_field(doc, doc.root, "schema"), "1")
    assert_equal(_field(doc, doc.root, "path"), _PATH)
    _admit(doc)


def test_operation_edits_and_a_changed_record_are_refused() raises:
    """An operation edit or a changed record is refused."""
    var doc = _record()
    var dispatch = _field(doc, doc.root, "after_source")
    var cases = List[String]()
    cases.append("if not _sum2_supported_environment():")
    cases.append("if False:")
    cases.append("or origin < 0.0")
    cases.append("or False")
    cases.append("or local < 0.0")
    cases.append("or False")
    cases.append("or local >= length")
    cases.append("or local > length")
    cases.append("var start = origin + local")
    cases.append("var start = origin - local")
    cases.append("start <= 0.0")
    cases.append("start < 0.0")
    cases.append("station - origin")
    cases.append("station + origin")
    cases.append("length) > local")
    cases.append("length) >= local")
    cases.append("local, start):")
    cases.append("local, start + 1.0):")
    cases.append("var word = bitcast[DType.uint64](start) + UInt64(1)")
    cases.append("var word = bitcast[DType.uint64](start) + UInt64(2)")
    cases.append("word >= UInt64(0x7FF0000000000000)")
    cases.append("word > UInt64(0x7FF0000000000000)")
    cases.append("local, cut):")
    cases.append("local, start):")
    cases.append("word += UInt64(1)")
    cases.append("word += UInt64(2)")
    cases.append("return bitcast[DType.float64](word)")
    cases.append("return bitcast[DType.float64](word - UInt64(1))")
    cases.append("var extra = 8 * count")
    cases.append("var extra = 2 * count")
    cases.append("after_index != threshold_at")
    cases.append("after_index == threshold_at")
    var index = 0
    while index < len(cases):
        var changed = _replace_all(dispatch, cases[index], cases[index + 1])
        _refuse_dispatch(changed, doc)
        index += 2
    var environment = Path(_ENVIRONMENT).read_text()
    var renamed = _replace_all(
        environment,
        "def _sum2_supported_environment()",
        "def _unchecked_environment()",
    )
    var environment_failed = False
    try:
        if token_sha256(renamed) != token_sha256(
            _field(doc, doc.root, "environment_source")
        ):
            raise Error(
                "raw cut inverse contract: environment guard premise changed"
            )
    except error:
        environment_failed = True
        assert_true(
            String(error).find("environment guard premise changed") >= 0
        )
    assert_true(environment_failed)
    var changed = Path(_RECORD).read_bytes()
    changed.append(UInt8(32))
    var refused = False
    try:
        if sha256_hex(changed) != _RECORD_SHA256:
            raise Error("raw cut inverse contract: unreviewed migration record")
    except error:
        refused = True
        assert_true(String(error).find("unreviewed migration") >= 0)
    assert_true(refused)


def main() raises:
    """Run the raw-cut inverse record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
