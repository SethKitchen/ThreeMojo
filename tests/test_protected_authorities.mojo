# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The protected authorities keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.protected_authorities import protected_authorities


def _copy(root: String) raises:
    """Copy the reviewed protected authorities.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        [
            "mkdir",
            "-p",
            root + "/tools/carla_lane_oracle",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("tools/carla_lane_oracle/accepted-successor-migration.json")
    files.append("tools/carla_lane_oracle/border-parser-successor.json")
    files.append("tools/carla_lane_oracle/cache-key-migration.json")
    files.append("tools/carla_lane_oracle/canonical-source-correspondence.json")
    files.append("tools/carla_lane_oracle/conditioned-cubic-successor.json")
    files.append("tools/carla_lane_oracle/constants.json")
    files.append("tools/carla_lane_oracle/consumer-successor-ledger.json")
    files.append(
        "tools/carla_lane_oracle/containing-model-removal-migration.json"
    )
    files.append("tools/carla_lane_oracle/coverage-followup-migration.json")
    files.append("tools/carla_lane_oracle/coverage-invariant-migration.json")
    files.append(
        "tools/carla_lane_oracle/curve-support-dispatch-migration.json"
    )
    files.append(
        "tools/carla_lane_oracle/default-query-restoration-migration.json"
    )
    files.append("tools/carla_lane_oracle/distance-validation-contract.json")
    files.append("tools/carla_lane_oracle/envelope-budget-contract.json")
    files.append("tools/carla_lane_oracle/frozen-arc-producer-migration.json")
    files.append("tools/carla_lane_oracle/full-audit-cleanup-successor.json")
    files.append("tools/carla_lane_oracle/grouped-table-contract.json")
    files.append("tools/carla_lane_oracle/grouped-y-exponent-ledger.json")
    files.append("tools/carla_lane_oracle/grouped-y-successor-record.json")
    files.append("tools/carla_lane_oracle/lane-control-migration.json")
    files.append("tools/carla_lane_oracle/lane-order-migration.json")
    files.append("tools/carla_lane_oracle/moment-finiteness-contract.json")
    files.append("tools/carla_lane_oracle/optional-runtime-migration.json")
    files.append("tools/carla_lane_oracle/raw-cut-inverse-migration.json")
    files.append("tools/carla_lane_oracle/render-actor-reuse-successor.json")
    files.append("tools/carla_lane_oracle/reviewed-cleanup-migration.json")
    files.append("tools/carla_lane_oracle/rounded-line-selector-migration.json")
    files.append(
        "tools/carla_lane_oracle/rounded-line-singleton-migration.json"
    )
    files.append("tools/carla_lane_oracle/runtime-boundary-successor.json")
    files.append(
        "tools/carla_lane_oracle/runtime-correspondence-migration.json"
    )
    files.append("tools/carla_lane_oracle/runtime-source-pins.json")
    files.append("tools/carla_lane_oracle/runtime-view-successor.json")
    files.append("tools/carla_lane_oracle/seed-count-successor.json")
    files.append("tools/carla_lane_oracle/selection-finiteness-contract.json")
    files.append("tools/carla_lane_oracle/shared_helper_contracts.py")
    files.append("tools/carla_lane_oracle/speed-parser-successor.json")
    files.append("tools/carla_lane_oracle/spiral-graph-correspondence.json")
    files.append("tools/carla_lane_oracle/spiral-moment-pins.json")
    files.append("tools/carla_lane_oracle/spiral-moment-provenance.json")
    files.append("tools/carla_lane_oracle/sum2-correspondence-migration.json")
    files.append("tools/carla_lane_oracle/sum2-guard-pins.json")
    files.append("tools/carla_lane_oracle/supported-source.json")
    files.append("tools/carla_lane_oracle/translated-parameter-source.json")
    files.append("tools/carla_lane_oracle/winner-sign-query-migration.json")

    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_protected_authorities_hold() raises:
    """The 44 protected authorities keep their reviewed digests."""
    protected_authorities(".")
    protected_authorities("./")
    protected_authorities("tools/..")


def test_a_changed_first_authority_is_refused() raises:
    """A changed first authority is refused."""
    var root = "/tmp/protected-authority-first"
    _copy(root)
    var path = (
        root + "/tools/carla_lane_oracle/accepted-successor-migration.json"
    )
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "protected authority changed:"
            " tools/carla_lane_oracle/accepted-successor-migration.json"
        )
    ):
        protected_authorities(root)


def test_a_changed_last_authority_is_refused() raises:
    """A changed last authority is refused."""
    var root = "/tmp/protected-authority-last"
    _copy(root)
    var path = (
        root + "/tools/carla_lane_oracle/winner-sign-query-migration.json"
    )
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "protected authority changed: "
            + "tools/carla_lane_oracle/winner-sign-query-migration.json"
        )
    ):
        protected_authorities(root)


def main() raises:
    """Run the protected-authority tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
