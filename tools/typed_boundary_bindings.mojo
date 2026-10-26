# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed typed-boundary binding inputs.

Five binding inputs keep their reviewed digests. A changed binding input is
refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


comptime _PREFIX = "full-audit cleanup successor: "


def _fail(message: String) raises:
    """Raise a typed-boundary binding-input error.

    Args:
        message: The failure text.

    Raises:
        Error: A binding input changed.
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
    """Require one binding input to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The binding input path.
        expected: The reviewed digest.

    Raises:
        Error: The binding input changed.
    """
    if sha256_hex(Path(root + "/" + path).read_bytes()) != expected:
        _fail("typed boundary bound input changed: " + path)


def typed_boundary_bindings(root: String) raises:
    """Require the reviewed typed-boundary binding-input digests.

    Args:
        root: The repository root.

    Raises:
        Error: A binding input changed.
    """
    var base = _root(root)
    _input(
        base,
        "docs/validation/carla-namespace-lookup-333.json",
        "56e4f180488b04d96ac481f9524670406c62cba7b3b83c343c7beebe9e677e11",
    )
    _input(
        base,
        "docs/validation/typed-boundary-successor-333.md",
        "ace0362083baf3a24f13c654c5c6ccb1357411643ebd9320097d631655a7ba16",
    )
    _input(
        base,
        "tools/carla_lane_oracle/envelope_budget_contracts.py",
        "8f7025ec3d9b6578a93cf5aceafe9c8b6c0cabeb00720b4856e58cf00c35e166",
    )
    _input(
        base,
        "tools/carla_lane_oracle/oracle.py",
        "9bf603f02bca35c0a79a440600eeb9e6389af9da26e62d68f72c723b9c319952",
    )
    _input(
        base,
        "tools/carla_lane_oracle/probe_typed_namespace_lookup.py",
        "e5bd86039476501b33d6b6e8cc3c877604ff6a388a4f87bc69c302bc39eb7461",
    )


def main() raises:
    """Check the typed-boundary binding inputs of this repository.

    Raises:
        Error: A binding input changed.
    """
    typed_boundary_bindings(".")
