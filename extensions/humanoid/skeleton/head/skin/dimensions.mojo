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

from extensions.humanoid.genome import EAR_LOBE, EAR_PROTRUSION, EAR_SIZE
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.skeleton.field import (
    DistanceField,
    field_gradient,
    sd_ellipsoid,
    sd_sphere,
    smax,
    smin,
)
from extensions.humanoid.skeleton.head.eyes import eye_center, eye_radius
from extensions.humanoid.skeleton.head.frame import (
    HeadDimensions,
    HeadMuscleDimensions,
)
from extensions.humanoid.skeleton.sculpt import Sculpt
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


def _ear_point(
    h: HeadDimensions,
    side: Float32,
    frame: EarFrame,
    s: Float32,
    t: Float32,
    n: Float32,
) -> Vector3:
    """Return a point of one ear, authored in the ear's own plane.

    `s` runs back along the ear, `t` up it and `n` out of its face, in
    template cm from the root in front of the ear canal.
    """
    var local = frame.root + frame.back * (s * frame.size) + frame.up * (
        t * frame.size
    ) + frame.out * (n * frame.size)
    return h.at(side * local.x, local.y, local.z)


@fieldwise_init
struct EarFrame(ImplicitlyCopyable):
    """The plane of the right ear, in template cm: its root, the unit
    directions back, up and out of it, and its size factor."""

    var root: Vector3
    var back: Vector3
    var up: Vector3
    var out: Vector3
    var size: Float32


def ear_frame(size: Float32, protrusion: Float32) -> EarFrame:
    """Return the right ear's plane for two gene expressions.

    The ear leans back about fifteen degrees at the top, and its back
    edge stands out from the head by about twenty degrees, more as
    `protrusion` rises.

    Args:
        size: The `EAR_SIZE` expression.
        protrusion: The `EAR_PROTRUSION` expression.

    Returns:
        The frame.
    """
    var flare = Float32(0.36) + Float32(0.2) * protrusion
    var out = Vector3(cos(flare), 0, sin(flare))
    var back = Vector3(sin(flare), 0, -cos(flare))
    var lean = Float32(0.26)
    var up = Vector3(0, cos(lean), 0) + back * sin(lean)
    back = back * cos(lean) - Vector3(0, sin(lean), 0)
    return EarFrame(
        Vector3(7.35, 71.3, -0.6),
        back,
        up,
        out,
        1 + Float32(0.16) * size,
    )


