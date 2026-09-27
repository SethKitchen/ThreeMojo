# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The procedural wood of three.js's `WoodNodeMaterial`, from
`examples/jsm/materials/WoodNodeMaterial.js`:
a physical material whose color is procedural wood, built as a node graph.

The graph is three.js's, function by function: rings of warped distance
from the trunk's axis, splotches of noise, cells of a smooth Voronoi, and
two soft-light mixes. Its nineteen uniforms have three.js's names, so
`NodeProgram.set_uniform` changes them as three.js's material properties
do. `wood_preset` gives the ten genuses and the four finishes.

**Where this differs from three.js.** three.js reads the local position
through `transformationMatrix`. A fragment here has no local position, so
the graph reads the world position through it: for a mesh at the origin
the two agree, and otherwise put the inverse of the mesh's world matrix in
it. three.js darkens the color by the darkening of the preset it loads
first, teak's raw one, which is one, whatever the finish; so does this.
"""

from materials.material import Material, PHYSICAL
from materials.nodes import (
    COLOR_NODE,
    NodeGraph,
    NodeProgram,
    NodeProgramId,
    NodeRef,
)
from math.matrix4 import Matrix4
from render.framebuffer import Color
from std.math import pi


@fieldwise_init
struct WoodGenus(Equatable, ImplicitlyCopyable, Writable):
    """Which wood `wood_preset` gives, three.js's `WoodGenuses`, as a type
    rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the ten genuses.

        Returns:
            Whether the value names a genus.
        """
        return self.value >= 0 and self.value < 10


comptime TEAK = WoodGenus(0)
comptime WALNUT = WoodGenus(1)
comptime WHITE_OAK = WoodGenus(2)
comptime PINE = WoodGenus(3)
comptime POPLAR = WoodGenus(4)
comptime MAPLE = WoodGenus(5)
comptime RED_OAK = WoodGenus(6)
comptime CHERRY = WoodGenus(7)
comptime CEDAR = WoodGenus(8)
comptime MAHOGANY = WoodGenus(9)


@fieldwise_init
struct WoodFinish(Equatable, ImplicitlyCopyable, Writable):
    """How the wood is finished, three.js's `Finishes`: the clear coat on
    it, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four finishes.

        Returns:
            Whether the value names a finish.
        """
        return self.value >= 0 and self.value < 4


comptime RAW = WoodFinish(0)
comptime MATTE = WoodFinish(1)
comptime SEMIGLOSS = WoodFinish(2)
comptime GLOSS = WoodFinish(3)


@fieldwise_init
struct WoodParams(Copyable, Movable):
    """A wood's numbers, three.js's `GetWoodPreset` result."""

    var center_size: Float32
    var large_warp_scale: Float32
    var large_grain_stretch: Float32
    var small_warp_strength: Float32
    var small_warp_scale: Float32
    var fine_warp_strength: Float32
    var fine_warp_scale: Float32
    var ring_thickness: Float32
    var ring_bias: Float32
    var ring_size_variance: Float32
    var ring_variance_scale: Float32
    var bark_thickness: Float32
    var splotch_scale: Float32
    var splotch_intensity: Float32
    var cell_scale: Float32
    var cell_size: Float32
    var dark_grain_color: Color
    var light_grain_color: Color
    var clearcoat: Float32
    var clearcoat_roughness: Float32
    var clearcoat_darken: Float32


def _hex(value: Int) -> Color:
    """Return a color from a `0xRRGGBB` number."""
    return Color(
        UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
    )


def wood_preset(genus: WoodGenus, finish: WoodFinish) raises -> WoodParams:
    """Return a genus's numbers under a finish, three.js's
    `GetWoodPreset(genus, finish)`.

    Args:
        genus: Which wood.
        finish: Raw, or a matte, semigloss or gloss clear coat.

    Returns:
        The numbers.

    Raises:
        Error: If the genus or the finish is none there is.
    """
    if not genus.is_valid():
        raise Error("A wood genus is one of the ten")
    if not finish.is_valid():
        raise Error("A wood finish is raw, matte, semigloss or gloss")
    # centerSize, largeWarpScale, largeGrainStretch, smallWarpStrength,
    # smallWarpScale, fineWarpStrength, fineWarpScale, 1 / ringThickness,
    # ringBias, ringSizeVariance, ringVarianceScale, barkThickness,
    # splotchScale, splotchIntensity, cellScale, cellSize, and the two
    # colors, per genus in `WoodGenuses` order.
    var table: List[List[Float32]] = [
        [1.11, 0.32, 0.24, 0.059, 2, 0.006, 32.8, 34, 0.03, 0.03, 4.4, 0.3, 0.2, 0.541, 910, 0.1],
        [1.07, 0.42, 0.34, 0.016, 10.3, 0.028, 12.7, 32, 0.08, 0.03, 5.5, 0.98, 1.84, 0.97, 710, 0.31],
        [1.23, 0.21, 0.21, 0.034, 2.44, 0.01, 14.3, 34, 0.82, 0.16, 1.4, 0.7, 0.2, 0.541, 800, 0.28],
        [1.23, 0.21, 0.18, 0.041, 2.44, 0.006, 23.2, 24, 0.1, 0.07, 5, 0.35, 0.51, 3.32, 1480, 0.07],
        [1.43, 0.33, 0.18, 0.04, 4.3, 0.004, 33.6, 37, 0.07, 0.03, 3.8, 0.3, 1.92, 0.71, 830, 0.04],
        [1.4, 0.38, 0.25, 0.067, 2.5, 0.005, 33.6, 35, 0.1, 0.07, 4.6, 0.61, 0.46, 1.49, 800, 0.03],
        [1.21, 0.24, 0.25, 0.044, 2.54, 0.01, 14.5, 34, 0.92, 0.03, 5.6, 1.01, 0.28, 3.48, 800, 0.25],
        [1.33, 0.11, 0.33, 0.024, 2.48, 0.01, 15.3, 36, 0.02, 0.04, 6.5, 0.09, 1.27, 1.24, 1530, 0.15],
        [1.11, 0.39, 0.12, 0.061, 1.9, 0.006, 4.8, 25, 0.01, 0.07, 6.7, 0.1, 0.61, 2.54, 630, 0.19],
        [1.25, 0.26, 0.29, 0.044, 2.54, 0.01, 15.3, 38, 0.01, 0.33, 1.2, 0.07, 0.77, 1.39, 1400, 0.23],
    ]
    var darks: List[Int] = [
        0x0C0504, 0x311E13, 0x8B4C21, 0xC58355, 0x716347,
        0xB08969, 0xAF613B, 0x913F27, 0x9A5B49, 0x501D12,
    ]
    var lights: List[Int] = [
        0x926C50, 0x523424, 0xC57E43, 0xD19D61, 0x998966,
        0xBC9D7D, 0xE0A27A, 0xB45837, 0xAE745E, 0x6D3722,
    ]
    ref row = table[genus.value]
    # The clear coat of each finish, and how much it darkens.
    var clearcoat = Float32(1)
    var roughness = Float32(0)
    var darken = Float32(1)
    if finish == GLOSS:
        darken = 0.2
        roughness = 0.1
    elif finish == SEMIGLOSS:
        darken = 0.4
        roughness = 0.4
    elif finish == MATTE:
        darken = 0.6
        roughness = 1
    else:
        clearcoat = 0
    return WoodParams(
        row[0],
        row[1],
        row[2],
        row[3],
        row[4],
        row[5],
        row[6],
        1 / row[7],
        row[8],
        row[9],
        row[10],
        row[11],
        row[12],
        row[13],
        row[14],
        row[15],
        _hex(darks[genus.value]),
        _hex(lights[genus.value]),
        clearcoat,
        roughness,
        darken,
    )


def _map_range(
    mut g: NodeGraph,
    x: NodeRef,
    from_min: NodeRef,
    from_max: NodeRef,
    to_min: NodeRef,
    to_max: NodeRef,
) raises -> NodeRef:
    """Return three.js's `mapRange` with its clamp on: the value moved from
    one range to the other, then `max(min(result, to_max), to_min)`."""
    var factor = g.div(g.sub(x, from_min), g.sub(from_max, from_min))
    var result = g.add(to_min, g.mul(factor, g.sub(to_max, to_min)))
    return g.max(g.min(result, to_max), to_min)


def _hash3d(mut g: NodeGraph, p: NodeRef) raises -> NodeRef:
    """Return three.js's `hash3d`: three numbers from zero to one."""
    var p3 = g.fract(g.mul(p, g.vec3(0.1031, 0.1030, 0.0973)))
    p3 = g.add(
        p3, g.dot(p3, g.add(g.swizzle(p3, "yzx"), g.float(33.33)))
    )
    return g.fract(
        g.mul(
            g.add(g.swizzle(p3, "xxy"), g.swizzle(p3, "yzz")),
            g.swizzle(p3, "zyx"),
        )
    )


