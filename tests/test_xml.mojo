# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.xml`: the tree it reads, the text it resolves, and
every way a text that is not well formed is refused."""

from loaders.xml import MAX_XML_DEPTH, NO_ELEMENT, XmlDocument, parse_xml
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def refused(text: String) raises:
    """Assert that `parse_xml` refuses a text."""
    try:
        _ = parse_xml(text)
    except:
        return
    print("parse_xml read what it should refuse: " + text)
    raise Error("not refused")


def test_tree() raises:
    var document = parse_xml(
        '\ufeff<?xml version="1.0"?>\n<!-- a comment -->\n'
        + '<!DOCTYPE root [<!ENTITY e "x">]>\n'
        + "<root a='1' b = \"two\">\n"
        + '  <item id="x">first</item>\n'
        + "  <item/>\n"
        + "  <other><?pi data?><!-- skip --></other>\n"
        + "</root>\n<!-- after -->\n<?tail?>\n"
    )
    assert_equal(document.count(), 4)
    var root = document.root()
    assert_equal(document.name(root), "root")
    assert_equal(document.parent(root), NO_ELEMENT)
    assert_equal(document.attribute(root, "a"), "1")
    assert_equal(document.attribute(root, "b"), "two")
    assert_equal(document.attribute(root, "c", "none"), "none")
    assert_true(document.has_attribute(root, "a"))
    assert_false(document.has_attribute(root, "c"))
    var children = document.children(root)
    assert_equal(len(children), 3)
    var items = document.children_named(root, "item")
    assert_equal(len(items), 2)
    assert_equal(document.child(root, "item"), items[0])
    assert_equal(document.child(root, "other"), children[2])
    assert_equal(document.child(root, "missing"), NO_ELEMENT)
    assert_equal(document.text(items[0]), "first")
    assert_equal(document.attribute(items[0], "id"), "x")
    assert_equal(document.text(items[1]), "")
    # A leaf with no attributes and no children.
    assert_false(document.has_attribute(items[1], "id"))
    assert_equal(document.attribute(items[1], "id", "-"), "-")
    assert_equal(len(document.children_named(items[1], "x")), 0)
    assert_equal(document.child(items[1], "x"), NO_ELEMENT)
    assert_equal(document.parent(items[1]), root)
    assert_equal(document.text(children[2]), "")
    assert_equal(document.text_content(root), "\n  \n  \n  \nfirst")


def test_text() raises:
    var document = parse_xml(
        "<a x='tab\there&#10;&lt;&amp;&gt;&quot;&apos;'>"
        + "&lt;b&gt; &#65;&#x42;&#xe9;&#x20AC;&#x1F600;"
        + "<![CDATA[<raw> & ]]>line\r\nnext\rlast</a>"
    )
    assert_equal(document.attribute(0, "x"), "tab here\n<&>\"'")
    assert_equal(
        document.text(0),
        "<b> ABé€\U0001F600<raw> & line\nnext\nlast",
    )


def test_depth() raises:
    var deep = String()
    for _ in range(MAX_XML_DEPTH):
        deep += "<a>"
    for _ in range(MAX_XML_DEPTH):
        deep += "</a>"
    assert_equal(parse_xml(deep).count(), MAX_XML_DEPTH)
    refused("<b>" + deep + "</b>")


def test_bad_indices() raises:
    var document = parse_xml("<a/>")
    with assert_raises():
        _ = document.name(-1)
    with assert_raises():
        _ = document.name(1)
    with assert_raises():
        _ = document.parent(1)
    with assert_raises():
        _ = document.has_attribute(1, "x")
    with assert_raises():
        _ = document.attribute(1, "x")
    with assert_raises():
        _ = document.children(1)
    with assert_raises():
        _ = document.children_named(1, "x")
    with assert_raises():
        _ = document.child(1, "x")
    with assert_raises():
        _ = document.text(1)
    with assert_raises():
        _ = document.text_content(1)
    assert_equal(XmlDocument().count(), 0)


def test_refused() raises:
    # No root, or more than one.
    refused("")
    refused("text")
    refused("<a/><b/>")
    refused("<a/>text")
    refused("<a/><!DOCTYPE a>")
    # What is not closed.
    refused("<?pi")
    refused("<!-- open")
    refused("<!DOCTYPE a [ <!ENTITY e 'x'> ")
    refused("<a><![CDATA[ open</a>")
    refused("<a><!-- open</a>")
    refused("<a><?pi</a>")
    refused("<a>")
    refused("<a><b></b>")
    # Names, tags and attributes.
    refused("<1a/>")
    refused("< a/>")
    refused("<a x='1'y='2'/>")
    refused("<a x/>")
    refused("<a x=1/>")
    refused("<a x='1/>")
    refused("<a x='<'/>")
    refused("<a x='1' x='2'/>")
    refused("<a/ >")
    refused("<a></b>")
    refused("<a></a")
    refused("<a></ a>")
    # References.
    refused("<a>&nope;</a>")
    refused("<a>&amp</a>")
    refused("<a>&abcdefghijkl;</a>")
    refused("<a>&#xZZ;</a>")
    refused("<a>&#12a;</a>")
    refused("<a>&#0;</a>")
    refused("<a>&#xD800;</a>")
    refused("<a>&#xDFFF;</a>")
    refused("<a>&#x110000;</a>")
    refused("<a x='&bad;'/>")
    # The same shapes, well formed, are read.
    assert_equal(parse_xml("<a>&#xD7FF;&#xE000;</a>").text(0).byte_length(), 6)
    assert_equal(parse_xml('<a x="\'"/>').attribute(0, "x"), "'")
    assert_equal(parse_xml("<a x='\"'/>").attribute(0, "x"), '"')
    assert_equal(parse_xml("<a:b c:d='1'></a:b >").name(0), "a:b")
    assert_equal(parse_xml("<_a-b.c\u00e9/>").name(0), "_a-b.c\u00e9")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
