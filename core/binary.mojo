# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Little-endian integers shared by the file readers.

The caller checks that `at` lies inside the buffer. These functions do
not allocate and do not raise.
"""


def little_endian_u32(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian 32-bit word at `at`.

    Args:
        bytes: The buffer.
        at: The index of the first byte.

    Returns:
        The word, with the first byte in the low eight bits.
    """
    return (
        Int(bytes[at])
        | (Int(bytes[at + 1]) << 8)
        | (Int(bytes[at + 2]) << 16)
        | (Int(bytes[at + 3]) << 24)
    )
