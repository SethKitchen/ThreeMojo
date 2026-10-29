# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Inputs and digests for tests that pin the output of a reference library.

A test draws its inputs with Python's `random.Random`, so the cases are the
ones the reference library saw. It then compares the SHA-256 of the Mojo
output with the digest that the reference library wrote for the same case.
"""

from tools._python_random import PythonRandom
from tools._sha256 import sha256_hex


def random_bytes(mut rng: PythonRandom, count: Int) -> List[Int]:
    """Return `count` draws of Python's `rng.randrange(256)`.

    `randrange(256)` takes nine random bits and rejects values from 256 up.

    Args:
        rng: The generator, advanced in place.
        count: The number of draws.

    Returns:
        The values, each in [0, 256).
    """
    var out = List[Int](capacity=count)
    while len(out) < count:
        var value = Int(rng.next_word() >> 23)
        if value < 256:
            out.append(value)
    return out^


def int_list(values: List[Int]) -> String:
    """Return `values` as a compact JSON array.

    Args:
        values: The integers.

    Returns:
        The array text, as `json.dumps(..., separators=(',', ':'))` writes it.
    """
    var text = String("[")
    for index in range(len(values)):
        if index > 0:
            text += ","
        text += String(values[index])
    return text + "]"


def digest(data: List[UInt8]) -> String:
    """Return the SHA-256 of `data` as lowercase hex.

    Args:
        data: The bytes.

    Returns:
        The digest.
    """
    return sha256_hex(Span(data))
