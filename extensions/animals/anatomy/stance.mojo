# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the limb muscles must do to hold a quadruped standing still.

The animal stands on four feet, each pressing at the middle of its
sole. Statics splits its weight between the fore and the hind feet by
where its center of mass lies between them: the fore share is
`(z_c - z_h) / (z_f - z_h)`. A center of mass behind the hind feet's
middle but over their soles, as in a crouching rat, puts all the weight
on the hind feet. Each foot pushes up with
half its pair's share. About each limb joint that push has a moment,
`-dz F`, with `dz` the foot's fore-aft distance from the joint; the
muscles that cross the joint must balance it.

The muscles whose moment arm opposes the load share it at one stress,
as an optimizer that minimizes the peak stress would share it:
`sigma = M / sum(r_i PCSA_i)`. The activation is that stress over the
specific tension, because a standing muscle is at its optimal length.

The effective mechanical advantage is the muscles' mean moment arm,
weighted by their forces, over the ground's moment arm, `r / R`
(Biewener 1989). A joint that no muscle here can hold, such as a
horse's fetlock, or one they could hold only above full activation,
reports `held` False: tendons and ligaments, such as a horse's stay
apparatus, hold it.
"""

from extensions.animals.anatomy.body import MAMMAL, species_body
from extensions.animals.anatomy.mass import BodyMass
from extensions.animals.anatomy.muscles import AnimalMuscle
from extensions.animals.build import Animal
from extensions.physics.quantities import NEWTON_METER, Torque
from extensions.sdf.vector import V3
from units.si import (
    METER,
    NEWTON,
    PASCAL,
    STANDARD_GRAVITY,
    Force,
    Length,
    Pressure,
)


@fieldwise_init
struct JointLoad(Copyable, Movable, Writable):
    """The static load on one joint of a standing animal."""

    var joint: String
    # The ground reaction on this limb's foot.
    var reaction: Force
    # The moment the muscles must make, positive by the right-hand rule
    # about the animal's left.
    var moment: Torque
    # The ground reaction's fore-aft lever about the joint.
    var ground_lever: Length
    # The holding muscles' force-weighted moment arm.
    var muscle_lever: Length
    # `muscle_lever / ground_lever`.
    var advantage: Float64
    # The holding muscles' shared stress.
    var stress: Pressure
    # That stress over the specific tension.
    var activation: Float64
    # Whether the muscles here can make the moment at full activation
    # or less. If not, tendons and ligaments hold the joint.
    var held: Bool


comptime _FORE = ["shoulder", "elbow", "wrist", "mcp"]
comptime _HIND = ["hip", "knee", "hock", "mtp"]


def _load(
    animal: Animal,
    muscles: List[AnimalMuscle],
    joint: String,
    foot: V3,
    push: Float64,
) raises -> JointLoad:
    var rig = animal.rig.copy()
    var world = animal.bind_pose().world(rig)
    var index = rig.find_joint(joint)
    var center = rig.joints[index]
    var dz = foot.z - center.z
    # The ground pushes up at the foot; the muscles must cancel it.
    var need = dz * push
    var lever_force = 0.0
    var force = 0.0
    var pcsa_lever = 0.0
    var tension = 0.0
    for m in muscles:
        for n in range(len(m.joints)):  # pragma: no branch
            if m.joints[n] != index:
                continue
            var r = Float64(m.moment_arms(rig, world)[n].value)
            if r * need <= 0.0:
                continue
            pcsa_lever += abs(r) * Float64(m.arch.pcsa().value)
            tension = Float64(m.arch.specific_tension.value)
    var able = pcsa_lever > 0.0
    var sigma = abs(need) / pcsa_lever if able else 0.0
    for m in muscles:
        for n in range(len(m.joints)):  # pragma: no branch
            if m.joints[n] != index:
                continue
            var r = Float64(m.moment_arms(rig, world)[n].value)
            if r * need <= 0.0:
                continue
            var f = sigma * Float64(m.arch.pcsa().value)
            force += f
            lever_force += abs(r) * f
    var lever = lever_force / force if force > 0.0 else 0.0
    var ground = abs(dz)
    return JointLoad(
        joint,
        Force(Float32(push), NEWTON),
        Torque(Float32(need), NEWTON_METER),
        Length(Float32(ground), METER),
        Length(Float32(lever), METER),
        lever / ground if ground > 0.0 else 0.0,
        Pressure(Float32(sigma), PASCAL),
        sigma / tension if able else 0.0,
        able and sigma <= tension,
    )


def standing_loads(
    animal: Animal, mass: BodyMass, muscles: List[AnimalMuscle]
) raises -> List[JointLoad]:
    """Return the static load on each left limb joint of a standing animal.

    Args:
        animal: The individual, at its real size, in its bind pose.
        mass: Its mass properties, sampled from the same sculpt.
        muscles: Its limb muscles, from `animal_muscles`.

    Returns:
        Shoulder to fetlock, then hip to hind fetlock.

    Raises:
        Error: If the animal is not a quadruped mammal, its center of
            mass is not over its feet, or its rig lacks a limb joint.
    """
    if species_body(animal.species).plan != MAMMAL:
        raise Error("Standing loads are for quadruped mammals")
    var total = mass.total()
    var weight = Float64(total.mass.value) * Float64(STANDARD_GRAVITY.value)
    var rig = animal.rig.copy()
    # Each foot presses at the middle of its sole. A sole runs from the
    # heel, the hock of a foot that stands on it, to the toe.
    var fore = (rig.j("mcpL") + rig.j("ftoeL")) * 0.5
    var hind = (rig.j("mtpL") + rig.j("htoeL")) * 0.5
    var heel = min(rig.j("hockL").z, rig.j("mtpL").z)
    var zc = Float64(total.center.z)
    if not (zc > heel and zc < fore.z):
        raise Error("The center of mass is not over the feet")
    # Over the hind soles themselves, the hind feet take it all, pressing
    # right under the center of mass.
    var share = max(0.0, (zc - hind.z) / (fore.z - hind.z))
    if share == 0.0:
        hind.z = zc
    var out = List[JointLoad]()
    for name in materialize[_FORE]():  # pragma: no branch
        out.append(
            _load(animal, muscles, name + "L", fore, 0.5 * share * weight)
        )
    for name in materialize[_HIND]():  # pragma: no branch
        out.append(
            _load(
                animal, muscles, name + "L", hind, 0.5 * (1.0 - share) * weight
            )
        )
    return out^
