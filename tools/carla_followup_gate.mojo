# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the coverage-followup record and its component digests.

    carla_followup_gate --migration PATH [--prior PATH] [--components DIR]

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
An absent prior skips the prior digest and the component digests.
A prior without a component directory checks only that prior digest.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import PY_DICT, PY_INT, PY_STR, MISSING, PyJson
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


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_followup_gate --migration PATH [--prior PATH]"
            " [--components DIR]"
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
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--migration" or word == "--prior" or word == "--components":
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--prior":
                prior = value
            else:
                components = value
            index += 2
            continue
        _usage()
    if migration.byte_length() == 0:
        _usage()
    if components.byte_length() > 0 and prior.byte_length() == 0:
        _usage()
    try:
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
