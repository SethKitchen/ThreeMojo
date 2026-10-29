# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the benchmark tools read about their host, through the C library.

The benchmarks record the machine and the environment they ran in:
`uname`, environment variables and the whole environment array.
"""

from std.ffi import OwnedDLHandle, external_call
from std.sys import CompilationTarget


def two_digits(value: Int) -> String:
    """Return a number with at least two digits.

    Args:
        value: The number, zero or more.

    Returns:
        The digits, with a leading zero below ten.
    """
    return ("0" if value < 10 else "") + String(value)


def c_string(text: String) -> List[UInt8]:
    """Return text with a final zero byte, for a C call.

    Args:
        text: The text.

    Returns:
        Its bytes and a zero.
    """
    var bytes = List[UInt8](text.as_bytes())
    bytes.append(0)
    return bytes^


def read_c_string(address: Int) -> String:
    """Return the zero-terminated text at an address.

    Args:
        address: The address. Zero gives an empty text.

    Returns:
        The text, with a replacement character for each bad UTF-8 byte.
    """
    if address == 0:
        return String()
    var length = external_call["strlen", Int](address)
    var bytes = List[UInt8](length=length, fill=0)
    _ = external_call["memcpy", Int](
        bytes.unsafe_ptr().unsafe_bitcast[NoneType](), address, length
    )
    return String(from_utf8_lossy=bytes)


def environment_value(name: String) -> Optional[String]:
    """Return an environment variable, or None when it is unset.

    Args:
        name: The variable.

    Returns:
        The value, which can be empty, or None.
    """
    var key = c_string(name)
    var address = external_call["getenv", Int](
        key.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    if address == 0:
        return None
    return read_c_string(address)


def environ_address() raises -> Int:
    """Return the address of this process's environment array.

    Returns:
        The address of the first `char *` of `environ`.

    Raises:
        Error: If the C library has no `environ` symbol.
    """
    comptime if CompilationTarget.is_macos():
        var cell = external_call["_NSGetEnviron", Int]()
        var value = List[Int](length=1, fill=0)
        _ = external_call["memcpy", Int](
            value.unsafe_ptr().unsafe_bitcast[NoneType](), cell, 8
        )
        return value[0]
    else:
        var handle = OwnedDLHandle()
        var symbol = handle.get_symbol[Int]("environ")
        var address: Int = symbol[][]
        return address


def uname_fields() -> List[String]:
    """Return `uname` as system, node, release, version and machine.

    Returns:
        The five fields.
    """
    var buffer = List[UInt8](length=2048, fill=0)
    _ = external_call["uname", Int32](
        buffer.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    var width: Int
    comptime if CompilationTarget.is_macos():
        width = 256
    else:
        width = 65
    var fields = List[String]()
    for index in range(5):
        var text = List[UInt8]()
        for i in range(width):
            var byte = buffer[index * width + i]
            if byte == 0:
                break
            text.append(byte)
        fields.append(String(from_utf8_lossy=text))
    return fields^
