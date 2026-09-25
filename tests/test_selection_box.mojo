# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `controls.selection_box`.

The expected selections come from three.js r180's own `SelectionBox`, run
headless in Node with the same scene, cameras and rectangles. Unit boxes
stand at a (0, 0, 0), b (1.5, 0, 0), c (-3, 2, 0) and far (0, 0, -50). Box d
stands at (0.5, 0, -2) in a node at (0, 1, 0) turned 90 degrees about y. A
line from (0, 0, 0) to (1, 0, 0) stands at (-0.5, -0.5, 1), and points of
the same geometry at (4, 4, 0). An instanced mesh at (0, -1, 0) has three
instances: at the origin, at (2, 0, 0), and at (-0.4, 0.3, 0) turned and
scaled.

A 50-degree camera and an orthographic camera ten meters wide both stand at
(0, 0, 10) and look at the origin.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.input import (
    InputEvent,
    InputKind,
    KEY_DOWN,
    Key,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
    SECONDARY,
)
from controls.selection_box import DRAG_DEPTH, Selection, SelectionBox
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import box
from materials.material import (
    Material,
    MaterialId,
    line_material,
    points_material,
)
from math.matrix4 import Matrix4, compose, translation
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.instanced_mesh import InstancedMesh
from objects.line import Line
from objects.mesh import Mesh
from objects.points import Points
from objects.skeleton import bind_skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from render.framebuffer import Color
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER, RADIAN


def _node(name: String, x: Float32, y: Float32, z: Float32) -> Object3D:
    """Return a named node at a place.

    Args:
        name: Its name.
        x: Its x.
        y: Its y.
        z: Its z.

    Returns:
        The node.
    """
    var node = Object3D()
    node.name = name
    node.set_position(x, y, z)
    return node^


def _world() raises -> Tuple[Scene, Assets]:
    """Return the scene of the module docstring, updated, and its assets.

    Returns:
        The scene and its assets.

    Raises:
        Error: Never.
    """
    var assets = Assets()
    var cube = assets.geometries.add(
        box(Length(1.0, METER), Length(1.0, METER), Length(1.0, METER))
    )
    var segment = BufferGeometry()
    segment.set_attribute(
        String(POSITION), BufferAttribute([Float32(0), 0, 0, 1, 0, 0], 3)
    )
    var track = assets.geometries.add(segment^)
    var paint = assets.materials.add(Material(Color(255, 255, 255)))
    var ink = assets.materials.add(line_material(Color(255, 255, 255)))
    var dots = assets.materials.add(points_material(Color(255, 255, 255)))
    var scene = Scene()
    scene.add_mesh(Mesh(cube, paint, scene.add(_node("a", 0, 0, 0))))
    scene.add_mesh(Mesh(cube, paint, scene.add(_node("b", 1.5, 0, 0))))
    scene.add_mesh(Mesh(cube, paint, scene.add(_node("c", -3, 2, 0))))
    var holder = _node("holder", 0, 1, 0)
    holder.set_euler(
        Angle(0.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE)
    )
    var held = scene.add(holder^)
    scene.add_mesh(
        Mesh(cube, paint, scene.attach(_node("d", 0.5, 0, -2), held))
    )
    scene.add_mesh(Mesh(cube, paint, scene.add(_node("far", 0, 0, -50))))
    scene.add_line(Line(track, ink, scene.add(_node("line", -0.5, -0.5, 1))))
    scene.add_points(Points(track, dots, scene.add(_node("points", 4, 4, 0))))
    var many = InstancedMesh(cube, paint, scene.add(_node("many", 0, -1, 0)), 3)
    many.set_matrix_at(1, translation(2, 0, 0))
    many.set_matrix_at(
        2,
        compose(
            Vector3(-0.4, 0.3, 0),
            Quaternion.from_axis_angle(Vector3(0, 0, 1), Angle(0.7, RADIAN)),
            Vector3(2, 2, 2),
        ),
    )
    scene.add_instanced_mesh(many^)
    scene.update()
    return (scene^, assets^)


