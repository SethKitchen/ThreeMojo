# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named muscles of the neck, the jaw and the face.

The neck's set is the sternocleidomastoid, the upper fibers of the
trapezius, the splenius and the semispinalis capitis, the levator
scapulae, the scalenes, the longus colli, the infrahyoid straps and
the suprahyoid floor of the mouth. The jaw's is the masseter and the
temporalis. The face's is the frontalis, the orbicularis oculi, the
zygomaticus major and the orbicularis oris. The suprahyoid floor and
the orbicularis oris lie across the midline; the rest are paired.

A muscle is one or more sweeps of elliptical stations authored in the
torso's frame, on the right; the left is its mirror image. The upper
trapezius meets the torso's trapezius at the base of the neck, and the
levator scapulae reaches the scapula's superior angle. Belly radii
scale with athleticism; tendon radii do not. Radii are authored in
centimeters on the six-foot male template. They are template
parameters. They are not a cited cross-section table.

    var dims = head_muscle_dimensions(person)
    var d = head_muscle_distance(dims, MASSETER, RIGHT, p)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.head.frame import (
    HeadDimensions,
    HeadMuscleDimensions,
)
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
    floats,
)
from math.vector3 import Vector3
from std.math import cos, pi, sin

# Floats per station: x, y, z, ml, ap, and whether it grows with
# athleticism.
comptime HEAD_STATION = 6


@fieldwise_init
struct HeadMuscle(Equatable, ImplicitlyCopyable, Writable):
    """Which muscle of the neck, the jaw or the face a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named muscles is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named muscle."""
        if self.value < 0:
            return False
        return self.value <= ORBICULARIS_ORIS.value


comptime STERNOCLEIDOMASTOID = HeadMuscle(0)
comptime UPPER_TRAPEZIUS = HeadMuscle(1)
comptime SPLENIUS_CAPITIS = HeadMuscle(2)
comptime SEMISPINALIS_CAPITIS = HeadMuscle(3)
comptime LEVATOR_SCAPULAE = HeadMuscle(4)
comptime SCALENES = HeadMuscle(5)
comptime LONGUS_COLLI = HeadMuscle(6)
comptime INFRAHYOID = HeadMuscle(7)
# Across the midline.
comptime SUPRAHYOID = HeadMuscle(8)
comptime MASSETER = HeadMuscle(9)
comptime TEMPORALIS = HeadMuscle(10)
comptime FRONTALIS = HeadMuscle(11)
comptime ORBICULARIS_OCULI = HeadMuscle(12)
comptime ZYGOMATICUS_MAJOR = HeadMuscle(13)
# Across the midline.
comptime ORBICULARIS_ORIS = HeadMuscle(14)


def head_muscle_label(part: HeadMuscle) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A head muscle, named or not.

    Returns:
        A short American English label, or `"head muscle"` when `part`
        is not named.
    """
    var labels: List[String] = [
        "sternocleidomastoid",
        "upper trapezius",
        "splenius capitis",
        "semispinalis capitis",
        "levator scapulae",
        "scalenes",
        "longus colli",
        "infrahyoid muscles",
        "suprahyoid muscles",
        "masseter",
        "temporalis",
        "frontalis",
        "orbicularis oculi",
        "zygomaticus major",
        "orbicularis oris",
    ]
    if not part.is_valid():
        return "head muscle"
    return labels[part.value]


def named_head_muscles() -> List[HeadMuscle]:
    """Return every named head muscle in a stable order.

    Returns:
        The neck's muscles, then the jaw's, then the face's.
    """
    var parts = List[HeadMuscle]()
    for index in range(ORBICULARIS_ORIS.value + 1):  # pragma: no branch
        parts.append(HeadMuscle(index))
    return parts^


def is_paired_head_muscle(part: HeadMuscle) raises -> Bool:
    """Return True if `part` is one of a pair.

    Args:
        part: A named muscle.

    Returns:
        False for the suprahyoid floor and the orbicularis oris, which
        cross the midline, and True for the rest.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A head muscle must be a named muscle")
    return not (part == SUPRAHYOID or part == ORBICULARIS_ORIS)


