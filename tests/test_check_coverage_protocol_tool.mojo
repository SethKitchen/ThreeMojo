# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reduced coverage records match the protocol reducer's accepted stream."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools.check_coverage_protocol import reduce_text


def _repeat(text: String, count: Int) -> String:
    """Return `text` repeated `count` times."""
    var out = String()
    var index = 0
    while index < count:
        out += text
        index += 1
    return out


def _record(size: Int) -> String:
    """Return one `COVEVAL2` record of `size` bytes."""
    var prefix = "COVEVAL2:é:1:T:"
    var vector = String()
    while prefix.byte_length() + vector.byte_length() + 2 < size:
        vector += "T"
    return prefix + vector + ";\n"


def test_distinct_hits_and_vectors_are_kept_in_order() raises:
    var raw = (
        "COVLINE:recursive:1.0:T\n"
        "COVLINE:recursive:1.0:F\n"
        "COVEVAL2:recursive:1:F:F-;\n"
        "COVLINE:abandoned:2.0:T\n"
        "COVEVAL2:recursive:1:F:TF;\n"
        "COVEVAL2:recursive:1:T:TT;\n"
        "COVEVAL2:callback:1:F:TF;\n"
        "COVEVAL2:callback:1:T:TF;\n"
        "COVLINE:recursive:1:T\n"
        "COVBRANCH:simple:3:F\n"
        "exception from abandoned evaluation\n"
    )
    var expected = (
        "COVLINE:recursive:1.0:T\n"
        "COVLINE:recursive:1.0:F\n"
        "COVEVAL2:recursive:1:F:F-;\n"
        "COVLINE:abandoned:2.0:T\n"
        "COVEVAL2:recursive:1:F:TF;\n"
        "COVEVAL2:recursive:1:T:TT;\n"
        "COVEVAL2:callback:1:F:TF;\n"
        "COVEVAL2:callback:1:T:TF;\n"
        "COVLINE:recursive:1:T\n"
        "COVLINE:simple:3:F\n"
        "COVBRANCH:simple:3:F\n"
        "exception from abandoned evaluation\n"
    )
    var probes = raw.replace("exception from abandoned evaluation\n", "")
    assert_equal(reduce_text(raw + _repeat(probes, 2)), expected)


def test_padding_and_repeated_copies_do_not_change_the_record() raises:
    var record = _record(512)
    assert_equal(record.byte_length(), 512)
    assert_equal(reduce_text(" " + record), record)
    assert_equal(reduce_text(_repeat(record, 3)), record)
    assert_equal(_record(511).byte_length(), 511)
    assert_equal(reduce_text(_record(511)), _record(511))


def test_an_oversized_or_ambiguous_record_is_refused() raises:
    with assert_raises(contains="Malformed or truncated evaluation record"):
        _ = reduce_text(_record(513))
    with assert_raises(contains="Inconsistent repeated truth conversion"):
        _ = reduce_text("COVEVAL2:m:4:F:?-;\n")
    with assert_raises(contains="Legacy compound coverage is ambiguous"):
        _ = reduce_text("COVBRANCH:m:4.0:T\n")


def test_diagnostics_pass_through_on_every_copy() raises:
    var raw = "hello\nCOVBRANCH:unparsed\n"
    assert_equal(reduce_text(_repeat(raw, 3)), _repeat(raw, 3))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
