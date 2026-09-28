# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""TSL's utility functions on a `NodeGraph`: triplanar mapping, sprite
sheets, oscillators, `remapClamp`, `rotate`, the equirectangular and matcap
coordinates, and the normal packings.

three.js: `src/nodes/utils/TriplanarTextures.js`, `SpriteSheetUV.js`,
`Oscillators.js`, `Remap.js`, `RotateNode.js`, `EquirectUV.js`,
`MatcapUV.js` and `Packing.js`.

Each function builds the nodes of three.js's function, in three.js's
order of operations, from the nodes `NodeGraph` already has. None adds an
instruction to the bytecode, so the CPU and the GPU run it with the one
interpreter. A function that three.js gives a default input takes an
`Optional` here, and `None` reads three.js's default.

**Where this differs from three.js.** `triplanar_textures` reads the world
position and normal by default. three.js reads the local ones, and a
fragment here has no local position. For a mesh at the origin, the two
are the same. Otherwise, give the position and the normal.
"""

from materials.nodes import (
    NODE_FLOAT,
    NODE_SAMPLER,
    NODE_VEC2,
    NODE_VEC3,
    NodeGraph,
    NodeRef,
    ValueType,
)
from math.euler import AXIS_X, AXIS_Y, EulerOrder, XYZ
from std.math import pi


def _expect(g: NodeGraph, node: NodeRef, type: ValueType, what: String) raises:
    """Refuse a node that is not of the type a function reads.

    Raises:
        Error: If the node is not of this graph or not of `type`.
    """
    var got = g.type_of(node)
    if got != type:
        raise Error(what + " reads a " + type.name() + ", not a " + got.name())


def _or(
    mut g: NodeGraph, given: Optional[NodeRef], default: Float32
) -> NodeRef:
    """Return the given node, or a constant `float` where none is given."""
    if Bool(given):
        return given.value()
    return g.float(default)


# --- triplanar mapping --------------------------------------------------------


def triplanar_textures(
    mut g: NodeGraph,
    texture_x: NodeRef,
    texture_y: Optional[NodeRef] = None,
    texture_z: Optional[NodeRef] = None,
    scale: Optional[NodeRef] = None,
    position: Optional[NodeRef] = None,
    normal: Optional[NodeRef] = None,
) raises -> NodeRef:
    """Return three textures projected along the three axes and blended by
    the normal, three.js's `triplanarTextures`.

    The blend is `normalize(abs(normal))`, divided by the sum of its
    components. The texture along `x` is read at `position.yz * scale`,
    along `y` at `position.zx * scale`, and along `z` at
    `position.xy * scale`.

    Args:
        g: The graph to build the nodes in.
        texture_x: A texture uniform, read along `x`.
        texture_y: A texture uniform, read along `y`; `texture_x` if none.
        texture_z: A texture uniform, read along `z`; `texture_x` if none.
        scale: A `float` that scales the position; one if none.
        position: A `vec3`; the world position if none.
        normal: A `vec3`; the world normal if none.

    Returns:
        A `vec4`, linear, with straight alpha.

    Raises:
        Error: If a texture is not a texture uniform of this graph, `scale`
            is not a `float`, or `position` or `normal` is not a `vec3`.
    """
    _expect(g, texture_x, NODE_SAMPLER, "triplanarTextures")
    var along_y = texture_y.value() if texture_y else texture_x
    var along_z = texture_z.value() if texture_z else texture_x
    _expect(g, along_y, NODE_SAMPLER, "triplanarTextures")
    _expect(g, along_z, NODE_SAMPLER, "triplanarTextures")
    var size = _or(g, scale, 1)
    _expect(g, size, NODE_FLOAT, "triplanarTextures' scale")
    var at = position.value() if position else g.position_world()
    var facing = normal.value() if normal else g.normal_world()
    _expect(g, at, NODE_VEC3, "triplanarTextures' position")
    _expect(g, facing, NODE_VEC3, "triplanarTextures' normal")
    var blend = g.normalize(g.abs(facing))
    blend = g.div(blend, g.dot(blend, g.vec3(1, 1, 1)))
    var cx = g.mul(
        g.texture(texture_x, g.mul(g.swizzle(at, "yz"), size)),
        g.swizzle(blend, "x"),
    )
    var cy = g.mul(
        g.texture(along_y, g.mul(g.swizzle(at, "zx"), size)),
        g.swizzle(blend, "y"),
    )
    var cz = g.mul(
        g.texture(along_z, g.mul(g.swizzle(at, "xy"), size)),
        g.swizzle(blend, "z"),
    )
    return g.add(g.add(cx, cy), cz)


def triplanar_texture(
    mut g: NodeGraph,
    texture_x: NodeRef,
    texture_y: Optional[NodeRef] = None,
    texture_z: Optional[NodeRef] = None,
    scale: Optional[NodeRef] = None,
    position: Optional[NodeRef] = None,
    normal: Optional[NodeRef] = None,
) raises -> NodeRef:
    """Return `triplanar_textures` of the same inputs, three.js's
    `triplanarTexture`.

    Args:
        g: The graph to build the nodes in.
        texture_x: A texture uniform, read along `x`.
        texture_y: A texture uniform, read along `y`; `texture_x` if none.
        texture_z: A texture uniform, read along `z`; `texture_x` if none.
        scale: A `float` that scales the position; one if none.
        position: A `vec3`; the world position if none.
        normal: A `vec3`; the world normal if none.

    Returns:
        A `vec4`, linear, with straight alpha.

    Raises:
        Error: As `triplanar_textures` raises.
    """
    return triplanar_textures(
        g, texture_x, texture_y, texture_z, scale, position, normal
    )


# --- sprite sheets ------------------------------------------------------------


def spritesheet_uv(
    mut g: NodeGraph,
    count: NodeRef,
    uv: Optional[NodeRef] = None,
    frame: Optional[NodeRef] = None,
) raises -> NodeRef:
    """Return the coordinate of one frame of a sprite sheet, three.js's
    `spritesheetUV`.

    Frames count from the top left, across and then down. The frame is
    `floor(mod(frame, width * height))`. Its column is `mod(frame, width)`
    and its row from the bottom is `height - ceil((frame + 1) / width)`.
    The answer is `(uv + vec2(column, row)) / count`.

    Args:
        g: The graph to build the nodes in.
        count: A `vec2`: the columns and the rows of the sheet.
        uv: A `vec2`, the coordinate in one frame; `uv()` if none.
        frame: A `float`, the frame; zero if none.

    Returns:
        A `vec2`.

    Raises:
        Error: If `count` or `uv` is not a `vec2`, or `frame` is not a
            `float`, of this graph.
    """
    _expect(g, count, NODE_VEC2, "spritesheetUV's count")
    var at = uv.value() if uv else g.uv()
    _expect(g, at, NODE_VEC2, "spritesheetUV's uv")
    var index = _or(g, frame, 0)
    _expect(g, index, NODE_FLOAT, "spritesheetUV's frame")
    var width = g.swizzle(count, "x")
    var height = g.swizzle(count, "y")
    var number = g.floor(g.mod(index, g.mul(width, height)))
    var column = g.mod(number, width)
    var row = g.sub(height, g.ceil(g.div(g.add(number, g.float(1)), width)))
    var scale = g.reciprocal(count)
    return g.mul(g.add(at, g.join([column, row])), scale)


# --- oscillators --------------------------------------------------------------


def _phase(mut g: NodeGraph, t: Optional[NodeRef]) raises -> NodeRef:
    """Return the oscillator's input: the given node or `time`."""
    var at = t.value() if t else g.time()
    _expect(g, at, NODE_FLOAT, "An oscillator")
    return at


