# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The modes, presets and buffer kinds of Streamline's DLSS features.

`UpscaleMode`, `SuperResolutionPreset`, `DenoiserPreset` and
`NormalRoughnessMode` carry the numbers of Streamline 2.14.16's
`sl::DLSSMode`, `sl::DLSSPreset`, `sl::DLSSDPreset` and
`sl::DLSSDNormalRoughnessMode`, from `sl_dlss.h` and `sl_dlss_d.h`. A native
binding can pass them on as they are. `Feature` and `BufferKind` are this
port's own numbering. `Feature.streamline_id` and `BufferKind.streamline_type`
give the number of `sl::Feature` and of `sl::BufferType` that each one stands
for. `MotionVectorSpace` is this port's alone: it only picks `mvecScale`.

**Checked against the running plugins.** `sl.dlss` and `sl.dlss_d` of
Streamline 2.14.16 were run on an NVIDIA TITAN RTX with driver 610.88. See
`docs/validation/streamline/`. `slDLSSGetOptimalSettings` and
`slDLSSDGetOptimalSettings` answer for five modes only. For `eOff` and for
`eUltraQuality` they return `eErrorInvalidParameter`, although the headers
list both. `UpscaleMode.has_optimal_settings` says which modes answer.

Each is a type and not an integer, and each has `is_valid`. The type stops a
bare integer at compile time. A value that no name stands for is still
constructible, and the boundary that reads it refuses it.

**DLSS 4.5.** The second-generation transformer models are Super Resolution
presets L and M and Ray Reconstruction preset F. `is_dlss_4_5` says so.
Streamline's headers name no DLSS version. The mapping is NVIDIA's
announcement of the models, and Streamline's comment on preset F.
"""


@fieldwise_init
struct Feature(Equatable, ImplicitlyCopyable, Writable):
    """Which DLSS feature a frame runs."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 2 features.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value >= 0 and self.value < 2

    def name(self) -> String:
        """Return the feature's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        var names: List[String] = ["super resolution", "ray reconstruction"]
        return names[self.value]

    def streamline_id(self) raises -> Int:
        """Return the number of the feature in Streamline.

        Returns:
            `sl::kFeatureDLSS` (0) for Super Resolution, or
            `sl::kFeatureDLSS_RR` (1001) for Ray Reconstruction.

        Raises:
            Error: If the feature is not valid.
        """
        if not self.is_valid():
            raise Error(
                "A DLSS feature must be super resolution or ray reconstruction"
            )
        return 0 if self.value == 0 else 1001


# DLSS Super Resolution: `sl::kFeatureDLSS`. It upscales a render.
comptime SUPER_RESOLUTION = Feature(0)
# DLSS Ray Reconstruction: `sl::kFeatureDLSS_RR`. It denoises and upscales
# a noisy ray-traced render.
comptime RAY_RECONSTRUCTION = Feature(1)


@fieldwise_init
struct UpscaleMode(Equatable, ImplicitlyCopyable, Writable):
    """How far DLSS upscales, `sl::DLSSMode`. Both features read it."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 7 modes.

        Returns:
            Whether the value is 0 to 6.
        """
        return self.value >= 0 and self.value < 7

    def name(self) -> String:
        """Return the mode's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        var names: List[String] = [
            "off",
            "max performance",
            "balanced",
            "max quality",
            "ultra performance",
            "ultra quality",
            "dlaa",
        ]
        return names[self.value]

    def has_optimal_settings(self) -> Bool:
        """Return True if Streamline answers `GetOptimalSettings` for it.

        Returns:
            Whether the mode is Performance, Balanced, Quality, Ultra
            Performance or DLAA. `sl.dlss` and `sl.dlss_d` 2.14.16 return
            `eErrorInvalidParameter` for off and for ultra quality.
        """
        return (
            self.value == 1
            or self.value == 2
            or self.value == 3
            or self.value == 4
            or self.value == 6
        )


# `eOff`: DLSS does nothing.
comptime MODE_OFF = UpscaleMode(0)
# `eMaxPerformance`: the Performance mode.
comptime MODE_MAX_PERFORMANCE = UpscaleMode(1)
# `eBalanced`.
comptime MODE_BALANCED = UpscaleMode(2)
# `eMaxQuality`: the Quality mode.
comptime MODE_MAX_QUALITY = UpscaleMode(3)
# `eUltraPerformance`.
comptime MODE_ULTRA_PERFORMANCE = UpscaleMode(4)
# `eUltraQuality`. The header lists it, but `sl.dlss` 2.14.16 gives it no
# render size.
comptime MODE_ULTRA_QUALITY = UpscaleMode(5)
# `eDLAA`: anti-aliasing at the output's size, without upscaling.
comptime MODE_DLAA = UpscaleMode(6)


