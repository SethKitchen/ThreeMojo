# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The castle as a scene that can be drawn at any hour.

A scene is the building, the ground, the woods and a sun that can be moved. The
look is physically based. The sky lights the scene through a prefiltered
environment, and the sun casts soft shadows. A picture is made in four steps.

1. The renderer draws the scene.
2. The sky and its cumulus are painted where the renderer drew only the clear
   ground (`paint_sky`).
3. The water of the moat is Clearwater's, drawn into the picture where it is
   nearest (`WaterScene.compose`).
4. The castle and the wood are reflected in the water, in the share that
   Fresnel's law gives (`reflect_in_water`).

`aim_sun` moves the sun, and prefilters the sky again for its light.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.fog import exp2_fog
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.castle.forest import (
    Clearing,
    ForestSettings,
    plant_forest,
)
from extensions.castle.kinds import LAWN, WATER
from extensions.castle.landscape import Landscape
from extensions.castle.landscape_mesh import add_ground
from extensions.castle.look import CastleLook, castle_look
from extensions.castle.plan import CastlePlan
from extensions.castle.reflect import reflect_in_water
from extensions.castle.parts import Kit, MaterialMesh
from extensions.castle.render import (
    build_structures,
    castle_meshes,
    default_view,
)
from extensions.castle.sky import paint_sky, sky_color
from extensions.scan.composite import SplatLayer, composite_splats
from extensions.castle.trees import plant_bushes, plant_trees
from extensions.water.frame import WaterScene
from extensions.water.pebbles import PebbleBed, pebble_bed
from extensions.water.resolution import SpectrumResolution
from lights.light import directional_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.sky import Sky
from render.framebuffer import Color, Framebuffer
from render.jpeg import decode
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.environment import pmrem_from_scene
from renderers.renderer import Renderer, available_workers
from std.math import asin
from std.pathlib import Path
from units.si import (
    Duration,
    InverseLength,
    Length,
    Length64,
    METER,
    PER_METER,
    SECOND,
)

# The clear color behind the scene. It is the horizon sky, which the sky
# painter replaces.
comptime _GROUND_COLOR = Color(150, 186, 226)
# The distance of the sun lamp from the middle of the castle, in meters.
comptime _SUN_DISTANCE = 160.0


@fieldwise_init
struct SceneSettings(ImplicitlyCopyable):
    """The choices of a scene that trade quality for time."""

    # The number of texels along a side of each tile of material.
    var texture_size: Int
    # The number of texels along a side of each face of the sky's cube.
    var environment_size: Int
    # The number of texels along a side of the shadow map of the sun.
    var shadow_size: Int
    # Whether the woods are grown. A test leaves them out.
    var woods: Bool
    # The path of the pebble photograph that Clearwater lays under the water.
    var pebbles: String
    # The spacing of the grid of the ground, in meters.
    var terrain_step: Length64


