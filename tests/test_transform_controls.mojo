# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `controls.transform_controls`.

The expected numbers come from three.js r180's own `TransformControls`,
run headless in Node with the same scene, camera and pointer. A node stands
at (0.5, 0.2, -0.3). In some tests it is turned 30 degrees about y, and in
some it is the child of a node at (1, 0, 0), turned 20 degrees about z and
scaled two times. A 50-degree camera at (4, 3, 6) looks at the origin
through a view of 100 by 100 pixels.

Each drag is the same five events: a move over a handle, a press there,
two moves, and a release. The pixel of the handle is the one three.js's
own picker chose; the drag's moves are the same in both. A render was run
between two events in three.js, as the controls here work the plane and
the handles out at each event.
"""

from cameras.camera import Camera
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.input import (
    InputEvent,
    InputKind,
    KEY_DOWN,
    Key,
    NO_BUTTON,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
    SECONDARY,
)
from controls.transform_controls import (
    AXIS_CHANGED,
    DRAGGING_CHANGED,
    HANDLE_E,
    HANDLE_X,
    HANDLE_XY,
    HANDLE_XYZ,
    HANDLE_XYZE,
    HANDLE_XZ,
    HANDLE_Y,
    HANDLE_YZ,
    HANDLE_Z,
    LOCAL_SPACE,
    MOUSE_DOWN,
    MOUSE_UP,
    NO_HANDLE,
    OBJECT_CHANGE,
    ROTATE_MODE,
    SCALE_MODE,
    TRANSLATE_MODE,
    TransformAxis,
    TransformControls,
    TransformEvent,
    TransformEventKind,
    TransformFrame,
    TransformMode,
    TransformSpace,
    WORLD_SPACE,
    decompose,
)
from core.buffer_geometry import COLOR, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from math.matrix4 import Matrix4, scaling
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from render.framebuffer import Color, FloatColor
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-3)
comptime SIZE = 100


def _camera(eye: Vector3 = Vector3(4, 3, 6)) raises -> PerspectiveCamera:
    """Return a 50-degree camera looking at the origin.

    Args:
        eye: Where it stands.

    Returns:
        The camera.

    Raises:
        Error: If the camera is refused.
    """
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(eye, Vector3(0, 0, 0))
    return camera^


def _scene(
    parent: Bool = False,
    turn: Bool = False,
    position: Vector3 = Vector3(0.5, 0.2, -0.3),
) raises -> Scene:
    """Return a scene with the node of the module docstring last.

    Args:
        parent: True to put the node under the turned and scaled parent.
        turn: True to turn the node 30 degrees about y.
        position: Where the node stands in its parent.

    Returns:
        The scene, updated.

    Raises:
        Error: If the scene is refused.
    """
    var scene = Scene()
    var node = Object3D()
    node.position = position
    if turn:
        node.set_euler(
            Angle(0.0, DEGREE), Angle(30.0, DEGREE), Angle(0.0, DEGREE)
        )
    if parent:
        var above = Object3D()
        above.set_position(1, 0, 0)
        above.set_euler(
            Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(20.0, DEGREE)
        )
        above.set_scale(2, 2, 2)
        var id = scene.add(above^)
        _ = scene.attach(node^, id)
    else:
        _ = scene.add(node^)
    scene.update()
    return scene^


def _last(scene: Scene) -> NodeId:
    """Return the scene's last node.

    Args:
        scene: The scene.

    Returns:
        Its id.
    """
    return NodeId(scene.count() - 1)


def _event(
    kind: InputKind, x: Int, y: Int, button: PointerButton = PRIMARY
) -> InputEvent:
    """Return a pointer event.

    Args:
        kind: What happened.
        x: The pixel's column.
        y: The pixel's row.
        button: The button.

    Returns:
        The event.
    """
    return InputEvent(kind, button=button, x=x, y=y)


def _kinds(
    events: List[TransformEvent], kinds: List[TransformEventKind]
) raises:
    """Assert the events are these kinds.

    Args:
        events: The events returned.
        kinds: The kinds expected.

    Raises:
        Error: If they differ.
    """
    assert_equal(len(events), len(kinds))
    for index in range(len(kinds)):
        assert_true(events[index].kind == kinds[index])


def _drag[
    C: Camera
](
    mut controls: TransformControls,
    camera: C,
    mut scene: Scene,
    x: Int,
    y: Int,
    dx: Int,
    dy: Int,
    axis: TransformAxis,
) raises:
    """Drag a handle as the module docstring says, and check its events.

    Args:
        controls: The controls, attached.
        camera: The camera.
        scene: The scene.
        x: The handle's pixel column.
        y: Its row.
        dx: How far each move goes across.
        dy: How far the first move goes down.
        axis: The handle three.js picked there.

    Raises:
        Error: If an event differs.
    """
    var events = controls.handle(
        _event(POINTER_MOVE, x, y, NO_BUTTON), camera, scene, SIZE, SIZE
    )
    _kinds(events, [AXIS_CHANGED])
    assert_true(controls.axis == axis)
    events = controls.handle(
        _event(POINTER_DOWN, x, y), camera, scene, SIZE, SIZE
    )
    _kinds(events, [DRAGGING_CHANGED, MOUSE_DOWN])
    assert_true(events[1].axis == axis)
    assert_true(events[1].dragging)
    events = controls.handle(
        _event(POINTER_MOVE, x + dx, y + dy), camera, scene, SIZE, SIZE
    )
    _kinds(events, [OBJECT_CHANGE])
    events = controls.handle(
        _event(POINTER_MOVE, x + 2 * dx, y + dy), camera, scene, SIZE, SIZE
    )
    _kinds(events, [OBJECT_CHANGE])
    events = controls.handle(
        _event(POINTER_UP, x + 2 * dx, y + dy), camera, scene, SIZE, SIZE
    )
    _kinds(events, [MOUSE_UP, DRAGGING_CHANGED, AXIS_CHANGED])
    assert_true(controls.axis == NO_HANDLE)
    assert_false(controls.dragging)


def _assert_vector(got: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a vector is (x, y, z), within tolerance.

    Args:
        got: The vector.
        x: Its x.
        y: Its y.
        z: Its z.

    Raises:
        Error: If it differs.
    """
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)
    assert_almost_equal(got.z, z, atol=TOLERANCE)


