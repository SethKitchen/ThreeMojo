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

The standing rig puts the hips at the origin, the thighs and the shins
straight down from them, and the ankles 0.85 m below. A tube is an open
vertical cylinder bound to one joint: a trunk, a leg or a foot.
"""

from std.math import cos, pi, sin

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from extensions.humanoid.rig.joints import (
    JOINT_COUNT,
    LEFT_THIGH,
    RIGHT_THIGH,
    HumanoidRig,
    Joint,
)
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT


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


def standing_rig(right_x: Float32 = -0.1) raises -> HumanoidRig:
    """Return a rig that stands at the template's stature, its hips at the
    origin.

    The thighs stand `right_x` from the middle, the right one at
    `right_x` and the left one opposite it, and run straight down 0.45 m
    to the knees. The shins run 0.4 m to the ankles at y = -0.85. Every
    other joint stands at the hips, its bone running up 0.1 m.

    Args:
        right_x: Where the right thigh stands across.

    Returns:
        The rig.
    """
    var joints = List[Vector3]()
    var ends = List[Vector3]()
    for _ in range(JOINT_COUNT):
        joints.append(Vector3(0, 0, 0))
        ends.append(Vector3(0, 0.1, 0))
    for side in range(2):
        var x = right_x
        var thigh = RIGHT_THIGH.value
        if side == 1:
            x = -right_x
            thigh = LEFT_THIGH.value
        joints[thigh] = Vector3(x, 0, 0)
        ends[thigh] = Vector3(x, -0.45, 0)
        joints[thigh + 1] = Vector3(x, -0.45, 0)
        ends[thigh + 1] = Vector3(x, -0.85, 0)
        joints[thigh + 2] = Vector3(x, -0.85, 0)
        ends[thigh + 2] = Vector3(x, -0.9, 0.15)
    return HumanoidRig(joints^, ends^, 1.8288)


def tube(
    x: Float32,
    z: Float32,
    radius: Float32,
    top: Float32,
    bottom: Float32,
    joint: Joint,
    rings: Int = 8,
    sides: Int = 12,
) raises -> BufferGeometry:
    """Return an open vertical tube, every vertex bound wholly to one joint.

    Args:
        x: Where its axis stands across.
        z: Where its axis stands front to back.
        radius: Its radius.
        top: The height of its top.
        bottom: The height of its bottom.
        joint: The joint every vertex is bound to.
        rings: How many bands it has, one or more.
        sides: How many sides it has, three or more.

    Returns:
        An indexed mesh with positions, normals and skin weights, facing
        out.
    """
    var flat = List[Float32]()
    var facing = List[Float32]()
    var bones = List[Float32]()
    var weights = List[Float32]()
    for r in range(rings + 1):
        var y = top + (bottom - top) * Float32(r) / Float32(rings)
        for s in range(sides):
            var turn = 2 * Float32(pi) * Float32(s) / Float32(sides)
            flat.append(x + radius * sin(turn))
            flat.append(y)
            flat.append(z + radius * cos(turn))
            facing.append(sin(turn))
            facing.append(0)
            facing.append(cos(turn))
            bones.append(Float32(joint.value))
            bones.append(0)
            bones.append(0)
            bones.append(0)
            weights.append(1)
            weights.append(0)
            weights.append(0)
            weights.append(0)
    var index = List[Int]()
    for r in range(rings):
        for s in range(sides):
            var a = r * sides + s
            var b = (r + 1) * sides + s
            var c = r * sides + (s + 1) % sides
            var d = (r + 1) * sides + (s + 1) % sides
            index.append(a)
            index.append(b)
            index.append(c)
            index.append(c)
            index.append(b)
            index.append(d)
    var mesh = BufferGeometry()
    mesh.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
    mesh.set_attribute(String(NORMAL), BufferAttribute(facing^, 3))
    mesh.set_attribute(String(SKIN_INDEX), BufferAttribute(bones^, 4))
    mesh.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))
    mesh.set_index(index^)
    return mesh^
