# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A port of three.js's `VolumeNodeMaterial`, `src/materials/nodes/
VolumeNodeMaterial.js`, and its `VolumetricLightingModel`: light and
shadow gathered along a ray through a mesh.

A `VOLUME` material marches a ray for each fragment. A camera farther from
the fragment than twice the mesh's bounding radius sends the ray from
itself to the fragment. A camera nearer than that, or inside, sends it
from the fragment to the camera. The ray takes `steps` equal steps. The
graph's `OFFSET_NODE` moves its start by that share of one step, which
breaks up the bands.

At each step the point and spot lights add their color, times their
shadow twice, to the density: `Lighting.volume_light_at`. Rectangles add
the camera-space volume LTC term, raised to the power 1.5 per channel.
An explicit opaque-scene depth input gates each original ray sample.
The graph's
`SCATTERING_NODE` multiplies the density; its `position_world` node reads
the step's position, as three.js's context hands `positionRay` to
`scatteringNode`. Beer's law then thins what the ray lets through by
`exp(-density * 0.01 * step)`. The surface shows one minus what is let
through, and the material's alpha.

Both rasterizers call `volumetric_light` with their own `RayLights`: the
host's `LitRay` over a `Lighting`, and the kernel's over its light buffer.

**Differences from r186.** The outgoing result remains one minus
transmittance; r186 accumulates outgoing light and ray emission separately.
Depth compares signed camera-axis distances on both projections. This
corrects r186's orthographic mixed-space gate: with near=1, far=9, a sample
at distance 2 is before an opaque surface at 3, but r186 compares the
sample's perspective depth 0.5625 with orthographic scene depth 0.25 and
rejects it. Our gate admits that sample, as axial ordering requires.
The reversed-perspective path has the inverse error: for the same planes,
forward sample depth 0.75 at distance 3 decodes as distance 9/7, so r186
admits it through a surface at distance 2. The axial gate rejects it.
"""

from lights.lighting import Lighting
from materials.material import (
    BACK_SIDE,
    DEFAULT_STEPS,
    VOLUME,
    Material,
)
from materials.nodes import (
    NO_NODES,
    NodeInputs,
    NodeProgramId,
    NodeSource,
    SCATTERING_NODE,
    run_nodes,
)
from math.vector3 import Vector3
from render.framebuffer import Color
from std.math import exp, inf, max, min
from units.si import Length, METER


# three.js's Beer's law constant: `scatteringDensity.mul( .01 )`.
comptime DENSITY_SCALE = Float32(0.01)


trait RayLights:
    """What a volume's ray reads at each step: the light the lights with a
    distance send there. The host's is `LitRay`; the kernel has its own
    over its light buffer."""

    def light_at(self, position: Vector3) -> Vector3:
        """Return the light that reaches one step of the ray.

        Args:
            position: Where the step is, in world space.

        Returns:
            The light, linear: three.js's `scatteringDensity` before the
            scattering node.
        """
        ...


struct LitRay[origin: Origin[mut=False]](ImplicitlyCopyable, RayLights):
    """The host's `RayLights`: a `Lighting`, and the surface the ray
    starts from, for the shadow maps' normal bias."""

    var lighting: Pointer[Lighting, Self.origin]
    var normal: Vector3
    var receives: Bool

    def __init__(
        out self,
        lighting: Pointer[Lighting, Self.origin],
        normal: Vector3,
        receives: Bool,
    ):
        """Read the lights of a `Lighting`.

        Args:
            lighting: The lights.
            normal: The unit normal of the fragment the ray starts at.
            receives: Whether the lights' shadows fall on the volume.
        """
        self.lighting = lighting
        self.normal = normal
        self.receives = receives

    def light_at(self, position: Vector3) -> Vector3:
        """Return `Lighting.volume_light_at` at one step.

        Args:
            position: Where the step is, in world space.

        Returns:
            The light, linear.
        """
        return self.lighting[].volume_light_at(
            position, self.normal, self.receives
        )


def _saturated(value: Float32) -> Float32:
    """Return a value held between zero and one."""
    return max(Float32(0), min(Float32(1), value))


def _thinned(through: Float32, density: Float32, step: Float32) -> Float32:
    """Return what a ray lets through after one step: three.js's
    `transmittance.mulAssign( scatteringDensity.mul( .01 ).negate().mul(
    stepSize ).exp() )`, for one channel."""
    return through * exp(-(density * DENSITY_SCALE) * step)


def volumetric_light[
    L: RayLights, S: NodeSource
](
    lights: L,
    source: S,
    scattered: Bool,
    inputs: NodeInputs,
    eye: Vector3,
    radius: Float32,
    steps: Int,
    offset: Float32,
    scene_depth: Length = Length(inf[DType.float32](), METER),
    view_back: Vector3 = Vector3(0, 0, 1),
) -> Vector3:
    """Return the light a volume's ray gathers for one fragment: three.js's
    depth gate and light inputs from r186's `VolumetricLightingModel`.

    The outgoing result remains one minus transmittance. It does not
    implement r186's separate outgoing-light accumulation or ray emission.

    Args:
        lights: The lights the ray reads at each step.
        source: The fragment's program.
        scattered: Whether the program sets `SCATTERING_NODE`.
        inputs: The fragment's attributes. Its `position` is the fragment's
            world position; each step runs the scattering node with the
            step's position in its place.
        eye: Where the camera is, in world space: three.js's
            `cameraPosition`.
        radius: The mesh's bounding radius in world space, three.js's
            `modelRadius`.
        steps: How many steps the ray takes, from one.
        offset: The share of a step the ray starts at: the graph's
            `OFFSET_NODE`, or zero.
        scene_depth: The opaque scene's signed camera-axis distance at
            this raster sample. Infinity means no depth input. Each step
            at or before this distance contributes, including equality.
            The gate does not move or resize the ray's steps.
        view_back: The camera's unit world-space backward axis.

    Returns:
        One minus what the ray lets through, per channel, linear: the
        surface's outgoing light.
    """
    var start = eye
    var end = inputs.position
    if not ((eye - inputs.position).length() > radius * 2):
        start = inputs.position
        end = eye
    var view = end - start
    var step = view.length() / Float32(steps)
    var direction = view
    direction.normalize()
    var travelled = offset * step
    var red = Float32(1)
    var green = Float32(1)
    var blue = Float32(1)
    var given = inputs
    for _ in range(steps):
        var at = start + direction * travelled
        # r186 gates scattering at each original sample. It does not
        # truncate the ray and redistribute its steps, or clip at near.
        if (eye - at).dot(view_back) > scene_depth.value:
            travelled += step
            continue
        var density = lights.light_at(at)
        if scattered:
            given.position = at
            var thick = run_nodes(source, SCATTERING_NODE, given)[0]
            density = density * thick
        red = _thinned(red, density.x, step)
        green = _thinned(green, density.y, step)
        blue = _thinned(blue, density.z, step)
        travelled += step
    return Vector3(
        1 - _saturated(red), 1 - _saturated(green), 1 - _saturated(blue)
    )


def volume_node_material(
    color: Color = Color(255, 255, 255),
    steps: Int = DEFAULT_STEPS,
    nodes: NodeProgramId = NO_NODES,
    opacity: Float32 = 1.0,
    scene_depth: Bool = False,
) raises -> Material:
    """Return three.js's `VolumeNodeMaterial` at its defaults: a `VOLUME`
    surface drawn from its back faces, blended, with no depth test and no
    depth write.

    Args:
        color: The color, as authored in sRGB. Only its alpha reaches the
            pixel; the ray's light replaces the rest.
        steps: How many steps a ray takes, three.js's `steps`.
        nodes: The graph with the `SCATTERING_NODE` and the `OFFSET_NODE`,
            or `NO_NODES`.
        opacity: The alpha, from zero to one.
        scene_depth: Capture opaque scene depth before any volume and gate
            scattering against it. False preserves the ungated ray.

    Returns:
        The material.

    Raises:
        Error: If `steps` is below one, `opacity` is outside zero to one,
            or `nodes` is a negative other than `NO_NODES`.
    """
    var material = Material(
        color,
        side=BACK_SIDE,
        opacity=opacity,
        kind=VOLUME,
        transparent=True,
        nodes=nodes,
    )
    material.depth_test = False
    material.depth_write = False
    material.set_steps(steps)
    material.set_volume_scene_depth(scene_depth)
    return material
