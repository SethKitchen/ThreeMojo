# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Transient heat histories written as VTK file series for ParaView."""

from extensions.fem.export import (
    series_names,
    vtk_record,
    vtk_series,
    vtk_temperatures,
)
from extensions.fem.mesh import TetMesh, box_mesh
from extensions.fem.thermal import ThermalResult, TransientResult
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Length64, METER


def _cube() raises -> TetMesh:
    var side = Length64(0.01, METER)
    return box_mesh(side, side, side, 1, 1, 1)


def _history(nodes: Int, records: Int) -> TransientResult:
    var history = TransientResult()
    for k in range(records):
        history.times.append(0.25 * Float64(k))
        var values = List[Float64]()
        for n in range(nodes):
            values.append(310.0 + Float64(k) + 0.125 * Float64(n))
        history.temperatures.append(values^)
    return history^


def _body(text: String) -> String:
    """Return the text after its title line."""
    var lines = text.split("\n")
    var out = String("")
    for k in range(2, len(lines)):
        out += String(lines[k]) + "\n"
    return out^


def test_a_record_is_a_temperature_file() raises:
    var mesh = _cube()
    var history = _history(mesh.node_count(), 3)
    var text = vtk_record(mesh, history, 2)
    assert_true(
        text.startswith(
            "# vtk DataFile Version 3.0\nThreeMojo temperatures at 0.5 s,"
            " meters, kelvin\n"
        )
    )
    # Past the title, it is the file of the same temperatures at rest.
    var values = history.temperatures[2].copy()
    var same = vtk_temperatures(mesh, ThermalResult(values^))
    assert_equal(_body(text), _body(same))
    assert_true("\n312.875\n" in text)
    with assert_raises(contains="outside the history"):
        _ = vtk_record(mesh, history, 3)
    with assert_raises(contains="outside the history"):
        _ = vtk_record(mesh, history, -1)
    with assert_raises(contains="not for this mesh"):
        _ = vtk_record(mesh, _history(3, 1), 0)


def test_the_names_of_a_series() raises:
    var names = series_names("out/heat", 3)
    assert_equal(len(names), 3)
    assert_equal(names[0], "out/heat_0000.vtk")
    assert_equal(names[2], "out/heat_0002.vtk")
    # A long series gets more digits.
    var long = series_names("t", 10001)
    assert_equal(long[0], "t_00000.vtk")
    assert_equal(long[10000], "t_10000.vtk")
    with assert_raises(contains="at least one record"):
        _ = series_names("heat", 0)
    with assert_raises(contains="empty"):
        _ = series_names("", 2)
    with assert_raises(contains="quote"):
        _ = series_names('a"b', 2)
    with assert_raises(contains="backslash"):
        _ = series_names("a\\b", 2)
    with assert_raises(contains="control"):
        _ = series_names("a\nb", 2)


def test_the_series_file() raises:
    var history = _history(8, 2)
    var text = vtk_series(series_names("heat", 2), history)
    assert_equal(
        text,
        (
            '{\n  "file-series-version": "1.0",\n  "files": [\n    {'
            ' "name": "heat_0000.vtk", "time": 0.0 },\n    { "name":'
            ' "heat_0001.vtk", "time": 0.25 }\n  ]\n}\n'
        ),
    )
    with assert_raises(contains="at least one record"):
        _ = vtk_series(List[String](), TransientResult())
    with assert_raises(contains="one file name per record"):
        _ = vtk_series(series_names("heat", 3), history)
    var bad: List[String] = ["heat_0000.vtk", 'a"b.vtk']
    with assert_raises(contains="quote"):
        _ = vtk_series(bad, history)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
