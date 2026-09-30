# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The skin of the neck and the head, sculpted over the modeled
anatomy.

The torso's and the limbs' skins are lofts of convex sections round
their anatomy. A face is not convex: the eyes sit in sockets, the nose
and the lips stand out, and the chin overhangs the throat. So the head's
skin is authored as a smooth union of solids in template centimeters,
as the anatomy is. The cranium is an ellipsoid a scalp's thickness
outside the vault. A broad blend joins it to the face, the jaw, the
cheekbones and the neck, with the sternocleidomastoid's ridges; cuts
take out the eye sockets and the space under the chin. A tight blend
adds the nose, the lips, the eyelids, the brow, the laryngeal
prominence and the ears. A separate shell represents the dermis for
occupancy and mass.

    var dims = head_muscle_dimensions(person)
    var d = head_skin_distance(dims, Vector3(0, 0.84, 0))
"""

from extensions.humanoid.genome import EAR_LOBE
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.skeleton.field import (
    DistanceField,
    field_gradient,
    sd_ellipsoid,
    sd_sphere,
    smin,
)
from extensions.humanoid.skeleton.head.eyes import eye_center, eye_radius
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
from std.math import cos, max, min, sin, sqrt

comptime HEAD_DERMIS = Float32(0.0015)
# The lids' shell round the eyeball, in template cm: its gap to the eye
# and its thickness. The slit's half-width and half-height.
comptime LID_GAP = Float32(0.06)
comptime LID_THICKNESS = Float32(0.3)
comptime SLIT_WIDTH = Float32(1.35)
comptime SLIT_HEIGHT = Float32(0.5)


struct EyeLids(Copyable, Movable):
    """The two pairs of lids: a shell round each eyeball, cut open at
    the front in an almond-shaped slit, tilted with the eye."""

    var right: Vector3
    var left: Vector3
    var inner: Float32
    var outer: Float32
    var reach: Float32
    var width: Float32
    var height: Float32
    var cos_tilt: Float32
    var sin_tilt: Float32
    var blend: Float32

    def __init__(out self, h: HeadDimensions) raises:
        """Fit the lids to the eyes of `h`.

        Args:
            h: Head landmarks.

        Raises:
            Error: Never, for a valid `h`.
        """
        var morph = h.frame.morph
        var scale = morph.eye_scale()
        var radius = eye_radius(h)
        self.right = eye_center(h, RIGHT)
        self.left = eye_center(h, LEFT)
        self.inner = radius + h.cm(LID_GAP)
        self.outer = self.inner + h.cm(LID_THICKNESS)
        self.reach = self.outer + h.cm(0.6)
        self.width = h.cm(SLIT_WIDTH) * scale
        self.height = h.cm(SLIT_HEIGHT) * scale
        var tilt = Float32(0.13) * morph.eye_tilt
        self.cos_tilt = cos(tilt)
        self.sin_tilt = sin(tilt)
        self.blend = h.cm(0.12)

    def distance(self, point: Vector3) -> Float32:
        """Return the distance to the nearer eye's lids, in meters."""
        var center = self.right
        var side = Float32(1)
        if point.x < 0:
            center = self.left
            side = -1
        var d = point - center
        var far = d.length()
        if far > self.reach:
            return far - self.outer
        var shell = max(far - self.outer, self.inner - far)
        # The slit, in the eye's own tilted frame: x toward the outer
        # corner, y up. The lower lid sits a little lower than the
        # upper lid is high, and the inner corner is lower than the
        # outer one on the template.
        var ox = d.x * side
        var qx = ox * self.cos_tilt - d.y * self.sin_tilt
        var qy = ox * self.sin_tilt + d.y * self.cos_tilt
        qy = qy - self.height * Float32(0.12) - qx * Float32(0.06)
        # An almond: the slit narrows toward its corners.
        var across = qx / self.width
        var taper = max(Float32(0.05), 1 - across * across)
        var open = sqrt(across * across + (qy / self.height) ** 2 / taper)
        var slit = (open - 1) * self.height
        var cut = max(slit, -d.z)
        return max(shell, -cut)



