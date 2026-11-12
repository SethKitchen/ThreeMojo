# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `window.capi_village` and `window.village_app`, the C ABI on the
village game.

The functions are the ones a C host calls, called here from Mojo with the
same scalars and the same opaque handle. The real village takes seconds to
build, so the apps here hold the tiny village of `tests/_village_tiny.mojo`.
`tm_create` is called only with arguments that it refuses: it builds the
default village, and the app's own construction is tested through
`new_app`. Each failure that the functions swallow is forced here, so that
each is seen to leave the app as it was.
"""

from _village_tiny import gray_photograph, tiny_game
from controls.input import KEY_W
from core.object3d import NodeId
from extensions.village.character import AIRBORNE, STANDING
from extensions.village.pad_input import KEY_SPACE as SPACE_KEY
from extensions.village.quality import (
    HIGH,
    LOW,
    MEDIUM,
    QualityPreset,
    ULTRA,
    game_quality,
)
from extensions.village.weather import (
    CLEAR,
    FOG,
    OVERCAST,
    RAIN,
    SNOW,
    WeatherKind,
)
from extensions.water.pebbles import pebble_bed
from extensions.water.upload import (
    COMPOSE_WORDS,
    WORD_GRID_HEIGHT,
    WORD_GRID_WIDTH,
    WORD_HEIGHT,
    WORD_STEP,
    WORD_WIDTH,
    grid_samples,
)
from lights.light import spot_light
from render.framebuffer import Color
from renderers.game_gpu import (
    FLOAT_COVER_BRIGHT,
    FLOAT_EXPOSURE,
    FLOAT_NIGHT_DAY,
    FLOAT_WATER_SHARE,
    INT_COVER_COLUMNS,
    INT_COVER_ROWS,
    INT_COVER_STEP,
    INT_DEPTH,
    INT_HEIGHT,
    INT_NIGHT_ON,
    INT_PASSES,
    INT_SMOOTH_ON,
    INT_TRIANGLES,
    INT_VERTICES,
    INT_WATER_BED_MADE,
    INT_WATER_GRID_HEIGHT,
    INT_WATER_GRID_WIDTH,
    INT_WATER_ON,
    INT_WATER_RIPPLE_MADE,
    INT_WATER_STEP,
    INT_WATER_SURFACE_MADE,
    INT_WATER_WORDS,
    INT_WIDTH,
    POINTER_COLOR,
    POINTER_CORNERS,
    POINTER_COVER,
    POINTER_DEPTH,
    POINTER_VERTICES,
    POINTER_WATER_CAUSTIC,
    POINTER_WATER_PEBBLE,
    POINTER_WATER_RIPPLE,
    POINTER_WATER_SURFACE,
    POINTER_WATER_WORDS,
)
from std.math import inf
from std.os import getenv, remove, setenv, unsetenv
from std.pathlib import Path
from std.memory import Layout
from extensions.village.gathering import HERBS
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, RADIAN, SECOND, Angle, Duration
from window.capi_abi import (
    ABI_VERSION,
    KEY_DOWN,
    KEY_SHIFT,
    KEY_SPACE,
    KEY_UP,
    MAX_SIDE,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    WHEEL,
)
from window.capi_village import (
    tm_abi_version,
    tm_create,
    tm_destroy,
    tm_event,
    tm_frame,
    tm_height,
    tm_init,
    tm_step,
    tm_village_finish,
    tm_village_floats,
    tm_village_audio,
    tm_village_ints,
    tm_village_passes,
    tm_village_pointers,
    tm_village_prepare,
    tm_width,
)
from window.village_app import (
    DAY_RATE,
    DEFAULT_QUALITY,
    GPU_VARIABLE,
    HOUR_VARIABLE,
    LONGEST_MICROSECONDS,
    QUALITY_VARIABLE,
    START_HOUR,
    VillageApp,
    WEATHER_VARIABLE,
    gpu_from_environment,
    hour_from_environment,
    new_app,
    play_parameters,
    quality_from_environment,
    quality_named,
    read_bed,
    weather_from_environment,
    weather_named,
)

comptime Handle = OpaquePointer[MutUntrackedOrigin]
comptime WIDTH = 48
comptime HEIGHT = 27
comptime FRAME_BYTES = WIDTH * HEIGHT * 4
comptime TICK = 16667
comptime KEY_ONE = 49
comptime NOT_A_KEY = 9999
comptime UNKNOWN_KIND = 99


def _make() raises -> Handle:
    """Make an app of the tiny village, which the test needs to succeed."""
    var app = new_app(WIDTH, HEIGHT, tiny_game(), pebble_bed(gray_photograph()))
    return Handle(unsafe_from_address=Int(app))


def _state(app: Handle) -> Pointer[VillageApp, MutUntrackedOrigin]:
    """View a handle as the app, to look into it and to break it on purpose."""
    return app.unsafe_bitcast[VillageApp]()


def _hash(app: Handle) -> UInt64:
    """Draw the app, and return the 64-bit FNV-1a hash of the frame."""
    var bytes = tm_frame(app)
    var hash = UInt64(14695981039346656037)
    for index in range(FRAME_BYTES):
        var byte = UInt64(bytes.unsafe_offset(index).unsafe_load())
        hash = (hash ^ byte) * UInt64(1099511628211)
    return hash


def _step(app: Handle, ticks: Int):
    """Step an app by whole sixtieths of a second."""
    for _ in range(ticks):
        tm_step(app, Int32(TICK))


def _press(app: Handle, code: Int):
    """Press a key."""
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(code))


def _release(app: Handle, code: Int):
    """Let a key go."""
    tm_event(app, Int32(KEY_UP), Int32(0), Int32(0), Int32(code))


def _forward(app: Handle) -> Float32:
    """Return how far the player is from the start, along the way they walk."""
    return _state(app)[].game.player.position.z


def test_the_abi_version_is_the_cores() raises:
    assert_equal(tm_abi_version(), Int32(ABI_VERSION))


def test_init_may_be_called_where_the_runtime_runs() raises:
    tm_init()
    var app = _make()
    assert_equal(tm_width(app), Int32(WIDTH))
    tm_destroy(app)


def test_a_side_that_is_not_positive_makes_no_app() raises:
    assert_false(Bool(tm_create(Int32(0), Int32(10))))
    assert_false(Bool(tm_create(Int32(10), Int32(-1))))


def test_a_side_that_is_too_large_makes_no_app() raises:
    assert_false(Bool(tm_create(Int32(MAX_SIDE + 1), Int32(10))))
    assert_false(Bool(tm_create(Int32(10), Int32(MAX_SIDE + 1))))


def test_a_quality_that_is_not_one_makes_no_app() raises:
    _ = setenv(QUALITY_VARIABLE, "best")
    try:
        assert_false(Bool(tm_create(Int32(10), Int32(10))))
    finally:
        _ = unsetenv(QUALITY_VARIABLE)


def test_a_name_gives_a_quality() raises:
    assert_equal(quality_named("low"), LOW)
    assert_equal(quality_named("medium"), MEDIUM)
    assert_equal(quality_named("high"), HIGH)
    assert_equal(quality_named("ultra"), ULTRA)
    with assert_raises(contains="low, medium, high or ultra, not best"):
        _ = quality_named("best")


def test_the_environment_names_the_quality() raises:
    _ = unsetenv(QUALITY_VARIABLE)
    assert_equal(DEFAULT_QUALITY, "medium")
    assert_equal(quality_from_environment(), MEDIUM)
    _ = setenv(QUALITY_VARIABLE, "high")
    try:
        assert_equal(quality_from_environment(), HIGH)
        _ = setenv(QUALITY_VARIABLE, "best")
        with assert_raises(contains="not best"):
            _ = quality_from_environment()
    finally:
        _ = unsetenv(QUALITY_VARIABLE)


def test_the_game_turns_the_weather_and_the_day_as_the_x11_game_does() raises:
    var parameters = play_parameters(LOW)
    assert_true(parameters.weather_cycle)
    assert_equal(parameters.quality.frame_size(1920, 1080)[0], 922)
    assert_almost_equal(parameters.day.hour, Float32(START_HOUR), atol=1e-6)
    assert_almost_equal(parameters.day.hours_a_second, DAY_RATE, atol=1e-9)
    # A day takes twenty minutes.
    assert_almost_equal(24 / parameters.day.hours_a_second, 1200, atol=0.01)
    with assert_raises():
        _ = play_parameters(QualityPreset(9))


def test_a_bed_is_the_photograph_or_sand() raises:
    var photograph = read_bed()
    assert_true(photograph.width > 1)
    var sand = read_bed("assets/no such photograph.jpg")
    assert_equal(sand.width, 1)
    assert_equal(sand.height, 1)
    assert_almost_equal(sand.pixels[0], 0.34, atol=1e-6)


def test_a_window_must_have_positive_sides() raises:
    with assert_raises(contains="positive sides, got 0 by 5"):
        _ = new_app(0, 5, tiny_game(), pebble_bed(gray_photograph()))
    with assert_raises(contains="positive sides, got 5 by -1"):
        _ = new_app(5, -1, tiny_game(), pebble_bed(gray_photograph()))


def test_an_app_has_its_size_and_a_frame_of_the_village() raises:
    var app = _make()
    assert_equal(tm_width(app), Int32(WIDTH))
    assert_equal(tm_height(app), Int32(HEIGHT))
    var bytes = tm_frame(app)
    var first = bytes.unsafe_offset(0).unsafe_load()
    var differs = False
    for index in range(FRAME_BYTES):
        if bytes.unsafe_offset(index).unsafe_load() != first:
            differs = True
    assert_true(differs)
    tm_destroy(app)


def test_the_same_steps_draw_the_same_frame() raises:
    var one = _make()
    var other = _make()
    _step(one, 5)
    _step(other, 5)
    assert_equal(_hash(one), _hash(other))
    tm_destroy(one)
    tm_destroy(other)


def test_a_key_held_walks_the_player_and_a_key_let_go_stops_them() raises:
    var idle = _make()
    var walker = _make()
    var start = _forward(walker)
    _press(walker, Int(KEY_W.value))
    _step(idle, 60)
    _step(walker, 60)
    assert_true(_forward(walker) < start - 1)
    assert_almost_equal(_forward(idle), start, atol=0.01)
    assert_true(_hash(idle) != _hash(walker))
    _release(walker, Int(KEY_W.value))
    assert_false(_state(walker)[].keys.is_held(KEY_W))
    _step(walker, 20)
    var stopped = _forward(walker)
    _step(walker, 10)
    assert_almost_equal(_forward(walker), stopped, atol=0.01)
    tm_destroy(idle)
    tm_destroy(walker)


def test_shift_runs() raises:
    var walker = _make()
    var runner = _make()
    var start = _forward(walker)
    _press(walker, Int(KEY_W.value))
    _press(runner, Int(KEY_W.value))
    _press(runner, KEY_SHIFT)
    assert_true(_state(runner)[].shift)
    _step(walker, 60)
    _step(runner, 60)
    assert_true(start - _forward(runner) > start - _forward(walker) + 0.5)
    _release(runner, KEY_SHIFT)
    assert_false(_state(runner)[].shift)
    tm_destroy(walker)
    tm_destroy(runner)


def test_the_space_bar_jumps_even_when_a_step_never_sees_it_held() raises:
    var app = _make()
    assert_false(_state(app)[].tapped)
    _press(app, KEY_SPACE)
    assert_true(_state(app)[].tapped)
    _release(app, KEY_SPACE)
    assert_false(_state(app)[].keys.is_held(SPACE_KEY))
    tm_step(app, Int32(TICK))
    assert_true(_state(app)[].game.player.stance == AIRBORNE)
    assert_false(_state(app)[].tapped)
    _step(app, 90)
    assert_true(_state(app)[].game.player.stance == STANDING)
    tm_destroy(app)


def test_the_number_keys_set_the_weather() raises:
    var app = _make()
    for number in range(4):
        _press(app, KEY_ONE + number)
        assert_true(_state(app)[].game.weather.kind == WeatherKind(number))
    tm_destroy(app)


def test_the_time_key_moves_the_day_on_three_hours() raises:
    var app = _make()
    var hour = _state(app)[].game.day.hour
    _press(app, KEY_ONE + 4)
    assert_almost_equal(_state(app)[].game.day.hour, (hour + 3) % 24, atol=1e-6)
    _release(app, KEY_ONE + 4)
    _state(app)[].game.day.hour = 22
    _press(app, KEY_ONE + 4)
    assert_almost_equal(_state(app)[].game.day.hour, 1, atol=1e-6)
    # The keys beside them set nothing.
    _press(app, KEY_ONE + 5)
    _press(app, KEY_ONE - 1)
    assert_almost_equal(_state(app)[].game.day.hour, 1, atol=1e-6)
    tm_destroy(app)


def test_a_key_that_repeats_acts_once() raises:
    var app = _make()
    var hour = _state(app)[].game.day.hour
    _press(app, KEY_ONE + 4)
    _press(app, KEY_ONE + 4)
    _press(app, KEY_ONE + 4)
    assert_almost_equal(_state(app)[].game.day.hour, (hour + 3) % 24, atol=1e-6)
    # The key goes up, and the next press acts again.
    _release(app, KEY_ONE + 4)
    _press(app, KEY_ONE + 4)
    assert_almost_equal(_state(app)[].game.day.hour, (hour + 6) % 24, atol=1e-6)
    # The same holds for the space bar's tap: a step took it, and a repeat
    # does not give another.
    _press(app, KEY_SPACE)
    tm_step(app, Int32(TICK))
    assert_false(_state(app)[].tapped)
    _press(app, KEY_SPACE)
    assert_false(_state(app)[].tapped)
    tm_destroy(app)


def test_a_drag_looks_at_the_next_step_and_a_wheel_is_dropped() raises:
    var app = _make()
    var before = _hash(app)
    tm_event(app, Int32(POINTER_DOWN), Int32(10), Int32(10), Int32(0))
    tm_event(app, Int32(POINTER_MOVE), Int32(20), Int32(10), Int32(0))
    tm_event(app, Int32(POINTER_UP), Int32(20), Int32(10), Int32(0))
    tm_event(app, Int32(WHEEL), Int32(0), Int32(0), Int32(1))
    tm_event(app, Int32(UNKNOWN_KIND), Int32(0), Int32(0), Int32(KEY_SPACE))
    assert_false(_state(app)[].tapped)
    assert_equal(before, _hash(app))
    # The drag turns the camera at the next step.
    var yaw = _state(app)[].game.view.yaw.to(RADIAN)
    tm_event(app, Int32(POINTER_DOWN), Int32(10), Int32(10), Int32(0))
    tm_event(app, Int32(POINTER_MOVE), Int32(60), Int32(10), Int32(0))
    _step(app, 1)
    assert_true(_state(app)[].game.view.yaw.to(RADIAN) != yaw)
    tm_destroy(app)


def test_a_code_that_is_not_a_key_is_dropped() raises:
    var app = _make()
    var before = _hash(app)
    _press(app, NOT_A_KEY)
    _release(app, NOT_A_KEY)
    _press(app, -5)
    assert_equal(before, _hash(app))
    assert_false(_state(app)[].shift)
    with assert_raises(contains="must be a key, got 9999"):
        _state(app)[].handle(KEY_DOWN, NOT_A_KEY)
    tm_destroy(app)


def test_negative_time_is_ignored() raises:
    var app = _make()
    var clock = _state(app)[].game.clock
    tm_step(app, Int32(-1))
    assert_equal(_state(app)[].game.clock, clock)
    tm_destroy(app)


def test_long_time_counts_as_a_tenth_of_a_second() raises:
    var app = _make()
    var clock = _state(app)[].game.clock
    tm_step(app, Int32(LONGEST_MICROSECONDS * 50))
    assert_almost_equal(_state(app)[].game.clock - clock, 0.1, atol=1e-4)
    tm_destroy(app)


def test_a_step_that_the_game_refuses_leaves_the_game_as_it_was() raises:
    var app = _make()
    _press(app, Int(KEY_W.value))
    var clock = _state(app)[].game.clock
    var start = _forward(app)
    # Held keys need a timeout that is positive.
    _state(app)[].keys.timeout = Duration(0.0, SECOND)
    _step(app, 10)
    assert_equal(_state(app)[].game.clock, clock)
    assert_equal(_forward(app), start)
    tm_destroy(app)


def test_a_frame_that_cannot_be_drawn_is_the_last_one() raises:
    var app = _make()
    _press(app, Int(KEY_W.value))
    _step(app, 4)
    var before = _hash(app)
    _step(app, 4)
    # The game draws no spot light.
    _state(app)[].scene.add_light(spot_light(Color(255, 255, 255), NodeId(0)))
    assert_equal(before, _hash(app))
    tm_destroy(app)


def _make_gpu() raises -> Handle:
    """Make an app of the tiny village that a GPU draws: it draws at the
    window's size."""
    var parameters = tiny_game()
    parameters.quality.render_scale = 1
    var app = new_app(
        WIDTH, HEIGHT, parameters, pebble_bed(gray_photograph()), True
    )
    return Handle(unsafe_from_address=Int(app))


