# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the mesh view of a castle: the view of the plan of Wijnendale,
the checks of the settings, and views of plans that are cut to the shapes the
real plan never has: a wall with a step of a tenth of a micrometer, and a low
wing with a short ridge. The plan is cut down for these,
because every build costs far more when the code is instrumented."""

from extensions.castle.render import castle_meshes, default_view
from extensions.castle.wijnendale import wijnendale_plan
from std.math import nan
from std.testing import TestSuite, assert_equal, assert_raises
from tests._castle_small import small_plan, with_a_tiny_step
from units.si import Length64, METER


def test_the_view_builds() raises:
    var meshes = castle_meshes(wijnendale_plan(), default_view())
    print("materials", len(meshes))
    assert_equal(len(meshes), 9)


def test_the_settings_must_describe_a_view() raises:
    var good = default_view()
    good.check()
    var not_a_number = nan[DType.float64]()
    var plinth = good
    plinth.plinth = Length64(not_a_number, METER)
    with assert_raises(contains="plinth"):
        plinth.check()
    plinth.plinth = Length64(-1.0, METER)
    with assert_raises(contains="plinth"):
        plinth.check()
    var step = good
    step.terrain_step = Length64(not_a_number, METER)
    with assert_raises(contains="terrain step"):
        step.check()
    step.terrain_step = Length64(0.0, METER)
    with assert_raises(contains="terrain step"):
        step.check()
    var pitch = good
    pitch.window_pitch = Length64(not_a_number, METER)
    with assert_raises(contains="window pitch"):
        pitch.check()
    pitch.window_pitch = Length64(0.0, METER)
    with assert_raises(contains="window pitch"):
        pitch.check()
    var spacing = good
    spacing.tree_spacing = Length64(not_a_number, METER)
    with assert_raises(contains="tree spacing"):
        spacing.check()
    spacing.tree_spacing = Length64(0.0, METER)
    with assert_raises(contains="tree spacing"):
        spacing.check()
    with assert_raises(contains="plinth"):
        _ = castle_meshes(wijnendale_plan(), plinth)


def test_a_cut_down_plan_with_unusual_parts_is_built() raises:
    """The quay has a step of a tenth of a micrometer, and the wing has the
    same step, low eaves and a short run of ridge."""
    var plan = small_plan()
    plan.quay.axis = with_a_tiny_step(plan.quay.axis)
    plan.wings[0].axis = with_a_tiny_step(plan.wings[0].axis)
    plan.wings[0].eave_height = Length64(3.0, METER)
    plan.wings[0].ridge_height = Length64(5.0, METER)
    plan.check()
    # A coarse ground: the grid of the ground is most of the cost.
    var view = default_view()
    view.terrain_step = Length64(30.0, METER)
    assert_equal(len(castle_meshes(plan, view)), 9)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
