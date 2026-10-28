# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The consumer ledger ends at the restored render-actor module."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._render_actor_predecessor import restored_render_actors
from tests._python_tokens import token_sha256
from tools._python_json import PY_INT, PyJson
from tools._sha256 import sha256_hex


comptime _LEDGER = "tools/carla_lane_oracle/consumer-successor-ledger.json"
"""The reviewed consumer ledger."""
comptime _LEDGER_SHA256 = (
    "cd966262e04f6017317603e2dd4651c26da58030b780506cb189ce5d1c2ae2be"
)
"""The SHA-256 of that ledger."""
comptime _MODULE = "extensions/carla/render_actors.mojo"
"""The render-actor consumer this ledger names."""
comptime _LIVE_TOKEN = (
    "f9121ffa7349551437387e2783e28f8bc35fcec29f530131bec2ce4a0af757e4"
)
"""The token digest of the live render-actor module."""
comptime _AFTER_SHA256 = (
    "0169a2466ef2cfe970e5e53b3311ea8cf81e481d11f668c531c2ca545497cdcc"
)
"""The SHA-256 of the ledger endpoint restored from the live file."""
comptime _AFTER_TOKEN = (
    "8b8a3b10474f988da8ebe3868e4ca277819c6096105e0940bf9acb7783f435d2"
)
"""The token digest of that endpoint."""
comptime _BEFORE_SHA256 = (
    "ae1f86645cb6c7dac99a741619595be18a61c558c56262c27a50fa9b9bacef3b"
)
"""The SHA-256 where the border and winner records pin this consumer."""
comptime _BEFORE_TOKEN = (
    "f77b3bea2a872f7b2a026cbfba75aa7a98ab9339f1c7aa21d1fae2bb6cb4cd1e"
)
"""The token digest of that pin."""
comptime _BORDER = "tools/carla_lane_oracle/border-parser-successor.json"
"""The border record that pins this consumer."""
comptime _BORDER_SHA256 = (
    "0119f046c502021dc422f82ad602074e24cf3fa192f27fd372e80a927d94860b"
)
"""The SHA-256 of the border record."""
comptime _WINNER = "tools/carla_lane_oracle/winner-sign-query-migration.json"
"""The winner record that pins this consumer."""
comptime _WINNER_SHA256 = (
    "b154b18213f9f0400661aff93e47b86bf83990c8838dfa0fca00b0fe6710b9a3"
)
"""The SHA-256 of the winner record."""
comptime _REUSE = "tests/test_carla_render_reuse.mojo"
"""A bound render-reuse test."""
comptime _REUSE_SHA256 = (
    "642c63f1f17d7c3729810ec576056a0831518547cfbf4e34c83bbbc58a013fc4"
)
"""The SHA-256 of that test."""
comptime _CACHE = "tests/test_carla_model_cache.mojo"
"""A bound model-cache test."""
comptime _CACHE_SHA256 = (
    "e8da22f338e2c2a602012960541954bc9f52082bda40c90775142b84dfdf779f"
)
"""The SHA-256 of that test."""
comptime _MOTION = "tests/test_carla_walker_render_motion.mojo"
"""A bound walker-motion test."""
comptime _MOTION_SHA256 = (
    "8c7d4bdbc5a62348f43fd18ecc98486b2212b373e52452d31547c117bc4020a3"
)
"""The SHA-256 of that test."""


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


def _ledger() raises -> PyJson:
    """Return the consumer ledger after its file digest matches.

    Returns:
        The parsed ledger.

    Raises:
        Error: The ledger bytes changed.
    """
    var raw = Path(_LEDGER).read_bytes()
    if sha256_hex(raw) != _LEDGER_SHA256:
        raise Error("reviewed consumer successor ledger: unreviewed ledger")
    return PyJson.parse(Path(_LEDGER).read_text())


def _edge(doc: PyJson) raises -> Int:
    """Return the one render-actor edge.

    Args:
        doc: The ledger.

    Returns:
        The edge object.

    Raises:
        Error: The ledger shape or the edge changed.
    """
    var schema = doc.at(doc.root, "schema")
    if doc.kind(schema) != PY_INT or doc.text(schema) != "1":
        raise Error(
            "reviewed consumer successor ledger: unexpected ledger shape"
        )
    if doc.get(doc.root, "scope") < 0 or doc.get(doc.root, "edges") < 0:
        raise Error(
            "reviewed consumer successor ledger: unexpected ledger shape"
        )
    var edges = doc.at(doc.root, "edges")
    if doc.length(edges) != 1:
        raise Error(
            "reviewed consumer successor ledger: unexpected ledger shape"
        )
    var edge = doc.item(edges, 0)
    if doc.length(edge) != 7:
        raise Error("reviewed consumer successor ledger: malformed edge")
    var keys = List[String]()
    keys.append("issue")
    keys.append("path")
    keys.append("before_sha256")
    keys.append("after_sha256")
    keys.append("before_token_sha256")
    keys.append("after_token_sha256")
    keys.append("correctness_tests")
    for key in keys:
        if doc.get(edge, key) < 0:
            raise Error("reviewed consumer successor ledger: malformed edge")
    if doc.text(doc.at(edge, "issue")) != "306":
        raise Error("reviewed consumer successor ledger: edge has no issue")
    if _field(doc, edge, "path") != _MODULE:
        raise Error(
            "reviewed consumer successor ledger: edge outside the pinned"
            " consumers"
        )
    return edge


