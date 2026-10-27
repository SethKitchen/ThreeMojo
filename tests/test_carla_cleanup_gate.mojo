# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed reviewed cleanup record fails the gate."""

from std.testing import TestSuite, assert_equal, assert_raises

from std.os import makedirs
from std.pathlib import Path
from tests._python_tokens import declaration_text, significant_json
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
    assert_equal(
        declaration_text(source, "first", none),
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
