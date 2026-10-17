# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The seam between a program and whatever upscales its frames.

`Upscaler` is the trait a program draws through. A native Streamline binding
will implement it for DLSS. `SpatialUpscaler` implements it with FSR1's EASU
and RCAS from `postprocessing.upscaling`, on the CPU, so a program runs on a
machine without an RTX GPU, and a test has a reference to compare a binding
with.

`SpatialUpscaler` is not DLSS. It reads the color only. It does not look at
the motion vectors, the depth or the history, so it adds no detail that the
render lacks. And it does not denoise, so it does not support Ray
Reconstruction. A program that wants a denoised, upscaled path-traced frame
without DLSS uses `postprocessing.temporal_denoise` first.
"""

from extensions.streamline.kinds import (
    Feature,
    RAY_RECONSTRUCTION,
    SUPER_RESOLUTION,
)
from extensions.streamline.sizing import FrameSize
from postprocessing.sampling import LightView
from postprocessing.upscaling import easu_pixel, rcas_pixel
from render.framebuffer import FloatColor
from std.math import isfinite


trait Upscaler:
    """Something that turns a render into a frame at the output's size."""

    def name(self) -> String:
        """Return the upscaler's name.

        Returns:
            The name.
        """
        ...

    def supports(self, feature: Feature) -> Bool:
        """Return whether the upscaler runs a feature.

        Args:
            feature: The feature.

        Returns:
            Whether `evaluate` accepts it.
        """
        ...

    def evaluate(
        self,
        feature: Feature,
        colors: List[FloatColor],
        render: FrameSize,
        output: FrameSize,
    ) raises -> List[FloatColor]:
        """Upscale a render.

        Args:
            feature: The feature to run.
            colors: The render, premultiplied, row by row from the top.
            render: The render's size.
            output: The size of the frame to return.

        Returns:
            The frame at the output's size, premultiplied.

        Raises:
            Error: If the feature is not valid or not supported, a size has
                a side below one pixel, the render is larger than the
                output, or the colors are not `render` sized.
        """
        ...


struct SpatialUpscaler(Upscaler):
    """FSR1's EASU, then RCAS, on the CPU: a fallback for Super Resolution."""

    # RCAS's sharpness: zero sharpens most, two hardly at all.
    var sharpness: Float32

    def __init__(out self, sharpness: Float32 = 0.2) raises:
        """Start with three.js's sharpness.

        Args:
            sharpness: RCAS's sharpness, zero or more.

        Raises:
            Error: If the sharpness is negative or not finite.
        """
        if not (isfinite(sharpness) and sharpness >= 0):
            raise Error("A sharpness must be finite and not negative")
        self.sharpness = sharpness

    def name(self) -> String:
        """Return the upscaler's name.

        Returns:
            "EASU and RCAS".
        """
        return "EASU and RCAS"

    def supports(self, feature: Feature) -> Bool:
        """Return whether the upscaler runs a feature.

        Args:
            feature: The feature.

        Returns:
            True for Super Resolution only.
        """
        return feature == SUPER_RESOLUTION

    def evaluate(
        self,
        feature: Feature,
        colors: List[FloatColor],
        render: FrameSize,
        output: FrameSize,
    ) raises -> List[FloatColor]:
        """Upscale a render with EASU, and sharpen it with RCAS.

        Args:
            feature: Super Resolution.
            colors: The render, premultiplied, row by row from the top.
            render: The render's size.
            output: The size of the frame to return.

        Returns:
            The frame at the output's size, premultiplied.

        Raises:
            Error: If the feature is not valid or not Super Resolution, a
                size has a side below one pixel, the render is larger than
                the output, or the colors are not `render` sized.
        """
        if not feature.is_valid():
            raise Error(
                "A feature must be super resolution or ray reconstruction"
            )
        if feature == RAY_RECONSTRUCTION:
            raise Error("The spatial upscaler does not denoise")
        if render.width < 1 or render.height < 1:
            raise Error("A render must be at least one pixel each way")
        if output.width < render.width or output.height < render.height:
            raise Error("The output must be at least as large as the render")
        if len(colors) != render.width * render.height:
            raise Error("The colors must fill the render")
        var source = LightView(colors, render.width, render.height)
        var easu = List[FloatColor](capacity=output.width * output.height)
        for y in range(output.height):  # pragma: no branch
            for x in range(output.width):  # pragma: no branch
                easu.append(
                    easu_pixel(
                        source, x, y, output.width, output.height
                    ).premultiplied()
                )
        var middle = LightView(easu, output.width, output.height)
        var result = List[FloatColor](capacity=output.width * output.height)
        for y in range(output.height):  # pragma: no branch
            for x in range(output.width):  # pragma: no branch
                result.append(rcas_pixel(middle, x, y, self.sharpness, False))
        _ = easu^
        return result^