def _pin(path: String, digest: String, group: String) raises -> String:
    """Return one consumer pin from a reviewed record.

    Args:
        path: The record path.
        digest: The record's file digest.
        group: The pin object.

    Returns:
        The pin for the render-actor module.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(path).read_bytes()
    if sha256_hex(raw) != digest:
        raise Error(
            "reviewed consumer successor ledger: historical consumer record"
            " changed: "
            + path
        )
    var doc = PyJson.parse(Path(path).read_text())
    return _field(doc, doc.at(doc.root, group), _MODULE)


def test_line_edits_restore_the_ledger_endpoint() raises:
    """Thirteen line edits restore the ledger endpoint, and both records pin its start.
    """
    var doc = _ledger()
    var edge = _edge(doc)
    assert_equal(_field(doc, edge, "before_sha256"), _BEFORE_SHA256)
    assert_equal(_field(doc, edge, "after_sha256"), _AFTER_SHA256)
    assert_equal(_field(doc, edge, "before_token_sha256"), _BEFORE_TOKEN)
    assert_equal(_field(doc, edge, "after_token_sha256"), _AFTER_TOKEN)
    assert_true(_BEFORE_SHA256 != _AFTER_SHA256)
    assert_true(_BEFORE_TOKEN != _AFTER_TOKEN)
    var restored = restored_render_actors()
    assert_equal(sha256_hex(restored.as_bytes()), _AFTER_SHA256)
    assert_equal(token_sha256(restored), _AFTER_TOKEN)
    var live = Path(_MODULE).read_text()
    assert_equal(token_sha256(live), _LIVE_TOKEN)
    assert_equal(
        _pin(_BORDER, _BORDER_SHA256, "unchanged_inputs"), _BEFORE_SHA256
    )
    assert_equal(
        _pin(_WINNER, _WINNER_SHA256, "canonical_source_unchanged"),
        _BEFORE_SHA256,
    )
    var tests = doc.at(edge, "correctness_tests")
    assert_equal(doc.length(tests), 3)
    assert_equal(_field(doc, tests, _REUSE), _REUSE_SHA256)
    assert_equal(_field(doc, tests, _CACHE), _CACHE_SHA256)
    assert_equal(_field(doc, tests, _MOTION), _MOTION_SHA256)
    assert_equal(sha256_hex(Path(_REUSE).read_bytes()), _REUSE_SHA256)
    assert_equal(sha256_hex(Path(_CACHE).read_bytes()), _CACHE_SHA256)
    assert_equal(sha256_hex(Path(_MOTION).read_bytes()), _MOTION_SHA256)


def test_a_changed_ledger_or_bound_test_is_refused() raises:
    """A changed ledger, endpoint, or bound test changes its digest."""
    var restored = restored_render_actors()
    assert_true(sha256_hex((restored + "\n").as_bytes()) != _AFTER_SHA256)
    var changed = restored + "\nvar unreviewed = 1\n"
    assert_true(sha256_hex(changed.as_bytes()) != _AFTER_SHA256)
    assert_true(token_sha256(changed) != _AFTER_TOKEN)
    var ledger = Path(_LEDGER).read_text()
    assert_true(sha256_hex((ledger + " ").as_bytes()) != _LEDGER_SHA256)
    var refused = False
    try:
        var extra = ledger + " "
        if sha256_hex(extra.as_bytes()) != _LEDGER_SHA256:
            raise Error("reviewed consumer successor ledger: unreviewed ledger")
    except error:
        refused = String(error).find("unreviewed ledger") >= 0
    assert_true(refused)
    var paths = List[String]()
    paths.append(_REUSE)
    paths.append(_CACHE)
    paths.append(_MOTION)
    var digests = List[String]()
    digests.append(_REUSE_SHA256)
    digests.append(_CACHE_SHA256)
    digests.append(_MOTION_SHA256)
    var index = 0
    while index < len(paths):
        var raw = Path(paths[index]).read_text()
        assert_true(sha256_hex((raw + "\n").as_bytes()) != digests[index])
        index += 1


def main() raises:
    """Run the consumer ledger tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
