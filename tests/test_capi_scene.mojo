# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `window.capi_scene`, the C ABI on the full renderer.

The functions are the ones a C host calls, called here from Mojo with the
same scalars and the same opaque handle. Each failure that the functions
swallow is forced here, so that each is seen to leave the app as it was.
"""

from controls.input import ARROW_UP
from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId
from objects.mesh import Mesh
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from window.capi_abi import (
    ABI_VERSION,
    KEY_DOWN,
    KEY_SPACE,
    KEY_UP,
    MAX_SIDE,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    WHEEL,
)
from window.capi_scene import (
    SceneApp,
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

comptime Handle = OpaquePointer[MutUntrackedOrigin]
comptime WIDTH = 40
comptime HEIGHT = 30
comptime FRAME_BYTES = WIDTH * HEIGHT * 4
comptime TICK = 16667
comptime UNKNOWN_KIND = 99
comptime BACKGROUND = 0


def _make() raises -> Handle:
    """Make an app, which the test needs to succeed."""
    var created = tm_create(Int32(WIDTH), Int32(HEIGHT))
    assert_true(Bool(created))
    return Handle(unsafe_from_address=Int(created.value()))


def _state(app: Handle) -> Pointer[SceneApp, MutUntrackedOrigin]:
    """View a handle as the app, to break it on purpose."""
    return app.unsafe_bitcast[SceneApp]()


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


def _drag(app: Handle):
    """Drag with the first button across the frame."""
    tm_event(app, Int32(POINTER_DOWN), Int32(10), Int32(10), Int32(0))
    tm_event(app, Int32(POINTER_MOVE), Int32(20), Int32(10), Int32(0))
    tm_event(app, Int32(POINTER_MOVE), Int32(30), Int32(14), Int32(0))
    tm_event(app, Int32(POINTER_UP), Int32(30), Int32(14), Int32(0))


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


def test_an_app_has_its_size_and_a_frame_with_cubes() raises:
    var app = _make()
    assert_equal(tm_width(app), Int32(WIDTH))
    assert_equal(tm_height(app), Int32(HEIGHT))
    var bytes = tm_frame(app)
    # The background is dark and the cubes are not: some pixel is bright.
    var brightest = 0
    for pixel in range(WIDTH * HEIGHT):
        brightest = max(
            brightest, Int(bytes.unsafe_offset(pixel * 4).unsafe_load())
        )
        assert_equal(
            bytes.unsafe_offset(pixel * 4 + 3).unsafe_load(), UInt8(255)
        )
    assert_true(brightest > 100)
    tm_destroy(app)


def test_the_same_steps_draw_the_same_frame() raises:
    var first = _make()
    var second = _make()
    _step(first, 5)
    _step(second, 5)
    assert_equal(_hash(first), _hash(second))
    tm_destroy(first)
    tm_destroy(second)


def test_stepping_turns_the_cubes() raises:
    var app = _make()
    var before = _hash(app)
    _step(app, 10)
    assert_true(before != _hash(app))
    tm_destroy(app)


def test_negative_time_is_ignored() raises:
    var app = _make()
    var before = _hash(app)
    tm_step(app, Int32(-1))
    assert_equal(before, _hash(app))
    tm_destroy(app)


def test_the_space_bar_pauses_and_resumes() raises:
    var app = _make()
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    var paused = _hash(app)
    _step(app, 10)
    assert_equal(paused, _hash(app))
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    _step(app, 10)
    assert_true(paused != _hash(app))
    tm_destroy(app)


def test_a_key_released_does_not_pause() raises:
    var app = _make()
    var before = _hash(app)
    tm_event(app, Int32(KEY_UP), Int32(0), Int32(0), Int32(KEY_SPACE))
    _step(app, 10)
    assert_true(before != _hash(app))
    tm_destroy(app)


def test_a_drag_turns_the_camera() raises:
    var plain = _make()
    var dragged = _make()
    _step(plain, 3)
    _drag(dragged)
    _step(dragged, 3)
    assert_true(_hash(plain) != _hash(dragged))
    tm_destroy(plain)
    tm_destroy(dragged)


def test_an_arrow_key_pans_the_camera() raises:
    var plain = _make()
    var panned = _make()
    _step(plain, 3)
    tm_event(panned, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(ARROW_UP.value))
    _step(panned, 3)
    assert_true(_hash(plain) != _hash(panned))
    tm_destroy(plain)
    tm_destroy(panned)


def test_the_wheel_dollies_the_camera() raises:
    var plain = _make()
    var dollied = _make()
    _step(plain, 3)
    tm_event(dollied, Int32(WHEEL), Int32(20), Int32(15), Int32(-1))
    _step(dollied, 3)
    assert_true(_hash(plain) != _hash(dollied))
    tm_destroy(plain)
    tm_destroy(dollied)


def test_an_event_of_an_unknown_kind_is_dropped() raises:
    var plain = _make()
    var touched = _make()
    tm_event(touched, Int32(UNKNOWN_KIND), Int32(5), Int32(5), Int32(0))
    _step(plain, 3)
    _step(touched, 3)
    assert_equal(_hash(plain), _hash(touched))
    tm_destroy(plain)
    tm_destroy(touched)


def test_a_step_that_cannot_turn_the_cubes_does_nothing() raises:
    var app = _make()
    var before = _hash(app)
    # A node that is not in the scene: the scene refuses to hand it out.
    _state(app)[].pivot = NodeId(9999)
    _step(app, 10)
    assert_equal(before, _hash(app))
    tm_destroy(app)


def test_a_frame_that_cannot_be_drawn_is_the_last_one() raises:
    var app = _make()
    var before = _hash(app)
    # A mesh that names a geometry the stores do not have.
    _state(app)[].scene.add_mesh(
        Mesh(GeometryId(9999), MaterialId(0), _state(app)[].center)
    )
    assert_equal(before, _hash(app))
    tm_destroy(app)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
