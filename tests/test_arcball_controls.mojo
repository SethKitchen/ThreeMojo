# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `controls.arcball_controls`.

The expected numbers come from three.js r180's own `ArcballControls`, run
headless in Node with the same camera, a view 100 pixels square, and the
same input. A pointer is at the center of its pixel, a wheel notch is a
`deltaY` of 100 pixels, and `performance.now` and
`requestAnimationFrame` follow the frames the tests run.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.arcball_controls import (
    ArcballControls,
    ArcballModifier,
    ArcballMouse,
    ArcballOperation,
    ArcballSnapshot,
    ArcballState,
    CTRL_MODIFIER,
    FOV_OPERATION,
    MOUSE_MIDDLE,
    MOUSE_PRIMARY,
    MOUSE_SECONDARY,
    MOUSE_WHEEL,
    NO_MODIFIER,
    NO_OPERATION,
    PAN_OPERATION,
    ROTATE_OPERATION,
    SHIFT_MODIFIER,
    STATE_ANIMATION_FOCUS,
    STATE_ANIMATION_ROTATE,
    STATE_FOV,
    STATE_IDLE,
    STATE_PAN,
    STATE_ROTATE,
    STATE_SCALE,
    ZOOM_OPERATION,
)
from controls.input import (
    InputEvent,
    InputKind,
    KEY_DOWN,
    Key,
    MIDDLE,
    NO_BUTTON,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
    RESIZE,
    SECONDARY,
    WHEEL,
)
from core.assets import Assets
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from helpers.segments import Segments
from materials.material import Material
from math.vector3 import Vector3
from objects.line import Line, SEGMENTS
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Angle,
    AngularAcceleration,
    AngularVelocity,
    DEGREE,
    Duration,
    Length,
    METER,
    MILLISECOND,
    RADIAN_PER_SECOND,
    RADIAN_PER_SECOND_SQUARED,
    SECOND,
)

comptime TOLERANCE = Float64(1e-4)
comptime SIZE = 100
comptime FRAME = Duration(1000.0 / 60.0, MILLISECOND)


