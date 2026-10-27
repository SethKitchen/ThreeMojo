# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the runtime-view successor record and its bound tests.

    carla_runtime_view_gate --migration PATH --event PATH --float32 PATH --length PATH --raw PATH --measurement PATH

The program checks the bytes it is given. It does not read the repository.
The caller observes those files first.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import PY_BOOL, PY_INT, PyJson
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "40fe6f5aef91b4a9f407f1a8ea83721b317d24b690d947c623feca8b73dcc907"
)
comptime _LANE = "extensions/carla/lane_invasion.mojo"
comptime _SENSOR = "extensions/carla/sensor_manager.mojo"
comptime _EVENT = "tests/test_carla_event_time_quantity.mojo"
comptime _FLOAT32 = "tests/compile_fail/carla_lane_invasion_event_time_rejects_float32_duration.mojo"
comptime _LENGTH = (
    "tests/compile_fail/carla_lane_invasion_event_time_rejects_length.mojo"
)
comptime _RAW = (
    "tests/compile_fail/carla_lane_invasion_event_time_rejects_raw_float64.mojo"
)
comptime _MEASUREMENT = (
    "tests/compile_fail/carla_measurement_time_is_not_a_raw_float64.mojo"
)


def _fail(message: String) raises:
    """Raise one runtime-view failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("reviewed runtime view successor: " + message)


def _is_one(doc: PyJson, node: Int) -> Bool:
    """Return whether a JSON value is Python's `1`.

    Args:
        doc: The document.
        node: The value.

    Returns:
        True for the integer 1 and for `True`.
    """
    var kind = doc.kind(node)
    if kind == PY_INT:
        return doc.text(node) == "1"
    if kind == PY_BOOL:
        return doc.flag(node)
    return False


def _is_333(doc: PyJson, node: Int) -> Bool:
    """Return whether a JSON value is the integer 333.

    Args:
        doc: The document.
        node: The value.

    Returns:
        True when the value is the integer 333.
    """
    return doc.kind(node) == PY_INT and doc.text(node) == "333"


def _digest(doc: PyJson, tests: Int, path: String) raises -> String:
    """Return the recorded digest for one test path.

    Args:
        doc: The record.
        tests: The correctness-test object.
        path: The test path.

    Returns:
        The digest, or an empty string when the path is absent.

    Raises:
        Error: The object cannot be read.
    """
    var index = 0
    while index < doc.length(tests):
        if doc.key(tests, index) == path:
            return doc.text(doc.value(tests, index))
        index += 1
    return ""


def _step_json(doc: PyJson, step: Int) raises -> String:
    """Return one step object in its recorded key order.

    Args:
        doc: The record.
        step: The step object.

    Returns:
        A JSON object.

    Raises:
        Error: A field is absent.
    """
    var out = String("{")
    var index = 0
    var count = doc.length(step)
    while index < count:
        if index > 0:
            out += ","
        var key = doc.key(step, index)
        out += '"' + key + '":"' + doc.text(doc.value(step, index)) + '"'
        index += 1
    out += "}"
    return out


def _check_step(doc: PyJson, steps: Int, path: String) raises -> Int:
    """Require one step and return its node.

    Args:
        doc: The record.
        steps: The steps object.
        path: The module path.

    Returns:
        The step node.

    Raises:
        Error: The step is missing or malformed.
    """
    var found = -1
    var index = 0
    while index < doc.length(steps):
        if doc.key(steps, index) == path:
            found = index
        index += 1
    if found < 0:
        _fail("unexpected successor scope")
    var step = doc.value(steps, found)
    var keys = List[String]()
    var before_sha = String("")
    var after_sha = String("")
    var before_token = String("")
    var after_token = String("")
    index = 0
    while index < doc.length(step):
        var key = doc.key(step, index)
        var value = doc.text(doc.value(step, index))
        keys.append(key)
        if key == "before_sha256":
            before_sha = value
        elif key == "after_sha256":
            after_sha = value
        elif key == "before_token_sha256":
            before_token = value
        elif key == "after_token_sha256":
            after_token = value
        else:
            _fail("malformed step: " + path)
        index += 1
    if (
        len(keys) != 4
        or before_sha.byte_length() == 0
        or after_sha.byte_length() == 0
        or before_token.byte_length() == 0
        or after_token.byte_length() == 0
        or before_sha == after_sha
        or before_token == after_token
    ):
        _fail("malformed step: " + path)
    return step


def runtime_view(
    migration: Span[UInt8, _],
    event: Span[UInt8, _],
    float32: Span[UInt8, _],
    length: Span[UInt8, _],
    raw: Span[UInt8, _],
    measurement: Span[UInt8, _],
) raises -> String:
    """Require the runtime-view record and return its steps.

    Args:
        migration: The successor record bytes.
        event: The event-time test bytes.
        float32: The Float32 duration rejection bytes.
        length: The length rejection bytes.
        raw: The raw Float64 rejection bytes.
        measurement: The measurement rejection bytes.

    Returns:
        The two steps as one JSON object.

    Raises:
        Error: The record or a bound test changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed exact step")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    if not (
        _is_one(doc, doc.at(doc.root, "schema"))
        and _is_333(doc, doc.at(doc.root, "issue"))
    ):
        _fail("unexpected successor scope")
    var steps = doc.at(doc.root, "steps")
    if doc.length(steps) != 2:
        _fail("unexpected successor scope")
    var lane = _check_step(doc, steps, _LANE)
    var sensor = _check_step(doc, steps, _SENSOR)
    var tests = doc.at(doc.root, "correctness_tests")
    var wanted = List[String]()
    wanted.append(_EVENT)
    wanted.append(_FLOAT32)
    wanted.append(_LENGTH)
    wanted.append(_RAW)
    wanted.append(_MEASUREMENT)
    var digests = List[String]()
    digests.append(sha256_hex(event))
    digests.append(sha256_hex(float32))
    digests.append(sha256_hex(length))
    digests.append(sha256_hex(raw))
    digests.append(sha256_hex(measurement))
    if doc.length(tests) != len(wanted):
        _fail("unexpected correctness test set")
    var index = 0
    while index < len(wanted):
        var recorded = _digest(doc, tests, wanted[index])
        if recorded.byte_length() == 0:
            _fail("unexpected correctness test set")
        if recorded != digests[index]:
            _fail("bound runtime view test changed: " + wanted[index])
        index += 1
    return (
        '{"'
        + _LANE
        + '":'
        + _step_json(doc, lane)
        + ',"'
        + _SENSOR
        + '":'
        + _step_json(doc, sensor)
        + "}"
    )


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_runtime_view_gate --migration PATH --event PATH"
            " --float32 PATH --length PATH --raw PATH --measurement PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the runtime-view record and print its steps."""
    var migration = String("")
    var event = String("")
    var float32 = String("")
    var length = String("")
    var raw = String("")
    var measurement = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--event"
            or word == "--float32"
            or word == "--length"
            or word == "--raw"
            or word == "--measurement"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--event":
                event = value
            elif word == "--float32":
                float32 = value
            elif word == "--length":
                length = value
            elif word == "--raw":
                raw = value
            else:
                measurement = value
            index += 2
            continue
        _usage()
    if (
        migration.byte_length() == 0
        or event.byte_length() == 0
        or float32.byte_length() == 0
        or length.byte_length() == 0
        or raw.byte_length() == 0
        or measurement.byte_length() == 0
    ):
        _usage()
    try:
        print(
            runtime_view(
                Path(migration).read_bytes(),
                Path(event).read_bytes(),
                Path(float32).read_bytes(),
                Path(length).read_bytes(),
                Path(raw).read_bytes(),
                Path(measurement).read_bytes(),
            )
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
