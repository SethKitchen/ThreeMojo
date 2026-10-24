# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The town count report matches the former Python `counts.py` output."""

from std.os.path import realpath
from std.testing import TestSuite, assert_equal

from tools._sha256 import sha256_hex
from tools.carla_count_derivation import derive


def test_the_report_matches_the_python_count_script() raises:
    var report = derive(realpath("."))
    assert_equal(
        sha256_hex(Span(report.file.as_bytes())),
        "f74a23428648f8777fd78623fe5b64c2a58a4cf951bdf122ed355d9be43cce68",
    )
    assert_equal(
        sha256_hex(Span(report.summary.as_bytes())),
        "dd4077aaca765df661a7c107af0aed2d39dcdccccba3c9f1048b52ef12a4902f",
    )
    assert_equal(report.file.byte_length(), 4918)
    assert_equal(report.summary.byte_length(), 1513)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