def _smooth(x: Float64) -> Float64:
    """Return the smooth step of a number clamped to 0 through 1."""
    var t = min(max(x, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def default_settings() -> SceneSettings:
    """Return the settings of a picture made to be looked at.

    Returns:
        512 texel tiles, a 128 texel sky, a 4096 texel shadow map, woods, and
        a ground grid of 1 m cells.
    """
    return SceneSettings(
        512, 128, 4096, True, String("assets/pebbles.jpg"), Length64(1.0, METER)
    )


def castle_renderer(
    width: Int, height: Int, tone_exposure: Float32 = 0.55
) raises -> Renderer:
    """Return a renderer set up for the castle.

    It supersamples, filters the shadows softly, and applies the ACES filmic
    tone curve.

    Args:
        width: The width of the picture, in pixels.
        height: The height of the picture, in pixels.
        tone_exposure: The exposure of the tone curve.

    Returns:
        The renderer.

    Raises:
        Error: If the size is not valid.
    """
    var renderer = Renderer(width, height, workers=available_workers())
    renderer.set_background(_GROUND_COLOR)
    renderer.set_antialias(True)
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP
    renderer.set_tone_mapping(ACES_FILMIC_TONE_MAPPING, tone_exposure)
    return renderer^


struct CastleScene(Movable):
    """The castle and what it needs to be drawn: the scene, its stores, the
    sky that lights it, the water and the sun."""

    var scene: Scene
    var assets: Assets
    # A scene of the sky alone, which is drawn into the cube that lights the
    # castle, and the sky that is in it.
    var heaven: Scene
    var heaven_sky: Sky
    var water: WaterScene
    var bed: PebbleBed
    # The height of the water in the frame of the scene: y up, with the ground
    # of the island at zero.
    var level: Float32
    # A node that stands for the sky dome, which the reflection leaves out.
    var dome: NodeId
    # The node of the sun lamp, and the point it looks at.
    var lamp: NodeId
    var middle: NodeId
    # The direction toward the sun, a unit vector with y up and z south.
    var sun: Vector3
    # The environment size that `aim_sun` uses.
    var environment_size: Int
    # The number of trees and of shrubs planted.
    var trees: Int
    var shrubs: Int
    # The scans of buildings that stand in the scene as Gaussian
    # splats, which are blended into each picture.
    var layers: List[SplatLayer]

    def __init__(
        out self,
        var scene: Scene,
        var assets: Assets,
        var heaven: Scene,
        heaven_sky: Sky,
        var water: WaterScene,
        var bed: PebbleBed,
        level: Float32,
        dome: NodeId,
        lamp: NodeId,
        middle: NodeId,
        environment_size: Int,
        trees: Int,
        shrubs: Int,
    ):
        self.scene = scene^
        self.assets = assets^
        self.heaven = heaven^
        self.heaven_sky = heaven_sky
        self.water = water^
        self.bed = bed^
        self.level = level
        self.dome = dome
        self.lamp = lamp
        self.middle = middle
        self.sun = Vector3(0, 1, 0)
        self.environment_size = environment_size
        self.trees = trees
        self.shrubs = shrubs
        self.layers = List[SplatLayer]()


def _add_sky(mut assets: Assets, mut scene: Scene, sun: Vector3) raises -> Sky:
    """Add a daylight sky dome to a scene."""
    var dome = Object3D()
    dome.set_scale(3000, 3000, 3000)
    var sky = Sky(assets, scene.add(dome^))
    ref program = assets.programs.get(sky.program)
    program.set_uniform("turbidity", Float32(4.0))
    program.set_uniform("rayleigh", Float32(2.6))
    program.set_uniform("mieCoefficient", Float32(0.004))
    program.set_uniform("mieDirectionalG", Float32(0.7))
    program.set_uniform("sunPosition", sun)
    scene.add_mesh(sky.mesh)
    return sky


def _add_meshes(
    mut scene: Scene,
    mut assets: Assets,
    look: CastleLook,
    upright: NodeId,
    meshes: List[MaterialMesh],
) raises:
    """Add the geometry of each material to a scene, but not the water, which
    Clearwater draws."""
    for at in range(len(meshes)):
        ref mesh = meshes[at]
        if mesh.material == WATER:
            continue
        scene.add_mesh(
            Mesh(
                assets.geometries.add(mesh.geometry.clone()),
                look.material(mesh.material),
                upright,
                cast_shadow=mesh.material != LAWN,
                receive_shadow=True,
            )
        )


def _finish(
    var scene: Scene,
    var assets: Assets,
    var heaven: Scene,
    heaven_sky: Sky,
    dome: NodeId,
    plan: CastlePlan,
    settings: SceneSettings,
    trees: Int,
    shrubs: Int,
) raises -> CastleScene:
    """Add the sun lamp and the water to a scene, and wrap it."""
    var middle = Object3D()
    middle.set_position(30, 4, -44)
    var middle_node = scene.add(middle^)
    var lamp_node = scene.add(Object3D())
    var lamp = directional_light(
        Color(255, 244, 224), lamp_node, 3.2, middle_node
    )
    lamp.cast_shadow = True
    lamp.shadow.map_size = settings.shadow_size
    lamp.shadow.bias = -0.0004
    lamp.shadow.normal_bias = 0.04
    lamp.shadow.set_extent(Length(90.0, METER))
    lamp.shadow.near = Length(20.0, METER)
    lamp.shadow.far = Length(360.0, METER)
    scene.add_light(lamp)
    var water = WaterScene(
        SpectrumResolution(256),
        64,
        256,
        SpectrumResolution(128),
        Duration(0.0, SECOND),
    )
    var bed = pebble_bed(decode(Path(settings.pebbles).read_bytes()))
    return CastleScene(
        scene^,
        assets^,
        heaven^,
        heaven_sky,
        water^,
        bed^,
        Float32(plan.moat.water_level.value - plan.island_level.value),
        dome,
        lamp_node,
        middle_node,
        settings.environment_size,
        trees,
        shrubs,
    )


def build_castle_scene(
    plan: CastlePlan,
    settings: SceneSettings,
    keep_x: Float64,
    keep_y: Float64,
    keep_radius: Float64,
) raises -> CastleScene:
    """Build the scene of a castle plan.

    The sun starts overhead. Call `aim_sun` before the first picture.

    Args:
        plan: The plan. It must be consistent.
        settings: The choices that trade quality for time.
        keep_x: The east coordinate of a place that no tree may stand near,
            such as the eye of the camera.
        keep_y: The north coordinate of that place.
        keep_radius: How far round it no tree stands, in meters.

    Returns:
        The scene.

    Raises:
        Error: If the plan, a texture, the pebble photograph or a mesh is not
            valid.
    """
    var assets = Assets()
    var scene = Scene()
    scene.environment_intensity = 0.5
    scene.fog = exp2_fog(Color(172, 196, 226), InverseLength(0.0008, PER_METER))
    var dome = scene.add(Object3D())
    var heaven = Scene()
    var heaven_sky = _add_sky(assets, heaven, Vector3(0, 1, 0))
    var look = castle_look(assets, settings.texture_size)
    var upright = scene.add(Object3D())
    var view = default_view()
    view.terrain_step = settings.terrain_step
    _add_meshes(scene, assets, look, upright, castle_meshes(plan, view))
    var trees = 0
    var shrubs = 0
    if settings.woods:
        trees = plant_trees(
            scene, assets, look, plan, upright, keep_x, keep_y, keep_radius
        )
        shrubs = plant_bushes(scene, assets, look, plan, upright)
    return _finish(
        scene^,
        assets^,
        heaven^,
        heaven_sky,
        dome,
        plan,
        settings,
        trees,
        shrubs,
    )


def build_landscape_scene(
    plan: CastlePlan,
    settings: SceneSettings,
    land: Landscape,
    forest: ForestSettings,
    clearings: List[Clearing],
) raises -> CastleScene:
    """Build the scene of a castle in its landscape.

    The ground is the castle's own round the moat and mountains far off
    (`build_landscape`). The water is the one plane of Clearwater at the level
    of the moat, so it floods every basin under that level. The fog is the
    color of the horizon, so that the far mountains fade into the sky. The sun
    starts overhead. Call `aim_sun` before the first picture.

    Args:
        plan: The plan. It must be consistent.
        settings: The choices that trade quality for time. Its terrain step
            is not used: the landscape sets the cells of the ground.
        land: The landscape, from `build_landscape`.
        forest: The choices of the woods, which are planted if `settings`
            asks for woods.
        clearings: Places that no tree stands near, such as the site of
            a scanned building.

    Returns:
        The scene.

    Raises:
        Error: If the plan, the settings, a texture, the pebble photograph or
            a mesh is not valid.
    """
    plan.check()
    var horizon = sky_color(0.0, 0.0)
    var fog = Color(
        UInt8(Int(horizon[0])), UInt8(Int(horizon[1])), UInt8(Int(horizon[2]))
    )
    var assets = Assets()
    var scene = Scene()
    scene.environment_intensity = 0.5
    scene.fog = exp2_fog(
        fog, InverseLength(Float32(land.settings.haze), PER_METER)
    )
    var dome = scene.add(Object3D())
    var heaven = Scene()
    var heaven_sky = _add_sky(assets, heaven, Vector3(0, 1, 0))
    var look = castle_look(assets, settings.texture_size)
    var upright = scene.add(Object3D())
    var kit = Kit()
    build_structures(plan, default_view(), kit)
    add_ground(land, kit)
    _add_meshes(scene, assets, look, upright, kit.meshes())
    var trees = 0
    var shrubs = 0
    if settings.woods:
        trees = plant_forest(
            scene, assets, look, land, upright, forest, clearings
        )
        shrubs = plant_bushes(scene, assets, look, plan, upright)
    return _finish(
        scene^,
        assets^,
        heaven^,
        heaven_sky,
        dome,
        plan,
        settings,
        trees,
        shrubs,
    )


def aim_sun(
    mut castle: CastleScene, renderer: Renderer, toward: Vector3
) raises:
    """Move the sun, and light the scene with the sky that it makes.

    Args:
        castle: The scene.
        renderer: The renderer that the sky cube is drawn with.
        toward: The unit direction toward the sun, with y up and z south.

    Raises:
        Error: If the sun is not over the horizon, or the sky cannot be
            drawn.
    """
    if not (toward.y > 0.0):
        raise Error("The sun must be over the horizon")
    castle.sun = toward
    # A low sun is dimmer and redder: its light crosses more of the air. The
    # light of the sky that fills the shadows is dimmer too.
    var altitude = asin(min(Float64(toward.y), 1.0)) * 180.0 / 3.141592653589793
    var warm = _smooth(altitude / 20.0)
    var strong = _smooth(altitude / 12.0)
    castle.scene.lights[0].color = Color(
        255, UInt8(Int(150.0 + 94.0 * warm)), UInt8(Int(90.0 + 134.0 * warm))
    )
    castle.scene.lights[0].intensity = Float32(3.2 * (0.3 + 0.7 * strong))
    castle.scene.environment_intensity = Float32(0.5 * (0.55 + 0.45 * strong))
    castle.scene.node(castle.lamp).set_position(
        30.0 + Float32(_SUN_DISTANCE) * toward.x,
        4.0 + Float32(_SUN_DISTANCE) * toward.y,
        -44.0 + Float32(_SUN_DISTANCE) * toward.z,
    )
    ref program = castle.assets.programs.get(castle.heaven_sky.program)
    program.set_uniform("sunPosition", toward)
    castle.heaven.update()
    var light = pmrem_from_scene(
        renderer,
        castle.heaven,
        castle.assets,
        size=castle.environment_size,
        far=Length(6000.0, METER),
    )
    castle.scene.environment = castle.assets.cube_textures.add(light^)
    castle.water.set_sun(toward)


def draw_castle[
    C: Camera
](
    mut castle: CastleScene,
    renderer: Renderer,
    camera: C,
    coverage: Float64,
    seed: Int,
) raises -> Framebuffer:
    """Draw the castle at the sun that `aim_sun` set.

    Args:
        castle: The scene.
        renderer: The renderer.
        camera: A centered perspective camera, above the water.
        coverage: How much of the sky the clouds cover, from 0 to 1.
        seed: Where the random numbers of the clouds start.

    Returns:
        The picture.

    Raises:
        Error: If the camera is not valid or a stage cannot be drawn.
    """
    castle.scene.update()
    var image = renderer.render(castle.scene, castle.assets, camera)
    _ = paint_sky(
        image,
        camera,
        coverage,
        seed,
        Float64(castle.sun.x),
        Float64(castle.sun.y),
        Float64(castle.sun.z),
    )
    # The scanned buildings are blended in after the sky, behind the
    # surfaces of the scene that are nearer, and before the water.
    for at in range(len(castle.layers)):
        _ = composite_splats(
            image, castle.layers[at], camera, available_workers()
        )
    var dry = image.pixels.copy()
    _ = castle.water.compose(
        image,
        castle.scene,
        camera,
        Length(castle.level, METER),
        castle.bed,
    )
    _ = reflect_in_water(
        renderer,
        castle.scene,
        castle.assets,
        camera,
        castle.dome,
        image,
        dry,
        castle.level,
        murk=0.7,
    )
    return image^


def add_splat_layer(mut castle: CastleScene, var layer: SplatLayer):
    """Stand a scanned building in the scene.

    Args:
        castle: The scene.
        layer: The scan, from `splat_layer`.
    """
    castle.layers.append(layer^)


def advance_water(mut castle: CastleScene, seconds: Float32) raises:
    """Let the ripples of the moat run on.

    Args:
        castle: The scene.
        seconds: How long to run them.

    Raises:
        Error: If the time is negative or not finite.
    """
    castle.water.advance(Duration(seconds, SECOND), False)
