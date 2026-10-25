# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The render-actor reuse record ends at the restored ledger endpoint."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import token_sha256
from tests._render_actor_predecessor import restored_render_actors
from tools._python_json import PY_INT, PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/render-actor-reuse-successor.json"
"""The reviewed render-actor reuse record."""
comptime _RECORD_SHA256 = (
    "c4d146fe145289a1ad443956d2941d1e90186d448b8056f8be97d72f4f672771"
)
"""The SHA-256 of that record."""
comptime _MODULE = "extensions/carla/render_actors.mojo"
"""The render-actor consumer this record names."""
comptime _BEFORE_SHA256 = (
    "ae1f86645cb6c7dac99a741619595be18a61c558c56262c27a50fa9b9bacef3b"
)
"""The SHA-256 where the border and winner records pin this consumer."""
comptime _AFTER_SHA256 = (
    "0169a2466ef2cfe970e5e53b3311ea8cf81e481d11f668c531c2ca545497cdcc"
)
"""The SHA-256 of the restored ledger endpoint."""
comptime _BEFORE_TOKEN = (
    "f77b3bea2a872f7b2a026cbfba75aa7a98ab9339f1c7aa21d1fae2bb6cb4cd1e"
)
"""The token digest of that pin."""
comptime _AFTER_TOKEN = (
    "8b8a3b10474f988da8ebe3868e4ca277819c6096105e0940bf9acb7783f435d2"
)
"""The token digest of the restored endpoint."""
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
comptime _CACHE = "tests/test_carla_model_cache.mojo"
"""A bound model-cache test."""
comptime _MOTION = "tests/test_carla_walker_render_motion.mojo"
"""A bound walker-motion test."""


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


def _record() raises -> PyJson:
    """Return the reuse record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error(
            "reviewed render actor reuse successor: unreviewed exact edge"
        )
    return PyJson.parse(Path(_RECORD).read_text())


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
    if sha256_hex(Path(path).read_bytes()) != digest:
        raise Error(
            "reviewed render actor reuse successor: historical consumer record"
            " changed: "
            + path
        )
    var doc = PyJson.parse(Path(path).read_text())
    return _field(doc, doc.at(doc.root, group), _MODULE)


def test_the_reuse_record_ends_at_the_restored_endpoint() raises:
    """The reuse record names the restored render-actor endpoint."""
    var doc = _record()
    var schema = doc.at(doc.root, "schema")
    if doc.kind(schema) != PY_INT or doc.text(schema) != "1":
        raise Error(
            "reviewed render actor reuse successor: unexpected successor scope"
        )
    if doc.text(doc.at(doc.root, "issue")) != "306":
        raise Error(
            "reviewed render actor reuse successor: unexpected successor scope"
        )
    if doc.get(doc.root, "scope") < 0:
        raise Error(
            "reviewed render actor reuse successor: unexpected successor scope"
        )
    var edges = doc.at(doc.root, "edges")
    if doc.length(edges) != 1:
        raise Error(
            "reviewed render actor reuse successor: unexpected successor scope"
        )
    var edge = doc.at(edges, _MODULE)
    assert_equal(_field(doc, edge, "before_sha256"), _BEFORE_SHA256)
    assert_equal(_field(doc, edge, "after_sha256"), _AFTER_SHA256)
    assert_equal(_field(doc, edge, "before_token_sha256"), _BEFORE_TOKEN)
    assert_equal(_field(doc, edge, "after_token_sha256"), _AFTER_TOKEN)
    assert_true(_BEFORE_SHA256 != _AFTER_SHA256)
    assert_true(_BEFORE_TOKEN != _AFTER_TOKEN)
    var restored = restored_render_actors()
    assert_equal(sha256_hex(restored.as_bytes()), _AFTER_SHA256)
    assert_equal(token_sha256(restored), _AFTER_TOKEN)
    assert_equal(
        _pin(_BORDER, _BORDER_SHA256, "unchanged_inputs"), _BEFORE_SHA256
    )
    assert_equal(
        _pin(_WINNER, _WINNER_SHA256, "canonical_source_unchanged"),
        _BEFORE_SHA256,
    )
    var tests = doc.at(doc.root, "correctness_tests")
    assert_equal(doc.length(tests), 3)
    assert_equal(
        sha256_hex(Path(_REUSE).read_bytes()), _field(doc, tests, _REUSE)
    )
    assert_equal(
        sha256_hex(Path(_CACHE).read_bytes()), _field(doc, tests, _CACHE)
    )
    assert_equal(
        sha256_hex(Path(_MOTION).read_bytes()), _field(doc, tests, _MOTION)
    )


def test_a_changed_reuse_record_or_endpoint_is_refused() raises:
    """A changed record, endpoint, or bound test changes its digest."""
    var restored = restored_render_actors()
    var changed = restored + "\nvar unreviewed = 1\n"
    assert_true(sha256_hex(changed.as_bytes()) != _AFTER_SHA256)
    assert_true(token_sha256(changed) != _AFTER_TOKEN)
    var record = Path(_RECORD).read_text()
    assert_true(sha256_hex((record + " ").as_bytes()) != _RECORD_SHA256)
    var doc = _record()
    var tests = doc.at(doc.root, "correctness_tests")
    var paths = List[String]()
    paths.append(_REUSE)
    paths.append(_CACHE)
    paths.append(_MOTION)
    for path in paths:
        var raw = Path(path).read_text()
        assert_true(
            sha256_hex((raw + "\n").as_bytes()) != _field(doc, tests, path)
        )


def main() raises:
    """Run the render-actor reuse record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
