# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.sky`, `objects.lensflare`, `objects.grounded_skybox`
and `objects.shadow_mesh`.

The skybox's vertices and the shadow's matrices come from three.js 0.180
run under Node: `assets/scene_objects/reference.mjs` writes them to
`reference.json`. The sky's colors are three.js's shader worked out again
here in doubles.
"""

from cameras.camera import unproject_point
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import box
from geometries.plane import plane
from loaders.json import JsonDocument, parse_json
from materials.material import BACK_SIDE, BASIC, Material
from math.bounds import Plane
from math.vector3 import Vector3
from math.vector4 import Vector4
from objects.grounded_skybox import GroundedSkybox, grounded_skybox
from objects.lensflare import Lensflare, LensflareElement, lensflare_geometry
from objects.mesh import Mesh
from objects.shadow_mesh import ShadowMesh, shadow_matrix, without_normals
from objects.sky import Sky
from render.framebuffer import Color, FloatColor
from render.raster_state import REVERSED_DEPTH
from render.rect import Rect
from render.target import RenderTarget
from render.texture import data_texture
from render.texture_store import TextureId
from renderers.renderer import Renderer
from std.math import acos, cos, exp, inf, nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


def meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


def reference() raises -> JsonDocument:
    """Return three.js's answers."""
    return parse_json(
        String(
            StringSlice(
                unsafe_from_utf8=open(
                    "assets/scene_objects/reference.json", "r"
                ).read_bytes()
            )
        )
    )


def camera_from(
    eye: Vector3, target: Vector3, fov: Float32 = 30
) raises -> PerspectiveCamera:
    """Return a square camera at `eye` looking at `target`."""
    var camera = PerspectiveCamera(
        Angle(fov, DEGREE), 1.0, meters(0.1), meters(100)
    )
    camera.place(eye, target)
    return camera^


# --- sky ------------------------------------------------------------------------


comptime Triple = SIMD[DType.float64, 4]


def _dot(a: Triple, b: Triple) -> Float64:
    """Return the dot product of the first three lanes."""
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _pow(base: Triple, power: Float64) -> Triple:
    """Return each lane raised to a power."""
    return Triple(base[0] ** power, base[1] ** power, base[2] ** power, 0)


def _exp(value: Triple) -> Triple:
    """Return e to each lane."""
    return Triple(exp(value[0]), exp(value[1]), exp(value[2]), 0)


def sky_color(direction: Triple, sun: Triple) -> Triple:
    """Return three.js's `SkyShader` color, in doubles, at its default
    uniforms."""
    var up = Triple(0, 1, 0, 0)
    var total_rayleigh = Triple(
        5.804542996261093e-6, 1.3562911419845635e-5, 3.0265902468824876e-5, 0
    )
    var mie_const = Triple(
        1.8399918514433978e14, 2.7798023919660528e14, 4.0790479543861094e14, 0
    )
    var sun_direction = sun / sqrt(_dot(sun, sun))
    var zenith_cos = min(max(_dot(sun_direction, up), -1.0), 1.0)
    var sun_e = 1000.0 * max(
        0.0,
        1.0
        - 2.718281828459045 ** -((1.6110731556870734 - acos(zenith_cos)) / 1.5),
    )
    var sunfade = 1.0 - min(max(1.0 - exp(sun[1] / 450000.0), 0.0), 1.0)
    var beta_r = total_rayleigh * (1.0 - (1.0 - sunfade))
    var beta_m = 0.434 * ((0.2 * 2.0) * 10e-18) * mie_const * 0.005
    var zenith = acos(max(0.0, _dot(up, direction)))
    var inverse = 1.0 / (
        cos(zenith) + 0.15 * (93.885 - ((zenith * 180.0) / pi)) ** -1.253
    )
    var fex = _exp(-(beta_r * (8.4e3 * inverse) + beta_m * (1.25e3 * inverse)))
    var cos_theta = _dot(direction, sun_direction)
    var r_phase = 0.05968310365946075 * (1.0 + (cos_theta * 0.5 + 0.5) ** 2)
    var g = 0.8
    var g2 = g * g
    var m_phase = 0.07957747154594767 * (
        (1.0 - g2) / (1.0 - 2.0 * g * cos_theta + g2) ** 1.5
    )
    var ratio = (beta_r * r_phase + beta_m * m_phase) / (beta_r + beta_m)
    var lin = _pow(sun_e * ratio * (1.0 - fex), 1.5)
    var t = min(max((1.0 - _dot(up, sun_direction)) ** 5, 0.0), 1.0)
    lin *= 1.0 + (_pow(sun_e * ratio * fex, 0.5) - 1.0) * t
    var l0 = 0.1 * fex
    var edge = 0.9999566769464484
    var s = min(max((cos_theta - edge) / 0.00002, 0.0), 1.0)
    l0 += (sun_e * 19000.0 * fex) * (s * s * (3.0 - 2.0 * s))
    var tex = (lin + l0) * 0.04 + Triple(0.0, 0.0003, 0.00075, 0)
    return _pow(tex, 1.0 / (1.2 + 1.2 * sunfade))


