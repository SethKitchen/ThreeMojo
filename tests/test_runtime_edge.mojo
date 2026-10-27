# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A reviewed view step extends the runtime-boundary edge in place."""

from std.testing import TestSuite, assert_equal

from tools._runtime_edge import extend_runtime_edge, extend_runtime_edges


def test_a_missing_view_step_leaves_the_edge() raises:
    """A path with no step does not extend the edge."""
    assert_equal(
        extend_runtime_edge(
            '{"path":"missing.mojo","edge":{"after_sha256":"old"},"steps":{}}'
        ),
        '{"extend":false}',
    )


def test_a_view_step_replaces_the_after_digests() raises:
    """Existing after keys stay in place, and new ones follow them."""
    assert_equal(
        extend_runtime_edge(
            '{"path":"cameras.mojo","edge":{"before_sha256":"b",'
            + '"after_sha256":"old","before_token_sha256":"bt",'
            + '"after_token_sha256":"old-token"},"steps":{"cameras.mojo":'
            + '{"before_sha256":"old","after_sha256":"new",'
            + '"before_token_sha256":"old-token","after_token_sha256":"new-token"}}}'
        ),
        '{"extend":true,"edge":{"before_sha256":"b","after_sha256":"new",'
        + '"before_token_sha256":"bt","after_token_sha256":"new-token"}}',
    )
    assert_equal(
        extend_runtime_edge(
            '{"path":"cameras.mojo","edge":{"before_sha256":"b"},"steps":'
            + '{"cameras.mojo":{"after_sha256":"new","after_token_sha256":"new-token"}}}'
        ),
        '{"extend":true,"edge":{"before_sha256":"b","after_sha256":"new",'
        + '"after_token_sha256":"new-token"}}',
    )


def test_runtime_edges_keep_their_order() raises:
    """A missing step stays false, and the next step extends its edge."""
    assert_equal(
        extend_runtime_edges(
            '{"steps":{"cameras.mojo":{"after_sha256":"new",'
            + '"after_token_sha256":"new-token"}},"items":['
            + '{"path":"missing.mojo","edge":{"after_sha256":"old"}},'
            + '{"path":"cameras.mojo","edge":{"before_sha256":"b"}}]}'
        ),
        '[{"extend":false},{"extend":true,"edge":{"before_sha256":"b",'
        + '"after_sha256":"new","after_token_sha256":"new-token"}}]',
    )


def main() raises:
    """Run the runtime-edge tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
