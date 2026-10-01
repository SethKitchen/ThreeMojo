# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's image conversions: `image::ColorConverter` and
`ImageConverter::ConvertInPlace`, and the decoders of the instance
segmentation, normals and optical flow cameras.

The sources are `LibCarla/source/carla/image/ColorConverter.h`,
`ImageConverter.h` and `ImageView.h`; the instance encoding of CARLA's
simulator plugin, `Carla/Game/Tagger.cpp`, `GetActorLabelColor`; and the
optical flow color wheel of `LibCarla/source/carla/ros2/publishers/
OpticalFlowEncoding.h`, which keeps the format of CARLA's
`get_color_coded_flow`.

The per-pixel steps are `extensions.carla.sensor`'s: `normalized_depth`
is `ColorConverter::Depth`, `logarithmic_gray` is `LogarithmicLinear`, and
`cityscapes_color` is `CityScapesPalette::GetColor`. This module applies
them to a whole `render.framebuffer.Framebuffer`, as `ConvertInPlace`
applies them to an image view. Boost.GIL writes a gray level g from 0 to
1 as the byte `uint8(g 255 + 0.5)`, with an opaque alpha.

The normals camera's encoding lives in a material of CARLA's simulator
plugin, not in the source. `decode_normal` follows CARLA's sensor reference: each part of
the unit normal, from -1 to 1, is stored from 0 to 255.

**Differences from CARLA.** A red channel of 30 or more is not a
semantic tag, and the CityScapes conversion refuses it, as
`cityscapes_color` does. CARLA wraps it around the palette.
"""

from extensions.carla.sensor import (
    SemanticTag,
    cityscapes_color,
    logarithmic_gray,
    normalized_depth,
)
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import atan2, isfinite, log, pi, sqrt


@fieldwise_init
struct ColorConverter(Equatable, ImplicitlyCopyable, Writable):
    """How to convert a camera image, CARLA's `carla.ColorConverter`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the four conversions."""
        return self.value >= 0 and self.value < 4


# Keep the image as it is.
comptime RAW = ColorConverter(0)
# Depth in RGB to a linear gray.
comptime DEPTH = ColorConverter(1)
# Depth in RGB to a logarithmic gray.
comptime LOGARITHMIC_DEPTH = ColorConverter(2)
# A semantic tag in red to its CityScapes color.
comptime CITY_SCAPES_PALETTE = ColorConverter(3)


def gray_byte(gray: Float32) -> UInt8:
    """Write a gray level as a byte, as Boost.GIL converts a float channel.

    Args:
        gray: The level, from 0 to 1.

    Returns:
        The byte `uint8(gray 255 + 0.5)`.
    """
    return UInt8(Int(gray * 255.0 + 0.5))


def convert_pixel(color: Color, converter: ColorConverter) raises -> Color:
    """Convert one pixel, as `ConvertInPlace` converts each.

    Args:
        color: The pixel.
        converter: The conversion.

    Returns:
        The pixel for `RAW`. A gray for `DEPTH` and `LOGARITHMIC_DEPTH`,
        and the palette color for `CITY_SCAPES_PALETTE`, both opaque.

    Raises:
        Error: If the conversion is not valid, or the red channel is not a
            semantic tag for `CITY_SCAPES_PALETTE`.
    """
    if not converter.is_valid():
        raise Error("A color converter must name one of four conversions")
    if converter == DEPTH:
        var g = gray_byte(normalized_depth(color))
        return Color(g, g, g)
    if converter == LOGARITHMIC_DEPTH:
        var g = gray_byte(logarithmic_gray(normalized_depth(color)))
        return Color(g, g, g)
    if converter == CITY_SCAPES_PALETTE:
        return cityscapes_color(SemanticTag(Int(color.r)))
    return color


def convert_in_place(mut image: Framebuffer, converter: ColorConverter) raises:
    """Convert every pixel of an image, `ImageConverter::ConvertInPlace`.

    Args:
        image: The image. Its pixels are replaced.
        converter: The conversion.

    Raises:
        Error: If `convert_pixel` refuses a pixel.
    """
    # A `Framebuffer` has a positive size, so neither loop runs zero times.
    for y in range(image.height):  # pragma: no branch
        for x in range(image.width):  # pragma: no branch
            image.set_pixel(
                x, y, convert_pixel(image.get_pixel(x, y), converter)
            )


# --- instance segmentation ---------------------------------------------------


@fieldwise_init
struct InstanceId(Equatable, ImplicitlyCopyable, Writable):
    """The object id an instance segmentation camera writes: the low 16
    bits of an actor's id."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the id fits in 16 bits."""
        return self.value >= 0 and self.value < 65536


