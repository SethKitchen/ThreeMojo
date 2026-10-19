# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `window.capi_splat` and `window.splat_app`, the C ABI on a
Gaussian splat scan.

The functions are the ones a C host calls, called here from Mojo with the
same scalars and the same opaque handle. The scan that most tests load is a
few splats, so that they run fast: the tomato scan is read once, by
`tm_create`. Each failure that the functions swallow is forced here, so that
each is seen to leave the app as it was.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
    write_color_bytes,
    write_covariance,
)
from std.math import abs, inf, sqrt
from std.memory import Layout
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import DEGREE, Angle
from window.capi_abi import (
    ABI_VERSION,
    KEY_DOWN,
    KEY_SPACE,
    KEY_UP,
    MAX_SIDE,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    SPLAT_CENTERS,
    SPLAT_COLORS,
    SPLAT_COVARIANCES,
    SPLAT_INFO_COUNT,
    SPLAT_INFO_DEGREE,
    SPLAT_INFO_ORDER,
    SPLAT_INFO_SCAN,
    SPLAT_ORDER,
    SPLAT_SH1,
    SPLAT_SH2,
    SPLAT_SH3,
    SPLAT_VIEW,
    SPLAT_VIEW_FLOATS,
    SplatInfo,
    SplatPart,
    WHEEL,
)
from window.capi_splat import (
    MAX_ASSET,
    tm_abi_version,
    tm_alloc,
    tm_asset,
    tm_create,
    tm_destroy,
    tm_event,
    tm_frame,
    tm_free,
    tm_height,
    tm_init,
    tm_resize,
    tm_splat_info,
    tm_splat_part,
    tm_splat_prepare,
    tm_splat_words,
    tm_step,
    tm_width,
)
from window.splat_app import (
    BACKGROUND,
    LONGEST_MICROSECONDS,
    SCAN,
    SplatApp,
    VIEW_BACKGROUND,
    VIEW_COUNT,
    VIEW_DEGREE,
    VIEW_EYE,
    VIEW_HEIGHT,
    VIEW_MODEL_VIEW,
    VIEW_PROJECTION,
    VIEW_WIDTH,
)

comptime Handle = OpaquePointer[MutUntrackedOrigin]
comptime WIDTH = 48
comptime HEIGHT = 27
comptime FRAME_BYTES = WIDTH * HEIGHT * 4
comptime DIR = "assets/gaussian_splat/"
comptime UNKNOWN_KIND = 99
comptime KEY_A = 97
comptime FRAME_US = 16667
comptime TOMATOES = 445409


def _plain() raises -> Handle:
    """Make an app with no scan, as a browser's first frame has."""
    var app = SplatApp(WIDTH, HEIGHT)
    var slot = alloc(Layout[SplatApp](count=1)).unsafe_leak()
    slot.unsafe_write(app^)
    return Handle(unsafe_from_address=Int(slot))


def _state(app: Handle) -> Pointer[SplatApp, MutUntrackedOrigin]:
    """View a handle as the app, to read or break it on purpose."""
    return app.unsafe_bitcast[SplatApp]()


def _room(file: List[UInt8]) raises -> Pointer[UInt8, MutUntrackedOrigin]:
    """Put bytes in room from `tm_alloc`, as a host does."""
    var room = tm_alloc(Int32(len(file)))
    assert_true(Bool(room))
    var bytes = room.value()
    for index in range(len(file)):
        bytes.unsafe_offset(index).unsafe_write(file[index])
    return bytes


def _give(app: Handle, name: String) raises -> Int32:
    """Give an app one of the small scans, as a host does."""
    var file = Path(DIR + name).read_bytes()
    var room = _room(file)
    var status = tm_asset(app, room, Int32(len(file)))
    tm_free(room)
    return status


def _loaded(name: String) raises -> Handle:
    """Make an app with no scan, and give it one."""
    var app = _plain()
    assert_equal(_give(app, name), Int32(0))
    return app


def _line() raises -> GaussianSplatGeometry:
    """Return four red splats in a row going away from the camera."""
    var centers = List[Float32]()
    var covariances = List[Float32](length=24, fill=0)
    var colors = List[UInt8](length=16, fill=0)
    for index in range(4):
        centers.append(Float32(0))
        centers.append(Float32(0))
        centers.append(Float32(-1.5 * Float32(index)))
        write_covariance(covariances, index * 6, 0.2, 0.2, 0.2, 0, 0, 0, 1)
        write_color_bytes(colors, index * 4, 255, 0, 0, 255)
    return create_gaussian_splat_geometry(centers^, covariances^, colors^)


