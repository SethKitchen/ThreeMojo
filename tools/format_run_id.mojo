# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Print one random id for a formatter manifest.

    format_run_id

prints 32 lowercase hexadecimal digits and a newline, the same shape as
`uuid.uuid4().hex`. The id is a version-4 UUID: 122 random bits, with the
version and variant fields set. Make uses it so concurrent `fmt-check`
runs do not share one manifest.
"""

from std.ffi import external_call
from std.sys import exit, stderr


def random_id() raises -> String:
    """Return 32 lowercase hex digits from a version-4 UUID.

    Returns:
        The id, without a newline.

    Raises:
        Error: If the operating system cannot supply random bytes.
    """
    var raw = List[UInt8](length=16, fill=0)
    var status = external_call["getentropy", Int32](
        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(raw.unsafe_ptr())),
        UInt64(16),
    )
    if status != 0:
        raise Error("getentropy failed")
    raw[6] = (raw[6] & 0x0F) | 0x40
    raw[8] = (raw[8] & 0x3F) | 0x80
    var digits = "0123456789abcdef"
    var text = String()
    for byte in raw:
        var value = Int(byte)
        text += digits[byte = value // 16 : value // 16 + 1]
        text += digits[byte = value % 16 : value % 16 + 1]
    return text^


def main() raises:
    """Print one random formatter id."""
    try:
        print(random_id())
    except error:
        print("format_run_id:", error, file=stderr)
        exit(1)
