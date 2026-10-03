# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact invalidation for CARLA's owned ground-truth overrides.

Texture arrays are public. A version counter cannot observe every write.
Compare the alpha of every stored level and all sampling state before reuse.
Source RGB is intentionally ignored: the owned coverage texture is white.
The cache does not share mutable image or mip storage with its source.
"""

from materials.material import Material
from render.texture import Texture
from render.texture_store import TextureId
from std.memory import bitcast


def coverage_matches(source: Texture, cached: Texture) -> Bool:
    """Return whether an owned white texture still represents its source.

    Args:
        source: The current source, including public array edits.
        cached: Its private, white-RGB coverage copy.

    Returns:
        True when the alpha, mip layout and sampler state are unchanged.

        The comparison leaves both inputs unchanged.
        It does not copy any image or mip buffers.
    """
    if source.width != cached.width:
        return False
    if source.height != cached.height:
        return False
    if source.texel_type != cached.texel_type:
        return False
    if source.wrap_s != cached.wrap_s:
        return False
    if source.wrap_t != cached.wrap_t:
        return False
    if source.mag_filter != cached.mag_filter:
        return False
    if source.min_filter != cached.min_filter:
        return False
    if source.flip_y != cached.flip_y:
        return False
    if source.mapping != cached.mapping:
        return False
    if source.color_space != cached.color_space:
        return False
    if source.alpha != cached.alpha:
        return False
    if source.levels != cached.levels:
        return False
    if source.offsets != cached.offsets:
        return False
    if source.ramp != cached.ramp:
        return False
    if source.offset != cached.offset:
        return False
    if source.repeat != cached.repeat:
        return False
    if source.rotation != cached.rotation:
        return False
    if source.center != cached.center:
        return False
    if source.anisotropy != cached.anisotropy:
        return False
    if source.channel != cached.channel:
        return False
    if len(source.pixels) != len(cached.pixels):
        return False
    if len(source.data) != len(cached.data):
        return False
    for i in range(3, len(source.pixels), 4):
        if source.pixels[i] != cached.pixels[i]:
            return False
    for i in range(3, len(source.data), 4):
        if bitcast[DType.uint32](source.data[i]) != bitcast[DType.uint32](
            cached.data[i]
        ):
            return False
    return True


def sensor_material_matches(
    source: Material, cached: Material, map: TextureId
) -> Bool:
    """Return whether a flat override keeps the source's coverage state.

    Args:
        source: The current source material.
        cached: The owned override for the same source and semantic tag.
        map: The current white-RGB coverage texture, or no texture.

    Returns:
        True when all copied coverage and clipping fields are unchanged.

        The comparison leaves both inputs unchanged.
        It does not create an override material.
    """
    if cached.map != map:
        return False
    if source.side != cached.side:
        return False
    if source.opacity != cached.opacity:
        return False
    if source.alpha_map != cached.alpha_map:
        return False
    if source.alpha_test != cached.alpha_test:
        return False
    if source.visible != cached.visible:
        return False
    if source.alpha_hash != cached.alpha_hash:
        return False
    if source.alpha_to_coverage != cached.alpha_to_coverage:
        return False
    if source.clip_plane_count != cached.clip_plane_count:
        return False
    if source.clip_intersection != cached.clip_intersection:
        return False
    if source.clip_shadows != cached.clip_shadows:
        return False
    return source._clip_planes == cached._clip_planes
