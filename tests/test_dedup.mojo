# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `coverage.dedup`."""

from coverage.dedup import (
    BRANCH_PRINT_VECTOR,
    BRANCH_QUIET,
    BlockOrigin,
    DEDUP_BYTES,
    Dedup,
)
from coverage.mcdc import is_mcdc_covered, parse_traces
from coverage.runtime import BRANCH_PREFIX
from std.testing import TestSuite, assert_equal, assert_false, assert_true


@fieldwise_init
struct _Place(Copyable, Movable):
    """Where one id sits in a byte list."""

    var start: Int
    var count: Int


struct _Ids:
    """Bytes of every id a test feeds, so a pointer into them stays valid.

    Add every id before taking a pointer. A later add can move the list.
    """

    var bytes: List[UInt8]

    def __init__(out self):
        self.bytes = List[UInt8]()

    def add(mut self, text: String) -> _Place:
        """Copy `text` and return where it sits."""
        var start = len(self.bytes)
        var count = text.byte_length()
        var raw = (
            text.unsafe_ptr()
            .unsafe_bitcast[UInt8]()
            .unsafe_mut_cast[True]()
            .unsafe_origin_cast[BlockOrigin]()
        )
        for index in range(count):
            self.bytes.append(raw.unsafe_offset(index)[])
        return _Place(start, count)

    def ptr(self, place: _Place) -> Pointer[UInt8, BlockOrigin]:
        """Return the bytes of `place`. Do not add more ids after this."""
        return (
            self.bytes.unsafe_ptr()
            .unsafe_offset(place.start)
            .unsafe_mut_cast[True]()
            .unsafe_origin_cast[BlockOrigin]()
        )


def _line(id: String, value: Bool) -> String:
    var mark = String(":F")
    if value:
        mark = String(":T")
    return BRANCH_PREFIX + id + mark + "\n"


def _feed(
    mut table: Dedup,
    ids: _Ids,
    mut stream: String,
    place: _Place,
    value: Bool,
):
    """Apply one probe and append the records a caller would write."""
    var code = table.absorb_branch(ids.ptr(place), place.count, value)
    if code == BRANCH_PRINT_VECTOR:
        var start = table.vector_start()
        for index in range(start, table.pending_count()):
            stream += _line(
                table.pending_text(index), table.pending_value(index)
            )
        var id = String()
        var raw = ids.ptr(place)
        for index in range(place.count):
            id += String(chr(Int(raw.unsafe_offset(index)[])))
        stream += _line(id, value)
        table.drop_vector()


def test_a_line_is_claimed_once() raises:
    var block = List[UInt8](length=DEDUP_BYTES, fill=0)
    var table = Dedup(block.unsafe_ptr().unsafe_origin_cast[BlockOrigin]())
    var ids = _Ids()
    var first = ids.add(String("render/rasterizer:12"))
    var second = ids.add(String("render/rasterizer:13"))
    assert_true(table.claim_line(ids.ptr(first), first.count))
    assert_false(table.claim_line(ids.ptr(first), first.count))
    assert_true(table.claim_line(ids.ptr(second), second.count))


def test_a_simple_branch_records_each_outcome_once() raises:
    var block = List[UInt8](length=DEDUP_BYTES, fill=0)
    var table = Dedup(block.unsafe_ptr().unsafe_origin_cast[BlockOrigin]())
    var ids = _Ids()
    var decision = ids.add(String("m:4"))
    var text = ids.ptr(decision)
    assert_equal(
        table.absorb_branch(text, decision.count, True), BRANCH_PRINT_VECTOR
    )
    assert_equal(table.pending_count(), 0)
    table.drop_vector()
    assert_equal(table.absorb_branch(text, decision.count, True), BRANCH_QUIET)
    assert_equal(
        table.absorb_branch(text, decision.count, False), BRANCH_PRINT_VECTOR
    )
    table.drop_vector()
    assert_equal(table.absorb_branch(text, decision.count, False), BRANCH_QUIET)


def test_a_repeated_vector_stays_quiet_and_mcdc_still_closes() raises:
    var block = List[UInt8](length=DEDUP_BYTES, fill=0)
    var table = Dedup(block.unsafe_ptr().unsafe_origin_cast[BlockOrigin]())
    var ids = _Ids()
    var c0 = ids.add(String("m:4.0"))
    var c1 = ids.add(String("m:4.1"))
    var decision = ids.add(String("m:4"))
    var stream = String()
    _feed(table, ids, stream, c0, True)
    _feed(table, ids, stream, c1, True)
    _feed(table, ids, stream, decision, True)
    _feed(table, ids, stream, c0, True)
    _feed(table, ids, stream, c1, True)
    _feed(table, ids, stream, decision, True)
    _feed(table, ids, stream, c0, False)
    _feed(table, ids, stream, decision, False)
    _feed(table, ids, stream, c0, True)
    _feed(table, ids, stream, c1, False)
    _feed(table, ids, stream, decision, False)

    var traces = parse_traces(stream)
    assert_equal(len(traces), 1)
    var trace = traces[0].copy()
    assert_equal(len(trace.evaluations), 3)
    assert_true(is_mcdc_covered(trace, 0))
    assert_true(is_mcdc_covered(trace.copy(), 1))
    var copies = 0
    for line in stream.splitlines():
        if String(line) == String("COVBRANCH:m:4:T"):
            copies += 1
    assert_equal(copies, 1)


def test_an_inner_decision_leaves_the_outer_condition() raises:
    var block = List[UInt8](length=DEDUP_BYTES, fill=0)
    var table = Dedup(block.unsafe_ptr().unsafe_origin_cast[BlockOrigin]())
    var ids = _Ids()
    var outer = ids.add(String("outer:1.0"))
    var inner_c = ids.add(String("inner:2.0"))
    var inner = ids.add(String("inner:2"))
    var outer_d = ids.add(String("outer:1"))
    assert_equal(
        table.absorb_branch(ids.ptr(outer), outer.count, True), BRANCH_QUIET
    )
    assert_equal(
        table.absorb_branch(ids.ptr(inner_c), inner_c.count, False),
        BRANCH_QUIET,
    )
    assert_equal(
        table.absorb_branch(ids.ptr(inner), inner.count, False),
        BRANCH_PRINT_VECTOR,
    )
    assert_equal(table.vector_start(), 1)
    assert_equal(table.pending_text(1), String("inner:2.0"))
    table.drop_vector()
    assert_equal(table.pending_count(), 1)
    assert_equal(table.pending_text(0), String("outer:1.0"))
    assert_equal(
        table.absorb_branch(ids.ptr(outer_d), outer_d.count, True),
        BRANCH_PRINT_VECTOR,
    )
    assert_equal(table.vector_start(), 0)
    assert_equal(table.pending_text(0), String("outer:1.0"))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
