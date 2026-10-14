# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The EXR packager rewrites the committed hex files and manifest.

The native files come back from the committed hex. The `.input` sources are
not committed, so the three source-error fields are left out of the check.
"""

from std.os import listdir
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from assets.exr_codecs.package_fixtures import hex_lines, package
from tools._json_tools import json_tokens

comptime FOLDER = "assets/exr_codecs"


def _bytes(text: String) raises -> List[UInt8]:
    """Decode hex lines."""
    var out = List[UInt8]()
    var high = -1
    for byte in text.as_bytes():
        var value = Int(byte)
        var digit: Int
        if value >= ord("0") and value <= ord("9"):
            digit = value - ord("0")
        elif value >= ord("a") and value <= ord("f"):
            digit = value - ord("a") + 10
        else:
            continue
        if high < 0:
            high = digit
        else:
            out.append(UInt8(high * 16 + digit))
            high = -1
    return out^


def _without_source_errors(text: String) -> List[String]:
    """Return the tokens without the three source-error members."""
    var found = json_tokens(text)[0].copy()
    var kept = List[String]()
    var index = 0
    while index < len(found):
        var token = found[index]
        if token.startswith('"max_') and token.endswith('_error"'):
            _ = kept.pop()
            index += 3
            continue
        kept.append(token)
        index += 1
    return kept^


def test_hex_lines_wrap_at_128_digits() raises:
    var data = List[UInt8](length=65, fill=171)
    var text = hex_lines(data)
    assert_equal(text, "ab" * 64 + "\nab\n")


def test_the_packager_rewrites_the_committed_files() raises:
    var fixtures = mkdtemp()
    var destination = mkdtemp()
    var count = 0
    for name in listdir(FOLDER):
        if name.endswith(".hex"):
            Path(
                fixtures + "/" + String(name[byte = : name.byte_length() - 4])
            ).write_bytes(_bytes(Path(FOLDER + "/" + name).read_text()))
            count += 1
    assert_equal(count, 130)
    var summary = package(fixtures, destination)
    assert_true(summary.startswith("5 9 compressed chunks 18 "))
    for name in listdir(destination):
        if name.endswith(".hex"):
            assert_equal(
                Path(destination + "/" + name).read_text(),
                Path(FOLDER + "/" + name).read_text(),
                name,
            )
    assert_true(
        _without_source_errors(Path(destination + "/manifest.json").read_text())
        == _without_source_errors(Path(FOLDER + "/manifest.json").read_text())
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
