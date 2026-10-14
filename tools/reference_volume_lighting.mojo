# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Generate or check independent three.js r186 volume-light fixtures.

    mojo run -I . --fp-mode contract=off tools/reference_volume_lighting.mojo [--check | --write]

This portable scalar Float64 reference imports no native implementation and
does not claim to execute WebGPU/TSL. The fetched upstream Git blob IDs
identify the equations transcribed here. Native tests use Float32 tolerances
against these independent constants.

`--write` replaces `assets/volume_lighting/r186.json`. `--check` verifies it,
and is the default. A float in the fixture must agree within a relative and
an absolute tolerance of 2e-14; every other token must be equal. Native
output is 1 - transmittance. Actual r186 outgoing-ray recurrence is also
recorded, but is outside issue #616's accepted scope and is deliberately not
asserted as the native final color.

The fixture is the one that the Python reference wrote. Each number
remembers whether Python held it as an int, because the fixture writes an
int without a fraction and Python's `sum` adds an int without compensation.
Built with `--fp-mode contract=off`, `--write` gives the same bytes.
"""

from std.math import sqrt, pi
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tools import JsonWriter
from tools._python_float import parse_float
from tools._python_math import cos, exp, power, py_sum

comptime FIXTURE = "assets/volume_lighting/r186.json"
"""The fixture, relative to the repository root."""
comptime TOLERANCE = 2e-14
"""The relative and absolute tolerance of a float in `--check`."""


@fieldwise_init
struct N(ImplicitlyCopyable, Movable):
    """A number, and whether the Python reference held it as an int."""

    var value: Float64
    """The value."""
    var whole: Bool
    """True when Python held the value as an int."""

    def __add__(self, other: N) -> N:
        """Add as Python adds.

        Args:
            other: The other number.

        Returns:
            The sum; an int when both numbers are ints.
        """
        return N(self.value + other.value, self.whole and other.whole)

    def __sub__(self, other: N) -> N:
        """Subtract as Python subtracts.

        Args:
            other: The other number.

        Returns:
            The difference; an int when both numbers are ints.
        """
        return N(self.value - other.value, self.whole and other.whole)

    def __mul__(self, other: N) -> N:
        """Multiply as Python multiplies.

        Args:
            other: The other number.

        Returns:
            The product; an int when both numbers are ints.
        """
        return N(self.value * other.value, self.whole and other.whole)

    def __truediv__(self, other: N) -> N:
        """Divide as Python's `/` divides.

        Args:
            other: The other number.

        Returns:
            The quotient, always a float.
        """
        return N(self.value / other.value, False)


def i(value: Int) -> N:
    """Return an int.

    Args:
        value: The value.

    Returns:
        The number.
    """
    return N(Float64(value), True)


def f(value: Float64) -> N:
    """Return a float.

    Args:
        value: The value.

    Returns:
        The number.
    """
    return N(value, False)


def ints(x: Int, y: Int, z: Int) -> List[N]:
    """Return a vector of three ints.

    Args:
        x: The first coordinate.
        y: The second coordinate.
        z: The third coordinate.

    Returns:
        The vector.
    """
    return [i(x), i(y), i(z)]


def floats(x: Float64, y: Float64, z: Float64) -> List[N]:
    """Return a vector of three floats.

    Args:
        x: The first coordinate.
        y: The second coordinate.
        z: The third coordinate.

    Returns:
        The vector.
    """
    return [f(x), f(y), f(z)]


def add(a: List[N], b: List[N]) -> List[N]:
    """Add two vectors.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The sum.
    """
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]


def sub(a: List[N], b: List[N]) -> List[N]:
    """Subtract two vectors.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The difference.
    """
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]


def scale(a: List[N], value: N) -> List[N]:
    """Multiply each coordinate by a number.

    Args:
        a: The vector.
        value: The factor.

    Returns:
        The scaled vector.
    """
    var out = List[N]()
    for x in a:
        out.append(x * value)
    return out^


def total(values: List[N]) -> N:
    """Sum as Python's `sum` does.

    Args:
        values: The items.

    Returns:
        The sum.
    """
    var numbers = List[Float64]()
    var kinds = List[Bool]()
    for x in values:
        numbers.append(x.value)
        kinds.append(x.whole)
    var result = py_sum(numbers, kinds)
    return N(result[0], result[1])


def dot(a: List[N], b: List[N]) -> N:
    """Return the dot product, summed as Python's `sum` does.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The dot product.
    """
    return total([a[0] * b[0], a[1] * b[1], a[2] * b[2]])


def cross(a: List[N], b: List[N]) -> List[N]:
    """Return the cross product.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The cross product.
    """
    return [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]


def length(a: List[N]) -> N:
    """Return the length of a vector.

    Args:
        a: The vector.

    Returns:
        The length, a float.
    """
    return f(sqrt(dot(a, a).value))


def normalize(a: List[N]) raises -> List[N]:
    """Return a vector of length one.

    Args:
        a: The vector.

    Returns:
        The unit vector.

    Raises:
        Error: If the vector is zero.
    """
    var size = length(a)
    if size.value == 0:
        raise Error("A reference fixture must not normalize a zero vector")
    return scale(a, i(1) / size)


def larger(a: N, b: N) -> N:
    """Return `max(a, b)`: `a`, unless `b` is greater.

    Args:
        a: The first number.
        b: The second number.

    Returns:
        The larger number.
    """
    return b if b.value > a.value else a


def smaller(a: N, b: N) -> N:
    """Return `min(a, b)`: `a`, unless `b` is less.

    Args:
        a: The first number.
        b: The second number.

    Returns:
        The smaller number.
    """
    return b if b.value < a.value else a


def pow(a: N, b: N) -> N:
    """Return `a ** b`.

    Args:
        a: The base.
        b: The exponent, a nonnegative int or a float.

    Returns:
        The power; an int when both numbers are ints.
    """
    return N(power(a.value, b.value), a.whole and b.whole)


@fieldwise_init
struct Camera(Copyable, Movable):
    """A perspective camera."""

    var eye: List[N]
    """The eye position, in meters."""
    var up: List[N]
    """The up axis."""
    var back: List[N]
    """The backward axis."""


def camera(eye: List[N], back: List[N] = ints(0, 0, 1)) -> Camera:
    """Return a camera with up along +Y.

    Args:
        eye: The eye position.
        back: The backward axis.

    Returns:
        The camera.
    """
    return Camera(eye.copy(), ints(0, 1, 0), back.copy())


def to_view(vector: List[N], view: Camera) -> List[N]:
    """Express a world vector on the camera axes.

    Args:
        vector: The vector.
        view: The camera.

    Returns:
        The view vector.
    """
    return [
        dot(vector, cross(view.up, view.back)),
        dot(vector, view.up),
        dot(vector, view.back),
    ]


@fieldwise_init
struct Light(Copyable, Movable):
    """A light. The fields that a kind does not use are empty."""

    var kind: String
    """`rectangle`, `point`, `spot` or `directional`."""
    var position: List[N]
    """The position, in meters."""
    var radiance: List[N]
    """The RGB radiance."""
    var half_width: List[N]
    """The rectangle's half width."""
    var half_height: List[N]
    """The rectangle's half height."""
    var axis: List[N]
    """The spot's axis toward the light."""
    var decay: N
    """The distance decay exponent."""
    var cutoff: N
    """The cutoff distance, or zero for none."""
    var cone_cos: N
    """The cosine of the spot's cone angle."""
    var penumbra_cos: N
    """The cosine of the spot's penumbra angle."""