def _perspective() raises -> PerspectiveCamera:
    """Return the 50-degree camera at (0, 0, 10).

    Returns:
        The camera.

    Raises:
        Error: Never.
    """
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 10), Vector3(0, 0, 0))
    return camera^


def _orthographic() raises -> OrthographicCamera:
    """Return the orthographic camera at (0, 0, 10).

    Returns:
        The camera.

    Raises:
        Error: Never.
    """
    var camera = OrthographicCamera(
        Length(-5.0, METER),
        Length(5.0, METER),
        Length(5.0, METER),
        Length(-5.0, METER),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 10), Vector3(0, 0, 0))
    return camera^


def _names(scene: Scene, got: Selection) raises -> String:
    """Return the names of what was selected, in the order the scene is
    walked, as three.js's `collection` lists them.

    Args:
        scene: The scene.
        got: The selection.

    Returns:
        The names, joined by commas.

    Raises:
        Error: If a node is not there.
    """
    var names = String()
    var order = scene.traverse()
    for at in range(len(order)):
        var picked = False
        for index in got.meshes:
            picked = picked or scene.meshes[index].node == order[at]
        for index in got.skinned_meshes:
            picked = picked or scene.skinned_meshes[index].node == order[at]
        for index in got.lines:
            picked = picked or scene.lines[index].node == order[at]
        for index in got.points:
            picked = picked or scene.points[index].node == order[at]
        if picked:
            if names:
                names += ","
            names += scene.get(order[at]).name
    return names^


def _instances(got: Selection) raises -> String:
    """Return the instances selected of the one instanced mesh.

    Args:
        got: The selection.

    Returns:
        Their indices, joined by commas.

    Raises:
        Error: If the instanced mesh was not walked.
    """
    assert_equal(len(got.instanced_meshes), 1)
    assert_equal(got.instanced_meshes[0], 0)
    var joined = String()
    for index in got.instances[0]:
        if joined:
            joined += ","
        joined += String(index)
    return joined^


def _check_perspective(
    start: Vector3,
    end: Vector3,
    names: String,
    instances: String,
    deep: Optional[Length] = None,
) raises:
    """Assert what a rectangle selects through the perspective camera.

    Args:
        start: One corner.
        end: The other.
        names: What three.js selects.
        instances: The instances three.js selects.
        deep: The far plane's distance, or none.

    Raises:
        Error: If the selection differs.
    """
    var made = _world()
    ref scene = made[0]
    ref assets = made[1]
    var got = SelectionBox(deep).select(
        _perspective(), scene, assets, start, end
    )
    assert_equal(_names(scene, got), names)
    assert_equal(_instances(got), instances)


def _check_orthographic(
    start: Vector3, end: Vector3, names: String, instances: String
) raises:
    """Assert what a rectangle selects through the orthographic camera.

    Args:
        start: One corner.
        end: The other.
        names: What three.js selects.
        instances: The instances three.js selects.

    Raises:
        Error: If the selection differs.
    """
    var made = _world()
    ref scene = made[0]
    ref assets = made[1]
    var got = SelectionBox().select(_orthographic(), scene, assets, start, end)
    assert_equal(_names(scene, got), names)
    assert_equal(_instances(got), instances)


def test_a_rectangle_in_the_middle_selects_what_is_behind_it() raises:
    _check_perspective(
        Vector3(-0.5, -0.5, 0.5),
        Vector3(0.5, 0.5, 0.5),
        "a,b,d,far,line",
        "0,1,2",
    )


def test_the_corners_can_come_in_either_order() raises:
    _check_perspective(
        Vector3(0.5, 0.5, 0.5),
        Vector3(-0.5, -0.5, 0.5),
        "a,b,d,far,line",
        "0,1,2",
    )


def test_a_rectangle_to_one_side_selects_only_what_is_there() raises:
    _check_perspective(Vector3(0.05, -0.2, 0.5), Vector3(1, 0.2, 0.5), "b", "")
    _check_perspective(Vector3(-1, 0.1, 0.5), Vector3(-0.1, 1, 0.5), "c,d", "")


