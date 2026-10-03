# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Generate Float32 phase neighbors without importing production arithmetic.

Use Decimal Machin-series pi and a Taylor sine, at two precisions. All input
values are decoded exactly from bits. Integer binary search brackets each
irrational target, so no host-float pi, multiplication, or nextafter can move
the target before neighbors are selected. Round references directly to binary32
with ties-to-even, without a binary64 intermediate.

Run `python3 tools/reference_sine_phases.py --check` to verify the fixture, or
use `--write` to replace its marked block in tests/test_sine.mojo.
"""

import argparse
from decimal import Decimal, ROUND_FLOOR, localcontext
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "tests/test_sine.mojo"
BEGIN = "# BEGIN GENERATED LARGE-ANGLE PHASE FIXTURE\n"
END = "# END GENERATED LARGE-ANGLE PHASE FIXTURE\n"
EXPONENTS = (13, 17, 21, 23, 31, 47, 63, 95, 126)


def exact_float32(bits):
    """Decode a finite binary32 bit pattern as an exact Decimal."""
    exponent, fraction = (bits >> 23) & 255, bits & 0x7FFFFF
    assert exponent != 255
    significand = fraction | (0x800000 if exponent else 0)
    power = exponent - 150 if exponent else -149
    # 200 digits suffice to represent even the smallest subnormal exactly.
    with localcontext() as context:
        context.prec = 200
        value = Decimal(significand) * (Decimal(2) ** power)
    return value.copy_negate() if bits & 0x80000000 else value


def machin_pi(precision):
    """Compute pi = 16 atan(1/5) - 4 atan(1/239) by convergent series."""
    threshold = Decimal(10) ** (-precision - 8)

    def atan_inverse(divisor):
        x = Decimal(1) / divisor
        power, total, index = x, x, 1
        while True:
            power *= -x * x
            term = power / (2 * index + 1)
            total += term
            if abs(term) < threshold:
                return total
            index += 1

    return 16 * atan_inverse(5) - 4 * atan_inverse(239)


def lower_bits(target):
    """Find the largest positive finite binary32 no greater than target."""
    low, high = 0, 0x7F7FFFFF
    assert 0 <= target <= exact_float32(high)
    while low < high:
        middle = (low + high + 1) // 2
        if exact_float32(middle) <= target:
            low = middle
        else:
            high = middle - 1
    return low


def rounded_bits(value):
    """Round a finite reference directly to binary32, nearest ties-to-even."""
    sign = 0x80000000 if value < 0 else 0
    value = abs(value)
    lower = lower_bits(value)
    down, up = exact_float32(lower), exact_float32(lower + 1)
    if value - down > up - value or (
        value - down == up - value and lower & 1
    ):
        lower += 1
    return sign | lower


def reference_sine(value, pi, precision):
    """Use full-turn reduction and a Taylor series, not the candidate path."""
    period = 2 * pi
    turns = ((value + pi) / period).to_integral_value(rounding=ROUND_FLOOR)
    x = value - turns * period
    term = total = x
    index = 1
    threshold = Decimal(10) ** (-precision)
    while True:
        term *= -x * x / ((2 * index) * (2 * index + 1))
        total += term
        if abs(term) < threshold:
            return total
        index += 1


def generate(precision):
    """Return metadata and four contiguous neighbors per selected target."""
    groups = []
    with localcontext() as context:
        context.prec = precision + 16
        pi = machin_pi(precision)
        half_pi = pi / 2
        for exponent in EXPONENTS:
            # Spread targets at coarse exponents while retaining all four
            # integer quadrants. The stride is a multiple of four.
            stride = 1 << max(2, exponent - 20)
            for quadrant in range(4):
                multiple = (1 << exponent) + quadrant * (stride + 1)
                for midpoint in (False, True):
                    phase = Decimal(multiple) + (Decimal("0.5") if midpoint else 0)
                    target = phase * half_pi
                    lower = lower_bits(target)
                    assert exact_float32(lower) < target < exact_float32(lower + 1)
                    rows = []
                    for bits in range(lower - 1, lower + 3):
                        value = exact_float32(bits)
                        nearest = int((value / half_pi + Decimal("0.5"))
                                      .to_integral_value(rounding=ROUND_FLOOR))
                        remainder = value - nearest * half_pi
                        sine = reference_sine(value, pi, precision)
                        rows.append((bits, nearest % 4, rounded_bits(remainder),
                                     rounded_bits(sine), nearest))
                    # When one ULP is at most one radian, these adjacent
                    # neighbors isolate exactly the selected increment.
                    if midpoint and exponent <= 23:
                        assert rows[1][4] == multiple
                        assert rows[2][4] == multiple + 1
                    groups.append((exponent, multiple, midpoint, rows))
    return groups


def render(groups):
    lines = [BEGIN.rstrip(),
             "# Generated by tools/reference_sine_phases.py; do not edit by hand.",
             "# Inputs, reference remainders, and reference sines use exact bits.",
             "def large_angle_phase_cases() -> List[Tuple[Int, Int, Int, Int]]:",
             '    """Return independent positive-angle phase fixtures.',
             "",
             "    Returns:",
             "        Angle bits, nearest quadrant, remainder bits, and sine bits.",
             '    """',
             "    return ["]
    for exponent, multiple, midpoint, rows in groups:
        label = f"({multiple} + 1/2)" if midpoint else str(multiple)
        lines.append(f"        # 2^{exponent} band: {label} * pi/2; below, below, above, above.")
        for bits, quadrant, remainder, sine, _ in rows:
            lines.append(f"        (0x{bits:08X}, {quadrant}, 0x{remainder:08X}, 0x{sine:08X}),")
    lines.extend(["    ]", "", "", END.rstrip()])
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    groups = generate(140)
    assert groups == generate(200), "phase oracle changed at higher precision"
    generated = render(groups)
    original = FIXTURE.read_text()
    start = original.index(BEGIN)
    end = original.index(END, start) + len(END)
    updated = original[:start] + generated + original[end:]
    if args.write:
        FIXTURE.write_text(updated)
    elif original != updated:
        raise SystemExit("phase fixture is stale; run with --write")
    print(f"Verified {len(groups)} targets, {sum(len(g[3]) for g in groups)} "
          "positive neighbors, both signs tested in Mojo; 140/200-digit agreement")


if __name__ == "__main__":
    main()
