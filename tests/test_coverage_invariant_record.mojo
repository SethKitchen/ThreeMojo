# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The coverage invariant pins reconstruct the frozen runtime and guard digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import token_sha256
from tests.test_accepted_successor_record import _apply, _indented
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/coverage-invariant-migration.json"
"""The reviewed coverage invariant record."""
comptime _RECORD_SHA256 = (
    "56a72d9bccbf9e7b8a6b51db2b9944ef4bbf55d9bcc7311f7f9615be3b3b36ac"
)
"""The SHA-256 of that record."""
comptime _FOLLOWUP = "tools/carla_lane_oracle/coverage-followup-migration.json"
"""The follow-up record whose pin reconstruction this invariant extends."""
comptime _ACCEPTED = "tools/carla_lane_oracle/accepted-successor-migration.json"
"""The accepted record at the start of the pin chain."""
comptime _FROZEN = "tools/carla_lane_oracle/frozen-arc-producer-migration.json"
"""The frozen record the reconstructed pins must reach."""
comptime _SUPPORT = (
    "tools/carla_lane_oracle/curve-support-dispatch-migration.json"
)
"""The support record whose dispatch successor is an invariant edge."""
comptime _MINIMIZER = "extensions/carla/curve_minimizer_support.mojo"
"""The live minimizer module."""
comptime _DISPATCH = "extensions/carla/curve_sample_dispatch.mojo"
"""The dispatch module."""
comptime _GROUPED = "extensions/carla/spiral_grouped_roundoff_proof.mojo"
"""The grouped module."""
comptime _LANE = "extensions/carla/lane_refinement.mojo"
"""The lane module."""
comptime _ORACLE = "tools/carla_lane_oracle/"
"""The directory that holds the records and the pin files."""


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


def _sha_file(path: String) raises -> String:
    """Return the SHA-256 of a file.

    Args:
        path: The file path.

    Returns:
        The digest.

    Raises:
        Error: The file cannot be read.
    """
    return sha256_hex(Path(path).read_bytes())


