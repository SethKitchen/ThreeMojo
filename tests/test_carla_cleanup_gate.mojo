# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed reviewed cleanup record fails the gate."""

from std.testing import TestSuite, assert_equal, assert_raises

from std.os import makedirs
from std.pathlib import Path
from tests._python_tokens import (
    declaration_place,
    declaration_text,
    function_slice,
    replace_token_fragment,
    ideal_function_source,
    python_syntax_json,
    significant_json,
    module_routing_json,
    module_statements_json,
    token_names,
    top_level_starts_json,
    without_move_sigils,
)
from tools.carla_cleanup_gate import (
    cleanup_digest,
    cleanup_record,
    cleanup_sha,
    cleanup_premises,
    cleanup_tokens,
    cleanup_words,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="reviewed cleanup source contract: unreviewed migration record"
    ):
        cleanup_record(String("").as_bytes(), String("").as_bytes(), False)


def test_a_changed_guard_pin_is_refused() raises:
    """Bytes that are not the recorded guard pin fail closed."""
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: unreviewed dependency pin"
            " successor: sum2-guard-pins.json"
        )
    ):
        cleanup_digest(String("nope").as_bytes(), "00")


def test_a_changed_successor_token_is_refused() raises:
    """A text that does not have the recorded token digest fails closed."""
    var directory = "/tmp/cleanup-token-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"label":"unreviewed complete successor: module.mojo","token":"00"}]'
    )
    Path(directory + "/0.text").write_text("def changed():\n    pass\n")
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: unreviewed complete successor:"
            " module.mojo"
        )
    ):
        cleanup_tokens(directory)


def test_a_missing_stored_word_is_refused() raises:
    """A geometry module without its stored arrays fails closed."""
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: missing or ambiguous"
            " stored-word declaration: _GL_NODES"
        )
    ):
        cleanup_words(
            "def empty():\n    pass\n",
            "geometry",
            "extensions/carla/geometry.mojo",
        )


def test_a_changed_stored_word_is_refused() raises:
    """Geometry arrays of zeros are not the reviewed words."""
    var source = String(
        "comptime _GL_NODES: Array[Float64, 5] = [0.0, 0.0, 0.0, 0.0, 0.0]\n"
        + "comptime _GL_WEIGHTS: Array[Float64, 5] = [0.0, 0.0, 0.0, 0.0,"
        " 0.0]\n"
    )
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: unchanged premise dependency"
            " changed: extensions/carla/geometry.mojo"
        )
    ):
        cleanup_words(source, "geometry", "extensions/carla/geometry.mojo")


def test_a_nested_def_is_not_a_top_level_start() raises:
    """Only a top-level def or import line is recorded."""
    var source = String(
        "def first():\n"
        + "    def nested():\n"
        + "        return 1\n"
        + "from a import b\n"
    )
    assert_equal(top_level_starts_json(source), "[[1,0],[4,0]]")


def test_an_ideal_generic_parameter_list_is_removed() raises:
    """`var` and the `derivatives: Bool` list are removed."""
    var source = String(
        "def _stored_half[\n"
        + "    derivatives: Bool\n"
        + "](value: Int) -> Int:\n"
        + "    var result = value\n"
        + "    return result\n"
    )
    var plain = ideal_function_source(source, "_stored_half")
    if plain.find("var ") >= 0 or plain.find("derivatives") >= 0:
        raise Error(plain)
    if plain.find("def _stored_half") < 0 or plain.find("return result") < 0:
        raise Error(plain)


def test_a_top_level_function_slice_stops_at_the_next_def() raises:
    """The slice starts at `def` and stops before the next top-level marker."""
    var source = String(
        "@hidden\n"
        + "def first(value: Int):\n"
        + "    return value\n"
        + "\n"
        + "def second[T: Int]():\n"
        + "    return 1\n"
        + "@later\n"
        + "def third():\n"
        + "    return 2\n"
    )
    assert_equal(
        function_slice(source, "first"),
        "def first(value: Int):\n    return value\n\n",
    )
    assert_equal(
        function_slice(source, "second"),
        "def second[T: Int]():\n    return 1\n",
    )
    assert_equal(
        function_slice(source, "third"),
        "def third():\n    return 2\n",
    )
    with assert_raises(contains="missing or ambiguous function: first"):
        _ = function_slice(source + "def first():\n    return 0\n", "first")
    with assert_raises(contains="missing or ambiguous function: absent"):
        _ = function_slice(source, "absent")


def test_one_executable_fragment_is_replaced() raises:
    """A comment does not hide the executable assignment."""
    var source = String(
        "def f():\n"
        + "    # terms += center_work\n"
        + "    terms += center_work\n"
        + "    return terms\n"
    )
    assert_equal(
        replace_token_fragment(source, "terms += center_work", "terms += 0"),
        "def f():\n"
        + "    # terms += center_work\n"
        + "    terms += 0\n"
        + "    return terms\n",
    )
    with assert_raises(
        contains="missing or ambiguous executable mutation fragment: terms += 0"
    ):
        _ = replace_token_fragment(source, "terms += 0", "terms += 1")


