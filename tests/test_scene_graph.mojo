# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for editing the scene graph and the `Object3D` transform API.

The expected numbers come from three.js r180, run in Node on the same
inputs: `Object3D.translateOnAxis`, `applyMatrix4`, `applyQuaternion`, the
`setRotationFrom*` family, `localToWorld`, `worldToLocal`, the
`getWorld*` family, and `attach`.
"""

from animation.animation_mixer import write_target
from animation.keyframe_track import (
    LIGHT_INTENSITY,
    MATERIAL_OPACITY,
    POSITION,
    LightIndex,
    MeshIndex,
    material_target,
    light_target,
    morph_target,
    node_target,
)
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.layers import Layers
from core.object3d import (
    GROUP_TYPE,
    NO_PARENT,
    OBJECT3D_TYPE,
    NodeId,
    Object3D,
    ObjectType,
    scale_of,
)
from core.raycaster import Raycaster
from core.scene import Scene
from exporters.gltf import export_gltf
from exporters.obj import export_obj
from exporters.object_json import object_to_json
from geometries.plane import plane
from lights.light import ambient_light, directional_light
from loaders.object_loader import read_object_json
from materials.material import BASIC, Material, MaterialId
from math.euler import XYZ, ZYX, Euler
from math.matrix4 import Matrix4, rotation_y, scaling, translation
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.group import group
from objects.instanced_mesh import BatchedMesh, InstancedMesh
from objects.line import Line
from objects.line_segments2 import LineSegments2
from objects.lod import Lod
from objects.mesh import Mesh
from objects.points import Points
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SkinnedMesh
from objects.sprite import Sprite
from render.framebuffer import Color
from renderers.renderer import Renderer
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import CENTIMETER, DEGREE, METER, RADIAN, Angle, Length

comptime TOLERANCE = Float64(1e-4)


def assert_vector(got: Vector3, x: Float64, y: Float64, z: Float64) raises:
    """Assert a vector matches three.js's, within rounding."""
    assert_almost_equal(Float64(got.x), x, atol=TOLERANCE)
    assert_almost_equal(Float64(got.y), y, atol=TOLERANCE)
    assert_almost_equal(Float64(got.z), z, atol=TOLERANCE)


def assert_quaternion(
    got: Quaternion, x: Float64, y: Float64, z: Float64, w: Float64
) raises:
    """Assert a quaternion matches three.js's, within rounding."""
    assert_almost_equal(Float64(got.x), x, atol=TOLERANCE)
    assert_almost_equal(Float64(got.y), y, atol=TOLERANCE)
    assert_almost_equal(Float64(got.z), z, atol=TOLERANCE)
    assert_almost_equal(Float64(got.w), w, atol=TOLERANCE)


def ids(nodes: List[NodeId]) -> List[Int]:
    """Return the numbers of a list of node ids."""
    var out = List[Int]()
    for node in nodes:
        out.append(node.value)
    return out^


def assert_ids(got: List[NodeId], expected: List[Int]) raises:
    """Assert a list of node ids, in order."""
    var numbers = ids(got)
    assert_equal(len(numbers), len(expected))
    for index in range(len(expected)):
        assert_equal(numbers[index], expected[index])


def turned(x: Float32, y: Float32, z: Float32) raises -> Object3D:
    """Return a node turned by `XYZ` Euler angles in radians."""
    var node = Object3D()
    node.set_euler(Angle(x, RADIAN), Angle(y, RADIAN), Angle(z, RADIAN))
    return node^


# --- Object3D: own-frame edits ---------------------------------------------


def test_translating_moves_along_the_nodes_own_axes() raises:
    var node = turned(0.3, 0.5, -0.2)
    node.translate_x(Length(2.0, METER))
    node.translate_y(Length(-1.0, METER))
    node.translate_z(Length(50.0, CENTIMETER))
    var axis = Vector3(1, 1, 0)
    axis.normalize()
    node.translate_on_axis(axis, Length(3.0, METER))
    assert_vector(node.position, 3.9799172, 0.74183416, -1.4500281)


def test_apply_matrix4_transforms_the_node_in_its_parents_frame() raises:
    var node = turned(0.1, 0.2, 0.3)
    node.set_position(1, 2, 3)
    node.set_scale(2, 2, 2)
    var matrix = translation(4, 5, 6)
    matrix.multiply(rotation_y(Angle(0.7, RADIAN)))
    matrix.multiply(scaling(0.5, 0.5, 0.5))
    node.apply_matrix4(matrix)
    assert_vector(node.position, 5.3487476, 6.0, 6.8251544)
    assert_quaternion(
        node.quaternion, 0.11280088, 0.42230724, 0.12216677, 0.89107117
    )
    assert_vector(node.scale, 1, 1, 1)
    # The matrix is kept, as three.js keeps `object.matrix`.
    var rebuilt = node.local_matrix()
    for index in range(16):
        assert_almost_equal(
            node.matrix.elements[index],
            rebuilt.elements[index],
            atol=TOLERANCE,
        )


