# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named arteries and veins of the torso, as implicit tubes.

The aorta rises from where the heart would be, arches over to the left
of the spine and descends to meet the pelvis's abdominal aorta. The
inferior vena cava climbs right of the spine to where the heart would
take it. The azygos vein runs up the right of the bodies and arches
forward. The internal thoracic arteries run behind the costal
cartilages and continue as the epigastric arteries in the rectus
sheath. Intercostal arteries and veins run under the ribs.

The heart, the great vessels of the neck and the arm's vessels are not
modeled. The aorta, the vena cava and the azygos vein are unpaired;
the rest are paired, authored on the right and mirrored on x for the
left. Physical radii drive distance and mass. Geometry applies a
separate diagrammatic minimum radius.

    var dims = torso_muscle_dimensions(person)
    var d = torso_vessel_distance(dims, THORACIC_AORTA, RIGHT, p)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    along_path,
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
struct TorsoVessel(Equatable, ImplicitlyCopyable, Writable):
    """Which named torso artery or vein a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named vessels is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named vessel."""
        if self.value < 0:
            return False
        return self.value <= INTERCOSTAL_VEINS.value


comptime THORACIC_AORTA = TorsoVessel(0)
comptime UPPER_ABDOMINAL_AORTA = TorsoVessel(1)
comptime UPPER_VENA_CAVA = TorsoVessel(2)
comptime AZYGOS_VEIN = TorsoVessel(3)
comptime INTERNAL_THORACIC_ARTERY = TorsoVessel(4)
comptime EPIGASTRIC_ARTERY = TorsoVessel(5)
comptime INTERCOSTAL_ARTERIES = TorsoVessel(6)
comptime INTERCOSTAL_VEINS = TorsoVessel(7)


def is_torso_artery(part: TorsoVessel) raises -> Bool:
    """Return True if `part` is an artery.

    Args:
        part: A named vessel.

    Returns:
        True for the aorta and the paired arteries.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A torso vessel must be a named artery or vein")
    return (
        part == THORACIC_AORTA
        or part == UPPER_ABDOMINAL_AORTA
        or part == INTERNAL_THORACIC_ARTERY
        or part == EPIGASTRIC_ARTERY
        or part == INTERCOSTAL_ARTERIES
    )


def is_paired_vessel(part: TorsoVessel) raises -> Bool:
    """Return True if `part` is one of a pair.

    Args:
        part: A named vessel.

    Returns:
        False for the aorta, the vena cava and the azygos vein.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A torso vessel must be a named artery or vein")
    return part.value >= INTERNAL_THORACIC_ARTERY.value