def _color_address(app: Handle) -> Int64:
    """Return where a prepared frame's colors go, as an address."""
    return tm_village_pointers(app)[unsafe_offset=POINTER_COLOR]


def _paint(app: Handle, gray: UInt8):
    """Do what a host's GPU does: write a flat color, and the depth of the
    sky, into the images that the prepared frame names."""
    var colors = Pointer[UInt8, MutUntrackedOrigin](
        unsafe_from_address=Int(
            tm_village_pointers(app)[unsafe_offset=POINTER_COLOR]
        )
    )
    var depths = Pointer[Float32, MutUntrackedOrigin](
        unsafe_from_address=Int(
            tm_village_pointers(app)[unsafe_offset=POINTER_DEPTH]
        )
    )
    for index in range(FRAME_BYTES):
        colors.unsafe_offset(index).unsafe_write(gray)
    for index in range(WIDTH * HEIGHT):
        depths.unsafe_offset(index).unsafe_write(inf[DType.float32]())


def _finished(app: Handle) raises -> UInt64:
    """Finish the frame that a flat gray was painted into, and return the
    64-bit FNV-1a hash of the result."""
    _step(app, 2)
    assert_equal(tm_village_prepare(app), Int32(1))
    _paint(app, 120)
    var bytes = tm_village_finish(app)
    var hash = UInt64(14695981039346656037)
    for index in range(FRAME_BYTES):
        var byte = UInt64(bytes.unsafe_offset(index).unsafe_load())
        hash = (hash ^ byte) * UInt64(1099511628211)
    return hash


