# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named muscles of the shoulder, the arm and the forearm.

The set is the deltoid and the rotator cuff, the teres major and the
coracobrachialis; the biceps, the brachialis and the triceps; and the
forearm's flexors in front and extensors behind. A muscle is one or
more sweeps of elliptical stations: a head, a belly and its tendon.
Each station is authored on the scapula or the clavicle in the torso's
frame, or on the upper arm, the forearm or the hand in the arm's frame;
see `extensions.humanoid.skeleton.arm.frame`.

A forearm muscle that ends on a wrist bone or a metacarpal carries its
tendon there. The long tendons to the fingers belong to the hand; see
`extensions.humanoid.skeleton.hand.muscles`. Belly radii scale with
athleticism; tendon radii do not. Radii are authored in centimeters on
the six-foot male template. They are template parameters. They are not
a cited cross-section table.

    var dims = arm_muscle_dimensions(person)
    var d = arm_muscle_distance(dims, BICEPS_BRACHII, RIGHT, p)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.arm.frame import (
    ArmDimensions,
    ArmMuscleDimensions,
)
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
    floats,
)
from math.vector3 import Vector3

# Which frame a station is authored in.
comptime ON_TORSO = 0
comptime ON_UPPER = 1
comptime ON_FORE = 2
comptime ON_HAND = 3
# Floats per station: frame, x, y, z, ml, ap, and whether it grows with
# athleticism.
comptime STATION = 7


@fieldwise_init
struct ArmMuscle(Equatable, ImplicitlyCopyable, Writable):
    """Which named muscle of the shoulder, the arm or the forearm a
    caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named muscles is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named arm muscle."""
        if self.value < 0:
            return False
        return self.value <= EXTENSOR_INDICIS.value


comptime DELTOID = ArmMuscle(0)
comptime SUPRASPINATUS = ArmMuscle(1)
comptime INFRASPINATUS = ArmMuscle(2)
comptime TERES_MINOR = ArmMuscle(3)
comptime SUBSCAPULARIS = ArmMuscle(4)
comptime TERES_MAJOR = ArmMuscle(5)
comptime CORACOBRACHIALIS = ArmMuscle(6)
comptime BICEPS_BRACHII = ArmMuscle(7)
comptime BRACHIALIS = ArmMuscle(8)
comptime TRICEPS_BRACHII = ArmMuscle(9)
comptime PRONATOR_TERES = ArmMuscle(10)
comptime FLEXOR_CARPI_RADIALIS = ArmMuscle(11)
comptime PALMARIS_LONGUS = ArmMuscle(12)
comptime FLEXOR_CARPI_ULNARIS = ArmMuscle(13)
comptime FLEXOR_DIGITORUM_SUPERFICIALIS = ArmMuscle(14)
comptime FLEXOR_DIGITORUM_PROFUNDUS = ArmMuscle(15)
comptime FLEXOR_POLLICIS_LONGUS = ArmMuscle(16)
comptime PRONATOR_QUADRATUS = ArmMuscle(17)
comptime BRACHIORADIALIS = ArmMuscle(18)
comptime EXTENSOR_CARPI_RADIALIS_LONGUS = ArmMuscle(19)
comptime EXTENSOR_CARPI_RADIALIS_BREVIS = ArmMuscle(20)
comptime EXTENSOR_DIGITORUM = ArmMuscle(21)
comptime EXTENSOR_DIGITI_MINIMI = ArmMuscle(22)
comptime EXTENSOR_CARPI_ULNARIS = ArmMuscle(23)
comptime ANCONEUS = ArmMuscle(24)
comptime SUPINATOR = ArmMuscle(25)
comptime ABDUCTOR_POLLICIS_LONGUS = ArmMuscle(26)
comptime EXTENSOR_POLLICIS_BREVIS = ArmMuscle(27)
comptime EXTENSOR_POLLICIS_LONGUS = ArmMuscle(28)
comptime EXTENSOR_INDICIS = ArmMuscle(29)