def _words(app: Handle, which: SplatPart) -> Int:
    return Int(tm_splat_words(app, Int32(which.value)))


def _floats(
    app: Handle, which: SplatPart
) raises -> Pointer[Float32, MutUntrackedOrigin]:
    """The address of a part, as floats, which the test needs."""
    var part = tm_splat_part(app, Int32(which.value))
    assert_true(Bool(part))
    return Pointer[Float32, MutUntrackedOrigin](
        unsafe_from_address=Int(part.value())
    )


def _indices(
    app: Handle,
) raises -> Pointer[UInt32, MutUntrackedOrigin]:
    """The address of the draw order, as 32-bit indices."""
    var part = tm_splat_part(app, Int32(SPLAT_ORDER.value))
    assert_true(Bool(part))
    return Pointer[UInt32, MutUntrackedOrigin](
        unsafe_from_address=Int(part.value())
    )


def _info(app: Handle, which: SplatInfo) -> Int:
    return Int(tm_splat_info(app, Int32(which.value)))


def _hash(app: Handle) -> UInt64:
    """Draw the app, and return the 64-bit FNV-1a hash of the frame."""
    var bytes = tm_frame(app)
    var hash = UInt64(14695981039346656037)
    for index in range(FRAME_BYTES):
        var byte = UInt64(bytes.unsafe_offset(index).unsafe_load())
        hash = (hash ^ byte) * UInt64(1099511628211)
    return hash


def _step(app: Handle, count: Int):
    """Run whole frames' worth of time."""
    for _ in range(count):
        tm_step(app, Int32(FRAME_US))


def _drag(app: Handle, button: Int, to_x: Int, to_y: Int):
    """Press at the middle, move to a point, and let go."""
    tm_event(app, Int32(POINTER_DOWN), Int32(24), Int32(13), Int32(button))
    tm_event(app, Int32(POINTER_MOVE), Int32(to_x), Int32(to_y), Int32(button))
    tm_event(app, Int32(POINTER_UP), Int32(to_x), Int32(to_y), Int32(button))


def test_the_abi_version_is_the_cores() raises:
    assert_equal(tm_abi_version(), Int32(ABI_VERSION))


def test_init_may_be_called_where_the_runtime_runs() raises:
    tm_init()
    var app = _plain()
    assert_equal(tm_width(app), Int32(WIDTH))
    tm_destroy(app)


def test_a_side_that_is_not_positive_makes_no_app() raises:
    assert_false(Bool(tm_create(Int32(0), Int32(10))))
    assert_false(Bool(tm_create(Int32(10), Int32(0))))
    assert_false(Bool(tm_create(Int32(-1), Int32(10))))


def test_a_side_that_is_too_large_makes_no_app() raises:
    assert_false(Bool(tm_create(Int32(MAX_SIDE + 1), Int32(10))))
    assert_false(Bool(tm_create(Int32(10), Int32(MAX_SIDE + 1))))


def test_create_reads_the_tomato_scan_when_it_can_be_read() raises:
    var created = tm_create(Int32(WIDTH), Int32(HEIGHT))
    assert_true(Bool(created))
    var app = Handle(unsafe_from_address=Int(created.value()))
    assert_equal(_info(app, SPLAT_INFO_COUNT), TOMATOES)
    assert_equal(_info(app, SPLAT_INFO_DEGREE), 3)
    assert_equal(_info(app, SPLAT_INFO_SCAN), 1)
    assert_equal(_words(app, SPLAT_CENTERS), TOMATOES * 3)
    assert_equal(_words(app, SPLAT_COLORS), TOMATOES)
    assert_equal(_words(app, SPLAT_SH3), TOMATOES * 6)
    tm_destroy(app)


def test_an_app_has_its_size_and_a_background_before_a_scan() raises:
    var app = _plain()
    assert_equal(tm_width(app), Int32(WIDTH))
    assert_equal(tm_height(app), Int32(HEIGHT))
    var bytes = tm_frame(app)
    for pixel in range(WIDTH * HEIGHT):
        assert_equal(bytes.unsafe_offset(pixel * 4).unsafe_load(), BACKGROUND.r)
        assert_equal(
            bytes.unsafe_offset(pixel * 4 + 1).unsafe_load(), BACKGROUND.g
        )
        assert_equal(
            bytes.unsafe_offset(pixel * 4 + 2).unsafe_load(), BACKGROUND.b
        )
        assert_equal(
            bytes.unsafe_offset(pixel * 4 + 3).unsafe_load(), UInt8(255)
        )
    tm_destroy(app)