def test_apply_matrix4_reads_a_mirror_as_a_negative_x_scale() raises:
    var node = Object3D()
    node.apply_matrix4(scaling(-1, 2, 3))
    assert_quaternion(node.quaternion, 0, 0, 0, 1)
    assert_vector(node.scale, -1, 2, 3)
    assert_vector(scale_of(scaling(1, -2, 3)), -1, 2, 3)


def test_apply_matrix4_starts_from_a_kept_matrix() raises:
    # With `matrix_auto_update` off, three.js premultiplies the matrix as it
    # stands, not one rebuilt from the parts.
    var node = Object3D()
    node.matrix_auto_update = False
    node.matrix = translation(1, 0, 0)
    node.apply_matrix4(translation(0, 2, 0))
    assert_vector(node.position, 1, 2, 0)
    assert_equal(node.matrix.elements[12], 1)
    assert_equal(node.matrix.elements[13], 2)


def test_apply_matrix4_refuses_a_flattening_and_changes_nothing() raises:
    var node = Object3D()
    node.set_position(1, 2, 3)
    with assert_raises(contains="flattens"):
        node.apply_matrix4(scaling(1, 0, 1))
    assert_vector(node.position, 1, 2, 3)
    assert_vector(node.scale, 1, 1, 1)
    assert_equal(node.matrix.elements[12], 0)
    with assert_raises(contains="flattens"):
        node.set_from_matrix(scaling(0, 0, 0))


def test_apply_quaternion_turns_in_the_parents_frame() raises:
    var node = turned(0.2, 0, 0)
    node.apply_quaternion(
        Quaternion.from_axis_angle(Vector3(0, 1, 0), Angle(0.6, RADIAN))
    )
    assert_quaternion(
        node.quaternion, 0.095374506, 0.29404384, -0.029502792, 0.95056379
    )


def test_set_rotation_from_each_form() raises:
    var node = Object3D()
    var axis = Vector3(1, 2, 3)
    axis.normalize()
    node.set_rotation_from_axis_angle(axis, Angle(0.9, RADIAN))
    assert_quaternion(
        node.quaternion, 0.11624943, 0.23249886, 0.34874829, 0.90044710
    )
    var euler = Euler(
        Angle(0.4, RADIAN), Angle(-0.3, RADIAN), Angle(1.1, RADIAN), XYZ
    )
    node.set_rotation_from_matrix(euler.to_quaternion().to_matrix())
    assert_quaternion(
        node.quaternion, 0.090916213, -0.22753605, 0.48120566, 0.84166662
    )
    node.set_rotation_from_euler(
        Euler(Angle(0.4, RADIAN), Angle(-0.3, RADIAN), Angle(1.1, RADIAN), ZYX)
    )
    assert_quaternion(
        node.quaternion, 0.24402104, -0.022184272, 0.53182647, 0.81063074
    )
    node.set_rotation_from_quaternion(Quaternion(0, 0, 1, 0))
    assert_quaternion(node.quaternion, 0, 0, 1, 0)


# --- world queries -----------------------------------------------------------


def hierarchy(mut scene: Scene) raises -> Tuple[NodeId, NodeId]:
    """Build three.js's reference pair: a parent at (1, 0, 0) turned a
    quarter about y and scaled 2, and a child at (0, 0, 1) turned 0.5
    about x and scaled (1, 3, 1)."""
    var parent = turned(0, Float32(pi / 2), 0)
    parent.set_position(1, 0, 0)
    parent.set_scale(2, 2, 2)
    var parent_id = scene.add(parent^)
    var child = turned(0.5, 0, 0)
    child.set_position(0, 0, 1)
    child.set_scale(1, 3, 1)
    var child_id = scene.attach(child^, parent_id)
    return (parent_id, child_id)