def osc_sine(mut g: NodeGraph, t: Optional[NodeRef] = None) raises -> NodeRef:
    """Return a sine wave from zero to one with a period of one, three.js's
    `oscSine`: `sin((t + 0.75) * 2 * PI) * 0.5 + 0.5`.

    Args:
        g: The graph to build the nodes in.
        t: A `float`; `time` if none.

    Returns:
        A `float`, zero at `t = 0`.

    Raises:
        Error: If `t` is not a `float` of this graph.
    """
    var at = _phase(g, t)
    var wave = g.sin(g.mul(g.add(at, g.float(0.75)), g.float(Float32(pi * 2))))
    return g.add(g.mul(wave, g.float(0.5)), g.float(0.5))


def osc_square(mut g: NodeGraph, t: Optional[NodeRef] = None) raises -> NodeRef:
    """Return a square wave of zero and one with a period of one, three.js's
    `oscSquare`: `round(fract(t))`.

    Args:
        g: The graph to build the nodes in.
        t: A `float`; `time` if none.

    Returns:
        A `float`.

    Raises:
        Error: If `t` is not a `float` of this graph.
    """
    return g.round(g.fract(_phase(g, t)))


def osc_triangle(
    mut g: NodeGraph, t: Optional[NodeRef] = None
) raises -> NodeRef:
    """Return a triangle wave from zero to one with a period of one,
    three.js's `oscTriangle`: `abs(fract(t + 0.5) * 2 - 1)`.

    Args:
        g: The graph to build the nodes in.
        t: A `float`; `time` if none.

    Returns:
        A `float`, zero at `t = 0` and one at `t = 0.5`.

    Raises:
        Error: If `t` is not a `float` of this graph.
    """
    var rising = g.fract(g.add(_phase(g, t), g.float(0.5)))
    return g.abs(g.sub(g.mul(rising, g.float(2)), g.float(1)))


