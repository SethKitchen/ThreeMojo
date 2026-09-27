# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""three.js's `MeshPostProcessingMaterial`,
`examples/jsm/materials/MeshPostProcessingMaterial.js` (r175): a physical
material whose ambient occlusion is read from a post-processing pass's
target, such as a GTAO pass, at the fragment's own pixel.

three.js patches the physical shader's `aomap_fragment`. Here the same sum
is a node program's ambient occlusion node, which replaces the map's:

- the pass's texel at `gl_FragCoord.xy * aoPassMapScale`, its red;
- with an ambient occlusion map, the lower of that and the map's red, then
  three.js's `(ao - 1) * aoMapIntensity + 1` of it.

The physical shading then dims the indirect light and the specular light
by it, as it dims them by a map.
"""

from materials.nodes import AO_NODE, NodeGraph, NodeProgram
from render.texture_store import NO_TEXTURE, TextureId


def mesh_post_processing_program(
    ao_pass_map: TextureId,
    ao_pass_map_scale: Float32 = 1,
    ao_map: TextureId = NO_TEXTURE,
    ao_map_intensity: Float32 = 1,
) raises -> NodeProgram:
    """Return the program of three.js's `MeshPostProcessingMaterial`: its
    ambient occlusion from a pass's target.

    Give its id to a `PHYSICAL` material's `nodes`. Its uniforms are
    three.js's: `tAoPassMap`, `aoPassMapScale`, and with a map `aoMap` and
    `aoMapIntensity`.

    Args:
        ao_pass_map: The pass's target, as a texture, one texel per pixel
            of the frame times the scale.
        ao_pass_map_scale: How many of its texels a pixel spans, three.js's
            `aoPassMapScale`.
        ao_map: The material's own ambient occlusion map, or `NO_TEXTURE`.
        ao_map_intensity: How strongly the map darkens.

    Returns:
        The program.

    Raises:
        Error: If `ao_pass_map` names no texture.
    """
    if ao_pass_map == NO_TEXTURE:
        raise Error("A post-processing material needs the pass's target")
    var g = NodeGraph()
    var place = g.floor(
        g.mul(
            g.swizzle(g.frag_coord(), "xy"),
            g.uniform("aoPassMapScale", ao_pass_map_scale),
        )
    )
    var occlusion = g.swizzle(
        g.texture_load(
            g.texture_uniform("tAoPassMap", ao_pass_map), place, g.float(0)
        ),
        "x",
    )
    if ao_map != NO_TEXTURE:
        var mapped = g.swizzle(
            g.texture(g.texture_uniform("aoMap", ao_map), g.uv()), "x"
        )
        occlusion = g.min(occlusion, mapped)
        occlusion = g.mul(
            occlusion,
            g.add(
                g.mul(
                    g.sub(occlusion, g.float(1)),
                    g.uniform("aoMapIntensity", ao_map_intensity),
                ),
                g.float(1),
            ),
        )
    g.set_output(AO_NODE, occlusion)
    return g.compile()
