# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The coverage follow-up keeps its source edges and pin reconstruction."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import token_sha256
from tests.test_accepted_successor_record import _apply, _indented
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/coverage-followup-migration.json"
"""The reviewed coverage follow-up record."""
comptime _RECORD_SHA256 = (
    "911929b7dc80b5c6e09e0cf27b2c8e1f9db52cd8df398d397fc70c900fed759e"
)
"""The SHA-256 of that record."""
comptime _ACCEPTED = "tools/carla_lane_oracle/accepted-successor-migration.json"
"""The accepted record whose pin reconstruction this follow-up extends."""
comptime _ACCEPTED_SHA256 = (
    "bb3a7b5e08a0a5400679f410da2c4574b45924294133df2f180f71fd74064d91"
)
"""The SHA-256 of the accepted record."""
comptime _INVARIANT = (
    "tools/carla_lane_oracle/coverage-invariant-migration.json"
)
"""The invariant record the reconstructed pins must reach."""
comptime _RAW = "tools/carla_lane_oracle/raw-cut-inverse-migration.json"
"""The raw-cut record whose successor is the dispatch edge."""
comptime _LANE = "extensions/carla/lane_refinement.mojo"
"""The lane module shared with the lane-order record."""
comptime _LANE_AFTER_SHA256 = (
    "13afed281e9df7549d3acb022680e2e20a57ea54411817eed6f45bf9042e5938"
)
"""The lane-order successor digest, which is this follow-up's lane end."""
comptime _LANE_AFTER_TOKEN = (
    "ad94f8e2a32d175b01e55f3e226c676a9aee371b49e00fc7b502ab56b6acfb46"
)
"""The token digest of that lane end."""
comptime _LANE_BEFORE_SHA256 = (
    "b607c75982a15122dd8f3de743e48ec66e71f027cb5dd034b459dc46602c5c3e"
)
"""The lane-order predecessor digest, which is this follow-up's lane start."""
comptime _MOMENT = "extensions/carla/spiral_moment_proof.mojo"
"""The live moment module."""
comptime _ROUNDOFF = "extensions/carla/spiral_roundoff_proof.mojo"
"""The live roundoff module."""
comptime _GROUPED = "extensions/carla/spiral_grouped_roundoff_proof.mojo"
"""The grouped module whose accepted predecessor is this follow-up's end."""
comptime _DISPATCH = "extensions/carla/curve_sample_dispatch.mojo"
"""The dispatch module whose raw-cut successor is this follow-up's end."""
comptime _ORACLE = "tools/carla_lane_oracle/"
"""The directory that holds the component records and the pin files."""


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
    """Return the follow-up record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    if _sha_file(_RECORD) != _RECORD_SHA256:
        raise Error("coverage followup successor: unreviewed migration record")
    return PyJson.parse(Path(_RECORD).read_text())


def test_the_followup_sources_stay_on_the_known_edges() raises:
    """The six edges stay on the live modules and the earlier successor records.
    """
    var doc = _record()
    assert_equal(_field(doc, doc.root, "schema"), "1")
    assert_equal(
        _sha_file(_INVARIANT),
        _field(doc, doc.root, "prior_invariant_migration_sha256"),
    )
    var sources = doc.at(doc.root, "sources")
    assert_equal(doc.length(sources), 6)
    var moment = Path(_MOMENT).read_text()
    var moment_edge = doc.at(sources, _MOMENT)
    assert_equal(
        sha256_hex(moment.as_bytes()), _field(doc, moment_edge, "after_sha256")
    )
    assert_equal(
        token_sha256(moment), _field(doc, moment_edge, "after_token_sha256")
    )
    var roundoff = Path(_ROUNDOFF).read_text()
    var roundoff_edge = doc.at(sources, _ROUNDOFF)
    assert_equal(
        sha256_hex(roundoff.as_bytes()),
        _field(doc, roundoff_edge, "after_sha256"),
    )
    assert_equal(
        token_sha256(roundoff), _field(doc, roundoff_edge, "after_token_sha256")
    )
    var lane = doc.at(sources, _LANE)
    assert_equal(_field(doc, lane, "after_sha256"), _LANE_AFTER_SHA256)
    assert_equal(_field(doc, lane, "after_token_sha256"), _LANE_AFTER_TOKEN)
    assert_equal(_field(doc, lane, "before_sha256"), _LANE_BEFORE_SHA256)
    if _sha_file(_ACCEPTED) != _ACCEPTED_SHA256:
        raise Error("coverage followup successor: unreviewed migration record")
    var accepted = PyJson.parse(Path(_ACCEPTED).read_text())
    var grouped = doc.at(sources, _GROUPED)
    var accepted_grouped = accepted.at(
        accepted.at(accepted.root, "sources"), _GROUPED
    )
    assert_equal(
        _field(doc, grouped, "after_sha256"),
        _field(accepted, accepted_grouped, "before_sha256"),
    )
    assert_equal(
        _field(doc, grouped, "after_token_sha256"),
        _field(accepted, accepted_grouped, "before_token_sha256"),
    )
    var raw = PyJson.parse(Path(_RAW).read_text())
    var successor = _field(raw, raw.root, "after_source")
    var dispatch = doc.at(sources, _DISPATCH)
    assert_equal(
        sha256_hex(successor.as_bytes()), _field(doc, dispatch, "after_sha256")
    )
    assert_equal(
        token_sha256(successor), _field(doc, dispatch, "after_token_sha256")
    )
    var components = doc.at(doc.root, "components")
    assert_equal(doc.length(components), 5)
    var index = 0
    while index < doc.length(components):
        var name = doc.key(components, index)
        assert_equal(
            _sha_file(_ORACLE + name), doc.text(doc.value(components, index))
        )
        index += 1


def test_the_followup_pins_reach_the_invariant_record() raises:
    """Both pin files reconstruct the invariant digests, and a changed record is refused.
    """
    var doc = _record()
    var accepted = PyJson.parse(Path(_ACCEPTED).read_text())
    var invariant = PyJson.parse(Path(_INVARIANT).read_text())
    var names = List[String]()
    names.append("runtime-source-pins.json")
    names.append("sum2-guard-pins.json")
    var follow_pins = doc.at(doc.root, "pin_files")
    var accepted_pins = accepted.at(accepted.root, "pin_files")
    var invariant_pins = invariant.at(invariant.root, "pin_files")
    for name in names:
        var raw = Path(_ORACLE + name).read_text()
        var pins = PyJson.parse(raw)
        assert_equal(_indented(pins), raw)
        var accepted_item = accepted.at(accepted_pins, name)
        assert_equal(
            sha256_hex(raw.as_bytes()),
            _field(accepted, accepted_item, "after_sha256"),
        )
        _apply(accepted, accepted.at(accepted_item, "transitions"), pins, -1)
        var restored = _indented(pins)
        var middle = sha256_hex(restored.as_bytes())
        var follow_item = doc.at(follow_pins, name)
        assert_equal(middle, _field(accepted, accepted_item, "before_sha256"))
        assert_equal(middle, _field(doc, follow_item, "after_sha256"))
        var one = PyJson.parse(restored)
        _apply(doc, doc.at(follow_item, "transitions"), one, 0)
        var shifted = sha256_hex(_indented(one).as_bytes())
        assert_true(shifted != _field(doc, follow_item, "after_sha256"))
        assert_true(shifted != _field(doc, follow_item, "before_sha256"))
        _apply(doc, doc.at(follow_item, "transitions"), pins, -1)
        var final = sha256_hex(_indented(pins).as_bytes())
        assert_equal(final, _field(doc, follow_item, "before_sha256"))
        var invariant_item = invariant.at(invariant_pins, name)
        assert_equal(final, _field(invariant, invariant_item, "after_sha256"))
    var changed = Path(_RECORD).read_bytes()
    changed.append(UInt8(32))
    var refused = False
    try:
        if sha256_hex(changed) != _RECORD_SHA256:
            raise Error(
                "coverage followup successor: unreviewed migration record"
            )
    except error:
        refused = True
        assert_true(String(error).find("unreviewed migration record") >= 0)
    assert_true(refused)


def main() raises:
    """Run the coverage follow-up record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
