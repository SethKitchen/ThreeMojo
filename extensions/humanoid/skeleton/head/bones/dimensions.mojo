# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The bones of the neck and the head, as implicit solids.

The set is the seven cervical vertebrae, the skull, the mandible, the
teeth and the hyoid. Every one lies on the midline, so none takes a
side.

The atlas is a ring with two lateral masses and wide transverse
processes. The axis carries the dens up through the atlas's front
arch. C3 to C6 have short forked spines; C7's spine is long, the
vertebra prominens. The skull's vault is a thin dome of bone. Its base,
its brow, the rims of the orbits, the nasal bones, the maxilla, the
cheekbones and their arches, the mastoids and the occipital condyles
are sweeps and knobs. The mandible is a U of bone with a ramus and a
condyle each side. The condyles sit in front of the ear canals, and
the occipital condyles sit on the atlas. The values are template
parameters. They are not a cited osteometric table.

    var dims = head_dimensions(Length(6.0, FOOT), MALE)
    var d = head_bone_distance(dims, SKULL, dims.at(0, 84.0, -1.0))
"""

from extensions.humanoid.side import RIGHT
from extensions.humanoid.skeleton.head.frame import HeadDimensions
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
    floats,
    tube,
)
from math.vector3 import Vector3

# Cortical shell, as a ratio of stature.
comptime HEAD_SHELL = Float32(0.0016)


@fieldwise_init
struct HeadBone(Equatable, ImplicitlyCopyable, Writable):
    """Which bone of the neck or the head a caller asks for.

    `C1` through `C7` are the cervical vertebrae, then the skull, the
    mandible, the teeth and the hyoid. The type stops a bare integer at
    compile time. A value that is not one of the named bones is still
    constructible, and the boundary that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named head bone."""
        if self.value < 0:
            return False
        return self.value <= HYOID.value


comptime C1 = HeadBone(0)
comptime C2 = HeadBone(1)
comptime C3 = HeadBone(2)
comptime C4 = HeadBone(3)
comptime C5 = HeadBone(4)
comptime C6 = HeadBone(5)
comptime C7 = HeadBone(6)
comptime SKULL = HeadBone(7)
comptime MANDIBLE = HeadBone(8)
comptime TEETH = HeadBone(9)
comptime HYOID = HeadBone(10)


def head_bone_label(part: HeadBone) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A head bone, named or not.

    Returns:
        `"atlas"`, `"axis"`, `"C3"` through `"C7"`, `"skull"`,
        `"mandible"`, `"teeth"` or `"hyoid"`, or `"head bone"` when
        `part` is not named.
    """
    if part == C1:
        return "atlas"
    if part == C2:
        return "axis"
    if part.value >= C3.value and part.value <= C7.value:
        return "C" + String(part.value + 1)
    if part == SKULL:
        return "skull"
    if part == MANDIBLE:
        return "mandible"
    if part == TEETH:
        return "teeth"
    if part == HYOID:
        return "hyoid"
    return "head bone"


def named_head_bones() -> List[HeadBone]:
    """Return every named head bone in a stable order.

    Returns:
        C1 to C7, the skull, the mandible, the teeth and the hyoid.
    """
    var parts = List[HeadBone]()
    for index in range(HYOID.value + 1):  # pragma: no branch
        parts.append(HeadBone(index))
    return parts^


def head_bone_field(
    dimensions: HeadDimensions, part: HeadBone
) raises -> SweepField:
    """Return the implicit solid of one head bone.

    Args:
        dimensions: Landmarks from `head_dimensions`.
        part: A named bone.

    Returns:
        The bone's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or if `part`
            is not named.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error(
            "A head bone must be a named cervical vertebra, the skull, the"
            " mandible, the teeth or the hyoid"
        )
    var sweeps = List[Sweep]()
    var domes = List[Dome]()
    var cuts = List[Sweep]()
    if part == C1:
        _atlas(sweeps, dimensions)
    elif part == C2:
        _axis(sweeps, dimensions)
    elif part.value <= C7.value:
        _cervical(sweeps, dimensions, part.value)
    elif part == SKULL:
        _skull(sweeps, domes, cuts, dimensions)
    elif part == MANDIBLE:
        _mandible(sweeps, dimensions)
    elif part == TEETH:
        _teeth(sweeps, dimensions)
    else:
        _hyoid(sweeps, dimensions)
    var field = SweepField(
        sweeps^,
        domes^,
        RIGHT,
        dimensions.cm(0.3),
        dimensions.cm(0.05),
        dimensions.cm(0.4),
    )
    for index in range(len(cuts)):
        field.cut(cuts[index].copy())
    return field^


def head_bone_distance(
    dimensions: HeadDimensions, part: HeadBone, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `head_dimensions`.
        part: Which bone to sample.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or if `part`
            is not named.
    """
    return head_bone_field(dimensions, part).distance(point)


