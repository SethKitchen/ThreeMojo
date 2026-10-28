# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the frozen ARC producer record.

    carla_frozen_arc_gate --migration PATH [--previous PATH]
    carla_frozen_arc_gate --bytes PATH --sha HEX --kind after|before|guard
    carla_frozen_arc_gate --source PATH --token HEX
    carla_frozen_arc_gate --prior HEX --cleanup HEX
    carla_frozen_arc_gate --places DIR
    carla_frozen_arc_gate --functions DIR
    carla_frozen_arc_gate --layout PATH --stored PATH
    carla_frozen_arc_gate --routing PATH
    carla_frozen_arc_gate --predecessor DIR

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
An absent previous file checks only the migration record.
`DIR` holds `payload` and `request.json`. The program prints the
predecessor.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import declaration_routing, token_sha256
from tools._carla_assets import dumps_indent
from tools._python_json import (
    MISSING,
    PY_DICT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
    loads,
)
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "70091e23400193257514363570187b47890e3c08c352fe79eb08bf291737cc9f"
)
comptime _SOURCE = "extensions/carla/curve_frozen_arc.mojo"


def _fail(message: String) raises:
    """Raise one frozen-ARC failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("frozen ARC producer contract: " + message)


def _require_record(doc: PyJson) raises:
    """Require schema 1.

    Args:
        doc: The migration record.

    Raises:
        Error: The schema changed.
    """
    var schema = doc.get(doc.root, "schema")
    if (
        schema == MISSING
        or doc.kind(schema) != PY_INT
        or doc.text(schema) != "1"
    ):
        _fail("unsupported migration schema")


def _require_previous(doc: PyJson, previous: Span[UInt8, _]) raises:
    """Require the cleanup digest and the successor path.

    Args:
        doc: The migration record.
        previous: The historical cleanup migration bytes.

    Raises:
        Error: The digest or the successor path changed.
    """
    var field = doc.get(doc.root, "previous_cleanup_migration_sha256")
    if (
        field == MISSING
        or doc.kind(field) != PY_STR
        or doc.text(field) != sha256_hex(previous)
    ):
        _fail("historical three-file cleanup changed")
    var successor = doc.get(doc.root, "source_successor")
    if successor == MISSING or doc.kind(successor) != PY_DICT:
        _fail("wrong successor source")
    var path = doc.get(successor, "path")
    if path == MISSING or doc.kind(path) != PY_STR or doc.text(path) != _SOURCE:
        _fail("wrong successor source")


def frozen_arc_record(
    migration: Span[UInt8, _],
    previous: Span[UInt8, _],
    check_previous: Bool,
) raises:
    """Require the frozen ARC producer record.

    Args:
        migration: The successor record bytes.
        previous: The historical cleanup migration. Used only when `check_previous` is true.
        check_previous: Whether to check the cleanup digest and the successor path.

    Raises:
        Error: The record, the cleanup digest, or the successor path changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed migration record")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    _require_record(doc)
    if not check_previous:
        return
    _require_previous(doc, previous)


def frozen_arc_digest(
    payload: Span[UInt8, _], expected: String, kind: String
) raises:
    """Require one frozen ARC pin digest.

    Args:
        payload: The pin bytes.
        expected: The required SHA-256 hex digest.
        kind: `after` for the active runtime pin, `before` for the reconstruction, or `guard` for the unchanged guard pin.

    Raises:
        Error: The digest changed.
    """
    if sha256_hex(payload) == expected:
        return
    if kind == "after":
        _fail("unreviewed runtime pin successor")
    if kind == "before":
        _fail("runtime predecessor reconstruction failed")
    _fail("guard pin lineage changed")


def frozen_arc_token(text: String, expected: String) raises:
    """Require the frozen ARC successor token digest.

    Args:
        text: The historical module source.
        expected: The required token digest.

    Raises:
        Error: The token digest changed.
    """
    if token_sha256(text) != expected:
        raise Error(
            "frozen ARC producer contract: complete frozen ARC successor"
            " changed"
        )


def frozen_arc_prior(actual: String, expected: String) raises:
    """Require the runtime pin predecessor to match the cleanup record.

    Args:
        actual: The digest supplied by the caller.
        expected: The digest stored in the producer record.

    Raises:
        Error: The digests differ.
    """
    if actual != expected:
        _fail("runtime pin predecessor differs from accepted cleanup")


def _place_group(index: Int) -> String:
    """Return one reviewed runtime-successor group.

    Args:
        index: The group position, from 0 through 2.

    Returns:
        The group name.
    """
    if index == 0:
        return "eligibility"
    if index == 1:
        return "optional_runtime"
    return "translation"


def _places_match(doc: PyJson) raises -> Bool:
    """Return whether the rows are the three reviewed placements.

    Args:
        doc: The placement list.

    Returns:
        True when the rows are exactly the reviewed group and path pairs.

    Raises:
        Error: A row cannot be read.
    """
    if doc.kind(doc.root) != PY_LIST or doc.length(doc.root) != 3:
        return False
    var seen = String("")
    var index = 0
    while index < 3:
        var row = doc.item(doc.root, index)
        var group = doc.text(doc.at(row, "group"))
        var path = doc.text(doc.at(row, "path"))
        if path != "extensions/carla/curve_frozen_arc.mojo":
            return False
        var slot = 0
        var found = False
        while slot < 3:
            if group == _place_group(slot):
                found = True
                break
            slot += 1
        if not found or seen.find(String(slot)) >= 0:
            return False
        seen = seen + String(slot)
        index += 1
    return seen.byte_length() == 3


