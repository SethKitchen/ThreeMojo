# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The stored-moment report keeps its shape and pin digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tools._spiral_moment_derive import (
    moment_products_from_rows,
    write_moment_products,
    write_products_after_report,
)
from tools._moment_report import (
    moment_meta_from_rows,
    moment_report,
    verified_table_then_meta,
)
from tools._sha256 import sha256_hex


def _meta(count: String) -> String:
    """Return one report input document.

    Args:
        count: The JSON text of `byte_count`.

    Returns:
        The meta document.
    """
    return (
        '{"byte_count":'
        + count
        + ',"source_sha256":"aa","be64_sha256":"bb","root":"/tmp/root",'
        + '"ideal_half_projection":{"helper_projections":5,'
        + '"rate_half_commutations":2,"projected_ast_sha256":"cc"},'
        + '"dependency_scope":{"group":"stored_arithmetic","paths":'
        + '["extensions/carla/curve_interval.mojo"]},"routing_sha256":'
        + '{"ideal_caller":"dd"},"source_block_sha256":{"ideal_spiral":"ee"}}'
    )


def _bytes(text: String) -> List[UInt8]:
    """Copy one text into raw bytes.

    Args:
        text: The text.

    Returns:
        The UTF-8 bytes.
    """
    var out = List[UInt8]()
    for byte in text.as_bytes():
        out.append(byte)
    return out^


def _pins() -> List[List[UInt8]]:
    """Return three pin files, including one non-UTF-8 file.

    Returns:
        The pin bytes.
    """
    var pins = List[List[UInt8]]()
    pins.append(_bytes("one"))
    pins.append(_bytes("two"))
    var raw = List[UInt8]()
    raw.append(0xFF)
    pins.append(raw^)
    return pins^


def test_the_moment_report_keeps_its_fields() raises:
    """A valid payload reports the historical fields and raw digests."""
    var pins = _pins()
    var digest_0 = sha256_hex(Span(pins[0]))
    var digest_1 = sha256_hex(Span(pins[1]))
    var digest_2 = sha256_hex(Span(pins[2]))
    var report = moment_report(_meta("22528"), pins)
    assert_equal(
        report,
        '{"scope":"fixed-count quadrant-zero ideal stored-polynomial'
        " coefficients and tight endpoints"
        ' only","counts":64,"coefficients":1408,"words":2816,"payload_bytes":22528,"zeroth_moment":"36028797018963971/36028797018963968","source_sha256":"aa","words_be64_sha256":"bb","pin_file_sha256":"'
        + digest_0
        + '","dependency_pin_file_sha256":"'
        + digest_1
        + '","environment_guard_pin_sha256":"'
        + digest_2
        + '","environment_guard_scope":"Invocation-local predicate and caller'
        " source contracts only; no native FP-state/codegen"
        ' qualification","checked_source_root":"/tmp/root","ideal_half_projection":{"helper_projections":5,"rate_half_commutations":2,"projected_ast_sha256":"cc"},"dependency_scope":{"group":"stored_arithmetic","paths":["extensions/carla/curve_interval.mojo"]},"routing_sha256":{"ideal_caller":"dd"},"source_block_sha256":{"ideal_spiral":"ee"},"not_certified":["rounded'
        ' geometry/error graphs","branch eligibility","native'
        ' execution/codegen","query correctness/performance"]}',
    )


def test_a_float_payload_size_keeps_its_spelling() raises:
    """`22528.0` matches the integer size and keeps its spelling."""
    var report = moment_report(_meta("22528.0"), _pins())
    assert_equal(
        report.find('"payload_bytes":22528.0'),
        report.find('"payload_bytes":'),
    )


def test_a_changed_report_shape_is_refused() raises:
    """A wrong payload size or pin count keeps the report message."""
    with assert_raises(contains="wrong derived table shape"):
        _ = moment_report(_meta("22529"), _pins())
    var short = List[List[UInt8]]()
    short.append(_bytes("one"))
    short.append(_bytes("two"))
    with assert_raises(contains="wrong derived table shape"):
        _ = moment_report(_meta("22528"), short)


def test_bad_rows_fail_before_the_report_meta() raises:
    """A short row list fails before a missing meta field is checked."""
    with assert_raises(
        contains="spiral moment derive: wrong derived table shape"
    ):
        _ = moment_meta_from_rows('{"rows":[]}')


def _coefficient_rows() -> String:
    """Return 64 derived rows of zero endpoint words.

    Returns:
        A JSON list with eleven cosine pairs and eleven sine pairs.
    """
    var coeff = String('{"words":["0","0"]}')
    var side = String("[")
    var index = 0
    while index < 11:
        if index > 0:
            side += ","
        side += coeff
        index += 1
    side += "]"
    var row = '{"cosine":' + side + ',"sine":' + side + "}"
    var rows = String("[")
    var row_index = 0
    while row_index < 64:
        if row_index > 0:
            rows += ","
        rows += row
        row_index += 1
    rows += "]"
    return rows


def test_the_table_is_checked_before_the_report_meta() raises:
    """A bad table fails before a missing meta field is checked."""
    with assert_raises(
        contains="spiral moment derive: wrong derived table shape"
    ):
        _ = verified_table_then_meta('{"rows":[],"source":"nope"}')
    var payload = '{"rows":' + _coefficient_rows() + ',"source":"nope"}'
    with assert_raises(contains="missing or malformed table declaration"):
        _ = verified_table_then_meta(payload)


def test_bad_rows_fail_before_the_generated_products() raises:
    """A short row list fails before the table source or the payload bytes."""
    with assert_raises(
        contains="spiral moment derive: wrong derived table shape"
    ):
        _ = moment_products_from_rows("[]")
    with assert_raises(
        contains="spiral moment derive: wrong derived table shape"
    ):
        _ = write_moment_products("[]", Path("/tmp/moment-product-bytes"))
    with assert_raises(contains="KeyError: 'report'"):
        _ = write_products_after_report(
            '{"rows":[]}', Path("/tmp/moment-product-bytes")
        )
    with assert_raises(
        contains="spiral moment derive: wrong derived table shape"
    ):
        _ = write_products_after_report(
            '{"report":{"source_sha256":"aa"},"rows":[]}',
            Path("/tmp/moment-product-bytes"),
        )
    with assert_raises(
        contains="spiral moment derive: wrong derived table shape"
    ):
        _ = write_products_after_report(
            '{"report":{"source_sha256":"aa"},"rows":[],'
            + '"destinations":["/src"],"protected":["/src"]}',
            Path("/tmp/moment-product-bytes"),
        )


def main() raises:
    """Run the moment report tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