def test_world_queries_match_three_js() raises:
    var scene = Scene()
    var pair = hierarchy(scene)
    var child = pair[1]
    scene.update()
    assert_vector(
        scene.local_to_world(child, Vector3(1, 2, 3)), 14.018602, 7.6544375, -2
    )
    assert_vector(
        scene.world_to_local(child, Vector3(4, 5, 6)),
        -3,
        0.81122306,
        -0.75977257,
    )
    assert_vector(scene.world_position(child), 3, 0, 0)
    assert_quaternion(
        scene.world_quaternion(child),
        0.17494102,
        0.68512454,
        -0.17494102,
        0.68512454,
    )
    assert_vector(scene.world_scale(child), 2, 6, 2)
    assert_vector(scene.world_direction(child), 0.87758256, -0.47942554, 0)
    # A camera looks down its -z, as `Camera.getWorldDirection` negates.
    assert_vector(
        scene.world_direction(child, camera=True),
        -0.87758256,
        0.47942554,
        0,
    )


def test_world_queries_refuse_a_stale_scene_and_a_flat_node() raises:
    var scene = Scene()
    var pair = hierarchy(scene)
    with assert_raises(contains="update"):
        _ = scene.local_to_world(pair[1], Vector3(0, 0, 0))
    with assert_raises(contains="update"):
        _ = scene.world_scale(pair[1])
    scene.node(pair[1]).set_scale(1, 0, 1)
    scene.update()
    with assert_raises(contains="flattens"):
        _ = scene.world_quaternion(pair[1])
    # The scale is there to read, zero and all, as three.js reads it.
    assert_vector(scene.world_scale(pair[1]), 2, 0, 2)
    # A flat node has no inverse: every point comes back as the origin.
    assert_vector(scene.world_to_local(pair[1], Vector3(4, 5, 6)), 0, 0, 0)
    with assert_raises(contains="out of range"):
        _ = scene.world_direction(NodeId(5))


# --- moving nodes ------------------------------------------------------------


def test_a_node_moves_under_a_newer_node() raises:
    # The limitation this lifts: an older node under a newer one.
    var scene = Scene()
    var old = scene.add(Object3D())
    scene.node(old).set_position(1, 0, 0)
    var new = scene.add(Object3D())
    scene.node(new).set_position(0, 5, 0)
    scene.add(old, parent=new)
    assert_equal(scene.get(old).parent.value, new.value)
    scene.update()
    assert_vector(scene.world_position(old), 1, 5, 0)
    assert_ids(scene.children(new), [old.value])
    assert_ids(scene.children(NO_PARENT), [new.value])
    assert_ids(scene.traverse(), [new.value, old.value])
    # And back to the top of the scene.
    scene.add(old)
    scene.update()
    assert_vector(scene.world_position(old), 1, 0, 0)
    assert_ids(scene.children(NO_PARENT), [new.value, old.value])


def test_add_makes_a_node_the_last_child_as_three_js_pushes_it() raises:
    var scene = Scene()
    var root = scene.add(Object3D())
    var a = scene.attach(Object3D(), root)
    var b = scene.attach(Object3D(), root)
    var c = scene.attach(Object3D(), root)
    assert_ids(scene.children(root), [a.value, b.value, c.value])
    scene.add(a, parent=root)
    assert_ids(scene.children(root), [b.value, c.value, a.value])
    scene.add(b, parent=root)
    assert_ids(scene.children(root), [c.value, a.value, b.value])


def test_a_node_cannot_go_under_itself_or_its_descendant() raises:
    var scene = Scene()
    var root = scene.add(Object3D())
    var child = scene.attach(Object3D(), root)
    var grandchild = scene.attach(Object3D(), child)
    with assert_raises(contains="descendant"):
        scene.add(root, parent=grandchild)
    with assert_raises(contains="descendant"):
        scene.add(child, parent=child)
    with assert_raises(contains="descendant"):
        scene.attach(root, parent=grandchild)
    with assert_raises(contains="out of range"):
        scene.add(NodeId(9), parent=root)
    with assert_raises(contains="already be in the scene"):
        scene.add(child, parent=NodeId(9))
    # Nothing moved.
    assert_equal(scene.get(child).parent.value, root.value)


def test_attach_keeps_the_world_transform_as_three_js_does() raises:
    var scene = Scene()
    var pair = hierarchy(scene)
    var child = pair[1]
    var other = turned(0, 0, 0.3)
    other.set_position(-2, 1, 0)
    other.set_scale(1.5, 1.5, 1.5)
    var other_id = scene.add(other^)
    scene.attach(child, parent=other_id)
    ref moved = scene.get(child)
    assert_vector(moved.position, 2.9874415, -1.6219583, 0)
    assert_quaternion(
        moved.quaternion, 0.27536035, 0.65128847, -0.27536035, 0.65128847
    )
    assert_vector(moved.scale, 1.3333333, 4, 1.3333333)
    assert_ids(scene.children(other_id), [child.value])
    # And to the top, as `scene.attach(child)` does.
    scene.detach(child)
    ref top = scene.get(child)
    assert_equal(top.parent, NO_PARENT)
    assert_vector(top.position, 3, 0, 0)
    assert_quaternion(
        top.quaternion, 0.17494102, 0.68512454, -0.17494102, 0.68512454
    )
    assert_vector(top.scale, 2, 6, 2)


