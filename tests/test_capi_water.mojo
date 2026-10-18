# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `window.capi_water`, the C ABI on the water extension.

The functions are the ones a C host calls, called here from Mojo with the
same scalars and the same opaque handle. Each failure that the functions
swallow is forced here, so that each is seen to leave the app as it was.
"""

from extensions.water.upload import FRAME_FLOATS
from extensions.water.view import FRAME
from std.math import inf
from std.memory import Layout
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import RADIAN, SECOND, Angle, Duration
from window.capi_abi import (
    ABI_VERSION,
    GPU_CAUSTIC,
    GPU_CAUSTIC_TABLE,
    GPU_GRID,
    GPU_INFO_GRID_HEIGHT,
    GPU_INFO_GRID_WIDTH,
    GPU_INFO_RIPPLE_SIDE,
    GPU_PEBBLE,
    GPU_PEBBLE_TABLE,
    GPU_RIPPLE,
    GPU_SAMPLES,
    GPU_SURFACE,
    GPU_SURFACE_TABLE,
    GPU_VALUES,
    GpuInfo,
    GpuPart,
    KEY_DOWN,
    KEY_SPACE,
    KEY_UP,
    MAX_SIDE,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    WHEEL,
)
from window.capi_water import (
    MAX_ASSET,
    tm_abi_version,
    tm_alloc,
    tm_asset,
    tm_create,
    tm_destroy,
    tm_event,
    tm_frame,
    tm_free,
    tm_gpu_glare,
    tm_gpu_info,
    tm_gpu_part,
    tm_gpu_prepare,
    tm_gpu_words,
    tm_height,
    tm_init,
    tm_step,
    tm_width,
)
from window.water_app import (
    BED,
    HIGHEST_PITCH,
    LONGEST_MICROSECONDS,
    LOWEST_PITCH,
    START_PITCH,
    STEP_MICROSECONDS,
    WaterApp,
)

comptime Handle = OpaquePointer[MutUntrackedOrigin]
comptime WIDTH = 48
comptime HEIGHT = 27
comptime FRAME_BYTES = WIDTH * HEIGHT * 4
comptime UNKNOWN_KIND = 99
comptime KEY_A = 97
comptime NO_FILE = "assets/no-such-photograph.jpg"


def _make() raises -> Handle:
    """Make an app, which the test needs to succeed."""
    var created = tm_create(Int32(WIDTH), Int32(HEIGHT))
    assert_true(Bool(created))
    return Handle(unsafe_from_address=Int(created.value()))


def _plain() raises -> Handle:
    """Make an app whose photograph could not be read, as in a browser."""
    var app = WaterApp(WIDTH, HEIGHT, NO_FILE)
    var slot = alloc(Layout[WaterApp](count=1)).unsafe_leak()
    slot.unsafe_write(app^)
    return Handle(unsafe_from_address=Int(slot))


def _room(file: List[UInt8]) raises -> Pointer[UInt8, MutUntrackedOrigin]:
    """Put bytes in room from `tm_alloc`, as a host does."""
    var room = tm_alloc(Int32(len(file)))
    assert_true(Bool(room))
    var bytes = room.value()
    for index in range(len(file)):
        bytes.unsafe_offset(index).unsafe_write(file[index])
    return bytes


def _state(app: Handle) -> Pointer[WaterApp, MutUntrackedOrigin]:
    """View a handle as the app, to read or break it on purpose."""
    return app.unsafe_bitcast[WaterApp]()


def _hash(app: Handle) -> UInt64:
    """Draw the app, and return the 64-bit FNV-1a hash of the frame."""
    var bytes = tm_frame(app)
    var hash = UInt64(14695981039346656037)
    for index in range(FRAME_BYTES):
        var byte = UInt64(bytes.unsafe_offset(index).unsafe_load())
        hash = (hash ^ byte) * UInt64(1099511628211)
    return hash


def _step(app: Handle, steps: Int):
    """Run whole ripple steps."""
    for _ in range(steps):
        tm_step(app, Int32(STEP_MICROSECONDS))


def _move(app: Handle, y: Int):
    """Move the pointer to a row."""
    tm_event(app, Int32(POINTER_MOVE), Int32(10), Int32(y), Int32(0))


def test_the_abi_version_is_the_cores() raises:
    assert_equal(tm_abi_version(), Int32(ABI_VERSION))


def test_init_may_be_called_where_the_runtime_runs() raises:
    tm_init()
    var app = _make()
    assert_equal(tm_width(app), Int32(WIDTH))
    tm_destroy(app)


def test_a_side_that_is_not_positive_makes_no_app() raises:
    assert_false(Bool(tm_create(Int32(0), Int32(10))))
    assert_false(Bool(tm_create(Int32(10), Int32(0))))
    assert_false(Bool(tm_create(Int32(-1), Int32(10))))


def test_a_side_that_is_too_large_makes_no_app() raises:
    assert_false(Bool(tm_create(Int32(MAX_SIDE + 1), Int32(10))))
    assert_false(Bool(tm_create(Int32(10), Int32(MAX_SIDE + 1))))


def test_an_app_has_its_size_and_an_opaque_picture() raises:
    var app = _make()
    assert_equal(tm_width(app), Int32(WIDTH))
    assert_equal(tm_height(app), Int32(HEIGHT))
    var bytes = tm_frame(app)
    var brightest = 0
    var darkest = 255
    for pixel in range(WIDTH * HEIGHT):
        var green = Int(bytes.unsafe_offset(pixel * 4 + 1).unsafe_load())
        brightest = max(brightest, green)
        darkest = min(darkest, green)
        assert_equal(
            bytes.unsafe_offset(pixel * 4 + 3).unsafe_load(), UInt8(255)
        )
    # Water, sky and glint are not one color.
    assert_true(brightest > darkest + 20)
    tm_destroy(app)


def test_the_same_steps_draw_the_same_picture() raises:
    var first = _make()
    var second = _make()
    _step(first, 3)
    _step(second, 3)
    assert_equal(_hash(first), _hash(second))
    tm_destroy(first)
    tm_destroy(second)


def test_a_step_moves_the_ripples_and_the_clock() raises:
    var app = _make()
    var before = _hash(app)
    _step(app, 1)
    assert_equal(_state(app)[].water.steps, 1)
    assert_true(before != _hash(app))
    tm_destroy(app)


def test_time_is_gathered_into_whole_ripple_steps() raises:
    var app = _make()
    # Three quarters of a step runs nothing. The fourth quarter runs one.
    var part = Int32(STEP_MICROSECONDS // 4 + 1)
    tm_step(app, part)
    tm_step(app, part)
    tm_step(app, part)
    assert_equal(_state(app)[].water.steps, 0)
    tm_step(app, part)
    assert_equal(_state(app)[].water.steps, 1)
    tm_destroy(app)


def test_one_long_step_runs_the_steps_it_holds() raises:
    var app = _make()
    tm_step(app, Int32(2 * STEP_MICROSECONDS))
    assert_equal(_state(app)[].water.steps, 2)
    tm_destroy(app)


def test_a_very_long_step_counts_only_a_tenth_of_a_second() raises:
    var app = _make()
    tm_step(app, Int32.MAX)
    assert_equal(
        _state(app)[].water.steps, LONGEST_MICROSECONDS // STEP_MICROSECONDS
    )
    tm_destroy(app)


def test_negative_time_is_ignored() raises:
    var app = _make()
    tm_step(app, Int32(-1))
    assert_equal(_state(app)[].water.steps, 0)
    assert_equal(_state(app)[].owed, 0)
    tm_destroy(app)


def test_the_space_bar_pauses_and_resumes() raises:
    var app = _make()
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    _step(app, 3)
    assert_equal(_state(app)[].water.steps, 0)
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    _step(app, 3)
    assert_equal(_state(app)[].water.steps, 3)
    tm_destroy(app)


def test_other_keys_do_not_pause() raises:
    var app = _make()
    tm_event(app, Int32(KEY_UP), Int32(0), Int32(0), Int32(KEY_SPACE))
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_A))
    _step(app, 2)
    assert_equal(_state(app)[].water.steps, 2)
    tm_destroy(app)


def test_a_press_taps_the_water_once() raises:
    var plain = _make()
    var tapped = _make()
    tm_event(tapped, Int32(POINTER_DOWN), Int32(5), Int32(5), Int32(0))
    assert_true(_state(tapped)[].tap)
    _step(plain, 8)
    _step(tapped, 8)
    assert_false(_state(tapped)[].tap)
    assert_true(_hash(plain) != _hash(tapped))
    tm_destroy(plain)
    tm_destroy(tapped)


def test_a_drag_tilts_the_camera() raises:
    var app = _make()
    assert_equal(_state(app)[].pitch, START_PITCH)
    tm_event(app, Int32(POINTER_DOWN), Int32(10), Int32(10), Int32(0))
    _move(app, 20)
    assert_almost_equal(_state(app)[].pitch, Float32(-0.68), atol=1e-5)
    _move(app, 15)
    assert_almost_equal(_state(app)[].pitch, Float32(-0.70), atol=1e-5)
    tm_destroy(app)


def test_the_tilt_stops_at_both_ends() raises:
    var app = _make()
    tm_event(app, Int32(POINTER_DOWN), Int32(10), Int32(0), Int32(0))
    _move(app, 4000)
    assert_equal(_state(app)[].pitch, HIGHEST_PITCH)
    _move(app, -4000)
    assert_equal(_state(app)[].pitch, LOWEST_PITCH)
    tm_destroy(app)


def test_a_move_without_a_button_does_not_tilt() raises:
    var app = _make()
    _move(app, 20)
    assert_equal(_state(app)[].pitch, START_PITCH)
    tm_event(app, Int32(POINTER_DOWN), Int32(10), Int32(10), Int32(0))
    tm_event(app, Int32(POINTER_UP), Int32(10), Int32(10), Int32(0))
    _move(app, 30)
    assert_equal(_state(app)[].pitch, START_PITCH)
    tm_destroy(app)


def test_a_tilted_camera_draws_another_picture() raises:
    var plain = _make()
    var tilted = _make()
    tm_event(tilted, Int32(POINTER_DOWN), Int32(10), Int32(0), Int32(0))
    _move(tilted, 60)
    assert_true(_hash(plain) != _hash(tilted))
    tm_destroy(plain)
    tm_destroy(tilted)


def test_events_of_other_kinds_are_dropped() raises:
    var app = _make()
    tm_event(app, Int32(WHEEL), Int32(5), Int32(5), Int32(1))
    tm_event(app, Int32(UNKNOWN_KIND), Int32(5), Int32(5), Int32(0))
    assert_false(_state(app)[].tap)
    assert_false(_state(app)[].dragging)
    assert_false(_state(app)[].paused)
    assert_equal(_state(app)[].pitch, START_PITCH)
    tm_destroy(app)


def test_a_step_that_the_water_refuses_does_nothing() raises:
    var app = _make()
    # A clock that is not finite: the water refuses to move it on.
    _state(app)[].water.clock = Duration(inf[DType.float32](), SECOND)
    _state(app)[].tap = True
    _step(app, 3)
    assert_equal(_state(app)[].water.steps, 0)
    assert_true(_state(app)[].tap)
    tm_destroy(app)


def test_a_frame_that_cannot_be_drawn_is_the_last_one() raises:
    var app = _make()
    var before = _hash(app)
    # A frame of no width: the water refuses to draw it.
    _state(app)[].width = 0
    assert_equal(before, _hash(app))
    tm_destroy(app)


def test_the_photograph_is_the_bed_when_it_can_be_read() raises:
    var app = _make()
    assert_true(_state(app)[].bed.width > 1)
    tm_destroy(app)


def test_plain_sand_takes_the_place_of_a_photograph_that_is_missing() raises:
    var app = WaterApp(WIDTH, HEIGHT, NO_FILE)
    assert_equal(app.bed.width, 1)
    assert_equal(app.bed.height, 1)
    # The water still draws over it.
    var picture = app.water.draw(
        WIDTH, HEIGHT, FRAME, True, app.bed, Angle(app.pitch, RADIAN)
    )
    assert_equal(picture.width, WIDTH)


def test_room_is_refused_when_its_size_is_out_of_range() raises:
    assert_false(Bool(tm_alloc(Int32(0))))
    assert_false(Bool(tm_alloc(Int32(-1))))
    assert_false(Bool(tm_alloc(Int32(MAX_ASSET + 1))))


def test_room_holds_what_is_written_to_it() raises:
    var room = tm_alloc(Int32(16))
    assert_true(Bool(room))
    var bytes = room.value()
    bytes.unsafe_offset(15).unsafe_write(UInt8(7))
    assert_equal(bytes.unsafe_offset(15).unsafe_load(), UInt8(7))
    tm_free(bytes)


def test_a_host_gives_the_app_its_photograph() raises:
    var app = _plain()
    assert_equal(_state(app)[].bed.width, 1)
    var file = Path(BED).read_bytes()
    var room = _room(file)
    assert_equal(tm_asset(app, room, Int32(len(file))), Int32(0))
    tm_free(room)
    assert_true(_state(app)[].bed.width > 1)
    tm_destroy(app)


def test_bytes_that_are_not_a_photograph_leave_the_bed_alone() raises:
    var app = _plain()
    var nothing = List[UInt8](length=16, fill=0)
    var room = _room(nothing)
    assert_equal(tm_asset(app, room, Int32(16)), Int32(1))
    tm_free(room)
    assert_equal(_state(app)[].bed.width, 1)
    tm_destroy(app)


def test_an_asset_with_no_length_is_refused() raises:
    var app = _plain()
    var room = _room(List[UInt8](length=4, fill=0))
    assert_equal(tm_asset(app, room, Int32(0)), Int32(1))
    assert_equal(tm_asset(app, room, Int32(-4)), Int32(1))
    tm_free(room)
    assert_equal(_state(app)[].bed.width, 1)
    tm_destroy(app)


def _floats(
    app: Handle, which: Int
) raises -> Pointer[Float32, MutUntrackedOrigin]:
    """The address of a prepared part, as floats, which the test needs."""
    var part = tm_gpu_part(app, Int32(which))
    assert_true(Bool(part))
    return Pointer[Float32, MutUntrackedOrigin](
        unsafe_from_address=Int(part.value())
    )


def _table(
    app: Handle, which: Int
) raises -> Pointer[Int64, MutUntrackedOrigin]:
    """The address of a prepared table, as 64-bit integers."""
    var part = tm_gpu_part(app, Int32(which))
    assert_true(Bool(part))
    return Pointer[Int64, MutUntrackedOrigin](
        unsafe_from_address=Int(part.value())
    )


def _words(app: Handle, which: Int) -> Int:
    return Int(tm_gpu_words(app, Int32(which)))


def test_nothing_is_prepared_before_the_first_prepare() raises:
    var app = _make()
    for which in range(GPU_GRID.value + 1):
        assert_false(Bool(tm_gpu_part(app, Int32(which))))
        assert_equal(_words(app, which), 0)
    assert_equal(tm_gpu_info(app, Int32(GPU_INFO_RIPPLE_SIDE.value)), Int32(0))
    assert_equal(tm_gpu_info(app, Int32(GPU_INFO_GRID_WIDTH.value)), Int32(0))
    assert_equal(tm_gpu_info(app, Int32(GPU_INFO_GRID_HEIGHT.value)), Int32(0))
    # The glare has no kernels and no glints yet.
    assert_equal(tm_gpu_glare(app), Int32(1))
    tm_destroy(app)


def test_prepare_makes_the_arrays_that_the_shader_reads() raises:
    var app = _make()
    _step(app, 3)
    assert_equal(tm_gpu_prepare(app), Int32(1))
    for which in range(GPU_VALUES.value + 1):
        assert_true(Bool(tm_gpu_part(app, Int32(which))))
        assert_true(_words(app, which) > 0)
    # The frame values are the camera, the sun, the clock and the placement.
    assert_equal(_words(app, GPU_VALUES.value), FRAME_FLOATS)
    var values = _floats(app, GPU_VALUES.value)
    assert_equal(values[unsafe_offset=15], _state(app)[].water.clock.value)
    assert_equal(values[unsafe_offset=12], _state(app)[].water.sun.x)
    # A table holds the level count, then a side and an offset for each level
    # and the base. The last level ends at the end of its array.
    var surface = _table(app, GPU_SURFACE_TABLE.value)
    var levels = Int(surface[unsafe_offset=0])
    assert_true(levels > 0)
    assert_equal(
        _words(app, GPU_SURFACE_TABLE.value), 2 * (1 + 2 * (levels + 1))
    )
    var side = Int(surface[unsafe_offset=1 + 2 * levels])
    var offset = Int(surface[unsafe_offset=2 + 2 * levels])
    assert_equal(_words(app, GPU_SURFACE.value), offset + side * side * 4)
    var caustic = _table(app, GPU_CAUSTIC_TABLE.value)
    var caustic_levels = Int(caustic[unsafe_offset=0])
    var caustic_side = Int(caustic[unsafe_offset=1 + 2 * caustic_levels])
    var caustic_offset = Int(caustic[unsafe_offset=2 + 2 * caustic_levels])
    assert_equal(
        _words(app, GPU_CAUSTIC.value), caustic_offset + caustic_side**2 * 3
    )
    # The photograph's table has three entries a level.
    var pebble = _table(app, GPU_PEBBLE_TABLE.value)
    var pebble_levels = Int(pebble[unsafe_offset=0])
    assert_equal(
        _words(app, GPU_PEBBLE_TABLE.value), 2 * (1 + 3 * (pebble_levels + 1))
    )
    var ripple_side = Int(tm_gpu_info(app, Int32(GPU_INFO_RIPPLE_SIDE.value)))
    assert_equal(_words(app, GPU_RIPPLE.value), ripple_side * ripple_side * 4)
    tm_destroy(app)


def test_the_prepared_surface_is_the_surface_the_frame_draws() raises:
    var app = _make()
    _step(app, 2)
    assert_equal(tm_gpu_prepare(app), Int32(1))
    var texels = _floats(app, GPU_SURFACE.value)
    var surface = _state(app)[].water._surface()
    assert_equal(texels[unsafe_offset=0], surface.field.samples[0])
    assert_equal(
        texels[unsafe_offset=_words(app, GPU_SURFACE.value) - 1],
        surface.mips[len(surface.mips) - 1].samples[
            len(surface.mips[len(surface.mips) - 1].samples) - 1
        ],
    )
    tm_destroy(app)


def test_the_photograph_is_packed_again_only_when_it_changes() raises:
    var app = _plain()
    assert_equal(tm_gpu_prepare(app), Int32(1))
    assert_equal(_words(app, GPU_PEBBLE.value), 3)
    assert_equal(tm_gpu_prepare(app), Int32(1))
    var file = Path(BED).read_bytes()
    var room = _room(file)
    assert_equal(tm_asset(app, room, Int32(len(file))), Int32(0))
    tm_free(room)
    assert_equal(tm_gpu_prepare(app), Int32(2))
    assert_true(_words(app, GPU_PEBBLE.value) > 3)
    assert_equal(tm_gpu_prepare(app), Int32(2))
    tm_destroy(app)


def test_the_glare_grid_is_sized_and_takes_the_glints() raises:
    var app = _make()
    assert_equal(tm_gpu_prepare(app), Int32(1))
    var width = Int(tm_gpu_info(app, Int32(GPU_INFO_GRID_WIDTH.value)))
    var height = Int(tm_gpu_info(app, Int32(GPU_INFO_GRID_HEIGHT.value)))
    assert_true(width > 0 and height > 0)
    assert_equal(_words(app, GPU_SAMPLES.value), width * height * 3)
    # The glare has not run: its part is empty.
    assert_false(Bool(tm_gpu_part(app, Int32(GPU_GRID.value))))
    # One bright glint in the middle spreads over the grid.
    var samples = _floats(app, GPU_SAMPLES.value)
    var middle = ((height // 2) * width + width // 2) * 3
    samples[unsafe_offset=middle] = 1.0e-3
    samples[unsafe_offset=middle + 1] = 1.0e-3
    samples[unsafe_offset=middle + 2] = 1.0e-3
    assert_equal(tm_gpu_glare(app), Int32(0))
    assert_equal(_words(app, GPU_GRID.value), width * height * 3)
    var grid = _floats(app, GPU_GRID.value)
    var total = Float32(0)
    for index in range(width * height * 3):
        total += grid[unsafe_offset=index]
    assert_true(total > 0)
    # A second frame of the same size keeps the same room for the glints.
    assert_equal(tm_gpu_prepare(app), Int32(1))
    assert_equal(
        Int(tm_gpu_part(app, Int32(GPU_SAMPLES.value)).value()), Int(samples)
    )
    tm_destroy(app)


def test_a_part_that_does_not_exist_is_refused() raises:
    var app = _make()
    assert_equal(tm_gpu_prepare(app), Int32(1))
    # One past each end, and far outside.
    for which in [-1, GPU_GRID.value + 1, 99]:
        assert_false(Bool(tm_gpu_part(app, Int32(which))))
        assert_equal(_words(app, which), 0)
    for which in [-1, GPU_INFO_GRID_HEIGHT.value + 1, 99]:
        assert_equal(tm_gpu_info(app, Int32(which)), Int32(0))
    tm_destroy(app)


def test_a_part_and_an_info_are_valid_in_their_ranges_only() raises:
    assert_false(GpuPart(-1).is_valid())
    assert_true(GpuPart(GPU_SURFACE.value).is_valid())
    assert_true(GpuPart(GPU_GRID.value).is_valid())
    assert_false(GpuPart(GPU_GRID.value + 1).is_valid())
    assert_false(GpuInfo(-1).is_valid())
    assert_true(GpuInfo(GPU_INFO_RIPPLE_SIDE.value).is_valid())
    assert_true(GpuInfo(GPU_INFO_GRID_HEIGHT.value).is_valid())
    assert_false(GpuInfo(GPU_INFO_GRID_HEIGHT.value + 1).is_valid())


def test_the_parts_are_numbered_as_the_header_numbers_them() raises:
    # window/threemojo.h lists these numbers for a host that is not in Mojo.
    var parts = [
        GPU_SURFACE,
        GPU_SURFACE_TABLE,
        GPU_RIPPLE,
        GPU_CAUSTIC,
        GPU_CAUSTIC_TABLE,
        GPU_PEBBLE,
        GPU_PEBBLE_TABLE,
        GPU_VALUES,
        GPU_SAMPLES,
        GPU_GRID,
    ]
    for number in range(len(parts)):
        assert_equal(parts[number].value, number)
    assert_equal(GPU_INFO_RIPPLE_SIDE.value, 0)
    assert_equal(GPU_INFO_GRID_WIDTH.value, 1)
    assert_equal(GPU_INFO_GRID_HEIGHT.value, 2)


def test_a_frame_that_cannot_be_prepared_leaves_the_last_arrays() raises:
    var app = _make()
    assert_equal(tm_gpu_prepare(app), Int32(1))
    var before = _words(app, GPU_SURFACE.value)
    var address = Int(tm_gpu_part(app, Int32(GPU_SURFACE.value)).value())
    # A caustic grid of no cells: the water refuses to make its caustics.
    _state(app)[].water.caustic_grid = 0
    assert_equal(tm_gpu_prepare(app), Int32(-1))
    assert_equal(_words(app, GPU_SURFACE.value), before)
    assert_equal(
        Int(tm_gpu_part(app, Int32(GPU_SURFACE.value)).value()), address
    )
    tm_destroy(app)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
