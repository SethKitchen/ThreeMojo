# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Linearly transformed cosines: how a rectangle of light reaches a surface,
from three.js `src/renderers/shaders/ShaderChunk/lights_physical_pars_fragment.glsl.js`
and `examples/jsm/lights/RectAreaLightTexturesLib.js`.

**What an area light asks.** A point light arrives from one direction and
a surface answers with one cosine. A rectangle of light arrives from every
direction inside its outline, and the answer is the integral of the
surface's reflectance over that outline: an integral with no closed form
for a GGX lobe. Heitz, Dupuy, Hill and Neubelt's trick is that a cosine
lobe *does* have one -- the form factor of a polygon, a sum over its edges
-- and that a GGX lobe at one roughness and one viewing angle is well
approximated by a cosine lobe pushed through a linear transform. Push the
rectangle through the inverse transform instead, take the cosine lobe's
form factor of it, and the integral falls out.

**Two tables, one lookup.** The transforms were fitted once and stored,
sixty-four roughnesses by sixty-four viewing angles, four numbers each:
`LTC_MAT_1` holds the inverse transform and `LTC_MAT_2` two Fresnel
terms. They are three.js's own numbers, read from `assets/ltc.f32` as
`load_ltc_tables` reads it -- thirty-two thousand floats that no source
file should hold -- and looked up with the bilinear filter three.js's
float texture applies, `ltc_lookup`. A scene with a rectangle of light
needs the tables; one without never opens the file.

Both rasterizers call the functions below. The diffuse term takes the
identity transform, the specular the fitted one, and the light's color
multiplies both: three.js's `RE_Direct_RectArea_Physical`, which only its
physical materials have, and so only `STANDARD` and `PHYSICAL` here.