@fieldwise_init
struct SuperResolutionPreset(Equatable, ImplicitlyCopyable, Writable):
    """Which model Super Resolution runs, `sl::DLSSPreset`.

    Presets A to D are gone from Streamline, so 1 to 4 are not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if Streamline still has this preset.

        Returns:
            Whether the value is 0, or 5 to 15.
        """
        return self.value == 0 or (self.value >= 5 and self.value < 16)

    def is_deprecated(self) -> Bool:
        """Return True for the presets that Streamline marks deprecated.

        Returns:
            Whether the preset is E or F.
        """
        return self.value == 5 or self.value == 6

    def reverts_to_default(self) -> Bool:
        """Return True for the presets that Streamline replaces by the
        default model.

        Returns:
            Whether the preset is G, H, I, N or O.
        """
        return (
            (self.value >= 7 and self.value < 10)
            or self.value == 14
            or self.value == 15
        )

    def is_dlss_4_5(self) -> Bool:
        """Return True for the second-generation transformer models.

        Returns:
            Whether the preset is L or M.
        """
        return self.value == 12 or self.value == 13

    def name(self) -> String:
        """Return the preset's name.

        Returns:
            "default", or the letter of the preset, or "unknown" for a value
            that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        if self.value == 0:
            return "default"
        var letters: List[String] = [
            "E",
            "F",
            "G",
            "H",
            "I",
            "J",
            "K",
            "L",
            "M",
            "N",
            "O",
        ]
        return letters[self.value - 5]


# `eDefault`: whatever Streamline picks. An over-the-air update can change it.
comptime SR_PRESET_DEFAULT = SuperResolutionPreset(0)
# `ePresetJ`: like K, with less ghosting and more flicker.
comptime SR_PRESET_J = SuperResolutionPreset(10)
# `ePresetK`: the transformer model of DLAA, Balanced and Quality.
comptime SR_PRESET_K = SuperResolutionPreset(11)
# `ePresetL`: DLSS 4.5, the sharper model, which Ultra Performance uses.
comptime SR_PRESET_L = SuperResolutionPreset(12)
# `ePresetM`: DLSS 4.5, the faster model, which Performance uses.
comptime SR_PRESET_M = SuperResolutionPreset(13)


@fieldwise_init
struct DenoiserPreset(Equatable, ImplicitlyCopyable, Writable):
    """Which model Ray Reconstruction runs, `sl::DLSSDPreset`.

    Presets A to C are gone from Streamline, so 1 to 3 are not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if Streamline still has this preset.

        Returns:
            Whether the value is 0, or 4 to 15.
        """
        return self.value == 0 or (self.value >= 4 and self.value < 16)

    def reverts_to_default(self) -> Bool:
        """Return True for the presets that Streamline replaces by the
        default model.

        Returns:
            Whether the preset is G to O.
        """
        return self.value >= 7 and self.value < 16

    def is_dlss_4_5(self) -> Bool:
        """Return True for the second-generation transformer model.

        Returns:
            Whether the preset is F.
        """
        return self.value == 6

    def name(self) -> String:
        """Return the preset's name.

        Returns:
            "default", or the letter of the preset, or "unknown" for a value
            that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        if self.value == 0:
            return "default"
        var letters: List[String] = [
            "D",
            "E",
            "F",
            "G",
            "H",
            "I",
            "J",
            "K",
            "L",
            "M",
            "N",
            "O",
        ]
        return letters[self.value - 4]


# `eDefault`: whatever Streamline picks.
comptime RR_PRESET_DEFAULT = DenoiserPreset(0)
# `ePresetD`: a transformer model.
comptime RR_PRESET_D = DenoiserPreset(4)
# `ePresetE`: a transformer model.
comptime RR_PRESET_E = DenoiserPreset(5)
# `ePresetF`: DLSS 4.5, the latest transformer model.
comptime RR_PRESET_F = DenoiserPreset(6)


@fieldwise_init
struct NormalRoughnessMode(Equatable, ImplicitlyCopyable, Writable):
    """How Ray Reconstruction finds the roughness,
    `sl::DLSSDNormalRoughnessMode`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 2 modes.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value >= 0 and self.value < 2

    def name(self) -> String:
        """Return the mode's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        var names: List[String] = ["unpacked", "packed"]
        return names[self.value]


# `eUnpacked`: the normals and the roughness are two buffers.
comptime ROUGHNESS_UNPACKED = NormalRoughnessMode(0)
# `ePacked`: the roughness is the alpha of the normals' buffer.
comptime ROUGHNESS_PACKED = NormalRoughnessMode(1)


