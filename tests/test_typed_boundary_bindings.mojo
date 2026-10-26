# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The typed-boundary binding inputs keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.typed_boundary_bindings import typed_boundary_bindings


def _copy(root: String) raises:
    """Copy the reviewed binding inputs.

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
            root + "/docs/validation",
            root + "/tools/carla_lane_oracle",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("docs/validation/carla-namespace-lookup-333.json")
    files.append("docs/validation/typed-boundary-successor-333.md")
    files.append("tools/carla_lane_oracle/envelope_budget_contracts.py")
    files.append("tools/carla_lane_oracle/oracle.py")
    files.append("tools/carla_lane_oracle/probe_typed_namespace_lookup.py")
    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_binding_inputs_hold() raises:
    """The five binding inputs keep their reviewed digests."""
    typed_boundary_bindings(".")
    typed_boundary_bindings("./")
    typed_boundary_bindings("docs/..")


def test_a_changed_namespace_lookup_is_refused() raises:
    """A changed namespace lookup is refused."""
    var root = "/tmp/typed-boundary-bindings-lookup"
    _copy(root)
    var path = root + "/docs/validation/carla-namespace-lookup-333.json"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "typed boundary bound input changed: "
            + "docs/validation/carla-namespace-lookup-333.json"
        )
    ):
        typed_boundary_bindings(root)


def test_a_changed_namespace_probe_is_refused() raises:
    """A changed namespace probe is refused."""
    var root = "/tmp/typed-boundary-bindings-probe"
    _copy(root)
    var path = root + "/tools/carla_lane_oracle/probe_typed_namespace_lookup.py"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "typed boundary bound input changed: "
            + "tools/carla_lane_oracle/probe_typed_namespace_lookup.py"
        )
    ):
        typed_boundary_bindings(root)


def main() raises:
    """Run the typed-boundary binding-input tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
