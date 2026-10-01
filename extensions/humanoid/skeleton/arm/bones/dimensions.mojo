# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The bones of the arm and the forearm, as implicit solids.

The set is the humerus, the radius and the ulna. Each is a smooth union
of sweeps and knobs authored in the arm's local frame; see
`extensions.humanoid.skeleton.arm.frame`. The forearm is supinated, so
the radius lies lateral of the ulna and the two run side by side.

The humerus is about 36 cm long on the six-foot template, the radius
27 cm and the ulna 29 cm, near the ratios Trotter and Gleser fit to
stature. The values are template parameters. They are not a cited
osteometric table.

    var dims = arm_dimensions(Length(6.0, FOOT), MALE)
    var d = arm_bone_distance(dims, HUMERUS, RIGHT, dims.frame.elbow)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.arm.frame import ArmDimensions, ArmFrame
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
)
from math.vector3 import Vector3

# Cortical shell, as a ratio of stature.
comptime ARM_SHELL = Float32(0.0016)


@fieldwise_init
struct ArmBone(Equatable, ImplicitlyCopyable, Writable):
    """Which bone of the arm a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named bones is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named arm bone."""
        if self.value < 0:
            return False
        return self.value <= ULNA.value


comptime HUMERUS = ArmBone(0)
comptime RADIUS = ArmBone(1)
comptime ULNA = ArmBone(2)


def arm_bone_label(part: ArmBone) -> String:
    """Return the error-text name of `part`.

    Args:
        part: An arm bone, named or not.

    Returns:
        `"humerus"`, `"radius"` or `"ulna"`, or `"arm bone"` when
        `part` is not named.
    """
    if part == HUMERUS:
        return "humerus"
    if part == RADIUS:
        return "radius"
    if part == ULNA:
        return "ulna"
    return "arm bone"


def named_arm_bones() -> List[ArmBone]:
    """Return every named arm bone in a stable order.

    Returns:
        The humerus, the radius and the ulna.
    """
    var parts = List[ArmBone]()
    for index in range(ULNA.value + 1):  # pragma: no branch
        parts.append(ArmBone(index))
    return parts^


