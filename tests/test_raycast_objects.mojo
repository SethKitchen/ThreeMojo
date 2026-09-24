# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for picking a skinned mesh, a line, points and a sprite with
`core.raycaster`."""

from cameras.orthographic_camera import centered
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.object3d import NodeId, Object3D
from core.raycaster import (
    LINE_HIT,
    POINTS_HIT,
    Raycaster,
    SKINNED_HIT,
    SPRITE_HIT,
)
from core.scene import Scene
from materials.material import (
    Material,
    points_material,
    sprite_material,
)
from math.matrix4 import Matrix4, translation
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.line import LOOP, Line, LineMode, STRIP
from objects.points import Points
from objects.skeleton import bind_skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from objects.sprite import Sprite
from render.framebuffer import Color
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-4)


def _down(x: Float32, y: Float32) raises -> Raycaster:
    """Return a raycaster from five meters up +z, looking down -z.

    Args:
        x: Where it starts across.
        y: Where it starts up.

    Returns:
        The raycaster.

    Raises:
        Error: Never.
    """
    return Raycaster(Vector3(x, y, 5), Vector3(0, 0, -1))


def _geometry(var points: List[Float32]) raises -> BufferGeometry:
    """Return a geometry of the given positions.

    Args:
        points: Three numbers a vertex.

    Returns:
        The geometry.

    Raises:
        Error: If the count does not divide by three.
    """
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(points^, 3))
    return geometry^


def _scene() raises -> Scene:
    """Return an updated scene of one node at the origin."""
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    return scene^


def _camera() raises -> PerspectiveCamera:
    """Return a camera five meters up +z, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera^


# --- skinned meshes ---------------------------------------------------------


def _rigged() raises -> Tuple[Scene, Assets]:
    """Return a triangle on one bone that has moved five meters along +x.

    Returns:
        The scene and its assets.

    Raises:
        Error: Never.
    """
    var assets = Assets()
    var geometry = _geometry([Float32(0), 0, 0, 1, 0, 0, 0, 1, 0])
    var bones: List[Float32] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    var weights: List[Float32] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
    geometry.set_attribute(String(SKIN_INDEX), BufferAttribute(bones^, 4))
    geometry.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))
    var shape = assets.geometries.add(geometry^)
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    var scene = Scene()
    var body = scene.add(Object3D())
    var bone = scene.add(Object3D())
    scene.update()
    var skeleton = bind_skeleton([bone], [Matrix4()])
    scene.add_skinned_mesh(SkinnedMesh(shape, paint, body, skeleton^))
    scene.node(bone).set_position(5, 0, 0)
    scene.update()
    return (scene^, assets^)


def test_a_skinned_mesh_is_picked_where_its_bones_carry_it() raises:
    var rig = _rigged()
    ref scene = rig[0]
    ref assets = rig[1]
    var hits = _down(5.2, 0.2).intersect_skinned_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_true(hits[0].kind == SKINNED_HIT)
    assert_almost_equal(hits[0].distance, Float32(5), atol=TOLERANCE)
    assert_almost_equal(hits[0].point.x, Float32(5.2), atol=TOLERANCE)
    assert_almost_equal(hits[0].normal.z, Float32(1), atol=TOLERANCE)
    # Where it was modelled, nothing is left.
    assert_equal(
        len(_down(0.2, 0.2).intersect_skinned_mesh(scene, assets, 0)), 0
    )
    assert_equal(len(_down(5.2, 0.2).intersect_scene(scene, assets)), 1)
    with assert_raises(contains="No skinned mesh"):
        _ = _down(0, 0).intersect_skinned_mesh(scene, assets, 1)
    with assert_raises(contains="No skinned mesh"):
        _ = _down(0, 0).intersect_skinned_mesh(scene, assets, -1)


# --- lines ------------------------------------------------------------------


def _with_line(
    var points: List[Float32], mode: LineMode = STRIP, indexed: Bool = False
) raises -> Tuple[Scene, Assets]:
    """Return a scene holding one line through the given points.

    Args:
        points: Three numbers a vertex.
        mode: How the points are joined.
        indexed: Whether to give the geometry an index.

    Returns:
        The scene and its assets.

    Raises:
        Error: Never.
    """
    var assets = Assets()
    var geometry = _geometry(points^)
    if indexed:
        geometry.set_index([0, 1, 1])
    var shape = assets.geometries.add(geometry^)
    var paint = assets.materials.add(Material(Color(255, 255, 255)))
    var scene = _scene()
    scene.add_line(Line(shape, paint, NodeId(0), mode=mode))
    return (scene^, assets^)


