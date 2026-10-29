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
   camera's yaw, on the village's `Terrain`. The walls, the furniture,
   the trees, the pond and every resident stop it. A door's gap lets it
   into a house, and its floor carries it there.
3. While the player moves and the look stick rests, the camera comes
   round behind the player.
4. The player's `Body` stands where the character stands and plays its
   stance's clip.
5. Each resident steps along its route and is posed: see `Residents`.
6. Each door swings open while someone stands near it, and shut after.
7. A new press of the use button uses the spot of `Gathering` in reach:
   see `extensions.village.gathering`. With no spot in reach, it talks
   to the villager in reach: see `extensions.village.talk`.
8. The camera follows the player. Where a wall stands between the
   player and the eye, the eye comes in to stand before the wall, and it
   goes back out slowly when the wall is passed. Under a ceiling, the
   eye stays below it. It stays above the ground or the floor. The
   inside of each house further than `INSIDE_REACH` from the eye hides.
9. The village prepares the frame: the grass for the camera, and the
   water's clock.
10. The weather moves on, and scales the lights and the fog: see
    `extensions.village.weather`. The day moves on, and dims and tints
    them for the hour; the houses' windows glow from dusk to dawn: see
    `extensions.village.day`.

`VillageGame.render` then draws the frame with `GameRenderer` at the
quality's size, composes the pond's water into it, and stretches it to the
window, and writes the heads-up display over it: see
`extensions.village.hud`. `GameQuality` says how finely each part of the frame is drawn: see
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
from extensions.attire.outfit import Outfit
from extensions.humanoid.athleticism import TONED, UNTONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.vegetation.field import FieldStats
from extensions.vegetation.ground import Ground, Lot, lot_openness
from extensions.vegetation.meadow import EXPOSURE, FARTHEST
from extensions.village.character import (
    Character,
    CharacterParameters,
    MoveInput,
    Obstacle,
)
from extensions.village.gathering import GatherParameters, Gathering
from extensions.village.hud import draw_hud, note_text, use_prompt
from extensions.village.skills import (
    FISHING,
    FORAGING,
    MINING,
    Skills,
    fish_haste,
    forage_bonus,
    ore_strikes,
    skill_name,
)
from extensions.village.critters import Critters, Haunt, default_haunts
from extensions.village.day import DayCycle, dim_water
from extensions.village.talk import (
    SPEECH_SECONDS,
    Speaker,
    Talk,
    default_speakers,
)
from extensions.village.weather import CLEAR, Weather, WeatherKind
from extensions.village.residents import (
    Body,
    Herd,
    HouseId,
    NO_HOUSE,
    Residents,
    ResidentsParameters,
    Villager,
)
from extensions.village.clothes import (
    CREAM_WOOL,
    GRAY_WOOL,
    MADDER,
    NETTLE,
    WALNUT,
    WELD,
    WOAD,
    village_outfit,
)
from extensions.village.quality import (
    GameQuality,
    LOW,
    game_quality,
    planted,
)
from extensions.village.scanned import CutBuilding
from extensions.village.terrain import OPEN_SKY, Terrain
from extensions.village.interior import Doorway
from extensions.village.village import Village, VillageParameters
from extensions.water.pebbles import PebbleBed
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from render.game_smooth import smooth_edges
from render.game_upscale import upscale_into
from renderers.game_renderer import FULL_SHADOWS, GameRenderer
from renderers.renderer import Renderer, available_workers
from std.math import exp
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
comptime SIGHT_POINTS = 4
"""How many points along the camera's sight hold a door open."""
comptime INSIDE_REACH = Float32(18)
"""How far past a house's edge a camera can be and still see its inside
drawn, in meters."""
comptime ARM_MARGIN = Float32(0.3)
"""How far before a wall the camera's eye stops, in meters."""
comptime ARM_EASE = Float32(3)
"""How fast the eye goes back out once a wall is passed: each second it
closes all but `exp(-ARM_EASE)` of its gap."""


