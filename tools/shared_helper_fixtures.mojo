# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed shared-helper fixtures.

4 fixtures keep their reviewed digests. A changed shared-helper fixture
is refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


def _fail(message: String) raises:
    """Raise a shared-helper fixture error.

    Args:
        message: The failure text.

    Raises:
        Error: A shared-helper fixture changed.
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


def _input(root: String, path: String, expected: String) raises:
    """Require one shared-helper fixture to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The fixture path.
        expected: The reviewed digest.

    Raises:
        Error: The shared-helper fixture changed.
    """
    if sha256_hex(Path(root + "/" + path).read_bytes()) != expected:
        _fail("shared-helper fixture changed: " + path)


def shared_helper_fixtures(root: String) raises:
    """Require the reviewed shared-helper fixture digests.

    Args:
        root: The repository root.

    Raises:
        Error: A shared-helper fixture changed.
    """
    var base = _root(root)
    _input(
        base,
        "tests/test_carla_curve_distance.mojo",
        "a5c6b76cff9757ebdfe194b6c2e27e3e1de46583daa3d97f4d3052b9d1f51776",
    )
    _input(
        base,
        "tests/test_carla_curve_distance_fraction.mojo",
        "cbf5fbf6f13a98147c4df989bd86ec007851c37738e5555e05405b7f72a82380",
    )
    _input(
        base,
        "tests/test_xml.mojo",
        "3e8f4193cee7fe65cbbf630cf70f33410e90eadbbf6f9af72f2ddbdc799486b6",
    )
    _input(
        base,
        "tests/test_carla_render_weathers.mojo",
        "5a66ac764a55f9cec74ed5ca188c3054f28c6544a48900757a6bf892855172ec",
    )


def main() raises:
    """Check the shared-helper fixtures of this repository.

    Raises:
        Error: A shared-helper fixture changed.
    """
    shared_helper_fixtures(".")
