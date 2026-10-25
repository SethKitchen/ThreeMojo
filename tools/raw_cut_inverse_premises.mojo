# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the raw-cut inverse premises.

The migration record, the environment guard, and the predecessor binding
stay fixed. The live dispatch keeps the road-info alias.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256
from tools._python_json import PY_DICT, PY_INT, PY_STR, PyJson
from tools._sha256 import sha256_hex
from tools.sum2_guard_callers import _function_text


comptime _MIGRATION = "tools/carla_lane_oracle/raw-cut-inverse-migration.json"
comptime _PREDECESSOR = (
    "tools/carla_lane_oracle/curve-support-dispatch-migration.json"
)
comptime _SOURCE = "extensions/carla/curve_sample_dispatch.mojo"
comptime _ENVIRONMENT = "extensions/carla/curve_sum2.mojo"
comptime _FIXTURE = "tests/test_carla_raw_cut_successor.mojo"
comptime _REFERENCE = "tests/test_carla_support_dispatch_successor.mojo"
comptime _MIGRATION_SHA = (
    "4f4eb051d9c1f9194796d3073fcadfa9f49dda4c44a851da0a3409ba09587dd0"
)
comptime _ALIAS = (
    "from extensions.carla.road_info import _info_index_si as info_index\n"
)
comptime _BARE = "from extensions.carla.road_info import info_index\n"
comptime _REFERENCE_NAME = "_reference_sample_dispatch_cut"


def _fail(message: String) raises:
    """Raise a raw-cut premise error.

    Args:
        message: The failure text.

    Raises:
        Error: A raw-cut inverse premise changed.
    """
    raise Error("raw cut inverse contract: " + message)


def _count(text: String, needle: String) -> Int:
    """Return how many times `needle` occurs in `text`.

    Args:
        text: The source.
        needle: The exact byte sequence.

    Returns:
        The number of non-overlapping matches.
    """
    var count = 0
    var offset = 0
    var size = text.byte_length()
    var step = needle.byte_length()
    while offset < size:
        var rest = String(text[byte=offset:])
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        offset += at + step
    return count


def _text(
    doc: PyJson, node: Int, key: String, message: String
) raises -> String:
    """Return one string field.

    Args:
        doc: The JSON document.
        node: The object that holds the field.
        key: The field name.
        message: The failure text when the field is not a string.

    Returns:
        The field text.

    Raises:
        Error: The field is missing or is not a string.
    """
    var child = doc.at(node, key)
    if doc.kind(child) != PY_STR:
        _fail(message)
    return doc.text(child)


def _admitted(source: String, after_hash: String) raises:
    """Require the live dispatch to be the recorded graph plus the alias.

    Args:
        source: The live dispatch module.
        after_hash: The recorded token digest.

    Raises:
        Error: The alias moved or the operation graph changed.
    """
    if _count(source, _ALIAS) != 1:
        _fail("raw inverse operation graph changed")
    var restored = source.replace(_ALIAS, _BARE)
    if token_sha256(restored) != after_hash:
        _fail("raw inverse operation graph changed")


def raw_cut_inverse_premises(root: String) raises:
    """Require the reviewed raw-cut inverse premises.

    Args:
        root: The repository root.

    Raises:
        Error: A migration pin, source graph, or fixture changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var migration = base + "/" + _MIGRATION
    if sha256_hex(Path(migration).read_bytes()) != _MIGRATION_SHA:
        _fail("unreviewed migration record")
    var doc = PyJson.parse(Path(migration).read_text())
    var schema = doc.at(doc.root, "schema")
    var path = doc.at(doc.root, "path")
    if (
        doc.kind(doc.root) != PY_DICT
        or doc.kind(schema) != PY_INT
        or doc.text(schema) != "1"
        or doc.kind(path) != PY_STR
        or doc.text(path) != _SOURCE
    ):
        _fail("wrong successor source or schema")
    var mismatch = "recorded source/token mismatch"
    var before = _text(doc, doc.root, "before_source", mismatch)
    var before_hash = _text(doc, doc.root, "before_token_sha256", mismatch)
    var after_hash = _text(doc, doc.root, "after_token_sha256", mismatch)
    if token_sha256(before) != before_hash:
        _fail(mismatch)
    if (
        token_sha256(_text(doc, doc.root, "after_source", mismatch))
        != after_hash
    ):
        _fail(mismatch)
    _admitted(Path(base + "/" + _SOURCE).read_text(), after_hash)
    var environment = _text(doc, doc.root, "environment_source", mismatch)
    if token_sha256(
        Path(base + "/" + _ENVIRONMENT).read_text()
    ) != token_sha256(environment):
        _fail("environment guard premise changed")
    var predecessor_hash = _text(
        doc, doc.root, "predecessor_migration_sha256", mismatch
    )
    var predecessor_path = base + "/" + _PREDECESSOR
    if sha256_hex(Path(predecessor_path).read_bytes()) != predecessor_hash:
        _fail("historical predecessor record changed")
    var predecessor = PyJson.parse(Path(predecessor_path).read_text())
    var bound = "successor is not bound to accepted predecessor"
    var sources = predecessor.at(predecessor.root, "sources")
    if (
        predecessor.kind(predecessor.root) != PY_DICT
        or predecessor.kind(sources) != PY_DICT
    ):
        _fail(bound)
    var item = predecessor.at(sources, _SOURCE)
    if predecessor.kind(item) != PY_DICT:
        _fail(bound)
    if _text(predecessor, item, "after_token_sha256", bound) != before_hash:
        _fail(bound)
    var fixture_hash = _text(
        doc, doc.root, "native_fixture_token_sha256", mismatch
    )
    if token_sha256(Path(base + "/" + _FIXTURE).read_text()) != fixture_hash:
        _fail("independent exact-word native fixture changed")
    var recorded = _text(doc, doc.root, "native_reference_source", mismatch)
    var reference = _function_text(
        Path(base + "/" + _REFERENCE).read_text(), _REFERENCE_NAME
    )
    if token_sha256(reference) != token_sha256(recorded):
        _fail("native predecessor reference changed")
