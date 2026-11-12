# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the crowns of the trees that stand at a distance: how many
triangles each has, how tall and wide it stands, and that every vertex has a
shade that is a share of the light.

The mesh frame is y up, with the foot of a tree at the origin.
"""

from core.buffer_geometry import BufferGeometry, COLOR
from extensions.castle.crowns import (
    ball_crown,
    broadleaf_crown,
    cone_crown,
    spruce,
)
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)


def _every_shade_is_a_share_of_the_light(geometry: BufferGeometry) raises:
    """Check that no vertex color is outside 0 to 1."""
    var colors = geometry.clone_attribute(String(COLOR))
    assert_true(len(colors.data) > 0)
    for at in range(len(colors.data)):
        assert_true(colors.data[at] >= 0.0 and colors.data[at] <= 1.0)


def test_a_spruce_is_tiers_of_drooping_sprays() raises:
    var tree = spruce(3, 24.0, 11, 0.3, 1.0)
    # Two tubes of a trunk, and three rows of sprays, two of them cards, on
    # each branch of each tier.
    assert_true(tree.bark.triangle_count() > 20)
    assert_true(tree.leaves.triangle_count() > 250)
    assert_true(tree.leaves.triangle_count() < 900)
    assert_equal(tree.height, 24.0)
    _every_shade_is_a_share_of_the_light(tree.leaves)
    # The tree stands on the origin and reaches its height.
    var box = tree.leaves.bounding_box()
    assert_true(box.max.y > 15.0 and box.max.y <= 24.5)
    assert_true(box.min.y > -1.0)


def test_fewer_tiers_and_a_narrower_crown_make_a_smaller_spruce() raises:
    var full = spruce(3, 24.0, 11, 0.3, 1.0)
    var few = spruce(3, 24.0, 5, 0.3, 1.0)
    assert_true(few.leaves.triangle_count() < full.leaves.triangle_count())
    var wide = spruce(3, 22.0, 10, 0.15, 1.25).leaves.bounding_box().size()
    var narrow = spruce(3, 26.0, 12, 0.25, 0.7).leaves.bounding_box().size()
    assert_true(wide.x > narrow.x)


def test_a_spruce_has_gaps_and_a_different_seed_a_different_tree() raises:
    var first = spruce(1, 24.0, 11, 0.3, 1.0)
    var second = spruce(2, 24.0, 11, 0.3, 1.0)
    assert_true(
        first.leaves.triangle_count() != second.leaves.triangle_count()
        or first.leaves.bounding_box().size().x
        != second.leaves.bounding_box().size().x
    )


def test_a_spruce_needs_four_tiers() raises:
    with assert_raises(contains="four tiers"):
        _ = spruce(1, 24.0, 3, 0.3, 1.0)


def test_a_broadleaf_crown_is_clusters_of_crossed_cards() raises:
    var tree = broadleaf_crown(3, 18.0, 22)
    # 22 clusters of three cards of two triangles.
    assert_equal(tree.leaves.triangle_count(), 22 * 3 * 2)
    assert_true(tree.bark.triangle_count() > 40)
    assert_equal(tree.height, 18.0)
    _every_shade_is_a_share_of_the_light(tree.leaves)
    var size = tree.leaves.bounding_box().size()
    # A round crown: about as wide as it is tall, over a clear trunk.
    assert_true(size.x > 8.0 and size.x < 24.0)
    var box = tree.leaves.bounding_box()
    assert_true(box.min.y > 3.0)


def test_a_crown_needs_eight_clusters() raises:
    with assert_raises(contains="eight clusters"):
        _ = broadleaf_crown(1, 18.0, 7)
    var small = broadleaf_crown(1, 18.0, 8)
    var large = broadleaf_crown(1, 18.0, 30)
    assert_true(small.leaves.triangle_count() < large.leaves.triangle_count())


def test_the_farthest_conifer_is_three_stacked_cones() raises:
    var tree = cone_crown(3, 24.0)
    assert_equal(tree.leaves.triangle_count(), 3 * 8)
    assert_equal(tree.bark.triangle_count(), 0)
    _every_shade_is_a_share_of_the_light(tree.leaves)
    var box = tree.leaves.bounding_box()
    assert_true(box.max.y > 15.0)


def test_the_farthest_broadleaf_is_a_lumpy_ball_on_a_short_trunk() raises:
    var tree = ball_crown(3, 17.0)
    # Five bands of ten cells of two triangles, less the triangle of no area
    # that each cell at a pole has.
    assert_equal(tree.leaves.triangle_count(), 5 * 10 * 2 - 2 * 10)
    assert_true(tree.bark.triangle_count() > 0)
    _every_shade_is_a_share_of_the_light(tree.leaves)
    # The hull is lumpy: another seed has another shape.
    var other = ball_crown(4, 17.0)
    assert_true(
        tree.leaves.bounding_box().size().x
        != other.leaves.bounding_box().size().x
        or tree.leaves.bounding_box().size().y
        != other.leaves.bounding_box().size().y
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
