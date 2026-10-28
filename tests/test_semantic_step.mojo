# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""One optional-runtime group binds declarations before its edges."""

from std.testing import TestSuite, assert_raises

from tools._semantic_declarations import semantic_step, semantic_steps


def _step(source: String, name: String) -> String:
    """Return one helper step.

    Args:
        source: The module source.
        name: The function name.

    Returns:
        The JSON step.
    """
    return (
        '{"group":"helper","items":[{"key":"helper","name":"'
        + name
        + '","source":"'
        + source
        + '"}],"prior":{},"bind_labels":[{"key":"helper","label":"helper"}],'
        + '"checks":[],"edges":["helper"],"prefix":"optional runtime'
        ' contract: "}'
    )


def test_a_missing_group_function_is_refused_before_the_edges() raises:
    """The missing function is reported before the fragment check."""
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: missing"
    ):
        _ = semantic_step(_step("def f():\\n    return 1\\n", "missing"))


def test_a_present_function_reaches_the_edge_check() raises:
    """A declared function is checked against the helper fragment."""
    with assert_raises(contains="exact UInt64 pair helper comparison"):
        _ = semantic_step(
            _step("def _same_cache_key():\\n    return 1\\n", "_same_cache_key")
        )


def test_optional_runtime_groups_keep_their_order() raises:
    """The first missing function is reported before the next group."""
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: missing"
    ):
        _ = semantic_steps(
            '{"prefix":"optional runtime contract: ","steps":['
            + '{"group":"helper","items":[{"key":"helper","name":"missing",'
            + '"source":"def f():\\n    return 1\\n"}],'
            + '"bind_labels":[{"key":"helper","label":"helper"}],"checks":[],'
            + '"edges":["helper"]},'
            + '{"group":"helper","items":[{"key":"helper","name":"_same_cache_key",'
            + '"source":"def _same_cache_key():\\n    return 1\\n"}],'
            + '"bind_labels":[{"key":"helper","label":"helper"}],"checks":[],'
            + '"edges":["helper"]}]}'
        )


def main() raises:
    """Run the semantic step tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
