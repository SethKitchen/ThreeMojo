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
`getObjectForDistance`: level zero shows below the second level's distance
whatever its own distance says, so a camera nearer than the first level's
distance still sees something. An `Lod` with no levels shows nothing.

**Hysteresis.** A camera hovering at a level's distance would flip the
level every frame, so three.js's `addLevel` takes a `hysteresis`, a
fraction of the level's distance: once a level is shown it keeps showing
until the camera comes that fraction nearer than its distance. That needs
a memory of which level is shown, three.js's `LOD.update`, which is
`update` here and `Scene.update_lods` for every LOD in a scene. The
renderer reads the memory and never writes it, so a scene that is never
updated shows the stateless choice and an LOD without hysteresis shows the
same level either way.

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
    # How much nearer than `distance`, as a fraction of it, the camera must
    # come before this level, once shown, gives way to the one before it.
    var hysteresis: Float32


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
    # The level `update` last chose, which is what its hysteresis is
    # measured against: three.js's `_currentLevel`. Zero before any update.
    var shown: Int

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
        self.shown = 0

    def count(self) -> Int:
        """Return how many levels there are."""
        return len(self.levels)

    def add_level(
        mut self,
        geometry: GeometryId,
        material: MaterialId,
        distance: Length = Length(0.0, METER),
        hysteresis: Float32 = 0,
    ) raises:
        """Add a level, three.js's `addLevel`, keeping the levels in order
        of distance. A level added at a distance another already has goes
        after it.

        Args:
            geometry: Id of the geometry to show from `distance` on.
            material: Id of the material to show it with.
            distance: How far the camera must be from the node for this
                level to show. Zero, the default, for the nearest level.
            hysteresis: How much nearer than `distance`, as a fraction of
                it from zero to one, the camera must come before this
                level, once shown, gives way. Zero, the default, flips at
                `distance` both ways.

        Raises:
            Error: If either id is negative, the distance is, or the
                hysteresis is not from zero to one.
        """
        if geometry.value < 0:
            raise Error("A level must name a geometry")
        if material.value < 0:
            raise Error("A level must name a material")
        if distance.value < 0:
            raise Error("A level's distance cannot be negative")
        if not (hysteresis >= 0 and hysteresis <= 1):
            raise Error("A level's hysteresis must be from zero to one")
        var slot = 0
        while (
            slot < len(self.levels)
            and self.levels[slot].distance.value <= distance.value
        ):
            slot += 1
        # The shown level is the same level after the insert, as three.js
        # keeps its visibility on the level's object.
        if len(self.levels) > 0 and slot <= self.shown:
            self.shown += 1
        self.levels.insert(
            slot, LodLevel(distance, geometry, material, hysteresis)
        )

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
        """Return which level shows from `distance` away with no memory,
        three.js's `getObjectForDistance`: the last whose distance has
        been reached, or the first when none has.

        Args:
            distance: How far the camera is from the node.

        Returns:
            The level's index, or -1 when there are no levels.
        """
        return self.level_from(distance, -1)

    def level_from(self, distance: Length, shown: Int) -> Int:
        """Return which level shows from `distance` away when `shown` is
        the level showing now: the choice three.js's `LOD.update` makes,
        without recording it.

        Each level from the second is reached at its distance, or at its
        distance less its hysteresis's share of it while it is the one
        shown. The level chosen is the last reached, and the first when
        none is.

        Args:
            distance: How far the camera is from the node.
            shown: Which level shows now, or -1 for none, which measures
                every level at its plain distance.

        Returns:
            The level's index, or -1 when there are no levels.
        """
        if len(self.levels) == 0:
            return -1
        var chosen = 0
        while chosen + 1 < len(self.levels):
            ref next = self.levels[chosen + 1]
            var reach = next.distance.value
            if chosen + 1 == shown:
                reach -= reach * next.hysteresis
            if distance.value < reach:
                break
            chosen += 1
        return chosen

    def update(mut self, distance: Length) -> Int:
        """Choose the level to show from `distance` away, three.js's
        `LOD.update`, and remember it for the next choice's hysteresis.

        Args:
            distance: How far the camera is from the node.

        Returns:
            The level's index, now `shown`, or -1 when there are no levels.
        """
        var chosen = self.level_from(distance, self.shown)
        if chosen >= 0:
            self.shown = chosen
        return chosen
