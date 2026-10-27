# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the runtime-boundary record and a bound file.

    carla_runtime_boundary_gate --migration PATH
    carla_runtime_boundary_gate --bytes PATH --sha HEX [--token HEX] --label TEXT

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._python_json import (
    MISSING,
    PY_DICT,
    PY_INT,
    PY_STR,
    PyJson,
    py_equal,
)
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "992854b1191bd365fca3e5e8d3a7fc751ac2eb3196b33684e04ebad833baab00"
)


def _fail(message: String) raises:
    """Raise one runtime-boundary failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("reviewed runtime boundary successor: " + message)


def _module(index: Int) -> String:
    """Return one reviewed module path.

    Args:
        index: The path position, from 0 through 3.

    Returns:
        The repository path.
    """
    if index == 0:
        return "extensions/carla/cameras.mojo"
    if index == 1:
        return "extensions/carla/lane_invasion.mojo"
    if index == 2:
        return "extensions/carla/sensor_manager.mojo"
    return "extensions/carla/world.mojo"


def _test_name(index: Int) -> String:
    """Return one bound test path.

    Args:
        index: The path position, from 0 through 11.

    Returns:
        The repository path.
    """
    if index == 0:
        return "tests/test_carla_sensors.mojo"
    if index == 1:
        return "tests/test_carla_sensors_world.mojo"
    if index == 2:
        return "tests/test_carla_world_signals.mojo"
    if index == 3:
        return "tests/compile_fail/carla_event_camera_time_rejects_float32_duration.mojo"
    if index == 4:
        return "tests/compile_fail/carla_event_camera_time_rejects_length.mojo"
    if index == 5:
        return "tests/compile_fail/carla_event_camera_time_rejects_raw_float64.mojo"
    if index == 6:
        return "tests/compile_fail/carla_lane_invasion_time_rejects_float32_duration.mojo"
    if index == 7:
        return "tests/compile_fail/carla_lane_invasion_time_rejects_length.mojo"
    if index == 8:
        return "tests/compile_fail/carla_lane_invasion_time_rejects_raw_float64.mojo"
    if index == 9:
        return "tests/compile_fail/carla_light_search_distance_rejects_duration.mojo"
    if index == 10:
        return "tests/compile_fail/carla_light_search_distance_rejects_float32_length.mojo"
    return "tests/compile_fail/carla_light_search_distance_rejects_raw_float64.mojo"


def _keys_match(doc: PyJson, node: Int, count: Int, tests: Bool) -> Bool:
    """Return whether an object has one reviewed key set.

    Args:
        doc: The record.
        node: The object, or `MISSING`.
        count: The number of reviewed keys.
        tests: True for the bound tests, false for the modules.

    Returns:
        True when the keys are exactly that set.
    """
    if (
        node == MISSING
        or doc.kind(node) != PY_DICT
        or doc.length(node) != count
    ):
        return False
    var index = 0
    while index < count:
        var name = _test_name(index) if tests else _module(index)
        if doc.get(node, name) == MISSING:
            return False
        index += 1
    return True


def _require_edge(doc: PyJson, edge: Int, name: String) raises:
    """Require the four edge digests and a real change.

    Args:
        doc: The record.
        edge: The edge object.
        name: The module path, used in the failure text.

    Raises:
        Error: The edge is malformed.
    """
    var before = doc.get(edge, "before_sha256")
    var after = doc.get(edge, "after_sha256")
    var before_token = doc.get(edge, "before_token_sha256")
    var after_token = doc.get(edge, "after_token_sha256")
    if (
        doc.length(edge) != 4
        or before == MISSING
        or after == MISSING
        or before_token == MISSING
        or after_token == MISSING
        or doc.kind(before) != PY_STR
        or doc.kind(after) != PY_STR
        or doc.text(before) == doc.text(after)
    ):
        _fail("malformed edge: " + name)


def runtime_boundary_record(migration: Span[UInt8, _]) raises:
    """Require the runtime-boundary record.

    Args:
        migration: The successor record bytes.

    Raises:
        Error: The record scope, tests, or an edge changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed exact edge")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    var schema = doc.get(doc.root, "schema")
    var issue = doc.get(doc.root, "issue")
    var three = PyJson.parse("333")
    if (
        schema == MISSING
        or doc.kind(schema) != PY_INT
        or doc.text(schema) != "1"
        or issue == MISSING
        or not py_equal(doc, issue, three, three.root)
        or not _keys_match(doc, doc.get(doc.root, "edges"), 4, False)
    ):
        _fail("unexpected successor scope")
    if not _keys_match(doc, doc.get(doc.root, "correctness_tests"), 12, True):
        _fail("unexpected correctness test set")
    var edges = doc.get(doc.root, "edges")
    var index = 0
    while index < 4:
        var name = _module(index)
        var edge = doc.get(edges, name)
        if edge == MISSING or doc.kind(edge) != PY_DICT:
            _fail("malformed edge: " + name)
        _require_edge(doc, edge, name)
        index += 1


def runtime_boundary_bytes(
    payload: Span[UInt8, _],
    expected_sha: String,
    expected_token: String,
    label: String,
) raises:
    """Require one file digest, and its token digest when given.

    Args:
        payload: The file bytes.
        expected_sha: The required SHA-256 hex digest.
        expected_token: The required token digest. Empty skips that check.
        label: The failure reason, without the prefix.

    Raises:
        Error: A digest changed, or the source cannot be tokenized.
    """
    if sha256_hex(payload) != expected_sha:
        _fail(label)
    if expected_token.byte_length() == 0:
        return
    if token_sha256(String(from_utf8_lossy=payload)) != expected_token:
        _fail(label)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_runtime_boundary_gate --migration PATH"
            " | --bytes PATH --sha HEX [--token HEX] --label TEXT"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check a runtime-boundary record or file and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var payload = String("")
    var digest = String("")
    var token = String("")
    var label = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--bytes"
            or word == "--sha"
            or word == "--token"
            or word == "--label"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--bytes":
                payload = value
            elif word == "--sha":
                digest = value
            elif word == "--token":
                token = value
            else:
                label = value
            index += 2
            continue
        _usage()
    if (migration.byte_length() == 0) == (payload.byte_length() == 0):
        _usage()
    if payload.byte_length() > 0 and (
        digest.byte_length() == 0 or label.byte_length() == 0
    ):
        _usage()
    try:
        if migration.byte_length() > 0:
            runtime_boundary_record(Path(migration).read_bytes())
        else:
            runtime_boundary_bytes(
                Path(payload).read_bytes(), digest, token, label
            )
    except error:
        print(String(error), file=stderr)
        exit(1)
