# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Locate bundled humanoid data outside the repository working directory."""

from std.os import getenv


def humanoid_asset_path(default_path: String) raises -> String:
    """Resolve a bundled asset beneath an optional configured asset root.

    Args:
        default_path: The repository-relative path starting with `assets/`.

    Returns:
        The default path when `THREEMOJO_ASSET_ROOT` is unset or empty.
        Otherwise, the same asset relative to that configured directory.

    Raises:
        Error: If the default path does not start with `assets/`.
    """
    if not default_path.startswith("assets/"):
        raise Error("A humanoid asset path must start with assets/")
    var root = getenv("THREEMOJO_ASSET_ROOT", "")
    if root == "":
        return default_path
    return root + "/" + String(default_path[byte=7:])