def sky_scene(mut assets: Assets, mut scene: Scene, sun: Vector3) raises -> Sky:
    """Return a sky ten meters across with the sun at `sun`."""
    var held = Object3D()
    held.set_scale(10, 10, 10)
    var sky = Sky(assets, scene.add(held^))
    scene.add_mesh(sky.mesh)
    scene.update()
    assets.programs.get(sky.program).set_uniform("sunPosition", sun)
    return sky


def test_a_sky_starts_at_three_js_uniforms() raises:
    var assets = Assets()
    var scene = Scene()
    var sky = Sky(assets, scene.add(Object3D()))
    ref program = assets.programs.get(sky.program)
    assert_equal(program.uniform("turbidity")[0], 2)
    assert_equal(program.uniform("rayleigh")[0], 1)
    assert_almost_equal(program.uniform("mieCoefficient")[0], 0.005)
    assert_almost_equal(program.uniform("mieDirectionalG")[0], 0.8)
    assert_equal(program.uniform("up")[1], 1)
    var material = assets.materials.get(sky.mesh.material)
    assert_true(material.side == BACK_SIDE)
    assert_false(material.depth_write)
    var bounds = assets.geometries.get(sky.mesh.geometry).bounding_box()
    assert_almost_equal(bounds.max.x, 0.5)


def test_a_sky_paints_three_js_colors() raises:
    var assets = Assets()
    var scene = Scene()
    var sun = Vector3(-0.3, 0.2, -0.8)
    _ = sky_scene(assets, scene, sun)
    var renderer = Renderer(16, 16)
    for view in range(3):
        var target = Vector3(0.8, 0.35, 0.3)
        if view == 1:
            target = Vector3(0, 0.9, 0.4)
        elif view == 2:
            target = Vector3(-0.6, 0.05, 0.1)
        var camera = camera_from(Vector3(0, 0, 0), target)
        var image = renderer.render(scene, assets, camera)
        for pixel in range(3):
            var x = 3 + pixel * 5
            var y = 12 - pixel * 4
            var far = unproject_point(
                Vector3(
                    (Float32(x) + 0.5) / 8 - 1, 1 - (Float32(y) + 0.5) / 8, 0.5
                ),
                camera,
                scene,
            )
            var way = Triple(Float64(far.x), Float64(far.y), Float64(far.z), 0)
            var color = sky_color(
                way / sqrt(_dot(way, way)),
                Triple(Float64(sun.x), Float64(sun.y), Float64(sun.z), 0),
            )
            var want = FloatColor(
                Float32(color[0]), Float32(color[1]), Float32(color[2]), 1
            ).encode()
            var got = image.get_pixel(x, y)
            assert_true(abs(Int(got.r) - Int(want.r)) <= 2)
            assert_true(abs(Int(got.g) - Int(want.g)) <= 2)
            assert_true(abs(Int(got.b) - Int(want.b)) <= 2)


def test_the_sun_is_a_bright_disc() raises:
    var assets = Assets()
    var scene = Scene()
    var sun = Vector3(0, 0.3, -1)
    _ = sky_scene(assets, scene, sun)
    var renderer = Renderer(16, 16)
    var image = renderer.render(
        scene, assets, camera_from(Vector3(0, 0, 0), sun, fov=1)
    )
    var middle = image.get_pixel(8, 8)
    assert_equal(Int(middle.r), 255)


# --- lens flare -----------------------------------------------------------------

comptime FLARE = 48


def white(mut assets: Assets) raises -> TextureId:
    """Add a small opaque white texture."""
    var data = List[Float32](length=4 * 4 * 4, fill=1)
    return assets.textures.add(data_texture(4, 4, data))


def flare_scene(
    mut assets: Assets, mut scene: Scene, light: Vector3
) raises -> Lensflare:
    """Return a flare at `light` with one element on the light and one
    opposite it."""
    var held = Object3D()
    held.set_position(light.x, light.y, light.z)
    var flare = Lensflare(assets, scene.add(held^))
    var map = white(assets)
    flare.add_element(assets, LensflareElement(map, 12, 0))
    flare.add_element(assets, LensflareElement(map, 8, 1, Color(255, 255, 255)))
    scene.update()
    return flare^