def test_nothing_is_prepared_before_a_scan() raises:
    var app = _plain()
    for which in range(SPLAT_VIEW.value + 1):
        assert_false(Bool(tm_splat_part(app, Int32(which))))
        assert_equal(_words(app, SplatPart(which)), 0)
    assert_equal(_info(app, SPLAT_INFO_COUNT), 0)
    assert_equal(_info(app, SPLAT_INFO_DEGREE), 0)
    assert_equal(_info(app, SPLAT_INFO_SCAN), 0)
    assert_equal(_info(app, SPLAT_INFO_ORDER), 0)
    assert_equal(tm_splat_prepare(app), Int32(1))
    tm_destroy(app)


def test_a_host_gives_the_app_its_scan() raises:
    var app = _loaded("v3.spz")
    assert_equal(_info(app, SPLAT_INFO_COUNT), 4)
    assert_equal(_info(app, SPLAT_INFO_DEGREE), 3)
    assert_equal(_info(app, SPLAT_INFO_SCAN), 1)
    assert_equal(_words(app, SPLAT_CENTERS), 12)
    assert_equal(_words(app, SPLAT_COVARIANCES), 24)
    assert_equal(_words(app, SPLAT_COLORS), 4)
    assert_equal(_words(app, SPLAT_SH1), 12)
    assert_equal(_words(app, SPLAT_SH2), 16)
    assert_equal(_words(app, SPLAT_SH3), 24)
    # The scan is read where it is: the part is the geometry's own list.
    var centers = _floats(app, SPLAT_CENTERS)
    assert_equal(
        centers[unsafe_offset=5], _state(app)[].splat.splat_geometry.centers[5]
    )
    # The order waits for the first prepare.
    assert_false(Bool(tm_splat_part(app, Int32(SPLAT_ORDER.value))))
    tm_destroy(app)


def test_a_scan_has_the_bands_it_carries_and_no_others() raises:
    var none = _loaded("v1.spz")
    assert_equal(_info(none, SPLAT_INFO_DEGREE), 0)
    for which in [SPLAT_SH1, SPLAT_SH2, SPLAT_SH3]:
        assert_false(Bool(tm_splat_part(none, Int32(which.value))))
        assert_equal(_words(none, which), 0)
    tm_destroy(none)
    var first = _loaded("v2.spz")
    assert_equal(_info(first, SPLAT_INFO_DEGREE), 1)
    assert_true(Bool(tm_splat_part(first, Int32(SPLAT_SH1.value))))
    assert_equal(_words(first, SPLAT_SH1), 6)
    assert_false(Bool(tm_splat_part(first, Int32(SPLAT_SH2.value))))
    assert_false(Bool(tm_splat_part(first, Int32(SPLAT_SH3.value))))
    tm_destroy(first)
    var second = _loaded("v4.spz")
    assert_equal(_info(second, SPLAT_INFO_COUNT), 2)
    assert_equal(_info(second, SPLAT_INFO_DEGREE), 1)
    tm_destroy(second)


def test_a_second_scan_replaces_the_first() raises:
    var app = _loaded("v3.spz")
    assert_equal(_give(app, "v1.spz"), Int32(0))
    assert_equal(_info(app, SPLAT_INFO_COUNT), 1)
    assert_equal(_info(app, SPLAT_INFO_SCAN), 2)
    tm_destroy(app)


def test_a_new_scan_clears_pending_pan_and_keeps_the_turn_paused() raises:
    var app = _loaded("v3.spz")
    var center = _state(app)[].controls.target
    var position = _state(app)[].camera.position
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    _drag(app, 2, 1024, 13)
    assert_equal(_give(app, "v3.spz"), Int32(0))
    assert_false(_state(app)[].controls.auto_rotate)
    assert_true(_state(app)[].controls.target == center)
    assert_true((_state(app)[].camera.position - position).length() < 1e-4)
    _step(app, 3)
    assert_true(_state(app)[].controls.target == center)
    assert_true((_state(app)[].camera.position - position).length() < 1e-4)
    tm_destroy(app)