def test_a_game_for_a_gpu_draws_at_the_windows_size() raises:
    # A preset draws a share of the window. For a GPU it draws all of it, and
    # the steps of the sky and the water, which count pixels, grow as the
    # frame does, so that they keep their spacing in the picture.
    var low = game_quality(LOW)
    var cpu = play_parameters(LOW)
    assert_almost_equal(cpu.quality.render_scale, Float32(0.48), atol=1e-6)
    assert_equal(cpu.quality.sky_step, low.sky_step)
    var gpu = play_parameters(LOW, True)
    assert_equal(gpu.quality.render_scale, Float32(1))
    # Each step is divided by the share, and rounded.
    assert_equal(gpu.quality.sky_step, Int(Float32(low.sky_step) / 0.48 + 0.5))
    assert_equal(gpu.quality.water_step, 13)
    assert_equal(gpu.quality.frame_size(1920, 1080)[0], 1920)
    var medium = play_parameters(MEDIUM, True)
    assert_equal(medium.quality.sky_step, game_quality(MEDIUM).sky_step * 2)
    # A preset that draws the whole window keeps its steps.
    var ultra = play_parameters(ULTRA, True)
    assert_equal(ultra.quality.sky_step, game_quality(ULTRA).sky_step)
    assert_equal(game_quality(ULTRA).water_step, 1)
    # The water on a GPU shades a grid of samples, so its step is two or more.
    assert_equal(ultra.quality.water_step, 2)
    # The steps stay within what a quality allows.
    var high = play_parameters(HIGH, True)
    high.quality.check()


