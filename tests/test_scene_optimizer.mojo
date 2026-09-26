# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.scene_optimizer`.

`assets/optimizer/three.json` holds what three.js r180's
`SceneOptimizer.toBatchedMesh` makes of one scene, run in Node by
`three_optimizer.mjs` beside it. The scene here is the same: a turned
group `Shelf` of three boxes and a sphere whose materials differ only in
color and a box of another material, a group `Empty` that holds a bare
node, and a node `Lamp` with a point light.
"""

from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from core.scene_optimizer import (
    SceneOptimizer,
    attributes_signature,
    material_signature,
)
from geometries.box import box
from geometries.sphere import sphere
from lights.light import point_light
from loaders.json import JsonDocument, parse_json
from materials.material import (
    LAMBERT,
    Material,
    MaterialId,
    standard_material,
)
from math.matrix4 import Matrix4
from objects.group import group
from objects.instanced_mesh import InstancedMesh
from objects.line import Line
from objects.line_segments2 import LineSegments2
from objects.lod import Lod
from objects.mesh import Mesh
from objects.points import Points
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SkinnedMesh
from objects.sprite import Sprite
from render.framebuffer import Color
from render.texture import Texture
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, Length, METER, RADIAN


def _node(name: String, x: Float32, y: Float32, z: Float32) raises -> Object3D:
    """Return a named node at a place, turned `x / 10` radians about x, as
    the reference turns each mesh."""
    var node = Object3D()
    node.name = name
    node.set_position(x, y, z)
    node.set_euler(
        Angle(x * 0.1, RADIAN), Angle(0.0, RADIAN), Angle(0.0, RADIAN)
    )
    return node^


def _build(mut scene: Scene, mut assets: Assets) raises:
    """Build the scene of the module docstring."""
    var side = Length(1.0, METER)
    var cube = assets.geometries.add(box(side, side, side))
    var ball = assets.geometries.add(sphere(Length(0.5, METER)))
    var shelf = group()
    shelf.name = "Shelf"
    shelf.set_position(1, 0, 0)
    shelf.set_euler(Angle(0.0, RADIAN), Angle(0.5, RADIAN), Angle(0.0, RADIAN))
    var held = scene.add(shelf^)
    var colors: List[Color] = [
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 0, 0),
    ]
    var names: List[String] = ["A", "B", "C", "D"]
    var places: List[Float32] = [0, 1, 0, 2, 0, 1, -1, 0.5, 2, 0, -1, -1]
    for at in range(4):
        var color = colors[at]
        var paint = assets.materials.add(Material(color, kind=LAMBERT))
        var node = scene.attach(
            _node(
                names[at],
                places[3 * at],
                places[3 * at + 1],
                places[3 * at + 2],
            ),
            held,
        )
        scene.add_mesh(Mesh(ball if at == 3 else cube, paint, node))
    var other = assets.materials.add(
        standard_material(Color(255, 255, 255), roughness=0.3)
    )
    scene.add_mesh(Mesh(cube, other, scene.attach(_node("Odd", 0, 0, 0), held)))
    var empty = group()
    empty.name = "Empty"
    var hollow = scene.add(empty^)
    _ = scene.attach(_node("Leaf", 0, 0, 0), hollow)
    var lamp = scene.add(_node("Lamp", 0, 0, 0))
    scene.add_light(point_light(Color(255, 255, 255), lamp))
    scene.update()


def _reference() raises -> JsonDocument:
    """Return what three.js made."""
    return parse_json(Path("assets/optimizer/three.json").read_text())


def test_the_meshes_are_batched_as_three_js_batches_them() raises:
    var scene = Scene()
    var assets = Assets()
    _build(scene, assets)
    var stats = SceneOptimizer().to_batched_mesh(scene, assets)
    assert_equal(stats.original_meshes, 5)
    assert_equal(stats.batched_meshes, 1)
    assert_equal(stats.single_meshes, 1)
    assert_equal(stats.draw_calls, 2)
    assert_equal(stats.unique_geometries, 2)
    var doc = _reference()
    # The nodes left, depth first.
    var nodes = doc.get(doc.root(), "nodes")
    var order = scene.traverse()
    assert_equal(len(order), doc.length(nodes))
    for at in range(len(order)):
        assert_equal(scene.get(order[at]).name, doc.string(doc.at(nodes, at)))
    # The one batch.
    var batches = doc.get(doc.root(), "batches")
    assert_equal(len(scene.batched_meshes), doc.length(batches))
    var want = doc.at(batches, 0)
    ref batch = scene.batched_meshes[0]
    assert_equal(scene.get(batch.node).name, doc.string(doc.get(want, "name")))
    var parent = scene.get(batch.node).parent
    assert_equal(scene.get(parent).name, doc.string(doc.get(want, "parent")))
    assert_equal(
        len(batch.geometries), doc.integer(doc.get(want, "geometries"))
    )
    var instances = doc.get(want, "instances")
    assert_equal(batch.count(), doc.length(instances))
    for at in range(batch.count()):
        var instance = doc.at(instances, at)
        var matrix = batch.matrix_at(at)
        for element in range(16):
            assert_almost_equal(
                Float64(matrix.elements[element]),
                doc.number(doc.at(doc.get(instance, "matrix"), element)),
                atol=1e-5,
            )
        var color = batch.color_at(at)
        var rgb = doc.get(instance, "color")
        assert_equal(Float64(color.r) / 255, doc.number(doc.at(rgb, 0)))
        assert_equal(Float64(color.g) / 255, doc.number(doc.at(rgb, 1)))
        assert_equal(Float64(color.b) / 255, doc.number(doc.at(rgb, 2)))
    # The batch wears the first mesh's material, in white.
    var worn = assets.materials.get(batch.material)
    assert_equal(worn.color.r, 255)
    assert_equal(worn.color.g, 255)
    assert_equal(worn.kind, LAMBERT)


def test_the_signatures_leave_out_the_color() raises:
    var assets = Assets()
    var red = Material(Color(255, 0, 0), kind=LAMBERT)
    var blue = Material(Color(0, 0, 255), kind=LAMBERT)
    assert_equal(
        material_signature(assets, red), material_signature(assets, blue)
    )
    blue.opacity = 0.5
    assert_true(
        material_signature(assets, red) != material_signature(assets, blue)
    )
    var side = Length(1.0, METER)
    assert_equal(
        attributes_signature(box(side, side, side)),
        "normal_3_False|position_3_False|uv_2_False",
    )


def test_a_kept_node_stays() raises:
    var scene = Scene()
    var assets = Assets()
    _build(scene, assets)
    var leaf = scene.find("Leaf").value()
    _ = SceneOptimizer([leaf]).to_batched_mesh(scene, assets)
    assert_true(Bool(scene.find("Leaf")))
    assert_true(Bool(scene.find("Empty")))
    with assert_raises(contains="not implemented"):
        SceneOptimizer().to_instancing_mesh()


def test_meshes_at_the_top_are_batched_at_the_top() raises:
    var scene = Scene()
    var assets = Assets()
    var side = Length(1.0, METER)
    var cube = assets.geometries.add(box(side, side, side))
    var shape = box(side, side, side)
    shape.delete_attribute("uv")
    var bare = assets.geometries.add(shape^)
    var mapped = Material(Color(255, 0, 0), kind=LAMBERT)
    mapped.map = assets.textures.add(Texture())
    var paint = assets.materials.add(mapped^)
    # Two boxes of one material, a box of the same index with no texture
    # coordinates, and a box of two materials, which is left as it is.
    scene.add_mesh(Mesh(cube, paint, scene.add(_node("A", 0, 0, 0))))
    scene.add_mesh(Mesh(cube, paint, scene.add(_node("B", 1, 0, 0))))
    scene.add_mesh(Mesh(bare, paint, scene.add(_node("C", 2, 0, 0))))
    var parts = Mesh(cube, paint, scene.add(_node("D", 3, 0, 0)))
    parts.materials = [paint, paint]
    scene.add_mesh(parts)
    var stats = SceneOptimizer().to_batched_mesh(scene, assets)
    assert_equal(stats.original_meshes, 3)
    assert_equal(stats.batched_meshes, 1)
    assert_equal(stats.single_meshes, 1)
    assert_equal(stats.unique_geometries, 2)
    ref batch = scene.batched_meshes[0]
    assert_equal(scene.get(batch.node).parent, NO_PARENT)
    assert_equal(scene.get(batch.node).name, "A_batch")
    # A map is a part of the signature.
    assert_true(
        material_signature(assets, assets.materials.get(paint))
        != material_signature(assets, Material(Color(255, 0, 0), kind=LAMBERT))
    )


def test_a_node_that_carries_anything_stays() raises:
    var scene = Scene()
    var assets = Assets()
    _ = SceneOptimizer().to_batched_mesh(scene, assets)
    assert_equal(len(scene.traverse()), 0)
    var geometry = GeometryId(0)
    var material = MaterialId(0)
    var names: List[String] = [
        "Skinned",
        "Instanced",
        "Lod",
        "Line",
        "Points",
        "Sprite",
        "Wide",
        "Bare",
    ]
    var nodes = List[NodeId]()
    for at in range(len(names)):
        nodes.append(scene.add(_node(names[at], 0, 0, 0)))
    scene.add_skinned_mesh(
        SkinnedMesh(
            geometry, material, nodes[0], Skeleton([Bone(nodes[0], Matrix4())])
        )
    )
    scene.add_instanced_mesh(InstancedMesh(geometry, material, nodes[1], 1))
    scene.add_lod(Lod(nodes[2]))
    scene.add_line(Line(geometry, material, nodes[3]))
    scene.add_points(Points(geometry, material, nodes[4]))
    scene.add_sprite(Sprite(material, nodes[5]))
    scene.add_wide_line(LineSegments2(geometry, material, nodes[6]))
    var stats = SceneOptimizer().to_batched_mesh(scene, assets)
    assert_equal(stats.original_meshes, 0)
    # Only the bare node is taken out.
    var left = scene.traverse()
    assert_equal(len(left), 7)
    for at in range(len(left)):
        assert_equal(scene.get(left[at]).name, names[at])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
