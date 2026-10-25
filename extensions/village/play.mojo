# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A game in the village: a player walks, runs and jumps among its people
and its animals, seen by a third-person camera.

`VillageGame.tick` runs one frame of the game loop:

1. The look stick turns the camera round the player: see
   `ThirdPersonControls`.
2. The player's `Character` steps by the move stick, relative to the
   camera's yaw. The houses, the trees, the pond and every resident stop
   it.
3. While the player moves and the look stick rests, the camera comes
   round behind the player.
4. The player's `Body` stands where the character stands and plays its
   stance's clip.
5. Each resident steps along its route and is posed: see `Residents`.
6. The camera follows the player and stays above the ground.
7. The village prepares the frame: the grass for the camera, and the
   water's clock.

`VillageGame.render` then draws the frame with `GameRenderer` at the
quality's size, composes the pond's water into it, and stretches it to the
window. `GameQuality` says how finely each part of the frame is drawn: see
`extensions.village.quality`.
"""

from cameras.perspective_camera import PerspectiveCamera
from controls.third_person_controls import ThirdPersonControls
from core.assets import Assets
from core.object3d import NodeId
from core.scene import Scene
from extensions.animals.registry import (
    COW,
    DEER,
    DOG,
    GOAT,
    HORSE,
    PIG,
    RABBIT,
    SHEEP,
)
from extensions.humanoid.athleticism import TONED, UNTONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.vegetation.field import FieldStats
from extensions.vegetation.ground import Ground, Lot
from extensions.vegetation.meadow import EXPOSURE, FARTHEST
from extensions.village.character import (
    Character,
    CharacterParameters,
    MoveInput,
    Obstacle,
)
from extensions.village.residents import (
    Body,
    Herd,
    Residents,
    ResidentsParameters,
    Villager,
)
from extensions.village.quality import (
    GameQuality,
    LOW,
    game_quality,
    planted,
)
from extensions.village.scanned import CutBuilding
from extensions.village.village import Village, VillageParameters
from extensions.water.pebbles import PebbleBed
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from render.game_upscale import upscale_into
from renderers.game_renderer import GameRenderer
from renderers.renderer import Renderer, available_workers
from std.time import perf_counter_ns
from units.si import (
    DEGREE,
    FOOT,
    INCH,
    METER,
    METER_PER_SECOND,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Length,
)

comptime FOCUS_HEIGHT = Float32(1.45)
"""How far above the player's feet the camera looks, in meters."""
comptime TRUNK = Float32(0.35)
"""A tree's trunk radius for a planting of size 1, in meters."""
comptime CALM = Float32(0.1)
"""A look stick that leans less than this lets the camera trail."""


def default_residents() -> ResidentsParameters:
    """Return the people and the animals of the default village.

    Returns:
        A woman by the brick house, a man on the trail and a child who
        runs round the pond; four sheep and a goat right of the trail,
        two cows and a horse left of it, a pig by the barn, a dog near
        the start, two rabbits by the trail and two deer past the pond.
    """
    var residents = ResidentsParameters()
    residents.villagers = [
        Villager(
            HumanoidSpec(Length(65.0, INCH), FEMALE, UNTONED, random_genome(3)),
            -18,
            -32,
            7,
            41,
            False,
        ),
        Villager(
            HumanoidSpec(Length(70.0, INCH), MALE, TONED, random_genome(8)),
            -2,
            0,
            14,
            42,
            False,
        ),
        Villager(
            HumanoidSpec(
                Length(50.0, INCH), FEMALE, UNTONED, random_genome(13)
            ),
            14,
            12,
            5,
            43,
            True,
        ),
    ]
    residents.herds = [
        Herd(SHEEP, 4, 15, 4, 7, 51),
        Herd(GOAT, 1, 20, -6, 5, 52),
        Herd(COW, 2, -18, 6, 8, 53),
        Herd(HORSE, 1, -14, -16, 7, 54),
        Herd(PIG, 1, -12, -48, 4, 55),
        Herd(DOG, 1, 4, 22, 4, 56),
        Herd(RABBIT, 2, -6, 14, 3, 57),
        Herd(DEER, 2, 30, -40, 10, 58),
    ]
    return residents^


