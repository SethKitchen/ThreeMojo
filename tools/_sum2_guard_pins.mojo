# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the Sum2 guard pin and the live helper graph.

The pin keys, schema, and lineage hashes stay fixed. The live helper keeps
the pinned token graph.
"""

from std.pathlib import Path

from tests._python_tokens import _tokenize
from tools._python_json import PY_DICT, PY_INT, PY_STR, PyJson
from tools._sha256 import sha256_hex


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _HELPER = "extensions/carla/curve_sum2.mojo"
comptime _WINNER = "tools/carla_lane_oracle/winner-sign-query-migration.json"
comptime _MANIFEST = (
    "98933650efb2cad39d62a4fe1ddc18c35331cd79dac3fb8b021284148f6b6109"
)
comptime _FORMAT = (
    "60448936958e8748ef0a419e6679ec6542e72615ac89a80a7bb24a79581a4e06"
)
comptime _PUBLIC = (
    "4cc4cefa6199c1cfbcfd05a636254d1a061889b9a51951d8ceb723544aa6c3dd"
)
comptime _FREEZE = (
    "eb64ab48aa4e09ea5c064a8ad7c7801bb7c04fdf5a14c7f61494ba8186930aef"
)
comptime _REMOVAL = (
    "3407eccdc3a2e58acfea1922f6e9f9cb7b9b5601c2c377b8da64ab5e7fb605f8"
)
comptime _WINNER_SHA = (
    "b154b18213f9f0400661aff93e47b86bf83990c8838dfa0fca00b0fe6710b9a3"
)


def _fail(message: String) raises:
    """Raise a Sum2 guard pin error.

    Args:
        message: The failure text.

    Raises:
        Error: The Sum2 guard pin changed.
    """
    raise Error(message)


def _keys(doc: PyJson, node: Int) -> List[String]:
    """Return the keys of one dict.

    Args:
        doc: The pin document.
        node: The dict node.

    Returns:
        The keys, in document order.
    """
    var keys = List[String]()
    var index = 0
    var count = doc.length(node)
    while index < count:
        keys.append(doc.key(node, index))
        index += 1
    return keys^


def _has(keys: List[String], name: String) -> Bool:
    """Return whether `name` is a key.

    Args:
        keys: The keys.
        name: The name to find.

    Returns:
        True when the name is present.
    """
    var index = 0
    while index < len(keys):
        if keys[index] == name:
            return True
        index += 1
    return False


def _same(actual: List[String], expected: List[String]) -> Bool:
    """Return whether the two key lists hold the same set.

    Args:
        actual: The document keys.
        expected: The reviewed keys.

    Returns:
        True when the sets are equal.
    """
    if len(actual) != len(expected):
        return False
    var index = 0
    while index < len(expected):
        if not _has(actual, expected[index]):
            return False
        index += 1
    return True


def _pin_keys() -> List[String]:
    """Return the reviewed pin keys.

    Returns:
        The key set.
    """
    var keys = List[String]()
    keys.append("schema")
    keys.append("source_manifest_sha256")
    keys.append("format_manifest_sha256")
    keys.append("public_doc_migration_sha256")
    keys.append("final_source_freeze_sha256")
    keys.append("containing_model_removal_sha256")
    keys.append("winner_sign_migration_sha256")
    keys.append("scope")
    keys.append("helper_source")
    keys.append("callers")
    keys.append("protected_inventory")
    return keys^


def _callers() -> List[String]:
    """Return the reviewed caller modules.

    Returns:
        The module names.
    """
    var names = List[String]()
    names.append("lane_geometry")
    names.append("curve_bounds")
    names.append("lane_refinement")
    names.append("map")
    names.append("map_builder")
    names.append("spiral_domain_proof")
    names.append("spiral_moment_proof")
    names.append("spiral_moment_table")
    names.append("spiral_roundoff_proof")
    names.append("curve_objective_model")
    names.append("curve_minimizer_support")
    names.append("curve_sample_dispatch")
    names.append("spiral_grouped_lane")
    names.append("spiral_grouped_roundoff_proof")
    return names^


def _sha(
    doc: PyJson, root: Int, key: String, expected: String, message: String
) raises:
    """Require one hex pin.

    Args:
        doc: The pin document.
        root: The document root.
        key: The pin key.
        expected: The reviewed digest.
        message: The failure text.

    Raises:
        Error: The pin is missing or different.
    """
    var node = doc.at(root, key)
    if doc.kind(node) != PY_STR or doc.text(node) != expected:
        _fail(message)


def _tokens(
    source: String, mut kinds: List[Int], mut texts: List[String]
) raises:
    """Tokenize `source`, dropping comments.

    Args:
        source: Module source.
        kinds: The token kinds, replaced by this call.
        texts: The token texts, replaced by this call.

    Raises:
        Error: The source cannot be tokenized.
    """
    _tokenize(source, kinds, texts)


def _same_tokens(
    left_kinds: List[Int],
    left_texts: List[String],
    right_kinds: List[Int],
    right_texts: List[String],
) -> Bool:
    """Return whether two token streams match.

    Args:
        left_kinds: The first token kinds.
        left_texts: The first token texts.
        right_kinds: The second token kinds.
        right_texts: The second token texts.

    Returns:
        True when every kind and text matches.
    """
    if len(left_kinds) != len(right_kinds) or len(left_texts) != len(
        right_texts
    ):
        return False
    var index = 0
    while index < len(left_kinds):
        if (
            left_kinds[index] != right_kinds[index]
            or left_texts[index] != right_texts[index]
        ):
            return False
        index += 1
    return True


def sum2_guard_pins(root: String) raises:
    """Require the Sum2 guard pin and the live helper graph.

    Args:
        root: The repository root.

    Raises:
        Error: A pin, lineage hash, caller set, or helper token changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    if doc.kind(doc.root) != PY_DICT or not _same(
        _keys(doc, doc.root), _pin_keys()
    ):
        _fail("wrong Sum2 guard pin keys")
    var schema = doc.at(doc.root, "schema")
    if doc.kind(schema) != PY_INT or doc.text(schema) != "2":
        _fail("unsupported Sum2 guard pin schema")
    _sha(
        doc,
        doc.root,
        "source_manifest_sha256",
        _MANIFEST,
        "unreviewed Sum2 guard source manifest",
    )
    var format_ok = (
        doc.kind(doc.at(doc.root, "format_manifest_sha256")) == PY_STR
    )
    format_ok = (
        format_ok
        and doc.text(doc.at(doc.root, "format_manifest_sha256")) == _FORMAT
    )
    format_ok = (
        format_ok
        and doc.kind(doc.at(doc.root, "public_doc_migration_sha256")) == PY_STR
    )
    format_ok = (
        format_ok
        and doc.text(doc.at(doc.root, "public_doc_migration_sha256")) == _PUBLIC
    )
    format_ok = (
        format_ok
        and doc.kind(doc.at(doc.root, "final_source_freeze_sha256")) == PY_STR
    )
    format_ok = (
        format_ok
        and doc.text(doc.at(doc.root, "final_source_freeze_sha256")) == _FREEZE
    )
    if not format_ok:
        _fail("unreviewed final Sum2 format/documentation lineage")
    _sha(
        doc,
        doc.root,
        "containing_model_removal_sha256",
        _REMOVAL,
        "unreviewed containing-model removal lineage",
    )
    var winner = sha256_hex(Path(base + "/" + _WINNER).read_bytes())
    var winner_node = doc.at(doc.root, "winner_sign_migration_sha256")
    if (
        doc.kind(winner_node) != PY_STR
        or doc.text(winner_node) != _WINNER_SHA
        or winner != _WINNER_SHA
    ):
        _fail("unreviewed winner/sign-query source migration")
    var callers = doc.at(doc.root, "callers")
    if doc.kind(callers) != PY_DICT or not _same(
        _keys(doc, callers), _callers()
    ):
        _fail("wrong Sum2 guard caller modules")
    var helper = doc.at(doc.root, "helper_source")
    if doc.kind(helper) != PY_STR:
        _fail("Sum2 complete guard/helper token graph changed")
    var live_kinds = List[Int]()
    var live_texts = List[String]()
    var pin_kinds = List[Int]()
    var pin_texts = List[String]()
    _tokens(Path(base + "/" + _HELPER).read_text(), live_kinds, live_texts)
    _tokens(doc.text(helper), pin_kinds, pin_texts)
    if not _same_tokens(live_kinds, live_texts, pin_kinds, pin_texts):
        _fail("Sum2 complete guard/helper token graph changed")
