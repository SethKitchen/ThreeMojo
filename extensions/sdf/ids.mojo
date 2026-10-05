# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The ids and kinds a distance field sculpt carries.

Each is a type, so a bare integer cannot stand in for one. A value the
type can hold but the code does not accept is refused where it is read.
"""

# How many surface parts there are.
comptime SURFACE_PART_COUNT = 12


@fieldwise_init
struct PrimitiveKind(Equatable, ImplicitlyCopyable, Writable):
    """Which solid a sculpt primitive is.

    `ELLIPSOID` is a turned ellipsoid. `CONE` is a round cone between two
    balls. `LENS` is an almond prism, the eye aperture. `FIN` is a planar
    polygon given a thickness and a rounded rim.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the four solids.

        Returns:
            Whether the value is from zero to three.
        """
        return self.value >= 0 and self.value < 4


comptime ELLIPSOID = PrimitiveKind(0)
comptime CONE = PrimitiveKind(1)
comptime LENS = PrimitiveKind(2)
comptime FIN = PrimitiveKind(3)


@fieldwise_init
struct BoneId(Equatable, ImplicitlyCopyable, Writable):
    """The bone a primitive rides: an index into its rig's bones.

    `is_valid` checks the sign only. A rig checks the upper bound.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative.

        Returns:
            Whether the value can index a bone.
        """
        return self.value >= 0


@fieldwise_init
struct TagId(Equatable, ImplicitlyCopyable, Writable):
    """One anatomical tag of a sculpt: its index in `SdfModel.tags`.

    Tags name what a primitive is, such as `nose` or `claw`. A painter
    reads them to color each region.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative.

        Returns:
            Whether the value can index a tag.
        """
        return self.value >= 0


@fieldwise_init
struct SurfacePart(Equatable, ImplicitlyCopyable, Writable):
    """Which separate surface a primitive belongs to.

    Primitives of one part blend into one skin. Parts are meshed apart:
    a lower jaw can stay a surface of its own, so a mouth can open. A
    sculpt names its parts; part zero is the main skin.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the parts.

        Returns:
            Whether the value is from zero to `SURFACE_PART_COUNT - 1`.
        """
        return self.value >= 0 and self.value < SURFACE_PART_COUNT


def require_part(part: SurfacePart) raises:
    """Refuse a surface part that is not one of the named parts.

    Args:
        part: The part to check.

    Raises:
        Error: If `part` is not valid.
    """
    if not part.is_valid():
        raise Error("Surface part must be from 0 to 11")


def require_kind(kind: PrimitiveKind) raises:
    """Refuse a primitive kind that is not one of the four solids.

    Args:
        kind: The kind to check.

    Raises:
        Error: If `kind` is not valid.
    """
    if not kind.is_valid():
        raise Error("Primitive kind must be from 0 to 3")
