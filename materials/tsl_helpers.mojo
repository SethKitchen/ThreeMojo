# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The TSL helpers of three.js's examples on a `NodeGraph`: a ray marched
through a box, soft particles, and the GGX sampling helpers.

three.js: `examples/jsm/tsl/utils/Raymarching.js`, `SoftParticles.js` and
`SpecularHelpers.js`.

Each function builds the nodes of three.js's function, in three.js's
order of operations, from the nodes `NodeGraph` already has. None adds an
instruction to the bytecode, so the CPU and the GPU run it with the one
interpreter.

**Where this differs from three.js.**

- `RaymarchingBox` opens a block that `Raymarch.End` closes, as `Loop` and
  `End` do. three.js takes a callback instead. The bytecode has no jumps,
  so the loop runs a fixed count of times, enough for the longest ray
  through the box, and a `Break` stops it where three.js's loop ends.
- A fragment here has no local position and no model matrix, so the ray
  goes into the box's space through a `mat4` that the caller gives: the
  inverse of the box's world matrix.
- `soft_particles` reads the scene's depth from a node that the caller
  gives. This port keeps no depth of the opaque scene for a node to read.
- `normalize` leaves a zero vector at zero. So where the normal is `+z` or
  `-z`, `ggx_reflection_sample` takes its second frame, where a GPU's
  `normalize` gives NaN.
