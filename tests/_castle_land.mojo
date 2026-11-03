# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Grounds for the tests of a castle in a landscape: a small real one, and
grounds made by hand, with a known meadow, ramp and shelf."""

from extensions.castle.landscape import (
    Landscape,
    LandscapeSettings,
    _Grid,
    build_landscape,
    default_landscape,
)
from extensions.castle.plan import Point, point
from tests._castle_small import small_plan
from units.si import Length64, METER


def small_settings() -> LandscapeSettings:
    """Return a landscape that bakes in a blink: cells of 5 m, a reach of
    6.4 km, a coarse patch of mountains and few octaves.

    Returns:
        The settings.
    """
    var settings = default_landscape()
    settings.near_step = Length64(5.0, METER)
    settings.reach = Length64(6400.0, METER)
    settings.segments = 64
    settings.octaves = 4
    return settings


def small_landscape() raises -> Landscape:
    """Return the cut-down castle in a small landscape.

    Returns:
        The landscape.

    Raises:
        Error: If the plan or the settings are refused.
    """
    return build_landscape(small_plan(), small_settings())


def _far_moat() -> List[Point]:
    """Return a square moat 4 km from the middle of the ground."""
    var moat = List[Point]()
    moat.append(point(4000.0, 4000.0))
    moat.append(point(4100.0, 4000.0))
    moat.append(point(4100.0, 4100.0))
    moat.append(point(4000.0, 4100.0))
    return moat^


def meadow(height: Float64 = 5.0) -> Landscape:
    """Return a level meadow, 4 km across, on a grid of 100 m, with the moat
    far away.

    Args:
        height: The height of the meadow over the water, in meters.

    Returns:
        The landscape, whose snow and tree lines are the defaults.
    """
    var grid = _Grid(-2000.0, -2000.0, 100.0, 41, 2000.0, 0.0)
    for at in range(41 * 41):
        grid.heights[at] = height
    var rings = List[_Grid]()
    rings.append(grid^)
    return Landscape(
        default_landscape(), 0.0, 0.0, 0.0, 2.0, rings^, _far_moat()
    )


def plateau() -> Landscape:
    """Return a ground on a grid of 10 m with a level plateau 5 m over the
    water, a ramp of 56 degrees and a shelf 100 m high on the east, a flat
    field 1 m over the water on the south, and a moat to the south.

    Returns:
        The landscape.
    """
    var grid = _Grid(-200.0, -200.0, 10.0, 41, 200.0, 0.0)
    for j in range(41):
        for i in range(41):
            var height = 5.0
            if j < 5:
                height = 1.0
            if i >= 30:
                height = 5.0 + 15.0 * Float64(i - 29)
            if i >= 36:
                height = 100.0
            grid.heights[j * 41 + i] = height
    var rings = List[_Grid]()
    rings.append(grid^)
    var moat = List[Point]()
    moat.append(point(-20.0, -120.0))
    moat.append(point(20.0, -120.0))
    moat.append(point(20.0, -80.0))
    moat.append(point(-20.0, -80.0))
    return Landscape(default_landscape(), 0.0, 0.0, 0.0, 2.0, rings^, moat^)


def rolling() -> Landscape:
    """Return a ground of hills on a grid of 10 m, every height different,
    with a moat far away.

    Returns:
        The landscape.
    """
    var grid = _Grid(-200.0, -200.0, 10.0, 41, 200.0, 0.0)
    for j in range(41):
        for i in range(41):
            grid.heights[j * 41 + i] = (
                5.0 + Float64((i * 7 + j * 13) % 11) + 0.5 * Float64(i % 3)
            )
    var rings = List[_Grid]()
    rings.append(grid^)
    return Landscape(
        default_landscape(), 0.0, 0.0, 0.0, 2.0, rings^, _far_moat()
    )
