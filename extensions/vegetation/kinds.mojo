# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The kinds of plant a blade can be, and what a frame does with a cluster.

`PlantKind` and `ClusterFate` are types and not integers, and each has
`is_valid`. The type stops a bare integer at compile time. A value that
no name stands for is still constructible, and the boundary that reads it
refuses it.
"""

from core.ordinal import ordinal_label, require_valid


@fieldwise_init
struct PlantKind(Equatable, ImplicitlyCopyable, Writable):
    """What one blade of a field is: green grass, dry grass, a poppy, a
    stalk with a seed head, or a low broad-leaf plant."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 5 kinds.

        Returns:
            Whether the value is 0 to 4.
        """
        return self.value >= 0 and self.value < 5

    def name(self) -> String:
        """Return the kind's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        var names: List[String] = [
            "grass",
            "dry grass",
            "poppy",
            "seed head",
            "broad leaf",
        ]
        return ordinal_label(self.is_valid(), self.value, names, "unknown")


# A green blade, dark at the root and yellow-green at the tip.
comptime GRASS = PlantKind(0)
# A dry blade, straw at the tip. A few of these break up the green.
comptime DRY_GRASS = PlantKind(1)
# A thin stem with a red cup of petals at its tip.
comptime POPPY = PlantKind(2)
# A tall thin stalk with a spike of seeds at its tip, above the grass.
comptime SEED_HEAD = PlantKind(3)
# A low rosette of broad leaves under the grass, as a plantain or a dock.
comptime BROADLEAF = PlantKind(4)


def require_plant_kind(kind: PlantKind) raises:
    """Refuse a plant kind that no name stands for.

    Args:
        kind: The kind to check.

    Raises:
        Error: If `kind` is not valid.
    """
    require_valid(
        kind.is_valid(),
        (
            "A plant kind must be grass, dry grass, a poppy, a seed head or a"
            " broad leaf"
        ),
    )


@fieldwise_init
struct ClusterFate(Equatable, ImplicitlyCopyable, Writable):
    """What one frame does with a cluster of grass: draw it, cull it, or
    leave it to the ground because it is past the last level of detail."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 3 fates.

        Returns:
            Whether the value is 0, 1 or 2.
        """
        return self.value >= 0 and self.value < 3

    def name(self) -> String:
        """Return the fate's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        var names: List[String] = ["drawn", "culled", "beyond"]
        return ordinal_label(self.is_valid(), self.value, names, "unknown")


# The cluster is in view and near enough: it is built and drawn.
comptime DRAWN = ClusterFate(0)
# The cluster's bound is outside the view: it is not built.
comptime CULLED = ClusterFate(1)
# The cluster is past the reach of the last level: the ground stands in.
comptime BEYOND = ClusterFate(2)


def require_cluster_fate(fate: ClusterFate) raises:
    """Refuse a cluster fate that no name stands for.

    Args:
        fate: The fate to check.

    Raises:
        Error: If `fate` is not valid.
    """
    require_valid(
        fate.is_valid(), "A cluster fate must be drawn, culled or beyond"
    )
