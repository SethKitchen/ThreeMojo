# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the envelope budget predecessor record.

    carla_envelope_gate --migration PATH
    carla_envelope_gate --source PATH --token HEX
    carla_envelope_gate --span PATH
    carla_envelope_gate --module-span PATH
    carla_envelope_gate --successor PATH
    carla_envelope_gate --module-successor PATH
    carla_envelope_gate --admission PATH
    carla_envelope_gate --predecessor DIR

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
`--span` reads one capture function and refuses a counter name between
the two capacity checks. `--module-span` selects that function from a
module first. `--successor` reads `actual` and `expected` function text
and requires the same significant tokens. `--module-successor` selects
the live function from `source` before that comparison.
`--admission` checks the admission token, then the capture-function gap.
`--predecessor` checks `record.json`, then prints the earlier function
from that record after the live module in `module.mojo` matches.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import (
    declaration_text,
    significant_json,
    token_names,
    token_sha256,
)
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD_SHA256 = (
    "c43aa2bfdfb2a33575745eefb44b2f8ff0714a71a31ad750e8c4c0572fa7f2be"
)


def envelope_record(migration: Span[UInt8, _]) raises:
    """Require the envelope budget predecessor record.

    Args:
        migration: The contract record bytes.

    Raises:
        Error: The digest changed.
    """
    if sha256_hex(migration) != _RECORD_SHA256:
        raise Error("Unreviewed envelope budget predecessor record")


def envelope_token(text: String, expected: String) raises:
    """Require the admission source token digest.

    Args:
        text: The checked source.
        expected: The required token digest.

    Raises:
        Error: The token digest changed.
    """
    if token_sha256(text) != expected:
        raise Error("Reviewed budget admission, routing or arithmetic changed")


comptime _SPAN_START = "    var at = info_index("
"""The first operation after the entry check."""
comptime _SPAN_END = "    if optional_work > max_terms - terms:"
"""The second capacity check."""


def envelope_budget_span(text: String) raises:
    """Refuse a counter name between the two capacity checks.

    Args:
        text: The capture function, already extracted.

    Raises:
        Error: A capacity marker is missing, or `terms` or `max_terms`
            appears between those markers.
    """
    var start = text.find(_SPAN_START)
    if start < 0:
        raise Error("substring not found")
    var end = text.find(_SPAN_END)
    if end < 0:
        raise Error("substring not found")
    var span = String("")
    if end >= start:
        span = String(text[byte=start:end])
    for name in token_names(span):
        if name == "terms" or name == "max_terms":
            raise Error("Intervening span can access budget parameters")


def envelope_successor(payload: String) raises:
    """Require two capture functions to have the same significant tokens.

    Args:
        payload: JSON with `actual` and `expected` function text.

    Raises:
        Error: A field is absent, a function cannot be tokenized, or the
            significant tokens differ.
    """
    var doc = PyJson.parse(payload)
    var actual = significant_json(doc.text(doc.at(doc.root, "actual")))
    var expected = significant_json(doc.text(doc.at(doc.root, "expected")))
    if actual != expected:
        raise Error("Envelope budget successor function changed")


def envelope_admission(payload: String) raises:
    """Check the admission token, then the capture-function gap.

    Args:
        payload: JSON with `checked`, the admission source, `source`, the
            module that declares the capture function, and `token`, the
            required digest.

    Raises:
        Error: A field is absent, the token digest changed, the function
            cannot be read, or a counter name appears in the gap. The token
            is checked before the gap.
    """
    var doc = PyJson.parse(payload)
    envelope_token(
        doc.text(doc.at(doc.root, "checked")),
        doc.text(doc.at(doc.root, "token")),
    )
    envelope_module_span(doc.text(doc.at(doc.root, "source")))


def _capture_function(source: String) raises -> String:
    """Return `_try_lane_envelope_capture` from one module.

    Args:
        source: The module, or the function itself.

    Returns:
        The dedented capture function.

    Raises:
        Error: The function is missing, repeated, or has no indented body.
    """
    var owners = List[String]()
    return declaration_text(source, "_try_lane_envelope_capture", owners)


def envelope_module_span(source: String) raises:
    """Refuse a counter name in the module's capture function.

    Args:
        source: The module that declares `_try_lane_envelope_capture`.

    Raises:
        Error: The function cannot be read, a capacity marker is missing,
            or `terms` or `max_terms` appears between those markers.
    """
    envelope_budget_span(_capture_function(source))