def test_a_new_scan_clears_old_damping_and_keeps_the_turn_running() raises:
    var app = _loaded("v3.spz")
    var fresh = _loaded("v3.spz")
    _drag(app, 0, 224, 43)
    _drag(app, 2, 1024, 13)
    _step(app, 1)
    assert_equal(_give(app, "v3.spz"), Int32(0))
    assert_true(_state(app)[].controls.auto_rotate)
    _step(app, 5)
    _step(fresh, 5)
    assert_true(
        _state(app)[].controls.target == _state(fresh)[].controls.target
    )
    assert_true(
        (
            _state(app)[].camera.position - _state(fresh)[].camera.position
        ).length()
        < 1e-4
    )
    tm_destroy(app)
    tm_destroy(fresh)


def test_a_scan_that_cannot_be_read_leaves_the_app_alone() raises:
    var app = _loaded("v3.spz")
    var room = _room(List[UInt8](length=64, fill=7))
    assert_equal(tm_asset(app, room, Int32(64)), Int32(1))
    assert_equal(tm_asset(app, room, Int32(0)), Int32(1))
    assert_equal(tm_asset(app, room, Int32(-4)), Int32(1))
    tm_free(room)
    assert_equal(_info(app, SPLAT_INFO_COUNT), 4)
    assert_equal(_info(app, SPLAT_INFO_SCAN), 1)
    tm_destroy(app)


def test_a_scan_with_no_splats_is_refused() raises:
    var app = _plain()
    var empty = SplatApp(WIDTH, HEIGHT)
    var refused = False
    try:
        empty.load_geometry(GaussianSplatGeometry())
    except:
        refused = True
    assert_true(refused)
    assert_false(empty.loaded)
    tm_destroy(app)


def test_a_path_that_cannot_be_read_loads_nothing() raises:
    var app = SplatApp(WIDTH, HEIGHT)
    assert_false(app.load_path("assets/no-such-scan.spz"))
    assert_false(app.loaded)
    assert_true(app.load_path(DIR + "v3.spz"))
    assert_true(app.loaded)
    assert_equal(app.splat.count(), 4)
    assert_true(Path(SCAN).exists())


def test_room_is_refused_when_its_size_is_out_of_range() raises:
    assert_false(Bool(tm_alloc(Int32(0))))
    assert_false(Bool(tm_alloc(Int32(-1))))
    assert_false(Bool(tm_alloc(Int32(MAX_ASSET + 1))))


def test_room_holds_what_is_written_to_it() raises:
    var room = _room([UInt8(1), UInt8(2), UInt8(3)])
    assert_equal(room.unsafe_offset(2).unsafe_load(), UInt8(3))
    tm_free(room)


def test_the_view_holds_the_camera_and_the_size() raises:
    var app = _loaded("v3.spz")
    assert_equal(tm_splat_prepare(app), Int32(0))
    assert_equal(_words(app, SPLAT_VIEW), SPLAT_VIEW_FLOATS)
    var view = _floats(app, SPLAT_VIEW)
    assert_equal(view[unsafe_offset=VIEW_WIDTH], Float32(WIDTH))
    assert_equal(view[unsafe_offset=VIEW_HEIGHT], Float32(HEIGHT))
    assert_equal(view[unsafe_offset=VIEW_DEGREE], Float32(3))
    assert_equal(view[unsafe_offset=VIEW_COUNT], Float32(4))
    assert_almost_equal(
        Float64(view[unsafe_offset=VIEW_BACKGROUND]), 7.0 / 255, atol=1e-6
    )
    assert_almost_equal(
        Float64(view[unsafe_offset=VIEW_BACKGROUND + 1]), 8.0 / 255, atol=1e-6
    )
    assert_almost_equal(
        Float64(view[unsafe_offset=VIEW_BACKGROUND + 2]), 15.0 / 255, atol=1e-6
    )
    # The eye is the camera's position, because the scan's node is the origin.
    ref camera = _state(app)[].camera
    assert_almost_equal(
        Float64(view[unsafe_offset=VIEW_EYE]),
        Float64(camera.position.x),
        atol=1e-4,
    )
    assert_almost_equal(
        Float64(view[unsafe_offset=VIEW_EYE + 1]),
        Float64(camera.position.y),
        atol=1e-4,
    )
    assert_almost_equal(
        Float64(view[unsafe_offset=VIEW_EYE + 2]),
        Float64(camera.position.z),
        atol=1e-4,
    )
    # The projection is the camera's: its first and sixth numbers are the
    # focal lengths, which the shader reads.
    var projection = camera.projection_matrix()
    for at in range(16):
        assert_equal(
            view[unsafe_offset=VIEW_PROJECTION + at], projection.elements[at]
        )
    # The view takes the camera's position to the origin.
    var x = Float64(camera.position.x)
    var y = Float64(camera.position.y)
    var z = Float64(camera.position.z)
    for row in range(3):
        var moved = (
            Float64(view[unsafe_offset=VIEW_MODEL_VIEW + row]) * x
            + Float64(view[unsafe_offset=VIEW_MODEL_VIEW + 4 + row]) * y
            + Float64(view[unsafe_offset=VIEW_MODEL_VIEW + 8 + row]) * z
            + Float64(view[unsafe_offset=VIEW_MODEL_VIEW + 12 + row])
        )
        assert_almost_equal(moved, 0.0, atol=1e-4)
    tm_destroy(app)