def _light(
    kind: String,
    position: List[N],
    radiance: List[N],
    decay: N = i(0),
    cutoff: N = i(0),
) -> Light:
    """Return a light with no rectangle or spot fields."""
    return Light(
        kind,
        position.copy(),
        radiance.copy(),
        List[N](),
        List[N](),
        List[N](),
        decay,
        cutoff,
        i(0),
        i(0),
    )


def area(position: List[N], radiance: List[N]) -> Light:
    """Return a two by two meter rectangle light that faces -Z.

    Args:
        position: The center.
        radiance: The RGB radiance.

    Returns:
        The light.
    """
    var light = _light("rectangle", position, radiance)
    light.half_width = ints(1, 0, 0)
    light.half_height = ints(0, 1, 0)
    return light^


def default_area() -> Light:
    """Return the default rectangle light: `area()` in the Python reference.

    Returns:
        The light.
    """
    return area([i(0), i(0), f(2.5)], [i(4), i(1), f(0.25)])


def mixed_lights() -> List[Light]:
    """Return a point, a spot, two rectangles and a directional light.

    Returns:
        The lights.
    """
    var spot = _light(
        "spot", ints(0, 0, 3), ints(5, 2, 1), decay=i(2), cutoff=i(8)
    )
    spot.axis = ints(0, 0, 1)
    spot.cone_cos = f(cos(Float64(pi) / Float64(3)))
    spot.penumbra_cos = f(cos(Float64(pi) / Float64(4)))
    return [
        _light(
            "point",
            [f(0.25), f(0.5), i(1)],
            ints(2, 3, 4),
            decay=i(2),
            cutoff=i(0),
        ),
        spot^,
        default_area(),
        area([f(0.5), f(-0.2), i(2)], [f(0.25), f(0.5), i(2)]),
        _light("directional", List[N](), ints(100, 100, 100)),
    ]


