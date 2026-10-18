# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Match a shadow map, a spot map, or a spot profile to its light.

Each of those records names one light. The search is the same.
"""


trait LightSlot(Copyable, Movable):
    """A record that belongs to one scene light."""

    def slot_light(self) -> Int:
        """Return which scene light this belongs to.

        Returns:
            The light's index in `scene.lights`.
        """
        ...


def index_of_light[T: LightSlot](items: List[T], light: Int) -> Int:
    """Return which item belongs to `light`, or -1.

    Args:
        items: The maps or profiles, in order.
        light: The light's index in `scene.lights`.

    Returns:
        The first place, or -1 when none belongs to `light`.
    """
    for slot in range(len(items)):
        if items[slot].slot_light() == light:
            return slot
    return -1