def test_the_environment_asks_for_a_game_for_a_gpu() raises:
    _ = unsetenv(GPU_VARIABLE)
    assert_false(gpu_from_environment())
    _ = setenv(GPU_VARIABLE, "1")
    try:
        assert_true(gpu_from_environment())
        _ = setenv(GPU_VARIABLE, "0")
        assert_false(gpu_from_environment())
    finally:
        _ = unsetenv(GPU_VARIABLE)


def test_a_game_that_a_gpu_does_not_draw_prepares_no_frame() raises:
    var app = _make()
    _step(app, 2)
    assert_equal(tm_village_prepare(app), Int32(0))
    assert_false(_state(app)[].gpu)
    # The CPU's frame draws more of the window when there is time.
    assert_true(_state(app)[].game.dynamic)
    tm_destroy(app)


def test_a_prepared_frame_is_described_to_the_host() raises:
    var app = _make_gpu()
    assert_true(_state(app)[].gpu)
    # A GPU draws into an image of a fixed size, so the frame keeps its
    # size.
    assert_false(_state(app)[].game.dynamic)
    _step(app, 3)
    assert_equal(tm_village_prepare(app), Int32(1))
    var ints = tm_village_ints(app)
    assert_equal(Int(ints[unsafe_offset=INT_WIDTH]), WIDTH)
    assert_equal(Int(ints[unsafe_offset=INT_HEIGHT]), HEIGHT)
    assert_true(Int(ints[unsafe_offset=INT_TRIANGLES]) > 0)
    assert_true(Int(ints[unsafe_offset=INT_VERTICES]) > 0)
    assert_equal(
        tm_village_floats(app)[unsafe_offset=FLOAT_EXPOSURE],
        _state(app)[].game.fast.exposure,
    )
    var addresses = tm_village_pointers(app)
    assert_true(addresses[unsafe_offset=POINTER_VERTICES] != 0)
    assert_true(addresses[unsafe_offset=POINTER_CORNERS] != 0)
    # The images that the host writes into are the game's own.
    assert_equal(
        Int(addresses[unsafe_offset=POINTER_COLOR]),
        Int(_state(app)[].game.gpu_image.pixels.unsafe_ptr()),
    )
    assert_equal(
        Int(addresses[unsafe_offset=POINTER_DEPTH]),
        Int(_state(app)[].game.gpu_image.depth.unsafe_ptr()),
    )
    tm_destroy(app)


