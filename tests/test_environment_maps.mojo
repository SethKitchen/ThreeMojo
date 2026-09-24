# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for how an environment is read: a panorama sampled directly, a
refraction mapping, the rotations and intensities of the material and the
scene, the background's blur, an object-space normal map, and the PMREMs
`renderers.environment` builds.

Every cube has six flat faces of six colors and every panorama three
columns of three, so a pixel says which direction was read. The worked
directions: a sphere's middle, seen from +z, faces the camera; it
reflects +z, and a refraction bends the view straight through it to -z.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import cube_background, texture_background
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import directional_light
from materials.material import (
    BACK_SIDE,
    BASIC,
    DEFAULT_REFRACTION_RATIO,
    LAMBERT,
    NO_ENV_ROTATION,
    OBJECT_SPACE_NORMAL_MAP,
    PHONG,
    STANDARD,
    TANGENT_SPACE_NORMAL_MAP,
    TOON,
    Material,
    MaterialId,
    NormalMapType,
)
from math.euler import XYZ, Euler, EulerOrder
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.cube_texture import (
    Basis3,
    CubeTexture,
    check_rotation,
    cube_of_panorama,
    env_rotation,
    equirect_uv,
    is_turned,
    refracted,
    validate_cube_uv,
)
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
)
from render.framebuffer import Color, FloatColor, Framebuffer
from render.pmrem import pmrem_from_cube, pmrem_from_equirectangular
from render.rasterizer import (
    RasterVertex,
    TextureFrames,
    check_triangle_state,
    env_direction,
    object_space_normal,
)
from render.srgb import LINEAR, SRGB
from render.texture import (
    CLAMP,
    CUBE_REFLECTION_MAPPING,
    CUBE_REFRACTION_MAPPING,
    EQUIRECTANGULAR_REFLECTION_MAPPING,
    EQUIRECTANGULAR_REFRACTION_MAPPING,
    IGNORED,
    NEAREST,
    REPEAT,
    UV_MAPPING,
    Mapping,
    Texture,
    BILINEAR,
    data_texture,
    float_texture,
)
from render.texture_store import TextureId
from renderers.environment import prefilter_environments
from renderers.renderer import Renderer
from std.math import nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER, RADIAN

comptime WIDTH = 32
comptime HEIGHT = 24
comptime CLEAR = Color(9, 9, 9)
comptime RED = Color(255, 0, 0)
comptime GREEN = Color(0, 255, 0)
comptime BLUE = Color(0, 0, 255)
comptime YELLOW = Color(255, 255, 0)
comptime CYAN = Color(0, 255, 255)
comptime MAGENTA = Color(255, 0, 255)


def solid(size: Int, color: Color) raises -> Texture:
    """Return a square texture of one color, clamped and nearest."""
    var pixels = List[UInt8]()
    for _ in range(size * size):
        pixels.append(color.r)
        pixels.append(color.g)
        pixels.append(color.b)
        pixels.append(color.a)
    return Texture(size, size, pixels^, CLAMP, NEAREST, SRGB, False)


def a_cube() raises -> CubeTexture:
    """Return a cube of six flat faces: red, green, blue, yellow, cyan and
    magenta, in face order."""
    var faces = List[Texture]()
    for color in [RED, GREEN, BLUE, YELLOW, CYAN, MAGENTA]:
        faces.append(solid(2, color))
    return CubeTexture(faces^)


def a_panorama(
    mapping: Mapping = EQUIRECTANGULAR_REFLECTION_MAPPING,
    mipmapped: Bool = False,
) raises -> Texture:
    """Return a 3x2 panorama of three columns: red around -z, green around
    +x and blue around +z, as `equirect_uv` lays longitude out."""
    var pixels = List[UInt8]()
    for _ in range(2):
        for color in [RED, GREEN, BLUE]:
            pixels.append(color.r)
            pixels.append(color.g)
            pixels.append(color.b)
            pixels.append(255)
    var image = Texture(3, 2, pixels^, CLAMP, NEAREST, SRGB, mipmapped)
    image.mapping = mapping
    return image^


def assert_color(got: Color, want: Color) raises:
    """Assert two colors match in red, green and blue."""
    assert_equal(got.r, want.r)
    assert_equal(got.g, want.g)
    assert_equal(got.b, want.b)


def a_renderer() raises -> Renderer:
    """Return a small renderer cleared to `CLEAR`."""
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(CLEAR)
    return renderer^