def test_a_far_plane_turned_as_three_js_turns_it() raises:
    # three.js turns the far plane's normal and keeps its constant, so the
    # plane is mirrored through the origin. Thirty meters out, it leaves
    # nothing out; eight meters out, it keeps only what lies beyond.
    _check_perspective(
        Vector3(-0.5, -0.5, 0.5),
        Vector3(0.5, 0.5, 0.5),
        "a,b,d,far,line",
        "0,1,2",
        Length(30.0, METER),
    )
    _check_perspective(
        Vector3(-0.5, -0.5, 0.5),
        Vector3(0.5, 0.5, 0.5),
        "far",
        "",
        Length(8.0, METER),
    )
    _check_perspective(
        Vector3(-1, -1, 0.5),
        Vector3(1, 1, 0.5),
        "a,b,c,d,far,line,points",
        "0,1,2",
        Length(1.0e6, METER),
    )


def test_a_rectangle_with_no_size_is_widened() raises:
    _check_perspective(Vector3(0, 0, 0.5), Vector3(0, 0, 0.5), "a,far", "")


def test_an_orthographic_camera_selects_along_parallel_sides() raises:
    _check_orthographic(
        Vector3(-0.5, -0.5, 0.5),
        Vector3(0.5, 0.5, 0.5),
        "a,b,d,far,line",
        "0,1,2",
    )
    _check_orthographic(Vector3(-1, 0, 0.5), Vector3(-0.2, 1, 0.5), "c,d", "")
    _check_orthographic(
        Vector3(-1, -1, 0.5),
        Vector3(1, 1, 0.5),
        "a,b,c,d,far,line,points",
        "0,1,2",
    )


def test_the_frustum_faces_in() raises:
    var made = _world()
    ref scene = made[0]
    var frustum = SelectionBox().frustum(
        _perspective(),
        scene,
        Vector3(-0.5, -0.5, 0.5),
        Vector3(0.5, 0.5, 0.5),
    )
    assert_true(frustum.contains_point(Vector3(0, 0, 0)))
    assert_true(not frustum.contains_point(Vector3(0, 0, 11)))
    assert_true(not frustum.contains_point(Vector3(5, 0, 0)))


def test_a_skinned_mesh_is_selected_by_its_geometry() raises:
    # three.js tests a skinned mesh as any mesh: by its geometry's bounding
    # sphere, not by where its bones put it.
    var assets = Assets()
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute([Float32(-1), -1, 0, 1, -1, 0, 0, 1, 0], 3),
    )
    var bones: List[Float32] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    var weights: List[Float32] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
    geometry.set_attribute(String(SKIN_INDEX), BufferAttribute(bones^, 4))
    geometry.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))
    var shape = assets.geometries.add(geometry^)
    var paint = assets.materials.add(Material(Color(255, 255, 255)))
    var scene = Scene()
    var body = scene.add(Object3D())
    var bone = scene.add(Object3D())
    scene.update()
    var skeleton = bind_skeleton([bone], [Matrix4()])
    scene.add_skinned_mesh(SkinnedMesh(shape, paint, body, skeleton^))
    scene.node(bone).set_position(4, 0, 0)
    scene.update()
    var middle = SelectionBox().select(
        _orthographic(),
        scene,
        assets,
        Vector3(-0.1, -0.1, 0.5),
        Vector3(0.1, 0.1, 0.5),
    )
    assert_equal(len(middle.skinned_meshes), 1)
    assert_equal(middle.skinned_meshes[0], 0)
    assert_equal(len(middle.meshes), 0)
    assert_equal(len(middle.instanced_meshes), 0)
    var aside = SelectionBox().select(
        _orthographic(),
        scene,
        assets,
        Vector3(0.6, -0.1, 0.5),
        Vector3(1, 0.1, 0.5),
    )
    assert_equal(len(aside.skinned_meshes), 0)


