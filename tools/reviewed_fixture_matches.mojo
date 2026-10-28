# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check four reviewed fixtures that still match.

The station test, the scaled note, the witness note, and the expectation
binding keep their reviewed digests. A changed fixture is refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


def _fail(message: String) raises:
    """Raise a reviewed-fixture error.

    Args:
        message: The failure text.

    Raises:
        Error: A reviewed fixture changed.
    """
    raise Error(message)


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


def _input(root: String, path: String, expected: String, reason: String) raises:
    """Require one reviewed fixture to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The fixture path.
        expected: The reviewed digest.
        reason: The refusal prefix.

    Raises:
        Error: The reviewed fixture changed.
    """
    if sha256_hex(Path(root + "/" + path).read_bytes()) != expected:
        _fail(reason + path)


def reviewed_fixture_matches(root: String) raises:
    """Require four reviewed fixtures to keep their reviewed digests.

    Args:
        root: The repository root.

    Raises:
        Error: A reviewed fixture changed.
    """
    var base = _root(root)
    _input(
        base,
        "tests/test_carla_waypoint_stations.mojo",
        "7e2f1d9029833c42c7a078e1943f52502b1d2629500fbf6ed2744f42560db5ce",
        "station correctness fixture changed: ",
    )
    _input(
        base,
        "docs/validation/scaled-float32-746.md",
        "97fbe81ea07c6e2f0ecff4a87c551ee7d72770342724d49b8b7e136c1b065e18",
        "scaled correctness input changed: ",
    )
    _input(
        base,
        "docs/validation/carla-witness-format-successor.md",
        "e2df2607c2aba63bf440dcc1efb2acad4da7a1e6f9eaef82cd1f8e2827fbb8db",
        "witness-format proof input changed: ",
    )
    _input(
        base,
        "tools/carla_lane_oracle/test_expectation_binding_successor.py",
        "e4ad0a6a13196e4a2bf16dae76f78f01d103260c2644632ec36fa74f46dad846",
        "PR760 physical input changed: ",
    )


def main() raises:
    """Check the four reviewed fixtures of this repository.

    Raises:
        Error: A reviewed fixture changed.
    """
    reviewed_fixture_matches(".")
