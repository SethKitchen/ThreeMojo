# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the render-actor and runtime-boundary refusal messages.

    carla_bound_consumer_messages
"""

from std.sys import argv, exit, stderr

from tools._bound_consumer_messages import bound_consumer_messages


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_bound_consumer_messages", file=stderr)
    exit(2)


def main():
    """Print the render-actor and runtime-boundary refusal messages."""
    if len(argv()) != 1:
        _usage()
    print(bound_consumer_messages(), end="")
