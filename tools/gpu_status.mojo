# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Report physical MAX devices before compiling accelerator kernels.

    sh tools/tool.sh .venv/bin/mojo gpu_status [--available]

With --available, exit 0 for a device, 1 for no device, and 2 on error.
Compiler target support alone does not mean a physical device is present,
so the tool asks the MAX driver for CUDA, HIP and Metal devices when it
runs. This program needs MAX. Without MAX, `tools/tool.sh` cannot build it
and exits with status 2, which is the status for an error.
"""

from max.gpu.host import DeviceContext
from std.sys import argv, exit, stderr

from tools._gpu_status import available_devices, outcome, parse_gpu_status


def device_count() raises -> Int:
    """Return the number of physical accelerators that the driver finds.

    A new process makes no virtual devices, so each counted device is
    physical.

    Returns:
        The CUDA, HIP and Metal devices together.

    Raises:
        Error: If the driver cannot count the devices.
    """
    var count = 0
    for api in ["cuda", "hip", "metal"]:
        count += DeviceContext.number_of_devices(api=api)
    return count


def main() raises:
    """Print the device report, or give the status for `--available`.

    Raises:
        Error: If the command line cannot be read.
    """
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var command = parse_gpu_status(arguments)
    if command.status == -1:
        print(command.message, end="")
        exit(0)
    if command.status != 0:
        print(command.message, end="", file=stderr)
        exit(command.status)
    var available: Bool
    try:
        available = available_devices(device_count(), False)
    except error:
        print("GPU detection failed: " + String(error), file=stderr)
        exit(2)
        return
    var result = outcome("--available" in command.flags, available)
    if result[1].byte_length() > 0:
        print(result[1])
    exit(result[0])