def _assert_turn(
    got: Quaternion, x: Float32, y: Float32, z: Float32, w: Float32
) raises:
    """Assert a rotation is (x, y, z, w), within tolerance.

    Args:
        got: The rotation.
        x: Its x.
        y: Its y.
        z: Its z.
        w: Its w.

    Raises:
        Error: If it differs.
    """
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)
    assert_almost_equal(got.z, z, atol=TOLERANCE)
    assert_almost_equal(got.w, w, atol=TOLERANCE)


def _controls(
    mode: TransformMode, space: TransformSpace, node: NodeId
) raises -> TransformControls:
    """Return controls in a mode and a space, attached to a node.

    Args:
        mode: The mode.
        space: The space.
        node: The node.

    Returns:
        The controls.

    Raises:
        Error: Never.
    """
    var controls = TransformControls()
    controls.mode = mode
    controls.space = space
    controls.attach(node)
    return controls^


def test_defaults_are_three_js() raises:
    var controls = TransformControls()
    assert_false(Bool(controls.node))
    assert_true(controls.enabled)
    assert_true(controls.axis == NO_HANDLE)
    assert_true(controls.mode == TRANSLATE_MODE)
    assert_true(controls.space == WORLD_SPACE)
    assert_false(Bool(controls.translation_snap))
    assert_false(Bool(controls.rotation_snap))
    assert_false(Bool(controls.scale_snap))
    assert_equal(controls.size, 1.0)
    assert_false(controls.dragging)
    assert_true(controls.show_x and controls.show_y and controls.show_z)


def test_translate_along_x_in_the_world() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    _drag(controls, camera, scene, 67, 49, 8, 3, HANDLE_X)
    _assert_vector(scene.get(_last(scene)).position, 1.592724, 0.2, -0.3)


def test_a_move_is_kept_in_the_limits() raises:
    # three.js's `minX` to `maxZ`: every coordinate is kept, whichever axis
    # is dragged.
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    controls.max_x = Length(1.0, METER)
    controls.min_y = Length(0.5, METER)
    _drag(controls, camera, scene, 67, 49, 8, 3, HANDLE_X)
    _assert_vector(scene.get(_last(scene)).position, 1.0, 0.5, -0.3)


