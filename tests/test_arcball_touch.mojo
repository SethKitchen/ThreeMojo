# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the touch input and the `start` and `end` counts of
`controls.arcball_controls`.

Every test starts from a camera five meters up +z, looking at the origin,
in a view 100 pixels square. A finger is at the center of its pixel.

One finger, a two-finger pan and three fingers are held to the mouse
operation that three.js r180 runs the same arithmetic for. The other
numbers are worked out by hand from three.js r180's `ArcballControls`:
`onRotateMove`, `onPinchMove`, `onDoublePanMove`, `zRotate`, `scale` and
`pan`. With a field of view of 90 degrees and the camera five meters
away, a place in the view is five meters times its normalized device
coordinate from the center.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.arcball_controls import (
    ArcballControls,
    ArcballInput,
    INPUT_CURSOR,
    INPUT_MULT_FINGER,
    INPUT_NONE,
    INPUT_ONE_FINGER,
    INPUT_ONE_FINGER_SWITCHED,
    INPUT_TWO_FINGER,
    MOUSE_WHEEL,
    STATE_ANIMATION_ROTATE,
    STATE_IDLE,
    STATE_PAN,
    STATE_ROTATE,
    STATE_SCALE,
    STATE_ZROTATE,
)
from controls.input import (
    InputEvent,
    InputKind,
    MIDDLE,
    NO_BUTTON,
    POINTER_CANCEL,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
    PointerId,
    SECONDARY,
    WHEEL,
    touch_event,
)
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, METER, MILLISECOND
from tests._cameras import orthographic_above

comptime TOLERANCE = Float64(1e-4)
comptime SIZE = 100
comptime FRAME = Duration(1000.0 / 60.0, MILLISECOND)
comptime HALF_ROOT = Float32(0.7071068)


def _box_scene(mut assets: Assets) raises -> Scene:
    """Return a scene with a box two meters wide at (1, 0, 0).

    Args:
        assets: Where the box and its material go.

    Returns:
        The scene.

    Raises:
        Error: If the scene is refused.
    """
    var scene = Scene()
    var geometry = assets.geometries.add(cube(Length(2.0, METER)))
    var material = assets.materials.add(Material(Color(255, 255, 255)))
    var node = Object3D()
    node.set_position(1, 0, 0)
    var id = scene.add(node^)
    scene.update()
    scene.add_mesh(Mesh(geometry, material, id))
    return scene^


struct Rig(Movable):
    """A perspective camera, its controls, and a scene with a box two
    meters wide at (1, 0, 0)."""

    var camera: PerspectiveCamera
    var controls: ArcballControls
    var scene: Scene
    var assets: Assets

    def __init__(out self, fov: Float64 = 90) raises:
        """Create the rig.

        Args:
            fov: The camera's field of view, in degrees.

        Raises:
            Error: If anything is refused.
        """
        self.camera = PerspectiveCamera(
            Angle(Float32(fov), DEGREE),
            1.0,
            Length(0.1, METER),
            Length(100.0, METER),
        )
        self.camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
        self.controls = ArcballControls(self.camera)
        self.assets = Assets()
        self.scene = _box_scene(self.assets)

    def finger(mut self, kind: InputKind, id: Int, x: Int, y: Int) raises:
        """Hand the controls one finger's event.

        Args:
            kind: What the finger did.
            id: The finger's pointer id.
            x: The pixel's column.
            y: The pixel's row.

        Raises:
            Error: If the event is refused.
        """
        self.controls.handle(
            touch_event(kind, PointerId(id), x, y),
            self.camera,
            self.scene,
            self.assets,
            SIZE,
            SIZE,
        )

    def mouse(
        mut self,
        kind: InputKind,
        x: Int,
        y: Int,
        button: PointerButton = PRIMARY,
        *,
        shift: Bool = False,
        ctrl: Bool = False,
        wheel: Int = 0,
    ) raises:
        """Hand the controls one event of the mouse.

        Args:
            kind: What happened.
            x: The pixel's column.
            y: The pixel's row.
            button: The button.
            shift: Whether Shift is held.
            ctrl: Whether Ctrl is held.
            wheel: The wheel's notches.

        Raises:
            Error: If the event is refused.
        """
        self.controls.handle(
            InputEvent(
                kind,
                button=button,
                x=x,
                y=y,
                shift=shift,
                ctrl=ctrl,
                wheel=wheel,
            ),
            self.camera,
            self.scene,
            self.assets,
            SIZE,
            SIZE,
        )

    def pinch(mut self) raises:
        """Put finger 1 at (40, 50) and finger 2 at (60, 50).

        Raises:
            Error: If an event is refused.
        """
        self.finger(POINTER_DOWN, 1, 40, 50)
        self.finger(POINTER_DOWN, 2, 60, 50)

    def frame(mut self, delta: Duration = FRAME) raises -> Bool:
        """Run one frame.

        Args:
            delta: How long it took.

        Returns:
            What `update` returns.

        Raises:
            Error: If `update` refuses.
        """
        return self.controls.update(self.camera, delta)


