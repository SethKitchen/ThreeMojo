# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the five Y-finiteness token digests.

    carla_y_gate --grouped PATH --interval PATH --trig PATH --geometry PATH --sum2 PATH
    carla_y_gate --mismatches --grouped PATH --interval PATH --trig PATH --geometry PATH --sum2 PATH

The program checks the texts it is given. It does not accept a stored-word
substitute. The caller does that before it starts the program.
`--mismatches` prints the paths whose tokens differ, in review order.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._python_json import PyJson
from tools._duplicate_pin_keys import reject_duplicate_pin_keys
from tools._sha256 import sha256_hex


comptime _GROUPED = (
    "cd92ac2f02c75fc420920fe3a73b4ddd28a4e5cf0d97785b4ae4eb0f54f2cbd7"
)
comptime _INTERVAL = (
    "e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11"
)
comptime _TRIG = (
    "523d5700201b957152eaa79ae6cce9ca8cb9a2a0098d5b105584667360a6de7f"
)
comptime _GEOMETRY = (
    "a1979bd37d0ea725f452e0a0a269c7aaef3cda485b291e8fe79b49b35850adcb"
)
comptime _SUM2 = (
    "3fbcbb7f6ba0b9120500698665f0419acf6618d8bd34b7e18b9d10896282383d"
)
comptime _RECORD_SHA256 = (
    "4b72cd07de22d61d70c7aa489e566cd25468189b6a60b5e105fa26ea726e6853"
)
comptime _PREDECESSOR_TOKEN = (
    "a8f3beca23c8d6a84d01f5eebecb0a01cd2102aad4e226ed6a782722733a86b7"
)
comptime _PASS = (
    '{"status":"PASS","maximum_accumulator_exponent":947,'
    + '"origin_error_refusal_unchanged":true,"y_call_and_writes_retained":true}'
)


def _token(source: String, expected: String, label: String) raises:
    """Require one module to keep its reviewed token digest.

    Args:
        source: The module text.
        expected: The reviewed digest.
        label: The path named in a failure.

    Raises:
        Error: The digest changed.
    """
    if token_sha256(source) != expected:
        raise Error(
            "Y-finiteness premise, graph, writes or ordering changed: " + label
        )


