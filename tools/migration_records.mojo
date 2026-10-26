# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed migration records.

Seventeen records keep their reviewed digests. A changed migration
record is refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


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


def _record(
    root: String, path: String, expected: String, message: String
) raises:
    """Require one migration record to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The migration path.
        expected: The reviewed digest.
        message: The refusal text.

    Raises:
        Error: The migration record changed.
    """
    if sha256_hex(Path(root + "/" + path).read_bytes()) != expected:
        raise Error(message)


def migration_records(root: String) raises:
    """Require the reviewed migration-record digests.

    Args:
        root: The repository root.

    Raises:
        Error: A migration record changed.
    """
    var base = _root(root)
    _record(
        base,
        "tools/carla_lane_oracle/accepted-successor-migration.json",
        "bb3a7b5e08a0a5400679f410da2c4574b45924294133df2f180f71fd74064d91",
        "accepted source successor: unreviewed migration record",
    )
    _record(
        base,
        "tools/carla_lane_oracle/border-parser-successor.json",
        "0119f046c502021dc422f82ad602074e24cf3fa192f27fd372e80a927d94860b",
        "reviewed border parser successor: immutable successor record changed",
    )
    _record(
        base,
        "tools/carla_lane_oracle/cache-key-migration.json",
        "06f0aefb02a1f897563f4e7d25e0a26f3fc56f1bef5f3fcb8eb68b5cd1188d5b",
        "cache-key successor: migration record changed",
    )
    _record(
        base,
        "tools/carla_lane_oracle/conditioned-cubic-successor.json",
        "a0cf7af298262796ba1db8292830f683ae2a1c3844e8d8d967fe5f5d4cfa309c",
        "conditioned source fixture changed",
    )
    _record(
        base,
        "tools/carla_lane_oracle/coverage-followup-migration.json",
        "911929b7dc80b5c6e09e0cf27b2c8e1f9db52cd8df398d397fc70c900fed759e",
        "coverage followup successor: unreviewed migration record",
    )
    _record(
        base,
        "tools/carla_lane_oracle/coverage-invariant-migration.json",
        "56a72d9bccbf9e7b8a6b51db2b9944ef4bbf55d9bcc7311f7f9615be3b3b36ac",
        "coverage invariant successor: unreviewed migration record",
    )
    _record(
        base,
        "tools/carla_lane_oracle/curve-support-dispatch-migration.json",
        "1a6d7794bf0869a1e717685e556d8400e075ab97917ce8d855da6bd61c3ee19f",
        "curve support/dispatch contract: unreviewed migration record",
    )
    _record(
        base,
        "tools/carla_lane_oracle/frozen-arc-producer-migration.json",
        "70091e23400193257514363570187b47890e3c08c352fe79eb08bf291737cc9f",
        "frozen ARC producer contract: unreviewed migration record",
    )
    _record(
        base,
        "tools/carla_lane_oracle/grouped-y-successor-record.json",
        "4b72cd07de22d61d70c7aa489e566cd25468189b6a60b5e105fa26ea726e6853",
        "Unreviewed grouped Y successor record",
    )
    _record(
        base,
        "tools/carla_lane_oracle/raw-cut-inverse-migration.json",
        "4f4eb051d9c1f9194796d3073fcadfa9f49dda4c44a851da0a3409ba09587dd0",
        "raw cut inverse contract: unreviewed migration record",
    )
    _record(
        base,
        "tools/carla_lane_oracle/render-actor-reuse-successor.json",
        "c4d146fe145289a1ad443956d2941d1e90186d448b8056f8be97d72f4f672771",
        "reviewed render actor reuse successor: unreviewed exact edge",
    )
    _record(
        base,
        "tools/carla_lane_oracle/reviewed-cleanup-migration.json",
        "01753344fe01d885eb3bbaf253815bca01816c57c09b6e7cc1c3a233808b42a9",
        "reviewed cleanup source contract: unreviewed migration record",
    )
    _record(
        base,
        "tools/carla_lane_oracle/rounded-line-selector-migration.json",
        "ccb63b640653126b098185b188e33a036b140919a3c48b1ecb1b1541571ef4c4",
        "rounded LINE selector contract: unreviewed selector migration",
    )
    _record(
        base,
        "tools/carla_lane_oracle/rounded-line-singleton-migration.json",
        "e4a0eb6c9e527dd66b2b803ee69754334feecc9bea33ce001cdf584d3a693506",
        "rounded LINE singleton contract: unreviewed migration record",
    )
    _record(
        base,
        "tools/carla_lane_oracle/runtime-boundary-successor.json",
        "992854b1191bd365fca3e5e8d3a7fc751ac2eb3196b33684e04ebad833baab00",
        "reviewed runtime boundary successor: unreviewed exact edge",
    )
    _record(
        base,
        "tools/carla_lane_oracle/runtime-view-successor.json",
        "40fe6f5aef91b4a9f407f1a8ea83721b317d24b690d947c623feca8b73dcc907",
        "reviewed runtime view successor: unreviewed exact step",
    )
    _record(
        base,
        "tools/carla_lane_oracle/speed-parser-successor.json",
        "47e949673fb8740816c06d455654c7e7ae43f65ce7d7568a201e83ae16c49364",
        "reviewed speed parser successor: unreviewed exact edge",
    )


def main() raises:
    """Check the migration records of this repository.

    Raises:
        Error: A migration record changed.
    """
    migration_records(".")