def default_residents() raises -> ResidentsParameters:
    """Return the people and the animals of the default village.

    Returns:
        A woman in a hooded green tunic by the brick house, who visits
        it; a man in a blue tunic on the trail, who visits the stone
        cottage; a child in a yellow tunic who runs round the pond; an
        old man in a gray tunic, who visits the framed cottage; and a
        woman in a red tunic by the framed house, who visits it. Four
        sheep and a goat right of the trail, two cows and a horse left
        of it, a pig by the barn, a dog near the start, two rabbits by
        the trail and two deer past the pond. The deer run from a player
        12 meters away, the rabbits from 6, the sheep from 3 and the goat
        from 2.

    Raises:
        Error: Never: the outfits check.
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
            village_outfit(NETTLE, WELD, GRAY_WOOL, True),
            HouseId(0),
        ),
        Villager(
            HumanoidSpec(Length(70.0, INCH), MALE, TONED, random_genome(8)),
            -2,
            0,
            14,
            42,
            False,
            village_outfit(WOAD, CREAM_WOOL, WALNUT, False),
            HouseId(2),
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
            village_outfit(WELD, MADDER, WALNUT, False),
            NO_HOUSE,
        ),
        Villager(
            HumanoidSpec(Length(67.0, INCH), MALE, UNTONED, random_genome(21)),
            6,
            -24,
            6,
            44,
            False,
            village_outfit(GRAY_WOOL, WALNUT, CREAM_WOOL, True),
            HouseId(4),
        ),
        Villager(
            HumanoidSpec(Length(64.0, INCH), FEMALE, TONED, random_genome(34)),
            14,
            -16,
            6,
            45,
            False,
            village_outfit(MADDER, CREAM_WOOL, WOAD, False),
            HouseId(3),
        ),
    ]
    residents.herds = [
        Herd(SHEEP, 4, 15, 4, 7, 51, flee=Length(3.0, METER)),
        Herd(GOAT, 1, 20, -6, 5, 52, flee=Length(2.0, METER)),
        Herd(COW, 2, -18, 6, 8, 53),
        Herd(HORSE, 1, -14, -16, 7, 54),
        Herd(PIG, 1, -12, -48, 4, 55),
        Herd(DOG, 1, 4, 22, 4, 56),
        Herd(RABBIT, 2, -6, 14, 3, 57, flee=Length(6.0, METER)),
        Herd(DEER, 2, 30, -40, 10, 58, flee=Length(12.0, METER)),
    ]
    return residents^


struct PlayParameters(Copyable, Movable):
    """What the game holds: the village, its residents and the player."""

    var village: VillageParameters
    var residents: ResidentsParameters
    var player: HumanoidSpec
    # What the player wears.
    var outfit: Outfit
    # How finely each part of a frame is drawn.
    var quality: GameQuality
    # Where the player starts, in meters, and the way they face.
    var start_x: Float32
    var start_z: Float32
    var heading: Angle
    # The camera's field of view.
    var field_of_view: Angle
    # What the player can gather about the village, and the villagers
    # who talk and give errands.
    var gathering: GatherParameters
    var speakers: List[Speaker]
    # Where the fireflies and the butterflies keep: see
    # `extensions.village.critters`.
    var haunts: List[Haunt]
    # Whether `VillageGame.render` writes the satchel, the prompt and the
    # last note over the frame: see `extensions.village.hud`.
    var hud: Bool
    # The weather the game begins in, and whether it turns from weather to
    # weather by itself: see `extensions.village.weather`.
    var weather: WeatherKind
    var weather_cycle: Bool
    # The hour the game begins at, and how fast the day moves on: see
    # `extensions.village.day`.
    var day: DayCycle

    def __init__(out self, quality: GameQuality) raises:
        """Create the default game at a quality: the village with the
        quality's plants, its residents, and a man of six feet on the
        trail who looks toward the houses. He wears a madder-red tunic
        trimmed in weld yellow over a linen shirt, walnut hose and
        leather boots. The village has its default spots to gather, and
        the heads-up display is on. Its villagers talk and give errands.
        Fireflies and butterflies keep to its default haunts. The
        weather is clear, and stays so. It is two in the afternoon, and
        stays so.

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
        self.outfit = village_outfit(MADDER, WELD, WALNUT, False)
        self.start_x = 0
        self.start_z = 26
        self.heading = Angle(0.0, RADIAN)
        self.field_of_view = Angle(55.0, DEGREE)
        self.gathering = GatherParameters()
        self.speakers = default_speakers()
        self.haunts = default_haunts()
        self.hud = True
        self.weather = CLEAR
        self.weather_cycle = False
        self.day = DayCycle()


