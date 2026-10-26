# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed typed-boundary conditioned inputs.

Five conditioned inputs keep their reviewed digests. Two contract leaves
keep their reviewed digests. A changed conditioned input is refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


comptime _PREFIX = "full-audit cleanup successor: "


def _fail(message: String) raises:
    """Raise a typed-boundary conditioned-input error.

    Args:
        message: The failure text.

    Raises:
        Error: A conditioned input changed.
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
    """Require one conditioned input to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The input path.
        expected: The reviewed digest.

    Raises:
        Error: The conditioned input changed.
    """
    if sha256_hex(Path(root + "/" + path).read_bytes()) != expected:
        _fail("typed boundary bound input changed: " + path)


def typed_boundary_conditioned(root: String) raises:
    """Require the reviewed typed-boundary conditioned-input digests.

    Args:
        root: The repository root.

    Raises:
        Error: A conditioned input changed.
    """
    var base = _root(root)
    _input(
        base,
        "tools/carla_lane_oracle/conditioned-cubic-successor.json",
        "a0cf7af298262796ba1db8292830f683ae2a1c3844e8d8d967fe5f5d4cfa309c",
    )
    _input(
        base,
        "tools/carla_lane_oracle/test_conditioned_cubic_contracts.py",
        "e6de36edf8083671416d28f90c129bed042a6e1f9fa2dcbb5b6fc2826f3d2e48",
    )
    _input(
        base,
        "docs/validation/conditioned-cubic-333.md",
        "20b3e2ddf5d979999cae5f262560e3f3a41bab773346351791a3b355dc0b0a2a",
    )
    _input(
        base,
        "assets/carla/town.xodr",
        "4130289eab48e8cc3c6cf928a054d6af15566e3cd1e5d6c95ecbe5d84377f797",
    )
    _input(
        base,
        "extensions/carla/curve_interval.mojo",
        "ff6bf0d35b357047c609ea7cb6dbcbe535446cf4e315d9eac5f6c341ddbf1040",
    )
    _input(
        base,
        "tools/carla_lane_oracle/typed_boundary_contracts.py",
        "59cc73b325af897981a2d7299cf2d4ed3c61d3ea64d5f958f2b85aef51666362",
    )
    _input(
        base,
        "tools/carla_lane_oracle/conditioned_cubic_contracts.py",
        "df99ea0826d5efa936c56e4ece9aa79b41806b60e52121c4f564a8de5d5b0198",
    )


def main() raises:
    """Check the typed-boundary conditioned inputs of this repository.

    Raises:
        Error: A conditioned input changed.
    """
    typed_boundary_conditioned(".")
