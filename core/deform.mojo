# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Where a geometry's vertices actually are once its morph targets are
worn, from three.js's `morphtarget_vertex` and `morphnormal_vertex`.

A geometry says where its vertices were modelled. A mesh says how much of
each morph target it wears. Neither alone says where a vertex *is*, and
two things need that answer: the renderer, which draws it, and the
raycaster, which has to agree about what the pointer is over.

They did not agree. Rendering applied the targets and picking did not, so
a morphed mesh was drawn in one place and clicked in another -- and worse,
still clickable where it no longer was. That is what this module is for:
one evaluator, two callers, no second copy of the arithmetic to drift.

## What is here and what is not

Morph targets only. Skinning also moves a vertex, but it needs the posed
bones, which come from the scene rather than from the geometry, and the
renderer already builds them per frame. Picking a skinned mesh is not
supported yet -- `Raycaster.intersect_scene` reads `scene.meshes`, and a
skinned mesh is not in it -- so the split costs nothing today. When
picking learns about rigs, the carrier list belongs here beside the
targets.

## Why a list and not a callback

Both callers want every vertex, and both want to ask about bounds before
they ask about triangles. Handing back the whole array once is cheaper
than a call per vertex and simpler than an iterator, and it is what the
renderer already does with world and view positions.

A mesh wearing nothing gets the base positions copied. The callers avoid
paying for that by asking `Mesh.is_morphed` first, which is why this does
not try to be clever about it.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    MAX_MORPH_TARGETS,
    NORMAL,
    POSITION,
)
from math.bounds import Box3, Sphere
from math.vector3 import Vector3


def morph_offset(
    base: Vector3, target: Vector3, weight: Float32, relative: Bool
) -> Vector3:
    """Return how far one morph target moves a vertex at `weight`.

    three.js's two lines of `morphtarget_vertex`, and the same pair for a
    normal. A target that holds finished positions contributes the run from
    the base to itself; one that holds offsets contributes itself.

    It returns the offset rather than the moved point so that the caller
    can add every target's offset to the *unmorphed* value. Moving the
    point once per target instead measures each target from where the last
    one left it, and two half-worn targets then land somewhere neither of
    them names.

    Args:
        base: The vertex as the geometry modelled it.
        target: What this target says about it.
        weight: How much of this target the mesh wears.
        relative: Whether the target holds offsets rather than positions.

    Returns:
        The offset to add to the base.
    """
    if relative:
        return target * weight
    return (target - base) * weight


def morphed_positions(
    geometry: BufferGeometry,
    influences: SIMD[DType.float32, MAX_MORPH_TARGETS],
) raises -> List[Vector3]:
    """Return where every vertex is once the morph targets are worn.

    Args:
        geometry: The geometry, which must have positions.
        influences: How much of each of its targets the mesh wears.

    Returns:
        One point per vertex, in the geometry's own space.

    Raises:
        Error: If the geometry has no positions, or a target does not
            cover a vertex.
    """
    ref positions = geometry.attribute_view(String(POSITION))
    var targets = geometry.morph_count()
    var out = List[Vector3]()
    for vertex in range(positions.count()):  # pragma: no branch
        var base = positions.vector3(vertex)
        var moved = base
        for target in range(targets):
            moved = moved + morph_offset(
                base,
                geometry.morph_position(target, vertex),
                influences[target],
                geometry.morph_relative,
            )
        out.append(moved)
    return out^


def morphed_normals(
    geometry: BufferGeometry,
    influences: SIMD[DType.float32, MAX_MORPH_TARGETS],
) raises -> List[Vector3]:
    """Return which way every vertex faces once the morph targets are worn.

    A geometry whose targets carry no normals keeps its base normals
    however far the positions move, which is what three.js's shader does
    without `morphAttributes.normal`.

    Args:
        geometry: The geometry, which must have normals.
        influences: How much of each of its targets the mesh wears.

    Returns:
        One direction per vertex, not made unit length: the caller turns
        them by its own matrix and normalizes after.

    Raises:
        Error: If the geometry has no normals, or a target does not cover
            a vertex.
    """
    ref normals = geometry.attribute_view(String(NORMAL))
    var targets = geometry.morph_count()
    if not geometry.has_morph_normals():
        targets = 0
    var out = List[Vector3]()
    for vertex in range(normals.count()):  # pragma: no branch
        var rest = normals.vector3(vertex)
        var facing = rest
        for target in range(targets):
            facing = facing + morph_offset(
                rest,
                geometry.morph_normal(target, vertex),
                influences[target],
                geometry.morph_relative,
            )
        out.append(facing)
    return out^


def box_of(points: List[Vector3]) -> Box3:
    """Return the box around a list of points, empty for no points.

    Args:
        points: The points to bound.

    Returns:
        The box.
    """
    var box = Box3.empty()
    for index in range(len(points)):
        box.expand_by_point(points[index])
    return box^


def sphere_of(points: List[Vector3]) raises -> Sphere:
    """Return a sphere around a list of points.

    The same construction `BufferGeometry.bounding_sphere` uses: the center
    of the box around them, and the distance to the furthest one. It is not
    the smallest sphere that holds them, and it does not need to be -- it
    only has to hold them, which is what a rejection test needs.

    Args:
        points: The points to bound.

    Returns:
        The sphere.

    Raises:
        Error: If there are no points to bound.
    """
    if len(points) == 0:
        raise Error("A bound needs a point to be around")
    var box = box_of(points)
    var center = box.center()
    var reach = Float32(0)
    for index in range(len(points)):  # pragma: no branch
        var out = (points[index] - center).length()
        if out > reach:
            reach = out
    return Sphere(center, reach)
