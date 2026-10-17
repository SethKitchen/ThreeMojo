# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The options of the two DLSS features, as Streamline 2.14.16 names them.

`SuperResolutionOptions` is `sl::DLSSOptions` and
`RayReconstructionOptions` is `sl::DLSSDOptions`, from `sl_dlss.h` and
`sl_dlss_d.h`. The fields keep Streamline's order and its defaults. Three
things differ:

- The mode and the output size have no default here. Streamline's default
  mode is `eOff` and its default size is invalid, and neither can run.
- The deprecated `sharpness` field and the on-screen indicator's axes are
  not carried.
- Streamline's `Boolean` has a third value, `eInvalid`. A `Bool` here is
  always true or false.

`check_super_resolution` and `check_ray_reconstruction` refuse what no
Streamline call could use. They also refuse a pre-exposure or an exposure
scale that is not positive. Streamline's headers do not say so. A zero
exposure would turn the frame black, and this port refuses it.
"""

from extensions.streamline.kinds import (
    DenoiserPreset,
    MODE_MAX_QUALITY,
    NormalRoughnessMode,
    ROUGHNESS_UNPACKED,
    RR_PRESET_DEFAULT,
    SR_PRESET_DEFAULT,
    SuperResolutionPreset,
    UpscaleMode,
    MODE_DLAA,
    MODE_BALANCED,
    MODE_MAX_PERFORMANCE,
    MODE_ULTRA_PERFORMANCE,
    MODE_ULTRA_QUALITY,
)
from math.matrix4 import Matrix4
from std.math import isfinite


# The output size is a `uint32_t` in Streamline.
comptime MAX_EXTENT = 4294967295


def _check_common(
    mode: UpscaleMode,
    output_width: Int,
    output_height: Int,
    pre_exposure: Float32,
    exposure_scale: Float32,
) raises:
    """Refuse the fields that both features share."""
    if not mode.is_valid():
        raise Error("A DLSS mode must be one of the seven")
    if output_width < 1 or output_width > MAX_EXTENT:
        raise Error("A DLSS output width must be from 1 to 4294967295 pixels")
    if output_height < 1 or output_height > MAX_EXTENT:
        raise Error("A DLSS output height must be from 1 to 4294967295 pixels")
    if not (isfinite(pre_exposure) and pre_exposure > 0):
        raise Error("A DLSS pre-exposure must be finite and positive")
    if not (isfinite(exposure_scale) and exposure_scale > 0):
        raise Error("A DLSS exposure scale must be finite and positive")


struct SuperResolutionOptions(Copyable, Movable):
    """What DLSS Super Resolution reads once a frame, `sl::DLSSOptions`."""

    # `mode`.
    var mode: UpscaleMode
    # `outputWidth` and `outputHeight`: the final target's size, in pixels.
    var output_width: Int
    var output_height: Int
    # `preExposure` and `exposureScale`.
    var pre_exposure: Float32
    var exposure_scale: Float32
    # `colorBuffersHDR`: whether the tagged colors are full HDR.
    var colors_are_hdr: Bool
    # `useAutoExposure`: DLSS finds the exposure itself.
    var auto_exposure: Bool
    # `alphaUpscalingEnabled`: the alpha is upscaled too. It costs time.
    var alpha_upscaling: Bool
    # `dlaaPreset`, `qualityPreset`, `balancedPreset`, `performancePreset`,
    # `ultraPerformancePreset` and `ultraQualityPreset`.
    var dlaa_preset: SuperResolutionPreset
    var quality_preset: SuperResolutionPreset
    var balanced_preset: SuperResolutionPreset
    var performance_preset: SuperResolutionPreset
    var ultra_performance_preset: SuperResolutionPreset
    var ultra_quality_preset: SuperResolutionPreset

    def __init__(
        out self, mode: UpscaleMode, output_width: Int, output_height: Int
    ):
        """Start with Streamline's defaults.

        Args:
            mode: The mode.
            output_width: The final target's width in pixels.
            output_height: Its height in pixels.
        """
        self.mode = mode
        self.output_width = output_width
        self.output_height = output_height
        self.pre_exposure = 1
        self.exposure_scale = 1
        self.colors_are_hdr = True
        self.auto_exposure = False
        self.alpha_upscaling = False
        self.dlaa_preset = SR_PRESET_DEFAULT
        self.quality_preset = SR_PRESET_DEFAULT
        self.balanced_preset = SR_PRESET_DEFAULT
        self.performance_preset = SR_PRESET_DEFAULT
        self.ultra_performance_preset = SR_PRESET_DEFAULT
        self.ultra_quality_preset = SR_PRESET_DEFAULT

    def preset(self) -> SuperResolutionPreset:
        """Return the preset that the mode runs.

        Returns:
            The preset field of the mode, or the default for `eOff` and for
            a mode that is not valid.
        """
        if self.mode == MODE_DLAA:
            return self.dlaa_preset
        if self.mode == MODE_MAX_QUALITY:
            return self.quality_preset
        if self.mode == MODE_BALANCED:
            return self.balanced_preset
        if self.mode == MODE_MAX_PERFORMANCE:
            return self.performance_preset
        if self.mode == MODE_ULTRA_PERFORMANCE:
            return self.ultra_performance_preset
        if self.mode == MODE_ULTRA_QUALITY:
            return self.ultra_quality_preset
        return SR_PRESET_DEFAULT

    def use_dlss_4_5(mut self, preset: SuperResolutionPreset) raises:
        """Run a DLSS 4.5 model in every mode.

        Args:
            preset: `SR_PRESET_M`, which is closer to the speed of the
                first-generation model, or `SR_PRESET_L`, which is sharper.

        Raises:
            Error: If the preset is not L or M.
        """
        if not preset.is_dlss_4_5():
            raise Error("A DLSS 4.5 Super Resolution preset is L or M")
        self.dlaa_preset = preset
        self.quality_preset = preset
        self.balanced_preset = preset
        self.performance_preset = preset
        self.ultra_performance_preset = preset
        self.ultra_quality_preset = preset


def _check_preset(preset: SuperResolutionPreset) raises:
    """Refuse a Super Resolution preset that Streamline no longer has."""
    if not preset.is_valid():
        raise Error("A Super Resolution preset must be default or E to O")


def check_super_resolution(options: SuperResolutionOptions) raises:
    """Refuse options that Streamline could not use.

    Args:
        options: The options.

    Raises:
        Error: If the mode, a preset or the size is not valid, or an
            exposure is not finite and positive.
    """
    _check_common(
        options.mode,
        options.output_width,
        options.output_height,
        options.pre_exposure,
        options.exposure_scale,
    )
    _check_preset(options.dlaa_preset)
    _check_preset(options.quality_preset)
    _check_preset(options.balanced_preset)
    _check_preset(options.performance_preset)
    _check_preset(options.ultra_performance_preset)
    _check_preset(options.ultra_quality_preset)


struct RayReconstructionOptions(Copyable, Movable):
    """What DLSS Ray Reconstruction reads once a frame, `sl::DLSSDOptions`."""

    # `mode`.
    var mode: UpscaleMode
    # `outputWidth` and `outputHeight`: the final target's size, in pixels.
    var output_width: Int
    var output_height: Int
    # `preExposure` and `exposureScale`.
    var pre_exposure: Float32
    var exposure_scale: Float32
    # `colorBuffersHDR`.
    var colors_are_hdr: Bool
    # `normalRoughnessMode`.
    var normal_roughness_mode: NormalRoughnessMode
    # `worldToCameraView` and `cameraViewToWorld`: the view matrix and its
    # inverse. Ray Reconstruction reads them when it gets the specular hit
    # distance and no specular motion vectors.
    var world_to_camera_view: Matrix4
    var camera_view_to_world: Matrix4
    # `alphaUpscalingEnabled`.
    var alpha_upscaling: Bool
    # `dlaaPreset`, `qualityPreset`, `balancedPreset`, `performancePreset`,
    # `ultraPerformancePreset` and `ultraQualityPreset`.
    var dlaa_preset: DenoiserPreset
    var quality_preset: DenoiserPreset
    var balanced_preset: DenoiserPreset
    var performance_preset: DenoiserPreset
    var ultra_performance_preset: DenoiserPreset
    var ultra_quality_preset: DenoiserPreset

    def __init__(
        out self, mode: UpscaleMode, output_width: Int, output_height: Int
    ):
        """Start with Streamline's defaults, and identity matrices.

        Args:
            mode: The mode.
            output_width: The final target's width in pixels.
            output_height: Its height in pixels.
        """
        self.mode = mode
        self.output_width = output_width
        self.output_height = output_height
        self.pre_exposure = 1
        self.exposure_scale = 1
        self.colors_are_hdr = True
        self.normal_roughness_mode = ROUGHNESS_UNPACKED
        self.world_to_camera_view = Matrix4()
        self.camera_view_to_world = Matrix4()
        self.alpha_upscaling = False
        self.dlaa_preset = RR_PRESET_DEFAULT
        self.quality_preset = RR_PRESET_DEFAULT
        self.balanced_preset = RR_PRESET_DEFAULT
        self.performance_preset = RR_PRESET_DEFAULT
        self.ultra_performance_preset = RR_PRESET_DEFAULT
        self.ultra_quality_preset = RR_PRESET_DEFAULT

    def preset(self) -> DenoiserPreset:
        """Return the preset that the mode runs.

        Returns:
            The preset field of the mode, or the default for `eOff` and for
            a mode that is not valid.
        """
        if self.mode == MODE_DLAA:
            return self.dlaa_preset
        if self.mode == MODE_MAX_QUALITY:
            return self.quality_preset
        if self.mode == MODE_BALANCED:
            return self.balanced_preset
        if self.mode == MODE_MAX_PERFORMANCE:
            return self.performance_preset
        if self.mode == MODE_ULTRA_PERFORMANCE:
            return self.ultra_performance_preset
        if self.mode == MODE_ULTRA_QUALITY:
            return self.ultra_quality_preset
        return RR_PRESET_DEFAULT

    def use_dlss_4_5(mut self, preset: DenoiserPreset) raises:
        """Run the DLSS 4.5 model in every mode.

        Args:
            preset: `RR_PRESET_F`.

        Raises:
            Error: If the preset is not F.
        """
        if not preset.is_dlss_4_5():
            raise Error("The DLSS 4.5 Ray Reconstruction preset is F")
        self.dlaa_preset = preset
        self.quality_preset = preset
        self.balanced_preset = preset
        self.performance_preset = preset
        self.ultra_performance_preset = preset
        self.ultra_quality_preset = preset


def _check_denoiser_preset(preset: DenoiserPreset) raises:
    """Refuse a Ray Reconstruction preset that Streamline no longer has."""
    if not preset.is_valid():
        raise Error("A Ray Reconstruction preset must be default or D to O")


def _largest(matrix: Matrix4) -> Float32:
    """Return the largest absolute element of a matrix."""
    var largest = Float32(0)
    # A matrix always has sixteen elements.
    for at in range(16):  # pragma: no branch
        largest = max(largest, abs(matrix.elements[at]))
    return largest


def _is_inverse(matrix: Matrix4, inverse: Matrix4) -> Bool:
    """Return True if two matrices multiply to the identity, within a
    rounding that grows with their size."""
    var product = matrix * inverse
    var identity = Matrix4()
    var tolerance = Float32(1e-5) * max(
        Float32(1), max(_largest(matrix), _largest(inverse))
    )
    # A matrix always has sixteen elements.
    for at in range(16):  # pragma: no branch
        if abs(product.elements[at] - identity.elements[at]) > tolerance:
            return False
    return True


def check_ray_reconstruction(options: RayReconstructionOptions) raises:
    """Refuse options that Streamline could not use.

    Args:
        options: The options.

    Raises:
        Error: If the mode, the normal and roughness mode, a preset or the
            size is not valid, an exposure is not finite and positive, a
            matrix is not finite, or the two matrices are not inverses.
    """
    _check_common(
        options.mode,
        options.output_width,
        options.output_height,
        options.pre_exposure,
        options.exposure_scale,
    )
    if not options.normal_roughness_mode.is_valid():
        raise Error("A normal and roughness mode must be unpacked or packed")
    _check_denoiser_preset(options.dlaa_preset)
    _check_denoiser_preset(options.quality_preset)
    _check_denoiser_preset(options.balanced_preset)
    _check_denoiser_preset(options.performance_preset)
    _check_denoiser_preset(options.ultra_performance_preset)
    _check_denoiser_preset(options.ultra_quality_preset)
    if not options.world_to_camera_view.is_finite():
        raise Error("The world to camera view matrix must be finite")
    if not options.camera_view_to_world.is_finite():
        raise Error("The camera view to world matrix must be finite")
    if not _is_inverse(
        options.world_to_camera_view, options.camera_view_to_world
    ):
        raise Error("The two view matrices must be inverses of each other")