struct OrthoRig(Movable):
    """An orthographic camera ten meters square, its controls, and the box
    scene."""

    var camera: OrthographicCamera
    var controls: ArcballControls
    var scene: Scene
    var assets: Assets

    def __init__(out self) raises:
        """Create the rig.

        Raises:
            Error: If anything is refused.
        """
        self.camera = orthographic_above()
        self.controls = ArcballControls(self.camera)
        self.assets = Assets()
        self.scene = _box_scene(self.assets)

    def finger(mut self, kind: InputKind, id: Int, x: Int, y: Int) raises:
        """Hand the controls one finger's event.

        Args:
            kind: What the finger did.
            id: The finger's pointer id.
            x: The pixel's column.
            y: The pixel's row.

        Raises:
            Error: If the event is refused.
        """
        self.controls.handle(
            touch_event(kind, PointerId(id), x, y),
            self.camera,
            self.scene,
            self.assets,
            SIZE,
            SIZE,
        )

    def mouse(
        mut self,
        kind: InputKind,
        x: Int,
        y: Int,
        button: PointerButton = PRIMARY,
    ) raises:
        """Hand the controls one event of the mouse.

        Args:
            kind: What happened.
            x: The pixel's column.
            y: The pixel's row.
            button: The button.

        Raises:
            Error: If the event is refused.
        """
        self.controls.handle(
            InputEvent(kind, button=button, x=x, y=y),
            self.camera,
            self.scene,
            self.assets,
            SIZE,
            SIZE,
        )


