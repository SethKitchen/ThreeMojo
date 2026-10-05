# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Texture format queries and refusal boundaries outside their happy path."""

from render.ktx2 import VkFormat, compressed_format_of
from render.uastc_hdr import AstcProfile
from std.testing import TestSuite, assert_equal, assert_raises


def test_astc_size_queries_distinguish_other_formats() raises:
    for value in [0, -1, 37, 131, 184]:
        assert_equal(VkFormat(value).astc_block_size(), 0)
    for value in [157, 158, 1000066000]:
        assert_equal(VkFormat(value).astc_block_size(), 4)
    for value in [165, 166, 1000066004]:
        assert_equal(VkFormat(value).astc_block_size(), 6)


def test_valid_astc_and_uncompressed_formats_refuse_block_layout() raises:
    for value in [-1, 999, 37, 157, 165, 1000066000, 1000066004]:
        with assert_raises(contains="not a block format"):
            _ = compressed_format_of(VkFormat(value))


def test_astc_profile_writes_its_value() raises:
    assert_equal(String(AstcProfile(0)), "AstcProfile(0)")
    assert_equal(String(AstcProfile(1)), "AstcProfile(1)")
    assert_equal(String(AstcProfile(2)), "AstcProfile(2)")
    assert_equal(String(AstcProfile(-1)), "AstcProfile(-1)")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
