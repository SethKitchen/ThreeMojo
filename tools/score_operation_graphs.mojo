# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live score operation graphs.

The score helper keeps its reviewed token digest. The winner-seed caller
keeps its reviewed token digest. Each declaration stays unique. A changed
operation is refused.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256


comptime _MAP = "extensions/carla/map.mojo"
comptime _HELPER = "_winner_seed_update_score"
comptime _CALLER = "_try_winner_seed"
comptime _HELPER_SHA = (
    "155efb5cb2224594d4f58a59cbd6e3c84b80ee21bcc8fed50f4252bbab6cb331"
)
comptime _CALLER_SHA = (
    "530591a025e3ab9a31870ed03f0b79d871e8a96c958eb688aa31d047b0143e40"
)


def _fail(message: String) raises:
    """Raise a score-operation error.

    Args:
        message: The failure text.

    Raises:
        Error: The score check failed.
    """
    raise Error(message)


def _prefix(text: String, at: Int, prefix: String) -> Bool:
    """Return whether `text` has `prefix` at byte `at`.

    Args:
        text: The source.
        at: The byte index.
        prefix: The expected text.

    Returns:
        True when the prefix is present.
    """
    var end = at + prefix.byte_length()
    if end > text.byte_length():
        return False
    return String(text[byte=at:end]) == prefix


def _line_starts(text: String) -> List[Int]:
    """Return the byte index of each line.

    Args:
        text: The source.

    Returns:
        The line starts, including zero.
    """
    var starts = List[Int]()
    starts.append(0)
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes):
        if bytes[index] == 10 and index + 1 < len(bytes):
            starts.append(index + 1)
        index += 1
    return starts^


def _boundary(text: String, at: Int) -> Bool:
    """Return whether a line starts a following declaration.

    Args:
        text: The source.
        at: A line start.

    Returns:
        True for `def`, `struct`, or `@`.
    """
    if _prefix(text, at, "def "):
        return True
    if _prefix(text, at, "struct "):
        return True
    return _prefix(text, at, "@")


def _declaration(text: String, name: String) raises -> String:
    """Return the one top-level declaration named `name`.

    Args:
        text: The Map module.
        name: The function name.

    Returns:
        The declaration through the following top-level line.

    Raises:
        Error: The declaration is missing or repeated.
    """
    var needle = "def " + name + "("
    var starts = _line_starts(text)
    var found = -1
    var count = 0
    var index = 0
    while index < len(starts):
        if _prefix(text, starts[index], needle):
            count += 1
            found = starts[index]
        index += 1
    if count != 1 or found < 0:
        _fail("ambiguous score declaration: " + name)
    var stop = text.byte_length()
    index = 0
    while index < len(starts):
        if starts[index] > found and _boundary(text, starts[index]):
            stop = starts[index]
            break
        index += 1
    return String(text[byte=found:stop])


def score_operation_graphs(text: String) raises:
    """Require the score helper and the winner-seed caller.

    Args:
        text: The Map module.

    Raises:
        Error: A declaration is ambiguous or its token digest changed.
    """
    var helper = token_sha256(_declaration(text, _HELPER))
    if helper != _HELPER_SHA:
        _fail("live score helper/caller operation graph changed: " + _HELPER)
    var caller = token_sha256(_declaration(text, _CALLER))
    if caller != _CALLER_SHA:
        _fail("live score helper/caller operation graph changed: " + _CALLER)


def _root(root: String) -> String:
    """Return `root` without a trailing slash.

    Args:
        root: The repository root.

    Returns:
        The root used to join the Map path.
    """
    if root.byte_length() > 1 and root.endswith("/"):
        var end = root.byte_length() - 1
        return String(root[byte=0:end])
    return root


def sampled_score_graphs(root: String) raises:
    """Require the live score operation graphs.

    Args:
        root: The repository root.

    Raises:
        Error: A score declaration changed.
    """
    var text = Path(_root(root) + "/" + _MAP).read_text()
    score_operation_graphs(text)
