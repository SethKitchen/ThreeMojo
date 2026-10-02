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


def test_xml_character_and_reference_boundaries() raises:
    for point in [0, 1, 8, 11, 12, 14, 31, 0xFFFE, 0xFFFF]:
        refused("<a>" + chr(point) + "</a>")
        refused("<a>&#" + String(point) + ";</a>")
    for reference in [
        "&#+65;",
        "&#x+41;",
        "&#;",
        "&#x;",
        "&#999999999999999999999;",
    ]:
        refused("<a>" + reference + "</a>")
    var valid = parse_xml("<a>&#000000000000000000000065;&#x000000000042;</a>")
    assert_equal(valid.text(0), "AB")
    var edges = parse_xml("<a>&#xD7FF;&#xE000;&#xFFFD;&#x10000;&#x10FFFF;</a>")
    assert_equal(edges.text(0).byte_length(), 17)


def test_xml_line_ends_normalize_in_attributes_and_cdata() raises:
    var attributes = parse_xml("<a x='a\r\nb\rc\td'/>")
    assert_equal(attributes.attribute(0, "x"), "a b c d")
    var references = parse_xml("<a x='&#13;&#10;&#9;'/>")
    assert_equal(references.attribute(0, "x"), "\r\n\t")
    var cdata = parse_xml("<a><![CDATA[a\r\nb\rc]]></a>")
    assert_equal(cdata.text(0), "a\nb\nc")


def test_comments_and_quoted_dtd_delimiters_are_checked() raises:
    for source in ["<!--x--y--><a/>", "<a><!--x--y--></a>", "<a>]]></a>"]:
        refused(source)
    assert_equal(parse_xml("<!----><a><!--ok--></a>").count(), 1)
    var dtd = parse_xml('<!DOCTYPE a [<!ENTITY unused "]">]><a/>')
    assert_equal(dtd.count(), 1)
    var commented = parse_xml(
        "<!DOCTYPE a [<!-- ] > [ --><?p ] > ?><!ENTITY e '>'>]><a/>"
    )
    assert_equal(commented.count(), 1)
    # DTD declarations remain unexpanded and never load external content.
    refused("<!DOCTYPE a [<!ENTITY e 'x'>]><a>&e;</a>")


def test_xml_raw_characters_are_checked_in_every_context() raises:
    # XML 1.0 fifth edition, productions [2], [66], and sections 2.11/3.3.3:
    # https://www.w3.org/TR/xml/
    for point in range(32):
        if point == 9 or point == 10 or point == 13:
            continue
        var character = chr(point)
        for source in [
            "<a>" + character + "</a>",
            "<a x='" + character + "'/>",
            "<a><![CDATA[" + character + "]]></a>",
            "<!--" + character + "--><a/>",
            "<?pi " + character + "?><a/>",
            "<!DOCTYPE a [<!ENTITY e '" + character + "'>]><a/>",
        ]:
            refused(source)
    for point in [0x20, 0x7F, 0x85, 0xD7FF, 0xE000, 0xFFFD, 0x10000, 0x10FFFF]:
        var character = chr(point)
        assert_equal(parse_xml("<a>" + character + "</a>").text(0), character)
        assert_equal(
            parse_xml("<a>&#" + String(point) + ";</a>").text(0), character
        )
    # A noncharacter is also forbidden inside markup that gets discarded.
    refused("<!--" + chr(0xFFFE) + "--><a/>")
    refused("<a x='" + chr(0xFFFF) + "'/>")
    assert_equal(parse_xml("<a>\t\n\r</a>").text(0), "\t\n\n")


def test_xml_reference_digits_are_unsigned_and_bounded() raises:
    for reference in [
        "&#-1;",
        "&# 65;",
        "&#65 ;",
        "&#x-1;",
        "&#x 41;",
        "&#X41;",
        "&#xg;",
        "&#x:;",
        "&#xG;",
        "&#x110000;",
        "&#xFFFFFFFFFFFFFFFFFFFF;",
        "&#xFFFE;",
        "&#xFFFF;",
        "&#xD800;",
        "&#xDFFF;",
    ]:
        refused("<a>" + reference + "</a>")
    for byte in range(128):
        var decimal = byte >= 48 and byte <= 57
        var hex_letter = (byte >= 65 and byte <= 70) or (
            byte >= 97 and byte <= 102
        )
        if not decimal:
            refused("<a>&#" + chr(byte) + ";</a>")
        if not decimal and not hex_letter:
            refused("<a>&#x" + chr(byte) + ";</a>")
    assert_equal(parse_xml("<a>&#x41;&#x6a;&#x6F;</a>").text(0), "Ajo")
    assert_equal(parse_xml("<a>&#9;&#10;&#13;</a>").text(0), "\t\n\r")
    # References are expanded after line endings are normalized.
    var document = parse_xml("<a x='\n\r\n\r\t&#13;\n&#10;&#9;'>\r&#13;\n</a>")
    assert_equal(document.attribute(0, "x"), "    \r \n\t")
    assert_equal(document.text(0), "\n\r\n")


def test_xml_comment_and_doctype_boundaries() raises:
    for source in [
        "<!--x---><a/>",
        "<!--x----><a/>",
        "<a/><!--x--y-->",
        "<!DOCTYPE a [<!--x--y-->]><a/>",
        "<!DOCTYPE a ]><a/>",
        "<!DOCTYPE a [<!--open]><a/>",
        "<!DOCTYPE a [<?pi ]><a/>",
        "<!DOCTYPE a [<!ENTITY e 'unclosed>]><a/>",
    ]:
        refused(source)
    for declaration in [
        '<!DOCTYPE a [<!ENTITY e "[ ] > < ?>">]>',
        "<!DOCTYPE a [<!ENTITY e '[ ] > < ?>'>]>",
        '<!DOCTYPE a SYSTEM "file:///does-not-exist.dtd">',
        '<!DOCTYPE a PUBLIC "example" "https://example.invalid/no.dtd">',
    ]:
        assert_equal(parse_xml(declaration + "<a/>").count(), 1)
    assert_equal(
        parse_xml("<!--a-b--><a><![CDATA[]]]]><![CDATA[>]]></a>").text(0), "]]>"
    )
    # No internal or external entity is expanded.
    refused('<!DOCTYPE a [<!ENTITY e SYSTEM "file:///etc/passwd">]><a>&e;</a>')
    refused('<!DOCTYPE a [<!ENTITY e "x">]><a x="&e;"/>')


def test_xml_errors_keep_original_byte_offsets() raises:
    with assert_raises(contains="XML at byte 7: a forbidden character"):
        _ = parse_xml("<a>é\r\n" + chr(1) + "</a>")
    with assert_raises(
        contains="XML at byte 7: a character reference is malformed"
    ):
        _ = parse_xml("<a>é\r\n&#+65;</a>")
    with assert_raises(contains="XML at byte 8: a forbidden character"):
        _ = parse_xml("<a x='é" + chr(0xFFFE) + "'/>")
    with assert_raises(
        contains="XML at byte 12: a comment contains a double hyphen"
    ):
        _ = parse_xml("<a>é\r\n<!--x--y--></a>")
    with assert_raises(contains="XML at byte 7: a CDATA close outside CDATA"):
        _ = parse_xml("<a>é\r\n]]></a>")
    assert_equal(parse_xml("<a>&#93;]></a>").text(0), "]]>")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
