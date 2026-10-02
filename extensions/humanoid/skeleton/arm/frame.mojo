# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Where the arm, the forearm and the hand hang, in the pelvis frame.

The arm hangs from the center of the humeral head, under the acromion
of the torso's scapula. It stands in the anatomical position: at the
side, the elbow straight and the palm forward. The upper arm turns
`ARM_ABDUCTION` out from the side about the shoulder, so its skin
clears the chest. The forearm and the hand turn out a little more at
the elbow: the carrying angle.

Every part of the arm and the hand is authored in centimeters on the
six-foot template, in a local frame that hangs straight down. Plus x is
lateral, toward the thumb; plus y is proximal; plus z is anterior,
toward the palm. `ArmFrame` places a local point on the right arm.
The left arm is its mirror image on x. Lengths scale with stature. The
values are template parameters. They are not a cited osteometric
table.

    var dims = arm_dimensions(Length(6.0, FOOT), MALE)
    var elbow = dims.frame.elbow
"""

from extensions.humanoid.athleticism import Athleticism, radius_scale
from extensions.humanoid.genome import ARM_LENGTH, Genome, check_genome
from extensions.humanoid.sex import MALE, Sex
from extensions.humanoid.side import RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import check_spec, finite_point
from extensions.humanoid.skeleton.pelvis.bones.dimensions import TEMPLATE_CM
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    ARM_ABDUCTION,
    TorsoDimensions,
    shoulder_girdle,
    torso_dimensions,
)
from math.vector3 import Vector3
from std.math import cos, isfinite, sin
from units.si import Length

# How far the forearm turns out from the upper arm at the elbow, in
# radians: about seven degrees for a man and ten for a woman.
comptime MALE_CARRYING_ANGLE = Float32(0.12)
comptime FEMALE_CARRYING_ANGLE = Float32(0.18)
# The elbow's axis, below the humeral head's center, in template cm.
comptime ELBOW_X = Float32(0.4)
comptime ELBOW_Y = Float32(-32.9)
comptime ELBOW_Z = Float32(0.4)
# How much `ARM_LENGTH` stretches the arm at an expression of one.
comptime ARM_REACH = Float32(0.06)
# The radiocarpal joint, below the elbow's axis, in template cm.
comptime WRIST_X = Float32(0.8)
comptime WRIST_Y = Float32(-28.4)
comptime WRIST_Z = Float32(0.45)


def turn(angle: Float32, x: Float32, y: Float32, z: Float32) -> Vector3:
    """Return `(x, y, z)` turned `angle` about z, down toward plus x.

    Args:
        angle: Radians. Zero leaves the point alone.
        x: Lateral component.
        y: Proximal component.
        z: Anterior component.

    Returns:
        The turned vector, in the input's units.
    """
    var c = cos(angle)
    var s = sin(angle)
    return Vector3(x * c - y * s, x * s + y * c, z)


@fieldwise_init
struct ArmFrame(ImplicitlyCopyable):
    """Places points authored on the hanging right arm.

    `shoulder`, `elbow` and `wrist` are the joint centers, in meters.
    The upper arm turns `upper_angle` from the vertical; the forearm
    and the hand turn `fore_angle`. `reach` stretches the upper arm and
    the forearm along their length; the hand keeps its size.
    """

    var stature: Float32
    var shoulder: Vector3
    var elbow: Vector3
    var wrist: Vector3
    var upper_angle: Float32
    var fore_angle: Float32
    # The factor on length down the upper arm and the forearm, from the
    # genome's `ARM_LENGTH`. One on the template.
    var reach: Float32

    def cm(self, value: Float32) -> Float32:
        """Return a template length in meters, scaled by stature.

        Args:
            value: Centimeters on the six-foot template.

        Returns:
            Meters.
        """
        return value * TEMPLATE_CM * self.stature

    def upper(self, x: Float32, y: Float32, z: Float32) -> Vector3:
        """Return a point of the upper arm.

        Args:
            x: Centimeters lateral of the humeral head's center.
            y: Centimeters above it: negative down the arm.
            z: Centimeters in front of it.

        Returns:
            The point in the pelvis frame, in meters.
        """
        return self.shoulder + turn(
            self.upper_angle, self.cm(x), self.cm(y) * self.reach, self.cm(z)
        )

    def fore(self, x: Float32, y: Float32, z: Float32) -> Vector3:
        """Return a point of the forearm.

        Args:
            x: Centimeters lateral of the elbow's axis.
            y: Centimeters above it: negative down the forearm.
            z: Centimeters in front of it.

        Returns:
            The point in the pelvis frame, in meters.
        """
        return self.elbow + turn(
            self.fore_angle, self.cm(x), self.cm(y) * self.reach, self.cm(z)
        )

    def hand(self, x: Float32, y: Float32, z: Float32) -> Vector3:
        """Return a point of the hand.

        Args:
            x: Centimeters lateral of the radiocarpal joint, toward the
                thumb.
            y: Centimeters above it: negative toward the fingertips.
            z: Centimeters in front of it, toward the palm.

        Returns:
            The point in the pelvis frame, in meters.
        """
        return self.wrist + turn(
            self.fore_angle, self.cm(x), self.cm(y), self.cm(z)
        )

    def hand_direction(self, x: Float32, y: Float32, z: Float32) -> Vector3:
        """Return a direction authored in the hand's frame, turned.

        Args:
            x: Lateral component.
            y: Proximal component.
            z: Anterior component.

        Returns:
            The unit direction in the pelvis frame.
        """
        var d = turn(self.fore_angle, x, y, z)
        d.normalize()
        return d


struct ArmDimensions(Copyable, Movable):
    """Stature, sex, the frame the arm and the hand hang in, and the
    torso they hang from.

    The torso's landmarks place what the arm reaches on the scapula and
    the clavicle.
    """

    var stature: Length
    var sex: Sex
    var frame: ArmFrame
    var torso: TorsoDimensions

    def __init__(
        out self,
        stature: Length,
        sex: Sex,
        frame: ArmFrame,
        var torso: TorsoDimensions,
    ):
        """Store an arm's size and frame.

        Args:
            stature: Standing height.
            sex: Osteological template.
            frame: Where the arm hangs.
            torso: Landmarks of the torso the arm hangs from.
        """
        self.stature = stature
        self.sex = sex
        self.frame = frame
        self.torso = torso^

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If sex or stature is refused, if the torso fails
                `validate`, or if a joint center is not finite.
        """
        check_spec(self.stature, self.sex, RIGHT, "arm")
        self.torso.validate()
        finite_point(self.frame.shoulder, "shoulder", "arm")
        finite_point(self.frame.elbow, "elbow", "arm")
        finite_point(self.frame.wrist, "wrist", "arm")


