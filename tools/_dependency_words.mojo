# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the reviewed stored-word check for one dependency.

An exact token match needs no word check. Only the reviewed trig and
geometry tokens may differ and still keep their stored words.
"""

from tests._python_tokens import token_sha256
from tools._cleanup_dependency_pins import cleanup_dependency_pins
from tools.carla_cleanup_gate import cleanup_paths, cleanup_words
from tools._python_json import MISSING, PyJson


def _word_choice(doc: PyJson, node: Int) raises -> String:
    """Return the word check for one dependency object.

    Args:
        doc: The parsed document.
        node: One dependency object.

    Returns:
        `match` when the token is unchanged, `trig` for the trig word
        check, or `geometry` for the geometry word check.

    Raises:
        Error: The path is not one of those reviewed token pairs.
    """
    var token_node = doc.get(node, "token")
    var token: String
    if token_node == MISSING:
        token = token_sha256(doc.text(doc.at(node, "text")))
    else:
        token = doc.text(token_node)
    var expected = doc.text(doc.at(node, "expected"))
    if token == expected:
        return "match"
    var path = doc.text(doc.at(node, "path"))
    if path == doc.text(doc.at(node, "trig_path")) and expected == doc.text(
        doc.at(node, "trig_token")
    ):
        return "trig"
    if path == doc.text(doc.at(node, "geometry_path")) and expected == doc.text(
        doc.at(node, "geometry_token")
    ):
        return "geometry"
    raise Error(
        "reviewed cleanup source contract: unchanged premise dependency"
        " changed: "
        + path
    )


def dependency_word_choice(payload: String) raises -> String:
    """Return which stored-word check a dependency needs.

    Args:
        payload: JSON with `expected`, `path`, `trig_path`, `trig_token`,
            `geometry_path`, and `geometry_token`. `token` is the current
            digest. `text` is hashed when `token` is absent.

    Returns:
        `match` when the token is unchanged, `trig` for the trig word
        check, or `geometry` for the geometry word check.

    Raises:
        Error: The path is not one of those reviewed token pairs.
    """
    var doc = PyJson.parse(payload)
    return _word_choice(doc, doc.root)


def dependency_word_choices(payload: String) raises -> String:
    """Return the word check for each dependency.

    Args:
        payload: A JSON list. Each item has the choice fields.

    Returns:
        A JSON list of `match`, `trig`, or `geometry`, in the same order.

    Raises:
        Error: A dependency is not one of those reviewed token pairs.
    """
    var doc = PyJson.parse(payload)
    var out = PyJson()
    var rows = out.new_list()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        out.append(
            rows, out.new_str(_word_choice(doc, doc.item(doc.root, index)))
        )
        index += 1
    out.root = rows
    return out.dumps()


def checked_dependency_words(payload: String) raises:
    """Choose every dependency word check, then require the selected words.

    Args:
        payload: A JSON list. Each item has the choice fields and `text`.

    Raises:
        Error: A dependency is unreviewed, a stored declaration cannot be read, or a word list changed.
    """
    var choices = PyJson.parse(dependency_word_choices(payload))
    var doc = PyJson.parse(payload)
    var count = choices.length(choices.root)
    var index = 0
    while index < count:
        var choice = choices.text(choices.item(choices.root, index))
        if choice == "trig" or choice == "geometry":
            var item = doc.item(doc.root, index)
            cleanup_words(
                doc.text(doc.at(item, "text")),
                choice,
                doc.text(doc.at(item, "path")),
            )
        index += 1


def pinned_dependency_words(payload: String) raises:
    """Read the dependency pins, then check the selected words.

    Args:
        payload: A JSON list. Each item has `text`, `expected`, and
            `path`. The trig and geometry pins are read here.

    Raises:
        Error: A dependency is unreviewed, a stored declaration cannot
            be read, or a word list changed. The pins are read before
            the word checks.
    """
    var pins = PyJson.parse(cleanup_dependency_pins())
    var doc = PyJson.parse(payload)
    var count = doc.length(doc.root)
    var out = PyJson()
    var rows = out.new_list()
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        var row = out.new_dict()
        out.set(row, "text", out.new_str(doc.text(doc.at(item, "text"))))
        out.set(
            row, "expected", out.new_str(doc.text(doc.at(item, "expected")))
        )
        out.set(row, "path", out.new_str(doc.text(doc.at(item, "path"))))
        out.set(
            row,
            "trig_path",
            out.new_str(pins.text(pins.at(pins.root, "trig_path"))),
        )
        out.set(
            row,
            "trig_token",
            out.new_str(pins.text(pins.at(pins.root, "trig_token"))),
        )
        out.set(
            row,
            "geometry_path",
            out.new_str(pins.text(pins.at(pins.root, "geometry_path"))),
        )
        out.set(
            row,
            "geometry_token",
            out.new_str(pins.text(pins.at(pins.root, "geometry_token"))),
        )
        out.append(rows, row)
        index += 1
    out.root = rows
    checked_dependency_words(out.dumps())


def pinned_words_then_paths(payload: String) raises -> String:
    """Check the pinned dependency words, then read the cleanup paths.

    Args:
        payload: A JSON list. Each item has `text`, `expected`, and
            `path`. An empty list skips the word checks.

    Returns:
        The cleanup paths, with `sources` and `premises`.

    Raises:
        Error: A dependency is unreviewed or a word list changed. The
            word checks run before the paths are read.
    """
    var doc = PyJson.parse(payload)
    if doc.length(doc.root) > 0:
        pinned_dependency_words(payload)
    return cleanup_paths()
