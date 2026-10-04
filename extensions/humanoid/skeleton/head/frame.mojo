# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Where the neck and the head stand, in the pelvis frame.

The neck climbs from the torso's first thoracic vertebra in a gentle
cervical lordosis. The head sits on the atlas with the Frankfort plane
level: the eyes look straight ahead.

The neck and the head share the torso's frame: the origin is the
midpoint of the two hip joint centers, plus y is proximal, plus x is
body-right and plus z is anterior. Every landmark is authored in
centimeters on the six-foot male template, through the torso's
`TorsoFrame`, and scales with stature. On the template the top of the
skull is 84.4 cm above the hip joint centers, the eyes 72.5 cm and the
chin 60.5 cm. The values are template parameters. They are not a cited
anthropometric table. A female template is narrower and shallower, as
the torso's is.

    var dims = head_dimensions(Length(6.0, FOOT), MALE)
    var atlas = dims.centers[0]
"""

from extensions.humanoid.athleticism import Athleticism, radius_scale
from extensions.humanoid.genome import Genome
from extensions.humanoid.sex import MALE, Sex
from extensions.humanoid.side import RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import check_spec, finite_point
from extensions.humanoid.skeleton.morph import HeadMorph
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    TorsoDimensions,
    TorsoFrame,
    torso_dimensions,
)
from extensions.humanoid.skeleton.torso.sweep import floats
from math.vector3 import Vector3
from std.math import isfinite
from units.si import Length

# Cervical vertebrae, C1 to C7.
comptime CERVICAL = 7
# How a head's size grows with stature: as stature to this power. The
# template's stature, in meters. How much larger a woman's head is than
# her torso's narrower frame alone makes it.
comptime HEAD_ALLOMETRY = Float32(0.5)
comptime TEMPLATE_STATURE = Float32(1.8288)
comptime FEMALE_HEAD = Float32(1.05)
# How much slimmer a woman's neck is than her frame alone makes it.
comptime FEMALE_NECK = Float32(0.9)


struct HeadDimensions(Copyable, Movable):
    """Size and landmarks of one neck and head in the pelvis frame.

    Positions are in meters. The lists run from C1 down to C7. The
    torso they stand on places the neck's lowest disc and the muscles
    that reach the chest and the shoulders.
    """

    var stature: Length
    var sex: Sex
    var frame: TorsoFrame
    var torso: TorsoDimensions
    # Vertebral body centers and their half-width, half-depth and
    # height. The atlas has no body: its entry is the ring's center.
    var centers: List[Vector3]
    var widths: List[Float32]
    var depths: List[Float32]
    var heights: List[Float32]

    def __init__(
        out self,
        stature: Length,
        sex: Sex,
        frame: TorsoFrame,
        var torso: TorsoDimensions,
        var centers: List[Vector3],
        var widths: List[Float32],
        var depths: List[Float32],
        var heights: List[Float32],
    ):
        """Store a neck's and a head's size and landmarks.

        Args:
            stature: Standing height.
            sex: Osteological template.
            frame: The frame that authored the landmarks.
            torso: The torso the neck stands on.
            centers: Vertebral centers, C1 to C7, in meters.
            widths: Their half-widths, in meters.
            depths: Their half-depths, in meters.
            heights: Their heights, in meters.
        """
        self.stature = stature
        self.sex = sex
        self.frame = frame
        self.torso = torso^
        self.centers = centers^
        self.widths = widths^
        self.depths = depths^
        self.heights = heights^

    def at(self, x: Float32, y: Float32, z: Float32) -> Vector3:
        """Return one point authored on the six-foot template.

        Args:
            x: Centimeters to the right of the midline.
            y: Centimeters above the hip joint centers.
            z: Centimeters in front of them.

        Returns:
            The point, in meters.
        """
        return self.frame.at(x, y, z)

    def cm(self, value: Float32) -> Float32:
        """Return a template length in meters, scaled by stature.

        Args:
            value: Centimeters on the six-foot template.

        Returns:
            Meters.
        """
        return self.frame.cm(value)

    def cranium(self, x: Float32, y: Float32, z: Float32) -> Vector3:
        """Return the semi-axes of a cranial ellipsoid, in meters.

        The genome's head genes stretch the cranium, and the frame's
        `head` factor grows it; `at` moves its center the same way, so
        the ellipsoid's surface follows the points the morph moves.

        Args:
            x: Half the breadth, in template cm.
            y: Half the height, in template cm.
            z: Half the length, in template cm.

        Returns:
            The semi-axes, widened and deepened for the sex.
        """
        var f = self.frame
        var s = f.morph.cranium_scale() * f.head
        return Vector3(
            f.cm(x) * f.wide * s.x, f.cm(y) * s.y, f.cm(z) * f.deep * s.z
        )

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If sex or stature is refused, if the torso fails
                `validate`, if a list does not hold seven vertebrae, if a
                size is not finite and positive, or if a landmark is not finite.
        """
        check_spec(self.stature, self.sex, RIGHT, "head")
        self.torso.validate()
        self.frame.validate()
        if (
            len(self.centers) != CERVICAL
            or len(self.widths) != CERVICAL
            or len(self.depths) != CERVICAL
            or len(self.heights) != CERVICAL
        ):
            raise Error("A neck needs seven vertebrae, C1 to C7")
        for index in range(CERVICAL):  # pragma: no branch
            finite_point(self.centers[index], "cervical vertebra", "head")
            finite_point(
                Vector3(
                    self.widths[index], self.depths[index], self.heights[index]
                ),
                "cervical size",
                "head",
            )
            if not (
                self.widths[index] > 0
                and self.depths[index] > 0
                and self.heights[index] > 0
            ):
                raise Error("A cervical vertebra's size must be positive")


