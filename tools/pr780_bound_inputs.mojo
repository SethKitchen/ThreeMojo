# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed PR780 bound inputs.

Four bound tests keep their reviewed digests. A changed bound input is
refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


comptime _PREFIX = "full-audit cleanup successor: "


def _fail(message: String) raises:
    """Raise a PR780 bound-input error.

    Args:
        message: The failure text.

    Raises:
        Error: A bound input changed.
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


def _input(root: String, path: String, expected: String) raises:
    """Require one bound input to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The bound input path.
        expected: The reviewed digest.

    Raises:
        Error: The bound input changed.
    """
    var digest = sha256_hex(Path(root + "/" + path).read_bytes())
    if digest != expected:
        _fail("PR780 bound input changed: " + path)


def pr780_bound_inputs(root: String) raises:
    """Require the four reviewed PR780 bound-input digests.

    Args:
        root: The repository root.

    Raises:
        Error: A bound input changed.
    """
    var base = _root(root)
    _input(
        base,
        "tests/test_anatomy_muscle.mojo",
        "3653d6056c1f9f639537eedb7cd80364baf80352b4aa984d39c0e737d8801401",
    )
    _input(
        base,
        "tests/test_animation_strings.mojo",
        "f5103e3660a63d3d5d9d348a0d928fa106e5cef03059d432a31335bb7dd14184",
    )
    _input(
        base,
        "tests/test_loader_bounds.mojo",
        "6e0c1487f1ff21f4654c2790e4460c0adf934bf6b9273e826782eec1bfed2d83",
    )
    _input(
        base,
        "tools/carla_lane_oracle/test_pr780_source_successor.py",
        "fad1fe54f34c47efeff20f5d26f3c644dcc6eb129848290bada4235215815606",
    )


def main() raises:
    """Check the PR780 bound inputs of this repository.

    Raises:
        Error: A bound input changed.
    """
    pr780_bound_inputs(".")
