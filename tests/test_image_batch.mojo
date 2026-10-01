# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Shared bounded result storage for CARLA and glTF image decoding."""

from loaders.image_batch import TextureDecodeBatch, decode_batch_size
from render.texture import Texture
from render.tasks import TaskGroup
from std.atomic import Atomic
from std.time import perf_counter_ns
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def test_empty_and_bounded_batches() raises:
    assert_equal(decode_batch_size(-1, 3), 0)
    for remaining in [-1, 0, 1, 3, 8]:
        for workers in [-2, 0, 1, 2, 4]:
            var batch = TextureDecodeBatch(remaining, workers)
            var expected = min(max(0, remaining), max(1, workers))
            assert_equal(len(batch.textures), expected)
            assert_equal(len(batch.errors), expected)
            batch.check()


def test_errors_keep_the_first_source_error() raises:
    var batch = TextureDecodeBatch(3, 3)
    batch.errors[1] = "second source failed"
    batch.errors[2] = "third source failed"
    with assert_raises(contains="second source failed"):
        batch.check()
    # Error checking does not consume any successful or failed slot.
    assert_equal(len(batch.textures), 3)
    batch.errors[1] = ""
    with assert_raises(contains="third source failed"):
        batch.check()


def test_results_move_with_their_mip_buffers() raises:
    var pixels: List[UInt8] = [
        20,
        40,
        60,
        255,
        20,
        40,
        60,
        255,
        20,
        40,
        60,
        255,
        20,
        40,
        60,
        255,
    ]
    var batch = TextureDecodeBatch(1, 2)
    batch.textures[0] = Texture(2, 2, pixels^)
    var address = (
        batch.textures[0].pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    )
    batch.check()
    var texture = batch.textures.pop()
    assert_equal(texture.levels, 2)
    assert_equal(len(texture.pixels), 20)
    assert_equal(
        texture.pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
        address,
    )
    assert_equal(len(batch.textures), 0)


async def _tracked_task(
    counters: MutPointer[Int32, MutAnyOrigin],
    errors: MutPointer[String, MutAnyOrigin],
    index: Int,
):
    var active = Atomic[Int32].fetch_add(counters, 1) + 1
    var peak = counters.unsafe_offset(1)
    var expected = Atomic[Int32].fetch_add(peak, 0)
    while active > expected:
        if Atomic[Int32].compare_exchange(peak, expected, active):
            break
    # Give overlapping tasks time to start without requiring a minimum
    # thread-pool size on the test machine.
    var until = perf_counter_ns() + 100_000
    while perf_counter_ns() < until:
        pass
    errors[unsafe_offset=index] = ""
    _ = Atomic[Int32].fetch_add(counters, -1)


def test_instrumented_tasks_obey_the_shared_batch_bound() raises:
    for workers in [1, 2, 8]:
        var counters: List[Int32] = [0, 0]
        var remaining = 5
        while remaining > 0:
            var batch = TextureDecodeBatch(remaining, workers)
            var count = len(batch.textures)
            var group = TaskGroup()
            for index in range(count):
                group.create_task(
                    _tracked_task(
                        counters.unsafe_ptr().unsafe_origin_cast[
                            MutAnyOrigin
                        ](),
                        batch.errors.unsafe_ptr().unsafe_origin_cast[
                            MutAnyOrigin
                        ](),
                        index,
                    )
                )
            group.wait()
            batch.check()
            assert_equal(counters[0], Int32(0))
            assert_true(counters[1] >= 1)
            assert_true(Int(counters[1]) <= min(workers, 5))
            remaining -= count


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
