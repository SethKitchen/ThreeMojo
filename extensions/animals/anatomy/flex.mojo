# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Muscle bellies that bulge as they shorten.

The surface response is a visual design model. In a pose, each muscle's
fiber length is its path length less its rigid tendon's slack length.
An ellipsoid belly shrinks by `f^w` on its nearest longitudinal axis and
grows by `f^(-w/2)` on the other two axes. This preserves that primitive's
volume. A round cone only widens across: its endpoints stay fixed, so
its volume is not conserved. Overlapping unions need not keep their
volume even when each ellipsoid does.

`w`, the response seen through skin and fat, is 0.5: a `DESIGN` value.
`f` is held to 0.6 to 1.4. These visual sculpts are not conserved tissue
mass models. The engineering layer's separate ellipsoid muscle bellies
use their explicitly specified volumes.

The bind pose leaves every solid as it is: there each muscle's fibers
are at their optimal length.
"""

from extensions.animals.anatomy.muscles import AnimalMuscle
from extensions.animals.build import Animal
from extensions.animals.rig import Pose
from extensions.sdf.field import SdfModel
from extensions.sdf.ids import CONE, ELLIPSOID
from extensions.sdf.vector import V3, Rigid, dot, length
from std.math import pow

# The share of a belly's change in shape that the surface shows.
comptime BULGE_SHARE = 0.5


def fiber_ratio(muscle: AnimalMuscle, world: List[Rigid]) raises -> Float64:
    """Return a muscle's fiber length over its optimal length, in a pose.

    Args:
        muscle: The muscle.
        world: The pose's world transform of each bone.

    Returns:
        The ratio with a rigid tendon, held to `[0.6, 1.4]`.

    Raises:
        Error: If the muscle architecture or path is invalid.
    """
    muscle.arch.check()
    var unit = Float64(muscle.unit_length(world).value)
    var fiber = unit - Float64(muscle.arch.tendon_slack.value)
    var f = fiber / Float64(muscle.arch.fiber_length.value)
    return min(1.4, max(0.6, f))


def flexed(
    animal: Animal, muscles: List[AnimalMuscle], pose: Pose
) raises -> SdfModel:
    """Return the sculpt with each muscle's belly shaped for a pose.

    The sculpt stays in the bind pose; mesh it moved by the same pose.
    It is a visual surface, not a conserved tissue-mass field.

    Args:
        animal: The individual.
        muscles: Its muscles, from the same rig.
        pose: The pose.

    Returns:
        A copy of the sculpt with the belly solids reshaped.

    Raises:
        Error: If the pose is for another rig.
    """
    var world = pose.world(animal.rig)
    var model = animal.model.copy()
    model.visual_only = True
    # Primitives are mutable. Validate IDs before any belly selection can
    # index the rig or the tag table, including the direct flexed API.
    for p in model.prims:
        animal.rig.check(p.bone)
        if not p.tag.is_valid() or p.tag.value >= len(model.tags):
            raise Error("Tag id names no tag of this sculpt")
    for m in muscles:
        if len(m.bellies) == 0:
            continue
        var f = fiber_ratio(m, world)
        var along = pow(f, BULGE_SHARE)
        var across = pow(f, -0.5 * BULGE_SHARE)
        var line = m.points[len(m.points) - 1] - m.points[0]
        var span = length(line)
        if not span > 0.0:
            raise Error("A muscle belly needs distinct bind endpoints")
        var d = line * (1.0 / span)
        for i in range(len(model.prims)):  # pragma: no branch
            ref p = model.prims[i]
            var bone = animal.rig.bones[p.bone.value].name
            if not bone.endswith(m.side):
                continue
            if model.tags[p.tag.value] not in m.bellies:
                continue
            if p.kind == ELLIPSOID:
                var dx = abs(dot(p.ax, d))
                var dy = abs(dot(p.ay, d))
                var dz = abs(dot(p.az, d))
                var sx = along if dx >= dy and dx >= dz else across
                var sy = along if dy > dx and dy >= dz else across
                var sz = along if dz > dx and dz > dy else across
                p.r = V3(p.r.x * sx, p.r.y * sy, p.r.z * sz)
            elif p.kind == CONE:
                p.r = V3(p.r.x * across, p.r.y * across, p.r.z)
    return model^


def flexed_animal(
    animal: Animal, muscles: List[AnimalMuscle], pose: Pose
) raises -> Animal:
    """Return the individual with its bellies shaped for a pose.

    Mesh it with the same pose: `mesh_animal(flexed_animal(a, m, p), p)`.
    The result is marked visual-only; tissue mass sampling refuses it.

    Args:
        animal: The individual.
        muscles: Its muscles, from the same rig.
        pose: The pose.

    Returns:
        A copy of the individual with the reshaped sculpt.

    Raises:
        Error: If the pose is for another rig.
    """
    var traits = animal.traits.copy()
    traits.set("anatomy_visual_flex", 1.0)
    return Animal(
        animal.species,
        animal.options,
        traits^,
        animal.rig.copy(),
        flexed(animal, muscles, pose),
        animal.palette.copy(),
        animal.eye,
        animal.look,
        animal.cell,
        animal.eye_cell,
    )
