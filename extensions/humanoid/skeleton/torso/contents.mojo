# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which solids `add_torso` attaches.

Each named value is a bit. Combine layers with `plus`. `BOTH` is the
skeleton, the ligaments and the muscles. `ALL` is every layer.

    _ = add_torso(..., contents=MUSCLES)
    _ = add_torso(..., contents=BONES.plus(VESSELS))
    _ = add_torso(..., contents=ALL)
"""


@fieldwise_init
struct TorsoContents(Equatable, ImplicitlyCopyable, Writable):
    """Which tissue layers a connected torso draws.

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

    def plus(self, other: TorsoContents) raises -> TorsoContents:
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
            raise Error("Torso contents must be a named layer set")
        return TorsoContents(self.value | other.value)

    def _require(self) raises:
        """Refuse a value that is not a named layer set."""
        if not self.is_valid():
            raise Error("Torso contents must be a named layer set")


# The vertebrae, the ribs and the sternum.
comptime BONES = TorsoContents(1)
# The intervertebral discs, the costal cartilages and the spinal
# ligaments.
comptime LIGAMENTS = TorsoContents(2)
# Named torso muscles.
comptime MUSCLES = TorsoContents(4)
# Arteries and veins of the torso.
comptime VESSELS = TorsoContents(8)
# The cisterna chyli, the thoracic duct and the node groups.
comptime LYMPH = TorsoContents(16)
# The spinal cord and the named nerves.
comptime NERVES = TorsoContents(32)
# Skin envelope.
comptime SKIN = TorsoContents(64)
# Skeleton, ligaments and muscles together.
comptime BOTH = TorsoContents(7)
# Every named layer.
comptime ALL = TorsoContents(127)
