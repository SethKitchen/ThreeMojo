# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed density successor inputs.

10 inputs keep their reviewed digests. A changed density successor input
is refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


def _fail(message: String) raises:
    """Raise a density-successor input error.

    Args:
        message: The failure text.

    Raises:
        Error: A density successor input changed.
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
    """Require one density successor input to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The input path.
        expected: The reviewed digest.

    Raises:
        Error: The density successor input changed.
    """
    if sha256_hex(Path(root + "/" + path).read_bytes()) != expected:
        _fail("density successor input changed: " + path)


def density_successor_inputs(root: String) raises:
    """Require the reviewed density-successor input digests.

    Args:
        root: The repository root.

    Raises:
        Error: A density successor input changed.
    """
    var base = _root(root)
    _input(
        base,
        "core/extent.mojo",
        "90490706baa17456a3ec99374c2a00f72768a0178b4e56436571ab4ca673f068",
    )
    _input(
        base,
        "extensions/humanoid/skeleton/head/assembly.mojo",
        "813a09e4b30a5a9682e606cdabb2e22188866f4153318a18f9df62f091c0435e",
    )
    _input(
        base,
        "extensions/humanoid/skeleton/look.mojo",
        "662665a1ea3c291b45030fcf90d732b2a7900f0c1a591e4d94d854201e8caa48",
    )
    _input(
        base,
        "geometries/attribute_utils.mojo",
        "91d45ff588571ab0bbda20331d1f60a0b55e124985a76f8cad97d682bdca523e",
    )
    _input(
        base,
        "loaders/bytes.mojo",
        "139ca1cb876bdf7b0a7c258d1d3a40375d8f3b73c75af160e26e07e7c9ba062a",
    )
    _input(
        base,
        "math/matrix4.mojo",
        "1e72ab51f9dbcee3af4c2bfe9da93946616736bf02f4b20e2160ee7b69b448fa",
    )
    _input(
        base,
        "math/square_matrix.mojo",
        "f1b2e67489949b53594b5f06604a0227260fd961df2fdebe5347d91c82d99a69",
    )
    _input(
        base,
        "math/vector4.mojo",
        "db774733a27a706e5d5c940c4533de2c567d7d6ece3c918215052bccfd87b9aa",
    )
    _input(
        base,
        "objects/gaussian_splat.mojo",
        "6b5834369f244c8eaf6a4a6d363bcca7f645a4964f72ddea25df62f63097cf3c",
    )
    _input(
        base,
        "render/tasks.mojo",
        "9b80dcaceec958190ade19bff6d106617c8c4c99e80d37eb0205609741ca2934",
    )


def main() raises:
    """Check the density successor inputs of this repository.

    Raises:
        Error: A density successor input changed.
    """
    density_successor_inputs(".")
