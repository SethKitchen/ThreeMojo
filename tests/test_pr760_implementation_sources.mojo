# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The PR760 implementation sources keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.pr760_implementation_sources import pr760_implementation_sources


def _copy(root: String) raises:
    """Copy the eight implementation sources.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/tools/carla_lane_oracle"], 10.0
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("tools/carla_lane_oracle/pr760-border_parser-predecessor.txt")
    files.append("tools/carla_lane_oracle/pr760-seed_count-predecessor.txt")
    files.append("tools/carla_lane_oracle/pr760-source-adapter-predecessor.txt")
    files.append("tools/carla_lane_oracle/pr760-winner_sign-predecessor.txt")
    files.append("tools/carla_lane_oracle/border_parser_contracts.py")
    files.append("tools/carla_lane_oracle/seed_count_contracts.py")
    files.append("tools/carla_lane_oracle/source_contracts.py")
    files.append("tools/carla_lane_oracle/winner_sign_contracts.py")
    # Copied in this process: one `cp` for each file took most of the
    # five seconds a test may run.
    for path in files:
        Path(root + "/" + path).write_bytes(Path(path).read_bytes())


def test_the_live_implementation_sources_hold() raises:
    """The eight sources keep their reviewed digests."""
    pr760_implementation_sources(".")
    pr760_implementation_sources("./")
    pr760_implementation_sources("tools/..")


def test_a_changed_predecessor_is_refused() raises:
    """A changed predecessor text is refused."""
    var root = "/tmp/pr760-implementation-predecessor"
    _copy(root)
    var path = (
        root + "/tools/carla_lane_oracle/pr760-border_parser-predecessor.txt"
    )
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "PR760 implementation source changed: "
            + "tools/carla_lane_oracle/pr760-border_parser-predecessor.txt"
        )
    ):
        pr760_implementation_sources(root)


def test_a_changed_successor_is_refused() raises:
    """A changed successor module is refused."""
    var root = "/tmp/pr760-implementation-successor"
    _copy(root)
    var path = root + "/tools/carla_lane_oracle/winner_sign_contracts.py"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "PR760 implementation source changed: "
            + "tools/carla_lane_oracle/winner_sign_contracts.py"
        )
    ):
        pr760_implementation_sources(root)


def main() raises:
    """Run the PR760 implementation-source tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
