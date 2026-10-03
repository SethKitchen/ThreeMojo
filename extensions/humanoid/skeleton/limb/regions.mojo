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

    def is_valid(self) -> Bool:
        """Return whether the region has a named density assignment."""
        return self.value >= 0 and self.value < 7


comptime DERMIS_REGION = LimbRegion(0)
comptime CORTICAL_REGION = LimbRegion(1)
comptime TRABECULAR_REGION = LimbRegion(2)
comptime MARROW_PROXY_REGION = LimbRegion(3)
comptime MUSCLE_REGION = LimbRegion(4)
comptime TENDON_REGION = LimbRegion(5)
comptime FAT_PROXY_REGION = LimbRegion(6)


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
