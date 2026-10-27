# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Kept-token digests agree only for the same tokens."""

from std.testing import TestSuite, assert_equal

from tests._python_tokens import token_sha256
from tools._token_digest import token_digest_match


def test_two_equal_sources_match() raises:
    """The same source agrees with itself."""
    var source = "def f():\n    return 1\n"
    assert_equal(
        token_digest_match(
            '{"left":"def f():\\n    return 1\\n","right":"def f():\\n   '
            ' return 1\\n"}'
        ),
        "true",
    )
    assert_equal(
        token_digest_match(
            '{"left":"def f():\\n    return 1\\n","right":"def g():\\n   '
            ' return 2\\n"}'
        ),
        "false",
    )
    var digest = token_sha256(source)
    assert_equal(
        token_digest_match(
            '{"text":"def f():\\n    return 1\\n","digest":"' + digest + '"}'
        ),
        "true",
    )
    assert_equal(
        token_digest_match(
            '{"text":"def f():\\n    return'
            ' 1\\n","digest":"0000000000000000000000000000000000000000000000000000000000000000"}'
        ),
        "false",
    )


def main() raises:
    """Run the token digest tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