def camera_at(z: Float32) raises -> PerspectiveCamera:
    """Return a camera on the z axis, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, z), Vector3(0, 0, 0))
    return camera^


def a_ball(
    mut scene: Scene, mut assets: Assets, paint: MaterialId, turn: Float32 = 0
) raises:
    """Put one coarse sphere at the origin, turned about y, drawn with
    `paint`."""
    var ball = Object3D()
    ball.set_euler(Angle(0.0, RADIAN), Angle(turn, RADIAN), Angle(0.0, RADIAN))
    var node = scene.add(ball^)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(sphere(Length(0.9, METER), 12, 8)),
            paint,
            node,
        )
    )
    scene.update()


def center(image: Framebuffer) raises -> Color:
    """Return the pixel at the middle of the image."""
    return image.get_pixel(WIDTH // 2, HEIGHT // 2)


def turned_y(angle: Float32) -> Euler:
    """Return a turn about y alone."""
    return Euler(
        Angle(0.0, RADIAN), Angle(angle, RADIAN), Angle(0.0, RADIAN), XYZ
    )


def mirror(
    mut assets: Assets,
    env: CubeTextureId,
    rotation: Euler = NO_ENV_ROTATION,
) raises -> MaterialId:
    """Return a white basic mirror of `env`."""
    return assets.materials.add(
        Material(
            Color(255, 255, 255),
            kind=BASIC,
            env_map=env,
            env_map_rotation=rotation,
        )
    )


def draw(
    renderer: Renderer, scene: Scene, assets: Assets, z: Float32
) raises -> Color:
    """Return the middle pixel of the scene seen from `z` on the z axis."""
    return center(renderer.render(scene, assets, camera_at(z)))


# --- the shared arithmetic ------------------------------------------------------


def test_a_refraction_bends_the_view_or_answers_nothing() raises:
    # Straight on, a ratio below one goes straight through.
    var through = refracted(Vector3(0, 0, 1), Vector3(0, 0, 1), 0.98)
    assert_almost_equal(through.z, -1, atol=1e-6)
    # Past the critical angle GLSL answers the zero vector.
    var grazing = Vector3(1, 0, 0.05)
    grazing.normalize()
    var reflected_inside = refracted(grazing, Vector3(0, 0, 1), 2)
    assert_equal(reflected_inside.length(), 0)
    # The environment's direction: reflected, or refracted, then turned.
    var frames = TextureFrames()
    var back = env_direction(Vector3(0, 0, 1), Vector3(0, 0, 1), False, frames)
    assert_almost_equal(back.z, 1, atol=1e-6)
    var bent = env_direction(Vector3(0, 0, 1), Vector3(0, 0, 1), True, frames)
    assert_almost_equal(bent.z, -1, atol=1e-6)
    frames.env_rotation = env_rotation(turned_y(Float32(pi)))
    var spun = env_direction(Vector3(0, 0, 1), Vector3(0, 0, 1), False, frames)
    assert_almost_equal(spun.z, -1, atol=1e-5)


def test_an_environment_rotation_turns_the_lookup_back() raises:
    # three.js negates the angles: a quarter turn about y reads +z in
    # the direction -x.
    var quarter = env_rotation(turned_y(Float32(pi / 2)))
    var read = quarter.turn(Vector3(0, 0, 1))
    assert_almost_equal(read.x, -1, atol=1e-6)
    assert_almost_equal(read.z, 0, atol=1e-6)
    assert_true(Basis3() == env_rotation(NO_ENV_ROTATION))
    assert_false(is_turned(NO_ENV_ROTATION))
    assert_true(is_turned(turned_y(0.5)))
    var x_turned = Euler(
        Angle(0.5, RADIAN), Angle(0.0, RADIAN), Angle(0.0, RADIAN), XYZ
    )
    assert_true(is_turned(x_turned))
    var z_turned = Euler(
        Angle(0.0, RADIAN), Angle(0.0, RADIAN), Angle(0.5, RADIAN), XYZ
    )
    assert_true(is_turned(z_turned))


def test_a_rotation_no_matrix_comes_from_is_refused() raises:
    var bad = NO_ENV_ROTATION
    bad.x = Angle(nan[DType.float32](), RADIAN)
    with assert_raises(contains="finite"):
        check_rotation(bad, "A turn")
    bad = NO_ENV_ROTATION
    bad.y = Angle(nan[DType.float32](), RADIAN)
    with assert_raises(contains="finite"):
        check_rotation(bad, "A turn")
    bad = NO_ENV_ROTATION
    bad.z = Angle(nan[DType.float32](), RADIAN)
    with assert_raises(contains="finite"):
        check_rotation(bad, "A turn")
    bad = NO_ENV_ROTATION
    bad.order = EulerOrder(0, 0, 1)
    with assert_raises(contains="order"):
        _ = env_rotation(bad)


def test_an_object_space_texel_is_turned_into_the_world() raises:
    # A quarter turn about y carries the object's +x to the world's -z.
    var frame = Basis3(0, 0, -1, 0, 1, 0, 1, 0, 0)
    var normal = object_space_normal(
        Vector3(0, 0, 1), FloatColor(1.0, 0.5, 0.5, 1.0), frame
    )
    assert_almost_equal(normal.z, -1, atol=1e-6)
    # A texel that unpacks to nothing leaves the geometry's normal.
    var kept = object_space_normal(
        Vector3(0, 1, 0), FloatColor(0.5, 0.5, 0.5, 1.0), frame
    )
    assert_almost_equal(kept.y, 1, atol=1e-6)


def a_corner() raises -> RasterVertex:
    """Return one corner of a basic triangle with no maps."""
    return RasterVertex(0, 0, 0.5, 1.0, FloatColor(1, 1, 1), 0, 0)


def test_a_triangle_must_agree_about_its_frames() raises:
    var a = a_corner()
    var b = a_corner()
    var c = a_corner()
    check_triangle_state(a, b, c)
    b.frames.refraction_ratio = 0.5
    with assert_raises(contains="frames"):
        check_triangle_state(a, b, c)
    b.frames.refraction_ratio = DEFAULT_REFRACTION_RATIO
    c.frames.normal_map_type = OBJECT_SPACE_NORMAL_MAP
    with assert_raises(contains="frames"):
        check_triangle_state(a, b, c)
    a.frames.normal_map_type = NormalMapType(7)
    with assert_raises(contains="normal map type"):
        check_triangle_state(a, b, c)
    a.frames.normal_map_type = TANGENT_SPACE_NORMAL_MAP
    a.frames.refraction_ratio = -1
    with assert_raises(contains="refraction ratio"):
        check_triangle_state(a, b, c)
    a.frames.refraction_ratio = nan[DType.float32]()
    with assert_raises(contains="refraction ratio"):
        check_triangle_state(a, b, c)


# --- a cube made from a panorama ----------------------------------------------


def test_a_panorama_cube_reads_the_panorama_itself() raises:
    var cube = cube_of_panorama(a_panorama())
    assert_true(cube.has_panorama())
    assert_equal(cube.mapping, EQUIRECTANGULAR_REFLECTION_MAPPING)
    # +z is the blue column, -z the red and +x the green.
    var ahead = cube.sample(Vector3(0, 0, 1))
    assert_almost_equal(ahead.b, 1, atol=1e-6)
    assert_almost_equal(cube.sample(Vector3(0, 0, -1)).r, 1, atol=1e-6)
    assert_almost_equal(cube.sample(Vector3(1, 0, 0)).g, 1, atol=1e-6)
    # Down its chain, the panorama's: one level here.
    assert_equal(cube.levels(), 1)
    assert_almost_equal(cube.sample_level(Vector3(0, 0, 1), 3).b, 1, atol=1e-6)
    var chained = cube_of_panorama(a_panorama(mipmapped=True))
    assert_equal(chained.levels(), 2)
    # The six faces are there for the readers that walk texels.
    assert_equal(len(cube.faces), 6)
    # A copy keeps the panorama and the mapping.
    var copy = CubeTexture(copy=cube)
    assert_true(copy.has_panorama())
    assert_equal(copy.mapping, EQUIRECTANGULAR_REFLECTION_MAPPING)


def test_a_panorama_cube_is_checked() raises:
    with assert_raises(contains="equirectangular mapping"):
        _ = cube_of_panorama(a_panorama(UV_MAPPING))
    var cube = cube_of_panorama(a_panorama())
    cube.mapping = CUBE_REFLECTION_MAPPING
    with assert_raises(contains="equirectangular"):
        cube.validate()
    var six = a_cube()
    six.mapping = EQUIRECTANGULAR_REFLECTION_MAPPING
    with assert_raises(contains="cube mapping"):
        six.validate()
    six.mapping = CUBE_REFRACTION_MAPPING
    six.validate()
    # Each axis of a face must clamp.
    six.faces[1].wrap_t = REPEAT
    with assert_raises(contains="CLAMP"):
        six.validate()
    six.faces[1].wrap_t = CLAMP
    six.faces[1].wrap_s = REPEAT
    with assert_raises(contains="CLAMP"):
        six.validate()


def test_a_pmrem_image_is_checked_axis_by_axis() raises:
    # The smallest layout: sixteen texels a tile, 336 by 64.
    var layout = float_texture(
        336,
        64,
        List[Float32](length=336 * 64 * 4, fill=0),
        CLAMP,
        BILINEAR,
        False,
        IGNORED,
    )
    validate_cube_uv(layout)
    layout.wrap_t = REPEAT
    with assert_raises(contains="CLAMP"):
        validate_cube_uv(layout)
    layout.wrap_t = CLAMP
    layout.flip_y = False
    with assert_raises(contains="flip_y"):
        validate_cube_uv(layout)


def test_a_pmrem_of_a_panorama_keeps_the_panorama() raises:
    var kept = pmrem_from_equirectangular(a_panorama())
    assert_true(kept.has_panorama())
    assert_true(kept.is_prefiltered())
    assert_almost_equal(kept.sample(Vector3(0, 0, 1)).b, 1, atol=1e-6)


# --- the material and the scene ---------------------------------------------------


def test_a_material_refuses_frames_nothing_reads() raises:
    var white = Color(255, 255, 255)
    _ = Material(white, kind=BASIC, env_map_rotation=turned_y(1))
    _ = Material(white, kind=STANDARD, env_map_rotation=turned_y(1))
    with assert_raises(contains="turns one"):
        _ = Material(white, kind=TOON, env_map_rotation=turned_y(1))
    var bad = NO_ENV_ROTATION
    bad.order = EulerOrder(0, 0, 1)
    with assert_raises(contains="order"):
        _ = Material(white, kind=BASIC, env_map_rotation=bad)
    _ = Material(white, kind=PHONG, refraction_ratio=0.5)
    with assert_raises(contains="refraction ratio"):
        _ = Material(white, kind=BASIC, refraction_ratio=-0.5)
    with assert_raises(contains="refraction ratio"):
        _ = Material(white, kind=BASIC, refraction_ratio=nan[DType.float32]())
    with assert_raises(contains="refracts"):
        _ = Material(white, kind=STANDARD, refraction_ratio=0.5)
    with assert_raises(contains="refracts"):
        _ = Material(white, kind=TOON, refraction_ratio=0.5)
    with assert_raises(contains="normal map type"):
        _ = Material(white, kind=LAMBERT, normal_map_type=NormalMapType(4))
    with assert_raises(contains="needs a normal map"):
        _ = Material(
            white, kind=LAMBERT, normal_map_type=OBJECT_SPACE_NORMAL_MAP
        )
    var mapped = Material(
        white,
        kind=LAMBERT,
        normal_map=data_texture_id(),
        normal_map_type=OBJECT_SPACE_NORMAL_MAP,
    )
    assert_equal(mapped.normal_map_type, OBJECT_SPACE_NORMAL_MAP)
    assert_equal(mapped.refraction_ratio, DEFAULT_REFRACTION_RATIO)


def data_texture_id() -> TextureId:
    """Return the first texture id, for a material that only names one."""
    return TextureId(0)


def test_a_scene_refuses_settings_it_cannot_use() raises:
    var scene = Scene()
    scene.validate_environment()
    assert_equal(scene.background_intensity, 1)
    assert_equal(scene.environment_intensity, 1)
    assert_equal(scene.background_blurriness, 0)
    for blur in [nan[DType.float32](), Float32(-0.1), Float32(1.1)]:
        scene.background_blurriness = blur
        with assert_raises(contains="blurriness"):
            scene.validate_environment()
    scene.background_blurriness = 0.5
    for shown in [nan[DType.float32](), Float32(-1)]:
        scene.background_intensity = shown
        with assert_raises(contains="background intensity"):
            scene.validate_environment()
    scene.background_intensity = 2
    for lit in [nan[DType.float32](), Float32(-1)]:
        scene.environment_intensity = lit
        with assert_raises(contains="environment intensity"):
            scene.validate_environment()
    scene.environment_intensity = 0
    scene.background_rotation.order = EulerOrder(0, 0, 1)
    with assert_raises(contains="background rotation"):
        scene.validate_environment()
    scene.background_rotation.order = XYZ
    scene.environment_rotation.order = EulerOrder(0, 0, 1)
    with assert_raises(contains="environment rotation"):
        scene.validate_environment()


# --- rendered ----------------------------------------------------------------------


def test_a_turned_env_map_reflects_the_face_it_is_turned_to() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var scene = Scene()
    a_ball(scene, assets, mirror(assets, sky))
    assert_color(draw(renderer, scene, assets, 4), CYAN)
    var turned = Scene()
    a_ball(turned, assets, mirror(assets, sky, turned_y(Float32(pi))))
    assert_color(draw(renderer, turned, assets, 4), MAGENTA)


def test_a_refraction_mapping_shows_what_is_behind() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var glass = a_cube()
    glass.mapping = CUBE_REFRACTION_MAPPING
    var sky = assets.cube_textures.add(glass^)
    var scene = Scene()
    a_ball(scene, assets, mirror(assets, sky))
    # Seen from +z, the view goes on through to the -z face.
    assert_color(draw(renderer, scene, assets, 4), MAGENTA)


def test_a_panorama_env_map_is_sampled_directly() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(cube_of_panorama(a_panorama()))
    var scene = Scene()
    a_ball(scene, assets, mirror(assets, sky))
    assert_color(draw(renderer, scene, assets, 4), BLUE)
    assert_color(draw(renderer, scene, assets, -4), RED)
    var bent = assets.cube_textures.add(
        cube_of_panorama(a_panorama(EQUIRECTANGULAR_REFRACTION_MAPPING))
    )
    var through = Scene()
    a_ball(through, assets, mirror(assets, bent))
    assert_color(draw(renderer, through, assets, 4), RED)


def a_metal(
    mut assets: Assets,
    env: CubeTextureId,
    rotation: Euler = NO_ENV_ROTATION,
) raises -> MaterialId:
    """Return a white mirror metal reflecting `env`."""
    return assets.materials.add(
        Material(
            Color(255, 255, 255),
            kind=STANDARD,
            roughness=0,
            metalness=1,
            env_map=env,
            env_map_rotation=rotation,
        )
    )


def test_a_pmrem_is_turned_dimmed_and_blurred() raises:
    # One PMREM for every reader, since building one is slow.
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(pmrem_from_cube(a_cube()))
    # A physical surface turns its own environment.
    var scene = Scene()
    a_ball(scene, assets, a_metal(assets, sky))
    var ahead = draw(renderer, scene, assets, 4)
    # Cyan: little red.
    assert_true(ahead.g > ahead.r and ahead.b > ahead.r)
    var turned = Scene()
    a_ball(turned, assets, a_metal(assets, sky, turned_y(Float32(pi))))
    var behind = draw(renderer, turned, assets, 4)
    # Magenta: little green.
    assert_true(behind.r > behind.g and behind.b > behind.g)
    # The scene turns and dims its own environment, and the material's own
    # turn is not read for it.
    var shared = Scene()
    shared.environment = sky
    a_ball(shared, assets, a_metal(assets, SCENE_ENVIRONMENT, turned_y(1)))
    ahead = draw(renderer, shared, assets, 4)
    assert_true(ahead.g > ahead.r and ahead.b > ahead.r)
    shared.environment_rotation = turned_y(Float32(pi))
    behind = draw(renderer, shared, assets, 4)
    assert_true(behind.r > behind.g and behind.b > behind.g)
    shared.environment_intensity = 0
    assert_color(draw(renderer, shared, assets, 4), Color(0, 0, 0))
    # A blurred background reads the PMREM: the neighbors blur in.
    var open = Scene()
    _ = open.add(Object3D())
    open.update()
    open.background = cube_background(sky)
    open.background_blurriness = 0.5
    var blurred = draw(renderer, open, assets, 4)
    assert_true(blurred.r > blurred.g and blurred.b > blurred.g)
    assert_true(blurred.g > 0)


def test_a_panorama_background_is_read_by_direction() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    scene.background = texture_background(assets.textures.add(a_panorama()))
    # Looking down -z from +z: the red column.
    assert_color(draw(renderer, scene, assets, 4), RED)
    scene.background_rotation = turned_y(Float32(pi))
    assert_color(draw(renderer, scene, assets, 4), BLUE)
    # Half the light: linear one half encodes to 188.
    scene.background_intensity = 0.5
    assert_color(draw(renderer, scene, assets, 4), Color(0, 0, 188))


def test_a_blurred_background_reads_at_a_roughness() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    # A panorama with a chain, read at its coarsest level: the three
    # columns averaged.
    scene.background = texture_background(
        assets.textures.add(a_panorama(mipmapped=True))
    )
    scene.background_blurriness = 1
    var gray = draw(renderer, scene, assets, 4)
    assert_equal(gray.r, gray.g)
    assert_equal(gray.g, gray.b)
    assert_true(gray.r > 100 and gray.r < 200)
    # A cube with no PMREM reads its faces' one level: sharp.
    scene.background = cube_background(assets.cube_textures.add(a_cube()))
    scene.background_blurriness = 0.5
    assert_color(draw(renderer, scene, assets, 4), MAGENTA)
    # A stretched image takes the intensity alone.
    var assets_flat = Assets()
    scene.background = texture_background(
        assets_flat.textures.add(solid(2, RED))
    )
    scene.background_intensity = 0.5
    assert_color(draw(renderer, scene, assets_flat, 4), Color(188, 0, 0))
    # And a refused setting stops the frame.
    scene.background_blurriness = 3
    with assert_raises(contains="blurriness"):
        _ = renderer.render(scene, assets_flat, camera_at(4))


def normals_facing_x(mut assets: Assets) raises -> TextureId:
    """Return a one-texel object-space normal map pointing along +x."""
    return assets.textures.add(
        data_texture(1, 1, [1.0, 0.5, 0.5], 3, alpha=IGNORED)
    )


def test_an_object_space_normal_map_turns_with_the_mesh() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var map = normals_facing_x(assets)
    var paint = assets.materials.add(
        Material(
            Color(255, 255, 255),
            kind=LAMBERT,
            normal_map=map,
            normal_map_type=OBJECT_SPACE_NORMAL_MAP,
        )
    )
    # A lamp along +x: a normal along +x is lit full, one along -x not.
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(1, 0, 0)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, Float32(pi)))
    a_ball(scene, assets, paint)
    assert_color(draw(renderer, scene, assets, 4), Color(255, 255, 255))
    # The mesh turned half round carries its +x to the world's -x.
    var turned = Scene()
    var lamp2 = Object3D()
    lamp2.set_position(1, 0, 0)
    var node2 = turned.add(lamp2^)
    turned.add_light(
        directional_light(Color(255, 255, 255), node2, Float32(pi))
    )
    a_ball(turned, assets, paint, Float32(pi))
    assert_color(draw(renderer, turned, assets, 4), Color(0, 0, 0))
    # Seen from inside, a back face's normal is turned round as well.
    var inside = assets.materials.add(
        Material(
            Color(255, 255, 255),
            kind=LAMBERT,
            side=BACK_SIDE,
            normal_map=map,
            normal_map_type=OBJECT_SPACE_NORMAL_MAP,
        )
    )
    var backs = Scene()
    var lamp3 = Object3D()
    lamp3.set_position(1, 0, 0)
    var node3 = backs.add(lamp3^)
    backs.add_light(directional_light(Color(255, 255, 255), node3, Float32(pi)))
    a_ball(backs, assets, inside)
    assert_color(draw(renderer, backs, assets, 4), Color(0, 0, 0))


# --- the PMREMs a scene needs -----------------------------------------------------


def test_prefiltering_builds_what_a_physical_reader_needs() raises:
    var empty = Assets()
    assert_equal(prefilter_environments(Scene(), empty), 0)
    var assets = Assets()
    # One cube a metal names and the scene's environment is, so the second
    # reader finds it built; and one a basic mirror names and the sky is.
    var own = assets.cube_textures.add(a_cube())
    var basic = assets.cube_textures.add(a_cube())
    _ = a_metal(assets, own)
    _ = a_metal(assets, SCENE_ENVIRONMENT)
    _ = a_metal(assets, NO_CUBE_TEXTURE)
    _ = mirror(assets, basic)
    var scene = Scene()
    scene.environment = own
    scene.background = cube_background(basic)
    # No blur: the sky is read by its faces.
    assert_equal(prefilter_environments(scene, assets), 1)
    assert_true(assets.cube_textures.get(own).is_prefiltered())
    assert_false(assets.cube_textures.get(basic).is_prefiltered())
    scene.background_blurriness = 0.25
    assert_equal(prefilter_environments(scene, assets), 1)
    assert_true(assets.cube_textures.get(basic).is_prefiltered())
    assert_equal(prefilter_environments(scene, assets), 0)
    # A blurred picture has no PMREM to build, and no environment.
    scene.background = texture_background(assets.textures.add(solid(2, RED)))
    scene.environment = NO_CUBE_TEXTURE
    assert_equal(prefilter_environments(scene, assets), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
