# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The numbers and names that the glTF 2.0 format fixes: the binary
container's words, the accessor component types, the primitive modes, the
sampler constants and the extension names.

`loaders.gltf` reads them, and `exporters.gltf` writes them. They are here
so that the exporter does not compile the loader.
"""

from render.texture import (
    BILINEAR,
    LINEAR_MIPMAP_LINEAR,
    LINEAR_MIPMAP_NEAREST,
    NEAREST,
    NEAREST_MIPMAP_LINEAR,
    NEAREST_MIPMAP_NEAREST,
    Filter,
)

# The binary container's header: the magic `glTF`, the version, and the
# two chunk types, as little-endian words.
comptime GLB_MAGIC = 0x46546C67
comptime GLB_VERSION = 2
comptime GLB_HEADER_BYTES = 12
comptime GLB_CHUNK_HEADER_BYTES = 8
comptime GLB_JSON_CHUNK = 0x4E4F534A
comptime GLB_BIN_CHUNK = 0x004E4942

# The accessor component types glTF names, by their GL constants.
comptime COMPONENT_BYTE = 5120
comptime COMPONENT_UNSIGNED_BYTE = 5121
comptime COMPONENT_SHORT = 5122
comptime COMPONENT_UNSIGNED_SHORT = 5123
comptime COMPONENT_UNSIGNED_INT = 5125
comptime COMPONENT_FLOAT = 5126

# The primitive modes that are read: points, the three kinds of line, and
# triangles. glTF names them by their GL constants.
comptime MODE_POINTS = 0
comptime MODE_LINES = 1
comptime MODE_LINE_LOOP = 2
comptime MODE_LINE_STRIP = 3
comptime MODE_TRIANGLES = 4

# The sampler's wrap and filter constants.
comptime WRAP_REPEAT = 10497
comptime WRAP_CLAMP = 33071
comptime WRAP_MIRROR = 33648
comptime FILTER_NEAREST = 9728
comptime FILTER_LINEAR = 9729
# The four minification filters that read a mipmap chain.
comptime FILTER_NEAREST_MIPMAP_NEAREST = 9984
comptime FILTER_LINEAR_MIPMAP_NEAREST = 9985
comptime FILTER_NEAREST_MIPMAP_LINEAR = 9986
comptime FILTER_LINEAR_MIPMAP_LINEAR = 9987

# The extensions that `loaders.gltf` reads. It refuses a file that requires
# any other, as three.js's `GLTFLoader` refuses one it has no plugin for.
comptime EMISSIVE_STRENGTH = "KHR_materials_emissive_strength"
comptime MATERIALS_IOR = "KHR_materials_ior"
comptime MATERIALS_SPECULAR = "KHR_materials_specular"
comptime MATERIALS_CLEARCOAT = "KHR_materials_clearcoat"
comptime MATERIALS_SHEEN = "KHR_materials_sheen"
comptime MATERIALS_IRIDESCENCE = "KHR_materials_iridescence"
comptime MATERIALS_ANISOTROPY = "KHR_materials_anisotropy"
comptime MATERIALS_UNLIT = "KHR_materials_unlit"
comptime MATERIALS_TRANSMISSION = "KHR_materials_transmission"
comptime MATERIALS_VOLUME = "KHR_materials_volume"
comptime MATERIALS_DISPERSION = "KHR_materials_dispersion"
comptime TEXTURE_TRANSFORM = "KHR_texture_transform"
comptime LIGHTS_PUNCTUAL = "KHR_lights_punctual"
comptime MESH_QUANTIZATION = "KHR_mesh_quantization"
comptime GPU_INSTANCING = "EXT_mesh_gpu_instancing"
comptime DRACO_MESH_COMPRESSION = "KHR_draco_mesh_compression"
comptime MATERIALS_BUMP = "EXT_materials_bump"
comptime TEXTURE_BASISU = "KHR_texture_basisu"
comptime MESHOPT_COMPRESSION = "EXT_meshopt_compression"
comptime MATERIALS_VARIANTS = "KHR_materials_variants"
comptime TEXTURE_WEBP = "EXT_texture_webp"


def gl_filter(filter: Filter) -> Int:
    """Return a filter as glTF's GL constant.

    Args:
        filter: Any of the six named filters.

    Returns:
        The constant: `FILTER_NEAREST` for `NEAREST`, and so on.
    """
    if filter == NEAREST:
        return FILTER_NEAREST
    if filter == BILINEAR:
        return FILTER_LINEAR
    if filter == NEAREST_MIPMAP_NEAREST:
        return FILTER_NEAREST_MIPMAP_NEAREST
    if filter == LINEAR_MIPMAP_NEAREST:
        return FILTER_LINEAR_MIPMAP_NEAREST
    if filter == NEAREST_MIPMAP_LINEAR:
        return FILTER_NEAREST_MIPMAP_LINEAR
    return FILTER_LINEAR_MIPMAP_LINEAR


def filter_of_gl(code: Int) raises -> Filter:
    """Return a glTF filter constant as a filter.

    Args:
        code: One of glTF's six filter constants.

    Returns:
        The filter.

    Raises:
        Error: If the constant is none of the six.
    """
    if code == FILTER_NEAREST:
        return NEAREST
    if code == FILTER_LINEAR:
        return BILINEAR
    if code == FILTER_NEAREST_MIPMAP_NEAREST:
        return NEAREST_MIPMAP_NEAREST
    if code == FILTER_LINEAR_MIPMAP_NEAREST:
        return LINEAR_MIPMAP_NEAREST
    if code == FILTER_NEAREST_MIPMAP_LINEAR:
        return NEAREST_MIPMAP_LINEAR
    if code == FILTER_LINEAR_MIPMAP_LINEAR:
        return LINEAR_MIPMAP_LINEAR
    raise Error("glTF: a filter that is not known")
