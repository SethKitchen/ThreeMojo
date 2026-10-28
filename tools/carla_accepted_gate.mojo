# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the accepted successor record and its pin digests.

    carla_accepted_gate --migration PATH [--prior PATH] [--components DIR]
    carla_accepted_gate --bytes PATH --sha HEX --kind after|before --label TEXT
    carla_accepted_gate --sources DIR
    carla_accepted_gate --pair DIR
    carla_accepted_gate --places DIR
    carla_accepted_gate --predecessor DIR

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
`--predecessor` reads `payload` and `request.json` from `DIR` and prints
the earlier pin.
An absent prior skips the followup digest and the component set.
A prior without a component directory checks the followup digest and the
component set. It does not read component files.
The bytes command checks one pin digest.
The sources command checks one successor token and one historical module
digest for each entry.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._duplicate_pin_keys import reject_duplicate_pin_keys
from tools._pin_restore import restore_reviewed_pin
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
    "bb3a7b5e08a0a5400679f410da2c4574b45924294133df2f180f71fd74064d91"
)


def _fail(message: String) raises:
    """Raise one accepted-successor failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("accepted source successor: " + message)


def _source_name(index: Int) raises -> String:
    """Return one reviewed source path.

    Args:
        index: The path position, from 0 through 2.

    Returns:
        The repository path.

    Raises:
        Error: The position is outside the reviewed set.
    """
    if index == 0:
        return "extensions/carla/curve_rounded_line.mojo"
    if index == 1:
        return "extensions/carla/spiral_domain_proof.mojo"
    if index == 2:
        return "extensions/carla/spiral_grouped_roundoff_proof.mojo"
    raise Error("accepted source successor: wrong exact successor set")


def _component_name(index: Int) raises -> String:
    """Return one reviewed component name.

    Args:
        index: The component position, from 0 through 5.

    Returns:
        The component file name.

    Raises:
        Error: The position is outside the reviewed set.
    """
    if index == 0:
        return "rounded-line-singleton-migration.json"
    if index == 1:
        return "rounded-line-selector-migration.json"
    if index == 2:
        return "distance-validation-contract.json"
    if index == 3:
        return "grouped-y-successor-record.json"
    if index == 4:
        return "grouped-y-proof.md"
    if index == 5:
        return "grouped-y-exponent-ledger.json"
    raise Error("accepted source successor: wrong component set")


def _sources_match(doc: PyJson, node: Int) raises -> Bool:
    """Return whether the source keys are the reviewed set.

    Args:
        doc: The record.
        node: The sources object.

    Returns:
        True when the keys are exactly the three reviewed paths.

    Raises:
        Error: The reviewed path table is unusable.
    """
    if doc.kind(node) != PY_DICT or doc.length(node) != 3:
        return False
    var index = 0
    while index < 3:
        if doc.get(node, _source_name(index)) == MISSING:
            return False
        index += 1
    return True


def _components_match(doc: PyJson, node: Int) raises -> Bool:
    """Return whether the component keys are the reviewed set.

    Args:
        doc: The record.
        node: The components object.

    Returns:
        True when the keys are exactly the six reviewed names.

    Raises:
        Error: The reviewed component table is unusable.
    """
    if doc.kind(node) != PY_DICT or doc.length(node) != 6:
        return False
    var index = 0
    while index < 6:
        if doc.get(node, _component_name(index)) == MISSING:
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
    """Require the prior followup digest.

    Args:
        doc: The migration record.
        prior: The historical followup migration bytes.

    Raises:
        Error: The digest changed.
    """
    var field = doc.get(doc.root, "prior_followup_migration_sha256")
    if (
        field == MISSING
        or doc.kind(field) != PY_STR
        or doc.text(field) != sha256_hex(prior)
    ):
        _fail("historical followup record changed")


def _require_components(doc: PyJson, component_dir: String) raises:
    """Require each component digest.

    Args:
        doc: The migration record.
        component_dir: The directory that holds one file per component name.

    Raises:
        Error: A component digest changed, or a component file cannot be read.
    """
    var node = doc.get(doc.root, "components")
    var index = 0
    var count = doc.length(node)
    while index < count:
        var name = doc.key(node, index)
        var digest = doc.value(node, index)
        if doc.kind(digest) != PY_STR or name.find("/") >= 0:
            _fail("component record changed: " + name)
        var payload = Path(component_dir + "/" + name).read_bytes()
        if sha256_hex(payload) != doc.text(digest):
            _fail("component record changed: " + name)
        index += 1


def accepted_record(
    migration: Span[UInt8, _],
    prior: Span[UInt8, _],
    component_dir: String,
    check_prior: Bool,
) raises:
    """Require the accepted successor record.

    Args:
        migration: The successor record bytes.
        prior: The followup migration. Used only when `check_prior` is true.
        component_dir: The component directory. Empty skips the component digests.
        check_prior: Whether to check the followup digest and the component set.

    Raises:
        Error: The record digest, a repeated key, the followup digest, or a component digest changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed migration record")
    reject_duplicate_pin_keys(migration)
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    _require_record(doc)
    if not check_prior:
        return
    _require_prior(doc, prior)
    var node = doc.get(doc.root, "components")
    if node == MISSING or not _components_match(doc, node):
        _fail("wrong component set")
    if component_dir.byte_length() == 0:
        return
    _require_components(doc, component_dir)