def test_attach_reads_a_kept_matrix_and_refuses_a_flat_parent() raises:
    var scene = Scene()
    var parent = scene.add(Object3D())
    scene.node(parent).matrix_auto_update = False
    scene.node(parent).matrix = translation(0, 3, 0)
    var child = scene.add(Object3D())
    scene.attach(child, parent=parent)
    assert_vector(scene.get(child).position, 0, -3, 0)
    var flat = scene.add(Object3D())
    scene.node(flat).set_scale(0, 1, 1)
    with assert_raises(contains="flattens"):
        scene.attach(child, parent=flat)
    assert_equal(scene.get(child).parent.value, parent.value)


# --- removing nodes ----------------------------------------------------------


def test_remove_takes_a_child_off_its_parent_only() raises:
    var scene = Scene()
    var root = scene.add(Object3D())
    var child = scene.attach(Object3D(), root)
    var leaf = scene.attach(Object3D(), child)
    # Not a child of the scene itself: nothing happens, as in three.js.
    scene.remove(child)
    assert_true(scene.in_scene(child))
    # Nor of a node it is not under.
    scene.remove(child, parent=leaf)
    assert_true(scene.in_scene(child))
    scene.remove(child, parent=root)
    assert_false(scene.in_scene(child))
    assert_false(scene.in_scene(leaf))
    assert_true(scene.in_scene(root))
    assert_true(scene.in_scene(NO_PARENT))
    # Its subtree stays under it, and its id stays its own.
    assert_equal(scene.get(child).parent, NO_PARENT)
    assert_equal(scene.get(leaf).parent.value, child.value)
    assert_equal(scene.count(), 3)
    assert_ids(scene.traverse(), [root.value])
    assert_ids(scene.children(NO_PARENT), [root.value])
    # A removed node is walked as three.js walks an object with no parent.
    assert_ids(scene.traverse(child), [child.value, leaf.value])
    # Removing it again does nothing.
    scene.remove(child)
    scene.remove_from_parent(child)
    assert_false(scene.in_scene(child))
    with assert_raises(contains="out of range"):
        scene.remove(NodeId(7))
    with assert_raises(contains="already be in the scene"):
        scene.remove(child, parent=NodeId(7))
    with assert_raises(contains="out of range"):
        _ = scene.in_scene(NodeId(7))


def test_a_removed_node_is_not_shown_and_comes_back_when_added() raises:
    var scene = Scene()
    var root = scene.add(Object3D())
    var child = scene.attach(Object3D(), root)
    scene.update()
    scene.remove_from_parent(root)
    assert_true(scene.is_stale())
    scene.update()
    assert_false(scene.is_shown(root))
    assert_false(scene.is_shown(child))
    assert_false(scene.shows(child, Layers()))
    # It still has a world matrix, as a removed three.js object does.
    assert_vector(scene.world_position(child), 0, 0, 0)
    scene.add(root)
    scene.update()
    assert_true(scene.is_shown(root))
    assert_true(scene.is_shown(child))


def test_clear_empties_a_node_or_the_scene() raises:
    var scene = Scene()
    var root = scene.add(Object3D())
    var a = scene.attach(Object3D(), root)
    var b = scene.attach(Object3D(), root)
    var other = scene.add(Object3D())
    scene.clear(a)
    assert_true(scene.in_scene(a))
    scene.clear(root)
    assert_false(scene.in_scene(a))
    assert_false(scene.in_scene(b))
    assert_equal(len(scene.children(root)), 0)
    scene.clear()
    assert_false(scene.in_scene(root))
    assert_false(scene.in_scene(other))
    assert_equal(len(scene.traverse()), 0)
    with assert_raises(contains="out of range"):
        scene.clear(NodeId(9))


