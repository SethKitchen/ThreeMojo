# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""One exact Float32-only arithmetic-provider edge, below source admission.

The complete inverse and dtype projection preserve every predecessor byte.
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
SOURCE_PATHS = ('math/scaled_products.mojo',)
BEFORE_SHA256 = {'math/scaled_products.mojo': 'b504f18cff7df27bff4fbf92fbed7aa4868518f1b1507ea1331540d7e6f0afbb'}
AFTER_SHA256 = {'math/scaled_products.mojo': '632438eb32acc53e5d4b10e8aa0ca9049a0fc2c5cd7e3d815039626ff3409c86'}
EDITS = {'math/scaled_products.mojo': (('1',
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
EDITS_SHA256 = '540f344db34128317861c868403d519dbe6047f8fa8997f597c1d3053c2a29cd'
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
PACKAGE_INPUTS = {'math/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479'}
PROVIDER_INPUTS = {'math/norm.mojo': '5275636f99048885fcc308bfa92fde3d52c5a8eefb48f616f59f8f31a0b5cbb1'}
NATIVE_TESTS = ('tests/test_scaled_products_subnormal.mojo',)
NATIVE_CLOSURE = frozenset({'math/__init__.mojo',
           'math/norm.mojo',
           'math/scaled_products.mojo',
           'tests/test_scaled_products_subnormal.mojo'})
TESTS = {'tests/test_scaled_products_subnormal.mojo': '9025041d39d6f2586d5baaa85ef043c17eaea0215f77ecf3ddc5be901bd423e8',
 'tools/carla_lane_oracle/test_scaled_float32_contracts.py': 'be7b72191ada5dcb0123e93491db6777dff24003d14cd858d5f5dffd4e61a2bd',
 'docs/validation/scaled-float32-746.md': '43d615855d3cae77db601d5be333475bc31819677137a7a40822d249d4ea669f'}

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
    verify_float64_domain(current, text)
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
