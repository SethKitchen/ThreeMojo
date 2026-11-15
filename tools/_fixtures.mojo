# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared parts of the generators of synthetic test data.

A generator `tools/make_NAME.mojo` writes the synthetic inputs of a test
into `assets/`. A Python script beside them then reads the inputs, runs
the reference library and writes the expected values. Only that script
needs Python.

- `SEED` is the seed of every generator, so one run gives the same files.
- `normal(noise, mean, sd)` gives a normal number.
- `whole(x)` rounds to an integer, a half to the even one.
- `numbers(values)` and `integers(values)` join values with spaces, each
  number as the shortest text that reads back to it.
- `write_text(path, text)` writes a file.
"""

from extensions.numerics.noise import Xorshift64
from std.pathlib import Path

comptime SEED = 20261115
"""The seed of every fixture generator."""


def normal(mut noise: Xorshift64, mean: Float64, sd: Float64) -> Float64:
    """Return a normal number.

    Args:
        noise: The source.
        mean: The mean.
        sd: The standard deviation.

    Returns:
        `mean + sd z`, with z the next standard normal number.
    """
    return mean + sd * noise.normal()


def whole(x: Float64) -> Int:
    """Return a number rounded to an integer, a half to the even one.

    Args:
        x: The number, finite.

    Returns:
        The nearest integer.
    """
    return Int(round(x))


def numbers(values: List[Float64]) -> String:
    """Return numbers separated by spaces.

    Args:
        values: The numbers.

    Returns:
        Each number as the shortest text that reads back to it.
    """
    var out = String()
    for i in range(len(values)):
        if i > 0:
            out += " "
        out += String(values[i])
    return out^


def integers(values: List[Int]) -> String:
    """Return integers separated by spaces.

    Args:
        values: The integers.

    Returns:
        The integers in decimal.
    """
    var out = String()
    for i in range(len(values)):
        if i > 0:
            out += " "
        out += String(values[i])
    return out^


def write_text(path: String, text: String) raises:
    """Write a text file.

    Args:
        path: The path, relative to the repository root.
        text: The text.

    Raises:
        Error: If the file cannot be written.
    """
    Path(path).write_text(text)
    print("wrote", path)
