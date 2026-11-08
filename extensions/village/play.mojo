# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A game in the village: a player walks, runs and jumps among its people
and its animals, seen by a third-person camera.

`VillageGame.tick` runs one frame of the game loop:

1. The look stick turns the camera around the player: see
   `ThirdPersonControls`.
2. The fight runs: see `extensions.village.battle`. The player's
   `Character` steps by the move stick, relative to the camera's yaw, on
   the village's `Terrain`, or an attack, a dodge or a blow carries it.
   The walls, the furniture, the trees, the pond, every resident, the
   bandits and the dummies stop it. A door's gap lets it into a house,
   and its floor carries it there. The bandits think and move, and the
   blows land. The player's `Body` stands where the character stands and
   plays its stance's clip, or its sword's. The coins and the herbs a
   fallen bandit gives go into the satchel, and the herbs the player eats
   to heal come out of it. Fighting trains the skill of the player's
   fighting style. Its level makes the player's blows in that style
   stronger, `SPECIALTY_MIGHT` more in the style they specialize in, and
   teaches the style's combos: see `extensions.village.skills` and
   `extensions.village.combos`.
3. While the player moves and the look stick rests, the camera comes
   around behind the player.
4. The camera turns toward the target the player locks on to.
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
   An eye that a wall brings within `CLOSE_EYE` of the player's head
   hides the player's body, so it does not fill the frame.
9. The village prepares the frame: the grass for the camera, and the
   water's clock.
10. The weather moves on, and scales the lights and the fog: see
    `extensions.village.weather`. The day moves on, and dims and tints
    them for the hour; the houses' windows glow from dusk to dawn: see
    `extensions.village.day`.

`VillageGame.render` then draws the frame with `GameRenderer` at the
quality's size, composes the pond's water into it, and stretches it to the
window, and writes the heads-up display over it: see
`extensions.village.hud` and `extensions.village.battle_hud`. `GameQuality` says how finely each part of the frame is drawn: see
`extensions.village.quality`.
"""

from cameras.perspective_camera import PerspectiveCamera
from controls.third_person_controls import ThirdPersonControls, yaw_of
from core.assets import Assets
from core.object3d import NodeId, Object3D
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
from extensions.attire.mix import (
    FARMER,
    GOODWIFE,
    MONK,
    NOBLEWOMAN,
    PEASANT,
    dressed_as,
)
from extensions.attire.outfit import Outfit
from extensions.humanoid.athleticism import TONED, UNTONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.skeleton.head.expression import (
    ANGER,
    FEAR,
    SADNESS,
)
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.vegetation.field import FieldStats
from extensions.vegetation.ground import Lot, lot_openness
from extensions.vegetation.meadow import EXPOSURE, FARTHEST, sun_direction
from extensions.vegetation.noise import hash01
from core.fog import FogView
from extensions.village.character import (
    Character,
    CharacterParameters,
    MoveInput,
    Obstacle,
    no_input,
    player_movement,
)
from extensions.village.battle import Battle, BattleParameters
from extensions.village.battle_hud import draw_battle
from extensions.village.gathering import (
    CHEST,
    HERBS,
    SEAL,
    GatherParameters,
    Gathering,
)
from extensions.village.battle_hud import DANGER, draw_target, hud_drop
from extensions.village.route import ROUTE_REACH, route_grid
from extensions.village.compass import CompassMark, clock_text, draw_compass
from extensions.village.hud import (
    GOLD_TEXT,
    WHITE_TEXT,
    Rgb,
    draw_hud,
    draw_text,
    draw_vignette,
    fill_box,
    hud_scale,
    text_width,
    note_text,
    use_prompt,
)
from extensions.village.skills import (
    FISHING,
    FORAGING,
    MINING,
    Skills,
    fighting_might,
    fish_haste,
    forage_bonus,
    ore_strikes,
    skill_name,
    style_skill,
)
from extensions.village.progress import PLACE_SHIFT, Progress
from extensions.village.styles import STYLES, FightingStyle
from extensions.village.combat import (
    DODGE,
    FALL,
    FLINCH,
    HEAVY,
    STAGGER,
    Fighter,
    is_attack,
    is_special,
)
from extensions.village.critters import Critters, Haunt, default_haunts
from extensions.village.faces import FaceLife, face_reach
from extensions.village.day import DayCycle, dim_water
from extensions.village.puffs import draw_puffs, dust_puffs
from extensions.village.map import MapHouse, MapMarks, draw_map
from extensions.village.sound import COIN, HIT, SPLASH, STEP, SWING, Sounds
from extensions.village.air import bloom, ground_mist
from extensions.village.gpu_post import GpuPost
from extensions.village.talk import (
    FAIR,
    NIGHT,
    SNOWY,
    WET,
    Mood,
    DONE,
    ErrandState,
    OFFERED,
    SPEECH_SECONDS,
    Speaker,
    Talk,
    default_speakers,
    revealed,
)
from extensions.village.weather import (
    CLEAR,
    Weather,
    WeatherKind,
    weather_label,
    weather_look,
)
from extensions.village.residents import (
    SIT,
    WORK,
    Body,
    Herd,
    HouseId,
    NO_HOUSE,
    Residents,
    ResidentsParameters,
    Stop,
    Villager,
)
from extensions.village.props import (
    BENCH,
    CROPS,
    WELL,
    WOODPILE,
    WOODPILE_DEPTH,
    Prop,
)
from extensions.village.clothes import (
    CREAM_WOOL,
    GRAY_WOOL,
    MADDER,
    NETTLE,
    WALNUT,
    WELD,
    WOAD,
    calling_groom,
    village_outfit,
)
from extensions.village.quality import GameQuality, planted
from extensions.village.scanned import CutBuilding
from extensions.village.terrain import OPEN_SKY, Floor, FloorIndex, Terrain
from extensions.village.interior import Doorway
from extensions.village.village import Village, VillageParameters
from extensions.water.pebbles import PebbleBed
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from render.tasks import TaskGroup
from render.game_smooth import smooth_edges
from render.game_upscale import upscale_into
from renderers.game_renderer import FULL_SHADOWS, GAME_LAMPS, GameRenderer
from lights.light import PHYSICAL_DECAY, point_light
from renderers.renderer import Renderer, available_workers
from std.math import cos, exp, isinf, sin, sqrt
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
comptime SHELTER_LIGHT = Float32(0.2)
"""Below this share of the day's light, the people stay home."""
comptime SHELTER_FALL = Float32(0.6)
"""Above this share of the heaviest rain or snow, the people stay home."""
comptime RAIN_RINGS = Float32(40)
"""How many drops a second ring the pond in a downpour."""
comptime WAKE_EVERY = Float32(0.18)
"""The seconds between two taps of a wading player's wake."""
comptime STRIDE = Float32(0.55)
"""The seconds between two footfalls at a walk."""
comptime HITSTOP = Float32(0.07)
"""How long the world all but stops after a hard blow lands, in seconds."""
comptime HITSTOP_PACE = Float32(0.15)
"""How fast the world moves while it all but stops."""
comptime HITSTOP_BLOW = Float32(40)
"""How much health a blow must take for the world to stop a moment."""
comptime VIGNETTE_HEALTH = Float32(0.35)
"""Below this share of their health, the frame's edges redden."""
comptime FALL_COST = 25
"""The share, in percent, of the coins a player loses when they fall."""
comptime DAWN_MIST = Float32(6.5)
"""The hour that the dawn's ground mist lies thickest."""
comptime SUN_STEP = Float32(1)
"""How far the sun turns, in degrees, before its shadows are drawn again."""
comptime SIGHT_POINTS = 4
"""How many points along the camera's sight hold a door open."""
comptime INSIDE_REACH = Float32(18)
"""How far past a house's edge a camera can be and still see its inside
drawn, in meters."""
comptime ARM_MARGIN = Float32(0.3)
"""How far before a wall the camera's eye stops, in meters."""
comptime CLOSE_EYE = Float32(1.2)
"""How near the player's head, in meters, the camera's eye can come before
the player's body hides: nearer, the head and the shoulders fill the
frame."""
comptime SHAKEN = Float32(1.0e-3)
"""A camera's shake of less than this, in meters, is not seen."""
comptime LANTERN_COLOR = Color(255, 205, 150)
"""The color of the lantern's light that follows the player by night."""
comptime LANTERN_INTENSITY = Float32(5)
"""How bright the player's lantern burns, as a point light's intensity:
a little less than a lamp's."""
comptime LANTERN_REACH = Float32(10)
"""How far the player's lantern lights, in meters."""
comptime LANTERN_HEIGHT = Float32(3)
"""How high over the player's feet the lantern's light stands, in
meters."""
comptime PUNCH = Float32(0.06)
"""The share by which a finisher's shake narrows the camera's field of
view."""
comptime PUNCH_SHAKE = Float32(0.12)
"""The shake, in meters, at which the view narrows by `PUNCH` in full: a
finisher's."""
comptime SPECIALTY_MIGHT = Float32(0.1)
"""How much stronger the player's blows are in the style they specialize
in."""
comptime TARGET_TOP = 30
"""How far down the frame the panel of the foe locked on to starts, in
dots of the heads-up display's font: under the compass."""
comptime FOE_SIGHT = Float32(60)
"""How near a foe must be for the compass to point to it, in meters."""
comptime SILVER_MARK = Rgb(200, 205, 215)
"""The color of the compass's mark at an errand taken."""
comptime GRIMACE = Float32(0.5)
"""How long the player's face holds what a move shows, in seconds."""
comptime WINDED = Float32(0.6)
"""Below this share of their stamina, the player pants."""
comptime ARM_EASE = Float32(3)
"""How fast the eye goes back out once a wall is passed: each second it
closes all but `exp(-ARM_EASE)` of its gap."""


