# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Generate exact rational controls for the periodic scalar helpers.

Decode input bits to Fraction. Use rational floor division and subtraction,
then round directly to the target format with ties to even. No production
code, host fmod, floating-point quotient, or floating-point remainder is used.
Run with --check to verify saved fixtures or --write to replace them.
"""

import argparse
from fractions import Fraction
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parent.parent


def exact(bits, fraction_bits, exponent_bits):
    """Decode a finite positive binary float without a host float."""
    exponent = bits >> fraction_bits
    significand = bits & ((1 << fraction_bits) - 1)
    bias = (1 << (exponent_bits - 1)) - 1
    assert exponent < (1 << exponent_bits) - 1
    if exponent:
        significand |= 1 << fraction_bits
    power = max(exponent, 1) - bias - fraction_bits
    return Fraction(significand) * Fraction(2) ** power


def rounded(value, fraction_bits, exponent_bits):
    """Round a dyadic rational to binary bits, with ties to even."""
    sign = (1 << (fraction_bits + exponent_bits)) if value < 0 else 0
    value = abs(value)
    if not value:
        return sign
    bias = (1 << (exponent_bits - 1)) - 1
    exponent = value.numerator.bit_length() - value.denominator.bit_length()
    if value < Fraction(2) ** exponent:
        exponent -= 1
    quantum = max(exponent - fraction_bits, 1 - bias - fraction_bits)
    scaled = value / Fraction(2) ** quantum
    significand, residual = divmod(scaled.numerator, scaled.denominator)
    twice = 2 * residual
    if twice > scaled.denominator or (
        twice == scaled.denominator and significand & 1
    ):
        significand += 1
    if significand >= 1 << (fraction_bits + 1):
        significand >>= 1
        quantum += 1
    exponent_field = quantum + fraction_bits + bias
    if exponent_field >= (1 << exponent_bits) - 1:
        return sign | (((1 << exponent_bits) - 1) << fraction_bits)
    if significand < 1 << fraction_bits:
        return sign | significand
    return sign | (exponent_field << fraction_bits) | (
        significand - (1 << fraction_bits)
    )


def pairs(fraction_bits, exponent_bits):
    """Cover every exponent, mantissa edges, neighbors, and random pairs."""
    limit = ((1 << exponent_bits) - 1) << fraction_bits
    bias = (1 << (exponent_bits - 1)) - 1
    mantissas = (0, 1, (1 << fraction_bits) // 3, (1 << fraction_bits) - 1)
    one_and_half = (bias << fraction_bits) | (1 << (fraction_bits - 1))
    result = set()
    for exponent in range((1 << exponent_bits) - 1):
        n = (exponent << fraction_bits) | mantissas[exponent % 4]
        m_exponent = (exponent * 73 + 19) % ((1 << exponent_bits) - 1)
        m = (m_exponent << fraction_bits) | mantissas[(exponent + 1) % 4]
        result.add((n, max(1, m)))
        result.add((n, one_and_half))
        # Exact multiples and their adjacent representable inputs.
        m = max(1, (exponent << fraction_bits) | (1 << (fraction_bits - 1)))
        for n in (m - 1, m, m + 1):
            if n < limit:
                result.add((n, m))
    edges = (
        0, 1, 2, 3, (1 << fraction_bits) - 1, 1 << fraction_bits,
        (1 << fraction_bits) + 1, bias << fraction_bits, one_and_half,
        ((bias + 1) << fraction_bits), limit - 2, limit - 1,
    )
    result.update((n, m) for n in edges for m in edges if m)
    generator = random.Random(603 + fraction_bits)
    result.update((generator.randrange(limit), generator.randrange(1, limit))
                  for _ in range(512))
    return sorted(result)


def fixtures32():
    """Return bit-exact modulo and folded-wave controls for both signs."""
    lines = []
    for n_bits, m_bits in pairs(23, 8):
        n, m = exact(n_bits, 23, 8), exact(m_bits, 23, 8)
        residual = n - (n // m) * m
        same = rounded(residual, 23, 8)
        opposite = rounded(m - residual, 23, 8) if residual else 0
        if opposite >= m_bits:
            opposite = m_bits - 1
        period = 2 * m
        phase = n - (n // period) * period
        wave = min(phase, period - phase)
        values = (n_bits, m_bits, same, opposite,
                  rounded(wave, 23, 8), rounded(wave - period, 23, 8))
        lines.append(' '.join(map(str, values)))
    return '\n'.join(lines) + '\n'


def fixtures64():
    """Return exact binary64 truncating remainder controls."""
    lines = []
    for n_bits, m_bits in pairs(52, 11):
        n, m = exact(n_bits, 52, 11), exact(m_bits, 52, 11)
        residual = n - (n // m) * m
        bits = rounded(residual, 52, 11)
        assert exact(bits, 52, 11) == residual
        lines.append(f'{n_bits} {m_bits} {bits}')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--write', action='store_true')
    args = parser.parse_args()
    for name, contents in [('periodic32.txt', fixtures32()),
                           ('remainder64.txt', fixtures64())]:
        path = ROOT / 'assets/math_remainder' / name
        if args.write:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)
        elif path.read_text() != contents:
            raise SystemExit(f'Fixture differs: {path.relative_to(ROOT)}')
        print(f'{name}: {len(contents.splitlines())} exact rational cases')


if __name__ == '__main__':
    main()
