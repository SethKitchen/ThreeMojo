# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed full-audit authority files.

The cleanup record keeps its reviewed digest. The PR760 image and the
owner predecessor keep their digests. The consumer ledger keeps its
reviewed digest. A changed authority file is refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


comptime _PREFIX = "full-audit cleanup successor: "
comptime _RECORD = "tools/carla_lane_oracle/full-audit-cleanup-successor.json"
comptime _RECORD_SHA = (
    "36198962f9fba313b4da6d74651586e3d1da95a9904e63388aa3014cdada09c5"
)
comptime _IMAGE = "tools/carla_lane_oracle/pr760-source-image.json"
comptime _IMAGE_SHA = (
    "ef91b7edab2c8a597aeedc90f86e834d5227aad5770ebe39e0438944f246f7cf"
)
comptime _OWNER = "tools/carla_lane_oracle/pr760-owner-predecessor.txt"
comptime _OWNER_SHA = (
    "6138ba2dcac394c716ea9ed32e74e0c6d15857d5c605fc82304d21d0c80fdc69"
)
comptime _LEDGER = "tools/carla_lane_oracle/consumer-successor-ledger.json"
comptime _LEDGER_SHA = (
    "cd966262e04f6017317603e2dd4651c26da58030b780506cb189ce5d1c2ae2be"
)


def _fail(message: String) raises:
    """Raise a full-audit authority error.

    Args:
        message: The failure text.

    Raises:
        Error: An authority file changed.
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


def _file(root: String, path: String, expected: String, message: String) raises:
    """Require one authority file to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The authority path.
        expected: The reviewed digest.
        message: The refusal text.

    Raises:
        Error: The authority file changed.
    """
    if sha256_hex(Path(root + "/" + path).read_bytes()) != expected:
        _fail(message)


def full_audit_authority(root: String) raises:
    """Require the reviewed full-audit authority digests.

    Args:
        root: The repository root.

    Raises:
        Error: An authority file changed.
    """
    var base = _root(root)
    _file(base, _RECORD, _RECORD_SHA, "immutable successor record changed")
    _file(base, _IMAGE, _IMAGE_SHA, "PR760 physical-image authority changed")
    _file(base, _OWNER, _OWNER_SHA, "PR760 predecessor owner evidence changed")
    _file(base, _LEDGER, _LEDGER_SHA, "unreviewed consumer ledger")


def main() raises:
    """Check the full-audit authority files of this repository.

    Raises:
        Error: An authority file changed.
    """
    full_audit_authority(".")
