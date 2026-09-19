# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A program that does nothing, for the cost of starting one.

    mojo build -o bench/build/noop bench/noop.mojo

`tools/bench_examples.py` times this beside `node -e ""` so the benchmark
page can show how much of each example's run is the process starting rather
than the frames being drawn. It imports nothing from ThreeMojo.
"""


def main():
    pass
