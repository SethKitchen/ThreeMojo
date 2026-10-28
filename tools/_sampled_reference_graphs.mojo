# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live sampled reference graphs.

The trig module and the interval module keep their reviewed token digests.
A changed token is refused.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256


comptime _TRIG = "extensions/carla/curve_trig.mojo"
comptime _INTERVAL = "extensions/carla/curve_interval.mojo"
comptime _TRIG_SHA = (
    "523d5700201b957152eaa79ae6cce9ca8cb9a2a0098d5b105584667360a6de7f"
)
comptime _INTERVAL_SHA = (
    "e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11"
)


def _fail(filename: String) raises:
    """Raise a reference-graph error.

    Args:
        filename: The module file name.

    Raises:
        Error: The live reference module changed.
    """
    raise Error(
        "reference module changed; renewed review required: " + filename
    )


def _check(
    base: String, path: String, filename: String, expected: String
) raises:
    """Require one module to keep its reviewed token digest.

    Args:
        base: The repository root.
        path: The module path.
        filename: The file name used in a failure.
        expected: The reviewed token digest.

    Raises:
        Error: The token digest changed.
    """
    if token_sha256(Path(base + "/" + path).read_text()) != expected:
        _fail(filename)


def sampled_reference_graphs(root: String) raises:
    """Require the live sampled reference graphs.

    Args:
        root: The repository root.

    Raises:
        Error: A trig or interval token changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    _check(base, _TRIG, "curve_trig.mojo", _TRIG_SHA)
    _check(base, _INTERVAL, "curve_interval.mojo", _INTERVAL_SHA)
