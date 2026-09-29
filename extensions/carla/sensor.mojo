# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's camera encodings and pinhole intrinsics.

A CARLA depth camera writes planar depth into 24 bits of RGB: red is the
low byte and blue the high byte, and full scale is 1000 meters.
`ColorConverter::LogarithmicLinear` maps a normalized depth to a gray.
A semantic camera writes a tag into red. `CityScapesPalette` gives each
tag a color.

`CameraIntrinsics` is the K matrix that CARLA's PythonAPI examples build
from an image size and a horizontal field of view. The camera frame is
OpenCV's: x right, y down, z forward. From a CARLA camera's local frame
that is (y, -z, x).
"""

from extensions.carla.transform import CarlaTransform
from math.vector3 import Vector3
from render.framebuffer import Color
from std.math import log, tan
from units.si import Angle, Length, METER, RADIAN


@fieldwise_init
struct SemanticTag(Equatable, ImplicitlyCopyable, Writable):
    """A CARLA semantic tag, `CityObjectLabel`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the palette has a color for this tag."""
        return self.value >= 0 and self.value < 30


comptime UNLABELED = SemanticTag(0)
comptime ROAD = SemanticTag(1)
comptime SIDEWALK = SemanticTag(2)
comptime BUILDING = SemanticTag(3)
comptime WALL = SemanticTag(4)
comptime FENCE = SemanticTag(5)
comptime POLE = SemanticTag(6)
comptime TRAFFIC_LIGHT = SemanticTag(7)
comptime TRAFFIC_SIGN = SemanticTag(8)
comptime VEGETATION = SemanticTag(9)
comptime TERRAIN = SemanticTag(10)
comptime SKY = SemanticTag(11)
comptime PEDESTRIAN = SemanticTag(12)
comptime RIDER = SemanticTag(13)
comptime CAR = SemanticTag(14)
comptime TRUCK = SemanticTag(15)
comptime BUS = SemanticTag(16)
comptime TRAIN = SemanticTag(17)
comptime MOTORCYCLE = SemanticTag(18)
comptime BICYCLE = SemanticTag(19)
comptime STATIC = SemanticTag(20)
comptime DYNAMIC = SemanticTag(21)
comptime OTHER_OBJECT = SemanticTag(22)
comptime WATER = SemanticTag(23)
comptime ROAD_LINE = SemanticTag(24)
comptime GROUND = SemanticTag(25)
comptime BRIDGE = SemanticTag(26)
comptime RAIL_TRACK = SemanticTag(27)
comptime GUARD_RAIL = SemanticTag(28)
comptime ROCK = SemanticTag(29)

# `CITYSCAPES_PALETTE_MAP`, red, green and blue per tag.
comptime _PALETTE: Array[Int, 90] = [
    0, 0, 0,
    128, 64, 128,
    244, 35, 232,
    70, 70, 70,
    102, 102, 156,
    190, 153, 153,
    153, 153, 153,
    250, 170, 30,
    220, 220, 0,
    107, 142, 35,
    152, 251, 152,
    70, 130, 180,
    220, 20, 60,
    255, 0, 0,
    0, 0, 142,
    0, 0, 70,
    0, 60, 100,
    0, 80, 100,
    0, 0, 230,
    119, 11, 32,
    110, 190, 160,
    170, 120, 50,
    55, 90, 80,
    45, 60, 150,
    157, 234, 50,
    81, 0, 81,
    150, 100, 100,
    230, 150, 140,
    180, 165, 180,
    180, 130, 70,
]  # fmt: skip


def cityscapes_color(tag: SemanticTag) raises -> Color:
    """Return a tag's color, `CityScapesPalette::GetColor`.

    Args:
        tag: The semantic tag.

    Returns:
        The opaque palette color.

    Raises:
        Error: If `tag` is not valid. CARLA wraps such a tag around the
            palette. This port refuses it.
    """
    if not tag.is_valid():
        raise Error("Semantic tag is not valid")
    var palette = materialize[_PALETTE]()
    var i = tag.value * 3
    return Color(
        UInt8(palette[i]), UInt8(palette[i + 1]), UInt8(palette[i + 2])
    )


# The depth that fills all 24 bits.
comptime DEPTH_FAR = Length(1000.0, METER)
comptime _DEPTH_STEPS = 16777215.0


def encode_depth(depth: Length) -> Color:
    """Pack a planar depth into RGB, as a CARLA depth camera does.

    Args:
        depth: Distance along the camera's forward axis. It is clamped to
            0 through `DEPTH_FAR`.

    Returns:
        Red is the low byte, green the middle byte and blue the high byte.
    """
    var normalized = min(max(Float64(depth.value) / 1000.0, 0.0), 1.0)
    var code = Int(normalized * _DEPTH_STEPS + 0.5)
    return Color(
        UInt8(code & 255), UInt8((code >> 8) & 255), UInt8((code >> 16) & 255)
    )


def normalized_depth(color: Color) -> Float32:
    """Unpack a depth color to 0 through 1, `ColorConverter::Depth`.

    Args:
        color: A depth camera's pixel.

    Returns:
        (R + G 256 + B 65536) / (2^24 - 1).
    """
    var code = Int(color.r) + Int(color.g) * 256 + Int(color.b) * 65536
    return Float32(Float64(code) / _DEPTH_STEPS)


def decode_depth(color: Color) -> Length:
    """Unpack a depth color to meters.

    Args:
        color: A depth camera's pixel.

    Returns:
        The planar depth.
    """
    return Length(normalized_depth(color) * 1000.0, METER)


def logarithmic_gray(normalized: Float32) -> Float32:
    """Map a normalized depth to a gray, `LogarithmicLinear`.

    Args:
        normalized: Depth from 0 through 1.

    Returns:
        1 + ln(depth) / 5.70378, clamped to 0.005 through 1.
    """
    if not (normalized > 0.0):
        return 0.005
    var value = 1.0 + log(normalized) / 5.70378
    return min(max(value, 0.005), 1.0)


struct CameraIntrinsics(ImplicitlyCopyable):
    """A pinhole camera's K matrix, as CARLA's PythonAPI builds it."""

    var width: Int
    var height: Int
    # Focal length and principal point, in pixels.
    var focal: Float32
    var cx: Float32
    var cy: Float32

    def __init__(out self, width: Int, height: Int, fov: Angle) raises:
        """Create intrinsics from an image size and a horizontal fov.

        Args:
            width: Pixels across. It must be positive.
            height: Pixels down. It must be positive.
            fov: The horizontal field of view, between 0 and 180 degrees.

        Raises:
            Error: If a size is not positive or the fov is out of range.
        """
        if width <= 0 or height <= 0:
            raise Error("A camera image needs a positive size")
        var radians = fov.to(RADIAN)
        if not (radians > 0.0 and radians < 3.14159265):
            raise Error("A camera fov must be between 0 and 180 degrees")
        self.width = width
        self.height = height
        self.focal = Float32(width) / (2.0 * tan(radians / 2.0))
        self.cx = Float32(width) / 2.0
        self.cy = Float32(height) / 2.0

    def project(self, camera: CarlaTransform, point: Vector3) -> Vector3:
        """Project a CARLA world point to a pixel.

        Args:
            camera: Where the camera is and where it looks.
            point: A point in CARLA's world frame.

        Returns:
            The pixel column, the pixel row and the planar depth in
            meters. A depth of zero or less is behind the camera, and its
            column and row mean nothing.
        """
        var local = camera.inverse_transform_point(point)
        if not (local.x > 0.0):
            return Vector3(0, 0, local.x)
        return Vector3(
            self.focal * local.y / local.x + self.cx,
            self.focal * -local.z / local.x + self.cy,
            local.x,
        )

    def ray(self, camera: CarlaTransform, u: Float32, v: Float32) -> Vector3:
        """Return the world direction through a pixel.

        Args:
            camera: Where the camera is and where it looks.
            u: Pixel column. Use x + 0.5 for the center of pixel x.
            v: Pixel row. Use y + 0.5 for the center of pixel y.

        Returns:
            A direction in CARLA's world frame whose forward part is one,
            so a hit's distance along it is its planar depth.
        """
        var local = Vector3(
            1.0, (u - self.cx) / self.focal, -(v - self.cy) / self.focal
        )
        return camera.rotation.rotate_vector(local)
