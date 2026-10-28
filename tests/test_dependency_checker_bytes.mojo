# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The dependency checkers keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.dependency_checker_bytes import dependency_checker_bytes


def _copy(root: String) raises:
    """Copy the reviewed dependency checkers.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/tools/carla_lane_oracle"],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("tools/carla_lane_oracle/source_contracts.py")
    files.append("tools/carla_lane_oracle/sum2_guard_contracts.py")
    files.append("tools/affected.py")
    files.append("tools/cache_key.py")
    files.append("tools/carla_lane_oracle/consumer_successor_ledger.py")
    files.append("tools/carla_lane_oracle/map_station_contracts.py")
    files.append("tools/carla_lane_oracle/shared_helper_contracts.py")
    files.append("tools/carla_lane_oracle/runtime_view_contracts.py")
    files.append("tools/carla_lane_oracle/map_deviation_contracts.py")
    files.append("tools/carla_lane_oracle/witness_format_contracts.py")
    files.append("tools/carla_lane_oracle/typed_boundary_contracts.py")
    files.append("tools/carla_lane_oracle/conditioned_cubic_contracts.py")
    files.append("tools/carla_lane_oracle/scaled_float32_contracts.py")
    files.append("tools/carla_lane_oracle/pr760_arithmetic_stage.py")
    files.append("tools/carla_lane_oracle/pr780_source_successor.py")
    files.append("tools/carla_lane_oracle/winner_sign_contracts.py")
    files.append("tools/carla_lane_oracle/border_parser_contracts.py")
    files.append("tools/carla_lane_oracle/lane_order_contracts.py")
    files.append("tools/carla_lane_oracle/cache_key_contracts.py")
    files.append("tools/carla_lane_oracle/rounded_line_selector_contracts.py")
    files.append("tools/carla_lane_oracle/seed_count_contracts.py")
    # Copied in this process: one `cp` for each file took most of the
    # five seconds a test may run.
    for path in files:
        Path(root + "/" + path).write_bytes(Path(path).read_bytes())


def test_the_live_dependency_checkers_hold() raises:
    """The 21 dependency checkers keep their reviewed digests."""
    dependency_checker_bytes(".")
    dependency_checker_bytes("./")
    dependency_checker_bytes("tools/..")


def test_a_changed_executing_checker_is_refused() raises:
    """A changed executing checker is refused."""
    var root = "/tmp/dependency-checker-affected"
    _copy(root)
    var path = root + "/tools/affected.py"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains="unreviewed dependency checker bytes: tools/affected.py"
    ):
        dependency_checker_bytes(root)


def test_a_changed_public_checker_is_refused() raises:
    """A changed public checker is refused."""
    var root = "/tmp/dependency-checker-seed"
    _copy(root)
    var path = root + "/tools/carla_lane_oracle/seed_count_contracts.py"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "unreviewed public consumer checker bytes: "
            + "tools/carla_lane_oracle/seed_count_contracts.py"
        )
    ):
        dependency_checker_bytes(root)


def test_a_linked_public_checker_is_refused() raises:
    """A linked public checker is refused."""
    var root = "/tmp/dependency-checker-link"
    _copy(root)
    var path = root + "/tools/carla_lane_oracle/winner_sign_contracts.py"
    var removed = run_program(["rm", path], 10.0)
    if removed.status != 0:
        raise Error(removed.output)
    var linked = run_program(
        ["ln", "-s", "tools/carla_lane_oracle/winner_sign_contracts.py", path],
        10.0,
    )
    if linked.status != 0:
        raise Error(linked.output)
    with assert_raises(
        contains=(
            "unreviewed public consumer checker bytes: "
            + "tools/carla_lane_oracle/winner_sign_contracts.py"
        )
    ):
        dependency_checker_bytes(root)


def main() raises:
    """Run the dependency-checker byte tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
