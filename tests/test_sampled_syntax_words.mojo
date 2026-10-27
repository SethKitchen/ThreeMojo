# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The sampled syntax keywords and generic messages stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools._sampled_syntax_words import sampled_syntax_words


def test_sampled_syntax_keywords_stay_in_reviewed_order() raises:
    """The six keywords stay ahead of the generic refusal messages."""
    var doc = PyJson.parse(sampled_syntax_words())
    var keywords = doc.at(doc.root, "keywords")
    assert_equal(doc.length(keywords), 6)
    assert_equal(doc.text(doc.item(keywords, 0)), "var")
    assert_equal(doc.text(doc.item(keywords, 1)), "mut")
    assert_equal(doc.text(doc.item(keywords, 2)), "out")
    assert_equal(doc.text(doc.item(keywords, 3)), "ref")
    assert_equal(doc.text(doc.item(keywords, 4)), "comptime")
    assert_equal(doc.text(doc.item(keywords, 5)), "raises")
    assert_equal(doc.text(doc.at(doc.root, "struct_word")), "struct")
    assert_equal(doc.text(doc.at(doc.root, "class_word")), "class")
    assert_equal(doc.text(doc.at(doc.root, "def_word")), "def")
    assert_equal(
        doc.text(doc.at(doc.root, "unclosed")),
        "unclosed Mojo generic declaration",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "ambiguous")), "ambiguous generic declaration"
    )
    assert_equal(
        doc.text(doc.at(doc.root, "parsed")),
        "ambiguous parsed generic declaration",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "primitive_class")), "_JetExpression"
    )
    assert_equal(doc.text(doc.at(doc.root, "type_params")), "type_params")
    assert_equal(
        doc.text(doc.at(doc.root, "mojo_parameters")), "mojo_type_parameters"
    )


def main() raises:
    """Run the sampled syntax word tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