def edge_form_factor(first: List[N], second: List[N]) -> List[N]:
    """Return the LTC edge integral of one rectangle edge.

    Args:
        first: The edge's first unit direction.
        second: The edge's second unit direction.

    Returns:
        The edge's vector form factor.
    """
    var x = dot(first, second).value
    var y = abs(x)
    var a = (0.0145206 * y + 0.4965155) * y + 0.8543985
    var b = (y + 4.1616724) * y + 3.4175940
    var v = a / b
    var theta_sintheta = v if x > 0 else 0.5 / sqrt(max(1 - x * x, 1e-7)) - v
    return scale(cross(first, second), f(theta_sintheta))


def volume_factor(position: List[N], corners: List[List[N]]) raises -> N:
    """Return the rectangle's form factor at a view position.

    Args:
        position: The view position.
        corners: The four view corners.

    Returns:
        The form factor.

    Raises:
        Error: If a corner is at the position.
    """
    var normal = cross(sub(corners[1], corners[0]), sub(corners[3], corners[0]))
    if dot(normal, sub(position, corners[0])).value < 0:
        return f(0.0)
    var sphere = List[List[N]]()
    for corner in corners:
        sphere.append(normalize(sub(corner, position)))
    var summed = floats(0.0, 0.0, 0.0)
    for index in range(4):
        summed = add(
            summed, edge_form_factor(sphere[index], sphere[(index + 1) % 4])
        )
    var absolute = floats(
        abs(summed[0].value), abs(summed[1].value), abs(summed[2].value)
    )
    var magnitude = length(absolute)
    return larger(
        (magnitude * magnitude + absolute[2]) / (magnitude + i(1)), f(0.0)
    )


def rectangle_direct(
    light: Light, position: List[N], view: Camera
) raises -> Tuple[N, List[N]]:
    """Return the rectangle's form factor and direct light at a position.

    Use absolute view positions as r186 does. Native code cancels the common
    camera translation before rotation; no native helper is used.

    Args:
        light: The rectangle light.
        position: The world position.
        view: The camera.

    Returns:
        The form factor and the RGB direct light.

    Raises:
        Error: If a corner is at the position.
    """
    var center = to_view(sub(light.position, view.eye), view)
    var width = to_view(light.half_width, view)
    var height = to_view(light.half_height, view)
    var corners: List[List[N]] = [
        sub(add(center, width), height),
        sub(sub(center, width), height),
        add(sub(center, width), height),
        add(add(center, width), height),
    ]
    var view_position = to_view(sub(position, view.eye), view)
    var factor = volume_factor(view_position, corners)
    var color = List[N]()
    for x in light.radiance:
        color.append(pow(x * factor, f(1.5)))
    return (factor, color^)


def distance_attenuation(distance: N, decay: N, cutoff: N) -> N:
    """Return the light's distance attenuation.

    Args:
        distance: The distance, in meters.
        decay: The decay exponent.
        cutoff: The cutoff distance, or zero for none.

    Returns:
        The attenuation.
    """
    var result = i(1) / larger(pow(distance, decay), f(0.01))
    if cutoff.value > 0:
        result = result * pow(
            larger(i(0), smaller(i(1), i(1) - pow(distance / cutoff, i(4)))),
            i(2),
        )
    return result


@fieldwise_init
struct Term(Copyable, Movable):
    """One light's direct light at a sample."""

    var kind: String
    """The light's kind."""
    var form_factor: N
    """The rectangle's form factor; unused for other kinds."""
    var rgb: List[N]
    """The RGB direct light."""