def test_the_handles_take_their_colors() raises:
    # three.js's `setColors`: no handle is red, green or blue after.
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    var x = Color(10, 20, 30)
    controls.set_colors(x, Color(40, 50, 60), Color(70, 80, 90), Color(1, 2, 3))
    assert_true(controls.x_color.r == x.r and controls.x_color.b == x.b)
    var colors = (
        controls.gizmo(camera, scene).clone_attribute(String(COLOR)).data.copy()
    )
    var tint = FloatColor(srgb=x)
    var found = False
    for at in range(0, len(colors), 3):
        assert_false(
            colors[at] == 1 and colors[at + 1] == 0 and colors[at + 2] == 0
        )
        if (
            abs(colors[at] - tint.r) < 1e-6
            and abs(colors[at + 2] - tint.b) < 1e-6
        ):
            found = True
    assert_true(found, "the x handles did not take their color")


def test_the_helper_lines() raises:
    # three.js's helper objects: an axis line while a handle is picked, and
    # a move's line from where the drag began while it is dragged.
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    assert_equal(
        len(
            controls.helper(camera, scene)
            .clone_attribute(String(POSITION))
            .data
        ),
        0,
    )
    _ = controls.handle(
        _event(POINTER_MOVE, 67, 49, NO_BUTTON), camera, scene, SIZE, SIZE
    )
    var lines = (
        controls.helper(camera, scene)
        .clone_attribute(String(POSITION))
        .data.copy()
    )
    assert_equal(len(lines), 6)
    _ = controls.handle(_event(POINTER_DOWN, 67, 49), camera, scene, SIZE, SIZE)
    _ = controls.handle(_event(POINTER_MOVE, 75, 52), camera, scene, SIZE, SIZE)
    scene.update()
    lines = (
        controls.helper(camera, scene)
        .clone_attribute(String(POSITION))
        .data.copy()
    )
    assert_equal(len(lines), 12)
    # The move's line ends where the node is.
    var node = scene.world_position(_last(scene))
    assert_almost_equal(lines[3], node.x, atol=1e-5)
    # A turn's axis line shows while its ring is picked.
    controls.mode = ROTATE_MODE
    lines = (
        controls.helper(camera, scene)
        .clone_attribute(String(POSITION))
        .data.copy()
    )
    assert_equal(len(lines), 6)
    # A free turn's line shows only while it is dragged, and the eye's ring
    # has none.
    controls.dragging = False
    controls.axis = HANDLE_XYZE
    assert_equal(
        len(
            controls.helper(camera, scene)
            .clone_attribute(String(POSITION))
            .data
        ),
        0,
    )
    controls.dragging = True
    assert_equal(
        len(
            controls.helper(camera, scene)
            .clone_attribute(String(POSITION))
            .data
        ),
        6,
    )
    controls.axis = HANDLE_E
    assert_equal(
        len(
            controls.helper(camera, scene)
            .clone_attribute(String(POSITION))
            .data
        ),
        0,
    )
    # A scale's drag has its axis line and no line from the start.
    controls.mode = SCALE_MODE
    controls.axis = HANDLE_X
    assert_equal(
        len(
            controls.helper(camera, scene)
            .clone_attribute(String(POSITION))
            .data
        ),
        6,
    )
    controls.dragging = False
    controls.detach()
    assert_equal(
        len(
            controls.helper(camera, scene)
            .clone_attribute(String(POSITION))
            .data
        ),
        0,
    )


def test_translate_on_a_local_plane_with_a_snap() raises:
    var scene = _scene(parent=True, turn=True)
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, LOCAL_SPACE, _last(scene))
    controls.translation_snap = Length(0.25, METER)
    _drag(controls, camera, scene, 80, 38, 6, -4, HANDLE_XY)
    _assert_vector(scene.get(_last(scene)).position, 0.861122, 0.25, -0.508494)


def test_translate_freely_on_the_camera_plane() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    _drag(controls, camera, scene, 58, 47, 7, 2, HANDLE_XYZ)
    _assert_vector(
        scene.get(_last(scene)).position, 1.367991, 0.067260, -0.812291
    )


def test_translate_with_a_world_snap_under_a_parent() raises:
    var scene = _scene(parent=True)
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    controls.translation_snap = Length(0.5, METER)
    _drag(controls, camera, scene, 78, 31, 3, -9, HANDLE_Y)
    _assert_vector(scene.get(_last(scene)).position, 0.597091, 0.5, -0.3)


