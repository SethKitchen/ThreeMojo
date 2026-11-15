# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The difference of two survival curves at a time, and the number needed
to treat, after Altman and Andersen (1999).

`survival_difference(treated, control, time)` gives
`S_treated(t) - S_control(t)` of two Kaplan-Meier curves, with the
standard error from the Greenwood variance of each curve, and its 95
percent interval. The number needed to treat (NNT) is its inverse: the
patients to treat for one more of them to be free of the event at the
time.

When the interval of the difference holds 0, the interval of the NNT runs
from a benefit through infinity to a harm. `nnt_interval` gives the
inverses of the two ends. The low end is then below 0: its size is the
number needed to harm.
"""

from extensions.clinical.survival import SurvivalCurve, Z95
from std.math import isfinite, sqrt
from units.si import Duration64, SECOND


struct SurvivalDifference(Copyable, Movable):
    """The difference of two survival curves at one time."""

    var time: Duration64
    """The time."""
    var treated: Float64
    """The survival of the treated group at the time."""
    var control: Float64
    """The survival of the control group at the time."""
    var difference: Float64
    """The treated survival less the control survival."""
    var standard_error: Float64
    """The standard error of the difference."""
    var lower: Float64
    """The low end of the 95 percent interval of the difference."""
    var upper: Float64
    """The high end of the 95 percent interval of the difference."""

    def __init__(
        out self,
        time: Duration64,
        treated: Float64,
        control: Float64,
        standard_error: Float64,
    ):
        """Create a difference, with its interval.

        Args:
            time: The time.
            treated: The treated survival.
            control: The control survival.
            standard_error: The standard error of the difference.
        """
        self.time = time
        self.treated = treated
        self.control = control
        self.difference = treated - control
        self.standard_error = standard_error
        self.lower = self.difference - Z95 * standard_error
        self.upper = self.difference + Z95 * standard_error

    def nnt(self) raises -> Float64:
        """Return the number needed to treat.

        Returns:
            `1 / difference`. Below 0 when the treated group does worse:
            then its size is the number needed to harm.

        Raises:
            Error: If the difference is 0.
        """
        if self.difference == 0:
            raise Error("Equal survivals need an infinite number to treat")
        return 1.0 / self.difference

    def nnt_interval(self) -> Tuple[Float64, Float64]:
        """Return the 95 percent interval of the number needed to treat.

        Returns:
            `1 / upper` and `1 / lower`. When the interval of the difference
            holds 0, the first is the least number needed to treat for a
            benefit, and the second is below 0: its size is the least number
            needed to harm, with infinity between them.
        """
        return (1.0 / self.upper, 1.0 / self.lower)


def _at(curve: SurvivalCurve, t: Float64) -> Tuple[Float64, Float64]:
    """Return the survival and its Greenwood variance at a time."""
    var survival = 1.0
    var greenwood = 0.0
    for i in range(len(curve.times)):
        if curve.times[i].to(SECOND) > t:
            break
        survival = curve.survival[i]
        greenwood = curve.greenwood[i]
    if survival == 0:
        return (0.0, 0.0)
    return (survival, survival * survival * greenwood)


def survival_difference(
    treated: SurvivalCurve, control: SurvivalCurve, time: Duration64
) raises -> SurvivalDifference:
    """Return the difference of two survival curves at a time.

    Args:
        treated: The Kaplan-Meier curve of the treated group.
        control: The Kaplan-Meier curve of the control group.
        time: The time, 0 or more and finite.

    Returns:
        The two survivals, their difference with its standard error, and the
        interval. A curve that falls to 0 has no variance from then on.

    Raises:
        Error: If the time is below 0 or not finite.
    """
    var t = time.to(SECOND)
    if not (t >= 0) or not isfinite(t):
        raise Error("The time of a survival difference must be 0 or more")
    var a = _at(treated, t)
    var b = _at(control, t)
    return SurvivalDifference(time, a[0], b[0], sqrt(a[1] + b[1]))