def arm_muscle_label(part: ArmMuscle) -> String:
    """Return the error-text name of `part`.

    Args:
        part: An arm muscle, named or not.

    Returns:
        A short American English label, or `"arm muscle"` when `part`
        is not named.
    """
    if not part.is_valid():
        return "arm muscle"
    var names = List[String]()
    names.append("deltoid")
    names.append("supraspinatus")
    names.append("infraspinatus")
    names.append("teres minor")
    names.append("subscapularis")
    names.append("teres major")
    names.append("coracobrachialis")
    names.append("biceps brachii")
    names.append("brachialis")
    names.append("triceps brachii")
    names.append("pronator teres")
    names.append("flexor carpi radialis")
    names.append("palmaris longus")
    names.append("flexor carpi ulnaris")
    names.append("flexor digitorum superficialis")
    names.append("flexor digitorum profundus")
    names.append("flexor pollicis longus")
    names.append("pronator quadratus")
    names.append("brachioradialis")
    names.append("extensor carpi radialis longus")
    names.append("extensor carpi radialis brevis")
    names.append("extensor digitorum")
    names.append("extensor digiti minimi")
    names.append("extensor carpi ulnaris")
    names.append("anconeus")
    names.append("supinator")
    names.append("abductor pollicis longus")
    names.append("extensor pollicis brevis")
    names.append("extensor pollicis longus")
    names.append("extensor indicis")
    return names[part.value]


def named_arm_muscles() -> List[ArmMuscle]:
    """Return every named arm muscle in a stable order.

    Returns:
        The shoulder's muscles, the arm's, the forearm's flexors and
        then its extensors.
    """
    var parts = List[ArmMuscle]()
    for index in range(EXTENSOR_INDICIS.value + 1):
        parts.append(ArmMuscle(index))
    return parts^


