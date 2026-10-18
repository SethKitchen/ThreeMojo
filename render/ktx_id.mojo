# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The twelve bytes at the start of a KTX file.

KTX 1 and KTX 2 share the mark, the space, and the ending. Only the two
version bytes differ.
"""


def ktx_file_id(major: UInt8, minor: UInt8) -> List[UInt8]:
    """Return the twelve-byte identifier for one KTX version.

    Args:
        major: The ASCII byte of the major version.
        minor: The ASCII byte of the minor version.

    Returns:
        The identifier. It starts with the KTX mark and ends with the
        line ending and the DOS end-of-file byte.
    """
    return [
        0xAB,
        0x4B,
        0x54,
        0x58,
        0x20,
        major,
        minor,
        0xBB,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
    ]
