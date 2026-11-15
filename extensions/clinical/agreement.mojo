# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The agreement of two methods, or of several raters, that measure the
same subjects.

- `bland_altman(first, second)` gives the bias of the first method against
  the second, and the 95 percent limits of agreement, `bias -+ 1.96 sd`.
  The interval of the bias and of each limit comes from the t
  distribution, after Bland and Altman (1986, 1999).
- `bland_altman_image` plots each difference against its mean, with the
  bias and the limits.
- `intraclass_correlation(ratings)` gives the six intraclass correlations
  of Shrout and Fleiss (1979), with the names of McGraw and Wong (1996):
  ICC(1,1), ICC(A,1), ICC(C,1) and their averages over the raters. Each
  has its F test and its 95 percent interval, as pingouin computes them.

A measurement is a plain number in a unit that the caller chooses, such as
a volume in milliliters. The bias and the limits are in that unit.
"""

from extensions.clinical.distributions import (
    f_quantile,
    f_upper,
    student_t_quantile,
)
from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from render.framebuffer import Color, Framebuffer
from std.math import floor, isfinite, sqrt

# The multiple of the standard deviation of the limits of agreement.
comptime LIMIT_FACTOR = 1.96


struct BlandAltman(Copyable, Movable):
    """The agreement of two methods on the same subjects."""

    var count: Int
    """The subjects."""
    var bias: Float64
    """The mean difference, the first method less the second."""
    var deviation: Float64
    """The sample standard deviation of the differences."""
    var lower: Float64
    """The lower limit of agreement, `bias - 1.96 sd`."""
    var upper: Float64
    """The upper limit of agreement, `bias + 1.96 sd`."""
    var bias_interval: Tuple[Float64, Float64]
    """The 95 percent interval of the bias."""
    var lower_interval: Tuple[Float64, Float64]
    """The 95 percent interval of the lower limit."""
    var upper_interval: Tuple[Float64, Float64]
    """The 95 percent interval of the upper limit."""

    def __init__(
        out self, count: Int, bias: Float64, deviation: Float64
    ) raises:
        """Create a result from the differences' mean and deviation.

        Args:
            count: The subjects, two or more.
            bias: The mean difference.
            deviation: The sample standard deviation of the differences.

        Raises:
            Error: If the count is less than two.
        """
        var t = student_t_quantile(0.975, Float64(count - 1))
        self.count = count
        self.bias = bias
        self.deviation = deviation
        self.lower = bias - LIMIT_FACTOR * deviation
        self.upper = bias + LIMIT_FACTOR * deviation
        var se_bias = deviation / sqrt(Float64(count))
        # The variance of a limit is about 3 sd^2 / n.
        var se_limit = sqrt(3.0 * deviation * deviation / Float64(count))
        self.bias_interval = (bias - t * se_bias, bias + t * se_bias)
        self.lower_interval = (
            self.lower - t * se_limit,
            self.lower + t * se_limit,
        )
        self.upper_interval = (
            self.upper - t * se_limit,
            self.upper + t * se_limit,
        )


def _require_pairs(first: List[Float64], second: List[Float64]) raises:
    """Refuse two methods that do not give one finite value each for two
    subjects or more."""
    if len(first) < 2 or len(first) != len(second):
        raise Error("Bland-Altman needs two subjects or more, one value each")
    for i in range(len(first)):  # pragma: no branch
        if not isfinite(first[i]) or not isfinite(second[i]):
            raise Error("The measurements of Bland-Altman must be finite")


def bland_altman(
    first: List[Float64], second: List[Float64]
) raises -> BlandAltman:
    """Return the agreement of two methods on the same subjects.

    Args:
        first: The value of each subject by the first method.
        second: The value of each subject by the second method.

    Returns:
        The bias, the first less the second, and the limits of agreement
        with their intervals.

    Raises:
        Error: If the methods do not give one finite value each for two
            subjects or more.
    """
    _require_pairs(first, second)
    var n = len(first)
    var total = 0.0
    for i in range(n):  # pragma: no branch
        total += first[i] - second[i]
    var bias = total / Float64(n)
    var squares = 0.0
    for i in range(n):  # pragma: no branch
        var gap = first[i] - second[i] - bias
        squares += gap * gap
    return BlandAltman(n, bias, sqrt(squares / Float64(n - 1)))


def _row(value: Float64, reach: Float64, bottom: Float64) -> Int:
    """Return the image row of a difference, with `reach` at the top."""
    return Int(floor((reach - value) / (2.0 * reach) * bottom + 0.5))


def bland_altman_image(
    first: List[Float64],
    second: List[Float64],
    result: BlandAltman,
    width: Int,
    height: Int,
) raises -> Framebuffer:
    """Plot each difference against the mean of its pair.

    The mean runs from the least to the most, with a margin of a tenth of
    the range, from the left edge to the right edge. The difference runs
    from `-r` at the bottom edge to `r` at the top edge, with `r` 1.25
    times the largest size of a difference or a limit. A gray line marks
    0, a blue line the bias, and red lines the limits. A cross marks each
    subject.

    Args:
        first: The value of each subject by the first method.
        second: The value of each subject by the second method.
        result: Their agreement, from `bland_altman`.
        width: The width of the image, from 64 to 4096 pixels.
        height: The height of the image, from 64 to 4096 pixels.

    Returns:
        A white image with a dark frame.

    Raises:
        Error: If the methods are not valid, the result is not theirs, the
            means do not vary, or a size is out of range.
    """
    _require_pairs(first, second)
    if result.count != len(first):
        raise Error("A Bland-Altman plot needs the result of its own data")
    if width < 64 or width > 4096 or height < 64 or height > 4096:
        raise Error("A Bland-Altman plot is from 64 to 4096 pixels a side")
    var least = (first[0] + second[0]) / 2.0
    var most = least
    var reach = max(abs(result.lower), abs(result.upper))
    for i in range(len(first)):  # pragma: no branch
        var mean = (first[i] + second[i]) / 2.0
        least = min(least, mean)
        most = max(most, mean)
        reach = max(reach, abs(first[i] - second[i]))
    if not (most > least) or not (reach > 0):
        raise Error("A Bland-Altman plot needs means and differences that vary")
    var margin = 0.1 * (most - least)
    least -= margin
    most += margin
    reach *= 1.25
    var image = Framebuffer(width, height, Color(255, 255, 255))
    var right = Float64(width - 1)
    var bottom = Float64(height - 1)

    draw_line(
        image,
        0,
        _row(0.0, reach, bottom),
        width - 1,
        _row(0.0, reach, bottom),
        Rgba(0.7, 0.7, 0.72, 1),
    )
    var red = Rgba(0.85, 0.2, 0.2, 1)
    draw_line(
        image,
        0,
        _row(result.lower, reach, bottom),
        width - 1,
        _row(result.lower, reach, bottom),
        red,
    )
    draw_line(
        image,
        0,
        _row(result.upper, reach, bottom),
        width - 1,
        _row(result.upper, reach, bottom),
        red,
    )
    draw_line(
        image,
        0,
        _row(result.bias, reach, bottom),
        width - 1,
        _row(result.bias, reach, bottom),
        Rgba(0.15, 0.4, 0.85, 1),
    )
    var dark = Rgba(0.24, 0.24, 0.26, 1)
    draw_line(image, 0, 0, width - 1, 0, dark)
    draw_line(image, 0, height - 1, width - 1, height - 1, dark)
    draw_line(image, 0, 0, 0, height - 1, dark)
    draw_line(image, width - 1, 0, width - 1, height - 1, dark)
    for i in range(len(first)):  # pragma: no branch
        var x = Int(
            floor(
                ((first[i] + second[i]) / 2.0 - least) / (most - least) * right
                + 0.5
            )
        )
        var y = _row(first[i] - second[i], reach, bottom)
        draw_line(image, x - 3, y, x + 3, y, dark)
        draw_line(image, x, y - 3, x, y + 3, dark)
    return image^


struct Icc(Copyable, Movable):
    """One intraclass correlation with its F test and interval."""

    var value: Float64
    """The correlation."""
    var f: Float64
    """The F statistic of the test that the correlation is 0."""
    var df1: Int
    """The degrees of freedom of the numerator."""
    var df2: Int
    """The degrees of freedom of the denominator."""
    var p_value: Float64
    """The chance of an F this large when the correlation is 0."""
    var lower: Float64
    """The low end of the 95 percent interval."""
    var upper: Float64
    """The high end of the 95 percent interval."""

    def __init__(
        out self,
        value: Float64,
        f: Float64,
        df1: Int,
        df2: Int,
        lower: Float64,
        upper: Float64,
    ) raises:
        """Create a result, with the p value of its F test.

        Args:
            value: The correlation.
            f: The F statistic.
            df1: The degrees of freedom of the numerator.
            df2: The degrees of freedom of the denominator.
            lower: The low end of the interval.
            upper: The high end of the interval.

        Raises:
            Error: If the F statistic or a freedom is out of range.
        """
        self.value = value
        self.f = f
        self.df1 = df1
        self.df2 = df2
        self.p_value = f_upper(f, Float64(df1), Float64(df2))
        self.lower = lower
        self.upper = upper


struct IccTable(Copyable, Movable):
    """The six intraclass correlations of one set of ratings."""

    var one: Icc
    """ICC(1,1): one rating, each subject by its own raters."""
    var agreement: Icc
    """ICC(A,1): one rating, absolute agreement of the same raters."""
    var consistency: Icc
    """ICC(C,1): one rating, consistency of the same raters."""
    var one_average: Icc
    """ICC(1,k): the mean of the k ratings, by the model of ICC(1,1)."""
    var agreement_average: Icc
    """ICC(A,k): the mean of the k ratings, absolute agreement."""
    var consistency_average: Icc
    """ICC(C,k): the mean of the k ratings, consistency."""

    def __init__(
        out self,
        var one: Icc,
        var agreement: Icc,
        var consistency: Icc,
        var one_average: Icc,
        var agreement_average: Icc,
        var consistency_average: Icc,
    ):
        """Create a table.

        Args:
            one: ICC(1,1).
            agreement: ICC(A,1).
            consistency: ICC(C,1).
            one_average: ICC(1,k).
            agreement_average: ICC(A,k).
            consistency_average: ICC(C,k).
        """
        self.one = one^
        self.agreement = agreement^
        self.consistency = consistency^
        self.one_average = one_average^
        self.agreement_average = agreement_average^
        self.consistency_average = consistency_average^


def intraclass_correlation(ratings: List[List[Float64]]) raises -> IccTable:
    """Return the six intraclass correlations of a set of ratings.

    The mean squares come from a two-way analysis of variance: `msb` of the
    subjects, `msj` of the raters, `mse` of the residual, and `msw` within
    the subjects.

    Args:
        ratings: One row for each subject, of one rating by each rater.
            Two subjects or more and two raters or more, all finite.

    Returns:
        The table of the six correlations.

    Raises:
        Error: If the ratings are not a finite table of two rows and two
            columns or more, or the residual has no variation.
    """
    var n = len(ratings)
    if n < 2:
        raise Error("An ICC needs two subjects or more")
    var k = len(ratings[0])
    if k < 2:
        raise Error("An ICC needs two raters or more")
    var grand = 0.0
    for row in ratings:  # pragma: no branch
        if len(row) != k:
            raise Error("Each subject of an ICC needs one rating by each rater")
        for v in row:  # pragma: no branch
            if not isfinite(v):
                raise Error("The ratings of an ICC must be finite")
            grand += v
    var fs = Float64(n)
    var fk = Float64(k)
    grand /= fs * fk
    var ssb = 0.0
    var total = 0.0
    var columns = List[Float64](length=k, fill=0.0)
    for row in ratings:  # pragma: no branch
        var mean = 0.0
        for j in range(k):  # pragma: no branch
            mean += row[j]
            columns[j] += row[j]
            total += (row[j] - grand) * (row[j] - grand)
        mean /= fk
        ssb += fk * (mean - grand) * (mean - grand)
    var ssj = 0.0
    for j in range(k):  # pragma: no branch
        var mean = columns[j] / fs
        ssj += fs * (mean - grand) * (mean - grand)
    var sse = total - ssb - ssj
    var df1 = n - 1
    var df_within = n * (k - 1)
    var df_error = (n - 1) * (k - 1)
    var msb = ssb / Float64(df1)
    var msj = ssj / (fk - 1.0)
    var mse = sse / Float64(df_error)
    var msw = (ssj + sse) / Float64(df_within)
    if not (mse > 0):
        raise Error("The ratings of an ICC need residual variation")
    var icc1 = (msb - msw) / (msb + (fk - 1.0) * msw)
    var icc2 = (msb - mse) / (msb + (fk - 1.0) * mse + fk * (msj - mse) / fs)
    var icc3 = (msb - mse) / (msb + (fk - 1.0) * mse)
    var f1 = msb / msw
    var f3 = msb / mse
    var d1 = Float64(df1)
    var f1l = f1 / f_quantile(0.975, d1, Float64(df_within))
    var f1u = f1 * f_quantile(0.975, Float64(df_within), d1)
    var f3l = f3 / f_quantile(0.975, d1, Float64(df_error))
    var f3u = f3 * f_quantile(0.975, Float64(df_error), d1)
    # Satterthwaite's degrees of freedom for ICC(A,1), after McGraw and
    # Wong (1996).
    var fj = msj / mse
    var common = fs * (1.0 + (fk - 1.0) * icc2) - fk * icc2
    var vn = Float64(df_error) * (fk * icc2 * fj + common) ** 2
    var vd = d1 * (fk * icc2 * fj) ** 2 + common**2
    var v = vn / vd
    var f2u = f_quantile(0.975, d1, v)
    var f2l = f_quantile(0.975, v, d1)
    var spread = fk * msj + (fk * fs - fk - fs) * mse
    var l2 = fs * (msb - f2u * mse) / (f2u * spread + fs * msb)
    var u2 = fs * (f2l * msb - mse) / (spread + fs * f2l * msb)
    return IccTable(
        Icc(
            icc1,
            f1,
            df1,
            df_within,
            (f1l - 1.0) / (f1l + fk - 1.0),
            (f1u - 1.0) / (f1u + fk - 1.0),
        ),
        Icc(icc2, f3, df1, df_error, l2, u2),
        Icc(
            icc3,
            f3,
            df1,
            df_error,
            (f3l - 1.0) / (f3l + fk - 1.0),
            (f3u - 1.0) / (f3u + fk - 1.0),
        ),
        Icc(
            (msb - msw) / msb,
            f1,
            df1,
            df_within,
            1.0 - 1.0 / f1l,
            1.0 - 1.0 / f1u,
        ),
        Icc(
            (msb - mse) / (msb + (msj - mse) / fs),
            f3,
            df1,
            df_error,
            l2 * fk / (1.0 + l2 * (fk - 1.0)),
            u2 * fk / (1.0 + u2 * (fk - 1.0)),
        ),
        Icc(
            (msb - mse) / msb,
            f3,
            df1,
            df_error,
            1.0 - 1.0 / f3l,
            1.0 - 1.0 / f3u,
        ),
    )
