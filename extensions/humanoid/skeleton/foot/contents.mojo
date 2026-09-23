# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which solids `add_foot` attaches.

Each named value is a bit. Combine layers with `plus`. `BOTH` is the
skeleton, the ligaments and the muscles. `ALL` is every layer.

    _ = add_foot(..., contents=MUSCLES)
    _ = add_foot(..., contents=BONES.plus(VESSELS))
    _ = add_foot(..., contents=ALL)
"""


@fieldwise_init
struct FootContents(Equatable, ImplicitlyCopyable, Writable):
    """Which tissue layers a connected foot draws.

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
        """Return True if this layer set draws the skeleton.

        Returns:
            True when the bones bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        self._require()
        return (self.value & BONES.value) != 0

    def includes_ligaments(self) raises -> Bool:
        """Return True if this layer set draws the ligaments.

        Returns:
            True when the ligaments bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        self._require()
        return (self.value & LIGAMENTS.value) != 0

    def includes_muscles(self) raises -> Bool:
        """Return True if this layer set draws muscles and tendons.

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
        """Return True if this layer set draws the lymphatic trunks.

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

    def plus(self, other: FootContents) raises -> FootContents:
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
            raise Error("Foot contents must be a named layer set")
        return FootContents(self.value | other.value)

    def _require(self) raises:
        """Refuse a value that is not a named layer set."""
        if not self.is_valid():
            raise Error("Foot contents must be a named layer set")


# Twenty-six bones of the foot.
comptime BONES = FootContents(1)
# Named ankle and foot ligaments.
comptime LIGAMENTS = FootContents(2)
# Intrinsic muscles and the extrinsic tendons in the foot.
comptime MUSCLES = FootContents(4)
# Arteries and veins of the foot.
comptime VESSELS = FootContents(8)
# Lymphatic trunks of the foot. Named nodes stay in the leg.
comptime LYMPH = FootContents(16)
# Named peripheral nerves.
comptime NERVES = FootContents(32)
# Skin envelope.
comptime SKIN = FootContents(64)
# Dorsal and digital hair shafts.
comptime HAIR = FootContents(128)
# Skeleton, ligaments and muscles together.
comptime BOTH = FootContents(7)
# Skin envelope and hair shafts.
comptime INTEGUMENT = FootContents(192)
# Every named layer.
comptime ALL = FootContents(255)