def envelope_module_successor(payload: String) raises:
    """Require the module's capture function to match the recorded successor.

    Args:
        payload: JSON with `source`, the module text, and `expected`, the
            recorded function text.

    Raises:
        Error: The function cannot be read, a field is absent, or the
            significant tokens differ.
    """
    var doc = PyJson.parse(payload)
    var actual = _capture_function(doc.text(doc.at(doc.root, "source")))
    var expected = doc.text(doc.at(doc.root, "expected"))
    if significant_json(actual) != significant_json(expected):
        raise Error("Envelope budget successor function changed")


def envelope_predecessor(record: String, source: String) raises -> String:
    """Return the earlier capture function after the successor matches.

    Args:
        record: The envelope budget contract record.
        source: The module that declares the live capture function.

    Returns:
        The recorded earlier capture function.

    Raises:
        Error: The record digest changed, the record cannot be read, the
            live function cannot be read, or its significant tokens differ.
            The record digest is checked before the live function.
    """
    envelope_record(record.as_bytes())
    var doc = PyJson.parse(record)
    var pair = PyJson()
    var body = pair.new_dict()
    pair.set(body, "source", pair.new_str(source))
    pair.set(
        body,
        "expected",
        pair.new_str(doc.text(doc.at(doc.root, "after_complete_function"))),
    )
    pair.root = body
    envelope_module_successor(pair.dumps())
    return doc.text(doc.at(doc.root, "before_complete_function"))


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_envelope_gate --migration PATH"
            " | --source PATH --token HEX | --span PATH | --module-span PATH"
            " | --successor PATH | --module-successor PATH | --admission PATH"
            " | --predecessor DIR"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the envelope record and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var source = String("")
    var token = String("")
    var span = String("")
    var successor = String("")
    var module_span = String("")
    var module_successor = String("")
    var admission = String("")
    var predecessor = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--source"
            or word == "--token"
            or word == "--span"
            or word == "--successor"
            or word == "--module-span"
            or word == "--module-successor"
            or word == "--admission"
            or word == "--predecessor"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--source":
                source = value
            elif word == "--span":
                span = value
            elif word == "--successor":
                successor = value
            elif word == "--module-span":
                module_span = value
            elif word == "--module-successor":
                module_successor = value
            elif word == "--admission":
                admission = value
            elif word == "--predecessor":
                predecessor = value
            else:
                token = value
            index += 2
            continue
        _usage()
    var modes = 0
    if migration.byte_length() > 0:
        modes += 1
    if source.byte_length() > 0:
        modes += 1
    if span.byte_length() > 0:
        modes += 1
    if successor.byte_length() > 0:
        modes += 1
    if module_span.byte_length() > 0:
        modes += 1
    if module_successor.byte_length() > 0:
        modes += 1
    if admission.byte_length() > 0:
        modes += 1
    if predecessor.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if source.byte_length() > 0 and token.byte_length() == 0:
        _usage()
    if migration.byte_length() > 0 and token.byte_length() > 0:
        _usage()
    if span.byte_length() > 0 and token.byte_length() > 0:
        _usage()
    if successor.byte_length() > 0 and token.byte_length() > 0:
        _usage()
    if module_span.byte_length() > 0 and token.byte_length() > 0:
        _usage()
    if module_successor.byte_length() > 0 and token.byte_length() > 0:
        _usage()
    if admission.byte_length() > 0 and token.byte_length() > 0:
        _usage()
    if predecessor.byte_length() > 0 and token.byte_length() > 0:
        _usage()
    try:
        if source.byte_length() > 0:
            envelope_token(Path(source).read_text(), token)
            return
        if span.byte_length() > 0:
            envelope_budget_span(Path(span).read_text())
            return
        if successor.byte_length() > 0:
            envelope_successor(Path(successor).read_text())
            return
        if module_span.byte_length() > 0:
            envelope_module_span(Path(module_span).read_text())
            return
        if module_successor.byte_length() > 0:
            envelope_module_successor(Path(module_successor).read_text())
            return
        if admission.byte_length() > 0:
            envelope_admission(Path(admission).read_text())
            return
        if predecessor.byte_length() > 0:
            var folder = predecessor
            if not folder.endswith("/"):
                folder += "/"
            print(
                envelope_predecessor(
                    Path(folder + "record.json").read_text(),
                    Path(folder + "module.mojo").read_text(),
                ),
                end="",
            )
            return
        envelope_record(Path(migration).read_bytes())
    except error:
        print(String(error), file=stderr)
        exit(1)
