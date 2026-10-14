# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare official DCT helpers, not Mojo, on deterministic half coefficients.

    mojo run -I . assets/exr_codecs/check_dct_precision.mojo HELPER_SO OPENEXR_SOURCE OUTPUT_JSON

Requires an x86-64 CPU with AVX, and the pinned OpenEXR 3.1.5 helper build.
This experiment does not set or adjust the Mojo fixture tolerance.

The coefficients are those of `random.Random(615)`, so the report is the
same, byte for byte, as the Python probe's that this tool replaces.
"""

from std.ffi import OwnedDLHandle
from std.math import isfinite
from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tools import JsonWriter
from tools._python_random import PythonRandom

comptime BLOCKS = 20000
"""The random blocks compared."""
comptime SEED = 615
"""The seed of the random coefficients."""
comptime LIMIT = 0.003
"""The scaled final error that counts as a counterexample."""


def half_bits(value: Float64) raises -> Int:
    """Round a double to the nearest half, ties to even, as
    `struct.pack("<e")` does.

    Args:
        value: The value.

    Returns:
        The half's bits.

    Raises:
        Error: If the value is too large for a half.
    """
    var bits = bitcast[DType.uint64](value)
    var sign = Int(bits >> 63) << 15
    var field = Int((bits >> 52) & 0x7FF)
    var fraction = Int(bits & ((UInt64(1) << 52) - 1))
    if field == 0x7FF:
        return sign | (0x7C00 if fraction == 0 else 0x7E00)
    if field == 0 and fraction == 0:
        return sign
    var significand = fraction | (1 << 52) if field else fraction
    var power = (field if field else 1) - 1075
    var length = 0
    while (significand >> length) > 0:
        length += 1
    var exponent = length - 1 + power
    var unit = max(exponent, -14) - 10
    var shift = unit - power
    var q: Int
    if shift <= 0:
        q = significand << -shift
    elif shift >= 62:
        q = 0
    else:
        q = significand >> shift
        var rest = significand & ((1 << shift) - 1)
        var half = 1 << (shift - 1)
        if rest > half or (rest == half and q & 1 == 1):
            q += 1
    if q >= 2048:
        q >>= 1
        unit += 1
    if q < 1024:
        return sign | q
    var stored = unit + 25
    if stored >= 31:
        raise Error("float too large to pack with e format")
    return sign | (stored << 10) | (q - 1024)


def half_value(bits: Int) -> Float64:
    """Return a half's value.

    Args:
        bits: The half's bits.

    Returns:
        The value, exactly.
    """
    return Float64(bitcast[DType.float16](UInt16(bits)))


def ordered(bits: Int) -> Int:
    """Return a half's position in value order.

    Args:
        bits: The half's bits.

    Returns:
        A key that increases with the value.
    """
    return 0x8000 - (bits & 0x7FFF) if bits & 0x8000 else 0x8000 + bits


def lookup(source: String) raises -> List[Int]:
    """Read OpenEXR's `dwaCompressorToLinear` table.

    Args:
        source: The OpenEXR source checkout.

    Returns:
        The table.

    Raises:
        Error: If the table is missing.
    """
    var text = Path(source + "/src/lib/OpenEXR/dwaLookups.h").read_text()
    var start = text.find("dwaCompressorToLinear[] =")
    if start < 0:
        raise Error("dwaCompressorToLinear is missing")
    var stop = text.find("}", start)
    var bytes = text.as_bytes()
    var table = List[Int]()
    var index = start
    while index + 1 < stop:
        if Int(bytes[index]) == ord("0") and Int(bytes[index + 1]) == ord("x"):
            var value = 0
            var digits = 0
            index += 2
            while index < stop:
                var byte = Int(bytes[index])
                if byte >= ord("0") and byte <= ord("9"):
                    value = value * 16 + byte - ord("0")
                elif byte >= ord("a") and byte <= ord("f"):
                    value = value * 16 + byte - ord("a") + 10
                else:
                    break
                digits += 1
                index += 1
            if digits > 0:
                table.append(value)
        else:
            index += 1
    return table^


struct Stats(Copyable, Movable):
    """The largest differences between the scalar and one SIMD helper."""

    var float_scaled: Float64
    """The largest scaled difference before rounding to half."""
    var final_scaled: Float64
    """The largest scaled difference after the lookup table."""
    var changed: Int
    """The coefficients whose half differs."""
    var input_steps: Int
    """The largest half difference, in steps, before the table."""
    var final_steps: Int
    """The largest half difference, in steps, after the table."""
    var over: Int
    """The coefficients with a scaled final error over 0.003."""

    def __init__(out self):
        """Start with no differences."""
        self.float_scaled = 0.0
        self.final_scaled = 0.0
        self.changed = 0
        self.input_steps = 0
        self.final_steps = 0
        self.over = 0


@fieldwise_init
struct Counterexample(Copyable, Movable):
    """The first coefficient whose final error passes the limit."""

    var trial: Int
    """The block."""
    var position: Int
    """The coefficient."""
    var input_bits: List[Int]
    """The block's 64 input halves."""
    var scalar_prehalf: Float64
    """The scalar helper's value."""
    var simd_prehalf: Float64
    """The SIMD helper's value."""
    var scalar_half: Int
    """The scalar value's half."""
    var simd_half: Int
    """The SIMD value's half."""
    var scalar_final: Float64
    """The scalar half after the table."""
    var simd_final: Float64
    """The SIMD half after the table."""
    var error: Float64
    """The scaled final error."""


