# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the lane-control labels and the frozen reference prefix.

    carla_lane_control_labels
"""

from std.sys import argv, exit, stderr

from tools._lane_control_labels import lane_control_labels


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_lane_control_labels", file=stderr)
    exit(2)


def main():
    """Print the lane-control labels and the frozen reference prefix."""
    if len(argv()) != 1:
        _usage()
    print(lane_control_labels(), end="")
