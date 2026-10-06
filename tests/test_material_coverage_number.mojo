# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Malformed numeric spans refuse before appending any token."""

from materials.glsl import _Lexer, _Token
from std.testing import TestSuite, assert_equal


def refused(text: String, why: String, at: Int = 0) raises:
    var lexer = _Lexer("fragment", False)
    var out = List[_Token]()
    _ = lexer.number("42", 0, 3, out)
    var message = String()
    try:
        _ = lexer.number(text, at, 7, out)
    except error:
        message = String(error)
    assert_equal(message, "GLSL fragment shader, line 7: " + why)
    assert_equal(len(out), 1)
    assert_equal(out[0].text, "42")
    assert_equal(out[0].number, Float64(42))
    assert_equal(out[0].line, 3)


def accepted(text: String, written: String, kind: Int, number: Float64) raises:
    var lexer = _Lexer("fragment", False)
    var out = List[_Token]()
    var end = lexer.number(text, 0, 7, out)
    assert_equal(end, text.byte_length())
    assert_equal(len(out), 1)
    assert_equal(out[0].kind.value, kind)
    assert_equal(out[0].text, written)
    assert_equal(out[0].number, number)
    assert_equal(out[0].line, 7)


def test_empty_spelling_never_appends_a_zero_token() raises:
    for text in ["", "+", "-", " ", "u", "U", "+1", "-1"]:
        refused(text, "a number needs digits")
    refused("7", "a number needs digits", 1)


def test_existing_numeric_diagnostics_keep_precedence() raises:
    refused("0x", "a hexadecimal number needs digits")
    refused("0xz", "a hexadecimal number needs digits")
    refused("1e+", "an exponent needs digits")
    refused("08", "an octal integer uses digits 0 to 7")
    refused("1x", "a letter cannot follow a number")
    refused("0x1g", "a letter cannot follow a number")
    refused("0x1G", "a letter cannot follow a number")
    refused("0xz", "a hexadecimal number needs digits")
    refused("f", "a letter cannot follow a number")
    refused("4294967296u", "an integer literal exceeds 32 bits")
    refused("2147483648", "an int literal exceeds 2147483647; use a u suffix")


def test_valid_number_tokens_keep_type_spelling_value_and_end() raises:
    accepted("0", "0", 1, 0)
    accepted("1u", "1", 5, 1)
    accepted("077u", "077", 5, 63)
    accepted("0x0", "0x0", 1, 0)
    accepted("0x9", "0x9", 1, 9)
    accepted("0xa", "0xa", 1, 10)
    accepted("0xf", "0xf", 1, 15)
    accepted("0xA", "0xA", 1, 10)
    accepted("0xF", "0xF", 1, 15)
    accepted(".5", ".5", 2, 0.5)
    accepted("12.5", "12.5", 2, 12.5)
    accepted("2e+1", "2e+1", 2, 20)


def test_normal_token_dispatch_keeps_names_marks_and_empty_sources() raises:
    var empty = _Lexer("fragment", False)
    empty.run("")
    assert_equal(len(empty.tokens), 1)
    assert_equal(empty.tokens[0].kind.value, 4)
    for word in ["u", "U", "e1"]:
        var lexer = _Lexer("fragment", False)
        lexer.run(word)
        assert_equal(len(lexer.tokens), 2)
        assert_equal(lexer.tokens[0].kind.value, 0)
        assert_equal(lexer.tokens[0].text, word)
        assert_equal(lexer.tokens[1].kind.value, 4)
    for mark in ["+", "-", "."]:
        var lexer = _Lexer("fragment", False)
        lexer.run(mark)
        assert_equal(len(lexer.tokens), 2)
        assert_equal(lexer.tokens[0].kind.value, 3)
        assert_equal(lexer.tokens[0].text, mark)
        assert_equal(lexer.tokens[1].kind.value, 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