def arm_frame(torso: TorsoDimensions) raises -> ArmFrame:
    """Return the frame of the right arm on a torso.

    Args:
        torso: Landmarks from `torso_dimensions`.

    Returns:
        The joint centers, the two turns and the reach.

    Raises:
        Error: If the torso's genome is not valid.
    """
    check_genome(torso.genome, "arm")
    var carrying = FEMALE_CARRYING_ANGLE
    if torso.sex == MALE:
        carrying = MALE_CARRYING_ANGLE
    var shoulder = shoulder_girdle(torso).shoulder
    var frame = ArmFrame(
        torso.stature.value,
        shoulder,
        shoulder,
        shoulder,
        ARM_ABDUCTION,
        ARM_ABDUCTION + carrying,
        1 + ARM_REACH * torso.genome.get(ARM_LENGTH),
    )
    frame.elbow = frame.upper(ELBOW_X, ELBOW_Y, ELBOW_Z)
    frame.wrist = frame.fore(WRIST_X, WRIST_Y, WRIST_Z)
    return frame


def arm_dimensions(
    stature: Length, sex: Sex, genome: Genome = Genome()
) raises -> ArmDimensions:
    """Return where an adult's right arm hangs.

    Args:
        stature: Standing height. Must lie in 1.2 m through 2.5 m.
        sex: `MALE` or `FEMALE`.
        genome: Heritable traits. The frame genes move the shoulder and
            `ARM_LENGTH` stretches the arm. The template genome by
            default.

    Returns:
        The arm's size and frame.

    Raises:
        Error: If `sex` is not valid, stature is not finite or is
            outside the software range, or `genome` is not valid.
    """
    check_spec(stature, sex, RIGHT, "arm")
    var torso = torso_dimensions(stature, sex, genome)
    var frame = arm_frame(torso)
    return ArmDimensions(stature, sex, frame, torso^)


struct ArmMuscleDimensions(Copyable, Movable):
    """Arm landmarks plus the athleticism scale for soft-tissue radii."""

    var arm: ArmDimensions
    var athleticism: Athleticism
    var scale: Float32

    def __init__(
        out self, var arm: ArmDimensions, athleticism: Athleticism
    ) raises:
        """Pair arm landmarks with an athleticism.

        Args:
            arm: Landmarks from `arm_dimensions`.
            athleticism: `UNTONED` or `TONED`.

        Raises:
            Error: If `athleticism` is not named.
        """
        self.arm = arm^
        self.athleticism = athleticism
        self.scale = radius_scale(athleticism)

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If the arm fails `validate`, if athleticism is not
                named, or if the scale is not positive.
        """
        self.arm.validate()
        if not self.athleticism.is_valid():
            raise Error("An arm muscle needs a toned or untoned athleticism")
        if not isfinite(self.scale) or self.scale <= 0:
            raise Error(
                "An arm muscle radius scale must be finite and positive"
            )


def arm_muscle_dimensions(spec: HumanoidSpec) raises -> ArmMuscleDimensions:
    """Return arm landmarks and the radius scale for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.

    Returns:
        The landmarks and the scale.

    Raises:
        Error: If `spec` is refused, or athleticism is not named.
    """
    if not spec.athleticism.is_valid():
        raise Error("An arm muscle needs a toned or untoned athleticism")
    return ArmMuscleDimensions(
        arm_dimensions(spec.stature, spec.sex, spec.genome), spec.athleticism
    )
