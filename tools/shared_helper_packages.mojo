# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed shared-helper package files.

Four package files keep their reviewed digests. A changed package file
is refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


comptime _EXTENSIONS = "extensions/__init__.mojo"
comptime _CARLA = "extensions/carla/__init__.mojo"
comptime _LOADERS = "loaders/__init__.mojo"
comptime _RENDER = "render/__init__.mojo"
comptime _EMPTY = (
    "5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479"
)
comptime _CARLA_SHA = (
    "13bda95e7b80d111a65052af5508e95af88c7a17871fcf33f3eaf5dc75fd1a2d"
)
comptime _PREFIX = "reviewed shared-helper successor: "


def _fail(message: String) raises:
    """Raise a shared-helper package error.

    Args:
        message: The failure text.

    Raises:
        Error: A package check failed.
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


def _package(root: String, path: String, expected: String) raises:
    """Require one package file to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The package file.
        expected: The reviewed digest.

    Raises:
        Error: The package file changed.
    """
    var digest = sha256_hex(Path(root + "/" + path).read_bytes())
    if digest != expected:
        _fail("package input changed: " + path)


def shared_helper_packages(root: String) raises:
    """Require the four reviewed shared-helper package digests.

    Args:
        root: The repository root.

    Raises:
        Error: A package file changed.
    """
    var base = _root(root)
    _package(base, _EXTENSIONS, _EMPTY)
    _package(base, _CARLA, _CARLA_SHA)
    _package(base, _LOADERS, _EMPTY)
    _package(base, _RENDER, _EMPTY)


def main() raises:
    """Check the shared-helper package files of this repository.

    Raises:
        Error: A package file changed.
    """
    shared_helper_packages(".")
