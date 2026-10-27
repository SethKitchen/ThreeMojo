# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the reviewed contract prefixes.

    carla_contract_prefixes
"""

from std.sys import argv, exit, stderr

from tools._contract_prefixes import contract_prefixes


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_contract_prefixes", file=stderr)
    exit(2)


def main():
    """Print the reviewed contract prefixes."""
    if len(argv()) != 1:
        _usage()
    print(contract_prefixes(), end="")