def test_translate_along_a_local_z() raises:
    var scene = _scene(parent=True, turn=True)
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, LOCAL_SPACE, _last(scene))
    _drag(controls, camera, scene, 79, 44, 5, 5, HANDLE_Z)
    _assert_vector(scene.get(_last(scene)).position, 0.964195, 0.2, 0.504009)


def test_translate_on_the_yz_and_xz_planes() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    _drag(controls, camera, scene, 56, 45, -4, 6, HANDLE_YZ)
    _assert_vector(scene.get(_last(scene)).position, 0.5, 0.100137, 0.682177)
    scene = _scene()
    controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    _drag(controls, camera, scene, 59, 49, 5, 5, HANDLE_XZ)
    _assert_vector(scene.get(_last(scene)).position, 1.409445, 0.2, 0.070771)


def test_rotate_about_the_world_x() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(ROTATE_MODE, WORLD_SPACE, _last(scene))
    _drag(controls, camera, scene, 58, 35, 6, 4, HANDLE_X)
    _assert_turn(scene.get(_last(scene)).quaternion, 0.110470, 0, 0, 0.993879)


def test_rotate_about_a_local_z_with_a_snap() raises:
    var scene = _scene(parent=True, turn=True)
    var camera = _camera()
    var controls = _controls(ROTATE_MODE, LOCAL_SPACE, _last(scene))
    controls.rotation_snap = Angle(15.0, DEGREE)
    _drag(controls, camera, scene, 88, 35, -6, 4, HANDLE_Z)
    _assert_turn(
        scene.get(_last(scene)).quaternion,
        0.205335,
        0.157559,
        0.766320,
        0.588018,
    )


def test_rotate_about_a_local_y() raises:
    var scene = _scene(turn=True)
    var camera = _camera()
    var controls = _controls(ROTATE_MODE, LOCAL_SPACE, _last(scene))
    _drag(controls, camera, scene, 70, 47, -5, 3, HANDLE_Y)
    _assert_turn(scene.get(_last(scene)).quaternion, 0, -0.610134, 0, 0.792298)


def test_rotate_about_the_line_of_sight() raises:
    var scene = _scene(parent=True)
    var camera = _camera()
    var controls = _controls(ROTATE_MODE, WORLD_SPACE, _last(scene))
    _drag(controls, camera, scene, 97, 46, -6, 4, HANDLE_E)
    _assert_turn(
        scene.get(_last(scene)).quaternion,
        -0.114498,
        -0.056060,
        -0.265607,
        0.955615,
    )


def test_rotate_freely_with_the_ball() raises:
    var scene = _scene(parent=True)
    var camera = _camera()
    var controls = _controls(ROTATE_MODE, WORLD_SPACE, _last(scene))
    _drag(controls, camera, scene, 77, 42, 6, 4, HANDLE_XYZE)
    _assert_turn(
        scene.get(_last(scene)).quaternion,
        0.395595,
        0.735865,
        -0.325848,
        0.442528,
    )


def test_rotate_about_an_axis_along_the_line_of_sight() raises:
    var scene = _scene(position=Vector3(0, 0, 0))
    var camera = _camera(Vector3(0, 0, 5))
    var controls = _controls(ROTATE_MODE, WORLD_SPACE, _last(scene))
    _drag(controls, camera, scene, 58, 41, 6, 4, HANDLE_Z)
    _assert_turn(scene.get(_last(scene)).quaternion, 0, 0, -0.280828, 0.959758)


def test_scale_along_x_with_a_snap() raises:
    var scene = _scene(turn=True)
    var camera = _camera()
    var controls = _controls(SCALE_MODE, WORLD_SPACE, _last(scene))
    controls.scale_snap = Float32(0.5)
    _drag(controls, camera, scene, 68, 47, 12, 2, HANDLE_X)
    _assert_vector(scene.get(_last(scene)).scale, 3.5, 1, 1)


def test_scale_evenly() raises:
    var scene = _scene(turn=True)
    var camera = _camera()
    var controls = _controls(SCALE_MODE, WORLD_SPACE, _last(scene))
    _drag(controls, camera, scene, 58, 47, 6, -6, HANDLE_XYZ)
    var scale = scene.get(_last(scene)).scale
    assert_almost_equal(scale.x, 34.055764, rtol=1e-3)
    assert_equal(scale.x, scale.y)
    assert_equal(scale.x, scale.z)


