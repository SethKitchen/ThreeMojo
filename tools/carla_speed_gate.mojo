# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the speed-parser successor record.

    carla_speed_gate --migration PATH --accepted PATH --module PATH --lexical PATH --xml PATH

The program checks the texts it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._python_json import PY_INT, PyJson
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "47e949673fb8740816c06d455654c7e7ae43f65ce7d7568a201e83ae16c49364"
)
comptime _MODULE = "extensions/carla/speed_limits.mojo"
comptime _LEXICAL = "tests/test_carla_speed_lexical.mojo"
comptime _XML = "tests/test_carla_speed_xml_lexical.mojo"


def _fail(message: String) raises:
    """Raise one speed-parser failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("reviewed speed parser successor: " + message)


def _field(doc: PyJson, name: String) raises -> String:
    """Return one string or integer field as text.

    Args:
        doc: The record.
        name: The field name.

    Returns:
        The field text.

    Raises:
        Error: The field is absent.
    """
    return doc.text(doc.at(doc.root, name))


def speed_parser(
    migration: Span[UInt8, _],
    accepted: Span[UInt8, _],
    module: String,
    lexical: Span[UInt8, _],
    xml: Span[UInt8, _],
) raises:
    """Require the speed-parser record and its live module.

    Args:
        migration: The successor record bytes.
        accepted: The prior accepted-migration bytes.
        module: The historical speed-limits source.
        lexical: The lexical correctness test bytes.
        xml: The XML lexical correctness test bytes.

    Raises:
        Error: The record, the grammar, or a bound test changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed exact edge")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    var schema = doc.at(doc.root, "schema")
    if (
        doc.kind(schema) != PY_INT
        or doc.text(schema) != "1"
        or _field(doc, "path") != _MODULE
    ):
        _fail("unexpected successor scope")
    var tests = doc.at(doc.root, "correctness_tests")
    var lexical_digest = String("")
    var xml_digest = String("")
    var index = 0
    var count = doc.length(tests)
    while index < count:
        var path = doc.key(tests, index)
        var digest = doc.text(doc.value(tests, index))
        if path == _LEXICAL and lexical_digest.byte_length() == 0:
            lexical_digest = digest
        elif path == _XML and xml_digest.byte_length() == 0:
            xml_digest = digest
        else:
            _fail("unexpected correctness test set")
        index += 1
    if lexical_digest.byte_length() == 0 or xml_digest.byte_length() == 0:
        _fail("unexpected correctness test set")
    if sha256_hex(accepted) != _field(doc, "prior_accepted_migration_sha256"):
        _fail("prior accepted lineage changed")
    var sides = List[String]()
    sides.append("before")
    sides.append("after")
    for name in sides:
        var text = _field(doc, name + "_complete_module")
        if sha256_hex(text.as_bytes()) != _field(
            doc, name + "_sha256"
        ) or token_sha256(text) != _field(doc, name + "_token_sha256"):
            _fail("recorded source identity changed")
    if token_sha256(module) != _field(doc, "after_token_sha256"):
        _fail("actual grammar, validation, binding or mantissa graph changed")
    if sha256_hex(lexical) != lexical_digest:
        _fail("bound parser/XML correctness test changed: " + _LEXICAL)
    if sha256_hex(xml) != xml_digest:
        _fail("bound parser/XML correctness test changed: " + _XML)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_speed_gate --migration PATH --accepted PATH"
            " --module PATH --lexical PATH --xml PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the speed-parser record and print nothing on success."""
    var migration = String("")
    var accepted = String("")
    var module = String("")
    var lexical = String("")
    var xml = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--accepted"
            or word == "--module"
            or word == "--lexical"
            or word == "--xml"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--accepted":
                accepted = value
            elif word == "--module":
                module = value
            elif word == "--lexical":
                lexical = value
            else:
                xml = value
            index += 2
            continue
        _usage()
    if (
        migration.byte_length() == 0
        or accepted.byte_length() == 0
        or module.byte_length() == 0
        or lexical.byte_length() == 0
        or xml.byte_length() == 0
    ):
        _usage()
    try:
        speed_parser(
            Path(migration).read_bytes(),
            Path(accepted).read_bytes(),
            Path(module).read_text(),
            Path(lexical).read_bytes(),
            Path(xml).read_bytes(),
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