def shows_player(eye: Vector3, focus: Vector3) -> Bool:
    """Return whether the camera's eye stands far enough from the player's
    head to show the player's body.

    Args:
        eye: Where the camera's eye is.
        focus: What it looks at: the player's head.

    Returns:
        True if the eye is `CLOSE_EYE` or more from the focus.
    """
    return (eye - focus).length() >= CLOSE_EYE


def trunks_reach(
    trunks: List[Obstacle], focus: Vector3, eye: Vector3, margin: Float32
) -> Float32:
    """Return how much of the way from a focus to an eye is clear of the
    trees' trunks.

    Args:
        trunks: The trunks, as round obstacles.
        focus: The point the camera looks at.
        eye: Where the camera would stand.
        margin: How far before a trunk the camera must stop, in meters.

    Returns:
        The share of the way, from 0 to 1, that the camera can stand at: 1
        when no trunk is in the way.
    """
    var dx = eye.x - focus.x
    var dz = eye.z - focus.z
    var a = dx * dx + dz * dz
    if a < 1.0e-8:
        return 1
    var first = Float32(1)
    for trunk in trunks:
        var fx = focus.x - trunk.x
        var fz = focus.z - trunk.z
        var b = 2 * (fx * dx + fz * dz)
        var c = fx * fx + fz * fz - trunk.radius * trunk.radius
        var d = b * b - 4 * a * c
        if d < 0 or c < 0:
            continue
        var t = (-b - sqrt(d)) / (2 * a)
        if t > 0 and t < first:
            first = t
    if first >= 1:
        return 1
    return max(Float32(0), first - margin / sqrt(a))


def village_mood(day: Float32, wet: Float32, snowed: Float32) -> Mood:
    """Return what the village is like, for its speakers to remark on.

    Args:
        day: The share of the day's light, from 0 to 1.
        wet: How wet the village is, from 0 to 1.
        snowed: How much snow lies on it, from 0 to 1.

    Returns:
        `NIGHT` in the dark, then `SNOWY` under snow, then `WET` when the
        village is soaked, and `FAIR` else.
    """
    if day < 0.5:
        return NIGHT
    if snowed > 0.3:
        return SNOWY
    if wet > 0.4:
        return WET
    return FAIR


def prop_stops(props: List[Prop]) -> List[Stop]:
    """Return the stops that a village's props give its people: a seat on
    each bench, and a place to work at each woodpile, bed of crops and
    well.

    Args:
        props: The props.

    Returns:
        The stops, in the order of the props.
    """
    var stops = List[Stop]()
    for prop in props:
        var turn = prop.turn.to(RADIAN)
        # The prop's own x and z on the ground.
        var along = Vector3(cos(turn), 0, -sin(turn))
        var front = Vector3(sin(turn), 0, cos(turn))
        var at = Vector3(prop.x, 0, prop.z)
        if prop.kind == BENCH:
            var seat = at + front * 0.45
            stops.append(Stop(seat.x, seat.z, yaw_of(front), SIT))
        elif prop.kind == WOODPILE:
            var block = at + front * (WOODPILE_DEPTH / 2 + 0.9)
            stops.append(
                Stop(block.x, block.z, yaw_of(Vector3(0, 0, 0) - front), WORK)
            )
        elif prop.kind == CROPS:
            var bed = at + front * 1.3
            stops.append(
                Stop(bed.x, bed.z, yaw_of(Vector3(0, 0, 0) - front), WORK)
            )
        elif prop.kind == WELL:
            var side = at + along * (prop.length + 0.7)
            stops.append(
                Stop(side.x, side.z, yaw_of(Vector3(0, 0, 0) - along), WORK)
            )
    return stops^


