# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a castle is built of, how its roofs are shaped, and where a number
came from.

A `Material` names a surface of the mesh view, which gets its own color and
texture. A `RoofKind` says how a tower or a wing is covered. A `Provenance`
says how a dimension of a plan was found. It is the reason a plan can claim
real dimensions: the plan of Wijnendale marks each figure as surveyed,
measured, documented or estimated, and never lets an estimate pass as a
survey.

Each is a type and not an integer, and each has `is_valid`. The type stops a
bare integer at compile time. A value that no name stands for is still
constructible, and the boundary that reads it refuses it.
"""


@fieldwise_init
struct Material(Equatable, ImplicitlyCopyable, Writable):
    """What a surface of the mesh view is made of."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 11 materials.

        Returns:
            Whether the value is 0 to 10.
        """
        return self.value >= 0 and self.value < 11

    def name(self) -> String:
        """Return the material's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        var names: List[String] = [
            "brick",
            "stone",
            "slate",
            "water",
            "lawn",
            "gravel",
            "foliage",
            "glass",
            "wood",
            "metal",
            "bark",
        ]
        return names[self.value]


# Red brick: the walls and the arches.
comptime BRICK = Material(0)
# Dressed natural stone: the plinth, the corbels and the gate's openings.
comptime STONE = Material(1)
# Slate: the roofs and the spires.
comptime SLATE = Material(2)
# The water of the moat.
comptime WATER = Material(3)
# Grass: the island, the banks and the meadow.
comptime LAWN = Material(4)
# Gravel: the paths.
comptime GRAVEL = Material(5)
# The crowns of trees.
comptime FOLIAGE = Material(6)
# Window glass.
comptime GLASS = Material(7)
# Timber: window frames, doors, fences and the rails of a bridge.
comptime WOOD = Material(8)
# Lead and zinc: ridges, finials and flat roofs.
comptime METAL = Material(9)
# The trunks and branches of trees.
comptime BARK = Material(10)


@fieldwise_init
struct RoofKind(Equatable, ImplicitlyCopyable, Writable):
    """How the top of a tower, a wing or the gate is covered."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 3 roof kinds.

        Returns:
            Whether the value is 0 to 2.
        """
        return self.value >= 0 and self.value < 3

    def name(self) -> String:
        """Return the roof kind's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        var names: List[String] = ["gable", "cone", "flat"]
        return names[self.value]


# Two slopes that meet at a ridge along the axis of a wing.
comptime GABLE = RoofKind(0)
# A spire over a round tower.
comptime CONE = RoofKind(1)
# A flat top behind a crenellated parapet.
comptime FLAT = RoofKind(2)


@fieldwise_init
struct Provenance(Equatable, ImplicitlyCopyable, Writable):
    """How a dimension of a plan was found."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 4 provenances.

        Returns:
            Whether the value is 0 to 3.
        """
        return self.value >= 0 and self.value < 4

    def name(self) -> String:
        """Return the provenance's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        var names: List[String] = [
            "surveyed",
            "measured",
            "documented",
            "estimated",
        ]
        return names[self.value]


# Read from a survey of the site, to a few centimeters: the Flemish large
# scale reference map.
comptime SURVEYED = Provenance(0)
# Derived from a measurement that is not of the object itself: a height from
# the airborne laser scan, to about a meter.
comptime MEASURED = Provenance(1)
# Stated in a heritage record or a standard, with no survey behind it.
comptime DOCUMENTED = Provenance(2)
# Assumed from typical practice or read from a photograph. It is a guess.
comptime ESTIMATED = Provenance(3)
