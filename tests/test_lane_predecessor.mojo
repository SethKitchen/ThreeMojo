# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A lane predecessor matches only an unowned declaration token."""

from std.testing import TestSuite, assert_equal

from tools._lane_predecessor import (
    accept_lane_predecessor,
    selected_lane_minimum,
    selected_lane_minima,
)


def _payload(
    owner: String,
    path: String,
    name: String,
    expected: String,
    declarations: String,
) -> String:
    """Return one predecessor decision document.

    Args:
        owner: The JSON owner list.
        path: The declaration path.
        name: The declaration name.
        expected: The candidate source.
        declarations: The JSON declaration list.

    Returns:
        The payload.
    """
    return (
        '{"owner":'
        + owner
        + ',"path":"'
        + path
        + '","name":"'
        + name
        + '","expected":"'
        + expected
        + '","declarations":'
        + declarations
        + "}"
    )


def test_an_unowned_matching_lane_declaration_is_accepted() raises:
    """The second declaration can match, and equal text is accepted."""
    var declarations = String(
        '[{"path":"other.mojo","name":"_run","before":"def _run():\\n   '
        ' pass\\n"},'
        + '{"path":"lane.mojo","name":"_run","before":"def _run():\\n   '
        ' pass\\n"}]'
    )
    assert_equal(
        accept_lane_predecessor(
            _payload(
                "[]",
                "lane.mojo",
                "_run",
                "def _run():\\n    pass\\n",
                declarations,
            )
        ),
        "true",
    )


def test_a_changed_lane_predecessor_is_refused() raises:
    """An owner, a different name, or a different token is refused."""
    var declarations = String(
        '[{"path":"lane.mojo","name":"_other","before":"def _run():\\n   '
        ' pass\\n"},'
        + '{"path":"lane.mojo","name":"_run","before":"def _run():\\n    return'
        ' 1\\n"}]'
    )
    assert_equal(
        accept_lane_predecessor(
            _payload(
                '["owner"]',
                "lane.mojo",
                "_run",
                "def _run():\\n    pass\\n",
                declarations,
            )
        ),
        "false",
    )
    assert_equal(
        accept_lane_predecessor(
            _payload(
                "[]",
                "missing.mojo",
                "_run",
                "def _run():\\n    pass\\n",
                declarations,
            )
        ),
        "false",
    )
    assert_equal(
        accept_lane_predecessor(
            _payload(
                "[]",
                "lane.mojo",
                "_run",
                "def _run():\\n    pass\\n",
                declarations,
            )
        ),
        "false",
    )
    assert_equal(
        accept_lane_predecessor(
            _payload(
                "[]", "lane.mojo", "_run", "def _run():\\n    pass\\n", "[]"
            )
        ),
        "false",
    )


def test_the_rounded_lane_minimum_is_selected() raises:
    """Only the empty-owner rounded lane minimum is selected."""
    assert_equal(
        selected_lane_minimum(
            '{"path":"extensions/carla/lane_refinement.mojo",'
            + '"name":"_rounded_axis_lane_minimum","owner":[]}'
        ),
        "true",
    )
    assert_equal(
        selected_lane_minimum(
            '{"path":"other.mojo","name":"_rounded_axis_lane_minimum","owner":[]}'
        ),
        "false",
    )
    assert_equal(
        selected_lane_minimum(
            '{"path":"extensions/carla/lane_refinement.mojo","name":"_other","owner":[]}'
        ),
        "false",
    )
    assert_equal(
        selected_lane_minimum(
            '{"path":"extensions/carla/lane_refinement.mojo",'
            + '"name":"_rounded_axis_lane_minimum","owner":["Box"]}'
        ),
        "false",
    )


def test_lane_minima_keep_their_order() raises:
    """Each declaration keeps its own minimum decision."""
    assert_equal(
        selected_lane_minima(
            '[{"path":"extensions/carla/lane_refinement.mojo",'
            + '"name":"_rounded_axis_lane_minimum","owner":[]},'
            + '{"path":"other.mojo","name":"_rounded_axis_lane_minimum",'
            + '"owner":[]}]'
        ),
        '["true","false"]',
    )


def main() raises:
    """Run the lane predecessor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
