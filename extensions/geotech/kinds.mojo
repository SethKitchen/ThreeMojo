# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The kinds of a retaining-wall analysis.

A `LoadKind` names a load the way AASHTO LRFD Table 3.4.1-1 does, so that
each load gets its own factor. A `PipeRun` says which way a buried pipe
runs through a wall section. A `ContactMode` says how much of a footing
bears on the soil. A `FailureMode` names one way a wall can fail.
"""


@fieldwise_init
struct LoadKind(Equatable, ImplicitlyCopyable, Writable):
    """The LRFD type of a load, which picks its load factor."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the nine load kinds.

        Returns:
            Whether the value is 0 to 8.
        """
        return self.value >= 0 and self.value < 9

    def name(self) -> String:
        """Return the code's short name of the load.

        Returns:
            DC, EV, EH, ES, LS, LS_V, WA, PW or EQ, or "?" if not valid.
        """
        var names: List[String] = [
            "DC",
            "EV",
            "EH",
            "ES",
            "LS",
            "LS_V",
            "WA",
            "PW",
            "EQ",
        ]
        if not self.is_valid():
            return "?"
        return names[self.value]


# The weight of the structure: concrete, pipe walls.
comptime DC = LoadKind(0)
# The vertical pressure of earth fill: soil on the heel.
comptime EV = LoadKind(1)
# The horizontal earth pressure.
comptime EH = LoadKind(2)
# An earth surcharge: rising ground behind the wall.
comptime ES = LoadKind(3)
# The live-load surcharge as a horizontal pressure, and top-of-wall loads.
comptime LS = LoadKind(4)
# The live-load surcharge as a vertical load on the heel. It is counted
# only where it is adverse: in the bearing check.
comptime LS_V = LoadKind(5)
# Water: the net horizontal pressure of unequal water levels.
comptime WA = LoadKind(6)
# The water inside a pipe barrel.
comptime PW = LoadKind(7)
# The horizontal inertia of an earthquake.
comptime EQ = LoadKind(8)


@fieldwise_init
struct PipeRun(Equatable, ImplicitlyCopyable, Writable):
    """Which way a buried pipe runs, relative to the wall."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is ACROSS or ALONG.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value == 0 or self.value == 1


# The pipe crosses the wall: a panel length of wall shares its volume.
comptime ACROSS = PipeRun(0)
# The pipe runs along the wall: each length of wall holds that length of pipe.
comptime ALONG = PipeRun(1)


@fieldwise_init
struct ContactMode(Equatable, ImplicitlyCopyable, Writable):
    """How much of a footing's base is in compression."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three contact modes.

        Returns:
            Whether the value is 0 to 2.
        """
        return self.value >= 0 and self.value < 3


# The whole base is in compression: a trapezoid.
comptime FULL_CONTACT = ContactMode(0)
# The heel lifts: a triangle from the toe.
comptime TOE_TRIANGLE = ContactMode(1)
# The toe lifts: a triangle from the heel.
comptime HEEL_TRIANGLE = ContactMode(2)


@fieldwise_init
struct FailureMode(Equatable, ImplicitlyCopyable, Writable):
    """One way a retaining wall can fail."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the nine failure modes.

        Returns:
            Whether the value is 0 to 8.
        """
        return self.value >= 0 and self.value < 9

    def name(self) -> String:
        """Return a short name of the failure mode.

        Returns:
            The name, or "?" if not valid.
        """
        var names: List[String] = [
            "sliding",
            "overturning",
            "bearing",
            "global slip",
            "stem flexure",
            "stem shear",
            "heel flexure",
            "toe flexure",
            "service pressure",
        ]
        if not self.is_valid():
            return "?"
        return names[self.value]


# The wall slides along its base.
comptime SLIDING = FailureMode(0)
# The resultant leaves the middle of the base and the wall tips over its toe.
comptime OVERTURNING = FailureMode(1)
# The soil under the footing fails in shear and the wall sinks and tilts.
comptime BEARING = FailureMode(2)
# A deep circular surface through the soil carries the wall away.
comptime GLOBAL_SLIP = FailureMode(3)
# The stem cracks and hinges at its base.
comptime STEM_FLEXURE = FailureMode(4)
# The stem shears off at its base.
comptime STEM_SHEAR = FailureMode(5)
# The heel cracks at the back face of the stem.
comptime HEEL_FLEXURE = FailureMode(6)
# The toe cracks at the front face of the stem.
comptime TOE_FLEXURE = FailureMode(7)
# The service pressure under the footing passes the allowed pressure.
comptime SERVICE_PRESSURE = FailureMode(8)
