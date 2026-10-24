# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The formatter manifest id is a version-4 UUID from Mojo."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tools.format_run_id import random_id


def _hex(text: String) -> Bool:
    """Return whether `text` is 32 lowercase hexadecimal digits."""
    var digits = "0123456789abcdef".as_bytes()
    var raw = text.as_bytes()
    if len(raw) != 32:
        return False
    for byte in raw:
        var found = False
        for index in range(len(digits)):
            if byte == digits[index]:
                found = True
        if not found:
            return False
    return True


def test_each_id_is_a_version_4_uuid() raises:
    var first = random_id()
    var second = random_id()
    assert_true(_hex(first), first)
    assert_true(_hex(second), second)
    assert_true(first != second)
    assert_equal(first[byte=12:13], "4")
    var variant = first[byte=16:17]
    assert_true(
        variant == "8" or variant == "9" or variant == "a" or variant == "b",
        String(variant),
    )
    var source = Path("Makefile").read_text()
    assert_true(source.find("$(TOOL) format_run_id") >= 0)
    assert_true(source.find("import uuid") < 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
