# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the touch input of `controls.drag_controls` and of
`controls.transform_controls`.

three.js r180 gives a finger the arithmetic of a mouse button in both
controls. So each test holds a finger to the numbers three.js gives the
same drag of the mouse, which the suites of the two controls record.

The drag scene is a unit cube at the origin, seen by a 90-degree camera
five meters up +z through a view of 100 by 100 pixels. The transform scene
is a node at (0.5, 0.2, -0.3), seen by a 50-degree camera at (4, 3, 6).
"""

from cameras.perspective_camera import PerspectiveCamera
from controls.drag_controls import (
    DRAG_END,
    DRAG_MOVE,
    DRAG_ROTATE,
    DRAG_START,
    DRAG_TRANSLATE,
    DragAction,
    DragControls,
    DragEvent,
    DragEventKind,
    HOVER_ON,
)
from controls.input import (
    InputEvent,
    InputKind,
    NO_BUTTON,
    POINTER_CANCEL,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PointerId,
    PointerType,
    SECONDARY,
    TOUCH_POINTER,
    touch_event,
)
from controls.transform_controls import (
    AXIS_CHANGED,
    DRAGGING_CHANGED,
    HANDLE_X,
    MOUSE_DOWN,
    MOUSE_UP,
    NO_HANDLE,
    OBJECT_CHANGE,
    TRANSLATE_MODE,
    TransformControls,
    TransformEvent,
    TransformEventKind,
    WORLD_SPACE,
)
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-3)
comptime SIZE = 100
comptime A = NodeId(0)


def _camera(fov: Float32, eye: Vector3) raises -> PerspectiveCamera:
    """Return a camera that looks at the origin.

    Args:
        fov: Its field of view, in degrees.
        eye: Where it stands.

    Returns:
        The camera.

    Raises:
        Error: If the camera is refused.
    """
    var camera = PerspectiveCamera(
        Angle(fov, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(eye, Vector3(0, 0, 0))
    return camera^


def _cube_scene(mut assets: Assets) raises -> Scene:
    """Return a scene with a unit cube at the origin, as node 0.

    Args:
        assets: Where the cube and its material go.

    Returns:
        The scene.

    Raises:
        Error: If the scene is refused.
    """
    var scene = Scene()
    var geometry = assets.geometries.add(cube(Length(1.0, METER)))
    var material = assets.materials.add(Material(Color(255, 255, 255)))
    var a = scene.add(Object3D())
    scene.update()
    scene.add_mesh(Mesh(geometry, material, a))
    return scene^


def _finger(kind: InputKind, x: Int, y: Int) -> InputEvent:
    """Return the event of finger 1.

    Args:
        kind: What the finger did.
        x: The pixel's column.
        y: The pixel's row.

    Returns:
        The event.
    """
    return touch_event(kind, PointerId(1), x, y)


def _dragged(events: List[DragEvent], kinds: List[DragEventKind]) raises:
    """Assert the events are these kinds, about the cube.

    Args:
        events: The events returned.
        kinds: The kinds expected.

    Raises:
        Error: If they differ.
    """
    assert_equal(len(events), len(kinds))
    for index in range(len(kinds)):
        assert_true(events[index].kind == kinds[index])
        assert_true(events[index].node == A)


def _transformed(
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


# --- DragControls ------------------------------------------------------------


def test_a_finger_translates_as_the_primary_button_does() raises:
    var assets = Assets()
    var scene = _cube_scene(assets)
    var camera = _camera(90, Vector3(0, 0, 5))
    var controls = DragControls([A])
    assert_true(controls.touch_action == DRAG_TRANSLATE)
    var events = controls.handle(
        _finger(POINTER_DOWN, 50, 50), camera, scene, assets, SIZE, SIZE
    )
    _dragged(events, [DRAG_START])
    events = controls.handle(
        _finger(POINTER_MOVE, 60, 45), camera, scene, assets, SIZE, SIZE
    )
    _dragged(events, [DRAG_MOVE])
    var position = scene.get(A).position
    assert_almost_equal(position.x, Float32(1.0), atol=TOLERANCE)
    assert_almost_equal(position.y, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(position.z, Float32(0.0), atol=TOLERANCE)
    events = controls.handle(
        _finger(POINTER_UP, 60, 45), camera, scene, assets, SIZE, SIZE
    )
    _dragged(events, [DRAG_END])
    assert_false(Bool(controls.selected()))


def test_a_finger_can_rotate() raises:
    var assets = Assets()
    var scene = _cube_scene(assets)
    var camera = _camera(90, Vector3(0, 0, 5))
    var controls = DragControls([A])
    controls.touch_action = DRAG_ROTATE
    _ = controls.handle(
        _finger(POINTER_DOWN, 50, 50), camera, scene, assets, SIZE, SIZE
    )
    var events = controls.handle(
        _finger(POINTER_MOVE, 60, 40), camera, scene, assets, SIZE, SIZE
    )
    _dragged(events, [DRAG_MOVE])
    # The numbers three.js gives this drag of the secondary button.
    var turn = scene.get(A).quaternion
    assert_almost_equal(turn.x, Float32(-0.099335), atol=TOLERANCE)
    assert_almost_equal(turn.y, Float32(0.099335), atol=TOLERANCE)
    assert_almost_equal(turn.z, Float32(-0.009967), atol=TOLERANCE)
    assert_almost_equal(turn.w, Float32(0.990033), atol=TOLERANCE)


def test_a_finger_does_not_hover() raises:
    var assets = Assets()
    var scene = _cube_scene(assets)
    var camera = _camera(90, Vector3(0, 0, 5))
    var controls = DragControls([A])
    var events = controls.handle(
        _finger(POINTER_MOVE, 50, 50), camera, scene, assets, SIZE, SIZE
    )
    _dragged(events, [])
    assert_false(Bool(controls.hovered()))
    # A mouse over the same pixel does.
    events = controls.handle(
        InputEvent(POINTER_MOVE, button=NO_BUTTON, x=50, y=50),
        camera,
        scene,
        assets,
        SIZE,
        SIZE,
    )
    _dragged(events, [HOVER_ON])


def test_a_cancel_lets_the_object_go() raises:
    var assets = Assets()
    var scene = _cube_scene(assets)
    var camera = _camera(90, Vector3(0, 0, 5))
    var controls = DragControls([A])
    _ = controls.handle(
        _finger(POINTER_DOWN, 50, 50), camera, scene, assets, SIZE, SIZE
    )
    var events = controls.handle(
        _finger(POINTER_CANCEL, 50, 50), camera, scene, assets, SIZE, SIZE
    )
    _dragged(events, [DRAG_END])
    assert_false(Bool(controls.selected()))


def test_an_invalid_touch_is_refused() raises:
    var assets = Assets()
    var scene = _cube_scene(assets)
    var camera = _camera(90, Vector3(0, 0, 5))
    var controls = DragControls([A])
    controls.touch_action = DragAction(9)
    with assert_raises(contains="drag action"):
        _ = controls.handle(
            _finger(POINTER_DOWN, 50, 50), camera, scene, assets, SIZE, SIZE
        )
    controls.touch_action = DRAG_TRANSLATE
    with assert_raises(contains="pointer type"):
        _ = controls.handle(
            InputEvent(POINTER_DOWN, pointer_type=PointerType(5)),
            camera,
            scene,
            assets,
            SIZE,
            SIZE,
        )
    with assert_raises(contains="pointer id"):
        _ = controls.handle(
            InputEvent(POINTER_DOWN, pointer_id=PointerId(-3)),
            camera,
            scene,
            assets,
            SIZE,
            SIZE,
        )


# --- TransformControls -------------------------------------------------------


def _node_scene() raises -> Scene:
    """Return a scene with one node at (0.5, 0.2, -0.3).

    Returns:
        The scene, updated.

    Raises:
        Error: If the scene is refused.
    """
    var scene = Scene()
    var node = Object3D()
    node.position = Vector3(0.5, 0.2, -0.3)
    _ = scene.add(node^)
    scene.update()
    return scene^


def test_a_finger_picks_a_handle_and_drags_it_at_once() raises:
    var scene = _node_scene()
    var camera = _camera(50, Vector3(4, 3, 6))
    var controls = TransformControls()
    controls.mode = TRANSLATE_MODE
    controls.space = WORLD_SPACE
    controls.attach(A)
    # No move comes first: the press picks the handle and starts the drag.
    var events = controls.handle(
        _finger(POINTER_DOWN, 67, 49), camera, scene, SIZE, SIZE
    )
    _transformed(events, [AXIS_CHANGED, DRAGGING_CHANGED, MOUSE_DOWN])
    assert_true(controls.axis == HANDLE_X)
    events = controls.handle(
        _finger(POINTER_MOVE, 75, 52), camera, scene, SIZE, SIZE
    )
    _transformed(events, [OBJECT_CHANGE])
    events = controls.handle(
        _finger(POINTER_MOVE, 83, 52), camera, scene, SIZE, SIZE
    )
    _transformed(events, [OBJECT_CHANGE])
    # The numbers three.js gives the same drag of the primary button.
    var position = scene.get(A).position
    assert_almost_equal(position.x, Float32(1.592724), atol=TOLERANCE)
    assert_almost_equal(position.y, Float32(0.2), atol=TOLERANCE)
    assert_almost_equal(position.z, Float32(-0.3), atol=TOLERANCE)
    events = controls.handle(
        _finger(POINTER_UP, 83, 52), camera, scene, SIZE, SIZE
    )
    _transformed(events, [MOUSE_UP, DRAGGING_CHANGED, AXIS_CHANGED])
    assert_true(controls.axis == NO_HANDLE)


def test_a_finger_that_moves_picks_no_handle() raises:
    var scene = _node_scene()
    var camera = _camera(50, Vector3(4, 3, 6))
    var controls = TransformControls()
    controls.attach(A)
    var events = controls.handle(
        _finger(POINTER_MOVE, 67, 49), camera, scene, SIZE, SIZE
    )
    _transformed(events, [])
    assert_true(controls.axis == NO_HANDLE)
    # A mouse over the same pixel does.
    events = controls.handle(
        InputEvent(POINTER_MOVE, button=NO_BUTTON, x=67, y=49),
        camera,
        scene,
        SIZE,
        SIZE,
    )
    _transformed(events, [AXIS_CHANGED])


def test_a_finger_is_the_primary_button_whatever_its_event_says() raises:
    var scene = _node_scene()
    var camera = _camera(50, Vector3(4, 3, 6))
    var controls = TransformControls()
    controls.attach(A)
    var press = InputEvent(
        POINTER_DOWN,
        button=SECONDARY,
        x=67,
        y=49,
        pointer_type=TOUCH_POINTER,
    )
    var events = controls.handle(press, camera, scene, SIZE, SIZE)
    _transformed(events, [AXIS_CHANGED, DRAGGING_CHANGED, MOUSE_DOWN])
    var release = InputEvent(
        POINTER_UP,
        button=SECONDARY,
        x=67,
        y=49,
        pointer_type=TOUCH_POINTER,
    )
    events = controls.handle(release, camera, scene, SIZE, SIZE)
    _transformed(events, [MOUSE_UP, DRAGGING_CHANGED, AXIS_CHANGED])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