@fieldwise_init
struct MotionVectorSpace(Equatable, ImplicitlyCopyable, Writable):
    """What unit the motion vectors are in, which sets `mvecScale`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 2 spaces.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value >= 0 and self.value < 2

    def name(self) -> String:
        """Return the space's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        var names: List[String] = ["normalized", "pixels"]
        return names[self.value]


# The vectors are already in Streamline's range of minus one to one:
# `mvecScale` is one, one.
comptime MOTION_NORMALIZED = MotionVectorSpace(0)
# The vectors are in render pixels: `mvecScale` is one over the render size.
comptime MOTION_PIXELS = MotionVectorSpace(1)


@fieldwise_init
struct BufferKind(Equatable, ImplicitlyCopyable, Writable):
    """What a tagged buffer holds. A binding tags each buffer with the
    Streamline resource tag of the same meaning."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 18 kinds.

        Returns:
            Whether the value is 0 to 17.
        """
        return self.value >= 0 and self.value < 18

    def name(self) -> String:
        """Return the kind's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        var names: List[String] = [
            "depth",
            "linear depth",
            "motion vectors",
            "specular motion vectors",
            "specular hit distance",
            "input color",
            "output color",
            "exposure",
            "albedo",
            "specular albedo",
            "normals",
            "normal and roughness",
            "roughness",
            "transparency layer",
            "transparency layer opacity",
            "color before transparency",
            "subsurface scattering guide",
            "depth of field guide",
        ]
        return names[self.value]

    def streamline_type(self) raises -> Int:
        """Return the number of the buffer in Streamline.

        Returns:
            The `sl::BufferType` of `sl_core_types.h` that the kind stands
            for: `kBufferTypeDepth` (0) for the depth, `kBufferTypeLinearDepth`
            (49) for the linear depth, `kBufferTypeScalingInputColor` (3) and
            `kBufferTypeScalingOutputColor` (4) for the colors, and so on.

        Raises:
            Error: If the kind is not valid.
        """
        if not self.is_valid():
            raise Error("A tagged buffer's kind must be one of the eighteen")
        var types: List[Int] = [
            0,
            49,
            1,
            10,
            42,
            3,
            4,
            13,
            7,
            8,
            5,
            14,
            6,
            51,
            52,
            40,
            58,
            64,
        ]
        return types[self.value]


# Hardware depth, at the render size.
comptime BUFFER_DEPTH = BufferKind(0)
# Depth in view space, at the render size.
comptime BUFFER_LINEAR_DEPTH = BufferKind(1)
# Dense motion vectors, camera and objects, at the render size.
comptime BUFFER_MOTION_VECTORS = BufferKind(2)
# Motion vectors of the specular reflections, at the render size.
comptime BUFFER_SPECULAR_MOTION_VECTORS = BufferKind(3)
# The distance from the specular ray's origin to its hit, at the render size.
comptime BUFFER_SPECULAR_HIT_DISTANCE = BufferKind(4)
# The color that goes in: the render, or the noisy ray-traced render.
comptime BUFFER_INPUT_COLOR = BufferKind(5)
# The color that comes out, at the output's size.
comptime BUFFER_OUTPUT_COLOR = BufferKind(6)
# The frame's exposure, one texel.
comptime BUFFER_EXPOSURE = BufferKind(7)
# The diffuse albedo, linear, at the render size.
comptime BUFFER_ALBEDO = BufferKind(8)
# The specular albedo, linear, at the render size.
comptime BUFFER_SPECULAR_ALBEDO = BufferKind(9)
# The shading normals, at the render size.
comptime BUFFER_NORMALS = BufferKind(10)
# The shading normals with the roughness in their alpha.
comptime BUFFER_NORMAL_ROUGHNESS = BufferKind(11)
# The linear roughness, at the render size.
comptime BUFFER_ROUGHNESS = BufferKind(12)
# The transparent layers, color or premultiplied color and alpha.
comptime BUFFER_TRANSPARENCY_LAYER = BufferKind(13)
# The transparent layers' opacity.
comptime BUFFER_TRANSPARENCY_LAYER_OPACITY = BufferKind(14)
# The noisy color before the transparent layers.
comptime BUFFER_COLOR_BEFORE_TRANSPARENCY = BufferKind(15)
# One float a pixel: the subsurface scattering strength.
comptime BUFFER_SUBSURFACE_GUIDE = BufferKind(16)
# One float a pixel: the depth of field's circle of confusion.
comptime BUFFER_DEPTH_OF_FIELD_GUIDE = BufferKind(17)
