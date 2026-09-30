# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The color the face's skin takes on region by region.

Skin is not one color over a face. The lips are red, because their thin
skin has no melanin to speak of and blood shows through it. The cheeks,
the tip of the nose and the ears are a little redder than the forehead.
The lids and the skin under the eyes are thin and darker. A man's jaw
and upper lip carry the gray-blue of the beard under the skin. The
brows' hair is painted into the skin under them, in the hair's color.

`tint_head_skin` writes these into a skin mesh's `color` attribute, one
linear factor per vertex, which a material with vertex colors multiplies
into its albedo. A factor of one leaves the albedo alone.

    var skin = head_skin_from_dimensions(dims, 48)
    tint_head_skin(skin, dims)
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from extensions.humanoid.genome import MELANIN
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.head.frame import (
    HeadDimensions,
    HeadMuscleDimensions,
)
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.skeleton.complexion import hair_tone, skin_tone
from extensions.humanoid.skeleton.head.hair.dimensions import (
    EYEBROWS,
    head_hair_field,
)
from extensions.humanoid.skeleton.head.skin.dimensions import EyeLids
from extensions.humanoid.skeleton.torso.sweep import SweepField
from extensions.humanoid.skeleton.morph import smoothstep
from math.vector3 import Vector3
from std.math import max, min, sqrt


@fieldwise_init
struct _Zone(ImplicitlyCopyable):
    """One region of color: an ellipsoid and the factor at its core."""

    var center: Vector3
    var radii: Vector3
    var factor: Vector3
    # How much of the ellipsoid's radius the full factor covers before
    # it fades.
    var core: Float32

    def weight(self, point: Vector3) -> Float32:
        """Return how much of the factor a point takes, 0 through 1."""
        var d = point - self.center
        var q = sqrt(
            (d.x / self.radii.x) ** 2
            + (d.y / self.radii.y) ** 2
            + (d.z / self.radii.z) ** 2
        )
        return 1 - smoothstep(self.core, 1, q)


# The name of the attribute that says how thin the skin is: one where
# light passes through it, at the rim of an ear, and zero where it
# cannot.
comptime THINNESS = "thinness"


def _mix(a: Vector3, b: Vector3, t: Float32) -> Vector3:
    """Return `a` moved toward `b` by `t`."""
    return a + (b - a) * t


def _zones(h: HeadDimensions) raises -> List[_Zone]:
    """Return the face's zones of color for the head `h`."""
    var c = h.cm(1)
    var dark = max(
        Float32(0), min(Float32(1), (h.torso.genome.get(MELANIN) + 1) / 2)
    )
    # Lips: pink and red on fair skin, deeper and a little violet on
    # dark skin.
    var lips = _mix(Vector3(0.95, 0.60, 0.64), Vector3(0.78, 0.60, 0.70), dark)
    var flush = _mix(Vector3(1.05, 0.93, 0.93), Vector3(1.02, 0.97, 0.97), dark)
    var lid = Vector3(0.93, 0.87, 0.90)
    var zones = List[_Zone]()
    zones.append(
        _Zone(
            h.at(0, 65.55, 10.5),
            Vector3(2.3 * c, 0.5 * c, 1.0 * c),
            lips,
            0.7,
        )
    )
    zones.append(
        _Zone(
            h.at(0, 64.5, 10.3),
            Vector3(2.2 * c, 0.6 * c, 1.0 * c),
            lips,
            0.7,
        )
    )
    zones.append(
        _Zone(
            h.at(0, 68.8, 11.6),
            Vector3(1.6 * c, 1.1 * c, 1.4 * c),
            flush,
            0.2,
        )
    )
    for s in range(2):  # pragma: no branch
        var side = Float32(1) - Float32(2 * s)
        # The cheek's flush.
        zones.append(
            _Zone(
                h.at(side * 4.3, 68.4, 8.2),
                Vector3(2.4 * c, 2.2 * c, 2.4 * c),
                flush,
                0.1,
            )
        )
        # The ear, thin and red.
        zones.append(
            _Zone(
                h.at(side * 8.7, 71.0, -1.6),
                Vector3(1.6 * c, 3.4 * c, 2.2 * c),
                flush,
                0.5,
            )
        )
        # The upper lid and the skin under the eye.
        zones.append(
            _Zone(
                h.at(side * 3.2, 72.6, 8.8),
                Vector3(1.7 * c, 0.9 * c, 1.2 * c),
                lid,
                0.3,
            )
        )
        zones.append(
            _Zone(
                h.at(side * 3.1, 71.0, 8.5),
                Vector3(1.6 * c, 0.8 * c, 1.2 * c),
                Vector3(0.94, 0.90, 0.93),
                0.2,
            )
        )
    if h.sex == MALE:
        # The beard's shadow over the jaw, the chin and the upper lip.
        var beard = _mix(
            Vector3(0.9, 0.9, 0.94), Vector3(0.95, 0.95, 0.96), dark
        )
        zones.append(
            _Zone(
                h.at(0, 63.0, 6.2),
                Vector3(6.2 * c, 3.6 * c, 5.2 * c),
                beard,
                0.55,
            )
        )
        zones.append(
            _Zone(
                h.at(0, 66.3, 10.4),
                Vector3(2.6 * c, 0.9 * c, 1.2 * c),
                beard,
                0.4,
            )
        )
    return zones^


