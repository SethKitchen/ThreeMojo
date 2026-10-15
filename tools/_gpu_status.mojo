# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The command line and the report of `tools/gpu_status.mojo`.

The tool itself needs MAX to count the devices. This module needs only the
standard library, so a CPU test suite can check the command line and the
report.
"""

from tools._cli import CommandLine, parse_command_line

comptime PROGRAM = "gpu_status.mojo"
"""The program name in usage messages."""
comptime USAGE = "usage: gpu_status.mojo [-h] [--available]\n"
"""The usage text, as `argparse` writes it."""
comptime HELP = (
    "\nReport physical MAX devices before compiling accelerator kernels."
    " With\n--available, exit 0 for a device, 1 for no device, and 2 on"
    " error. Compiler\ntarget support alone does not mean a physical device"
    " is present.\n\noptions:\n  -h, --help   show this help message and"
    " exit\n  --available\n"
)
"""The help text after the usage."""
comptime PRESENT = "GPU: present. Device parity tests will run."
"""The report when a device is present."""
comptime ABSENT = (
    "GPU: absent. Device parity tests SKIP; host layout tests still run."
)
"""The report when no device is present."""


def parse_gpu_status(arguments: List[String]) -> CommandLine:
    """Parse the tool's command line.

    Args:
        arguments: The arguments, without the program name.

    Returns:
        The options. A nonzero status carries the text to print.
    """
    return parse_command_line(
        arguments, PROGRAM, USAGE, HELP, ["--available"], List[String]()
    )


def outcome(only_status: Bool, available: Bool) -> Tuple[Int, String]:
    """Return the exit status and the report line.

    Args:
        only_status: True for `--available`, which prints nothing.
        available: True when a physical device is present.

    Returns:
        The exit status and the line to print, which is empty for
        `--available`.
    """
    if only_status:
        return (0 if available else 1, String())
    return (0, String(PRESENT) if available else String(ABSENT))


def available_devices(count: Int, virtual: Bool) -> Bool:
    """Return whether physical devices are present.

    Args:
        count: The number of accelerators that the driver reports.
        virtual: True when the driver makes virtual devices.

    Returns:
        True for at least one device that is not virtual.
    """
    return not virtual and count > 0
