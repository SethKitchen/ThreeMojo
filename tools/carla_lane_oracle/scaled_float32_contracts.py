# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Two exact Float32-only arithmetic-provider edges, below source admission.

The complete inverses and their projections preserve every predecessor byte.
The scaled-products edge adds a compile-time Float32 branch. The matrix
inverse edge adds an Apple-GPU-only compile-time choice; the host and CUDA
still run the predecessor's exact cofactors.
The independent PR744 leaf owns the four formatter-only witness edges.
This module neither reads a root nor grants a receipt. Owners bind the
executed leaf, proof inputs and the new native witness's actual context.
"""
import hashlib
import json
import sys

_EXECUTED_MODULE_CODE = sys._getframe().f_code

LEAF = 'tools/carla_lane_oracle/scaled_float32_contracts.py'
MATH = 'math/scaled_products.mojo'
INVERSE = 'math/matrix_inverse.mojo'
SOURCE_PATHS = ('math/scaled_products.mojo', 'math/matrix_inverse.mojo')
BEFORE_SHA256 = {'math/scaled_products.mojo': 'b504f18cff7df27bff4fbf92fbed7aa4868518f1b1507ea1331540d7e6f0afbb',
 'math/matrix_inverse.mojo': '34dd50cb00f3efe560ae73b1f0be8d2a399d045e1f9db699ce507b6da6ec09ee'}
AFTER_SHA256 = {'math/scaled_products.mojo': '632438eb32acc53e5d4b10e8aa0ca9049a0fc2c5cd7e3d815039626ff3409c86',
 'math/matrix_inverse.mojo': '2c348411da34ea22b6888f96a22b34d8d416e2209ecd95d36d59cf6c698466b0'}
EDITS = {'math/matrix_inverse.mojo': (('1',
                               '\n'
                               'from std.math import isfinite\n'
                               'from math.matrix_determinant import _determinant_f32\n'
                               '\n',
                               '\n'
                               'from std.math import isfinite\n'
                               'from std.memory import bitcast\n'
                               'from std.sys.info import is_apple_gpu\n'
                               'from math.matrix_determinant import _determinant_f32\n'
                               '\n'),
                              ('2',
                               '    Bool, Array[Float32, size * size]\n'
                               ']:\n'
                               '    """Use exact-sign cofactors for finite inputs; return zeros if '
                               'singular.\n'
                               '\n',
                               '    Bool, Array[Float32, size * size]\n'
                               ']:\n'
                               '    """Invert a matrix whose entries are out of the fast path\'s '
                               'range.\n'
                               '\n'
                               '    The host and CUDA use exact-sign cofactors in Float64. Apple '
                               'GPUs have\n'
                               '    no Float64, so a kernel for one uses '
                               '`_inverse_scaled_float32`.\n'
                               '    """\n'
                               '    comptime chosen = _inverse_scaled_float32[\n'
                               '        size\n'
                               '    ] if is_apple_gpu() else _inverse_exact_cofactors[size]\n'
                               '    return chosen(entries)\n'
                               '\n'
                               '\n'
                               'def _power_of_two(exponent: Int) -> Float32:\n'
                               '    """Return two to a power from -126 through 127, from its '
                               'bits.\n'
                               '\n'
                               '    Every power in that range is a normal Float32. A smaller one '
                               'would be\n'
                               '    subnormal, which an Apple GPU flushes to zero, so callers '
                               'never ask\n'
                               '    for one; see `_times_power_of_two`.\n'
                               '    """\n'
                               '    return bitcast[DType.float32](UInt32(exponent + 127) << 23)\n'
                               '\n'
                               '\n'
                               'def _times_power_of_two(value: Float32, exponent: Int) -> '
                               'Float32:\n'
                               '    """Return `value` times two to any power, in steps of normal '
                               'powers.\n'
                               '\n'
                               '    Each factor is normal and each step moves in the same direction.\n'
                               '    For a normal input and normal result, scaling is exact.\n'
                               '    Subnormal products can round in more than one step or flush to zero;\n'
                               '    overflow yields infinity.\n'
                               '    """\n'
                               '    var result = value\n'
                               '    var left = exponent\n'
                               '    while left > 127:\n'
                               '        result *= _power_of_two(127)\n'
                               '        left -= 127\n'
                               '    while left < -126:\n'
                               '        result *= _power_of_two(-126)\n'
                               '        left += 126\n'
                               '    return result * _power_of_two(left)\n'
                               '\n'
                               '\n'
                               'def _binade(value: Float32) -> Int:\n'
                               '    """Return floor(log2(abs(value))) for a nonzero value, or -126 '
                               'for a\n'
                               '    subnormal one, from the exponent bits."""\n'
                               '    return max(-126, Int((bitcast[DType.uint32](value) >> 23) & '
                               '0xFF) - 127)\n'
                               '\n'
                               '\n'
                               'def _inverse_scaled_float32[\n'
                               '    size: Int\n'
                               '](entries: Array[Float32, size * size]) -> Tuple[\n'
                               '    Bool, Array[Float32, size * size]\n'
                               ']:\n'
                               '    """Invert with Float32 alone; return zeros if elimination '
                               'finds the\n'
                               '    matrix singular.\n'
                               '\n'
                               '    Each column, then each row, gets a power of two near its '
                               'largest entry,\n'
                               "    chosen from the entries' exponents before any entry changes. "
                               'Each entry\n'
                               "    is divided by its row's and its column's power once. The "
                               'division is\n'
                               '    exact unless the scaled entry falls below the normal range, '
                               'which only\n'
                               '    happens to an entry far smaller than both its row and its '
                               'column.\n'
                               '    Gauss-Jordan elimination with partial pivoting inverts the '
                               'scaled\n'
                               '    matrix, and the powers are multiplied back, exactly unless an '
                               'inverse\n'
                               '    entry itself leaves the normal range. A nonfinite entry skips '
                               'the\n'
                               '    scaling and propagates as elimination does.\n'
                               '\n'
                               '    Unlike the exact cofactors, this decides singularity by a zero '
                               'pivot,\n'
                               '    so a matrix within rounding of singular can go either way. '
                               'Apple GPUs\n'
                               '    use it because they have no Float64.\n'
                               '\n'
                               '    Parameters:\n'
                               "        size: The matrix's side, two through four.\n"
                               '\n'
                               '    Args:\n'
                               '        entries: The matrix, column-major.\n'
                               '\n'
                               '    Returns:\n'
                               '        Whether it is invertible, and its inverse or zeros.\n'
                               '    """\n'
                               '    comptime assert 2 <= size <= 4\n'
                               '    var matrix = entries.copy()\n'
                               '    var inverse = Array[Float32, size * size](fill=0)\n'
                               '    var result = Array[Float32, size * size](fill=0)\n'
                               '    var row_shift = Array[Int, size](fill=0)\n'
                               '    var column_shift = Array[Int, size](fill=0)\n'
                               '    var finite = True\n'
                               '    for index in range(size * size):  # pragma: no branch\n'
                               '        finite = finite and isfinite(entries[index])\n'
                               '    if finite:\n'
                               '        # The exponents are chosen before any entry is scaled: '
                               'each column\n'
                               '        # by its largest entry, then each row by its largest entry '
                               'over\n'
                               '        # those. An entry is then scaled once. Scaling the rows '
                               'first could\n'
                               '        # leave a column of small entries subnormal, and an Apple '
                               'GPU\n'
                               '        # flushes them, which makes an invertible matrix '
                               'singular.\n'
                               '        for column in range(size):  # pragma: no branch\n'
                               '            var largest = -1000\n'
                               '            for row in range(size):  # pragma: no branch\n'
                               '                var entry = entries[column * size + row]\n'
                               '                if entry != 0:\n'
                               '                    largest = max(largest, _binade(entry))\n'
                               '            if largest == -1000:\n'
                               '                return False, result^\n'
                               '            column_shift[column] = largest\n'
                               '        for row in range(size):  # pragma: no branch\n'
                               '            var largest = -1000\n'
                               '            for column in range(size):  # pragma: no branch\n'
                               '                var entry = entries[column * size + row]\n'
                               '                if entry != 0:\n'
                               '                    largest = max(\n'
                               '                        largest, _binade(entry) - '
                               'column_shift[column]\n'
                               '                    )\n'
                               '            if largest == -1000:\n'
                               '                return False, result^\n'
                               '            row_shift[row] = largest\n'
                               '        for column in range(size):  # pragma: no branch\n'
                               '            for row in range(size):  # pragma: no branch\n'
                               '                matrix[column * size + row] = '
                               '_times_power_of_two(\n'
                               '                    entries[column * size + row],\n'
                               '                    -(row_shift[row] + column_shift[column]),\n'
                               '                )\n'
                               '    for index in range(size):  # pragma: no branch\n'
                               '        inverse[index * size + index] = 1\n'
                               '    for column in range(size):  # pragma: no branch\n'
                               '        var pivot_row = column\n'
                               '        var pivot_magnitude = abs(matrix[column * size + column])\n'
                               '        for row in range(column + 1, size):\n'
                               '            var magnitude = abs(matrix[column * size + row])\n'
                               '            if magnitude > pivot_magnitude:\n'
                               '                pivot_row = row\n'
                               '                pivot_magnitude = magnitude\n'
                               '        if pivot_magnitude == 0:\n'
                               '            return False, result^\n'
                               '        if pivot_row != column:\n'
                               '            for at in range(size):  # pragma: no branch\n'
                               '                var first = at * size + column\n'
                               '                var second = at * size + pivot_row\n'
                               '                var saved = matrix[first]\n'
                               '                matrix[first] = matrix[second]\n'
                               '                matrix[second] = saved\n'
                               '                saved = inverse[first]\n'
                               '                inverse[first] = inverse[second]\n'
                               '                inverse[second] = saved\n'
                               '        var pivot = matrix[column * size + column]\n'
                               '        for row in range(size):  # pragma: no branch\n'
                               '            if row == column:\n'
                               '                continue\n'
                               '            var factor = matrix[column * size + row] / pivot\n'
                               '            for at in range(size):  # pragma: no branch\n'
                               '                matrix[at * size + row] -= factor * matrix[at * '
                               'size + column]\n'
                               '                inverse[at * size + row] -= factor * inverse[at * '
                               'size + column]\n'
                               '        for at in range(size):  # pragma: no branch\n'
                               '            matrix[at * size + column] /= pivot\n'
                               '            inverse[at * size + column] /= pivot\n'
                               "    # M = R M' C with R and C diagonal powers of two, so M's "
                               'inverse is\n'
                               "    # C^-1 M'^-1 R^-1: entry (i, j) is M'^-1 (i, j) over 2 ** (c_i "
                               '+ r_j).\n'
                               '    for column in range(size):  # pragma: no branch\n'
                               '        for row in range(size):  # pragma: no branch\n'
                               '            result[column * size + row] = _times_power_of_two(\n'
                               '                inverse[column * size + row],\n'
                               '                -(column_shift[row] + row_shift[column]),\n'
                               '            )\n'
                               '    return True, result^\n'
                               '\n'
                               '\n'
                               'def _inverse_exact_cofactors[\n'
                               '    size: Int\n'
                               '](entries: Array[Float32, size * size]) -> Tuple[\n'
                               '    Bool, Array[Float32, size * size]\n'
                               ']:\n'
                               '    """Use exact-sign cofactors for finite inputs; return zeros if '
                               'singular.\n'
                               '\n')),
 'math/scaled_products.mojo': (('1',
                                'large terms cancel. The Float32 specialization is '
                                'device-compatible.\n'
                                '"""\n'
                                '\n'
                                'from std.math import fma, frexp, inf, isfinite, ldexp\n'
                                '\n'
                                '\n'
                                '@fieldwise_init\n',
                                'large terms cancel. The Float32 specialization is '
                                'device-compatible.\n'
                                '"""\n'
                                '\n'
                                'from std.bit import count_leading_zeros\n'
                                'from std.math import fma, frexp, inf, isfinite, ldexp\n'
                                'from std.memory import bitcast\n'
                                '\n'
                                '\n'
                                '@fieldwise_init\n'),
                               ('2',
                                '        1.1754943508222875e-38\n'
                                '    ) if dtype == DType.float32 else SIMD[dtype, '
                                '1](2.2250738585072014e-308)\n'
                                '    comptime shift = 64 if dtype == DType.float32 else 512\n'
                                '    if value != 0 and abs(value) < tiny:\n'
                                '        var parts = frexp(value * ldexp(SIMD[dtype, 1](1), '
                                'Int32(shift)))\n'
                                '        return _Scaled(parts[0], exponent + Int(parts[1]) - '
                                'shift)\n',
                                '        1.1754943508222875e-38\n'
                                '    ) if dtype == DType.float32 else SIMD[dtype, '
                                '1](2.2250738585072014e-308)\n'
                                '    comptime shift = 64 if dtype == DType.float32 else 512\n'
                                '    comptime if dtype == DType.float32:\n'
                                '        # A subnormal Float32 is split from its bits. Apple GPUs '
                                'flush\n'
                                '        # subnormal operands to zero, so scaling one up first '
                                'reads zero\n'
                                '        # there. The bits give the same fraction and exponent.\n'
                                '        var bits = bitcast[DType.uint32](value)\n'
                                '        var significand = bits & UInt32(0x7FFFFF)\n'
                                '        if (bits & UInt32(0x7F800000)) == 0 and significand != '
                                '0:\n'
                                '            var top = 31 - Int(count_leading_zeros(significand))\n'
                                '            var fraction = (\n'
                                '                (bits & UInt32(0x80000000))\n'
                                '                | UInt32(126 << 23)\n'
                                '                | ((significand << UInt32(23 - top)) & '
                                'UInt32(0x7FFFFF))\n'
                                '            )\n'
                                '            return _Scaled(bitcast[dtype](fraction), exponent + '
                                'top - 148)\n'
                                '    if value != 0 and abs(value) < tiny:\n'
                                '        var parts = frexp(value * ldexp(SIMD[dtype, 1](1), '
                                'Int32(shift)))\n'
                                '        return _Scaled(parts[0], exponent + Int(parts[1]) - '
                                'shift)\n'))}
