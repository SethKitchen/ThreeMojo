# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The shape a scalp's hair takes when its shell is drawn alone.

A designed style lies close on the scalp, and its guide strands are what
falls, ties and coils. A game humanoid with no strands draws only the
shell, so every designed style looked the same there: cropped close.
`HairSilhouette` gives such a shell its style's shape. A bob, long hair
and a half-up fall to the jaw, as long grown hair does, and slicked hair
to the nape. Long hair also hangs down the back. A bun, a topknot or a
pair of space buns is a ball out from each tie. A ponytail, a high
ponytail, a braid, twin braids and pigtails hang from their ties as
tapered tails. A style that is not designed keeps the
shell it has.

    var hair = HairSilhouette(dimensions, skin, BUN)
    var d = hair.distance(point)

This is not a three.js port. See Extensions.
"""

from extensions.humanoid.side import RIGHT
from extensions.humanoid.skeleton.field import DistanceField, smin
from extensions.humanoid.skeleton.head.frame import (
    HeadDimensions,
    HeadMuscleDimensions,
)
from extensions.humanoid.skeleton.head.hair.dimensions import (
    SCALP_HAIR,
    HairShape,
)
from extensions.humanoid.skeleton.head.hair.groom import (
    BRAID_TIE_Y,
    BRAID_TIE_Z,
    BUN_RADIUS,
    BUN_TIE_Y,
    BUN_TIE_Z,
    CRANIUM_CENTER_Y,
    HALF_TIE_Y,
    HALF_TIE_Z,
    HIGH_TIE_Y,
    HIGH_TIE_Z,
    PIGTAIL_X,
    PIGTAIL_Y,
    PIGTAIL_Z,
    SPACE_BUN_RADIUS,
    SPACE_BUN_X,
    TOPKNOT_RADIUS,
    TOPKNOT_TIE_Y,
    TOPKNOT_TIE_Z,
    SPACE_BUN_Y,
    SPACE_BUN_Z,
    TAIL_TIE_Y,
    TAIL_TIE_Z,
)
from extensions.humanoid.skeleton.head.hair.styles import (
    BOB,
    BRAID,
    BUN,
    HALF_UP,
    HIGH_PONYTAIL,
    LONG,
    PIGTAILS,
    PONYTAIL,
    SLICKED,
    SPACE_BUNS,
    TOPKNOT,
    TWIN_BRAIDS,
    HairStyle,
)
from extensions.humanoid.skeleton.head.skin.dimensions import HeadSkinField
from extensions.humanoid.skeleton.sculpt import Sculpt
from math.vector3 import Vector3, component_max, component_min

# How long the shell of a style that falls is drawn: one reaches the
# jaw, as `HairShape`'s length does.
comptime BOB_LENGTH = Float32(1.0)
comptime HALF_UP_LENGTH = Float32(0.7)
comptime SLICK_LENGTH = Float32(0.3)
# How far a bun's ball sits out from its tie, in its radius: nearer than
# the groom coils it, as the shell is the hair's mass and the tie lies
# under the hair's surface.
comptime BUN_SET = Float32(0.55)
# Long hair down the back: the middle of the sheet and its half sizes
# across, down and through, in template centimeters.
comptime SHEET_Y = Float32(62.0)
comptime SHEET_Z = Float32(-11.0)
comptime SHEET_WIDTH = Float32(7.0)
comptime SHEET_FALL = Float32(11.0)
comptime SHEET_DEPTH = Float32(2.4)


def _ponytail() -> List[Vector3]:
    """Return a ponytail's run, from its tie, in template centimeters:
    out from the head, then down the nape."""
    return [
        Vector3(0, 0, 0),
        Vector3(0, -1.5, -2.0),
        Vector3(0, -9.5, -2.0),
        Vector3(0, -18.5, -1.0),
    ]


def _ponytail_radii() -> List[Float32]:
    """Return a ponytail's radius at each point of its run, in template
    centimeters."""
    return [1.9, 2.1, 1.6, 0.7]


def _high_ponytail() -> List[Vector3]:
    """Return a high ponytail's run from its tie on the crown: back over
    the head, then down behind it."""
    return [
        Vector3(0, 0, 0),
        Vector3(0, 0, -3.5),
        Vector3(0, -6.5, -7.0),
        Vector3(0, -18.5, -6.5),
        Vector3(0, -26.5, -5.5),
    ]


def _high_ponytail_radii() -> List[Float32]:
    """Return a high ponytail's radii."""
    return [2.3, 2.5, 2.3, 1.7, 0.8]


