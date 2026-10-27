# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Consumer import scopes stay in module order."""

from std.testing import TestSuite, assert_equal

from tests._python_tokens import import_scope_prefixes


def test_import_scopes_keep_their_order() raises:
    """Each prefix stops at its own first definition."""
    assert_equal(
        import_scope_prefixes(
            '["header\\n@dec\\ndef foo():\\n    pass\\n","only header\\n"]'
        ),
        '["header","only header\\n"]',
    )


def main() raises:
    """Run the import-scope tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
