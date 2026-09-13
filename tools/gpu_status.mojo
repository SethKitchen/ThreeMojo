# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Report whether this machine has a GPU Mojo can target.

`make check-gpu` runs this first so the answer is on screen before the tests
are. Without it a green GPU suite is ambiguous: the tests return early when
there is no accelerator, so "passed" can mean "ran and agreed with the CPU" or
"found no hardware and did nothing at all". Those deserve to look different.

Exits zero either way. Not having a GPU is not a failure — it is the normal
case for most machines, and the CPU renderer is the whole library minus one
module.
"""

from render.gpu import available


def main():
    """Print the accelerator status."""
    if available():
        print("GPU: present. The GPU suite will exercise the device.")
    else:
        print("GPU: absent. Hardware-dependent tests will report SKIP.")
