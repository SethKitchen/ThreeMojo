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

from extensions.humanoid.skeleton.layer_set import (
    layer_includes,
    layer_set_valid,
    layer_union,
)

comptime _MESSAGE = "Foot contents must be a named layer set"


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
        return layer_set_valid(self.value, ALL.value)

    def includes_bones(self) raises -> Bool:
        """Return True if this layer set draws the skeleton.

        Returns:
            True when the bones bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        return layer_includes(self.value, BONES.value, ALL.value, _MESSAGE)

    def includes_ligaments(self) raises -> Bool:
        """Return True if this layer set draws the ligaments.

        Returns:
            True when the ligaments bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        return layer_includes(self.value, LIGAMENTS.value, ALL.value, _MESSAGE)

    def includes_muscles(self) raises -> Bool:
        """Return True if this layer set draws muscles and tendons.

        Returns:
            True when the muscles bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        return layer_includes(self.value, MUSCLES.value, ALL.value, _MESSAGE)

    def includes_vessels(self) raises -> Bool:
        """Return True if this layer set draws the arteries and veins.

        Returns:
            True when the vessels bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        return layer_includes(self.value, VESSELS.value, ALL.value, _MESSAGE)

    def includes_lymph(self) raises -> Bool:
        """Return True if this layer set draws the lymphatic trunks.

        Returns:
            True when the lymph bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        return layer_includes(self.value, LYMPH.value, ALL.value, _MESSAGE)

    def includes_nerves(self) raises -> Bool:
        """Return True if this layer set draws the peripheral nerves.

        Returns:
            True when the nerves bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        return layer_includes(self.value, NERVES.value, ALL.value, _MESSAGE)

    def includes_skin(self) raises -> Bool:
        """Return True if this layer set draws the skin envelope.

        Returns:
            True when the skin bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        return layer_includes(self.value, SKIN.value, ALL.value, _MESSAGE)

    def includes_hair(self) raises -> Bool:
        """Return True if this layer set draws the hair shafts.

        Returns:
            True when the hair bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        return layer_includes(self.value, HAIR.value, ALL.value, _MESSAGE)

    def plus(self, other: FootContents) raises -> FootContents:
        """Return the union of this set and `other`.

        Args:
            other: Another named layer set.

        Returns:
            Every bit from either set.

        Raises:
            Error: If this value or `other` is not a named layer set.
        """
        return FootContents(
            layer_union(self.value, other.value, ALL.value, _MESSAGE)
        )


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