def _voronoi3d(
    mut g: NodeGraph, x: NodeRef, smoothness: Float32, randomness: Float32
) raises -> NodeRef:
    """Return three.js's `voronoi3d`: the distance to the cells' jittered
    centers around `x`, weighted by how near each is, eased."""
    var p = g.floor(x)
    var f = g.fract(x)
    var spread = g.float(max(smoothness * smoothness, 0.001))
    # The weighted distances and the weights, summed as one `vec2`: two
    # sums would keep every weight alive until the second read it.
    var sums = g.vec2(0, 0)
    for k in range(-1, 2):
        for j in range(-1, 2):
            for i in range(-1, 2):
                var b = g.vec3(Float32(i), Float32(j), Float32(k))
                var offset = g.mul(
                    _hash3d(g, g.add(p, b)), g.float(randomness)
                )
                var d = g.length(g.add(g.sub(b, f), offset))
                var weight = g.exp(g.div(g.negate(g.mul(d, d)), spread))
                sums = g.add(sums, g.join([g.mul(d, weight), weight]))
    var res = g.swizzle(sums, "x")
    var total = g.swizzle(sums, "y")
    var averaged = g.select(
        g.greater_than(total, g.float(0)), g.div(res, total), res
    )
    return g.smoothstep(g.float(0), g.float(1), averaged)


