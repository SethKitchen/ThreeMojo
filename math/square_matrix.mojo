# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Column-major arithmetic shared by `Matrix3` and `Matrix4`.

The index of row `r` and column `c` is `c * n + r`.
"""


@always_inline
def _transpose_square[n: Int](mut elements: Array[Float32, n * n]):
    """Swap the rows and columns of an `n` by `n` matrix.

    Parameters:
        n: The side length. Three or four.

    Args:
        elements: The matrix, changed in place.
    """
    for row in range(n):  # pragma: no branch
        for column in range(row + 1, n):
            var high = elements[column * n + row]
            elements[column * n + row] = elements[row * n + column]
            elements[row * n + column] = high


@always_inline
def _post_multiply[
    n: Int
](mut left: Array[Float32, n * n], right: Array[Float32, n * n]):
    """Replace `left` with `left * right`.

    The right-hand matrix is applied to a point first. `n` is three or
    four, so none of the loops can run zero times.

    Parameters:
        n: The side length.

    Args:
        left: The matrix applied second. It is replaced.
        right: The matrix applied first.
    """
    var result = Array[Float32, n * n](fill=0.0)
    for row in range(n):  # pragma: no branch
        for column in range(n):  # pragma: no branch
            var total = Float32(0)
            for k in range(n):  # pragma: no branch
                total += left[k * n + row] * right[column * n + k]
            result[column * n + row] = total
    left = result^


@always_inline
def _elements_equal[
    n: Int
](left: Array[Float32, n * n], right: Array[Float32, n * n]) -> Bool:
    """Return True when every element matches.

    `n` is three or four, so the loop runs.

    Parameters:
        n: The side length.

    Args:
        left: One matrix.
        right: The other matrix.

    Returns:
        Whether the elements are equal.
    """
    for index in range(n * n):  # pragma: no branch
        if left[index] != right[index]:
            return False
    return True


@always_inline
def _scale_elements[
    n: Int
](mut elements: Array[Float32, n * n], factor: Float32):
    """Multiply every element by one number.

    `n` is three or four, so the loop runs.

    Parameters:
        n: The side length.

    Args:
        elements: The matrix, changed in place.
        factor: The number.
    """
    for index in range(n * n):  # pragma: no branch
        elements[index] *= factor


def append_elements[
    count: Int
](mut out: List[Float32], elements: Array[Float32, count]):
    """Append every stored element, in order.

    `count` is nine or sixteen, so the loop runs.

    Parameters:
        count: How many elements the matrix stores.

    Args:
        out: The list that receives the elements.
        elements: The matrix storage.

    Returns:
        Nothing. The list grows by `count` numbers.

    Raises:
        Error: Never.
    """
    for index in range(count):  # pragma: no branch
        out.append(elements[index])


def copy_elements[count: Int](elements: Array[Float32, count]) -> List[Float32]:
    """Return every stored element, in order.

    Parameters:
        count: How many elements the matrix stores. Nine or sixteen.

    Args:
        elements: The matrix storage.

    Returns:
        `count` numbers.

    Raises:
        Error: Never.
    """
    var values = List[Float32]()
    append_elements(values, elements)
    return values^


def store_elements[
    count: Int
](mut dest: List[Float32], at: Int, elements: Array[Float32, count]):
    """Write every stored element into a list, in order.

    `count` is nine or sixteen, so the loop runs.

    Parameters:
        count: How many elements the matrix stores.

    Args:
        dest: The list. It already holds the slots.
        at: The first slot.
        elements: The matrix storage.

    Returns:
        Nothing. `count` slots are replaced.

    Raises:
        Error: Never.
    """
    for index in range(count):  # pragma: no branch
        dest[at + index] = elements[index]
