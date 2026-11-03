# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A castle plan cut down to one tower and one wing, for the tests that build
a view or a scene. The whole plan takes much longer to build when the code
is instrumented for coverage, and a test of a branch needs only a part."""

from extensions.castle.plan import CastlePlan, Point, Tower, Wing, point
from extensions.castle.wijnendale import wijnendale_plan
from std.math import sqrt


def small_plan() raises -> CastlePlan:
    """Return the plan of Wijnendale with its first tower and its first wing.

    Returns:
        The plan, checked.

    Raises:
        Error: If the plan is not consistent.
    """
    var plan = wijnendale_plan()
    var tower = plan.towers[0].copy()
    var wing = plan.wings[0].copy()
    plan.towers = List[Tower]()
    plan.towers.append(tower^)
    plan.wings = List[Wing]()
    plan.wings.append(wing^)
    plan.check()
    return plan^


def with_a_tiny_step(axis: List[Point]) -> List[Point]:
    """Return an axis with a point a tenth of a micrometer from its start.

    Args:
        axis: The axis, two points at least.

    Returns:
        The axis with one more point.
    """
    var dx = axis[1].x.value - axis[0].x.value
    var dy = axis[1].y.value - axis[0].y.value
    var length = sqrt(dx * dx + dy * dy)
    var result = List[Point]()
    result.append(axis[0])
    result.append(
        point(
            axis[0].x.value + 1.0e-7 * dx / length,
            axis[0].y.value + 1.0e-7 * dy / length,
        )
    )
    for at in range(1, len(axis)):
        result.append(axis[at])
    return result^