def direct(light: Light, position: List[N], view: Camera) raises -> Term:
    """Return one light's direct light at a position.

    Args:
        light: The light.
        position: The world position.
        view: The camera.

    Returns:
        The term.

    Raises:
        Error: If the position is at a rectangle corner.
    """
    if light.kind == "rectangle":
        var result = rectangle_direct(light, position, view)
        return Term(light.kind, result[0], result[1].copy())
    if light.kind == "directional":
        # r186 direct() ignores lights without a distance property.
        return Term(light.kind, f(0.0), floats(0.0, 0.0, 0.0))
    var toward = sub(light.position, position)
    var distance = length(toward)
    var attenuation = distance_attenuation(distance, light.decay, light.cutoff)
    if light.kind == "spot":
        var cosine = dot(normalize(toward), light.axis)
        var fraction = larger(
            i(0),
            smaller(
                i(1),
                (cosine - light.cone_cos)
                / (light.penumbra_cos - light.cone_cos),
            ),
        )
        attenuation = attenuation * (
            fraction * fraction * (i(3) - i(2) * fraction)
        )
    return Term(light.kind, f(0.0), scale(light.radiance, attenuation))


@fieldwise_init
struct Scene(Copyable, Movable):
    """A volume, a camera, its lights and an optional opaque blocker."""

    var name: String
    """The scene's name."""
    var view: Camera
    """The camera."""
    var relation: String
    """`inside` or `outside`: where the camera is."""
    var fragment: List[N]
    """The volume fragment that the ray ends at."""
    var model_radius: N
    """The volume's bounding radius, in meters."""
    var steps: Int
    """The ray-march steps."""
    var offset: N
    """The sample offset, in steps."""
    var scattering_scale: N
    """The scattering scale."""
    var has_depth: Bool
    """True when an opaque blocker writes the scene depth."""
    var depth: Float64
    """The blocker's camera-axis distance, in meters."""
    var blocker: String
    """Where the blocker is."""
    var lights: List[Light]
    """The lights."""


def scene(
    name: String,
    inside: Bool = False,
    mixed: Bool = False,
    has_depth: Bool = False,
    depth: Float64 = 0.0,
    blocker: String = "none",
) -> Scene:
    """Return a scene with a unit cube volume and a fragment at z = -1.

    Args:
        name: The scene's name.
        inside: True for a camera inside the volume.
        mixed: True for the mixed lights, False for one rectangle.
        has_depth: True when an opaque blocker writes the scene depth.
        depth: The blocker's camera-axis distance.
        blocker: Where the blocker is.

    Returns:
        The scene.
    """
    var lights = mixed_lights() if mixed else [default_area()]
    return Scene(
        name,
        camera([i(0), i(0), f(0.5)] if inside else ints(0, 0, 4)),
        "inside" if inside else "outside",
        ints(0, 0, -1),
        f(sqrt(Float64(3))),
        4,
        f(0.0) if inside else f(0.25),
        f(0.75),
        has_depth,
        depth,
        blocker,
        lights^,
    )


def write_vector(mut out: JsonWriter, vector: List[N]):
    """Write a vector as a list.

    Args:
        out: The writer.
        vector: The vector.
    """
    out.begin_array()
    for x in vector:
        write_number(out, x)
    out.end()


def write_number(mut out: JsonWriter, value: N):
    """Write a number as an int or a float, as Python held it.

    Args:
        out: The writer.
        value: The number.
    """
    if value.whole:
        out.integer(Int(value.value))
    else:
        out.number(value.value)


def write_camera(mut out: JsonWriter, view: Camera):
    """Write a camera.

    Args:
        out: The writer.
        view: The camera.
    """
    out.begin_object()
    out.key("eye")
    write_vector(out, view.eye)
    out.key("up")
    write_vector(out, view.up)
    out.key("back")
    write_vector(out, view.back)
    out.key("near")
    out.number(0.1)
    out.key("far")
    out.number(100.0)
    out.key("projection")
    out.string("perspective")
    out.end()