def default_residents() raises -> ResidentsParameters:
    """Return the people and the animals of the default village.

    Returns:
        A goodwife by the brick house, who visits it; a peasant on the
        trail, who visits the stone cottage; a farmer's child who runs
        around the pond; an old monk, who visits the framed cottage; and
        a noblewoman by the framed house, who visits it. Each wears the
        hair and the beard of their calling. Four
        sheep and a goat in their pen right of the trail, two cows and a horse left
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
            -6,
            -28,
            6,
            41,
            False,
            dressed_as(GOODWIFE, FEMALE, 3),
            HouseId(0),
            calling_groom(GOODWIFE, FEMALE, 3),
        ),
        Villager(
            HumanoidSpec(Length(70.0, INCH), MALE, TONED, random_genome(8)),
            -2,
            0,
            14,
            42,
            False,
            dressed_as(PEASANT, MALE, 8),
            HouseId(2),
            calling_groom(PEASANT, MALE, 8),
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
            dressed_as(FARMER, FEMALE, 13),
            NO_HOUSE,
            calling_groom(FARMER, FEMALE, 13),
        ),
        Villager(
            HumanoidSpec(Length(67.0, INCH), MALE, UNTONED, random_genome(21)),
            6,
            -24,
            6,
            44,
            False,
            dressed_as(MONK, MALE, 21),
            HouseId(4),
            calling_groom(MONK, MALE, 21),
        ),
        Villager(
            HumanoidSpec(Length(64.0, INCH), FEMALE, TONED, random_genome(34)),
            14,
            -16,
            6,
            45,
            False,
            dressed_as(NOBLEWOMAN, FEMALE, 34),
            HouseId(3),
            calling_groom(NOBLEWOMAN, FEMALE, 34),
        ),
    ]
    residents.herds = [
        Herd(SHEEP, 4, 15, 4, 7, 51, flee=Length(3.0, METER)),
        Herd(GOAT, 1, 17, 6, 4, 52, flee=Length(2.0, METER)),
        Herd(COW, 2, -18, 6, 8, 53),
        Herd(HORSE, 1, -22, -10, 6, 54),
        Herd(PIG, 1, -12, -48, 4, 55),
        Herd(DOG, 1, 4, 22, 4, 56, follows=True),
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
    # Who fights in the village: see `extensions.village.battle`.
    var battle: BattleParameters

    def __init__(out self, quality: GameQuality) raises:
        """Create the default game at a quality: the village with the
        quality's plants, its residents, and a man of six feet on the
        trail who looks toward the houses. He wears a madder-red tunic
        trimmed in weld yellow over a linen shirt, walnut hose and
        leather boots. The village has its default spots to gather, and
        the heads-up display is on. Its villagers talk and give errands.
        Fireflies and butterflies keep to its default haunts. The
        weather is clear, and stays so. It is two in the afternoon, and
        stays so. Three bandits and their captain keep a camp to the
        north-west, three wolves keep a den east of the pond, and two
        straw dummies stand east of the start.

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
        self.battle = BattleParameters()
        self.battle.coarseness = Float64(quality.animal_coarseness)
        self.battle.fight_reach = quality.fight_reach


def player_mood(mut life: FaceLife, fighter: Fighter) raises:
    """Set the player's face by how their fight goes.

    A blow that lands on them, or stamina run out, shows fear, and a fall
    sadness. An attack shows anger: the heavy attack and the specials
    more. Below `WINDED` of their stamina the player pants.

    Args:
        life: The player's face.
        fighter: The player in the fight.

    Raises:
        Error: Never: the expressions are named.
    """
    var move = fighter.move
    if move == FALL:
        life.feel(SADNESS, 1, GRIMACE)
    elif move == FLINCH or move == STAGGER:
        life.feel(FEAR, 0.7, GRIMACE)
    elif move == HEAVY or is_special(move):
        life.feel(ANGER, 0.9, GRIMACE)
    elif is_attack(move):
        life.feel(ANGER, 0.55, GRIMACE)
    var top = fighter.parameters.stamina
    var left = fighter.stamina / top if top > 0 else Float32(1)
    life.pant((WINDED - left) / WINDED)


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


def game_residents(parameters: PlayParameters) -> ResidentsParameters:
    """Return the residents a game builds: its own, with animals no finer
    than its quality's preset meshes them.

    A game given residents of its own keeps their animals' coarseness
    where it is coarser than the preset's. Where it is finer, the preset's
    holds: a game at a low quality builds its animals coarse, whoever
    chose its residents.

    Args:
        parameters: The game's parameters.

    Returns:
        The residents, with their animal coarseness at least the
        quality's.
    """
    var residents = parameters.residents.copy()
    residents.animal_coarseness = max(
        residents.animal_coarseness,
        Float64(parameters.quality.animal_coarseness),
    )
    return residents^


