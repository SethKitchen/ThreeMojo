# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Amphipathic helices: the hydrophobic moment of Eisenberg and others, and
the helical wheel.

A helix that binds a membrane, such as an antimicrobial peptide, has its
hydrophobic side chains on one face and its charged side chains on the
other. Each residue of an alpha helix turns 100 degrees about the axis.
The hydrophobic moment sums the hydrophobicity `h` of each residue as a
vector at its angle:

    mu = |sum of h_n exp(i n delta)| / N

A large moment means that one face is hydrophobic and the other polar.

- `eisenberg_hydrophobicity(code)` and `sequence_hydrophobicity(sequence)`
  give the normalized consensus scale of Eisenberg and others (1984).
- `hydrophobic_moment(values, angle)` gives the mean hydrophobicity, the
  moment and its direction of a whole sequence.
- `window_moment(values, angle, window)` gives the largest moment of a
  window of residues, as the R package Peptides gives it.
- `helical_wheel(values, angle, size)` draws a helical wheel.
"""

from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from render.framebuffer import Color, Framebuffer
from std.math import atan2, cos, floor, isfinite, sin, sqrt
from units.si import Angle64, DEGREE64, RADIAN

# The most residues of a helical wheel.
comptime MAX_WHEEL = 100
# The ends of the scale, for the colors of a wheel.
comptime _MOST_HYDROPHOBIC = 1.38
comptime _MOST_HYDROPHILIC = -2.53


def eisenberg_hydrophobicity(code: String) -> Tuple[Bool, Float64]:
    """Return the hydrophobicity of an amino acid on the scale of Eisenberg.

    The scale is the normalized consensus scale of Eisenberg, Schwarz,
    Komaromy and Wall (1984).

    Args:
        code: The one-letter code, in capitals, such as `I`.

    Returns:
        Whether the code is one of the twenty amino acids, and its value
        from -2.53 (arginine) to 1.38 (isoleucine). Zero for another code.
    """
    var codes = "ARNDCQEGHILKMFPSTWYV"
    var values: List[Float64] = [
        0.62,
        -2.53,
        -0.78,
        -0.90,
        0.29,
        -0.85,
        -0.74,
        0.48,
        -0.40,
        1.38,
        1.06,
        -1.50,
        0.64,
        1.19,
        0.12,
        -0.18,
        -0.05,
        0.81,
        0.26,
        1.08,
    ]
    if code.byte_length() != 1:
        return (False, 0.0)
    var at = codes.find(code)
    if at < 0:
        return (False, 0.0)
    return (True, values[at])


def sequence_hydrophobicity(sequence: String) raises -> List[Float64]:
    """Return the hydrophobicity of each residue of a sequence.

    Args:
        sequence: The one-letter codes, in capitals.

    Returns:
        The value of each residue on the scale of Eisenberg.

    Raises:
        Error: If the sequence is empty or holds a code that is not one of
            the twenty amino acids.
    """
    if sequence.byte_length() == 0:
        raise Error("A sequence needs one residue or more")
    var out = List[Float64]()
    for code in sequence.codepoint_slices():  # pragma: no branch
        var value = eisenberg_hydrophobicity(String(code))
        if not value[0]:
            raise Error("A sequence holds only the twenty one-letter codes")
        out.append(value[1])
    return out^


struct HydrophobicMoment(Copyable, Movable):
    """The hydrophobic moment of a stretch of residues."""

    var mean: Float64
    """The mean hydrophobicity of the stretch."""
    var moment: Float64
    """The length of the sum of the vectors, over the residues."""
    var direction: Angle64
    """The angle of the sum, from the first residue's angle toward the
    second's: the middle of the hydrophobic face."""
    var start: Int
    """The first residue of the stretch, from 0."""
    var length: Int
    """The residues of the stretch."""

    def __init__(
        out self,
        mean: Float64,
        moment: Float64,
        direction: Angle64,
        start: Int,
        length: Int,
    ):
        """Create a moment.

        Args:
            mean: The mean hydrophobicity.
            moment: The moment.
            direction: The direction of the moment.
            start: The first residue.
            length: The residues.
        """
        self.mean = mean
        self.moment = moment
        self.direction = direction
        self.start = start
        self.length = length


