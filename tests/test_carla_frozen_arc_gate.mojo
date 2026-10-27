# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed frozen ARC producer record fails the gate."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import declaration_routing
from tools.carla_frozen_arc_gate import (
    frozen_arc_digest,
    frozen_arc_functions,
    frozen_arc_layout,
    frozen_arc_places,
    frozen_arc_prior,
    frozen_arc_record,
    frozen_arc_token,
)


def test_a_function_suite_is_omitted_from_routing() raises:
    """A function body is not part of the declaration routing."""
    assert_equal(
        declaration_routing("def first():\n    return 1\n"),
        '[[[],[[1,"def"],[1,"first"],[55,"("],[55,")"],[55,":"]]]]',
    )


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="frozen ARC producer contract: unreviewed migration record"
    ):
        frozen_arc_record(String("").as_bytes(), String("").as_bytes(), False)


def test_a_changed_guard_pin_is_refused() raises:
    """A different guard-pin digest fails closed."""
    with assert_raises(
        contains="frozen ARC producer contract: guard pin lineage changed"
    ):
        frozen_arc_digest(String("nope").as_bytes(), "00", "guard")


def test_a_changed_successor_token_is_refused() raises:
    """A source that does not have the recorded token digest fails closed."""
    with assert_raises(
        contains=(
            "frozen ARC producer contract: complete frozen ARC successor"
            " changed"
        )
    ):
        frozen_arc_token("def changed():\n    pass\n", "00")


def test_a_different_prior_pin_is_refused() raises:
    """A runtime pin predecessor that differs from the cleanup record fails closed.
    """
    with assert_raises(
        contains=(
            "frozen ARC producer contract: runtime pin predecessor differs"
            " from accepted cleanup"
        )
    ):
        frozen_arc_prior("aa", "bb")


def test_a_wrong_runtime_placement_is_refused() raises:
    """A placement outside the reviewed set fails closed."""
    var directory = "/tmp/frozen-places-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text("[]")
    with assert_raises(
        contains=(
            "frozen ARC producer contract: wrong runtime successor placements"
        )
    ):
        frozen_arc_places(directory)


def test_a_changed_producer_function_is_refused() raises:
    """A producer function whose token list changed fails closed."""
    var directory = "/tmp/frozen-functions-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"name":"center","actual":"[]","expected":"[[1,\\"def\\"]]"}]'
    )
    with assert_raises(
        contains=(
            "frozen ARC producer contract: complete producer/Box function"
            " changed: center"
        )
    ):
        frozen_arc_functions(directory)


def test_a_changed_arc_layout_is_refused() raises:
    """A RoundedArc routing text that changed fails closed."""
    with assert_raises(
        contains=(
            "frozen ARC producer contract: RoundedArc/Box field layout,"
            " imports, or declaration owners changed"
        )
    ):
        frozen_arc_layout("[]", "[[]]")


def main() raises:
    """Run the frozen ARC gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