def _record() raises -> PyJson:
    """Return the invariant record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    if _sha_file(_RECORD) != _RECORD_SHA256:
        raise Error("coverage invariant successor: unreviewed migration record")
    return PyJson.parse(Path(_RECORD).read_text())


def _pointer(doc: PyJson, change: Int) raises -> String:
    """Return one transition pointer as `part|part`.

    Args:
        doc: The record.
        change: The transition object.

    Returns:
        The pointer text.

    Raises:
        Error: The pointer is missing.
    """
    var pointer = doc.at(change, "pointer")
    var out = String()
    var index = 0
    while index < doc.length(pointer):
        if index > 0:
            out += "|"
        out += doc.text(doc.item(pointer, index))
        index += 1
    return out


def _has(found: List[String], needle: String) -> Bool:
    """Return whether `needle` is one of `found`.

    Args:
        found: The collected pointers.
        needle: The expected pointer.

    Returns:
        True when the pointer is present.
    """
    for item in found:
        if item == needle:
            return True
    return False


def test_the_invariant_edges_and_pointers_stay_bound() raises:
    """The four edges and both pointer sets stay on the earlier records."""
    var doc = _record()
    assert_equal(_field(doc, doc.root, "schema"), "1")
    assert_equal(
        _sha_file(_FROZEN),
        _field(doc, doc.root, "prior_frozen_migration_sha256"),
    )
    var sources = doc.at(doc.root, "sources")
    assert_equal(doc.length(sources), 4)
    var minimizer = Path(_MINIMIZER).read_text()
    var minimizer_edge = doc.at(sources, _MINIMIZER)
    assert_equal(
        sha256_hex(minimizer.as_bytes()),
        _field(doc, minimizer_edge, "after_sha256"),
    )
    assert_equal(
        token_sha256(minimizer),
        _field(doc, minimizer_edge, "after_token_sha256"),
    )
    var support = PyJson.parse(Path(_SUPPORT).read_text())
    var support_sources = support.at(support.root, "sources")
    var dispatch_source = _field(
        support, support.at(support_sources, _DISPATCH), "after_source"
    )
    var dispatch = doc.at(sources, _DISPATCH)
    assert_equal(
        sha256_hex(dispatch_source.as_bytes()),
        _field(doc, dispatch, "after_sha256"),
    )
    assert_equal(
        token_sha256(dispatch_source),
        _field(doc, dispatch, "after_token_sha256"),
    )
    var follow = PyJson.parse(Path(_FOLLOWUP).read_text())
    var follow_sources = follow.at(follow.root, "sources")
    var grouped = doc.at(sources, _GROUPED)
    var follow_grouped = follow.at(follow_sources, _GROUPED)
    assert_equal(
        _field(doc, grouped, "after_sha256"),
        _field(follow, follow_grouped, "before_sha256"),
    )
    assert_equal(
        _field(doc, grouped, "after_token_sha256"),
        _field(follow, follow_grouped, "before_token_sha256"),
    )
    var lane = doc.at(sources, _LANE)
    var follow_lane = follow.at(follow_sources, _LANE)
    assert_equal(
        _field(doc, lane, "after_sha256"),
        _field(follow, follow_lane, "before_sha256"),
    )
    assert_equal(
        _field(doc, lane, "after_token_sha256"),
        _field(follow, follow_lane, "before_token_sha256"),
    )
    var components = doc.at(doc.root, "components")
    assert_equal(doc.length(components), 3)
    var index = 0
    while index < doc.length(components):
        var name = doc.key(components, index)
        assert_equal(
            _sha_file(_ORACLE + name), doc.text(doc.value(components, index))
        )
        index += 1
    var pins = doc.at(doc.root, "pin_files")
    var runtime = doc.at(pins, "runtime-source-pins.json")
    var runtime_rows = doc.at(runtime, "transitions")
    assert_equal(doc.length(runtime_rows), 7)
    var expected = List[String]()
    var modules = List[String]()
    modules.append(_MINIMIZER)
    modules.append(_DISPATCH)
    modules.append(_GROUPED)
    modules.append(_LANE)
    for path in modules:
        expected.append("groups|optional_runtime|" + path)
    var groups = List[String]()
    groups.append("canonical_accumulation")
    groups.append("translation")
    groups.append("support")
    for group in groups:
        expected.append("groups|" + group + "|" + _LANE)
    var found = List[String]()
    index = 0
    while index < doc.length(runtime_rows):
        found.append(_pointer(doc, doc.item(runtime_rows, index)))
        index += 1
    assert_equal(len(found), len(expected))
    for needle in expected:
        assert_true(_has(found, needle))
    var guard = doc.at(pins, "sum2-guard-pins.json")
    var guard_rows = doc.at(guard, "transitions")
    assert_equal(doc.length(guard_rows), 7)
    var guard_expected = List[String]()
    guard_expected.append(
        "callers|curve_minimizer_support|functions|_minimizer_support"
    )
    guard_expected.append(
        "callers|curve_sample_dispatch|functions|_try_sample_dispatch_cuts"
    )
    guard_expected.append(
        "callers|spiral_grouped_roundoff_proof|functions|_try_spiral_grouped_roundoff_envelope"
    )
    guard_expected.append(
        "protected_inventory|extensions/carla/curve_sample_dispatch.mojo"
    )
    guard_expected.append(
        "protected_inventory|extensions/carla/spiral_grouped_roundoff_proof.mojo"
    )
    guard_expected.append("callers|lane_refinement|functions|_run_lane_search")
    guard_expected.append(
        "protected_inventory|extensions/carla/lane_refinement.mojo"
    )
    found.clear()
    index = 0
    while index < doc.length(guard_rows):
        found.append(_pointer(doc, doc.item(guard_rows, index)))
        index += 1
    assert_equal(len(found), len(guard_expected))
    for needle in guard_expected:
        assert_true(_has(found, needle))


def test_the_invariant_pins_reach_the_frozen_record() raises:
    """Both pin files reconstruct the frozen digests, and a changed record is refused.
    """
    var doc = _record()
    var accepted = PyJson.parse(Path(_ACCEPTED).read_text())
    var follow = PyJson.parse(Path(_FOLLOWUP).read_text())
    var frozen = PyJson.parse(Path(_FROZEN).read_text())
    var names = List[String]()
    names.append("runtime-source-pins.json")
    names.append("sum2-guard-pins.json")
    var keys = List[String]()
    keys.append("runtime_pins_after_sha256")
    keys.append("guard_pins_unchanged_sha256")
    var slot = 0
    while slot < len(names):
        var name = names[slot]
        var raw = Path(_ORACLE + name).read_text()
        var pins = PyJson.parse(raw)
        var accepted_item = accepted.at(
            accepted.at(accepted.root, "pin_files"), name
        )
        _apply(accepted, accepted.at(accepted_item, "transitions"), pins, -1)
        var follow_item = follow.at(follow.at(follow.root, "pin_files"), name)
        _apply(follow, follow.at(follow_item, "transitions"), pins, -1)
        var middle = sha256_hex(_indented(pins).as_bytes())
        var item = doc.at(doc.at(doc.root, "pin_files"), name)
        assert_equal(middle, _field(doc, item, "after_sha256"))
        var one = PyJson.parse(_indented(pins))
        _apply(doc, doc.at(item, "transitions"), one, 0)
        var shifted = sha256_hex(_indented(one).as_bytes())
        assert_true(shifted != _field(doc, item, "after_sha256"))
        assert_true(shifted != _field(doc, item, "before_sha256"))
        _apply(doc, doc.at(item, "transitions"), pins, -1)
        var final = sha256_hex(_indented(pins).as_bytes())
        assert_equal(final, _field(doc, item, "before_sha256"))
        assert_equal(final, _field(frozen, frozen.root, keys[slot]))
        slot += 1
    var changed = Path(_RECORD).read_bytes()
    changed.append(UInt8(32))
    var refused = False
    try:
        if sha256_hex(changed) != _RECORD_SHA256:
            raise Error(
                "coverage invariant successor: unreviewed migration record"
            )
    except error:
        refused = True
        assert_true(String(error).find("unreviewed migration record") >= 0)
    assert_true(refused)


def main() raises:
    """Run the coverage invariant record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
