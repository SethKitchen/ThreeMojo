# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed protected authorities.

44 authorities keep their reviewed digests. A changed protected authority
is refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


comptime _PREFIX = "PR760 staged provenance: "


def _fail(message: String) raises:
    """Raise a protected-authority error.

    Args:
        message: The failure text.

    Raises:
        Error: A protected authority changed.
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
    """Require one protected authority to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The authority path.
        expected: The reviewed digest.

    Raises:
        Error: The protected authority changed.
    """
    if sha256_hex(Path(root + "/" + path).read_bytes()) != expected:
        _fail("protected authority changed: " + path)


def protected_authorities(root: String) raises:
    """Require the reviewed protected-authority digests.

    Args:
        root: The repository root.

    Raises:
        Error: A protected authority changed.
    """
    var base = _root(root)
    _input(
        base,
        "tools/carla_lane_oracle/accepted-successor-migration.json",
        "bb3a7b5e08a0a5400679f410da2c4574b45924294133df2f180f71fd74064d91",
    )
    _input(
        base,
        "tools/carla_lane_oracle/border-parser-successor.json",
        "0119f046c502021dc422f82ad602074e24cf3fa192f27fd372e80a927d94860b",
    )
    _input(
        base,
        "tools/carla_lane_oracle/cache-key-migration.json",
        "06f0aefb02a1f897563f4e7d25e0a26f3fc56f1bef5f3fcb8eb68b5cd1188d5b",
    )
    _input(
        base,
        "tools/carla_lane_oracle/canonical-source-correspondence.json",
        "8490ba39e7c31649d935a1ee48c7628cae638e4f968a52db857904a542477e8d",
    )
    _input(
        base,
        "tools/carla_lane_oracle/conditioned-cubic-successor.json",
        "a0cf7af298262796ba1db8292830f683ae2a1c3844e8d8d967fe5f5d4cfa309c",
    )
    _input(
        base,
        "tools/carla_lane_oracle/constants.json",
        "31f1096a37e774523f90f92bc1f1d75c0b288bb74bf226e4cce227625119404c",
    )
    _input(
        base,
        "tools/carla_lane_oracle/consumer-successor-ledger.json",
        "cd966262e04f6017317603e2dd4651c26da58030b780506cb189ce5d1c2ae2be",
    )
    _input(
        base,
        "tools/carla_lane_oracle/containing-model-removal-migration.json",
        "3407eccdc3a2e58acfea1922f6e9f9cb7b9b5601c2c377b8da64ab5e7fb605f8",
    )
    _input(
        base,
        "tools/carla_lane_oracle/coverage-followup-migration.json",
        "911929b7dc80b5c6e09e0cf27b2c8e1f9db52cd8df398d397fc70c900fed759e",
    )
    _input(
        base,
        "tools/carla_lane_oracle/coverage-invariant-migration.json",
        "56a72d9bccbf9e7b8a6b51db2b9944ef4bbf55d9bcc7311f7f9615be3b3b36ac",
    )
    _input(
        base,
        "tools/carla_lane_oracle/curve-support-dispatch-migration.json",
        "1a6d7794bf0869a1e717685e556d8400e075ab97917ce8d855da6bd61c3ee19f",
    )
    _input(
        base,
        "tools/carla_lane_oracle/default-query-restoration-migration.json",
        "b7b619185f2b0139863d6a1a16a29cad3e91db70c1d6d036ec8f115ab3b329fa",
    )
    _input(
        base,
        "tools/carla_lane_oracle/distance-validation-contract.json",
        "74409c5bb90df7e52e7e91c0bb00ed8466e3c0bf4f458507c84f0f72923548bb",
    )
    _input(
        base,
        "tools/carla_lane_oracle/envelope-budget-contract.json",
        "c43aa2bfdfb2a33575745eefb44b2f8ff0714a71a31ad750e8c4c0572fa7f2be",
    )
    _input(
        base,
        "tools/carla_lane_oracle/frozen-arc-producer-migration.json",
        "70091e23400193257514363570187b47890e3c08c352fe79eb08bf291737cc9f",
    )
    _input(
        base,
        "tools/carla_lane_oracle/full-audit-cleanup-successor.json",
        "36198962f9fba313b4da6d74651586e3d1da95a9904e63388aa3014cdada09c5",
    )
    _input(
        base,
        "tools/carla_lane_oracle/grouped-table-contract.json",
        "b0ff2742f388bdd88484fc21a9ac15efa8f7b64f7376908207dfdb7d79f66792",
    )
    _input(
        base,
        "tools/carla_lane_oracle/grouped-y-exponent-ledger.json",
        "a184b9ba8aa05cc85387f97731c949889be1717271c2307373c30fa67e347f65",
    )
    _input(
        base,
        "tools/carla_lane_oracle/grouped-y-successor-record.json",
        "4b72cd07de22d61d70c7aa489e566cd25468189b6a60b5e105fa26ea726e6853",
    )
    _input(
        base,
        "tools/carla_lane_oracle/lane-control-migration.json",
        "73d95d594e740205bad4cd900288a68d9f82897474fdc33e4d6043a156790170",
    )
    _input(
        base,
        "tools/carla_lane_oracle/lane-order-migration.json",
        "e0aece69b861bc11a197cae17803e3273cdbd0cfed7ed0ca577ca6c3b4d217b1",
    )
    _input(
        base,
        "tools/carla_lane_oracle/moment-finiteness-contract.json",
        "06d9206275071726fdda7a58b5aa68c012a361e4e51a5236ff6727c7a8df6f09",
    )
    _input(
        base,
        "tools/carla_lane_oracle/optional-runtime-migration.json",
        "36f47160daa93bcedc338c022b1f6b5e41cae424ca7a6531d46d3daded48a158",
    )
    _input(
        base,
        "tools/carla_lane_oracle/raw-cut-inverse-migration.json",
        "4f4eb051d9c1f9194796d3073fcadfa9f49dda4c44a851da0a3409ba09587dd0",
    )
    _input(
        base,
        "tools/carla_lane_oracle/render-actor-reuse-successor.json",
        "c4d146fe145289a1ad443956d2941d1e90186d448b8056f8be97d72f4f672771",
    )
    _input(
        base,
        "tools/carla_lane_oracle/reviewed-cleanup-migration.json",
        "01753344fe01d885eb3bbaf253815bca01816c57c09b6e7cc1c3a233808b42a9",
    )
    _input(
        base,
        "tools/carla_lane_oracle/rounded-line-selector-migration.json",
        "ccb63b640653126b098185b188e33a036b140919a3c48b1ecb1b1541571ef4c4",
    )
    _input(
        base,
        "tools/carla_lane_oracle/rounded-line-singleton-migration.json",
        "e4a0eb6c9e527dd66b2b803ee69754334feecc9bea33ce001cdf584d3a693506",
    )
    _input(
        base,
        "tools/carla_lane_oracle/runtime-boundary-successor.json",
        "992854b1191bd365fca3e5e8d3a7fc751ac2eb3196b33684e04ebad833baab00",
    )
    _input(
        base,
        "tools/carla_lane_oracle/runtime-correspondence-migration.json",
        "61b54904d08b53231c981cdf40edb502caaaf7f791810d752ae57107f12d808d",
    )
    _input(
        base,
        "tools/carla_lane_oracle/runtime-source-pins.json",
        "897dc034b66fe150ac092de03c5981168751d2c487b4615d45415df66e46f8c8",
    )
    _input(
        base,
        "tools/carla_lane_oracle/runtime-view-successor.json",
        "40fe6f5aef91b4a9f407f1a8ea83721b317d24b690d947c623feca8b73dcc907",
    )
    _input(
        base,
        "tools/carla_lane_oracle/seed-count-successor.json",
        "fe8f0b4bba9ddc037113340e06f223d1ee4ed0b8ec4d67752d4e39ea946be271",
    )
    _input(
        base,
        "tools/carla_lane_oracle/selection-finiteness-contract.json",
        "dcd2c780640775e29a566491679dc6fbf5ab1afa43fbfbae86cb778433cf92e8",
    )
    _input(
        base,
        "tools/carla_lane_oracle/shared_helper_contracts.py",
        "70b070d0bd5117b146a71470a46cb7a02c7fc31dfac1a5236eed50faf75b468e",
    )
    _input(
        base,
        "tools/carla_lane_oracle/speed-parser-successor.json",
        "47e949673fb8740816c06d455654c7e7ae43f65ce7d7568a201e83ae16c49364",
    )
    _input(
        base,
        "tools/carla_lane_oracle/spiral-graph-correspondence.json",
        "5486b6a6b5dd9eaa60582fd5f26d27ad39a533acc73580ad7e7466c716cf0fb5",
    )
    _input(
        base,
        "tools/carla_lane_oracle/spiral-moment-pins.json",
        "f93f01b65069e79bbcf0f056905187c99d0bf438939f5cac00b8b4aff1f4191b",
    )
    _input(
        base,
        "tools/carla_lane_oracle/spiral-moment-provenance.json",
        "3a0e9c2a8dcc1de4d8cdf6ddb3796645b355ce507f3123f6b4c8eeebabc801ba",
    )
    _input(
        base,
        "tools/carla_lane_oracle/sum2-correspondence-migration.json",
        "a965a4fee4c54ac565a5d2f73e0d815bbf9bb72103e5db7a2b5ebbaf5b8ffd77",
    )
    _input(
        base,
        "tools/carla_lane_oracle/sum2-guard-pins.json",
        "229f983ad560d194901aa877b630b08ea9dc656ede5ff61961080c80d1e4fdeb",
    )
    _input(
        base,
        "tools/carla_lane_oracle/supported-source.json",
        "e426aa9b4926aeee8238d529c43e223b88d133d9ee05f8867b939b99b4675018",
    )
    _input(
        base,
        "tools/carla_lane_oracle/translated-parameter-source.json",
        "4fa22368f74fe53ad18aab0e1a7732bf9cf5dd219b4130d1fd8f496f2076a946",
    )
    _input(
        base,
        "tools/carla_lane_oracle/winner-sign-query-migration.json",
        "b154b18213f9f0400661aff93e47b86bf83990c8838dfa0fca00b0fe6710b9a3",
    )


def main() raises:
    """Check the protected authorities of this repository.

    Raises:
        Error: A protected authority changed.
    """
    protected_authorities(".")
