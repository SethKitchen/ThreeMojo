# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the lane-control migration record.

    carla_lane_control_gate --migration PATH
    carla_lane_control_gate --tokens DIR
    carla_lane_control_gate --tokens-then-predecessors DIR
    carla_lane_control_gate --prepare PATH
    carla_lane_control_gate --prepare-labeled PATH

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._duplicate_pin_keys import reject_duplicate_pin_keys
from tools._lane_declarations import (
    lane_control_prepare,
    lane_control_prepare_with_labels,
)
from tools._lane_predecessor import accept_lane_predecessors
from tools._python_json import MISSING, PY_LIST, PY_STR, PyJson
from tools._sha256 import sha256_hex


comptime _RECORD_SHA256 = (
    "73d95d594e740205bad4cd900288a68d9f82897474fdc33e4d6043a156790170"
)
comptime _PREDECESSOR_SHA256 = (
    "33d33ba0e481e3eca3b17ae0d02457ab53bae906430b0dca58abcfa876756315"
)


def _fail(message: String) raises:
    """Raise one lane-control failure.

    Args:
        message: The complete failure text.

    Raises:
        Error: Always.
    """
    raise Error(message)


def _field(doc: PyJson, name: String) raises -> String:
    """Return one string field.

    Args:
        doc: The record.
        name: The field name.

    Returns:
        The field text.

    Raises:
        Error: The field is absent or is not a string.
    """
    var node = doc.get(doc.root, name)
    if node == MISSING or doc.kind(node) != PY_STR:
        _fail("lane-control predecessor changed")
    return doc.text(node)


def lane_control_record(migration: Span[UInt8, _]) raises:
    """Require the lane-control migration and its embedded sources.

    Args:
        migration: The successor record bytes.

    Raises:
        Error: The record digest, a repeated key, or an embedded source digest changed.
    """
    if sha256_hex(migration) != _RECORD_SHA256:
        _fail("lane-control migration record changed")
    reject_duplicate_pin_keys(migration)
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    var before = _field(doc, "before_source")
    var before_hash = _field(doc, "before_sha256")
    var digest = sha256_hex(before.as_bytes())
    if digest != before_hash or digest != _PREDECESSOR_SHA256:
        _fail("lane-control predecessor changed")
    var after = doc.get(doc.root, "after_source")
    var after_hash = doc.get(doc.root, "after_sha256")
    if (
        after == MISSING
        or doc.kind(after) != PY_STR
        or after_hash == MISSING
        or doc.kind(after_hash) != PY_STR
        or sha256_hex(doc.text(after).as_bytes()) != doc.text(after_hash)
    ):
        _fail("lane-control successor record changed")


def lane_control_tokens(directory: String) raises:
    """Require each declaration pair to have the same tokens.

    Args:
        directory: A directory with `labels.json` and `N.left` / `N.right` texts.

    Raises:
        Error: A pair differs, or the directory cannot be read.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("lane-control successor module changed")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var label = doc.text(doc.item(doc.root, index))
        var left = Path(directory + "/" + String(index) + ".left").read_text()
        var right = Path(directory + "/" + String(index) + ".right").read_text()
        if token_sha256(left) != token_sha256(right):
            _fail(label)
        index += 1


def lane_control_tokens_then_predecessors(directory: String) raises -> String:
    """Check the declaration tokens, then the lane predecessors.

    Args:
        directory: Token pairs in `N.left` and `N.right`, plus `labels.json`
            and `predecessor.json`.

    Returns:
        A JSON list of `true` or `false`, in predecessor order.

    Raises:
        Error: A token pair differs before a predecessor is accepted.
    """
    lane_control_tokens(directory)
    return accept_lane_predecessors(
        Path(directory + "/predecessor.json").read_text()
    )


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_lane_control_gate --migration PATH | --tokens DIR |"
            " --tokens-then-predecessors DIR | --prepare PATH |"
            " --prepare-labeled PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the lane-control record and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var tokens = String("")
    var tokens_then_predecessors = String("")
    var prepare = String("")
    var prepare_labeled = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--tokens"
            or word == "--tokens-then-predecessors"
            or word == "--prepare"
            or word == "--prepare-labeled"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--tokens":
                tokens = value
            elif word == "--tokens-then-predecessors":
                tokens_then_predecessors = value
            elif word == "--prepare-labeled":
                prepare_labeled = value
            else:
                prepare = value
            index += 2
            continue
        _usage()
    var modes = 0
    if migration.byte_length() > 0:
        modes += 1
    if tokens.byte_length() > 0:
        modes += 1
    if tokens_then_predecessors.byte_length() > 0:
        modes += 1
    if prepare.byte_length() > 0:
        modes += 1
    if prepare_labeled.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    try:
        if prepare_labeled.byte_length() > 0:
            print(
                lane_control_prepare_with_labels(
                    Path(prepare_labeled).read_text()
                ),
                end="",
            )
            return
        if prepare.byte_length() > 0:
            print(lane_control_prepare(Path(prepare).read_text()), end="")
            return
        if tokens_then_predecessors.byte_length() > 0:
            print(
                lane_control_tokens_then_predecessors(tokens_then_predecessors),
                end="",
            )
            return
        if tokens.byte_length() > 0:
            lane_control_tokens(tokens)
            return
        lane_control_record(Path(migration).read_bytes())
    except error:
        print(String(error), file=stderr)
        exit(1)
