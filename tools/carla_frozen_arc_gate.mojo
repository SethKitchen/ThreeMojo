# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the frozen ARC producer record.

    carla_frozen_arc_gate --protected-bundle
    carla_frozen_arc_gate --migration PATH [--previous PATH]
    carla_frozen_arc_gate --bytes PATH --sha HEX --kind after|before|guard
    carla_frozen_arc_gate --digest-token PATH
    carla_frozen_arc_gate --labeled-digest PATH
    carla_frozen_arc_gate --source PATH --token HEX
    carla_frozen_arc_gate --prior HEX --cleanup HEX
    carla_frozen_arc_gate --places DIR
    carla_frozen_arc_gate --functions DIR
    carla_frozen_arc_gate --layout PATH --stored PATH
    carla_frozen_arc_gate --routing PATH
    carla_frozen_arc_gate --predecessor DIR
    carla_frozen_arc_gate --predecessor-labels DIR
    carla_frozen_arc_gate --predecessor-paths DIR
    carla_frozen_arc_gate --predecessor-declarations DIR
    carla_frozen_arc_gate --predecessor-declarations-paths DIR
    carla_frozen_arc_gate --review PATH
    carla_frozen_arc_gate --review-labels PATH

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
An absent previous file checks only the migration record.
`DIR` holds `payload` and `request.json`. The program prints the
predecessor. `--predecessor-labels` reads the frozen pin labels before
that predecessor. The request omits `groups`.
`--predecessor-paths` reads the frozen-arc paths after that predecessor.
`--predecessor-declarations` also holds `guard` and `sha`. It reads the
declaration catalog after that predecessor.
`--predecessor-declarations-paths` reads the frozen-arc paths after that
catalog.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import (
    declaration_routing,
    declaration_text,
    significant_json,
    token_sha256,
)
from tools._carla_assets import dumps_indent
from tools._cleanup_declarations import cleanup_declarations_after_digest
from tools._duplicate_pin_keys import reject_duplicate_pin_keys
from tools._frozen_pin_labels import frozen_pin_labels
from tools._json_tools import quote_ascii
from tools._invariant_labels import invariant_labels_with_migration
from tools._migration_records import migration_records
from tools._record_paths import record_paths
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
        Error: The record digest, a repeated key, the cleanup digest, or the successor path changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed migration record")
    reject_duplicate_pin_keys(migration)
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


def frozen_digest_and_token(payload: String) raises:
    """Check the guard pin digest, then the successor token.

    Args:
        payload: JSON with `bytes`, `sha`, `kind`, `text`, and `token`.

    Raises:
        Error: The pin digest changed, or the successor token changed.
    """
    var doc = PyJson.parse(payload)
    frozen_arc_digest(
        doc.text(doc.at(doc.root, "bytes")).as_bytes(),
        doc.text(doc.at(doc.root, "sha")),
        doc.text(doc.at(doc.root, "kind")),
    )
    frozen_arc_token(
        doc.text(doc.at(doc.root, "text")),
        doc.text(doc.at(doc.root, "token")),
    )


