# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the coverage-followup record and its component digests.

    carla_followup_gate --migration PATH [--prior PATH] [--components DIR]
    carla_followup_gate --bytes PATH --sha HEX --kind after|before --label TEXT
    carla_followup_gate --tokens DIR
    carla_followup_gate --pair DIR
    carla_followup_gate --places DIR

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
An absent prior skips the prior digest and the component digests.
A prior without a component directory checks only that prior digest.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
)
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "911929b7dc80b5c6e09e0cf27b2c8e1f9db52cd8df398d397fc70c900fed759e"
)


def _fail(message: String) raises:
    """Raise one coverage-followup failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("coverage followup successor: " + message)


def _source_name(index: Int) raises -> String:
    """Return one reviewed source path.

    Args:
        index: The path position, from 0 through 5.

    Returns:
        The repository path.

    Raises:
        Error: The position is outside the reviewed set.
    """
    if index == 0:
        return "extensions/carla/curve_sample_dispatch.mojo"
    if index == 1:
        return "extensions/carla/spiral_moment_proof.mojo"
    if index == 2:
        return "extensions/carla/curve_bounds.mojo"
    if index == 3:
        return "extensions/carla/lane_refinement.mojo"
    if index == 4:
        return "extensions/carla/spiral_grouped_roundoff_proof.mojo"
    if index == 5:
        return "extensions/carla/spiral_roundoff_proof.mojo"
    raise Error("coverage followup successor: wrong exact successor set")


def _sources_match(doc: PyJson, node: Int) raises -> Bool:
    """Return whether the source keys are the reviewed set.

    Args:
        doc: The record.
        node: The sources object.

    Returns:
        True when the keys are exactly the six reviewed paths.

    Raises:
        Error: The reviewed path table is unusable.
    """
    if doc.kind(node) != PY_DICT or doc.length(node) != 6:
        return False
    var index = 0
    while index < 6:
        if doc.get(node, _source_name(index)) == MISSING:
            return False
        index += 1
    return True


def _require_record(doc: PyJson) raises:
    """Require schema 1 and the reviewed source set.

    Args:
        doc: The migration record.

    Raises:
        Error: The schema or the source set changed.
    """
    var schema = doc.get(doc.root, "schema")
    var sources = doc.get(doc.root, "sources")
    if (
        schema == MISSING
        or doc.kind(schema) != PY_INT
        or doc.text(schema) != "1"
        or sources == MISSING
        or not _sources_match(doc, sources)
    ):
        _fail("wrong exact successor set")


def _require_prior(doc: PyJson, prior: Span[UInt8, _]) raises:
    """Require the prior invariant digest.

    Args:
        doc: The migration record.
        prior: The historical invariant migration bytes.

    Raises:
        Error: The digest changed.
    """
    var field = doc.get(doc.root, "prior_invariant_migration_sha256")
    if (
        field == MISSING
        or doc.kind(field) != PY_STR
        or doc.text(field) != sha256_hex(prior)
    ):
        _fail("historical invariant record changed")


def _require_components(doc: PyJson, component_dir: String) raises:
    """Require each component migration digest.

    Args:
        doc: The migration record.
        component_dir: The directory that holds one file per component name.

    Raises:
        Error: A component digest changed, or a component file cannot be read.
    """
    var node = doc.get(doc.root, "components")
    if node == MISSING or doc.kind(node) != PY_DICT:
        _fail("component migration record changed: ")
    var index = 0
    var count = doc.length(node)
    while index < count:
        var name = doc.key(node, index)
        var digest = doc.value(node, index)
        if (
            doc.kind(digest) != PY_STR
            or name.byte_length() == 0
            or name.find("/") >= 0
        ):
            _fail("component migration record changed: " + name)
        var payload = Path(component_dir + "/" + name).read_bytes()
        if sha256_hex(payload) != doc.text(digest):
            _fail("component migration record changed: " + name)
        index += 1


def followup_record(
    migration: Span[UInt8, _],
    prior: Span[UInt8, _],
    component_dir: String,
    check_prior: Bool,
) raises:
    """Require the coverage-followup record.

    Args:
        migration: The successor record bytes.
        prior: The prior invariant migration. Used only when `check_prior` is true.
        component_dir: The component directory. Empty skips the component digests.
        check_prior: Whether to check the prior digest.

    Raises:
        Error: The record, the prior digest, or a component digest changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed migration record")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    _require_record(doc)
    if not check_prior:
        return
    _require_prior(doc, prior)
    if component_dir.byte_length() == 0:
        return
    _require_components(doc, component_dir)


def followup_digest(
    payload: Span[UInt8, _],
    expected: String,
    kind: String,
    label: String,
) raises:
    """Require one reconstructed pin digest.

    Args:
        payload: The pin bytes.
        expected: The required SHA-256 hex digest.
        kind: `after` for the active pin, `before` for the reconstruction.
        label: The pin filename. Used when the active pin changed.

    Raises:
        Error: The digest changed.
    """
    if sha256_hex(payload) == expected:
        return
    if kind == "before":
        _fail("historical pin reconstruction failed")
    _fail("unreviewed runtime pin successor: " + label)