def _knob(h: HeadDimensions, p: Vector3, r: Float32) -> Sweep:
    """Return a round knob of radius `r` template cm at `p`."""
    var knob = Sweep(Vector3(1, 0, 0))
    knob.round(p, h.cm(r))
    return knob^


def _plate(
    h: HeadDimensions,
    hint: Vector3,
    points: List[Vector3],
    ml: Float32,
    ap: Float32,
) -> Sweep:
    """Return a sweep of one elliptical section through `points`.

    `ml` runs along `hint` and `ap` across, both in template cm.
    """
    var plate = Sweep(hint)
    for index in range(len(points)):  # pragma: no branch
        plate.add(points[index], h.cm(ml), h.cm(ap))
    return plate^


def _arc(h: HeadDimensions, coords: List[Float32]) -> List[Vector3]:
    """Return template points `(x, y, z)` from right to left.

    `coords` holds the right half, from the far right in to the
    midline, as flat triples. The left half is its mirror, so the arc
    runs across the body without doubling the midline point.
    """
    var count = len(coords) // 3
    var points = List[Vector3]()
    for index in range(count):  # pragma: no branch
        points.append(
            h.at(
                coords[index * 3], coords[index * 3 + 1], coords[index * 3 + 2]
            )
        )
    # The midline point is last in `coords`; mirror the rest back out.
    for index in range(count - 2, -1, -1):  # pragma: no branch
        points.append(
            h.at(
                -coords[index * 3],
                coords[index * 3 + 1],
                coords[index * 3 + 2],
            )
        )
    return points^


def _atlas(mut sweeps: List[Sweep], h: HeadDimensions):
    """Append the atlas: its front arch, its lateral masses, its back
    arch and its wide transverse processes."""
    var c = h.centers[0]
    var y = c.y
    var front = List[Vector3]()
    front.append(Vector3(h.cm(1.4), y, c.z + h.cm(1.3)))
    front.append(Vector3(0, y, c.z + h.cm(1.8)))
    front.append(Vector3(-h.cm(1.4), y, c.z + h.cm(1.3)))
    sweeps.append(tube(front, h.cm(0.35), h.cm(0.35)))
    sweeps.append(_knob(h, Vector3(0, y, c.z + h.cm(2.0)), 0.3))
    var back = List[Vector3]()
    back.append(Vector3(h.cm(1.7), y, c.z - h.cm(0.8)))
    back.append(Vector3(h.cm(1.3), y, c.z - h.cm(2.2)))
    back.append(Vector3(0, y + h.cm(0.1), c.z - h.cm(2.8)))
    back.append(Vector3(-h.cm(1.3), y, c.z - h.cm(2.2)))
    back.append(Vector3(-h.cm(1.7), y, c.z - h.cm(0.8)))
    sweeps.append(tube(back, h.cm(0.3), h.cm(0.3)))
    sweeps.append(_knob(h, Vector3(0, y, c.z - h.cm(2.9)), 0.4))
    for s in range(2):  # pragma: no branch
        var sign = Float32(1) - Float32(2 * s)
        var mass = Sweep(Vector3(1, 0, 0))
        mass.add(
            Vector3(sign * h.cm(1.6), y - h.cm(0.5), c.z + h.cm(0.3)),
            h.cm(0.6),
            h.cm(0.75),
        )
        mass.add(
            Vector3(sign * h.cm(1.6), y + h.cm(0.5), c.z + h.cm(0.3)),
            h.cm(0.65),
            h.cm(0.8),
        )
        sweeps.append(mass^)
        var process = List[Vector3]()
        process.append(Vector3(sign * h.cm(2.1), y, c.z + h.cm(0.1)))
        process.append(
            Vector3(sign * h.cm(3.6), y - h.cm(0.1), c.z - h.cm(0.1))
        )
        sweeps.append(tube(process, h.cm(0.35), h.cm(0.3)))
        sweeps.append(
            _knob(
                h,
                Vector3(sign * h.cm(3.7), y - h.cm(0.1), c.z - h.cm(0.1)),
                0.45,
            )
        )


