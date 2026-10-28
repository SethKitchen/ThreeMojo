# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the coverage-invariant record and its component digests.

    carla_invariant_gate --input-bundle
    carla_invariant_gate --migration PATH [--prior PATH] [--components DIR]
    carla_invariant_gate --bytes PATH --sha HEX --kind after|before --label TEXT
    carla_invariant_gate --pair DIR
    carla_invariant_gate --places DIR
    carla_invariant_gate --predecessor DIR

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
An absent prior skips the frozen digest and the component digests.
A prior without a component directory checks only that frozen digest.
The component directory holds `names.json` and the payloads `0`, `1`, and
so on. An escaping name fails before the record digests.
`DIR` holds `payload` and `request.json`. The program prints the
predecessor.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._carla_assets import dumps_indent
from tools._migration_records import migration_records
from tools.carla_dispatch_gate import dispatch_paths
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
    loads,
)
from tools._posix_path import component_confined
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "56a72d9bccbf9e7b8a6b51db2b9944ef4bbf55d9bcc7311f7f9615be3b3b36ac"
)


def _fail(message: String) raises:
    """Raise one coverage-invariant failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("coverage invariant successor: " + message)


def _source_name(index: Int) raises -> String:
    """Return one reviewed source path.

    Args:
        index: The path position, from 0 through 3.

    Returns:
        The repository path.

    Raises:
        Error: The position is outside the reviewed set.
    """
    if index == 0:
        return "extensions/carla/curve_minimizer_support.mojo"
    if index == 1:
        return "extensions/carla/curve_sample_dispatch.mojo"
    if index == 2:
        return "extensions/carla/spiral_grouped_roundoff_proof.mojo"
    if index == 3:
        return "extensions/carla/lane_refinement.mojo"
    _fail("wrong successor set")
    return ""


def _sources_match(doc: PyJson, node: Int) raises -> Bool:
    """Return whether the source keys are the reviewed set.

    Args:
        doc: The record.
        node: The sources object.

    Returns:
        True when the keys are exactly the four reviewed paths.

    Raises:
        Error: The reviewed path table is unusable.
    """
    if doc.kind(node) != PY_DICT or doc.length(node) != 4:
        return False
    var index = 0
    while index < 4:
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
    ):
        _fail("unsupported schema")
    if sources == MISSING or not _sources_match(doc, sources):
        _fail("wrong successor set")


def _require_prior(doc: PyJson, prior: Span[UInt8, _]) raises:
    """Require the frozen-producer digest.

    Args:
        doc: The migration record.
        prior: The historical frozen-producer migration bytes.

    Raises:
        Error: The digest changed.
    """
    var field = doc.get(doc.root, "prior_frozen_migration_sha256")
    if (
        field == MISSING
        or doc.kind(field) != PY_STR
        or doc.text(field) != sha256_hex(prior)
    ):
        _fail("historical frozen record changed")


def _read_component_names(component_dir: String) raises -> List[String]:
    """Return the component names listed beside the indexed payloads.

    Args:
        component_dir: The directory whose `names.json` lists the names.

    Returns:
        The names in listed order.

    Raises:
        Error: The name list is missing or is not a list of strings.
    """
    var doc = PyJson.parse(Path(component_dir + "/names.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("component record changed: ")
    var names = List[String]()
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var item = doc.item(doc.root, index)
        if doc.kind(item) != PY_STR:
            _fail("component record changed: ")
        names.append(doc.text(item))
        index += 1
    return names^


def _confine_component_names(component_dir: String) raises:
    """Require every listed component name to stay inside the directory.

    Args:
        component_dir: The directory whose `names.json` lists the names.

    Raises:
        Error: A name escapes the directory. The record digests are not
            checked.
    """
    var names = _read_component_names(component_dir)
    var index = 0
    while index < len(names):
        var name = names[index]
        if not component_confined(component_dir, name):
            _fail("component record changed: " + name)
        index += 1


def _require_components(doc: PyJson, component_dir: String) raises:
    """Require each component migration digest.

    Args:
        doc: The migration record.
        component_dir: The directory that holds `names.json` and `0`, `1`, ...

    Raises:
        Error: A component digest changed, or a component file cannot be read.
    """
    var names = _read_component_names(component_dir)
    var node = doc.get(doc.root, "components")
    if node == MISSING or doc.kind(node) != PY_DICT:
        _fail("component record changed: ")
    var index = 0
    var count = doc.length(node)
    while index < count:
        var name = doc.key(node, index)
        var digest = doc.value(node, index)
        if (
            doc.kind(digest) != PY_STR
            or name.byte_length() == 0
            or name.find("/") >= 0
            or index >= len(names)
            or names[index] != name
        ):
            _fail("component record changed: " + name)
        var payload = Path(component_dir + "/" + String(index)).read_bytes()
        if sha256_hex(payload) != doc.text(digest):
            _fail("component record changed: " + name)
        index += 1


def invariant_record(
    migration: Span[UInt8, _],
    prior: Span[UInt8, _],
    component_dir: String,
    check_prior: Bool,
) raises:
    """Require the coverage-invariant record.

    Args:
        migration: The successor record bytes.
        prior: The frozen-producer migration. Used only when `check_prior` is true.
        component_dir: The component directory. Empty skips the component digests.
        check_prior: Whether to check the frozen digest.

    Raises:
        Error: An escaping component name fails before a changed record,
            frozen digest, or component digest.
    """
    if component_dir.byte_length() > 0:
        _confine_component_names(component_dir)
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


def invariant_digest(
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
        label: The pin filename, used in the failure text.

    Raises:
        Error: The digest changed.
    """
    if sha256_hex(payload) == expected:
        return
    if kind == "before":
        _fail("historical pin reconstruction failed: " + label)
    if label == "runtime-source-pins.json":
        _fail("unreviewed runtime pin successor: " + label)
    _fail("unreviewed guarded pin successor: " + label)