def _require_places(doc: PyJson) raises:
    """Require the runtime successor placements and their token values.

    Args:
        doc: The placement list.

    Raises:
        Error: The placement set changed, or a token value changed.
    """
    if not _places_match(doc):
        _fail("wrong runtime successor placements")
    var index = 0
    while index < 3:
        var row = doc.item(doc.root, index)
        if doc.text(doc.at(row, "actual")) != doc.text(doc.at(row, "expected")):
            _fail("runtime successor token mismatch")
        index += 1


def frozen_arc_places(directory: String) raises:
    """Require the runtime successor placements and their token values.

    Args:
        directory: A directory whose `labels.json` lists the placements.

    Raises:
        Error: The placement set changed, or a token value changed.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    _require_places(doc)


def _placement_rows(
    pins: PyJson, request: PyJson, transitions: Int, groups_key: String
) raises -> PyJson:
    """Return one placement row for each runtime successor.

    Args:
        pins: The active runtime pin document.
        request: The predecessor request.
        transitions: The transition list in `request`.
        groups_key: The pin object that holds the groups.

    Returns:
        A list of `group`, `path`, `actual`, and `expected`.

    Raises:
        Error: A transition or a pin path cannot be read.
    """
    var rows = PyJson()
    var root = rows.new_list()
    var count = request.length(transitions)
    var index = 0
    while index < count:
        var change = request.item(transitions, index)
        var group = request.text(request.at(change, "group"))
        var path = request.text(request.at(change, "path"))
        var expected = request.text(request.at(change, "after"))
        var actual = pins.text(
            pins.at(pins.at(pins.at(pins.root, groups_key), group), path)
        )
        var row = rows.new_dict()
        rows.set(row, "group", rows.new_str(group))
        rows.set(row, "path", rows.new_str(path))
        rows.set(row, "actual", rows.new_str(actual))
        rows.set(row, "expected", rows.new_str(expected))
        rows.append(root, row)
        index += 1
    rows.root = root
    return rows^


def _write_historical_values(
    mut pins: PyJson, request: PyJson, transitions: Int, groups_key: String
) raises:
    """Write each transition's historical token into the pins.

    Args:
        pins: The active runtime pin document.
        request: The predecessor request.
        transitions: The transition list in `request`.
        groups_key: The pin object that holds the groups.

    Raises:
        Error: A transition or a pin path cannot be read.
    """
    var count = request.length(transitions)
    var index = 0
    while index < count:
        var change = request.item(transitions, index)
        var group = request.text(request.at(change, "group"))
        var path = request.text(request.at(change, "path"))
        var parent = pins.at(pins.root, groups_key)
        parent = pins.at(parent, group)
        pins.set(
            parent, path, pins.adopt(request, request.at(change, "before"))
        )
        index += 1


def frozen_runtime_predecessor(
    payload: Span[UInt8, _], request: String
) raises -> String:
    """Rebuild one frozen runtime pin predecessor.

    Args:
        payload: The active runtime pin bytes.
        request: JSON with `after`, `before`, `groups`, and `transitions`.

    Returns:
        The predecessor as `json.dumps` writes it with `indent=2`, plus a newline.

    Raises:
        Error: The digest, the placements, or a pin transition changed.
    """
    var spec = PyJson.parse(request)
    var after = spec.text(spec.at(spec.root, "after"))
    if sha256_hex(payload) != after:
        _fail("unreviewed runtime pin successor")
    var pins = loads(payload)
    var groups_key = spec.text(spec.at(spec.root, "groups"))
    var transitions = spec.at(spec.root, "transitions")
    var rows = _placement_rows(pins, spec, transitions, groups_key)
    _require_places(rows)
    _write_historical_values(pins, spec, transitions, groups_key)
    var predecessor = dumps_indent(pins, pins.root, 2) + "\n"
    var before = spec.text(spec.at(spec.root, "before"))
    if sha256_hex(predecessor.as_bytes()) != before:
        _fail("runtime predecessor reconstruction failed")
    return predecessor


def frozen_arc_functions(directory: String) raises:
    """Require each producer function token list to match its record.

    Args:
        directory: A directory whose `labels.json` lists the functions in order.

    Raises:
        Error: A function token list changed, or the list cannot be read.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("complete producer/Box function changed")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var row = doc.item(doc.root, index)
        var name = doc.text(doc.at(row, "name"))
        if doc.text(doc.at(row, "actual")) != doc.text(doc.at(row, "expected")):
            _fail("complete producer/Box function changed: " + name)
        index += 1


