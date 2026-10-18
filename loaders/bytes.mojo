# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whether an ASCII word sits at one byte.

Several readers ask this question. They share one check.
"""


def bytes_match(
    bytes: Span[UInt8, _], at: Int, limit: Int, word: String
) -> Bool:
    """Return True when `word` fits before `limit` and matches there.

    Args:
        bytes: The bytes to read.
        at: The first byte of `word`.
        limit: The first byte `word` must not reach. This is the end of
            `bytes`, or the end of a shorter span inside them.
        word: The ASCII text to match. The word is not empty.

    Returns:
        Whether every byte of `word` is at `at`.
    """
    var expected = word.as_bytes()
    if at + len(expected) > limit:
        return False
    # The word is not empty: the loop always runs.
    for offset in range(len(expected)):  # pragma: no branch
        if bytes[at + offset] != expected[offset]:
            return False
    return True
