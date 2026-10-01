# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which solids `add_arm` attaches.

Each named value is a bit. Combine layers with `plus`. `BOTH` is the
skeleton, the ligaments and the muscles. `ALL` is every layer.

    _ = add_arm(..., contents=MUSCLES)
    _ = add_arm(..., contents=BONES.plus(VESSELS))
    _ = add_arm(..., contents=ALL)
"""


@fieldwise_init
struct ArmContents(Equatable, ImplicitlyCopyable, Writable):
    """Which tissue layers an arm draws.

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
        """Return True if this layer set draws the hair.

        Returns:
            True when the hair bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        self._require()
        return (self.value & HAIR.value) != 0

    def plus(self, other: ArmContents) raises -> ArmContents:
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
            raise Error("Arm contents must be a named layer set")
        return ArmContents(self.value | other.value)

    def _require(self) raises:
        """Refuse a value that is not a named layer set."""
        if not self.is_valid():
            raise Error("Arm contents must be a named layer set")


# The humerus, the radius and the ulna.
comptime BONES = ArmContents(1)
# The shoulder and elbow capsules, the articular cartilages, the
# collateral and annular ligaments and the interosseous membrane.
comptime LIGAMENTS = ArmContents(2)
# Named muscles of the arm and the forearm, and their tendons.
comptime MUSCLES = ArmContents(4)
# Arteries and veins of the arm.
comptime VESSELS = ArmContents(8)
# Lymph nodes and collecting vessels of the arm.
comptime LYMPH = ArmContents(16)
# The named nerves of the arm.
comptime NERVES = ArmContents(32)
# Skin envelope.
comptime SKIN = ArmContents(64)
# Hair on the skin.
comptime HAIR = ArmContents(128)
# Skeleton, ligaments and muscles together.
comptime BOTH = ArmContents(7)
# Every named layer.
comptime ALL = ArmContents(255)
