# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.vrml_parse`.

The token kinds are the ones chevrotain gives with three.js 0.180's
token list, checked in node for the same text.
"""

from loaders.vrml_parse import (
    VRML_BOOLEAN_VALUE,
    VRML_DEF,
    VRML_FALSE,
    VRML_HEX,
    VRML_HEX_VALUE,
    VRML_IDENTIFIER,
    VRML_LEFT_CURLY,
    VRML_LEFT_SQUARE,
    VRML_NODE_NAME,
    VRML_NODE_VALUE,
    VRML_NO_VALUE,
    VRML_NULL,
    VRML_NULL_VALUE,
    VRML_NUMBER,
    VRML_NUMBER_VALUE,
    VRML_RIGHT_CURLY,
    VRML_RIGHT_SQUARE,
    VRML_ROUTE,
    VRML_ROUTE_IDENTIFIER,
    VRML_STRING,
    VRML_STRING_VALUE,
    VRML_TO,
    VRML_TRUE,
    VRML_USE,
    VRML_USE_VALUE,
    VRML_VERSION,
    VrmlToken,
    VrmlTokenKind,
    VrmlValueKind,
    lex_vrml,
    parse_vrml_text,
    parse_vrml_tree,
)
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def kinds_of(text: String) raises -> List[Int]:
    """Return the kind of each token of a text."""
    var out = List[Int]()
    for token in lex_vrml(text):
        out.append(token.kind.value)
    return out^


def test_tokens_match_chevrotain() raises:
    var tokens = lex_vrml(
        "DEFAULT Boxes Box ColorInterpolator TextureTransform TRUEX a.b"
        " a-b TOP 0x1F 0X 1 -.5e3 +2E+2 1e FALSE NULL USE ROUTE TO DEF"
        ' "a\\"b\\u0041\\n" [ ] { } #VRML V2.0 # gone\r\n'
    )
    var want_kinds: List[VrmlTokenKind] = [
        VRML_IDENTIFIER,
        VRML_IDENTIFIER,
        VRML_NODE_NAME,
        VRML_IDENTIFIER,
        VRML_NODE_NAME,
        VRML_TRUE,
        VRML_IDENTIFIER,
        VRML_ROUTE_IDENTIFIER,
        VRML_IDENTIFIER,
        VRML_IDENTIFIER,
        VRML_HEX,
        VRML_NUMBER,
        VRML_IDENTIFIER,
        VRML_NUMBER,
        VRML_NUMBER,
        VRML_NUMBER,
        VRML_NUMBER,
        VRML_IDENTIFIER,
        VRML_FALSE,
        VRML_NULL,
        VRML_USE,
        VRML_ROUTE,
        VRML_TO,
        VRML_DEF,
        VRML_STRING,
        VRML_LEFT_SQUARE,
        VRML_RIGHT_SQUARE,
        VRML_LEFT_CURLY,
        VRML_RIGHT_CURLY,
        VRML_VERSION,
    ]
    var want_images: List[String] = [
        "DEFAULT",
        "Boxes",
        "Box",
        "ColorInterpolator",
        "TextureTransform",
        "TRUE",
        "X",
        "a.b",
        "a-b",
        "TOP",
        "0x1F",
        "0",
        "X",
        "1",
        "-.5e3",
        "+2E+2",
        "1",
        "e",
        "FALSE",
        "NULL",
        "USE",
        "ROUTE",
        "TO",
        "DEF",
        '"a\\"b\\u0041\\n"',
        "[",
        "]",
        "{",
        "}",
        "#VRML V2.0 # gone",
    ]
    assert_equal(len(tokens), len(want_kinds))
    for i in range(len(tokens)):
        assert_equal(tokens[i].kind, want_kinds[i])
        assert_equal(tokens[i].image, want_images[i])


def test_white_space_and_comments() raises:
    # A comma, the control spaces, a no-break space, an ideographic space,
    # a byte order mark and a line separator are all white space.
    var text = "a,\t\x0b\x0cb  c 　d ﻿e  f # x g\n#y"
    var tokens = lex_vrml(text)
    assert_equal(len(tokens), 7)
    assert_equal(tokens[6].image, "g")
    # Inside an identifier, a no-break space does not end it, as the
    # identifier's pattern takes any character that is not ASCII.
    assert_equal(lex_vrml("a bé c")[0].image, "a bé")
    assert_equal(lex_vrml("#VRML x y")[0].image, "#VRML x")
    assert_equal(len(lex_vrml("# only a comment")), 0)
    # A comment ends an identifier.
    assert_equal(lex_vrml("x#c")[0].image, "x")


def test_lexing_errors() raises:
    for bad in [
        String("Group.x"),
        "a-b.c",
        "1.",
        '"open',
        '"line\nbreak"',
        '"bad \\q"',
        '"short \\u12"',
        '"end \\',
        "'x'",
        "a.b-c",
        "ab. x",
        "+",
        "\\",
    ]:
        with assert_raises(contains="unexpected character"):
            _ = lex_vrml(bad)


def test_route_identifiers() raises:
    var tokens = lex_vrml("ab.cd ef")
    assert_equal(tokens[0].kind, VRML_ROUTE_IDENTIFIER)
    assert_equal(tokens[0].image, "ab.cd")
    assert_equal(tokens[1].kind, VRML_IDENTIFIER)


def test_parse_errors() raises:
    with assert_raises(contains="`#VRML` version line"):
        _ = parse_vrml_tree(List[VrmlToken]())
    var bad = List[VrmlToken]()
    bad.append(VrmlToken(VrmlTokenKind(40), "x", 0))
    with assert_raises(contains="token kind that is not valid"):
        _ = parse_vrml_tree(bad^)
    with assert_raises(contains="expected a node at the end"):
        _ = parse_vrml_text("#VRML V2.0")
    with assert_raises(contains="expected `{` at byte 17"):
        _ = parse_vrml_text("#VRML V2.0\nGroup Group")
    with assert_raises(contains="expected the end of the file"):
        _ = parse_vrml_text("#VRML V2.0\nGroup { } ]")
    with assert_raises(contains="expected a value"):
        _ = parse_vrml_text("#VRML V2.0\nGroup { translation }")
    with assert_raises(contains="too big for a double"):
        _ = parse_vrml_text("#VRML V2.0\nGroup { translation 1e999 0 0 }")
    with assert_raises(contains="a name after DEF"):
        _ = parse_vrml_text("#VRML V2.0\nDEF 1 Group { }")
    with assert_raises(contains="unexpected character"):
        _ = lex_vrml('"a\rb"')


def test_tree() raises:
    var tree = parse_vrml_text(
        "#VRML V2.0 utf8\nDEF Box Group { children [ USE Box NULL Shape { } ]"
        ' name "a\'b" "c" 0x1F 2 solid TRUE FALSE TRUE empty [ ] }\n'
        "ROUTE a.b TO c.d"
    )
    assert_equal(tree.version, "#VRML V2.0 utf8")
    assert_equal(len(tree.roots), 1)
    ref group = tree.nodes[tree.roots[0]]
    assert_equal(group.def_name, "Box")
    assert_true(group.has_def)
    # Nodes, then uses, then nulls: the kind is the last of them.
    ref children = group.fields[0]
    assert_equal(children.kind, VRML_NULL_VALUE)
    assert_equal(children.values[0].kind, VRML_NODE_VALUE)
    assert_equal(tree.nodes[children.values[0].node].name, "Shape")
    assert_equal(children.values[1].kind, VRML_USE_VALUE)
    assert_equal(children.values[1].text, "Box")
    assert_equal(children.values[2].kind, VRML_NULL_VALUE)
    # Strings, then numbers, then hex numbers.
    ref name = group.fields[1]
    assert_equal(name.kind, VRML_HEX_VALUE)
    assert_equal(name.values[0].text, "ab")
    assert_equal(name.values[1].text, "c")
    assert_equal(name.values[2].number, 2)
    assert_equal(name.values[3].text, "0x1F")
    # The trues, then the falses.
    ref solid = group.fields[2]
    assert_equal(solid.kind, VRML_BOOLEAN_VALUE)
    assert_true(solid.values[0].boolean)
    assert_true(solid.values[1].boolean)
    assert_false(solid.values[2].boolean)
    assert_equal(group.fields[3].kind, VRML_NO_VALUE)
    assert_equal(tree.route_from[0], "a.b")
    assert_equal(tree.route_to[0], "c.d")
    assert_true(VrmlValueKind(7).is_valid())
    assert_false(VrmlValueKind(8).is_valid())
    # A hex number at the end of the text.
    assert_equal(lex_vrml("0x1F")[0].kind, VRML_HEX)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
