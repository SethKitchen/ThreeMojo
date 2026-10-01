# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's `geom::BoundingBox`, from `LibCarla/source/carla/geom/BoundingBox.h`.

A bounding box is a center, a half size and a rotation, all in the local
frame of an actor. It is a thin CARLA-named layer over ThreeMojo's
`math.obb.OBB`: `to_obb` gives the oriented box, and `contains` asks the
oriented box. The layer keeps CARLA's names and CARLA's numbers.

**Differences from CARLA.**

- `contains` does not apply the box's own rotation. CARLA's `Contains`
  does not either: it moves the point into the frame of the transform,
  subtracts the center, and compares with the half size. This port keeps
  that.
- A half size must be finite and zero or more, as `OBB` requires. CARLA
  accepts any number, and a negative half size contains nothing.
"""

from extensions.carla.math import rotations_equal
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.matrix3 import Matrix3
from math.obb import OBB
from math.vector3 import Vector3
from units.si import DEGREE, Angle


def _no_rotation() -> CarlaRotation:
    return CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE))


struct BoundingBox(Equatable, ImplicitlyCopyable, Writable):
    """A box in an actor's local frame, CARLA's `geom::BoundingBox`."""

    # The center, in meters, in the local frame.
    var location: Vector3
    # Half the size along each of the box's axes, in meters.
    var extent: Vector3
    # The box's own rotation in the local frame.
    var rotation: CarlaRotation

    def __init__(
        out self, location: Vector3, extent: Vector3, rotation: CarlaRotation
    ) raises:
        """Create a box.

        Args:
            location: The center, in meters.
            extent: Half the size along each axis, in meters.
            rotation: The box's rotation.

        Raises:
            Error: If a half size is negative or not finite.
        """
        # `OBB` owns the check on the half size.
        _ = OBB(location, extent, Matrix3())
        self.location = location
        self.extent = extent
        self.rotation = rotation

    def __init__(out self, location: Vector3, extent: Vector3) raises:
        """Create a box with no rotation.

        Args:
            location: The center, in meters.
            extent: Half the size along each axis, in meters.

        Raises:
            Error: If a half size is negative or not finite.
        """
        self = BoundingBox(location, extent, _no_rotation())

    def __init__(out self, extent: Vector3) raises:
        """Create a box at the origin with no rotation.

        Args:
            extent: Half the size along each axis, in meters.

        Raises:
            Error: If a half size is negative or not finite.
        """
        self = BoundingBox(Vector3(0, 0, 0), extent, _no_rotation())

    def to_obb(self) raises -> OBB:
        """Return the same box as an `OBB`, in the local frame.

        Returns:
            An oriented box whose axes are the rotation's forward, right
            and up vectors. The box keeps CARLA's left-handed frame.

        Raises:
            Error: If the half size is not valid.
        """
        var f = self.rotation.forward_vector()
        var r = self.rotation.right_vector()
        var u = self.rotation.up_vector()
        var axes = Matrix3()
        axes.set(f.x, r.x, u.x, f.y, r.y, u.y, f.z, r.z, u.z)
        return OBB(self.location, self.extent, axes)

    def contains(
        self, world_point: Vector3, bbox_to_world: CarlaTransform
    ) raises -> Bool:
        """Return whether a world point is in the box, `Contains`.

        Args:
            world_point: The point, in the world frame.
            bbox_to_world: The transform from the box's frame to the world.

        Returns:
            Whether the point, moved into the box's frame, is within the
            half size of the center on every axis, faces included. The
            box's own rotation is not applied, as in CARLA.

        Raises:
            Error: If the half size is not valid.
        """
        var local = bbox_to_world.inverse_transform_point(world_point)
        return OBB(self.location, self.extent, Matrix3()).contains_point(local)

    def _corners(self) -> List[Vector3]:
        var e = self.extent
        var out = List[Vector3]()
        for sx in [-1, 1]:  # pragma: no branch
            for sy in [-1, 1]:  # pragma: no branch
                for sz in [-1, 1]:  # pragma: no branch
                    out.append(
                        Vector3(
                            Float32(sx) * e.x,
                            Float32(sy) * e.y,
                            Float32(sz) * e.z,
                        )
                    )
        return out^

    def local_vertices(self) -> List[Vector3]:
        """Return the eight corners in the local frame, `GetLocalVertices`.

        Returns:
            The corners, turned by the box's rotation and moved to its
            center, in CARLA's order: minus x first, then minus y, then
            minus z.
        """
        var out = List[Vector3]()
        for corner in self._corners():  # pragma: no branch
            out.append(self.location + self.rotation.rotate_vector(corner))
        return out^

    def local_vertices_no_rotation(self) -> List[Vector3]:
        """Return the eight corners without the box's rotation,
        `GetLocalVerticesNoRotation`.

        Returns:
            The corners moved to the center, in the order of
            `local_vertices`.
        """
        var out = List[Vector3]()
        for corner in self._corners():  # pragma: no branch
            out.append(self.location + corner)
        return out^

    def world_vertices(self, bbox_to_world: CarlaTransform) -> List[Vector3]:
        """Return the eight corners in the world frame, `GetWorldVertices`.

        Args:
            bbox_to_world: The transform from the box's frame to the world.

        Returns:
            `local_vertices`, each moved by the transform.
        """
        var out = List[Vector3]()
        for corner in self.local_vertices():  # pragma: no branch
            out.append(bbox_to_world.transform_point(corner))
        return out^

    def __eq__(self, other: Self) -> Bool:
        """Compare as CARLA does, `operator==`.

        Args:
            other: The other box.

        Returns:
            Whether the centers and half sizes are equal and the rotations
            are equal by `rotations_equal`.
        """
        return (
            self.location == other.location
            and self.extent == other.extent
            and rotations_equal(self.rotation, other.rotation)
        )

    def write_to(self, mut writer: Some[Writer]):
        """Write the box.

        Args:
            writer: The destination.
        """
        writer.write(
            "BoundingBox(location=(",
            self.location.x,
            ", ",
            self.location.y,
            ", ",
            self.location.z,
            "), extent=(",
            self.extent.x,
            ", ",
            self.extent.y,
            ", ",
            self.extent.z,
            "), ",
            self.rotation,
            ")",
        )