def tree_obstacles(
    parameters: VillageParameters, lots: List[Lot]
) -> List[Obstacle]:
    """Return a trunk for each planting that grows in a village's meadow.

    A planting on a lot or its apron, or in the pond, does not grow: the
    meadow leaves it out, and so does this.

    Args:
        parameters: The village.
        lots: The lots the meadow leaves bare, as `Village` gives them to
            its meadow: the houses', the scanned building's and the
            footpaths'.

    Returns:
        One obstacle a planting that grows, `TRUNK` times its size
        across.
    """
    var out = List[Obstacle]()
    ref plantings = parameters.meadow.plantings
    for index in range(len(plantings)):
        ref planting = plantings[index]
        if lot_openness(lots, planting.x, planting.z) < 1:
            continue
        if parameters.meadow.ground.wet(planting.x, planting.z):
            continue
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
    # The ground, the houses' walls and floors, and the solid lots.
    var terrain: Terrain
    # The share of the camera's distance its eye stands at: less than one
    # while a wall stands in the way.
    var reach: Float32
    # The game's clock, in seconds.
    var clock: Float32
    # How finely each part of a frame is drawn, the window's size, and the
    # renderer that draws the frame at its smaller size.
    var quality: GameQuality
    var width: Int
    var height: Int
    var fast: GameRenderer
    # How long the last frame's draw, its water, the smoothing of its edges
    # and its stretch took, in milliseconds.
    var render_ms: Float64
    var water_ms: Float64
    var smooth_ms: Float64
    var upscale_ms: Float64
    # The last frame, the window's size: `render` draws into it.
    var window: Framebuffer
    # What the player can gather, and what the player has.
    var gathering: Gathering
    # Whether `render` writes the heads-up display; the last note, and how
    # long ago it was given, in seconds.
    var hud: Bool
    var note: String
    var note_age: Float32
    # The villagers who talk, and how tall each villager is, in meters.
    var talk: Talk
    var heads: List[Float32]
    # The fireflies and the butterflies.
    var critters: Critters
    # The player's gathering skills.
    var skills: Skills
    # The weather, and how long its clouds, fog and rain took to draw in
    # the last frame, in milliseconds.
    var weather: Weather
    var weather_ms: Float64
    # The hour of the day.
    var day: DayCycle

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
        # The houses' brick, plaster, wood and tiles show at each pixel.
        self.fast.pixel_maps = True
        self.render_ms = 0
        self.water_ms = 0
        self.smooth_ms = 0
        self.upscale_ms = 0
        self.window = Framebuffer(
            width, height, List[UInt8](length=width * height * 4, fill=0)
        )
        self.village = Village(
            scene, assets, renderer, parameters.village, bed^, scan^
        )
        ref field = self.village.meadow.field
        self.terrain = self.village.terrain()
        self.reach = 1
        # Each house's front door: the villagers' homes.
        var homes = List[Doorway]()
        for index in range(len(self.village.houses)):
            homes.append(self.village.houses[index].interior.front_door())
        # The residents' points keep off the buildings and the props.
        var keep_off = field.lots.copy()
        keep_off.extend(self.village.props.lots.copy())
        self.residents = Residents(
            scene,
            assets,
            parameters.residents,
            self.terrain,
            keep_off,
            homes,
        )
        self.body = Body(
            scene,
            assets,
            parameters.player,
            parameters.outfit,
            parameters.residents.triangles,
            parameters.residents.detail,
        )
        self.player = Character(
            CharacterParameters(),
            parameters.start_x,
            parameters.start_z,
            parameters.heading,
            self.terrain,
        )
        self.village.meadow.grass_wind_every = self.quality.grass_wind_every
        # A still shadow map is drawn once, and the grass changes as the
        # player walks, so only full shadows take the grass.
        self.village.meadow.set_grass_shadows(
            scene, self.quality.shadows == FULL_SHADOWS
        )
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
        self.trees = tree_obstacles(
            parameters.village, self.village.meadow.field.lots
        )
        # The spots keep off the lots and the props, as the residents do,
        # and a solid spot stops a character as a trunk does.
        self.gathering = Gathering(
            scene,
            assets,
            self.village.looks,
            parameters.gathering,
            self.village.meadow.field.ground,
            keep_off,
        )
        self.trees.extend(self.gathering.obstacles())
        self.talk = Talk(
            scene,
            assets,
            self.village.looks,
            parameters.speakers.copy(),
            len(parameters.residents.villagers),
        )
        self.critters = Critters(
            scene,
            assets,
            self.village.looks,
            parameters.haunts,
            self.village.meadow.field.ground,
            self.village.level,
        )
        self.skills = Skills()
        self.heads = List[Float32]()
        for villager in parameters.residents.villagers:
            self.heads.append(villager.spec.stature.to(METER))
        self.hud = parameters.hud
        self.note = String()
        self.note_age = 0
        self.weather = Weather(scene, parameters.weather)
        self.weather.cycle = parameters.weather_cycle
        self.day = parameters.day
        self.weather_ms = 0
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
        self.view.turn(input.look_right, input.look_up, delta)
        var blocking = self.trees.copy()
        blocking.extend(self.residents.obstacles())
        self.player.step(input, self.view.yaw, delta, self.terrain, blocking)
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
        self.residents.update(scene, delta, self.terrain, around, feet)
        var people = List[Vector3]()
        people.append(feet)
        for index in range(len(self.residents.people)):
            people.append(self.residents.people[index].position)
        for index in range(len(self.residents.beasts)):
            people.append(self.residents.beasts[index].character.position)
        # A door the camera looks through stays open too: points along the
        # last frame's sight hold it, at the height of the player's feet.
        var sight = self.camera.position
        for k in range(SIGHT_POINTS):  # pragma: no branch
            var t = Float32(k) / Float32(SIGHT_POINTS)
            people.append(
                Vector3(
                    sight.x + (feet.x - sight.x) * t,
                    feet.y,
                    sight.z + (feet.z - sight.z) * t,
                )
            )
        self.village.doors.update(scene, people, delta)
        self.note_age += delta.to(SECOND)
        # The player's skills set how well they gather.
        self.gathering.ore_strikes = ore_strikes(self.skills.level(MINING))
        self.gathering.forage_bonus = forage_bonus(self.skills.level(FORAGING))
        self.gathering.fish_haste = fish_haste(self.skills.level(FISHING))
        var gathered = self.gathering.update(scene, feet, input.use, delta)
        if gathered:
            var kind = gathered.value()
            var gives = self.gathering.satchel.last
            self.note = note_text(kind, gives)
            self.note_age = 0
            var risen = self.skills.gain(kind, gives)
            if risen:
                var skill = risen.value()
                self.note = String(
                    skill_name(skill), " LEVEL ", self.skills.level(skill), "!"
                )
        # The use button talks only where no spot is in reach.
        var places = List[Vector3]()
        for index in range(len(self.residents.people)):
            places.append(self.residents.people[index].position)
        var free = input.use and self.gathering.focus < 0 and not gathered
        var spoke = self.talk.update(
            scene,
            feet,
            places,
            self.heads,
            free,
            self.gathering.satchel,
            delta,
        )
        if spoke:
            # The villager stops, and turns to the player while they talk.
            var who = self.talk.speakers[self.talk.focus].villager
            self.residents.hold(who, SPEECH_SECONDS, feet)
        self.view.follow_target(
            Vector3(feet.x, feet.y + FOCUS_HEIGHT, feet.z), delta
        )
        self.fast.focus = feet
        # The eye comes in at once before a wall, and goes back out slowly.
        var focus = self.view.focus
        var clear = self.terrain.view_reach(focus, self.view.eye(), ARM_MARGIN)
        if clear < self.reach:
            self.reach = clear
        else:
            var ease = 1 - exp(-ARM_EASE * delta.to(SECOND))
            self.reach += (clear - self.reach) * ease
        var eye = focus + (self.view.eye() - focus) * self.reach
        # The floors and ceilings that the player's feet reach: the eye
        # stays over the floor under it, and under the ceilings that
        # `Terrain.view_ceiling` holds it under.
        self.view.place_within(
            self.camera,
            Length(self.terrain.height_at(eye.x, eye.z, feet.y), METER),
            Length(self.terrain.view_ceiling(focus, eye, feet.y), METER),
            self.reach,
        )
        # A house's inside shows only to a camera near it: from further
        # away, its windows show little of it.
        # The houses' lamps are lit from dusk to dawn.
        var daylight = self.day.daylight()
        var lamps = daylight < 0.5
        self.critters.update(scene, daylight, self.weather.look.rain, delta)
        ref eye_at = self.camera.position
        for index in range(len(self.village.houses)):
            ref house = self.village.houses[index]
            scene.node(house.lit).visible = lamps
            scene.node(house.daylit).visible = not lamps
            ref middle = scene.node(house.root).position
            var dx = eye_at.x - middle.x
            var dz = eye_at.z - middle.z
            var near = house.radius + INSIDE_REACH
            scene.node(house.inside).visible = dx * dx + dz * dz < near * near
        scene.update()
        self.clock += delta.to(SECOND)
        var stats = self.village.update(
            scene, assets, self.camera, Duration(self.clock, SECOND)
        )
        # The meadow's sun sets its lights again as it fits its shadows to
        # the camera, so the weather scales them after.
        self.weather.update(scene, delta, self.view.yaw)
        # The day dims and tints what the weather set.
        self.day.advance(delta)
        ref seen_from = self.camera.position
        var roofed = (
            self.terrain.ceiling_over(seen_from.x, seen_from.z, feet.y)
            < OPEN_SKY
        )
        self.day.light(scene, roofed)
        return stats

    def render(mut self, scene: Scene, assets: Assets) raises:
        """Draw the frame that `tick` prepared into `window`.

        The frame is drawn at the quality's smaller size, and the pond's
        water is composed into it if the camera sees the pond. Its edges
        are smoothed if the quality's `smooth_edges` asks, and it is
        stretched over `window`. The window's frame is kept from frame to
        frame, so it is not allocated again. The weather's clouds and fog,
        and the night's darkness and stars, cover the frame's sky before
        the stretch, and the weather's rain falls over
        the window's frame after it, unless the camera's eye is under a
        roof. If `hud` is set, the satchel, the prompt and the last note
        are written over the window's frame.

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
        # Water that the camera cannot see is not composed: its surface
        # and caustics cost most of the composition.
        if self.village.pond_seen(self.camera):
            # The water is lit by its own sky: it darkens with the night.
            var share = self.day.water_light()
            var dark = share < 1
            var before = image.depth.copy() if dark else List[Float32]()
            _ = self.village.water.compose(
                image, scene, self.camera, self.village.level, self.village.bed
            )
            if dark:
                dim_water(image, before, share)
        var watered = perf_counter_ns()
        self.weather.cover(image, self.camera)
        self.day.night_sky(image, self.camera, 1 - self.weather.look.clouds)
        var covered = perf_counter_ns()
        self.render_ms = Float64(drawn - began) / 1.0e6
        self.water_ms = Float64(watered - drawn) / 1.0e6
        self.smooth_ms = 0
        if self.quality.smooth_edges:
            smooth_edges(image, available_workers())
            self.smooth_ms = Float64(perf_counter_ns() - covered) / 1.0e6
        self.upscale_ms = 0
        if image.width == self.width and image.height == self.height:
            self.window = image^
        else:
            var smoothed = perf_counter_ns()
            upscale_into(image, self.window, available_workers())
            self.upscale_ms = Float64(perf_counter_ns() - smoothed) / 1.0e6
        var raining = perf_counter_ns()
        # No rain falls before an eye under a roof.
        ref eye = self.camera.position
        var feet = self.player.position.y
        if self.terrain.ceiling_over(eye.x, eye.z, feet) >= OPEN_SKY:
            self.weather.rain(self.window)
        self.weather_ms = (
            Float64(perf_counter_ns() - raining + covered - watered) / 1.0e6
        )
        if self.hud:
            draw_hud(
                self.window,
                self.gathering.satchel,
                self.prompt(),
                self.note,
                self.note_age,
                self.talk.speech,
                self.talk.age,
                self.talk.errands(self.gathering.satchel),
                self.skills.lines(),
            )

    def prompt(self) -> String:
        """Return what the use button does now, for the heads-up display.

        Returns:
            The prompt for the spot the player can use, or else for the
            villager the player can talk to, or an empty string if there
            is neither.
        """
        var focus = self.gathering.focus
        if focus < 0:
            return self.talk.prompt()
        ref g = self.gathering.spots[focus]
        return use_prompt(
            g.spot.kind, g.strikes, g.phase, self.gathering.ore_strikes
        )
