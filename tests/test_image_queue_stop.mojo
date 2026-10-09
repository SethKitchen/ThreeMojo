# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Monotonic stop claims and real worker failure/join boundaries."""

from loaders.image_batch import (
    TextureDecodeSource,
    _claim_decode,
    _decode_worker,
    _stop_decode,
    decode_textures,
)
from render.tasks import TaskGroup
from render.texture import Texture
from std.atomic import Atomic
from std.runtime import parallelism_level
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from std.time import perf_counter_ns


def test_stop_and_repeated_stop_never_rewind_claims() raises:
    var next: UInt64 = 0
    var pointer = Pointer(to=next).unsafe_origin_cast[MutAnyOrigin]()
    assert_equal(_claim_decode(pointer), UInt64(0))
    assert_equal(_claim_decode(pointer), UInt64(1))
    _stop_decode(pointer, 7)
    assert_equal(next, UInt64(7))
    assert_equal(_claim_decode(pointer), UInt64(7))
    _stop_decode(pointer, 7)
    assert_equal(next, UInt64(8))
    assert_equal(_claim_decode(pointer), UInt64(8))
    _stop_decode(pointer, 7)
    assert_equal(next, UInt64(9))


def test_stale_observation_cannot_claim_after_stop() raises:
    var next: UInt64 = 1
    var pointer = Pointer(to=next).unsafe_origin_cast[MutAnyOrigin]()
    var earlier_observation = Atomic[UInt64].fetch_add(pointer, 0)
    assert_true(earlier_observation < UInt64(12))
    _stop_decode(pointer, 12)
    # The claim itself observes the stop. A stale preliminary observation
    # cannot authorize a decode, because only this returned index is used.
    assert_equal(_claim_decode(pointer), UInt64(12))
    assert_equal(_claim_decode(pointer), UInt64(13))


def test_terminal_claims_do_not_wrap_at_signed_limit() raises:
    var count = Int.MAX
    var next = UInt64(count) - 1
    var pointer = Pointer(to=next).unsafe_origin_cast[MutAnyOrigin]()
    assert_equal(_claim_decode(pointer), UInt64(count) - 1)
    _stop_decode(pointer, count)
    for offset in range(4):
        var terminal = _claim_decode(pointer)
        assert_equal(terminal, UInt64(count) + UInt64(offset))
        assert_true(terminal >= UInt64(count))
    _stop_decode(pointer, count)
    assert_equal(next, UInt64(count) + UInt64(4))


@fieldwise_init
struct _CatchSource[
    queue_origin: Origin[mut=True], counter_origin: Origin[mut=True]
](TextureDecodeSource):
    var queue: MutPointer[UInt64, Self.queue_origin]
    # Active, finished, witnessed stop, then one visit count per source job.
    var counters: MutPointer[Int64, Self.counter_origin]
    var count: Int
    var low_succeeds: Bool
    var empty_error: Bool

    def decode(self, index: Int) raises -> Texture:
        _ = Atomic[Int64].fetch_add(self.counters, 1)
        _ = Atomic[Int64].fetch_add(self.counters.unsafe_offset(3 + index), 1)
        if index == 0:
            var until = perf_counter_ns() + 1_000_000_000
            while (
                Atomic[UInt64].fetch_add(self.queue, 0) < UInt64(self.count)
                and perf_counter_ns() < until
            ):
                pass
            if Atomic[UInt64].fetch_add(self.queue, 0) >= UInt64(self.count):
                _ = Atomic[Int64].fetch_add(self.counters.unsafe_offset(2), 1)
        elif index == 1:
            var until = perf_counter_ns() + 1_000_000_000
            while (
                Atomic[Int64].fetch_add(self.counters.unsafe_offset(3), 0) == 0
                and perf_counter_ns() < until
            ):
                pass
        _ = Atomic[Int64].fetch_add(self.counters, -1)
        _ = Atomic[Int64].fetch_add(self.counters.unsafe_offset(1), 1)
        if index == 0 and not self.low_succeeds:
            raise Error("" if self.empty_error else "low source failure")
        if index == 1:
            raise Error("high source failure")
        var pixels = List[UInt8](length=4, fill=UInt8(23 + index))
        return Texture(1, 1, pixels^)


