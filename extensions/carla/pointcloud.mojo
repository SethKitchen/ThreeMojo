# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's point cloud writer, `pointcloud::PointCloudIO`, from
`LibCarla/source/carla/pointcloud/PointCloudIO.h`.

A LiDAR measurement's `save_to_disk` writes an ASCII PLY file: the
header, then one line a detection with four digits after the point. The
detection says what its properties are and how to write itself, as
CARLA's `WritePlyHeaderInfo` and `WriteDetection` do. `LidarDetection`
and `SemanticLidarDetection` are CARLA's two, from
`sensor/data/LidarData.h` and `SemanticLidarData.h`. Another detection
type conforms to `PlyDetection`.

ThreeMojo's `exporters.ply.export_ply` writes three.js's PLY from a
scene: `x`, `y` and `z`, and optional normals, UVs and colors. It has no
way to write CARLA's `I`, `CosAngle`, `ObjIdx` and `ObjTag` properties,
so this module writes the file itself. Numbers are written as C's
`%.4f`, with `extensions.carla.mesh.format_fixed`.

**Differences from CARLA.** The header of an empty cloud is written from
the type. CARLA reads the first detection for it, which is past the end
of an empty list.
"""

from extensions.carla.lidar import LidarPoint
from extensions.carla.mesh import format_fixed
from math.vector3 import Vector3
from std.os import makedirs
from std.os.path import dirname, exists
from std.pathlib import Path


trait PlyDetection(ImplicitlyCopyable):
    """A detection that CARLA's PLY writer can write."""

    @staticmethod
    def ply_header_info() -> String:
        """Return the `property` lines, `WritePlyHeaderInfo`.

        Returns:
            The lines, with no line break after the last.
        """
        ...

    def write_detection(self, mut out: String) raises:
        """Append this detection's numbers, `WriteDetection`.

        Args:
            out: The text to append to. No line break is written.

        Raises:
            Error: If a number cannot be written.
        """
        ...


@fieldwise_init
struct LidarDetection(PlyDetection):
    """A LiDAR point and its intensity, CARLA's `LidarDetection`."""

    # In meters, in the sensor's frame.
    var point: Vector3
    var intensity: Float32

    @staticmethod
    def from_lidar_point(point: LidarPoint) -> LidarDetection:
        """Take a point of `extensions.carla.lidar.scan_lidar`.

        Args:
            point: The point.

        Returns:
            Its location and intensity.
        """
        return LidarDetection(point.point, point.intensity)

    @staticmethod
    def ply_header_info() -> String:
        """Return CARLA's four `property float32` lines.

        Returns:
            The lines for `x`, `y`, `z` and `I`.
        """
        return (
            "property float32 x\nproperty float32 y\nproperty float32 z\n"
            "property float32 I"
        )

    def write_detection(self, mut out: String) raises:
        """Append `x y z I`.

        Args:
            out: The text to append to.

        Raises:
            Error: If a number cannot be written.
        """
        out += (
            format_fixed(self.point.x, 4)
            + " "
            + format_fixed(self.point.y, 4)
            + " "
            + format_fixed(self.point.z, 4)
            + " "
            + format_fixed(self.intensity, 4)
        )


@fieldwise_init
struct SemanticLidarDetection(PlyDetection):
    """A semantic LiDAR point, CARLA's `SemanticLidarDetection`."""

    # In meters, in the sensor's frame.
    var point: Vector3
    # The cosine of the angle between the ray and the surface normal.
    var cos_inc_angle: Float32
    # The index of the object hit, and its semantic tag.
    var object_idx: UInt32
    var object_tag: UInt32

    @staticmethod
    def ply_header_info() -> String:
        """Return CARLA's six `property` lines.

        Returns:
            The lines for `x`, `y`, `z`, `CosAngle`, `ObjIdx` and `ObjTag`.
        """
        return (
            "property float32 x\nproperty float32 y\nproperty float32 z\n"
            "property float32 CosAngle\nproperty uint32 ObjIdx\n"
            "property uint32 ObjTag"
        )

    def write_detection(self, mut out: String) raises:
        """Append `x y z CosAngle ObjIdx ObjTag`.

        Args:
            out: The text to append to.

        Raises:
            Error: If a number cannot be written.
        """
        out += (
            format_fixed(self.point.x, 4)
            + " "
            + format_fixed(self.point.y, 4)
            + " "
            + format_fixed(self.point.z, 4)
            + " "
            + format_fixed(self.cos_inc_angle, 4)
            + " "
            + String(self.object_idx)
            + " "
            + String(self.object_tag)
        )


def dump[T: PlyDetection](points: List[T]) raises -> String:
    """Write detections as an ASCII PLY file, `PointCloudIO::Dump`.

    Args:
        points: The detections.

    Returns:
        The text: `ply`, `format ascii 1.0`, `element vertex` and the
        count, the detection's properties, `end_header`, then one line a
        detection.

    Raises:
        Error: If a number cannot be written.
    """
    var out = String(
        "ply\nformat ascii 1.0\nelement vertex " + String(len(points)) + "\n"
    )
    out += T.ply_header_info()
    out += "\nend_header\n"
    for point in points:
        point.write_detection(out)
        out += "\n"
    return out^


def validate_file_path(path: String, extension: String) raises -> String:
    """Fix a file's extension and make its folder,
    `FileSystem::ValidateFilePath`.

    Args:
        path: The file path.
        extension: The extension it must have, with its dot, or empty.

    Returns:
        The path with its extension replaced when it differs, as
        `std::filesystem::path::replace_extension` does. The folder that
        will hold it exists afterward.

    Raises:
        Error: If the folder cannot be made.
    """
    var out = path
    if extension != "":
        var slash = path.rfind("/")
        var name = String(path[byte = slash + 1 :])
        var dot = name.rfind(".")
        var current = String()
        if dot > 0 and name != "..":
            current = String(name[byte=dot:])
        if current != extension:
            out = String(
                path[byte = : path.byte_length() - current.byte_length()]
            )
            out += extension
    var folder = dirname(out)
    if folder != "" and not exists(folder):
        makedirs(folder)
    return out^


def save_to_disk[
    T: PlyDetection
](path: String, points: List[T]) raises -> String:
    """Write detections to a PLY file, `PointCloudIO::SaveToDisk`.

    Args:
        path: The file path. Its extension becomes `.ply`.
        points: The detections.

    Returns:
        The path written.

    Raises:
        Error: If the file cannot be written.
    """
    var target = validate_file_path(path, ".ply")
    Path(target).write_text(dump(points))
    return target^
