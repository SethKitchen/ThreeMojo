# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the GPU status report and its command line without MAX.

`tools/gpu_status.mojo` needs MAX to count devices. Its command line and
its report are in `tools/_gpu_status.mojo`, which needs only the standard
library.
"""

from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tools._gpu_status import (
    ABSENT,
    PRESENT,
    USAGE,
    available_devices,
    outcome,
    parse_gpu_status,
)


def test_available_exits_0_for_a_device_and_1_without() raises:
    var present = outcome(True, True)
    assert_equal(present[0], 0)
    assert_equal(present[1], "")
    var absent = outcome(True, False)
    assert_equal(absent[0], 1)
    assert_equal(absent[1], "")


def test_the_report_names_the_device_state() raises:
    var present = outcome(False, True)
    assert_equal(present[0], 0)
    assert_equal(present[1], "GPU: present. Device parity tests will run.")
    var absent = outcome(False, False)
    assert_equal(absent[0], 0)
    assert_equal(
        absent[1],
        "GPU: absent. Device parity tests SKIP; host layout tests still run.",
    )
    assert_equal(present[1], PRESENT)
    assert_equal(absent[1], ABSENT)


def test_virtual_devices_are_not_physical() raises:
    assert_true(available_devices(1, False))
    assert_false(available_devices(0, False))
    assert_false(available_devices(2, True))


def test_the_command_line_matches_argparse() raises:
    var plain = parse_gpu_status(List[String]())
    assert_equal(plain.status, 0)
    assert_false("--available" in plain.flags)
    var flag = parse_gpu_status(["--avail"])
    assert_equal(flag.status, 0)
    assert_true("--available" in flag.flags)
    var help = parse_gpu_status(["--bogus", "-h"])
    assert_equal(help.status, -1)
    assert_equal(
        help.message,
        (
            "usage: gpu_status.mojo [-h] [--available]\n\nReport physical MAX"
            " devices before compiling accelerator kernels. With\n--available,"
            " exit 0 for a device, 1 for no device, and 2 on error."
            " Compiler\ntarget support alone does not mean a physical device is"
            " present.\n\noptions:\n  -h, --help   show this help message and"
            " exit\n  --available\n"
        ),
    )
    var value = parse_gpu_status(["--available=3"])
    assert_equal(value.status, 2)
    assert_equal(
        value.message,
        String(USAGE)
        + "gpu_status.mojo: error: argument --available: ignored explicit"
        " argument '3'\n",
    )
    var unknown = parse_gpu_status(["--mojo", "-5"])
    assert_equal(
        unknown.message,
        String(USAGE)
        + "gpu_status.mojo: error: unrecognized arguments: --mojo -5\n",
    )
    var separator = parse_gpu_status(["--"])
    assert_equal(separator.status, 2)
    var positional = parse_gpu_status(["--", "-h", "--available"])
    assert_equal(
        positional.message,
        String(USAGE)
        + "gpu_status.mojo: error: unrecognized arguments: -- -h --available\n",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