def followup_tokens(directory: String) raises:
    """Require each successor text to have its recorded token digest.

    Args:
        directory: A directory with `labels.json` and `N.text` files.

    Raises:
        Error: A token digest changed, or the directory cannot be read.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("complete successor changed")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var row = doc.item(doc.root, index)
        var path = doc.text(doc.at(row, "path"))
        var expected = doc.text(doc.at(row, "token"))
        var text = Path(directory + "/" + String(index) + ".text").read_text()
        if token_sha256(text) != expected:
            _fail("complete successor changed: " + path)
        index += 1


def followup_pair(directory: String) raises:
    """Require the fixed runtime then guard pin order.

    Args:
        directory: A directory whose `labels.json` is the pin-file names in order.

    Raises:
        Error: The names are not the reviewed pair, or the list cannot be read.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if (
        doc.kind(doc.root) != PY_LIST
        or doc.length(doc.root) != 2
        or doc.text(doc.item(doc.root, 0)) != "runtime-source-pins.json"
        or doc.text(doc.item(doc.root, 1)) != "sum2-guard-pins.json"
    ):
        _fail("wrong fixed ordered pin pair")


def followup_places(directory: String) raises:
    """Require each pin placement to be unique and current.

    Args:
        directory: A directory whose `labels.json` lists the placements in order.

    Raises:
        Error: A placement is repeated or its current value changed.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("active pin placement mismatch")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var row = doc.item(doc.root, index)
        var duplicate = doc.at(row, "duplicate")
        if doc.kind(duplicate) == PY_BOOL and doc.flag(duplicate):
            _fail("duplicate pin placement")
        if doc.text(doc.at(row, "actual")) != doc.text(doc.at(row, "expected")):
            _fail("active pin placement mismatch")
        index += 1


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_followup_gate --migration PATH [--prior PATH]"
            " [--components DIR] | --bytes PATH --sha HEX --kind after|before"
            " --label TEXT | --tokens DIR | --pair DIR | --places DIR"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the coverage-followup record and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var prior = String("")
    var components = String("")
    var payload = String("")
    var digest = String("")
    var kind = String("")
    var label = String("")
    var tokens = String("")
    var pair = String("")
    var places = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--prior"
            or word == "--components"
            or word == "--bytes"
            or word == "--sha"
            or word == "--kind"
            or word == "--label"
            or word == "--tokens"
            or word == "--pair"
            or word == "--places"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--prior":
                prior = value
            elif word == "--components":
                components = value
            elif word == "--bytes":
                payload = value
            elif word == "--sha":
                digest = value
            elif word == "--kind":
                kind = value
            elif word == "--label":
                label = value
            elif word == "--tokens":
                tokens = value
            elif word == "--pair":
                pair = value
            else:
                places = value
            index += 2
            continue
        _usage()
    var modes = 0
    if migration.byte_length() > 0:
        modes += 1
    if payload.byte_length() > 0:
        modes += 1
    if tokens.byte_length() > 0:
        modes += 1
    if pair.byte_length() > 0:
        modes += 1
    if places.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if payload.byte_length() > 0 and (
        digest.byte_length() == 0
        or label.byte_length() == 0
        or (kind != "after" and kind != "before")
        or tokens.byte_length() > 0
    ):
        _usage()
    if tokens.byte_length() > 0 and (
        migration.byte_length() > 0
        or prior.byte_length() > 0
        or components.byte_length() > 0
        or payload.byte_length() > 0
        or pair.byte_length() > 0
    ):
        _usage()
    if pair.byte_length() > 0 and (
        migration.byte_length() > 0
        or prior.byte_length() > 0
        or components.byte_length() > 0
        or payload.byte_length() > 0
        or tokens.byte_length() > 0
        or places.byte_length() > 0
    ):
        _usage()
    if places.byte_length() > 0 and (
        migration.byte_length() > 0
        or prior.byte_length() > 0
        or components.byte_length() > 0
        or payload.byte_length() > 0
        or tokens.byte_length() > 0
        or pair.byte_length() > 0
    ):
        _usage()
    if migration.byte_length() > 0 and (
        components.byte_length() > 0 and prior.byte_length() == 0
    ):
        _usage()
    try:
        if places.byte_length() > 0:
            followup_places(places)
            return
        if pair.byte_length() > 0:
            followup_pair(pair)
            return
        if tokens.byte_length() > 0:
            followup_tokens(tokens)
            return
        if payload.byte_length() > 0:
            followup_digest(Path(payload).read_bytes(), digest, kind, label)
            return
        if prior.byte_length() == 0:
            followup_record(
                Path(migration).read_bytes(), String("").as_bytes(), "", False
            )
        elif components.byte_length() == 0:
            followup_record(
                Path(migration).read_bytes(),
                Path(prior).read_bytes(),
                "",
                True,
            )
        else:
            followup_record(
                Path(migration).read_bytes(),
                Path(prior).read_bytes(),
                components,
                True,
            )
    except error:
        print(String(error), file=stderr)
        exit(1)