def _near(actual: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a vector's components.

    Args:
        actual: The vector.
        x: The expected x.
        y: The expected y.
        z: The expected z.

    Raises:
        Error: If a component differs.
    """
    assert_almost_equal(actual.x, x, atol=TOLERANCE)
    assert_almost_equal(actual.y, y, atol=TOLERANCE)
    assert_almost_equal(actual.z, z, atol=TOLERANCE)


def _same(actual: Vector3, expected: Vector3) raises:
    """Assert that two vectors agree.

    Args:
        actual: The vector.
        expected: The vector it must equal.

    Raises:
        Error: If a component differs.
    """
    _near(actual, expected.x, expected.y, expected.z)


def _only(mut rig: Rig, *, pan: Bool, rotate: Bool, zoom: Bool):
    """Turn the three operations on or off.

    Args:
        rig: The rig.
        pan: Whether a pan is on.
        rotate: Whether a turn is on.
        zoom: Whether a zoom is on.
    """
    rig.controls.enable_pan = pan
    rig.controls.enable_rotate = rotate
    rig.controls.enable_zoom = zoom


# --- the types ---------------------------------------------------------------


def test_the_input_and_the_new_state_know_their_values() raises:
    assert_true(INPUT_NONE.is_valid())
    assert_true(INPUT_CURSOR.is_valid())
    assert_false(ArcballInput(-1).is_valid())
    assert_false(ArcballInput(6).is_valid())
    assert_true(STATE_ZROTATE.is_valid())
    var rig = Rig()
    assert_true(rig.controls.input() == INPUT_NONE)
    assert_equal(rig.controls.take_starts(), 0)
    assert_equal(rig.controls.take_ends(), 0)


# --- one finger --------------------------------------------------------------


def test_one_finger_turns_as_the_primary_button_does() raises:
    var rig = Rig()
    var mouse = Rig()
    _ = rig.frame()
    _ = mouse.frame()
    rig.finger(POINTER_DOWN, 1, 50, 50)
    mouse.mouse(POINTER_DOWN, 50, 50)
    assert_true(rig.controls.input() == INPUT_ONE_FINGER)
    assert_true(mouse.controls.input() == INPUT_CURSOR)
    assert_true(rig.controls.state() == STATE_ROTATE)
    _ = rig.frame()
    _ = mouse.frame()
    rig.finger(POINTER_MOVE, 1, 55, 50)
    mouse.mouse(POINTER_MOVE, 55, 50)
    _ = rig.frame()
    _ = mouse.frame()
    rig.finger(POINTER_MOVE, 1, 60, 50)
    mouse.mouse(POINTER_MOVE, 60, 50)
    # The numbers three.js gives this drag of the primary button.
    _near(rig.camera.position, -0.498430, 0.000531, 4.975095)
    _same(rig.camera.position, mouse.camera.position)
    rig.finger(POINTER_UP, 1, 60, 50)
    mouse.mouse(POINTER_UP, 60, 50)
    assert_true(rig.controls.input() == INPUT_NONE)
    # The turn goes on after the finger lifts, as after a release.
    _ = rig.frame()
    _ = mouse.frame()
    assert_true(rig.controls.state() == STATE_ANIMATION_ROTATE)
    _ = rig.frame()
    _ = mouse.frame()
    _same(rig.camera.position, mouse.camera.position)
    _same(rig.camera.up, mouse.camera.up)
    assert_equal(rig.controls.take_starts(), 1)
    assert_equal(rig.controls.take_ends(), 1)


# --- two fingers -------------------------------------------------------------


def test_a_pinch_zooms_by_the_distance_between_two_fingers() raises:
    var rig = Rig()
    _only(rig, pan=False, rotate=False, zoom=True)
    rig.pinch()
    assert_true(rig.controls.input() == INPUT_TWO_FINGER)
    assert_true(rig.controls.state() == STATE_SCALE)
    # Twice as far apart is half the distance.
    rig.finger(POINTER_MOVE, 2, 80, 50)
    _near(rig.camera.position, 0, 0, 2.5)
    _near(rig.controls.center(), 0, 0, 0)
    assert_true(rig.frame())
    # Back to 20 apart, then to 10: fingers nearer than 12 pixels count
    # as 12 apart, so the distance is 5 * 20 / 12.
    rig.finger(POINTER_MOVE, 2, 60, 50)
    _near(rig.camera.position, 0, 0, 5)
    rig.finger(POINTER_MOVE, 2, 50, 50)
    _near(rig.camera.position, 0, 0, Float32(5) * 20 / 12)


def test_two_fingers_turn_the_camera_about_the_view_axis() raises:
    var rig = Rig()
    _only(rig, pan=False, rotate=True, zoom=False)
    rig.pinch()
    assert_true(rig.controls.state() == STATE_ZROTATE)
    # With no pan and no zoom, the gizmo is bright during the turn.
    assert_almost_equal(rig.controls.gizmo_opacity(), 1, atol=TOLERANCE)
    # The line between the fingers turns an eighth of a turn clockwise on
    # the view, and the camera rolls the other way about its view axis.
    rig.finger(POINTER_MOVE, 1, 50, 40)
    _near(rig.camera.position, 0, 0, 5)
    _near(rig.camera.up, -HALF_ROOT, HALF_ROOT, 0)
    # A quarter of a turn in all.
    rig.finger(POINTER_MOVE, 2, 50, 60)
    _near(rig.camera.position, 0, 0, 5)
    _near(rig.camera.up, -1, 0, 0)
    _near(rig.controls.center(), 0, 0, 0)
    rig.finger(POINTER_UP, 2, 50, 60)
    assert_true(rig.controls.state() == STATE_IDLE)
    assert_true(rig.controls.input() == INPUT_ONE_FINGER_SWITCHED)
    assert_almost_equal(rig.controls.gizmo_opacity(), 0.6, atol=TOLERANCE)
    # `update` keeps the up the turn gave.
    _ = rig.frame()
    _near(rig.camera.up, -1, 0, 0)


def test_a_two_finger_pan_is_the_pan_of_the_secondary_button() raises:
    var rig = Rig()
    var mouse = Rig()
    _only(rig, pan=True, rotate=False, zoom=False)
    rig.pinch()
    assert_true(rig.controls.state() == STATE_PAN)
    mouse.mouse(POINTER_DOWN, 50, 50, SECONDARY)
    # Both fingers go ten right and ten down, one after the other.
    rig.finger(POINTER_MOVE, 1, 50, 60)
    rig.finger(POINTER_MOVE, 2, 70, 60)
    mouse.mouse(POINTER_MOVE, 60, 60, SECONDARY)
    _same(rig.camera.position, mouse.camera.position)
    _same(rig.controls.center(), mouse.controls.center())
    # The point under the midpoint follows it: a tenth of the view is a
    # meter at five meters.
    _near(rig.controls.center(), -1, 1, 0)


def test_a_two_finger_pan_keeps_its_speed_after_a_zoom() raises:
    # three.js reads the pan at the distance the controls began at, and
    # scales the move to the distance now.
    var rig = Rig()
    var mouse = Rig()
    rig.mouse(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    mouse.mouse(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    _only(rig, pan=True, rotate=False, zoom=False)
    rig.pinch()
    mouse.mouse(POINTER_DOWN, 50, 50, SECONDARY)
    rig.finger(POINTER_MOVE, 1, 50, 60)
    rig.finger(POINTER_MOVE, 2, 70, 60)
    mouse.mouse(POINTER_MOVE, 60, 60, SECONDARY)
    assert_true(rig.camera.position.z < 5)
    _same(rig.camera.position, mouse.camera.position)
    _same(rig.controls.center(), mouse.controls.center())


def test_a_pinch_with_a_pan_zooms_toward_the_point_between_the_fingers() raises:
    var rig = Rig()
    _only(rig, pan=True, rotate=False, zoom=True)
    rig.pinch()
    # Finger 2 goes 20 right. The fingers are twice as far apart, and
    # the point between them is at 0.21 across the view: 1.05 meters
    # right of the center. The zoom halves the camera's offset from that
    # point, to (0.525, -0.025, 2.5). The pan then moves the camera by
    # the meter the midpoint went at five meters, halved for the distance
    # now, the other way.
    rig.finger(POINTER_MOVE, 2, 80, 50)
    _near(rig.camera.position, 0.025, -0.025, 2.5)
    _near(rig.controls.center(), 0.025, -0.025, 0)
    assert_true(rig.controls.state() == STATE_PAN)


def test_a_turn_with_a_pan_is_about_the_point_between_the_fingers() raises:
    var rig = Rig()
    _only(rig, pan=True, rotate=True, zoom=False)
    rig.pinch()
    # Finger 1 goes to (50, 40). The point between the fingers is at
    # (0.11, 0.09) of the view: (0.55, 0.45) meters. The camera turns an
    # eighth of a turn about the view axis through that point. Then the
    # pan moves it by (-0.5, -0.5) meters in its own turned axes.
    rig.finger(POINTER_MOVE, 1, 50, 40)
    _near(rig.camera.up, -HALF_ROOT, HALF_ROOT, 0)
    _near(rig.camera.position, 0.479289, -0.964214, 5)
    _near(rig.controls.center(), 0.479289, -0.964214, 0)


def test_a_pinch_and_a_turn_take_turns_on_each_move() raises:
    var rig = Rig()
    _only(rig, pan=False, rotate=True, zoom=True)
    rig.pinch()
    # The fingers stay on one line, so the turn is nothing. Each move
    # starts the pinch again from the last distance: 20 to 40, then 40 to
    # 60.
    rig.finger(POINTER_MOVE, 2, 80, 50)
    _near(rig.camera.position, 0, 0, 2.5)
    rig.finger(POINTER_MOVE, 2, 100, 50)
    _near(rig.camera.position, 0, 0, Float32(5) / 3)
    _near(rig.camera.up, 0, 1, 0)


def test_two_fingers_send_start_and_end_for_each_operation() raises:
    var rig = Rig()
    rig.pinch()
    # One for the finger, then a turn, a pinch and a pan.
    assert_equal(rig.controls.take_starts(), 4)
    assert_equal(rig.controls.take_ends(), 0)
    rig.finger(POINTER_MOVE, 2, 70, 60)
    assert_true(rig.frame())
    rig.finger(POINTER_UP, 2, 70, 60)
    assert_equal(rig.controls.take_ends(), 3)
    rig.finger(POINTER_UP, 1, 40, 50)
    assert_equal(rig.controls.take_ends(), 1)
    assert_equal(rig.controls.take_starts(), 0)
    assert_true(rig.controls.input() == INPUT_NONE)


def test_a_pinch_from_one_pixel_does_not_zoom() raises:
    # three.js divides by the distance the pinch began at.
    var rig = Rig()
    _only(rig, pan=False, rotate=False, zoom=True)
    rig.finger(POINTER_DOWN, 1, 50, 50)
    rig.finger(POINTER_DOWN, 2, 50, 50)
    rig.finger(POINTER_MOVE, 2, 90, 50)
    _near(rig.camera.position, 0, 0, 5)


def test_the_finger_left_of_two_turns_after_it_moves_far_enough() raises:
    var rig = Rig()
    var mouse = Rig()
    rig.controls.enable_animations = False
    mouse.controls.enable_animations = False
    rig.pinch()
    rig.finger(POINTER_UP, 2, 60, 50)
    assert_true(rig.controls.input() == INPUT_ONE_FINGER_SWITCHED)
    # Less than 32 pixels from where it was: nothing.
    rig.finger(POINTER_MOVE, 1, 60, 50)
    assert_true(rig.controls.input() == INPUT_ONE_FINGER_SWITCHED)
    _near(rig.camera.position, 0, 0, 5)
    # 32 pixels: a turn starts there.
    rig.finger(POINTER_MOVE, 1, 72, 50)
    assert_true(rig.controls.input() == INPUT_ONE_FINGER)
    assert_true(rig.controls.state() == STATE_ROTATE)
    _near(rig.camera.position, 0, 0, 5)
    rig.finger(POINTER_MOVE, 1, 82, 50)
    mouse.mouse(POINTER_DOWN, 72, 50)
    mouse.mouse(POINTER_MOVE, 82, 50)
    _same(rig.camera.position, mouse.camera.position)
    # A second finger makes two again.
    rig.finger(POINTER_UP, 1, 82, 50)
    rig.pinch()
    rig.finger(POINTER_UP, 1, 40, 50)
    rig.finger(POINTER_DOWN, 3, 20, 50)
    assert_true(rig.controls.input() == INPUT_TWO_FINGER)
    rig.finger(POINTER_UP, 3, 20, 50)
    rig.finger(POINTER_UP, 2, 60, 50)
    assert_true(rig.controls.input() == INPUT_NONE)


# --- three fingers -----------------------------------------------------------


def test_three_fingers_change_the_field_of_view_as_shift_and_a_drag_do() raises:
    var rig = Rig(60)
    var mouse = Rig(60)
    rig.finger(POINTER_DOWN, 1, 40, 50)
    rig.finger(POINTER_DOWN, 2, 50, 50)
    rig.finger(POINTER_DOWN, 3, 60, 50)
    assert_true(rig.controls.input() == INPUT_MULT_FINGER)
    assert_true(rig.controls.state() == STATE_SCALE)
    mouse.mouse(POINTER_DOWN, 50, 50, MIDDLE, shift=True)
    # The mean of the fingers goes 20 pixels up.
    rig.finger(POINTER_MOVE, 1, 40, 30)
    rig.finger(POINTER_MOVE, 2, 50, 30)
    rig.finger(POINTER_MOVE, 3, 60, 30)
    mouse.mouse(POINTER_MOVE, 50, 30, MIDDLE, shift=True)
    # The numbers three.js gives that drag.
    _near(rig.camera.position, 0, 0, 4.292810)
    assert_almost_equal(rig.camera.fov.to(DEGREE), 67.838655, atol=1e-3)
    _same(rig.camera.position, mouse.camera.position)
    # A fourth finger joins the mean: 20 pixels up from the start again.
    rig.finger(POINTER_DOWN, 4, 50, 30)
    rig.finger(POINTER_MOVE, 4, 50, 30)
    _near(rig.camera.position, 0, 0, 4.292810)
    # The operation ends when the last finger lifts.
    rig.finger(POINTER_UP, 1, 40, 30)
    rig.finger(POINTER_UP, 2, 50, 30)
    rig.finger(POINTER_UP, 3, 60, 30)
    assert_true(rig.controls.input() == INPUT_MULT_FINGER)
    assert_true(rig.controls.state() == STATE_SCALE)
    rig.finger(POINTER_UP, 4, 50, 30)
    assert_true(rig.controls.input() == INPUT_NONE)
    assert_true(rig.controls.state() == STATE_IDLE)
    # A finger, three two-finger operations and the three-finger one.
    assert_equal(rig.controls.take_starts(), 5)
    assert_equal(rig.controls.take_ends(), 1)


# --- an orthographic camera --------------------------------------------------


def test_two_fingers_move_an_orthographic_camera() raises:
    var rig = OrthoRig()
    var mouse = OrthoRig()
    rig.controls.enable_rotate = False
    rig.controls.enable_zoom = False
    rig.finger(POINTER_DOWN, 1, 40, 50)
    rig.finger(POINTER_DOWN, 2, 60, 50)
    mouse.mouse(POINTER_DOWN, 50, 50, SECONDARY)
    rig.finger(POINTER_MOVE, 1, 50, 60)
    rig.finger(POINTER_MOVE, 2, 70, 60)
    mouse.mouse(POINTER_MOVE, 60, 60, SECONDARY)
    _same(rig.camera.position, mouse.camera.position)
    _near(rig.controls.center(), -1, 1, 0)
    rig.finger(POINTER_UP, 1, 50, 60)
    rig.finger(POINTER_UP, 2, 70, 60)
    # A pinch changes the zoom.
    rig.controls.enable_pan = False
    rig.controls.enable_zoom = True
    rig.finger(POINTER_DOWN, 1, 40, 50)
    rig.finger(POINTER_DOWN, 2, 60, 50)
    rig.finger(POINTER_MOVE, 2, 80, 50)
    assert_almost_equal(rig.camera.zoom, Float32(2), atol=TOLERANCE)


def test_three_fingers_do_nothing_to_an_orthographic_camera() raises:
    # three.js works out a field of view that the camera does not have,
    # and zooms by what it gives.
    var rig = OrthoRig()
    rig.finger(POINTER_DOWN, 1, 40, 50)
    rig.finger(POINTER_DOWN, 2, 50, 50)
    rig.finger(POINTER_DOWN, 3, 60, 50)
    rig.finger(POINTER_MOVE, 2, 50, 20)
    assert_almost_equal(rig.camera.zoom, Float32(1), atol=TOLERANCE)
    _near(rig.camera.position, 0, 0, 5)


# --- taps --------------------------------------------------------------------


def test_two_taps_of_a_finger_are_a_double_click() raises:
    var rig = Rig()
    rig.controls.enable_animations = False
    rig.finger(POINTER_DOWN, 1, 60, 50)
    rig.finger(POINTER_UP, 1, 60, 50)
    _ = rig.frame()
    rig.finger(POINTER_DOWN, 1, 60, 50)
    rig.finger(POINTER_UP, 1, 60, 50)
    # The numbers three.js gives the same double click of the mouse.
    _near(rig.camera.position, 0.84, -0.04, 5.545455)
    _near(rig.controls.center(), 0.84, -0.04, 1)
    # Two presses and the focus started. Two releases and the focus ended.
    assert_equal(rig.controls.take_starts(), 3)
    assert_equal(rig.controls.take_ends(), 3)


def test_a_tap_of_a_second_finger_is_no_click() raises:
    var rig = Rig()
    rig.controls.enable_animations = False
    rig.finger(POINTER_DOWN, 1, 10, 10)
    rig.finger(POINTER_DOWN, 2, 60, 50)
    rig.finger(POINTER_UP, 2, 60, 50)
    rig.finger(POINTER_DOWN, 2, 60, 50)
    rig.finger(POINTER_UP, 2, 60, 50)
    _near(rig.controls.center(), 0, 0, 0)
    # The first finger lifts, and a new first finger taps twice.
    rig.finger(POINTER_UP, 1, 10, 10)
    rig.finger(POINTER_DOWN, 2, 60, 50)
    rig.finger(POINTER_UP, 2, 60, 50)
    rig.finger(POINTER_DOWN, 2, 60, 50)
    rig.finger(POINTER_UP, 2, 60, 50)
    _near(rig.controls.center(), 0.84, -0.04, 1)


def test_the_first_finger_is_not_first_again_while_others_are_down() raises:
    var rig = Rig()
    rig.controls.enable_animations = False
    rig.finger(POINTER_DOWN, 1, 60, 50)
    rig.finger(POINTER_DOWN, 2, 10, 10)
    rig.finger(POINTER_UP, 1, 60, 50)
    # Finger 1 again, with finger 2 still down: not the first finger.
    rig.finger(POINTER_DOWN, 1, 60, 50)
    rig.finger(POINTER_UP, 1, 60, 50)
    rig.finger(POINTER_DOWN, 1, 60, 50)
    rig.finger(POINTER_UP, 1, 60, 50)
    _near(rig.controls.center(), 0, 0, 0)


# --- the mouse and fingers together -------------------------------------------


def test_fingers_wait_while_a_mouse_button_holds_the_controls() raises:
    var rig = Rig()
    rig.mouse(POINTER_DOWN, 50, 50, SECONDARY)
    rig.finger(POINTER_DOWN, 1, 20, 20)
    rig.finger(POINTER_MOVE, 1, 80, 80)
    rig.finger(POINTER_UP, 1, 80, 80)
    assert_true(rig.controls.input() == INPUT_CURSOR)
    _near(rig.camera.position, 0, 0, 5)
    rig.mouse(POINTER_UP, 50, 50, SECONDARY)
    assert_true(rig.controls.input() == INPUT_NONE)


def test_the_mouse_waits_while_a_finger_holds_the_controls() raises:
    var rig = Rig()
    rig.controls.enable_animations = False
    rig.finger(POINTER_DOWN, 1, 50, 50)
    rig.mouse(POINTER_DOWN, 20, 20, SECONDARY)
    rig.mouse(POINTER_MOVE, 80, 80, SECONDARY)
    rig.mouse(POINTER_UP, 80, 80, SECONDARY)
    assert_true(rig.controls.input() == INPUT_ONE_FINGER)
    _near(rig.camera.position, 0, 0, 5)
    rig.finger(POINTER_UP, 1, 50, 50)


def test_a_release_with_no_press_to_measure_counts_no_click() raises:
    # three.js reads a press that it does not have in each of these.
    var rig = Rig()
    rig.controls.enable_animations = False
    rig.mouse(POINTER_DOWN, 10, 10, SECONDARY)
    # Two taps of a finger, a double click, leave no press behind.
    rig.finger(POINTER_DOWN, 1, 60, 50)
    rig.finger(POINTER_UP, 1, 60, 50)
    rig.finger(POINTER_DOWN, 1, 60, 50)
    rig.finger(POINTER_UP, 1, 60, 50)
    rig.mouse(POINTER_MOVE, 10, 10, SECONDARY)
    rig.mouse(POINTER_UP, 10, 10, SECONDARY)
    assert_true(rig.controls.input() == INPUT_NONE)
    # One tap of a finger leaves one press, and a release of the mouse
    # then has no second one.
    rig = Rig()
    rig.mouse(POINTER_DOWN, 10, 10, SECONDARY)
    rig.finger(POINTER_DOWN, 1, 60, 50)
    rig.finger(POINTER_UP, 1, 60, 50)
    rig.mouse(POINTER_UP, 10, 10, SECONDARY)
    _near(rig.controls.center(), 0, 0, 0)


# --- cancel --------------------------------------------------------------------


def test_a_cancel_lets_every_finger_go_and_ends_nothing() raises:
    var rig = Rig()
    rig.pinch()
    _ = rig.controls.take_starts()
    rig.finger(POINTER_CANCEL, 1, 40, 50)
    assert_true(rig.controls.input() == INPUT_NONE)
    assert_equal(rig.controls.take_ends(), 0)
    # The other finger is no longer followed.
    rig.finger(POINTER_MOVE, 2, 90, 90)
    rig.finger(POINTER_UP, 2, 90, 90)
    _near(rig.camera.position, 0, 0, 5)
    # A new finger starts again.
    rig.finger(POINTER_DOWN, 3, 50, 50)
    assert_true(rig.controls.input() == INPUT_ONE_FINGER)
    rig.finger(POINTER_UP, 3, 50, 50)
    # A canceled mouse lets its button go.
    rig.mouse(POINTER_DOWN, 50, 50)
    rig.controls.handle(
        InputEvent(POINTER_CANCEL),
        rig.camera,
        rig.scene,
        rig.assets,
        SIZE,
        SIZE,
    )
    assert_true(rig.controls.input() == INPUT_NONE)


# --- operations turned off -----------------------------------------------------


def test_disabled_controls_follow_fingers_and_move_nothing() raises:
    var rig = Rig()
    rig.controls.enabled = False
    rig.pinch()
    rig.finger(POINTER_MOVE, 2, 90, 80)
    rig.finger(POINTER_DOWN, 3, 50, 50)
    rig.finger(POINTER_MOVE, 3, 50, 10)
    assert_true(rig.controls.input() == INPUT_MULT_FINGER)
    _near(rig.camera.position, 0, 0, 5)
    assert_equal(rig.controls.take_starts(), 0)
    assert_false(rig.frame())


def test_each_two_finger_operation_can_be_off() raises:
    var rig = Rig()
    _only(rig, pan=False, rotate=False, zoom=False)
    rig.pinch()
    rig.finger(POINTER_MOVE, 2, 90, 80)
    rig.finger(POINTER_DOWN, 3, 50, 50)
    rig.finger(POINTER_MOVE, 3, 50, 10)
    _near(rig.camera.position, 0, 0, 5)
    _near(rig.camera.up, 0, 1, 0)
    # A finger still starts, though its turn is off.
    assert_equal(rig.controls.take_starts(), 1)
    # A turn with a zoom on, or a pan on, leaves the gizmo dim.
    rig = Rig()
    _only(rig, pan=False, rotate=True, zoom=True)
    rig.pinch()
    assert_almost_equal(rig.controls.gizmo_opacity(), 0.6, atol=TOLERANCE)
    rig = Rig()
    _only(rig, pan=True, rotate=True, zoom=False)
    rig.pinch()
    assert_almost_equal(rig.controls.gizmo_opacity(), 0.6, atol=TOLERANCE)


# --- start and end for the mouse -------------------------------------------------


def test_the_mouse_sends_start_and_end() raises:
    var rig = Rig()
    rig.controls.enable_animations = False
    rig.mouse(POINTER_DOWN, 50, 50, SECONDARY)
    rig.mouse(POINTER_MOVE, 60, 50, SECONDARY)
    rig.mouse(POINTER_UP, 60, 50, SECONDARY)
    assert_equal(rig.controls.take_starts(), 1)
    assert_equal(rig.controls.take_ends(), 1)
    # A wheel notch is an operation of its own.
    rig.mouse(WHEEL, 50, 50, NO_BUTTON, wheel=1)
    rig.mouse(WHEEL, 50, 50, NO_BUTTON, shift=True, wheel=1)
    assert_equal(rig.controls.take_starts(), 2)
    assert_equal(rig.controls.take_ends(), 2)
    # A wheel with no action sends nothing.
    _ = rig.controls.unset_mouse_action(MOUSE_WHEEL)
    rig.mouse(WHEEL, 50, 50, NO_BUTTON, wheel=1)
    assert_equal(rig.controls.take_starts(), 0)
    assert_equal(rig.controls.take_ends(), 0)


def test_a_change_of_operation_in_a_drag_ends_one_and_starts_another() raises:
    var rig = Rig()
    rig.controls.enable_animations = False
    rig.mouse(POINTER_DOWN, 50, 50)
    # Ctrl makes the primary button pan, and letting it go turns again.
    rig.mouse(POINTER_MOVE, 55, 50, ctrl=True)
    rig.mouse(POINTER_MOVE, 60, 50)
    rig.mouse(POINTER_UP, 60, 50)
    assert_equal(rig.controls.take_starts(), 3)
    assert_equal(rig.controls.take_ends(), 3)
    # The middle button zooms, and with Shift changes the field of view.
    rig.mouse(POINTER_DOWN, 50, 50, MIDDLE)
    rig.mouse(POINTER_MOVE, 50, 55, MIDDLE, shift=True)
    rig.mouse(POINTER_MOVE, 50, 60, MIDDLE)
    rig.mouse(POINTER_UP, 50, 60, MIDDLE)
    assert_equal(rig.controls.take_starts(), 3)
    assert_equal(rig.controls.take_ends(), 3)


def test_a_turn_turned_off_in_a_drag_sends_no_end() raises:
    # three.js's `onSinglePanEnd` returns before it sends `end`.
    var rig = Rig()
    rig.mouse(POINTER_DOWN, 50, 50)
    rig.controls.enable_rotate = False
    rig.mouse(POINTER_UP, 50, 50)
    assert_equal(rig.controls.take_starts(), 1)
    assert_equal(rig.controls.take_ends(), 0)


def test_a_double_click_sends_end_even_with_focus_off() raises:
    var rig = Rig()
    rig.controls.enable_animations = False
    rig.controls.enable_focus = False
    rig.mouse(POINTER_DOWN, 60, 50)
    rig.mouse(POINTER_UP, 60, 50)
    rig.mouse(POINTER_DOWN, 60, 50)
    rig.mouse(POINTER_UP, 60, 50)
    _near(rig.controls.center(), 0, 0, 0)
    # Two presses, and no focus. Two releases, and the double click.
    assert_equal(rig.controls.take_starts(), 2)
    assert_equal(rig.controls.take_ends(), 3)


def test_fingers_that_are_not_followed_change_nothing() raises:
    var rig = Rig()
    rig.controls.enable_animations = False
    # A release with no finger down.
    rig.finger(POINTER_UP, 4, 50, 50)
    assert_true(rig.controls.input() == INPUT_NONE)
    # A move and a release of a finger the controls do not follow, while
    # they follow another.
    rig.finger(POINTER_DOWN, 1, 50, 50)
    rig.finger(POINTER_MOVE, 9, 60, 50)
    rig.finger(POINTER_DOWN, 2, 70, 50)
    rig.finger(POINTER_UP, 9, 60, 50)
    # three.js ends the two-finger operations at any finger's release.
    assert_true(rig.controls.input() == INPUT_ONE_FINGER_SWITCHED)


def test_an_invalid_pointer_is_refused() raises:
    var rig = Rig()
    with assert_raises(contains="pointer id"):
        rig.finger(POINTER_DOWN, -1, 50, 50)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
