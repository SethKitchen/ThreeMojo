# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The width-overflow witness keeps its reviewed formatting endpoint."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.witness_width_successor import witness_width_successor


def _copy(root: String) raises:
    """Copy the width-overflow witness.

    Args:
        root: The temporary repository.

    Raises:
        Error: The file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(["mkdir", "-p", root + "/tests"], 10.0)
    if made.status != 0:
        raise Error(made.output)
    var copied = run_program(
        [
            "cp",
            "tests/test_carla_width_overflow_admission.mojo",
            root + "/tests/test_carla_width_overflow_admission.mojo",
        ],
        10.0,
    )
    if copied.status != 0:
        raise Error(copied.output)


def test_the_live_width_witness_holds() raises:
    """The live witness restores the historical formatting."""
    witness_width_successor(".")
    witness_width_successor("./")
    witness_width_successor("tests/..")


def test_a_changed_witness_is_refused() raises:
    """A changed witness file is refused."""
    var root = "/tmp/witness-width-endpoint"
    _copy(root)
    var path = root + "/tests/test_carla_width_overflow_admission.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "unknown exact formatted witness: "
            + "tests/test_carla_width_overflow_admission.mojo"
        )
    ):
        witness_width_successor(root)


def test_a_changed_formatting_word_is_refused() raises:
    """A changed formatting comment is refused."""
    var root = "/tmp/witness-width-edit"
    _copy(root)
    var path = root + "/tests/test_carla_width_overflow_admission.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace(
            "recursive search or a large workload",
            "recursive searches or a large workload",
        )
    )
    with assert_raises(
        contains=(
            "unknown exact formatted witness: "
            + "tests/test_carla_width_overflow_admission.mojo"
        )
    ):
        witness_width_successor(root)


def main() raises:
    """Run the width-overflow witness tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