def test_a_frame_that_a_gpu_drew_is_finished_on_the_cpu() raises:
    var app = _make_gpu()
    _step(app, 2)
    assert_equal(tm_village_prepare(app), Int32(1))
    _paint(app, 120)
    var bytes = tm_village_finish(app)
    # The finished frame is the window's.
    assert_equal(Int(bytes), Int(_state(app)[].game.window.pixels.unsafe_ptr()))
    assert_equal(len(_state(app)[].game.window.pixels), FRAME_BYTES)
    # The image that the host writes into is free for the next frame, and it
    # is the size of the window.
    assert_equal(len(_state(app)[].game.gpu_image.pixels), FRAME_BYTES)
    assert_equal(len(_state(app)[].game.gpu_image.depth), WIDTH * HEIGHT)
    # The heads-up display is drawn over the gray: not every pixel is.
    var grays = 0
    for index in range(WIDTH * HEIGHT):
        if bytes.unsafe_offset(index * 4).unsafe_load() == 120:
            grays += 1
    assert_true(grays > 0)
    # Frame after frame, the two images take turns.
    var first = Int(_color_address(app))
    _step(app, 1)
    assert_equal(tm_village_prepare(app), Int32(1))
    assert_true(
        Int(tm_village_pointers(app)[unsafe_offset=POINTER_COLOR]) != first
    )
    _paint(app, 120)
    _ = tm_village_finish(app)
    tm_destroy(app)


def test_the_same_painted_frames_finish_the_same() raises:
    var one = _make_gpu()
    var two = _make_gpu()
    assert_equal(_finished(one), _finished(two))
    assert_equal(_finished(one), _finished(two))
    tm_destroy(one)
    tm_destroy(two)


def test_a_frame_that_cannot_be_prepared_for_a_gpu_is_refused() raises:
    var app = _make_gpu()
    _step(app, 2)
    # The game draws no spot light.
    _state(app)[].scene.add_light(spot_light(Color(255, 255, 255), NodeId(0)))
    assert_equal(tm_village_prepare(app), Int32(0))
    tm_destroy(app)


def test_a_frame_that_cannot_be_finished_is_the_last_one() raises:
    var app = _make_gpu()
    var before = _finished(app)
    _step(app, 2)
    assert_equal(tm_village_prepare(app), Int32(1))
    _paint(app, 120)
    # The weather needs a depth for each pixel.
    _state(app)[].game.gpu_image.depth = List[Float32](length=1, fill=0)
    var bytes = tm_village_finish(app)
    var hash = UInt64(14695981039346656037)
    for index in range(FRAME_BYTES):
        var byte = UInt64(bytes.unsafe_offset(index).unsafe_load())
        hash = (hash ^ byte) * UInt64(1099511628211)
    assert_equal(hash, before)
    # The image is back, so a later frame can use it.
    assert_equal(len(_state(app)[].game.gpu_image.pixels), FRAME_BYTES)
    tm_destroy(app)


