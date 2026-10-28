# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Synthetic rigs and meshes for the tests of `extensions.attire`.

The line rig stands each joint one meter apart along x. Each bone runs
one meter straight down from its joint. The stature is the template's,
so the face opening keeps its template size.

A strip is a ladder of quads down the y axis, from y = 0 to y = -1, in
the plane z = 0, facing +z. Every vertex is bound wholly to one joint.

An empty mesh has every attribute a garment has, and no vertex.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.rig.game import GameHumanoid, add_game_humanoid
from extensions.humanoid.rig.joints import JOINT_COUNT, HumanoidRig, Joint
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from renderers.renderer import available_workers
from units.si import FOOT, Length


def line_rig() raises -> HumanoidRig:
    """Return a rig whose joint `j` stands at x = j, its bone one meter
    straight down.

    Returns:
        The rig, at the template's stature.
    """
    var joints = List[Vector3]()
    var ends = List[Vector3]()
    for j in range(JOINT_COUNT):
        joints.append(Vector3(Float32(j), 0, 0))
        ends.append(Vector3(Float32(j), -1, 0))
    return HumanoidRig(joints^, ends^, 1.8288)


def strip(
    x: Float32, rungs: Int, joint: Joint, normals: Bool = True
) raises -> BufferGeometry:
    """Return an indexed ladder of quads down from (x, 0, 0) to (x, -1, 0).

    Args:
        x: Where the ladder stands.
        rungs: How many quads, one or more.
        joint: The joint every vertex is bound to.
        normals: Whether to give it normals facing +z.

    Returns:
        The mesh: two vertices a rung, one meter wide in z = 0.
    """
    var flat = List[Float32]()
    var facing = List[Float32]()
    var bones = List[Float32]()
    var weights = List[Float32]()
    for r in range(rungs + 1):
        var y = -Float32(r) / Float32(rungs)
        for side in range(2):
            flat.append(x + Float32(side) - 0.5)
            flat.append(y)
            flat.append(0)
            facing.append(0)
            facing.append(0)
            facing.append(1)
            bones.append(Float32(joint.value))
            bones.append(0)
            bones.append(0)
            bones.append(0)
            weights.append(1)
            weights.append(0)
            weights.append(0)
            weights.append(0)
    var index = List[Int]()
    for r in range(rungs):
        var a = 2 * r
        index.append(a)
        index.append(a + 1)
        index.append(a + 2)
        index.append(a + 1)
        index.append(a + 3)
        index.append(a + 2)
    var mesh = BufferGeometry()
    mesh.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
    if normals:
        mesh.set_attribute(String(NORMAL), BufferAttribute(facing^, 3))
    mesh.set_attribute(String(SKIN_INDEX), BufferAttribute(bones^, 4))
    mesh.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))
    mesh.set_index(index^)
    return mesh^


def empty_mesh(normals: Bool = True) raises -> BufferGeometry:
    """Return a skinned mesh with no vertex and no triangle.

    Args:
        normals: Whether to give it an empty normal attribute.

    Returns:
        The mesh: empty positions, skin indices and skin weights, and an
        empty index.
    """
    var mesh = BufferGeometry()
    mesh.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    if normals:
        mesh.set_attribute(String(NORMAL), BufferAttribute(List[Float32](), 3))
    mesh.set_attribute(String(SKIN_INDEX), BufferAttribute(List[Float32](), 4))
    mesh.set_attribute(String(SKIN_WEIGHT), BufferAttribute(List[Float32](), 4))
    mesh.set_index(List[Int]())
    return mesh^


def coarse_spec() -> HumanoidSpec:
    """Return the six-foot male template."""
    return HumanoidSpec(Length(6.0, FOOT), MALE)


def coarse_person(
    mut scene: Scene, mut assets: Assets, guides: Int = 0
) raises -> GameHumanoid:
    """Return a coarse game humanoid in `scene`: detail 12, 3000 triangles.

    Args:
        scene: The scene.
        assets: The store.
        guides: Guide strands of hair, or none.

    Returns:
        The humanoid.
    """
    var root = scene.add(Object3D())
    return add_game_humanoid(
        scene,
        assets,
        root,
        coarse_spec(),
        3000,
        12,
        8,
        8,
        guides=guides,
        followers=1 if guides > 0 else 0,
        workers=available_workers(),
    )
