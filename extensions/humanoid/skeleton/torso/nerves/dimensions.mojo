# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named nerves of the torso, as implicit tubes.

The spinal cord runs down the vertebral canal from T1 and ends in the
conus at the first lumbar disc. The sympathetic trunks run down the
rib heads and the fronts of the lumbar bodies. The intercostal nerves
run under the ribs, and the iliohypogastric nerve crosses the back of
the abdomen toward the groin. The brain, the neck and the arm's nerves
are not modeled.

The spinal cord lies on the midline; the rest are paired, authored on
the right and mirrored on x for the left. Physical radii drive distance
and mass. Geometry applies a separate diagrammatic minimum radius.

    var dims = torso_muscle_dimensions(person)
    var d = torso_nerve_distance(dims, SPINAL_CORD, RIGHT, p)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    L1,
    along_path,
    canal_center,
    rib_path,
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
struct TorsoNerve(Equatable, ImplicitlyCopyable, Writable):
    """Which named torso nerve a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named nerves is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named nerve."""
        if self.value < 0:
            return False
        return self.value <= ILIOHYPOGASTRIC_NERVE.value


comptime SPINAL_CORD = TorsoNerve(0)
comptime SYMPATHETIC_TRUNK = TorsoNerve(1)
comptime INTERCOSTAL_NERVES = TorsoNerve(2)
comptime ILIOHYPOGASTRIC_NERVE = TorsoNerve(3)


def is_paired_nerve(part: TorsoNerve) raises -> Bool:
    """Return True if `part` is one of a pair.

    Args:
        part: A named nerve.

    Returns:
        False for the spinal cord.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A torso nerve must be a named nerve")
    return part != SPINAL_CORD


def torso_nerve_field(
    dimensions: TorsoMuscleDimensions, part: TorsoNerve, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one torso nerve.

    Args:
        dimensions: Landmarks shared with the muscles.
        part: A named nerve.
        side: `RIGHT` or `LEFT`. The spinal cord ignores it.

    Returns:
        The nerve's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    if not side.is_valid():
        raise Error("A torso side must be RIGHT or LEFT")
    var placed = RIGHT
    if is_paired_nerve(part):
        placed = side
    var t = dimensions.torso.copy()
    var f = t.frame
    var sweeps = List[Sweep]()
    if part == SPINAL_CORD:
        var cord = List[Vector3]()
        for index in range(L1.value + 1):
            cord.append(canal_center(t, index))
        # The conus ends at the disc below the first lumbar vertebra.
        cord.append(canal_center(t, L1.value + 1) + Vector3(0, f.cm(1.2), 0))
        sweeps.append(tube(cord, f.cm(0.5), f.cm(0.3)))
    elif part == SYMPATHETIC_TRUNK:
        var chain = List[Vector3]()
        for index in range(1, 11, 3):
            var c = t.centers[index]
            chain.append(
                Vector3(t.widths[index] + f.cm(0.8), c.y, c.z + f.cm(0.2))
            )
        for index in range(13, 16, 2):
            var c = t.centers[index]
            chain.append(
                Vector3(
                    t.widths[index] - f.cm(0.2),
                    c.y,
                    c.z + t.depths[index] - f.cm(0.2),
                )
            )
        sweeps.append(tube(chain, f.cm(0.15), f.cm(0.15)))
    elif part == INTERCOSTAL_NERVES:
        for rib in range(11):
            var path = rib_path(t, rib)
            var run = List[Vector3]()
            for k in range(9):
                var at = along_path(path, 0.08 + 0.1 * Float32(k))
                run.append(at - Vector3(0, f.cm(0.8), 0))
            sweeps.append(tube(run, f.cm(0.12), f.cm(0.1)))
    else:
        sweeps.append(
            tube(
                template_points(
                    f,
                    floats(
                        3.0,
                        24.0,
                        -3.0,
                        7.5,
                        21.0,
                        -3.8,
                        11.5,
                        17.0,
                        -1.5,
                        13.0,
                        14.0,
                        3.0,
                        9.0,
                        8.0,
                        7.0,
                    ),
                ),
                f.cm(0.13),
                f.cm(0.1),
            )
        )
    return SweepField(
        sweeps^, List[Dome](), placed, f.cm(0.03), f.cm(0.02), 0.004
    )


def torso_nerve_distance(
    dimensions: TorsoMuscleDimensions,
    part: TorsoNerve,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `torso_muscle_dimensions`.
        part: Which nerve to sample.
        side: `RIGHT` or `LEFT`. The spinal cord ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return torso_nerve_field(dimensions, part, side).distance(point)


def torso_nerve_label(part: TorsoNerve) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A torso nerve, named or not.

    Returns:
        A short American English label, or `"torso nerve"` when `part`
        is not named.
    """
    if part == SPINAL_CORD:
        return "spinal cord"
    if part == SYMPATHETIC_TRUNK:
        return "sympathetic trunk"
    if part == INTERCOSTAL_NERVES:
        return "intercostal nerves"
    if part == ILIOHYPOGASTRIC_NERVE:
        return "iliohypogastric nerve"
    return "torso nerve"


def named_torso_nerves() -> List[TorsoNerve]:
    """Return every named torso nerve in a stable order.

    Returns:
        The cord, the sympathetic trunk, the intercostals and the
        iliohypogastric nerve.
    """
    var parts = List[TorsoNerve]()
    for index in range(ILIOHYPOGASTRIC_NERVE.value + 1):
        parts.append(TorsoNerve(index))
    return parts^
