# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reproduce the CUDA device-context teardown hang.

The write-up is the wiki page "The CUDA teardown hang", whose source is
docs/wiki/The-CUDA-teardown-hang.md.

    mojo run -I . docs/max-gpu-teardown-issue/repro.mojo buffers_first
    mojo run -I . docs/max-gpu-teardown-issue/repro.mojo context_first

The first exits normally. The second never returns from the *second*
context's first allocation on MAX 26.5.0 under CUDA on WSL 2, so run it under
`timeout`.
"""

from max.gpu.host import DeviceContext
from std.sys import argv


def buffers_first(label: String) raises:
    """Create a context and two buffers; release the buffers, then the context.
    """
    var ctx = DeviceContext()
    var pixels = ctx.enqueue_create_buffer[DType.uint8](256)
    var depth = ctx.enqueue_create_buffer[DType.float32](256)
    ctx.synchronize()
    _ = pixels^
    _ = depth^
    print(label, "buffers released")
    _ = ctx^
    print(label, "context released")


def context_first(label: String) raises:
    """The same, but release the context while its buffers are alive."""
    var ctx = DeviceContext()
    var pixels = ctx.enqueue_create_buffer[DType.uint8](256)
    var depth = ctx.enqueue_create_buffer[DType.float32](256)
    ctx.synchronize()
    _ = ctx^
    print(label, "context released")
    _ = pixels^
    _ = depth^
    print(label, "buffers released")


def main() raises:
    var variant = String(argv()[1])
    if variant == "buffers_first":
        buffers_first("A")
        buffers_first("B")
        print("OK: buffers then context, twice")
    else:
        context_first("A")
        # Hangs here, inside B's first enqueue_create_buffer.
        context_first("B")
        print("OK: context then buffers, twice")