def test_the_order_holds_every_splat_once_furthest_first() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    assert_equal(tm_splat_prepare(app), Int32(0))
    assert_equal(_info(app, SPLAT_INFO_ORDER), 1)
    assert_equal(_words(app, SPLAT_ORDER), 4)
    var order = _indices(app)
    var seen = List[Bool](length=4, fill=False)
    var view = _floats(app, SPLAT_VIEW)
    var last = Float64(1e30)
    for position in range(4):
        var index = Int(order[unsafe_offset=position])
        assert_true(index >= 0 and index < 4)
        assert_false(seen[index])
        seen[index] = True
        # The depth along the view axis, which grows with the distance.
        var depth = -(
            Float64(view[unsafe_offset=VIEW_MODEL_VIEW + 2]) * 0.0
            + Float64(view[unsafe_offset=VIEW_MODEL_VIEW + 10])
            * Float64(-1.5 * Float32(index))
            + Float64(view[unsafe_offset=VIEW_MODEL_VIEW + 14])
        )
        assert_true(depth <= last + 1e-4)
        last = depth
    tm_destroy(app)


def test_the_order_is_made_again_only_when_the_view_has_turned() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    assert_equal(tm_splat_prepare(app), Int32(0))
    assert_equal(_info(app, SPLAT_INFO_ORDER), 1)
    # A step with the camera's own turn stopped, and nothing pending, moves
    # nothing, so the order stands.
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    _step(app, 2)
    assert_equal(tm_splat_prepare(app), Int32(0))
    assert_equal(_info(app, SPLAT_INFO_ORDER), 1)
    # A long drag turns the view far enough to sort again.
    _drag(app, 0, 24 + 200, 13)
    _step(app, 60)
    assert_equal(tm_splat_prepare(app), Int32(0))
    assert_true(_info(app, SPLAT_INFO_ORDER) > 1)
    tm_destroy(app)


def test_a_new_scan_makes_its_own_order() raises:
    var app = _loaded("v3.spz")
    assert_equal(tm_splat_prepare(app), Int32(0))
    assert_equal(_words(app, SPLAT_ORDER), 4)
    assert_equal(_give(app, "v1.spz"), Int32(0))
    assert_false(Bool(tm_splat_part(app, Int32(SPLAT_ORDER.value))))
    assert_equal(tm_splat_prepare(app), Int32(0))
    assert_equal(_words(app, SPLAT_ORDER), 1)
    tm_destroy(app)


def test_a_cpu_frame_before_prepare_keeps_a_gpu_order_to_publish() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    _ = tm_frame(app)
    assert_false(Bool(tm_splat_part(app, Int32(SPLAT_ORDER.value))))
    assert_equal(tm_splat_prepare(app), Int32(0))
    assert_equal(_words(app, SPLAT_ORDER), 4)
    assert_equal(_info(app, SPLAT_INFO_ORDER), 1)
    var order = _indices(app)
    for index in range(4):
        assert_equal(
            Int(order[unsafe_offset=index]), _state(app)[].splat.order[index]
        )
    tm_destroy(app)