def test_a_drag_selects_as_it_moves_and_when_it_ends() raises:
    var made = _world()
    ref scene = made[0]
    ref assets = made[1]
    var camera = _perspective()
    var box = SelectionBox()
    # Nothing before a press, and nothing for another button.
    assert_false(
        Bool(
            box.handle(
                InputEvent(POINTER_MOVE, x=10, y=10),
                camera,
                scene,
                assets,
                100,
                100,
            )
        )
    )
    assert_false(
        Bool(
            box.handle(
                InputEvent(POINTER_DOWN, button=SECONDARY, x=25, y=25),
                camera,
                scene,
                assets,
                100,
                100,
            )
        )
    )
    assert_false(box.dragging)
    assert_false(
        Bool(
            box.handle(
                InputEvent(POINTER_DOWN, button=PRIMARY, x=25, y=25),
                camera,
                scene,
                assets,
                100,
                100,
            )
        )
    )
    assert_true(box.dragging)
    # A pixel's center: (25.5 / 100) * 2 - 1.
    assert_almost_equal(box.start_point.x, -0.49, atol=1e-6)
    assert_almost_equal(box.start_point.y, 0.49, atol=1e-6)
    assert_equal(box.start_point.z, DRAG_DEPTH)
    # A key in the middle of a drag selects nothing.
    assert_false(
        Bool(
            box.handle(
                InputEvent(KEY_DOWN, key=Key(113)),
                camera,
                scene,
                assets,
                100,
                100,
            )
        )
    )
    var moved = box.handle(
        InputEvent(POINTER_MOVE, x=74, y=74), camera, scene, assets, 100, 100
    )
    assert_equal(_names(scene, moved.value()), "a,b,d,far,line")
    assert_equal(_instances(moved.value()), "0,1,2")
    var ended = box.handle(
        InputEvent(POINTER_UP, button=PRIMARY, x=60, y=60),
        camera,
        scene,
        assets,
        100,
        100,
    )
    assert_false(box.dragging)
    assert_equal(_names(scene, ended.value()), "a,d,far,line")
    assert_equal(_instances(ended.value()), "2")


def test_a_drag_refuses_what_is_invalid() raises:
    var made = _world()
    ref scene = made[0]
    ref assets = made[1]
    var camera = _perspective()
    var box = SelectionBox()
    with assert_raises(contains="Invalid input kind"):
        _ = box.handle(
            InputEvent(InputKind(99)), camera, scene, assets, 100, 100
        )
    with assert_raises(contains="Invalid pointer button"):
        _ = box.handle(
            InputEvent(POINTER_DOWN, button=PointerButton(99)),
            camera,
            scene,
            assets,
            100,
            100,
        )
    with assert_raises(contains="positive width"):
        _ = box.handle(
            InputEvent(POINTER_DOWN, button=PRIMARY),
            camera,
            scene,
            assets,
            0,
            100,
        )
    with assert_raises(contains="positive width"):
        _ = box.handle(
            InputEvent(POINTER_DOWN, button=PRIMARY),
            camera,
            scene,
            assets,
            100,
            0,
        )


def test_an_empty_scene_selects_nothing() raises:
    var scene = Scene()
    scene.update()
    var assets = Assets()
    var none = InstancedMesh(
        GeometryId(0), MaterialId(0), scene.add(Object3D()), 0
    )
    scene.add_instanced_mesh(none^)
    scene.update()
    var got = SelectionBox().select(
        _perspective(),
        scene,
        assets,
        Vector3(-1, -1, 0.5),
        Vector3(1, 1, 0.5),
    )
    assert_equal(len(got.meshes), 0)
    # An instanced mesh of no instances is walked, and has none inside.
    assert_equal(len(got.instanced_meshes), 1)
    assert_equal(len(got.instances[0]), 0)
    var empty = Scene()
    empty.update()
    var nothing = SelectionBox().select(
        _perspective(),
        empty,
        assets,
        Vector3(-1, -1, 0.5),
        Vector3(1, 1, 0.5),
    )
    assert_equal(len(nothing.instanced_meshes), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