def test_scale_through_the_center_turns_the_node_inside_out() raises:
    var scene = _scene(turn=True)
    var camera = _camera()
    var controls = _controls(SCALE_MODE, WORLD_SPACE, _last(scene))
    _drag(controls, camera, scene, 58, 47, -3, 1, HANDLE_XYZ)
    var scale = scene.get(_last(scene)).scale
    assert_almost_equal(scale.x, -14.002998, rtol=1e-3)
    assert_equal(scale.x, scale.z)


def test_scale_on_a_plane() raises:
    var scene = _scene(parent=True, turn=True)
    var camera = _camera()
    var controls = _controls(SCALE_MODE, WORLD_SPACE, _last(scene))
    _drag(controls, camera, scene, 80, 38, 5, -3, HANDLE_XY)
    _assert_vector(scene.get(_last(scene)).scale, 3.778776, 1.062920, 1)


def test_translate_seen_through_an_orthographic_camera() raises:
    var scene = _scene()
    var camera = OrthographicCamera(
        Length(-2.0, METER),
        Length(2.0, METER),
        Length(2.0, METER),
        Length(-2.0, METER),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(4, 3, 6), Vector3(0, 0, 0))
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    _drag(controls, camera, scene, 64, 35, 2, -7, HANDLE_Y)
    _assert_vector(scene.get(_last(scene)).position, 0.5, 0.503264, -0.3)
    scene.update()
    var frame = TransformFrame(camera, scene, _last(scene))
    assert_almost_equal(frame.factor, 4.0, atol=TOLERANCE)
    _assert_vector(frame.eye, 0.512148, 0.384111, 0.768221)


def test_the_frame_matches_three_js() raises:
    var scene = _scene(parent=True)
    var frame = TransformFrame(_camera(), scene, _last(scene))
    assert_almost_equal(frame.factor, 6.486188, atol=TOLERANCE)
    _assert_vector(frame.eye, 0.300116, 0.311725, 0.901531)
    _assert_vector(frame.parent.scale, 2, 2, 2)
    _assert_vector(frame.parent.position, 1, 0, 0)


def test_decompose_a_mirror_and_refuse_a_flat_transform() raises:
    var mirrored = decompose(scaling(-2, 3, 4))
    _assert_vector(mirrored.scale, -2, 3, 4)
    _assert_turn(mirrored.quaternion, 0, 0, 0, 1)
    with assert_raises(contains="flattens an axis"):
        _ = decompose(scaling(1, 0, 1))


def test_a_press_away_from_the_handles_starts_no_drag() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    var events = controls.handle(
        _event(POINTER_DOWN, 5, 5), camera, scene, SIZE, SIZE
    )
    _kinds(events, [])
    assert_false(controls.dragging)
    events = controls.handle(
        _event(POINTER_MOVE, 10, 10), camera, scene, SIZE, SIZE
    )
    _kinds(events, [])
    events = controls.handle(
        _event(POINTER_UP, 10, 10), camera, scene, SIZE, SIZE
    )
    _kinds(events, [])


def test_a_press_with_another_button_only_picks() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    var events = controls.handle(
        _event(POINTER_DOWN, 67, 49, SECONDARY), camera, scene, SIZE, SIZE
    )
    _kinds(events, [AXIS_CHANGED])
    assert_false(controls.dragging)
    # A release of that button changes nothing.
    events = controls.handle(
        _event(POINTER_UP, 67, 49, SECONDARY), camera, scene, SIZE, SIZE
    )
    _kinds(events, [])
    assert_true(controls.axis == HANDLE_X)


def test_a_second_press_during_a_drag_is_ignored() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    _ = controls.handle(_event(POINTER_DOWN, 67, 49), camera, scene, SIZE, SIZE)
    assert_true(controls.dragging)
    var events = controls.handle(
        _event(POINTER_DOWN, 20, 20), camera, scene, SIZE, SIZE
    )
    _kinds(events, [])
    assert_true(controls.axis == HANDLE_X)