def _require_values(values: List[Float64], angle: Angle64) raises -> Float64:
    """Refuse values that are empty or not finite, or an angle not between
    0 and 360 degrees. Return the angle in radians."""
    if len(values) == 0:
        raise Error("A hydrophobic moment needs one residue or more")
    for v in values:  # pragma: no branch
        if not isfinite(v):
            raise Error("A hydrophobicity must be finite")
    var degrees = angle.to(DEGREE64)
    if not (degrees > 0 and degrees < 360):
        raise Error("The angle of a residue is between 0 and 360 degrees")
    return angle.to(RADIAN)


def _moment(
    values: List[Float64], step: Float64, start: Int, length: Int
) -> HydrophobicMoment:
    """Return the moment of a stretch, its first residue at angle 0."""
    var across = 0.0
    var along = 0.0
    var total = 0.0
    for n in range(length):  # pragma: no branch
        var h = values[start + n]
        across += h * sin(step * Float64(n))
        along += h * cos(step * Float64(n))
        total += h
    var size = Float64(length)
    return HydrophobicMoment(
        total / size,
        sqrt(across * across + along * along) / size,
        Angle64(atan2(across, along), RADIAN),
        start,
        length,
    )


def hydrophobic_moment(
    values: List[Float64], angle: Angle64
) raises -> HydrophobicMoment:
    """Return the hydrophobic moment of a whole sequence.

    Args:
        values: The hydrophobicity of each residue.
        angle: The turn from one residue to the next: 100 degrees for an
            alpha helix, 160 to 180 for a strand.

    Returns:
        The mean, the moment and its direction.

    Raises:
        Error: If there is no value, a value is not finite, or the angle is
            not between 0 and 360 degrees.
    """
    var step = _require_values(values, angle)
    return _moment(values, step, 0, len(values))


def window_moment(
    values: List[Float64], angle: Angle64, window: Int
) raises -> HydrophobicMoment:
    """Return the largest hydrophobic moment of a window of residues.

    Each window takes its first residue at angle 0. A tie keeps the first
    window. A window longer than the sequence takes the whole sequence.

    Args:
        values: The hydrophobicity of each residue.
        angle: The turn from one residue to the next.
        window: The residues of a window, 1 or more. 11 is usual.

    Returns:
        The moment of the window with the largest moment.

    Raises:
        Error: If the values or the angle are not valid, as for
            `hydrophobic_moment`, or the window is below 1.
    """
    var step = _require_values(values, angle)
    if window < 1:
        raise Error("A window has one residue or more")
    var length = min(window, len(values))
    var best = _moment(values, step, 0, length)
    for start in range(1, len(values) - length + 1):
        var next = _moment(values, step, start, length)
        if next.moment > best.moment:
            best = next^
    return best^


struct HelicalWheel(Movable):
    """A drawn helical wheel and the place of each residue."""

    var image: Framebuffer
    """The wheel on a white square."""
    var xs: List[Float64]
    """The column of the center of each residue's disc."""
    var ys: List[Float64]
    """The row of the center of each residue's disc."""
    var radius: Float64
    """The radius of each disc, in pixels."""

    def __init__(out self, var image: Framebuffer, radius: Float64):
        """Create a wheel with no residue placed yet.

        Args:
            image: The image.
            radius: The radius of each disc.
        """
        self.image = image^
        self.xs = List[Float64]()
        self.ys = List[Float64]()
        self.radius = radius


def _shade(h: Float64) -> Rgba:
    """Return orange for hydrophobic residues and blue for hydrophilic ones,
    paler near 0."""
    if h >= 0:
        var t = Float32(min(h / _MOST_HYDROPHOBIC, 1.0))
        return Rgba(1.0 - 0.05 * t, 1.0 - 0.45 * t, 1.0 - 0.9 * t, 1)
    var t = Float32(min(h / _MOST_HYDROPHILIC, 1.0))
    return Rgba(1.0 - 0.85 * t, 1.0 - 0.6 * t, 1.0 - 0.2 * t, 1)