def write_light(mut out: JsonWriter, light: Light):
    """Write a light with the members of its kind.

    Args:
        out: The writer.
        light: The light.
    """
    out.begin_object()
    out.key("kind")
    out.string(light.kind)
    if light.kind != "directional":
        out.key("position")
        write_vector(out, light.position)
    if light.kind == "rectangle":
        out.key("half_width")
        write_vector(out, light.half_width)
        out.key("half_height")
        write_vector(out, light.half_height)
    out.key("radiance")
    write_vector(out, light.radiance)
    if light.kind == "spot":
        out.key("toward_light_axis")
        write_vector(out, light.axis)
    if light.kind == "point" or light.kind == "spot":
        out.key("decay")
        write_number(out, light.decay)
        out.key("cutoff")
        write_number(out, light.cutoff)
    if light.kind == "spot":
        out.key("cone_cos")
        write_number(out, light.cone_cos)
        out.key("penumbra_cos")
        write_number(out, light.penumbra_cos)
    out.end()


def write_term(mut out: JsonWriter, term: Term):
    """Write one light's direct light.

    Args:
        out: The writer.
        term: The term.
    """
    out.begin_object()
    out.key("kind")
    out.string(term.kind)
    if term.kind == "rectangle":
        out.key("form_factor")
        write_number(out, term.form_factor)
    out.key("rgb")
    write_vector(out, term.rgb)
    out.end()


def evaluate(mut out: JsonWriter, item: Scene) raises:
    """Ray-march a scene and write every sample and the result.

    Args:
        out: The writer.
        item: The scene.

    Raises:
        Error: If a sample is at a rectangle corner.
    """
    var view = item.view.copy()
    var eye = view.eye.copy()
    var front_to_back = (
        length(sub(eye, item.fragment)).value > item.model_radius.value * 2
    )
    var start = eye.copy() if front_to_back else item.fragment.copy()
    var end = item.fragment.copy() if front_to_back else eye.copy()
    var ray = sub(end, start)
    var step_size = length(ray) / i(item.steps)
    var direction = normalize(ray)
    var transmittance = floats(1.0, 1.0, 1.0)
    var outgoing = floats(0.0, 0.0, 0.0)
    out.begin_object()
    out.key("front_to_back")
    out.boolean(front_to_back)
    out.key("step_size_m")
    write_number(out, step_size)
    out.key("samples")
    out.begin_array()
    for index in range(item.steps):
        var position = add(
            start, scale(direction, (i(index) + item.offset) * step_size)
        )
        var distance = dot(sub(eye, position), view.back)
        # linearDepth(viewZToPerspectiveDepth(z)) simplifies to this
        # monotonic camera-axis distance comparison for perspective cameras.
        var accepted = not item.has_depth or item.depth >= distance.value
        var terms = List[Term]()
        for light in item.lights:
            terms.append(direct(light, position, view))
        var summed = List[N]()
        for channel in range(3):
            var column = List[N]()
            for term in terms:
                column.append(term.rgb[channel])
            summed.append(total(column))
        var density = scale(
            summed, item.scattering_scale if accepted else f(0.0)
        )
        var falloff = List[N]()
        for value in density:
            falloff.append(f(exp((-value.value) * 0.01 * step_size.value)))
        var step_light = scale(density, f(0.01))
        var next = List[N]()
        for channel in range(3):
            if front_to_back:
                next.append(
                    outgoing[channel]
                    + step_light[channel] * transmittance[channel] * step_size
                )
            else:
                next.append(
                    outgoing[channel] * falloff[channel]
                    + step_light[channel] * step_size
                )
            transmittance[channel] = transmittance[channel] * falloff[channel]
        outgoing = next^
        out.begin_object()
        out.key("index")
        out.integer(index)
        out.key("position")
        write_vector(out, position)
        out.key("camera_axis_depth_m")
        write_number(out, distance)
        out.key("linear_depth")
        write_number(out, (distance - f(0.1)) / (f(100.0) - f(0.1)))
        out.key("depth_gate")
        out.boolean(accepted)
        out.key("direct_terms")
        out.begin_array()
        for term in terms:
            write_term(out, term)
        out.end()
        out.key("ungated_light")
        write_vector(out, summed)
        out.key("scattering_density")
        write_vector(out, density)
        out.key("transmittance_after")
        write_vector(out, transmittance)
        out.key("r186_outgoing_after_out_of_scope")
        write_vector(out, outgoing)
        out.end()
    out.end()
    out.key("native_transmittance")
    write_vector(out, transmittance)
    var accepted_output = List[N]()
    for value in transmittance:
        accepted_output.append(i(1) - larger(i(0), smaller(i(1), value)))
    out.key("native_accepted_output")
    write_vector(out, accepted_output)
    out.key("r186_outgoing_out_of_scope")
    write_vector(out, outgoing)
    out.end()


