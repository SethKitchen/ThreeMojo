# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed PR776 bound inputs.

5 inputs keep their reviewed digests. A changed PR776 bound input is refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


def _fail(message: String) raises:
    """Raise a PR776 bound-input error.

    Args:
        message: The failure text.

    Raises:
        Error: A PR776 bound input changed.
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
    """Require one PR776 bound input to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The input path.
        expected: The reviewed digest.

    Raises:
        Error: The PR776 bound input changed.
    """
    if sha256_hex(Path(root + "/" + path).read_bytes()) != expected:
        _fail("PR776 bound input changed: " + path)


def pr776_bound_inputs(root: String) raises:
    """Require the reviewed PR776 bound-input digests.

    Args:
        root: The repository root.

    Raises:
        Error: A PR776 bound input changed.
    """
    var base = _root(root)
    _input(
        base,
        "tools/carla_lane_oracle/test_main_rebase_successor.py",
        "2ca5e9f72a38766945e182fbe004e3e64011efa897e22445ab7372102634a792",
    )
    _input(
        base,
        "tests/compile_fail/a_gpu_info_is_not_a_bare_int.mojo",
        "785b9a1746336fdea844b431f6a5ffd6812a623a72d1929c544eb9f107cf7819",
    )
    _input(
        base,
        "tests/compile_fail/a_gpu_part_is_not_a_bare_int.mojo",
        "a8880f3e6f546bf30671147e5a75bf37b5bf5b294b0c239590cb258a8266199f",
    )
    _input(
        base,
        "tests/compile_fail/a_splat_info_is_not_a_bare_int.mojo",
        "c55c1951bf968f929fd3f5dfb9cebb9c49ce7ee1d3bf4a7259c37eeceb22af46",
    )
    _input(
        base,
        "tests/compile_fail/a_splat_part_is_not_a_bare_int.mojo",
        "af4017aee6d8d7d3e23a30fa59da038925b618a5556cc3240b90d8092b2206ee",
    )


def main() raises:
    """Check the PR776 bound inputs of this repository.

    Raises:
        Error: A PR776 bound input changed.
    """
    pr776_bound_inputs(".")