struct VillageGame(Movable):
    """The village, its residents and the player, and the camera on the
    player."""

    var village: Village
    var residents: Residents
    var body: Body
    var player: Character
    var view: ThirdPersonControls
    var camera: PerspectiveCamera
    # The camera's field of view while no blow tightens it.
    var wide: Angle
    # The node of the lantern's light that follows the player by night.
    var lantern: NodeId
    var trees: List[Obstacle]
    # The ground, the houses' walls and floors, and the solid lots.
    var terrain: Terrain
    # The share of the camera's distance its eye stands at: less than one
    # while a wall stands in the way.
    var reach: Float32
    # The game's clock, in seconds.
    var clock: Float32
    # The rain's drops on the pond that are owed to the next frame, how
    # many drops have fallen, and the seconds until a wading player's
    # next wake.
    var rain_rings: Float32
    var splashes: Int
    var wake: Float32
    # The direction toward the sun, or the moon, as the scene last set it.
    var sun_was: Vector3
    var sounds: Sounds
    """The village's sounds, which a host takes with `audio`."""
    var paused: Bool
    """Whether the game is paused: nothing moves, and the frame shows the
    controls."""
    var hitstop: Float32
    """How long the world still nearly stops after a blow landed, in
    seconds."""
    var dust_at: Vector3
    """Where the player's feet last kicked up dust: a hard landing, or a
    roll."""
    var dust_since: Float32
    """How long ago, in seconds, the dust was kicked up."""
    var was_kicking: Bool
    """Whether the player was landing hard or rolling last frame."""
    var show_map: Bool
    """Whether the frame shows the map of the village round the
    player."""
    var stride: Float32
    """The seconds until the player's next footfall."""
    var swinging: Bool
    """Whether the player was making an attack last frame."""
    var foes_health: Float32
    """The health of every foe last frame, so a blow that lands is
    heard."""
    var combo_was: Int
    """The player's combo last frame, so a blow on a dummy is heard too."""
    var coins_were: Int
    """The coins the satchel held last frame."""
    # How finely each part of a frame is drawn, the window's size, and the
    # renderer that draws the frame at its smaller size.
    var quality: GameQuality
    var width: Int
    var height: Int
    var fast: GameRenderer
    # How long the last frame's draw, its water, the smoothing of its edges
    # and its stretch and sharpening took, in milliseconds.
    var render_ms: Float64
    var water_ms: Float64
    var smooth_ms: Float64
    var upscale_ms: Float64
    # The last frame, the window's size: `render` draws into it.
    var window: Framebuffer
    # The image that a GPU draws into, between `prepare_gpu` and
    # `finish_gpu`: the renderer's size, which is the window's for a game
    # that a GPU draws. And when `prepare_gpu` began, in nanoseconds.
    var gpu_image: Framebuffer
    var gpu_began: Int
    # What a GPU draws after the triangles, when it does: the weather, the
    # night, the pond's water and the smoothing of edges.
    var gpu_post: GpuPost
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
    # The fight: the player's sword, the bandits and the dummies.
    var battle: Battle
    # How near the camera must be to a face to see it move, in meters.
    var face_reach: Float32
    # The villager who last spoke, or -1.
    var talker: Int

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
        self.gpu_image = Framebuffer(
            size[0],
            size[1],
            List[UInt8](length=size[0] * size[1] * 4, fill=0),
        )
        self.gpu_began = 0
        self.gpu_post = GpuPost()
        self.village = Village(
            scene, assets, renderer, parameters.village, bed^, scan^
        )
        ref field = self.village.meadow.field
        self.terrain = self.village.terrain()
        self.reach = 1
        # Each house's front door: the villagers' homes.
        var homes = List[Doorway]()
        # And the way up each one's stairs, to bed by night.
        var climbs = List[List[Vector3]]()
        for index in range(len(self.village.houses)):
            homes.append(self.village.houses[index].interior.front_door())
            climbs.append(self.village.houses[index].interior.climb.copy())
        # The residents' points keep off the buildings and the props.
        var keep_off = field.lots.copy()
        keep_off.extend(self.village.props.lots.copy())
        self.residents = Residents(
            scene,
            assets,
            game_residents(parameters),
            self.terrain,
            keep_off,
            homes,
            prop_stops(parameters.village.props),
            climbs,
        )
        self.body = Body(
            scene,
            assets,
            parameters.player,
            parameters.outfit,
            parameters.residents.triangles,
            parameters.residents.detail,
            speaks=parameters.residents.faces,
            seed=1,
        )
        # The camera is close to the player: their skirt keeps out of
        # their legs.
        self.body.keep_hems(scene, assets)
        self.player = Character(
            player_movement(),
            parameters.start_x,
            parameters.start_z,
            parameters.heading,
            self.terrain,
        )
        self.battle = Battle(
            scene,
            assets,
            parameters.battle,
            self.village.looks,
            self.terrain,
            keep_off,
            self.body,
            self.player.position,
            parameters.residents.triangles,
            parameters.residents.detail,
        )
        # The fighters near the camera keep their skirts out of their
        # legs too.
        self.battle.keep_hems(scene, assets)
        # The companion goes into a house by its front door.
        self.battle.set_doors(homes.copy(), climbs.copy())
        # She and the raiders find their ways round the houses and the pond.
        var grid = route_grid(
            self.terrain,
            self.player.parameters.wade_depth.to(METER),
            ROUTE_REACH,
        )
        self.battle.set_grid(grid^)
        self.village.meadow.grass_wind_every = self.quality.grass_wind_every
        # A still shadow map is drawn once, and the grass changes as the
        # player walks, so only full shadows take the grass.
        self.village.meadow.set_grass_shadows(
            scene, self.quality.shadows == FULL_SHADOWS
        )
        self.village.water.shade_step = self.quality.water_step
        self.village.water.refresh_every = self.quality.water_refresh_every
        self.face_reach = face_reach(size[1], parameters.field_of_view)
        self.talker = -1
        self.view = ThirdPersonControls(parameters.heading)
        self.wide = parameters.field_of_view
        # A lantern's light follows the player by night: see `tick`.
        var holder = Object3D()
        holder.visible = False
        self.lantern = scene.add(holder^)
        scene.add_light(
            point_light(
                LANTERN_COLOR,
                self.lantern,
                LANTERN_INTENSITY,
                PHYSICAL_DECAY,
                LANTERN_REACH,
            )
        )
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
        self.rain_rings = 0
        self.splashes = 0
        self.wake = 0
        self.sounds = Sounds()
        self.paused = False
        self.show_map = False
        self.hitstop = 0
        self.dust_at = Vector3(0, 0, 0)
        self.dust_since = 10
        self.was_kicking = False
        self.stride = 0
        self.swinging = False
        self.foes_health = 0
        self.combo_was = 0
        self.coins_were = 0
        self.sun_was = sun_direction(
            parameters.village.meadow.sun_elevation,
            parameters.village.meadow.sun_azimuth,
        )
        self.village.meadow.register_shadings(self.fast, assets)
        self.fast.set_shadows(self.quality.shadows, self.quality.shadow_size)
        var movers = List[NodeId]()
        movers.append(self.body.carrier)
        for index in range(len(self.residents.bodies)):
            movers.append(self.residents.bodies[index].carrier)
        for index in range(len(self.residents.beasts)):
            movers.append(self.residents.beasts[index].node)
        movers.extend(self.battle.movers())
        scene.update()
        self.fast.set_moving(scene, movers)

    def progress(self) raises -> Progress:
        """Return what the player keeps from this game to the next.

        Returns:
            Each skill's experience, what the satchel holds, each combo's
            mastery, the specialty and the style in hand.

        Raises:
            Error: Never: the combos build.
        """
        var out = Progress()
        out.experience = self.skills.experience.copy()
        out.satchel = self.gathering.satchel.counts.copy()
        out.mastery = self.battle.book.mastery.copy()
        out.specialty = self.battle.book.specialty
        out.style = self.battle.fighter.style
        for index in range(len(self.talk.states)):
            out.errands.append(self.talk.states[index].value)
            out.rounds.append(self.talk.rounds[index])
        out.spent = self.gathering.spent()
        ref at = self.player.position
        out.place = [
            Int(at.x * 100) + PLACE_SHIFT,
            Int(at.z * 100) + PLACE_SHIFT,
            Int(self.day.hour * 1000) + PLACE_SHIFT,
            self.weather.kind.value,
        ]
        return out^

    def restore(mut self, mut scene: Scene, progress: Progress) raises:
        """Take up what the player kept from a game before: the levels
        that the experience gives teach their combos again. The style in
        hand is taken up if the player carries it.

        Args:
            scene: The scene: the spots used up hide.
            progress: The kept progress.

        Raises:
            Error: If `Progress.check` refuses it.
        """
        progress.check()
        # The world as the game before left it: its errands, its spots
        # used up, where the player stood, the hour and the weather.
        if len(progress.errands) == len(self.talk.states):
            for index in range(len(progress.errands)):
                var state = ErrandState(progress.errands[index])
                if state.is_valid():
                    self.talk.states[index] = state
                self.talk.rounds[index] = progress.rounds[index]
        for index in progress.spent:
            self.gathering.spend(scene, index)
        if len(progress.place) == 4:
            var x = Float32(progress.place[0] - PLACE_SHIFT) / 100
            var z = Float32(progress.place[1] - PLACE_SHIFT) / 100
            var hour = Float32(progress.place[2] - PLACE_SHIFT) / 1000
            if hour >= 0 and hour < 24:
                self.day.hour = hour
            var weather = WeatherKind(progress.place[3])
            if weather.is_valid():
                self.weather.set(weather)
                self.weather.look = weather_look(weather)
            if abs(x) < 1.0e4 and abs(z) < 1.0e4:
                var ground = self.terrain.height_at(x, z, 1.0e4)
                self.player.position = Vector3(x, ground, z)
                self.player.velocity = Vector3(0, 0, 0)
        self.skills.experience = progress.experience.copy()
        self.gathering.satchel.counts = progress.satchel.copy()
        self.battle.book.mastery = progress.mastery.copy()
        self.battle.book.specialty = progress.specialty
        self.battle.parameters.specialty = progress.specialty
        ref carried = self.battle.parameters.styles
        for k in range(len(carried)):  # pragma: no branch
            if carried[k] == progress.style:
                if self.battle.fighter.set_style(progress.style):
                    self.battle.style_at = k
                return

    def tick(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        given: MoveInput,
        elapsed: Duration,
    ) raises -> FieldStats:
        """Run one frame of the game. A paused game runs its frame with no
        time and no input, so nothing moves.

        Args:
            scene: The scene the game is in.
            assets: The stores.
            given: The player's input for the frame.
            elapsed: The frame's time.

        Returns:
            What the frame draws of the grass.

        Raises:
            Error: If the time is negative, or a part cannot move or
                prepare the frame.
        """
        var input = given
        var delta = elapsed
        if self.paused:
            input = no_input()
            delta = Duration(0.0, SECOND)
        # Just after a blow lands, the world all but stops a moment.
        if self.hitstop > 0:
            self.hitstop -= delta.to(SECOND)
            delta = Duration(delta.to(SECOND) * HITSTOP_PACE, SECOND)
        self.view.turn(input.look_right, input.look_up, delta)
        var blocking = self.trees.copy()
        blocking.extend(self.residents.obstacles())
        var calm = abs(input.look_right) < CALM and abs(input.look_up) < CALM
        self.battle.herbs = self.gathering.satchel.count(HERBS)
        # Each style's skill sets its level, which teaches its combos; the
        # style the player fights in sets how strong the blows are.
        for k in range(STYLES):  # pragma: no branch
            var level = self.skills.level(style_skill(FightingStyle(k)))
            self.battle.levels[k] = level
        ref fighter = self.battle.fighter
        var might = fighting_might(self.battle.levels[fighter.style.value])
        if fighter.style == self.battle.book.specialty:
            might *= 1 + SPECIALTY_MIGHT
        fighter.parameters.might = might
        self.battle.tick(
            scene,
            input,
            self.view,
            self.player,
            self.body,
            self.terrain,
            blocking,
            delta,
        )
        if calm and self.battle.lock < 0:
            var top = self.player.parameters.run_speed.to(METER_PER_SECOND)
            var share = self.player.speed().to(METER_PER_SECOND) / top
            self.view.trail(self.player.heading, share, delta)
        # A fallen bandit's coins go into the satchel, and the fight's
        # last word is the note.
        self.gathering.satchel.counts[CHEST.value] += self.battle.loot
        self.battle.loot = 0
        self.gathering.satchel.counts[SEAL.value] += self.battle.seals
        self.battle.seals = 0
        # A fall costs a share of the coins the player carries.
        if self.battle.fell:
            self.battle.fell = False
            var coins = self.gathering.satchel.count(CHEST)
            var lost = coins * FALL_COST // 100
            if lost > 0:
                self.gathering.satchel.counts[CHEST.value] -= lost
                self.battle.notes.append(String("YOU LOSE ", lost, " COINS"))
        self.gathering.satchel.counts[HERBS.value] += (
            self.battle.found - self.battle.eaten
        )
        self.battle.found = 0
        self.battle.eaten = 0
        if len(self.battle.notes) > 0:
            self.note = self.battle.notes[len(self.battle.notes) - 1]
            self.note_age = 0
            self.battle.notes.clear()
        # Fighting trains each style's skill.
        for k in range(STYLES):  # pragma: no branch
            var skill = style_skill(FightingStyle(k))
            if self.skills.train(skill, self.battle.trained[k]):
                self.note = String(
                    skill_name(skill), " LEVEL ", self.skills.level(skill), "!"
                )
                self.note_age = 0
            self.battle.trained[k] = 0
        var around = self.trees.copy()
        around.extend(self.battle.obstacles())
        ref feet = self.player.position
        around.append(
            Obstacle(feet.x, feet.z, self.player.parameters.radius.to(METER))
        )
        # At night, and in hard rain or snow, the people go home.
        var look = self.weather.look
        var shelter = (
            self.day.daylight() < SHELTER_LIGHT
            or look.rain > SHELTER_FALL
            or look.snow > SHELTER_FALL
        )
        self.residents.update(
            scene,
            delta,
            self.terrain,
            around,
            feet,
            shelter,
            self.battle.dangers(),
        )
        var people = List[Vector3]()
        people.append(feet)
        for index in range(len(self.residents.people)):
            people.append(self.residents.people[index].position)
        for index in range(len(self.residents.beasts)):
            people.append(self.residents.beasts[index].character.position)
        # The companion and the raiders open the doors too.
        people.extend(self.battle.friends())
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
        self.talk.mood = village_mood(
            self.day.daylight(), self.weather.wet, self.weather.snowed
        )
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
            # Their mouth says the words, and their face shows how they
            # feel.
            var who = self.talk.speakers[self.talk.focus].villager
            self.talker = who
            self.residents.hold(who, SPEECH_SECONDS, feet)
            ref life = self.residents.bodies[who].life
            life.say(self.talk.words)
            life.feel(self.talk.feeling, self.talk.strength, SPEECH_SECONDS)
        self.view.follow_target(
            Vector3(feet.x, feet.y + FOCUS_HEIGHT, feet.z), delta
        )
        self.fast.focus = feet
        # The eye comes in at once before a wall, and goes back out slowly.
        var focus = self.view.focus
        var clear = min(
            self.terrain.view_reach(focus, self.view.eye(), ARM_MARGIN),
            trunks_reach(self.trees, focus, self.view.eye(), ARM_MARGIN),
        )
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
        # An eye that a wall brings in close hides the player's body.
        scene.node(self.body.carrier).visible = shows_player(
            self.camera.position, self.view.focus
        )
        # A strong blow shakes the camera, and what it looks at with it.
        var jolt = self.battle.shake
        if jolt > SHAKEN:
            var t = self.clock * 47
            var off = Vector3(sin(t) * jolt, cos(t * 1.3) * jolt * 0.7, 0)
            self.camera.place(self.camera.position + off, self.view.focus + off)
        # It tightens the view a moment too, and the view eases back as the
        # shake dies: a finisher's shake narrows it by `PUNCH` in full.
        var punch = min(Float32(1), jolt / PUNCH_SHAKE) * PUNCH
        self.camera.fov = Angle(self.wide.to(DEGREE) * (1 - punch), DEGREE)
        # The player's face shows the fight, and each face near the camera
        # moves.
        player_mood(self.body.life, self.battle.fighter)
        var viewer = self.camera.position
        self.body.show_face(scene, viewer, self.face_reach, delta)
        for index in range(len(self.residents.bodies)):
            self.residents.bodies[index].show_face(
                scene, viewer, self.face_reach, delta
            )
        # A house's inside shows only to a camera near it: from further
        # away, its windows show little of it.
        # The houses' lamps are lit from dusk to dawn.
        var daylight = self.day.daylight()
        var lamps = daylight < 0.5
        self.critters.update(scene, daylight, self.weather.look.rain, delta)
        ref eye_at = self.camera.position
        scene.node(self.village.props.lit).visible = lamps
        scene.node(self.village.lamps).visible = lamps
        # By night a lantern's light follows the player, so a fight can be
        # seen. When the lamps take every light the renderer draws, it
        # takes the light of the lamp farthest from the camera.
        scene.node(self.lantern).visible = lamps
        ref held = self.player.position
        scene.node(self.lantern).set_position(
            held.x, held.y + LANTERN_HEIGHT, held.z
        )
        var spare = -1
        if len(self.village.bulbs) >= GAME_LAMPS:
            var farthest = Float32(-1)
            for k in range(len(self.village.bulbs)):  # pragma: no branch
                var p = scene.node(self.village.bulbs[k]).position
                var d = (p - self.camera.position).length()
                if d > farthest:
                    farthest = d
                    spare = k
        for k in range(len(self.village.bulbs)):
            scene.node(self.village.bulbs[k]).visible = k != spare
        scene.node(self.village.props.daylit).visible = not lamps
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
        # The player's skirt rides over their legs as the bones now stand,
        # and so do the skirts of the fighters nearest the camera.
        _ = self.body.push_hems(scene, assets)
        _ = self.battle.push_hems(scene, assets, self.camera.position)
        self.clock += delta.to(SECOND)
        self.ripple_pond(scene, delta)
        self.hear(delta)
        var stats = self.village.update(
            scene, assets, self.camera, Duration(self.clock, SECOND)
        )
        # The meadow's sun sets its lights again as it fits its shadows to
        # the camera, so the weather scales them after.
        self.weather.update(scene, delta, self.view.yaw)
        # The day dims and tints what the weather set.
        self.day.advance(delta)
        self.follow_sun(scene)
        # The rain soaks the village, and the snow whitens it in the day's
        # light.
        self.village.weather_surfaces(
            assets,
            self.weather.wet,
            self.weather.snowed,
            self.day.daylight()
            * (0.5 + 0.5 * min(Float32(1), self.weather.look.sky / 2.6)),
        )
        ref seen_from = self.camera.position
        var roofed = (
            self.terrain.ceiling_over(seen_from.x, seen_from.z, feet.y)
            < OPEN_SKY
        )
        self.day.light(scene, roofed)
        return stats

    def hear(mut self, delta: Duration) raises:
        """Start the sounds of this frame: the player's footfalls, the
        swing of an attack, a blow that lands on a foe, and coins into the
        satchel; and set the air's sound to the weather and the hour.

        Args:
            delta: The frame's time.

        Raises:
            Error: Never: each sound is one.
        """
        var seconds = delta.to(SECOND)
        # A footfall each stride, quicker and louder at a run; a splash in
        # the pond.
        var speed = self.player.speed().to(METER_PER_SECOND)
        self.stride -= seconds
        if self.player.grounded and speed > 0.5 and self.stride <= 0:
            self.stride = STRIDE / max(Float32(1), speed / 1.4)
            ref feet = self.player.position
            var kind = STEP
            if self.village.meadow.field.ground.drowned(feet.x, feet.z):
                kind = SPLASH
            self.sounds.play(kind, min(Float32(1), 0.3 + 0.1 * speed), 0)
        var attacking = is_attack(self.battle.fighter.move)
        if attacking and not self.swinging:
            self.sounds.play(SWING, 0.6, 0)
        self.swinging = attacking
        var health = self.battle.foes_health()
        var landed = self.battle.fighter.combo > self.combo_was
        self.combo_was = self.battle.fighter.combo
        if health < self.foes_health - 0.5 or landed:
            self.sounds.play(HIT, 0.8, 0)
            # A hard blow stops the world a moment, so it is felt.
            if health < self.foes_health - HITSTOP_BLOW:
                self.hitstop = HITSTOP
        self.foes_health = health
        # A hard landing and a roll kick up dust from the ground.
        var kicking = (
            self.player.landing > 0 or self.battle.fighter.move == DODGE
        ) and self.player.grounded
        if kicking and not self.was_kicking:
            self.dust_at = self.player.position
            self.dust_since = 0
        self.was_kicking = kicking
        self.dust_since += seconds
        var coins = self.gathering.satchel.count(CHEST)
        if coins > self.coins_were:
            self.sounds.play(COIN, 0.7, 0)
        self.coins_were = coins
        ref look = self.weather.look
        self.sounds.set_air(
            min(Float32(1), 0.15 + 0.5 * look.gloom + 0.3 * look.clouds),
            min(Float32(1), look.rain),
            self.day.daylight(),
        )

    def audio(mut self, frames: Int) raises -> List[Float32]:
        """Return the next samples of the village's sound, for a host to
        play.

        Args:
            frames: How many samples to make on each side, from 0 to
                `SAMPLE_RATE`.

        Returns:
            `2 * frames` stereo samples, the left first, from -1 to 1.

        Raises:
            Error: If `frames` is out of range.
        """
        return self.sounds.mix(frames)

    def follow_sun(mut self, mut scene: Scene) raises:
        """Turn the sun, or the moon, to the hour, once it has moved
        `SUN_STEP` degrees: its light, its shadows and the water's glints.
        The scene is updated again once the sun has moved, so the frame
        can read its world matrix.

        Args:
            scene: The scene: the sun's node is moved.

        Raises:
            Error: If the sun's node is not in the scene.
        """
        var toward = self.day.sun_toward()
        var turned = (
            toward.x * self.sun_was.x
            + toward.y * self.sun_was.y
            + toward.z * self.sun_was.z
        )
        if turned > cos(SUN_STEP * 0.017453292):
            return
        self.sun_was = toward
        scene.node(self.village.meadow.sun.node).set_position(
            toward.x * 100, toward.y * 100, toward.z * 100
        )
        # The frame reads the sun's world matrix to draw its shadows: it
        # moved after the frame's update, so the scene is updated again.
        scene.update()
        self.fast.refresh_shadows()
        self.village.water.set_sun(toward)

    def sheltered(self, image: Framebuffer) raises -> List[Bool]:
        """Return which pixels of a frame show a point under a roof.

        Args:
            image: The frame, with its depths.

        Returns:
            True for each pixel whose point stands under the ceiling of a
            floor of a house.

        Raises:
            Error: If the frame has no depth for each pixel, or the
                camera's matrices cannot be inverted.
        """
        var w = image.width
        var h = image.height
        if len(image.depth) != w * h:
            raise Error("A frame needs a depth for each pixel")
        var inverse = self.camera.projection_matrix()
        inverse.multiply(self.camera.view_matrix())
        inverse.invert()
        var under = List[Bool](length=w * h, fill=False)
        # The floors sorted into cells, and the rows shared over every
        # core: a pixel tests only the floors over its point.
        var index = FloorIndex(self.terrain.floors)
        var tasks = max(1, min(available_workers() * 2, h))
        var group = TaskGroup()
        for t in range(tasks):  # pragma: no branch
            group.create_task(
                _shelter_task(
                    image.depth.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    under.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    w,
                    h,
                    Pointer(to=inverse)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=index)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=self.terrain.floors)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    t * h // tasks,
                    (t + 1) * h // tasks,
                )
            )
        group.wait()
        _ = inverse
        _ = len(index.members)
        return under^

    def veil(self, mut image: Framebuffer, scene: Scene, day: Float32) raises:
        """Lay the ground mist of the hour and the weather over a frame,
        and make its bright light glow.

        The mist rises in fog, and at dawn. The light glows most at night,
        when the lamps and the windows are the brightest things there are.

        Args:
            image: The frame, with its depths.
            scene: The scene: the mist takes its fog's color.
            day: The share of the day's light, from 0 to 1.

        Raises:
            Error: If the frame has no depth for each pixel.
        """
        var hour = self.day.hour
        var dawn = max(Float32(0), 1 - abs(hour - DAWN_MIST) / 1.5)
        var thick = min(Float32(0.7), self.weather.look.fog * 30 + dawn * 0.3)
        _ = ground_mist(
            image,
            self.camera,
            self.village.level.to(METER),
            thick,
            scene.fog.color,
        )
        _ = bloom(image, 0.92 - 0.2 * (1 - day), 0.25 + 0.5 * (1 - day))

    def ripple_pond(mut self, scene: Scene, delta: Duration) raises:
        """Tap the pond where something stirs it this frame: the rain, a
        wading player, and a fish that bites at a float.

        Args:
            scene: The scene, with current world matrices.
            delta: The frame's time.

        Raises:
            Error: If a float's node is not in the scene.
        """
        ref ground = self.village.meadow.field.ground
        ref pond = ground.pond
        var radius = pond.radius.to(METER)
        var seconds = delta.to(SECOND)
        var level = self.village.level.to(METER)
        # Rain rings: about `RAIN_RINGS` drops a second in a downpour.
        self.rain_rings += self.weather.look.rain * RAIN_RINGS * seconds
        var falling = min(Int(self.rain_rings), 32)
        self.rain_rings -= Float32(Int(self.rain_rings))
        for _ in range(falling):
            self.splashes += 1
            var a = hash01(self.splashes, 1, 71) * 6.2831855
            var r = radius * sqrt(hash01(self.splashes, 2, 71))
            self.village.splash(
                pond.x.to(METER) + r * cos(a),
                pond.z.to(METER) + r * sin(a),
                Length(0.12, METER),
                0.02 + 0.03 * hash01(self.splashes, 3, 71),
            )
        # A wading player leaves a wake, a few taps a second.
        ref feet = self.player.position
        self.wake -= seconds
        if (
            ground.drowned(feet.x, feet.z)
            and feet.y < level + 0.05
            and self.player.speed().to(METER_PER_SECOND) > 0.3
            and self.wake <= 0
        ):
            self.wake = WAKE_EVERY
            self.village.splash(feet.x, feet.z, Length(0.35, METER), 0.05)
        # A fish that bites jerks its float.
        for at in self.gathering.biting(scene):
            self.village.splash(at.x, at.z, Length(0.15, METER), 0.03)

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
        are written over the window's frame, and what the fight shows.

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
        self._finish(scene, assets, image, began, perf_counter_ns(), False)

    def prepare_gpu(
        mut self, scene: Scene, assets: Assets, passes: Bool = False
    ) raises:
        """Begin the frame that `tick` prepared, for a GPU to draw.

        The shadow maps, the gathering, the light at the vertices, the setup
        of each triangle and the sky are done here, on the CPU. The GPU then
        draws the frame as `fast.gpu_frame` describes it, into `gpu_image`,
        and `finish_gpu` ends the frame. The frame is drawn at the quality's
        size, so a game that a GPU draws should have a render scale of one.

        With `passes`, the GPU also does what follows the triangles: the
        weather and the night over the sky, the pond's water, and the
        smoothing of edges. `gpu_post` then holds their numbers, and
        `finish_gpu` leaves them out. The pond's water must have a shade
        step from 2 to 64.

        Args:
            scene: The scene the game is in.
            assets: The stores.
            passes: Whether the GPU draws the weather, the night, the water
                and the smoothing too.

        Raises:
            Error: If the scene cannot be drawn, or the passes cannot be
                prepared.
        """
        self.gpu_began = perf_counter_ns()
        self.gpu_post.on = False
        self.fast.prepare_gpu(
            scene, assets, self.camera, Duration(self.clock, SECOND)
        )
        if passes:
            self.gpu_post.prepare(
                self.village,
                self.weather,
                self.day,
                self.camera,
                scene,
                self.gpu_image,
                self.quality.smooth_edges,
            )

    def finish_gpu(mut self, scene: Scene, assets: Assets) raises:
        """End the frame that `prepare_gpu` began, once a GPU has drawn it
        into `gpu_image`.

        The pond's water, the weather, the night, the smoothing of the
        edges, the rain and the heads-up display are done as `render` does
        them, on the GPU's image. The frame is then in `window`, and
        `gpu_image` is free for the next frame.

        Args:
            scene: The scene the game is in.
            assets: The stores.

        Raises:
            Error: If the scene cannot be drawn.
        """
        var drawn = perf_counter_ns()
        var image = Framebuffer(
            1, 1, List[UInt8](length=4, fill=0), List[Float32](length=1, fill=0)
        )
        swap(image, self.gpu_image)
        try:
            self._finish(
                scene, assets, image, self.gpu_began, drawn, self.gpu_post.on
            )
        finally:
            swap(image, self.gpu_image)

    def _finish(
        mut self,
        scene: Scene,
        assets: Assets,
        mut image: Framebuffer,
        began: Int,
        drawn: Int,
        passes: Bool,
    ) raises:
        """Do what follows the draw of a frame, on its image, and leave the
        frame in `window`. An image of the window's size is swapped with it,
        so `image` holds the window's last frame after. With `passes`, a GPU
        has drawn the weather, the night, the water and the smoothing."""
        var watered = perf_counter_ns()
        var covered = watered
        if not passes:
            # Water that the camera cannot see is not composed: its surface
            # and caustics cost most of the composition.
            if self.village.pond_seen(self.camera):
                # The water is lit by its own sky: it darkens with the night.
                var share = self.day.water_light()
                var before = image.depth.copy()
                _ = self.village.water.compose(
                    image,
                    scene,
                    self.camera,
                    self.village.level,
                    self.village.bed,
                )
                if share < 1:
                    dim_water(image, before, share)
                # The pond mirrors the village and the stars, and fades into
                # the fog.
                var clear = 1 - self.weather.look.clouds
                var stars = self.day.night_look(self.camera, clear).stars
                self.village.look.clock = self.clock
                _ = self.village.look.apply(
                    image,
                    before,
                    self.camera,
                    self.village.level,
                    FogView(scene.fog),
                    stars,
                )
            watered = perf_counter_ns()
            self.weather.cover(image, self.camera)
            self.day.night_sky(image, self.camera, 1 - self.weather.look.clouds)
            # The chimneys smoke over the finished frame, dim at night.
            var day = self.day.daylight()
            var light = 0.2 + 0.8 * day
            var puffs = self.village.smoke(self.clock)
            puffs.extend(
                dust_puffs(self.dust_at, self.clock, self.dust_since, 7)
            )
            # A fallen foe goes in a puff of dust.
            puffs.extend(self.battle.vanish_puffs(self.clock))
            _ = draw_puffs(image, puffs, self.camera, light)
            self.veil(image, scene, day)
            covered = perf_counter_ns()
        self.render_ms = Float64(drawn - began) / 1.0e6
        self.water_ms = Float64(watered - drawn) / 1.0e6
        self.smooth_ms = 0
        if self.quality.smooth_edges and not passes:
            smooth_edges(image, available_workers())
            self.smooth_ms = Float64(perf_counter_ns() - covered) / 1.0e6
        self.upscale_ms = 0
        # What a house's roof keeps the rain and the snow off, on the
        # frame's own grid: a door open onto a room shows no rain.
        var falling = self.weather.look.rain + self.weather.look.snow > 0.01
        var sheltered = List[Bool]()
        var mask_width = image.width
        var mask_height = image.height
        if falling and not passes:
            sheltered = self.sheltered(image)
        if image.width == self.width and image.height == self.height:
            swap(self.window, image)
        else:
            var smoothed = perf_counter_ns()
            # The stretch softens each edge: it sharpens back what it
            # took as it writes the window.
            upscale_into(
                image, self.window, available_workers(), self.quality.sharpness
            )
            self.upscale_ms = Float64(perf_counter_ns() - smoothed) / 1.0e6
        var raining = perf_counter_ns()
        # No rain falls before an eye under a roof.
        ref eye = self.camera.position
        var feet = self.player.position.y
        if self.terrain.ceiling_over(eye.x, eye.z, feet) >= OPEN_SKY:
            self.weather.rain(self.window, sheltered, mask_width, mask_height)
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
                self.speech(),
                self.talk.age,
                self.talk.errands(self.gathering.satchel),
                self.skills.lines(),
            )
            draw_battle(
                self.window, self.battle, scene, self.camera, self.view.look()
            )
            # A fighting warden's bars take the top of the frame, so the
            # compass and the target panel stand under them.
            # The hour and the weather give way there too: the numbers of
            # the blows over a giant warden's head would cross them.
            var drop = hud_drop(self.battle)
            var caption = String(
                clock_text(self.day.hour),
                "  ",
                weather_label(self.weather.kind),
            )
            draw_compass(
                self.window,
                self.player.position,
                self.view.yaw,
                self.compass_marks(),
                caption if drop == 0 else String(),
                drop,
            )
            draw_target(
                self.window,
                self.battle,
                (TARGET_TOP + drop) * hud_scale(self.window.height),
            )
        if self.show_map:
            _ = draw_map(
                self.window,
                self.village.meadow.field.ground,
                self.map_marks(scene),
                self.player.position,
                self.player.heading.to(RADIAN),
            )
        if self.hud:
            draw_vignette(self.window, self.vignette())
        if self.paused:
            self.draw_pause()

    def vignette(self) -> Float32:
        """Return how red the frame's edges are: the more, the nearer the
        player is to falling, and in a flash as a blow lands.

        Returns:
            From 0 to 1.
        """
        ref f = self.battle.fighter
        var share = f.health / max(Float32(1), f.parameters.health)
        var low = max(Float32(0), (VIGNETTE_HEALTH - share) / VIGNETTE_HEALTH)
        var flash = Float32(0)
        for hurt in self.battle.hurts:
            flash = max(flash, max(Float32(0), 1 - hurt.age / 0.4) * 0.6)
        return min(Float32(1), max(low * 0.8, flash))

    def map_marks(self, scene: Scene) raises -> MapMarks:
        """Return what the map shows: the houses, the villagers, those with
        an errand to give, and the foes that stand.

        Args:
            scene: The scene, updated: the houses' places.

        Returns:
            The marks.

        Raises:
            Error: If the scene is stale.
        """
        var marks = MapMarks()
        for index in range(len(self.village.houses)):  # pragma: no branch
            ref house = self.village.houses[index]
            var at = scene.world_position(house.root)
            marks.houses.append(MapHouse(at.x, at.z, house.radius))
        var giving = List[Bool](length=len(self.residents.people), fill=False)
        for index in range(len(self.talk.speakers)):
            if self.talk.states[index] == OFFERED:
                var v = self.talk.speakers[index].villager
                if v < len(giving):
                    giving[v] = True
        for index in range(len(self.residents.people)):
            var at = self.residents.people[index].position
            if giving[index]:
                marks.errands.append(at)
            else:
                marks.people.append(at)
        marks.foes = self.battle.dangers()
        return marks^

    def draw_pause(mut self):
        """Draw the pause panel over the window: the word, the controls,
        and how to go on."""
        var scale = hud_scale(self.window.height)
        var lines: List[String] = [
            "PAUSED",
            "",
            "Move  WASD or the left stick",
            "Look  arrows, right stick or drag the mouse",
            "Run  Shift   Jump  Space   Use  E",
            "Attack  click, J, K   Dodge  L   Guard  hold G",
            "Weather  1 to 4, 9 snow   Time  5",
            "Map  N   Resume  P   Quit  Esc",
        ]
        var tall = len(lines) * 10 * scale
        var top = (self.window.height - tall) // 2
        fill_box(
            self.window,
            0,
            top - 6 * scale,
            self.window.width,
            top + tall + 4 * scale,
            Rgb(10, 8, 6),
            0.6,
        )
        for k in range(len(lines)):  # pragma: no branch
            var width = text_width(lines[k], scale)
            draw_text(
                self.window,
                (self.window.width - width) // 2,
                top + k * 10 * scale,
                lines[k],
                scale,
                GOLD_TEXT if k == 0 else WHITE_TEXT,
                1,
            )

    def speech(self) -> String:
        """Return what the villager last said, for the heads-up display.

        Returns:
            Their name and their words. The words show as far as the
            villager's mouth has said them: see `revealed`.
        """
        if self.talker < 0:
            return self.talk.speech.copy()
        ref life = self.residents.bodies[self.talker].life
        var total = life.speech.duration()
        var share = life.spoken / total if total > 0 else Float32(1)
        var words = self.talk.words.byte_length()
        var name = self.talk.speech.byte_length() - words
        var bytes = self.talk.speech.as_bytes()
        var out = String()
        for i in range(name):  # pragma: no branch
            out += chr(Int(bytes[i]))
        return out + revealed(self.talk.words, share)

    def compass_marks(self) -> List[CompassMark]:
        """Return the places the compass points to.

        Returns:
            A gold mark at each villager with an errand to offer, a silver
            one at each villager whose errand is taken, and a red one at
            the nearest foe that stands, within `FOE_SIGHT`.
        """
        var marks = List[CompassMark]()
        for index in range(len(self.talk.speakers)):
            var state = self.talk.states[index]
            if state == DONE:
                continue
            var v = self.talk.speakers[index].villager
            var color = GOLD_TEXT if state == OFFERED else SILVER_MARK
            marks.append(CompassMark(self.residents.people[v].position, color))
        ref feet = self.player.position
        var nearest = -1
        var best = FOE_SIGHT * FOE_SIGHT
        for index in range(len(self.battle.foes)):
            ref foe = self.battle.foes[index]
            if foe.down >= 0:
                continue
            var d = foe.character.position - feet
            var far = d.x * d.x + d.z * d.z
            if far < best:
                best = far
                nearest = index
        if nearest >= 0:
            marks.append(
                CompassMark(
                    self.battle.foes[nearest].character.position, DANGER
                )
            )
        return marks^

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


__async def _shelter_task(
    depth: Pointer[Float32, ImmutAnyOrigin],
    under: MutPointer[Bool, MutAnyOrigin],
    w: Int,
    h: Int,
    inverse: Pointer[Matrix4, ImmutAnyOrigin],
    index: Pointer[FloorIndex, ImmutAnyOrigin],
    floors: Pointer[List[Floor], ImmutAnyOrigin],
    first: Int,
    past: Int,
):
    """Mark which pixels of rows `first` to `past` show a point under a
    roof."""
    for y in range(first, past):  # pragma: no branch
        var ny = 1 - (Float32(y) + 0.5) / Float32(h) * 2
        for x in range(w):  # pragma: no branch
            var z = depth[unsafe_offset=y * w + x]
            if isinf(z):
                continue
            var nx = (Float32(x) + 0.5) / Float32(w) * 2 - 1
            var at = inverse[].transform_point(Vector3(nx, ny, z))
            var ceiling = index[].ceiling_over(floors[], at.x, at.z, at.y)
            under[unsafe_offset=y * w + x] = at.y < ceiling
