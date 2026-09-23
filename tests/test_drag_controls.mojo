# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `controls.drag_controls`.

The expected numbers come from three.js r180's own `DragControls`, run
headless in Node on the same scene: a unit cube `a` at the origin, and a
unit cube `b` one meter along x inside a node `g` that stands one meter up
and is scaled two times. A camera five meters up +z with a 90-degree view
looks at the origin, through a view of 100 by 100 pixels. Each event was
given at the center of its pixel.
"""

from cameras.orthographic_camera import centered
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
    HOVER_OFF,
    HOVER_ON,
    NO_DRAG,
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
    SECONDARY,
    WHEEL,
)
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from materials.material import DOUBLE_SIDE, Material
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

comptime TOLERANCE = Float64(1e-4)
comptime SIZE = 100
comptime A = NodeId(0)
comptime G = NodeId(1)
comptime B = NodeId(2)


def _camera() raises -> PerspectiveCamera:
    """Return a 90-degree camera five meters up +z, looking at the origin.

    Returns:
        The camera.

    Raises:
        Error: If the camera is refused.
    """
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera^


def _scene(mut assets: Assets) raises -> Scene:
    """Return the scene of the module docstring.

    Args:
        assets: Where the cube and its material go.

    Returns:
        The scene: `a` is node 0, `g` node 1 and `b` node 2.

    Raises:
        Error: If the scene is refused.
    """
    var scene = Scene()
    var geometry = assets.geometries.add(cube(Length(1.0, METER)))
    var material = assets.materials.add(Material(Color(255, 255, 255)))
    var a = scene.add(Object3D())
    var group = Object3D()
    group.set_position(0, 1, 0)
    group.set_scale(2, 2, 2)
    var g = scene.add(group^)
    var inner = Object3D()
    inner.set_position(1, 0, 0)
    var b = scene.attach(inner^, g)
    scene.update()
    scene.add_mesh(Mesh(geometry, material, a))
    scene.add_mesh(Mesh(geometry, material, b))
    return scene^


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


def _expect(
    events: List[DragEvent], kinds: List[DragEventKind], nodes: List[NodeId]
) raises:
    """Assert the events are these kinds, about these nodes.

    Args:
        events: The events returned.
        kinds: The kinds expected.
        nodes: The node of each.

    Raises:
        Error: If they differ.
    """
    assert_equal(len(events), len(kinds))
    for index in range(len(kinds)):
        assert_true(events[index].kind == kinds[index])
        assert_true(events[index].node == nodes[index])


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


def test_defaults_are_three_js() raises:
    var controls = DragControls([A])
    assert_true(controls.enabled)
    assert_true(controls.recursive)
    assert_false(controls.transform_group)
    assert_equal(controls.rotate_speed, 1.0)
    assert_true(controls.primary_action == DRAG_TRANSLATE)
    assert_true(controls.middle_action == DRAG_TRANSLATE)
    assert_true(controls.secondary_action == DRAG_ROTATE)
    assert_false(Bool(controls.selected()))
    assert_false(Bool(controls.hovered()))


def test_hover_on_and_off() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var camera = _camera()
    var controls = DragControls([A, G])
    var events = controls.handle(
        _event(POINTER_MOVE, 50, 50, NO_BUTTON),
        camera,
        scene,
        assets,
        SIZE,
        SIZE,
    )
    _expect(events, [HOVER_ON], [A])
    assert_true(controls.hovered().value() == A)
    events = controls.handle(
        _event(POINTER_MOVE, 50, 50, NO_BUTTON),
        camera,
        scene,
        assets,
        SIZE,
        SIZE,
    )
    _expect(events, [], [])
    events = controls.handle(
        _event(POINTER_MOVE, 74, 37, NO_BUTTON),
        camera,
        scene,
        assets,
        SIZE,
        SIZE,
    )
    _expect(events, [HOVER_OFF, HOVER_ON], [A, B])
    events = controls.handle(
        _event(POINTER_MOVE, 5, 95, NO_BUTTON),
        camera,
        scene,
        assets,
        SIZE,
        SIZE,
    )
    _expect(events, [HOVER_OFF], [B])
    events = controls.handle(
        _event(POINTER_MOVE, 5, 95, NO_BUTTON),
        camera,
        scene,
        assets,
        SIZE,
        SIZE,
    )
    _expect(events, [], [])


def test_translate_on_the_plane_facing_the_camera() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var camera = _camera()
    var controls = DragControls([A, G])
    var events = controls.handle(
        _event(POINTER_DOWN, 50, 50), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [DRAG_START], [A])
    assert_true(controls.selected().value() == A)
    events = controls.handle(
        _event(POINTER_MOVE, 60, 45), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [DRAG_MOVE], [A])
    _assert_vector(scene.get(A).position, 1.0, 0.5, 0.0)
    events = controls.handle(
        _event(POINTER_UP, 60, 45), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [DRAG_END], [A])
    assert_false(Bool(controls.selected()))


def test_translate_a_child_in_its_parents_frame() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var camera = _camera()
    var controls = DragControls([A, G])
    var events = controls.handle(
        _event(POINTER_DOWN, 74, 37), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [DRAG_START], [B])
    events = controls.handle(
        _event(POINTER_MOVE, 80, 30), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [DRAG_MOVE], [B])
    _assert_vector(scene.get(B).position, 1.3, 0.35, 0.0)
    _assert_vector(scene.get(G).position, 0.0, 1.0, 0.0)


def test_transform_group_moves_the_outermost_listed_node() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var camera = _camera()
    var controls = DragControls([A, G])
    controls.transform_group = True
    var events = controls.handle(
        _event(POINTER_DOWN, 74, 37), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [DRAG_START], [G])
    events = controls.handle(
        _event(POINTER_MOVE, 80, 30), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [DRAG_MOVE], [G])
    _assert_vector(scene.get(G).position, 0.6, 1.7, 0.0)
    _assert_vector(scene.get(B).position, 1.0, 0.0, 0.0)
    # A node with no listed node above it is moved itself.
    events = controls.handle(
        _event(POINTER_UP, 80, 30), camera, scene, assets, SIZE, SIZE
    )
    events = controls.handle(
        _event(POINTER_DOWN, 50, 50), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [DRAG_START], [A])


def test_transform_group_skips_nodes_not_listed() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var camera = _camera()
    var controls = DragControls([A, B])
    controls.transform_group = True
    var events = controls.handle(
        _event(POINTER_DOWN, 74, 37), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [DRAG_START], [B])


def test_rotate_about_the_cameras_up_and_right() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var camera = _camera()
    var controls = DragControls([A, G])
    var events = controls.handle(
        _event(POINTER_DOWN, 50, 50, SECONDARY),
        camera,
        scene,
        assets,
        SIZE,
        SIZE,
    )
    _expect(events, [DRAG_START], [A])
    events = controls.handle(
        _event(POINTER_MOVE, 60, 40, SECONDARY),
        camera,
        scene,
        assets,
        SIZE,
        SIZE,
    )
    _expect(events, [DRAG_MOVE], [A])
    var turn = scene.get(A).quaternion
    assert_almost_equal(turn.x, -0.099335, atol=TOLERANCE)
    assert_almost_equal(turn.y, 0.099335, atol=TOLERANCE)
    assert_almost_equal(turn.z, -0.009967, atol=TOLERANCE)
    assert_almost_equal(turn.w, 0.990033, atol=TOLERANCE)
    _ = controls.handle(
        _event(POINTER_MOVE, 70, 45, SECONDARY),
        camera,
        scene,
        assets,
        SIZE,
        SIZE,
    )
    turn = scene.get(A).quaternion
    assert_almost_equal(turn.x, -0.050970, atol=TOLERANCE)
    assert_almost_equal(turn.y, 0.197430, atol=TOLERANCE)
    assert_almost_equal(turn.z, 0.009880, atol=TOLERANCE)
    assert_almost_equal(turn.w, 0.978941, atol=TOLERANCE)
    _assert_vector(scene.get(A).position, 0, 0, 0)


def test_a_press_with_no_action_picks_but_moves_nothing() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var camera = _camera()
    var controls = DragControls([A, G])
    var events = controls.handle(
        _event(POINTER_DOWN, 5, 5), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [], [])
    events = controls.handle(
        _event(POINTER_DOWN, 50, 50, NO_BUTTON),
        camera,
        scene,
        assets,
        SIZE,
        SIZE,
    )
    _expect(events, [], [])
    assert_true(controls.selected().value() == A)
    events = controls.handle(
        _event(POINTER_MOVE, 60, 50, NO_BUTTON),
        camera,
        scene,
        assets,
        SIZE,
        SIZE,
    )
    _expect(events, [], [])
    _assert_vector(scene.get(A).position, 0, 0, 0)
    events = controls.handle(
        _event(POINTER_UP, 60, 50, NO_BUTTON), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [DRAG_END], [A])
    # A release with nothing picked up reports nothing.
    events = controls.handle(
        _event(POINTER_UP, 60, 50), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [], [])


def test_a_ray_that_misses_the_plane_starts_no_drag() raises:
    # A camera inside a two-sided cube, looking away from its origin: the
    # ray strikes the far face, and points away from the plane through the
    # origin.
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_mesh(
        Mesh(
            assets.geometries.add(cube(Length(1.0, METER))),
            assets.materials.add(
                Material(Color(255, 255, 255), side=DOUBLE_SIDE)
            ),
            node,
        )
    )
    var camera = centered(
        Length(4.0, METER), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, -0.25), Vector3(0, 0, -1))
    var controls = DragControls([A])
    var events = controls.handle(
        _event(POINTER_DOWN, 50, 50), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [], [])
    assert_true(controls.selected().value() == A)
    events = controls.handle(
        _event(POINTER_MOVE, 60, 50), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [], [])


def test_the_middle_button_translates() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var camera = _camera()
    var controls = DragControls([A])
    var events = controls.handle(
        _event(POINTER_DOWN, 50, 50, MIDDLE), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [DRAG_START], [A])
    _ = controls.handle(
        _event(POINTER_MOVE, 60, 45, MIDDLE), camera, scene, assets, SIZE, SIZE
    )
    _assert_vector(scene.get(A).position, 1.0, 0.5, 0.0)


def test_without_recursion_a_child_is_not_picked() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var camera = _camera()
    var controls = DragControls([A, G])
    controls.recursive = False
    var events = controls.handle(
        _event(POINTER_MOVE, 74, 37, NO_BUTTON),
        camera,
        scene,
        assets,
        SIZE,
        SIZE,
    )
    _expect(events, [], [])
    events = controls.handle(
        _event(POINTER_MOVE, 50, 50, NO_BUTTON),
        camera,
        scene,
        assets,
        SIZE,
        SIZE,
    )
    _expect(events, [HOVER_ON], [A])


def test_other_events_and_disabled_controls_do_nothing() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var camera = _camera()
    var controls = DragControls([A])
    var events = controls.handle(
        InputEvent(KEY_DOWN, key=Key(113)), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [], [])
    events = controls.handle(
        InputEvent(WHEEL, wheel=1), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [], [])
    controls.enabled = False
    events = controls.handle(
        _event(POINTER_DOWN, 50, 50), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [], [])
    assert_false(Bool(controls.selected()))


def test_action_of_each_button() raises:
    var controls = DragControls([A])
    assert_true(controls.action_of(PRIMARY) == DRAG_TRANSLATE)
    assert_true(controls.action_of(MIDDLE) == DRAG_TRANSLATE)
    assert_true(controls.action_of(SECONDARY) == DRAG_ROTATE)
    assert_true(controls.action_of(NO_BUTTON) == NO_DRAG)


def test_invalid_input_is_refused() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var camera = _camera()
    var controls = DragControls([A])
    with assert_raises(contains="Invalid input kind"):
        _ = controls.handle(
            InputEvent(InputKind(9)), camera, scene, assets, SIZE, SIZE
        )
    with assert_raises(contains="Invalid key"):
        _ = controls.handle(
            InputEvent(KEY_DOWN, key=Key(999)),
            camera,
            scene,
            assets,
            SIZE,
            SIZE,
        )
    with assert_raises(contains="Invalid pointer button"):
        _ = controls.handle(
            _event(POINTER_DOWN, 0, 0, PointerButton(7)),
            camera,
            scene,
            assets,
            SIZE,
            SIZE,
        )
    controls.secondary_action = DragAction(5)
    with assert_raises(contains="Invalid drag action"):
        _ = controls.handle(
            _event(POINTER_DOWN, 0, 0, SECONDARY),
            camera,
            scene,
            assets,
            SIZE,
            SIZE,
        )
    controls.secondary_action = DRAG_ROTATE
    with assert_raises(contains="positive width and height"):
        _ = controls.handle(
            _event(POINTER_DOWN, 0, 0), camera, scene, assets, 0, SIZE
        )
    with assert_raises(contains="positive width and height"):
        _ = controls.handle(
            _event(POINTER_DOWN, 0, 0), camera, scene, assets, SIZE, 0
        )
    var stray = DragControls([NodeId(40)])
    with assert_raises():
        _ = stray.handle(
            _event(POINTER_DOWN, 0, 0), camera, scene, assets, SIZE, SIZE
        )


def test_no_objects_pick_nothing() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var camera = _camera()
    var controls = DragControls(List[NodeId]())
    var events = controls.handle(
        _event(POINTER_DOWN, 50, 50), camera, scene, assets, SIZE, SIZE
    )
    _expect(events, [], [])


def test_kinds_and_actions_are_checked() raises:
    assert_true(NO_DRAG.is_valid())
    assert_true(DRAG_ROTATE.is_valid())
    assert_false(DragAction(3).is_valid())
    assert_false(DragAction(-1).is_valid())
    assert_true(HOVER_ON.is_valid())
    assert_true(DRAG_END.is_valid())
    assert_false(DragEventKind(5).is_valid())
    assert_false(DragEventKind(-1).is_valid())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