The form factor already integrates the cosine over the light's outline,
so it carries no reciprocal pi where every other lit sum does: it is added
after `Lighting.scale` is applied, not before.
"""

from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import sqrt
from std.memory import bitcast
from std.pathlib import Path

# The tables are sixty-four by sixty-four, four floats a texel.
comptime LTC_SIZE = 64
comptime LTC_TEXELS = LTC_SIZE * LTC_SIZE
comptime LTC_FLOATS = LTC_TEXELS * 4
# How the lookup coordinate is squeezed onto texel centers: three.js's
# `LUT_SCALE` and `LUT_BIAS`.
comptime LTC_SCALE = Float32(LTC_SIZE - 1) / Float32(LTC_SIZE)
comptime LTC_BIAS = Float32(0.5) / Float32(LTC_SIZE)
# Where the tables live, relative to the repository root.
comptime LTC_PATH = "assets/ltc.f32"


@fieldwise_init
struct RectLight(ImplicitlyCopyable):
    """What one rectangle of light adds to a physical surface, before the
    light's radiance multiplies it: the two terms three.js's
    `RE_Direct_RectArea_Physical` adds to `reflectedLight`.

    A struct rather than a tuple because the device kernel returns it
    across the same boundary `Reflected` crosses.
    """

    # Through the identity transform, times the diffuse color.
    var diffuse: Vector3
    # Through the fitted transform, times the Fresnel terms.
    var specular: Vector3


struct LtcTables(Copyable, Movable):
    """The two LTC tables of three.js, or none until `load_ltc_tables` is
    asked.

    Held by `Renderer` and handed to `Lighting`, which refuses a scene with
    a rectangle of light and no tables rather than lighting it wrong.
    """

    # `LTC_FLOATS` each, row-major from the row for a viewing angle of
    # zero, four floats a texel; or empty.
    var first: List[Float32]
    var second: List[Float32]

    def __init__(out self):
        """Start with no tables."""
        self.first = List[Float32]()
        self.second = List[Float32]()

    def __init__(
        out self, var first: List[Float32], var second: List[Float32]
    ) raises:
        """Adopt two tables.

        Args:
            first: `LTC_MAT_1`, the inverse transforms.
            second: `LTC_MAT_2`, the Fresnel terms.

        Raises:
            Error: If either does not hold `LTC_FLOATS` numbers.
        """
        if len(first) != LTC_FLOATS or len(second) != LTC_FLOATS:
            raise Error("An LTC table holds sixty-four squared texels of four")
        self.first = first^
        self.second = second^

    def is_loaded(self) -> Bool:
        """Return True if the tables were loaded."""
        return len(self.first) == LTC_FLOATS


def load_ltc_tables(path: String = LTC_PATH) raises -> LtcTables:
    """Read the two tables from a file of little-endian floats: the first
    table's `LTC_FLOATS` numbers and then the second's.

    Args:
        path: Where the file is; `LTC_PATH` by default.

    Returns:
        The tables.

    Raises:
        Error: If the file cannot be read or is not twice `LTC_FLOATS`
            floats long.
    """
    var bytes = Path(path).read_bytes()
    if len(bytes) != 2 * LTC_FLOATS * 4:
        raise Error("An LTC file holds two tables of sixty-four squared texels")
    var first = List[Float32]()
    var second = List[Float32]()
    for index in range(2 * LTC_FLOATS):  # pragma: no branch
        var at = index * 4
        var bits = (
            UInt32(bytes[at])
            | (UInt32(bytes[at + 1]) << 8)
            | (UInt32(bytes[at + 2]) << 16)
            | (UInt32(bytes[at + 3]) << 24)
        )
        var value = bitcast[DType.float32](bits)
        if index < LTC_FLOATS:
            first.append(value)
        else:
            second.append(value)
    return LtcTables(first^, second^)


def ltc_uv(dot_nv: Float32, roughness: Float32) -> Vector2:
    """Return where a roughness and a viewing angle land in the tables:
    three.js's `LTC_Uv`.

    Across by the roughness, down by the square root of one minus the
    cosine between the normal and the eye, each squeezed onto the texel
    centers so a lookup at zero reads the first texel whole and one at one
    the last.

    Args:
        dot_nv: The cosine between the normal and the eye, zero to one.
        roughness: The floored roughness.

    Returns:
        The coordinate, zero to one each way.
    """
    var grazing = sqrt(1 - dot_nv)
    return Vector2(
        roughness * LTC_SCALE + LTC_BIAS, grazing * LTC_SCALE + LTC_BIAS
    )


def ltc_texel(uv: Vector2) -> SIMD[DType.float32, 4]:
    """Return which texels a lookup reads and how it weights them: the
    column and row of the texel above and to the left of the coordinate,
    and the fractions toward the next column and row, as a bilinear
    float texture reads it.

    Args:
        uv: What `ltc_uv` returned.

    Returns:
        The column, the row, the fraction across and the fraction down.
    """
    var across = uv.x * Float32(LTC_SIZE) - 0.5
    var down = uv.y * Float32(LTC_SIZE) - 0.5
    if across < 0:
        across = 0
    if down < 0:
        down = 0
    var column = Float32(Int(across))
    var row = Float32(Int(down))
    if column > Float32(LTC_SIZE - 1):
        column = Float32(LTC_SIZE - 1)
    if row > Float32(LTC_SIZE - 1):
        row = Float32(LTC_SIZE - 1)
    return SIMD[DType.float32, 4](column, row, across - column, down - row)


def ltc_neighbor(column: Int, row: Int) -> Int:
    """Return the offset of a texel's four floats, the edges clamped.

    Args:
        column: The column, which can be one past the last.
        row: The row, which can be one past the last.

    Returns:
        Where the texel's first float is.
    """
    var c = column
    var r = row
    if c >= LTC_SIZE:
        c = LTC_SIZE - 1
    if r >= LTC_SIZE:
        r = LTC_SIZE - 1
    return (r * LTC_SIZE + c) * 4


def ltc_lookup(table: List[Float32], uv: Vector2) -> SIMD[DType.float32, 4]:
    """Return a table's four numbers at a coordinate, bilinearly filtered.

    Args:
        table: Either table, loaded.
        uv: What `ltc_uv` returned.

    Returns:
        The four numbers.
    """
    var place = ltc_texel(uv)
    var column = Int(place[0])
    var row = Int(place[1])
    return ltc_blend(
        _texel_of(table, ltc_neighbor(column, row)),
        _texel_of(table, ltc_neighbor(column + 1, row)),
        _texel_of(table, ltc_neighbor(column, row + 1)),
        _texel_of(table, ltc_neighbor(column + 1, row + 1)),
        place[2],
        place[3],
    )


def _texel_of(table: List[Float32], at: Int) -> SIMD[DType.float32, 4]:
    """Return the four floats of a table from `at`, lane by lane as the
    device reads them."""
    var texel = SIMD[DType.float32, 4](0)
    for lane in range(4):  # pragma: no branch
        texel[lane] = table[at + lane]
    return texel


def ltc_blend(
    top_left: SIMD[DType.float32, 4],
    top_right: SIMD[DType.float32, 4],
    bottom_left: SIMD[DType.float32, 4],
    bottom_right: SIMD[DType.float32, 4],
    tx: Float32,
    ty: Float32,
) -> SIMD[DType.float32, 4]:
    """Return four texels blended bilinearly, the arithmetic both
    rasterizers share once each has fetched them.

    Args:
        top_left: The texel above and to the left of the coordinate.
        top_right: The one to its right.
        bottom_left: The one below it.
        bottom_right: The one below and to the right.
        tx: The fraction toward the right pair.
        ty: The fraction toward the lower pair.

    Returns:
        The blend.
    """
    var above = top_left * (1 - tx) + top_right * tx
    var below = bottom_left * (1 - tx) + bottom_right * tx
    return above * (1 - ty) + below * ty


def ltc_clipped_sphere_form_factor(f: Vector3) -> Float32:
    """Return the form factor of a polygon from its vector form factor,
    clipped at the horizon: three.js's `LTC_ClippedSphereFormFactor`, the
    approximation from "Real-Time Area Lighting: a Journey from Research to
    Production".

    Args:
        f: The sum of the edges' vector form factors.

    Returns:
        The form factor, never below zero.
    """
    var length = f.length()
    var factor = (length * length + f.z) / (length + 1)
    if factor < 0:
        return 0
    return factor


def ltc_edge_vector_form_factor(v1: Vector3, v2: Vector3) -> Vector3:
    """Return one edge's vector form factor: three.js's
    `LTC_EdgeVectorFormFactor`, its rational fit to `theta / sin(theta) / 2pi`.

    Args:
        v1: The edge's first end, on the unit sphere.
        v2: Its second end, on the unit sphere.

    Returns:
        The edge's contribution.
    """
    var x = v1.dot(v2)
    var y = x
    if y < 0:
        y = -y
    var a = 0.8543985 + (0.4965155 + 0.0145206 * y) * y
    var b = 3.4175940 + (4.1616724 + y) * y
    var v = a / b
    var theta_sintheta = v
    if x <= 0:
        var under = 1 - x * x
        if under < 1e-7:
            under = 1e-7
        theta_sintheta = 0.5 / sqrt(under) - v
    var crossed = v1
    crossed.cross(v2)
    return Vector3(
        crossed.x * theta_sintheta,
        crossed.y * theta_sintheta,
        crossed.z * theta_sintheta,
    )


def _transformed(
    minv: SIMD[DType.float32, 4],
    t1: Vector3,
    t2: Vector3,
    normal: Vector3,
    point: Vector3,
) -> Vector3:
    """Return `point` in the surface's frame and through the inverse
    transform: three.js's `mat * (rectCoords[i] - P)` with `mat = mInv *
    transposeMat3(mat3(T1, T2, N))`.

    The transposed frame takes a world vector to its coordinates along
    `t1`, `t2` and the normal. The inverse transform is the matrix
    `[[a, 0, b], [0, 1, 0], [c, 0, d]]` three.js builds from the table's
    four numbers, column major, applied to that.
    """
    var along_t1 = t1.dot(point)
    var along_t2 = t2.dot(point)
    var along_n = normal.dot(point)
    # mInv's columns are (a, 0, b), (0, 1, 0), (c, 0, d) for the table's
    # (x, y, z, w) as (a, b, c, d).
    return Vector3(
        minv[0] * along_t1 + minv[2] * along_n,
        along_t2,
        minv[1] * along_t1 + minv[3] * along_n,
    )


def ltc_evaluate(
    normal: Vector3,
    toward_eye: Vector3,
    position: Vector3,
    minv: SIMD[DType.float32, 4],
    corner0: Vector3,
    corner1: Vector3,
    corner2: Vector3,
    corner3: Vector3,
) -> Float32:
    """Return how much of a rectangle of light a surface receives through
    a lobe: three.js's `LTC_Evaluate`.

    Nothing from behind the rectangle: it shines one way. Otherwise the
    surface's frame is built around its normal and the eye, the corners
    are taken into that frame, pushed through the inverse transform and
    projected onto the unit sphere, and the polygon's form factor is
    summed edge by edge and clipped at the horizon.

    Args:
        normal: The surface's unit normal.
        toward_eye: Unit vector from the surface toward the camera.
        position: Where the surface is, in world space.
        minv: The inverse transform's four numbers, `(1, 0, 0, 1)` for
            the identity the diffuse term takes.
        corner0: The rectangle's first corner, counterclockwise seen from
            the side it shines toward.
        corner1: Its second corner.
        corner2: Its third corner.
        corner3: Its fourth corner.

    Returns:
        The form factor, zero through about one.
    """
    var v1 = corner1 - corner0
    var v2 = corner3 - corner0
    var light_normal = v1
    light_normal.cross(v2)
    if light_normal.dot(position - corner0) < 0:
        return 0
    # An orthonormal basis around the normal, from the eye: three.js's
    # `T1 = normalize(V - N * dot(V, N))`. Seen straight along the normal
    # the eye gives no tangent, where GLSL would normalize a zero vector;
    # any tangent serves then, since the lobe is symmetric about the
    # normal, and the axis least along it is taken.
    var along = normal.dot(toward_eye)
    var t1 = Vector3(
        toward_eye.x - normal.x * along,
        toward_eye.y - normal.y * along,
        toward_eye.z - normal.z * along,
    )
    if t1.length() < 1e-6:
        t1 = normal
        if normal.x * normal.x < 0.5:
            t1.cross(Vector3(1, 0, 0))
        else:
            t1.cross(Vector3(0, 1, 0))
    t1.normalize()
    var t2 = normal
    t2.cross(t1)
    t2 = Vector3(-t2.x, -t2.y, -t2.z)
    var c0 = _transformed(minv, t1, t2, normal, corner0 - position)
    var c1 = _transformed(minv, t1, t2, normal, corner1 - position)
    var c2 = _transformed(minv, t1, t2, normal, corner2 - position)
    var c3 = _transformed(minv, t1, t2, normal, corner3 - position)
    # `normalize` leaves a zero vector alone: a corner the transform
    # squashes onto the surface stays where it is.
    c0.normalize()
    c1.normalize()
    c2.normalize()
    c3.normalize()
    var total = ltc_edge_vector_form_factor(c0, c1)
    total = total + ltc_edge_vector_form_factor(c1, c2)
    total = total + ltc_edge_vector_form_factor(c2, c3)
    total = total + ltc_edge_vector_form_factor(c3, c0)
    return ltc_clipped_sphere_form_factor(total)


def rect_area_light(
    normal: Vector3,
    toward_eye: Vector3,
    position: Vector3,
    light_position: Vector3,
    half_width: Vector3,
    half_height: Vector3,
    diffuse_color: Vector3,
    specular_color: Vector3,
    minv: SIMD[DType.float32, 4],
    fresnel: SIMD[DType.float32, 4],
) -> RectLight:
    """Return what one rectangle of light adds to a physical surface, its
    diffuse and its specular: three.js's `RE_Direct_RectArea_Physical`
    before the light's color multiplies it.

    The rectangle's corners are counterclockwise seen from the side it
    shines toward, its node's -z, as three.js lays them out from the
    light's `halfWidth` and `halfHeight`. The specular takes the table's
    transform and Stephen Hill's Fresnel approximation from the second
    table's first two numbers; the diffuse takes the identity.

    Args:
        normal: The surface's unit normal.
        toward_eye: Unit vector from the surface toward the camera.
        position: Where the surface is.
        light_position: Where the rectangle's center is.
        half_width: From the center to the middle of a side, in world space.
        half_height: From the center to the middle of the other side.
        diffuse_color: The surface's diffuse color, linear.
        specular_color: Its reflectance head on, linear.
        minv: The first table's four numbers for this roughness and angle.
        fresnel: The second table's four numbers for the same.

    Returns:
        The diffuse and the specular, each to be multiplied by the light's
        radiance.
    """
    var corner0 = light_position + half_width - half_height
    var corner1 = light_position - half_width - half_height
    var corner2 = light_position - half_width + half_height
    var corner3 = light_position + half_width + half_height
    var lobe = ltc_evaluate(
        normal, toward_eye, position, minv, corner0, corner1, corner2, corner3
    )
    var flat = ltc_evaluate(
        normal,
        toward_eye,
        position,
        SIMD[DType.float32, 4](1, 0, 0, 1),
        corner0,
        corner1,
        corner2,
        corner3,
    )
    var specular = Vector3(
        (specular_color.x * fresnel[0] + (1 - specular_color.x) * fresnel[1])
        * lobe,
        (specular_color.y * fresnel[0] + (1 - specular_color.y) * fresnel[1])
        * lobe,
        (specular_color.z * fresnel[0] + (1 - specular_color.z) * fresnel[1])
        * lobe,
    )
    var diffuse = Vector3(
        diffuse_color.x * flat, diffuse_color.y * flat, diffuse_color.z * flat
    )
    return RectLight(diffuse, specular)