def draw_flare(
    flare: Lensflare,
    renderer: Renderer,
    scene: Scene,
    mut assets: Assets,
    mut target: RenderTarget,
) raises -> Bool:
    """Draw the scene and the flare into a target."""
    var camera = camera_from(Vector3(0, 0, 0), Vector3(0, 0, -1), 60)
    renderer.render_into(target, scene, assets, camera)
    return flare.render(renderer, target, scene, assets, camera)


def test_an_open_flare_adds_its_elements() raises:
    var assets = Assets()
    var scene = Scene()
    var flare = flare_scene(assets, scene, Vector3(1, 0, -5))
    var renderer = Renderer(FLARE, FLARE)
    renderer.background = Color(0, 0, 0)
    var target = RenderTarget(FLARE, FLARE, Color(0, 0, 0))
    assert_true(draw_flare(flare, renderer, scene, assets, target))
    ref program = assets.programs.get(flare.programs[0])
    assert_equal(program.uniform("visibility")[0], 1)
    var image = target.resolve()
    # The light lands right of the middle, and the second element as far
    # left of it. Between them, nothing.
    var light_x = Int(Float64(FLARE) / 2 * (1 + (1.0 / 5.0) / 0.57735))
    assert_true(image.get_pixel(light_x, FLARE // 2).r > 200)
    assert_true(image.get_pixel(FLARE - 1 - light_x, FLARE // 2).r > 200)
    assert_equal(Int(image.get_pixel(FLARE // 2, 4).r), 0)
    assert_equal(len(flare.elements), 2)
    assert_equal(
        assets.geometries.get(flare.geometry).vertex_count(),
        lensflare_geometry().vertex_count(),
    )


def test_a_flare_with_no_elements_draws_nothing_over_the_scene() raises:
    var assets = Assets()
    var scene = Scene()
    var held = Object3D()
    held.set_position(0, 0, -5)
    var flare = Lensflare(assets, scene.add(held^))
    scene.update()
    var renderer = Renderer(FLARE, FLARE)
    renderer.background = Color(0, 0, 0)
    var target = RenderTarget(FLARE, FLARE, Color(0, 0, 0))
    assert_true(draw_flare(flare, renderer, scene, assets, target))
    assert_equal(Int(target.resolve().get_pixel(FLARE // 2, FLARE // 2).r), 0)


def test_what_hides_the_light_hides_the_flare() raises:
    var assets = Assets()
    var scene = Scene()
    var flare = flare_scene(assets, scene, Vector3(0, 0, -5))
    var wall = Object3D()
    wall.set_position(0, 0, -2)
    var node = scene.add(wall^)
    var material = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    scene.add_mesh(
        Mesh(assets.geometries.add(plane(meters(4), meters(4))), material, node)
    )
    scene.update()
    var renderer = Renderer(FLARE, FLARE)
    var target = RenderTarget(FLARE, FLARE, Color(0, 0, 0))
    assert_true(draw_flare(flare, renderer, scene, assets, target))
    # The red wall fails the depth test at all nine pixels, and red has no
    # blue: the visibility is zero.
    assert_equal(
        assets.programs.get(flare.programs[0]).uniform("visibility")[0], 0
    )
    # A magenta wall hides the light too, but its color is what three.js's
    # probe square draws, so the flare shows through, as in three.js.
    var magenta = Material(Color(255, 0, 255), kind=BASIC)
    assets.materials.materials[material.value] = magenta
    assert_true(draw_flare(flare, renderer, scene, assets, target))
    assert_almost_equal(
        assets.programs.get(flare.programs[0]).uniform("visibility")[0], 1
    )


def test_a_flare_behind_the_camera_or_at_the_edge_draws_nothing() raises:
    var assets = Assets()
    var scene = Scene()
    var renderer = Renderer(FLARE, FLARE)
    var target = RenderTarget(FLARE, FLARE, Color(0, 0, 0))
    var behind = flare_scene(assets, scene, Vector3(0, 0, 5))
    assert_false(draw_flare(behind, renderer, scene, assets, target))
    for index in range(4):
        var light = Vector3(-5, 0, -5)
        if index == 1:
            light = Vector3(5, 0, -5)
        elif index == 2:
            light = Vector3(0, -5, -5)
        elif index == 3:
            light = Vector3(0, 5, -5)
        var edge = flare_scene(assets, scene, light)
        assert_false(draw_flare(edge, renderer, scene, assets, target))


def test_a_viewport_off_the_target_reads_black() raises:
    var assets = Assets()
    var scene = Scene()
    var flare = flare_scene(assets, scene, Vector3(0, 0, -5))
    var renderer = Renderer(FLARE, FLARE)
    renderer.set_viewport(Rect(-FLARE + 12, 0, FLARE * 2 - 24, FLARE))
    var target = RenderTarget(FLARE, FLARE, Color(0, 0, 0))
    # The light is in the middle of the viewport, which is left of the
    # middle of the target: some of the nine pixels are off the target.
    var corner_x = -FLARE + 12 + (FLARE * 2 - 24) // 2 - 8
    var seen = flare.visibility(renderer, target, assets, corner_x, 16, 0.5)
    assert_almost_equal(seen, Float32(6.0 / 9.0 * (6.0 / 9.0)), atol=1e-6)
    var inside = flare.visibility(renderer, target, assets, 10, 10, 0.5)
    assert_equal(inside, 1)


def test_a_flare_refuses_what_it_cannot_draw() raises:
    var assets = Assets()
    var scene = Scene()
    var flare = flare_scene(assets, scene, Vector3(0, 0, -5))
    var renderer = Renderer(FLARE, FLARE)
    renderer.depth_mode = REVERSED_DEPTH
    var target = RenderTarget(FLARE, FLARE, Color(0, 0, 0))
    with assert_raises(contains="standard depth"):
        _ = draw_flare(flare, renderer, scene, assets, target)
    with assert_raises(contains="finite"):
        _ = LensflareElement(TextureId(0), nan[DType.float32]())
    with assert_raises(contains="finite"):
        _ = LensflareElement(TextureId(0), 1, inf[DType.float32]())
    with assert_raises():
        flare.add_element(assets, LensflareElement(TextureId(99)))


# --- grounded skybox --------------------------------------------------------------


def test_a_grounded_skybox_matches_three_js() raises:
    var doc = reference()
    var want = doc.get(doc.root(), "skybox")
    var geometry = grounded_skybox(meters(2), meters(10), 4)
    ref positions = geometry.attribute_view(String(POSITION))
    ref normals = geometry.attribute_view(String(NORMAL))
    var position = doc.get(want, "position")
    var normal = doc.get(want, "normal")
    assert_equal(positions.count() * 3, doc.length(position))
    for vertex in range(positions.count()):
        for k in range(3):
            assert_almost_equal(
                Float64(positions.component(vertex, k)),
                doc.number(doc.at(position, vertex * 3 + k)),
                atol=5e-5,
            )
            assert_almost_equal(
                Float64(normals.component(vertex, k)),
                doc.number(doc.at(normal, vertex * 3 + k)),
                atol=1e-6,
            )
    var index = doc.get(want, "index")
    assert_equal(len(geometry.index), doc.length(index))
    for i in range(len(geometry.index)):
        assert_equal(geometry.index[i], doc.integer(doc.at(index, i)))


def test_a_grounded_skybox_stands_on_its_floor() raises:
    var geometry = grounded_skybox(meters(1.5), meters(20), 8)
    var bounds = geometry.bounding_box()
    assert_almost_equal(bounds.min.y, -1.5, atol=1e-5)
    assert_almost_equal(bounds.max.y, 20, atol=1e-4)
    var assets = Assets()
    var scene = Scene()
    var map = white(assets)
    var skybox = GroundedSkybox(
        assets, map, meters(1.5), meters(20), scene.add(Object3D()), 8
    )
    var material = assets.materials.get(skybox.mesh.material)
    assert_true(material.map == map)
    assert_false(material.depth_write)
    assert_equal(
        assets.geometries.get(skybox.mesh.geometry).vertex_count(),
        geometry.vertex_count(),
    )


def test_a_grounded_skybox_refuses_what_it_cannot_build() raises:
    with assert_raises(contains="positive"):
        _ = grounded_skybox(meters(0), meters(10))
    with assert_raises(contains="positive"):
        _ = grounded_skybox(meters(1), meters(-1))
    with assert_raises(contains="finite"):
        _ = grounded_skybox(meters(inf[DType.float32]()), meters(10))
    with assert_raises(contains="finite"):
        _ = grounded_skybox(meters(1), meters(nan[DType.float32]()))
    with assert_raises(contains="two rings"):
        _ = grounded_skybox(meters(1), meters(10), 1)
    var assets = Assets()
    var scene = Scene()
    with assert_raises():
        _ = GroundedSkybox(
            assets, TextureId(5), meters(1), meters(10), scene.add(Object3D())
        )


# --- shadow mesh ----------------------------------------------------------------


def test_a_shadow_matrix_matches_three_js() raises:
    var doc = reference()
    var assets = Assets()
    var scene = Scene()
    var held = Object3D()
    held.set_position(0.5, 2, -0.25)
    held.set_euler(
        Angle(Float32(0.3 * 180 / pi), DEGREE),
        Angle(Float32(0.6 * 180 / pi), DEGREE),
        Angle(Float32(0.1 * 180 / pi), DEGREE),
    )
    var node = scene.add(held^)
    var caster = Mesh(
        assets.geometries.add(box(meters(1), meters(1), meters(1))),
        assets.materials.add(Material(Color(255, 255, 255))),
        node,
    )
    scene.add_mesh(caster)
    var shadow = ShadowMesh(assets, scene, caster)
    scene.update()
    var ground = Plane(Vector3(0, 1, 0), 0.01)
    var cases: List[String] = ["shadow_point", "shadow_direction"]
    var lights: List[Vector4] = [
        Vector4(2, 5, 1, 1),
        Vector4(0.3, 1, 0.2, 0),
    ]
    for index in range(2):
        shadow.update(scene, ground, lights[index])
        scene.update()
        var got = scene.world_matrix(shadow.mesh.node)
        var want = doc.get(doc.root(), cases[index])
        for k in range(16):
            assert_almost_equal(
                Float64(got.elements[k]),
                doc.number(doc.at(want, k)),
                atol=2e-5,
            )
    # Every point lands where the normal times the point is the constant:
    # three.js negates the constant of a `Plane`, so the shadow of a plane
    # at y = -0.01 lies at y = 0.01.
    var flat = shadow_matrix(ground, Vector4(2, 5, 1, 1))
    var landed = flat.transform_point(Vector3(0.3, 1.7, -0.4))
    assert_almost_equal(landed.y, 0.01, atol=1e-6)
    assert_false(shadow.mesh.frustum_culled)
    assert_false(scene.get(shadow.mesh.node).matrix_auto_update)


def test_a_shadow_draws_its_casters_shape_without_normals() raises:
    var solid = box(meters(1), meters(1), meters(1))
    var bare = without_normals(solid)
    assert_false(bare.has_attribute(String(NORMAL)))
    assert_true(bare.has_attribute(String(UV)))
    assert_equal(bare.vertex_count(), solid.vertex_count())
    assert_equal(without_normals(bare).attribute_count(), 2)
    assert_equal(without_normals(BufferGeometry()).attribute_count(), 0)
    var assets = Assets()
    var scene = Scene()
    var caster = Mesh(
        assets.geometries.add(solid^),
        assets.materials.add(Material(Color(255, 255, 255))),
        scene.add(Object3D()),
    )
    var shadow = ShadowMesh(assets, scene, caster)
    assert_false(
        assets.geometries.get(shadow.mesh.geometry).has_attribute(
            String(NORMAL)
        )
    )
    caster.geometry = GeometryId(40)
    with assert_raises():
        _ = ShadowMesh(assets, scene, caster)


def test_a_shadow_darkens_the_ground_once() raises:
    var assets = Assets()
    var scene = Scene()
    var floor = Object3D()
    floor.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    scene.add_mesh(
        Mesh(
            assets.geometries.add(plane(meters(8), meters(8))),
            assets.materials.add(Material(Color(128, 128, 128), kind=BASIC)),
            scene.add(floor^),
        )
    )
    var held = Object3D()
    held.set_position(0, 1, 0)
    var caster = Mesh(
        assets.geometries.add(box(meters(1), meters(1), meters(1))),
        assets.materials.add(Material(Color(255, 0, 0), kind=BASIC)),
        scene.add(held^),
    )
    scene.add_mesh(caster)
    var shadow = ShadowMesh(assets, scene, caster)
    scene.add_mesh(shadow.mesh)
    scene.update()
    shadow.update(scene, Plane(Vector3(0, 1, 0), 0.01), Vector4(1.5, 6, 0, 1))
    scene.update()
    var renderer = Renderer(32, 32)
    var image = renderer.render(
        scene, assets, camera_from(Vector3(0, 5, 0.01), Vector3(0, 0, 0), 60)
    )
    # The ground far from the box, and the shadow beside the box: black
    # at 0.6 over gray, once, though the box's faces overlap there.
    var lit = FloatColor(srgb=Color(128, 128, 128))
    var once = FloatColor(lit.r * 0.4, lit.g * 0.4, lit.b * 0.4, 1).encode()
    assert_equal(Int(image.get_pixel(2, 2).r), 128)
    var dark = 0
    for x in range(32):
        var c = image.get_pixel(x, 16)
        if c.g == c.r and abs(Int(c.r) - Int(once.r)) <= 1:
            dark += 1
    assert_true(dark >= 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
