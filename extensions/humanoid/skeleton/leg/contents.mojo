# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which solids `add_leg` attaches.

Each named value is a bit. Combine layers with `plus`. `BOTH` is bones
and muscles. `ALL` is every layer.

    _ = add_leg(..., contents=MUSCLES)
    _ = add_leg(..., contents=BONES.plus(VESSELS))
    _ = add_leg(..., contents=ALL)
"""


@fieldwise_init
struct LegContents(Equatable, ImplicitlyCopyable, Writable):
    """Which tissue layers a connected leg draws.

    The type stops a bare integer at compile time. A value outside the
    named bits is still constructible, and the boundary that reads it
    refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a non-empty set of named layers."""
        if self.value <= 0:
            return False
        return self.value <= ALL.value

    def includes_bones(self) raises -> Bool:
        """Return True if this layer set draws the bones and knee tissues.

        Returns:
            True when the bones bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        self._require()
        return (self.value & BONES.value) != 0

    def includes_muscles(self) raises -> Bool:
        """Return True if this layer set draws the skeletal muscles.

        Returns:
            True when the muscles bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        self._require()
        return (self.value & MUSCLES.value) != 0

    def includes_vessels(self) raises -> Bool:
        """Return True if this layer set draws the arteries and veins.

        Returns:
            True when the vessels bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        self._require()
        return (self.value & VESSELS.value) != 0

    def includes_lymph(self) raises -> Bool:
        """Return True if this layer set draws the lymph nodes and trunks.

        Returns:
            True when the lymph bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        self._require()
        return (self.value & LYMPH.value) != 0

    def includes_nerves(self) raises -> Bool:
        """Return True if this layer set draws the peripheral nerves.

        Returns:
            True when the nerves bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        self._require()
        return (self.value & NERVES.value) != 0

    def includes_skin(self) raises -> Bool:
        """Return True if this layer set draws the skin envelope.

        Returns:
            True when the skin bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        self._require()
        return (self.value & SKIN.value) != 0

    def includes_hair(self) raises -> Bool:
        """Return True if this layer set draws the hair shafts.

        Returns:
            True when the hair bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        self._require()
        return (self.value & HAIR.value) != 0

    def plus(self, other: LegContents) raises -> LegContents:
        """Return the union of this set and `other`.

        Args:
            other: Another named layer set.

        Returns:
            Every bit from either set.

        Raises:
            Error: If this value or `other` is not a named layer set.
        """
        self._require()
        if not other.is_valid():
            raise Error("Leg contents must be a named layer set")
        return LegContents(self.value | other.value)

    def _require(self) raises:
        """Refuse a value that is not a named layer set."""
        if not self.is_valid():
            raise Error("Leg contents must be a named layer set")


# Cortical bones and the five knee tissues.
comptime BONES = LegContents(1)
# Named skeletal muscles and three connective-tissue solids.
comptime MUSCLES = LegContents(2)
# Arteries and veins of the leg.
comptime VESSELS = LegContents(4)
# Lymph nodes and lymphatic trunks.
comptime LYMPH = LegContents(8)
# Named peripheral nerves.
comptime NERVES = LegContents(16)
# Skin envelope.
comptime SKIN = LegContents(32)
# Hair shafts on the thigh and calf.
comptime HAIR = LegContents(64)
# Bones, knee tissues and muscles together.
comptime BOTH = LegContents(3)
# Skin envelope and hair shafts.
comptime INTEGUMENT = LegContents(96)
# Every named layer.
comptime ALL = LegContents(127)
