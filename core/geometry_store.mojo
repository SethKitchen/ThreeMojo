# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The owner of every geometry in a scene.

three.js lets a `Mesh` hold a reference to a `BufferGeometry`, and two meshes
holding the same one is ordinary: a forest is one tree geometry drawn at two
hundred transforms. Mojo has no shared references to hand out, so the geometry
has to live somewhere that outlives every mesh — here — and meshes name it by
index.

That is the same trade `core.scene` makes for nodes, for the same reason, and
it answers the same question: who owns this buffer? Exactly one thing does, and
a `Mesh` is three integers and a colour rather than a copy of a vertex array.
`Mesh` used to take its geometry by value, so the comment promising that "one
geometry can be drawn at many nodes without being copied" was not true of the
code beneath it.

Storage is append-only. Nothing here reference-counts, reuses an id, or
collects anything, because nothing yet removes a geometry — and an id that can
never dangle needs no generation counter to prove it. When deletion arrives,
that is the moment to add one, not before.
"""

from core.buffer_geometry import BufferGeometry


@fieldwise_init
struct GeometryId(Equatable, ImplicitlyCopyable, Writable):
    """Which geometry in a `GeometryStore`, as a type rather than a bare int.

    An index, not a pointer, and not interchangeable with the other three
    small integers a `Mesh` carries. See `core.object3d.NodeId`.
    """

    var value: Int


struct GeometryStore(Movable):
    """Owns geometries and hands out ids naming them."""

    var geometries: List[BufferGeometry]

    def __init__(out self):
        """Create an empty store."""
        self.geometries = List[BufferGeometry]()

    def count(self) -> Int:
        """Return how many geometries the store holds."""
        return len(self.geometries)

    def add(mut self, var geometry: BufferGeometry) -> GeometryId:
        """Take ownership of `geometry` and return the id naming it.

        Args:
            geometry: The geometry to store; moved in, not copied.

        Returns:
            Its id, which stays valid for the life of the store.
        """
        self.geometries.append(geometry^)
        return GeometryId(len(self.geometries) - 1)

    def get(
        self, id: GeometryId
    ) raises -> ref[origin_of(self.geometries[0])] BufferGeometry:
        """Return a borrowed view of the geometry with that id.

        Copies nothing. As with `BufferGeometry.attribute_view`, binding the
        result with `var` is a compile error rather than a silent copy of
        every vertex; bind it with `ref`.

        Args:
            id: Which geometry to read.

        Returns:
            A reference to it, valid as long as the store is.

        Raises:
            Error: If no geometry has that id.
        """
        if id.value < 0 or id.value >= len(self.geometries):
            raise Error("No geometry has that id")
        return self.geometries[id.value]