def frozen_arc_layout(actual: String, stored: String) raises:
    """Require the RoundedArc declaration routing to match the record.

    Args:
        actual: The routing text of the live arc source.
        stored: The routing text stored in the producer record.

    Raises:
        Error: The routing changed.
    """
    if actual != stored:
        _fail(
            "RoundedArc/Box field layout, imports, or declaration owners"
            " changed"
        )


def _dependency(index: Int) -> String:
    """Return one frozen-arc dependency path.

    Args:
        index: The path position, 0 or 1.

    Returns:
        The repository path.
    """
    if index == 0:
        return "extensions/carla/polynomial.mojo"
    return "extensions/carla/road.mojo"


def frozen_arc_paths() raises -> String:
    """Return the frozen-arc source and its dependency paths.

    Returns:
        JSON with `source` and `protected` in reviewed order.

    Raises:
        Error: The lists cannot be written.
    """
    var doc = PyJson()
    var spec = doc.new_dict()
    doc.set(spec, "source", doc.new_str(_SOURCE))
    var protected = doc.new_list()
    var index = 0
    while index < 2:
        doc.append(protected, doc.new_str(_dependency(index)))
        index += 1
    doc.set(spec, "protected", protected)
    doc.root = spec
    return doc.dumps()


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_frozen_arc_gate --migration PATH [--previous PATH]"
            " | --bytes PATH --sha HEX --kind after|before|guard"
            " | --source PATH --token HEX | --prior HEX --cleanup HEX"
            " | --places DIR | --functions DIR"
            " | --layout PATH --stored PATH | --routing PATH"
            " | --predecessor DIR"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the frozen ARC record, or print one restored runtime pin.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var previous = String("")
    var payload = String("")
    var digest = String("")
    var kind = String("")
    var source = String("")
    var token = String("")
    var prior = String("")
    var cleanup = String("")
    var places = String("")
    var functions = String("")
    var layout = String("")
    var stored = String("")
    var routing = String("")
    var predecessor = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--previous"
            or word == "--bytes"
            or word == "--sha"
            or word == "--kind"
            or word == "--source"
            or word == "--token"
            or word == "--prior"
            or word == "--cleanup"
            or word == "--places"
            or word == "--functions"
            or word == "--layout"
            or word == "--stored"
            or word == "--routing"
            or word == "--predecessor"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--previous":
                previous = value
            elif word == "--bytes":
                payload = value
            elif word == "--sha":
                digest = value
            elif word == "--kind":
                kind = value
            elif word == "--source":
                source = value
            elif word == "--token":
                token = value
            elif word == "--prior":
                prior = value
            elif word == "--cleanup":
                cleanup = value
            elif word == "--places":
                places = value
            elif word == "--functions":
                functions = value
            elif word == "--layout":
                layout = value
            elif word == "--stored":
                stored = value
            elif word == "--routing":
                routing = value
            else:
                predecessor = value
            index += 2
            continue
        _usage()
    var modes = 0
    if migration.byte_length() > 0:
        modes += 1
    if payload.byte_length() > 0:
        modes += 1
    if source.byte_length() > 0:
        modes += 1
    if prior.byte_length() > 0 or cleanup.byte_length() > 0:
        modes += 1
    if places.byte_length() > 0:
        modes += 1
    if functions.byte_length() > 0:
        modes += 1
    if layout.byte_length() > 0 or stored.byte_length() > 0:
        modes += 1
    if routing.byte_length() > 0:
        modes += 1
    if predecessor.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if (layout.byte_length() == 0) != (stored.byte_length() == 0):
        _usage()
    if (prior.byte_length() == 0) != (cleanup.byte_length() == 0):
        _usage()
    if payload.byte_length() > 0 and (
        digest.byte_length() == 0
        or (kind != "after" and kind != "before" and kind != "guard")
    ):
        _usage()
    if source.byte_length() > 0 and token.byte_length() == 0:
        _usage()
    if previous.byte_length() > 0 and migration.byte_length() == 0:
        _usage()
    try:
        if predecessor.byte_length() > 0:
            print(
                frozen_runtime_predecessor(
                    Path(predecessor + "/payload").read_bytes(),
                    Path(predecessor + "/request.json").read_text(),
                ),
                end="",
            )
            return
        if routing.byte_length() > 0:
            print(declaration_routing(Path(routing).read_text()), end="")
            return
        if layout.byte_length() > 0:
            frozen_arc_layout(
                Path(layout).read_text(), Path(stored).read_text()
            )
            return
        if functions.byte_length() > 0:
            frozen_arc_functions(functions)
            return
        if places.byte_length() > 0:
            frozen_arc_places(places)
            return
        if prior.byte_length() > 0:
            frozen_arc_prior(prior, cleanup)
            return
        if source.byte_length() > 0:
            frozen_arc_token(Path(source).read_text(), token)
            return
        if payload.byte_length() > 0:
            frozen_arc_digest(Path(payload).read_bytes(), digest, kind)
            return
        if previous.byte_length() == 0:
            frozen_arc_record(
                Path(migration).read_bytes(), String("").as_bytes(), False
            )
        else:
            frozen_arc_record(
                Path(migration).read_bytes(),
                Path(previous).read_bytes(),
                True,
            )
    except error:
        print(String(error), file=stderr)
        exit(1)
