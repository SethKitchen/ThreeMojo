# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The main rebase inputs keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.main_rebase_inputs import main_rebase_inputs


def _copy(root: String) raises:
    """Copy the reviewed main inputs.

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
            root + "/examples",
            root + "/extensions/streamline",
            root + "/tests/compile_fail",
            root + "/tools/carla_lane_oracle",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("examples/streamline.mojo")
    files.append("extensions/streamline/__init__.mojo")
    files.append("extensions/streamline/constants.mojo")
    files.append("extensions/streamline/kinds.mojo")
    files.append("extensions/streamline/options.mojo")
    files.append("extensions/streamline/tags.mojo")
    files.append("tests/compile_fail/a_buffer_kind_is_not_a_bare_int.mojo")
    files.append("tests/compile_fail/a_denoiser_preset_is_not_a_bare_int.mojo")
    files.append("tests/compile_fail/a_dlss_feature_is_not_a_bare_int.mojo")
    files.append("tests/compile_fail/a_dlss_mode_is_not_a_bare_int.mojo")
    files.append(
        "tests/compile_fail/a_motion_vector_space_is_not_a_bare_int.mojo"
    )
    files.append(
        "tests/compile_fail/a_normal_roughness_mode_is_not_a_bare_int.mojo"
    )
    files.append(
        "tests/compile_fail/a_super_resolution_preset_is_not_a_bare_int.mojo"
    )
    files.append("tests/test_streamline_constants.mojo")
    files.append("tests/test_streamline_kinds.mojo")
    files.append("tests/test_streamline_options.mojo")
    files.append("tests/test_streamline_tags.mojo")
    files.append("tools/carla_lane_oracle/typed_boundary_contracts.py")

    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_main_inputs_hold() raises:
    """The 18 main inputs keep their reviewed digests."""
    main_rebase_inputs(".")
    main_rebase_inputs("./")
    main_rebase_inputs("examples/..")


def test_a_changed_streamline_example_is_refused() raises:
    """A changed streamline example is refused."""
    var root = "/tmp/main-rebase-streamline"
    _copy(root)
    var path = root + "/examples/streamline.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(contains="main input changed: examples/streamline.mojo"):
        main_rebase_inputs(root)


def test_a_changed_typed_boundary_contract_is_refused() raises:
    """A changed typed-boundary contract is refused."""
    var root = "/tmp/main-rebase-typed"
    _copy(root)
    var path = root + "/tools/carla_lane_oracle/typed_boundary_contracts.py"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "main input changed: "
            + "tools/carla_lane_oracle/typed_boundary_contracts.py"
        )
    ):
        main_rebase_inputs(root)


def main() raises:
    """Run the main-rebase input tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
