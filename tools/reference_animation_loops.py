#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact Fraction controls for stored-Float32 animation clock operations.

Decode and round every operand without host floating-point arithmetic. Keep
three.js r180 boundary, initial reverse and finite-finish conventions. This
reference does not import production code or duplicate integer division code.
"""
import argparse
from fractions import Fraction
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parent.parent
MAX = (1 << 63) - 1
INF = 0x7f800000
SIGN = 0x80000000


def exact(bits):
    sign = -1 if bits & SIGN else 1
    bits &= SIGN - 1
    exponent, significand = bits >> 23, bits & 0x7fffff
    assert exponent < 255
    if exponent:
        significand |= 1 << 23
    return sign * Fraction(significand) * Fraction(2) ** (max(exponent, 1) - 150)


def rounded(value):
    sign = SIGN if value < 0 else 0
    value = abs(value)
    if not value:
        return sign
    exponent = value.numerator.bit_length() - value.denominator.bit_length()
    if value < Fraction(2) ** exponent:
        exponent -= 1
    quantum = max(exponent - 23, -149)
    scaled = value / Fraction(2) ** quantum
    significand, residual = divmod(scaled.numerator, scaled.denominator)
    if 2 * residual > scaled.denominator or (
            2 * residual == scaled.denominator and significand & 1):
        significand += 1
    if significand >= 1 << 24:
        significand >>= 1
        quantum += 1
    field = quantum + 150
    if field >= 255:
        return sign | INF
    if significand < 1 << 23:
        return sign | significand
    return sign | field << 23 | (significand - (1 << 23))


def outcome(case):
    length_bits, phase_bits, seconds_bits, scale_bits, mode, repetitions, started, count = case
    length, phase = exact(length_bits), exact(phase_bits)
    # On failure no timing/event field is changed. Tests seed prior events.
    original = (1, phase_bits, 17, count, started, 1, 1, 0)
    step_bits = rounded(exact(seconds_bits) * exact(scale_bits))
    if step_bits & ~SIGN == INF:
        return original
    step = exact(step_bits)
    if not step:
        return (0, phase_bits, 0, count, started, 0, 1, 0)
    moved_bits = rounded(phase + step)
    if moved_bits & ~SIGN == INF:
        return original
    moved = exact(moved_bits)
    direction = -1 if step < 0 else 1
    if mode == 0:
        finished = moved >= length or moved < 0
        endpoint = max(Fraction(0), min(length, moved))
        return (0, rounded(endpoint), 0, count if started else 0, 1,
                int(finished), direction if finished else 1, int(finished))
    before = phase // length
    if abs(before) > MAX:
        return original
    after = moved // length
    delta = after - before
    running_count = 0 if not started and step > 0 else count
    if delta and repetitions >= 0:
        pending = max(repetitions - running_count, 0)
        if pending <= abs(delta):
            if mode == 1:
                end = length if step > 0 else Fraction(0)
            else:
                stop = before + max(pending, 1) if step > 0 else before - max(pending, 1) + 1
                # The initial reverse boundary wraps before complete legs.
                # Zero repetitions finish there without that initial wrap.
                if not started and step < 0 and pending > 1:
                    stop += 1
                end = length if stop % 2 else Fraction(0)
            return (0, rounded(end), 0, count, started, 1, direction, 1)
    if abs(delta) > MAX or running_count + abs(delta) > MAX:
        return original
    remainder = moved - after * length
    leg = mode == 2 and bool(after % 2)
    if mode == 2 and not started and step < 0 and delta:
        leg = not leg
    reduced = remainder + (length if leg else 0)
    stored = rounded(reduced)
    if stored == INF:
        return original
    upper = length * (2 if leg else 1)
    if exact(stored) >= upper:
        stored -= 1
    return (0, stored, delta, running_count + abs(delta) if delta else count,
            int(started or bool(delta)), 0, direction, 0)


def cases():
    result = set()
    lengths = [1, 3, 0x007fffff, 0x00800000, 0x3eaaaaab, 0x3f800000,
               0x3fc00000, 0x40000000, 0x7effffff, 0x7f000000, 0x7f7fffff]
    steps = [0, 1, 0x3f800000, 0x4bfffffe, 0x4bffffff, 0x4c000000,
             0x4c000001, 0x5e800000, 0x5effffff, 0x5f000000,
             0x5f000001, 0x71800000, 0x7f7fffff]
    for length in lengths:
        for step in set(steps + [length - 1, length, min(length + 1, INF - 1)]):
            for mode in range(3):
                for sign in (0, SIGN):
                    result.add((length, 0, step | sign, 0x3f800000, mode, -1, 0, -1))
    # Every exponent, ordinary rounding near boundaries, and finite ends.
    for exponent in range(255):
        length = max(1, exponent << 23 | 0x400000)
        for offset in (-1, 0, 1):
            step = max(0, min(INF - 1, length + offset))
            result.add((length, length - 1, step, 0x3e800000, 1, -1, 1, 1))
            result.add((length, length, step | SIGN, 0x3f800000, 2, 3, 1, 1))
    for mode in (1, 2):
        for step in (0x3f800000, 0x5effffff, 0x5f000000, 0x71800000, 0x7f7fffff):
            for sign in (0, SIGN):
                for reps in (0, 1, 2, 3, MAX):
                    for started, count in ((0, -1), (1, 1), (1, MAX)):
                        result.add((0x3f800000, 0, step | sign, 0x3f800000, mode, reps, started, count))
    generator = random.Random(610)
    for _ in range(700):
        length = generator.randrange(1, INF)
        phase = generator.choice((0, length - 1, length, generator.randrange(INF)))
        step = generator.randrange(INF) | generator.choice((0, SIGN))
        scale = generator.choice((0, 1, 0x3eaaaaab, 0x3f000000, 0x3f800000,
                                  0x3fc00000, 0x40000000, INF - 1))
        started = generator.randrange(2)
        result.add((length, phase, step, scale, generator.randrange(3),
                    generator.choice((-1, 0, 1, 2, MAX)), started, 1 if started else -1))
    # Stored Float32 add and multiply must not silently become wider operations.
    result.add((0x3fc00000, 0x3f000000, 0x4c000000, 0x3f800000, 1, -1, 0, -1))
    result.add((0x3f800000, 0x3f7fffff, 0x33800000, 0x3f800000, 1, -1, 0, -1))
    result.add((0x3f800000, SIGN, SIGN, 0x3f800000, 1, -1, 0, -1))
    # All independent same-leg guard outcomes, including externally set phase.
    result.update((0x3f800000, phase, step, 0x3f800000, mode, -1, 1, 1)
                  for phase, step, mode in (
                      (0xbe800000, 0x3f000000, 1),
                      (0x40000000, 0xbf000000, 2),
                      (0x3fc00000, 0x3f000000, 2),
                      (0x3f800000, 0x3e800000, 1),
                      (0x3f800000, 0xbe800000, 2),
                  ))
    for mode in (1, 2):
        for count, step in ((MAX, 0x3f800000), (MAX - 1, 0x3f800000), (MAX, 0x3f000000)):
            result.add((0x3f800000, 0, step, 0x3f800000, mode, -1, 1, count))
        for repetitions in (-1, 1):
            result.add((0x3f800000, 0x40200000, 0xbe800000, 0x3f800000,
                        mode, repetitions, 0, -1))
    for repetitions in (-1, 1):
        result.add((0x7f7fffff, 0, 0xbf800000, 0x3f800000, 2, repetitions, 1, 0))
    for mode in range(3):
        result.add((0x7f7fffff, 0x7f7fffff, 0x7f7fffff, 0x3f800000, mode, -1, 1, 1))
    return sorted(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    rows = cases()
    text = ''.join(' '.join(map(str, case + outcome(case))) + '\n' for case in rows)
    path = ROOT / 'assets/animation/loop_reference.txt'
    if args.write:
        path.write_text(text)
    elif args.check:
        assert path.read_text() == text, f'{path} is stale'
    else:
        print(text, end='')
    if args.check or args.write:
        print(f'{len(rows)} exact animation controls verified')


if __name__ == '__main__':
    main()
