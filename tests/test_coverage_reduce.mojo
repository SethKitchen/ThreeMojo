# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A joined capture reduces like separately fed lines."""

from std.testing import TestSuite, assert_equal

from tools._coverage_reduce import reduce_capture
from tools.coverage_io import Reducer


def test_joined_lines_reduce_like_separate_feeds() raises:
    """Keeping the newline on each record matches one feed per line."""
    var lines = List[String]()
    lines.append("COVLINE:recursive:1.0:T\n")
    lines.append("plain\n")
    lines.append("COVLINE:recursive:1.0:T\n")
    var joined = String("")
    var reducer = Reducer()
    for line in lines:
        joined += line
        reducer.feed(line)
    assert_equal(reduce_capture(joined), reducer.output)


def main() raises:
    """Run the capture reduction tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
