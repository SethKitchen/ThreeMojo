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
`vtk_result` adds the solved fields: the point vectors `displacement`, in
meters, and the cell scalars `von_mises` and cell tensors `stress`, in
pascals. Each number is written in full, so it reads back exactly.
"""

from extensions.fem.ids import LINEAR
from extensions.fem.mesh import TetMesh
from extensions.fem.static import StaticResult
from units.si import PASCAL


def _number(value: Float64) -> String:
    """Return a number in the shortest text that reads back to it."""
    return String(value)


def _geometry(mesh: TetMesh) -> String:
    """Return the header, points, cells, cell types and materials."""
    var count = mesh.nodes_per_element()
    var kind = String("10")
    if mesh.order != LINEAR:
        kind = "24"
    var out = String("# vtk DataFile Version 3.0\n")
    out += "ThreeMojo tetrahedral mesh, meters\nASCII\n"
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
        The text, with each element's material, von Mises stress and
        stress tensor, and each node's displacement.

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