def _write_stats(mut out: JsonWriter, name: String, stats: Stats):
    """Write one helper's statistics."""
    out.key(name)
    out.begin_object()
    out.key("max_float_scaled")
    out.number(stats.float_scaled)
    out.key("max_final_scaled")
    out.number(stats.final_scaled)
    out.key("changed_input_halves")
    out.integer(stats.changed)
    out.key("max_input_half_steps")
    out.integer(stats.input_steps)
    out.key("max_final_half_steps")
    out.integer(stats.final_steps)
    out.key("over_0003")
    out.integer(stats.over)
    out.end()


def _write_first(
    mut out: JsonWriter, name: String, first: Counterexample, bits: Bool
):
    """Write one helper's first counterexample."""
    out.key(name)
    out.begin_object()
    out.key("trial")
    out.integer(first.trial)
    out.key("position")
    out.integer(first.position)
    if bits:
        out.key("input_half_bits")
        out.begin_array()
        for value in first.input_bits:
            out.integer(value)
        out.end()
    out.key("scalar_prehalf")
    out.number(first.scalar_prehalf)
    out.key("simd_prehalf")
    out.number(first.simd_prehalf)
    out.key("scalar_half")
    out.integer(first.scalar_half)
    out.key("simd_half")
    out.integer(first.simd_half)
    out.key("scalar_final")
    out.number(first.scalar_final)
    out.key("simd_final")
    out.number(first.simd_final)
    out.key("scaled_error")
    out.number(first.error)
    out.end()


def _report(
    stats: List[Stats],
    first: List[Counterexample],
    found: List[Bool],
    full: Bool,
) -> String:
    """Return the report, or the printed summary when `full` is False."""
    var names: List[String] = ["sse2", "avx"]
    var out = JsonWriter()
    out.begin_object()
    out.key("blocks")
    out.integer(BLOCKS)
    if full:
        out.key("seed")
        out.integer(SEED)
        out.key("distribution")
        out.string(
            "64 independent uniform[-2,2] coefficients, each rounded to half"
        )
    out.key("results")
    out.begin_object()
    for index in range(2):
        _write_stats(out, names[index], stats[index])
    out.end()
    out.key("first_counterexamples")
    out.begin_object()
    # Python kept them in the order they were first found.
    var order: List[Int] = [0, 1]
    # Within one block, every SSE2 coefficient comes before any AVX one.
    if found[0] and found[1] and first[1].trial < first[0].trial:
        order = [1, 0]
    for index in order:
        if found[index]:
            _write_first(out, names[index], first[index], full)
    out.end()
    out.end()
    return out.text()


def probe(helper: String, source: String) raises -> Tuple[String, String]:
    """Compare the scalar and SIMD DCT helpers on seeded blocks.

    Args:
        helper: The helper library.
        source: The OpenEXR source checkout.

    Returns:
        The report and the printed summary.

    Raises:
        Error: If the helper or the table cannot be loaded.
    """
    var library = OwnedDLHandle(helper)
    var table = lookup(source)
    var random = PythonRandom(SEED)
    var a = List[Float32](length=64, fill=0)
    var b = List[Float32](length=64, fill=0)
    var c = List[Float32](length=64, fill=0)
    var d = List[Float32](length=64, fill=0)
    var stats: List[Stats] = [Stats(), Stats()]
    var first = List[Counterexample]()
    var found: List[Bool] = [False, False]
    for _ in range(2):
        first.append(
            Counterexample(0, 0, List[Int](), 0.0, 0.0, 0, 0, 0.0, 0.0, 0.0)
        )
    for trial in range(BLOCKS):
        var bits = List[Int]()
        for index in range(64):
            var value = -2.0 + 4.0 * random.random()
            bits.append(half_bits(value))
            a[index] = Float32(half_value(bits[index]))
        library.call["compare_dct", NoneType](
            a.unsafe_ptr().unsafe_bitcast[NoneType](),
            b.unsafe_ptr().unsafe_bitcast[NoneType](),
            c.unsafe_ptr().unsafe_bitcast[NoneType](),
            d.unsafe_ptr().unsafe_bitcast[NoneType](),
        )
        for which in range(2):
            ref out = stats[which]
            for index in range(64):
                var x = Float64(b[index])
                var y = Float64(c[index] if which == 0 else d[index])
                out.float_scaled = max(
                    out.float_scaled, abs(x - y) / max(1.0, abs(y))
                )
                var hx = half_bits(x)
                var hy = half_bits(y)
                if hx == hy:
                    continue
                out.changed += 1
                out.input_steps = max(
                    out.input_steps, abs(ordered(hx) - ordered(hy))
                )
                var tx = table[hx]
                var ty = table[hy]
                var vx = half_value(tx)
                var vy = half_value(ty)
                if not (isfinite(vx) and isfinite(vy)):
                    continue
                var error = abs(vx - vy) / max(1.0, abs(vy))
                out.final_scaled = max(out.final_scaled, error)
                out.final_steps = max(
                    out.final_steps, abs(ordered(tx) - ordered(ty))
                )
                if error > LIMIT:
                    out.over += 1
                    if not found[which]:
                        found[which] = True
                        first[which] = Counterexample(
                            trial,
                            index,
                            bits.copy(),
                            x,
                            y,
                            hx,
                            hy,
                            vx,
                            vy,
                            error,
                        )
    return (
        _report(stats, first, found, True),
        _report(stats, first, found, False),
    )


def main() raises:
    var given = argv()
    if len(given) != 4:
        print(
            "usage: check_dct_precision HELPER_SO OPENEXR_SOURCE OUTPUT_JSON",
            file=stderr,
        )
        exit(2)
    var result = probe(String(given[1]), String(given[2]))
    Path(String(given[3])).write_text(result[0] + "\n")
    print(result[1])
