# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Generate Float32 phase neighbors without importing production arithmetic.

    mojo run -I . tools/reference_sine_phases.mojo (--check | --write)

Use Machin-series pi and a Taylor sine in binary fixed point, at two
precisions: 140 and 200 decimal digits. All input values are decoded exactly
from bits. Integer binary search brackets each irrational target, so no
host-float pi, multiplication, or nextafter can move the target before
neighbors are selected. Round references directly to binary32 with
ties-to-even, without a binary64 intermediate.

`--check` verifies the fixture block in `tests/test_sine.mojo`. `--write`
replaces it.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt

comptime FIXTURE = "tests/test_sine.mojo"
"""The test file that holds the generated block."""
comptime BEGIN = "# BEGIN GENERATED LARGE-ANGLE PHASE FIXTURE\n"
"""The block's first line."""
comptime END = "# END GENERATED LARGE-ANGLE PHASE FIXTURE\n"
"""The block's last line."""
comptime EXPONENTS = [13, 17, 21, 23, 31, 47, 63, 95, 126]
"""The binary exponent bands of the targets."""
comptime SIGN = 0x80000000
"""The binary32 sign bit."""
comptime LARGEST = 0x7F7FFFFF
"""The bits of the largest finite binary32."""


@fieldwise_init
struct Fixed(Copyable, Movable):
    """A binary fixed-point scale: a value v is the integer v * 2**bits."""

    var bits: Int
    """The fraction bits."""
    var digits: Int
    """The decimal precision that the fraction bits hold."""

    @staticmethod
    def of(digits: Int) -> Fixed:
        """Return a scale for a decimal precision, with 16 guard digits.

        Args:
            digits: The decimal digits.

        Returns:
            The scale. It always holds every binary32 exactly.
        """
        return Fixed(max((digits + 16) * 3322 // 1000 + 1, 160), digits)

    def one(self) -> BigInt:
        """Return 1.

        Returns:
            The fixed-point one.
        """
        return BigInt(1) << self.bits

    def times(self, a: BigInt, b: BigInt) -> BigInt:
        """Return a * b, rounded down.

        Args:
            a: The first factor.
            b: The second factor.

        Returns:
            The product.
        """
        return (a * b) >> self.bits

    def exact_float32(self, bits: Int) raises -> BigInt:
        """Decode a finite binary32 bit pattern exactly.

        Args:
            bits: The bits.

        Returns:
            The value.

        Raises:
            Error: If the bits encode an infinity or a NaN.
        """
        var exponent = (bits >> 23) & 255
        if exponent == 255:
            raise Error("not a finite binary32")
        var significand = (bits & 0x7FFFFF) | (0x800000 if exponent else 0)
        var power = exponent - 150 if exponent else -149
        var value = BigInt(significand) << (power + self.bits)
        return -value if bits & SIGN else value^

    def pi(self) raises -> BigInt:
        """Compute pi = 16 atan(1/5) - 4 atan(1/239) by convergent series.

        Returns:
            Pi.

        Raises:
            Error: Never; the divisors are not zero.
        """
        return BigInt(16) * self._atan_inverse(5) - BigInt(
            4
        ) * self._atan_inverse(239)

    def _atan_inverse(self, divisor: Int) raises -> BigInt:
        """Return atan(1 / divisor)."""
        var x = self.one() // BigInt(divisor)
        var square = self.times(x, x)
        var power = x.copy()
        var total = x.copy()
        var index = 1
        while not power.is_zero():
            power = -self.times(power, square)
            total = total + power // BigInt(2 * index + 1)
            index += 1
        return total^

    def lower_bits(self, target: BigInt) raises -> Int:
        """Find the largest positive finite binary32 no greater than target.

        Args:
            target: A value from zero to the largest binary32.

        Returns:
            The bits.

        Raises:
            Error: If the target is out of range.
        """
        if target.negative or target > self.exact_float32(LARGEST):
            raise Error("target out of the binary32 range")
        var low = 0
        var high = LARGEST
        while low < high:
            var middle = (low + high + 1) // 2
            if self.exact_float32(middle) <= target:
                low = middle
            else:
                high = middle - 1
        return low

    def rounded_bits(self, value: BigInt) raises -> Int:
        """Round a finite reference directly to binary32, ties to even.

        Args:
            value: The value.

        Returns:
            The bits of the nearest binary32.

        Raises:
            Error: If the value is out of range.
        """
        var sign = SIGN if value.negative else 0
        var magnitude = abs(value)
        var lower = self.lower_bits(magnitude)
        var below = magnitude - self.exact_float32(lower)
        var above = self.exact_float32(lower + 1) - magnitude
        if below > above or (below == above and lower & 1):
            lower += 1
        return sign | lower

    def sine(self, value: BigInt, pi: BigInt) raises -> BigInt:
        """Use full-turn reduction and a Taylor series, not the candidate
        path.

        Args:
            value: The angle.
            pi: Pi.

        Returns:
            The sine.

        Raises:
            Error: Never; the divisors are not zero.
        """
        var period = pi * BigInt(2)
        var turns = (value + pi) // period
        var x = value - turns * period
        var square = self.times(x, x)
        var term = x.copy()
        var total = x.copy()
        var threshold = self.one() // BigInt(10) ** self.digits
        var index = 1
        while True:
            term = -(
                self.times(term, square)
                // BigInt((2 * index) * (2 * index + 1))
            )
            total = total + term
            if abs(term) < threshold:
                return total^
            index += 1


@fieldwise_init
struct Row(Copyable, Movable):
    """One positive neighbor of a target."""

    var bits: Int
    """The angle's bits."""
    var quadrant: Int
    """The nearest quadrant, modulo four."""
    var remainder: Int
    """The bits of the angle less the nearest multiple of pi/2."""
    var sine: Int
    """The bits of the sine."""
    var nearest: BigInt
    """The nearest multiple of pi/2."""


@fieldwise_init
struct Group(Copyable, Movable):
    """Four contiguous neighbors of one target."""

    var exponent: Int
    """The binary exponent band."""
    var multiple: BigInt
    """The target's multiple of pi/2, less any half."""
    var midpoint: Bool
    """True when the target is the multiple plus one half."""
    var rows: List[Row]
    """Two neighbors below the target and two above it."""


def generate(precision: Int) raises -> List[Group]:
    """Return four contiguous neighbors per selected target.

    Args:
        precision: The decimal digits of the calculation.

    Returns:
        The groups.

    Raises:
        Error: If a neighbor does not bracket its target.
    """
    var scale = Fixed.of(precision)
    var pi = scale.pi()
    var half_pi = pi >> 1
    var groups = List[Group]()
    comptime exponents = EXPONENTS
    for exponent in materialize[exponents]():
        # Spread targets at coarse exponents while retaining all four
        # integer quadrants. The stride is a multiple of four.
        var stride = BigInt(1) << max(2, exponent - 20)
        for quadrant in range(4):
            var multiple = (BigInt(1) << exponent) + BigInt(quadrant) * (
                stride + BigInt(1)
            )
            for midpoint in [False, True]:
                var target = multiple * half_pi
                if midpoint:
                    target = target + (half_pi >> 1)
                var lower = scale.lower_bits(target)
                if not (
                    scale.exact_float32(lower) < target
                    and target < scale.exact_float32(lower + 1)
                ):
                    raise Error("a target is a binary32 value")
                var rows = List[Row]()
                for bits in range(lower - 1, lower + 3):
                    var value = scale.exact_float32(bits)
                    var nearest = (value + (half_pi >> 1)) // half_pi
                    var remainder = value - nearest * half_pi
                    rows.append(
                        Row(
                            bits,
                            (nearest % BigInt(4)).to_int(),
                            scale.rounded_bits(remainder),
                            scale.rounded_bits(scale.sine(value, pi)),
                            nearest.copy(),
                        )
                    )
                # When one ULP is at most one radian, these adjacent
                # neighbors isolate exactly the selected increment.
                if midpoint and exponent <= 23:
                    if rows[1].nearest != multiple or rows[
                        2
                    ].nearest != multiple + BigInt(1):
                        raise Error("neighbors miss the selected increment")
                groups.append(Group(exponent, multiple.copy(), midpoint, rows^))
    return groups^


def _hex(value: Int) -> String:
    """Return eight uppercase hexadecimal digits."""
    comptime digits = "0123456789ABCDEF"
    var out = String()
    for shift in range(28, -1, -4):
        out += chr(Int(digits.as_bytes()[(value >> shift) & 15]))
    return out^


def render(groups: List[Group]) -> String:
    """Return the generated block.

    Args:
        groups: The groups.

    Returns:
        The block, from its BEGIN line to its END line.
    """
    var lines: List[String] = [
        String(String(BEGIN).rstrip()),
        "# Generated by tools/reference_sine_phases.mojo; do not edit by hand.",
        "# Inputs, reference remainders, and reference sines use exact bits.",
        "def large_angle_phase_cases() -> List[Tuple[Int, Int, Int, Int]]:",
        '    """Return independent positive-angle phase fixtures.',
        "",
        "    Returns:",
        "        Angle bits, nearest quadrant, remainder bits, and sine bits.",
        '    """',
        "    return [",
    ]
    for group in groups:
        var label = (
            "(" + group.multiple.to_string() + " + 1/2)"
        ) if group.midpoint else group.multiple.to_string()
        lines.append(
            "        # 2^"
            + String(group.exponent)
            + " band: "
            + label
            + " * pi/2; below, below, above, above."
        )
        for row in group.rows:
            lines.append(
                "        (0x"
                + _hex(row.bits)
                + ", "
                + String(row.quadrant)
                + ", 0x"
                + _hex(row.remainder)
                + ", 0x"
                + _hex(row.sine)
                + "),"
            )
    lines.append("    ]")
    lines.append("")
    lines.append("")
    lines.append(String(String(END).rstrip()))
    return "\n".join(lines) + "\n"


def _nearest_text(groups: List[Group]) -> String:
    """Return every row's nearest multiple, which `render` leaves out."""
    var out = String()
    for group in groups:
        for row in group.rows:
            out += row.nearest.to_string() + " "
    return out^


def run(root: String, write: Bool) raises -> Tuple[Int, String]:
    """Check or replace the generated block.

    Args:
        root: The repository root.
        write: True to replace the block.

    Returns:
        The exit status and the report.

    Raises:
        Error: If the two precisions disagree or the block is missing.
    """
    var groups = generate(140)
    var higher = generate(200)
    var generated = render(groups)
    if generated != render(higher) or _nearest_text(groups) != _nearest_text(
        higher
    ):
        raise Error("phase oracle changed at higher precision")
    var path = Path(root + "/" + FIXTURE)
    var original = path.read_text()
    var start = original.find(BEGIN)
    var stop = original.find(END, start)
    if start < 0 or stop < 0:
        raise Error("the generated block is missing from " + FIXTURE)
    stop += String(END).byte_length()
    var updated = (
        String(original[byte=:start]) + generated + String(original[byte=stop:])
    )
    if write:
        path.write_text(updated)
    elif original != updated:
        return (1, "phase fixture is stale; run with --write\n")
    var rows = 0
    for group in groups:
        rows += len(group.rows)
    return (
        0,
        "Verified "
        + String(len(groups))
        + " targets, "
        + String(rows)
        + " positive neighbors, both signs tested in Mojo; 140/200-digit"
        " agreement\n",
    )


def main() raises:
    var given = argv()
    if len(given) != 2 or not (
        String(given[1]) == "--check" or String(given[1]) == "--write"
    ):
        print("usage: reference_sine_phases (--check | --write)", file=stderr)
        exit(2)
    var outcome = run(".", String(given[1]) == "--write")
    if outcome[0] != 0:
        print(outcome[1], end="", file=stderr)
    else:
        print(outcome[1], end="")
    exit(outcome[0])
