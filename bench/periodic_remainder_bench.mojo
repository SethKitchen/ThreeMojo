# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare unchanged ordinary workloads and hard finite remainder inputs.

The legacy hard path is a timing reference, not a correctness reference.
Its checksum is expected to differ. Each row reports 200,000 calls.
"""

from math.utils import euclidean_modulo, pingpong
from std.memory import bitcast
from std.time import perf_counter_ns


def _input(index: Int, kind: Int) -> Float32:
    if kind == 0:
        return Float32(index % 256) / 64
    if kind == 1:
        return Float32(index % 8192) / 8 - 512
    return bitcast[DType.float32](UInt32(0x71800000) + UInt32(index % 4096))


def _legacy(count: Int, kind: Int) -> Float64:
    var checksum = Float64(0)
    for i in range(count):
        var n = _input(i, kind)
        checksum += Float64(((n % Float32(1.5)) + Float32(1.5)) % Float32(1.5))
    return checksum


def _corrected(count: Int, kind: Int) -> Float64:
    var checksum = Float64(0)
    for i in range(count):
        checksum += Float64(euclidean_modulo(_input(i, kind), 1.5))
    return checksum


def _legacy_wave(count: Int, kind: Int) -> Float64:
    var checksum = Float64(0)
    for i in range(count):
        var n = _input(i, kind)
        var phase = ((n % Float32(1.5)) + Float32(1.5)) % Float32(1.5)
        checksum += Float64(Float32(0.75) - abs(phase - Float32(0.75)))
    return checksum


def _wave(count: Int, kind: Int) -> Float64:
    var checksum = Float64(0)
    for i in range(count):
        checksum += Float64(pingpong(_input(i, kind), 0.75))
    return checksum


def main() raises:
    var count = 200000
    for trial in range(7):
        for kind in range(3):
            var start = perf_counter_ns()
            var legacy = _legacy(count, kind)
            var legacy_ns = perf_counter_ns() - start
            start = perf_counter_ns()
            var corrected = _corrected(count, kind)
            var corrected_ns = perf_counter_ns() - start
            start = perf_counter_ns()
            var legacy_wave = _legacy_wave(count, kind)
            var legacy_wave_ns = perf_counter_ns() - start
            start = perf_counter_ns()
            var wave = _wave(count, kind)
            var wave_ns = perf_counter_ns() - start
            if kind < 2 and legacy != corrected:
                raise Error("Ordinary checksums differ")
            if kind < 2 and legacy_wave != wave:
                raise Error("Ordinary wave checksums differ")
            print(
                trial,
                kind,
                count,
                legacy_ns,
                corrected_ns,
                legacy_wave_ns,
                wave_ns,
                legacy,
                corrected,
                legacy_wave,
                wave,
            )
