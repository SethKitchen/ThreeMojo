# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Contact checks shared by the physics benches.

A bench steps bodies against a ground whose id is zero. The check counts
how many of those bodies have no contact with it.
"""

from extensions.physics.world import CollisionEvent


def bodies_missing_contact(events: List[CollisionEvent], bodies: Int) -> Int:
    """Return how many bodies from 1 through `bodies` miss body 0.

    Args:
        events: The contacts from one step.
        bodies: How many dynamic bodies were stepped. Body 0 is the ground.

    Returns:
        The count of bodies 1 through `bodies` that no event pairs with body 0.
    """
    var touched = List[Bool](length=bodies + 1, fill=False)
    for event in events:
        if event.other.value == 0 and event.body.value > 0:
            touched[event.body.value] = True
    var missing = 0
    for i in range(1, bodies + 1):
        if not touched[i]:
            missing += 1
    return missing