def test_a_cpu_resort_is_published_by_the_next_prepare() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    assert_equal(tm_splat_prepare(app), Int32(0))
    var first = _indices(app)[unsafe_offset=0]
    var center = _state(app)[].controls.target
    _state(app)[].camera.place(
        center * 2 - _state(app)[].camera.position, center
    )
    _ = tm_frame(app)
    # A CPU draw does not replace the arrays the host has already read.
    assert_equal(_indices(app)[unsafe_offset=0], first)
    assert_equal(_info(app, SPLAT_INFO_ORDER), 1)
    assert_equal(tm_splat_prepare(app), Int32(0))
    assert_equal(_info(app, SPLAT_INFO_ORDER), 2)
    assert_true(_indices(app)[unsafe_offset=0] != first)
    for index in range(4):
        assert_equal(
            Int(_indices(app)[unsafe_offset=index]),
            _state(app)[].splat.order[index],
        )
    # Drawing the same view again does not need a new order upload.
    _ = tm_frame(app)
    assert_equal(tm_splat_prepare(app), Int32(0))
    assert_equal(_info(app, SPLAT_INFO_ORDER), 2)
    tm_destroy(app)


def test_a_refused_cpu_frame_keeps_its_resort_pending() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    assert_equal(tm_splat_prepare(app), Int32(0))
    var first = _indices(app)[unsafe_offset=0]
    var center = _state(app)[].controls.target
    _state(app)[].camera.place(
        center * 2 - _state(app)[].camera.position, center
    )
    _state(app)[].camera.fov = Angle(0.0, DEGREE)
    _ = tm_frame(app)
    assert_equal(_indices(app)[unsafe_offset=0], first)
    _state(app)[].camera.fov = Angle(50.0, DEGREE)
    assert_equal(tm_splat_prepare(app), Int32(0))
    assert_equal(_info(app, SPLAT_INFO_ORDER), 2)
    assert_true(_indices(app)[unsafe_offset=0] != first)
    tm_destroy(app)


def test_the_same_steps_draw_the_same_picture() raises:
    var first = _plain()
    var second = _plain()
    _state(first)[].load_geometry(_line())
    _state(second)[].load_geometry(_line())
    _step(first, 3)
    _step(second, 3)
    assert_equal(_hash(first), _hash(second))
    tm_destroy(first)
    tm_destroy(second)


def test_the_splats_show_in_the_frame_and_the_turn_moves_them() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    var bytes = tm_frame(app)
    var red = 0
    for pixel in range(WIDTH * HEIGHT):
        if bytes.unsafe_offset(pixel * 4).unsafe_load() > UInt8(60):
            red += 1
    assert_true(red > 4)
    var before = _hash(app)
    _step(app, 30)
    assert_true(before != _hash(app))
    tm_destroy(app)


def test_the_space_bar_stops_and_starts_the_turn() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    assert_true(_state(app)[].controls.auto_rotate)
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    assert_false(_state(app)[].controls.auto_rotate)
    var held = _state(app)[].camera.position
    _step(app, 5)
    assert_almost_equal(
        Float64(_state(app)[].camera.position.x), Float64(held.x), atol=1e-4
    )
    assert_almost_equal(
        Float64(_state(app)[].camera.position.z), Float64(held.z), atol=1e-4
    )
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    assert_true(_state(app)[].controls.auto_rotate)
    _step(app, 5)
    assert_true(_state(app)[].camera.position.x != held.x)
    tm_destroy(app)


def test_other_keys_do_not_stop_the_turn() raises:
    var app = _plain()
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_A))
    tm_event(app, Int32(KEY_UP), Int32(0), Int32(0), Int32(KEY_A))
    tm_event(app, Int32(KEY_UP), Int32(0), Int32(0), Int32(KEY_SPACE))
    assert_true(_state(app)[].controls.auto_rotate)
    tm_destroy(app)


def test_a_drag_turns_the_camera_and_the_second_button_pans_it() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    var start = _state(app)[].camera.position
    _drag(app, 0, 40, 13)
    _step(app, 30)
    var turned = _state(app)[].camera.position
    assert_true(turned.x != start.x)
    assert_almost_equal(
        Float64((turned - _state(app)[].controls.target).length()),
        Float64((start - _state(app)[].controls.target).length()),
        atol=1e-3,
    )
    var target = _state(app)[].controls.target
    _drag(app, 2, 40, 20)
    _step(app, 30)
    assert_true(_state(app)[].controls.target.x != target.x)
    tm_destroy(app)


