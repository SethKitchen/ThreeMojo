# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A capture receipt must name its capture before the bytes are hashed."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.coverage_captures import verify_captures


def test_a_capture_receipt_is_refused_before_the_bytes() raises:
    """A missing receipt and a short receipt fail with their own text."""
    var root = "/tmp/coverage-captures-mojo"
    makedirs(root, exist_ok=True)
    var envelope = root + "/envelope.json"
    Path(envelope).write_text(
        '{"sha256":"abc","receipt":{"execution":{"suites":["tests/test_fixture.mojo"],'
        + '"profiles":["raw"],"compiler":[{"literal":"mojo"}],'
        + '"cache":"@ROOT@/.cache/native-coverage"}}}'
    )
    with assert_raises(contains="missing capture receipt:"):
        var missing = List[String]()
        missing.append(root + "/missing.txt.gz")
        verify_captures(envelope, missing)
    Path(root + "/cap.txt.gz.proof.json").write_text('{"schema":"no"}\n')
    with assert_raises(contains="Malformed coverage capture receipt: cap.txt.gz"):
        var captures = List[String]()
        captures.append(root + "/cap.txt.gz")
        verify_captures(envelope, captures)


def main() raises:
    """Run the capture receipt tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