def test_a_removed_node_is_not_drawn_hit_lit_or_exported() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var lamp = scene.add(Object3D())
    scene.node(lamp).set_position(0, 0, 5)
    scene.add_light(directional_light(Color(255, 255, 255), lamp, 1.0))
    var quad = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var red = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    scene.add_mesh(Mesh(quad, red, node))
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var renderer = Renderer(8, 8)
    var ray = Raycaster(Vector3(0.3, 0.6, 5), Vector3(0, 0, -1))
    scene.update()
    assert_true(renderer.render(scene, assets, camera).get_pixel(4, 4).r > 0)
    assert_equal(len(ray.intersect_mesh(scene, assets, 0)), 1)
    assert_true(scene.light_shown(scene.lights[0]))
    assert_true(export_obj(scene, assets).find("v ") >= 0)
    scene.remove(node)
    scene.remove(lamp)
    scene.update()
    var image = renderer.render(scene, assets, camera)
    assert_equal(image.get_pixel(4, 4).r, renderer.background.r)
    assert_equal(len(ray.intersect_mesh(scene, assets, 0)), 0)
    assert_false(scene.light_shown(scene.lights[0]))
    assert_equal(export_obj(scene, assets).find("v "), -1)
    var json = object_to_json(scene, assets)
    assert_equal(json.find('"type":"Mesh"'), -1)
    assert_equal(json.find("DirectionalLight"), -1)
    var gltf = export_gltf(scene, assets)
    assert_equal(String(unsafe_from_utf8=gltf.document).find('"mesh"'), -1)


def test_a_removed_node_is_not_animated() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    var other = scene.add(Object3D())
    scene.add_mesh(Mesh(GeometryId(0), MaterialId(0), node))
    scene.add_light(directional_light(Color(255, 255, 255), node, 1.0))
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    var assets = Assets()
    _ = assets.materials.add(Material(Color(0, 0, 0)))
    var position = node_target(node, POSITION)
    write_target(scene, assets, position, [1, 2, 3, 0], 0)
    assert_vector(scene.get(node).position, 1, 2, 3)
    scene.remove(node)
    write_target(scene, assets, position, [4, 5, 6, 0], 0)
    assert_vector(scene.get(node).position, 1, 2, 3)
    # Nor a mesh or a light on it.
    write_target(
        scene, assets, morph_target(MeshIndex(0), 0), [0.5, 0, 0, 0], 0
    )
    assert_equal(scene.meshes[0].morph_influence(0), 0)
    var bright = light_target(LightIndex(0), LIGHT_INTENSITY)
    write_target(scene, assets, bright, [3, 0, 0, 0], 0)
    assert_equal(scene.lights[0].intensity, 1)
    # A light on no node, a node still in the scene, and a material still
    # take their values.
    var fill = light_target(LightIndex(1), LIGHT_INTENSITY)
    write_target(scene, assets, fill, [3, 0, 0, 0], 0)
    assert_equal(scene.lights[1].intensity, 3)
    write_target(scene, assets, node_target(other, POSITION), [7, 0, 0, 0], 0)
    assert_vector(scene.get(other).position, 7, 0, 0)
    var opacity = material_target(MaterialId(0), MATERIAL_OPACITY)
    write_target(scene, assets, opacity, [0.25, 0, 0, 0], 0)
    assert_equal(assets.materials.get(MaterialId(0)).opacity, 0.25)


# --- set and the private invariants ------------------------------------------


def test_set_moves_a_node_to_a_new_parent_and_keeps_it_removed() raises:
    var scene = Scene()
    var a = scene.add(Object3D())
    var b = scene.add(Object3D())
    var c = scene.attach(Object3D(), a)
    var d = scene.attach(Object3D(), a)
    var moved = scene.get(c)
    moved.parent = b
    scene.set(c, moved^)
    assert_ids(scene.children(b), [c.value])
    # The same parent keeps the place among the siblings.
    var same = scene.get(d)
    same.name = "d"
    scene.set(d, same^)
    assert_ids(scene.children(a), [d.value])
    scene.remove(c, parent=b)
    var back = scene.get(c)
    back.parent = a
    scene.set(c, back^)
    assert_false(scene.in_scene(c))
    # A removed node under a parent is not one of the scene's children,
    # but it is its parent's, as the node says.
    assert_ids(scene.children(a), [d.value, c.value])
    assert_ids(scene.children(NO_PARENT), [a.value, b.value])
    assert_ids(scene.traverse(a), [a.value, d.value, c.value])


def test_validate_catches_every_array_drifting_apart() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    scene._removed.append(False)
    with assert_raises(contains="different lengths"):
        scene.validate()
    _ = scene._removed.pop()
    scene._sequence.append(0)
    with assert_raises(contains="different lengths"):
        scene.validate()
    _ = scene._sequence.pop()
    scene.validate()


def test_a_walk_refuses_a_broken_link_or_a_loop() raises:
    var scene = Scene()
    var a = scene.add(Object3D())
    var b = scene.add(Object3D())
    scene.node(a).parent = b
    scene.node(b).parent = a
    with assert_raises(contains="loop"):
        _ = scene.traverse(a)
    with assert_raises(contains="loop"):
        _ = scene.traverse_ancestors(a)
    with assert_raises(contains="loop"):
        scene.attach(a, parent=NO_PARENT)
    scene.node(b).parent = NodeId(-2)
    with assert_raises(contains="parent"):
        _ = scene.in_scene(a)
    scene.node(b).parent = NodeId(8)
    with assert_raises(contains="parent"):
        _ = scene.traverse()
    with assert_raises(contains="parent"):
        _ = scene.in_scene(a)