EDITS_SHA256 = '3b2e5a1e539868da565ca2e7ca385e993410829e54d69002edfc5cbf6fed549d'
FLOAT32_BRANCH = ('    comptime if dtype == DType.float32:\n'
 '        # A subnormal Float32 is split from its bits. Apple GPUs flush\n'
 '        # subnormal operands to zero, so scaling one up first reads zero\n'
 '        # there. The bits give the same fraction and exponent.\n'
 '        var bits = bitcast[DType.uint32](value)\n'
 '        var significand = bits & UInt32(0x7FFFFF)\n'
 '        if (bits & UInt32(0x7F800000)) == 0 and significand != 0:\n'
 '            var top = 31 - Int(count_leading_zeros(significand))\n'
 '            var fraction = (\n'
 '                (bits & UInt32(0x80000000))\n'
 '                | UInt32(126 << 23)\n'
 '                | ((significand << UInt32(23 - top)) & UInt32(0x7FFFFF))\n'
 '            )\n'
 '            return _Scaled(bitcast[dtype](fraction), exponent + top - 148)\n')
ADDED_IMPORTS = ('from std.bit import count_leading_zeros\n', 'from std.memory import bitcast\n')
APPLE_INVERSE_BLOCK = ('def _inverse_wide[\n'
 '    size: Int\n'
 '](entries: Array[Float32, size * size]) -> Tuple[\n'
 '    Bool, Array[Float32, size * size]\n'
 ']:\n'
 '    """Invert a matrix whose entries are out of the fast path\'s range.\n'
 '\n'
 '    The host and CUDA use exact-sign cofactors in Float64. Apple GPUs have\n'
 '    no Float64, so a kernel for one uses `_inverse_scaled_float32`.\n'
 '    """\n'
 '    comptime chosen = _inverse_scaled_float32[\n'
 '        size\n'
 '    ] if is_apple_gpu() else _inverse_exact_cofactors[size]\n'
 '    return chosen(entries)\n'
 '\n'
 '\n'
 'def _power_of_two(exponent: Int) -> Float32:\n'
 '    """Return two to a power from -126 through 127, from its bits.\n'
 '\n'
 '    Every power in that range is a normal Float32. A smaller one would be\n'
 '    subnormal, which an Apple GPU flushes to zero, so callers never ask\n'
 '    for one; see `_times_power_of_two`.\n'
 '    """\n'
 '    return bitcast[DType.float32](UInt32(exponent + 127) << 23)\n'
 '\n'
 '\n'
 'def _times_power_of_two(value: Float32, exponent: Int) -> Float32:\n'
 '    """Return `value` times two to any power, in steps of normal powers.\n'
 '\n'
 '    Each factor is normal and each step moves in the same direction.\n'
 '    For a normal input and normal result, scaling is exact.\n'
 '    Subnormal products can round in more than one step or flush to zero;\n'
 '    overflow yields infinity.\n'
 '    """\n'
 '    var result = value\n'
 '    var left = exponent\n'
 '    while left > 127:\n'
 '        result *= _power_of_two(127)\n'
 '        left -= 127\n'
 '    while left < -126:\n'
 '        result *= _power_of_two(-126)\n'
 '        left += 126\n'
 '    return result * _power_of_two(left)\n'
 '\n'
 '\n'
 'def _binade(value: Float32) -> Int:\n'
 '    """Return floor(log2(abs(value))) for a nonzero value, or -126 for a\n'
 '    subnormal one, from the exponent bits."""\n'
 '    return max(-126, Int((bitcast[DType.uint32](value) >> 23) & 0xFF) - 127)\n'
 '\n'
 '\n'
 'def _inverse_scaled_float32[\n'
 '    size: Int\n'
 '](entries: Array[Float32, size * size]) -> Tuple[\n'
 '    Bool, Array[Float32, size * size]\n'
 ']:\n'
 '    """Invert with Float32 alone; return zeros if elimination finds the\n'
 '    matrix singular.\n'
 '\n'
 '    Each column, then each row, gets a power of two near its largest entry,\n'
 "    chosen from the entries' exponents before any entry changes. Each entry\n"
 "    is divided by its row's and its column's power once. The division is\n"
 '    exact unless the scaled entry falls below the normal range, which only\n'
 '    happens to an entry far smaller than both its row and its column.\n'
 '    Gauss-Jordan elimination with partial pivoting inverts the scaled\n'
 '    matrix, and the powers are multiplied back, exactly unless an inverse\n'
 '    entry itself leaves the normal range. A nonfinite entry skips the\n'
 '    scaling and propagates as elimination does.\n'
 '\n'
 '    Unlike the exact cofactors, this decides singularity by a zero pivot,\n'
 '    so a matrix within rounding of singular can go either way. Apple GPUs\n'
 '    use it because they have no Float64.\n'
 '\n'
 '    Parameters:\n'
 "        size: The matrix's side, two through four.\n"
 '\n'
 '    Args:\n'
 '        entries: The matrix, column-major.\n'
 '\n'
 '    Returns:\n'
 '        Whether it is invertible, and its inverse or zeros.\n'
 '    """\n'
 '    comptime assert 2 <= size <= 4\n'
 '    var matrix = entries.copy()\n'
 '    var inverse = Array[Float32, size * size](fill=0)\n'
 '    var result = Array[Float32, size * size](fill=0)\n'
 '    var row_shift = Array[Int, size](fill=0)\n'
 '    var column_shift = Array[Int, size](fill=0)\n'
 '    var finite = True\n'
 '    for index in range(size * size):  # pragma: no branch\n'
 '        finite = finite and isfinite(entries[index])\n'
 '    if finite:\n'
 '        # The exponents are chosen before any entry is scaled: each column\n'
 '        # by its largest entry, then each row by its largest entry over\n'
 '        # those. An entry is then scaled once. Scaling the rows first could\n'
 '        # leave a column of small entries subnormal, and an Apple GPU\n'
 '        # flushes them, which makes an invertible matrix singular.\n'
 '        for column in range(size):  # pragma: no branch\n'
 '            var largest = -1000\n'
 '            for row in range(size):  # pragma: no branch\n'
 '                var entry = entries[column * size + row]\n'
 '                if entry != 0:\n'
 '                    largest = max(largest, _binade(entry))\n'
 '            if largest == -1000:\n'
 '                return False, result^\n'
 '            column_shift[column] = largest\n'
 '        for row in range(size):  # pragma: no branch\n'
 '            var largest = -1000\n'
 '            for column in range(size):  # pragma: no branch\n'
 '                var entry = entries[column * size + row]\n'
 '                if entry != 0:\n'
 '                    largest = max(\n'
 '                        largest, _binade(entry) - column_shift[column]\n'
 '                    )\n'
 '            if largest == -1000:\n'
 '                return False, result^\n'
 '            row_shift[row] = largest\n'
 '        for column in range(size):  # pragma: no branch\n'
 '            for row in range(size):  # pragma: no branch\n'
 '                matrix[column * size + row] = _times_power_of_two(\n'
 '                    entries[column * size + row],\n'
 '                    -(row_shift[row] + column_shift[column]),\n'
 '                )\n'
 '    for index in range(size):  # pragma: no branch\n'
 '        inverse[index * size + index] = 1\n'
 '    for column in range(size):  # pragma: no branch\n'
 '        var pivot_row = column\n'
 '        var pivot_magnitude = abs(matrix[column * size + column])\n'
 '        for row in range(column + 1, size):\n'
 '            var magnitude = abs(matrix[column * size + row])\n'
 '            if magnitude > pivot_magnitude:\n'
 '                pivot_row = row\n'
 '                pivot_magnitude = magnitude\n'
 '        if pivot_magnitude == 0:\n'
 '            return False, result^\n'
 '        if pivot_row != column:\n'
 '            for at in range(size):  # pragma: no branch\n'
 '                var first = at * size + column\n'
 '                var second = at * size + pivot_row\n'
 '                var saved = matrix[first]\n'
 '                matrix[first] = matrix[second]\n'
 '                matrix[second] = saved\n'
 '                saved = inverse[first]\n'
 '                inverse[first] = inverse[second]\n'
 '                inverse[second] = saved\n'
 '        var pivot = matrix[column * size + column]\n'
 '        for row in range(size):  # pragma: no branch\n'
 '            if row == column:\n'
 '                continue\n'
 '            var factor = matrix[column * size + row] / pivot\n'
 '            for at in range(size):  # pragma: no branch\n'
 '                matrix[at * size + row] -= factor * matrix[at * size + column]\n'
 '                inverse[at * size + row] -= factor * inverse[at * size + column]\n'
 '        for at in range(size):  # pragma: no branch\n'
 '            matrix[at * size + column] /= pivot\n'
 '            inverse[at * size + column] /= pivot\n'
 "    # M = R M' C with R and C diagonal powers of two, so M's inverse is\n"
 "    # C^-1 M'^-1 R^-1: entry (i, j) is M'^-1 (i, j) over 2 ** (c_i + r_j).\n"
 '    for column in range(size):  # pragma: no branch\n'
 '        for row in range(size):  # pragma: no branch\n'
 '            result[column * size + row] = _times_power_of_two(\n'
 '                inverse[column * size + row],\n'
 '                -(column_shift[row] + row_shift[column]),\n'
 '            )\n'
 '    return True, result^\n'
 '\n'
 '\n')