def torso_vessel_field(
    dimensions: TorsoMuscleDimensions, part: TorsoVessel, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one torso vessel.

    Args:
        dimensions: Landmarks shared with the muscles.
        part: A named vessel.
        side: `RIGHT` or `LEFT`. An unpaired vessel ignores it.

    Returns:
        The vessel's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    if not side.is_valid():
        raise Error("A torso side must be RIGHT or LEFT")
    var placed = RIGHT
    if is_paired_vessel(part):
        placed = side
    var t = dimensions.torso.copy()
    var f = t.frame
    var sweeps = List[Sweep]()
    if part == THORACIC_AORTA:
        sweeps.append(
            tube(
                template_points(
                    f,
                    floats(
                        1.0,
                        39.0,
                        3.5,
                        0.5,
                        46.0,
                        2.0,
                        -1.0,
                        48.8,
                        0.0,
                        -2.2,
                        47.0,
                        -2.5,
                        -2.5,
                        40.0,
                        -2.8,
                        -2.0,
                        34.0,
                        -1.6,
                        -1.2,
                        29.0,
                        0.4,
                    ),
                ),
                f.cm(1.25),
                f.cm(1.1),
            )
        )
    elif part == UPPER_ABDOMINAL_AORTA:
        sweeps.append(
            tube(
                template_points(
                    f,
                    floats(
                        -1.2,
                        29.0,
                        0.4,
                        -0.9,
                        25.0,
                        1.8,
                        -0.9,
                        21.5,
                        2.6,
                        -0.9,
                        18.3,
                        2.9,
                    ),
                ),
                f.cm(1.05),
                f.cm(0.95),
            )
        )
    elif part == UPPER_VENA_CAVA:
        sweeps.append(
            tube(
                template_points(
                    f,
                    floats(
                        2.2,
                        18.3,
                        2.3,
                        2.4,
                        22.0,
                        2.6,
                        2.8,
                        27.0,
                        2.2,
                        3.0,
                        31.0,
                        1.8,
                        2.9,
                        34.5,
                        1.8,
                    ),
                ),
                f.cm(1.1),
                f.cm(1.15),
            )
        )
    elif part == AZYGOS_VEIN:
        sweeps.append(
            tube(
                template_points(
                    f,
                    floats(
                        1.6,
                        24.0,
                        0.2,
                        1.8,
                        30.0,
                        -1.5,
                        1.9,
                        38.0,
                        -3.3,
                        1.6,
                        44.0,
                        -3.4,
                        1.8,
                        46.5,
                        0.5,
                    ),
                ),
                f.cm(0.4),
                f.cm(0.5),
            )
        )
    elif part == INTERNAL_THORACIC_ARTERY:
        sweeps.append(
            tube(
                template_points(
                    f,
                    floats(
                        3.0,
                        49.0,
                        2.8,
                        3.2,
                        44.0,
                        4.4,
                        3.2,
                        39.0,
                        6.2,
                        3.2,
                        34.5,
                        7.7,
                        4.2,
                        30.0,
                        8.2,
                    ),
                ),
                f.cm(0.16),
                f.cm(0.13),
            )
        )
    elif part == EPIGASTRIC_ARTERY:
        # The superior epigastric meets the inferior one in the rectus
        # sheath; the inferior rises from the external iliac.
        sweeps.append(
            tube(
                template_points(
                    f,
                    floats(
                        4.4,
                        29.0,
                        8.4,
                        4.3,
                        22.0,
                        7.7,
                        4.2,
                        15.0,
                        7.0,
                        4.8,
                        9.0,
                        6.2,
                        5.6,
                        4.5,
                        4.9,
                    ),
                ),
                f.cm(0.12),
                f.cm(0.14),
            )
        )
    else:
        # Under each rib from the third to the eleventh: the vein above,
        # the artery below it.
        var below = f.cm(0.6)
        var r = f.cm(0.10)
        if part == INTERCOSTAL_VEINS:
            below = f.cm(0.45)
            r = f.cm(0.12)
        for rib in range(2, 11):
            var path = rib_path(t, rib)
            var run = List[Vector3]()
            for k in range(8):
                var at = along_path(path, 0.08 + 0.09 * Float32(k))
                run.append(at - Vector3(0, below, 0))
            sweeps.append(tube(run, r, r))
    return SweepField(
        sweeps^, List[Dome](), placed, f.cm(0.03), f.cm(0.02), 0.004
    )


def torso_vessel_distance(
    dimensions: TorsoMuscleDimensions,
    part: TorsoVessel,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `torso_muscle_dimensions`.
        part: Which vessel to sample.
        side: `RIGHT` or `LEFT`. An unpaired vessel ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return torso_vessel_field(dimensions, part, side).distance(point)


def torso_vessel_label(part: TorsoVessel) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A torso vessel, named or not.

    Returns:
        A short American English label, or `"torso vessel"` when `part`
        is not named.
    """
    if part == THORACIC_AORTA:
        return "thoracic aorta"
    if part == UPPER_ABDOMINAL_AORTA:
        return "upper abdominal aorta"
    if part == UPPER_VENA_CAVA:
        return "inferior vena cava"
    if part == AZYGOS_VEIN:
        return "azygos vein"
    if part == INTERNAL_THORACIC_ARTERY:
        return "internal thoracic artery"
    if part == EPIGASTRIC_ARTERY:
        return "epigastric artery"
    if part == INTERCOSTAL_ARTERIES:
        return "intercostal arteries"
    if part == INTERCOSTAL_VEINS:
        return "intercostal veins"
    return "torso vessel"


def named_torso_vessels() -> List[TorsoVessel]:
    """Return every named torso vessel in a stable order.

    Returns:
        Four unpaired trunks, then four paired runs.
    """
    var parts = List[TorsoVessel]()
    for index in range(INTERCOSTAL_VEINS.value + 1):
        parts.append(TorsoVessel(index))
    return parts^