def encode_instance(tag: SemanticTag, instance: InstanceId) raises -> Color:
    """Write a tag and an id as a pixel, CARLA's `GetActorLabelColor`.

    Args:
        tag: The semantic tag.
        instance: The object id.

    Returns:
        Red is the tag, green the low byte of the id and blue the high
        byte.

    Raises:
        Error: If the tag or the id is not valid.
    """
    if not tag.is_valid():
        raise Error("Semantic tag is not valid")
    if not instance.is_valid():
        raise Error("An instance id must fit in 16 bits")
    return Color(
        UInt8(tag.value),
        UInt8(instance.value & 0xFF),
        UInt8((instance.value & 0xFF00) >> 8),
    )


def decode_instance_tag(color: Color) -> SemanticTag:
    """Read the semantic tag of an instance segmentation pixel.

    Args:
        color: The pixel.

    Returns:
        The red channel as a tag. Check it with `is_valid`.
    """
    return SemanticTag(Int(color.r))


def decode_instance_id(color: Color) -> InstanceId:
    """Read the object id of an instance segmentation pixel.

    Args:
        color: The pixel.

    Returns:
        Green plus 256 times blue.
    """
    return InstanceId(Int(color.g) + Int(color.b) * 256)


# --- normals -------------------------------------------------------------------


def decode_normal(color: Color) -> Vector3:
    """Read a normals camera pixel as a normal.

    Args:
        color: The pixel.

    Returns:
        Each channel c as c / 255 * 2 - 1, in the camera's frame.
    """
    return Vector3(
        Float32(color.r) / 255.0 * 2.0 - 1.0,
        Float32(color.g) / 255.0 * 2.0 - 1.0,
        Float32(color.b) / 255.0 * 2.0 - 1.0,
    )


# --- optical flow ----------------------------------------------------------------


def _fmod(a: Float32, b: Float32) -> Float32:
    # C's fmod: the remainder takes the sign of a.
    return a - b * Float32(Int(a / b))


def encode_flow_pixel(vx: Float32, vy: Float32) raises -> Color:
    """Color one optical flow pixel, `EncodeFlowPixelToBgra`.

    The hue is the direction, atan2(vy, vx) plus 180 degrees, and the
    value rises with the magnitude as a log, to full at 0.1.

    Args:
        vx: The flow across, in CARLA's normalized image units.
        vy: The flow down.

    Returns:
        The color, with an alpha of zero, as CARLA writes it.

    Raises:
        Error: If a part is not finite. CARLA's cast of a NaN hue is
            undefined.
    """
    if not (isfinite(vx) and isfinite(vy)):
        raise Error("An optical flow must be finite")
    comptime rad2ang = Float32(360.0) / (Float32(2.0) * Float32(pi))
    # CARLA adds 360 to a negative angle here. In `Float32` the product
    # of -pi and `rad2ang` rounds to exactly -180, so the sum is never
    # negative, and that step is left out.
    var angle = _fmod(180.0 + atan2(vy, vx) * rad2ang, 360.0)
    var norm = sqrt(vx * vx + vy * vy)
    comptime shift = Float32(0.999)
    var a = 1.0 / log(Float32(0.1) + shift)
    var intensity = min(max(a * log(norm + shift), 0.0), 1.0)
    var h_60 = angle * (Float32(1.0) / Float32(60.0))
    var value = intensity
    var c = value
    var x = c * (1.0 - abs(_fmod(h_60, 2.0) - 1.0))
    var m = value - c
    var r: Float32 = 1.0
    var g: Float32 = 1.0
    var b: Float32 = 1.0
    var sector = Int(h_60)
    if sector == 0:
        r, g, b = c, x, 0.0
    elif sector == 1:
        r, g, b = x, c, 0.0
    elif sector == 2:
        r, g, b = 0.0, c, x
    elif sector == 3:
        r, g, b = 0.0, x, c
    elif sector == 4:
        r, g, b = x, 0.0, c
    elif sector == 5:
        r, g, b = c, 0.0, x
    return Color(
        UInt8(Int((r + m) * 255.0)),
        UInt8(Int((g + m) * 255.0)),
        UInt8(Int((b + m) * 255.0)),
        0,
    )


def encode_flow_image(
    width: Int, height: Int, flow: List[Float32]
) raises -> Framebuffer:
    """Color an optical flow image, `EncodeFlowImageToBgra`.

    Args:
        width: Pixels across.
        height: Pixels down.
        flow: Two numbers a pixel, vx then vy, row by row from the top.

    Returns:
        The colored image.

    Raises:
        Error: If the size is not positive, `flow` does not hold two
            numbers a pixel, or a number is not finite.
    """
    if width <= 0 or height <= 0:
        raise Error("An optical flow image needs a positive size")
    if len(flow) != width * height * 2:
        raise Error("An optical flow image needs two numbers a pixel")
    var out = Framebuffer(width, height, Color(0, 0, 0, 0))
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var i = (y * width + x) * 2
            out.set_pixel(x, y, encode_flow_pixel(flow[i], flow[i + 1]))
    return out^
