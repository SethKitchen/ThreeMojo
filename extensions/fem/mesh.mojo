# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Meshes of four-node tetrahedra.

A `TetMesh` holds nodes in meters and elements of four nodes each. Each
element also names a material. `add_element` turns an element inside out
when its volume is negative, so every element has a positive volume.

A face of a tetrahedron is on the outer surface when no other element
shares it. `boundary_faces` returns those faces, each turned to face out
of its element.

`box_mesh` fills a box with a grid of cubes. `voxel_mesh` fills the
voxels of one label of a label map. Each cube becomes six tetrahedra
that share the diagonal from its low corner to its high corner: the
Kuhn split. Neighbor cubes then share whole faces, so the mesh is
conforming.
"""

from extensions.fem.ids import (
    DOF_X,
    DOF_Y,
    DofAxis,
    ElementId,
    ElementOrder,
    LINEAR,
    MaterialId,
    NodeId,
    QUADRATIC,
    require_dof_axis,
    require_id,
)
from std.collections import Dict
from extensions.imaging.ids import LabelId, require_label
from extensions.imaging.labels import LabelMap
from extensions.sdf.vector import V3, cross, dot, v3
from std.math import isfinite, max, min
from units.si import CUBIC_METER, Length64, METER, Volume64

# The most elements that `box_mesh` makes.
comptime MAX_MESH_ENTRIES = 16777216


def signed_volume(a: V3, b: V3, c: V3, d: V3) -> Float64:
    """Return the signed volume of a tetrahedron, in cubic meters.

    Args:
        a: The first corner.
        b: The second corner.
        c: The third corner.
        d: The fourth corner.

    Returns:
        `(b - a) . ((c - a) x (d - a)) / 6`. It is positive when `d` is on
        the side of the face `a b c` that its normal by the right hand
        points to.
    """
    return dot(b - a, cross(c - a, d - a)) / 6.0


struct TetMesh(Copyable, Movable):
    """Nodes and four-node tetrahedra."""

    var nodes: List[V3]
    """The node positions, in meters."""
    var corners: List[Int]
    """The node indexes of each element, element by element: four for a
    linear mesh, ten for a quadratic one."""
    var materials: List[Int]
    """The material index of each element."""
    var order: ElementOrder
    """`LINEAR` or `QUADRATIC`."""

    def __init__(out self):
        """Create an empty linear mesh."""
        self.nodes = List[V3]()
        self.corners = List[Int]()
        self.materials = List[Int]()
        self.order = LINEAR

    def nodes_per_element(self) -> Int:
        """Return how many nodes each element has.

        Returns:
            4 for a linear mesh and 10 for a quadratic one.
        """
        return self.order.nodes()

    def node_count(self) -> Int:
        """Return how many nodes the mesh holds.

        Returns:
            The node count.
        """
        return len(self.nodes)

    def element_count(self) -> Int:
        """Return how many elements the mesh holds.

        Returns:
            The element count.
        """
        return len(self.materials)

    def add_node(mut self, position: V3) raises -> NodeId:
        """Add a node.

        Args:
            position: Its place, in meters.

        Returns:
            The new node.

        Raises:
            Error: If a coordinate is not finite.
        """
        if not isfinite(position.x + position.y + position.z):
            raise Error("A node needs a finite position")
        self.nodes.append(position)
        return NodeId(len(self.nodes) - 1)

    def require_node(self, node: NodeId) raises:
        """Refuse a node id that names no node.

        Args:
            node: The node.

        Raises:
            Error: If the id is negative or past the last node.
        """
        require_id(node.is_valid(), node.value, len(self.nodes), "node")

    def require_element(self, element: ElementId) raises:
        """Refuse an element id that names no element.

        Args:
            element: The element.

        Raises:
            Error: If the id is negative or past the last element.
        """
        require_id(
            element.is_valid(), element.value, len(self.materials), "element"
        )

    def add_element(
        mut self,
        a: NodeId,
        b: NodeId,
        c: NodeId,
        d: NodeId,
        material: MaterialId,
    ) raises -> ElementId:
        """Add a tetrahedron, turned so that its volume is positive.

        Args:
            a: The first corner.
            b: The second corner.
            c: The third corner.
            d: The fourth corner.
            material: Its material. The problem checks the upper bound.

        Returns:
            The new element.

        Raises:
            Error: If the mesh is quadratic, a node id names no node, the
                material id is negative, or the tetrahedron is flat.
        """
        if self.order != LINEAR:
            raise Error("add_element makes four-node elements of a linear mesh")
        self.require_node(a)
        self.require_node(b)
        self.require_node(c)
        self.require_node(d)
        if not material.is_valid():
            raise Error("A material id cannot be negative")
        var pa = self.nodes[a.value]
        var pb = self.nodes[b.value]
        var pc = self.nodes[c.value]
        var pd = self.nodes[d.value]
        var volume = signed_volume(pa, pb, pc, pd)
        var edges = (
            dot(pb - pa, pb - pa)
            + dot(pc - pa, pc - pa)
            + dot(pd - pa, pd - pa)
        )
        # A volume below a millionth of the edges' cube is flat.
        var scale = edges * (edges**0.5)
        if not (abs(volume) > 1.0e-6 * scale):
            raise Error("A tetrahedron needs four corners that are not flat")
        self.corners.append(a.value)
        self.corners.append(b.value)
        if volume > 0:
            self.corners.append(c.value)
            self.corners.append(d.value)
        else:
            self.corners.append(d.value)
            self.corners.append(c.value)
        self.materials.append(material.value)
        return ElementId(len(self.materials) - 1)

    def element_nodes(self, element: ElementId) raises -> List[Int]:
        """Return the node indexes of an element.

        Args:
            element: The element.

        Returns:
            The four corners, in an order with a positive volume, and for a
            quadratic mesh the six edge nodes after them: edges 0-1, 1-2,
            0-2, 0-3, 1-3 and 2-3.

        Raises:
            Error: If the id names no element.
        """
        self.require_element(element)
        var count = self.nodes_per_element()
        var out = List[Int]()
        for k in range(count):  # pragma: no branch
            out.append(self.corners[count * element.value + k])
        return out^

    def volume(self, element: ElementId) raises -> Volume64:
        """Return the volume of an element.

        Args:
            element: The element.

        Returns:
            Its volume.

        Raises:
            Error: If the id names no element.
        """
        var n = self.element_nodes(element)
        return Volume64(
            signed_volume(
                self.nodes[n[0]],
                self.nodes[n[1]],
                self.nodes[n[2]],
                self.nodes[n[3]],
            ),
            CUBIC_METER,
        )

    def total_volume(self) raises -> Volume64:
        """Return the volume of every element together.

        Returns:
            The sum of the element volumes.
        """
        var total = 0.0
        for e in range(self.element_count()):
            total += self.volume(ElementId(e)).value
        return Volume64(total, CUBIC_METER)

    def nodes_on_plane(
        self, axis: DofAxis, at: Length64, tolerance: Length64
    ) raises -> List[NodeId]:
        """Return the nodes whose coordinate on an axis is near a value.

        Args:
            axis: The axis.
            at: The coordinate of the plane.
            tolerance: How far a node can be from the plane.

        Returns:
            The nodes, in index order.

        Raises:
            Error: If the axis is not valid.
        """
        require_dof_axis(axis)
        var out = List[NodeId]()
        var target = at.to(METER)
        var reach = tolerance.to(METER)
        for index in range(len(self.nodes)):
            var p = self.nodes[index]
            var value = p.z
            if axis == DOF_X:
                value = p.x
            elif axis == DOF_Y:
                value = p.y
            if abs(value - target) <= reach:
                out.append(NodeId(index))
        return out^


def _add_cube(
    mut mesh: TetMesh, corner: List[Int], material: MaterialId
) raises:
    """Add the six tetrahedra of a cube whose corner `x + 2y + 4z` is
    `corner[x + 2y + 4z]`."""
    # The six orders of the axes give the six tetrahedra of a cube.
    var orders: List[Int] = [
        0,
        1,
        2,
        0,
        2,
        1,
        1,
        0,
        2,
        1,
        2,
        0,
        2,
        0,
        1,
        2,
        1,
        0,
    ]
    for t in range(6):  # pragma: no branch
        var at = 0
        var path = List[Int]()
        path.append(corner[0])
        for step in range(3):  # pragma: no branch
            at += 1 << orders[3 * t + step]
            path.append(corner[at])
        _ = mesh.add_element(
            NodeId(path[0]),
            NodeId(path[1]),
            NodeId(path[2]),
            NodeId(path[3]),
            material,
        )


def _require_cells(nx: Int, ny: Int, nz: Int) raises:
    """Refuse a cube count that is not positive or that is too large."""
    if nx < 1 or ny < 1 or nz < 1:
        raise Error("A box mesh needs at least one cube on each axis")
    if nx > MAX_MESH_ENTRIES // 6 // ny // nz:
        raise Error("A box mesh holds at most 2^24 elements")


def box_mesh(
    size_x: Length64,
    size_y: Length64,
    size_z: Length64,
    nx: Int,
    ny: Int,
    nz: Int,
) raises -> TetMesh:
    """Return a box from the origin to its size, filled with tetrahedra.

    Args:
        size_x: The length of the box on x.
        size_y: The length of the box on y.
        size_z: The length of the box on z.
        nx: Cubes along x. At least one.
        ny: Cubes along y. At least one.
        nz: Cubes along z. At least one.

    Returns:
        A mesh of `(nx + 1)(ny + 1)(nz + 1)` nodes and `6 nx ny nz`
        elements of material zero.

    Raises:
        Error: If a size is not positive and finite, or a count is out of
            range.
    """
    _require_cells(nx, ny, nz)
    var sx = size_x.to(METER)
    var sy = size_y.to(METER)
    var sz = size_z.to(METER)
    if not (sx > 0 and sy > 0 and sz > 0) or not isfinite(sx + sy + sz):
        raise Error("A box needs positive, finite sizes")
    var mesh = TetMesh()
    for k in range(nz + 1):  # pragma: no branch
        for j in range(ny + 1):  # pragma: no branch
            for i in range(nx + 1):  # pragma: no branch
                _ = mesh.add_node(
                    v3(
                        sx * Float64(i) / Float64(nx),
                        sy * Float64(j) / Float64(ny),
                        sz * Float64(k) / Float64(nz),
                    )
                )
    for k in range(nz):  # pragma: no branch
        for j in range(ny):  # pragma: no branch
            for i in range(nx):  # pragma: no branch
                var corner = List[Int]()
                for bit in range(8):
                    var x = i + (bit & 1)
                    var y = j + ((bit >> 1) & 1)
                    var z = k + ((bit >> 2) & 1)
                    corner.append(x + (nx + 1) * (y + (ny + 1) * z))
                _add_cube(mesh, corner, MaterialId(0))
    return mesh^


def voxel_mesh(map: LabelMap, label: LabelId) raises -> TetMesh:
    """Return the voxels of one label filled with tetrahedra.

    Voxel `(i, j, k)` is the box of one voxel around its center at
    `(i * spacing_x, j * spacing_y, k * spacing_z)`: the volume frame of
    the imaging extension. Voxels that touch share their nodes.

    Args:
        map: The label map.
        label: The label to mesh.

    Returns:
        A mesh of six elements of material zero for each voxel.

    Raises:
        Error: If the label is not valid or has no voxels.
    """
    return voxel_mesh_labels(map, [label])


def voxel_mesh_labels(map: LabelMap, labels: List[LabelId]) raises -> TetMesh:
    """Return the voxels of several labels filled with tetrahedra.

    Each label is a material: an element's material index is its label's
    place in `labels`. Voxels that touch share their nodes, across labels
    too, so the materials join at their interfaces.

    Args:
        map: The label map.
        labels: The labels to mesh, each once.

    Returns:
        A mesh of six elements for each voxel of the labels.

    Raises:
        Error: If the list is empty, a label is not valid or comes twice,
            or the labels have no voxels.
    """
    if len(labels) == 0:
        raise Error("A voxel mesh needs at least one label")
    var material = List[Int](length=256, fill=-1)
    for index in range(len(labels)):  # pragma: no branch
        require_label(labels[index])
        if material[labels[index].value] >= 0:
            raise Error("A label can only be meshed once")
        material[labels[index].value] = index
    var sx = map.spacing_x.to(METER)
    var sy = map.spacing_y.to(METER)
    var sz = map.spacing_z.to(METER)
    var px = map.nx + 1
    var py = map.ny + 1
    var node_of = List[Int](length=px * py * (map.nz + 1), fill=-1)
    var mesh = TetMesh()
    for k in range(map.nz):  # pragma: no branch
        for j in range(map.ny):  # pragma: no branch
            for i in range(map.nx):  # pragma: no branch
                var which = material[Int(map.labels[map.index(i, j, k)])]
                if which < 0:
                    continue
                var corner = List[Int]()
                for bit in range(8):
                    var x = i + (bit & 1)
                    var y = j + ((bit >> 1) & 1)
                    var z = k + ((bit >> 2) & 1)
                    var key = x + px * (y + py * z)
                    if node_of[key] < 0:
                        node_of[key] = mesh.add_node(
                            v3(
                                (Float64(x) - 0.5) * sx,
                                (Float64(y) - 0.5) * sy,
                                (Float64(z) - 0.5) * sz,
                            )
                        ).value
                    corner.append(node_of[key])
                _add_cube(mesh, corner, MaterialId(which))
    if mesh.element_count() == 0:
        raise Error("The labels have no voxels")
    return mesh^


def boundary_faces(mesh: TetMesh) -> List[Int]:
    """Return the faces that only one element has.

    Args:
        mesh: The mesh.

    Returns:
        Four numbers per face: three node indexes, ordered so that the
        face's normal by the right hand points out of its element, and the
        element.
    """
    # The faces of a tetrahedron `0 1 2 3` that face out of it, each
    # followed by the corner it leaves out.
    var table: List[Int] = [1, 2, 3, 0, 0, 3, 2, 1, 0, 1, 3, 2, 0, 2, 1, 3]
    var keys = List[Tuple[Int, Int, Int]]()
    var faces = List[Int]()
    for e in range(mesh.element_count()):
        for f in range(4):
            var at = mesh.nodes_per_element() * e
            var a = mesh.corners[at + table[4 * f]]
            var b = mesh.corners[at + table[4 * f + 1]]
            var c = mesh.corners[at + table[4 * f + 2]]
            keys.append(_sorted(a, b, c))
            faces.append(a)
            faces.append(b)
            faces.append(c)
            faces.append(e)
    var order = _sort_keys(keys)
    var out = List[Int]()
    var at = 0
    while at < len(order):
        var next = at + 1
        while next < len(order) and keys[order[next]] == keys[order[at]]:
            next += 1
        if next - at == 1:
            var face = order[at]
            for part in range(4):
                out.append(faces[4 * face + part])
        at = next
    return out^


def edge_pairs() -> List[Int]:
    """Return the corner pairs of the six edges of a tetrahedron.

    Returns:
        Twelve corner indexes, two for each edge: 0-1, 1-2, 0-2, 0-3, 1-3
        and 2-3. Edge `k` has its node at index `4 + k` of a quadratic
        element.
    """
    return [0, 1, 1, 2, 0, 2, 0, 3, 1, 3, 2, 3]


def quadratic_mesh(mesh: TetMesh) raises -> TetMesh:
    """Return a linear mesh with a node added at the middle of each edge.

    Elements that share an edge share its node. The edges stay straight.

    Args:
        mesh: A linear mesh.

    Returns:
        A quadratic mesh of the same elements and materials.

    Raises:
        Error: If the mesh is already quadratic.
    """
    if mesh.order != LINEAR:
        raise Error("The mesh is already quadratic")
    var out = TetMesh()
    out.nodes = mesh.nodes.copy()
    out.materials = mesh.materials.copy()
    out.order = QUADRATIC
    var middles = Dict[Int, Int]()
    var count = mesh.node_count()
    var pairs = edge_pairs()
    for e in range(mesh.element_count()):
        for k in range(4):
            out.corners.append(mesh.corners[4 * e + k])
        for edge in range(6):
            var a = mesh.corners[4 * e + pairs[2 * edge]]
            var b = mesh.corners[4 * e + pairs[2 * edge + 1]]
            var key = min(a, b) * count + max(a, b)
            var node = middles.get(key, -1)
            if node < 0:
                node = len(out.nodes)
                out.nodes.append((mesh.nodes[a] + mesh.nodes[b]) * 0.5)
                middles[key] = node
            out.corners.append(node)
    return out^


def _sorted(a: Int, b: Int, c: Int) -> Tuple[Int, Int, Int]:
    """Return three indexes in increasing order."""
    var low = min(a, min(b, c))
    var high = max(a, max(b, c))
    return (low, a + b + c - low - high, high)


def _sort_keys(keys: List[Tuple[Int, Int, Int]]) -> List[Int]:
    """Return the indexes of `keys` sorted by key, by a merge sort."""
    var order = List[Int]()
    for index in range(len(keys)):
        order.append(index)
    var scratch = order.copy()
    var width = 1
    while width < len(order):
        var start = 0
        while start < len(order):
            var middle = min(start + width, len(order))
            var end = min(start + 2 * width, len(order))
            var i = start
            var j = middle
            for k in range(start, end):  # pragma: no branch
                if j >= end or (
                    i < middle and _before(keys[order[i]], keys[order[j]])
                ):
                    scratch[k] = order[i]
                    i += 1
                else:
                    scratch[k] = order[j]
                    j += 1
            start = end
        order = scratch.copy()
        width *= 2
    return order^


def _before(a: Tuple[Int, Int, Int], b: Tuple[Int, Int, Int]) -> Bool:
    """Return whether key `a` sorts no later than key `b`."""
    if a[0] != b[0]:
        return a[0] < b[0]
    if a[1] != b[1]:
        return a[1] < b[1]
    return a[2] <= b[2]
