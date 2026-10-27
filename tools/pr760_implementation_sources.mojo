# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed PR760 implementation sources.

Four predecessor texts keep their reviewed digests. Four successor
modules keep their reviewed digests. A changed implementation source
is refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


comptime _PREFIX = "full-audit cleanup successor: "


def _fail(message: String) raises:
    """Raise a PR760 implementation-source error.

    Args:
        message: The failure text.

    Raises:
        Error: An implementation source changed.
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


def _source(root: String, path: String, expected: String) raises:
    """Require one implementation source to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The source path.
        expected: The reviewed digest.

    Raises:
        Error: The source changed.
    """
    var digest = sha256_hex(Path(root + "/" + path).read_bytes())
    if digest != expected:
        _fail("PR760 implementation source changed: " + path)


def pr760_implementation_sources(root: String) raises:
    """Require the reviewed PR760 predecessor and successor digests.

    Args:
        root: The repository root.

    Raises:
        Error: An implementation source changed.
    """
    var base = _root(root)
    _source(
        base,
        "tools/carla_lane_oracle/pr760-border_parser-predecessor.txt",
        "d7a638dcf4d5cadabd183be03cbea08945e9bb5351f4b96dd24803d42fa5626e",
    )
    _source(
        base,
        "tools/carla_lane_oracle/pr760-seed_count-predecessor.txt",
        "ff4a330326fd69bc649e6f235d1f05db4ed40e6b76b1d75e66a4474741c16345",
    )
    _source(
        base,
        "tools/carla_lane_oracle/pr760-source-adapter-predecessor.txt",
        "83fdd35b61f0dc7739160c113ae6b4558ad07d45ffded22b7062bc9a209032d0",
    )
    _source(
        base,
        "tools/carla_lane_oracle/pr760-winner_sign-predecessor.txt",
        "2ed96052d6568fee1bb7700515b7ad03bd38edafc7ca413fc1c03bb9ad5f6aad",
    )
    _source(
        base,
        "tools/carla_lane_oracle/border_parser_contracts.py",
        "734d7b24aaf4e9f537cd7f0d7c7b8094d9c29106770b66c4a7a24cab74604dd4",
    )
    _source(
        base,
        "tools/carla_lane_oracle/seed_count_contracts.py",
        "daa8f391a18e54a3fae958150673c134897db52ce5de87291f613f84df7c6d90",
    )
    _source(
        base,
        "tools/carla_lane_oracle/source_contracts.py",
        "41c7beca0d045d43d51f6100ba4f45a41baa0f8d784498845e22cfdfd3de504f",
    )
    _source(
        base,
        "tools/carla_lane_oracle/winner_sign_contracts.py",
        "f850902634073364fe2407b00d12e9fdfb2ecfc6cf2a03414269fbb7984a8a7f",
    )


def main() raises:
    """Check the PR760 implementation sources of this repository.

    Raises:
        Error: An implementation source changed.
    """
    pr760_implementation_sources(".")
