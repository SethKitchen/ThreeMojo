# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `window.capi_water_gpu`, the C ABI on the water shaded on a GPU.

The device fuses multiplies and adds where the host does not, so a GPU frame
is close to the CPU frame and not equal to it. The tests compare the mean
difference of the 8-bit channels. Each test that opens a device skips, and
says so, on a machine without a GPU.
"""

from std.sys import has_accelerator
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from window.capi_abi import ABI_VERSION, MAX_SIDE
from window.capi_water_gpu import (
    GpuWaterApp,
    tm_abi_version,
    tm_create,
    tm_destroy,
    tm_event,
    tm_frame,
    tm_height,
    tm_init,
    tm_step,
    tm_width,
)
from window.water_app import BED, STEP_MICROSECONDS

comptime Handle = OpaquePointer[MutUntrackedOrigin]
comptime WIDTH = 48
comptime HEIGHT = 27
comptime FRAME_BYTES = WIDTH * HEIGHT * 4
comptime KEY_DOWN = 0
comptime KEY_SPACE = 32


def _skipped(name: String) -> Bool:
    # An early return looks like a pass, so a skip says so.
    if has_accelerator():
        return False
    print("SKIP (no GPU):", name)
    return True


def _make() raises -> Handle:
    """Make an app, which the test needs to succeed."""
    var created = tm_create(Int32(WIDTH), Int32(HEIGHT))
    assert_true(Bool(created))
    return Handle(unsafe_from_address=Int(created.value()))


def _state(app: Handle) -> Pointer[GpuWaterApp, MutUntrackedOrigin]:
    """View a handle as the app, to read or break it on purpose."""
    return app.unsafe_bitcast[GpuWaterApp]()


def _copy(app: Handle) -> List[UInt8]:
    """Draw the app, and copy the frame out."""
    var bytes = tm_frame(app)
    var copy = List[UInt8](capacity=FRAME_BYTES)
    for index in range(FRAME_BYTES):
        copy.append(bytes.unsafe_offset(index).unsafe_load())
    return copy^


def _mean_difference(a: List[UInt8], b: List[UInt8]) -> Float64:
    """The mean absolute difference of two frames' bytes."""
    var total = 0
    for index in range(len(a)):
        total += abs(Int(a[index]) - Int(b[index]))
    return Float64(total) / Float64(len(a))


def test_the_abi_version_is_the_cores() raises:
    assert_equal(tm_abi_version(), Int32(ABI_VERSION))


def test_a_side_out_of_range_makes_no_app() raises:
    assert_false(Bool(tm_create(Int32(0), Int32(10))))
    assert_false(Bool(tm_create(Int32(-1), Int32(10))))
    assert_false(Bool(tm_create(Int32(MAX_SIDE + 1), Int32(10))))
    assert_false(Bool(tm_create(Int32(10), Int32(MAX_SIDE + 1))))


def test_a_machine_without_a_gpu_makes_no_app() raises:
    if has_accelerator():
        return
    print("A machine without a GPU: tm_create returns NULL")
    assert_false(Bool(tm_create(Int32(WIDTH), Int32(HEIGHT))))


def test_an_app_has_its_size_and_an_opaque_picture() raises:
    if _skipped("an app has its size and an opaque picture"):
        return
    tm_init()
    var app = _make()
    assert_equal(tm_width(app), Int32(WIDTH))
    assert_equal(tm_height(app), Int32(HEIGHT))
    var frame = _copy(app)
    var brightest = 0
    for pixel in range(WIDTH * HEIGHT):
        brightest = max(brightest, Int(frame[pixel * 4 + 1]))
        assert_equal(frame[pixel * 4 + 3], UInt8(255))
    assert_true(brightest > 100)
    tm_destroy(app)


def test_the_picture_is_close_to_the_cpu_picture() raises:
    if _skipped("the picture is close to the cpu picture"):
        return
    var app = _make()
    tm_step(app, Int32(STEP_MICROSECONDS))
    var gpu = _copy(app)
    # The same water, drawn by the CPU.
    _state(app)[].app.draw()
    var cpu = _state(app)[].app.frame.pixels.copy()
    assert_equal(len(cpu), FRAME_BYTES)
    assert_true(_mean_difference(gpu, cpu) < 2.0)
    tm_destroy(app)


def test_the_same_steps_draw_the_same_picture() raises:
    if _skipped("the same steps draw the same picture"):
        return
    var first = _make()
    var second = _make()
    tm_step(first, Int32(2 * STEP_MICROSECONDS))
    tm_step(second, Int32(2 * STEP_MICROSECONDS))
    assert_equal(_mean_difference(_copy(first), _copy(second)), 0.0)
    tm_destroy(first)
    tm_destroy(second)


def test_events_and_steps_move_the_water() raises:
    if _skipped("events and steps move the water"):
        return
    var app = _make()
    var before = _copy(app)
    tm_step(app, Int32(STEP_MICROSECONDS))
    assert_equal(_state(app)[].app.water.steps, 1)
    assert_true(_mean_difference(before, _copy(app)) > 0.0)
    # The space bar pauses it.
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    tm_step(app, Int32(STEP_MICROSECONDS))
    assert_equal(_state(app)[].app.water.steps, 1)
    tm_destroy(app)


def test_a_frame_that_cannot_be_drawn_is_the_last_one() raises:
    if _skipped("a frame that cannot be drawn is the last one"):
        return
    var app = _make()
    var before = _copy(app)
    # A frame of no width: the water refuses to draw it.
    _state(app)[].app.width = 0
    assert_equal(_mean_difference(before, _copy(app)), 0.0)
    tm_destroy(app)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
