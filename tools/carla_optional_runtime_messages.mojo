# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the optional-runtime contract messages.

    carla_optional_runtime_messages
"""

from std.sys import argv, exit, stderr

from tools._optional_runtime_messages import optional_runtime_messages


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_optional_runtime_messages", file=stderr)
    exit(2)


def main():
    """Print the optional-runtime contract messages."""
    if len(argv()) != 1:
        _usage()
    print(optional_runtime_messages(), end="")
