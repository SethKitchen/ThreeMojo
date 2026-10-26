# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed score-live premises.

The score helper and the winner-seed caller keep their token digests.
Three optional premises and eight support premises keep their digests.
The score fixture keeps its file digest. A changed premise or a changed
fixture is refused.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256
from tools._sha256 import sha256_hex
from tools.seed_count_premises import (
    _declaration,
    _indent,
    _is_definition,
    _line_starts,
)


comptime _MAP = "extensions/carla/map.mojo"
comptime _FIXTURE = "tests/test_carla_winner_seed_update_score.mojo"
comptime _FIXTURE_SHA = (
    "fb9b3c95f3e390bebf2be132544371c5626ed7b9be77181d6701aa2e89a9f3e4"
)
comptime _HELPER = (
    "155efb5cb2224594d4f58a59cbd6e3c84b80ee21bcc8fed50f4252bbab6cb331"
)
comptime _CALLER = (
    "530591a025e3ab9a31870ed03f0b79d871e8a96c958eb688aa31d047b0143e40"
)
comptime _PREFIX = "reviewed seed-count successor: "


def _fail(message: String) raises:
    """Raise a score-live premise error.

    Args:
        message: The failure text.

    Raises:
        Error: A score-live check failed.
    """
    raise Error(_PREFIX + message)


def _root(root: String) -> String:
    """Return `root` without a trailing slash.

    Args:
        root: The repository root.

    Returns:
        The root used to join paths.
    """
    if root.byte_length() > 1 and root.endswith("/"):
        var end = root.byte_length() - 1
        return String(root[byte=0:end])
    return root


def _definitions(text: String, name: String) -> Int:
    """Count declarations of `name` at every indent.

    Args:
        text: The module source.
        name: The function name.

    Returns:
        The number of `def name(` and `def name[` lines.
    """
    var starts = _line_starts(text)
    var count = 0
    var index = 0
    while index < len(starts):
        var at = starts[index]
        var body = at + _indent(text, at)
        if _is_definition(text, body, name):
            count += 1
        index += 1
    return count


def _live_pair(text: String, name: String, expected: String) raises:
    """Require one score declaration with the reviewed digest.

    Args:
        text: The Map source.
        name: The function name.
        expected: The reviewed token digest.

    Raises:
        Error: The declaration is missing, repeated, or changed.
    """
    if _definitions(text, name) != 1:
        _fail("ambiguous score declaration: " + name)
    var label = _MAP + ":" + name
    var actual = token_sha256(_declaration(text, name, "", label))
    if actual != expected:
        _fail("live score helper/caller operation graph changed: " + name)


def _premise(
    root: String,
    path: String,
    name: String,
    owner: String,
    expected: String,
    kind: String,
) raises:
    """Require one extra premise to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The module path.
        name: The function name.
        owner: The struct name, or empty.
        expected: The reviewed token digest.
        kind: `optional-guard` or `support-guard`.

    Raises:
        Error: The declaration is missing or its digest changed.
    """
    var label = path + ":" + name
    if owner != "":
        label = path + ":" + owner + "." + name
    var text = Path(root + "/" + path).read_text()
    var actual = token_sha256(_declaration(text, name, owner, label))
    if actual != expected:
        _fail("live " + kind + " premise changed: " + label)


def seed_count_score_live(root: String) raises:
    """Require the reviewed score-live premises and the score fixture.

    Args:
        root: The repository root.

    Raises:
        Error: A score declaration, an extra premise, or the fixture changed.
    """
    var base = _root(root)
    var text = Path(base + "/" + _MAP).read_text()
    _live_pair(text, "_winner_seed_update_score", _HELPER)
    _live_pair(text, "_try_winner_seed", _CALLER)
    _premise(
        base,
        "extensions/carla/map_search.mojo",
        "validate",
        "MapQueryBudget",
        "d4844df8e4cbed35dfa9533c921cacc7975ea2cfed0d4efd57f6541b078a1cdc",
        "optional-guard",
    )
    _premise(
        base,
        "extensions/carla/map_search.mojo",
        "_step_product",
        "_MapQueryWork",
        "123e48a4de30fe5f383a3e2d4c4b747f53b4181fc672a040560ef72d1d27f825",
        "optional-guard",
    )
    _premise(
        base,
        "extensions/carla/curve_sum2.mojo",
        "_sum2_update",
        "",
        "ce9a6e6e0203c349208ed4d0feee47106c0fbc1b9addd3517a0003b11990f18b",
        "optional-guard",
    )
    _premise(
        base,
        "extensions/carla/curve_interval.mojo",
        "whole",
        "_Interval",
        "86d1e02f0f8cb20cee66f09ed7e2342d0e56c1d6b7a99de864cb52fb14019dbc",
        "support-guard",
    )
    _premise(
        base,
        "extensions/carla/curve_interval.mojo",
        "rounded",
        "_Interval",
        "4097f0ddac630fbd70272ab9cea2c963fb9150d999d07c32114ea8624813d8aa",
        "support-guard",
    )
    _premise(
        base,
        "extensions/carla/curve_interval.mojo",
        "__neg__",
        "_Interval",
        "9e2f35fa8cbc07e6d6ae013d35510b2dd0b3d0327c995ed00f5c9416b12e2dfa",
        "support-guard",
    )
    _premise(
        base,
        "extensions/carla/curve_interval.mojo",
        "__sub__",
        "_Interval",
        "a481d28615c2cf2bccb4248f1977b7273bf29c8d96121ee339ba5e63d2f15a94",
        "support-guard",
    )
    _premise(
        base,
        "extensions/carla/curve_interval.mojo",
        "__truediv__",
        "_Interval",
        "d63998431c4fb89405f915fea9a3de39f5026da3eb3081bad1305c69b2401316",
        "support-guard",
    )
    _premise(
        base,
        "extensions/carla/curve_interval.mojo",
        "square",
        "_Interval",
        "5ba837ee949861751a9996bee84a5cb02bf767c2100e3c8b4f6e3621a910d922",
        "support-guard",
    )
    _premise(
        base,
        "extensions/carla/curve_interval.mojo",
        "sqrt",
        "_Interval",
        "6b3199c6c1f107ea5bad08837c6ff7ad389e655b1eb20ce4d42c904ed271c359",
        "support-guard",
    )
    _premise(
        base,
        "extensions/carla/curve_interval.mojo",
        "contains",
        "_Interval",
        "a1b087462723ccf3cbc7b63725adf7b67c2487dde5e8a1928acf5be31dbfaf93",
        "support-guard",
    )
    var fixture = Path(base + "/" + _FIXTURE).read_bytes()
    if sha256_hex(fixture) != _FIXTURE_SHA:
        _fail("score-helper numerical fixture changed: " + _FIXTURE)


def main() raises:
    """Check the score-live premises of this repository.

    Raises:
        Error: A score-live premise or the score fixture changed.
    """
    seed_count_score_live(".")