def _through(h: HeadDimensions, hint: Vector3, rows: List[Float32]) -> Sweep:
    """Return a sweep through template stations `x, y, z, ml, ap`."""
    var sweep = Sweep(hint)
    for index in range(len(rows) // 5):  # pragma: no branch
        var at = index * 5
        sweep.add(
            h.at(rows[at], rows[at + 1], rows[at + 2]),
            h.cm(rows[at + 3]),
            h.cm(rows[at + 4]),
        )
    return sweep^


def _mirrored(
    h: HeadDimensions,
    mut sweeps: List[Sweep],
    hint: Vector3,
    rows: List[Float32],
):
    """Append a sweep through template stations, and its mirror on x."""
    sweeps.append(_through(h, hint, rows))
    var flipped = rows.copy()
    for index in range(len(rows) // 5):  # pragma: no branch
        flipped[index * 5] = -rows[index * 5]
    sweeps.append(_through(h, hint, flipped))


struct HeadSkinField(Copyable, DistanceField, Movable):
    """The outer skin surface of the neck and the head."""

    var dermis: Float32
    var center: Vector3
    var radii: Vector3
    var face: SweepField
    var details: SweepField
    var blend: Float32
    var fine: Float32
    var epsilon: Float32
    # The lids: a shell round each eyeball, open in an almond-shaped
    # slit at the front.
    var lids: EyeLids
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: HeadMuscleDimensions) raises:
        """Sculpt the skin over the modeled neck and head.

        Args:
            dimensions: Head landmarks and the muscles' radius scale.

        Raises:
            Error: If `dimensions.validate` refuses the copy.
        """
        dimensions.validate()
        var h = dimensions.head.copy()
        var f = h.frame
        var morph = f.morph
        var eye = morph.eye_scale()
        var lip = morph.lip_scale()
        var lobe = h.torso.genome.get(EAR_LOBE)
        self.lids = EyeLids(h)
        self.dermis = HEAD_DERMIS
        self.epsilon = f.cm(0.15)
        self.blend = f.cm(1.2)
        self.fine = f.cm(0.35)
        self.center = h.at(0, 75.1, -1.0)
        self.radii = h.cranium(8.1, 9.3, 10.6)
        var x = Vector3(1, 0, 0)
        var up = Vector3(0, 1, 0)
        var sweeps = List[Sweep]()
        # fmt: off
        # The face, from the forehead down to the chin.
        sweeps.append(_through(h, x, floats(
            0, 77.5, 1.5, 6.3, 7.2,
            0, 76.0, 2.0, 6.8, 7.1,
            0, 73.8, 2.8, 7.0, 6.6,
            0, 70.8, 3.2, 7.0, 5.6,
            0, 67.4, 2.8, 6.2, 6.1,
            0, 64.6, 2.2, 5.6, 7.0,
            0, 61.8, 2.5, 4.2, 6.3,
        )))
        # The neck, from its base up to the back of the skull.
        sweeps.append(_through(h, x, floats(
            0, 50.5, -2.3, 6.4, 7.2,
            0, 54.0, -2.2, 5.8, 7.1,
            0, 58.0, -2.0, 5.5, 7.0,
            0, 62.0, -2.4, 5.4, 7.3,
            0, 66.0, -2.8, 5.6, 7.4,
        )))
        # The jaw line, the cheekbones and the sternocleidomastoids.
        _mirrored(h, sweeps, x, floats(
            6.0, 68.8, -1.2, 0.9, 0.9,
            5.6, 63.6, 0.2, 0.9, 0.9,
            4.2, 62.1, 4.0, 0.9, 0.9,
            2.3, 61.4, 6.9, 0.9, 0.9,
        ))
        _mirrored(h, sweeps, x, floats(5.0, 70.6, 6.6, 1.4, 1.4))
        # Behind the ear, over the mastoid and the splenius.
        _mirrored(h, sweeps, x, floats(5.6, 68.0, -3.6, 1.3, 1.3))
        # The sternocleidomastoid's clavicular head.
        _mirrored(h, sweeps, x, floats(
            4.9, 58.0, 1.6, 1.0, 1.0,
            5.4, 51.0, 2.6, 1.0, 1.0,
        ))
        _mirrored(h, sweeps, x, floats(
            5.3, 68.5, -0.6, 1.3, 1.3,
            4.4, 61.5, 2.2, 1.3, 1.3,
            2.3, 52.0, 4.2, 1.1, 1.1,
        ))
        # The trapezius's slope from the back of the neck to the
        # shoulder.
        _mirrored(h, sweeps, x, floats(
            2.5, 62.0, -7.3, 1.4, 1.4,
            5.5, 56.0, -6.2, 1.9, 1.9,
            8.5, 55.2, -5.2, 1.9, 1.9,
            7.0, 53.5, -6.6, 1.9, 1.9,
            10.0, 53.0, -4.0, 1.6, 1.6,
            13.5, 51.8, -1.5, 1.3, 1.3,
        ))
        # fmt: on
        self.face = SweepField(
            sweeps^, List[Dome](), RIGHT, self.blend, f.cm(0.05), f.cm(1.0)
        )
        # The eye sockets, and the space under the chin in front of the
        # throat.
        for s in range(2):  # pragma: no branch
            var side = Float32(1) - Float32(2 * s)
            self.face.cut(
                _through(
                    h, x, floats(side * 3.2, 72.1, 9.6, 1.9 * eye, 1.9 * eye)
                )
            )
        self.face.cut(_through(h, x, floats(0, 55.0, 9.5, 5.0, 4.8)))
        var small = List[Sweep]()
        # fmt: off
        # The nose: its bridge, its tip and the two wings.
        small.append(_through(h, x, floats(
            0, 73.0, 9.2, 0.55, 0.5,
            0, 70.5, 9.9, 0.75, 0.6,
            0, 68.7, 10.5, 0.95, 0.8,
        )))
        _mirrored(h, small, x, floats(1.2, 68.2, 9.6, 0.65, 0.55))
        # The lips, the eyelids, the brow and the laryngeal prominence.
        var ul = 0.45 * lip
        var ll = 0.5 * lip
        small.append(_through(h, up, floats(
            2.3, 65.0, 8.5, 0.3 * lip, 0.3 * lip,
            1.1, 65.2, 9.3, ul, ul,
            0.35, 65.25, 9.55, ul, ul,
            0, 65.1, 9.6, ul * 0.9, ul * 0.9,
            -0.35, 65.25, 9.55, ul, ul,
            -1.1, 65.2, 9.3, ul, ul,
            -2.3, 65.0, 8.5, 0.3 * lip, 0.3 * lip,
        )))
        small.append(_through(h, up, floats(
            2.1, 64.4, 8.5, 0.3 * lip, 0.3 * lip,
            1.0, 64.1, 9.2, ll, ll,
            0, 64.0, 9.35, ll, ll,
            -1.0, 64.1, 9.2, ll, ll,
            -2.1, 64.4, 8.5, 0.3 * lip, 0.3 * lip,
        )))
        _mirrored(h, small, up, floats(
            5.0, 74.2, 7.2, 0.4, 0.4,
            2.5, 74.6, 8.9, 0.4, 0.4,
            0.6, 74.3, 9.2, 0.35, 0.35,
        ))
        small.append(_through(h, x, floats(0, 57.9, 4.9, 0.7, 0.7)))
        small.append(_through(h, x, floats(0, 61.4, 8.2, 1.5, 0.9)))
        # Each ear: a thin plate tilted back at the top, with a lobe.
        # A free lobe hangs lower and fuller; an attached one is small
        # and joins the cheek.
        var drop = 0.5 * lobe
        _mirrored(h, small, x, floats(
            7.9, 74.3, -2.0, 0.3, 1.0,
            8.3, 72.3, -1.6, 0.35, 1.7,
            8.2, 70.2, -1.1, 0.35, 1.3,
            7.9 - 0.2 * lobe, 68.6 - drop, -0.7, 0.4 + 0.08 * lobe,
            0.6 + 0.15 * lobe,
        ))
        # fmt: on
        self.details = SweepField(
            small^, List[Dome](), RIGHT, self.fine, f.cm(0.05), f.cm(0.4)
        )
        self.low = Vector3(
            min(self.face.low.x, self.details.low.x),
            min(self.face.low.y, self.center.y - self.radii.y),
            min(self.face.low.z, self.center.z - self.radii.z),
        )
        self.high = Vector3(
            max(self.face.high.x, self.details.high.x),
            max(self.face.high.y, self.center.y + self.radii.y),
            max(self.face.high.z, self.details.high.z),
        )

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the outer surface of the neck and the head.

        Negative is inside. Zero is the surface.
        """
        var d = smin(
            sd_ellipsoid(point, self.center, self.radii),
            self.face.distance(point),
            self.blend,
        )
        d = smin(d, self.details.distance(point), self.fine)
        return smin(d, self.lids.distance(point), self.lids.blend)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


struct HeadSkinLayerField(Copyable, DistanceField, Movable):
    """The dermal shell immediately inside a `HeadSkinField`."""

    var outer: HeadSkinField
    var thickness: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: HeadMuscleDimensions) raises:
        """Build the dermal shell of the neck and the head.

        Args:
            dimensions: Head landmarks and the muscles' radius scale.

        Raises:
            Error: If the outer field refuses its inputs.
        """
        self.outer = HeadSkinField(dimensions)
        self.thickness = self.outer.dermis
        self.low = self.outer.low
        self.high = self.outer.high

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the dermal shell, in meters.

        Negative is inside the dermis. Deep anatomy and exterior space
        are both outside this shell.
        """
        var d = self.outer.distance(point)
        return max(d, -d - self.thickness)


def head_skin_distance(
    dimensions: HeadMuscleDimensions, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside the head's skin, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return HeadSkinField(dimensions).distance(point)
