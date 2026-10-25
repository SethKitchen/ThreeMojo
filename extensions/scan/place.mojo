# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Where a scan stands in a scene: its frame as a node's transform.

A `ScanFrame` maps a scan's coordinates to a building's: meters, z up and
+y north. A scene of the renderer has y up. So its x is the building's x
(east), its y is the building's z (up) and its z is the building's -y
(south).

`scan_placement` turns the frame, with its heading, into the rotation, the
uniform scale and the position of one `Object3D`. The scan's splats then
stand in the scene in meters, with the scan's origin at the scene's origin
and the scan's up along the scene's +y. Move the node to put the scan
anywhere else: a scanned church on a village green, or a hall beside a
tower.
"""

from core.object3d import Object3D
from extensions.scan.frame import ScanFrame
from generators.utils import Vec3d
from math.matrix4 import basis
from math.quaternion import Quaternion
from math.vector3 import Vector3


@fieldwise_init
struct ScanPlacement(ImplicitlyCopyable):
    """The rotation, scale and position that stand a scan in a scene."""

    var rotation: Quaternion
    """The turn from the scan's axes to the scene's."""
    var scale: Float32
    """The meters in one scan unit."""
    var position: Vector3
    """Where the scan's origin stands in the scene, in meters."""

    def apply(self, mut node: Object3D):
        """Give a node this placement.

        Args:
            node: The node that holds the scan's splats.
        """
        node.set_quaternion(self.rotation)
        node.set_scale(self.scale, self.scale, self.scale)
        node.set_position(self.position.x, self.position.y, self.position.z)

    def to_scene(self, point: Vec3d) -> Vector3:
        """Return a scan point in the scene, in meters.

        Args:
            point: The point, in scan units.

        Returns:
            Where the node puts it.
        """
        var scaled = Vector3(
            Float32(point.x) * self.scale,
            Float32(point.y) * self.scale,
            Float32(point.z) * self.scale,
        )
        return self.rotation.rotate(scaled) + self.position


def _scene_point(building: Vec3d) -> Vector3:
    """Return a building point in the scene's axes.

    Args:
        building: A point with x east, y north and z up.

    Returns:
        The point with x east, y up and z south.
    """
    return Vector3(
        Float32(building.x), Float32(building.z), Float32(-building.y)
    )


def scan_placement(frame: ScanFrame) raises -> ScanPlacement:
    """Return the placement that a frame gives a scan in a scene.

    Args:
        frame: The scan's frame.

    Returns:
        The placement. A scan point `p` is at `rotation * (scale * p) +
        position` in the scene, which is the frame's building point in
        meters, with its axes turned to the scene's.

    Raises:
        Error: If the frame is not valid.
    """
    frame.check()
    var map = frame.map()
    var origin = map.place(Vec3d(0, 0, 0))
    var unit = Float32(map.unit)
    # Each scan axis, as the scene's unit vector that it becomes.
    var columns = List[Vector3]()
    for axis in range(3):
        var step = Vec3d(frame.origin.x, frame.origin.y, frame.origin.z)
        if axis == 0:
            step.x += 1
        elif axis == 1:
            step.y += 1
        else:
            step.z += 1
        var turned = _scene_point(map.place(step)) / unit
        columns.append(turned)
    var rotation = Quaternion.from_matrix(
        basis(columns[0], columns[1], columns[2])
    )
    return ScanPlacement(rotation, unit, _scene_point(origin))