def osc_sawtooth(
    mut g: NodeGraph, t: Optional[NodeRef] = None
) raises -> NodeRef:
    """Return a sawtooth wave from zero to one with a period of one,
    three.js's `oscSawtooth`: `fract(t)`.

    Args:
        g: The graph to build the nodes in.
        t: A `float`; `time` if none.

    Returns:
        A `float`.

    Raises:
        Error: If `t` is not a `float` of this graph.
    """
    return g.fract(_phase(g, t))


# --- remap --------------------------------------------------------------------


def remap_clamp(
    mut g: NodeGraph,
    x: NodeRef,
    in_low: NodeRef,
    in_high: NodeRef,
    out_low: Optional[NodeRef] = None,
    out_high: Optional[NodeRef] = None,
) raises -> NodeRef:
    """Return `x` moved from one range to another and held inside the
    second, three.js's `remapClamp`:
    `clamp((x - inLow) / (inHigh - inLow)) * (outHigh - outLow) + outLow`.

    `NodeGraph.remap` is three.js's `remap`, which does not clamp.

    Args:
        g: The graph to build the nodes in.
        x: The value.
        in_low: Where the first range starts.
        in_high: Where it ends.
        out_low: Where the second range starts; zero if none.
        out_high: Where it ends; one if none.

    Returns:
        The node, of the widest type.

    Raises:
        Error: If any is not a node of this graph, or two are vectors of
            two sizes.
    """
    var low = _or(g, out_low, 0)
    var high = _or(g, out_high, 1)
    var t = g.saturate(g.div(g.sub(x, in_low), g.sub(in_high, in_low)))
    return g.add(g.mul(t, g.sub(high, low)), low)


# --- rotate -------------------------------------------------------------------


def _axis_matrix(
    mut g: NodeGraph, axis: Int, cosine: NodeRef, sine: NodeRef
) raises -> NodeRef:
    """Return three.js's rotation matrix about one axis, as `RotateNode`
    lays out its columns, without the fourth row and column."""
    var zero = g.float(0)
    var one = g.float(1)
    var minus = g.negate(sine)
    if axis == AXIS_X:
        return g.mat3(
            g.vec3(1, 0, 0),
            g.join([zero, cosine, sine]),
            g.join([zero, minus, cosine]),
        )
    if axis == AXIS_Y:
        return g.mat3(
            g.join([cosine, zero, minus]),
            g.vec3(0, 1, 0),
            g.join([sine, zero, cosine]),
        )
    return g.mat3(
        g.join([cosine, sine, zero]),
        g.join([minus, cosine, zero]),
        g.join([zero, zero, one]),
    )


