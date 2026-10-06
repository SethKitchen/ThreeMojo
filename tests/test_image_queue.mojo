# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""The production image queue's bounds, progress, errors, and move ownership."""

from loaders.image_batch import (
    TextureDecodeSource,
    _claim_decode,
    decode_textures,
)
from render.texture import Texture
from std.atomic import Atomic
from std.runtime import parallelism_level
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from std.time import perf_counter_ns


def _peak[
    origin: Origin[mut=True]
](address: MutPointer[Int64, origin], value: Int64):
    var expected = Atomic[Int64].fetch_add(address, 0)
    while value > expected:
        if Atomic[Int64].compare_exchange(address, expected, value):
            break


@fieldwise_init
struct _TrackedSource[
    counter_origin: Origin[mut=True],
    visit_origin: Origin[mut=True],
    address_origin: Origin[mut=True],
](TextureDecodeSource):
    # Active jobs, peak jobs, staged bytes, peak bytes, finished jobs,
    # job 2 finished while job 0 was active, job 0 finished, job 0 started.
    var counters: MutPointer[Int64, Self.counter_origin]
    var visits: MutPointer[Int64, Self.visit_origin]
    var addresses: MutPointer[
        Optional[MutPointer[UInt8, UntrackedOrigin[mut=True]]],
        Self.address_origin,
    ]
    var slow: Int
    var fail: Bool
    var empty_error: Bool

    def decode(self, index: Int) raises -> Texture:
        _ = Atomic[Int64].fetch_add(self.visits.unsafe_offset(index), 1)
        var active = Atomic[Int64].fetch_add(self.counters, 1) + 1
        _peak(self.counters.unsafe_offset(1), active)
        if self.slow == 0 and parallelism_level() > 1:
            if index == 0:
                _ = Atomic[Int64].fetch_add(self.counters.unsafe_offset(7), 1)
            else:
                # Do not let a fast claimant outrun a descheduled first
                # claimant before job 0 has entered the active region.
                var until_started = perf_counter_ns() + 1_000_000_000
                while (
                    Atomic[Int64].fetch_add(self.counters.unsafe_offset(7), 0)
                    == 0
                    and perf_counter_ns() < until_started
                ):
                    pass
        var bytes = (index + 1) * 1024
        var held = Atomic[Int64].fetch_add(
            self.counters.unsafe_offset(2), Int64(bytes)
        ) + Int64(bytes)
        _peak(self.counters.unsafe_offset(3), held)
        var compressed = List[UInt8](length=bytes, fill=UInt8(index))
        if index == 0 and self.slow == 0 and parallelism_level() > 1:
            # Hold the first job until a later job proves queue progress.
            # The deadline prevents a faulty scheduler from hanging this
            # test. The assertion below still rejects missing progress.
            var until = perf_counter_ns() + 1_000_000_000
            while (
                Atomic[Int64].fetch_add(self.counters.unsafe_offset(5), 0) == 0
                and perf_counter_ns() < until
            ):
                pass
        else:
            var until = perf_counter_ns() + (
                100_000_000 if index == self.slow else 100_000
            )
            while perf_counter_ns() < until:
                pass
        var pixels = List[UInt8](length=16, fill=UInt8(20 + index))
        var texture = Texture(2, 2, pixels^)
        self.addresses[
            unsafe_offset=index
        ] = texture.pixels.unsafe_ptr().unsafe_origin_cast[
            UntrackedOrigin[mut=True]
        ]()
        _ = len(compressed)
        _ = Atomic[Int64].fetch_add(
            self.counters.unsafe_offset(2), -Int64(bytes)
        )
        _ = Atomic[Int64].fetch_add(self.counters, -1)
        _ = Atomic[Int64].fetch_add(self.counters.unsafe_offset(4), 1)
        if (
            index == 2
            and Atomic[Int64].fetch_add(self.counters.unsafe_offset(6), 0) == 0
        ):
            _ = Atomic[Int64].fetch_add(self.counters.unsafe_offset(5), 1)
        if index == 0:
            _ = Atomic[Int64].fetch_add(self.counters.unsafe_offset(6), 1)
        if self.fail and (index == 1 or index == 3):
            if self.empty_error:
                raise Error("")
            raise Error("failure " + String(index))
        return texture^