def test_a_generic_declaration_becomes_python_source() raises:
    """`struct` becomes `class`, and the parameter list is metadata."""
    var source = String(
        "struct Box[T: Int]:\n"
        + "    def value[\n"
        + "        derivatives: Bool,\n"
        + "    ]() -> Int:\n"
        + "        var number = 1\n"
        + "        return number\n"
    )
    var document = python_syntax_json(source)
    if document.find('"class"') < 0 or document.find('"struct"') >= 0:
        raise Error(document)
    if document.find("derivatives") < 0 or document.find("var ") >= 0:
        raise Error(document)
    if document.find("def value") < 0 or document.find("return number") < 0:
        raise Error(document)


def test_a_repeated_generic_name_is_refused() raises:
    """Two generic declarations with the same name fail closed."""
    with assert_raises(contains="ambiguous generic declaration"):
        _ = python_syntax_json(
            "def value[T: Int]():\n    return 1\n\n"
            + "def value[U: Int]():\n    return 2\n"
        )


def test_a_stored_word_routing_masks_the_right_hand_side() raises:
    """A named comptime declaration keeps only the tokens through equals."""
    var source = "comptime _GL_NODES: Array[Float64, 5] = [0.0]\n"
    assert_equal(
        module_routing_json(source, '["_GL_NODES"]'),
        '[[["NAME","comptime"],["NAME","_GL_NODES"],["OP",":"],'
        + '["NAME","Array"],["OP","["],["NAME","Float64"],["OP",","],'
        + '["NUMBER","5"],["OP","]"],["OP","="],["STORED_WORDS","_GL_NODES"]]]',
    )


def test_a_module_docstring_is_not_a_top_level_statement() raises:
    """The opening module string is omitted from the statement list."""
    var source = String('"""Module."""\n' + "def first():\n" + "    return 1\n")
    assert_equal(
        module_statements_json(source),
        '[[["NAME","def"],["NAME","first"],["OP","("],["OP",")"],["OP",":"]]]',
    )


def test_argument_move_sigils_are_removed() raises:
    """A postfix move sigil before a comma or parenthesis is removed."""
    var source = "def f(road^, section^):\n    return road\n"
    var plain = without_move_sigils(source)
    if plain.find("^") >= 0:
        raise Error(plain)
    var names = token_names(plain)
    var saw_road = False
    var saw_section = False
    for name in names:
        if name == "road":
            saw_road = True
        if name == "section":
            saw_section = True
    if not saw_road or not saw_section:
        raise Error("argument name missing")


def test_a_comment_does_not_change_significant_tokens() raises:
    """A comment is not part of the significant token list."""
    var source = "def first():\n    return 1\n"
    if significant_json(source) != significant_json(source + "# note\n"):
        raise Error("comment changed the significant tokens")
    if significant_json(source) == significant_json(
        "def first():\n    return 2\n"
    ):
        raise Error("changed body kept the significant tokens")


def test_a_struct_method_keeps_its_declaration() raises:
    """A module function and a struct method keep the Python declaration text.
    """
    var source = String(
        "def first():\n    return 1\n\nstruct Owner:\n    def second():\n"
        + "        return 2\n"
    )
    var none = List[String]()
    var place = declaration_place(source, "first", none)
    assert_equal(place.text, "def first():\n    return 1\n\n")
    if place.first != 0 or place.last != 3:
        raise Error("first declaration span changed")
    assert_equal(
        declaration_text(source, "first", List[String]()),
        "def first():\n    return 1\n\n",
    )
    var owner = List[String]()
    owner.append("Owner")
    assert_equal(
        declaration_text(source, "second", owner),
        "def second():\n    return 2\n",
    )
    var wrong = List[String]()
    with assert_raises(contains="guard caller owner/scope changed: second"):
        _ = declaration_text(source, "second", wrong)


def test_a_repeated_premise_fragment_is_refused() raises:
    """A premise fragment that occurs twice fails closed."""
    var directory = "/tmp/cleanup-premises-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"label":"ordered finite domain premise","fragments":'
        + '["_rounded_operand(low)"]}]'
    )
    Path(directory + "/0.mojo").write_text(
        "def bounds():\n"
        + "    _rounded_operand(low)\n"
        + "    _rounded_operand(low)\n"
    )
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: ordered finite domain premise"
        )
    ):
        cleanup_premises(directory)


def test_the_stored_word_digest_matches_sha256() raises:
    """The stored-word digest is SHA-256 of the given bytes."""
    var digest = cleanup_sha(String("abc").as_bytes())
    if (
        digest
        != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    ):
        raise Error(digest)


def main() raises:
    """Run the reviewed cleanup gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