def _soft_light_mix(
    mut g: NodeGraph, t: NodeRef, col1: NodeRef, col2: NodeRef
) raises -> NodeRef:
    """Return three.js's `softLightMix` of two colors by `t`."""
    var one = g.vec3(1, 1, 1)
    var screen = g.sub(one, g.mul(g.sub(one, col2), g.sub(one, col1)))
    var light = g.add(
        g.mul(g.mul(g.sub(one, col1), col2), col1), g.mul(col1, screen)
    )
    return g.add(g.mul(g.one_minus(t), col1), g.mul(t, light))


def _noise1(mut g: NodeGraph, p: NodeRef) raises -> NodeRef:
    """Return three.js's `noise1Norm`: Perlin noise from zero to one."""
    return g.mx_noise_float(p, 0.5, 0.5)


def _space_warp(
    mut g: NodeGraph,
    p: NodeRef,
    strength: NodeRef,
    xy_scale: NodeRef,
    z_scale: NodeRef,
) raises -> NodeRef:
    """Return three.js's `spaceWarp`: `p` flattened onto the plane across
    the trunk and pushed out along its own direction by noise."""
    var combined = g.mul(g.join([xy_scale, xy_scale, z_scale]), p)
    var noise = g.mul(
        g.sub(g.mx_noise_vec3(g.mul(combined, g.float(1.6 * 1.5)), 0.5, 0.5), g.float(0.5)),
        strength,
    )
    var flat = g.mul(p, g.vec3(1, 1, 0))
    return g.add(g.mul(noise, g.normalize(flat)), flat)