def invariant_pair(directory: String) raises:
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


def invariant_places(directory: String) raises:
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


def _joined_pointer(request: PyJson, pointer: Int) raises -> String:
    """Join one pointer into a single lookup key.

    Args:
        request: The predecessor request.
        pointer: The pointer list.

    Returns:
        The parts separated by newlines.

    Raises:
        Error: A pointer part cannot be read.
    """
    var key = String("")
    var count = request.length(pointer)
    var index = 0
    while index < count:
        if index > 0:
            key += "\n"
        key += request.text(request.item(pointer, index))
        index += 1
    return key


def _pin_at(pins: PyJson, request: PyJson, pointer: Int) raises -> String:
    """Return the string at one pin pointer.

    Args:
        pins: The active pin document.
        request: The predecessor request.
        pointer: The pointer list.

    Returns:
        The current string at that pointer. An empty pointer reads the root.

    Raises:
        Error: A pointer key is absent.
    """
    var node = pins.root
    var count = request.length(pointer)
    var index = 0
    while index < count:
        node = pins.at(node, request.text(request.item(pointer, index)))
        index += 1
    return pins.text(node)


def _require_pin_places(pins: PyJson, request: PyJson, transitions: Int) raises:
    """Require each pin placement to be unique and current.

    Args:
        pins: The active pin document.
        request: The predecessor request.
        transitions: The transition list in `request`.

    Raises:
        Error: A placement is repeated, its current value changed, or a pointer key is absent.
    """
    var seen = List[String]()
    var duplicates = List[Bool]()
    var actuals = List[String]()
    var expecteds = List[String]()
    var count = request.length(transitions)
    var index = 0
    while index < count:
        var change = request.item(transitions, index)
        var pointer = request.at(change, "pointer")
        var key = _joined_pointer(request, pointer)
        var duplicate = False
        var seen_index = 0
        while seen_index < len(seen):
            if seen[seen_index] == key:
                duplicate = True
            seen_index += 1
        var actual = String("")
        if not duplicate:
            actual = _pin_at(pins, request, pointer)
            seen.append(key)
        duplicates.append(duplicate)
        actuals.append(actual)
        expecteds.append(request.text(request.at(change, "after")))
        index += 1
    index = 0
    while index < len(duplicates):
        if duplicates[index]:
            _fail("duplicate pin placement")
        if actuals[index] != expecteds[index]:
            _fail("active pin placement mismatch")
        index += 1


def _write_pin_transitions(
    mut pins: PyJson, request: PyJson, transitions: Int
) raises:
    """Write each transition's historical value back into the pins.

    Args:
        pins: The active pin document.
        request: The predecessor request.
        transitions: The transition list in `request`.

    Raises:
        Error: A pointer is empty or a pointer key is absent.
    """
    var count = request.length(transitions)
    var index = 0
    while index < count:
        var change = request.item(transitions, index)
        var pointer = request.at(change, "pointer")
        var parts = request.length(pointer)
        if parts == 0:
            raise Error("pin transition pointer is empty")
        var parent = pins.root
        var cursor = 0
        while cursor < parts - 1:
            parent = pins.at(
                parent, request.text(request.item(pointer, cursor))
            )
            cursor += 1
        pins.set(
            parent,
            request.text(request.item(pointer, parts - 1)),
            pins.adopt(request, request.at(change, "before")),
        )
        index += 1


