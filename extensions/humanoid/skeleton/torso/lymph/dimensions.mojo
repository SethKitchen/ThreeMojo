# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named lymphatics of the torso, as implicit solids.

The cisterna chyli collects the lymph of the legs and the abdomen in
front of the first two lumbar bodies. The thoracic duct carries it up
between the aorta and the azygos vein toward the neck, which is not
modeled. Para-aortic nodes lie beside the lumbar aorta; parasternal
nodes follow the internal thoracic vessels. The axillary nodes lie in
the fat of the armpit and gather the arm's lymph and the chest wall's.
Five representative nodes stand for each group. Radii are authored ratios of stature. They are
not a cited count or size table.

The cisterna and the duct lie on the midline; the node groups are
paired, authored on the right and mirrored on x for the left.

    var dims = torso_muscle_dimensions(person)
    var d = torso_lymph_distance(dims, THORACIC_DUCT, RIGHT, p)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    template_points,
)
from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    TorsoMuscleDimensions,
)
from extensions.humanoid.skeleton.torso.sweep import (
    floats,
    Dome,
    Sweep,
    SweepField,
    tube,
)
from math.vector3 import Vector3


@fieldwise_init
struct TorsoLymph(Equatable, ImplicitlyCopyable, Writable):
    """Which named torso lymphatic a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named lymphatic."""
        if self.value < 0:
            return False
        return self.value <= AXILLARY_NODES.value


comptime CISTERNA_CHYLI = TorsoLymph(0)
comptime THORACIC_DUCT = TorsoLymph(1)
comptime PARA_AORTIC_NODES = TorsoLymph(2)
comptime PARASTERNAL_NODES = TorsoLymph(3)
# The apical, central, lateral, pectoral and subscapular nodes.
comptime AXILLARY_NODES = TorsoLymph(4)


def is_paired_lymph(part: TorsoLymph) raises -> Bool:
    """Return True if `part` is one of a pair.

    Args:
        part: A named lymphatic.

    Returns:
        True for the three node groups.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A torso lymphatic must be a named part")
    return part.value >= PARA_AORTIC_NODES.value


def torso_lymph_field(
    dimensions: TorsoMuscleDimensions, part: TorsoLymph, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one torso lymphatic.

    Args:
        dimensions: Landmarks shared with the muscles.
        part: A named lymphatic.
        side: `RIGHT` or `LEFT`. A midline part ignores it.

    Returns:
        The part's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    if not side.is_valid():
        raise Error("A torso side must be RIGHT or LEFT")
    var placed = RIGHT
    if is_paired_lymph(part):
        placed = side
    var t = dimensions.torso.copy()
    var f = t.frame
    var sweeps = List[Sweep]()
    if part == CISTERNA_CHYLI:
        var sac = Sweep(Vector3(1, 0, 0))
        sac.add(f.at(0.8, 22.5, 0.8), f.cm(0.6), f.cm(0.5))
        sac.add(f.at(0.8, 24.5, 0.8), f.cm(0.6), f.cm(0.5))
        sweeps.append(sac^)
    elif part == THORACIC_DUCT:
        sweeps.append(
            tube(
                template_points(
                    f,
                    floats(
                        0.8,
                        25.5,
                        0.6,
                        0.6,
                        32.0,
                        -1.0,
                        0.2,
                        40.0,
                        -2.6,
                        -0.8,
                        46.0,
                        -2.6,
                        -1.8,
                        51.5,
                        -1.8,
                    ),
                ),
                f.cm(0.15),
                f.cm(0.15),
            )
        )
    else:
        var nodes = template_points(
            f,
            floats(
                3.3,
                15.0,
                1.8,
                3.3,
                17.5,
                1.9,
                3.2,
                20.0,
                1.9,
                3.1,
                22.5,
                1.6,
                3.0,
                25.0,
                1.2,
            ),
        )
        var r = f.cm(0.45)
        if part == PARASTERNAL_NODES:
            nodes = template_points(
                f,
                floats(
                    3.3,
                    47.0,
                    3.5,
                    3.4,
                    44.5,
                    4.8,
                    3.4,
                    42.0,
                    5.8,
                    3.4,
                    39.5,
                    6.6,
                    3.4,
                    37.0,
                    7.4,
                ),
            )
            r = f.cm(0.3)
        if part == AXILLARY_NODES:
            # fmt: off
            nodes = template_points(f, floats(
                13.6, 46.8, 0.6, 15.0, 42.5, -1.0, 16.0, 43.8, -0.5,
                13.8, 40.8, 3.2, 13.5, 41.0, -4.5,
            ))
            # fmt: on
            r = f.cm(0.5)
        for index in range(len(nodes)):  # pragma: no branch
            var node = Sweep(Vector3(1, 0, 0))
            node.round(nodes[index], r)
            sweeps.append(node^)
    return SweepField(
        sweeps^, List[Dome](), placed, f.cm(0.03), f.cm(0.02), 0.004
    )


def torso_lymph_distance(
    dimensions: TorsoMuscleDimensions,
    part: TorsoLymph,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `torso_muscle_dimensions`.
        part: Which lymphatic to sample.
        side: `RIGHT` or `LEFT`. A midline part ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return torso_lymph_field(dimensions, part, side).distance(point)


def torso_lymph_label(part: TorsoLymph) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A torso lymphatic, named or not.

    Returns:
        A short American English label, or `"torso lymph"` when `part`
        is not named.
    """
    if part == CISTERNA_CHYLI:
        return "cisterna chyli"
    if part == THORACIC_DUCT:
        return "thoracic duct"
    if part == PARA_AORTIC_NODES:
        return "para-aortic nodes"
    if part == PARASTERNAL_NODES:
        return "parasternal nodes"
    if part == AXILLARY_NODES:
        return "axillary nodes"
    return "torso lymph"


def named_torso_lymph() -> List[TorsoLymph]:
    """Return every named torso lymphatic in a stable order.

    Returns:
        The cisterna, the duct and the three node groups.
    """
    var parts = List[TorsoLymph]()
    for index in range(AXILLARY_NODES.value + 1):  # pragma: no branch
        parts.append(TorsoLymph(index))
    return parts^