def test_claims_continue_while_earlier_jobs_are_unfinished() raises:
    var next: UInt64 = 0
    var pointer = Pointer(to=next).unsafe_origin_cast[MutAnyOrigin]()
    assert_equal(_claim_decode(pointer), UInt64(0))
    assert_equal(_claim_decode(pointer), UInt64(1))
    # Job 1 can finish and claim 2 while job 0 remains unfinished. There
    # is no batch completion state for the claim operation to wait on.
    assert_equal(_claim_decode(pointer), UInt64(2))
    assert_equal(_claim_decode(pointer), UInt64(3))
    assert_equal(next, UInt64(4))


def test_workers_bound_active_staging_and_move_completed_mips() raises:
    for count in [-1, 0, 1, 5]:
        for workers in [-1, 0, 1, 2, 8]:
            var counters = List[Int64](length=8, fill=0)
            var visits = List[Int64](length=max(0, count), fill=0)
            var addresses = List[
                Optional[MutPointer[UInt8, UntrackedOrigin[mut=True]]]
            ](length=max(0, count), fill=None)
            var source = _TrackedSource(
                counters.unsafe_ptr(),
                visits.unsafe_ptr(),
                addresses.unsafe_ptr(),
                -1,
                False,
                False,
            )
            var textures = decode_textures(source, count, workers)
            assert_equal(len(textures), max(0, count))
            assert_equal(counters[0], 0)
            assert_equal(counters[2], 0)
            assert_equal(Int(counters[4]), max(0, count))
            var bound = min(max(1, workers), max(0, count))
            assert_true(Int(counters[1]) <= bound)
            assert_true(Int(counters[3]) <= bound * max(0, count) * 1024)
            for index in range(max(0, count)):
                assert_equal(visits[index], 1)
                assert_equal(textures[index].levels, 2)
                assert_equal(len(textures[index].pixels), 20)
                assert_equal(textures[index].pixels[0], UInt8(20 + index))
                assert_equal(
                    textures[index]
                    .pixels.unsafe_ptr()
                    .unsafe_origin_cast[UntrackedOrigin[mut=True]](),
                    addresses[index].value(),
                )


def test_queue_progresses_past_a_slow_first_image() raises:
    var counters = List[Int64](length=8, fill=0)
    var visits = List[Int64](length=5, fill=0)
    var addresses = List[
        Optional[MutPointer[UInt8, UntrackedOrigin[mut=True]]]
    ](length=5, fill=None)
    var source = _TrackedSource(
        counters.unsafe_ptr(),
        visits.unsafe_ptr(),
        addresses.unsafe_ptr(),
        0,
        False,
        False,
    )
    var textures = decode_textures(source, 5, 2)
    assert_equal(len(textures), 5)
    assert_equal(counters[4], 5)
    # A one-thread runtime still proves ordering and the upper bound. It
    # cannot demonstrate simultaneous execution of two decode workers.
    if parallelism_level() > 1:
        assert_equal(counters[5], 1)
        assert_equal(counters[1], 2)


def test_first_error_is_deterministic_and_all_workers_finish() raises:
    for workers in [1, 2, 8]:
        for empty in [False, True]:
            var counters = List[Int64](length=8, fill=0)
            var visits = List[Int64](length=5, fill=0)
            var addresses = List[
                Optional[MutPointer[UInt8, UntrackedOrigin[mut=True]]]
            ](length=5, fill=None)
            var source = _TrackedSource(
                counters.unsafe_ptr(),
                visits.unsafe_ptr(),
                addresses.unsafe_ptr(),
                1,
                True,
                empty,
            )
            # A later failure can complete first. Even an empty error is
            # retained as a failure rather than treated as a successful slot.
            var raised = False
            var message = String("no error")
            try:
                _ = decode_textures(source, 5, workers)
            except e:
                raised = True
                message = String(e)
            assert_true(raised)
            assert_equal(message, "" if empty else "failure 1")
            assert_equal(counters[0], 0)
            assert_equal(counters[2], 0)
            if workers > 1:
                # Failure can stop unclaimed jobs, but every claimed index
                # belongs to a contiguous prefix and finishes exactly once.
                var claimed: Int64 = 0
                var saw_unclaimed = False
                for index in range(5):
                    if visits[index] == 0:
                        saw_unclaimed = True
                    else:
                        assert_false(saw_unclaimed)
                        assert_equal(visits[index], Int64(1))
                        claimed += 1
                assert_true(claimed >= 2)
                assert_true(claimed <= 5)
                assert_equal(counters[4], claimed)
            else:
                assert_equal(counters[4], Int64(2))
            # Retrying with the same fixed inputs owns fresh queue state.
            source.fail = False
            source.slow = -1
            var retry = decode_textures(source, 5, workers)
            assert_equal(len(retry), 5)
            assert_equal(counters[0], 0)
            assert_equal(counters[2], 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