def _skip_json_space(text: String, mut index: Int):
    """Move past ASCII space in a JSON document.

    Args:
        text: The JSON text.
        index: The current byte index.
    """
    var data = text.as_bytes()
    var count = len(data)
    while index < count:
        var byte = data[index]
        if byte != 32 and byte != 9 and byte != 10 and byte != 13:
            return
        index += 1


def _json_hex(byte: Int) raises -> Int:
    """Return one hex value.

    Args:
        byte: An ASCII hex digit.

    Returns:
        The value from 0 through 15.

    Raises:
        Error: The byte is not a hex digit.
    """
    if byte >= 48 and byte <= 57:
        return byte - 48
    if byte >= 65 and byte <= 70:
        return byte - 55
    if byte >= 97 and byte <= 102:
        return byte - 87
    raise Error("JSONDecodeError")


def _json_string(text: String, mut index: Int) raises -> String:
    """Read one JSON string and return its decoded text.

    Args:
        text: The JSON text.
        index: The index of the opening quote.

    Returns:
        The decoded string.

    Raises:
        Error: The string is not closed or an escape is invalid.
    """
    var data = text.as_bytes()
    var count = len(data)
    if index >= count or data[index] != 34:
        raise Error("JSONDecodeError")
    index += 1
    var out = String("")
    while index < count:
        var byte = data[index]
        index += 1
        if byte == 34:
            return out
        if byte != 92:
            out += chr(Int(byte))
            continue
        if index >= count:
            raise Error("JSONDecodeError")
        var escaped = data[index]
        index += 1
        if escaped == 34 or escaped == 92 or escaped == 47:
            out += chr(Int(escaped))
        elif escaped == 98:
            out += chr(8)
        elif escaped == 102:
            out += chr(12)
        elif escaped == 110:
            out += chr(10)
        elif escaped == 114:
            out += chr(13)
        elif escaped == 116:
            out += chr(9)
        elif escaped == 117:
            if index + 4 > count:
                raise Error("JSONDecodeError")
            var code = 0
            var shift = 0
            while shift < 4:
                code = code * 16 + _json_hex(Int(data[index]))
                index += 1
                shift += 1
            out += chr(code)
        else:
            raise Error("JSONDecodeError")
    raise Error("JSONDecodeError")


def _json_value(text: String, mut index: Int) raises:
    """Skip one JSON value and refuse a repeated object key.

    Args:
        text: The JSON text.
        index: The start of the value.

    Raises:
        Error: The value is not JSON, or an object key is repeated.
    """
    _skip_json_space(text, index)
    var data = text.as_bytes()
    var count = len(data)
    if index >= count:
        raise Error("JSONDecodeError")
    var byte = data[index]
    if byte == 34:
        _ = _json_string(text, index)
        return
    if byte == 123:
        _json_object(text, index)
        return
    if byte == 91:
        _json_array(text, index)
        return
    while index < count:
        var mark = data[index]
        if (
            mark == 44
            or mark == 125
            or mark == 93
            or mark == 32
            or mark == 9
            or mark == 10
            or mark == 13
        ):
            return
        index += 1


def _json_object(text: String, mut index: Int) raises:
    """Read one JSON object and refuse a repeated key.

    Args:
        text: The JSON text.
        index: The index of `{`.

    Raises:
        Error: The object is not JSON, or a key is repeated.
    """
    var data = text.as_bytes()
    var count = len(data)
    index += 1
    _skip_json_space(text, index)
    if index < count and data[index] == 125:
        index += 1
        return
    var keys = List[String]()
    while True:
        _skip_json_space(text, index)
        var key = _json_string(text, index)
        var seen = 0
        while seen < len(keys):
            if keys[seen] == key:
                raise Error("duplicate runtime source pin key: " + key)
            seen += 1
        keys.append(key)
        _skip_json_space(text, index)
        if index >= count or data[index] != 58:
            raise Error("JSONDecodeError")
        index += 1
        _json_value(text, index)
        _skip_json_space(text, index)
        if index >= count:
            raise Error("JSONDecodeError")
        if data[index] == 125:
            index += 1
            return
        if data[index] != 44:
            raise Error("JSONDecodeError")
        index += 1