def arm_muscle_paths(part: ArmMuscle) raises -> List[List[Float32]]:
    """Return the authored sweeps of one muscle.

    Each path is a hint direction, three floats, then stations of
    `STATION` floats each: the frame (`ON_TORSO`, `ON_UPPER`, `ON_FORE`
    or `ON_HAND`), the point in template centimeters, the radius along
    the hint and the radius across, and one if the station grows with
    athleticism or zero for a tendon.

    Args:
        part: A named muscle.

    Returns:
        One list per sweep.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("An arm muscle must be a named muscle")
    var paths = List[List[Float32]]()
    # fmt: off
    if part == DELTOID:
        # Anterior, middle and posterior heads, from the clavicle, the
        # acromion and the scapular spine to the deltoid tuberosity.
        paths.append(floats(
            0.3, 0, 1,
            0, 15.0, 49.6, 0.8, 0.5, 1.6, 1,
            1, 1.3, 1.0, 3.4, 1.0, 2.0, 1,
            1, 2.3, -5.0, 2.7, 1.0, 1.8, 1,
            1, 1.9, -12.5, 0.9, 0.5, 0.7, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            0, 19.9, 49.3, -1.5, 0.5, 1.4, 1,
            1, 4.3, -0.8, 0.2, 1.2, 2.0, 1,
            1, 3.6, -7.0, 0.3, 1.1, 1.7, 1,
            1, 2.3, -12.5, 0.4, 0.5, 0.7, 0,
        ))
        paths.append(floats(
            0.3, 0, -1,
            0, 13.0, 48.6, -9.8, 0.5, 1.6, 1,
            1, 1.2, 0.6, -3.6, 1.0, 2.0, 1,
            1, 2.4, -5.0, -2.6, 1.0, 1.7, 1,
            1, 1.9, -12.5, -0.2, 0.5, 0.7, 0,
        ))
    elif part == SUPRASPINATUS:
        paths.append(floats(
            0, 1, 0,
            0, 8.8, 49.8, -9.3, 0.9, 1.0, 1,
            0, 12.5, 49.6, -7.6, 1.1, 1.2, 1,
            0, 16.3, 48.4, -4.3, 0.6, 0.8, 1,
            1, 1.6, 1.9, 0.2, 0.45, 0.6, 0,
        ))
    elif part == INFRASPINATUS:
        paths.append(floats(
            -0.6, 0, 0.8,
            0, 8.4, 46.0, -10.8, 0.8, 1.6, 1,
            0, 12.0, 46.2, -7.9, 1.0, 1.8, 1,
            0, 15.4, 46.2, -5.9, 0.9, 1.3, 1,
            1, 1.5, -0.3, -2.4, 0.45, 0.7, 0,
        ))
        paths.append(floats(
            -0.6, 0, 0.8,
            0, 9.0, 41.0, -10.5, 0.8, 1.6, 1,
            0, 12.0, 43.2, -8.0, 1.0, 1.8, 1,
            0, 15.0, 45.4, -6.0, 0.9, 1.3, 1,
            1, 1.5, -0.8, -2.3, 0.45, 0.7, 0,
        ))
    elif part == TERES_MINOR:
        paths.append(floats(
            -0.6, 0, 0.8,
            0, 12.0, 41.3, -8.9, 0.8, 0.9, 1,
            0, 14.4, 43.8, -6.9, 0.9, 1.0, 1,
            1, 1.3, -1.6, -2.3, 0.45, 0.55, 0,
        ))
    elif part == SUBSCAPULARIS:
        # On the blade's front, between the scapula and the ribs, to the
        # lesser tubercle.
        paths.append(floats(
            -0.6, 0, 0.8,
            0, 8.6, 45.2, -9.0, 0.55, 1.8, 1,
            0, 12.0, 45.4, -5.9, 0.7, 1.8, 1,
            0, 15.0, 45.6, -1.8, 0.8, 1.3, 1,
            1, 0.4, -0.9, 2.0, 0.45, 0.6, 0,
        ))
        paths.append(floats(
            -0.6, 0, 0.8,
            0, 9.0, 40.2, -8.6, 0.55, 1.8, 1,
            0, 11.6, 42.6, -6.6, 0.7, 1.8, 1,
            0, 14.6, 45.0, -2.2, 0.8, 1.3, 1,
            1, 0.4, -1.4, 1.9, 0.45, 0.6, 0,
        ))
    elif part == TERES_MAJOR:
        paths.append(floats(
            1, 0, 0,
            0, 9.4, 37.8, -9.4, 1.2, 1.3, 1,
            0, 12.6, 39.6, -7.8, 1.5, 1.6, 1,
            1, -1.4, -8.6, -1.2, 1.1, 1.2, 1,
            1, -0.4, -6.8, 0.9, 0.4, 0.6, 0,
        ))
    elif part == CORACOBRACHIALIS:
        paths.append(floats(
            1, 0, 0,
            0, 15.0, 46.6, 1.4, 0.5, 0.5, 1,
            1, -1.5, -6.0, 1.6, 0.9, 0.9, 1,
            1, -1.3, -11.0, 1.2, 1.0, 1.0, 1,
            1, -0.6, -15.5, 0.9, 0.4, 0.5, 0,
        ))
    elif part == BICEPS_BRACHII:
        # The short head from the coracoid, the long head over the top of
        # the humeral head and down its groove, one belly, one tendon to
        # the radial tuberosity.
        paths.append(floats(
            1, 0, 0,
            0, 15.2, 46.5, 1.8, 0.45, 0.45, 0,
            1, -0.9, -5.0, 2.9, 0.7, 0.7, 1,
            1, 0.4, -10.0, 3.4, 1.2, 1.0, 1,
        ))
        paths.append(floats(
            1, 0, 0,
            0, 16.4, 47.9, -2.4, 0.3, 0.3, 0,
            1, 0.6, 2.5, 0.9, 0.3, 0.3, 0,
            1, 0.9, -2.8, 2.2, 0.3, 0.35, 0,
            1, 1.0, -7.0, 2.9, 0.6, 0.7, 1,
            1, 0.4, -10.0, 3.4, 1.2, 1.0, 1,
        ))
        paths.append(floats(
            1, 0, 0,
            1, 0.4, -10.0, 3.4, 1.2, 1.0, 1,
            1, 0.4, -14.0, 3.9, 1.7, 1.5, 1,
            1, 0.4, -20.0, 4.3, 1.8, 1.6, 1,
            1, 0.5, -25.5, 3.7, 1.3, 1.2, 1,
            1, 0.6, -30.0, 2.4, 0.45, 0.5, 0,
            2, 1.2, -4.4, 0.9, 0.35, 0.4, 0,
        ))
    elif part == BRACHIALIS:
        paths.append(floats(
            1, 0, 0,
            1, 1.0, -15.0, 1.5, 1.3, 0.8, 1,
            1, 0.6, -21.0, 2.0, 1.9, 1.0, 1,
            1, 0.4, -27.0, 2.2, 2.0, 1.1, 1,
            1, 0.4, -31.0, 2.0, 1.4, 0.8, 1,
            2, -0.6, -2.6, 1.0, 0.5, 0.4, 0,
        ))
    elif part == TRICEPS_BRACHII:
        # The long head from below the glenoid, the lateral head from the
        # back of the shaft, one belly behind the humerus, and its tendon
        # to the olecranon.
        paths.append(floats(
            1, 0, 0,
            0, 15.1, 44.3, -4.6, 0.5, 0.5, 0,
            1, -0.8, -5.5, -2.6, 1.0, 1.1, 1,
            1, -0.3, -11.0, -3.2, 1.4, 1.3, 1,
        ))
        paths.append(floats(
            1, 0, 0,
            1, 2.0, -5.0, -1.2, 0.6, 0.6, 1,
            1, 1.6, -11.0, -2.4, 1.2, 1.1, 1,
        ))
        paths.append(floats(
            1, 0, 0,
            1, 0.2, -11.0, -3.0, 1.8, 1.4, 1,
            1, 0.3, -18.0, -3.4, 2.1, 1.6, 1,
            1, 0.3, -24.0, -3.0, 1.9, 1.4, 1,
            1, 0.3, -28.5, -2.4, 1.3, 0.9, 1,
            2, -0.4, 1.0, -2.1, 0.7, 0.5, 0,
        ))
    elif part == PRONATOR_TERES:
        paths.append(floats(
            1, 0, 0,
            2, -3.0, 1.5, 0.4, 0.6, 0.6, 1,
            2, -1.6, -3.5, 1.9, 1.1, 0.9, 1,
            2, 0.6, -8.0, 2.4, 1.0, 0.8, 1,
            2, 2.6, -11.0, 0.9, 0.4, 0.5, 0,
        ))
    elif part == FLEXOR_CARPI_RADIALIS:
        paths.append(floats(
            1, 0, 0,
            2, -2.8, 1.0, 0.6, 0.5, 0.5, 1,
            2, -1.5, -5.0, 2.6, 0.9, 0.7, 1,
            2, -0.2, -11.0, 3.1, 1.0, 0.7, 1,
            2, 0.6, -17.0, 2.9, 0.6, 0.5, 1,
            2, 1.4, -25.0, 2.0, 0.3, 0.3, 0,
            3, 1.2, -2.0, 1.4, 0.25, 0.25, 0,
            3, 1.05, -4.2, 0.9, 0.25, 0.25, 0,
        ))
    elif part == PALMARIS_LONGUS:
        paths.append(floats(
            1, 0, 0,
            2, -3.0, 1.1, 0.2, 0.4, 0.4, 1,
            2, -1.8, -5.0, 2.9, 0.7, 0.6, 1,
            2, -0.8, -11.0, 3.4, 0.6, 0.5, 1,
            2, -0.2, -16.0, 3.4, 0.2, 0.2, 0,
            2, 0.4, -26.0, 2.6, 0.18, 0.18, 0,
            3, -0.1, -2.2, 1.9, 0.18, 0.18, 0,
        ))
    elif part == FLEXOR_CARPI_ULNARIS:
        paths.append(floats(
            1, 0, 0,
            2, -3.2, 1.2, -0.8, 0.6, 0.6, 1,
            2, -3.0, -4.0, -0.2, 1.1, 1.0, 1,
            2, -2.6, -11.0, 0.4, 1.1, 1.0, 1,
            2, -2.3, -18.0, 0.8, 0.8, 0.7, 1,
            2, -2.0, -25.0, 1.0, 0.35, 0.35, 0,
            3, -1.5, -1.2, 1.2, 0.3, 0.3, 0,
        ))
    elif part == FLEXOR_DIGITORUM_SUPERFICIALIS:
        paths.append(floats(
            1, 0, 0,
            2, -2.4, 0.6, 0.8, 0.7, 0.6, 1,
            2, -1.2, -6.0, 2.0, 1.5, 0.8, 1,
            2, -0.4, -13.0, 2.2, 1.7, 0.8, 1,
            2, 0.2, -20.0, 2.0, 1.4, 0.8, 1,
            2, 0.6, -26.0, 1.7, 0.9, 0.5, 0,
            2, 0.8, -28.2, 1.5, 0.8, 0.45, 0,
        ))
    elif part == FLEXOR_DIGITORUM_PROFUNDUS:
        paths.append(floats(
            1, 0, 0,
            2, -1.4, -2.5, 0.4, 0.9, 0.6, 1,
            2, -1.0, -9.0, 1.0, 1.4, 0.7, 1,
            2, -0.4, -17.0, 1.1, 1.3, 0.7, 1,
            2, 0.2, -24.0, 1.1, 1.0, 0.6, 1,
            2, 0.6, -28.0, 1.1, 0.8, 0.4, 0,
        ))
    elif part == FLEXOR_POLLICIS_LONGUS:
        paths.append(floats(
            1, 0, 0,
            2, 1.7, -7.0, 1.2, 0.6, 0.5, 1,
            2, 1.7, -14.0, 1.5, 0.8, 0.6, 1,
            2, 1.5, -21.0, 1.5, 0.7, 0.5, 1,
            2, 1.3, -27.0, 1.3, 0.3, 0.3, 0,
        ))
    elif part == PRONATOR_QUADRATUS:
        # A flat square across the front of the lower radius and ulna.
        paths.append(floats(
            0, 1, 0,
            2, -1.3, -24.8, 0.7, 1.2, 0.45, 1,
            2, 1.9, -24.8, 1.0, 1.2, 0.45, 1,
        ))
    elif part == BRACHIORADIALIS:
        paths.append(floats(
            1, 0, 0,
            1, 1.9, -22.0, 0.8, 0.6, 0.5, 1,
            1, 2.6, -27.5, 1.2, 1.2, 1.0, 1,
            2, 3.2, -5.0, 1.3, 1.5, 1.1, 1,
            2, 3.0, -12.0, 1.2, 1.2, 0.9, 1,
            2, 3.1, -20.0, 0.9, 0.5, 0.4, 0,
            2, 3.2, -26.6, 0.5, 0.35, 0.3, 0,
        ))
    elif part == EXTENSOR_CARPI_RADIALIS_LONGUS:
        paths.append(floats(
            1, 0, 0,
            1, 2.4, -27.0, 0.2, 0.6, 0.6, 1,
            2, 3.4, -3.0, -0.2, 1.0, 0.9, 1,
            2, 3.3, -10.0, -0.8, 0.9, 0.8, 1,
            2, 3.0, -18.0, -0.9, 0.4, 0.4, 0,
            2, 2.6, -26.5, -0.9, 0.3, 0.3, 0,
            3, 1.3, -3.8, -0.6, 0.25, 0.25, 0,
        ))
    elif part == EXTENSOR_CARPI_RADIALIS_BREVIS:
        paths.append(floats(
            1, 0, 0,
            2, 3.1, 0.5, -0.7, 0.5, 0.5, 1,
            2, 2.9, -6.0, -1.1, 0.9, 0.8, 1,
            2, 2.6, -13.0, -1.3, 0.9, 0.7, 1,
            2, 2.2, -20.0, -1.3, 0.4, 0.4, 0,
            2, 1.8, -26.5, -1.3, 0.3, 0.3, 0,
            3, 0.1, -4.0, -0.6, 0.25, 0.25, 0,
        ))
    elif part == EXTENSOR_DIGITORUM:
        paths.append(floats(
            1, 0, 0,
            2, 2.8, 0.2, -1.0, 0.5, 0.5, 1,
            2, 1.8, -7.0, -1.8, 1.2, 0.8, 1,
            2, 1.0, -14.0, -2.0, 1.3, 0.8, 1,
            2, 0.6, -21.0, -1.8, 1.0, 0.6, 1,
            2, 0.6, -27.0, -1.5, 0.8, 0.35, 0,
            2, 0.7, -28.4, -1.4, 0.8, 0.3, 0,
        ))
    elif part == EXTENSOR_DIGITI_MINIMI:
        paths.append(floats(
            1, 0, 0,
            2, 2.5, 0.0, -1.3, 0.4, 0.4, 1,
            2, -0.5, -9.0, -2.1, 0.6, 0.5, 1,
            2, -1.2, -18.0, -1.9, 0.5, 0.45, 1,
            2, -1.3, -24.0, -1.5, 0.25, 0.25, 0,
            2, -1.2, -28.0, -1.2, 0.25, 0.25, 0,
        ))
    elif part == EXTENSOR_CARPI_ULNARIS:
        paths.append(floats(
            1, 0, 0,
            2, 2.3, 0.0, -1.5, 0.5, 0.5, 1,
            2, -0.9, -7.0, -1.6, 0.9, 0.8, 1,
            2, -1.9, -14.0, -1.2, 0.9, 0.7, 1,
            2, -2.1, -21.0, -0.8, 0.4, 0.4, 0,
            2, -2.1, -26.5, -0.6, 0.3, 0.3, 0,
            3, -2.2, -3.6, -0.3, 0.25, 0.25, 0,
        ))
    elif part == ANCONEUS:
        paths.append(floats(
            1, 0, 0,
            2, 3.0, 0.8, -0.9, 0.5, 0.5, 1,
            2, 1.2, -1.8, -2.0, 1.0, 0.7, 1,
            2, -0.4, -4.5, -1.8, 0.5, 0.4, 1,
        ))
    elif part == SUPINATOR:
        paths.append(floats(
            1, 0, 0,
            2, 3.0, 0.2, -0.5, 0.5, 0.5, 1,
            2, 3.3, -2.6, -0.4, 0.8, 0.7, 1,
            2, 2.7, -5.8, 0.4, 0.6, 0.5, 1,
        ))
    elif part == ABDUCTOR_POLLICIS_LONGUS:
        paths.append(floats(
            1, 0, 0,
            2, 0.3, -9.0, -1.0, 0.6, 0.5, 1,
            2, 1.4, -15.0, -1.3, 0.8, 0.6, 1,
            2, 2.6, -21.0, -0.9, 0.5, 0.4, 1,
            2, 3.3, -26.0, 0.0, 0.3, 0.3, 0,
            3, 2.6, -3.0, 0.9, 0.25, 0.25, 0,
        ))
    elif part == EXTENSOR_POLLICIS_BREVIS:
        paths.append(floats(
            1, 0, 0,
            2, 1.4, -15.0, -1.0, 0.5, 0.4, 1,
            2, 2.4, -20.0, -1.0, 0.6, 0.45, 1,
            2, 3.3, -25.5, -0.1, 0.3, 0.3, 0,
            3, 3.1, -5.6, 1.0, 0.22, 0.22, 0,
        ))
    elif part == EXTENSOR_POLLICIS_LONGUS:
        paths.append(floats(
            1, 0, 0,
            2, -0.6, -12.0, -1.1, 0.5, 0.4, 1,
            2, 0.3, -18.0, -1.3, 0.7, 0.5, 1,
            2, 1.2, -24.0, -1.4, 0.4, 0.35, 1,
            2, 1.7, -27.8, -1.5, 0.25, 0.25, 0,
            3, 2.2, -2.2, -0.8, 0.22, 0.22, 0,
        ))
    else:
        paths.append(floats(
            1, 0, 0,
            2, -0.7, -17.0, -1.0, 0.45, 0.35, 1,
            2, 0.0, -22.0, -1.2, 0.55, 0.4, 1,
            2, 0.6, -26.5, -1.3, 0.25, 0.25, 0,
            2, 0.9, -28.3, -1.3, 0.22, 0.22, 0,
        ))
    # fmt: on
    return paths^


def station_point(
    dimensions: ArmDimensions, frame: Int, x: Float32, y: Float32, z: Float32
) -> Vector3:
    """Return a point authored in one of the arm's frames.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        frame: `ON_TORSO`, `ON_UPPER`, `ON_FORE` or `ON_HAND`. Any other
            value reads as `ON_HAND`.
        x: Template centimeters in that frame.
        y: Template centimeters in that frame.
        z: Template centimeters in that frame.

    Returns:
        The point in the pelvis frame, in meters.
    """
    var f = dimensions.frame
    if frame == ON_TORSO:
        return dimensions.torso.frame.at(x, y, z)
    if frame == ON_UPPER:
        return f.upper(x, y, z)
    if frame == ON_FORE:
        return f.fore(x, y, z)
    return f.hand(x, y, z)


def paths_field(
    dimensions: ArmDimensions,
    paths: List[List[Float32]],
    scale: Float32,
    side: BodySide,
    k: Float32,
) -> SweepField:
    """Return the field of authored station paths, placed on `side`.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        paths: Paths laid out as `arm_muscle_paths` returns them.
        scale: How much a growing station's radii grow.
        side: `RIGHT` or `LEFT`.
        k: Smooth-union radius, in template cm.

    Returns:
        The field.
    """
    var f = dimensions.frame
    var sweeps = List[Sweep]()
    for p in range(len(paths)):
        var row = paths[p].copy()
        var sweep = Sweep(Vector3(row[0], row[1], row[2]))
        for s in range((len(row) - 3) // STATION):
            var at = 3 + STATION * s
            var grow = Float32(1)
            if row[at + 6] > 0:
                grow = scale
            sweep.add(
                station_point(
                    dimensions,
                    Int(row[at]),
                    row[at + 1],
                    row[at + 2],
                    row[at + 3],
                ),
                f.cm(row[at + 4] * grow),
                f.cm(row[at + 5] * grow),
            )
        sweeps.append(sweep^)
    return SweepField(
        sweeps^, List[Dome](), side, f.cm(k), f.cm(0.1), f.cm(0.5)
    )


def arm_muscle_field(
    dimensions: ArmMuscleDimensions, part: ArmMuscle, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one arm muscle.

    Args:
        dimensions: Landmarks and the radius scale.
        part: A named muscle.
        side: `RIGHT` or `LEFT`.

    Returns:
        The muscle's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    var paths = arm_muscle_paths(part)
    if not side.is_valid():
        raise Error("An arm side must be RIGHT or LEFT")
    return paths_field(dimensions.arm, paths, dimensions.scale, side, 0.4)


def arm_muscle_distance(
    dimensions: ArmMuscleDimensions,
    part: ArmMuscle,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        part: Which muscle to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return arm_muscle_field(dimensions, part, side).distance(point)