def _join_catch_workers[
    Source: TextureDecodeSource
](
    source: Source,
    next: MutPointer[UInt64, MutAnyOrigin],
    count: Int,
    results: MutPointer[Optional[Texture], MutAnyOrigin],
    errors: MutPointer[Optional[String], MutAnyOrigin],
):
    # The readonly parameter supplies the production immutable source borrow.
    # All pointer owners remain in the caller until this join returns.
    var group = TaskGroup()
    for _ in range(2):
        group.create_task(
            _decode_worker(
                Pointer(to=source).unsafe_origin_cast[ImmutAnyOrigin](),
                next,
                count,
                results,
                errors,
            )
        )
    group.wait()
    _ = Pointer(to=source)


def _actual_catch_stop(low_succeeds: Bool, empty_error: Bool) raises:
    # Simultaneous workers require two runtime threads. The unsigned cursor
    # controls above still run on one-thread hosts, without a concurrency claim.
    if parallelism_level() <= 1:
        return
    var count = 12
    var next: UInt64 = 0
    var counters = List[Int64](length=count + 3, fill=0)
    var source = _CatchSource(
        Pointer(to=next),
        counters.unsafe_ptr(),
        count,
        low_succeeds,
        empty_error,
    )
    var results = List[Optional[Texture]](capacity=count)
    for _ in range(count):
        results.append(None)
    var errors = List[Optional[String]](length=count, fill=None)
    _join_catch_workers(
        source,
        Pointer(to=next).unsafe_origin_cast[MutAnyOrigin](),
        count,
        results.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
        errors.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
    )
    _ = Pointer(to=source)
    _ = next
    assert_equal(counters[0], Int64(0))
    assert_equal(counters[1], Int64(2))
    # Job zero waited for the production catch to move the real cursor.
    assert_equal(counters[2], Int64(1))
    assert_equal(counters[3], Int64(1))
    assert_equal(counters[4], Int64(1))
    for index in range(2, count):
        assert_equal(counters[3 + index], Int64(0))
        assert_false(results[index])
        assert_false(errors[index])
    assert_true(errors[1])
    assert_equal(errors[1].value(), "high source failure")
    if low_succeeds:
        assert_false(errors[0])
        assert_true(results[0])
        assert_equal(results[0].value().pixels[0], UInt8(23))
    else:
        assert_false(results[0])
        assert_true(errors[0])
        assert_equal(
            errors[0].value(), "" if empty_error else "low source failure"
        )
    # Both final terminal claims stay beyond the input count. Nothing was
    # narrowed from that terminal range into a signed result index.
    assert_true(next >= UInt64(count))
    assert_true(next <= UInt64(count + 2))


def test_actual_high_failure_stops_before_lower_failure_finishes() raises:
    _actual_catch_stop(False, False)
    _actual_catch_stop(False, True)


def test_already_claimed_success_finishes_after_actual_failure() raises:
    _actual_catch_stop(True, False)


@fieldwise_init
struct _FirstFailureSource[origin: Origin[mut=True]](TextureDecodeSource):
    var visits: MutPointer[Int64, Self.origin]
    var fail: Bool
    var fail_all: Bool

    def decode(self, index: Int) raises -> Texture:
        _ = Atomic[Int64].fetch_add(self.visits.unsafe_offset(index), 1)
        if self.fail and (self.fail_all or index == 0):
            raise Error("first failure")
        var pixels = List[UInt8](length=4, fill=UInt8(index))
        return Texture(1, 1, pixels^)


def test_public_failures_join_a_prefix_and_retries_start_fresh() raises:
    for workers in [1, 2, 8]:
        var visits = List[Int64](length=64, fill=0)
        var source = _FirstFailureSource(visits.unsafe_ptr(), True, False)
        var returned = False
        var failed = False
        try:
            _ = decode_textures(source, 64, workers)
            returned = True
        except e:
            failed = True
            assert_equal(String(e), "first failure")
        assert_true(failed)
        assert_false(returned)
        assert_equal(visits[0], Int64(1))
        var saw_zero = False
        for index in range(64):
            if visits[index] == 0:
                saw_zero = True
            else:
                assert_false(saw_zero)
                assert_equal(visits[index], Int64(1))
        source.fail = False
        var textures = decode_textures(source, 64, workers)
        assert_equal(len(textures), 64)
        for index in range(64):
            assert_equal(textures[index].pixels[0], UInt8(index))
            assert_true(visits[index] == 1 or visits[index] == 2)


