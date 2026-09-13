# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

@no_inline
def observe(id: StaticString, value: Bool) -> Bool:
    print(id, value)
    return value


def build(rings: Int, columns: Int) -> Int:
    var data = List[Float32]()
    var outer_a = 0
    for ring in range(rings + 1):
        outer_a += 1
        var inner_a = 0
        for column in range(columns + 1):
            inner_a += 1
            var x = Float32(ring) * Float32(column)
            data.append(x)
            data.append(x * 2)
            data.append(x * 3)
        _ = observe("inner_a", inner_a > 0)
    _ = observe("outer_a", outer_a > 0)

    var index = List[Int]()
    var outer_b = 0
    for ring in range(rings):
        outer_b += 1
        var inner_b = 0
        for column in range(columns):
            inner_b += 1
            var top = ring * (columns + 1) + column
            if ring != 0:
                index.append(top)
                index.append(top + 1)
            if ring != rings - 1:
                index.append(top + columns + 1)
        _ = observe("inner_b", inner_b > 0)
    _ = observe("outer_b", outer_b > 0)
    return len(data) + len(index)


def main():
    print(build(8, 12))