def _axis(mut sweeps: List[Sweep], h: HeadDimensions):
    """Append the axis: its tall body, the dens that rises through the
    atlas, its upper facets and its large forked spine."""
    _cervical(sweeps, h, 1)
    var c = h.centers[1]
    var dens = List[Vector3]()
    dens.append(Vector3(0, c.y + 0.4 * h.heights[1], c.z + h.cm(0.1)))
    dens.append(h.at(0, 66.6, -1.8))
    sweeps.append(tube(dens, h.cm(0.5), h.cm(0.4)))
    for s in range(2):  # pragma: no branch
        var sign = Float32(1) - Float32(2 * s)
        sweeps.append(
            _knob(h, Vector3(sign * h.cm(1.5), c.y + h.cm(1.1), c.z), 0.55)
        )


def _cervical(mut sweeps: List[Sweep], h: HeadDimensions, index: Int):
    """Append a lower cervical vertebra: its body, the arch round a
    wide canal, the articular pillars, short transverse processes and
    the spine. C3 to C6 fork at the tip; C7's spine is long."""
    var c = h.centers[index]
    var w = h.widths[index]
    var d = h.depths[index]
    var tall = h.heights[index]
    var body = Sweep(Vector3(1, 0, 0))
    body.add(c - Vector3(0, 0.5 * tall, 0), w, d)
    body.add(c + Vector3(0, 0.5 * tall, 0), w, d)
    sweeps.append(body^)
    var root = c.z - d
    var joint = Vector3(0, c.y - h.cm(0.2), root - h.cm(1.7))
    # How far each spine drops and reaches back, C2 to C7.
    var drops = floats(0.5, 0.5, 0.6, 0.7, 0.8, 1.2)
    var reach = floats(1.6, 1.3, 1.4, 1.5, 1.8, 2.9)
    var tip = Vector3(
        0, c.y - h.cm(drops[index - 1]), joint.z - h.cm(reach[index - 1])
    )
    var spine = Sweep(Vector3(1, 0, 0))
    spine.add(joint, h.cm(0.3), h.cm(0.45))
    spine.add(tip, h.cm(0.3), h.cm(0.35))
    sweeps.append(spine^)
    if index < 6:
        # The fork: a small knob each side of the tip.
        for s in range(2):  # pragma: no branch
            var sign = Float32(1) - Float32(2 * s)
            sweeps.append(
                _knob(h, Vector3(sign * h.cm(0.35), tip.y, tip.z), 0.32)
            )
    else:
        sweeps.append(_knob(h, tip, 0.45))
    for s in range(2):  # pragma: no branch
        var sign = Float32(1) - Float32(2 * s)
        var arch = List[Vector3]()
        arch.append(Vector3(sign * 0.6 * w, c.y, root + 0.3 * d))
        arch.append(
            Vector3(sign * (0.55 * w + h.cm(0.4)), c.y, root - h.cm(0.4))
        )
        arch.append(
            Vector3(sign * h.cm(1.3), c.y - h.cm(0.1), root - h.cm(1.1))
        )
        arch.append(joint)
        sweeps.append(tube(arch, h.cm(0.3), h.cm(0.28)))
        var pillar = Sweep(Vector3(1, 0, 0))
        pillar.round(
            Vector3(sign * h.cm(1.55), c.y - 0.5 * tall, root - h.cm(0.6)),
            h.cm(0.45),
        )
        pillar.round(
            Vector3(sign * h.cm(1.55), c.y + 0.5 * tall, root - h.cm(0.6)),
            h.cm(0.45),
        )
        sweeps.append(pillar^)
        var reach_out = h.cm(1.5)
        if index == 6:
            reach_out = h.cm(1.9)
        var process = List[Vector3]()
        process.append(Vector3(sign * 0.9 * w, c.y, c.z - 0.2 * d))
        process.append(
            Vector3(sign * (w + reach_out), c.y + h.cm(0.05), c.z - h.cm(0.3))
        )
        sweeps.append(tube(process, h.cm(0.3), h.cm(0.32)))