def test_reset_puts_the_node_back() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    assert_equal(len(controls.reset(scene)), 0)
    _ = controls.handle(_event(POINTER_DOWN, 67, 49), camera, scene, SIZE, SIZE)
    _ = controls.handle(_event(POINTER_MOVE, 75, 52), camera, scene, SIZE, SIZE)
    _assert_vector(scene.get(_last(scene)).position, 1.091667, 0.2, -0.3)
    var events = controls.reset(scene)
    _kinds(events, [OBJECT_CHANGE])
    _assert_vector(scene.get(_last(scene)).position, 0.5, 0.2, -0.3)
    # The drag goes on from where the pointer was.
    _ = controls.handle(_event(POINTER_MOVE, 75, 52), camera, scene, SIZE, SIZE)
    _assert_vector(scene.get(_last(scene)).position, 0.5, 0.2, -0.3)


def test_a_drag_with_no_axis_does_nothing() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    _ = controls.handle(_event(POINTER_DOWN, 67, 49), camera, scene, SIZE, SIZE)
    controls.axis = NO_HANDLE
    var events = controls.handle(
        _event(POINTER_MOVE, 75, 52), camera, scene, SIZE, SIZE
    )
    _kinds(events, [])
    _assert_vector(scene.get(_last(scene)).position, 0.5, 0.2, -0.3)
    events = controls.handle(
        _event(POINTER_UP, 75, 52), camera, scene, SIZE, SIZE
    )
    _kinds(events, [DRAGGING_CHANGED])


def test_a_move_off_the_plane_does_nothing() raises:
    # The camera looks straight down z at the node, and the drag follows
    # the camera plane. A move to a pixel whose ray runs away from it,
    # which only a camera inside the gizmo sees, is simulated by moving
    # the camera behind the node before the move.
    var scene = _scene(position=Vector3(0, 0, 0))
    var camera = _camera(Vector3(0, 0, 5))
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    _ = controls.handle(_event(POINTER_DOWN, 50, 50), camera, scene, SIZE, SIZE)
    assert_true(controls.axis == HANDLE_XYZ)
    var away = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    away.place(Vector3(0, 0, 5), Vector3(0, 0, 10))
    var events = controls.handle(
        _event(POINTER_MOVE, 60, 50), away, scene, SIZE, SIZE
    )
    _kinds(events, [])


def test_detached_or_disabled_controls_do_nothing() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = TransformControls()
    var events = controls.handle(
        _event(POINTER_MOVE, 67, 49), camera, scene, SIZE, SIZE
    )
    _kinds(events, [])
    assert_equal(
        len(
            controls.gizmo(camera, scene)
            .clone_attribute(String(POSITION))
            .data.copy()
        ),
        0,
    )
    controls.attach(_last(scene))
    _ = controls.handle(_event(POINTER_MOVE, 67, 49), camera, scene, SIZE, SIZE)
    assert_true(controls.axis == HANDLE_X)
    controls.detach()
    assert_true(controls.axis == NO_HANDLE)
    assert_false(Bool(controls.node))
    controls.attach(_last(scene))
    controls.enabled = False
    events = controls.handle(
        _event(POINTER_DOWN, 67, 49), camera, scene, SIZE, SIZE
    )
    _kinds(events, [])
    assert_equal(len(controls.reset(scene)), 0)
    events = controls.handle(
        InputEvent(KEY_DOWN, key=Key(119)), camera, scene, SIZE, SIZE
    )
    _kinds(events, [])


def test_other_events_do_nothing() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    var events = controls.handle(
        InputEvent(KEY_DOWN, key=Key(119)), camera, scene, SIZE, SIZE
    )
    _kinds(events, [])


def test_hidden_axes_are_not_picked() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    controls.show_x = False
    var events = controls.handle(
        _event(POINTER_MOVE, 67, 49), camera, scene, SIZE, SIZE
    )
    assert_true(controls.axis != HANDLE_X)
    # Looking straight down z hides the z axis and the planes seen edge-on.
    scene = _scene(position=Vector3(0, 0, 0))
    var above = _camera(Vector3(0, 0, 5))
    controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    var gizmo = controls.gizmo(above, scene)
    # X and Y: a shaft and two cones of 8 rim and 8 spoke segments each.
    # The octahedron has 12 edges and the XY square 4.
    assert_equal(
        len(gizmo.clone_attribute(String(POSITION)).data), (2 * 33 + 12 + 4) * 6
    )
    _ = events^