def accepted_digest(
    payload: Span[UInt8, _],
    expected: String,
    kind: String,
    label: String,
) raises:
    """Require one pin digest.

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
        _fail("historical pins failed reconstruction")
    _fail("unreviewed runtime pin successor: " + label)


def accepted_sources(directory: String) raises:
    """Require each successor token and historical module digest.

    Args:
        directory: A directory with `labels.json`, `N.text`, and `N.module`.

    Raises:
        Error: A token or a module digest changed, or the directory cannot be read.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("unreviewed complete successor")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var row = doc.item(doc.root, index)
        var path = doc.text(doc.at(row, "path"))
        var expected = doc.text(doc.at(row, "token"))
        var module_sha = doc.text(doc.at(row, "module_sha"))
        var text = Path(directory + "/" + String(index) + ".text").read_text()
        if token_sha256(text) != expected:
            _fail("unreviewed complete successor: " + path)
        var module = Path(
            directory + "/" + String(index) + ".module"
        ).read_bytes()
        if sha256_hex(module) != module_sha:
            _fail("historical module changed: " + path)
        index += 1


def accepted_pair(directory: String) raises:
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


def accepted_places(directory: String) raises:
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


def accepted_pin_predecessor(
    payload: Span[UInt8, _], request: String
) raises -> String:
    """Rebuild one accepted pin predecessor.

    Args:
        payload: The active pin bytes.
        request: JSON with `after`, `before`, `label`, and `transitions`.

    Returns:
        The predecessor as `json.dumps` writes it with `indent=2`, plus a
        newline.

    Raises:
        Error: The digest, a repeated key, a placement, or the restored
            bytes changed. The digest is checked before a repeated key. A
            repeated key is refused before the pin is placed. The restored
            digest is checked after the placements.
    """
    return restore_reviewed_pin(
        payload,
        request,
        "accepted source successor: ",
        "historical pins failed reconstruction",
    )


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_accepted_gate --migration PATH [--prior PATH]"
            " [--components DIR] | --bytes PATH --sha HEX --kind after|before"
            " --label TEXT | --sources DIR | --pair DIR | --places DIR"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the accepted successor record and print nothing on success.

    `--predecessor` prints the earlier pin.

    Raises:
        Error: The command is invalid.
    """
    var arguments = argv()
    if len(arguments) == 3 and arguments[1] == "--predecessor":
        try:
            var folder = String(arguments[2])
            if not folder.endswith("/"):
                folder += "/"
            print(
                accepted_pin_predecessor(
                    Path(folder + "payload").read_bytes(),
                    Path(folder + "request.json").read_text(),
                ),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    var migration = String("")
    var prior = String("")
    var components = String("")
    var payload = String("")
    var digest = String("")
    var kind = String("")
    var label = String("")
    var sources = String("")
    var pair = String("")
    var places = String("")
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
            or word == "--sources"
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
            elif word == "--sources":
                sources = value
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
    if sources.byte_length() > 0:
        modes += 1
    if pair.byte_length() > 0:
        modes += 1
    if places.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if payload.byte_length() > 0 and (
        prior.byte_length() > 0
        or components.byte_length() > 0
        or sources.byte_length() > 0
        or digest.byte_length() == 0
        or label.byte_length() == 0
        or (kind != "after" and kind != "before")
    ):
        _usage()
    if sources.byte_length() > 0 and (
        migration.byte_length() > 0
        or prior.byte_length() > 0
        or components.byte_length() > 0
        or payload.byte_length() > 0
        or digest.byte_length() > 0
        or kind.byte_length() > 0
        or label.byte_length() > 0
        or pair.byte_length() > 0
    ):
        _usage()
    if pair.byte_length() > 0 and (
        migration.byte_length() > 0
        or prior.byte_length() > 0
        or components.byte_length() > 0
        or payload.byte_length() > 0
        or digest.byte_length() > 0
        or kind.byte_length() > 0
        or label.byte_length() > 0
        or sources.byte_length() > 0
        or places.byte_length() > 0
    ):
        _usage()
    if places.byte_length() > 0 and (
        migration.byte_length() > 0
        or prior.byte_length() > 0
        or components.byte_length() > 0
        or payload.byte_length() > 0
        or digest.byte_length() > 0
        or kind.byte_length() > 0
        or label.byte_length() > 0
        or sources.byte_length() > 0
        or pair.byte_length() > 0
    ):
        _usage()
    if migration.byte_length() > 0 and (
        digest.byte_length() > 0
        or kind.byte_length() > 0
        or label.byte_length() > 0
    ):
        _usage()
    if components.byte_length() > 0 and prior.byte_length() == 0:
        _usage()
    try:
        if places.byte_length() > 0:
            accepted_places(places)
            return
        if pair.byte_length() > 0:
            accepted_pair(pair)
            return
        if sources.byte_length() > 0:
            accepted_sources(sources)
            return
        if payload.byte_length() > 0:
            accepted_digest(Path(payload).read_bytes(), digest, kind, label)
            return
        if prior.byte_length() == 0:
            accepted_record(
                Path(migration).read_bytes(), String("").as_bytes(), "", False
            )
        elif components.byte_length() == 0:
            accepted_record(
                Path(migration).read_bytes(), Path(prior).read_bytes(), "", True
            )
        else:
            accepted_record(
                Path(migration).read_bytes(),
                Path(prior).read_bytes(),
                components,
                True,
            )
    except error:
        print(String(error), file=stderr)
        exit(1)