def head_scale(stature: Length, sex: Sex) -> Float32:
    """Return how much larger a head is than stature alone makes it.

    A head keeps its size better than a body does: across adults it
    grows about as stature to the power `HEAD_ALLOMETRY`, not in
    proportion. The six-foot male template's head is the reference. A
    woman's head is also less narrowed and shallowed than her torso.
    The head grows about the base of the jaw, so a shorter person's
    crown stands a little above the stature: about 2.5 cm at 1.63 m.

    Args:
        stature: Standing height.
        sex: `MALE` or `FEMALE`.

    Returns:
        The factor: one on the template, above one for a shorter person.
    """
    var ratio = TEMPLATE_STATURE / Float32(stature.value)
    var factor = ratio ** (1 - HEAD_ALLOMETRY)
    if sex != MALE:
        factor *= FEMALE_HEAD
    return factor


def head_dimensions(
    stature: Length, sex: Sex, genome: Genome = Genome()
) raises -> HeadDimensions:
    """Return the landmarks of a neck and a head for an adult humanoid.

    Args:
        stature: Standing height. Must lie in 1.2 m through 2.5 m.
        sex: `MALE` or `FEMALE`.
        genome: Heritable traits. The head's genes reshape the neck,
            the cranium and the face; see `HeadMorph`. The template
            genome by default.

    Returns:
        The cervical landmarks in the pelvis frame, and the torso they
        stand on.

    Raises:
        Error: If `sex` is not valid, stature is not finite or is
            outside the software range, or `genome` is not valid.
    """
    check_spec(stature, sex, RIGHT, "head")
    var torso = torso_dimensions(stature, sex, genome)
    # The head's own frame: the torso's, without the shoulders' and the
    # chest's genes, and with the head's shape.
    var f = TorsoFrame(
        torso.frame.stature,
        torso.frame.wide,
        torso.frame.deep,
        torso.frame.anchor,
        morph=HeadMorph(genome, sex),
        head=head_scale(stature, sex),
        neck=FEMALE_NECK if sex != MALE else Float32(1),
    )
    # Centers (y, z), half-width, half-depth and height, C1 to C7. The
    # atlas's center is its ring's.
    var y = floats(65.6, 63.3, 61.3, 59.45, 57.6, 55.75, 53.85)
    var z = floats(-2.4, -2.0, -2.1, -2.1, -2.3, -2.6, -3.1)
    var w = floats(1.5, 0.85, 0.8, 0.85, 0.9, 0.95, 1.1)
    var d = floats(1.5, 0.8, 0.75, 0.78, 0.8, 0.82, 0.88)
    var h = floats(0.9, 1.9, 1.3, 1.3, 1.3, 1.35, 1.4)
    var centers = List[Vector3]()
    var widths = List[Float32]()
    var depths = List[Float32]()
    var heights = List[Float32]()
    for index in range(CERVICAL):  # pragma: no branch
        centers.append(f.at(0, y[index], z[index]))
        widths.append(f.cm(w[index]) * f.wide)
        depths.append(f.cm(d[index]) * f.deep)
        heights.append(f.cm(h[index]))
    return HeadDimensions(
        stature, sex, f, torso^, centers^, widths^, depths^, heights^
    )


struct HeadMuscleDimensions(Copyable, Movable):
    """Head landmarks plus the athleticism scale for soft-tissue radii."""

    var head: HeadDimensions
    var athleticism: Athleticism
    var scale: Float32

    def __init__(
        out self, var head: HeadDimensions, athleticism: Athleticism
    ) raises:
        """Pair head landmarks with an athleticism.

        Args:
            head: Landmarks from `head_dimensions`.
            athleticism: `UNTONED` or `TONED`.

        Raises:
            Error: If `athleticism` is not named.
        """
        self.head = head^
        self.athleticism = athleticism
        self.scale = radius_scale(athleticism)

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If the head fails `validate`, if athleticism is not
                named, or if the scale is not positive.
        """
        self.head.validate()
        if not self.athleticism.is_valid():
            raise Error("A head muscle needs a toned or untoned athleticism")
        if not isfinite(self.scale) or self.scale <= 0:
            raise Error(
                "A head muscle radius scale must be finite and positive"
            )


def head_muscle_dimensions(spec: HumanoidSpec) raises -> HeadMuscleDimensions:
    """Return head landmarks and the radius scale for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.

    Returns:
        The landmarks and the scale.

    Raises:
        Error: If `spec` is refused, or athleticism is not named.
    """
    if not spec.athleticism.is_valid():
        raise Error("A head muscle needs a toned or untoned athleticism")
    return HeadMuscleDimensions(
        head_dimensions(spec.stature, spec.sex, spec.genome), spec.athleticism
    )