def test_the_wheel_dollies_and_stays_between_the_limits() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    var target = _state(app)[].controls.target
    var near = _state(app)[].controls.min_distance.value
    var far = _state(app)[].controls.max_distance.value
    for _ in range(40):
        tm_event(app, Int32(WHEEL), Int32(24), Int32(13), Int32(-1))
        _step(app, 1)
    _step(app, 200)
    var close = (_state(app)[].camera.position - target).length()
    assert_almost_equal(Float64(close), Float64(near), atol=1e-3)
    for _ in range(80):
        tm_event(app, Int32(WHEEL), Int32(24), Int32(13), Int32(1))
        _step(app, 1)
    _step(app, 200)
    var away = (_state(app)[].camera.position - target).length()
    assert_almost_equal(Float64(away), Float64(far), atol=1e-2)
    tm_destroy(app)


def test_the_scan_is_framed_as_the_example_frames_it() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    ref state = _state(app)[]
    var sphere = state.splat.bounding_sphere.value()
    var reach = (state.camera.position - sphere.center).length()
    # 1.15 times the distance at which the sphere fits a 50 degree view.
    var fit = Float64(sphere.radius) / 0.42261826174 * 1.15
    assert_almost_equal(Float64(reach), fit, atol=1e-2)
    assert_equal(state.controls.target.z, sphere.center.z)
    assert_almost_equal(
        Float64(state.controls.min_distance.value),
        Float64(sphere.radius) * 1.1,
        atol=1e-4,
    )
    assert_almost_equal(
        Float64(state.controls.max_distance.value),
        Float64(sphere.radius) * 8,
        atol=1e-4,
    )
    tm_destroy(app)


def test_events_of_unknown_kinds_are_dropped() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    var held = _state(app)[].camera.position
    tm_event(app, Int32(UNKNOWN_KIND), Int32(1), Int32(2), Int32(3))
    tm_event(app, Int32(POINTER_DOWN), Int32(1), Int32(2), Int32(9))
    _step(app, 5)
    assert_almost_equal(
        Float64(_state(app)[].camera.position.x), Float64(held.x), atol=1e-4
    )
    assert_almost_equal(
        Float64(_state(app)[].camera.position.y), Float64(held.y), atol=1e-4
    )
    tm_destroy(app)


def test_negative_time_is_ignored() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    var held = _state(app)[].camera.position
    tm_step(app, Int32(-1000))
    assert_equal(_state(app)[].camera.position.x, held.x)
    tm_destroy(app)


def test_a_very_long_step_counts_only_a_tenth_of_a_second() raises:
    var first = _plain()
    var second = _plain()
    _state(first)[].load_geometry(_line())
    _state(second)[].load_geometry(_line())
    tm_step(first, Int32(LONGEST_MICROSECONDS))
    tm_step(second, Int32(60000000))
    assert_equal(
        _state(first)[].camera.position.x, _state(second)[].camera.position.x
    )
    assert_equal(
        _state(first)[].camera.position.z, _state(second)[].camera.position.z
    )
    tm_destroy(first)
    tm_destroy(second)


def test_the_frame_can_change_size() raises:
    var app = _loaded("v3.spz")
    assert_equal(tm_resize(app, Int32(64), Int32(36)), Int32(0))
    assert_equal(tm_width(app), Int32(64))
    assert_equal(tm_height(app), Int32(36))
    assert_equal(_state(app)[].camera.aspect, Float32(64) / Float32(36))
    assert_equal(tm_splat_prepare(app), Int32(0))
    assert_equal(
        _floats(app, SPLAT_VIEW)[unsafe_offset=VIEW_WIDTH], Float32(64)
    )
    assert_equal(_info(app, SPLAT_INFO_COUNT), 4)
    tm_destroy(app)


def test_a_size_that_is_out_of_range_leaves_the_frame_alone() raises:
    var app = _plain()
    assert_equal(tm_resize(app, Int32(0), Int32(10)), Int32(1))
    assert_equal(tm_resize(app, Int32(10), Int32(-1)), Int32(1))
    assert_equal(tm_resize(app, Int32(MAX_SIDE + 1), Int32(10)), Int32(1))
    assert_equal(tm_resize(app, Int32(10), Int32(MAX_SIDE + 1)), Int32(1))
    assert_equal(tm_width(app), Int32(WIDTH))
    assert_equal(tm_height(app), Int32(HEIGHT))
    tm_destroy(app)


def test_a_frame_that_cannot_be_drawn_is_the_last_one() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    var before = _hash(app)
    # A field of view of nothing: the camera refuses its projection.
    _state(app)[].camera.fov = Angle(0.0, DEGREE)
    assert_equal(_hash(app), before)
    tm_destroy(app)