def test_a_line_is_met_within_its_threshold() raises:
    var made = _with_line([Float32(-1), 0, 0, 1, 0, 0])
    ref scene = made[0]
    ref assets = made[1]
    var caster = _down(0.5, 0.3)
    caster.line_threshold = Length(0.5, METER)
    var hits = caster.intersect_line(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_true(hits[0].kind == LINE_HIT)
    assert_equal(hits[0].triangle, 0)
    assert_almost_equal(hits[0].distance, Float32(5), atol=TOLERANCE)
    # The point is on the line; the distance is to the ray's nearest.
    assert_almost_equal(hits[0].point.y, Float32(0), atol=TOLERANCE)
    assert_almost_equal(hits[0].point.x, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(hits[0].normal.length(), Float32(0), atol=TOLERANCE)
    # three.js's `Line.raycast` gives no face, texture or point on line.
    assert_true(not Bool(hits[0].face))
    assert_true(not Bool(hits[0].uv))
    assert_true(not Bool(hits[0].point_on_line))
    # Too far to one side for a tighter threshold.
    caster.line_threshold = Length(0.1, METER)
    assert_equal(len(caster.intersect_line(scene, assets, 0)), 0)
    # The whole line out of reach.
    assert_equal(len(_down(0, 5).intersect_line(scene, assets, 0)), 0)
    # Past the far distance.
    var short = Raycaster(
        Vector3(0, 0, 5), Vector3(0, 0, -1), far=Length(2.0, METER)
    )
    assert_equal(len(short.intersect_line(scene, assets, 0)), 0)
    assert_equal(len(_down(0, 0).intersect_scene(scene, assets)), 1)


def _nearer_than_six() raises -> Raycaster:
    """Return a raycaster down -z from five meters up, counting hits only
    from six meters on."""
    return Raycaster(
        Vector3(0, 0, 5), Vector3(0, 0, -1), near=Length(6.0, METER)
    )


def test_hits_nearer_than_near_are_dropped() raises:
    var line = _with_line([Float32(-1), 0, 0, 1, 0, 0])
    assert_equal(len(_nearer_than_six().intersect_line(line[0], line[1], 0)), 0)
    var cloud = _with_points([Float32(0), 0, 0])
    assert_equal(
        len(_nearer_than_six().intersect_points(cloud[0], cloud[1], 0)), 0
    )
    var card = _with_sprite()
    var caster = _nearer_than_six()
    caster.set_from_camera(Vector2(0, 0), _camera(), _scene())
    assert_equal(len(caster.intersect_sprite(card[0], card[1], 0)), 0)


def test_a_strip_of_one_point_has_no_segment_to_meet() raises:
    var made = _with_line([Float32(0), 0, 0])
    assert_equal(len(_down(0, 0).intersect_line(made[0], made[1], 0)), 0)


def test_a_loop_is_met_on_its_closing_segment() raises:
    var made = _with_line([Float32(-1), 0, 0, 1, 0, 0, 0, 1, 0], LOOP)
    var caster = _down(-0.5, 0.5)
    caster.line_threshold = Length(0.05, METER)
    var hits = caster.intersect_line(made[0], made[1], 0)
    assert_equal(len(hits), 1)
    assert_equal(hits[0].triangle, 2)


def test_a_line_on_another_layer_or_of_no_points_is_not_met() raises:
    var made = _with_line([Float32(-1), 0, 0, 1, 0, 0])
    made[0].node(NodeId(0)).layers.set(3)
    made[0].update()
    assert_equal(len(_down(0, 0).intersect_line(made[0], made[1], 0)), 0)
    var empty = _with_line(List[Float32]())
    assert_equal(len(_down(0, 0).intersect_line(empty[0], empty[1], 0)), 0)


def test_a_line_pick_refuses_what_it_cannot_measure() raises:
    var made = _with_line([Float32(-1), 0, 0, 1, 0, 0])
    ref scene = made[0]
    var caster = _down(0, 0)
    with assert_raises(contains="No line"):
        _ = caster.intersect_line(scene, made[1], 1)
    with assert_raises(contains="No line"):
        _ = caster.intersect_line(scene, made[1], -1)
    caster.line_threshold = Length(-1.0, METER)
    with assert_raises(contains="threshold"):
        _ = caster.intersect_line(scene, made[1], 0)
    caster.line_threshold = Length(nan[DType.float32](), METER)
    with assert_raises(contains="threshold"):
        _ = caster.intersect_line(scene, made[1], 0)
    var indexed = _with_line([Float32(-1), 0, 0, 1, 0, 0], indexed=True)
    with assert_raises(contains="indexed"):
        _ = _down(0, 0).intersect_line(indexed[0], indexed[1], 0)


# --- points -----------------------------------------------------------------


def _with_points(
    var points: List[Float32], indexed: Bool = False
) raises -> Tuple[Scene, Assets]:
    """Return a scene holding one points object at the given places.

    Args:
        points: Three numbers a vertex.
        indexed: Whether to give the geometry an index.

    Returns:
        The scene and its assets.

    Raises:
        Error: Never.
    """
    var assets = Assets()
    var geometry = _geometry(points^)
    if indexed:
        geometry.set_index([0, 0, 0])
    var shape = assets.geometries.add(geometry^)
    var paint = assets.materials.add(points_material(Color(255, 255, 255)))
    var scene = _scene()
    scene.add_points(Points(shape, paint, NodeId(0)))
    return (scene^, assets^)


def test_a_point_is_met_within_its_threshold() raises:
    var made = _with_points([Float32(0), 0, 0, 1, 0, 0])
    ref scene = made[0]
    ref assets = made[1]
    var caster = _down(1.05, 0)
    caster.points_threshold = Length(0.1, METER)
    var hits = caster.intersect_points(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_true(hits[0].kind == POINTS_HIT)
    assert_equal(hits[0].triangle, 1)
    # The point on the ray nearest the vertex.
    assert_almost_equal(hits[0].point.x, Float32(1.05), atol=TOLERANCE)
    assert_almost_equal(hits[0].distance, Float32(5), atol=TOLERANCE)
    # A threshold wide enough for both finds both.
    caster.points_threshold = Length(2.0, METER)
    assert_equal(len(caster.intersect_points(scene, assets, 0)), 2)
    # Out of reach, past the far distance, and on another layer.
    assert_equal(len(_down(0, 10).intersect_points(scene, assets, 0)), 0)
    var short = Raycaster(
        Vector3(0, 0, 5), Vector3(0, 0, -1), far=Length(2.0, METER)
    )
    assert_equal(len(short.intersect_points(scene, assets, 0)), 0)
    assert_equal(len(_down(0, 0).intersect_scene(scene, assets)), 1)
    var hidden = _with_points([Float32(0), 0, 0])
    hidden[0].node(NodeId(0)).layers.set(3)
    hidden[0].update()
    assert_equal(len(_down(0, 0).intersect_points(hidden[0], hidden[1], 0)), 0)


def test_a_points_pick_refuses_what_it_cannot_measure() raises:
    var made = _with_points([Float32(0), 0, 0])
    var caster = _down(0, 0)
    with assert_raises(contains="No points"):
        _ = caster.intersect_points(made[0], made[1], 1)
    with assert_raises(contains="No points"):
        _ = caster.intersect_points(made[0], made[1], -1)
    caster.points_threshold = Length(-1.0, METER)
    with assert_raises(contains="threshold"):
        _ = caster.intersect_points(made[0], made[1], 0)
    var indexed = _with_points([Float32(0), 0, 0], indexed=True)
    with assert_raises(contains="indexed"):
        _ = _down(0, 0).intersect_points(indexed[0], indexed[1], 0)


# --- sprites ----------------------------------------------------------------


def _with_sprite(
    attenuated: Bool = True, turn: Float32 = 0
) raises -> Tuple[Scene, Assets]:
    """Return a scene holding one unit sprite at the origin.

    Args:
        attenuated: Whether it shrinks with distance.
        turn: Its rotation in degrees.

    Returns:
        The scene and its assets.

    Raises:
        Error: Never.
    """
    var assets = Assets()
    var card = sprite_material(Color(255, 255, 255))
    card.size_attenuation = attenuated
    card.rotation = Angle(turn, DEGREE)
    var paint = assets.materials.add(card)
    var scene = _scene()
    scene.add_sprite(Sprite(paint, NodeId(0)))
    return (scene^, assets^)


def _aimed(x: Float32, y: Float32) raises -> Raycaster:
    """Return a raycaster that knows the camera, aimed down from `x`, `y`.

    Args:
        x: Where it starts across.
        y: Where it starts up.

    Returns:
        The raycaster.

    Raises:
        Error: Never.
    """
    var caster = _down(0, 0)
    caster.set_from_camera(Vector2(0, 0), _camera(), _scene())
    caster.set(Vector3(x, y, 5), Vector3(0, 0, -1))
    return caster^


def test_a_sprite_is_met_on_either_half() raises:
    var made = _with_sprite()
    ref scene = made[0]
    ref assets = made[1]
    var lower = _aimed(0.3, -0.3).intersect_sprite(scene, assets, 0)
    assert_equal(len(lower), 1)
    assert_true(lower[0].kind == SPRITE_HIT)
    assert_equal(lower[0].triangle, 0)
    assert_equal(lower[0].mesh.geometry.value, -1)
    assert_almost_equal(lower[0].distance, Float32(5), atol=TOLERANCE)
    # The texture at the point, as three.js's `Sprite.raycast` mixes it
    # (three.js 0.180 in node: 0.8, 0.3 at 0.3, -0.2).
    assert_almost_equal(lower[0].uv.value().x, Float32(0.8), atol=TOLERANCE)
    assert_almost_equal(lower[0].uv.value().y, Float32(0.2), atol=TOLERANCE)
    assert_true(not Bool(lower[0].face))
    var upper = _aimed(-0.3, 0.3).intersect_sprite(scene, assets, 0)
    assert_equal(upper[0].triangle, 1)
    assert_almost_equal(upper[0].uv.value().x, Float32(0.2), atol=TOLERANCE)
    assert_almost_equal(upper[0].uv.value().y, Float32(0.8), atol=TOLERANCE)
    assert_equal(len(_aimed(0.6, 0).intersect_sprite(scene, assets, 0)), 0)
    assert_equal(len(_aimed(0, 0).intersect_scene(scene, assets)), 1)


def test_a_sprite_is_turned_and_sized_as_it_is_drawn() raises:
    # Turned an eighth, its corner reaches past half a meter.
    var turned = _with_sprite(turn=45)
    assert_equal(
        len(_aimed(0.6, 0).intersect_sprite(turned[0], turned[1], 0)), 1
    )
    # Unattenuated, under a camera five meters off, it is five meters wide.
    var fixed = _with_sprite(attenuated=False)
    assert_equal(len(_aimed(2, 0).intersect_sprite(fixed[0], fixed[1], 0)), 1)
    # Under an orthographic camera it keeps its size.
    var flat = _down(0, 0)
    var camera = centered(
        Length(4.0, METER), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    flat.set_from_camera(Vector2(0, 0), camera, _scene())
    flat.set(Vector3(2, 0, 5), Vector3(0, 0, -1))
    assert_equal(len(flat.intersect_sprite(fixed[0], fixed[1], 0)), 0)


def test_a_sprite_needs_a_camera_a_layer_and_a_range() raises:
    var made = _with_sprite()
    ref scene = made[0]
    ref assets = made[1]
    with assert_raises(contains="camera"):
        _ = _down(0, 0).intersect_sprite(scene, assets, 0)
    # A scene pick leaves sprites out until a camera is set.
    assert_equal(len(_down(0, 0).intersect_scene(scene, assets)), 0)
    with assert_raises(contains="No sprite"):
        _ = _aimed(0, 0).intersect_sprite(scene, assets, 1)
    with assert_raises(contains="No sprite"):
        _ = _aimed(0, 0).intersect_sprite(scene, assets, -1)
    var short = _aimed(0, 0)
    short.far = Length(2.0, METER)
    assert_equal(len(short.intersect_sprite(scene, assets, 0)), 0)
    var hidden = _with_sprite()
    hidden[0].node(NodeId(0)).layers.set(3)
    hidden[0].update()
    assert_equal(len(_aimed(0, 0).intersect_sprite(hidden[0], hidden[1], 0)), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
