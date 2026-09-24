# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Levels of detail, from three.js `src/objects/LOD.js`.

A shape seen from far away covers a few pixels, and a few pixels do not
need ten thousand triangles. An `Lod` is a scene node with a list of
levels. Each level is any object: a scene node, with whatever it carries
and whatever hangs under it. A tree can be a full tree up close, a rough
one further off and a billboard beyond that.

The levels are children of the LOD's node, as three.js's `addLevel` makes
each object a child. `Scene.add_lod` and `Scene.add_lod_level` attach
them. Choosing a level shows it and hides the others, three.js's
`LOD.update`, which sets `visible` on each level's object. So the
renderer, the raycaster and the bounds need nothing of their own for an
LOD: they see the level that is shown, as they see any node.

The levels are kept in order of distance, as three.js keeps them, and the
level shown is the last whose distance the camera has reached, three.js's
`getObjectForDistance`: level zero shows below the second level's distance
whatever its own distance says, so a camera nearer than the first level's
distance still sees something. An `Lod` with no levels shows nothing.

**Hysteresis.** A camera hovering at a level's distance would flip the
level every frame, so three.js's `addLevel` takes a `hysteresis`, a
fraction of the level's distance: once a level is shown it keeps showing
until the camera comes that fraction nearer than its distance. three.js
remembers which level is shown in its objects' `visible` flags and in
`_currentLevel`; this remembers it in `shown`.

**Updating.** three.js's renderer calls `LOD.update(camera)` on every LOD
whose `autoUpdate` is set, as it draws. This renderer does not change the
scene it draws. Call `Scene.update_lods` with the camera's position before
a frame, as `Scene.update` is called; it updates every LOD whose
`auto_update` is set. A scene never updated shows level zero, which
`Scene.add_lod` shows and whose siblings it hides.

A level's distance is a `Length`. A bare number does not compile, and a
compile-fail file proves it. It is measured from the camera's position to
the node's world origin, in meters, and three.js's `camera.zoom` does not
divide it, since no camera here has one.
"""

from core.object3d import NodeId
from units.si import Length, METER


@fieldwise_init
struct LodLevel(ImplicitlyCopyable):
    """One level of detail: what to show from `distance` on."""

    var distance: Length
    # The node shown at this level, with everything under it: three.js's
    # `object`.
    var object: NodeId
    # How much nearer than `distance`, as a fraction of it, the camera must
    # come before this level, once shown, gives way to the one before it.
    var hysteresis: Float32


struct Lod(Copyable, Movable):
    """A scene node that shows one of several objects, by how far the
    camera is from it."""

    var node: NodeId
    # In order of distance, nearest first. Public to be read; add with
    # `add_level`, which keeps the order.
    var levels: List[LodLevel]
    # The level last chosen, which is what its hysteresis is measured
    # against: three.js's `_currentLevel`. Zero before any update.
    var shown: Int
    # Whether `Scene.update_lods` updates this LOD: three.js's
    # `autoUpdate`.
    var auto_update: Bool

    def __init__(out self, node: NodeId, *, auto_update: Bool = True) raises:
        """Start an LOD with no levels on a scene node.

        Args:
            node: Index of the scene node the levels hang from.
            auto_update: Whether `Scene.update_lods` updates it, three.js's
                `autoUpdate`. On by default, as there.

        Raises:
            Error: If the node index is negative.
        """
        if node.value < 0:
            raise Error("An LOD must name a scene node")
        self.node = node
        self.levels = List[LodLevel]()
        self.shown = 0
        self.auto_update = auto_update

    def count(self) -> Int:
        """Return how many levels there are."""
        return len(self.levels)

    def add_level(
        mut self,
        object: NodeId,
        distance: Length = Length(0.0, METER),
        hysteresis: Float32 = 0,
    ) raises:
        """Add a level, three.js's `addLevel`, keeping the levels in order
        of distance. A level added at a distance another already has goes
        after it.

        This records the level. `Scene.add_lod` and `Scene.add_lod_level`
        also make the object a child of the LOD's node, as three.js's
        `addLevel` does.

        Args:
            object: The node to show from `distance` on.
            distance: How far the camera must be from the node for this
                level to show. Zero, the default, for the nearest level.
            hysteresis: How much nearer than `distance`, as a fraction of
                it from zero to one, the camera must come before this
                level, once shown, gives way. Zero, the default, flips at
                `distance` both ways.

        Raises:
            Error: If the node id is negative, is the LOD's own node, or
                is a level already, the distance is negative, or the
                hysteresis is not from zero to one.
        """
        if object.value < 0:
            raise Error("A level must name a scene node")
        if object == self.node:
            raise Error("An LOD cannot be its own level")
        for level in self.levels:
            if level.object == object:
                raise Error("A node is one level of an LOD at most")
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
        self.levels.insert(slot, LodLevel(distance, object, hysteresis))

    def remove_level(mut self, distance: Length) -> Optional[NodeId]:
        """Remove the first level at a distance, three.js's `removeLevel`.

        `Scene.remove_lod_level` also takes the object out from under the
        LOD's node, as three.js's does.

        Args:
            distance: The level's distance, exactly.

        Returns:
            The removed level's node, or none when no level is at that
            distance. three.js returns true or false.
        """
        for index in range(len(self.levels)):
            if self.levels[index].distance.value == distance.value:
                var object = self.levels.pop(index).object
                if self.shown > index or self.shown >= len(self.levels):
                    self.shown = max(self.shown - 1, 0)
                return object
        return None

    def current_level(self) -> Int:
        """Return the level last chosen, three.js's `getCurrentLevel`."""
        return self.shown

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
        three.js's `getObjectForDistance` when no level has been hidden:
        the last whose distance has been reached, or the first when none
        has.

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

        `Scene.update_lods` calls this and then shows the level chosen and
        hides the others.

        Args:
            distance: How far the camera is from the node.

        Returns:
            The level's index, now `shown`, or -1 when there are no levels.
        """
        var chosen = self.level_from(distance, self.shown)
        if chosen >= 0:
            self.shown = chosen
        return chosen