def _make_passes(hour: Float32 = -1, weather: Int = -1) raises -> Handle:
    """Make an app of the tiny village for a GPU that takes the passes: the
    weather, the night, the water and the smoothing of edges. It begins at an
    hour, in a weather, and the water has a step of two pixels."""
    var parameters = tiny_game()
    parameters.quality.render_scale = 1
    parameters.quality.water_step = 2
    var app = new_app(
        WIDTH,
        HEIGHT,
        parameters,
        pebble_bed(gray_photograph()),
        True,
        hour,
        weather,
    )
    var handle = Handle(unsafe_from_address=Int(app))
    assert_equal(tm_village_passes(handle, 1), Int32(1))
    return handle


def _look(app: Handle, degrees: Float32):
    """Turn the player's view to a heading: 180 faces the pond."""
    _state(app)[].game.view.yaw = Angle(degrees, DEGREE)


def _prepared(app: Handle, ticks: Int = 3) raises:
    """Step an app, and prepare its frame."""
    _step(app, ticks)
    assert_equal(tm_village_prepare(app), Int32(1))


def _grays(app: Handle) -> Int:
    """Count the pixels of the finished frame that are the flat gray that
    `_paint` wrote."""
    var bytes = tm_village_finish(app)
    var grays = 0
    for index in range(WIDTH * HEIGHT):
        if bytes.unsafe_offset(index * 4).unsafe_load() == 120:
            grays += 1
    return grays


def test_a_host_takes_the_passes_only_for_a_gpu() raises:
    var cpu = _make()
    assert_equal(tm_village_passes(cpu, 1), Int32(0))
    assert_false(_state(cpu)[].passes)
    tm_destroy(cpu)
    var gpu = _make_gpu()
    assert_false(_state(gpu)[].passes)
    assert_equal(tm_village_passes(gpu, 1), Int32(1))
    assert_true(_state(gpu)[].passes)
    assert_equal(tm_village_passes(gpu, 0), Int32(1))
    assert_false(_state(gpu)[].passes)
    tm_destroy(gpu)


def test_a_frame_without_the_passes_asks_for_the_depths() raises:
    var app = _make_gpu()
    _prepared(app)
    var ints = tm_village_ints(app)
    assert_equal(Int(ints[unsafe_offset=INT_DEPTH]), 1)
    assert_equal(Int(ints[unsafe_offset=INT_PASSES]), 0)
    assert_false(_state(app)[].game.gpu_post.on)
    tm_destroy(app)


def test_the_passes_are_described_to_the_host() raises:
    # At night, in the rain, facing the pond: every pass has work.
    var app = _make_passes(23, Int(RAIN.value))
    _look(app, 180)
    _prepared(app)
    var ints = tm_village_ints(app)
    var floats = tm_village_floats(app)
    var addresses = tm_village_pointers(app)
    assert_equal(Int(ints[unsafe_offset=INT_PASSES]), 1)
    assert_equal(Int(ints[unsafe_offset=INT_DEPTH]), 0)
    assert_equal(Int(ints[unsafe_offset=INT_NIGHT_ON]), 1)
    assert_equal(Int(ints[unsafe_offset=INT_WATER_ON]), 1)
    assert_equal(
        Int(ints[unsafe_offset=INT_SMOOTH_ON]),
        1 if _state(app)[].game.quality.smooth_edges else 0,
    )
    assert_true(floats[unsafe_offset=FLOAT_NIGHT_DAY] < 1)
    assert_true(floats[unsafe_offset=FLOAT_WATER_SHARE] < 1)
    # The clouds are a grid of four-pixel steps over the frame.
    var step = Int(ints[unsafe_offset=INT_COVER_STEP])
    assert_equal(
        Int(ints[unsafe_offset=INT_COVER_COLUMNS]),
        (WIDTH + step - 1) // step + 1,
    )
    assert_equal(
        Int(ints[unsafe_offset=INT_COVER_ROWS]), (HEIGHT + step - 1) // step + 1
    )
    assert_true(addresses[unsafe_offset=POINTER_COVER] != 0)
    # The water is shaded on a grid of samples, from the tables it kept.
    assert_equal(Int(ints[unsafe_offset=INT_WATER_STEP]), 2)
    assert_equal(
        Int(ints[unsafe_offset=INT_WATER_GRID_WIDTH]), grid_samples(WIDTH, 2)
    )
    assert_equal(
        Int(ints[unsafe_offset=INT_WATER_GRID_HEIGHT]), grid_samples(HEIGHT, 2)
    )
    assert_equal(Int(ints[unsafe_offset=INT_WATER_WORDS]), COMPOSE_WORDS)
    assert_equal(Int(ints[unsafe_offset=INT_WATER_SURFACE_MADE]), 1)
    assert_equal(Int(ints[unsafe_offset=INT_WATER_BED_MADE]), 1)
    assert_true(Int(ints[unsafe_offset=INT_WATER_RIPPLE_MADE]) >= 1)
    assert_true(addresses[unsafe_offset=POINTER_WATER_SURFACE] != 0)
    assert_true(addresses[unsafe_offset=POINTER_WATER_RIPPLE] != 0)
    assert_true(addresses[unsafe_offset=POINTER_WATER_CAUSTIC] != 0)
    assert_true(addresses[unsafe_offset=POINTER_WATER_PEBBLE] != 0)
    assert_true(addresses[unsafe_offset=POINTER_WATER_WORDS] != 0)
    ref words = _state(app)[].game.gpu_post.upload.words
    assert_equal(Int(words[WORD_WIDTH]), WIDTH)
    assert_equal(Int(words[WORD_HEIGHT]), HEIGHT)
    assert_equal(Int(words[WORD_GRID_WIDTH]), grid_samples(WIDTH, 2))
    assert_equal(Int(words[WORD_GRID_HEIGHT]), grid_samples(HEIGHT, 2))
    assert_equal(Int(words[WORD_STEP]), 2)
    assert_equal(
        addresses[unsafe_offset=POINTER_WATER_WORDS],
        Int64(Int(_state(app)[].game.gpu_post.upload.words.unsafe_ptr())),
    )
    tm_destroy(app)