def write_scene(mut out: JsonWriter, item: Scene) raises:
    """Write a scene and its expected result.

    Args:
        out: The writer.
        item: The scene.

    Raises:
        Error: If a sample is at a rectangle corner.
    """
    out.begin_object()
    out.key("name")
    out.string(item.name)
    out.key("camera")
    write_camera(out, item.view)
    out.key("camera_relation")
    out.string(item.relation)
    out.key("fragment")
    write_vector(out, item.fragment)
    out.key("model_radius")
    write_number(out, item.model_radius)
    out.key("steps")
    out.integer(item.steps)
    out.key("offset")
    write_number(out, item.offset)
    out.key("scattering_scale")
    write_number(out, item.scattering_scale)
    out.key("scene_depth_m")
    if item.has_depth:
        out.number(item.depth)
    else:
        out.null()
    out.key("blocker_relation")
    out.string(item.blocker)
    out.key("volume_bounds")
    out.begin_object()
    out.key("min")
    write_vector(out, ints(-1, -1, -1))
    out.key("max")
    write_vector(out, ints(1, 1, 1))
    out.end()
    out.key("lights")
    out.begin_array()
    for light in item.lights:
        write_light(out, light)
    out.end()
    out.key("expected")
    evaluate(out, item)
    out.end()


def scenes() -> List[Scene]:
    """Return every ray scene, in fixture order.

    Returns:
        The scenes.
    """
    var result = List[Scene]()
    var outside: List[Tuple[String, Bool, Float64]] = [
        ("none", False, 0.0),
        ("before", True, 2.0),
        ("inside", True, 4.0),
        ("behind", True, 6.0),
    ]
    for mixed in [False, True]:
        for entry in outside:
            result.append(
                scene(
                    "outside_"
                    + ("mixed_" if mixed else "rectangle_")
                    + entry[0],
                    mixed=mixed,
                    has_depth=entry[1],
                    depth=entry[2],
                    blocker=entry[0],
                )
            )
    var inside: List[Tuple[String, Bool, Float64]] = [
        ("none", False, 0.0),
        ("before_samples", True, 0.2),
        ("inside", True, 0.5),
        ("equality", True, 0.75),
        ("behind", True, 2.5),
    ]
    for entry in inside:
        result.append(
            scene(
                "inside_mixed_" + entry[0],
                inside=True,
                mixed=True,
                has_depth=entry[1],
                depth=entry[2],
                blocker=entry[0],
            )
        )
    var back = scene("outside_rectangle_back_side")
    back.lights = [area(ints(0, 0, -2), [i(4), i(1), f(0.25)])]
    result.append(back^)
    var rotated = scene("outside_rotated_camera_mixed", mixed=True)
    rotated.view = camera(ints(4, 0, 0), ints(1, 0, 0))
    rotated.fragment = ints(-1, 0, 0)
    result.append(rotated^)
    # Exact inputs shared with tests/test_volume_scene_depth.mojo. Their
    # point radiance is constant, so admitted-step counts also give an
    # elementary Beer-law oracle independent of rectangle arithmetic.
    var point = _light("point", ints(0, 5, 0), ints(10, 10, 10))
    var constant: List[Tuple[String, String, Bool, Float64]] = [
        ("depth_constant_outside_before", "before", False, 1.5),
        ("depth_constant_outside_inside", "inside", False, 3.5),
        ("depth_constant_outside_behind", "behind", False, 6.0),
        ("depth_constant_inside", "inside", True, 0.5),
        ("depth_constant_oblique", "inside", False, 1.7),
    ]
    for entry in constant:
        var item = scene(
            entry[0],
            inside=entry[2],
            has_depth=True,
            depth=entry[3],
            blocker=entry[1],
        )
        if entry[0] == "depth_constant_oblique":
            item.view = camera(ints(3, 0, 4))
            item.fragment = ints(0, 0, 0)
            item.model_radius = f(1.0)
        item.steps = 5
        item.offset = f(0.0)
        item.scattering_scale = f(1.0)
        item.lights = [point.copy()]
        result.append(item^)
    return result^