def test_all_failures_decode_no_more_than_the_worker_limit() raises:
    for workers in [-1, 0, 1, 2, 8]:
        for count in [1, 17, 64]:
            var visits = List[Int64](length=count, fill=0)
            var source = _FirstFailureSource(visits.unsafe_ptr(), True, True)
            var failed = False
            try:
                _ = decode_textures(source, count, workers)
            except e:
                failed = True
                assert_equal(String(e), "first failure")
            assert_true(failed)
            var attempted = 0
            var saw_zero = False
            var before = List[Int64](capacity=count)
            for index in range(count):
                before.append(visits[index])
                if visits[index] == 0:
                    saw_zero = True
                else:
                    assert_false(saw_zero)
                    assert_equal(visits[index], Int64(1))
                    attempted += 1
            assert_true(attempted >= 1)
            assert_true(attempted <= min(max(workers, 1), count))
            source.fail = False
            var retry = decode_textures(source, count, workers)
            assert_equal(len(retry), count)
            for index in range(count):
                assert_equal(visits[index], before[index] + 1)
                assert_equal(retry[index].pixels[0], UInt8(index))


@fieldwise_init
struct _LifetimeSource[origin: Origin[mut=True]](TextureDecodeSource):
    # Active, finished, destroyed, active at destruction, finished at
    # destruction, first callback started, failure announced, owned-byte reads.
    var counters: MutPointer[Int64, Self.origin]
    var pixels: List[UInt8]

    def __deinit__(deinit self):
        self.counters[unsafe_offset=3] = Atomic[Int64].fetch_add(
            self.counters, 0
        )
        self.counters[unsafe_offset=4] = Atomic[Int64].fetch_add(
            self.counters.unsafe_offset(1), 0
        )
        _ = Atomic[Int64].fetch_add(self.counters.unsafe_offset(2), 1)

    def decode(self, index: Int) raises -> Texture:
        _ = Atomic[Int64].fetch_add(self.counters, 1)
        if index == 0:
            _ = Atomic[Int64].fetch_add(self.counters.unsafe_offset(5), 1)
            var until = perf_counter_ns() + 1_000_000_000
            while (
                Atomic[Int64].fetch_add(self.counters.unsafe_offset(6), 0) == 0
                and perf_counter_ns() < until
            ):
                pass
            assert_equal(
                Atomic[Int64].fetch_add(self.counters.unsafe_offset(6), 0), 1
            )
            assert_equal(
                Atomic[Int64].fetch_add(self.counters.unsafe_offset(2), 0), 0
            )
            assert_equal(self.pixels[0], UInt8(71))
            _ = Atomic[Int64].fetch_add(self.counters.unsafe_offset(7), 1)
        else:
            var until = perf_counter_ns() + 1_000_000_000
            while (
                Atomic[Int64].fetch_add(self.counters.unsafe_offset(5), 0) == 0
                and perf_counter_ns() < until
            ):
                pass
            _ = Atomic[Int64].fetch_add(self.counters.unsafe_offset(6), 1)
        var pixels = self.pixels.copy()
        _ = Atomic[Int64].fetch_add(self.counters, -1)
        _ = Atomic[Int64].fetch_add(self.counters.unsafe_offset(1), 1)
        if index == 1:
            raise Error("owned source failure")
        return Texture(1, 1, pixels^)


def _decode_with_last_source_use[
    origin: Origin[mut=True]
](counters: MutPointer[Int64, origin]) raises:
    var pixels = List[UInt8](length=4, fill=UInt8(71))
    var source = _LifetimeSource(counters, pixels^)
    # Do not retain source after this call. Its destructor must run when the
    # public failure unwinds this helper, after every claimed callback joins.
    _ = decode_textures(source, 2, 2)


def test_owned_source_is_destroyed_after_failed_workers_join() raises:
    if parallelism_level() <= 1:
        return
    var counters = List[Int64](length=8, fill=0)
    var failed = False
    try:
        _decode_with_last_source_use(counters.unsafe_ptr())
    except e:
        failed = True
        assert_equal(String(e), "owned source failure")
    assert_true(failed)
    assert_equal(counters[0], Int64(0))
    assert_equal(counters[1], Int64(2))
    assert_equal(counters[2], Int64(1))
    assert_equal(counters[3], Int64(0))
    assert_equal(counters[4], Int64(2))
    assert_equal(counters[5], Int64(1))
    assert_equal(counters[6], Int64(1))
    assert_equal(counters[7], Int64(1))


def main() raises:
    print("IMAGE_QUEUE_STOP_RUNTIME_THREADS", parallelism_level())
    TestSuite.discover_tests[__functions_in_module()]().run()