def test_by_day_with_the_pond_out_of_view_there_is_no_night_and_no_water() raises:
    var app = _make_passes(12, Int(CLEAR.value))
    # Turned to the side, the player has the pond behind them.
    _look(app, 90)
    _prepared(app)
    var ints = tm_village_ints(app)
    assert_equal(Int(ints[unsafe_offset=INT_PASSES]), 1)
    assert_equal(Int(ints[unsafe_offset=INT_NIGHT_ON]), 0)
    assert_equal(Int(ints[unsafe_offset=INT_WATER_ON]), 0)
    # The water's tables are not made while the pond is out of view.
    assert_equal(_state(app)[].game.gpu_post.upload.surface_made, 0)
    assert_almost_equal(
        tm_village_floats(app)[unsafe_offset=FLOAT_COVER_BRIGHT], 1
    )
    tm_destroy(app)


def test_the_water_tables_are_kept_from_frame_to_frame() raises:
    var app = _make_passes(12, Int(CLEAR.value))
    _look(app, 180)
    _prepared(app)
    ref upload = _state(app)[].game.gpu_post.upload
    assert_equal(upload.bed_made, 1)
    assert_equal(upload.surface_made, 1)
    # The photograph is packed once. The surface is packed only when the
    # scene found a new one: the quality finds the waves every few frames.
    var every = _state(app)[].game.village.water.refresh_every
    assert_true(every > 1)
    for _ in range(every + 1):
        _prepared(app, 1)
    assert_equal(upload.bed_made, 1)
    assert_equal(upload.surface_made, 2)
    tm_destroy(app)


def test_with_the_passes_taken_the_cpu_leaves_them_out() raises:
    # Fog hides the sky with mist: the CPU would change the gray sky that
    # the host painted. With the passes taken it leaves it as it is.
    var taken = _make_passes(12, Int(FOG.value))
    _look(taken, 0)
    _prepared(taken)
    _paint(taken, 120)
    var kept = _grays(taken)
    var left = _make_passes(12, Int(FOG.value))
    _look(left, 0)
    assert_equal(tm_village_passes(left, 0), Int32(1))
    _prepared(left)
    _paint(left, 120)
    var changed = _grays(left)
    assert_true(kept > changed)
    tm_destroy(taken)
    tm_destroy(left)


def test_rain_and_the_display_are_still_drawn_on_the_cpu() raises:
    var app = _make_passes(12, Int(RAIN.value))
    _look(app, 0)
    _prepared(app)
    _paint(app, 120)
    var kept = _grays(app)
    # The heads-up display and the rain are drawn over the gray.
    assert_true(kept < WIDTH * HEIGHT)
    assert_true(kept > 0)
    tm_destroy(app)


def test_passes_that_cannot_be_prepared_are_refused() raises:
    var app = _make_passes(12, Int(CLEAR.value))
    _look(app, 180)
    _step(app, 3)
    # The water on a GPU shades a grid: one pixel is not a grid.
    _state(app)[].game.village.water.shade_step = 1
    assert_equal(tm_village_prepare(app), Int32(0))
    assert_false(_state(app)[].game.gpu_post.on)
    # A step that is right again prepares the frame.
    _state(app)[].game.village.water.shade_step = 2
    assert_equal(tm_village_prepare(app), Int32(1))
    assert_true(_state(app)[].game.gpu_post.on)
    # A host that gives the passes back gets the depths again.
    assert_equal(tm_village_passes(app, 0), Int32(1))
    assert_equal(tm_village_prepare(app), Int32(1))
    assert_equal(Int(tm_village_ints(app)[unsafe_offset=INT_DEPTH]), 1)
    assert_false(_state(app)[].game.gpu_post.on)
    tm_destroy(app)


def test_a_weather_is_named() raises:
    assert_equal(weather_named("clear"), CLEAR)
    assert_equal(weather_named("overcast"), OVERCAST)
    assert_equal(weather_named("rain"), RAIN)
    assert_equal(weather_named("fog"), FOG)
    assert_equal(weather_named("snow"), SNOW)
    with assert_raises(contains="rain, fog or snow, not storm"):
        _ = weather_named("storm")


def test_keys_pause_the_game_and_show_the_map() raises:
    var app = _make()
    _press(app, 112)
    assert_true(_state(app)[].game.paused)
    _release(app, 112)
    _press(app, 110)
    assert_true(_state(app)[].game.show_map)
    _release(app, 110)
    _press(app, 57)
    assert_equal(_state(app)[].game.weather.kind.value, 4)
    tm_destroy(app)