def _braid() -> List[Vector3]:
    """Return a braid's run from its tie at the nape, down the back."""
    return [
        Vector3(0, 0, 0),
        Vector3(0, -2.5, -1.5),
        Vector3(0, -14.5, -2.0),
        Vector3(0, -28.5, -2.0),
    ]


def _braid_radii() -> List[Float32]:
    """Return a braid's radii: narrower than a tail, as it is woven."""
    return [1.5, 1.3, 1.1, 0.6]


def _pigtail() -> List[Vector3]:
    """Return the right pigtail's run from its tie behind the ear: out
    and down beside the neck."""
    return [
        Vector3(0, 0, 0),
        Vector3(2.0, -1.0, -1.0),
        Vector3(3.0, -8.0, -0.5),
        Vector3(3.0, -14.0, 0),
    ]


def _pigtail_radii() -> List[Float32]:
    """Return a pigtail's radii."""
    return [1.9, 2.2, 1.7, 0.8]


def _twin_braid() -> List[Vector3]:
    """Return the right braid's run from its tie behind the ear: out a
    little, then down beside the neck and over the collarbone."""
    return [
        Vector3(0, 0, 0),
        Vector3(1.5, -1.5, -0.8),
        Vector3(2.2, -12.0, 0),
        Vector3(2.0, -24.0, 1.0),
    ]


def _twin_braid_radii() -> List[Float32]:
    """Return a twin braid's radii: woven, so narrower than a tail."""
    return [1.4, 1.2, 1.0, 0.5]


def _half_tail() -> List[Vector3]:
    """Return a half-up's short tail from its tie at the back of the
    head."""
    return [Vector3(0, 0, 0), Vector3(0, -1.5, -2.0), Vector3(0, -7.5, -2.0)]


def _half_tail_radii() -> List[Float32]:
    """Return a half-up tail's radii."""
    return [1.4, 1.5, 0.6]


def _tail(
    mut clay: Sculpt,
    h: HeadDimensions,
    tie: Vector3,
    run: List[Vector3],
    radii: List[Float32],
    mirror: Float32,
):
    """Add a tapered tail that hangs from a tie.

    Args:
        clay: The sculpt the tail joins.
        h: The head's frame.
        tie: The tie, in template centimeters.
        run: The tail's points from the tie, in template centimeters.
        radii: Its radius at each point, in template centimeters.
        mirror: One for the run as it is; minus one to mirror it across
            the midline.
    """
    var points = List[Vector3]()
    var sizes = List[Float32]()
    for index in range(len(run)):  # pragma: no branch
        var p = tie + run[index]
        points.append(h.at(mirror * p.x, p.y, p.z))
        sizes.append(h.cm(radii[index]))
    clay.chain(points, sizes)


def _bun(mut clay: Sculpt, h: HeadDimensions, tie: Vector3, radius: Float32):
    """Add a bun: a ball out from its tie, away from the cranium's
    middle, where the groom coils one.

    Args:
        clay: The sculpt the bun joins.
        h: The head's frame.
        tie: The tie, in template centimeters.
        radius: The bun's radius, in template centimeters.
    """
    var away = tie - Vector3(0, CRANIUM_CENTER_Y, -1.0)
    away.normalize()
    var middle = tie + away * (radius * BUN_SET)
    var r = h.cm(radius)
    clay.ellipsoid(h.at(middle.x, middle.y, middle.z), Vector3(r, r, r))


def style_length(style: HairStyle) -> Optional[Float32]:
    """Return how long a style's shell is when it is drawn alone, or None
    where the style's own length stands.

    Args:
        style: A named style.

    Returns:
        A length for `HairShape`: one for a bob or long hair, which fall
        to the jaw, less for a half-up, and less still for slicked hair,
        which reaches the nape.
    """
    if style == BOB or style == LONG:
        return BOB_LENGTH
    if style == HALF_UP:
        return HALF_UP_LENGTH
    if style == SLICKED:
        return SLICK_LENGTH
    return None