def test_the_gizmo_of_each_mode() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    var gizmo = controls.gizmo(camera, scene)
    assert_equal(
        len(gizmo.clone_attribute(String(POSITION)).data),
        (3 * 33 + 12 + 12) * 6,
    )
    assert_equal(
        len(gizmo.clone_attribute(String(COLOR)).data), (3 * 33 + 12 + 12) * 6
    )
    controls.mode = SCALE_MODE
    gizmo = controls.gizmo(camera, scene)
    # A shaft and two boxes of 12 edges each, three planes, and a box.
    assert_equal(
        len(gizmo.clone_attribute(String(POSITION)).data),
        (3 * 25 + 12 + 12) * 6,
    )
    controls.mode = ROTATE_MODE
    gizmo = controls.gizmo(camera, scene)
    assert_equal(len(gizmo.clone_attribute(String(POSITION)).data), 5 * 32 * 6)
    # With y hidden, the y ring and the two rings of every axis go too.
    controls.show_y = False
    gizmo = controls.gizmo(camera, scene)
    assert_equal(len(gizmo.clone_attribute(String(POSITION)).data), 2 * 32 * 6)
    controls.show_y = True
    controls.show_z = False
    gizmo = controls.gizmo(camera, scene)
    assert_equal(len(gizmo.clone_attribute(String(POSITION)).data), 2 * 32 * 6)


def test_the_gizmo_follows_the_node_and_the_view() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    controls.size = 2
    var gizmo = controls.gizmo(camera, scene)
    var points = gizmo.clone_attribute(String(POSITION)).data.copy()
    # The x shaft runs from the node half a handle along x: a handle is a
    # quarter of the factor, times the size.
    var reach = Float32(6.850213) * 2 / 4 * 0.5
    assert_almost_equal(points[0], 0.5, atol=TOLERANCE)
    assert_almost_equal(points[3], 0.5 + reach, atol=TOLERANCE)
    assert_almost_equal(points[4], 0.2, atol=TOLERANCE)
    var colors = gizmo.clone_attribute(String(COLOR)).data.copy()
    # Red, as linear light.
    assert_almost_equal(colors[0], 1, atol=TOLERANCE)
    assert_almost_equal(colors[1], 0, atol=TOLERANCE)


def test_the_handle_under_the_pointer_is_yellow() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    controls.axis = HANDLE_XY
    var gizmo = controls.gizmo(camera, scene)
    var colors = gizmo.clone_attribute(String(COLOR)).data.copy()
    # The x axis is a letter of XY, so it is yellow.
    assert_almost_equal(colors[0], 1, atol=TOLERANCE)
    assert_almost_equal(colors[1], 1, atol=TOLERANCE)
    assert_almost_equal(colors[2], 0, atol=TOLERANCE)
    # The z axis is not.
    var z_first = 2 * 33 * 6
    assert_almost_equal(colors[z_first], 0, atol=TOLERANCE)
    assert_almost_equal(colors[z_first + 2], 1, atol=TOLERANCE)
    controls.enabled = False
    gizmo = controls.gizmo(camera, scene)
    var plain = gizmo.clone_attribute(String(COLOR)).data.copy()
    assert_almost_equal(plain[1], 0, atol=TOLERANCE)


def test_the_drag_plane_of_each_handle() raises:
    var scene = _scene(position=Vector3(0, 0, 0))
    var camera = _camera()
    var frame = TransformFrame(camera, scene, _last(scene))
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    controls.axis = HANDLE_XY
    _assert_vector(controls.plane(frame).normal, 0, 0, 1)
    controls.axis = HANDLE_YZ
    _assert_vector(controls.plane(frame).normal, 1, 0, 0)
    controls.axis = HANDLE_XZ
    _assert_vector(controls.plane(frame).normal, 0, 1, 0)
    controls.axis = HANDLE_X
    # The part of the eye's direction across x.
    var eye = frame.eye
    var across = Vector3(0, eye.y, eye.z)
    across.normalize()
    var normal = controls.plane(frame).normal
    assert_almost_equal(abs(normal.dot(across)), 1, atol=TOLERANCE)
    controls.axis = HANDLE_XYZ
    normal = controls.plane(frame).normal
    assert_almost_equal(abs(normal.dot(eye)), 1, atol=TOLERANCE)
    controls.mode = ROTATE_MODE
    controls.axis = HANDLE_X
    normal = controls.plane(frame).normal
    assert_almost_equal(abs(normal.dot(eye)), 1, atol=TOLERANCE)