def _json_array(text: String, mut index: Int) raises:
    """Read one JSON array.

    Args:
        text: The JSON text.
        index: The index of `[`.

    Raises:
        Error: The array is not JSON, or a nested object key is repeated.
    """
    var data = text.as_bytes()
    var count = len(data)
    index += 1
    _skip_json_space(text, index)
    if index < count and data[index] == 93:
        index += 1
        return
    while True:
        _json_value(text, index)
        _skip_json_space(text, index)
        if index >= count:
            raise Error("JSONDecodeError")
        if data[index] == 93:
            index += 1
            return
        if data[index] != 44:
            raise Error("JSONDecodeError")
        index += 1


def _reject_duplicate_keys(payload: Span[UInt8, _]) raises:
    """Refuse a repeated key before a pin is placed.

    Args:
        payload: The active pin bytes.

    Raises:
        Error: A key is repeated, or the bytes are not JSON. The repeated
            key has no contract prefix. Invalid JSON uses the parser text.
    """
    var text = String(from_utf8_lossy=payload)
    var index = 0
    try:
        _json_value(text, index)
        _skip_json_space(text, index)
        if index != len(text.as_bytes()):
            raise Error("JSONDecodeError")
    except error:
        var message = String(error)
        if message.startswith("duplicate runtime source pin key:"):
            raise error
        _ = loads(payload)


def invariant_pin_predecessor_pair(
    runtime_payload: Span[UInt8, _],
    runtime_request: String,
    guard_payload: Span[UInt8, _],
    guard_request: String,
) raises -> String:
    """Rebuild the runtime predecessor, then the guard predecessor.

    Args:
        runtime_payload: The active runtime pin bytes.
        runtime_request: The runtime predecessor request.
        guard_payload: The active guard pin bytes.
        guard_request: The guard predecessor request.

    Returns:
        The runtime byte length, a newline, the runtime predecessor, the
        guard byte length, a newline, and the guard predecessor.

    Raises:
        Error: The runtime predecessor fails before the guard pin is
            checked. A repeated guard key is refused before that pin is
            placed.
    """
    var runtime = invariant_pin_predecessor(runtime_payload, runtime_request)
    var spec = PyJson.parse(guard_request)
    var after = spec.text(spec.at(spec.root, "after"))
    var label = spec.text(spec.at(spec.root, "label"))
    if sha256_hex(guard_payload) != after:
        if label == "runtime-source-pins.json":
            _fail("unreviewed runtime pin successor: " + label)
        _fail("unreviewed guarded pin successor: " + label)
    _reject_duplicate_keys(guard_payload)
    var guard = invariant_pin_predecessor(guard_payload, guard_request)
    return (
        String(len(runtime.as_bytes()))
        + "\n"
        + runtime
        + String(len(guard.as_bytes()))
        + "\n"
        + guard
    )


def invariant_pin_predecessor(
    payload: Span[UInt8, _], request: String
) raises -> String:
    """Rebuild one coverage-invariant pin predecessor.

    Args:
        payload: The active pin bytes.
        request: JSON with `after`, `before`, `label`, and `transitions`.

    Returns:
        The predecessor as `json.dumps` writes it with `indent=2`, plus a newline.

    Raises:
        Error: The digest, a placement, or a pin transition changed.
    """
    var spec = PyJson.parse(request)
    var after = spec.text(spec.at(spec.root, "after"))
    var label = spec.text(spec.at(spec.root, "label"))
    if sha256_hex(payload) != after:
        if label == "runtime-source-pins.json":
            _fail("unreviewed runtime pin successor: " + label)
        _fail("unreviewed guarded pin successor: " + label)
    var pins = loads(payload)
    var transitions = spec.at(spec.root, "transitions")
    _require_pin_places(pins, spec, transitions)
    _write_pin_transitions(pins, spec, transitions)
    var predecessor = dumps_indent(pins, pins.root, 2) + "\n"
    var before = spec.text(spec.at(spec.root, "before"))
    if sha256_hex(predecessor.as_bytes()) != before:
        _fail("historical pin reconstruction failed: " + label)
    return predecessor


def invariant_sources() raises -> String:
    """Return the four coverage-invariant source paths.

    Returns:
        A JSON list in reviewed order.

    Raises:
        Error: The list cannot be written.
    """
    var doc = PyJson()
    var names = doc.new_list()
    var index = 0
    while index < 4:
        doc.append(names, doc.new_str(_source_name(index)))
        index += 1
    doc.root = names
    return doc.dumps()