def build_fixture() raises -> Tuple[String, Int, Int]:
    """Return the fixture text and its case counts.

    Returns:
        The JSON text with a final newline, the direct cases and the ray
        scenes.

    Raises:
        Error: If a sample is at a rectangle corner.
    """
    var out = JsonWriter()
    out.begin_object()
    out.key("schema_version")
    out.integer(1)
    out.key("upstream")
    out.string("three.js r186")
    out.key("issue")
    out.integer(616)
    out.key("generation")
    out.string(
        "Independent Python Float64 scalar equations, not a WebGPU capture"
    )
    out.key("sources")
    out.begin_array()
    var blobs: List[Tuple[String, String]] = [
        (
            "src/nodes/functions/BSDF/LTC.js",
            "6030b42b22794eb87711bfd5d1e65f974abf1eba",
        ),
        (
            "src/nodes/functions/VolumetricLightingModel.js",
            "d37d3a6c2362170e043b8624958afbe16ae87137",
        ),
        (
            "src/nodes/lighting/RectAreaLightNode.js",
            "d0b31a4575fe98021cd529f776c617dafaeac91d",
        ),
        (
            "src/nodes/display/ViewportDepthNode.js",
            "7e96a52c22bbc0bc356a241b38c2e409da0740fc",
        ),
        (
            "src/nodes/lighting/LightUtils.js",
            "f0498b00e6284876d4a264eaca1fe7ced97739d0",
        ),
        (
            "src/nodes/lighting/SpotLightNode.js",
            "783cdc430a91b265ef6fae1f6e2057b023368f5c",
        ),
    ]
    for blob in blobs:
        out.begin_object()
        out.key("path")
        out.string(blob[0])
        out.key("git_blob_sha")
        out.string(blob[1])
        out.key("url")
        out.string("https://github.com/mrdoob/three.js/blob/r186/" + blob[0])
        out.end()
    out.end()
    out.key("scope")
    out.begin_object()
    var scope: List[Tuple[String, String]] = [
        (
            "accepted",
            (
                "r186 rectangle direct light and scattering-depth gate;"
                " native 1-transmittance output retained"
            ),
        ),
        (
            "out_of_scope",
            "r186 outgoingRayLight recurrence and scatteringEmissiveNode port",
        ),
        (
            "depth",
            (
                "Opaque positive camera-axis distance; equality accepted;"
                " original ray samples unchanged"
            ),
        ),
        (
            "before_blocker",
            (
                "Outside-camera samples before the volume and blocker can"
                " contribute, as in r186"
            ),
        ),
        (
            "normalization",
            (
                "All reference normalizations are nonzero; native"
                " normalize(0) stays zero, while GPU normalize(0) is"
                " undefined"
            ),
        ),
        (
            "rounding",
            (
                "Native Float32 may differ in final bits; sqrt(x)*x replaces"
                " power 1.5 and common view translation cancels before"
                " rotation"
            ),
        ),
        (
            "shadows",
            (
                "These independent mixed scenes have no shadows, IES maps, or"
                " projectors; existing native regressions cover them"
            ),
        ),
    ]
    for entry in scope:
        out.key(entry[0])
        out.string(entry[1])
    out.end()
    out.key("direct_cases")
    out.begin_array()
    var cases: List[Tuple[String, List[N], List[N]]] = [
        ("axis_front", ints(0, 0, 0), ints(0, 0, 1)),
        ("off_axis", floats(0.3, -0.4, -0.2), ints(0, 0, 1)),
        ("yaw_90", ints(0, 0, 0), ints(1, 0, 0)),
        ("back_side", ints(0, 0, 2), ints(0, 0, 1)),
        ("on_emitter_plane", ints(0, 0, 1), ints(0, 0, 1)),
    ]
    for entry in cases:
        var light = area(ints(0, 0, 1), ints(4, 1, 0))
        var view = camera(ints(0, 0, 4), entry[2])
        var result = rectangle_direct(light, entry[1], view)
        out.begin_object()
        out.key("name")
        out.string(entry[0])
        out.key("position")
        write_vector(out, entry[1])
        out.key("camera")
        write_camera(out, view)
        out.key("light")
        write_light(out, light)
        out.key("form_factor")
        write_number(out, result[0])
        out.key("direct_light")
        write_vector(out, result[1])
        out.end()
    out.end()
    var all_scenes = scenes()
    out.key("scenes")
    out.begin_array()
    for item in all_scenes:
        write_scene(out, item)
    out.end()
    out.end()
    return (out.text() + "\n", len(cases), len(all_scenes))