def _lash_line(lids: EyeLids, point: Vector3) -> Float32:
    """Return how dark the lashes make a point at the lids' margin,
    0 through 1: most on the upper lid's edge, less on the lower."""
    var center = lids.right
    var side = Float32(1)
    if point.x < 0:
        center = lids.left
        side = -1
    var d = point - center
    var far = d.length()
    if d.z <= 0 or far > lids.reach:
        return 0
    var ox = d.x * side
    var qx = ox * lids.cos_tilt - d.y * lids.sin_tilt
    var qy = ox * lids.sin_tilt + d.y * lids.cos_tilt
    qy = qy + lids.height * Float32(0.1) - qx * Float32(0.06)
    var across = qx / lids.width
    var taper = max(Float32(0.05), 1 - across * across)
    var open = sqrt(across * across + (qy / lids.height) ** 2 / taper)
    # A band just outside the slit, on the lid's front.
    var band = 1 - smoothstep(0.0, 0.35, abs(open - 1.08))
    var upper = Float32(0.85) if qy > 0 else Float32(0.45)
    return band * upper * (1 - smoothstep(0.85, 1.0, abs(across)))


def _thin_zones(h: HeadDimensions) raises -> List[_Zone]:
    """Return where the face's skin is thin enough to let light through.

    The factor's `x` is the thinness at the zone's core."""
    var c = h.cm(1)
    var zones = List[_Zone]()
    zones.append(
        _Zone(
            h.at(0, 68.3, 11.3),
            Vector3(1.9 * c, 1.1 * c, 1.3 * c),
            Vector3(0.4, 0, 0),
            0.3,
        )
    )
    zones.append(
        _Zone(
            h.at(0, 64.7, 10.4),
            Vector3(2.4 * c, 0.9 * c, 0.9 * c),
            Vector3(0.25, 0, 0),
            0.4,
        )
    )
    for s in range(2):  # pragma: no branch
        var side = Float32(1) - Float32(2 * s)
        zones.append(
            _Zone(
                h.at(side * 8.9, 71.2, -2.0),
                Vector3(1.8 * c, 3.6 * c, 2.4 * c),
                Vector3(1, 0, 0),
                0.5,
            )
        )
        zones.append(
            _Zone(
                h.at(side * 3.2, 72.1, 8.8),
                Vector3(1.6 * c, 1.0 * c, 0.9 * c),
                Vector3(0.3, 0, 0),
                0.3,
            )
        )
    return zones^


def _linear(byte: UInt8) -> Float32:
    """Return an sRGB byte as linear light, near enough."""
    return (Float32(byte) / 255) ** Float32(2.2)


def _painted(var brow: SweepField) -> SweepField:
    """Return a brow as deep as it is tall, so the skin under all of it
    lies inside it."""
    for index in range(len(brow.sweeps[0].stations)):  # pragma: no branch
        brow.sweeps[0].stations[index].ap = brow.sweeps[0].stations[index].ml
    return brow^