def _wood_rings(
    mut g: NodeGraph,
    w: NodeRef,
    thickness: NodeRef,
    bias: NodeRef,
    size_variance: NodeRef,
    variance_scale: NodeRef,
    bark: NodeRef,
) raises -> NodeRef:
    """Return three.js's `woodRings` at a distance `w` from the trunk."""
    var scaled = g.mul(w, variance_scale)
    var noise = _noise1(g, g.join([scaled, scaled, scaled]))
    var rings = g.mul(
        g.fract(g.mul(g.add(g.mul(noise, size_variance), w), thickness)),
        bark,
    )
    var zero = g.float(0)
    var one = g.float(1)
    var sharp = g.min(
        _map_range(g, rings, zero, bias, zero, one),
        _map_range(g, rings, bias, one, one, zero),
    )
    var blur = g.max(
        g.div(g.length(g.position_view()), g.float(10)), g.float(1)
    )
    return g.add(
        g.mul(
            g.smoothstep(g.negate(blur), blur, g.sub(sharp, g.float(0.5))),
            g.float(0.5),
        ),
        g.float(0.5),
    )


def _wood_detail(
    mut g: NodeGraph,
    warp: NodeRef,
    p: NodeRef,
    y: NodeRef,
    splotch_scale: NodeRef,
) raises -> NodeRef:
    """Return three.js's `woodDetail`: noise around the trunk and along
    it."""
    var turn = Float32(2 * pi)
    var around = g.clamp(
        g.add(
            g.div(
                g.atan2(g.swizzle(warp, "y"), g.swizzle(warp, "x")),
                g.float(turn),
            ),
            g.float(0.5),
        ),
        g.float(0),
        g.float(1),
    )
    var radial = g.mul(around, g.float(turn * 3))
    var combined = g.join(
        [g.sin(radial), y, g.mul(g.cos(radial), g.swizzle(p, "z"))]
    )
    var scaled = g.mul(g.vec3(0.1, 1.19, 0.05), combined)
    return _noise1(g, g.mul(scaled, splotch_scale))


def _cell_structure(
    mut g: NodeGraph, p: NodeRef, cell_scale: NodeRef, cell_size: NodeRef
) raises -> NodeRef:
    """Return three.js's `cellStructure`: the wood's pores, a smooth
    Voronoi of the warped place."""
    var warp = _space_warp(
        g,
        g.mul(p, g.div(cell_scale, g.float(50))),
        g.div(cell_scale, g.float(1000)),
        g.float(0.1),
        g.float(1.77),
    )
    var cells = _voronoi3d(
        g,
        g.join([g.mul(g.swizzle(warp, "xy"), g.float(75)), g.float(0)]),
        0.5,
        1,
    )
    return _map_range(
        g,
        cells,
        cell_size,
        g.add(cell_size, g.float(0.21)),
        g.float(0),
        g.float(1),
    )


