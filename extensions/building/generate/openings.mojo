# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Doors and windows for an assembled building model.

`add_doors` gives each room one door into a corridor or a lobby on its
storey, in the longest wall it shares with one. A room with no such wall,
or with one too short for a door, gets a door into the neighbor it shares
its longest doorless wall with, as a room of a suite. A lobby gets a
double-width entrance in its longest outside wall.

`add_windows` puts a row of windows in every outside wall, one per bay.
The bays divide the wall evenly into the fewest bays no wider than the
bay width. Each window leaves a pier between it and the next.

Both read the shared faces of the cell complex, so a door always joins
the two rooms whose wall it is in.
"""

from std.math import isfinite
from extensions.building.construction import Glazing
from extensions.building.ids import ElementId, SpaceId
from extensions.building.kinds import (
    CORRIDOR,
    DOOR,
    LOBBY,
    SpaceUse,
    WALL,
    WINDOW,
)
from extensions.building.model import Building
from extensions.topology.ids import CellId, FaceId
from units.si import Length64, METER


@fieldwise_init
struct WindowOptions(ImplicitlyCopyable):
    """The row of windows `add_windows` cuts in each outside wall."""

    var bay: Length64
    var pier: Length64
    var sill: Length64
    var height: Length64
    var glazing: Glazing

    def check(self) raises:
        """Refuse a row no wall can hold.

        Raises:
            Error: If a size is not positive and finite, the sill is
                negative, or the pier is not narrower than the bay.
        """
        var bay = self.bay.to(METER)
        var pier = self.pier.to(METER)
        var sill = self.sill.to(METER)
        var height = self.height.to(METER)
        if not (
            bay > 0
            and pier > 0
            and height > 0
            and isfinite(bay + pier + height)
        ):
            raise Error("Window sizes must be positive and finite")
        if not (sill >= 0 and isfinite(sill)):
            raise Error("A window sill must be zero or more and finite")
        if pier >= bay:
            raise Error("A pier must be narrower than its bay")
        self.glazing.check()


def _is_hall(use: SpaceUse) -> Bool:
    """Return True for a space that rooms open onto."""
    return use == CORRIDOR or use == LOBBY


def _longest_wall(
    building: Building, faces: List[FaceId]
) raises -> Optional[ElementId]:
    """Return the wall element of the longest wall face in a list."""
    var best = Optional[ElementId](None)
    var best_length = Float64(0)
    for i in range(len(faces)):
        var element = building.element_of_face(faces[i])
        if not element:
            continue
        var id = element.value()
        if building.elements[id.value].kind != WALL:
            continue
        var length = building.wall_frame(id).length
        if length > best_length:
            best_length = length
            best = id
    return best


def _door(
    mut building: Building, wall: ElementId, width: Float64, height: Float64
) raises -> Bool:
    """Add a door at the middle of a wall, if it fits. Return whether it
    was added."""
    var frame = building.wall_frame(wall)
    if frame.length < width + 0.2 or frame.height < height:
        return False
    _ = building.add_opening(
        DOOR,
        wall,
        Length64((frame.length - width) / 2, METER),
        Length64(0, METER),
        Length64(width, METER),
        Length64(height, METER),
        None,
    )
    return True


def add_doors(
    mut building: Building, width: Length64, height: Length64
) raises -> Int:
    """Give every room a door, and every lobby an entrance.

    Args:
        building: The model. Its walls must have no openings where the
            doors go.
        width: The door width.
        height: The door height.

    Returns:
        The number of doors added.

    Raises:
        Error: If a size is not positive and finite, or a door overlaps an
            opening already in its wall.
    """
    var w = width.to(METER)
    var h = height.to(METER)
    if not (w > 0 and h > 0 and isfinite(w) and isfinite(h)):
        raise Error("A door's size must be positive and finite")
    var added = 0
    for s in range(len(building.spaces)):
        var use = building.spaces[s].use
        var cell = building.spaces[s].cell
        if _is_hall(use):
            if use == LOBBY:
                var outside = _longest_wall(
                    building, building.topology.complex.exterior_faces(cell)
                )
                if outside and _door(building, outside.value(), w * 2, h):
                    added += 1
            continue
        # The longest wall into a hall, else the longest wall into a
        # neighbor on the storey that has no door in it yet.
        var hall_faces = List[FaceId]()
        var neighbor_faces = List[FaceId]()
        var neighbors = building.space_neighbors(SpaceId(s))
        for k in range(len(neighbors)):
            var other = neighbors[k].value
            if building.spaces[other].storey != building.spaces[s].storey:
                continue
            var shared = building.topology.complex.shared_faces(
                cell, building.spaces[other].cell
            )
            for f in range(len(shared)):  # pragma: no branch
                if _is_hall(building.spaces[other].use):
                    hall_faces.append(shared[f])
                elif not _has_opening(building, shared[f]):
                    neighbor_faces.append(shared[f])
        var placed = False
        var wall = _longest_wall(building, hall_faces)
        if wall:
            placed = _door(building, wall.value(), w, h)
        if not placed:
            var other_wall = _longest_wall(building, neighbor_faces)
            if other_wall:
                placed = _door(building, other_wall.value(), w, h)
        if placed:
            added += 1
    return added


def _has_opening(building: Building, face: FaceId) raises -> Bool:
    """Return True if the wall on a face has an opening.

    Only a door opens a wall between two rooms: windows go in outside walls.
    """
    var element = building.element_of_face(face)
    if not element:
        return False
    return len(building.openings_of(element.value())) > 0


def add_windows(mut building: Building, options: WindowOptions) raises -> Int:
    """Cut a row of windows in every outside wall.

    Args:
        building: The model.
        options: The bay, the pier, the sill, the height and the glazing.

    Returns:
        The number of windows added.

    Raises:
        Error: If the options are not valid.
    """
    options.check()
    var bay = options.bay.to(METER)
    var pier = options.pier.to(METER)
    var sill = options.sill.to(METER)
    var height = options.height.to(METER)
    var added = 0
    for e in range(len(building.elements)):
        if building.elements[e].kind != WALL:
            continue
        var id = ElementId(e)
        if not building.is_exterior(id):
            continue
        var frame = building.wall_frame(id)
        if sill + height > frame.height:
            continue
        var count = Int(frame.length / bay)
        if Float64(count) * bay < frame.length:
            count += 1
        var spacing = frame.length / Float64(count)
        var width = spacing - pier
        if width <= 0.3:
            continue
        var doors = building.openings_of(id)
        for k in range(count):  # pragma: no branch
            var offset = Float64(k) * spacing + pier / 2
            # Leave out a window that would cut a door.
            var clear = True
            for d in range(len(doors)):
                ref door = building.openings[doors[d].value]
                var start = door.offset.to(METER)
                var end = start + door.width.to(METER)
                if offset < end and start < offset + width:
                    clear = False
            if not clear:
                continue
            _ = building.add_opening(
                WINDOW,
                id,
                Length64(offset, METER),
                Length64(sill, METER),
                Length64(width, METER),
                Length64(height, METER),
                options.glazing,
            )
            added += 1
    return added
