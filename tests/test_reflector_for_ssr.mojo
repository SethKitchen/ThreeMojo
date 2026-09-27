# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""three.js's `ReflectorForSSRPass`: a ground mirror that fades its
reflection by height and by a fresnel factor, and the SSR pass that lays no
reflection of its own over it."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.layers import Layers
from core.scene import Scene
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.reflector_for_ssr import ReflectorForSSR, fresnel_coefficient
from postprocessing.composer import EffectComposer, ssr_pass
from render.framebuffer import Framebuffer
from render.texture_store import NO_TEXTURE
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from test_reflector import (
    SIZE,
    count_red,
    floor_node,
    high_camera,
    meters,
    red_box,
    square,
)
from units.si import Angle, DEGREE


def test_the_fresnel_factor_is_one_from_the_side() raises:
    assert_equal(fresnel_coefficient(Vector3(0, 0, 0)), 1)
    assert_equal(fresnel_coefficient(Vector3(3, 0, 0)), 1)
    assert_equal(fresnel_coefficient(Vector3(0, 2, 0)), 0)
    assert_almost_equal(fresnel_coefficient(Vector3(0, 1, 1)), 0.5)


def a_ground(
    mut assets: Assets, mut scene: Scene, depth: Bool
) raises -> ReflectorForSSR:
    """Return a ground mirror under a red box, on layer three."""
    _ = red_box(assets, scene, Vector3(0, 1, 0))
    var node = floor_node(scene)
    var mirror = ReflectorForSSR(
        assets,
        square(assets, 6),
        node,
        use_depth_texture=depth,
        resolution=Vector2(SIZE, SIZE),
    )
    var layers = Layers(UInt32(1 << 3))
    scene.get(node).layers = layers
    scene.add_mesh(mirror.mesh.copy())
    scene.update()
    return mirror^


def drawn(
    mut mirror: ReflectorForSSR, mut scene: Scene, mut assets: Assets
) raises -> Framebuffer:
    """Return the scene drawn through a camera that sees every layer."""
    var renderer = Renderer(SIZE, SIZE)
    var camera = high_camera()
    camera.layers = Layers(UInt32(0xFFFFFFFF))
    assert_true(mirror.update(renderer, scene, assets, camera))
    return renderer.render(scene, assets, camera)


def test_without_depth_the_mirror_overlays_as_a_reflector_does() raises:
    var assets = Assets()
    var scene = Scene()
    var mirror = a_ground(assets, scene, False)
    assert_true(mirror.depth == NO_TEXTURE)
    var image = drawn(mirror, scene, assets)
    # The box and its reflection.
    assert_true(count_red(image) > 40)
    assert_false(assets.materials.get(mirror.mesh.material).transparent)


def test_with_depth_the_reflection_fades_by_height() raises:
    var assets = Assets()
    var scene = Scene()
    var opaque = a_ground(assets, scene, False)
    var sharp = count_red(drawn(opaque, scene, assets))
    var faded_assets = Assets()
    var faded_scene = Scene()
    var mirror = a_ground(faded_assets, faded_scene, True)
    assert_true(mirror.depth != NO_TEXTURE)
    assert_true(
        faded_assets.materials.get(mirror.mesh.material).transparent
    )
    var faded = count_red(drawn(mirror, faded_scene, faded_assets))
    # The reflection blends, so fewer of its pixels are strongly red.
    assert_true(faded < sharp)
    # Past the distance, nothing of the box is reflected.
    mirror.max_distance = meters(0.2)
    var cut = count_red(drawn(mirror, faded_scene, faded_assets))
    assert_true(cut <= faded)
    mirror.opacity = Float32(0) / Float32(0)
    with assert_raises(contains="distance and opacity are finite"):
        _ = drawn(mirror, faded_scene, faded_assets)


def test_a_camera_below_the_ground_renders_nothing() raises:
    var assets = Assets()
    var scene = Scene()
    var mirror = a_ground(assets, scene, True)
    var below = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, meters(0.1), meters(100)
    )
    below.place(Vector3(0, -2, 4), Vector3(0, 0, 0))
    assert_false(mirror.update(Renderer(SIZE, SIZE), scene, assets, below))


def test_the_ssr_pass_leaves_the_ground_to_its_mirror() raises:
    var assets = Assets()
    var scene = Scene()
    var mirror = a_ground(assets, scene, True)
    var renderer = Renderer(SIZE, SIZE)
    var camera = high_camera()
    camera.layers = Layers(UInt32(0xFFFFFFFF))
    _ = mirror.update(renderer, scene, assets, camera)
    var composer = EffectComposer()
    var step = ssr_pass(1, meters(5), meters(0.2))
    step.ssr.ground = Layers(UInt32(1 << 3))
    composer.add_pass(step^)
    var frame = composer.render(renderer, scene, assets, camera)
    assert_equal(frame.width, SIZE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