def _tokens(text: String) -> Tuple[List[String], List[Int]]:
    """Split JSON text into tokens, with the line of each."""
    var bytes = text.as_bytes()
    var found = List[String]()
    var lines = List[Int]()
    var line = 1
    var index = 0
    while index < len(bytes):
        var byte = Int(bytes[index])
        if byte == ord("\n"):
            line += 1
            index += 1
        elif byte == ord(" ") or byte == ord("\t") or byte == ord("\r"):
            index += 1
        elif chr(byte) in "{}[]:,":
            found.append(chr(byte))
            lines.append(line)
            index += 1
        elif byte == ord('"'):
            var end = index + 1
            while end < len(bytes) and Int(bytes[end]) != ord('"'):
                end += 2 if Int(bytes[end]) == ord("\\") else 1
            end = min(end + 1, len(bytes))
            found.append(String(text[byte=index:end]))
            lines.append(line)
            index = end
        else:
            var end = index
            while end < len(bytes) and not (
                chr(Int(bytes[end])) in "{}[]:, \t\r\n"
            ):
                end += 1
            found.append(String(text[byte=index:end]))
            lines.append(line)
            index = end
    return (found^, lines^)


def _is_number(token: String) -> Bool:
    """Return True for a JSON number token."""
    var first = Int(token.as_bytes()[0])
    return first == ord("-") or (first >= ord("0") and first <= ord("9"))


def _is_float(token: String) -> Bool:
    """Return True for a number token that Python reads as a float."""
    return token.find(".") >= 0 or token.find("e") >= 0 or token.find("E") >= 0


def compare(expected: String, actual: String) raises -> String:
    """Compare two fixture texts as the Python reference compared them.

    A float in `expected` must be close to a number in `actual`, within
    `TOLERANCE` relative or absolute. Every other token must be equal.

    Args:
        expected: The text that this tool builds.
        actual: The saved text.

    Returns:
        An empty string, or the first difference.

    Raises:
        Error: If a number does not parse.
    """
    var want = _tokens(expected)
    var got = _tokens(actual)
    var count = min(len(want[0]), len(got[0]))
    for index in range(count):
        var e = want[0][index]
        var a = got[0][index]
        var same = e == a
        if not same and _is_number(e) and _is_float(e) and _is_number(a):
            var x = parse_float(e)
            var y = parse_float(a)
            same = abs(x - y) <= max(TOLERANCE * max(abs(x), abs(y)), TOLERANCE)
        if not same:
            return "line " + String(got[1][index]) + ": " + a + " != " + e
    if len(want[0]) != len(got[0]):
        return "the fixture's structure differs"
    return ""


def run(root: String, write: Bool) raises -> Tuple[Int, String]:
    """Check or write the fixture.

    Args:
        root: The repository root.
        write: True to replace the fixture.

    Returns:
        The exit status and the report.

    Raises:
        Error: If the fixture cannot be read or written.
    """
    var built = build_fixture()
    var path = Path(root + "/" + FIXTURE)
    var verb: String
    if write:
        path.write_text(built[0])
        verb = "wrote"
    else:
        var difference = compare(built[0], path.read_text())
        if difference:
            return (1, FIXTURE + ": " + difference + "\n")
        verb = "checked"
    return (
        0,
        verb
        + " "
        + String(built[1])
        + " direct cases and "
        + String(built[2])
        + " ray scenes: "
        + FIXTURE
        + "\n",
    )


def main() raises:
    var given = argv()
    var write = False
    if len(given) == 2 and String(given[1]) == "--write":
        write = True
    elif len(given) > 2 or (len(given) == 2 and String(given[1]) != "--check"):
        print(
            "usage: reference_volume_lighting [--check | --write]", file=stderr
        )
        exit(2)
    var outcome = run(".", write)
    if outcome[0] != 0:
        print(outcome[1], end="", file=stderr)
    else:
        print(outcome[1], end="")
    exit(outcome[0])
