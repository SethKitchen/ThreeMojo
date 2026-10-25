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

`VillageGame.render` then draws the frame. `play_village` is a lighter
village for a game: its trees and its grass have fewer leaves and blades
near the camera, so a frame draws in a few seconds on a CPU instead of
twenty.
"""

from cameras.perspective_camera import PerspectiveCamera
from controls.third_person_controls import ThirdPersonControls
from core.assets import Assets
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
from extensions.vegetation.crown import CrownLevel
from extensions.vegetation.field import FieldStats, LodBand
from extensions.vegetation.ground import Ground, Lot
from extensions.vegetation.meadow import FARTHEST
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
from extensions.village.scanned import CutBuilding
from extensions.village.village import Village, VillageParameters
from extensions.water.pebbles import PebbleBed
from extensions.water.resolution import SpectrumResolution
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from renderers.renderer import Renderer
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


def play_village() raises -> VillageParameters:
    """Return the default village, made lighter for a game.

    The trees wear every third leaf to 20 meters and cards past that. The
    grass keeps fewer blades near the camera and ends at 40 meters. There
    are fewer leaves on the ground, a coarser ground mesh, and smaller
    water and sky textures.

    Returns:
        The village.

    Raises:
        Error: Never; the defaults are in range.
    """
    var parameters = VillageParameters()
    ref meadow = parameters.meadow
    meadow.crown_levels = [
        CrownLevel(Length(20.0, METER), 0.35, False),
        CrownLevel(Length(80.0, METER), 0.1, True),
        CrownLevel(Length(1.0e5, METER), 0.03, True),
    ]
    meadow.field.density = 200
    meadow.field.bands = [
        LodBand(Length(6.0, METER), 0.6, 3),
        LodBand(Length(16.0, METER), 0.2, 2),
        LodBand(Length(40.0, METER), 0.05, 1),
    ]
    meadow.litter = 20000
    meadow.ground_cells = 128
    meadow.sky_size = 256
    parameters.ocean = SpectrumResolution(64)
    parameters.glare = SpectrumResolution(64)
    parameters.caustic_resolution = 128
    return parameters^


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
    # Where the player starts, in meters, and the way they face.
    var start_x: Float32
    var start_z: Float32
    var heading: Angle
    # The camera's field of view.
    var field_of_view: Angle

    def __init__(out self) raises:
        """Create the default game: the lighter village, its residents,
        and a man of six feet on the trail who looks toward the houses.

        Raises:
            Error: Never; the defaults are in range.
        """
        self.village = play_village()
        self.residents = default_residents()
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

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        renderer: Renderer,
        parameters: PlayParameters,
        var bed: PebbleBed,
        var scan: Optional[CutBuilding],
    ) raises:
        """Build the game into a scene and its stores.

        Args:
            scene: The scene.
            assets: The stores.
            renderer: The renderer the frames are drawn with. Its size sets
                the camera's aspect.
            parameters: What the game holds.
            bed: The pebble photograph the pond's water shows through.
            scan: A scanned building for the village, or None.

        Raises:
            Error: If the village, a resident or the player cannot be
                built.
        """
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
        self.view = ThirdPersonControls(parameters.heading)
        self.camera = PerspectiveCamera(
            parameters.field_of_view,
            Float32(renderer.width) / Float32(renderer.height),
            Length(0.1, METER),
            Length(
                parameters.village.meadow.mountain_radius.to(METER) * FARTHEST,
                METER,
            ),
        )
        self.trees = tree_obstacles(parameters.village)
        self.clock = 0

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
        var eye = self.view.eye()
        self.view.place(
            self.camera, Length(field.ground.height_at(eye.x, eye.z), METER)
        )
        scene.update()
        self.clock += delta.to(SECOND)
        return self.village.update(
            scene, assets, self.camera, Duration(self.clock, SECOND)
        )

    def render(
        mut self, mut renderer: Renderer, scene: Scene, assets: Assets
    ) raises -> Framebuffer:
        """Draw the frame that `tick` prepared.

        Args:
            renderer: The renderer.
            scene: The scene the game is in.
            assets: The stores.

        Returns:
            The picture, with the pond's water.

        Raises:
            Error: If the scene cannot be drawn.
        """
        return self.village.render(renderer, scene, assets, self.camera)
