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

from extensions.humanoid.side import RIGHT
from extensions.humanoid.skeleton.field import (
    DistanceField,
    field_gradient,
    sd_ellipsoid,
    smin,
)
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
from std.math import max, min

comptime HEAD_DERMIS = Float32(0.0015)


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
        self.dermis = HEAD_DERMIS
        self.epsilon = f.cm(0.15)
        self.blend = f.cm(1.2)
        self.fine = f.cm(0.35)
        self.center = h.at(0, 75.1, -1.0)
        self.radii = Vector3(h.cm(8.1) * f.wide, h.cm(9.3), h.cm(10.6) * f.deep)
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
                _through(h, x, floats(side * 3.2, 72.1, 9.6, 1.9, 1.9))
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
        small.append(_through(h, up, floats(
            2.3, 65.0, 8.5, 0.45, 0.45,
            1.1, 65.2, 9.3, 0.45, 0.45,
            0, 65.1, 9.6, 0.45, 0.45,
            -1.1, 65.2, 9.3, 0.45, 0.45,
            -2.3, 65.0, 8.5, 0.45, 0.45,
        )))
        small.append(_through(h, up, floats(
            2.1, 64.4, 8.5, 0.5, 0.5,
            1.0, 64.1, 9.2, 0.5, 0.5,
            0, 64.0, 9.35, 0.5, 0.5,
            -1.0, 64.1, 9.2, 0.5, 0.5,
            -2.1, 64.4, 8.5, 0.5, 0.5,
        )))
        _mirrored(h, small, x, floats(3.2, 72.0, 7.3, 1.15, 1.15))
        _mirrored(h, small, up, floats(
            5.0, 74.2, 7.2, 0.4, 0.4,
            2.5, 74.6, 8.9, 0.4, 0.4,
            0.6, 74.3, 9.2, 0.35, 0.35,
        ))
        small.append(_through(h, x, floats(0, 57.9, 4.9, 0.7, 0.7)))
        small.append(_through(h, x, floats(0, 61.4, 8.2, 1.5, 0.9)))
        # Each ear: a thin plate tilted back at the top, with a lobe.
        _mirrored(h, small, x, floats(
            7.9, 74.3, -2.0, 0.3, 1.0,
            8.3, 72.3, -1.6, 0.35, 1.7,
            8.2, 70.2, -1.1, 0.35, 1.3,
            7.9, 68.6, -0.7, 0.4, 0.6,
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
        return smin(d, self.details.distance(point), self.fine)

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