def _ear(
    h: HeadDimensions,
    mut clay: Sculpt,
    side: Float32,
    frame: EarFrame,
    lobe: Float32,
):
    """Add one ear: the helix's rim round a thin plate, the antihelix,
    the tragus, the lobe, the root, and the concha and the canal carved
    into it."""
    var k = h.cm(1) * frame.size
    # The plate: the auricle's body.
    clay.ellipsoid(
        _ear_point(h, side, frame, 1.3, 0.3, -0.05),
        Vector3(1.25 * k, 2.75 * k, 0.36 * k),
        _ear_point(h, side, frame, 1.3, 0.3, 1.0)
        - _ear_point(h, side, frame, 1.3, 0.3, 0.0),
        _ear_point(h, side, frame, 1.3, 1.3, 0.0)
        - _ear_point(h, side, frame, 1.3, 0.3, 0.0),
    )
    # The helix: a rolled rim from the crus over the top and down the
    # back to the lobe.
    var rim: List[Float32] = [
        0.35, 1.2, 0.3,
        0.45, 2.3, 0.3,
        1.1, 3.05, 0.3,
        2.0, 2.95, 0.25,
        2.6, 2.2, 0.2,
        2.8, 1.0, 0.1,
        2.7, -0.3, 0.0,
        2.35, -1.3, 0.0,
        1.8, -2.0, 0.0,
    ]
    var points = List[Vector3]()
    var radii = List[Float32]()
    for index in range(len(rim) // 3):  # pragma: no branch
        points.append(
            _ear_point(h, side, frame, rim[index * 3], rim[index * 3 + 1], rim[index * 3 + 2])
        )
        radii.append(0.34 * k if index > 0 else 0.26 * k)
    clay.chain(points, radii)
    # The antihelix: a lower ridge inside the rim, forked at the top.
    var ridge: List[Float32] = [
        0.9, 2.2, 0.28,
        1.6, 1.4, 0.3,
        1.9, 0.3, 0.3,
        1.6, -0.8, 0.28,
        1.1, -1.4, 0.25,
    ]
    points = List[Vector3]()
    radii = List[Float32]()
    for index in range(len(ridge) // 3):  # pragma: no branch
        points.append(
            _ear_point(h, side, frame, ridge[index * 3], ridge[index * 3 + 1], ridge[index * 3 + 2])
        )
        radii.append(0.26 * k)
    clay.chain(points, radii)
    # The tragus, in front of the canal.
    clay.ellipsoid(
        _ear_point(h, side, frame, 0.0, -0.35, 0.35),
        Vector3(0.32 * k, 0.45 * k, 0.3 * k),
    )
    # The lobe: free and full, or small and attached.
    var hang = Float32(0.35) * lobe
    clay.ellipsoid(
        _ear_point(h, side, frame, 1.05 + 0.1 * lobe, -2.3 - hang, 0.0),
        Vector3((0.72 + 0.12 * lobe) * k, (0.72 + 0.15 * lobe) * k, 0.3 * k),
    )
    # The root, where the ear's front joins the side of the head.
    clay.ellipsoid(
        _ear_point(h, side, frame, 0.15, 0.2, -0.7),
        Vector3(0.7 * k, 2.2 * k, 0.8 * k),
    )
    # The concha, the bowl in front of the antihelix, and the canal at
    # its floor; the scaphoid fossa inside the helix.
    clay.hollow_ellipsoid(
        _ear_point(h, side, frame, 0.95, -0.25, 0.5),
        Vector3(0.72 * k, 1.0 * k, 0.4 * k),
    )
    clay.hollow_ellipsoid(
        _ear_point(h, side, frame, 0.45, -0.35, 0.0),
        Vector3(0.28 * k, 0.32 * k, 0.6 * k),
    )
    clay.hollow_capsule(
        _ear_point(h, side, frame, 1.2, 2.55, 0.42),
        _ear_point(h, side, frame, 2.3, 0.8, 0.4),
        0.26 * k,
        0.22 * k,
    )


struct HeadSkinField(Copyable, DistanceField, Movable):
    """The outer skin surface of the neck and the head."""

    var dermis: Float32
    var center: Vector3
    var radii: Vector3
    # The neck and the back of the head, as sections along curves.
    var neck: SweepField
    # The face's mask, and the heights it is cut off at.
    var mask: SweepField
    var mask_top: Float32
    var mask_bottom: Float32
    var mask_soft: Float32
    # The face's broad forms, with the eye sockets carved out.
    var face: Sculpt
    # The nose and the lips, with the nostrils and the mouth carved.
    var features: Sculpt
    # The two ears.
    var ears: Sculpt
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
        var genome = h.torso.genome
        var lobe = genome.get(EAR_LOBE)
        self.lids = EyeLids(h)
        self.dermis = HEAD_DERMIS
        self.epsilon = f.cm(0.15)
        self.blend = f.cm(1.2)
        self.fine = f.cm(0.3)
        self.center = h.at(0, 75.1, -1.0)
        self.radii = h.cranium(8.1, 9.3, 10.6)
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
        # The face's mask, from the brow down to the chin: each section
        # is x, y and z of its center, and its half-width and half-depth,
        # in template cm. A sweep's ends are round and long, so two soft
        # planes cut the mask off above the brow and under the chin.
        var mask = List[Sweep]()
        # fmt: off
        mask.append(_through(h, x, floats(
            0, 77.5, 1.7, 6.8, 7.2,
            0, 74.6, 2.4, 7.0, 7.0,
            0, 72.1, 2.8, 7.05, 6.1,
            0, 70.3, 3.0, 7.0, 5.7,
            0, 68.0, 2.8, 6.3, 6.1,
            0, 66.0, 2.3, 5.8, 6.6,
            0, 64.2, 2.1, 5.4, 6.7,
            0, 62.6, 2.4, 4.6, 6.4,
            0, 60.6, 2.9, 3.4, 5.6,
        )))
        # fmt: on
        self.mask = SweepField(
            mask^, List[Dome](), RIGHT, self.blend, f.cm(0.05), f.cm(1.0)
        )
        self.mask_top = h.at(0, 76.5, 0).y
        self.mask_bottom = h.at(0, 60.2, 0).y
        self.mask_soft = f.cm(1.4)
        # The space under the chin, in front of the throat.
        self.neck.cut(_through(h, x, floats(0, 55.0, 10.0, 5.0, 4.8)))
        self.face = Sculpt(f.cm(1.5), f.cm(0.5))
        self.features = Sculpt(f.cm(0.3), f.cm(0.12))
        self.ears = Sculpt(f.cm(0.16), f.cm(0.1))
        var c = h.cm(1)
        for s in range(2):  # pragma: no branch
            var side = Float32(1) - Float32(2 * s)
            _face_side(h, self.face, side, eye)
            _nose_side(h, self.features, side)
            _mouth_side(h, self.features, side, lip)
            _ear(
                h,
                self.ears,
                side,
                ear_frame(genome.get(EAR_SIZE), genome.get(EAR_PROTRUSION)),
                lobe,
            )
        # The forehead, broad and flat across, over the frontalis.
        self.face.ellipsoid(h.at(0, 78.3, 2.4), Vector3(8.0 * c, 4.8 * c, 7.0 * c))
        # The middle of the face: the glabella and the chin.
        self.face.ellipsoid(h.at(0, 74.3, 8.4), Vector3(1.6 * c, 1.0 * c, 1.0 * c))
        self.face.ellipsoid(h.at(0, 61.2, 7.5), Vector3(1.9 * c, 1.25 * c, 1.5 * c))
        # The nose's middle: the bridge down to the tip, the tip, and
        # the columella under it.
        var bridge = List[Vector3]()
        bridge.append(h.at(0, 73.4, 9.05))
        bridge.append(h.at(0, 71.8, 9.5))
        bridge.append(h.at(0, 70.2, 10.05))
        bridge.append(h.at(0, 69.3, 10.4))
        var widths: List[Float32] = [0.6 * c, 0.58 * c, 0.6 * c, 0.64 * c]
        self.features.chain(bridge, widths)
        self.features.ellipsoid(
            h.at(0, 68.9, 10.25), Vector3(0.85 * c, 0.75 * c, 0.78 * c)
        )
        # The base of the nose, joining the tip to the wings.
        self.features.ellipsoid(
            h.at(0, 68.45, 9.8), Vector3(1.15 * c, 0.62 * c, 0.75 * c)
        )
        self.features.capsule(
            h.at(0, 68.3, 10.3), h.at(0, 67.7, 9.45), 0.26 * c, 0.28 * c
        )
        # The lips' middle: the tubercle of the upper lip, and the
        # philtrum's groove above it.
        self.features.ellipsoid(
            h.at(0, 65.0, 9.5), Vector3(0.45 * c, 0.36 * lip * c, 0.4 * lip * c)
        )
        self.features.hollow_ellipsoid(
            h.at(0, 66.35, 9.6), Vector3(0.28 * c, 0.75 * c, 0.2 * c)
        )
        # The line where the lips meet.
        self.features.hollow_ellipsoid(
            h.at(0, 64.8, 9.9), Vector3(2.2 * c, 0.05 * c, 0.55 * c)
        )
        # The fold under the lower lip.
        self.features.hollow_capsule(
            h.at(-1.3, 63.35, 9.25), h.at(1.3, 63.35, 9.25), 0.2 * c, 0.2 * c
        )
        if h.sex == MALE:
            # The laryngeal prominence.
            self.features.ellipsoid(
                h.at(0, 57.9, 4.9), Vector3(0.7 * c, 0.9 * c, 0.7 * c)
            )
        self.low = Vector3(
            min(self.neck.low.x, self.ears.low.x),
            min(self.neck.low.y, self.center.y - self.radii.y),
            min(self.neck.low.z, self.center.z - self.radii.z),
        )
        self.high = Vector3(
            max(self.neck.high.x, self.ears.high.x),
            max(self.neck.high.y, self.center.y + self.radii.y),
            max(self.features.high.z, self.face.high.z),
        )

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the outer surface of the neck and the head.

        Negative is inside. Zero is the surface.
        """
        var d = smin(
            sd_ellipsoid(point, self.center, self.radii),
            self.neck.distance(point),
            self.blend,
        )
        var mask = smax(
            smax(
                self.mask.distance(point),
                point.y - self.mask_top,
                self.mask_soft,
            ),
            self.mask_bottom - point.y,
            self.fine,
        )
        d = smin(d, mask, self.blend)
        d = smin(d, self.face.union(point), self.face.blend)
        d = self.face.carved(d, point)
        d = smin(d, self.features.union(point), self.fine)
        d = self.features.carved(d, point)
        d = smin(d, self.ears.union(point), self.ears.blend)
        d = self.ears.carved(d, point)
        return smin(d, self.lids.distance(point), self.lids.blend)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def _face_side(h: HeadDimensions, mut clay: Sculpt, side: Float32, eye: Float32):
    """Add one side's broad forms of the face, and carve its eye
    socket."""
    var c = h.cm(1)
    # The brow over the orbit, from the temple to the glabella.
    var brow = List[Vector3]()
    brow.append(h.at(side * 5.5, 73.9, 6.3))
    brow.append(h.at(side * 3.4, 74.5, 8.6))
    brow.append(h.at(side * 1.3, 74.3, 9.25))
    var brow_r: List[Float32] = [0.7 * c, 0.85 * c, 0.8 * c]
    clay.chain(brow, brow_r)
    # The cheekbone's mound and its arch back to the ear.
    clay.ellipsoid(
        h.at(side * 4.8, 70.3, 5.6),
        Vector3(1.9 * c, 1.3 * c, 2.0 * c),
        Vector3(side * 0.4, 0, 1),
    )
    clay.capsule(
        h.at(side * 5.7, 70.7, 4.4), h.at(side * 7.0, 71.0, 0.6), 0.9 * c, 0.75 * c
    )
    # The temple, over the temporalis.
    clay.ellipsoid(
        h.at(side * 6.75, 77.8, 0.5), Vector3(1.3 * c, 3.4 * c, 4.5 * c)
    )
    # The side of the orbit, round the outer corner of the eye.
    clay.ellipsoid(
        h.at(side * 5.4, 72.6, 6.9), Vector3(1.2 * c, 1.8 * c, 1.3 * c)
    )
    # The side of the face, over the masseter.
    clay.ellipsoid(
        h.at(side * 5.6, 66.2, 1.8), Vector3(1.3 * c, 2.6 * c, 2.4 * c)
    )
    # The line of the jaw, from its angle under to the chin, over the
    # floor of the mouth.
    var under = List[Vector3]()
    under.append(h.at(side * 5.2, 63.3, -0.4))
    under.append(h.at(side * 4.2, 61.5, 3.2))
    under.append(h.at(side * 2.3, 60.8, 5.8))
    under.append(h.at(side * 0.4, 60.6, 6.8))
    var under_r: List[Float32] = [0.95 * c, 0.95 * c, 0.9 * c, 0.9 * c]
    clay.chain(under, under_r)
    # The cheek's soft mass between the cheekbone and the jaw.
    clay.ellipsoid(
        h.at(side * 4.4, 66.6, 5.4), Vector3(1.8 * c, 2.1 * c, 2.0 * c)
    )
    # The angle of the jaw, under the ear.
    clay.ellipsoid(
        h.at(side * 5.2, 63.9, -0.2), Vector3(0.9 * c, 1.2 * c, 1.4 * c)
    )
    # The eye socket, where the lids sit.
    clay.hollow_ellipsoid(
        h.at(side * 3.35, 72.05, 9.3), Vector3(1.5 * eye * c, 1.0 * eye * c, 1.2 * c)
    )


def _nose_side(h: HeadDimensions, mut clay: Sculpt, side: Float32):
    """Add one side of the nose: the wing round the nostril, the side
    wall up to the bridge, and the nostril carved out."""
    var c = h.cm(1)
    clay.ellipsoid(
        h.at(side * 1.0, 68.35, 9.55),
        Vector3(0.5 * c, 0.48 * c, 0.7 * c),
        Vector3(side * 0.35, 0, 1),
    )
    clay.ellipsoid(
        h.at(side * 0.85, 70.3, 9.25), Vector3(0.55 * c, 1.7 * c, 0.75 * c)
    )
    clay.hollow_ellipsoid(
        h.at(side * 0.55, 67.85, 9.85),
        Vector3(0.3 * c, 0.18 * c, 0.5 * c),
        Vector3(side * 0.25, -0.35, 1),
    )


def _mouth_side(h: HeadDimensions, mut clay: Sculpt, side: Float32, lip: Float32):
    """Add one side of the lips: the upper lip's roll with its bow and
    the lower lip's fuller roll."""
    var c = h.cm(1)
    var upper = List[Vector3]()
    upper.append(h.at(side * 2.35, 64.9, 8.15))
    upper.append(h.at(side * 1.55, 65.1, 8.95))
    upper.append(h.at(side * 0.6, 65.25, 9.45))
    upper.append(h.at(side * 0.15, 65.12, 9.5))
    var upper_r: List[Float32] = [
        0.16 * c,
        0.38 * lip * c,
        0.42 * lip * c,
        0.4 * lip * c,
    ]
    clay.chain(upper, upper_r)
    var lower = List[Vector3]()
    lower.append(h.at(side * 2.3, 64.72, 8.15))
    lower.append(h.at(side * 1.5, 64.42, 8.9))
    lower.append(h.at(side * 0.55, 64.3, 9.3))
    lower.append(h.at(side * 0.05, 64.3, 9.35))
    var lower_r: List[Float32] = [
        0.16 * c,
        0.45 * lip * c,
        0.54 * lip * c,
        0.54 * lip * c,
    ]
    clay.chain(lower, lower_r)


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