def test_an_app_gives_its_host_the_village_s_sound() raises:
    var app = _make()
    var room = alloc(Layout[Float32](count=400)).unsafe_leak()
    for k in range(400):
        room.unsafe_offset(k).unsafe_write(9)
    assert_equal(tm_village_audio(app, room, Int32(200)), Int32(200))
    for k in range(400):
        var s = room[unsafe_offset=k]
        assert_true(s >= -1 and s <= 1)
    # Too many samples at once makes none.
    assert_equal(tm_village_audio(app, room, Int32(100000)), Int32(0))
    # No samples at all is no work.
    assert_equal(tm_village_audio(app, room, Int32(0)), Int32(0))
    room.unsafe_free()
    tm_destroy(app)


def test_an_app_keeps_its_progress_in_a_file() raises:
    var path = String(getenv("TMPDIR", "/tmp"), "/village_progress_kept.bin")
    if Path(path).exists():
        remove(path)
    var app = _make()
    # No file yet: the game begins as it is, and keeps nothing until told.
    _state(app)[].keep()
    _state(app)[].resume(path)
    assert_false(Path(path).exists())
    _state(app)[].game.gathering.satchel.counts[HERBS.value] = 4
    _state(app)[].game.day.hour = 21
    tm_destroy(app)
    assert_true(Path(path).exists())
    # The next game takes up where this one ended.
    var again = _make()
    _state(again)[].resume(path)
    assert_equal(_state(again)[].game.gathering.satchel.count(HERBS), 4)
    assert_almost_equal(_state(again)[].game.day.hour, 21, atol=1e-3)
    # A file that cannot be written loses only the progress.
    _state(again)[].keeps = String(path, "/not/a/dir")
    tm_destroy(again)


def test_the_environment_sets_the_weather_and_the_hour() raises:
    _ = unsetenv(HOUR_VARIABLE)
    _ = unsetenv(WEATHER_VARIABLE)
    assert_equal(weather_from_environment(), -1)
    assert_equal(hour_from_environment(), -1)
    _ = setenv(WEATHER_VARIABLE, "rain")
    _ = setenv(HOUR_VARIABLE, "21.5")
    try:
        assert_equal(weather_from_environment(), Int(RAIN.value))
        assert_almost_equal(hour_from_environment(), 21.5)
        _ = setenv(WEATHER_VARIABLE, "storm")
        with assert_raises(contains="not storm"):
            _ = weather_from_environment()
        _ = setenv(HOUR_VARIABLE, "24")
        with assert_raises(contains="from 0 to less than 24, not 24"):
            _ = hour_from_environment()
        _ = setenv(HOUR_VARIABLE, "-2")
        with assert_raises(contains="not -2"):
            _ = hour_from_environment()
        _ = setenv(HOUR_VARIABLE, "noon")
        with assert_raises(contains="noon"):
            _ = hour_from_environment()
    finally:
        _ = unsetenv(HOUR_VARIABLE)
        _ = unsetenv(WEATHER_VARIABLE)


def test_an_hour_or_a_weather_that_is_not_valid_makes_no_app() raises:
    _ = setenv(HOUR_VARIABLE, "30")
    try:
        assert_false(Bool(tm_create(Int32(10), Int32(10))))
    finally:
        _ = unsetenv(HOUR_VARIABLE)
    _ = setenv(WEATHER_VARIABLE, "storm")
    try:
        assert_false(Bool(tm_create(Int32(10), Int32(10))))
    finally:
        _ = unsetenv(WEATHER_VARIABLE)


def test_a_game_begins_at_an_hour_in_a_weather() raises:
    var app = _make()
    var state = _state(app)
    var hour = state[].game.day.hour
    # -1 keeps the game's own.
    state[].start_at(-1, -1)
    assert_equal(state[].game.day.hour, hour)
    state[].start_at(21, Int(OVERCAST.value))
    assert_equal(state[].game.day.hour, 21)
    assert_equal(state[].game.weather.kind, OVERCAST)
    # The sky has that look at once.
    assert_almost_equal(state[].game.weather.look.clouds, 0.85)
    state[].start_at(5, -1)
    assert_equal(state[].game.day.hour, 5)
    assert_equal(state[].game.weather.kind, OVERCAST)
    with assert_raises(contains="from 0 to less than 24, not 24"):
        state[].start_at(24, -1)
    with assert_raises(contains="must be a kind, not 9"):
        state[].start_at(-1, 9)
    # A refused start leaves the game as it was.
    assert_equal(state[].game.day.hour, 5)
    assert_equal(state[].game.weather.kind, OVERCAST)
    tm_destroy(app)
    var begun = new_app(
        WIDTH,
        HEIGHT,
        tiny_game(),
        pebble_bed(gray_photograph()),
        False,
        22,
        Int(FOG.value),
    )
    assert_equal(begun[].game.day.hour, 22)
    assert_equal(begun[].game.weather.kind, FOG)
    tm_destroy(Handle(unsafe_from_address=Int(begun)))
    with assert_raises(contains="not 25"):
        _ = new_app(
            WIDTH,
            HEIGHT,
            tiny_game(),
            pebble_bed(gray_photograph()),
            False,
            25,
            -1,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