def test_settings_are_checked() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    controls.mode = TransformMode(3)
    with assert_raises(contains="Invalid transform mode"):
        controls.check()
    controls.mode = ROTATE_MODE
    controls.space = TransformSpace(2)
    with assert_raises(contains="Invalid transform space"):
        controls.check()
    controls.space = LOCAL_SPACE
    controls.axis = TransformAxis(10)
    with assert_raises(contains="Invalid transform axis"):
        controls.check()
    controls.axis = HANDLE_XY
    with assert_raises(contains="has no handle XY"):
        controls.check()
    controls.axis = HANDLE_E
    controls.check()
    controls.size = 0
    with assert_raises(contains="size must be positive"):
        controls.check()
    controls.size = nan[DType.float32]()
    with assert_raises(contains="size must be positive"):
        controls.check()
    controls.size = 1
    controls.translation_snap = Length(0.0, METER)
    with assert_raises(contains="translation snap"):
        controls.check()
    controls.translation_snap = None
    controls.rotation_snap = Angle(-1.0, DEGREE)
    with assert_raises(contains="rotation snap"):
        controls.check()
    controls.rotation_snap = None
    controls.scale_snap = Float32(0)
    with assert_raises(contains="scale snap"):
        controls.check()
    with assert_raises(contains="scale snap"):
        _ = controls.gizmo(camera, scene)


def test_invalid_input_is_refused() raises:
    var scene = _scene()
    var camera = _camera()
    var controls = _controls(TRANSLATE_MODE, WORLD_SPACE, _last(scene))
    with assert_raises(contains="Invalid input kind"):
        _ = controls.handle(InputEvent(InputKind(9)), camera, scene, SIZE, SIZE)
    with assert_raises(contains="Invalid pointer button"):
        _ = controls.handle(
            _event(POINTER_DOWN, 0, 0, PointerButton(5)),
            camera,
            scene,
            SIZE,
            SIZE,
        )
    with assert_raises(contains="Invalid key"):
        _ = controls.handle(
            InputEvent(KEY_DOWN, key=Key(999)), camera, scene, SIZE, SIZE
        )
    controls.mode = TransformMode(7)
    with assert_raises(contains="Invalid transform mode"):
        _ = controls.handle(
            _event(POINTER_DOWN, 0, 0), camera, scene, SIZE, SIZE
        )
    controls.mode = TRANSLATE_MODE
    with assert_raises(contains="positive width and height"):
        _ = controls.handle(_event(POINTER_DOWN, 0, 0), camera, scene, 0, SIZE)
    with assert_raises(contains="positive width and height"):
        _ = controls.handle(_event(POINTER_DOWN, 0, 0), camera, scene, SIZE, 0)
    controls.attach(NodeId(9))
    with assert_raises():
        _ = controls.handle(
            _event(POINTER_DOWN, 0, 0), camera, scene, SIZE, SIZE
        )


def test_the_types_are_checked() raises:
    assert_true(TRANSLATE_MODE.is_valid())
    assert_true(SCALE_MODE.is_valid())
    assert_false(TransformMode(3).is_valid())
    assert_false(TransformMode(-1).is_valid())
    assert_true(WORLD_SPACE.is_valid())
    assert_true(LOCAL_SPACE.is_valid())
    assert_false(TransformSpace(2).is_valid())
    assert_true(NO_HANDLE.is_valid())
    assert_true(HANDLE_XYZE.is_valid())
    assert_false(TransformAxis(10).is_valid())
    assert_false(TransformAxis(-1).is_valid())
    assert_true(AXIS_CHANGED.is_valid())
    assert_true(MOUSE_UP.is_valid())
    assert_false(TransformEventKind(5).is_valid())
    assert_false(TransformEventKind(-1).is_valid())
    assert_equal(HANDLE_XYZE.name(), "XYZE")
    assert_equal(NO_HANDLE.name(), "")
    assert_true(HANDLE_XZ.has("Z"))
    assert_false(HANDLE_XZ.has("Y"))
    with assert_raises(contains="Invalid transform axis"):
        _ = TransformAxis(12).name()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
