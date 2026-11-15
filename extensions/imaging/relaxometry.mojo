# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""MRI relaxometry: T2 from multi-echo spin echoes, and T1 from inversion
recovery.

T1 and T2 are the times in which tissue regains and loses its
magnetization. They change with water, iron, fat and collagen. So research
maps them: T2 of cartilage in osteoarthritis, T1 of the myocardium in
fibrosis, and both in tumors and multiple sclerosis.

- `fit_t2(echo_times, signals)` fits `ln S` to a line in the echo time:
  `S = S0 exp(-TE / T2)`.
- `fit_t1(inversion_times, signals)` fits the magnitudes of an inversion
  recovery, `S = |A - B exp(-TI / T1)|`. The true signals before the null
  are negative, so the fit takes each count of first signals as negative,
  as Barral and others (2010) do. For each count and each T1, A and B are
  linear least squares. A golden-section search over `log T1`, from 1 ms
  to 10 s, finds T1, and Gauss-Newton steps on A, B and T1 polish the best
  fit.
- `t2_maps` and `t1_maps` fit each voxel of a series of volumes.
"""

from extensions.imaging.image_volume import ImageVolume
from extensions.numerics.dense import (
    DenseMatrix,
    cholesky_solve,
)
from std.math import isfinite, log
from units.quantity import Unit
from units.si import MILLISECOND64, Duration64
from extensions.numerics.elementary import precise_exp
from extensions.numerics.search import golden_minimum

# The search of log T1 in ms, and its steps.
comptime _LEAST_LOG_T1 = 0.0
comptime _MOST_LOG_T1 = 9.210340371976184
comptime _SEARCH_STEPS = 100
comptime _POLISH_STEPS = 4


def _times(times: List[Duration64], least: Int) raises -> List[Float64]:
    """Return times in ms, checked to be at least `least`, finite, 0 or more
    and rising."""
    if len(times) < least:
        raise Error(
            "A relaxation fit needs " + String(least) + " times or more"
        )
    var out = List[Float64]()
    for t in times:  # pragma: no branch
        var ms = t.to(MILLISECOND64)
        if not (ms >= 0) or not isfinite(ms):
            raise Error("A relaxation time must be finite and 0 or more")
        if len(out) > 0 and not (ms > out[len(out) - 1]):
            raise Error("The times of a relaxation fit must rise")
        out.append(ms)
    return out^


def _signals(signals: List[Float64], count: Int) raises:
    """Refuse signals that are not one finite value 0 or more per time."""
    if len(signals) != count:
        raise Error("A relaxation fit needs one signal for each time")
    for s in signals:  # pragma: no branch
        if not (s >= 0) or not isfinite(s):
            raise Error("A signal must be finite and 0 or more")


struct T2Fit(Copyable, Movable):
    """The mono-exponential fit of a multi-echo decay."""

    var t2: Duration64
    """The transverse relaxation time."""
    var s0: Float64
    """The fitted signal at an echo time of 0."""

    def __init__(out self, t2: Duration64, s0: Float64):
        """Create a fit.

        Args:
            t2: T2.
            s0: The signal at an echo time of 0.
        """
        self.t2 = t2
        self.s0 = s0


def _line(x: List[Float64], y: List[Float64]) -> Tuple[Float64, Float64]:
    """Return the slope and the intercept of the least squares line."""
    var n = Float64(len(x))
    var mx = 0.0
    var my = 0.0
    for i in range(len(x)):  # pragma: no branch
        mx += x[i] / n
        my += y[i] / n
    var xx = 0.0
    var xy = 0.0
    for i in range(len(x)):  # pragma: no branch
        xx += (x[i] - mx) * (x[i] - mx)
        xy += (x[i] - mx) * (y[i] - my)
    var slope = xy / xx
    return (slope, my - slope * mx)


def fit_t2(
    echo_times: List[Duration64], signals: List[Float64]
) raises -> T2Fit:
    """Fit T2 to the signals of a multi-echo spin echo.

    Args:
        echo_times: The echo times, two or more, rising.
        signals: The signal at each echo time, above 0.

    Returns:
        T2 and S0 of the least squares line of `ln S` on the echo time.

    Raises:
        Error: If the times are not valid, a signal is not above 0 and
            finite, or the signals do not fall with the echo time.
    """
    var x = _times(echo_times, 2)
    _signals(signals, len(x))
    var y = List[Float64]()
    for s in signals:  # pragma: no branch
        if not (s > 0):
            raise Error("A T2 fit needs signals above 0")
        y.append(log(s))
    var fit = _line(x, y)
    if not (fit[0] < 0):
        raise Error("A T2 fit needs signals that fall with the echo time")
    return T2Fit(Duration64(-1.0 / fit[0], MILLISECOND64), precise_exp(fit[1]))


struct T1Fit(Copyable, Movable):
    """The fit of an inversion recovery."""

    var t1: Duration64
    """The longitudinal relaxation time."""
    var a: Float64
    """A: the signal at full recovery."""
    var b: Float64
    """B: about 2 A for a full inversion."""
    var flips: Int
    """The first signals that the fit takes as negative."""
    var residual: Float64
    """The sum of the squares of the misfit."""

    def __init__(
        out self,
        t1: Duration64,
        a: Float64,
        b: Float64,
        flips: Int,
        residual: Float64,
    ):
        """Create a fit.

        Args:
            t1: T1.
            a: A.
            b: B.
            flips: The signals taken as negative.
            residual: The sum of squares of the misfit.
        """
        self.t1 = t1
        self.a = a
        self.b = b
        self.flips = flips
        self.residual = residual


def _linear(
    x: List[Float64], y: List[Float64], t1: Float64
) -> Tuple[Float64, Float64, Float64]:
    """Return A, B and the sum of squares of the best `A - B exp(-x / t1)`
    at one T1."""
    var n = Float64(len(x))
    var me = 0.0
    var my = 0.0
    var e = List[Float64]()
    for i in range(len(x)):  # pragma: no branch
        var v = precise_exp(-x[i] / t1)
        e.append(v)
        me += v / n
        my += y[i] / n
    var ee = 0.0
    var ey = 0.0
    for i in range(len(x)):  # pragma: no branch
        ee += (e[i] - me) * (e[i] - me)
        ey += (e[i] - me) * (y[i] - my)
    var slope = ey / ee
    var a = my - slope * me
    var sum = 0.0
    for i in range(len(x)):  # pragma: no branch
        var r = a + slope * e[i] - y[i]
        sum += r * r
    return (a, -slope, sum)


def _search(x: List[Float64], y: List[Float64]) raises -> Float64:
    """Return the log T1 of the least sum of squares, by golden section."""

    def cost(log_t1: Float64) capturing -> Float64:
        return _linear(x, y, precise_exp(log_t1))[2]

    return golden_minimum[cost](_LEAST_LOG_T1, _MOST_LOG_T1, _SEARCH_STEPS)


def _polish(
    x: List[Float64], y: List[Float64], start: Float64
) raises -> Tuple[Float64, Float64, Float64]:
    """Return A, B and T1 after Gauss-Newton steps from the T1 of a search."""
    var t1 = start
    var fit = _linear(x, y, t1)
    var a = fit[0]
    var b = fit[1]
    for _ in range(_POLISH_STEPS):  # pragma: no branch
        var gram = DenseMatrix(3, 3)
        var right = List[Float64](length=3, fill=0.0)
        for i in range(len(x)):  # pragma: no branch
            var e = precise_exp(-x[i] / t1)
            var r = y[i] - (a - b * e)
            var j: List[Float64] = [1.0, -e, -b * e * x[i] / (t1 * t1)]
            for p in range(3):  # pragma: no branch
                right[p] += j[p] * r
                for q in range(p + 1):  # pragma: no branch
                    gram.add(p, q, j[p] * j[q])
        var step = cholesky_solve(gram, right)
        a += step[0]
        b += step[1]
        t1 += step[2]
    return (a, b, t1)


def _t1(x: List[Float64], signals: List[Float64]) raises -> T1Fit:
    """Fit an inversion recovery, trying each count of negative signals."""
    var best = T1Fit(Duration64(0, MILLISECOND64), 0, 0, 0, -1.0)
    for flips in range(len(x) + 1):  # pragma: no branch
        var y = List[Float64]()
        for i in range(len(x)):  # pragma: no branch
            y.append(-signals[i] if i < flips else signals[i])
        var t1 = precise_exp(_search(x, y))
        var fit = _linear(x, y, t1)
        if best.residual < 0 or fit[2] < best.residual:
            best = T1Fit(
                Duration64(t1, MILLISECOND64), fit[0], fit[1], flips, fit[2]
            )
    var y = List[Float64]()
    for i in range(len(x)):  # pragma: no branch
        y.append(-signals[i] if i < best.flips else signals[i])
    var done = _polish(x, y, best.t1.to(MILLISECOND64))
    var residual = 0.0
    for i in range(len(x)):  # pragma: no branch
        var r = y[i] - (done[0] - done[1] * precise_exp(-x[i] / done[2]))
        residual += r * r
    return T1Fit(
        Duration64(done[2], MILLISECOND64),
        done[0],
        done[1],
        best.flips,
        residual,
    )


def fit_t1(
    inversion_times: List[Duration64], signals: List[Float64]
) raises -> T1Fit:
    """Fit T1 to the magnitude signals of an inversion recovery.

    Args:
        inversion_times: The inversion times, four or more, rising.
        signals: The magnitude signal at each inversion time, 0 or more.

    Returns:
        T1, A and B of the least squares fit, the count of signals taken
        as negative, and the sum of squares of the misfit.

    Raises:
        Error: If the times or the signals are not valid, or the
            Gauss-Newton steps meet a singular system.
    """
    var x = _times(inversion_times, 4)
    _signals(signals, len(x))
    return _t1(x, signals)


struct RelaxationMaps(Copyable, Movable):
    """A map of a relaxation time and of its amplitude."""

    var time: ImageVolume
    """T1 or T2 in ms. 0 where a voxel has no fit."""
    var amplitude: ImageVolume
    """S0 of a T2 fit, or A of a T1 fit. 0 where a voxel has no fit."""

    def __init__(out self, var time: ImageVolume, var amplitude: ImageVolume):
        """Create maps.

        Args:
            time: The map of the time.
            amplitude: The map of the amplitude.
        """
        self.time = time^
        self.amplitude = amplitude^


def _zeros(
    series: List[ImageVolume], count: Int, threshold: Float64
) raises -> ImageVolume:
    """Refuse a series that does not match the times or shares no grid, or a
    threshold below 0. Return a volume of zeros on the grid."""
    if len(series) != count:
        raise Error("A relaxation series needs one volume for each time")
    if not (threshold >= 0) or not isfinite(threshold):
        raise Error("A relaxation threshold must be finite and 0 or more")
    var out = series[0].copy()
    for volume in series:  # pragma: no branch
        if volume.nx != out.nx or volume.ny != out.ny or volume.nz != out.nz:
            raise Error(
                "The volumes of a relaxation series have different grids"
            )
    for at in range(out.count()):  # pragma: no branch
        out.values[at] = 0
    return out^


def t2_maps(
    series: List[ImageVolume], echo_times: List[Duration64], threshold: Float64
) raises -> RelaxationMaps:
    """Fit T2 at each voxel of a multi-echo series.

    A voxel has a fit when each of its signals is finite and above the
    threshold, and the signals fall with the echo time.

    Args:
        series: One volume for each echo time, on one grid.
        echo_times: The echo times, two or more, rising.
        threshold: The signal that each signal of a voxel must be above.
            0 or more.

    Returns:
        The T2 map in ms and the S0 map, with a window that fits each.

    Raises:
        Error: If the times are not valid, there is not one volume for each
            time, the volumes have different grids, or the threshold is
            not finite or is below 0.
    """
    var x = _times(echo_times, 2)
    var time = _zeros(series, len(x), threshold)
    var amplitude = time.copy()
    for at in range(time.count()):  # pragma: no branch
        var y = List[Float64]()
        for volume in series:  # pragma: no branch
            var s = Float64(volume.values[at])
            if not (s > threshold) or not isfinite(s):
                break
            y.append(log(s))
        if len(y) != len(x):
            continue
        var fit = _line(x, y)
        if not (fit[0] < 0):
            continue
        time.values[at] = Float32(-1.0 / fit[0])
        amplitude.values[at] = Float32(precise_exp(fit[1]))
    time.fit_window()
    amplitude.fit_window()
    return RelaxationMaps(time^, amplitude^)


def t1_maps(
    series: List[ImageVolume],
    inversion_times: List[Duration64],
    threshold: Float64,
) raises -> RelaxationMaps:
    """Fit T1 at each voxel of an inversion recovery series.

    The signals pass near 0 at the null, so a voxel has a fit when its
    signal at the longest inversion time is above the threshold, and each
    signal is finite.

    Args:
        series: One magnitude volume for each inversion time, on one grid.
        inversion_times: The inversion times, four or more, rising.
        threshold: The signal at the longest time must be above it. 0 or
            more.

    Returns:
        The T1 map in ms and the A map, with a window that fits each.

    Raises:
        Error: If the times are not valid, there is not one volume for each
            time, the volumes have different grids, the threshold is not
            finite or is below 0, or a fit meets a singular system.
    """
    var x = _times(inversion_times, 4)
    var time = _zeros(series, len(x), threshold)
    var amplitude = time.copy()
    var last = len(x) - 1
    for at in range(time.count()):  # pragma: no branch
        var y = List[Float64]()
        for volume in series:  # pragma: no branch
            y.append(Float64(volume.values[at]))
        var usable = True
        for s in y:  # pragma: no branch
            usable = usable and isfinite(s) and s >= 0
        if not usable or not (y[last] > threshold):
            continue
        var fit = _t1(x, y)
        time.values[at] = Float32(fit.t1.to(MILLISECOND64))
        amplitude.values[at] = Float32(fit.a)
    time.fit_window()
    amplitude.fit_window()
    return RelaxationMaps(time^, amplitude^)