def test_a_view_that_cannot_be_prepared_leaves_the_last_arrays() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    assert_equal(tm_splat_prepare(app), Int32(0))
    var address = Int(tm_splat_part(app, Int32(SPLAT_VIEW.value)).value())
    var generation = _info(app, SPLAT_INFO_ORDER)
    _state(app)[].camera.fov = Angle(0.0, DEGREE)
    assert_equal(tm_splat_prepare(app), Int32(1))
    assert_equal(
        Int(tm_splat_part(app, Int32(SPLAT_VIEW.value)).value()), address
    )
    assert_equal(_info(app, SPLAT_INFO_ORDER), generation)
    tm_destroy(app)


def test_a_refused_view_does_not_publish_a_new_order() raises:
    var app = _plain()
    _state(app)[].load_geometry(_line())
    assert_equal(tm_splat_prepare(app), Int32(0))
    var order = _state(app)[].order.copy()
    var view = _state(app)[].view.copy()
    var center = _state(app)[].controls.target
    _state(app)[].camera.place(
        center * 2 - _state(app)[].camera.position, center
    )
    _state(app)[].camera.fov = Angle(0.0, DEGREE)
    assert_equal(tm_splat_prepare(app), Int32(1))
    assert_equal(_info(app, SPLAT_INFO_ORDER), 1)
    assert_equal(_state(app)[].order, order)
    assert_equal(_state(app)[].view, view)
    _state(app)[].camera.fov = Angle(50.0, DEGREE)
    assert_equal(tm_splat_prepare(app), Int32(0))
    assert_equal(_info(app, SPLAT_INFO_ORDER), 2)
    assert_true(_state(app)[].order[0] != order[0])
    tm_destroy(app)


def test_a_part_that_does_not_exist_is_refused() raises:
    var app = _loaded("v3.spz")
    assert_equal(tm_splat_prepare(app), Int32(0))
    for which in [-1, SPLAT_VIEW.value + 1, 99]:
        assert_false(Bool(tm_splat_part(app, Int32(which))))
        assert_equal(_words(app, SplatPart(which)), 0)
    for which in [-1, SPLAT_INFO_ORDER.value + 1, 99]:
        assert_equal(tm_splat_info(app, Int32(which)), Int32(0))
    tm_destroy(app)


def test_a_part_and_an_info_are_valid_in_their_ranges_only() raises:
    assert_false(SplatPart(-1).is_valid())
    assert_true(SplatPart(SPLAT_CENTERS.value).is_valid())
    assert_true(SplatPart(SPLAT_VIEW.value).is_valid())
    assert_false(SplatPart(SPLAT_VIEW.value + 1).is_valid())
    assert_false(SplatInfo(-1).is_valid())
    assert_true(SplatInfo(SPLAT_INFO_COUNT.value).is_valid())
    assert_true(SplatInfo(SPLAT_INFO_ORDER.value).is_valid())
    assert_false(SplatInfo(SPLAT_INFO_ORDER.value + 1).is_valid())


def test_the_parts_are_numbered_as_the_header_numbers_them() raises:
    # window/threemojo.h lists these numbers for a host that is not in Mojo.
    var parts = [
        SPLAT_CENTERS,
        SPLAT_COVARIANCES,
        SPLAT_COLORS,
        SPLAT_SH1,
        SPLAT_SH2,
        SPLAT_SH3,
        SPLAT_ORDER,
        SPLAT_VIEW,
    ]
    for number in range(len(parts)):
        assert_equal(parts[number].value, number)
    assert_equal(SPLAT_INFO_COUNT.value, 0)
    assert_equal(SPLAT_INFO_DEGREE.value, 1)
    assert_equal(SPLAT_INFO_SCAN.value, 2)
    assert_equal(SPLAT_INFO_ORDER.value, 3)
    # The view's numbers, as the shaders read them.
    assert_equal(VIEW_MODEL_VIEW, 0)
    assert_equal(VIEW_PROJECTION, 16)
    assert_equal(VIEW_WIDTH, 32)
    assert_equal(VIEW_HEIGHT, 33)
    assert_equal(VIEW_EYE, 34)
    assert_equal(VIEW_DEGREE, 37)
    assert_equal(VIEW_COUNT, 38)
    assert_equal(VIEW_BACKGROUND, 40)
    assert_equal(SPLAT_VIEW_FLOATS, 48)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
