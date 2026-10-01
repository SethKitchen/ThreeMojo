# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which solids `add_head` attaches.

Each named value is a bit. Combine layers with `plus`. `BOTH` is the
skeleton, the ligaments and the muscles. `ALL` is every layer, the
eyes and the mouth too.

    _ = add_head(..., contents=MUSCLES)
    _ = add_head(..., contents=BONES.plus(VESSELS))
    _ = add_head(..., contents=ALL)
"""


@fieldwise_init
struct HeadContents(Equatable, ImplicitlyCopyable, Writable):
    """Which tissue layers a neck and head draw.

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

    def includes_eyes(self) raises -> Bool:
        """Return True if this layer set draws the eyeballs.

        Returns:
            True when the eyes bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        self._require()
        return (self.value & EYES.value) != 0

    def includes_mouth(self) raises -> Bool:
        """Return True if this layer set draws the teeth, the gums and
        the tongue.

        Returns:
            True when the mouth bit is set.

        Raises:
            Error: If this value is not a named layer set.
        """
        self._require()
        return (self.value & MOUTH.value) != 0

    def plus(self, other: HeadContents) raises -> HeadContents:
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
            raise Error("Head contents must be a named layer set")
        return HeadContents(self.value | other.value)

    def _require(self) raises:
        """Refuse a value that is not a named layer set."""
        if not self.is_valid():
            raise Error("Head contents must be a named layer set")


# The seven cervical vertebrae, the skull, the mandible, the teeth and
# the hyoid.
comptime BONES = HeadContents(1)
# The cervical discs, the nuchal ligament and the jaw joints.
comptime LIGAMENTS = HeadContents(2)
# Named muscles of the neck, the jaw and the face.
comptime MUSCLES = HeadContents(4)
# Arteries and veins of the neck and the head.
comptime VESSELS = HeadContents(8)
# Lymph nodes of the neck.
comptime LYMPH = HeadContents(16)
# The named nerves of the neck and the face.
comptime NERVES = HeadContents(32)
# Skin envelope.
comptime SKIN = HeadContents(64)
# Hair of the scalp and the eyebrows.
comptime HAIR = HeadContents(128)
# The two eyeballs: sclera, iris and pupil.
comptime EYES = HeadContents(256)
# The teeth, the gums and the tongue of the scanned face, which move
# with its expressions.
comptime MOUTH = HeadContents(512)
# Skeleton, ligaments and muscles together.
comptime BOTH = HeadContents(7)
# Every named layer.
comptime ALL = HeadContents(1023)
