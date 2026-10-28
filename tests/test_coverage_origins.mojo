# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A short origin index is refused before a checkpoint is accepted."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.coverage_origins import generation_record


def test_a_short_origin_index_is_refused() raises:
    """An empty index fails before the checkpoint is read."""
    var root = "/tmp/coverage-origins-mojo"
    var build = root + "/build"
    makedirs(build, exist_ok=True)
    Path(build + "/origins.ready").write_bytes(List[UInt8]())
    with assert_raises(contains="Truncated generation origin header"):
        _ = generation_record(root, build, List[UInt8](), "compiler", "", "mojo")


def main() raises:
    """Run the origin record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
