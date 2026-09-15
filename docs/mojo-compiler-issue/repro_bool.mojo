# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reproducer for the Mojo compiler hang: this variant hangs.

The write-up is the wiki page "The Mojo compiler hang", whose source is
docs/wiki/The-Mojo-compiler-hang.md. Do not add this file to a build
target; build it by hand under a time limit.
"""


@no_inline
def observe(id: StaticString, value: Bool) -> Bool:
    print(id, value)
    return value


def build(rings: Int, columns: Int) -> Int:
    var data = List[Float32]()
    var outer_a = False
    for ring in range(rings + 1):
        outer_a = True
        var inner_a = False
        for column in range(columns + 1):
            inner_a = True
            var x = Float32(ring) * Float32(column)
            data.append(x)
            data.append(x * 2)
            data.append(x * 3)
        _ = observe("inner_a", inner_a)
    _ = observe("outer_a", outer_a)

    var index = List[Int]()
    var outer_b = False
    for ring in range(rings):
        outer_b = True
        var inner_b = False
        for column in range(columns):
            inner_b = True
            var top = ring * (columns + 1) + column
            if ring != 0:
                index.append(top)
                index.append(top + 1)
            if ring != rings - 1:
                index.append(top + columns + 1)
        _ = observe("inner_b", inner_b)
    _ = observe("outer_b", outer_b)
    return len(data) + len(index)


def main():
    print(build(8, 12))