# --- walking the tree --------------------------------------------------------


def walked(mut scene: Scene) raises -> List[NodeId]:
    """Build a tree whose ids do not follow its order, and return its
    nodes: root 0 with children 1 and 3, node 2 under node 1, and node 4
    moved from the top to under node 2. Node 3 is hidden."""
    var nodes = List[NodeId]()
    nodes.append(scene.add(Object3D()))
    nodes.append(scene.attach(Object3D(), nodes[0]))
    nodes.append(scene.attach(Object3D(), nodes[1]))
    nodes.append(scene.attach(Object3D(), nodes[0]))
    nodes.append(scene.add(Object3D()))
    scene.add(nodes[4], parent=nodes[2])
    scene.node(nodes[3]).visible = False
    scene.node(nodes[1]).name = "twin"
    scene.node(nodes[4]).name = "twin"
    return nodes^


def test_traverse_is_three_js_depth_first_order() raises:
    var scene = Scene()
    var nodes = walked(scene)
    assert_ids(scene.traverse(), [0, 1, 2, 4, 3])
    assert_ids(scene.traverse(nodes[1]), [1, 2, 4])
    assert_ids(scene.descendants(nodes[0]), [0, 1, 2, 4, 3])
    assert_ids(scene.traverse_visible(), [0, 1, 2, 4])
    assert_equal(len(scene.traverse_visible(nodes[3])), 0)
    assert_ids(scene.traverse_ancestors(nodes[4]), [2, 1, 0])
    assert_equal(len(scene.traverse_ancestors(nodes[0])), 0)
    assert_equal(len(Scene().traverse()), 0)
    with assert_raises(contains="out of range"):
        _ = scene.traverse(NodeId(-2))
    with assert_raises(contains="out of range"):
        _ = scene.traverse_ancestors(NodeId(5))
    with assert_raises(contains="out of range"):
        _ = scene.descendants(NO_PARENT)
    # `update` walks the same way, so a parent newer than its child works.
    scene.node(nodes[2]).set_position(0, 1, 0)
    scene.node(nodes[4]).set_position(1, 0, 0)
    scene.update()
    assert_vector(scene.world_position(nodes[4]), 1, 1, 0)


def test_objects_are_found_by_name_and_id() raises:
    var scene = Scene()
    var nodes = walked(scene)
    assert_equal(scene.find("twin").value().value, 1)
    assert_equal(scene.find("twin", nodes[2]).value().value, 4)
    assert_false(Bool(scene.find("nobody")))
    assert_ids(scene.objects_by_name("twin"), [1, 4])
    assert_equal(len(scene.objects_by_name("twin", nodes[3])), 0)
    assert_equal(scene.object_by_id(nodes[4]).value().value, 4)
    assert_false(Bool(scene.object_by_id(nodes[3], nodes[1])))
    # A removed node is not in the scene to be found.
    scene.remove(nodes[1], parent=nodes[0])
    assert_false(Bool(scene.find("twin")))
    assert_false(Bool(scene.object_by_id(nodes[4])))
    assert_equal(scene.find("twin", nodes[1]).value().value, 1)
    # An empty scene has nothing to find.
    var empty = Scene()
    assert_equal(len(empty.objects_by_name("twin")), 0)
    assert_false(Bool(empty.object_by_id(NodeId(0))))


def _render_order_of(node: Object3D) -> Int:
    """Read a node's render order, for the property lookups."""
    return node.render_order


def _name_of(node: Object3D) -> String:
    """Read a node's name, for the property lookups."""
    return node.name


def test_objects_are_found_by_any_property() raises:
    var scene = Scene()
    var nodes = walked(scene)
    scene.node(nodes[2]).render_order = 3
    scene.node(nodes[3]).render_order = 3
    var first = scene.object_by_property[_render_order_of](3)
    assert_equal(first.value().value, 2)
    assert_ids(scene.objects_by_property[_render_order_of](3), [2, 3])
    assert_ids(scene.objects_by_property[_render_order_of](3, nodes[1]), [2])
    assert_false(Bool(scene.object_by_property[_render_order_of](9)))
    # The name as a property is `objects_by_name` again.
    assert_ids(scene.objects_by_property[_name_of]("twin"), [1, 4])
    var empty = Scene()
    assert_false(Bool(empty.object_by_property[_render_order_of](0)))
    assert_equal(len(empty.objects_by_property[_render_order_of](0)), 0)


