# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The kinds of a building model: elements, openings, space uses and
section shapes."""


@fieldwise_init
struct ElementKind(Equatable, ImplicitlyCopyable, Writable):
    """What a building element is."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 5 kinds.

        Returns:
            Whether the value is 0 to 4.
        """
        return self.value >= 0 and self.value < 5

    def name(self) -> String:
        """Return the kind's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        var names: List[String] = ["wall", "slab", "roof", "column", "beam"]
        return names[self.value]


# A vertical element on a wall face of the cell complex.
comptime WALL = ElementKind(0)
# A floor or a ground slab on a horizontal face.
comptime SLAB = ElementKind(1)
# A slab with the outside above it.
comptime ROOF = ElementKind(2)
# A vertical frame member on an axis.
comptime COLUMN = ElementKind(3)
# A horizontal frame member on an axis.
comptime BEAM = ElementKind(4)


@fieldwise_init
struct OpeningKind(Equatable, ImplicitlyCopyable, Writable):
    """What fills an opening in a wall."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 2 kinds.

        Returns:
            Whether the value is 0 to 1.
        """
        return self.value >= 0 and self.value < 2

    def name(self) -> String:
        """Return the kind's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        var names: List[String] = ["door", "window"]
        return names[self.value]


comptime DOOR = OpeningKind(0)
comptime WINDOW = OpeningKind(1)


@fieldwise_init
struct SpaceUse(Equatable, ImplicitlyCopyable, Writable):
    """What a space is used for. It sets loads, gains and furniture."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 12 kinds.

        Returns:
            Whether the value is 0 to 11.
        """
        return self.value >= 0 and self.value < 12

    def name(self) -> String:
        """Return the kind's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        var names: List[String] = [
            "office",
            "corridor",
            "core",
            "lobby",
            "retail",
            "living",
            "bedroom",
            "kitchen",
            "bathroom",
            "storage",
            "mechanical",
            "meeting",
        ]
        return names[self.value]


comptime OFFICE = SpaceUse(0)
comptime CORRIDOR = SpaceUse(1)
# Stairs, lifts and shafts.
comptime CORE = SpaceUse(2)
comptime LOBBY = SpaceUse(3)
comptime RETAIL = SpaceUse(4)
comptime LIVING = SpaceUse(5)
comptime BEDROOM = SpaceUse(6)
comptime KITCHEN = SpaceUse(7)
comptime BATHROOM = SpaceUse(8)
comptime STORAGE = SpaceUse(9)
comptime MECHANICAL = SpaceUse(10)
comptime MEETING = SpaceUse(11)


@fieldwise_init
struct SectionShape(Equatable, ImplicitlyCopyable, Writable):
    """The shape of a frame member's cross-section."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 3 kinds.

        Returns:
            Whether the value is 0 to 2.
        """
        return self.value >= 0 and self.value < 3

    def name(self) -> String:
        """Return the kind's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        var names: List[String] = ["rectangle", "i_shape", "circle"]
        return names[self.value]


# A solid rectangle: width by depth.
comptime RECTANGLE = SectionShape(0)
# A doubly symmetric I: flanges of a width and a thickness, and a web.
comptime I_SHAPE = SectionShape(1)
# A solid circle: the width is the diameter.
comptime CIRCLE = SectionShape(2)
