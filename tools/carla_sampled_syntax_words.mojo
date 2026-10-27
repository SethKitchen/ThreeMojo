# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the sampled syntax keywords and the generic messages.

    carla_sampled_syntax_words
"""

from std.sys import argv, exit, stderr

from tools._sampled_syntax_words import sampled_syntax_words


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_sampled_syntax_words", file=stderr)
    exit(2)


def main():
    """Print the sampled syntax keywords and the generic messages."""
    if len(argv()) != 1:
        _usage()
    print(sampled_syntax_words(), end="")