def _axis_of(order: EulerOrder, place: Int) -> Int:
    """Return the axis an order turns about at a place: 0, 1 or 2."""
    if place == 0:
        return order.first
    if place == 1:
        return order.second
    return order.third


def rotate(
    mut g: NodeGraph,
    position: NodeRef,
    rotation: NodeRef,
    order: EulerOrder = XYZ,
) raises -> NodeRef:
    """Return a position turned about the origin, three.js's `rotate`.

    A `vec2` turns by a `float` angle in radians, counterclockwise, through
    `mat2(cos, sin, -sin, cos)`. A `vec3` turns by a `vec3` of angles about
    the three axes. The rotation is the product of the three axes'
    matrices in `order`, first on the left, as three.js's `RotateNode`
    multiplies them, and it multiplies the position.

    Args:
        g: The graph to build the nodes in.
        position: A `vec2` or a `vec3`.
        rotation: A `float` for a `vec2`, a `vec3` for a `vec3`, in radians.
        order: The order of the axes' matrices, `XYZ` by default.

    Returns:
        The node, of the position's type.

    Raises:
        Error: If `order` does not name three different axes, a node is not
            of this graph, or the types are not a pair above.
    """
    if not order.is_valid():
        raise Error("rotate's order must name three different axes")
    var type = g.type_of(position)
    if type == NODE_VEC2:
        _expect(g, rotation, NODE_FLOAT, "rotate of a vec2")
        var c = g.cos(rotation)
        var s = g.sin(rotation)
        var x = g.swizzle(position, "x")
        var y = g.swizzle(position, "y")
        return g.join(
            [
                g.sub(g.mul(c, x), g.mul(s, y)),
                g.add(g.mul(s, x), g.mul(c, y)),
            ]
        )
    _expect(g, position, NODE_VEC3, "rotate")
    _expect(g, rotation, NODE_VEC3, "rotate of a vec3")
    var cosines = g.cos(rotation)
    var sines = g.sin(rotation)
    var letters = List[String]()
    letters.append("x")
    letters.append("y")
    letters.append("z")
    var chain = NodeRef(-1)
    for place in range(3):  # pragma: no branch
        var axis = _axis_of(order, place)
        var matrix = _axis_matrix(
            g,
            axis,
            g.swizzle(cosines, letters[axis]),
            g.swizzle(sines, letters[axis]),
        )
        chain = matrix if place == 0 else g.mul(chain, matrix)
    return g.mul(chain, position)


# --- equirectangular and matcap coordinates -----------------------------------


def position_world_direction(mut g: NodeGraph) raises -> NodeRef:
    """Return the unit direction from the camera to the fragment, three.js's
    `positionWorldDirection`.

    Args:
        g: The graph to build the nodes in.

    Returns:
        A `vec3`.

    Raises:
        Error: Never; the nodes it builds always match.
    """
    return g.normalize(g.sub(g.position_world(), g.camera_position()))


def equirect_uv(
    mut g: NodeGraph, direction: Optional[NodeRef] = None
) raises -> NodeRef:
    """Return where a direction lands on an equirectangular map, three.js's
    `equirectUV`: `u = atan(d.z, d.x) / (2 PI) + 0.5` and
    `v = asin(clamp(d.y, -1, 1)) / PI + 0.5`.

    Args:
        g: The graph to build the nodes in.
        direction: A unit `vec3`; `position_world_direction` if none.

    Returns:
        A `vec2` from zero to one.

    Raises:
        Error: If `direction` is not a `vec3` of this graph.
    """
    var d = direction.value() if direction else position_world_direction(g)
    _expect(g, d, NODE_VEC3, "equirectUV")
    var u = g.add(
        g.mul(
            g.atan2(g.swizzle(d, "z"), g.swizzle(d, "x")),
            g.float(Float32(1 / (pi * 2))),
        ),
        g.float(0.5),
    )
    var v = g.add(
        g.mul(
            g.asin(g.clamp(g.swizzle(d, "y"), g.float(-1), g.float(1))),
            g.float(Float32(1 / pi)),
        ),
        g.float(0.5),
    )
    return g.join([u, v])


