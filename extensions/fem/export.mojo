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
