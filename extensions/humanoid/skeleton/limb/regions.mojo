# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exclusive density assignments in the canonical lower-limb integral.

These are accounting regions, not independently measured tissue volumes.
Bone pores are included in the apparent-density regions. Their fluid and
marrow mass is not added separately. Unresolved soft tissue uses fat as
an explicit density proxy.
"""


@fieldwise_init
struct LimbRegion(Equatable, ImplicitlyCopyable, Writable):
    """A named exclusive density assignment, never a bare integer."""

    var value: Int
    """Encoded region index; consumers must call is_valid."""

    def is_valid(self) -> Bool:
        """Return whether the region has a named density assignment.

        Returns:
            True for one of the seven named assignments.
        """
        return self.value >= 0 and self.value < 7


comptime DERMIS_REGION = LimbRegion(0)
"""The outer dermal shell assignment."""
comptime CORTICAL_REGION = LimbRegion(1)
"""Bone tissue mass at cortical apparent density."""
comptime TRABECULAR_REGION = LimbRegion(2)
"""Bone tissue mass at trabecular apparent density."""
comptime MARROW_PROXY_REGION = LimbRegion(3)
"""Medullary space assigned the named fat density proxy."""
comptime MUSCLE_REGION = LimbRegion(4)
"""The first matching muscle-belly assignment."""
comptime TENDON_REGION = LimbRegion(5)
"""The first matching tendon assignment."""
comptime FAT_PROXY_REGION = LimbRegion(6)
"""Unresolved interior assigned the named fat density proxy."""


def region_label(region: LimbRegion) raises -> String:
    """Return a stable machine-readable name for a density assignment.

    Args:
        region: One of the seven named limb regions.

    Returns:
        The report key.

    Raises:
        Error: If `region` is not named.
    """
    if not region.is_valid():
        raise Error("A limb region must name an exclusive density assignment")
    var names: List[String] = [
        "dermis",
        "cortical_apparent",
        "trabecular_apparent",
        "marrow_fat_proxy",
        "muscle",
        "tendon",
        "unresolved_fat_proxy",
    ]
    return names[region.value]
