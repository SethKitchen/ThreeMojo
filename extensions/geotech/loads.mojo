# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Loads on a wall section and their LRFD factors.

Each load is a force per unit length of wall with a kind, which picks its
factor, and an arm. A vertical load's arm is its distance from the toe,
the front edge of the footing. A lateral load's arm is its height above
the bottom of the footing, and it pushes toward the toe.

`LoadFactors` holds one factor per `LoadKind`. The presets are the
AASHTO LRFD Tables 3.4.1-1 and 3.4.1-2 values a cantilever wall uses:
the minimum vertical factors for eccentricity and sliding, the maximum
for bearing, Service I, and Extreme Event I.
"""

from std.math import isfinite
from extensions.geotech.kinds import LoadKind
from extensions.geotech.units import MomentPerLength64
from units.si import Length64, LineLoad64


@fieldwise_init
struct VerticalLoad(Copyable, Movable):
    """A downward load and its distance from the toe."""

    var kind: LoadKind
    var label: String
    var force: LineLoad64
    var arm: Length64


@fieldwise_init
struct LateralLoad(Copyable, Movable):
    """A load toward the toe and its height above the footing's base."""

    var kind: LoadKind
    var label: String
    var force: LineLoad64
    var arm: Length64


@fieldwise_init
struct LoadFactors(ImplicitlyCopyable, Writable):
    """One load factor per load kind."""

    var dc: Float64
    var ev: Float64
    var eh: Float64
    var es: Float64
    var ls: Float64
    # Zero leaves the live load on the heel out.
    var ls_v: Float64
    var wa: Float64
    var pw: Float64
    var eq: Float64

    def of(self, kind: LoadKind) raises -> Float64:
        """Return the factor of a load kind.

        Args:
            kind: The kind.

        Returns:
            Its factor.

        Raises:
            Error: If the kind is not valid.
        """
        if not kind.is_valid():
            raise Error("A load kind is not valid")
        var all: List[Float64] = [
            self.dc,
            self.ev,
            self.eh,
            self.es,
            self.ls,
            self.ls_v,
            self.wa,
            self.pw,
            self.eq,
        ]
        return all[kind.value]

    def write_to(self, mut writer: Some[Writer]):
        """Write the factors.

        Args:
            writer: Where to write.
        """
        writer.write(
            "LoadFactors(DC=",
            self.dc,
            ", EV=",
            self.ev,
            ", EH=",
            self.eh,
            ", ES=",
            self.es,
            ", LS=",
            self.ls,
            ", LS_V=",
            self.ls_v,
            ", WA=",
            self.wa,
            ", PW=",
            self.pw,
            ", EQ=",
            self.eq,
            ")",
        )


def strength_i_minimum() -> LoadFactors:
    """Return Strength I with the minimum vertical factors.

    For eccentricity and sliding: DC 0.90, EV 1.00, EH and ES 1.50,
    LS 1.75, no live load on the heel, WA and PW 1.00.

    Returns:
        The factors.
    """
    return LoadFactors(0.90, 1.00, 1.50, 1.50, 1.75, 0.0, 1.0, 1.0, 0.0)


def strength_i_maximum() -> LoadFactors:
    """Return Strength I with the maximum vertical factors.

    For bearing and member design: DC 1.25, EV 1.35, EH and ES 1.50,
    LS 1.75 on the heel too, WA and PW 1.00.

    Returns:
        The factors.
    """
    return LoadFactors(1.25, 1.35, 1.50, 1.50, 1.75, 1.75, 1.0, 1.0, 0.0)


def service_i() -> LoadFactors:
    """Return Service I: every load at 1.00, with live load on the heel.

    Returns:
        The factors.
    """
    return LoadFactors(1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0)


def extreme_event_i(live: Float64 = 0.5) -> LoadFactors:
    """Return Extreme Event I with the given live-load factor.

    Args:
        live: The factor on live load, 0.5 by default; none on the heel.

    Returns:
        The factors, with earthquake inertia at 1.00.
    """
    return LoadFactors(1.0, 1.0, 1.0, 1.0, live, 0.0, 1.0, 1.0, 1.0)


@fieldwise_init
struct Resultant(ImplicitlyCopyable):
    """The factored sums of the loads on a wall section."""

    var vertical: LineLoad64
    var horizontal: LineLoad64
    # The moment of the vertical loads about the toe.
    var resisting: MomentPerLength64
    # The moment of the lateral loads about the toe.
    var overturning: MomentPerLength64

    def location(self) raises -> Length64:
        """Return where the resultant crosses the base, from the toe.

        Returns:
            (resisting - overturning) / vertical.

        Raises:
            Error: If the vertical load is not positive.
        """
        if not (self.vertical.value > 0):
            raise Error("The vertical resultant must be positive")
        return Length64(
            (self.resisting.value - self.overturning.value)
            / self.vertical.value
        )


def factored(
    vertical: List[VerticalLoad],
    lateral: List[LateralLoad],
    factors: LoadFactors,
) raises -> Resultant:
    """Return the factored sums of a section's loads.

    Args:
        vertical: The vertical loads.
        lateral: The lateral loads.
        factors: The factors.

    Returns:
        The sums and moments about the toe.

    Raises:
        Error: If a load's kind is not valid or a value is not finite.
    """
    var v = Float64(0)
    var mr = Float64(0)
    var h = Float64(0)
    var mo = Float64(0)
    for load in vertical:
        var f = factors.of(load.kind)
        v += f * load.force.value
        mr += f * load.force.value * load.arm.value
    for load in lateral:
        var f = factors.of(load.kind)
        h += f * load.force.value
        mo += f * load.force.value * load.arm.value
    if not (isfinite(v) and isfinite(h) and isfinite(mr) and isfinite(mo)):
        raise Error("A load is not finite")
    return Resultant(
        LineLoad64(v),
        LineLoad64(h),
        MomentPerLength64(mr),
        MomentPerLength64(mo),
    )