def equirect_direction(
    mut g: NodeGraph, uv: Optional[NodeRef] = None
) raises -> NodeRef:
    """Return the unit direction an equirectangular coordinate names,
    three.js's `equirectDirection`, the inverse of `equirect_uv`.

    Args:
        g: The graph to build the nodes in.
        uv: A `vec2`; `uv()` if none.

    Returns:
        A `vec3`.

    Raises:
        Error: If `uv` is not a `vec2` of this graph.
    """
    var at = uv.value() if uv else g.uv()
    _expect(g, at, NODE_VEC2, "equirectDirection")
    var theta = g.mul(
        g.sub(g.swizzle(at, "x"), g.float(0.5)), g.float(Float32(pi * 2))
    )
    var phi = g.mul(
        g.sub(g.swizzle(at, "y"), g.float(0.5)), g.float(Float32(pi))
    )
    var cos_phi = g.cos(phi)
    return g.join(
        [
            g.mul(cos_phi, g.cos(theta)),
            g.sin(phi),
            g.mul(cos_phi, g.sin(theta)),
        ]
    )


def matcap_uv(mut g: NodeGraph) raises -> NodeRef:
    """Return where the view normal reads a matcap, three.js's `matcapUV`.

    The view direction `d` is the unit vector from the fragment to the
    camera, in view space. `x = normalize(vec3(d.z, 0, -d.x))` and
    `y = cross(d, x)`. The answer is
    `vec2(dot(x, n), dot(y, n)) * 0.495 + 0.5`, `n` the view normal.

    Args:
        g: The graph to build the nodes in.

    Returns:
        A `vec2` from zero to one.

    Raises:
        Error: Never; the nodes it builds always match.
    """
    var d = g.normalize(g.negate(g.position_view()))
    var x = g.normalize(
        g.join([g.swizzle(d, "z"), g.float(0), g.negate(g.swizzle(d, "x"))])
    )
    var y = g.cross(d, x)
    var n = g.normal_view()
    var at = g.join([g.dot(x, n), g.dot(y, n)])
    return g.add(g.mul(at, g.float(0.495)), g.float(0.5))


# --- normal packing -----------------------------------------------------------


def pack_normal_to_rgb(mut g: NodeGraph, normal: NodeRef) raises -> NodeRef:
    """Return a unit vector as a color, three.js's `packNormalToRGB`:
    `n * 0.5 + 0.5`.

    Args:
        g: The graph to build the nodes in.
        normal: A `float` or a vector.

    Returns:
        The node, of the normal's type.

    Raises:
        Error: If `normal` is not a `float` or a vector of this graph.
    """
    return g.add(g.mul(normal, g.float(0.5)), g.float(0.5))


def unpack_rgb_to_normal(mut g: NodeGraph, rgb: NodeRef) raises -> NodeRef:
    """Return a color as a vector, three.js's `unpackRGBToNormal`:
    `c * 2 - 1`.

    Args:
        g: The graph to build the nodes in.
        rgb: A `float` or a vector.

    Returns:
        The node, of the color's type.

    Raises:
        Error: If `rgb` is not a `float` or a vector of this graph.
    """
    return g.sub(g.mul(rgb, g.float(2)), g.float(1))


def unpack_normal(mut g: NodeGraph, xy: NodeRef) raises -> NodeRef:
    """Return a unit normal from its first two components, three.js's
    `unpackNormal`: `vec3(xy, sqrt(saturate(1 - dot(xy, xy))))`.

    Args:
        g: The graph to build the nodes in.
        xy: A `vec2`.

    Returns:
        A `vec3`.

    Raises:
        Error: If `xy` is not a `vec2` of this graph.
    """
    _expect(g, xy, NODE_VEC2, "unpackNormal")
    var z = g.sqrt(g.saturate(g.sub(g.float(1), g.dot(xy, xy))))
    return g.join([xy, z])