def _disc(
    mut image: Framebuffer, x: Float64, y: Float64, r: Float64, fill: Rgba
):
    """Fill a disc with a dark rim of one pixel."""
    var rim = Rgba(0.24, 0.24, 0.26, 1)
    var low_x = Int(floor(x - r))
    var low_y = Int(floor(y - r))
    for j in range(low_y, Int(floor(y + r)) + 2):  # pragma: no branch
        for i in range(low_x, Int(floor(x + r)) + 2):  # pragma: no branch
            var d = sqrt((Float64(i) - x) ** 2 + (Float64(j) - y) ** 2)
            if d <= r - 1.0:
                draw_line(image, i, j, i, j, fill)
            elif d <= r:
                draw_line(image, i, j, i, j, rim)


def helical_wheel(
    values: List[Float64], angle: Angle64, size: Int
) raises -> HelicalWheel:
    """Draw a helical wheel: the residues seen down the axis of the helix.

    Residue `n` sits at the angle `n * angle`, clockwise from the top. The
    residues spiral out by one disc for each full turn, so that no two
    overlap. Each disc is orange for a hydrophobic residue and blue for a
    hydrophilic one, paler near 0. A gray line joins the residues in order,
    and a dark arrow from the center points along the moment, its length
    the moment times the outer radius.

    Args:
        values: The hydrophobicity of each residue, from 1 to 100.
        angle: The turn from one residue to the next.
        size: The side of the image, from 64 to 4096 pixels.

    Returns:
        The image and the center of each residue's disc, where a caller can
        write its letter.

    Raises:
        Error: If the values or the angle are not valid, as for
            `hydrophobic_moment`, there are more than 100 residues, or the
            size is out of range.
    """
    var step = _require_values(values, angle)
    var count = len(values)
    if count > MAX_WHEEL:
        raise Error("A helical wheel holds 100 residues at most")
    if size < 64 or size > 4096:
        raise Error("A helical wheel is from 64 to 4096 pixels on a side")
    var side = Float64(size)
    var center = (side - 1.0) / 2.0
    var inner = 0.12 * side
    var turns = Float64(count - 1) * angle.to(DEGREE64) / 360.0
    var r = (0.47 * side - inner) / (1.0 + 2.0 * turns)
    var out = HelicalWheel(Framebuffer(size, size, Color(255, 255, 255)), r)
    for n in range(count):  # pragma: no branch
        var reach = inner + 2.0 * r * Float64(n) * angle.to(DEGREE64) / 360.0
        var a = step * Float64(n)
        out.xs.append(center + reach * sin(a))
        out.ys.append(center - reach * cos(a))
    var gray = Rgba(0.7, 0.7, 0.72, 1)
    for n in range(1, count):
        draw_line(
            out.image,
            Int(floor(out.xs[n - 1] + 0.5)),
            Int(floor(out.ys[n - 1] + 0.5)),
            Int(floor(out.xs[n] + 0.5)),
            Int(floor(out.ys[n] + 0.5)),
            gray,
        )
    var moment = _moment(values, step, 0, count)
    var outer = inner + 2.0 * r * turns + r
    var length = min(moment.moment, 1.0) * outer
    var d = moment.direction.to(RADIAN)
    var tip_x = center + length * sin(d)
    var tip_y = center - length * cos(d)
    var dark = Rgba(0.24, 0.24, 0.26, 1)
    var cx = Int(floor(center + 0.5))
    draw_line(
        out.image,
        cx,
        cx,
        Int(floor(tip_x + 0.5)),
        Int(floor(tip_y + 0.5)),
        dark,
    )
    for side_turn in [2.6, -2.6]:  # pragma: no branch
        var back = d + side_turn
        var head = 0.06 * side
        draw_line(
            out.image,
            Int(floor(tip_x + 0.5)),
            Int(floor(tip_y + 0.5)),
            Int(floor(tip_x + head * sin(back) + 0.5)),
            Int(floor(tip_y - head * cos(back) + 0.5)),
            dark,
        )
    for n in range(count):  # pragma: no branch
        _disc(out.image, out.xs[n], out.ys[n], r, _shade(values[n]))
    return out^