def _skull(
    mut sweeps: List[Sweep],
    mut domes: List[Dome],
    mut cuts: List[Sweep],
    h: HeadDimensions,
):
    """Append the skull: the vault's dome and its base, the face with
    its orbits and its nasal opening cut out, the brow, the nasal bones,
    the alveolar arch, the cheekbones' arches, the ear canals, the
    mastoids, the occipital protuberance and condyles, and the
    clivus."""
    # The vault: a shell of bone about seven millimeters thick, open
    # below the cranial floor, which a slab closes.
    var center = h.at(0, 75.4, -1.0)
    domes.append(
        Dome(
            center,
            h.cranium(7.1, 8.5, 9.4),
            h.cm(0.35),
            h.at(0, 70.6, 0).y,
        )
    )
    var floor = Sweep(Vector3(1, 0, 0))
    floor.add(h.at(0, 70.9, -6.5), h.cm(3.4), h.cm(0.9))
    floor.add(h.at(0, 70.9, -2.0), h.cm(5.2), h.cm(0.9))
    floor.add(h.at(0, 70.9, 3.0), h.cm(5.0), h.cm(0.9))
    floor.add(h.at(0, 70.9, 5.5), h.cm(3.8), h.cm(0.9))
    sweeps.append(floor^)
    # The face: the frontal's lower edge, the cheekbones and the maxilla
    # as one block, widest across the cheekbones.
    var face = Sweep(Vector3(1, 0, 0))
    face.add(h.at(0, 73.6, 6.2), h.cm(5.8), h.cm(2.4))
    face.add(h.at(0, 70.6, 5.4), h.cm(6.3), h.cm(2.7))
    face.add(h.at(0, 68.2, 5.6), h.cm(4.2), h.cm(2.4))
    face.add(h.at(0, 66.3, 5.2), h.cm(3.1), h.cm(2.0))
    sweeps.append(face^)
    sweeps.append(
        _plate(
            h,
            Vector3(0, 1, 0),
            _arc(h, floats(4.6, 73.9, 6.4, 2.2, 74.1, 8.0, 0.0, 73.7, 8.4)),
            0.5,
            0.5,
        )
    )
    for s in range(2):  # pragma: no branch
        var x = Float32(1) - Float32(2 * s)
        # The orbit, cut shallow enough to leave the vault whole.
        var orbit = Sweep(Vector3(1, 0, 0))
        orbit.add(h.at(x * 3.2, 71.9, 8.4), h.cm(1.8), h.cm(1.6))
        cuts.append(orbit^)
        # The arch back from the cheekbone to the ear.
        var arch = List[Vector3]()
        arch.append(h.at(x * 5.6, 70.2, 3.8))
        arch.append(h.at(x * 6.2, 70.4, 1.2))
        arch.append(h.at(x * 6.1, 70.8, -0.6))
        sweeps.append(_plate(h, Vector3(0, 1, 0), arch, 0.55, 0.3))
        # The ear canal's rim, the mastoid and the occipital condyle.
        sweeps.append(_knob(h, h.at(x * 6.1, 71.2, -0.9), 0.6))
        sweeps.append(_knob(h, h.at(x * 5.4, 69.2, -2.0), 1.0))
        sweeps.append(_knob(h, h.at(x * 1.3, 66.9, -2.2), 0.6))
        # The lower occipital bone, down to the condyle.
        var occiput = List[Vector3]()
        occiput.append(h.at(x * 3.5, 70.9, -7.0))
        occiput.append(h.at(x * 2.0, 68.3, -4.0))
        occiput.append(h.at(x * 1.3, 67.2, -2.5))
        sweeps.append(tube(occiput, h.cm(0.6), h.cm(0.45)))
    # The pear-shaped nasal opening, and the nasal bones above it.
    var aperture = Sweep(Vector3(1, 0, 0))
    aperture.add(h.at(0, 70.0, 8.3), h.cm(0.6), h.cm(1.2))
    aperture.add(h.at(0, 68.2, 8.3), h.cm(1.1), h.cm(1.2))
    cuts.append(aperture^)
    var nose = List[Vector3]()
    nose.append(h.at(0, 72.6, 8.4))
    nose.append(h.at(0, 70.4, 9.2))
    sweeps.append(_plate(h, Vector3(1, 0, 0), nose, 0.6, 0.3))
    # The alveolar arch that holds the upper teeth.
    sweeps.append(
        _plate(
            h,
            Vector3(0, 1, 0),
            _arc(
                h,
                floats(
                    2.9,
                    66.3,
                    1.5,
                    2.8,
                    66.3,
                    3.6,
                    2.2,
                    66.3,
                    5.6,
                    1.0,
                    66.3,
                    6.9,
                    0.0,
                    66.3,
                    7.2,
                ),
            ),
            0.9,
            0.8,
        )
    )
    # The occipital protuberance and the clivus above the dens.
    sweeps.append(_knob(h, h.at(0, 72.3, -9.9), 0.6))
    var clivus = List[Vector3]()
    clivus.append(h.at(0, 70.6, -0.3))
    clivus.append(h.at(0, 67.8, -1.0))
    sweeps.append(_plate(h, Vector3(1, 0, 0), clivus, 1.0, 0.6))