# --- clone and copy ----------------------------------------------------------


def test_clone_copies_a_subtree_as_a_removed_node() raises:
    var scene = Scene()
    var nodes = walked(scene)
    scene.node(nodes[1]).set_position(3, 0, 0)
    scene.node(nodes[1]).user_data.set_number("hp", 7)
    var copy = scene.clone(nodes[1])
    assert_equal(copy.value, 5)
    assert_equal(scene.count(), 8)
    assert_false(scene.in_scene(copy))
    assert_equal(scene.get(copy).parent, NO_PARENT)
    assert_vector(scene.get(copy).position, 3, 0, 0)
    assert_equal(scene.get(copy).name, "twin")
    assert_equal(scene.get(copy).user_data.number("hp"), 7)
    assert_ids(scene.traverse(copy), [5, 6, 7])
    assert_equal(scene.get(NodeId(7)).name, "twin")
    # The source is untouched, and the copy's user data is its own.
    scene.node(copy).user_data.set_number("hp", 1)
    assert_equal(scene.get(nodes[1]).user_data.number("hp"), 7)
    assert_ids(scene.traverse(), [0, 1, 2, 4, 3])
    scene.add(copy, parent=nodes[0])
    assert_ids(scene.traverse(), [0, 1, 2, 4, 3, 5, 6, 7])
    # Not recursive: the node alone.
    var alone = scene.clone(nodes[1], recursive=False)
    assert_ids(scene.traverse(alone), [8])
    with assert_raises(contains="out of range"):
        _ = scene.clone(NodeId(40))


def test_clone_copies_what_the_nodes_carry() raises:
    var scene = Scene()
    var root = scene.add(Object3D())
    var child = scene.attach(Object3D(), root)
    var aim = scene.attach(Object3D(), root)
    var outside = scene.add(Object3D())
    var geometry = GeometryId(0)
    var material = MaterialId(0)
    for node in [child, outside]:
        scene.add_mesh(Mesh(geometry, material, node))
        scene.add_instanced_mesh(InstancedMesh(geometry, material, node, 2))
        scene.add_batched_mesh(BatchedMesh(material, node))
        scene.add_lod(Lod(node))
        var bones = List[Bone]()
        bones.append(Bone(outside, Matrix4()))
        scene.add_skinned_mesh(
            SkinnedMesh(geometry, material, node, Skeleton(bones^))
        )
        scene.add_line(Line(geometry, material, node))
        scene.add_points(Points(geometry, material, node))
        scene.add_sprite(Sprite(material, node))
        scene.add_wide_line(LineSegments2(geometry, material, node))
    # One light aims inside the copied subtree, one outside it, one at a
    # node that is not there at all; an ambient light rides no node.
    scene.add_light(directional_light(Color(255, 255, 255), child, 1, aim))
    scene.add_light(directional_light(Color(255, 255, 255), child, 1, outside))
    scene.add_light(
        directional_light(Color(255, 255, 255), child, 1, NodeId(99))
    )
    scene.add_light(ambient_light(Color(255, 255, 255), 1))
    var copy = scene.clone(root)
    # Nodes 4, 5 and 6 are the copies of 0, 1 and 2.
    assert_ids(scene.traverse(copy), [4, 5, 6])
    assert_equal(len(scene.meshes), 3)
    assert_equal(scene.meshes[2].node.value, 5)
    assert_equal(scene.instanced_meshes[2].node.value, 5)
    assert_equal(scene.instanced_meshes[2].count(), 2)
    assert_equal(scene.batched_meshes[2].node.value, 5)
    assert_equal(scene.lods[2].node.value, 5)
    assert_equal(scene.skinned_meshes[2].node.value, 5)
    # The skeleton is shared, as three.js's clone shares it.
    assert_equal(scene.skinned_meshes[2].skeleton.node(0).value, outside.value)
    assert_equal(scene.lines[2].node.value, 5)
    assert_equal(scene.points[2].node.value, 5)
    assert_equal(scene.sprites[2].node.value, 5)
    assert_equal(scene.wide_lines[2].node.value, 5)
    assert_equal(len(scene.lights), 7)
    assert_equal(scene.lights[4].node.value, 5)
    assert_equal(scene.lights[4].target.value, 6)
    assert_equal(scene.lights[5].target.value, outside.value)
    assert_equal(scene.lights[6].target.value, 99)