struct _Brows(Movable):
    """The brows' hair, painted into the skin under them: the hair's
    color over the skin's, patchy as sparse hairs are."""

    var right: SweepField
    var left: SweepField
    var factor: Vector3
    var edge: Float32
    var grain: Float32
    # The box both brows lie in, out to their soft edge. A point outside
    # it takes no hair, and costs no sweep.
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: HeadMuscleDimensions) raises:
        """Find the brows and the color their hair gives the skin.

        Args:
            dimensions: The head the brows lie on.

        Raises:
            Error: If the genome or the brows are refused.
        """
        self.right = _painted(head_hair_field(dimensions, EYEBROWS, RIGHT))
        self.left = _painted(head_hair_field(dimensions, EYEBROWS, LEFT))
        var genome = dimensions.head.torso.genome
        var skin = skin_tone(genome)
        var hair = hair_tone(genome)
        self.factor = Vector3(
            min(Float32(1.5), _linear(hair.r) / _linear(skin.r)),
            min(Float32(1.5), _linear(hair.g) / _linear(skin.g)),
            min(Float32(1.5), _linear(hair.b) / _linear(skin.b)),
        )
        self.edge = dimensions.head.cm(0.12)
        self.grain = dimensions.head.cm(0.12)
        var pad = Vector3(self.edge, self.edge, self.edge)
        self.low = (
            Vector3(
                min(self.right.low.x, self.left.low.x),
                min(self.right.low.y, self.left.low.y),
                min(self.right.low.z, self.left.low.z),
            )
            - pad
        )
        self.high = (
            Vector3(
                max(self.right.high.x, self.left.high.x),
                max(self.right.high.y, self.left.high.y),
                max(self.right.high.z, self.left.high.z),
            )
            + pad
        )

    def weight(self, point: Vector3) -> Float32:
        """Return how much of the hair's color a point takes."""
        if (
            point.y < self.low.y
            or point.y > self.high.y
            or point.z < self.low.z
            or point.x < self.low.x
            or point.x > self.high.x
        ):
            return 0
        var d = min(self.right.distance(point), self.left.distance(point))
        if d > self.edge:
            return 0
        var cover = 1 - smoothstep(-self.edge, self.edge, d)
        # Each hair is a streak: a hashed shade on a fine lattice.
        var qx = Int((point.x / self.grain) * 3)
        var qy = Int(point.y / self.grain)
        var h = UInt32(qx) * 374761393 + UInt32(qy) * 668265263
        h = (h ^ (h >> 13)) * 1274126177
        var hair = Float32(0.55) + Float32(0.4) * Float32(h & 0xFF) / 255
        return cover * hair


def tint_head_skin(
    mut geometry: BufferGeometry, dimensions: HeadMuscleDimensions
) raises:
    """Write the face's zones of color into a skin mesh.

    The lips take their own color over whatever else is under them;
    every other zone multiplies what is there.

    It also writes the `THINNESS` attribute, one float a vertex, that
    `skin_scatter` reads.

    Args:
        geometry: A skin mesh in the pelvis frame, with `position`. Its
            `color` attribute is written, three linear floats a vertex.
        dimensions: The head the mesh covers.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or the mesh has
            no `position` attribute.
    """
    dimensions.validate()
    var zones = _zones(dimensions.head)
    var thin = _thin_zones(dimensions.head)
    var lids = EyeLids(dimensions.head)
    var brows = _Brows(dimensions)
    ref positions = geometry.attribute_view(String(POSITION))
    var count = positions.count()
    var colors = List[Float32](capacity=count * 3)
    var thinness = List[Float32](capacity=count)
    for index in range(count):  # pragma: no branch
        var p = positions.vector3(index)
        var through = Float32(0)
        for z in range(len(thin)):  # pragma: no branch
            through = max(through, thin[z].factor.x * thin[z].weight(p))
        thinness.append(through)
        var color = Vector3(1, 1, 1)
        for z in range(len(zones)):  # pragma: no branch
            var w = zones[z].weight(p)
            if w <= 0:
                continue
            var f = zones[z].factor
            if z < 2:
                color = _mix(color, f, w)
            else:
                color = Vector3(
                    color.x * (1 + (f.x - 1) * w),
                    color.y * (1 + (f.y - 1) * w),
                    color.z * (1 + (f.z - 1) * w),
                )
        color = _mix(color, brows.factor, brows.weight(p))
        var lash = _lash_line(lids, p)
        if lash > 0:
            color = color * (1 - Float32(0.8) * lash)
        colors.append(color.x)
        colors.append(color.y)
        colors.append(color.z)
    geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    geometry.set_attribute(String(THINNESS), BufferAttribute(thinness^, 1))


def untinted(mut geometry: BufferGeometry) raises:
    """Give a skin mesh a `color` attribute of plain white.

    A material with vertex colors needs the attribute on every mesh it
    paints; a skin with no zones of color then keeps its albedo.

    Args:
        geometry: A mesh with `position`.

    Raises:
        Error: If the mesh has no `position` attribute.
    """
    var count = geometry.attribute_view(String(POSITION)).count()
    var colors = List[Float32](length=count * 3, fill=1)
    geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
