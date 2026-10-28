# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Classify a stored-moment decimal word and a constant error.

The caller evaluates the fraction first. This check only reads that
result, the token text, and the decimal-word error.
"""

from tools._python_json import MISSING, PyJson
from tools._spiral_moment_words import decimal_integers_json


def signed_zero_word(payload: String) raises -> String:
    """Return whether a zero fraction keeps a negative token sign.

    Args:
        payload: JSON with `token` and `zero`. `zero` is true when the
            fraction is zero.

    Returns:
        `true` when `zero` is true and `token` starts with `-`. Otherwise
        `false`.

    Raises:
        Error: A field is absent.
    """
    var doc = PyJson.parse(payload)
    var token = doc.text(doc.at(doc.root, "token"))
    if doc.flag(doc.at(doc.root, "zero")) and token.startswith("-"):
        return "true"
    return "false"


def decimal_word_result(payload: String) raises -> String:
    """Return the one decimal word, or `nearest` for an unsupported token.

    Args:
        payload: JSON with `words`, a list of decimal word strings, or
            `error`, the decimal-word failure.

    Returns:
        `nearest` when the error is `unsupported decimal word`. Otherwise
        the single word.

    Raises:
        Error: The error is a different failure, or the word list does not
            hold one word. The text is `binary64 overflow` for the list.
    """
    var doc = PyJson.parse(payload)
    var error = doc.get(doc.root, "error")
    if error != MISSING:
        var message = doc.text(error)
        if message == "unsupported decimal word":
            return "nearest"
        raise Error(message)
    var words = doc.at(doc.root, "words")
    if doc.length(words) != 1:
        raise Error("binary64 overflow")
    return doc.text(doc.item(words, 0))


def classified_decimal_word(token: String) raises -> String:
    """Round one decimal literal, then classify that word.

    Args:
        token: A decimal literal or integer fraction.

    Returns:
        The unsigned decimal encoding of the rounded word.

    Raises:
        Error: The literal is not finite, or the rounded word is not the
            one stored encoding. The literal is rounded before the word
            is classified.
    """
    var listed = PyJson()
    var rows = listed.new_list()
    listed.append(rows, listed.new_str(token))
    listed.root = rows
    var parsed = PyJson.parse(decimal_integers_json(listed.dumps()))
    var decision = PyJson()
    var body = decision.new_dict()
    var words = decision.new_list()
    decision.append(
        words, decision.new_str(parsed.text(parsed.item(parsed.root, 0)))
    )
    decision.set(body, "words", words)
    decision.root = body
    return decimal_word_result(decision.dumps())


def constant_error_text(payload: String) raises -> String:
    """Return the constant-declaration failure text.

    Args:
        payload: JSON with `message` and `name`.

    Returns:
        `malformed constant declaration: NAME` for an unsupported or
        incomplete routing message. Otherwise `message`.

    Raises:
        Error: A field is absent.
    """
    var doc = PyJson.parse(payload)
    var message = doc.text(doc.at(doc.root, "message"))
    var name = doc.text(doc.at(doc.root, "name"))
    if (
        message == "unsupported top-level source routing"
        or message == "incomplete top-level source routing"
    ):
        return "malformed constant declaration: " + name
    return message
