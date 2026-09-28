# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A port of three.js's `MeshSSSNodeMaterial`, `src/materials/nodes/
MeshSSSNodeMaterial.js`: a physical surface that lets light through from
behind, and its `SSSLightingModel`.

A `PHYSICAL` material whose node graph sets `THICKNESS_COLOR_NODE` is a
`MeshSSSNodeMaterial`. Each light with a direction then adds

    (pow(saturate(dot(V, -H)), power) * scale + ambient) * color
        * attenuation * light

to the direct diffuse light, where `H` is the way to the light bent along
the normal by `distortion`. That is three.js's `SSSLightingModel.direct`,
before `PhysicalLightingModel.direct`. The thickness is part of the color:
three.js's examples multiply a thickness map's red into it.

The five numbers are outputs too: `THICKNESS_DISTORTION_NODE`,
`THICKNESS_AMBIENT_NODE`, `THICKNESS_ATTENUATION_NODE`,
`THICKNESS_POWER_NODE` and `THICKNESS_SCALE_NODE`. A graph that does not
set one takes three.js's default. Both rasterizers call `scatters`,
`thickness_of` and `subsurface_diffuse`, and sum the light through with
`lights.lighting.scattering_through`, so the two agree.
"""

from lights.lighting import Reflected
from materials.material import MaterialKind, PHYSICAL
from materials.nodes import (
    NodeInputs,
    NodeSource,
    THICKNESS_AMBIENT_NODE,
    THICKNESS_ATTENUATION_NODE,
    THICKNESS_COLOR_NODE,
    THICKNESS_DISTORTION_NODE,
    THICKNESS_POWER_NODE,
    THICKNESS_SCALE_NODE,
    NodeOutput,
    has_output,
    run_nodes,
)
from math.vector3 import Vector3


# three.js's `MeshSSSNodeMaterial` defaults: `thicknessDistortionNode`,
# `thicknessAmbientNode`, `thicknessAttenuationNode`, `thicknessPowerNode`
# and `thicknessScaleNode`.
comptime DEFAULT_THICKNESS_DISTORTION = Float32(0.1)
comptime DEFAULT_THICKNESS_AMBIENT = Float32(0.0)
comptime DEFAULT_THICKNESS_ATTENUATION = Float32(0.1)
comptime DEFAULT_THICKNESS_POWER = Float32(2.0)
comptime DEFAULT_THICKNESS_SCALE = Float32(10.0)


@fieldwise_init
struct Thickness(ImplicitlyCopyable):
    """What one fragment's graph says about the light through it: the six
    thickness nodes of three.js's `MeshSSSNodeMaterial`, run."""

    # The color of the light through, `thicknessColorNode`, linear.
    var color: Vector3
    # How far the normal bends the way to the light,
    # `thicknessDistortionNode`.
    var distortion: Float32
    # Light through from every side, `thicknessAmbientNode`.
    var ambient: Float32
    # How much of the light gets through, `thicknessAttenuationNode`.
    var attenuation: Float32
    # How tight the light through is, `thicknessPowerNode`.
    var power: Float32
    # How bright it is, `thicknessScaleNode`.
    var scale: Float32


def scatters[S: NodeSource](source: S, noded: Bool, kind: MaterialKind) -> Bool:
    """Return True if a fragment lets light through from behind: three.js's
    `useSSS`, a `thicknessColorNode` on a `MeshSSSNodeMaterial`.

    Args:
        source: The fragment's program.
        noded: Whether the fragment runs a program.
        kind: The material's kind. Only `PHYSICAL` scatters, as three.js's
            material extends `MeshPhysicalNodeMaterial`.

    Returns:
        Whether the program sets `THICKNESS_COLOR_NODE` on a `PHYSICAL`
        surface.
    """
    return (
        noded and kind == PHYSICAL and has_output(source, THICKNESS_COLOR_NODE)
    )


def _number[
    S: NodeSource
](
    source: S, output: NodeOutput, inputs: NodeInputs, default: Float32
) -> Float32:
    """Return what a `float` output computes, or the default where the
    graph does not set it."""
    if has_output(source, output):
        return run_nodes(source, output, inputs)[0]
    return default


def thickness_of[S: NodeSource](source: S, inputs: NodeInputs) -> Thickness:
    """Return a fragment's six thickness nodes, each run once, or three.js's
    default where the graph does not set it.

    Args:
        source: The fragment's program, one `scatters` answered True for.
        inputs: The fragment's attributes.

    Returns:
        The color and the five numbers.
    """
    var color = run_nodes(source, THICKNESS_COLOR_NODE, inputs)
    return Thickness(
        Vector3(color[0], color[1], color[2]),
        _number(
            source,
            THICKNESS_DISTORTION_NODE,
            inputs,
            DEFAULT_THICKNESS_DISTORTION,
        ),
        _number(
            source, THICKNESS_AMBIENT_NODE, inputs, DEFAULT_THICKNESS_AMBIENT
        ),
        _number(
            source,
            THICKNESS_ATTENUATION_NODE,
            inputs,
            DEFAULT_THICKNESS_ATTENUATION,
        ),
        _number(source, THICKNESS_POWER_NODE, inputs, DEFAULT_THICKNESS_POWER),
        _number(source, THICKNESS_SCALE_NODE, inputs, DEFAULT_THICKNESS_SCALE),
    )


def subsurface_diffuse(
    direct: Reflected, through: Vector3, thickness: Thickness
) -> Reflected:
    """Return a physical surface's direct light with the light through it
    added to the diffuse part: three.js's `reflectedLight.directDiffuse
    .addAssign( scatteringIllu.mul( thicknessAttenuationNode.mul( lightColor
    ) ) )`, summed over the lights. Not scaled by one over pi, as three.js
    adds it outside `BRDF_Lambert`.

    Args:
        direct: The sums from `Lighting.physical_at`, already scaled.
        through: The lights' colors times `scattering_through`, summed, as
            `Lighting.scattered_at` sums them with the thickness's numbers.
        thickness: The fragment's thickness nodes.

    Returns:
        The sums, the diffuse one with the light through added.
    """
    var att = thickness.attenuation
    return Reflected(
        Vector3(
            direct.diffuse.x + through.x * thickness.color.x * att,
            direct.diffuse.y + through.y * thickness.color.y * att,
            direct.diffuse.z + through.z * thickness.color.z * att,
        ),
        direct.specular,
        direct.clearcoat,
        direct.sheen,
    )
