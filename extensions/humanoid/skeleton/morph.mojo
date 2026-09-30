# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a genome reshapes the neck and the head.

Every landmark of the neck and the head is authored in centimeters on
the six-foot template and placed through the head's frame. `HeadMorph`
moves each authored point before the frame places it. It is a sum of
smooth, local displacements, one for each face and head gene: the nose's
genes move the points near the nose, the eyes' genes the points around
each orbit, and so on. So the skull, the muscles, the vessels, the skin
and the hair move together, and the anatomy stays inside the skin.

    var morph = HeadMorph(genome)
    var tip = morph.apply(Vector3(0, 68.7, 10.5))

Each displacement fades to nothing at the edge of its region, and none
is strong enough to fold space over on itself. Below the neck's base
the morph is the identity, so the neck still meets the torso. The
template genome gives the identity everywhere.

The strengths are authored. At an expression of one each trait sits
near the edge of the adult range, not beyond it. The ears are skin
alone, so the skin shapes them itself; see `warp_ear`.
"""

from extensions.humanoid.genome import (
    BROW_ARCH,
    BROW_HEIGHT,
    BROW_RIDGE,
    CHEEKBONES,
    CHIN,
    EYE_DEPTH,
    EYE_SIZE,
    EYE_SPACING,
    EYE_TILT,
    Genome,
    HEAD_HEIGHT,
    HEAD_LENGTH,
    HEAD_WIDTH,
    JAW_WIDTH,
    LIP_FULLNESS,
    MOUTH_WIDTH,
    NECK_LENGTH,
    NOSE_BRIDGE,
    NOSE_LENGTH,
    NOSE_PROJECTION,
    NOSE_WIDTH,
    check_genome,
)
from extensions.humanoid.sex import MALE, Sex
from math.vector3 import Vector3
from std.math import cos, max, min, sin

# Where each feature sits on the template, in centimeters: x to the
# right, y above the hip joint centers, z forward.
comptime EYE_X = Float32(3.2)
comptime EYE_Y = Float32(72.1)
comptime EYE_Z = Float32(7.4)
comptime CRANIUM_Z = Float32(-1.0)
comptime VAULT_Y = Float32(72.0)
# How far each trait moves at an expression of one.
comptime HEAD_WIDTH_SCALE = Float32(0.07)
comptime HEAD_LENGTH_SCALE = Float32(0.06)
comptime HEAD_HEIGHT_SCALE = Float32(0.09)
comptime NECK_STRETCH = Float32(2.2)
comptime EYE_SIZE_SCALE = Float32(0.12)


def _clamp01(value: Float32) -> Float32:
    """Return `value` held to 0 through 1."""
    return max(Float32(0), min(Float32(1), value))


def smoothstep(edge0: Float32, edge1: Float32, x: Float32) -> Float32:
    """Return the Hermite step from `edge0` to `edge1`.

    Args:
        edge0: Where the step starts, at zero.
        edge1: Where it ends, at one.
        x: The value to step.

    Returns:
        Zero below `edge0`, one above `edge1`, and a smooth curve
        between.
    """
    var t = _clamp01((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)


def bump(point: Vector3, center: Vector3, radius: Float32) -> Float32:
    """Return a smooth weight that is one at `center` and zero at
    `radius` and beyond.

    Args:
        point: Where to weigh.
        center: Where the weight is one.
        radius: Where it has fallen to zero.

    Returns:
        `(1 - d^2 / r^2)^2` inside the radius, and zero outside.
    """
    var dx = point.x - center.x
    var dy = point.y - center.y
    var dz = point.z - center.z
    var q = (dx * dx + dy * dy + dz * dz) / (radius * radius)
    if q >= 1:
        return 0
    var w = 1 - q
    return w * w


def _side(x: Float32) -> Float32:
    """Return one on the right, minus one on the left."""
    if x < 0:
        return -1
    return 1


struct HeadMorph(ImplicitlyCopyable):
    """The displacements a genome makes to the neck and the head.

    The fields are the genome's expressions of the genes the head
    reads. `active` is False for the template genome, and then `apply`
    returns its point unchanged.
    """

    var active: Bool
    var head_width: Float32
    var head_length: Float32
    var head_height: Float32
    var jaw_width: Float32
    var chin: Float32
    var cheekbones: Float32
    var brow_ridge: Float32
    var brow_height: Float32
    var brow_arch: Float32
    var eye_size: Float32
    var eye_spacing: Float32
    var eye_tilt: Float32
    var eye_depth: Float32
    var nose_length: Float32
    var nose_width: Float32
    var nose_projection: Float32
    var nose_bridge: Float32
    var mouth_width: Float32
    var lip_fullness: Float32
    var neck_length: Float32

    def __init__(out self):
        """Make the identity morph of the template genome."""
        self.active = False
        self.head_width = 0
        self.head_length = 0
        self.head_height = 0
        self.jaw_width = 0
        self.chin = 0
        self.cheekbones = 0
        self.brow_ridge = 0
        self.brow_height = 0
        self.brow_arch = 0
        self.eye_size = 0
        self.eye_spacing = 0
        self.eye_tilt = 0
        self.eye_depth = 0
        self.nose_length = 0
        self.nose_width = 0
        self.nose_projection = 0
        self.nose_bridge = 0
        self.mouth_width = 0
        self.lip_fullness = 0
        self.neck_length = 0

    def __init__(out self, genome: Genome, sex: Sex = MALE) raises:
        """Read the head's genes from `genome`, on the template of `sex`.

        The female template's face differs from the male one's the way
        the averages of the two differ: a smaller brow ridge and nose, a
        narrower jaw and a smaller chin, slightly larger eyes and fuller
        lips, and a longer neck. Those offsets are added to the genes.

        Args:
            genome: The genome to read.
            sex: `MALE` or `FEMALE`. `MALE` by default.

        Raises:
            Error: If `genome` is not valid.
        """
        check_genome(genome, "head")
        self.head_width = genome.get(HEAD_WIDTH)
        self.head_length = genome.get(HEAD_LENGTH)
        self.head_height = genome.get(HEAD_HEIGHT)
        self.jaw_width = genome.get(JAW_WIDTH)
        self.chin = genome.get(CHIN)
        self.cheekbones = genome.get(CHEEKBONES)
        self.brow_ridge = genome.get(BROW_RIDGE)
        self.brow_height = genome.get(BROW_HEIGHT)
        self.brow_arch = genome.get(BROW_ARCH)
        self.eye_size = genome.get(EYE_SIZE)
        self.eye_spacing = genome.get(EYE_SPACING)
        self.eye_tilt = genome.get(EYE_TILT)
        self.eye_depth = genome.get(EYE_DEPTH)
        self.nose_length = genome.get(NOSE_LENGTH)
        self.nose_width = genome.get(NOSE_WIDTH)
        self.nose_projection = genome.get(NOSE_PROJECTION)
        self.nose_bridge = genome.get(NOSE_BRIDGE)
        self.mouth_width = genome.get(MOUTH_WIDTH)
        self.lip_fullness = genome.get(LIP_FULLNESS)
        self.neck_length = genome.get(NECK_LENGTH)
        if sex != MALE:
            self.brow_ridge -= 1.0
            self.nose_length -= 0.35
            self.nose_width -= 0.45
            self.nose_projection -= 0.25
            self.nose_bridge -= 0.25
            self.jaw_width -= 0.8
            self.chin -= 0.4
            self.eye_size += 0.2
            self.lip_fullness += 0.35
            self.cheekbones += 0.2
            self.brow_height += 0.4
            self.brow_arch += 0.4
            self.neck_length += 0.25
        self.active = False
        var fields: List[Float32] = [
            self.head_width,
            self.head_length,
            self.head_height,
            self.jaw_width,
            self.chin,
            self.cheekbones,
            self.brow_ridge,
            self.brow_height,
            self.brow_arch,
            self.eye_size,
            self.eye_spacing,
            self.eye_tilt,
            self.eye_depth,
            self.nose_length,
            self.nose_width,
            self.nose_projection,
            self.nose_bridge,
            self.mouth_width,
            self.lip_fullness,
            self.neck_length,
        ]
        for index in range(len(fields)):  # pragma: no branch
            if fields[index] != 0:
                self.active = True

    def cranium_scale(self) -> Vector3:
        """Return how much the cranium grows across, up and along.

        Returns:
            The factors on x, y and z. One on the template genome.
        """
        return Vector3(
            1 + HEAD_WIDTH_SCALE * self.head_width,
            1 + HEAD_HEIGHT_SCALE * self.head_height,
            1 + HEAD_LENGTH_SCALE * self.head_length,
        )

    def eye_scale(self) -> Float32:
        """Return how much each eye and its opening grow.

        Returns:
            The factor. One on the template genome.
        """
        return 1 + EYE_SIZE_SCALE * self.eye_size

    def lip_scale(self) -> Float32:
        """Return how much thicker each lip is.

        Returns:
            The factor. One on the template genome.
        """
        return 1 + Float32(0.35) * self.lip_fullness

    def eye_center(self, side: Float32) -> Vector3:
        """Return where one eyeball's center lands, in template cm.

        Args:
            side: One for the right eye, minus one for the left.

        Returns:
            The center after the morph.
        """
        return self.apply(Vector3(side * EYE_X, EYE_Y, EYE_Z))

    def apply(self, point: Vector3) -> Vector3:
        """Return where the morph moves one template point.

        Args:
            point: A point in template centimeters.

        Returns:
            The moved point, in template centimeters.
        """
        if not self.active:
            return point
        var p = point
        var side = _side(p.x)
        var d = Vector3(0, 0, 0)
        # The face's features, each in its own region. The weights are
        # taken at the authored point, so the displacements add.
        # The eyes: size about the eyeball's center, then spacing,
        # tilt and depth.
        var eye = Vector3(side * EYE_X, EYE_Y, EYE_Z)
        var w = bump(p, eye, 2.9)
        if w > 0:
            var k = EYE_SIZE_SCALE * self.eye_size * w
            d = d + Vector3(
                (p.x - eye.x) * k, (p.y - eye.y) * k, (p.z - eye.z) * k
            )
            d.x += side * Float32(0.45) * self.eye_spacing * w
            var turn = Float32(0.13) * self.eye_tilt * w
            var ox = (p.x - eye.x) * side
            var oy = p.y - eye.y
            d.y += ox * sin(turn) + oy * (cos(turn) - 1)
            d.x += side * (ox * (cos(turn) - 1) - oy * sin(turn))
            d.z -= Float32(0.45) * self.eye_depth * w
        # The brows: height and arch move the soft brow; the ridge is
        # bone.
        var brow = Vector3(side * 2.9, 74.6, 8.6)
        w = bump(p, brow, 2.3)
        if w > 0:
            d.y += Float32(0.45) * self.brow_height * w
            var middle = bump(p, Vector3(side * 2.6, 74.8, 8.8), 1.3)
            d.y += Float32(0.35) * self.brow_arch * middle
        w = bump(p, Vector3(side * 2.6, 74.2, 8.2), 3.2)
        if w > 0:
            d.z += Float32(0.5) * self.brow_ridge * w
        # The cheekbones stand out and forward.
        w = bump(p, Vector3(side * 5.2, 70.4, 5.6), 3.0)
        if w > 0:
            d.x += side * Float32(0.55) * self.cheekbones * w
            d.z += Float32(0.25) * self.cheekbones * w
        # The nose: length moves the tip down, width spreads the wings,
        # projection brings the tip forward, and the bridge rises.
        w = bump(p, Vector3(0, 70.0, 9.6), 3.6)
        if w > 0:
            d.y -= (
                max(Float32(0), 73.4 - p.y)
                * Float32(0.14)
                * (self.nose_length * w)
            )
        w = bump(p, Vector3(0, 68.4, 9.6), 2.4)
        if w > 0:
            d.x += p.x * Float32(0.28) * self.nose_width * w
        w = bump(p, Vector3(0, 69.0, 10.2), 2.8)
        if w > 0:
            d.z += (
                max(Float32(0), p.z - 8.2)
                * Float32(0.30)
                * (self.nose_projection * w)
            )
        w = bump(p, Vector3(0, 72.2, 9.1), 1.8)
        if w > 0:
            d.z += Float32(0.4) * self.nose_bridge * w
        # The mouth: width from corner to corner, and fullness swells
        # the lips up, down and forward about the line between them.
        w = bump(p, Vector3(0, 64.6, 9.0), 3.4)
        if w > 0:
            d.x += p.x * Float32(0.14) * self.mouth_width * w
        w = bump(p, Vector3(0, 64.6, 9.3), 1.7)
        if w > 0:
            d.y += (p.y - 64.6) * Float32(0.35) * self.lip_fullness * w
            d.z += Float32(0.3) * self.lip_fullness * w
        # The chin forward and down, and the jaw's angles out.
        w = bump(p, Vector3(0, 61.6, 7.4), 3.6)
        if w > 0:
            d.z += Float32(0.8) * self.chin * w
            d.y -= Float32(0.4) * self.chin * w
        w = bump(p, Vector3(side * 4.9, 63.8, 0.5), 4.2)
        if w > 0:
            d.x += side * Float32(0.6) * self.jaw_width * w
        p = p + d
        # The whole head: breadth and length of the cranium, and the
        # height of the vault, fading out down the neck.
        var head = smoothstep(59.0, 69.0, point.y)
        if head > 0:
            var s = self.cranium_scale()
            p.x = p.x * (1 + (s.x - 1) * head)
            p.z = CRANIUM_Z + (p.z - CRANIUM_Z) * (1 + (s.z - 1) * head)
            if p.y > VAULT_Y:
                p.y = VAULT_Y + (p.y - VAULT_Y) * s.y
        # The neck stretches between its base and the skull.
        p.y += NECK_STRETCH * self.neck_length * smoothstep(51.5, 64.0, point.y)
        return p