APPLE_DISPATCH = '    ] if is_apple_gpu() else _inverse_exact_cofactors[size]\n'
INVERSE_IMPORTS = ('from std.memory import bitcast\n', 'from std.sys.info import is_apple_gpu\n')
PACKAGE_INPUTS = {'math/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479'}
PROVIDER_INPUTS = {'math/norm.mojo': '5275636f99048885fcc308bfa92fde3d52c5a8eefb48f616f59f8f31a0b5cbb1',
 'math/matrix_determinant.mojo': 'c5b25179893fd2903dbda5de68914a50e662e3428107ef2c3424ef42cafcde19'}
NATIVE_TESTS = ('tests/test_scaled_products_subnormal.mojo', 'tests/test_matrix_inverse_float32.mojo')
NATIVE_CLOSURE = frozenset({'math/__init__.mojo',
           'math/matrix_determinant.mojo',
           'math/matrix_inverse.mojo',
           'math/norm.mojo',
           'math/scaled_products.mojo',
           'tests/test_matrix_inverse_float32.mojo',
           'tests/test_scaled_products_subnormal.mojo'})
TESTS = {'tests/test_scaled_products_subnormal.mojo': '9025041d39d6f2586d5baaa85ef043c17eaea0215f77ecf3ddc5be901bd423e8',
 'tests/test_matrix_inverse_float32.mojo': '69c220142e9650325fbf04732280f5e6b362cb7bdfa4574c61aa908c36b7ae3a',
 'tools/carla_lane_oracle/test_scaled_float32_contracts.py': 'd06b9558ab87dc6542760a1ae54418b2827ebbc11df3d09e0a621b38ea1c68d9',
 'docs/validation/scaled-float32-746.md': '97fbe81ea07c6e2f0ecff4a87c551ee7d72770342724d49b8b7e136c1b065e18'}

