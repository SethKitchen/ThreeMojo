# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Spell stored binary64 words as `0x` text.

    carla_stored_words --hex PATH
    carla_stored_words --integers PATH
    carla_stored_words --require PATH
    carla_stored_words --table PATH
    carla_stored_words --table-after-count PATH
    carla_stored_words --decimal PATH
    carla_stored_words --rounded-array PATH
    carla_stored_words --node-sums PATH
    carla_stored_words --fractions PATH

`--hex` reads a JSON list of unsigned decimals and prints `0x` words.
`--integers` reads a JSON list of `0x` words and prints decimal text.
`--require` reads `words`, `expected`, and `message`, and prints nothing
when the spellings match. `--table` reads `source` and `count`, then
prints the table words as decimals. `--table-after-count` reads the
word count before that table. `--decimal` rounds each literal and
prints those encodings as decimals. `--rounded-array` reads one
constant array before that rounding. `--node-sums` spells the stored
nodes and weights before it rounds the node sums. `--fractions` spells
each stored word before its fraction text.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import PyJson
from tools._spiral_moment_words import (
    decimal_integers_json,
    fraction_texts_from_decimals,
    rounded_array_words,
    rounded_node_sums_from_decimals,
    hex_integers_json,
    hex_words_json,
    parsed_table_integers,
    require_stored_words,
)
from tools.carla_moment_gate import moment_files


def parsed_table_after_count(payload: String) raises -> String:
    """Read the word count, then the stored table words as integers.

    Args:
        payload: JSON with `source`, the stored table text.

    Returns:
        A JSON list of unsigned decimal words, in source order.

    Raises:
        Error: The declaration is malformed, or a word is not
            hexadecimal. The word count is read before the declaration
            is checked.
    """
    var files = PyJson.parse(moment_files())
    var count = files.text(files.at(files.root, "words"))
    var doc = PyJson.parse(payload)
    var source = doc.subtree(doc.at(doc.root, "source")).dumps()
    return parsed_table_integers(
        '{"source":' + source + ',"count":' + count + "}"
    )


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_stored_words --hex PATH | --integers PATH | --require"
            " PATH | --table PATH | --table-after-count PATH | --decimal PATH |"
            " --rounded-array PATH |"
            " --node-sums PATH | --fractions PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Spell or check one list of stored words.

    Raises:
        Error: The command is invalid, or a word changed.
    """
    var arguments = argv()
    if len(arguments) != 3:
        _usage()
    var mode = arguments[1]
    if (
        mode != "--hex"
        and mode != "--integers"
        and mode != "--require"
        and mode != "--table"
        and mode != "--table-after-count"
        and mode != "--decimal"
        and mode != "--rounded-array"
        and mode != "--node-sums"
        and mode != "--fractions"
    ):
        _usage()
    try:
        var text = Path(arguments[2]).read_text()
        if mode == "--hex":
            print(hex_words_json(text), end="")
            return
        if mode == "--integers":
            print(hex_integers_json(text), end="")
            return
        if mode == "--table":
            print(parsed_table_integers(text), end="")
            return
        if mode == "--table-after-count":
            print(parsed_table_after_count(text), end="")
            return
        if mode == "--decimal":
            print(decimal_integers_json(text), end="")
            return
        if mode == "--rounded-array":
            print(rounded_array_words(text), end="")
            return
        if mode == "--node-sums":
            print(rounded_node_sums_from_decimals(text), end="")
            return
        if mode == "--fractions":
            print(fraction_texts_from_decimals(text), end="")
            return
        require_stored_words(text)
    except error:
        print(String(error), file=stderr)
        exit(1)
