# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Three people dressed from the skin out, walking: clothing and armor.

    mojo run -I . examples/armory.mojo [path.png]

The page is Outfits and armor. A peasant woman wears a shirt, hose, a
tunic, a hood, boots and a wool cloak that swings as she walks. A
man-at-arms wears a gambeson under a mail hauberk and coif, with a
heater shield on his back and a sword that swings from his hip on a
spring chain. A knight wears the same under a full harness of plate and
a surcoat per pale, his sword at his hip. Each outfit is made from the
wearer's own skin, so each fits a body of its own. The camera turns
round them as they walk. It writes `out/armory.png` and prints how long
the dressing, the cloth and the frames took.
"""

from tools._example_output import example_destination, gallery_camera
from tools._example_studio import (
    cast_received_shadows,
    studio_floor,
    studio_sun,
)

from animation.animation_mixer import AnimationAction, AnimationMixer
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.attire.cloth import Cloak, CloakCut, add_cloak
from extensions.attire.fabric import fabric_material
from extensions.attire.kinds import LEATHER, PLATE, WOOL
from extensions.attire.outfit import dress
from extensions.attire.preset import outfit_named
from extensions.attire.props import heater_shield, sword_in_scabbard
from extensions.attire.sockets import BACK, LEFT_HIP, attach, socket_place
from extensions.attire.springs import (
    SpringChain,
    SpringSettings,
    add_spring_chain,
    body_colliders,
)
from extensions.humanoid.genome import (
    SHOULDER_BREADTH,
    MELANIN,
    Expression,
    Genome,
)
from extensions.humanoid.rig.clips import walk_clip
from extensions.humanoid.rig.game import GameHumanoid, add_game_humanoid
from extensions.humanoid.rig.joints import HIPS
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.spec import HumanoidSpec
from geometries.sphere import sphere
from lights.light import ambient_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from materials.material import (
    BACK_SIDE,
    BASIC,
    DOUBLE_SIDE,
    Material,
    SCENE_ENVIRONMENT,
    physical_material,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.environment import pmrem_from_scene
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin
from std.pathlib import Path
from std.time import perf_counter_ns
from units.si import (
    DEGREE,
    FOOT,
    INCH,
    METER,
    SECOND,
    Angle,
    Duration,
    Length,
)

comptime DEFAULT_OUTPUT = "out/armory.png"
comptime WIDTH = 480
comptime HEIGHT = 270
comptime FPS = 24
comptime FRAMES = 72
comptime TRIANGLES = 24000
# Frames the cloth and the springs settle for at rest, before the walk.
comptime SETTLE = 40


def _seconds_since(start: Int) -> Float64:
    """Return the seconds since `start`, a `perf_counter_ns` reading."""
    return Float64(perf_counter_ns() - start) / 1e9


def studio(mut assets: Assets) raises -> Scene:
    """Return a studio for polished metal: a bright sky over a dark floor,
    with two soft boxes, drawn into an environment."""
    var scene = Scene()
    var dome = sphere(Length(1.0, METER), 48, 24)
    ref placed = dome.attribute_view(String(POSITION))
    var colors = List[Float32]()
    for v in range(placed.count()):
        var q = placed.vector3(v)
        var value = Float32(0.35) + 0.3 * q.y
        if q.y > 0:
            value = 0.35 + 1.4 * q.y * q.y
        var a = (q - Vector3(-0.6, 0.4, 0.6)).length_sq()
        var b = (q - Vector3(0.7, 0.2, -0.5)).length_sq()
        if a < 0.12:
            value += 3.0
        if b < 0.08:
            value += 2.0
        colors.append(value)
        colors.append(value * 0.98)
        colors.append(value * 0.95)
    dome.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    var paint = Material(Color(255, 255, 255), side=BACK_SIDE, kind=BASIC)
    paint.vertex_colors = True
    scene.add_mesh(
        Mesh(
            assets.geometries.add(dome^),
            assets.materials.add(paint),
            scene.add(Object3D()),
        )
    )
    scene.update()
    return scene^


def _person(
    mut scene: Scene, mut assets: Assets, x: Float32, spec: HumanoidSpec
) raises -> GameHumanoid:
    """Add one person standing on the floor at `x`."""
    var at = scene.add(Object3D())
    var person = add_game_humanoid(
        scene, assets, at, spec, TRIANGLES, workers=available_workers()
    )
    # Stand the soles on the floor: the pelvis frame's origin is at the
    # hips.
    ref skin = assets.geometries.get(
        scene.skinned_meshes[person.skins[0]].geometry
    )
    ref placed = skin.attribute_view(String(POSITION))
    var lowest = Float32(1e9)
    for v in range(placed.count()):
        lowest = min(lowest, placed.vector3(v).y)
    scene.node(at).set_position(x, -lowest, 0)
    return person^


def _sword(
    mut scene: Scene, mut assets: Assets, person: GameHumanoid
) raises -> SpringChain:
    """Hang a sword from a person's left hip on a spring chain."""
    var hip = socket_place(person.rig, LEFT_HIP) - person.rig.joints[HIPS.value]
    var chain = add_spring_chain(
        scene,
        person.bones[HIPS.value],
        [hip, hip + Vector3(0.03, -0.5, -0.06)],
        SpringSettings(stiffness=0.8, gravity=1.0, drag=0.3, radius=0.03),
    )
    chain.colliders = body_colliders(person)
    var parts = sword_in_scabbard(Length(0.85, METER))
    scene.add_mesh(
        Mesh(
            assets.geometries.add(parts[0].clone()),
            assets.materials.add(fabric_material(LEATHER, Color(70, 40, 24))),
            chain.nodes[0],
        )
    )
    scene.add_mesh(
        Mesh(
            assets.geometries.add(parts[1].clone()),
            assets.materials.add(fabric_material(PLATE, Color(220, 220, 226))),
            chain.nodes[0],
        )
    )
    return chain^


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(20, 21, 24))
    renderer.tone_mapping = ACES_FILMIC_TONE_MAPPING
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP
    var assets = Assets()
    var room = studio(assets)
    var lighting = pmrem_from_scene(renderer, room, assets, size=64)
    var scene = Scene()
    scene.environment = assets.cube_textures.add(lighting^)
    scene.environment_intensity = 0.9

    var start = perf_counter_ns()
    var peasant = _person(
        scene,
        assets,
        -1.1,
        HumanoidSpec(
            Length(65, INCH),
            FEMALE,
            genome=Genome().with_gene(MELANIN, Expression(-0.4)),
        ),
    )
    var soldier = _person(
        scene,
        assets,
        0.0,
        HumanoidSpec(
            Length(70, INCH),
            MALE,
            genome=Genome()
            .with_gene(MELANIN, Expression(0.5))
            .with_gene(SHOULDER_BREADTH, Expression(0.6)),
        ),
    )
    var knight = _person(
        scene, assets, 1.1, HumanoidSpec(Length(6, FOOT), MALE)
    )
    print("Built three people in", _seconds_since(start), "s")

    start = perf_counter_ns()
    _ = dress(scene, assets, peasant, outfit_named("peasant"))
    _ = dress(scene, assets, soldier, outfit_named("man-at-arms"))
    _ = dress(scene, assets, knight, outfit_named("knight"))
    print("Dressed them in", _seconds_since(start), "s")

    # The man-at-arms's shield, on his back, its face turned out.
    var slung = Object3D()
    slung.rotate_y(Angle(180.0, DEGREE))
    var back = attach(scene, soldier, BACK, slung^)
    var paint = physical_material(
        Color(255, 255, 255),
        roughness=0.55,
        side=DOUBLE_SIDE,
        env_map=SCENE_ENVIRONMENT,
    )
    paint.vertex_colors = True
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                heater_shield(
                    Length(0.7, METER), Color(28, 52, 130), Color(226, 222, 210)
                )
            ),
            assets.materials.add(paint),
            back,
        )
    )
    var swords = List[SpringChain]()
    swords.append(_sword(scene, assets, soldier))
    swords.append(_sword(scene, assets, knight))
    scene.update()
    var cut = CloakCut(dye=Color(64, 78, 48))
    var cloak = add_cloak(scene, assets, peasant, cut)

    var step = Duration(Float32(1) / Float32(FPS), SECOND)
    start = perf_counter_ns()
    for _ in range(SETTLE):
        scene.update()
        cloak.step(scene, assets, step, available_workers())
        for k in range(len(swords)):
            # Each chain reads the scene as the chain before it left it.
            scene.update()
            swords[k].step(scene, step)

    cast_received_shadows(scene)
    studio_floor(scene, assets, Length(12.0, METER))
    studio_sun(scene, 1.6, 3.4, 2.8, Length(5.0, METER))
    scene.add_light(ambient_light(Color(200, 210, 255), 0.12))
    var mixer = AnimationMixer()
    var people = List[Int]()
    people.append(
        mixer.add(AnimationAction(walk_clip(peasant.bones, peasant.rig)))
    )
    people.append(
        mixer.add(AnimationAction(walk_clip(soldier.bones, soldier.rig)))
    )
    people.append(
        mixer.add(AnimationAction(walk_clip(knight.bones, knight.rig)))
    )
    for k in people:
        mixer.action(k).play()

    var frames = List[Framebuffer]()
    var drawing = Float64(0)
    for frame in range(FRAMES):
        if frame > 0:
            mixer.update(scene, step)
        scene.update()
        cloak.step(scene, assets, step, available_workers())
        for k in range(len(swords)):
            # Each chain reads the scene as the chain before it left it.
            scene.update()
            swords[k].step(scene, step)
        scene.update()
        var turn = Float32(-0.55) + Float32(1.1) * Float32(frame) / Float32(
            FRAMES - 1
        )
        var eye = Vector3(4.4 * sin(turn), 1.15, 4.4 * cos(turn))
        var camera = gallery_camera(
            WIDTH,
            HEIGHT,
            eye,
            Vector3(0.0, 0.85, 0.0),
            field_of_view=Angle(34.0, DEGREE),
            near=Length(0.05, METER),
            far=Length(30.0, METER),
        )
        var drawn = perf_counter_ns()
        frames.append(renderer.render(scene, assets, camera))
        drawing += _seconds_since(drawn)
    print(
        "Stepped the cloth and drew",
        FRAMES,
        "frames in",
        _seconds_since(start),
        "s,",
        drawing,
        "s of it drawing",
    )
    Path(destination).write_bytes(encode(frames, delay_ms=1000 // FPS))
    print("Wrote", destination)