def require(ok, message):
    if not ok:
        raise ValueError('scaled Float32 source successor: ' + message)


def sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def verify_float64_domain(before, after):
    """Project the whole predecessor outside one compile-time Float32 branch.

    For nonzero subnormal significand n, top=floor(log2(n)). The constructed
    fraction is sign*n/2**(top+1), with exponent old_exponent+top-148.
    Recombination is sign*n*2**(-149+old_exponent), with no significand loss.
    The compile-time dtype guard eliminates the complete addition for Float64.
    """
    require(sha(before) == BEFORE_SHA256[MATH] and sha(after) == AFTER_SHA256[MATH],
            'unsealed arithmetic domain')
    require(FLOAT32_BRANCH.startswith('    comptime if dtype == DType.float32:\n')
            and after.count(FLOAT32_BRANCH) == 1, 'Float32 guard or branch changed')
    projected = after.replace(FLOAT32_BRANCH, '', 1)
    for added in ADDED_IMPORTS:
        require(projected.count(added) == 1, 'Float32 support import changed')
        projected = projected.replace(added, '', 1)
    require(projected == before, 'non-Float32 provider changed')


def verify_host_inverse_domain(before, after):
    """Project the whole predecessor outside one Apple-GPU-only addition.

    The addition is a new `_inverse_wide` that chooses at compile time, and
    the Apple helpers. Off an Apple GPU it chooses `_inverse_exact_cofactors`,
    which is the predecessor's `_inverse_wide` under a new name, unchanged.
    """
    require(sha(before) == BEFORE_SHA256[INVERSE] and sha(after) == AFTER_SHA256[INVERSE],
            'unsealed inverse domain')
    require(APPLE_INVERSE_BLOCK.startswith('def _inverse_wide[\n')
            and APPLE_INVERSE_BLOCK.count(APPLE_DISPATCH) == 1
            and after.count(APPLE_INVERSE_BLOCK + 'def _inverse_exact_cofactors[\n') == 1,
            'Apple guard or block changed')
    projected = after.replace(APPLE_INVERSE_BLOCK + 'def _inverse_exact_cofactors[\n',
                              'def _inverse_wide[\n', 1)
    for added in INVERSE_IMPORTS:
        require(projected.count(added) == 1, 'Apple support import changed')
        projected = projected.replace(added, '', 1)
    require(projected == before, 'host inverse provider changed')


