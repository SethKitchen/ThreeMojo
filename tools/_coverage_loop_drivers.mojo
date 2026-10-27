# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the native loop source and the production drivers.

The checker still compiles these texts. This record only keeps their bytes.
"""


def coverage_loop_drivers() -> String:
    """Return the native loop source and the production drivers.

    Returns:
        JSON with the production driver, the hang driver, the compile-error
        driver, and the native source.
    """
    return (
        '{"production":"from production import total\\nfrom std.testing import'
        " assert_equal\\nfrom std.ffi import external_call\\n\\ndef main()"
        ' raises:\\n    assert_equal(external_call[\\"alarm\\",'
        " UInt32](UInt32(5)), UInt32(0))\\n    assert_equal(total(0), 1)\\n   "
        ' assert_equal(total(2), 2)\\n    print(\\"RESULT production'
        ' capture\\")\\n","hang":"from production import total\\nfrom'
        " std.testing import assert_equal\\nfrom std.ffi import"
        " external_call\\n\\ndef main() raises:\\n   "
        ' assert_equal(external_call[\\"alarm\\", UInt32](UInt32(5)),'
        " UInt32(0))\\n    assert_equal(total(0), 1)\\n    while True:\\n      "
        '  _ = external_call[\\"pause\\", Int32]()\\n","compile_error":"from'
        " production import total\\n\\ndef main() raises:\\n    var broken"
        ' =\\n","source":"from std.testing import assert_equal\\nfrom std.sys'
        " import argv\\n\\ndef fixed(leave: Int) raises -> Int:\\n    var total"
        " = 0\\n    for index in range(3):\\n        if leave == 1:\\n         "
        "   break\\n        if leave == 2:\\n            return total\\n       "
        ' if leave == 3:\\n            raise Error(\\"expected body\\")\\n     '
        "   if index == 0:\\n            continue\\n        total += index\\n  "
        "  else:\\n        total += 10\\n    return total\\n\\ndef empty() ->"
        " Int:\\n    for index in range(0):\\n        return index\\n   "
        " else:\\n        return 7\\n\\ndef mark(value: Int, mut order: String)"
        " -> Int:\\n    order += String(value)\\n    return value\\n\\ndef"
        " literal() raises -> Int:\\n    var total = 0\\n    var order ="
        ' String(\\"\\")\\n    for value in [mark(1, order), mark(2, order),'
        ' mark(3, order)]:\\n        assert_equal(order, \\"123\\")\\n       '
        " total += value\\n    return total\\n\\ndef dynamic(n: Int) -> Int:\\n"
        "    var total = 0\\n    for index in range(n):\\n        total +="
        " index\\n    return total\\n\\ndef main() raises:\\n    var mode ="
        " Int(String(argv()[1]))\\n    assert_equal(fixed(0), 13)\\n   "
        " assert_equal(fixed(1), 0)\\n    assert_equal(fixed(2), 0)\\n    var"
        " caught = False\\n    try:\\n        _ = fixed(3)\\n    except"
        ' error:\\n        caught = String(error) == \\"expected body\\"\\n   '
        " assert_equal(caught, True)\\n    assert_equal(empty(), 7)\\n   "
        " assert_equal(literal(), 6)\\n    assert_equal(dynamic(2), 1)\\n    if"
        " mode == 0:\\n        assert_equal(dynamic(0), 0)\\n   "
        ' print(\\"RESULT constant loops\\")\\n"}'
    )
