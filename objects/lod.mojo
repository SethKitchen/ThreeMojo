# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Levels of detail, from three.js `src/objects/LOD.js`.

A shape seen from far away covers a few pixels, and a few pixels do not
need ten thousand triangles. An `Lod` is a scene node with a list of
levels, each a geometry and a material to show from some distance on, and
the renderer shows the one level the camera's distance to the node picks,
each frame: three.js's `LOD.update`, folded into `Renderer.prepare`. A
tree can be a full tree up close, a rough one further off and a billboard
beyond that, and the scene holds one object.

The levels are kept in order of distance, as three.js keeps them, and the
level shown is the last whose distance the camera has reached, three.js's
`getCurrentLevel`: level zero shows below the second level's distance
whatever its own distance says, so a camera nearer than the first level's
distance still sees something. An `Lod` with no levels shows nothing.

A level's distance is a `Length`. A bare number does not compile, and a
compile-fail file proves it. It is measured from the camera's position to
the node's world origin, in meters, and three.js's `camera.zoom` does not
divide it, since no camera here has one.
"""

from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId
from units.si import Length, METER


@fieldwise_init
struct LodLevel(ImplicitlyCopyable):
    """One level of detail: what to show from `distance` on."""

    var distance: Length
    var geometry: GeometryId
    var material: MaterialId


struct Lod(Copyable, Movable):
    """A scene node that shows one of several geometries, by how far the
    camera is from it."""

    var node: NodeId
    # Whether the renderer may skip the shown level when its bounding
    # sphere, carried to world space, lies outside the camera's frustum.
    var frustum_culled: Bool
    # In order of distance, nearest first. Public to be read; add with
    # `add_level`, which keeps the order.
    var levels: List[LodLevel]

    def __init__(out self, node: NodeId, *, frustum_culled: Bool = True) raises:
        """Start an LOD with no levels on a scene node.

        Args:
            node: Index of the scene node the levels are drawn at.
            frustum_culled: Whether the renderer may skip the shown level
                when its bounds are out of view.

        Raises:
            Error: If the node index is negative.
        """
        if node.value < 0:
            raise Error("An LOD must name a scene node")
        self.node = node
        self.frustum_culled = frustum_culled
        self.levels = List[LodLevel]()

    def count(self) -> Int:
        """Return how many levels there are."""
        return len(self.levels)

    def add_level(
        mut self,
        geometry: GeometryId,
        material: MaterialId,
        distance: Length = Length(0.0, METER),
    ) raises:
        """Add a level, three.js's `addLevel`, keeping the levels in order
        of distance. A level added at a distance another already has goes
        after it.

        Args:
            geometry: Id of the geometry to show from `distance` on.
            material: Id of the material to show it with.
            distance: How far the camera must be from the node for this
                level to show. Zero, the default, for the nearest level.

        Raises:
            Error: If either id is negative, or the distance is.
        """
        if geometry.value < 0:
            raise Error("A level must name a geometry")
        if material.value < 0:
            raise Error("A level must name a material")
        if distance.value < 0:
            raise Error("A level's distance cannot be negative")
        var slot = 0
        while (
            slot < len(self.levels)
            and self.levels[slot].distance.value <= distance.value
        ):
            slot += 1
        self.levels.insert(slot, LodLevel(distance, geometry, material))

    def level_at(self, index: Int) raises -> LodLevel:
        """Return one level, in order of distance.

        Args:
            index: Which level, from zero at the nearest.

        Returns:
            The level.

        Raises:
            Error: If there is no such level.
        """
        if index < 0 or index >= len(self.levels):
            raise Error("No level has that index")
        return self.levels[index]

    def level_for(self, distance: Length) -> Int:
        """Return which level shows from `distance` away, three.js's
        `getCurrentLevel`: the last whose distance has been reached, or
        the first when none has.

        Args:
            distance: How far the camera is from the node.

        Returns:
            The level's index, or -1 when there are no levels.
        """
        if len(self.levels) == 0:
            return -1
        var chosen = 0
        while (
            chosen + 1 < len(self.levels)
            and distance.value >= self.levels[chosen + 1].distance.value
        ):
            chosen += 1
        return chosen