def _mandible(mut sweeps: List[Sweep], h: HeadDimensions):
    """Append the mandible: its U-shaped body, and on each side a ramus
    with its condyle and its coronoid process."""
    sweeps.append(
        _plate(
            h,
            Vector3(0, 1, 0),
            _arc(
                h,
                floats(
                    4.7,
                    63.6,
                    -0.4,
                    4.3,
                    62.9,
                    2.2,
                    3.2,
                    62.3,
                    5.0,
                    1.6,
                    61.9,
                    7.0,
                    0.0,
                    61.9,
                    7.7,
                ),
            ),
            1.5,
            0.55,
        )
    )
    sweeps.append(_knob(h, h.at(0, 61.1, 7.9), 0.6))
    for s in range(2):  # pragma: no branch
        var x = Float32(1) - Float32(2 * s)
        var ramus = Sweep(Vector3(0, 0, 1))
        ramus.add(h.at(x * 4.7, 63.6, -0.4), h.cm(1.5), h.cm(0.45))
        ramus.add(h.at(x * 4.9, 66.6, -0.3), h.cm(1.4), h.cm(0.42))
        ramus.add(h.at(x * 5.0, 69.8, 0.1), h.cm(0.9), h.cm(0.4))
        sweeps.append(ramus^)
        var condyle = Sweep(Vector3(1, 0, 0))
        condyle.add(h.at(x * 5.0, 70.9, 0.3), h.cm(0.9), h.cm(0.5))
        sweeps.append(condyle^)
        var coronoid = List[Vector3]()
        coronoid.append(h.at(x * 4.8, 66.8, 0.9))
        coronoid.append(h.at(x * 4.5, 69.3, 1.9))
        sweeps.append(tube(coronoid, h.cm(0.45), h.cm(0.3)))


def _teeth(mut sweeps: List[Sweep], h: HeadDimensions):
    """Append the two rows of teeth. The upper incisors close in front
    of the lower ones."""
    sweeps.append(
        _plate(
            h,
            Vector3(0, 1, 0),
            _arc(
                h,
                floats(
                    2.6,
                    65.5,
                    2.0,
                    2.5,
                    65.4,
                    3.8,
                    2.0,
                    65.3,
                    5.4,
                    1.2,
                    65.2,
                    6.5,
                    0.0,
                    65.1,
                    7.0,
                ),
            ),
            0.45,
            0.42,
        )
    )
    sweeps.append(
        _plate(
            h,
            Vector3(0, 1, 0),
            _arc(
                h,
                floats(
                    2.5,
                    64.4,
                    2.2,
                    2.3,
                    64.3,
                    4.0,
                    1.8,
                    64.3,
                    5.4,
                    1.0,
                    64.2,
                    6.3,
                    0.0,
                    64.2,
                    6.6,
                ),
            ),
            0.45,
            0.4,
        )
    )


def _hyoid(mut sweeps: List[Sweep], h: HeadDimensions):
    """Append the hyoid: its body in front and a greater horn back each
    side."""
    sweeps.append(
        _plate(
            h,
            Vector3(0, 1, 0),
            _arc(
                h,
                floats(
                    2.1,
                    59.8,
                    1.4,
                    1.6,
                    59.4,
                    3.2,
                    0.8,
                    59.2,
                    4.1,
                    0.0,
                    59.2,
                    4.3,
                ),
            ),
            0.35,
            0.25,
        )
    )