def _perspective(fov: Float64 = 90) raises -> PerspectiveCamera:
    """Return a camera five meters up +z, looking at the origin.

    Args:
        fov: The vertical field of view, in degrees.

    Returns:
        The camera.

    Raises:
        Error: If the camera is refused.
    """
    var camera = PerspectiveCamera(
        Angle(Float32(fov), DEGREE),
        1.0,
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera


def _orthographic() raises -> OrthographicCamera:
    """Return an orthographic camera ten meters square, five up +z.

    Returns:
        The camera.

    Raises:
        Error: If its volume is refused.
    """
    var camera = OrthographicCamera(
        Length(-5.0, METER),
        Length(5.0, METER),
        Length(5.0, METER),
        Length(-5.0, METER),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera^


def _event(
    kind: InputKind,
    x: Int,
    y: Int,
    button: PointerButton = PRIMARY,
    *,
    shift: Bool = False,
    ctrl: Bool = False,
    wheel: Int = 0,
) -> InputEvent:
    """Return a pointer event.

    Args:
        kind: What happened.
        x: The pixel's column.
        y: The pixel's row.
        button: The button.
        shift: Whether Shift is held.
        ctrl: Whether Ctrl is held.
        wheel: The wheel's notches.

    Returns:
        The event.
    """
    return InputEvent(
        kind, button=button, x=x, y=y, shift=shift, ctrl=ctrl, wheel=wheel
    )


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
        self.camera = _perspective(fov)
        self.controls = ArcballControls(self.camera)
        self.assets = Assets()
        self.scene = _box_scene(self.assets)

    def send(
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
        """Hand the controls one event.

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
            _event(kind, x, y, button, shift=shift, ctrl=ctrl, wheel=wheel),
            self.camera,
            self.scene,
            self.assets,
            SIZE,
            SIZE,
        )

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
    """An orthographic camera, its controls, and the box scene."""

    var camera: OrthographicCamera
    var controls: ArcballControls
    var scene: Scene
    var assets: Assets

    def __init__(out self) raises:
        """Create the rig.

        Raises:
            Error: If anything is refused.
        """
        self.camera = _orthographic()
        self.controls = ArcballControls(self.camera)
        self.assets = Assets()
        self.scene = _box_scene(self.assets)

    def send(
        mut self,
        kind: InputKind,
        x: Int,
        y: Int,
        button: PointerButton = PRIMARY,
        *,
        shift: Bool = False,
        wheel: Int = 0,
    ) raises:
        """Hand the controls one event.

        Args:
            kind: What happened.
            x: The pixel's column.
            y: The pixel's row.
            button: The button.
            shift: Whether Shift is held.
            wheel: The wheel's notches.

        Raises:
            Error: If the event is refused.
        """
        self.controls.handle(
            _event(kind, x, y, button, shift=shift, wheel=wheel),
            self.camera,
            self.scene,
            self.assets,
            SIZE,
            SIZE,
        )

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


def _pose(
    camera: PerspectiveCamera,
    position: Vector3,
    forward: Vector3,
    up: Vector3,
) raises:
    """Assert a perspective camera's position, direction and up.

    Args:
        camera: The camera.
        position: The expected position.
        forward: The expected unit direction it looks in.
        up: The expected up: its own y axis.

    Raises:
        Error: If one differs.
    """
    _near(camera.position, position.x, position.y, position.z)
    var ahead = camera.target - camera.position
    ahead.normalize()
    _near(ahead, forward.x, forward.y, forward.z)
    _near(camera.up, up.x, up.y, up.z)


def _pose(
    camera: OrthographicCamera,
    position: Vector3,
    forward: Vector3,
    up: Vector3,
) raises:
    """Assert an orthographic camera's position, direction and up.

    Args:
        camera: The camera.
        position: The expected position.
        forward: The expected unit direction it looks in.
        up: The expected up: its own y axis.

    Raises:
        Error: If one differs.
    """
    _near(camera.position, position.x, position.y, position.z)
    var ahead = camera.target - camera.position
    ahead.normalize()
    _near(ahead, forward.x, forward.y, forward.z)
    _near(camera.up, up.x, up.y, up.z)


def _level(
    camera: PerspectiveCamera, x: Float32, y: Float32, z: Float32
) raises:
    """Assert a perspective camera is at a place, looking down -z, +y up.

    Args:
        camera: The camera.
        x: Its expected x.
        y: Its expected y.
        z: Its expected z.

    Raises:
        Error: If it differs.
    """
    _pose(camera, Vector3(x, y, z), Vector3(0, 0, -1), Vector3(0, 1, 0))


def _level(
    camera: OrthographicCamera, x: Float32, y: Float32, z: Float32
) raises:
    """Assert an orthographic camera is at a place, looking down -z, +y up.

    Args:
        camera: The camera.
        x: Its expected x.
        y: Its expected y.
        z: Its expected z.

    Raises:
        Error: If it differs.
    """
    _pose(camera, Vector3(x, y, z), Vector3(0, 0, -1), Vector3(0, 1, 0))


def _data(geometry: BufferGeometry, name: StaticString) raises -> List[Float32]:
    """Return one attribute's numbers.

    Args:
        geometry: The geometry.
        name: The attribute's name.

    Returns:
        The numbers.

    Raises:
        Error: If the geometry has no such attribute.
    """
    return geometry.clone_attribute(String(name)).data.copy()


# --- defaults ----------------------------------------------------------------


def test_the_defaults_are_three_js() raises:
    var rig = Rig()
    ref c = rig.controls
    assert_true(c.enabled)
    assert_almost_equal(c.radius_factor, Float32(0.67), atol=TOLERANCE)
    assert_almost_equal(c.scale_factor, Float32(1.1), atol=TOLERANCE)
    assert_almost_equal(
        c.damping_factor.to(RADIAN_PER_SECOND_SQUARED), 25, atol=TOLERANCE
    )
    assert_almost_equal(c.w_max.to(RADIAN_PER_SECOND), 20, atol=TOLERANCE)
    assert_almost_equal(
        c.focus_animation_time.to(MILLISECOND), 500, atol=TOLERANCE
    )
    assert_almost_equal(c.min_fov.to(DEGREE), 5, atol=TOLERANCE)
    assert_almost_equal(c.max_fov.to(DEGREE), 90, atol=TOLERANCE)
    assert_true(c.enable_animations)
    assert_false(c.enable_grid)
    assert_false(c.cursor_zoom)
    assert_false(c.adjust_near_far)
    assert_true(c.enable_pan and c.enable_rotate and c.enable_zoom)
    assert_true(c.enable_gizmos and c.enable_focus)
    assert_true(c.state() == STATE_IDLE)
    assert_almost_equal(c.trackball_radius().to(METER), 3.35, atol=TOLERANCE)
    assert_true(c.operation_of(MOUSE_PRIMARY) == ROTATE_OPERATION)
    assert_true(c.operation_of(MOUSE_PRIMARY, CTRL_MODIFIER) == PAN_OPERATION)
    assert_true(c.operation_of(MOUSE_SECONDARY) == PAN_OPERATION)
    assert_true(c.operation_of(MOUSE_MIDDLE) == ZOOM_OPERATION)
    assert_true(c.operation_of(MOUSE_MIDDLE, SHIFT_MODIFIER) == FOV_OPERATION)
    assert_true(c.operation_of(MOUSE_WHEEL) == ZOOM_OPERATION)
    assert_true(c.operation_of(MOUSE_WHEEL, SHIFT_MODIFIER) == FOV_OPERATION)
    # A key with no action of its own falls back to the button's.
    assert_true(
        c.operation_of(MOUSE_SECONDARY, SHIFT_MODIFIER) == PAN_OPERATION
    )
    _level(rig.camera, 0, 0, 5)


def test_each_type_knows_its_values() raises:
    assert_true(STATE_ANIMATION_ROTATE.is_valid())
    assert_false(ArcballState(8).is_valid())
    assert_false(ArcballState(-1).is_valid())
    assert_true(FOV_OPERATION.is_valid() and NO_OPERATION.is_valid())
    assert_false(ArcballOperation(5).is_valid())
    assert_true(MOUSE_WHEEL.is_valid())
    assert_false(ArcballMouse(4).is_valid())
    assert_true(SHIFT_MODIFIER.is_valid())
    assert_false(ArcballModifier(-1).is_valid())


# --- turning -----------------------------------------------------------------


def test_a_drag_turns_on_the_trackball_as_three_js_does() raises:
    var rig = Rig()
    rig.send(POINTER_DOWN, 50, 50)
    assert_true(rig.controls.state() == STATE_ROTATE)
    assert_almost_equal(rig.controls.gizmo_opacity(), 1, atol=TOLERANCE)
    rig.send(POINTER_MOVE, 60, 45)
    _pose(
        rig.camera,
        Vector3(-0.499624, -0.248854, 4.968747),
        Vector3(0.099925, 0.049771, -0.993749),
        Vector3(-0.001758, 0.998755, 0.049845),
    )
    rig.send(POINTER_MOVE, 80, 30)
    _pose(
        rig.camera,
        Vector3(-1.771376, -1.165237, 4.528184),
        Vector3(0.354275, 0.233047, -0.905637),
        Vector3(-0.040488, 0.971364, 0.234122),
    )
    # Out on the hyperboloid.
    rig.send(POINTER_MOVE, 95, 5)
    _pose(
        rig.camera,
        Vector3(-3.591798, -3.473725, -0.179492),
        Vector3(0.718360, 0.694745, 0.035898),
        Vector3(-0.510895, 0.491830, 0.705046),
    )
    rig.send(POINTER_UP, 95, 5)
    _near(rig.controls.center(), 0, 0, 0)


def test_a_drag_pans_as_three_js_does() raises:
    var rig = Rig()
    rig.send(POINTER_DOWN, 50, 50, SECONDARY)
    assert_true(rig.controls.state() == STATE_PAN)
    rig.send(POINTER_MOVE, 60, 45, SECONDARY)
    _level(rig.camera, -1, -0.5, 5)
    _near(rig.controls.center(), -1, -0.5, 0)
    rig.send(POINTER_MOVE, 70, 70, SECONDARY)
    _level(rig.camera, -2, 2, 5)
    rig.send(POINTER_UP, 70, 70, SECONDARY)
    assert_true(rig.controls.state() == STATE_IDLE)
    # `target` stays where it was, as in three.js.
    _near(rig.controls.target, 0, 0, 0)


def test_the_wheel_zooms_as_three_js_does() raises:
    var rig = Rig()
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    _level(rig.camera, 0, 0, 4.632931)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 3.104064, atol=TOLERANCE
    )
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=1)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=1)
    _level(rig.camera, 0, 0, 5.396152)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 3.615422, atol=TOLERANCE
    )


def test_the_wheel_zooms_to_the_cursor_as_three_js_does() raises:
    var rig = Rig()
    rig.controls.cursor_zoom = True
    rig.send(WHEEL, 70, 30, NO_BUTTON, wheel=-1)
    _level(rig.camera, 0.150498, 0.143157, 4.632931)
    _near(rig.controls.center(), 0.150498, 0.143157, 0)


def test_a_middle_drag_zooms_as_three_js_does() raises:
    var rig = Rig()
    rig.send(POINTER_DOWN, 50, 50, MIDDLE)
    assert_true(rig.controls.state() == STATE_SCALE)
    rig.send(POINTER_MOVE, 50, 30, MIDDLE)
    _level(rig.camera, 0, 0, 4.292810)
    rig.send(POINTER_MOVE, 50, 80, MIDDLE)
    _level(rig.camera, 0, 0, 6.285104)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 4.211019, atol=TOLERANCE
    )
    rig.send(POINTER_UP, 50, 80, MIDDLE)
    # A zoom leaves its state set after the release, as in three.js.
    assert_true(rig.controls.state() == STATE_SCALE)


def test_shift_and_the_wheel_change_the_field_of_view_as_three_js_does() raises:
    var rig = Rig(60)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 1.934123, atol=TOLERANCE
    )
    rig.send(WHEEL, 50, 50, NO_BUTTON, shift=True, wheel=-1)
    _level(rig.camera, 0, 0, 4.545455)
    assert_almost_equal(rig.camera.fov.to(DEGREE), 64.838060, atol=1e-3)
    rig.send(WHEEL, 50, 50, NO_BUTTON, shift=True, wheel=1)
    rig.send(WHEEL, 50, 50, NO_BUTTON, shift=True, wheel=1)
    _level(rig.camera, 0, 0, 5.5)
    assert_almost_equal(rig.camera.fov.to(DEGREE), 55.386717, atol=1e-3)
    # The trackball keeps its size on the screen.
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 1.934123, atol=TOLERANCE
    )


def test_shift_and_a_middle_drag_change_the_field_of_view() raises:
    var rig = Rig(60)
    rig.send(POINTER_DOWN, 50, 50, MIDDLE, shift=True)
    assert_true(rig.controls.state() == STATE_FOV)
    rig.send(POINTER_MOVE, 50, 30, MIDDLE, shift=True)
    _level(rig.camera, 0, 0, 4.292810)
    assert_almost_equal(rig.camera.fov.to(DEGREE), 67.838655, atol=1e-3)
    rig.send(POINTER_MOVE, 50, 60, MIDDLE, shift=True)
    _level(rig.camera, 0, 0, 5.396152)
    assert_almost_equal(rig.camera.fov.to(DEGREE), 56.290428, atol=1e-3)
    rig.send(POINTER_UP, 50, 60, MIDDLE)


def test_the_field_of_view_stops_at_its_limit() raises:
    var rig = Rig()
    rig.send(WHEEL, 50, 50, NO_BUTTON, shift=True, wheel=-1)
    _level(rig.camera, 0, 0, 5)
    assert_almost_equal(rig.camera.fov.to(DEGREE), 90, atol=1e-3)


# --- animations --------------------------------------------------------------


def test_a_turn_let_go_goes_on_and_slows_as_three_js_does() raises:
    var rig = Rig()
    _ = rig.frame()
    rig.send(POINTER_DOWN, 50, 50)
    _ = rig.frame()
    rig.send(POINTER_MOVE, 55, 50)
    _ = rig.frame()
    rig.send(POINTER_MOVE, 60, 50)
    var dragged = Vector3(-0.498430, 0.000531, 4.975095)
    _near(rig.camera.position, dragged.x, dragged.y, dragged.z)
    rig.send(POINTER_UP, 60, 50)
    # The first frame starts the clock of the animation.
    assert_true(rig.frame())
    assert_true(rig.controls.state() == STATE_ANIMATION_ROTATE)
    _near(rig.camera.position, dragged.x, dragged.y, dragged.z)
    _ = rig.frame()
    _pose(
        rig.camera,
        Vector3(-0.728921, 0.000945, 4.946582),
        Vector3(0.145784, -0.000189, -0.989316),
        Vector3(0.000727, 1.000000, -0.000084),
    )
    _ = rig.frame()
    _near(rig.camera.position, -0.923738, 0.001338, 4.913930)
    _ = rig.frame()
    _near(rig.camera.position, -1.083242, 0.001688, 4.881248)
    for _ in range(60):
        _ = rig.frame()
    _pose(
        rig.camera,
        Vector3(-1.377917, 0.002407, 4.806385),
        Vector3(0.275583, -0.000481, -0.961277),
        Vector3(0.001394, 0.999999, -0.000101),
    )
    assert_true(rig.controls.state() == STATE_IDLE)
    assert_almost_equal(rig.controls.gizmo_opacity(), 0.6, atol=TOLERANCE)
    assert_false(rig.frame())


def test_a_turn_let_go_after_a_pause_stops() raises:
    var rig = Rig()
    _ = rig.frame()
    rig.send(POINTER_DOWN, 50, 50)
    _ = rig.frame()
    rig.send(POINTER_MOVE, 55, 50)
    _ = rig.frame()
    rig.send(POINTER_MOVE, 60, 50)
    _ = rig.frame(Duration(200.0, MILLISECOND))
    rig.send(POINTER_UP, 60, 50)
    assert_true(rig.controls.state() == STATE_IDLE)
    _ = rig.frame()
    _near(rig.camera.position, -0.498430, 0.000531, 4.975095)


def test_a_double_click_moves_to_the_box_over_time() raises:
    var rig = Rig()
    _ = rig.frame()
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    _ = rig.frame()
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    _level(rig.camera, 0, 0, 5)
    var step = Duration(100.0, MILLISECOND)
    _ = rig.frame(step)
    assert_true(rig.controls.state() == STATE_ANIMATION_FOCUS)
    _level(rig.camera, 0, 0, 5)
    _ = rig.frame(step)
    _level(rig.camera, 0.409920, -0.019520, 5.255353)
    _near(rig.controls.center(), 0.409920, -0.019520, 0.488)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 3.194127, atol=TOLERANCE
    )
    _ = rig.frame(step)
    _level(rig.camera, 0.658560, -0.031360, 5.420499)
    _ = rig.frame(Duration(300.0, MILLISECOND))
    _level(rig.camera, 0.84, -0.04, 5.545455)
    _near(rig.controls.center(), 0.84, -0.04, 1)
    assert_true(rig.controls.state() == STATE_IDLE)
    _ = rig.frame(step)
    _level(rig.camera, 0.84, -0.04, 5.545455)


def test_a_double_click_moves_at_once_without_animations() raises:
    var rig = Rig()
    rig.controls.enable_animations = False
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    _ = rig.frame()
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    _level(rig.camera, 0.84, -0.04, 5.545455)
    _near(rig.controls.center(), 0.84, -0.04, 1)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 3.045455, atol=TOLERANCE
    )


# --- update ------------------------------------------------------------------


def test_update_follows_a_new_target_as_three_js_does() raises:
    var rig = Rig()
    rig.controls.target = Vector3(1, 1, 0)
    assert_false(rig.frame())
    _pose(
        rig.camera,
        Vector3(0, 0, 5),
        Vector3(0.192450, 0.192450, -0.962250),
        Vector3(-0.037743, 0.981307, 0.188713),
    )
    _near(rig.controls.center(), 1, 1, 0)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 3.481422, atol=TOLERANCE
    )


def test_update_keeps_the_distance_within_its_limits() raises:
    var rig = Rig()
    rig.controls.max_distance = Length(4.0, METER)
    _ = rig.frame()
    _level(rig.camera, 0, 0, 4)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 2.68, atol=TOLERANCE
    )
    rig.controls.max_distance = Length(inf[DType.float32](), METER)
    rig.controls.min_distance = Length(6.0, METER)
    _ = rig.frame()
    _level(rig.camera, 0, 0, 6)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 4.02, atol=TOLERANCE
    )


def test_a_zoom_stops_at_the_distance_limits() raises:
    var rig = Rig()
    rig.controls.max_distance = Length(5.2, METER)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=1)
    _level(rig.camera, 0, 0, 5.2)
    rig.controls.max_distance = Length(inf[DType.float32](), METER)
    rig.controls.min_distance = Length(4.9, METER)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    _level(rig.camera, 0, 0, 4.9)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 3.283, atol=TOLERANCE
    )


def test_update_keeps_an_orthographic_zoom_within_its_limits() raises:
    var rig = OrthoRig()
    rig.controls.max_zoom = 0.5
    _ = rig.frame()
    assert_almost_equal(rig.camera.zoom, 0.5, atol=TOLERANCE)
    # three.js scales from the zoom when the last operation began.
    rig.controls.max_zoom = inf[DType.float32]()
    rig.controls.min_zoom = 2
    _ = rig.frame()
    assert_almost_equal(rig.camera.zoom, 4, atol=TOLERANCE)


def test_an_orthographic_zoom_stops_at_the_zoom_limits() raises:
    var rig = OrthoRig()
    rig.controls.max_zoom = 1.05
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    assert_almost_equal(rig.camera.zoom, 1.05, atol=TOLERANCE)
    rig.controls.max_zoom = inf[DType.float32]()
    rig.controls.min_zoom = 0.95
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=1)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=1)
    assert_almost_equal(rig.camera.zoom, 0.95, atol=TOLERANCE)
    _level(rig.camera, 0, 0, 5)


def test_update_clamps_the_field_of_view_and_redraws_the_gizmo() raises:
    var rig = Rig()
    rig.camera.fov = Angle(60.0, DEGREE)
    _ = rig.frame()
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 1.934123, atol=TOLERANCE
    )
    var positions = _data(rig.controls.gizmo(), POSITION)
    # The first point of the x circle is at the radius along x.
    assert_almost_equal(positions[0], 1.934123, atol=TOLERANCE)
    rig.camera.fov = Angle(120.0, DEGREE)
    _ = rig.frame()
    assert_almost_equal(rig.camera.fov.to(DEGREE), 90, atol=1e-3)


# --- state -------------------------------------------------------------------


def test_reset_puts_the_camera_back() raises:
    var rig = Rig()
    rig.send(POINTER_DOWN, 50, 50, SECONDARY)
    rig.send(POINTER_MOVE, 60, 45, SECONDARY)
    rig.send(POINTER_UP, 60, 45, SECONDARY)
    rig.send(POINTER_DOWN, 50, 50)
    rig.send(POINTER_MOVE, 60, 45)
    rig.send(POINTER_UP, 60, 45)
    _ = rig.frame()
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    rig.controls.reset(rig.camera)
    _level(rig.camera, 0, 0, 5)
    _near(rig.controls.center(), 0, 0, 0)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 3.35, atol=TOLERANCE
    )
    assert_true(rig.frame())


def test_save_state_moves_where_reset_goes() raises:
    var rig = Rig()
    rig.send(POINTER_DOWN, 50, 50, SECONDARY)
    rig.send(POINTER_MOVE, 60, 45, SECONDARY)
    rig.send(POINTER_UP, 60, 45, SECONDARY)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    rig.controls.save_state(rig.camera)
    rig.send(POINTER_DOWN, 50, 50)
    rig.send(POINTER_MOVE, 60, 45)
    rig.send(POINTER_UP, 60, 45)
    _ = rig.frame()
    rig.controls.reset(rig.camera)
    _level(rig.camera, -1, -0.5, 4.632931)
    _near(rig.controls.center(), -1, -0.5, 0)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 3.104064, atol=TOLERANCE
    )


def test_a_snapshot_pastes_the_camera_and_the_trackball() raises:
    var rig = Rig()
    rig.send(POINTER_DOWN, 50, 50)
    rig.send(POINTER_MOVE, 60, 45)
    rig.send(POINTER_UP, 60, 45)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    rig.send(POINTER_DOWN, 50, 50, SECONDARY)
    rig.send(POINTER_MOVE, 60, 45, SECONDARY)
    rig.send(POINTER_UP, 60, 45, SECONDARY)
    var position = Vector3(-1.384077, -0.690305, 4.488325)
    var forward = Vector3(0.099925, 0.049771, -0.993749)
    var up = Vector3(-0.001758, 0.998755, 0.049845)
    _pose(rig.camera, position, forward, up)
    var snapshot = rig.controls.copy_state(rig.camera)
    _near(snapshot.camera_up, up.x, up.y, up.z)
    assert_almost_equal(snapshot.camera_zoom, 1, atol=TOLERANCE)
    assert_almost_equal(snapshot.camera_fov.to(DEGREE), 90, atol=1e-3)
    assert_almost_equal(
        snapshot.gizmo_matrix.elements[0], 0.926586, atol=TOLERANCE
    )
    var other = Rig()
    other.controls.paste_state(other.camera, snapshot)
    _pose(other.camera, position, forward, up)
    _near(other.controls.center(), -0.921133, -0.459721, -0.115647)
    assert_almost_equal(
        other.controls.trackball_radius().to(METER), 3.104064, atol=TOLERANCE
    )
    assert_true(other.frame())
    _pose(other.camera, position, forward, up)


def test_an_orthographic_snapshot_round_trips() raises:
    var rig = OrthoRig()
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    rig.send(POINTER_DOWN, 50, 50, SECONDARY)
    rig.send(POINTER_MOVE, 60, 45, SECONDARY)
    rig.send(POINTER_UP, 60, 45, SECONDARY)
    var snapshot = rig.controls.copy_state(rig.camera)
    rig.controls.save_state(rig.camera)
    var other = OrthoRig()
    other.controls.paste_state(other.camera, snapshot)
    assert_almost_equal(other.camera.zoom, rig.camera.zoom, atol=TOLERANCE)
    _level(other.camera, rig.camera.position.x, rig.camera.position.y, 5)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=1)
    rig.controls.reset(rig.camera)
    assert_almost_equal(rig.camera.zoom, other.camera.zoom, atol=TOLERANCE)


def test_a_snapshot_that_no_camera_can_take_is_refused() raises:
    var rig = Rig()
    var snapshot = rig.controls.copy_state(rig.camera)
    snapshot.camera_fov = Angle(0.0, DEGREE)
    with assert_raises(contains="field of view"):
        rig.controls.paste_state(rig.camera, snapshot)
    snapshot.camera_fov = Angle(180.0, DEGREE)
    with assert_raises(contains="field of view"):
        rig.controls.paste_state(rig.camera, snapshot)
    snapshot.camera_fov = Angle(60.0, DEGREE)
    snapshot.camera_near = Length(0.0, METER)
    with assert_raises(contains="near plane"):
        rig.controls.paste_state(rig.camera, snapshot)
    snapshot.camera_near = Length(1.0, METER)
    snapshot.camera_far = Length(1.0, METER)
    with assert_raises(contains="far plane"):
        rig.controls.paste_state(rig.camera, snapshot)
    snapshot.camera_far = Length(10.0, METER)
    snapshot.camera_zoom = 0
    with assert_raises(contains="zoom"):
        rig.controls.paste_state(rig.camera, snapshot)
    var ortho = OrthoRig()
    var flat = ortho.controls.copy_state(ortho.camera)
    flat.camera_near = Length(-1.0, METER)
    with assert_raises(contains="behind"):
        ortho.controls.paste_state(ortho.camera, flat)
    # A near plane at the camera is one an orthographic camera can have.
    flat.camera_near = Length(0.0, METER)
    ortho.controls.paste_state(ortho.camera, flat)
    assert_almost_equal(ortho.camera.near.to(METER), 0, atol=TOLERANCE)


# --- near and far ------------------------------------------------------------


def test_adjust_near_far_moves_the_planes_as_three_js_does() raises:
    var rig = Rig()
    rig.controls.adjust_near_far = True
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    assert_almost_equal(rig.camera.near.to(METER), 0.1, atol=TOLERANCE)
    assert_almost_equal(rig.camera.far.to(METER), 100, atol=TOLERANCE)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=1)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=1)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=1)
    _level(rig.camera, 0, 0, 5.823691)
    assert_almost_equal(rig.camera.near.to(METER), 0.1, atol=TOLERANCE)
    assert_almost_equal(rig.camera.far.to(METER), 100.823691, atol=1e-3)


def test_a_zoom_puts_back_the_first_near_plane() raises:
    var rig = Rig()
    rig.camera.near = Length(0.5, METER)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    assert_almost_equal(rig.camera.near.to(METER), 0.1, atol=TOLERANCE)


# --- the gizmo and the grid --------------------------------------------------


def test_the_gizmo_is_three_circles_about_the_center() raises:
    var rig = Rig()
    var gizmo = rig.controls.gizmo()
    var positions = _data(gizmo, POSITION)
    var colors = _data(gizmo, COLOR)
    # Three circles of 128 segments, two points each.
    assert_equal(len(positions), 3 * 128 * 2 * 3)
    assert_equal(len(colors), len(positions))
    # The x circle starts at (r, 0, 0) and goes toward +z.
    _near(Vector3(positions[0], positions[1], positions[2]), 3.35, 0, 0)
    _near(
        Vector3(positions[3], positions[4], positions[5]),
        3.35 * 0.998795,
        0,
        3.35 * 0.049068,
    )
    # The y circle goes toward +y, and the z circle lies in xy.
    var y_start = 128 * 6
    _near(
        Vector3(
            positions[y_start + 3],
            positions[y_start + 4],
            positions[y_start + 5],
        ),
        0,
        3.35 * 0.049068,
        -3.35 * 0.998795,
    )
    var z_start = 2 * 128 * 6
    _near(
        Vector3(
            positions[z_start + 3],
            positions[z_start + 4],
            positions[z_start + 5],
        ),
        3.35 * 0.998795,
        3.35 * 0.049068,
        0,
    )
    # Red, green and blue: 0xff8080 and its turns, in linear light.
    assert_almost_equal(colors[0], 1, atol=TOLERANCE)
    assert_almost_equal(colors[1], 0.215861, atol=TOLERANCE)
    assert_almost_equal(colors[y_start + 1], 1, atol=TOLERANCE)
    assert_almost_equal(colors[z_start + 2], 1, atol=TOLERANCE)
    assert_almost_equal(rig.controls.gizmo_opacity(), 0.6, atol=TOLERANCE)
    rig.controls.set_gizmos_visible(False)
    assert_true(rig.frame())
    assert_equal(len(_data(rig.controls.gizmo(), POSITION)), 0)
    rig.controls.set_gizmos_visible(True)
    rig.controls.enable_gizmos = False
    assert_equal(len(_data(rig.controls.gizmo(), POSITION)), 0)


def test_the_gizmo_follows_a_zoom_and_a_pan() raises:
    var rig = Rig()
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    rig.send(POINTER_DOWN, 50, 50, SECONDARY)
    rig.send(POINTER_MOVE, 60, 45, SECONDARY)
    var positions = _data(rig.controls.gizmo(), POSITION)
    # The circles keep their radius and are scaled with the zoom.
    var center = rig.controls.center()
    _near(
        Vector3(positions[0], positions[1], positions[2]),
        center.x + 3.35 * 0.926586,
        center.y,
        center.z,
    )


def test_an_orthographic_gizmo_undoes_the_camera_zoom() raises:
    var camera = _orthographic()
    camera.zoom = 2
    var controls = ArcballControls(camera)
    var positions = _data(controls.gizmo(), POSITION)
    assert_almost_equal(positions[0], 3.35 * 0.5, atol=TOLERANCE)


def test_set_tb_radius_resizes_the_trackball() raises:
    var rig = Rig()
    rig.controls.set_tb_radius(0.5, rig.camera)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 2.5, atol=TOLERANCE
    )
    assert_true(rig.frame())
    with assert_raises(contains="radius factor"):
        rig.controls.set_tb_radius(0, rig.camera)
    var ortho = OrthoRig()
    ortho.controls.set_tb_radius(0.5, ortho.camera)
    assert_almost_equal(
        ortho.controls.trackball_radius().to(METER), 2.5, atol=TOLERANCE
    )


def test_a_resize_fits_the_trackball_to_the_view() raises:
    var rig = Rig()
    rig.camera.aspect = 2
    rig.send(RESIZE, 200, 100, NO_BUTTON)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 3.35, atol=TOLERANCE
    )
    rig.camera.aspect = 0.5
    rig.send(RESIZE, 50, 100, NO_BUTTON)
    assert_almost_equal(
        rig.controls.trackball_radius().to(METER), 1.675, atol=TOLERANCE
    )
    assert_true(rig.frame())


def test_a_pan_shows_a_grid_as_three_js_does() raises:
    var rig = Rig()
    assert_equal(len(_data(rig.controls.grid(), POSITION)), 0)
    rig.controls.enable_grid = True
    rig.send(POINTER_DOWN, 50, 50, SECONDARY)
    var positions = _data(rig.controls.grid(), POSITION)
    # 61 lines each way, two points each.
    assert_equal(len(positions), 244 * 3)
    _near(Vector3(positions[0], positions[1], positions[2]), -15, 15, 0)
    _near(Vector3(positions[3], positions[4], positions[5]), 15, 15, 0)
    _near(Vector3(positions[6], positions[7], positions[8]), -15, 15, 0)
    _near(Vector3(positions[9], positions[10], positions[11]), -15, -15, 0)
    _near(
        Vector3(positions[729], positions[730], positions[731]),
        15,
        -15,
        0,
    )
    # A wheel notch draws it again at the new size.
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=1)
    positions = _data(rig.controls.grid(), POSITION)
    assert_almost_equal(positions[0], -15 * 1.079230, atol=1e-3)
    rig.send(POINTER_UP, 50, 50, SECONDARY)
    assert_equal(len(_data(rig.controls.grid(), POSITION)), 0)


def test_an_orthographic_grid_as_three_js_does() raises:
    var rig = OrthoRig()
    rig.controls.enable_grid = True
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    rig.send(POINTER_DOWN, 50, 50, SECONDARY)
    var positions = _data(rig.controls.grid(), POSITION)
    _near(
        Vector3(positions[0], positions[1], positions[2]),
        -13.89879,
        13.89879,
        0,
    )


# --- switching ---------------------------------------------------------------


def test_ctrl_during_a_drag_switches_to_a_pan_as_three_js_does() raises:
    var rig = Rig()
    rig.send(POINTER_DOWN, 50, 50)
    rig.send(POINTER_MOVE, 60, 45)
    var up = Vector3(-0.001758, 0.998755, 0.049845)
    var forward = Vector3(0.099925, 0.049771, -0.993749)
    rig.send(POINTER_MOVE, 70, 45, ctrl=True)
    assert_true(rig.controls.state() == STATE_PAN)
    _pose(rig.camera, Vector3(-0.499624, -0.248854, 4.968747), forward, up)
    rig.send(POINTER_MOVE, 80, 45, ctrl=True)
    _pose(rig.camera, Vector3(-1.494617, -0.245621, 4.868859), forward, up)
    _near(rig.controls.center(), -0.994993, 0.003233, -0.099888)
    rig.send(POINTER_MOVE, 80, 60)
    assert_true(rig.controls.state() == STATE_ROTATE)
    _pose(rig.camera, Vector3(-1.494617, -0.245621, 4.868859), forward, up)
    rig.send(POINTER_MOVE, 90, 60)
    _pose(
        rig.camera,
        Vector3(-2.533262, -0.075798, 4.656947),
        Vector3(0.307654, 0.015806, -0.951367),
        Vector3(0.019763, 0.999540, 0.022997),
    )
    rig.send(POINTER_UP, 90, 60)


# --- mouse actions -----------------------------------------------------------


def test_set_mouse_action_replaces_and_refuses_as_three_js_does() raises:
    var rig = Rig()
    ref c = rig.controls
    # The wheel has one direction: it zooms or changes the field of view.
    assert_false(c.set_mouse_action(PAN_OPERATION, MOUSE_WHEEL))
    assert_false(c.set_mouse_action(ROTATE_OPERATION, MOUSE_WHEEL))
    assert_false(c.set_mouse_action(NO_OPERATION, MOUSE_PRIMARY))
    assert_true(c.set_mouse_action(ZOOM_OPERATION, MOUSE_WHEEL))
    assert_true(c.set_mouse_action(FOV_OPERATION, MOUSE_WHEEL, SHIFT_MODIFIER))
    assert_equal(len(c.mouse_actions), 7)
    # A button and key already used take the new operation.
    assert_true(c.set_mouse_action(PAN_OPERATION, MOUSE_PRIMARY))
    assert_true(c.operation_of(MOUSE_PRIMARY) == PAN_OPERATION)
    assert_equal(len(c.mouse_actions), 7)
    assert_true(
        c.set_mouse_action(ROTATE_OPERATION, MOUSE_SECONDARY, CTRL_MODIFIER)
    )
    assert_equal(len(c.mouse_actions), 8)
    assert_true(c.unset_mouse_action(MOUSE_SECONDARY, CTRL_MODIFIER))
    assert_false(c.unset_mouse_action(MOUSE_SECONDARY, CTRL_MODIFIER))
    assert_true(c.unset_mouse_action(MOUSE_PRIMARY))
    # With no action of its own and no fallback, a button does nothing.
    assert_true(c.operation_of(MOUSE_PRIMARY) == NO_OPERATION)
    assert_true(c.operation_of(MOUSE_PRIMARY, CTRL_MODIFIER) == PAN_OPERATION)
    assert_true(c.operation_of(MOUSE_PRIMARY, SHIFT_MODIFIER) == NO_OPERATION)


def test_an_invalid_mouse_action_is_refused() raises:
    var rig = Rig()
    with assert_raises(contains="operation"):
        _ = rig.controls.set_mouse_action(ArcballOperation(5), MOUSE_PRIMARY)
    with assert_raises(contains="mouse"):
        _ = rig.controls.set_mouse_action(PAN_OPERATION, ArcballMouse(4))
    with assert_raises(contains="mouse"):
        _ = rig.controls.unset_mouse_action(ArcballMouse(-1))
    with assert_raises(contains="modifier"):
        _ = rig.controls.operation_of(MOUSE_PRIMARY, ArcballModifier(3))
    rig.controls.mouse_actions[0].operation = ArcballOperation(-1)
    with assert_raises(contains="operation"):
        rig.send(POINTER_DOWN, 50, 50)
    with assert_raises(contains="operation"):
        _ = rig.frame()


def test_with_no_mouse_actions_nothing_moves() raises:
    var rig = Rig()
    rig.controls.mouse_actions.clear()
    rig.send(POINTER_DOWN, 50, 50)
    rig.send(POINTER_MOVE, 60, 45)
    rig.send(POINTER_UP, 60, 45)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    _level(rig.camera, 0, 0, 5)
    assert_true(rig.controls.operation_of(MOUSE_WHEEL) == NO_OPERATION)
    assert_true(
        rig.controls.operation_of(MOUSE_WHEEL, SHIFT_MODIFIER) == NO_OPERATION
    )
    assert_false(rig.controls.unset_mouse_action(MOUSE_WHEEL))
    assert_true(rig.controls.set_mouse_action(ZOOM_OPERATION, MOUSE_WHEEL))
    assert_true(rig.controls.operation_of(MOUSE_WHEEL) == ZOOM_OPERATION)


def test_a_button_whose_action_goes_mid_drag_stops() raises:
    var rig = Rig()
    rig.send(POINTER_DOWN, 50, 50, MIDDLE)
    _ = rig.controls.unset_mouse_action(MOUSE_MIDDLE)
    rig.send(POINTER_MOVE, 50, 30, MIDDLE)
    _level(rig.camera, 0, 0, 5)
    rig.send(POINTER_UP, 50, 30, MIDDLE)


# --- refused input -----------------------------------------------------------


def test_invalid_events_and_settings_are_refused() raises:
    var rig = Rig()
    with assert_raises(contains="input kind"):
        rig.send(InputKind(9), 50, 50)
    with assert_raises(contains="button"):
        rig.send(POINTER_DOWN, 50, 50, PointerButton(7))
    with assert_raises(contains="key"):
        rig.controls.handle(
            InputEvent(POINTER_DOWN, key=Key(999)),
            rig.camera,
            rig.scene,
            rig.assets,
            SIZE,
            SIZE,
        )
    with assert_raises(contains="size"):
        rig.controls.handle(
            _event(POINTER_DOWN, 50, 50),
            rig.camera,
            rig.scene,
            rig.assets,
            0,
            SIZE,
        )
    with assert_raises(contains="size"):
        rig.controls.handle(
            _event(POINTER_DOWN, 50, 50),
            rig.camera,
            rig.scene,
            rig.assets,
            SIZE,
            0,
        )
    with assert_raises(contains="negative"):
        _ = rig.frame(Duration(-1.0, MILLISECOND))
    rig.controls.radius_factor = 0
    with assert_raises(contains="radius factor"):
        _ = rig.frame()
    rig.controls.radius_factor = 0.67
    rig.controls.scale_factor = 0
    with assert_raises(contains="scale factor"):
        _ = rig.frame()
    rig.controls.scale_factor = 1.1
    rig.controls.focus_animation_time = Duration(0.0, SECOND)
    with assert_raises(contains="focus"):
        _ = rig.frame()


def test_a_camera_on_a_node_is_refused() raises:
    var camera = _perspective()
    camera.attach(NodeId(0))
    with assert_raises(contains="placed camera"):
        _ = ArcballControls(camera)
    var ortho = _orthographic()
    ortho.attach(NodeId(0))
    with assert_raises(contains="placed camera"):
        _ = ArcballControls(ortho)


def test_a_key_changes_nothing() raises:
    var rig = Rig()
    rig.controls.handle(
        InputEvent(KEY_DOWN, key=Key(97)),
        rig.camera,
        rig.scene,
        rig.assets,
        SIZE,
        SIZE,
    )
    # A move and a release with no press are not listened to.
    rig.send(POINTER_MOVE, 60, 45)
    rig.send(POINTER_UP, 60, 45)
    _level(rig.camera, 0, 0, 5)
    assert_false(rig.frame())


# --- what is turned off ------------------------------------------------------


def test_disabled_controls_ignore_input() raises:
    var rig = Rig()
    rig.controls.enabled = False
    rig.send(POINTER_DOWN, 50, 50)
    rig.send(POINTER_MOVE, 60, 45)
    rig.send(POINTER_UP, 60, 45)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    _level(rig.camera, 0, 0, 5)
    # Controls turned off during a drag stop following it.
    rig.controls.enabled = True
    rig.send(POINTER_DOWN, 50, 50)
    rig.controls.enabled = False
    rig.send(POINTER_MOVE, 60, 45)
    _level(rig.camera, 0, 0, 5)
    rig.send(POINTER_UP, 60, 45)


def test_each_operation_can_be_turned_off() raises:
    var rig = Rig()
    rig.controls.enable_pan = False
    rig.controls.enable_rotate = False
    rig.controls.enable_zoom = False
    rig.send(POINTER_DOWN, 50, 50, SECONDARY)
    rig.send(POINTER_MOVE, 60, 45, SECONDARY)
    rig.send(POINTER_UP, 60, 45, SECONDARY)
    rig.send(POINTER_DOWN, 50, 50)
    rig.send(POINTER_MOVE, 60, 45)
    rig.send(POINTER_UP, 60, 45)
    rig.send(POINTER_DOWN, 50, 50, MIDDLE)
    rig.send(POINTER_MOVE, 60, 45, MIDDLE)
    rig.send(POINTER_MOVE, 60, 30, MIDDLE, shift=True)
    rig.send(POINTER_UP, 60, 45, MIDDLE)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    _level(rig.camera, 0, 0, 5)
    assert_true(rig.controls.state() == STATE_IDLE)


def test_operations_turned_off_during_a_drag() raises:
    var rig = Rig()
    # A turn switched to a pan that is off, and a pan to a turn that is off.
    rig.send(POINTER_DOWN, 50, 50)
    rig.controls.enable_pan = False
    rig.send(POINTER_MOVE, 60, 45, ctrl=True)
    assert_true(rig.controls.state() == STATE_ROTATE)
    rig.controls.enable_rotate = False
    rig.send(POINTER_UP, 60, 45)
    assert_true(rig.controls.state() == STATE_ROTATE)
    rig.controls.enable_pan = True
    rig.send(POINTER_DOWN, 50, 50, ctrl=True)
    rig.send(POINTER_MOVE, 60, 45)
    assert_true(rig.controls.state() == STATE_PAN)
    rig.send(POINTER_UP, 60, 45)
    # A zoom and a change of field of view that are off.
    rig.send(POINTER_DOWN, 50, 50, MIDDLE)
    rig.controls.enable_zoom = False
    rig.send(POINTER_MOVE, 50, 30, MIDDLE)
    rig.send(POINTER_MOVE, 50, 30, MIDDLE, shift=True)
    rig.send(POINTER_UP, 50, 30, MIDDLE)
    _level(rig.camera, 0, 0, 5)


def test_a_wheel_with_nothing_to_do() raises:
    var rig = Rig()
    rig.controls.enable_zoom = False
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    rig.controls.enable_zoom = True
    _ = rig.controls.unset_mouse_action(MOUSE_WHEEL)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    _ = rig.controls.set_mouse_action(ZOOM_OPERATION, MOUSE_WHEEL)
    # No notch zooms by one.
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=0)
    rig.send(WHEEL, 50, 50, NO_BUTTON, shift=True, wheel=0)
    _level(rig.camera, 0, 0, 5)
    assert_almost_equal(rig.camera.fov.to(DEGREE), 90, atol=1e-3)
    # A zoom to the cursor needs a pan.
    rig.controls.cursor_zoom = True
    rig.controls.enable_pan = False
    rig.send(WHEEL, 70, 30, NO_BUTTON, wheel=-1)
    _level(rig.camera, 0, 0, 4.632931)


# --- switching operations mid-drag -------------------------------------------


def test_a_zoom_and_a_field_of_view_switch_into_each_other() raises:
    var rig = Rig(60)
    rig.send(POINTER_DOWN, 50, 50, MIDDLE)
    rig.send(POINTER_MOVE, 50, 50, MIDDLE)
    # No movement is no zoom.
    _level(rig.camera, 0, 0, 5)
    rig.send(POINTER_MOVE, 50, 40, MIDDLE, shift=True)
    assert_true(rig.controls.state() == STATE_FOV)
    rig.send(POINTER_MOVE, 50, 40, MIDDLE)
    assert_true(rig.controls.state() == STATE_SCALE)
    rig.send(POINTER_UP, 50, 40, MIDDLE)
    _level(rig.camera, 0, 0, 5)


def test_a_grid_is_drawn_again_when_a_pan_restarts() raises:
    var rig = Rig()
    rig.controls.enable_grid = True
    rig.send(POINTER_DOWN, 50, 50)
    rig.send(POINTER_MOVE, 50, 50, ctrl=True)
    assert_equal(len(_data(rig.controls.grid(), POSITION)), 244 * 3)
    rig.send(POINTER_MOVE, 55, 50)
    assert_equal(len(_data(rig.controls.grid(), POSITION)), 0)
    rig.send(POINTER_UP, 55, 50)
    # A wheel notch in a pan leaves the grid, and the pan restarts.
    rig.send(POINTER_DOWN, 50, 50, SECONDARY)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=1)
    rig.send(POINTER_MOVE, 55, 50, SECONDARY)
    assert_true(rig.controls.state() == STATE_PAN)
    assert_equal(len(_data(rig.controls.grid(), POSITION)), 244 * 3)
    rig.send(POINTER_UP, 55, 50, SECONDARY)


def test_an_orthographic_camera_has_no_field_of_view_to_change() raises:
    var rig = OrthoRig()
    rig.send(POINTER_DOWN, 50, 50, MIDDLE, shift=True)
    assert_true(rig.controls.state() == STATE_IDLE)
    rig.send(POINTER_MOVE, 50, 30, MIDDLE, shift=True)
    rig.send(POINTER_UP, 50, 30, MIDDLE)
    rig.send(WHEEL, 50, 50, NO_BUTTON, shift=True, wheel=-1)
    assert_almost_equal(rig.camera.zoom, 1, atol=TOLERANCE)
    _level(rig.camera, 0, 0, 5)


def test_a_second_button_during_a_drag_is_ignored() raises:
    var rig = Rig()
    rig.send(POINTER_DOWN, 50, 50)
    rig.send(POINTER_DOWN, 50, 50, SECONDARY)
    assert_true(rig.controls.state() == STATE_ROTATE)
    rig.send(POINTER_UP, 50, 50)
    # A press with no button starts nothing.
    rig.send(POINTER_DOWN, 50, 50, NO_BUTTON)
    rig.send(POINTER_MOVE, 60, 45, NO_BUTTON)
    _level(rig.camera, 0, 0, 5)


# --- the middle of the view --------------------------------------------------


def test_the_middle_of_an_odd_view_is_on_the_view_axis() raises:
    var rig = Rig()
    rig.controls.handle(
        _event(POINTER_DOWN, 50, 50),
        rig.camera,
        rig.scene,
        rig.assets,
        101,
        101,
    )
    rig.controls.handle(
        _event(POINTER_MOVE, 60, 50),
        rig.camera,
        rig.scene,
        rig.assets,
        101,
        101,
    )
    rig.controls.handle(
        _event(POINTER_UP, 60, 50), rig.camera, rig.scene, rig.assets, 101, 101
    )
    assert_true(rig.camera.position.x < 0)
    rig.controls.handle(
        _event(POINTER_DOWN, 50, 50, SECONDARY),
        rig.camera,
        rig.scene,
        rig.assets,
        101,
        101,
    )
    rig.controls.handle(
        _event(POINTER_MOVE, 50, 50, SECONDARY),
        rig.camera,
        rig.scene,
        rig.assets,
        101,
        101,
    )
    rig.controls.handle(
        _event(POINTER_UP, 50, 50, SECONDARY),
        rig.camera,
        rig.scene,
        rig.assets,
        101,
        101,
    )


def test_just_inside_the_rim_the_trackball_is_a_hyperboloid() raises:
    # Between the sphere's silhouette and 45 degrees on it, three.js takes
    # the hyperboloid: a ray there meets the sphere, but too far round.
    var rig = Rig()
    rig.controls.handle(
        _event(POINTER_DOWN, 500, 500),
        rig.camera,
        rig.scene,
        rig.assets,
        1000,
        1000,
    )
    rig.controls.handle(
        _event(POINTER_MOVE, 950, 500),
        rig.camera,
        rig.scene,
        rig.assets,
        1000,
        1000,
    )
    assert_true(rig.camera.position.x < 0)
    rig.controls.handle(
        _event(POINTER_UP, 950, 500),
        rig.camera,
        rig.scene,
        rig.assets,
        1000,
        1000,
    )


# --- clicks ------------------------------------------------------------------


def test_a_slow_or_distant_second_click_is_no_double_click() raises:
    var rig = Rig()
    rig.controls.enable_animations = False
    # A press held too long.
    rig.send(POINTER_DOWN, 60, 50)
    _ = rig.frame(Duration(300.0, MILLISECOND))
    rig.send(POINTER_UP, 60, 50)
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    _level(rig.camera, 0, 0, 5)
    # A second click too late.
    _ = rig.frame(Duration(400.0, MILLISECOND))
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    _level(rig.camera, 0, 0, 5)
    # A second click too far away, then a third near it.
    rig.send(POINTER_DOWN, 90, 90)
    rig.send(POINTER_UP, 90, 90)
    _level(rig.camera, 0, 0, 5)
    rig.send(POINTER_DOWN, 90, 90)
    rig.send(POINTER_UP, 90, 90)
    # A drag between the clicks.
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_MOVE, 95, 50)
    rig.send(POINTER_UP, 95, 50)
    rig.send(POINTER_DOWN, 60, 50, SECONDARY)
    rig.send(POINTER_UP, 60, 50, SECONDARY)
    assert_true(rig.controls.state() == STATE_IDLE)


def test_a_double_click_on_nothing_or_with_focus_off_does_nothing() raises:
    var rig = Rig()
    rig.controls.enable_animations = False
    rig.send(POINTER_DOWN, 5, 5)
    rig.send(POINTER_UP, 5, 5)
    rig.send(POINTER_DOWN, 5, 5)
    rig.send(POINTER_UP, 5, 5)
    _level(rig.camera, 0, 0, 5)
    rig.controls.enable_focus = False
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    _level(rig.camera, 0, 0, 5)
    var ortho = OrthoRig()
    ortho.controls.enable_pan = False
    ortho.send(POINTER_DOWN, 60, 50)
    ortho.send(POINTER_UP, 60, 50)
    ortho.send(POINTER_DOWN, 60, 50)
    ortho.send(POINTER_UP, 60, 50)
    _level(ortho.camera, 0, 0, 5)


def test_a_double_click_passes_over_a_line_and_can_skip_the_zoom() raises:
    var rig = Rig()
    rig.controls.enable_animations = False
    rig.controls.enable_zoom = False
    var segments = Segments()
    segments.add(Vector3(-5, 0, 2), Vector3(5, 0, 2), FloatColor(1, 1, 1, 1))
    var shape = rig.assets.geometries.add(segments.geometry())
    var paint = rig.assets.materials.add(Material(Color(255, 255, 255)))
    rig.scene.add_line(Line(shape, paint, NodeId(0), mode=SEGMENTS))
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    # The box's face is hit behind the line, and nothing zooms.
    _level(rig.camera, 0.84, -0.04, 6)
    _near(rig.controls.center(), 0.84, -0.04, 1)


# --- interrupted animations --------------------------------------------------


def _let_go_turning(mut rig: Rig) raises:
    """Drag across the view and let go while moving.

    Args:
        rig: The rig.

    Raises:
        Error: If an event is refused.
    """
    _ = rig.frame()
    rig.send(POINTER_DOWN, 50, 50)
    _ = rig.frame()
    rig.send(POINTER_MOVE, 55, 50)
    _ = rig.frame()
    rig.send(POINTER_MOVE, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    _ = rig.frame()


def test_a_wheel_notch_stops_a_turn_let_go() raises:
    var rig = Rig()
    _let_go_turning(rig)
    _ = rig.frame()
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    var position = rig.camera.position
    assert_true(rig.frame())
    _near(rig.camera.position, position.x, position.y, position.z)
    assert_almost_equal(rig.controls.gizmo_opacity(), 0.6, atol=TOLERANCE)
    assert_false(rig.frame())


def test_a_new_turn_stops_a_turn_let_go() raises:
    var rig = Rig()
    _let_go_turning(rig)
    rig.send(POINTER_DOWN, 50, 50)
    assert_true(rig.controls.state() == STATE_ROTATE)
    _ = rig.frame()
    assert_true(rig.controls.state() == STATE_ROTATE)
    rig.send(POINTER_UP, 50, 50)
    # A press that starts nothing leaves the turn going, until a drag
    # restarts a turn: the frame then stops, and the gizmo stays bright.
    _let_go_turning(rig)
    rig.controls.enable_rotate = False
    rig.send(POINTER_DOWN, 50, 50)
    rig.controls.enable_rotate = True
    rig.send(POINTER_MOVE, 52, 50)
    assert_true(rig.controls.state() == STATE_ROTATE)
    _ = rig.frame()
    assert_almost_equal(rig.controls.gizmo_opacity(), 1, atol=TOLERANCE)
    rig.send(POINTER_UP, 52, 50)


def test_a_wheel_notch_stops_a_focus() raises:
    var rig = Rig()
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    _ = rig.frame()
    assert_true(rig.controls.state() == STATE_ANIMATION_FOCUS)
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    _ = rig.frame()
    _ = rig.frame()
    _level(rig.camera, 0, 0, 4.632931)
    # A pan after a focus that ended.
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    for _ in range(40):
        _ = rig.frame()
    assert_true(rig.controls.state() == STATE_IDLE)
    rig.send(POINTER_DOWN, 50, 50, SECONDARY)
    assert_true(rig.controls.state() == STATE_PAN)
    rig.send(POINTER_UP, 50, 50, SECONDARY)


def test_a_turn_without_animations_stops_at_the_release() raises:
    var rig = Rig()
    rig.controls.enable_animations = False
    _ = rig.frame()
    rig.send(POINTER_DOWN, 50, 50)
    _ = rig.frame()
    rig.send(POINTER_MOVE, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    assert_true(rig.controls.state() == STATE_IDLE)
    var position = rig.camera.position
    _ = rig.frame()
    _near(rig.camera.position, position.x, position.y, position.z)


# --- orthographic ------------------------------------------------------------


def test_an_orthographic_double_click_zooms_the_camera() raises:
    var rig = OrthoRig()
    rig.controls.enable_animations = False
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    _ = rig.frame()
    rig.send(POINTER_DOWN, 60, 50)
    rig.send(POINTER_UP, 60, 50)
    _level(rig.camera, 1.05, -0.05, 6)
    assert_almost_equal(rig.camera.zoom, 1.1, atol=TOLERANCE)
    _near(rig.controls.center(), 1.05, -0.05, 1)


def test_an_orthographic_drag_turns_as_three_js_does() raises:
    var rig = OrthoRig()
    rig.send(POINTER_DOWN, 50, 50)
    rig.send(POINTER_MOVE, 60, 45)
    _pose(
        rig.camera,
        Vector3(-1.499213, -0.736497, 4.712742),
        Vector3(0.299843, 0.147299, -0.942548),
        Vector3(-0.016174, 0.988651, 0.149359),
    )
    rig.send(POINTER_MOVE, 90, 20)
    _pose(
        rig.camera,
        Vector3(-4.084505, -2.866704, -0.314368),
        Vector3(0.816901, 0.573341, 0.062874),
        Vector3(-0.486497, 0.626372, 0.609081),
    )
    rig.send(POINTER_UP, 90, 20)


def test_an_orthographic_pan_as_three_js_does() raises:
    var rig = OrthoRig()
    rig.send(POINTER_DOWN, 50, 50, SECONDARY)
    rig.send(POINTER_MOVE, 60, 45, SECONDARY)
    _level(rig.camera, -1, -0.5, 5)
    rig.send(POINTER_UP, 60, 45, SECONDARY)


def test_an_orthographic_zoom_as_three_js_does() raises:
    var rig = OrthoRig()
    rig.send(WHEEL, 50, 50, NO_BUTTON, wheel=-1)
    _level(rig.camera, 0, 0, 5)
    assert_almost_equal(rig.camera.zoom, 1.079230, atol=TOLERANCE)
    rig.controls.cursor_zoom = True
    rig.send(WHEEL, 70, 30, NO_BUTTON, wheel=-1)
    _level(rig.camera, 0.139450, 0.132647, 5)
    assert_almost_equal(rig.camera.zoom, 1.164738, atol=TOLERANCE)
    # A pan when zoomed in moves less.
    rig.send(POINTER_DOWN, 60, 45, SECONDARY)
    rig.send(POINTER_MOVE, 70, 50, SECONDARY)
    _level(rig.camera, -0.719113, 0.561928, 5)
    rig.send(POINTER_UP, 70, 50, SECONDARY)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
