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

from extensions.humanoid.skeleton.layer_set import (
    layer_includes,
    layer_set_valid,
    layer_union,
)

comptime _MESSAGE = "Torso contents must be a named layer set"


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

    def plus(self, other: TorsoContents) raises -> TorsoContents:
        """Return the union of this set and `other`.

        Args:
            other: Another named layer set.

        Returns:
            Every bit from either set.

        Raises:
            Error: If this value or `other` is not a named layer set.
        """
        return TorsoContents(
            layer_union(self.value, other.value, ALL.value, _MESSAGE)
        )


def require_torso_contents(contents: TorsoContents) raises:
    """Refuse a torso layer set that is not named.

    Args:
        contents: Which tissue layers a torso draws.

    Returns:
        Nothing. The call returns when the set is named.

    Raises:
        Error: If the set is not a named layer set.
    """
    if not contents.is_valid():
        raise Error(_MESSAGE)


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