def y_finiteness(
    grouped: String,
    interval: String,
    trig: String,
    geometry: String,
    sum2: String,
) raises -> String:
    """Require the five Y-finiteness modules to keep their token digests.

    Args:
        grouped: The grouped roundoff proof.
        interval: The interval module.
        trig: The trig module.
        geometry: The geometry module.
        sum2: The sum2 module.

    Returns:
        The pass record as one JSON object.

    Raises:
        Error: A token digest changed.
    """
    _token(
        grouped,
        _GROUPED,
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    _token(interval, _INTERVAL, "extensions/carla/curve_interval.mojo")
    _token(trig, _TRIG, "extensions/carla/curve_trig.mojo")
    _token(geometry, _GEOMETRY, "extensions/carla/geometry.mojo")
    _token(sum2, _SUM2, "extensions/carla/curve_sum2.mojo")
    return _PASS


def _note_mismatch(
    mut doc: PyJson,
    rows: Int,
    source: String,
    expected: String,
    label: String,
) raises:
    """Append `label` when its token digest differs.

    Args:
        doc: The result document.
        rows: The path list.
        source: The module text.
        expected: The reviewed digest.
        label: The module path.

    Raises:
        Error: The module cannot be tokenized.
    """
    if token_sha256(source) != expected:
        doc.append(rows, doc.new_str(label))


def y_token_mismatches(
    grouped: String,
    interval: String,
    trig: String,
    geometry: String,
    sum2: String,
) raises -> String:
    """List the Y-finiteness modules whose token digests differ.

    Args:
        grouped: The grouped roundoff proof.
        interval: The interval module.
        trig: The trig module.
        geometry: The geometry module.
        sum2: The sum2 module.

    Returns:
        A JSON list of paths, in review order. The list is empty when
        every digest matches.

    Raises:
        Error: A module cannot be tokenized.
    """
    var doc = PyJson()
    var rows = doc.new_list()
    _note_mismatch(
        doc,
        rows,
        grouped,
        _GROUPED,
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    _note_mismatch(
        doc, rows, interval, _INTERVAL, "extensions/carla/curve_interval.mojo"
    )
    _note_mismatch(doc, rows, trig, _TRIG, "extensions/carla/curve_trig.mojo")
    _note_mismatch(
        doc, rows, geometry, _GEOMETRY, "extensions/carla/geometry.mojo"
    )
    _note_mismatch(doc, rows, sum2, _SUM2, "extensions/carla/curve_sum2.mojo")
    doc.root = rows
    return doc.dumps()


def y_successor(
    migration: Span[UInt8, _],
    before: Span[UInt8, _],
    after: Span[UInt8, _],
    before_sha: String,
    after_sha: String,
    check_sources: Bool,
) raises:
    """Require the grouped Y successor record and its module bytes.

    Args:
        migration: The successor record bytes.
        before: The predecessor module bytes. Used when `check_sources` is true.
        after: The successor module bytes. Used when `check_sources` is true.
        before_sha: The required predecessor digest.
        after_sha: The required successor digest.
        check_sources: Whether to check the two module digests.

    Raises:
        Error: A digest changed, or a key is repeated after the record digest.
    """
    if sha256_hex(migration) != _RECORD_SHA256:
        raise Error("Unreviewed grouped Y successor record")
    reject_duplicate_pin_keys(migration)
    if not check_sources:
        return
    if sha256_hex(before) != before_sha or sha256_hex(after) != after_sha:
        raise Error("Grouped Y complete-module byte identity changed")


def y_identity(
    before: String,
    after: String,
    before_token: String,
    after_token: String,
) raises:
    """Require the recorded module tokens to match the reviewed digests.

    Args:
        before: The predecessor module source.
        after: The successor module source.
        before_token: The token recorded for the predecessor.
        after_token: The token recorded for the successor.

    Raises:
        Error: A recorded token or a module token changed.
    """
    if (
        before_token != _PREDECESSOR_TOKEN
        or token_sha256(before) != _PREDECESSOR_TOKEN
        or after_token != _GROUPED
        or token_sha256(after) != _GROUPED
    ):
        raise Error("Grouped Y predecessor/successor token identity changed")


def y_predecessor(record: String) raises -> String:
    """Return the earlier grouped module after the successor record matches.

    Args:
        record: The grouped Y successor record.

    Returns:
        The recorded earlier module.

    Raises:
        Error: The record digest changed, the recorded module bytes differ,
            or a module token changed. The record digest is checked before
            the module bytes.
    """
    y_successor(
        record.as_bytes(),
        String("").as_bytes(),
        String("").as_bytes(),
        "",
        "",
        False,
    )
    var doc = PyJson.parse(record)
    var before = doc.text(doc.at(doc.root, "before_complete_module"))
    var after = doc.text(doc.at(doc.root, "after_complete_module"))
    y_successor(
        record.as_bytes(),
        before.as_bytes(),
        after.as_bytes(),
        doc.text(doc.at(doc.root, "predecessor_file_sha256")),
        doc.text(doc.at(doc.root, "successor_file_sha256")),
        True,
    )
    y_identity(
        before,
        after,
        doc.text(doc.at(doc.root, "predecessor_token_sha256")),
        doc.text(doc.at(doc.root, "successor_token_sha256")),
    )
    return before


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_y_gate [--mismatches] --grouped PATH --interval PATH"
            " --trig PATH --geometry PATH --sum2 PATH | --before-text PATH --after-text"
            " PATH --before-token HEX --after-token HEX | --predecessor PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check five source files and print the pass record.

    Raises:
        Error: The command is invalid.
    """
    var mismatches = False
    var predecessor = String("")
    var grouped = String("")
    var interval = String("")
    var trig = String("")
    var geometry = String("")
    var sum2 = String("")
    var record = String("")
    var before = String("")
    var after = String("")
    var before_sha = String("")
    var after_sha = String("")
    var before_text = String("")
    var after_text = String("")
    var before_token = String("")
    var after_token = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--mismatches":
            mismatches = True
            index += 1
            continue
        if word == "--predecessor":
            if index + 1 >= len(arguments):
                _usage()
            predecessor = arguments[index + 1]
            index += 2
            continue
        if (
            word == "--grouped"
            or word == "--interval"
            or word == "--trig"
            or word == "--geometry"
            or word == "--sum2"
            or word == "--record"
            or word == "--before"
            or word == "--after"
            or word == "--before-sha"
            or word == "--after-sha"
            or word == "--before-text"
            or word == "--after-text"
            or word == "--before-token"
            or word == "--after-token"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--grouped":
                grouped = value
            elif word == "--interval":
                interval = value
            elif word == "--trig":
                trig = value
            elif word == "--geometry":
                geometry = value
            elif word == "--sum2":
                sum2 = value
            elif word == "--record":
                record = value
            elif word == "--before":
                before = value
            elif word == "--after":
                after = value
            elif word == "--before-sha":
                before_sha = value
            elif word == "--after-sha":
                after_sha = value
            elif word == "--before-text":
                before_text = value
            elif word == "--after-text":
                after_text = value
            elif word == "--before-token":
                before_token = value
            else:
                after_token = value
            index += 2
            continue
        _usage()
    if predecessor.byte_length() > 0:
        if (
            mismatches
            or grouped.byte_length() > 0
            or interval.byte_length() > 0
            or trig.byte_length() > 0
            or geometry.byte_length() > 0
            or sum2.byte_length() > 0
            or record.byte_length() > 0
            or before.byte_length() > 0
            or after.byte_length() > 0
            or before_sha.byte_length() > 0
            or after_sha.byte_length() > 0
            or before_text.byte_length() > 0
            or after_text.byte_length() > 0
            or before_token.byte_length() > 0
            or after_token.byte_length() > 0
        ):
            _usage()
        try:
            print(y_predecessor(Path(predecessor).read_text()), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    var identity = (
        before_text.byte_length() > 0
        or after_text.byte_length() > 0
        or before_token.byte_length() > 0
        or after_token.byte_length() > 0
    )
    if identity:
        if (
            before_text.byte_length() == 0
            or after_text.byte_length() == 0
            or before_token.byte_length() == 0
            or after_token.byte_length() == 0
            or record.byte_length() > 0
            or grouped.byte_length() > 0
            or interval.byte_length() > 0
            or trig.byte_length() > 0
            or geometry.byte_length() > 0
            or sum2.byte_length() > 0
            or before.byte_length() > 0
            or after.byte_length() > 0
            or before_sha.byte_length() > 0
            or after_sha.byte_length() > 0
        ):
            _usage()
        try:
            y_identity(
                Path(before_text).read_text(),
                Path(after_text).read_text(),
                before_token,
                after_token,
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    var sources = (
        before.byte_length() > 0
        or after.byte_length() > 0
        or before_sha.byte_length() > 0
        or after_sha.byte_length() > 0
    )
    if record.byte_length() > 0:
        if (
            grouped.byte_length() > 0
            or interval.byte_length() > 0
            or trig.byte_length() > 0
            or geometry.byte_length() > 0
            or sum2.byte_length() > 0
            or (
                sources
                and (
                    before.byte_length() == 0
                    or after.byte_length() == 0
                    or before_sha.byte_length() == 0
                    or after_sha.byte_length() == 0
                )
            )
        ):
            _usage()
        try:
            if sources:
                y_successor(
                    Path(record).read_bytes(),
                    Path(before).read_bytes(),
                    Path(after).read_bytes(),
                    before_sha,
                    after_sha,
                    True,
                )
            else:
                y_successor(
                    Path(record).read_bytes(),
                    String("").as_bytes(),
                    String("").as_bytes(),
                    "",
                    "",
                    False,
                )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if (
        grouped.byte_length() == 0
        or interval.byte_length() == 0
        or trig.byte_length() == 0
        or geometry.byte_length() == 0
        or sum2.byte_length() == 0
    ):
        _usage()
    try:
        if mismatches:
            print(
                y_token_mismatches(
                    Path(grouped).read_text(),
                    Path(interval).read_text(),
                    Path(trig).read_text(),
                    Path(geometry).read_text(),
                    Path(sum2).read_text(),
                ),
                end="",
            )
            return
        print(
            y_finiteness(
                Path(grouped).read_text(),
                Path(interval).read_text(),
                Path(trig).read_text(),
                Path(geometry).read_text(),
                Path(sum2).read_text(),
            )
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
