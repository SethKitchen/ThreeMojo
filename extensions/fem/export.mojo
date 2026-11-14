# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write tetrahedral meshes and their results as legacy VTK files.

ParaView and other analysis tools read the legacy VTK format. The file is
an ASCII `UNSTRUCTURED_GRID`. A four-node element is cell type 10,
`VTK_TETRA`. A ten-node element is cell type 24, `VTK_QUADRATIC_TETRA`,
whose edge order is this extension's: 0-1, 1-2, 2-0, 0-3, 1-3 and 2-3.

Each element has its material index as the cell scalar `material`.
`vtk_temperatures` adds the point scalars `temperature`, in kelvin.
`vtk_record` writes one record of a transient history the same way, with
its time in the title line. `vtk_series` writes the file series that
ParaView 5.5 and later reads as a time series: a JSON file named like
`heat.vtk.series` that lists each file with its time in seconds.
`series_names` gives the file names `heat_0000.vtk`, `heat_0001.vtk` and
on. `vtk_heat` writes a steady result with the cell vectors `heat_flux`,
in watts per square meter, beside the temperatures.
`vtk_modes` adds one point vector per mode shape, `mode_1` and on, with
the frequencies in the title line. `vtk_result` adds the solved fields: the point vectors `displacement`, in
meters, and the cell scalars `von_mises` and cell tensors `stress`, in
pascals. It adds the cell scalars `principal`, the three principal
stresses from the largest, and the cell vectors `first_direction`, the
direction of the largest. Each number is written in full, so it reads
back exactly.
"""

from extensions.fem.ids import ElementId, LINEAR
from extensions.fem.mesh import TetMesh
from extensions.fem.modal import ModalResult
from extensions.fem.thermal import (
    ThermalProblem,
    ThermalResult,
    TransientResult,
    heat_flux,
)
from extensions.fem.static import StaticResult
from units.si import PASCAL, PER_SECOND


def _number(value: Float64) -> String:
    """Return a number in the shortest text that reads back to it."""
    return String(value)


def _geometry(
    mesh: TetMesh, title: String = "ThreeMojo tetrahedral mesh, meters"
) -> String:
    """Return the header, points, cells, cell types and materials."""
    var count = mesh.nodes_per_element()
    var kind = String("10")
    if mesh.order != LINEAR:
        kind = "24"
    var out = String("# vtk DataFile Version 3.0\n")
    out += title + "\nASCII\n"
    out += "DATASET UNSTRUCTURED_GRID\n"
    out += "POINTS " + String(mesh.node_count()) + " double\n"
    for p in mesh.nodes:
        out += _number(p.x) + " " + _number(p.y) + " " + _number(p.z) + "\n"
    var cells = mesh.element_count()
    out += "CELLS " + String(cells) + " " + String(cells * (count + 1)) + "\n"
    for e in range(cells):
        out += String(count)
        for k in range(count):  # pragma: no branch
            out += " " + String(mesh.corners[count * e + k])
        out += "\n"
    out += "CELL_TYPES " + String(cells) + "\n"
    for _ in range(cells):
        out += kind + "\n"
    out += "CELL_DATA " + String(cells) + "\n"
    out += "SCALARS material int 1\nLOOKUP_TABLE default\n"
    for e in range(cells):
        out += String(mesh.materials[e]) + "\n"
    return out^


def vtk_mesh(mesh: TetMesh) -> String:
    """Return a mesh as the text of a legacy VTK file.

    Args:
        mesh: The mesh.

    Returns:
        The text, with each element's material.
    """
    return _geometry(mesh)


def vtk_result(mesh: TetMesh, result: StaticResult) raises -> String:
    """Return a mesh and a solved result as the text of a legacy VTK file.

    Args:
        mesh: The mesh that was solved.
        result: Its result.

    Returns:
        The text, with each element's material, von Mises stress,
        principal stresses and stress tensor, and each node's
        displacement.

    Raises:
        Error: If the result is not for this mesh.
    """
    if len(result.displacements) != 3 * mesh.node_count():
        raise Error("The result is not for this mesh")
    if len(result.von_mises) != mesh.element_count():
        raise Error("The result is not for this mesh")
    var out = _geometry(mesh)
    var cells = mesh.element_count()
    out += "SCALARS von_mises double 1\nLOOKUP_TABLE default\n"
    for e in range(cells):
        out += _number(result.von_mises[e].to(PASCAL)) + "\n"
    out += "SCALARS principal double 3\nLOOKUP_TABLE default\n"
    var firsts = List[String]()
    for e in range(cells):
        var principal = result.principal(ElementId(e))
        out += _number(principal.values[0].to(PASCAL)) + " "
        out += _number(principal.values[1].to(PASCAL)) + " "
        out += _number(principal.values[2].to(PASCAL)) + "\n"
        var d = principal.directions[0]
        firsts.append(
            _number(d.x) + " " + _number(d.y) + " " + _number(d.z) + "\n"
        )
    out += "VECTORS first_direction double\n"
    for line in firsts:
        out += line
    out += "TENSORS stress double\n"
    # Voigt order xx, yy, zz, yz, xz, xy as a full symmetric matrix.
    var order: List[Int] = [0, 5, 4, 5, 1, 3, 4, 3, 2]
    for e in range(cells):
        for k in range(9):
            if k > 0:
                out += " "
            out += _number(result.stresses[6 * e + order[k]])
        out += "\n"
    out += "POINT_DATA " + String(mesh.node_count()) + "\n"
    out += "VECTORS displacement double\n"
    for n in range(mesh.node_count()):
        var at = 3 * n
        out += _number(result.displacements[at]) + " "
        out += _number(result.displacements[at + 1]) + " "
        out += _number(result.displacements[at + 2]) + "\n"
    return out^


def vtk_modes(mesh: TetMesh, modes: ModalResult) raises -> String:
    """Return a mesh and its mode shapes as the text of a legacy VTK file.

    The title line gives the frequencies in cycles per second. ParaView
    can animate each shape with its Warp By Vector filter.

    Args:
        mesh: The mesh whose modes were found.
        modes: Its modes.

    Returns:
        The text, with each element's material and one point vector per
        mode: `mode_1`, `mode_2` and on.

    Raises:
        Error: If a shape is not for this mesh.
    """
    var title = String("ThreeMojo natural modes, meters, Hz:")
    for frequency in modes.frequencies:
        title += " " + _number(frequency.to(PER_SECOND))
    var out = _geometry(mesh, title)
    out += "POINT_DATA " + String(mesh.node_count()) + "\n"
    for m in range(len(modes.shapes)):
        ref shape = modes.shapes[m]
        if len(shape) != 3 * mesh.node_count():
            raise Error("The mode shape is not for this mesh")
        out += "VECTORS mode_" + String(m + 1) + " double\n"
        for n in range(mesh.node_count()):
            out += _number(shape[3 * n]) + " "
            out += _number(shape[3 * n + 1]) + " "
            out += _number(shape[3 * n + 2]) + "\n"
    return out^


def vtk_temperatures(mesh: TetMesh, result: ThermalResult) raises -> String:
    """Return a mesh and its temperatures as the text of a legacy VTK file.

    Args:
        mesh: The mesh that was solved.
        result: Its temperatures.

    Returns:
        The text, with each element's material and each node's
        temperature in kelvin as the point scalars `temperature`.

    Raises:
        Error: If the result is not for this mesh.
    """
    return _temperatures(
        mesh, result.temperatures, "ThreeMojo temperatures, meters, kelvin"
    )


def _temperatures(
    mesh: TetMesh, values: List[Float64], title: String
) raises -> String:
    """Return a mesh and one temperature per node as VTK text."""
    if len(values) != mesh.node_count():
        raise Error("The result is not for this mesh")
    var out = _geometry(mesh, title)
    out += "POINT_DATA " + String(mesh.node_count()) + "\n"
    out += "SCALARS temperature double 1\nLOOKUP_TABLE default\n"
    for value in values:
        out += _number(value) + "\n"
    return out^


def vtk_record(
    mesh: TetMesh, history: TransientResult, record: Int
) raises -> String:
    """Return one record of a transient history as a legacy VTK file.

    Args:
        mesh: The mesh that was solved.
        history: Its temperatures in time.
        record: The record, from 0 for the start.

    Returns:
        The text, as `vtk_temperatures` writes it, with the record's
        time in seconds in the title line.

    Raises:
        Error: If the record is outside the history, or the history is
            not for this mesh.
    """
    if record < 0 or record >= len(history.times):
        raise Error("The record is outside the history")
    return _temperatures(
        mesh,
        history.temperatures[record],
        "ThreeMojo temperatures at "
        + _number(history.times[record])
        + " s, meters, kelvin",
    )


def _require_name(name: String) raises:
    """Refuse a file name that a JSON string would need to escape."""
    var bytes = name.as_bytes()
    if len(bytes) == 0:
        raise Error("A file name of a series must not be empty")
    for byte in bytes:  # pragma: no branch
        if byte < 32 or byte == 34 or byte == 92:
            raise Error(
                "A file name of a series must not hold a quote, a backslash"
                " or a control character"
            )


def series_names(stem: String, count: Int) raises -> List[String]:
    """Return the file names of a series of records.

    Args:
        stem: The start of each name, such as `heat` or `out/heat`.
        count: The number of records. One or more.

    Returns:
        The names `stem_0000.vtk`, `stem_0001.vtk` and on. The number
        has four digits, or more when the count needs them.

    Raises:
        Error: If the count is less than one, or the stem is empty or
            holds a quote, a backslash or a control character.
    """
    if count < 1:
        raise Error("A series needs at least one record")
    _require_name(stem)
    var width = max(4, String(count - 1).byte_length())
    var out = List[String]()
    for k in range(count):  # pragma: no branch
        var number = String(k)
        while number.byte_length() < width:
            number = "0" + number
        out.append(stem + "_" + number + ".vtk")
    return out^


def vtk_series(names: List[String], history: TransientResult) raises -> String:
    """Return the file series of a transient history, for ParaView.

    Write the result to a file whose name ends in `.vtk.series`, beside
    the files of the records. ParaView 5.5 and later opens it as one
    data set in time.

    Args:
        names: The file name of each record, such as `series_names`
            gives, relative to the series file.
        history: The history.

    Returns:
        The JSON text, version 1.0, with each name and its time in
        seconds.

    Raises:
        Error: If the history has no record, the names do not fit the
            records, or a name is empty or holds a quote, a backslash or
            a control character.
    """
    var count = len(history.times)
    if count == 0:
        raise Error("A series needs at least one record")
    if len(names) != count:
        raise Error("A series needs one file name per record")
    var out = String('{\n  "file-series-version": "1.0",\n  "files": [\n')
    for k in range(count):  # pragma: no branch
        _require_name(names[k])
        out += '    { "name": "' + names[k] + '", "time": '
        out += _number(history.times[k]) + " }"
        if k + 1 < count:
            out += ","
        out += "\n"
    out += "  ]\n}\n"
    return out^


def vtk_heat(problem: ThermalProblem, result: ThermalResult) raises -> String:
    """Return a steady thermal result with its heat flux as a VTK file.

    Use the Glyph filter of ParaView on `heat_flux` to draw arrows from
    hot to cold.

    Args:
        problem: The problem that was solved.
        result: Its temperatures.

    Returns:
        The text, with each element's material, the cell vectors
        `heat_flux` in watts per square meter, and each node's
        temperature in kelvin as the point scalars `temperature`.

    Raises:
        Error: If the result is not for this problem.
    """
    var flux = heat_flux(problem, result)
    ref mesh = problem.mesh
    var out = _geometry(mesh, "ThreeMojo heat, meters, kelvin, W/m^2")
    out += "VECTORS heat_flux double\n"
    for e in range(mesh.element_count()):  # pragma: no branch
        out += _number(flux.values[3 * e]) + " "
        out += _number(flux.values[3 * e + 1]) + " "
        out += _number(flux.values[3 * e + 2]) + "\n"
    out += "POINT_DATA " + String(mesh.node_count()) + "\n"
    out += "SCALARS temperature double 1\nLOOKUP_TABLE default\n"
    for value in result.temperatures:  # pragma: no branch
        out += _number(value) + "\n"
    return out^