def frozen_labeled_digest(payload: String) raises:
    """Read the guard label, then check the pin digest and the token.

    Args:
        payload: JSON with `bytes`, `sha`, `text`, and `token`.

    Raises:
        Error: The pin digest changed, or the successor token changed.
            The guard label is read before those checks.
    """
    var labels = PyJson.parse(frozen_pin_labels())
    var doc = PyJson.parse(payload)
    var gate = PyJson()
    var body = gate.new_dict()
    gate.set(body, "bytes", gate.new_str(doc.text(doc.at(doc.root, "bytes"))))
    gate.set(body, "sha", gate.new_str(doc.text(doc.at(doc.root, "sha"))))
    gate.set(
        body, "kind", gate.new_str(labels.text(labels.at(labels.root, "guard")))
    )
    gate.set(body, "text", gate.new_str(doc.text(doc.at(doc.root, "text"))))
    gate.set(body, "token", gate.new_str(doc.text(doc.at(doc.root, "token"))))
    gate.root = body
    frozen_digest_and_token(gate.dumps())


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
        Error: The digest, a repeated key, the placements, or a pin
            transition changed. The digest is checked before a repeated
            key. A repeated key is refused before the pin is placed.
    """
    var spec = PyJson.parse(request)
    var after = spec.text(spec.at(spec.root, "after"))
    if sha256_hex(payload) != after:
        _fail("unreviewed runtime pin successor")
    reject_duplicate_pin_keys(payload)
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


def frozen_predecessor_with_labels(
    payload: Span[UInt8, _], request: String
) raises -> String:
    """Read the frozen pin labels, then rebuild the runtime predecessor.

    Args:
        payload: The active runtime pin bytes.
        request: JSON with `after`, `before`, and `transitions`.

    Returns:
        The predecessor as `json.dumps` writes it with `indent=2`, plus a
        newline.

    Raises:
        Error: The digest, a repeated key, the placements, or a pin
            transition changed. The labels are read before the
            predecessor is rebuilt. The digest is checked before a
            repeated key.
    """
    var labels = PyJson.parse(frozen_pin_labels())
    var groups = labels.text(labels.at(labels.root, "groups"))
    var supplied = request
    if request.byte_length() > 0 and request.find('"groups"') < 0:
        var opener = String(request[byte=0:1])
        if opener == "{":
            var tail = String(request[byte=1:])
            var quoted = quote_ascii(groups)
            if tail == "}":
                supplied = '{"groups":' + quoted + "}"
            else:
                supplied = '{"groups":' + quoted + "," + tail
    return frozen_runtime_predecessor(payload, supplied)


def frozen_predecessor_then_paths(
    payload: Span[UInt8, _], request: String
) raises -> String:
    """Read the pin labels, rebuild the predecessor, then return the paths.

    Args:
        payload: The active runtime pin bytes.
        request: JSON with `after`, `before`, and `transitions`.

    Returns:
        JSON with `predecessor` and `paths`. The predecessor is checked
        before the paths are read.

    Raises:
        Error: The digest, the placements, or a pin transition changed.
            The predecessor is checked before the paths are read.
    """
    var predecessor = frozen_predecessor_with_labels(payload, request)
    return (
        '{"predecessor":'
        + quote_ascii(predecessor)
        + ',"paths":'
        + frozen_arc_paths()
        + "}"
    )


def frozen_predecessor_then_declarations(
    payload: Span[UInt8, _],
    request: String,
    guard: Span[UInt8, _],
    expected: String,
) raises -> String:
    """Read the pin labels, rebuild the predecessor, then return the catalog.

    Args:
        payload: The active runtime pin bytes.
        request: JSON with `after`, `before`, and `transitions`.
        guard: The reconstructed guard-pin bytes.
        expected: The required guard-pin SHA-256 hex digest.

    Returns:
        JSON with `junction`, `unreviewed`, and `declarations`. The
        predecessor is checked before the catalog is returned.

    Raises:
        Error: The predecessor changed, or the guard digest changed. The
            predecessor is checked before the catalog is returned.
    """
    _ = frozen_predecessor_with_labels(payload, request)
    return cleanup_declarations_after_digest(guard, expected)


def frozen_declarations_then_paths(
    payload: Span[UInt8, _],
    request: String,
    guard: Span[UInt8, _],
    expected: String,
) raises -> String:
    """Rebuild the predecessor, then return the catalog and the paths.

    Args:
        payload: The active runtime pin bytes.
        request: JSON with `after`, `before`, and `transitions`.
        guard: The reconstructed guard-pin bytes.
        expected: The required guard-pin SHA-256 hex digest.

    Returns:
        JSON with `predecessor`, `catalog`, and `paths`. The predecessor
        is checked before the catalog. The paths are read after the catalog.

    Raises:
        Error: The predecessor changed, or the guard digest changed. The
            predecessor is checked before the catalog is returned.
    """
    var predecessor = frozen_predecessor_with_labels(payload, request)
    var catalog = cleanup_declarations_after_digest(guard, expected)
    return (
        '{"predecessor":'
        + quote_ascii(predecessor)
        + ',"catalog":'
        + catalog
        + ',"paths":'
        + frozen_arc_paths()
        + "}"
    )


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


def frozen_producer_review(payload: String) raises:
    """Check every producer function and the arc layout.

    Args:
        payload: JSON with `functions` and `layout`. Each function has `name` and `source`. It also has `actual`, or `module` and `owner`. `layout` has `source` and `stored`.

    Raises:
        Error: A function cannot be read, a function token list changed, the arc source cannot be routed, or the routing changed.
    """
    var doc = PyJson.parse(payload)
    var functions = doc.at(doc.root, "functions")
    if doc.kind(functions) != PY_LIST:
        _fail("complete producer/Box function changed")
    var count = doc.length(functions)
    var bodies = List[String]()
    var index = 0
    while index < count:
        var row = doc.item(functions, index)
        var actual = doc.get(row, "actual")
        if actual == MISSING:
            var owners = List[String]()
            var owner = doc.at(row, "owner")
            var owner_count = doc.length(owner)
            var cursor = 0
            while cursor < owner_count:
                owners.append(doc.text(doc.item(owner, cursor)))
                cursor += 1
            bodies.append(
                declaration_text(
                    doc.text(doc.at(row, "module")),
                    doc.text(doc.at(row, "name")),
                    owners,
                )
            )
        else:
            bodies.append(doc.text(actual))
        index += 1
    var actuals = List[String]()
    var sources = List[String]()
    index = 0
    while index < count:
        var row = doc.item(functions, index)
        actuals.append(significant_json(bodies[index]))
        sources.append(significant_json(doc.text(doc.at(row, "source"))))
        index += 1
    index = 0
    while index < count:
        var row = doc.item(functions, index)
        var name = doc.text(doc.at(row, "name"))
        if actuals[index] != sources[index]:
            _fail("complete producer/Box function changed: " + name)
        index += 1
    var layout = doc.at(doc.root, "layout")
    frozen_arc_layout(
        declaration_routing(doc.text(doc.at(layout, "source"))),
        doc.text(doc.at(layout, "stored")),
    )


def producer_review_then_labels(payload: String) raises -> String:
    """Check the producer review, then read the invariant labels.

    Args:
        payload: JSON with `functions` and `layout`, as the producer
            review reads them.

    Returns:
        JSON with `labels` and `migration`. The review runs before the
        labels.

    Raises:
        Error: A producer function or the arc layout changed. The review
            runs before the labels are read.
    """
    frozen_producer_review(payload)
    return invariant_labels_with_migration()


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


def frozen_protected_bundle() raises -> String:
    """Read the frozen-arc paths, then the migration record.

    Returns:
        JSON with `paths` and `migration`. The paths are read before
        the migration record.

    Raises:
        Error: The paths cannot be written. The paths are read before
            the migration record.
    """
    var paths = frozen_arc_paths()
    var records = PyJson.parse(migration_records())
    var migration = records.subtree(records.at(records.root, "frozen")).dumps()
    return '{"paths":' + paths + ',"migration":' + migration + "}"


def frozen_record_paths(migration: Span[UInt8, _]) raises -> String:
    """Require the frozen record, then return the companion paths.

    Args:
        migration: The successor record bytes.

    Returns:
        The companion migration record paths.

    Raises:
        Error: The migration record changed. The record is checked before
            the companion paths.
    """
    frozen_arc_record(migration, String("").as_bytes(), False)
    return record_paths()


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_frozen_arc_gate --migration PATH [--previous PATH]"
            " | --bytes PATH --sha HEX --kind after|before|guard"
            " | --digest-token PATH | --labeled-digest PATH"
            " | --source PATH --token HEX | --prior HEX --cleanup HEX"
            " | --places DIR | --functions DIR"
            " | --layout PATH --stored PATH | --routing PATH"
            " | --predecessor DIR | --predecessor-labels DIR"
            " | --predecessor-paths DIR | --predecessor-declarations DIR"
            " | --predecessor-declarations-paths DIR"
            " | --review PATH"
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
    var review = String("")
    var arguments = argv()
    if len(arguments) == 2 and arguments[1] == "--protected-bundle":
        try:
            print(frozen_protected_bundle(), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) == 3 and arguments[1] == "--digest-token":
        try:
            frozen_digest_and_token(Path(arguments[2]).read_text())
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) == 3 and arguments[1] == "--labeled-digest":
        try:
            frozen_labeled_digest(Path(arguments[2]).read_text())
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) == 3 and arguments[1] == "--record-paths":
        try:
            print(
                frozen_record_paths(Path(arguments[2]).read_bytes()),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) == 3 and arguments[1] == "--review-labels":
        try:
            print(
                producer_review_then_labels(Path(arguments[2]).read_text()),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) == 3 and arguments[1] == "--predecessor-labels":
        try:
            var directory = arguments[2]
            print(
                frozen_predecessor_with_labels(
                    Path(directory + "/payload").read_bytes(),
                    Path(directory + "/request.json").read_text(),
                ),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) == 3 and arguments[1] == "--predecessor-paths":
        try:
            var directory = arguments[2]
            print(
                frozen_predecessor_then_paths(
                    Path(directory + "/payload").read_bytes(),
                    Path(directory + "/request.json").read_text(),
                ),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if (
        len(arguments) == 3
        and arguments[1] == "--predecessor-declarations-paths"
    ):
        try:
            var directory = arguments[2]
            print(
                frozen_declarations_then_paths(
                    Path(directory + "/payload").read_bytes(),
                    Path(directory + "/request.json").read_text(),
                    Path(directory + "/guard").read_bytes(),
                    Path(directory + "/sha").read_text(),
                ),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) == 3 and arguments[1] == "--predecessor-declarations":
        try:
            var directory = arguments[2]
            print(
                frozen_predecessor_then_declarations(
                    Path(directory + "/payload").read_bytes(),
                    Path(directory + "/request.json").read_text(),
                    Path(directory + "/guard").read_bytes(),
                    Path(directory + "/sha").read_text(),
                ),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
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
            or word == "--review"
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
            elif word == "--predecessor":
                predecessor = value
            else:
                review = value
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
    if review.byte_length() > 0:
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
        if review.byte_length() > 0:
            frozen_producer_review(Path(review).read_text())
            return
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