def invariant_protected_tail() raises -> String:
    """Return the protected inputs that follow the dispatch closure.

    Returns:
        A JSON list in reviewed order.

    Raises:
        Error: The list cannot be written.
    """
    var doc = PyJson()
    var names = doc.new_list()
    doc.append(
        names,
        doc.new_str("tools/carla_lane_oracle/grouped-table-contract.json"),
    )
    doc.append(names, doc.new_str(_source_name(2)))
    doc.append(names, doc.new_str("extensions/carla/geometry.mojo"))
    doc.append(
        names,
        doc.new_str("tests/test_carla_support_dispatch_successor.mojo"),
    )
    doc.append(
        names,
        doc.new_str("tools/carla_lane_oracle/lane-control-migration.json"),
    )
    doc.append(
        names, doc.new_str("tests/test_carla_lane_control_successor.mojo")
    )
    doc.root = names
    return doc.dumps()


def invariant_input_bundle() raises -> String:
    """Read the invariant migration and the dispatch paths, then the tail.

    Returns:
        JSON with `invariant`, `dispatch`, `paths`, and `tail`. The
        migration records are read before the dispatch paths. The tail
        is read last.

    Raises:
        Error: The paths or the tail cannot be written. The migration
            records are read before the paths and the tail.
    """
    var records = PyJson.parse(migration_records())
    var invariant = records.subtree(
        records.at(records.root, "invariant")
    ).dumps()
    var dispatch = records.subtree(records.at(records.root, "dispatch")).dumps()
    var paths = dispatch_paths()
    var tail = invariant_protected_tail()
    return (
        '{"invariant":'
        + invariant
        + ',"dispatch":'
        + dispatch
        + ',"paths":'
        + paths
        + ',"tail":'
        + tail
        + "}"
    )


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_invariant_gate --migration PATH [--prior PATH]"
            " [--components DIR] | --bytes PATH --sha HEX --kind after|before"
            " --label TEXT | --pair DIR | --places DIR | --predecessor DIR"
            " | --predecessor-pair DIR"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the coverage-invariant record, or print one restored pin.

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
    var pair = String("")
    var places = String("")
    var predecessor = String("")
    var predecessor_pair = String("")
    var arguments = argv()
    if len(arguments) == 2 and arguments[1] == "--input-bundle":
        try:
            print(invariant_input_bundle(), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
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
            or word == "--pair"
            or word == "--places"
            or word == "--predecessor"
            or word == "--predecessor-pair"
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
            elif word == "--pair":
                pair = value
            elif word == "--places":
                places = value
            elif word == "--predecessor-pair":
                predecessor_pair = value
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
    if pair.byte_length() > 0:
        modes += 1
    if places.byte_length() > 0:
        modes += 1
    if predecessor.byte_length() > 0:
        modes += 1
    if predecessor_pair.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if payload.byte_length() > 0 and (
        digest.byte_length() == 0
        or label.byte_length() == 0
        or (kind != "after" and kind != "before")
    ):
        _usage()
    if migration.byte_length() > 0 and (
        components.byte_length() > 0 and prior.byte_length() == 0
    ):
        _usage()
    try:
        if predecessor_pair.byte_length() > 0:
            print(
                invariant_pin_predecessor_pair(
                    Path(predecessor_pair + "/runtime").read_bytes(),
                    Path(predecessor_pair + "/runtime.json").read_text(),
                    Path(predecessor_pair + "/guard").read_bytes(),
                    Path(predecessor_pair + "/guard.json").read_text(),
                ),
                end="",
            )
            return
        if predecessor.byte_length() > 0:
            print(
                invariant_pin_predecessor(
                    Path(predecessor + "/payload").read_bytes(),
                    Path(predecessor + "/request.json").read_text(),
                ),
                end="",
            )
            return
        if places.byte_length() > 0:
            invariant_places(places)
            return
        if pair.byte_length() > 0:
            invariant_pair(pair)
            return
        if payload.byte_length() > 0:
            invariant_digest(Path(payload).read_bytes(), digest, kind, label)
            return
        if prior.byte_length() == 0:
            invariant_record(
                Path(migration).read_bytes(), String("").as_bytes(), "", False
            )
        elif components.byte_length() == 0:
            invariant_record(
                Path(migration).read_bytes(), Path(prior).read_bytes(), "", True
            )
        else:
            invariant_record(
                Path(migration).read_bytes(),
                Path(prior).read_bytes(),
                components,
                True,
            )
    except error:
        print(String(error), file=stderr)
        exit(1)