struct PlayParameters(Copyable, Movable):
    """What the game holds: the village, its residents and the player."""

    var village: VillageParameters
    var residents: ResidentsParameters
    var player: HumanoidSpec
    # How finely each part of a frame is drawn.
    var quality: GameQuality
    # Where the player starts, in meters, and the way they face.
    var start_x: Float32
    var start_z: Float32
    var heading: Angle
    # The camera's field of view.
    var field_of_view: Angle

    def __init__(out self, quality: GameQuality) raises:
        """Create the default game at a quality: the village with the
        quality's plants, its residents, and a man of six feet on the
        trail who looks toward the houses.

        Args:
            quality: How finely each part of a frame is drawn.

        Raises:
            Error: If `GameQuality.check` refuses the quality.
        """
        quality.check()
        self.quality = quality
        self.village = planted(VillageParameters(), quality.plants)
        self.residents = default_residents()
        self.residents.animal_coarseness = Float64(quality.animal_coarseness)
        self.player = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
        self.start_x = 0
        self.start_z = 26
        self.heading = Angle(0.0, RADIAN)
        self.field_of_view = Angle(55.0, DEGREE)


def tree_obstacles(parameters: VillageParameters) -> List[Obstacle]:
    """Return a trunk for each planting of a village's meadow.

    Args:
        parameters: The village.

    Returns:
        One obstacle a planting, `TRUNK` times its size across.
    """
    var out = List[Obstacle]()
    ref plantings = parameters.meadow.plantings
    for index in range(len(plantings)):
        ref planting = plantings[index]
        out.append(Obstacle(planting.x, planting.z, TRUNK * planting.size))
    return out^


