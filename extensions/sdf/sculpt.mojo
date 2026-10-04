# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compound sculpting helpers: an ellipsoid aimed by its long axis, and
a smooth tube along a Catmull-Rom curve.

These are procedural-animals' `ellY` and `tube`.
"""

from extensions.sdf.field import SdfModel
from extensions.sdf.ids import BoneId, SurfacePart
from extensions.sdf.vector import V3, cross, normalize


def ell_y(
    mut m: SdfModel,
    tag: String,
    bone: BoneId,
    c: V3,
    ydir: V3,
    r: V3,
    lateral: V3 = V3(1.0, 0.0, 0.0),
    k: Float64 = 0.02,
    carve: Bool = False,
    part: SurfacePart = SurfacePart(0),
    thin: Bool = False,
) raises -> Int:
    """Add an ellipsoid whose local y follows a direction.

    Args:
        m: The sculpt.
        tag: What the primitive is.
        bone: The bone it rides.
        c: The center.
        ydir: The direction of the local y axis.
        r: The radii: lateral, along `ydir`, and the third axis.
        lateral: A direction near the local x axis.
        k: The blend radius.
        carve: Whether it cuts instead of adds.
        part: The surface it belongs to.
        thin: Whether coarse meshes must inflate it to stay visible.

    Returns:
        Its index.

    Raises:
        Error: If `SdfModel.ell` refuses it.
    """
    var y = normalize(ydir)
    var z = normalize(cross(lateral, y))
    return m.ell(
        tag, bone, c, r, axis=z, up=y, k=k, carve=carve, part=part, thin=thin
    )


def _catmull(p0: V3, p1: V3, p2: V3, p3: V3, t: Float64) -> V3:
    var t2 = t * t
    var t3 = t2 * t
    return (
        p1 * 2.0
        + (p2 - p0) * t
        + (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
        + (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3
    ) * 0.5


def tube(
    mut m: SdfModel,
    tag: String,
    bone: BoneId,
    points: List[V3],
    radii: List[Float64],
    after: V3,
    n: Int,
    k: Float64,
    part: SurfacePart = SurfacePart(0),
) raises:
    """Add a tube along a Catmull-Rom curve, as a chain of round cones.

    The first span is one cone that blends into what is there with `k`.
    Every later span is `n` cones joined by a hard union: round cones
    that share their end balls and tangents meet smoothly, while a smooth
    union of overlapping cones would swell at every joint.

    Args:
        m: The sculpt.
        tag: What the primitives are.
        bone: The bone they ride.
        points: The control points.
        radii: The radius at each control point.
        after: A point beyond the last, which sets the end tangent.
        n: Cones per span after the first.
        k: The first cone's blend radius.
        part: The surface they belong to.

    Raises:
        Error: If fewer than two points are given, the lists differ in
            length, or `SdfModel.cone` refuses a cone.
    """
    if len(points) < 2 or len(points) != len(radii):
        raise Error("A tube needs two or more points, one radius each")
    var last = len(points) - 1
    for i in range(last):  # pragma: no branch
        var p0 = points[max(0, i - 1)]
        var p3 = points[i + 2] if i + 2 <= last else after
        var spans = 1 if i == 0 else n
        for j in range(spans):
            var t0 = Float64(j) / Float64(spans)
            var t1 = Float64(j + 1) / Float64(spans)
            var dr = radii[i + 1] - radii[i]
            _ = m.cone(
                tag,
                bone,
                _catmull(p0, points[i], points[i + 1], p3, t0),
                _catmull(p0, points[i], points[i + 1], p3, t1),
                radii[i] + dr * t0,
                radii[i] + dr * t1,
                k=k if i == 0 else 0.0,
                part=part,
            )
