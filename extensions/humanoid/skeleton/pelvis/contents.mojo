# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which solids `add_pelvis` attaches.

Each named value is a bit. Combine layers with `plus`. `BOTH` is the
skeleton, the ligaments and the muscles. `ALL` is every layer.

    _ = add_pelvis(..., contents=MUSCLES)
    _ = add_pelvis(..., contents=BONES.plus(VESSELS))
    _ = add_pelvis(..., contents=ALL)
"""

from extensions.humanoid.skeleton.layer_set import (
    layer_includes,
    layer_set_valid,
    layer_union,
)

comptime _MESSAGE = "Pelvis contents must be a named layer set"


@fieldwise_init
struct PelvisContents(Equatable, ImplicitlyCopyable, Writable):
    """Which tissue layers a connected pelvis draws.

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

    def plus(self, other: PelvisContents) raises -> PelvisContents:
        """Return the union of this set and `other`.

        Args:
            other: Another named layer set.

        Returns:
            Every bit from either set.

        Raises:
            Error: If this value or `other` is not a named layer set.
        """
        return PelvisContents(
            layer_union(self.value, other.value, ALL.value, _MESSAGE)
        )


def require_pelvis_contents(contents: PelvisContents) raises:
    """Refuse a pelvis layer set that is not named.

    Args:
        contents: Which tissue layers a pelvis draws.

    Returns:
        Nothing. The call returns when the set is named.

    Raises:
        Error: If the set is not a named layer set.
    """
    if not contents.is_valid():
        raise Error(_MESSAGE)


# The two hip bones, the sacrum and the coccyx.
comptime BONES = PelvisContents(1)
# Named pelvic ligaments, the labrum, the socket's cartilage and the
# interpubic disc.
comptime LIGAMENTS = PelvisContents(2)
# Named pelvic muscles.
comptime MUSCLES = PelvisContents(4)
# Arteries and veins of the pelvis.
comptime VESSELS = PelvisContents(8)
# Pelvic node groups and the iliac lymphatic trunk.
comptime LYMPH = PelvisContents(16)
# Named pelvic nerves.
comptime NERVES = PelvisContents(32)
# Skin envelope.
comptime SKIN = PelvisContents(64)
# Skeleton, ligaments and muscles together.
comptime BOTH = PelvisContents(7)
# Every named layer.
comptime ALL = PelvisContents(127)