def wood_program(params: WoodParams) raises -> NodeProgram:
    """Return the program of three.js's `WoodNodeMaterial`: its color node,
    with its uniforms set to a preset's numbers.

    The uniforms are three.js's material properties by name:
    `centerSize`, `largeWarpScale`, `largeGrainStretch`,
    `smallWarpStrength`, `smallWarpScale`, `fineWarpStrength`,
    `fineWarpScale`, `ringThickness`, `ringBias`, `ringSizeVariance`,
    `ringVarianceScale`, `barkThickness`, `splotchScale`,
    `splotchIntensity`, `cellScale`, `cellSize`, `darkGrainColor`,
    `lightGrainColor` and `transformationMatrix`.

    Args:
        params: The numbers, from `wood_preset`.

    Returns:
        The program; give its id to `wood_material`.

    Raises:
        Error: If the graph cannot be compiled, which the tests rule out.
    """
    var g = NodeGraph()
    var center_size = g.uniform("centerSize", params.center_size)
    var large_warp_scale = g.uniform("largeWarpScale", params.large_warp_scale)
    var large_grain_stretch = g.uniform(
        "largeGrainStretch", params.large_grain_stretch
    )
    var small_warp_strength = g.uniform(
        "smallWarpStrength", params.small_warp_strength
    )
    var small_warp_scale = g.uniform("smallWarpScale", params.small_warp_scale)
    var fine_warp_strength = g.uniform(
        "fineWarpStrength", params.fine_warp_strength
    )
    var fine_warp_scale = g.uniform("fineWarpScale", params.fine_warp_scale)
    var ring_thickness = g.uniform("ringThickness", params.ring_thickness)
    var ring_bias = g.uniform("ringBias", params.ring_bias)
    var ring_size_variance = g.uniform(
        "ringSizeVariance", params.ring_size_variance
    )
    var ring_variance_scale = g.uniform(
        "ringVarianceScale", params.ring_variance_scale
    )
    var bark_thickness = g.uniform("barkThickness", params.bark_thickness)
    var splotch_scale = g.uniform("splotchScale", params.splotch_scale)
    var splotch_intensity = g.uniform(
        "splotchIntensity", params.splotch_intensity
    )
    var cell_scale = g.uniform("cellScale", params.cell_scale)
    var cell_size = g.uniform("cellSize", params.cell_size)
    var dark = g.uniform("darkGrainColor", params.dark_grain_color)
    var light = g.uniform("lightGrainColor", params.light_grain_color)
    var transform = g.uniform("transformationMatrix", Matrix4())
    var p = g.swizzle(
        g.mul(transform, g.join([g.position_world(), g.float(1)])), "xyz"
    )
    # three.js's `wood`, step by step.
    var center = _map_range(
        g,
        g.length(g.mul(p, g.vec3(1, 1, 0))),
        g.float(0),
        g.float(1),
        g.float(0),
        center_size,
    )
    var main_warp = _space_warp(
        g,
        _space_warp(g, p, center, large_warp_scale, large_grain_stretch),
        small_warp_strength,
        small_warp_scale,
        g.float(0.17),
    )
    var detail_warp = _space_warp(
        g, main_warp, fine_warp_strength, fine_warp_scale, g.float(0.17)
    )
    var reach = g.length(detail_warp)
    var rings = _wood_rings(
        g,
        reach,
        g.div(g.float(1), ring_thickness),
        ring_bias,
        ring_size_variance,
        ring_variance_scale,
        bark_thickness,
    )
    var detail = _wood_detail(g, detail_warp, p, reach, splotch_scale)
    var cells = _cell_structure(
        g,
        main_warp,
        cell_scale,
        g.div(
            cell_size,
            g.max(
                g.mul(g.length(g.position_view()), g.float(10)), g.float(1)
            ),
        ),
    )
    var base = g.mix(dark, light, rings)
    g.set_output(
        COLOR_NODE,
        _soft_light_mix(
            g,
            splotch_intensity,
            _soft_light_mix(g, g.float(0.407), base, cells),
            detail,
        ),
    )
    return g.compile()


def wood_material(
    program: NodeProgramId, params: WoodParams
) raises -> Material:
    """Return three.js's `WoodNodeMaterial`: a physical material with the
    wood's program as its color, and the finish's clear coat.

    Args:
        program: The id of `wood_program`'s program in the store.
        params: The numbers, for the clear coat.

    Returns:
        The material.

    Raises:
        Error: Never: a physical material takes a clear coat.
    """
    var material = Material(Color(255, 255, 255), kind=PHYSICAL, nodes=program)
    material.clearcoat = params.clearcoat
    material.clearcoat_roughness = params.clearcoat_roughness
    return material^