def test_clone_of_a_scene_with_nothing_on_it() raises:
    var scene = Scene()
    var root = scene.add(Object3D())
    var copy = scene.clone(root)
    assert_equal(copy.value, 1)
    assert_equal(len(scene.meshes), 0)
    assert_equal(len(scene.lights), 0)


def test_copy_makes_a_node_like_another() raises:
    var scene = Scene()
    var holder = scene.add(group())
    var target = scene.attach(group(), holder)
    var own = scene.attach(Object3D(), target)
    var source = scene.add(Object3D())
    scene.node(source).set_position(1, 2, 3)
    scene.node(source).name = "source"
    scene.node(source).visible = False
    scene.node(source).user_data.set_string("tag", "x")
    var kid = scene.attach(Object3D(), source)
    scene.node(kid).name = "kid"
    scene.copy(target, source)
    ref copied = scene.get(target)
    assert_equal(copied.name, "source")
    assert_vector(copied.position, 1, 2, 3)
    assert_false(copied.visible)
    assert_equal(copied.user_data.string("tag"), "x")
    # Its own parent, type and children stay, and a clone of the source's
    # child joins them.
    assert_equal(copied.parent.value, holder.value)
    assert_equal(copied.object_type, GROUP_TYPE)
    var kids = scene.children(target)
    assert_equal(len(kids), 2)
    assert_equal(kids[0].value, own.value)
    assert_equal(scene.get(kids[1]).name, "kid")
    assert_true(scene.in_scene(kids[1]))
    # Not recursive: no new children.
    scene.copy(own, source, recursive=False)
    assert_equal(len(scene.children(own)), 0)
    assert_equal(scene.get(own).name, "source")
    with assert_raises(contains="out of range"):
        scene.copy(NodeId(20), source)
    with assert_raises(contains="out of range"):
        scene.copy(target, NodeId(20))


# --- groups and their type ---------------------------------------------------


def test_a_group_is_an_object3d_of_the_group_type() raises:
    var made = group()
    assert_equal(made.object_type, GROUP_TYPE)
    assert_equal(Object3D().object_type, OBJECT3D_TYPE)
    assert_true(GROUP_TYPE.is_valid())
    assert_false(ObjectType(2).is_valid())
    assert_equal(Object3D(copy=made).object_type, GROUP_TYPE)


def test_a_node_of_no_type_is_refused_at_every_boundary() raises:
    var scene = Scene()
    var bad = Object3D()
    bad.object_type = ObjectType(5)
    with assert_raises(contains="Object3D or a Group"):
        _ = scene.add(bad)
    var node = scene.add(Object3D())
    with assert_raises(contains="Object3D or a Group"):
        scene.set(node, bad)
    scene.node(node).object_type = ObjectType(-1)
    with assert_raises(contains="Object3D or a Group"):
        scene.update()
    with assert_raises(contains="Object3D or a Group"):
        _ = object_to_json(scene, Assets())


def test_a_group_and_user_data_round_trip_through_scene_json() raises:
    var scene = Scene()
    var holder = scene.add(group())
    var plain = scene.attach(Object3D(), holder)
    scene.node(holder).user_data.set_json("spawn", '{"x": 1, "tags": ["a"]}')
    scene.node(holder).user_data.set_boolean("solid", True)
    var json = object_to_json(scene, Assets())
    assert_true(json.find('"type":"Group"') >= 0)
    assert_true(
        json.find('"userData":{"spawn":{"x":1,"tags":["a"]},"solid":true}') >= 0
    )
    var back = Scene()
    var assets = Assets()
    var model = read_object_json(json, back, assets)
    ref read = back.get(model.nodes[0])
    assert_equal(read.object_type, GROUP_TYPE)
    assert_equal(
        read.user_data.to_json(), scene.get(holder).user_data.to_json()
    )
    assert_equal(back.get(model.nodes[1]).object_type, OBJECT3D_TYPE)
    assert_equal(back.get(model.nodes[1]).user_data.count(), 0)
    _ = plain
    # A userData that is not an object is refused.
    var wrong = json.replace('"userData":{', '"userData":[{').replace(
        ',"solid":true}', ',"solid":true}]'
    )
    var refused = Scene()
    var refused_assets = Assets()
    with assert_raises(contains="JSON object"):
        _ = read_object_json(wrong, refused, refused_assets)


def test_user_data_is_written_as_gltf_extras() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    _ = scene.add(Object3D())
    scene.node(node).user_data.set_number("hp", 3)
    var text = String(unsafe_from_utf8=export_gltf(scene, Assets()).document)
    assert_true(text.find('"extras":{"hp":3}') >= 0)
    assert_equal(text.find('"extras"', text.find('"extras"') + 1), -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
