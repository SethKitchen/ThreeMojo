# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The id of a node program, apart from the node system itself.

A `Material` holds a `NodeProgramId`, so every module that builds a
material needs the type. It lives here so that those modules do not
compile `materials.nodes`, which is large.
"""


@fieldwise_init
struct NodeProgramId(Equatable, ImplicitlyCopyable, Writable):
    """Which program in a `NodeProgramStore`, as a type rather than a bare
    int. See `core.object3d.NodeId` for why these are wrapped."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this can name a program, or is `NO_NODES`.

        Returns:
            Whether the value is zero or more, or is `NO_NODES`.
        """
        return self.value >= 0 or self == NO_NODES


# What a material holds when no graph replaces any of its shading.
comptime NO_NODES = NodeProgramId(-1)
