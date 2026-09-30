# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The skin of the neck and the head: a scanned head fitted over the
modeled anatomy.

The face is the face model's mean head, learned from scans of real
faces and placed on the template (see `scan`). It carries the eyelids,
the lips, the nostrils and the ears that a sculpt of even solids makes
look like a doll's. Two modeled solids join it in a smooth union. The
vault is an ellipsoid a scalp's thickness outside the skull, so the
skull stays inside whatever the scan's shape. The neck is swept round
its muscles, with the sternocleidomastoid's ridges and the trapezius's
slope, down to where the body's skin takes over. A separate shell
represents the dermis for occupancy and mass.

    var dims = head_muscle_dimensions(person)
    var d = head_skin_distance(dims, Vector3(0, 0.84, 0))
"""

from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.skeleton.field import (
    Bounds,
    DistanceField,
    field_gradient,
    sd_ellipsoid,
    smax,
    smin,
)
from extensions.humanoid.skeleton.head.eyes import eye_center, eye_radius
from extensions.humanoid.skeleton.head.frame import (
    HeadDimensions,
    HeadMuscleDimensions,
)
from extensions.humanoid.skeleton.head.skin.scan import (
    FIT_MARGIN,
    SCAN_BLEND,
    ScannedHead,
    scan_model,
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
comptime LID_GAP = Float32(0.04)
comptime LID_THICKNESS = Float32(0.3)
comptime SLIT_WIDTH = Float32(1.35)
comptime SLIT_HEIGHT = Float32(0.47)


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
    var back: Float32

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
        self.blend = h.cm(0.15)
        self.back = h.cm(0.2) * scale

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
        # Only the front of the eyeball has lids: behind its equator
        # the orbit's fat and the face hold it.
        var shell = max(
            max(far - self.outer, self.inner - far), self.back - d.z
        )
        # The slit, in the eye's own tilted frame: x toward the outer
        # corner, y up. The lower lid sits a little lower than the
        # upper lid is high, and the inner corner is lower than the
        # outer one on the template.
        var ox = d.x * side
        var qx = ox * self.cos_tilt - d.y * self.sin_tilt
        var qy = ox * self.sin_tilt + d.y * self.cos_tilt
        qy = qy + self.height * Float32(0.1) - qx * Float32(0.06)
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


struct HeadHull(Copyable, DistanceField, Movable):
    """The modeled solids the skin must cover: the vault and the neck.

    The vault is an ellipsoid a scalp's thickness outside the skull,
    cut away in front of a plane through the brow so it cannot fill the
    face. The neck is swept round its muscles, from its base up to the
    back of the skull, with the sternocleidomastoid's ridges and the
    trapezius's slope.
    """

    var center: Vector3
    var radii: Vector3
    var brow: Vector3
    var facing: Vector3
    var neck: SweepField
    var blend: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, h: HeadDimensions) raises:
        """Model the vault and the neck of `h`.

        Args:
            h: Head landmarks.

        Raises:
            Error: If a sweep refuses its sections.
        """
        var f = h.frame
        self.blend = f.cm(1.2)
        # The scan is fitted a margin outside the vault, so the vault is
        # that much smaller than the skin over it.
        self.center = h.at(0, 75.1, -1.0)
        self.radii = h.cranium(
            8.1 - FIT_MARGIN, 9.3 - FIT_MARGIN, 10.6 - FIT_MARGIN
        )
        self.brow = h.at(0, 77.5, 8.0)
        self.facing = Vector3(0, -1, 1.2)
        self.facing.normalize()
        var x = Vector3(1, 0, 0)
        var sweeps = List[Sweep]()
        # fmt: off
        # The neck, from its base up to the back of the skull.
        sweeps.append(_through(h, x, floats(
            0, 50.5, -2.3, 6.4, 7.2,
            0, 54.0, -2.2, 5.8, 7.1,
            0, 58.0, -2.0, 5.5, 7.0,
            0, 62.0, -2.4, 5.4, 7.3,
            0, 66.0, -2.8, 5.6, 7.4,
        )))
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
        self.neck = SweepField(
            sweeps^, List[Dome](), RIGHT, self.blend, f.cm(0.05), f.cm(1.0)
        )
        # The space under the chin, in front of the throat.
        self.neck.cut(_through(h, x, floats(0, 55.0, 10.0, 5.0, 4.8)))
        self.low = Vector3(
            self.neck.low.x,
            min(self.neck.low.y, self.center.y - self.radii.y),
            min(self.neck.low.z, self.center.z - self.radii.z),
        )
        self.high = Vector3(
            self.neck.high.x,
            self.center.y + self.radii.y,
            self.neck.high.z,
        )

    def vault(self, point: Vector3) -> Float32:
        """Return the distance to the vault, in meters."""
        return smax(
            sd_ellipsoid(point, self.center, self.radii),
            (point - self.brow).dot(self.facing),
            self.blend,
        )

    def distance(self, point: Vector3) -> Float32:
        """Return the distance to the vault and the neck, in meters,
        negative inside."""
        return smin(self.vault(point), self.neck.distance(point), self.blend)


struct HeadSkinField(Copyable, DistanceField, Movable):
    """The outer skin surface of the neck and the head."""

    var dermis: Float32
    # The vault and the neck the skin must cover.
    var hull: HeadHull
    # The scanned head, fitted over the hull, and the box round its ears.
    var scan: ScannedHead
    var ears: Bounds
    var fine: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: HeadMuscleDimensions) raises:
        """Fit the skin over the modeled neck and head.

        Args:
            dimensions: Head landmarks and the muscles' radius scale.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or the
                face model cannot be read.
        """
        dimensions.validate()
        var h = dimensions.head.copy()
        var f = h.frame
        self.dermis = HEAD_DERMIS
        self.epsilon = f.cm(0.15)
        self.fine = f.cm(SCAN_BLEND)
        self.hull = HeadHull(h)
        self.scan = ScannedHead(h, scan_model(), self.hull)
        self.ears = self.scan.ears
        self.low = Vector3(
            min(self.hull.low.x, self.scan.low.x),
            min(self.hull.low.y, self.scan.low.y),
            min(self.hull.low.z, self.scan.low.z),
        )
        self.high = Vector3(
            max(self.hull.high.x, self.scan.high.x),
            max(self.hull.high.y, self.scan.high.y),
            max(self.hull.high.z, self.scan.high.z),
        )

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the outer surface of the neck and the head.

        Negative is inside. Zero is the surface.
        """
        var d = self.hull.distance(point)
        # Off the scan's box, the scan cannot change the surface, and
        # searching its mesh costs the most.
        if self.scan.bound(point) > d + self.fine:
            return d
        return smin(d, self.scan.distance(point), self.fine)

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