"""

from materials.tsl_check import _expect
from materials.nodes import (
    MAX_LOOP_COUNT,
    NODE_FLOAT,
    NODE_MAT4,
    NODE_VEC2,
    NODE_VEC3,
    NodeGraph,
    NodeRef,
    NodeVar,
    ValueType,
)
from materials.tsl_utils import equirect_uv
from std.math import ceil, pi
from units.si import Length, METER

# three.js's `ENV_RAY_LENGTH` and `ENV_RAY_LENGTH_THRESHOLD`: how far a ray
# that misses the scene is taken to go, and past which a hit is a miss.
comptime ENV_RAY_LENGTH = Length(1e4, METER)
comptime ENV_RAY_LENGTH_THRESHOLD = Length(1e3, METER)


def _floats(g: NodeGraph, nodes: List[NodeRef], what: String) raises:
    """Refuse a list of nodes unless each is a `float`.

    Raises:
        Error: If one is not a `float` of this graph.
    """
    for index in range(len(nodes)):  # pragma: no branch
        _expect(g, nodes[index], NODE_FLOAT, what)


# --- raymarching --------------------------------------------------------------


@fieldwise_init
struct Raymarch(ImplicitlyCopyable, Movable):
    """A ray that `RaymarchingBox` marches through its box: what three.js
    hands its callback, and the loop that `End` closes."""

    # three.js's `positionRay`: where the ray is this time through, in the
    # box's space. `End` moves it one step on.
    var position_ray: NodeVar
    # three.js's `stepSize`: how far one step goes, a `float`.
    var step_size: NodeRef
    # The ray's unit direction in the box's space, a `vec3`.
    var direction: NodeRef
    # How far along the ray the step is, three.js's loop index.
    var distance: NodeVar

    def End(self, mut g: NodeGraph) raises:
        """Move the ray one step on and close the loop, the end of
        three.js's `Loop` in `RaymarchingBox`.

        Args:
            g: The graph that `RaymarchingBox` opened the loop in.

        Raises:
            Error: If the graph holds no such variables or no loop is open.
        """
        var moved = g.mul(self.direction, self.step_size)
        g.assign(self.position_ray, g.add(g.get(self.position_ray), moved))
        g.assign(self.distance, g.add(g.get(self.distance), self.step_size))
        g.End()


def _hit_box(
    mut g: NodeGraph, origin: NodeRef, direction: NodeRef
) raises -> NodeRef:
    """Return three.js's `hitBox`: where a ray enters and leaves the box
    from -0.5 to 0.5, a `vec2` of distances along it."""
    var inverse = g.reciprocal(direction)
    var to_min = g.mul(g.sub(g.vec3(-0.5, -0.5, -0.5), origin), inverse)
    var to_max = g.mul(g.sub(g.vec3(0.5, 0.5, 0.5), origin), inverse)
    var near = g.min(to_min, to_max)
    var far = g.max(to_min, to_max)
    var t0 = g.max(
        g.swizzle(near, "x"),
        g.max(g.swizzle(near, "y"), g.swizzle(near, "z")),
    )
    var t1 = g.min(
        g.swizzle(far, "x"), g.min(g.swizzle(far, "y"), g.swizzle(far, "z"))
    )
    return g.join([t0, t1])


def raymarch_count(steps: Int) -> Int:
    """Return how many times `RaymarchingBox` unrolls its loop: enough for
    the longest ray through the box, the diagonal, at the shortest step.

    A step is the shortest of `1 / abs(direction)` over `steps`, at least
    `1 / steps`. The diagonal is the square root of three long.

    Args:
        steps: The `steps` of three.js.

    Returns:
        `ceil(sqrt(3) * steps) + 1`.
    """
    return Int(ceil(Float64(1.7320508075688772) * Float64(steps))) + 1


def RaymarchingBox(
    mut g: NodeGraph, steps: Int, world_to_local: NodeRef
) raises -> Raymarch:
    """Open a loop that marches a ray from the camera through the box from
    -0.5 to 0.5 of its space, three.js's `RaymarchingBox`.

    The ray starts where it enters the box, or at the camera inside it. A
    fragment whose ray misses the box is thrown away. Each step is the
    shortest of `1 / abs(direction)` over `steps`. The code between this
    call and `Raymarch.End` is the body of three.js's callback. It reads
    `position_ray` with `g.get`. The loop stops where the ray leaves the
    box.

    Args:
        g: The graph.
        steps: How many steps cross the box along its nearest axis, from
            one to where `raymarch_count` passes `MAX_LOOP_COUNT`.
        world_to_local: A `mat4`, the inverse of the box's world matrix.

    Returns:
        The ray.

    Raises:
        Error: If `steps` is below one or makes too long a loop, or
            `world_to_local` is not a `mat4` of this graph.
    """
    if steps < 1 or raymarch_count(steps) > MAX_LOOP_COUNT:
        raise Error(
            "RaymarchingBox takes from one step to "
            + String(MAX_LOOP_COUNT)
            + " times through its loop, not "
            + String(steps)
            + " steps"
        )
    _expect(g, world_to_local, NODE_MAT4, "RaymarchingBox's matrix")
    var origin = g.swizzle(
        g.mul(world_to_local, g.join([g.camera_position(), g.float(1)])),
        "xyz",
    )
    var local = g.swizzle(
        g.mul(world_to_local, g.join([g.position_world(), g.float(1)])),
        "xyz",
    )
    var direction = g.normalize(g.sub(local, origin))
    var bounds = _hit_box(g, origin, direction)
    var enter = g.swizzle(bounds, "x")
    var leave = g.swizzle(bounds, "y")
    g.If(g.greater_than(enter, leave))
    g.Discard()
    g.End()
    enter = g.max(enter, g.float(0))
    var inc = g.reciprocal(g.abs(direction))
    var step_size = g.div(
        g.min(
            g.swizzle(inc, "x"),
            g.min(g.swizzle(inc, "y"), g.swizzle(inc, "z")),
        ),
        g.float(Float32(steps)),
    )
    var position_ray = g.Var(g.add(origin, g.mul(enter, direction)))
    var distance = g.Var(enter)
    _ = g.Loop(raymarch_count(steps))
    g.If(g.greater_than_equal(g.get(distance), leave))
    g.Break()
    g.End()
    return Raymarch(position_ray, step_size, direction, distance)


# --- soft particles -----------------------------------------------------------


def perspective_depth_to_view_z(
    mut g: NodeGraph, depth: NodeRef, near: NodeRef, far: NodeRef
) raises -> NodeRef:
    """Return the view-space `z` of a perspective depth, three.js's
    `perspectiveDepthToViewZ`: `near * far / ((far - near) * depth - far)`.

    Args:
        g: The graph to build the nodes in.
        depth: A `float`, zero at the near plane and one at the far plane.
        near: A `float`, the near plane's distance in meters.
        far: A `float`, the far plane's distance in meters.

    Returns:
        A `float`, negative in front of the camera.

    Raises:
        Error: If one is not a `float` of this graph.
    """
    _floats(g, [depth, near, far], "perspectiveDepthToViewZ")
    return g.div(g.mul(near, far), g.sub(g.mul(g.sub(far, near), depth), far))


def contrast_curve(
    mut g: NodeGraph, input: NodeRef, power: NodeRef
) raises -> NodeRef:
    """Return three.js's `contrastCurve` of `SoftParticles.js`: an S curve
    from zero to one, steeper at one half as `power` grows.

    Args:
        g: The graph to build the nodes in.
        input: A `float` from zero to one.
        power: A `float`.

    Returns:
        A `float` from zero to one.

    Raises:
        Error: If one is not a `float` of this graph.
    """
    _floats(g, [input, power], "contrastCurve")
    var above_half = g.greater_than(input, g.float(0.5))
    var folded = g.select(above_half, g.one_minus(input), input)
    var output = g.mul(
        g.pow(g.saturate(g.mul(folded, g.float(2))), power), g.float(0.5)
    )
    return g.select(above_half, g.one_minus(output), output)


def soft_particles(
    mut g: NodeGraph,
    viewport_depth: NodeRef,
    near: Length,
    far: Length,
    opacity: Optional[NodeRef] = None,
    distance: Length = Length(1.0, METER),
    contrast: Float32 = 2,
) raises -> NodeRef:
    """Return a particle's opacity, faded where it nears the scene behind
    it, three.js's `softParticles`.

    The scene's view `z` is `perspective_depth_to_view_z` of the depth.
    The gap is `saturate((positionView.z - sceneZ) / distance)`, and the
    answer is `opacity * contrast_curve(gap, contrast)`.

    Args:
        g: The graph to build the nodes in.
        viewport_depth: A `float`, the opaque scene's depth at the
            fragment's pixel, zero at the near plane and one at the far
            plane. three.js reads `viewportDepthTexture()`.
        near: The camera's near plane.
        far: The camera's far plane.
        opacity: A `float`, the particle's opacity; one if none.
        distance: The gap over which the particle fades.
        contrast: How sharp the fade is.

    Returns:
        A `float`.

    Raises:
        Error: If `near` is not above zero, `far` is not past `near`,
            `distance` is not above zero, or a node is not a `float` of
            this graph.
    """
    var near_m = near.to(METER)
    var far_m = far.to(METER)
    if not (near_m > 0 and far_m > near_m):
        raise Error("softParticles needs 0 < near < far")
    if not (distance.to(METER) > 0):
        raise Error("softParticles needs a distance above zero")
    var alpha = opacity.value() if opacity else g.float(1)
    _floats(g, [viewport_depth, alpha], "softParticles")
    var scene_z = perspective_depth_to_view_z(
        g, viewport_depth, g.float(near_m), g.float(far_m)
    )
    var gap = g.saturate(
        g.div(
            g.sub(g.swizzle(g.position_view(), "z"), scene_z),
            g.float(distance.to(METER)),
        )
    )
    return g.mul(alpha, contrast_curve(g, gap, g.float(contrast)))


# --- specular helpers ---------------------------------------------------------


def sample_ggx_vndf(
    mut g: NodeGraph,
    v: NodeRef,
    ax: NodeRef,
    ay: NodeRef,
    r1: NodeRef,
    r2: NodeRef,
) raises -> NodeRef:
    """Return a microfacet normal drawn from GGX's bounded visible normals,
    three.js's `SampleGGXVNDF` (Eto and Tokuyoshi 2023).

    Args:
        g: The graph to build the nodes in.
        v: A `vec3`, the unit view direction in the surface's frame, `+z`
            along the normal.
        ax: A `float`, the roughness along `x`, GGX's alpha.
        ay: A `float`, the roughness along `y`.
        r1: A `float` from zero to one, the first random number.
        r2: A `float` from zero to one, the second random number.

    Returns:
        A unit `vec3` in the surface's frame.

    Raises:
        Error: If `v` is not a `vec3`, or another is not a `float`, of this
            graph.
    """
    _expect(g, v, NODE_VEC3, "SampleGGXVNDF")
    _floats(g, [ax, ay, r1, r2], "SampleGGXVNDF")
    var vx = g.swizzle(v, "x")
    var vy = g.swizzle(v, "y")
    var vz = g.swizzle(v, "z")
    var one = g.float(1)
    var zero = g.float(0)
    var wi = g.normalize(g.join([g.mul(ax, vx), g.mul(ay, vy), vz]))
    var a = g.min(ax, ay)
    var s = g.add(one, g.length(g.swizzle(v, "xy")))
    var a2 = g.mul(a, a)
    var s2 = g.mul(s, s)
    var k = g.div(
        g.mul(g.one_minus(a2), s2), g.add(s2, g.mul(g.mul(a2, vz), vz))
    )
    var b = g.mul(g.swizzle(wi, "z"), k)
    var phi = g.mul(g.float(Float32(6.283185307179586)), r1)
    var z = g.sub(g.mul(g.one_minus(r2), g.add(one, b)), b)
    var sin_theta = g.sqrt(g.max(zero, g.sub(one, g.mul(z, z))))
    var c = g.join(
        [g.mul(sin_theta, g.cos(phi)), g.mul(sin_theta, g.sin(phi)), z]
    )
    var wm = g.add(c, wi)
    return g.normalize(
        g.join(
            [
                g.mul(ax, g.swizzle(wm, "x")),
                g.mul(ay, g.swizzle(wm, "y")),
                g.max(zero, g.swizzle(wm, "z")),
            ]
        )
    )


def d_gtr(
    mut g: NodeGraph, roughness: NodeRef, n_dot_h: NodeRef, k: NodeRef
) raises -> NodeRef:
    """Return the generalized Trowbridge-Reitz distribution, three.js's
    `D_GTR`: `a2 / (PI * pow(NoH ** 2 * (a2 - 1) + 1, k))`, `a2` the
    roughness squared. `k = 2` is GGX.

    Args:
        g: The graph to build the nodes in.
        roughness: A `float`, GGX's alpha.
        n_dot_h: A `float`, the normal dotted with the half vector.
        k: A `float`, the exponent.

    Returns:
        A `float`.

    Raises:
        Error: If one is not a `float` of this graph.
    """
    _floats(g, [roughness, n_dot_h, k], "D_GTR")
    var a2 = g.mul(roughness, roughness)
    var n_dot_h2 = g.mul(n_dot_h, n_dot_h)
    var base = g.add(g.mul(n_dot_h2, g.sub(a2, g.float(1))), g.float(1))
    return g.div(a2, g.mul(g.float(Float32(pi)), g.pow(base, k)))


def smith_g(
    mut g: NodeGraph, n_dot_x: NodeRef, alpha: NodeRef
) raises -> NodeRef:
    """Return Smith's masking of one direction, three.js's `SmithG`:
    `2 NoX / (NoX + sqrt(a2 + (1 - a2) NoX ** 2))`.

    Args:
        g: The graph to build the nodes in.
        n_dot_x: A `float`, the normal dotted with the direction.
        alpha: A `float`, GGX's alpha, not squared.

    Returns:
        A `float`.

    Raises:
        Error: If one is not a `float` of this graph.
    """
    _floats(g, [n_dot_x, alpha], "SmithG")
    var a2 = g.mul(alpha, alpha)
    var n_dot_x2 = g.mul(n_dot_x, n_dot_x)
    return g.div(
        g.mul(g.float(2), n_dot_x),
        g.add(
            n_dot_x,
            g.sqrt(g.add(a2, g.mul(g.one_minus(a2), n_dot_x2))),
        ),
    )


def geometry_term(
    mut g: NodeGraph, n_dot_l: NodeRef, n_dot_v: NodeRef, alpha: NodeRef
) raises -> NodeRef:
    """Return Smith's masking and shadowing, three.js's `GeometryTerm`:
    `SmithG(NoV, alpha) * SmithG(NoL, alpha)`.

    Args:
        g: The graph to build the nodes in.
        n_dot_l: A `float`, the normal dotted with the light.
        n_dot_v: A `float`, the normal dotted with the view.
        alpha: A `float`, GGX's alpha, not squared.

    Returns:
        A `float`.

    Raises:
        Error: If one is not a `float` of this graph.
    """
    var view = smith_g(g, n_dot_v, alpha)
    return g.mul(view, smith_g(g, n_dot_l, alpha))


def ggx_vndf_pdf(
    mut g: NodeGraph, n_dot_h: NodeRef, n_dot_v: NodeRef, roughness: NodeRef
) raises -> NodeRef:
    """Return the density of a direction that `sample_ggx_vndf` draws,
    three.js's `GGXVNDFPdf`: `D / max(1e-6, 2 (k NoV + t))`.

    Args:
        g: The graph to build the nodes in.
        n_dot_h: A `float`, the normal dotted with the half vector.
        n_dot_v: A `float`, the normal dotted with the view.
        roughness: A `float`, GGX's alpha.

    Returns:
        A `float`.

    Raises:
        Error: If one is not a `float` of this graph.
    """
    _floats(g, [n_dot_h, n_dot_v, roughness], "GGXVNDFPdf")
    var d = d_gtr(g, roughness, n_dot_h, g.float(2))
    var a2 = g.mul(roughness, roughness)
    var one = g.float(1)
    var sin_v2 = g.max(g.float(0), g.sub(one, g.mul(n_dot_v, n_dot_v)))
    var s = g.add(one, g.sqrt(sin_v2))
    var s2 = g.mul(s, s)
    var k = g.div(
        g.mul(g.sub(one, a2), s2),
        g.add(s2, g.mul(g.mul(a2, n_dot_v), n_dot_v)),
    )
    var t = g.sqrt(g.add(g.mul(a2, sin_v2), g.mul(n_dot_v, n_dot_v)))
    return g.div(
        d,
        g.max(
            g.float(1e-6),
            g.mul(g.float(2), g.add(g.mul(k, n_dot_v), t)),
        ),
    )


def f_schlick(mut g: NodeGraph, f0: NodeRef, theta: NodeRef) raises -> NodeRef:
    """Return Schlick's Fresnel of `SpecularHelpers.js`, three.js's
    `F_Schlick`: `f0 + (1 - f0) (1 - theta) ** 5`.

    Args:
        g: The graph to build the nodes in.
        f0: A `vec3`, the reflectance at normal incidence.
        theta: A `float`, the cosine of the angle.

    Returns:
        A `vec3`.

    Raises:
        Error: If `f0` is not a `vec3`, or `theta` is not a `float`, of
            this graph.
    """
    _expect(g, f0, NODE_VEC3, "F_Schlick")
    _expect(g, theta, NODE_FLOAT, "F_Schlick's theta")
    var one_minus = g.sub(g.float(1), theta)
    var one_minus2 = g.mul(one_minus, one_minus)
    var one_minus5 = g.mul(g.mul(one_minus2, one_minus2), one_minus)
    return g.add(f0, g.mul(g.sub(g.vec3(1, 1, 1), f0), one_minus5))


def get_specular_dominant_factor(
    mut g: NodeGraph, n_dot_v: NodeRef, roughness: NodeRef
) raises -> NodeRef:
    """Return how far toward the reflection the specular lobe leans,
    three.js's `getSpecularDominantFactor`:
    `clamp((1 - NoV) ** 10.8649 * (1 - a) + a)`, where
    `a = 0.298475 * log(39.4115 - 39.0029 * roughness)`.

    Args:
        g: The graph to build the nodes in.
        n_dot_v: A `float`, the normal dotted with the view.
        roughness: A `float`.

    Returns:
        A `float` from zero to one.

    Raises:
        Error: If one is not a `float` of this graph.
    """
    _floats(g, [n_dot_v, roughness], "getSpecularDominantFactor")
    var a = g.mul(
        g.float(0.298475),
        g.log(g.sub(g.float(39.4115), g.mul(g.float(39.0029), roughness))),
    )
    var f = g.add(
        g.mul(
            g.pow(g.sub(g.float(1), n_dot_v), g.float(10.8649)),
            g.sub(g.float(1), a),
        ),
        a,
    )
    return g.saturate(f)


@fieldwise_init
struct GgxReflectionSample(ImplicitlyCopyable, Movable):
    """What `ggx_reflection_sample` gives, three.js's `ggxReflectionStruct`:
    six nodes."""

    # A unit `vec3`: the reflected ray in view space.
    var reflect_dir: NodeRef
    # A `vec3`: what the gathered light is multiplied by, Fresnel's tint in.
    var sample_weight: NodeRef
    # A `float`: the direction's density, for multiple importance sampling.
    var pdf: NodeRef
    # A `float`: the normal dotted with the view, from zero.
    var n_dot_v: NodeRef
    # A `float`: GGX's alpha, the roughness squared, at least 0.001.
    var alpha: NodeRef
    # A `vec3`: the reflectance at normal incidence.
    var f0: NodeRef


def ggx_reflection_sample(
    mut g: NodeGraph,
    n: NodeRef,
    v: NodeRef,
    roughness: NodeRef,
    metalness: NodeRef,
    albedo: NodeRef,
    xi: NodeRef,
) raises -> GgxReflectionSample:
    """Return one GGX reflection drawn from the bounded visible normals and
    its weight, three.js's `ggxReflectionSample`.

    The frame is `T = normalize(cross(+z, N))`, or `cross(+y, N)` where
    that is shorter than 0.001, and `B = normalize(cross(N, T))`. The
    weight is `F * G2 * (k NoV + t) / max(2 NoV, 1e-4)`, which cancels the
    distribution, as three.js writes it.

    Args:
        g: The graph to build the nodes in.
        n: A unit `vec3`, the view-space normal.
        v: A unit `vec3`, from the surface to the camera in view space.
        roughness: A `float`.
        metalness: A `float`.
        albedo: A `vec3`, the surface's color.
        xi: A `vec2` of two random numbers from zero to one.

    Returns:
        The six nodes.

    Raises:
        Error: If `n`, `v` or `albedo` is not a `vec3`, `xi` is not a
            `vec2`, or `roughness` or `metalness` is not a `float`, of this
            graph.
    """
    _expect(g, n, NODE_VEC3, "ggxReflectionSample's normal")
    _expect(g, v, NODE_VEC3, "ggxReflectionSample's view")
    _expect(g, albedo, NODE_VEC3, "ggxReflectionSample's albedo")
    _expect(g, xi, NODE_VEC2, "ggxReflectionSample's random numbers")
    _floats(g, [roughness, metalness], "ggxReflectionSample")
    var zero = g.float(0)
    var a = g.max(g.mul(roughness, roughness), g.float(0.001))
    var t = g.normalize(g.cross(g.vec3(0, 0, 1), n))
    t = g.select(
        g.less_than(g.length(t), g.float(1e-3)),
        g.normalize(g.cross(g.vec3(0, 1, 0), n)),
        t,
    )
    var b = g.normalize(g.cross(n, t))
    var v_local = g.join([g.dot(t, v), g.dot(b, v), g.dot(n, v)])
    var h_local = sample_ggx_vndf(
        g, v_local, a, a, g.swizzle(xi, "x"), g.swizzle(xi, "y")
    )
    h_local = g.select(
        g.less_than(g.swizzle(h_local, "z"), zero), g.negate(h_local), h_local
    )
    var h = g.normalize(
        g.add(
            g.add(
                g.mul(t, g.swizzle(h_local, "x")),
                g.mul(b, g.swizzle(h_local, "y")),
            ),
            g.mul(n, g.swizzle(h_local, "z")),
        )
    )
    var l = g.normalize(g.reflect(g.negate(v), h))
    var half = g.normalize(g.add(v, l))
    var n_dot_v = g.max(zero, g.dot(n, v))
    var n_dot_l = g.max(zero, g.dot(n, l))
    var n_dot_h = g.max(zero, g.dot(n, half))
    var v_dot_h = g.max(zero, g.dot(v, half))
    var f0 = g.mix(g.vec3(0.04, 0.04, 0.04), albedo, metalness)
    var fresnel = f_schlick(g, f0, v_dot_h)
    var pdf = ggx_vndf_pdf(g, n_dot_h, n_dot_v, a)
    var a2 = g.mul(a, a)
    var sin_v2 = g.max(g.one_minus(g.mul(n_dot_v, n_dot_v)), zero)
    var s = g.add(g.float(1), g.sqrt(sin_v2))
    var s2 = g.mul(s, s)
    var k = g.div(
        g.mul(g.one_minus(a2), s2),
        g.add(s2, g.mul(g.mul(a2, n_dot_v), n_dot_v)),
    )
    var bound = g.sqrt(g.add(g.mul(a2, sin_v2), g.mul(n_dot_v, n_dot_v)))
    var weight = g.div(
        g.mul(
            g.mul(fresnel, geometry_term(g, n_dot_l, n_dot_v, a)),
            g.add(g.mul(k, n_dot_v), bound),
        ),
        g.max(g.mul(g.float(2), n_dot_v), g.float(1e-4)),
    )
    return GgxReflectionSample(l, weight, pdf, n_dot_v, a, f0)


def equirect_uv_to_dir(mut g: NodeGraph, uv: NodeRef) raises -> NodeRef:
    """Return the unit direction an equirectangular coordinate names,
    three.js's `equirectUvToDir`: `phi = u * 2 PI - PI`,
    `lat = (v - 0.5) * PI`, and
    `normalize(vec3(cos(lat) cos(phi), sin(lat), cos(lat) sin(phi)))`.

    Args:
        g: The graph to build the nodes in.
        uv: A `vec2`.

    Returns:
        A `vec3`.

    Raises:
        Error: If `uv` is not a `vec2` of this graph.
    """
    _expect(g, uv, NODE_VEC2, "equirectUvToDir")
    var phi = g.sub(
        g.mul(g.swizzle(uv, "x"), g.float(Float32(pi * 2))),
        g.float(Float32(pi)),
    )
    var lat = g.mul(
        g.sub(g.swizzle(uv, "y"), g.float(0.5)), g.float(Float32(pi))
    )
    var cos_lat = g.cos(lat)
    return g.normalize(
        g.join(
            [
                g.mul(cos_lat, g.cos(phi)),
                g.sin(lat),
                g.mul(cos_lat, g.sin(phi)),
            ]
        )
    )


def equirect_dir_pdf(mut g: NodeGraph, direction: NodeRef) raises -> NodeRef:
    """Return the density over solid angle of a direction drawn uniformly
    on an equirectangular map, three.js's `equirectDirPdf`:
    `1 / (2 PI ** 2 sin(theta))`, and zero at the poles.

    Args:
        g: The graph to build the nodes in.
        direction: A unit `vec3`.

    Returns:
        A `float`.

    Raises:
        Error: If `direction` is not a `vec3` of this graph.
    """
    _expect(g, direction, NODE_VEC3, "equirectDirPdf")
    var at = equirect_uv(g, direction)
    var sin_theta = g.sin(g.mul(g.swizzle(at, "y"), g.float(Float32(pi))))
    return g.select(
        g.less_than(g.abs(sin_theta), g.float(1e-6)),
        g.float(0),
        g.div(
            g.float(1),
            g.mul(g.float(Float32(2 * pi * pi)), sin_theta),
        ),
    )


def mis_power_heuristic(
    mut g: NodeGraph, pdf_a: NodeRef, pdf_b: NodeRef
) raises -> NodeRef:
    """Return Veach's power heuristic with an exponent of two, three.js's
    `misPowerHeuristic`: `a ** 2 / (a ** 2 + b ** 2)`.

    Args:
        g: The graph to build the nodes in.
        pdf_a: A `float`, the density of the strategy weighed.
        pdf_b: A `float`, the density of the other.

    Returns:
        A `float` from zero to one.

    Raises:
        Error: If one is not a `float` of this graph.
    """
    _floats(g, [pdf_a, pdf_b], "misPowerHeuristic")
    var a2 = g.mul(pdf_a, pdf_a)
    var b2 = g.mul(pdf_b, pdf_b)
    return g.div(a2, g.add(a2, b2))
