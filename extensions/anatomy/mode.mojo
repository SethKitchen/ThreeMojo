# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whether a body is drawn to look right or to measure right.

Game mode draws the coat, the fur and the baked shadows, and it can
change any shape that reads better. Engineering mode draws the tissues
as they are measured: bone, muscle and skin, each in one flat color,
with no noise on the normals and no baked occlusion. Its mass, inertia
and muscle forces are in SI units and carry their sources.
"""


@fieldwise_init
struct AnatomyMode(Equatable, ImplicitlyCopyable, Writable):
    """How a body is drawn and what its numbers are fit for."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is a named mode.

        Returns:
            True for game or engineering mode.
        """
        return self == GAME_MODE or self == ENGINEERING_MODE


# Visuals first: the coat, fur and baked shadows.
comptime GAME_MODE = AnatomyMode(0)
# Measured values first: tissues in flat colors, typed SI outputs.
comptime ENGINEERING_MODE = AnatomyMode(1)


def require_mode(mode: AnatomyMode) raises:
    """Refuse a mode that has no name.

    Args:
        mode: The requested mode.

    Raises:
        Error: If the mode is not game or engineering.
    """
    if not mode.is_valid():
        raise Error("An anatomy mode must be game or engineering")
