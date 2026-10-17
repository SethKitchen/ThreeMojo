# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The size a scene is rendered at, and the size DLSS says it wants.

DLSS upscales from a render smaller than the output. Streamline's
`slDLSSGetOptimalSettings` says how small, for a mode and an output size.
That call needs a device. `estimated_render_size` is the answer to plan an
allocation with before the device is there: the ratio of each mode as NVIDIA
publishes it, rounded to the nearest pixel. It is an estimate. The size that
Streamline returns is the size to render at.

`estimated_optimal_settings` adds the range of sizes that dynamic resolution
can use. Both match `sl.dlss` and `sl.dlss_d` 2.14.16 on a TITAN RTX with
driver 610.88, at 3840x2160, 2560x1440, 1920x1080, 1280x720 and 1000x563
(`docs/validation/streamline/result.tsv`). Streamline answers for five modes.
For off and for ultra quality it returns `eErrorInvalidParameter`.

`OptimalSettings` is `sl::DLSSOptimalSettings` and `sl::DLSSDOptimalSettings`,
which have the same seven fields. `check_optimal_settings` refuses a reply
that cannot be right. `check_render_size` says whether the size a frame
renders at, which dynamic resolution can change, is one that DLSS accepts.
"""

from extensions.streamline.kinds import (
    MODE_BALANCED,
    MODE_DLAA,
    MODE_MAX_PERFORMANCE,
    MODE_MAX_QUALITY,
    MODE_ULTRA_PERFORMANCE,
    MODE_ULTRA_QUALITY,
    UpscaleMode,
)
from std.math import floor, isfinite


@fieldwise_init
struct FrameSize(Equatable, ImplicitlyCopyable, Writable):
    """A width and a height, in pixels."""

    var width: Int
    var height: Int


def render_scale(mode: UpscaleMode) raises -> Float64:
    """Return the share of the output's side that a mode renders.

    Args:
        mode: The mode.

    Returns:
        One for off and for DLAA. For the others NVIDIA's ratios: Quality
        two thirds, Balanced 0.58, Performance a half and Ultra Performance
        a third.

    Raises:
        Error: If the mode is not valid, or is ultra quality, which
            `sl.dlss` 2.14.16 refuses with `eErrorInvalidParameter`.
    """
    if not mode.is_valid():
        raise Error("A DLSS mode must be one of the seven")
    if mode == MODE_ULTRA_QUALITY:
        raise Error("DLSS gives ultra quality no render size")
    if mode == MODE_MAX_QUALITY:
        return 2.0 / 3.0
    if mode == MODE_BALANCED:
        return 0.58
    if mode == MODE_MAX_PERFORMANCE:
        return 0.5
    if mode == MODE_ULTRA_PERFORMANCE:
        return 1.0 / 3.0
    return 1.0


def _scaled(side: Int, scale: Float64) -> Int:
    """Return a side at a scale, to the nearest pixel and at least one."""
    return max(Int(floor(Float64(side) * scale + 0.5)), 1)


def estimated_render_size(
    mode: UpscaleMode, output: FrameSize
) raises -> FrameSize:
    """Return the size to plan a render at, before Streamline can say.

    Args:
        mode: The mode.
        output: The output's size.

    Returns:
        The output's size at the mode's ratio, to the nearest pixel.

    Raises:
        Error: If the mode is not valid, or the output has a side below one.
    """
    var scale = render_scale(mode)
    if output.width < 1 or output.height < 1:
        raise Error("An output must be at least one pixel each way")
    return FrameSize(
        _scaled(output.width, scale), _scaled(output.height, scale)
    )


struct OptimalSettings(Copyable, Movable):
    """What DLSS says about the render size, `sl::DLSSOptimalSettings`."""

    # `optimalRenderWidth` and `optimalRenderHeight`.
    var optimal_width: Int
    var optimal_height: Int
    # `optimalSharpness`.
    var optimal_sharpness: Float32
    # `renderWidthMin`, `renderHeightMin`, `renderWidthMax` and
    # `renderHeightMax`: the sizes dynamic resolution can use.
    var min_width: Int
    var min_height: Int
    var max_width: Int
    var max_height: Int

    def __init__(
        out self,
        optimal_width: Int,
        optimal_height: Int,
        optimal_sharpness: Float32,
        min_width: Int,
        min_height: Int,
        max_width: Int,
        max_height: Int,
    ):
        """Hold a reply of Streamline.

        Args:
            optimal_width: The width to render at.
            optimal_height: The height to render at.
            optimal_sharpness: The sharpness to use.
            min_width: The smallest width dynamic resolution can use.
            min_height: The smallest height.
            max_width: The largest width.
            max_height: The largest height.
        """
        self.optimal_width = optimal_width
        self.optimal_height = optimal_height
        self.optimal_sharpness = optimal_sharpness
        self.min_width = min_width
        self.min_height = min_height
        self.max_width = max_width
        self.max_height = max_height


def estimated_optimal_settings(
    mode: UpscaleMode, output: FrameSize
) raises -> OptimalSettings:
    """Return what Streamline answers for a mode, before it can say.

    Args:
        mode: The mode. It must be one that `has_optimal_settings`.
        output: The output's size.

    Returns:
        The estimated render size as the optimal size. The largest size is
        the output. The smallest is half the output, a share of 0.99 for
        DLAA, and the optimal size for Ultra Performance. The sharpness is
        zero: it is a deprecated field.

    Raises:
        Error: If the mode is off or ultra quality, which Streamline gives no
            settings, or is not valid, or the output has a side below one.
    """
    if not mode.has_optimal_settings():
        raise Error("DLSS gives this mode no optimal settings")
    var optimal = estimated_render_size(mode, output)
    var smallest = optimal
    if mode == MODE_DLAA:
        smallest = FrameSize(
            _scaled(output.width, 0.99), _scaled(output.height, 0.99)
        )
    elif mode != MODE_ULTRA_PERFORMANCE:
        smallest = FrameSize(
            _scaled(output.width, 0.5), _scaled(output.height, 0.5)
        )
    var largest = output if mode != MODE_ULTRA_PERFORMANCE else optimal
    return OptimalSettings(
        optimal.width,
        optimal.height,
        0,
        smallest.width,
        smallest.height,
        largest.width,
        largest.height,
    )


def check_optimal_settings(settings: OptimalSettings, output: FrameSize) raises:
    """Refuse a reply of Streamline that cannot be right.

    Args:
        settings: The reply.
        output: The output's size that it was asked for.

    Raises:
        Error: If a size is below one pixel, the optimal size is outside the
            range or larger than the output, or the sharpness is not a
            number from zero to one.
    """
    if settings.min_width < 1 or settings.min_height < 1:
        raise Error("A DLSS render size must be at least one pixel each way")
    if (
        settings.optimal_width < settings.min_width
        or settings.optimal_height < settings.min_height
    ):
        raise Error("The optimal render size is below the smallest one")
    if (
        settings.optimal_width > settings.max_width
        or settings.optimal_height > settings.max_height
    ):
        raise Error("The optimal render size is above the largest one")
    if (
        settings.optimal_width > output.width
        or settings.optimal_height > output.height
    ):
        raise Error("The optimal render size is larger than the output")
    if not (
        isfinite(settings.optimal_sharpness)
        and settings.optimal_sharpness >= 0
        and settings.optimal_sharpness <= 1
    ):
        raise Error("The optimal sharpness must be from zero to one")


def check_render_size(settings: OptimalSettings, render: FrameSize) raises:
    """Refuse a render size that DLSS does not accept.

    Args:
        settings: The reply of Streamline.
        render: The size the frame is rendered at.

    Raises:
        Error: If a side is below the smallest size or above the largest.
    """
    if render.width < settings.min_width or render.height < settings.min_height:
        raise Error("The render is smaller than DLSS accepts")
    if render.width > settings.max_width or render.height > settings.max_height:
        raise Error("The render is larger than DLSS accepts")
