# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed moment producer fails the token gate."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_json import PyJson
from tools._spiral_moment_words import hex_words_json, require_stored_words
from tools.carla_moment_gate import moment_finiteness


def test_a_changed_module_is_refused() raises:
    """Stand-in sources do not have the reviewed digest."""
    with assert_raises(
        contains="Moment producer count/work/arithmetic graph changed"
    ):
        _ = moment_finiteness(
            "def main():\n    pass\n",
            "def main():\n    pass\n",
            "def main():\n    pass\n",
            "def main():\n    pass\n",
        )


def test_stored_words_use_uppercase_hex() raises:
    """A stored word is `0x` and 16 uppercase digits."""
    assert_equal(
        hex_words_json('["0","255","9223372036854775808"]'),
        '["0x0000000000000000","0x00000000000000FF","0x8000000000000000"]',
    )
    assert_equal(
        hex_words_json('["18446744073709551615"]'),
        '["0xFFFFFFFFFFFFFFFF"]',
    )
    with assert_raises(contains="invalid UInt64 word"):
        _ = hex_words_json('[""]')
    with assert_raises(contains="invalid UInt64 word"):
        _ = hex_words_json('["12a"]')
    with assert_raises(contains="invalid UInt64 word"):
        _ = hex_words_json('["18446744073709551616"]')
    with assert_raises(contains="invalid UInt64 word"):
        _ = hex_words_json('["99999999999999999999"]')
    var doc = PyJson()
    var root = doc.new_dict()
    var words = doc.new_list()
    doc.append(words, doc.new_str("255"))
    var expected = doc.new_list()
    doc.append(expected, doc.new_str("0x00000000000000FF"))
    doc.set(root, "words", words)
    doc.set(root, "expected", expected)
    doc.set(
        root, "message", doc.new_str("stored constant words changed: nodes")
    )
    doc.root = root
    require_stored_words(doc.dumps())
    var short = doc.new_list()
    doc.set(root, "expected", short)
    with assert_raises(contains="stored constant words changed: nodes"):
        require_stored_words(doc.dumps())
    doc.set(root, "expected", expected)
    var changed = doc.new_list()
    doc.append(changed, doc.new_str("0x0000000000000000"))
    doc.set(root, "expected", changed)
    with assert_raises(contains="stored constant words changed: nodes"):
        require_stored_words(doc.dumps())


def main() raises:
    """Run the moment-gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