def predecessor_source(path, text):
    """Recover every historical byte through unique, sealed inverse spans."""
    require(path in SOURCE_PATHS and type(text) is str, 'unknown source')
    require(sha(text) == AFTER_SHA256[path], 'unknown exact endpoint: ' + path)
    require(hashlib.sha256(json.dumps(EDITS, sort_keys=True).encode()).hexdigest() == EDITS_SHA256,
            'inverse inventory changed')
    current = text
    for name, before, after in reversed(EDITS[path]):
        require(bool(before) and bool(after) and current.count(after) == 1,
                'missing or ambiguous inverse: ' + path + ':' + name)
        current = current.replace(after, before, 1)
    require(sha(current) == BEFORE_SHA256[path], 'inverse endpoint changed: ' + path)
    if path == MATH:
        verify_float64_domain(current, text)
    else:
        verify_host_inverse_domain(current, text)
    return current


def verify_sources(texts):
    """Classify only the complete historical or reviewed arithmetic endpoint."""
    require(type(texts) is dict and set(texts) == set(SOURCE_PATHS),
            'unknown or empty source scope')
    active = []
    for path in SOURCE_PATHS:
        text = texts[path]
        require(type(text) is str, 'source is not text')
        if sha(text) != BEFORE_SHA256[path]:
            predecessor_source(path, text)
            active.append(path)
    return tuple(active)


def edges(paths):
    """Descriptors alone grant no admission and cannot replace physical reads."""
    require(type(paths) is tuple and len(set(paths)) == len(paths)
            and set(paths) <= set(SOURCE_PATHS), 'unknown edge scope')
    return {path: {'path': path, 'before_sha256': BEFORE_SHA256[path],
                   'after_sha256': AFTER_SHA256[path]} for path in paths}