def arm_bone_field(
    dimensions: ArmDimensions, part: ArmBone, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one arm bone.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        part: A named bone.
        side: `RIGHT` or `LEFT`.

    Returns:
        The bone's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("An arm bone must be the humerus, the radius or the ulna")
    if not side.is_valid():
        raise Error("An arm side must be RIGHT or LEFT")
    var f = dimensions.frame
    var sweeps = List[Sweep]()
    if part == HUMERUS:
        _humerus(sweeps, f)
    elif part == RADIUS:
        _radius(sweeps, f)
    else:
        _ulna(sweeps, f)
    return SweepField(sweeps^, List[Dome](), side, f.cm(0.3), f.cm(0.05), 0.004)


def arm_bone_distance(
    dimensions: ArmDimensions, part: ArmBone, side: BodySide, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        part: Which bone to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return arm_bone_field(dimensions, part, side).distance(point)


def humeral_head(dimensions: ArmDimensions) -> Vector3:
    """Return the center of the right humeral head, in meters.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.

    Returns:
        The shoulder joint's center.
    """
    return dimensions.frame.shoulder


def _knob(f: ArmFrame, p: Vector3, r: Float32) -> Sweep:
    """Return a round knob of radius `r` template cm at `p`."""
    var knob = Sweep(Vector3(1, 0, 0))
    knob.round(p, f.cm(r))
    return knob^


def _rod(f: ArmFrame, points: List[Vector3], radii: List[Float32]) -> Sweep:
    """Return a round sweep through `points` with template-cm radii."""
    var rod = Sweep(Vector3(1, 0, 0))
    for index in range(len(points)):  # pragma: no branch
        rod.round(points[index], f.cm(radii[index]))
    return rod^


def _humerus(mut sweeps: List[Sweep], f: ArmFrame):
    """Append the humerus: its head and tubercles, its shaft and its
    flared lower end with the condyles."""
    # The head is the shoulder's ball; the greater tubercle stands out
    # laterally and the lesser tubercle in front.
    sweeps.append(_knob(f, f.upper(0, 0, 0), 2.3))
    var greater = List[Vector3]()
    greater.append(f.upper(1.6, 0.8, 0.2))
    greater.append(f.upper(2.0, -1.6, 0.3))
    sweeps.append(_rod(f, greater, _pair(1.2, 1.0)))
    sweeps.append(_knob(f, f.upper(0.5, -0.8, 1.6), 0.75))
    var shaft = List[Vector3]()
    shaft.append(f.upper(0.5, -1.5, 0.0))
    shaft.append(f.upper(0.9, -4.0, 0.1))
    shaft.append(f.upper(1.0, -10.0, 0.15))
    shaft.append(f.upper(0.9, -18.0, 0.1))
    shaft.append(f.upper(0.7, -24.0, 0.0))
    var radii = List[Float32]()
    radii.append(1.9)
    radii.append(1.45)
    radii.append(1.2)
    radii.append(1.1)
    radii.append(1.05)
    sweeps.append(_rod(f, shaft, radii))
    # The deltoid tuberosity, a low ridge on the lateral shaft.
    var deltoid = List[Vector3]()
    deltoid.append(f.upper(1.7, -11.0, 0.4))
    deltoid.append(f.upper(1.6, -15.0, 0.35))
    sweeps.append(_rod(f, deltoid, _pair(0.5, 0.45)))
    # The lower end flattens front to back and widens side to side.
    var flare = Sweep(Vector3(0, 0, 1))
    flare.add(f.upper(0.7, -24.0, 0.0), f.cm(0.95), f.cm(1.1))
    flare.add(f.upper(0.5, -28.5, -0.1), f.cm(0.8), f.cm(2.0))
    flare.add(f.upper(0.4, -31.3, 0.0), f.cm(0.85), f.cm(2.9))
    sweeps.append(flare^)
    sweeps.append(_knob(f, f.upper(-2.9, -31.5, -0.2), 0.85))
    sweeps.append(_knob(f, f.upper(3.3, -31.8, 0.0), 0.6))
    # The trochlea, a spool on the medial side; the capitulum, a ball in
    # front of the lateral side.
    var trochlea = Sweep(Vector3(0, 1, 0))
    trochlea.round(f.upper(-1.7, -32.8, 0.3), f.cm(1.15))
    trochlea.round(f.upper(-0.5, -33.0, 0.35), f.cm(0.95))
    trochlea.round(f.upper(0.4, -32.9, 0.4), f.cm(1.1))
    sweeps.append(trochlea^)
    sweeps.append(_knob(f, f.upper(1.6, -32.9, 0.9), 1.0))


def _radius(mut sweeps: List[Sweep], f: ArmFrame):
    """Append the radius: its head under the capitulum, its bowed shaft
    and its wide lower end with the styloid."""
    sweeps.append(_knob(f, f.fore(1.7, -2.2, 0.5), 1.1))
    sweeps.append(_knob(f, f.fore(1.2, -4.4, 0.9), 0.6))
    var shaft = List[Vector3]()
    shaft.append(f.fore(1.7, -3.3, 0.45))
    shaft.append(f.fore(2.1, -10.0, 0.35))
    shaft.append(f.fore(2.3, -17.5, 0.3))
    shaft.append(f.fore(2.1, -23.3, 0.35))
    var radii = List[Float32]()
    radii.append(0.65)
    radii.append(0.7)
    radii.append(0.78)
    radii.append(0.9)
    sweeps.append(_rod(f, shaft, radii))
    var lower = Sweep(Vector3(0, 0, 1))
    lower.add(f.fore(2.1, -23.3, 0.35), f.cm(0.9), f.cm(1.0))
    lower.add(f.fore(1.6, -26.8, 0.45), f.cm(1.0), f.cm(1.95))
    sweeps.append(lower^)
    var styloid = List[Vector3]()
    styloid.append(f.fore(2.9, -26.9, 0.3))
    styloid.append(f.fore(3.2, -28.1, 0.2))
    sweeps.append(_rod(f, styloid, _pair(0.45, 0.3)))


def _ulna(mut sweeps: List[Sweep], f: ArmFrame):
    """Append the ulna: the olecranon and the coronoid around the
    trochlea, the tapering shaft, the head and the styloid."""
    var olecranon = List[Vector3]()
    olecranon.append(f.fore(-0.3, 0.4, -1.7))
    olecranon.append(f.fore(-0.6, -0.3, -1.5))
    olecranon.append(f.fore(-0.8, -2.0, -0.9))
    var radii = List[Float32]()
    radii.append(0.8)
    radii.append(1.05)
    radii.append(1.0)
    sweeps.append(_rod(f, olecranon, radii))
    var coronoid = List[Vector3]()
    coronoid.append(f.fore(-0.8, -1.4, -0.6))
    coronoid.append(f.fore(-0.6, -1.2, 0.8))
    sweeps.append(_rod(f, coronoid, _pair(0.7, 0.55)))
    var shaft = List[Vector3]()
    shaft.append(f.fore(-0.8, -2.0, -0.9))
    shaft.append(f.fore(-1.0, -7.0, -0.5))
    shaft.append(f.fore(-1.2, -15.0, -0.2))
    shaft.append(f.fore(-1.3, -23.0, -0.1))
    shaft.append(f.fore(-1.35, -25.8, -0.1))
    var shaft_radii = List[Float32]()
    shaft_radii.append(1.0)
    shaft_radii.append(0.75)
    shaft_radii.append(0.62)
    shaft_radii.append(0.55)
    shaft_radii.append(0.62)
    sweeps.append(_rod(f, shaft, shaft_radii))
    sweeps.append(_knob(f, f.fore(-1.4, -26.3, -0.1), 0.85))
    var styloid = List[Vector3]()
    styloid.append(f.fore(-1.8, -26.5, -0.6))
    styloid.append(f.fore(-2.0, -27.2, -0.7))
    sweeps.append(_rod(f, styloid, _pair(0.35, 0.22)))


def _pair(a: Float32, b: Float32) -> List[Float32]:
    """Return a two-value list."""
    var out = List[Float32]()
    out.append(a)
    out.append(b)
    return out^
