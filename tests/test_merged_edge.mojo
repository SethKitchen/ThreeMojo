# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A runtime-boundary edge keeps its path in front of the stored keys."""

from std.testing import TestSuite, assert_equal

from tools._merged_edge import merged_edge


def test_the_module_path_is_written_first() raises:
    """Stored keys follow the path, and a stored path replaces it."""
    assert_equal(
        merged_edge(
            '{"path":"cameras.mojo","edge":{"before_sha256":"a",'
            + '"after_sha256":"b"}}'
        ),
        '{"path":"cameras.mojo","before_sha256":"a","after_sha256":"b"}',
    )
    assert_equal(
        merged_edge(
            '{"path":"cameras.mojo","edge":{"before_sha256":"a",'
            + '"path":"old","after_sha256":"b","flags":[1,true,false,null]}}'
        ),
        '{"path":"old","before_sha256":"a","after_sha256":"b","flags":[1,true,false,null]}',
    )
    assert_equal(
        merged_edge('{"path":"cameras.mojo","edge":{}}'),
        '{"path":"cameras.mojo"}',
    )


def main() raises:
    """Run the merged edge tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
