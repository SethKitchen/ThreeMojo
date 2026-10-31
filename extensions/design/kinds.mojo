# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The kinds of a design check.

A `WindExposure` is the exposure category of ASCE/SEI 7-16 section
26.7: the roughness of the ground upwind of a building. An `AnchorKind`
says how an anchor of ACI 318-19 chapter 17 gets into the concrete.
"""


@fieldwise_init
struct WindExposure(Equatable, ImplicitlyCopyable, Writable):
    """The exposure category B, C or D of ASCE 7-16 section 26.7.3."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three exposures.

        Returns:
            Whether the value is 0 to 2.
        """
        return self.value >= 0 and self.value < 3

    def name(self) -> String:
        """Return the code's letter of the exposure.

        Returns:
            B, C or D, or "?" if not valid.
        """
        if not self.is_valid():
            return "?"
        var names: List[String] = ["B", "C", "D"]
        return names[self.value]


# Urban, suburban and wooded terrain.
comptime EXPOSURE_B = WindExposure(0)
# Open terrain with scattered obstructions, and all that is not B or D.
comptime EXPOSURE_C = WindExposure(1)
# Flat, unobstructed areas and water surfaces.
comptime EXPOSURE_D = WindExposure(2)


@fieldwise_init
struct AnchorKind(Equatable, ImplicitlyCopyable, Writable):
    """A cast-in or a post-installed anchor, ACI 318-19 chapter 17."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two kinds.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value >= 0 and self.value < 2

    def name(self) -> String:
        """Return the name of the kind.

        Returns:
            "cast-in" or "post-installed", or "?" if not valid.
        """
        if not self.is_valid():
            return "?"
        var names: List[String] = ["cast-in", "post-installed"]
        return names[self.value]


# A headed stud, headed bolt or hooked bolt set before the pour.
comptime CAST_IN = AnchorKind(0)
# An expansion, undercut, screw or adhesive anchor set in hardened
# concrete.
comptime POST_INSTALLED = AnchorKind(1)
