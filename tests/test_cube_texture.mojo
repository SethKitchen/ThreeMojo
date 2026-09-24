# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.cube_texture` and `render.cube_texture_store`.

The one thing that has to be right here is which face a direction reads
and which way round the face is read. Both are asserted against
worked-out answers: a direction along an axis reads that axis's face at
its middle, and a direction leaning toward a face's right edge, as the
camera that rendered it would see its right, reads that edge.
"""

from math.vector2 import Vector2
from std.math import sqrt
from math.vector3 import Vector3
from render.cube_texture import (
    FACE_COUNT,
    NEGATIVE_X,
    NEGATIVE_Y,
    NEGATIVE_Z,
    POSITIVE_X,
    POSITIVE_Y,
    POSITIVE_Z,
    SEEN_FROM_INSIDE,
    SEEN_FROM_OUTSIDE,
    CubeLayout,
    CubeTexture,
    cube_texture_from,
    cube_texture_of,
    face_forward,
    face_of,
    face_up,
    face_uv,
    reflected,
    reflection_level,
    rough_reflection,
)
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
    CubeTextureStore,
)
from render.framebuffer import Color, Framebuffer
from render.png import DecodedImage
from render.srgb import LINEAR, SRGB, UNKNOWN_SPACE
from render.texture import (
    BILINEAR,
    CLAMP,
    IGNORED,
    NEAREST,
    REPEAT,
    Filter,
    Texture,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(1e-6)

# One color per face, in face order: red, green, blue, yellow, cyan,
# magenta.
comptime RED = Color(255, 0, 0)
comptime GREEN = Color(0, 255, 0)
comptime BLUE = Color(0, 0, 255)
comptime YELLOW = Color(255, 255, 0)
comptime CYAN = Color(0, 255, 255)
comptime MAGENTA = Color(255, 0, 255)


def face_colors() -> List[Color]:
    """Return the six face colors, in face order."""
    return [RED, GREEN, BLUE, YELLOW, CYAN, MAGENTA]


def solid(size: Int, color: Color) raises -> Texture:
    """Return a square texture of one color, clamped and nearest."""
    var pixels = List[UInt8]()
    for _ in range(size * size):
        pixels.append(color.r)
        pixels.append(color.g)
        pixels.append(color.b)
        pixels.append(color.a)
    return Texture(size, size, pixels^, CLAMP, NEAREST, SRGB, False)


def six_solid(size: Int = 2) raises -> List[Texture]:
    """Return six one-color faces, in face order."""
    var faces = List[Texture]()
    for color in face_colors():
        faces.append(solid(size, color))
    return faces^


def halves(left: Color, right: Color) -> List[UInt8]:
    """Return a 2x2 image's bytes, `left` down the left column and `right`
    down the right."""
    var pixels = List[UInt8]()
    for _ in range(2):
        for tint in [left, right]:
            pixels.append(tint.r)
            pixels.append(tint.g)
            pixels.append(tint.b)
            pixels.append(255)
    return pixels^


def assert_color(got: Color, want: Color) raises:
    """Assert two colors match in every channel."""
    assert_equal(got.r, want.r)
    assert_equal(got.g, want.g)
    assert_equal(got.b, want.b)
    assert_equal(got.a, want.a)


# --- the two tables ---------------------------------------------------------


def test_each_face_looks_along_its_own_axis() raises:
    assert_equal(face_forward(POSITIVE_X).x, Float32(1))
    assert_equal(face_forward(NEGATIVE_X).x, Float32(-1))
    assert_equal(face_forward(POSITIVE_Y).y, Float32(1))
    assert_equal(face_forward(NEGATIVE_Y).y, Float32(-1))
    assert_equal(face_forward(POSITIVE_Z).z, Float32(1))
    assert_equal(face_forward(NEGATIVE_Z).z, Float32(-1))
    # An index that is no face reads as the last one rather than raising:
    # the kernel calls this and cannot raise.
    assert_equal(face_forward(9).z, Float32(-1))


def test_up_is_y_except_on_the_y_faces() raises:
    # three.js's own six ups under the WebGL coordinate system.
    for face in [POSITIVE_X, NEGATIVE_X, POSITIVE_Z, NEGATIVE_Z, 9]:
        assert_equal(face_up(face).y, Float32(1))
    assert_equal(face_up(POSITIVE_Y).z, Float32(-1))
    assert_equal(face_up(NEGATIVE_Y).z, Float32(1))


def test_forward_and_up_are_at_right_angles_on_every_face() raises:
    # A camera needs its up off its view direction, or `look_at` has no
    # frame; the two tables keep them perpendicular.
    for face in range(FACE_COUNT):
        assert_equal(face_forward(face).dot(face_up(face)), Float32(0))
        assert_equal(face_forward(face).length(), Float32(1))
        assert_equal(face_up(face).length(), Float32(1))


# --- which face, and where on it ---------------------------------------------


def test_a_direction_along_an_axis_reads_that_face() raises:
    assert_equal(face_of(Vector3(2, 0, 0)), POSITIVE_X)
    assert_equal(face_of(Vector3(-2, 0.5, 0.5)), NEGATIVE_X)
    assert_equal(face_of(Vector3(0, 3, 0)), POSITIVE_Y)
    assert_equal(face_of(Vector3(0.2, -3, 0.2)), NEGATIVE_Y)
    assert_equal(face_of(Vector3(0, 0, 4)), POSITIVE_Z)
    assert_equal(face_of(Vector3(0.3, 0.3, -4)), NEGATIVE_Z)


def test_a_tie_goes_to_x_then_y_then_z() raises:
    # OpenGL's own tie-break, so both backends read one face along an
    # edge rather than each preferring its own.
    assert_equal(face_of(Vector3(1, 1, 0)), POSITIVE_X)
    assert_equal(face_of(Vector3(-1, -1, -1)), NEGATIVE_X)
    assert_equal(face_of(Vector3(0, 1, 1)), POSITIVE_Y)
    assert_equal(face_of(Vector3(0, -1, -1)), NEGATIVE_Y)
    # The zero vector leans along nothing and is given positive x.
    assert_equal(face_of(Vector3(0, 0, 0)), POSITIVE_X)


def test_the_axis_itself_reads_the_middle_of_its_face() raises:
    for face in range(FACE_COUNT):
        var place = face_uv(face, face_forward(face) * 3)
        assert_almost_equal(Float64(place.x), 0.5, atol=TOLERANCE)
        assert_almost_equal(Float64(place.y), 0.5, atol=TOLERANCE)


def test_leaning_toward_up_reads_the_top_of_the_face() raises:
    for face in range(FACE_COUNT):
        var place = face_uv(face, face_forward(face) + face_up(face))
        assert_almost_equal(Float64(place.x), 0.5, atol=TOLERANCE)
        assert_almost_equal(Float64(place.y), 1.0, atol=TOLERANCE)


def test_leaning_toward_the_cameras_right_reads_the_right_edge() raises:
    # A camera's right is its forward crossed with its up. Looking along
    # +x with +y up, that is +z: the right edge of the +x face is toward
    # +z, as the camera that rendered it saw it.
    var place = face_uv(POSITIVE_X, Vector3(1, 0, 1))
    assert_almost_equal(Float64(place.x), 1.0, atol=TOLERANCE)
    assert_almost_equal(Float64(place.y), 0.5, atol=TOLERANCE)
    # And -z is the left edge, and a lean of half reads a quarter in.
    var left = face_uv(POSITIVE_X, Vector3(2, 0, -1))
    assert_almost_equal(Float64(left.x), 0.25, atol=TOLERANCE)


def test_the_zero_vector_reads_the_middle() raises:
    var place = face_uv(POSITIVE_X, Vector3(0, 0, 0))
    assert_almost_equal(Float64(place.x), 0.5, atol=TOLERANCE)
    assert_almost_equal(Float64(place.y), 0.5, atol=TOLERANCE)


def test_a_reflection_turns_the_view_back_through_the_normal() raises:
    # Square on, the surface reflects the camera.
    var back = reflected(Vector3(0, 0, 1), Vector3(0, 0, 1))
    assert_almost_equal(Float64(back.z), 1.0, atol=TOLERANCE)
    # At forty-five degrees the view bounces off sideways.
    var toward = Vector3(1, 0, 1)
    toward.normalize()
    var off = reflected(toward, Vector3(0, 0, 1))
    assert_almost_equal(Float64(off.x), Float64(-toward.x), atol=TOLERANCE)
    assert_almost_equal(Float64(off.z), Float64(toward.z), atol=TOLERANCE)
    assert_almost_equal(Float64(off.length()), 1.0, atol=TOLERANCE)
    # A grazing view reflects on past the surface.
    var grazing = reflected(Vector3(1, 0, 0), Vector3(0, 0, 1))
    assert_almost_equal(Float64(grazing.x), -1.0, atol=TOLERANCE)


# --- the cube texture ----------------------------------------------------------


def test_a_cube_samples_each_face_by_direction() raises:
    var cube = CubeTexture(six_solid())
    assert_equal(cube.size, 2)
    var colors = face_colors()
    for face in range(FACE_COUNT):
        var seen = cube.sample(face_forward(face)).encode()
        assert_color(seen, colors[face])
    # A lean that stays on the face reads the same color.
    assert_color(cube.sample(Vector3(1, 0.4, -0.4)).encode(), RED)


def test_a_face_is_borrowed_by_index() raises:
    var cube = CubeTexture(six_solid(4))
    assert_equal(cube.face(POSITIVE_Y).width, 4)
    assert_equal(cube.face(NEGATIVE_Z).texel(0, 0).r, MAGENTA.r)
    with assert_raises():
        _ = cube.face(FACE_COUNT).width
    with assert_raises():
        _ = cube.face(-1).width


def test_a_cube_needs_exactly_six_faces() raises:
    var five = six_solid()
    _ = five.pop()
    with assert_raises():
        _ = CubeTexture(five^)
    var seven = six_solid()
    seven.append(solid(2, RED))
    with assert_raises():
        _ = CubeTexture(seven^)


def test_a_cube_refuses_a_blank_face() raises:
    var faces = six_solid()
    faces[3] = Texture()
    with assert_raises():
        _ = CubeTexture(faces^)


def test_a_cube_refuses_a_face_that_is_not_square() raises:
    var faces = six_solid()
    var pixels = List[UInt8]()
    for _ in range(2 * 3 * 4):
        pixels.append(7)
    faces[1] = Texture(2, 3, pixels^, CLAMP, NEAREST, SRGB, False)
    with assert_raises():
        _ = CubeTexture(faces^)


def test_a_cube_refuses_faces_of_two_sizes() raises:
    var faces = six_solid()
    faces[5] = solid(4, MAGENTA)
    with assert_raises():
        _ = CubeTexture(faces^)


def test_a_cube_refuses_a_face_that_is_not_clamped() raises:
    # A coordinate past a face's edge belongs to the next face, which a
    # flat image cannot read, so the edge must hold.
    var faces = six_solid()
    faces[0] = Texture(2, 2, halves(RED, RED), REPEAT, NEAREST, SRGB, False)
    with assert_raises():
        _ = CubeTexture(faces^)


def test_a_face_edited_into_nonsense_is_refused_on_validate() raises:
    var cube = CubeTexture(six_solid())
    cube.validate()
    cube.faces[2].mag_filter = Filter(9)
    with assert_raises():
        cube.validate()


def test_a_cube_copies_its_faces() raises:
    var cube = CubeTexture(six_solid())
    var twin = CubeTexture(copy=cube)
    assert_equal(twin.size, 2)
    assert_color(twin.sample(Vector3(0, -1, 0)).encode(), YELLOW)
    # Its own faces: editing the copy leaves the original alone.
    twin.faces[3] = solid(2, RED)
    assert_color(cube.sample(Vector3(0, -1, 0)).encode(), YELLOW)


# --- from images and from renders ---------------------------------------------


def six_images(left: Color, right: Color) -> List[DecodedImage]:
    """Return six 2x2 images, each `left` down its left column and `right`
    down its right, declared sRGB."""
    var images = List[DecodedImage]()
    for _ in range(FACE_COUNT):
        images.append(DecodedImage(2, 2, halves(left, right), SRGB))
    return images^


def test_images_seen_from_inside_are_read_as_they_are() raises:
    # Leaning toward a face's right, as its camera saw right, reads the
    # right column.
    var cube = cube_texture_from(six_images(RED, GREEN))
    assert_color(cube.sample(Vector3(1, 0, 0.5)).encode(), GREEN)
    assert_color(cube.sample(Vector3(1, 0, -0.5)).encode(), RED)
    assert_equal(cube.face(0).wrap_s, CLAMP)
    assert_equal(cube.face(0).mag_filter, BILINEAR)
    assert_equal(cube.face(0).levels, 1)


def _texel(face: Int, x: Int, y: Int) -> Color:
    """Return a color unique to one texel of one face."""
    return Color(
        UInt8(face * 40 + 10), UInt8(x * 100 + 20), UInt8(y * 100 + 30)
    )


def _distinct_images() -> List[DecodedImage]:
    """Return six 2x2 images in which every texel of every face differs."""
    var images = List[DecodedImage]()
    for face in range(FACE_COUNT):
        var pixels = List[UInt8]()
        for y in range(2):
            for x in range(2):
                var tint = _texel(face, x, y)
                pixels.append(tint.r)
                pixels.append(tint.g)
                pixels.append(tint.b)
                pixels.append(255)
        images.append(DecodedImage(2, 2, pixels^, SRGB))
    return images^


def _three_js_direction(face: Int, x: Int, y: Int) -> Vector3:
    """Return the direction three.js shows one texel of an image cube in.

    `LightProbeGenerator.fromCubeTexture` of three.js 0.180, which walks
    the six images of a `CubeTextureLoader` cube as `flipEnvMap` samples
    them: `col` counts right and `row` counts up, and image `face` lies
    along the axis this table gives. The px image lies toward -x.
    """
    var col = Float32(-1) + (Float32(x) + 0.5)
    var row = Float32(1) - (Float32(y) + 0.5)
    if face == 0:
        return Vector3(-1, row, -col)
    if face == 1:
        return Vector3(1, row, col)
    if face == 2:
        return Vector3(-col, 1, -row)
    if face == 3:
        return Vector3(-col, -1, row)
    if face == 4:
        return Vector3(-col, row, 1)
    return Vector3(col, row, -1)


def test_images_seen_from_outside_are_where_three_js_shows_them() raises:
    # three.js's layout: the px and nx images trade places, and no image
    # is mirrored. Every texel of every image is read in the direction
    # three.js shows it in.
    var cube = cube_texture_from(_distinct_images(), SEEN_FROM_OUTSIDE, NEAREST)
    for face in range(FACE_COUNT):
        for y in range(2):
            for x in range(2):
                var seen = cube.sample(_three_js_direction(face, x, y))
                assert_color(seen.encode(), _texel(face, x, y))
    # The px image is the face that looks along -x, as it is.
    assert_color(cube.sample(Vector3(-1, 0.5, 0.5)).encode(), _texel(0, 0, 0))
    assert_color(cube.sample(Vector3(1, 0.5, 0.5)).encode(), _texel(1, 1, 0))
    assert_equal(cube.face(0).mag_filter, NEAREST)


def _render_target_direction(face: Int, column: Int, row: Int) -> Vector3:
    """Return the direction three.js reads one texel of a cube render
    target in.

    three.js 0.180's `CubeCamera` renders each face with a field of view of
    minus ninety degrees, which turns the view a half turn, into a WebGL
    framebuffer whose row zero is the bottom. `flipEnvMap` is one for a
    render target, so the OpenGL cube map table reads it as it is:
    `column` is `s` and `row` is `t`, both counting from zero.
    """
    var sc = (Float32(column) + 0.5) - 1
    var tc = (Float32(row) + 0.5) - 1
    if face == 0:
        return Vector3(1, -tc, -sc)
    if face == 1:
        return Vector3(-1, -tc, sc)
    if face == 2:
        return Vector3(sc, 1, tc)
    if face == 3:
        return Vector3(sc, -1, -tc)
    if face == 4:
        return Vector3(sc, -tc, 1)
    return Vector3(-sc, -tc, -1)


def test_a_rendered_face_is_three_js_render_target_face_mirrored() raises:
    # A face that `render_cube` returns holds the rows of three.js's cube
    # render target face in the same order, and each row mirrored: this
    # port's face is the camera's own view, and three.js's is read through
    # a left-handed table. Each texel stands for the same direction.
    var frames = List[Framebuffer]()
    for face in range(FACE_COUNT):
        var pixels = List[UInt8]()
        for y in range(2):
            for x in range(2):
                var tint = _texel(face, x, y)
                pixels.append(tint.r)
                pixels.append(tint.g)
                pixels.append(tint.b)
                pixels.append(255)
        frames.append(Framebuffer(2, 2, pixels^))
    var cube = cube_texture_of(frames, NEAREST)
    for face in range(FACE_COUNT):
        for y in range(2):
            for x in range(2):
                var seen = cube.sample(_render_target_direction(face, 1 - x, y))
                assert_color(seen.encode(), _texel(face, x, y))


def test_a_cube_can_be_built_with_a_chain_and_a_space() raises:
    var cube = cube_texture_from(
        six_images(RED, GREEN),
        color_space=LINEAR,
        mipmapped=True,
        alpha=IGNORED,
    )
    assert_equal(cube.face(0).color_space, LINEAR)
    assert_equal(cube.face(0).levels, 2)
    assert_equal(cube.face(0).alpha, IGNORED)


def test_six_images_are_needed_and_a_known_layout() raises:
    var five = six_images(RED, GREEN)
    _ = five.pop()
    with assert_raises():
        _ = cube_texture_from(five^)
    with assert_raises():
        _ = cube_texture_from(six_images(RED, GREEN), CubeLayout(7))
    assert_true(SEEN_FROM_INSIDE.is_valid())
    assert_true(SEEN_FROM_OUTSIDE.is_valid())
    assert_false(CubeLayout(7).is_valid())


def test_an_uninterpretable_color_space_must_be_settled() raises:
    var images = List[DecodedImage]()
    for _ in range(FACE_COUNT):
        images.append(DecodedImage(2, 2, halves(RED, GREEN), UNKNOWN_SPACE))
    with assert_raises():
        _ = cube_texture_from(images)
    # Settled by the caller, the same images are fine.
    var cube = cube_texture_from(images, color_space=SRGB)
    assert_equal(cube.face(0).color_space, SRGB)


def test_an_empty_image_is_refused() raises:
    var images = six_images(RED, GREEN)
    images[2] = DecodedImage(0, 0, List[UInt8](), SRGB)
    with assert_raises():
        _ = cube_texture_from(images, SEEN_FROM_OUTSIDE)
    # Either dimension alone, too.
    images[2] = DecodedImage(2, 0, List[UInt8](), SRGB)
    with assert_raises():
        _ = cube_texture_from(images, SEEN_FROM_OUTSIDE)
    images[2] = DecodedImage(0, 2, List[UInt8](), SRGB)
    with assert_raises():
        _ = cube_texture_from(images, SEEN_FROM_OUTSIDE)


def test_six_renders_become_a_cube() raises:
    var frames = List[Framebuffer]()
    for color in face_colors():
        frames.append(Framebuffer(3, 3, color))
    var cube = cube_texture_of(frames)
    assert_equal(cube.size, 3)
    assert_equal(cube.face(0).color_space, SRGB)
    assert_equal(cube.face(0).wrap_s, CLAMP)
    assert_color(cube.sample(Vector3(0, 0, -1)).encode(), MAGENTA)
    # With a chain and nearest, when asked.
    var chained = cube_texture_of(frames, NEAREST, True, IGNORED)
    assert_equal(chained.face(0).levels, 2)
    assert_equal(chained.face(0).mag_filter, NEAREST)
    assert_equal(chained.face(0).alpha, IGNORED)
    _ = frames.pop()
    with assert_raises():
        _ = cube_texture_of(frames)


def test_a_render_that_is_not_square_is_refused() raises:
    var frames = List[Framebuffer]()
    for color in face_colors():
        frames.append(Framebuffer(4, 3, color))
    with assert_raises():
        _ = cube_texture_of(frames)


# --- the store -------------------------------------------------------------------


def test_the_store_hands_out_ids_in_order() raises:
    var store = CubeTextureStore()
    assert_equal(store.count(), 0)
    var first = store.add(CubeTexture(six_solid()))
    var second = store.add(CubeTexture(six_solid(4)))
    assert_equal(first, CubeTextureId(0))
    assert_equal(second, CubeTextureId(1))
    assert_equal(store.count(), 2)
    assert_equal(store.get(second).size, 4)
    assert_color(store.get(first).sample(Vector3(0, 1, 0)).encode(), BLUE)


def test_the_store_refuses_what_is_not_an_id() raises:
    var store = CubeTextureStore()
    _ = store.add(CubeTexture(six_solid()))
    with assert_raises():
        _ = store.get(CubeTextureId(1)).size
    with assert_raises():
        _ = store.get(NO_CUBE_TEXTURE).size
    with assert_raises():
        _ = store.get(SCENE_ENVIRONMENT).size
    # The two absences are values of their own, and not each other.
    assert_true(NO_CUBE_TEXTURE != SCENE_ENVIRONMENT)
    assert_true(NO_CUBE_TEXTURE.value < 0)
    assert_true(SCENE_ENVIRONMENT.value < 0)


# --- reading the chain by roughness ------------------------------------------


def test_a_cube_reads_its_chain_by_level() raises:
    # Faces of two halves, left black and right white, with a chain: the
    # full size reads one half, and the coarsest level reads the average.
    var faces = List[Texture]()
    for _ in range(FACE_COUNT):
        faces.append(
            Texture(
                2,
                2,
                halves(Color(0, 0, 0), Color(255, 255, 255)),
                CLAMP,
                NEAREST,
                LINEAR,
            )
        )
    var cube = CubeTexture(faces^)
    assert_equal(cube.levels(), 2)
    # Straight along +x reads the middle of the face, which is the seam;
    # a lean toward the camera's right reads the white half.
    var sharp = cube.sample_level(Vector3(1, 0, 0.4), 0)
    assert_equal(sharp.r, Float32(1))
    var blurred = cube.sample_level(Vector3(1, 0, 0.4), 1)
    assert_almost_equal(blurred.r, Float32(0.5), atol=1e-2)
    # Between the two, between the two.
    var between = cube.sample_level(Vector3(1, 0, 0.4), 0.5)
    assert_almost_equal(between.r, Float32(0.75), atol=1e-2)
    # A cube without a chain reads its one image at every level.
    var flat = CubeTexture(six_solid())
    assert_equal(flat.levels(), 1)
    assert_color(flat.sample_level(Vector3(1, 0, 0), 3).encode(), RED)
    assert_color(flat.sample_level(Vector3(0, 1, 0), 0).encode(), BLUE)


def test_a_roughness_picks_a_level_and_bends_the_reflection() raises:
    # Zero reads the full size and one the coarsest level, linearly.
    assert_equal(reflection_level(0, 5), Float32(0))
    assert_equal(reflection_level(1, 5), Float32(4))
    assert_equal(reflection_level(0.5, 5), Float32(2))
    assert_equal(reflection_level(1, 1), Float32(0))
    # A smooth surface reflects the view exactly; a rough one bends the
    # reflection toward the normal by the square of the roughness, and
    # what comes back is unit length.
    var eye = Vector3(0, 0, 1)
    var tilted = Vector3(1, 0, 1)
    tilted.normalize()
    var sharp = rough_reflection(eye, tilted, 0)
    var exact = reflected(eye, tilted)
    assert_almost_equal(sharp.x, exact.x, atol=1e-6)
    assert_almost_equal(sharp.z, exact.z, atol=1e-6)
    var rough = rough_reflection(eye, tilted, 1)
    assert_almost_equal(rough.x, tilted.x, atol=1e-6)
    assert_almost_equal(rough.z, tilted.z, atol=1e-6)
    var half = rough_reflection(eye, tilted, 0.5)
    assert_almost_equal(half.length(), Float32(1), atol=1e-6)
    assert_true(half.x < exact.x, "the reflection did not bend")
    assert_true(half.x > tilted.x, "the reflection bent past the normal")
    # Opposite directions that cancel leave nothing to normalize, and the
    # zero vector comes back as it is.
    var cancelled = rough_reflection(Vector3(0, 0, 1), Vector3(0, 0, 0), 1)
    assert_equal(cancelled.length(), Float32(0))


def test_a_rising_roughness_moves_a_reflection_steadily_to_the_average() raises:
    # Four-texel faces of two halves, black and white, with three levels:
    # the same direction, on the white half, read at a rising roughness
    # falls from white toward the average and never rises on the way.
    var faces = List[Texture]()
    for _ in range(FACE_COUNT):
        var pixels = List[UInt8]()
        for _ in range(4):
            for column in range(4):
                var tone = UInt8(0)
                if column >= 2:
                    tone = 255
                pixels.append(tone)
                pixels.append(tone)
                pixels.append(tone)
                pixels.append(255)
        faces.append(Texture(4, 4, pixels^, CLAMP, NEAREST, LINEAR))
    var cube = CubeTexture(faces^)
    assert_equal(cube.levels(), 3)
    var direction = Vector3(1, 0, 0.6)
    var last = Float32(2)
    for step in range(5):
        var roughness = Float32(step) / 4
        var seen = cube.sample_level(
            direction, reflection_level(roughness, cube.levels())
        )
        assert_true(seen.r <= last, "the reflection sharpened as it roughened")
        last = seen.r
    assert_equal(
        cube.sample_level(direction, reflection_level(0, 3)).r, Float32(1)
    )
    assert_almost_equal(
        cube.sample_level(direction, reflection_level(1, 3)).r,
        Float32(0.5),
        atol=1e-2,
    )


def test_the_coarsest_level_over_reads_a_cosine_weighted_irradiance() raises:
    # A sky that is one white face on black. The coarsest level of the
    # white face is white, which is what a physical surface facing it
    # reads as its irradiance. The cosine-weighted integral over the
    # hemisphere of what that surface sees is smaller: the face fills
    # the middle of the hemisphere but not the sides, and the sides are
    # black. The gap is the approximation; see `physical_outgoing`.
    var faces = List[Texture]()
    for face in range(FACE_COUNT):
        var tone = UInt8(0)
        if face == POSITIVE_Z:
            tone = 255
        faces.append(solid(2, Color(tone, tone, tone)))
    var cube = CubeTexture(faces^)
    var read = cube.sample_level(Vector3(0, 0, 1), Float32(cube.levels() - 1))
    assert_equal(read.r, Float32(1))
    # The integral, by a grid over the hemisphere: each direction's
    # cosine times what the cube shows there, over the cosine's own sum.
    var lit = Float64(0)
    var total = Float64(0)
    var steps = 96
    for row in range(steps):
        for column in range(steps):
            var x = (Float64(column) + 0.5) / Float64(steps) * 2 - 1
            var y = (Float64(row) + 0.5) / Float64(steps) * 2 - 1
            var flat = x * x + y * y
            if flat >= 1:
                continue
            # Directions spread uniformly over the disc are the cosine
            # weighting already, by Nusselt's analog.
            var direction = Vector3(
                Float32(x), Float32(y), Float32(sqrt(1 - flat))
            )
            lit += Float64(cube.sample_level(direction, 0).r)
            total += 1
    var reference = lit / total
    assert_true(reference > 0.5, "the face lit less than half the hemisphere")
    assert_true(reference < 0.7, "the face lit almost the whole hemisphere")
    assert_true(
        read.r > Float32(reference) + 0.25,
        "the coarsest level read the integral",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
