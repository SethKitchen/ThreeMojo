# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed runtime-boundary record fails the gate."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.carla_runtime_boundary_gate import (
    boundary_extend,
    boundary_steps,
    runtime_boundary_record,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="reviewed runtime boundary successor: unreviewed exact edge"
    ):
        runtime_boundary_record(String("").as_bytes())


def test_a_foreign_view_step_is_refused() raises:
    """A step outside the four modules fails closed."""
    var directory = "/tmp/boundary-step-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text('["extensions/carla/map.mojo"]')
    with assert_raises(
        contains=(
            "reviewed runtime boundary successor: runtime view step outside"
            " the boundary scope"
        )
    ):
        boundary_steps(directory)


def test_a_disconnected_view_step_is_refused() raises:
    """A step that does not start at the edge end fails closed."""
    with assert_raises(
        contains=(
            "reviewed runtime boundary successor: runtime view step does not"
            " extend the edge: extensions/carla/world.mojo"
        )
    ):
        boundary_extend("aa", "bb", "cc", "cc", "extensions/carla/world.mojo")


def main() raises:
    """Run the runtime-boundary gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