def head_muscle_paths(part: HeadMuscle) raises -> List[List[Float32]]:
    """Return the authored sweeps of one muscle, rings aside.

    Each path is a hint direction, three floats, then stations of
    `HEAD_STATION` floats each: the point in template centimeters, the
    radius along the hint and the radius across, and one if the station
    grows with athleticism or zero for a tendon. The orbicularis
    muscles are rings, which `head_muscle_field` builds; their paths
    are empty.

    Args:
        part: A named muscle.

    Returns:
        One list per sweep.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A head muscle must be a named muscle")
    var paths = List[List[Float32]]()
    # fmt: off
    if part == STERNOCLEIDOMASTOID:
        # The sternal head from the mastoid to the manubrium, and the
        # clavicular head beside it down to the clavicle.
        paths.append(floats(
            1, 0, 0,
            5.4, 69.3, -1.2, 0.8, 0.6, 1,
            4.9, 65.5, 0.2, 1.2, 0.8, 1,
            3.9, 60.5, 1.9, 1.2, 0.8, 1,
            2.6, 55.0, 3.3, 0.9, 0.6, 1,
            1.9, 50.5, 3.9, 0.5, 0.4, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            4.4, 60.0, 1.3, 0.7, 0.45, 1,
            4.9, 55.0, 2.1, 0.8, 0.4, 1,
            5.3, 50.8, 2.6, 0.7, 0.3, 0,
        ))
    elif part == UPPER_TRAPEZIUS:
        # From the occiput and the nuchal ligament down and out to the
        # lateral clavicle, over the torso's upper fibers. It hugs the
        # back of the neck, and turns out to the shoulder at the neck's
        # base.
        paths.append(floats(
            0, 0, 1,
            1.2, 71.3, -9.1, 0.3, 1.0, 1,
            1.6, 66.5, -8.0, 0.4, 1.2, 1,
            2.3, 61.0, -7.3, 0.5, 1.4, 1,
            4.8, 56.2, -6.6, 0.5, 1.7, 1,
            10.0, 53.2, -4.2, 0.45, 1.6, 1,
            14.2, 51.3, -0.9, 0.35, 0.8, 0,
        ))
    elif part == SPLENIUS_CAPITIS:
        paths.append(floats(
            0, 0, 1,
            0.6, 53.5, -8.2, 0.35, 0.7, 1,
            1.4, 58.0, -6.6, 0.45, 1.1, 1,
            2.8, 63.5, -5.6, 0.5, 1.3, 1,
            4.6, 68.0, -4.2, 0.45, 1.1, 1,
            5.2, 69.8, -3.0, 0.3, 0.6, 0,
        ))
    elif part == SEMISPINALIS_CAPITIS:
        paths.append(floats(
            0, 0, 1,
            1.3, 52.5, -6.6, 0.5, 0.6, 1,
            1.4, 58.0, -5.4, 0.6, 0.8, 1,
            1.5, 64.0, -5.0, 0.7, 0.9, 1,
            1.8, 69.0, -6.6, 0.55, 0.9, 1,
            2.0, 71.3, -8.2, 0.35, 0.7, 0,
        ))
    elif part == LEVATOR_SCAPULAE:
        # From the upper cervical transverse processes to the scapula's
        # superior angle.
        paths.append(floats(
            1, 0, 0,
            3.7, 65.3, -2.7, 0.45, 0.45, 0,
            4.2, 61.5, -3.6, 0.7, 0.6, 1,
            4.8, 57.0, -4.8, 0.8, 0.6, 1,
            6.5, 52.5, -7.6, 0.5, 0.4, 1,
            7.8, 50.2, -9.6, 0.35, 0.3, 0,
        ))
    elif part == SCALENES:
        # The anterior and middle scalenes, from the transverse
        # processes to the first rib.
        paths.append(floats(
            1, 0, 0,
            3.1, 61.0, -1.9, 0.45, 0.4, 0,
            3.6, 58.0, -1.6, 0.7, 0.6, 1,
            4.3, 54.0, -1.1, 0.8, 0.65, 1,
            4.9, 50.4, -0.7, 0.55, 0.45, 0,
        ))
    elif part == LONGUS_COLLI:
        # Down the fronts of the vertebral bodies.
        paths.append(floats(
            1, 0, 0,
            0.6, 65.8, -0.5, 0.35, 0.3, 0,
            0.8, 62.0, -0.9, 0.45, 0.35, 1,
            0.9, 58.0, -1.1, 0.5, 0.35, 1,
            0.9, 54.0, -1.9, 0.45, 0.3, 1,
            0.8, 50.5, -2.6, 0.3, 0.25, 0,
        ))
    elif part == INFRAHYOID:
        # The straps from the hyoid over the larynx to the manubrium.
        paths.append(floats(
            1, 0, 0,
            0.8, 59.1, 3.5, 0.5, 0.25, 0,
            1.0, 57.6, 3.5, 0.7, 0.25, 1,
            1.1, 55.0, 3.3, 0.75, 0.25, 1,
            1.2, 52.0, 3.2, 0.7, 0.25, 1,
            1.3, 49.4, 3.0, 0.5, 0.2, 0,
        ))
    elif part == SUPRAHYOID:
        # The floor of the mouth, from the chin back to the hyoid.
        paths.append(floats(
            1, 0, 0,
            0.0, 61.2, 6.6, 1.2, 0.35, 1,
            0.0, 60.2, 4.6, 2.6, 0.35, 1,
            0.0, 59.5, 2.6, 2.2, 0.3, 1,
        ))
    elif part == MASSETER:
        # From the zygomatic arch down the ramus to the angle.
        paths.append(floats(
            0, 0, 1,
            5.8, 70.1, 2.2, 1.0, 0.35, 0,
            5.75, 68.0, 1.6, 1.5, 0.6, 1,
            5.6, 65.5, 0.8, 1.6, 0.6, 1,
            5.3, 63.3, 0.0, 1.2, 0.4, 0,
        ))
    elif part == TEMPORALIS:
        # A fan on the side of the vault, whose tendon runs under the
        # zygomatic arch to the coronoid process.
        paths.append(floats(
            0, 0, 1,
            7.0, 78.6, -1.2, 3.8, 0.3, 1,
            7.3, 75.0, -0.2, 3.0, 0.4, 1,
            6.9, 72.2, 0.9, 1.2, 0.45, 1,
            5.6, 70.4, 1.5, 0.7, 0.4, 0,
            4.6, 69.3, 1.9, 0.45, 0.35, 0,
        ))
    elif part == FRONTALIS:
        # A thin sheet over the forehead, down to the brow.
        paths.append(floats(
            0, 0, 1,
            2.5, 80.5, 6.1, 0.2, 1.9, 1,
            2.6, 77.5, 7.8, 0.22, 2.0, 1,
            2.7, 74.9, 8.4, 0.2, 1.8, 1,
        ))
    elif part == ZYGOMATICUS_MAJOR:
        # From the cheekbone down to the corner of the mouth.
        paths.append(floats(
            1, 0, 0,
            4.9, 69.9, 5.9, 0.35, 0.3, 0,
            3.9, 67.3, 7.2, 0.45, 0.35, 1,
            2.6, 65.0, 8.1, 0.35, 0.3, 0,
        ))
    # fmt: on
    return paths^


def _ring(
    h: HeadDimensions,
    center: Vector3,
    wide: Float32,
    tall: Float32,
    back: Float32,
    r: Float32,
) -> Sweep:
    """Return a closed ring of muscle round `center`, in template cm.

    The ring is `wide` across and `tall` up and down, in radii. It
    curves `back` toward its sides, so it follows the face. `r` is the
    radius of its section.
    """
    var ring = Sweep(Vector3(0, 0, 1))
    for step in range(17):  # pragma: no branch
        var turn = Float32(2) * pi * Float32(step) / Float32(16)
        var across = cos(turn)
        ring.round(
            h.at(
                center.x + wide * across,
                center.y + tall * sin(turn),
                center.z - back * across * across,
            ),
            h.cm(r),
        )
    return ring^


def head_muscle_field(
    dimensions: HeadMuscleDimensions, part: HeadMuscle, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one head muscle.

    Args:
        dimensions: Landmarks and the radius scale.
        part: A named muscle.
        side: `RIGHT` or `LEFT`. A muscle across the midline ignores
            it.

    Returns:
        The muscle's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    var paths = head_muscle_paths(part)
    if not side.is_valid():
        raise Error("A head side must be RIGHT or LEFT")
    var h = dimensions.head.copy()
    var placed = side
    if not is_paired_head_muscle(part):
        placed = RIGHT
    var sweeps = List[Sweep]()
    for p in range(len(paths)):
        ref row = paths[p]
        var sweep = Sweep(Vector3(row[0], row[1], row[2]))
        for s in range((len(row) - 3) // HEAD_STATION):  # pragma: no branch
            var at = 3 + HEAD_STATION * s
            var grow = Float32(1)
            if row[at + 5] > 0:
                grow = dimensions.scale
            sweep.add(
                h.at(row[at], row[at + 1], row[at + 2]),
                h.cm(row[at + 3] * grow),
                h.cm(row[at + 4] * grow),
            )
        sweeps.append(sweep^)
    if part == ORBICULARIS_OCULI:
        sweeps.append(
            _ring(
                h,
                Vector3(3.2, 71.9, 7.9),
                2.0,
                1.85,
                0.9,
                0.3 * dimensions.scale,
            )
        )
    elif part == ORBICULARIS_ORIS:
        sweeps.append(
            _ring(
                h, Vector3(0, 64.8, 8.2), 2.3, 1.1, 0.9, 0.4 * dimensions.scale
            )
        )
    return SweepField(
        sweeps^, List[Dome](), placed, h.cm(0.3), h.cm(0.05), h.cm(0.5)
    )


def head_muscle_distance(
    dimensions: HeadMuscleDimensions,
    part: HeadMuscle,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        part: Which muscle to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return head_muscle_field(dimensions, part, side).distance(point)
