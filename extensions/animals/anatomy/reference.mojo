# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Grid-independent reference landmarks for the authored animal template.

These are DESIGN envelope measurements, not measured anatomy. Ellipsoids
and round cones use analytic supports. Fins use their finite polygon and
thickness envelope. Lenses use their local bounding rectangle. Carvers
and smooth blends do not alter the landmark envelope. The coat is kept
for total length; body and withers roles select their named solids.

The construction is covariant under a uniform scale. It avoids treating
an under-resolved occupancy grid as dimensional validation.
"""

from extensions.animals.anatomy.body import (
    BODY_LENGTH,
    SHOULDER_HEIGHT,
    species_body,
)
from extensions.animals.anatomy.density import (
    IN_BODY,
    ON_WITHERS,
    solid_densities,
    solid_roles,
)
from extensions.animals.anatomy.mass import _check_sampling_model
from extensions.animals.anatomy.tissue import FOREIGN, tissue_of
from extensions.animals.build import Animal
from extensions.sdf.field import Primitive
from extensions.sdf.ids import CONE, ELLIPSOID, FIN
from extensions.sdf.vector import V3, dot
from std.math import isfinite, sqrt
from units.si import Length, METER


def _extent(
    p: Primitive, outline: List[Float64], direction: V3
) -> Tuple[Float64, Float64]:
    var center = dot(p.c, direction)
    if p.kind == ELLIPSOID:
        var x = dot(p.ax, direction) * p.r.x
        var y = dot(p.ay, direction) * p.r.y
        var z = dot(p.az, direction) * p.r.z
        var radius = sqrt(x * x + y * y + z * z)
        return (center - radius, center + radius)
    if p.kind == CONE:
        var end = dot(p.b, direction)
        return (
            min(center - p.r.x, end - p.r.y),
            max(center + p.r.x, end + p.r.y),
        )
    if p.kind == FIN:
        var low = 1e300
        var high = -1e300
        # The model was checked first: a fin has three points at least.
        for i in range(p.first, p.first + p.count):  # pragma: no branch
            var u = outline[2 * i]
            var v = outline[2 * i + 1]
            var q = center + dot(p.ax, direction) * u + dot(p.ay, direction) * v
            var half = max(0.2 * p.r.x, p.r.x + p.lo * u + p.hi * v)
            var radius = abs(dot(p.az, direction)) * half
            low = min(low, q - radius)
            high = max(high, q + radius)
        return (low, high)
    # Conservative local rectangle of the intersection of two circles.
    var x = sqrt(p.r.x * p.r.x - p.r.y * p.r.y)
    var y = p.r.x - abs(p.r.y)
    var middle = 0.5 * (p.lo + p.hi)
    var depth = 0.5 * (p.hi - p.lo)
    center += dot(p.az, direction) * middle
    var radius = (
        abs(dot(p.ax, direction)) * x
        + abs(dot(p.ay, direction)) * y
        + abs(dot(p.az, direction)) * depth
    )
    return (center - radius, center + radius)


def reference_length(animal: Animal) raises -> Length:
    """Measure the selected geometric reference envelope, without a voxel grid.

    Args:
        animal: The individual, in its bind geometry.

    Returns:
        The template's withers height or projected body/total length.
        This is a DESIGN landmark, not a biological measurement.

    Raises:
        Error: If the model is malformed, the reference is absent, the
            geometry is visual-only, or the result cannot fit an SI length.
    """
    if (
        animal.model.visual_only
        or animal.traits.get("anatomy_visual_flex", 0.0) != 0.0
    ):
        raise Error("Visual flex geometry has no canonical reference landmark")
    var body = species_body(animal.species)
    var densities = solid_densities(animal)
    var roles = solid_roles(animal)
    _check_sampling_model(animal.model)
    var ground = 1e300
    var withers = -1e300
    var low = 1e300
    var high = -1e300
    var y = V3(0, 1, 0)
    var z = V3(0, 0, 1)
    for i in range(len(animal.model.prims)):
        ref p = animal.model.prims[i]
        if p.carve:
            continue
        var bone = animal.rig.bones[p.bone.value].name
        if tissue_of(p.part, animal.model.tags[p.tag.value], bone) == FOREIGN:
            continue
        if body.reference == SHOULDER_HEIGHT:
            if densities[i] <= 0.0:
                continue
            var bounds = _extent(p, animal.model.outline, y)
            ground = min(ground, bounds[0])
            if roles[i] & ON_WITHERS != 0:
                withers = max(withers, bounds[1])
        else:
            if body.reference == BODY_LENGTH and roles[i] & IN_BODY == 0:
                continue
            var bounds = _extent(p, animal.model.outline, z)
            low = min(low, bounds[0])
            high = max(high, bounds[1])
    var value = (
        withers - ground if body.reference == SHOULDER_HEIGHT else high - low
    )
    if not (isfinite(Float32(value)) and Float32(value) > 0.0):
        raise Error("A reference landmark must fit a positive finite SI length")
    return Length(Float32(value), METER)
