# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Python numbers for ported report tools: `int` or `float`, `/`, `median`.

A Python report keeps an integer an `int` until an operation makes it a
`float`. JSON then writes `7` or `7.0`. `PyNumber` keeps that difference.

- `true_divide` is `int / int`: the double nearest to the exact quotient.
- `median` is CPython's `statistics.median`: the middle item, or the mean
  of the two middle items, `(a + b) / 2`.
- `format_fixed` is `format(value, ".Nf")`, rounded from the exact value
  of the double with ties to even.
"""

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._json_value import JsonTree

comptime _EXACT = 9007199254740992
"""2**53: every integer up to this size is a double."""


@fieldwise_init
struct PyNumber(Copyable, Movable):
    """A Python `int` or `float`."""

    var is_int: Bool
    """True for an `int`."""
    var integer: Int
    """The value of an `int`."""
    var real: Float64
    """The value of a `float`."""

    @staticmethod
    def of_int(value: Int) -> PyNumber:
        """Return an `int`.

        Args:
            value: The value.

        Returns:
            The number.
        """
        return PyNumber(True, value, 0.0)

    @staticmethod
    def of_float(value: Float64) -> PyNumber:
        """Return a `float`.

        Args:
            value: The value.

        Returns:
            The number.
        """
        return PyNumber(False, 0, value)

    def as_float(self) -> Float64:
        """Return the value as `float(value)` does.

        Returns:
            The double. An `int` past 2**53 rounds to the nearest double.
        """
        if not self.is_int:
            return self.real
        return BigInt(self.integer).to_float()

    def less(self, other: PyNumber) -> Bool:
        """Return whether this number is below another.

        Args:
            other: The other number.

        Returns:
            True when this value is smaller.
        """
        if self.is_int and other.is_int:
            return self.integer < other.integer
        return self.as_float() < other.as_float()

    def add_to_json(self, mut tree: JsonTree) raises -> Int:
        """Add this number to a JSON tree, as `json.dumps` writes it.

        Args:
            tree: The tree.

        Returns:
            The node.

        Raises:
            Error: If a float has no shortest text.
        """
        if self.is_int:
            return tree.integer(self.integer)
        return tree.number(self.real)

    def python_text(self) raises -> String:
        """Return `str(value)`.

        Returns:
            The digits of an `int`, or the `repr` of a `float`.

        Raises:
            Error: If a float has no shortest text.
        """
        var tree = JsonTree()
        return tree.text(self.add_to_json(tree))


def true_divide(numerator: Int, denominator: Int) raises -> Float64:
    """Return `numerator / denominator` for two Python `int` values.

    Args:
        numerator: The dividend.
        denominator: The divisor, not zero.

    Returns:
        The double nearest to the exact quotient, with ties to even.

    Raises:
        Error: `division by zero` when the divisor is zero.
    """
    if denominator == 0:
        raise Error("division by zero")
    if (
        numerator <= _EXACT
        and numerator >= -_EXACT
        and denominator <= _EXACT
        and denominator >= -_EXACT
    ):
        return Float64(numerator) / Float64(denominator)
    return Fraction.of(BigInt(numerator), BigInt(denominator)).to_float()


def _sorted(values: List[PyNumber]) -> List[PyNumber]:
    """Return the numbers in ascending order, stably."""
    var result = values.copy()
    for i in range(1, len(result)):
        var j = i
        while j > 0 and result[j].less(result[j - 1]):
            result.swap_elements(j, j - 1)
            j -= 1
    return result^


def median(values: List[PyNumber]) raises -> PyNumber:
    """Return `statistics.median(values)`.

    Args:
        values: The data.

    Returns:
        The middle value, or `(a + b) / 2` of the two middle values.

    Raises:
        Error: `no median for empty data` when there are no values.
    """
    if len(values) == 0:
        raise Error("no median for empty data")
    var data = _sorted(values)
    var n = len(data)
    if n % 2 == 1:
        return data[n // 2].copy()
    var a = data[n // 2 - 1].copy()
    var b = data[n // 2].copy()
    if a.is_int and b.is_int:
        return PyNumber.of_float(true_divide(a.integer + b.integer, 2))
    return PyNumber.of_float((a.as_float() + b.as_float()) / 2.0)


def _absolute_difference(value: PyNumber, middle: PyNumber) -> PyNumber:
    """Return `abs(value - middle)`."""
    if value.is_int and middle.is_int:
        return PyNumber.of_int(abs(value.integer - middle.integer))
    return PyNumber.of_float(abs(value.as_float() - middle.as_float()))


def distribution(mut tree: JsonTree, values: List[PyNumber]) raises -> Int:
    """Add the summary `{n, median, min, max, mad}` of the Python reports.

    `mad` is the unscaled median absolute deviation from the median.

    Args:
        tree: The tree for the new object.
        values: The data, at least one value.

    Returns:
        The object node.

    Raises:
        Error: If there are no values.
    """
    var middle = median(values)
    var smallest = values[0].copy()
    var largest = values[0].copy()
    var deviations = List[PyNumber]()
    for value in values:
        if value.less(smallest):
            smallest = value.copy()
        if largest.less(value):
            largest = value.copy()
        deviations.append(_absolute_difference(value, middle))
    var result = tree.object()
    tree.set(result, "n", tree.integer(len(values)))
    tree.set(result, "median", middle.add_to_json(tree))
    tree.set(result, "min", smallest.add_to_json(tree))
    tree.set(result, "max", largest.add_to_json(tree))
    tree.set(result, "mad", median(deviations).add_to_json(tree))
    return result


def format_fixed(value: Float64, places: Int) raises -> String:
    """Return `format(value, "." + str(places) + "f")`.

    Args:
        value: A finite double.
        places: The digits after the point, zero or more.

    Returns:
        The text, rounded from the exact value with ties to even.

    Raises:
        Error: If the value is not finite.
    """
    var exact = Fraction.from_float(value)
    var negative = exact.numerator.negative or (value == 0 and 1.0 / value < 0)
    var scaled = abs(exact) * Fraction(BigInt(10) ** places)
    var parts = scaled.numerator.divmod(scaled.denominator)
    var whole = parts[0].copy()
    var twice = parts[1] * BigInt(2)
    if twice > scaled.denominator or (
        twice == scaled.denominator and whole.is_odd()
    ):
        whole = whole + BigInt(1)
    var digits = whole.to_string()
    while digits.byte_length() <= places:
        digits = "0" + digits
    var split = digits.byte_length() - places
    var text = String(digits[byte=:split])
    if places > 0:
        text += "." + String(digits[byte=split:])
    return "-" + text if negative else text