struct HairSilhouette(Copyable, DistanceField, Movable):
    """A scalp's hair shell in the shape of its style, for a shell drawn
    with no strands over it."""

    var hair: HairShape
    # The style's tails, buns and sheet, empty where it has none.
    var ties: Sculpt
    var low: Vector3
    var high: Vector3

    def __init__(
        out self,
        dimensions: HeadMuscleDimensions,
        skin: HeadSkinField,
        style: HairStyle,
    ) raises:
        """Shape a scalp's hair as its style.

        Args:
            dimensions: Landmarks from `head_muscle_dimensions`.
            skin: The head's skin, from the same dimensions.
            style: How the hair is cut.

        Raises:
            Error: If `HairShape` refuses its inputs.
        """
        self.hair = HairShape(
            dimensions, SCALP_HAIR, RIGHT, skin, style, style_length(style)
        )
        var h = dimensions.head.copy()
        self.ties = Sculpt(self.hair.soft, self.hair.soft)
        if style == LONG:
            self.ties.ellipsoid(
                h.at(0, SHEET_Y, SHEET_Z),
                Vector3(h.cm(SHEET_WIDTH), h.cm(SHEET_FALL), h.cm(SHEET_DEPTH)),
            )
        elif style == PONYTAIL:
            _tail(
                self.ties,
                h,
                Vector3(0, TAIL_TIE_Y, TAIL_TIE_Z),
                _ponytail(),
                _ponytail_radii(),
                1,
            )
        elif style == HIGH_PONYTAIL:
            _tail(
                self.ties,
                h,
                Vector3(0, HIGH_TIE_Y, HIGH_TIE_Z),
                _high_ponytail(),
                _high_ponytail_radii(),
                1,
            )
        elif style == BRAID:
            _tail(
                self.ties,
                h,
                Vector3(0, BRAID_TIE_Y, BRAID_TIE_Z),
                _braid(),
                _braid_radii(),
                1,
            )
        elif style == HALF_UP:
            _tail(
                self.ties,
                h,
                Vector3(0, HALF_TIE_Y, HALF_TIE_Z),
                _half_tail(),
                _half_tail_radii(),
                1,
            )
        elif style == PIGTAILS:
            for mirror in [Float32(1), Float32(-1)]:  # pragma: no branch
                _tail(
                    self.ties,
                    h,
                    Vector3(PIGTAIL_X, PIGTAIL_Y, PIGTAIL_Z),
                    _pigtail(),
                    _pigtail_radii(),
                    mirror,
                )
        elif style == TWIN_BRAIDS:
            for mirror in [Float32(1), Float32(-1)]:  # pragma: no branch
                _tail(
                    self.ties,
                    h,
                    Vector3(PIGTAIL_X, PIGTAIL_Y, PIGTAIL_Z),
                    _twin_braid(),
                    _twin_braid_radii(),
                    mirror,
                )
        elif style == TOPKNOT:
            _bun(
                self.ties,
                h,
                Vector3(0, TOPKNOT_TIE_Y, TOPKNOT_TIE_Z),
                TOPKNOT_RADIUS,
            )
        elif style == BUN:
            _bun(self.ties, h, Vector3(0, BUN_TIE_Y, BUN_TIE_Z), BUN_RADIUS)
        elif style == SPACE_BUNS:
            for mirror in [Float32(1), Float32(-1)]:  # pragma: no branch
                _bun(
                    self.ties,
                    h,
                    Vector3(mirror * SPACE_BUN_X, SPACE_BUN_Y, SPACE_BUN_Z),
                    SPACE_BUN_RADIUS,
                )
        self.low = self.hair.low
        self.high = self.hair.high
        if len(self.ties.pieces) > 0:
            var pad = Vector3(self.hair.soft, self.hair.soft, self.hair.soft)
            self.low = component_min(self.low, self.ties.low - pad)
            self.high = component_max(self.high, self.ties.high + pad)

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the hair, in meters.

        Negative is inside.
        """
        var d = self.hair.distance(point)
        # Past the blend, the ties cannot change the union.
        return smin(
            d, self.ties.union(point, d + self.hair.soft), self.hair.soft
        )