struct VillageGame(Movable):
    """The village, its residents and the player, and the camera on the
    player."""

    var village: Village
    var residents: Residents
    var body: Body
    var player: Character
    var view: ThirdPersonControls
    var camera: PerspectiveCamera
    var trees: List[Obstacle]
    # The game's clock, in seconds.
    var clock: Float32
    # How finely each part of a frame is drawn, the window's size, and the
    # renderer that draws the frame at its smaller size.
    var quality: GameQuality
    var width: Int
    var height: Int
    var fast: GameRenderer
    # How long the last frame's draw, water and stretch took, in
    # milliseconds.
    var render_ms: Float64
    var water_ms: Float64
    var upscale_ms: Float64
    # The last frame, the window's size: `render` draws into it.
    var window: Framebuffer

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        renderer: Renderer,
        parameters: PlayParameters,
        var bed: PebbleBed,
        var scan: Optional[CutBuilding],
        width: Int,
        height: Int,
    ) raises:
        """Build the game into a scene and its stores.

        Args:
            scene: The scene.
            assets: The stores.
            renderer: What the meadow paints its sky with.
            parameters: What the game holds.
            bed: The pebble photograph the pond's water shows through.
            scan: A scanned building for the village, or None.
            width: The window's width, in pixels.
            height: The window's height, in pixels.

        Raises:
            Error: If the quality or the window's size is refused, or the
                village, a resident or the player cannot be built.
        """
        self.quality = parameters.quality
        var size = self.quality.frame_size(width, height)
        self.width = width
        self.height = height
        self.fast = GameRenderer(size[0], size[1], EXPOSURE)
        self.fast.sky_step = self.quality.sky_step
        self.render_ms = 0
        self.water_ms = 0
        self.upscale_ms = 0
        self.window = Framebuffer(
            width, height, List[UInt8](length=width * height * 4, fill=0)
        )
        self.village = Village(
            scene, assets, renderer, parameters.village, bed^, scan^
        )
        ref field = self.village.meadow.field
        self.residents = Residents(
            scene, assets, parameters.residents, field.ground, field.lots
        )
        self.body = Body(
            scene,
            assets,
            parameters.player,
            parameters.residents.triangles,
            parameters.residents.detail,
        )
        self.player = Character(
            CharacterParameters(),
            parameters.start_x,
            parameters.start_z,
            parameters.heading,
            field.ground,
        )
        self.village.meadow.grass_wind_every = self.quality.grass_wind_every
        self.village.water.shade_step = self.quality.water_step
        self.village.water.refresh_every = self.quality.water_refresh_every
        self.view = ThirdPersonControls(parameters.heading)
        self.camera = PerspectiveCamera(
            parameters.field_of_view,
            Float32(width) / Float32(height),
            Length(0.1, METER),
            Length(
                parameters.village.meadow.mountain_radius.to(METER) * FARTHEST,
                METER,
            ),
        )
        self.trees = tree_obstacles(parameters.village)
        self.clock = 0
        self.village.meadow.register_shadings(self.fast, assets)
        self.fast.set_shadows(self.quality.shadows, self.quality.shadow_size)
        var movers = List[NodeId]()
        movers.append(self.body.carrier)
        for index in range(len(self.residents.bodies)):
            movers.append(self.residents.bodies[index].carrier)
        for index in range(len(self.residents.beasts)):
            movers.append(self.residents.beasts[index].node)
        scene.update()
        self.fast.set_moving(scene, movers)

    def tick(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        input: MoveInput,
        delta: Duration,
    ) raises -> FieldStats:
        """Run one frame of the game.

        Args:
            scene: The scene the game is in.
            assets: The stores.
            input: The player's input for the frame.
            delta: The frame's time.

        Returns:
            What the frame draws of the grass.

        Raises:
            Error: If the time is negative, or a part cannot move or
                prepare the frame.
        """
        ref field = self.village.meadow.field
        self.view.turn(input.look_right, input.look_up, delta)
        var blocking = self.trees.copy()
        blocking.extend(self.residents.obstacles())
        self.player.step(
            input, self.view.yaw, delta, field.ground, field.lots, blocking
        )
        var calm = abs(input.look_right) < CALM and abs(input.look_up) < CALM
        if calm:
            var top = self.player.parameters.run_speed.to(METER_PER_SECOND)
            var share = self.player.speed().to(METER_PER_SECOND) / top
            self.view.trail(self.player.heading, share, delta)
        self.body.pose(scene, self.player, delta)
        var around = self.trees.copy()
        ref feet = self.player.position
        around.append(
            Obstacle(feet.x, feet.z, self.player.parameters.radius.to(METER))
        )
        self.residents.update(scene, delta, field.ground, field.lots, around)
        self.view.follow_target(
            Vector3(feet.x, feet.y + FOCUS_HEIGHT, feet.z), delta
        )
        self.fast.focus = feet
        var eye = self.view.eye()
        self.view.place(
            self.camera, Length(field.ground.height_at(eye.x, eye.z), METER)
        )
        scene.update()
        self.clock += delta.to(SECOND)
        return self.village.update(
            scene, assets, self.camera, Duration(self.clock, SECOND)
        )

    def render(mut self, scene: Scene, assets: Assets) raises:
        """Draw the frame that `tick` prepared into `window`.

        The frame is drawn at the quality's smaller size, the pond's water
        is composed into it, and it is stretched over `window`. The window's
        frame is kept from frame to frame, so it is not allocated again.

        Args:
            scene: The scene the game is in.
            assets: The stores.

        Raises:
            Error: If the scene cannot be drawn.
        """
        var began = perf_counter_ns()
        var image = self.fast.render(
            scene, assets, self.camera, Duration(self.clock, SECOND)
        )
        var drawn = perf_counter_ns()
        _ = self.village.water.compose(
            image, scene, self.camera, self.village.level, self.village.bed
        )
        var watered = perf_counter_ns()
        self.render_ms = Float64(drawn - began) / 1.0e6
        self.water_ms = Float64(watered - drawn) / 1.0e6
        self.upscale_ms = 0
        if image.width == self.width and image.height == self.height:
            self.window = image^
            return
        upscale_into(image, self.window, available_workers())
        self.upscale_ms = Float64(perf_counter_ns() - watered) / 1.0e6
