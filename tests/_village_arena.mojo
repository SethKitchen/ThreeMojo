# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A fight on flat ground for the tests of `extensions.village.battle`.

The player stands at the middle and faces -z. A dummy stands 1.5 meters
before them, and a bandit further before them. Each person is bare and
built with the smallest budgets.
"""

from controls.third_person_controls import ThirdPersonControls
from core.assets import Assets
from core.scene import Scene
from extensions.attire.outfit import Outfit
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.vegetation.ground import Ground, Lot
from extensions.village.battle import Battle, BattleParameters
from extensions.village.companion import default_allies
from extensions.village.character import (
    Character,
    CharacterParameters,
    MoveInput,
    Obstacle,
    no_input,
)
from extensions.village.foes import (
    Bandit,
    Den,
    Post,
    bandit_fighter,
    wolf_fighter,
)
from extensions.village.residents import Body
from extensions.village.surfaces import house_looks
from extensions.village.terrain import Terrain
from units.si import (
    DEGREE,
    INCH,
    METER,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Length,
)


def flat_ground() raises -> Ground:
    """Return level ground with no pond.

    Returns:
        The ground.

    Raises:
        Error: Never: the ground's values are in range.
    """
    return Ground(hill_height=Length(0.0, METER))


def arena_parameters(
    bandits: Int = 1,
    dummies: Int = 1,
    far: Float32 = 6,
    wolves: Int = 0,
    ally: Bool = False,
    thrower: Bool = False,
) raises -> BattleParameters:
    """Return a fight of bandits and dummies before the player.

    Args:
        bandits: How many bandits, three meters apart along x, `far`
            meters before the player, each of a bandit's strength.
        dummies: How many dummies, three meters apart along x, 1.5 meters
            before the player.
        far: How far before the player the bandits stand, in meters.
        wolves: How many wolves keep a den `far` meters before the player
            and three meters to its left, meshed in two poses.
        ally: Whether the companion fights beside the player.
        thrower: Whether the bandits throw knives.

    Returns:
        The fight. A fallen foe lingers a second and comes back after
        two; a fallen player comes to after half a second.

    Raises:
        Error: Never: the defaults check.
    """
    var p = BattleParameters()
    p.bandits = List[Bandit]()
    for k in range(bandits):
        p.bandits.append(
            Bandit(
                HumanoidSpec(Length(66.0, INCH), MALE),
                Outfit(),
                Float32(k) * 3,
                -far,
                Angle(180.0, DEGREE),
                5 + k,
                bandit_fighter(),
                thrower,
            )
        )
    p.dens = List[Den]()
    if wolves > 0:
        p.dens.append(Den(-3, -far, wolves, 9, wolf_fighter()))
    p.phases = 2
    p.posts = List[Post]()
    for k in range(dummies):
        p.posts.append(Post(Float32(k) * 3, -1.5, Angle(180.0, DEGREE)))
    if not ally:
        p.allies = List[Bandit]()
    else:
        p.allies = default_allies()
    p.linger = Duration(1.0, SECOND)
    p.respawn = Duration(2.0, SECOND)
    p.revive = Duration(0.5, SECOND)
    return p^


struct Arena(Movable):
    """A fight, and everything it moves."""

    var assets: Assets
    """The stores."""
    var scene: Scene
    """The scene."""
    var body: Body
    """The player's body."""
    var terrain: Terrain
    """The flat ground."""
    var player: Character
    """The player's character, at the middle, facing -z."""
    var view: ThirdPersonControls
    """The camera, looking along -z."""
    var battle: Battle
    """The fight."""

    def __init__(out self, parameters: BattleParameters) raises:
        """Build a fight on flat ground.

        Args:
            parameters: Who fights.

        Raises:
            Error: If a fighter cannot be built.
        """
        self.assets = Assets()
        self.scene = Scene()
        self.body = Body(
            self.scene,
            self.assets,
            HumanoidSpec(Length(60.0, INCH), FEMALE),
            Outfit(),
            500,
            8,
        )
        self.terrain = Terrain(flat_ground())
        self.player = Character(
            CharacterParameters(), 0, 0, Angle(0.0, RADIAN), self.terrain
        )
        self.view = ThirdPersonControls(Angle(0.0, RADIAN))
        var looks = house_looks(self.assets, 4, 1)
        self.battle = Battle(
            self.scene,
            self.assets,
            parameters,
            looks,
            self.terrain,
            List[Lot](),
            self.body,
            self.player.position,
            500,
            8,
        )

    def tick(mut self, input: MoveInput, seconds: Float32 = 0.05) raises:
        """Run the fight for one frame.

        Args:
            input: The player's input.
            seconds: The frame's time.

        Raises:
            Error: If the fight cannot move on.
        """
        self.battle.tick(
            self.scene,
            input,
            self.view,
            self.player,
            self.body,
            self.terrain,
            List[Obstacle](),
            Duration(seconds, SECOND),
        )

    def run(mut self, seconds: Float32, input: MoveInput = no_input()) raises:
        """Run the fight for a time, in frames of a twentieth of a second.

        Args:
            seconds: How long.
            input: The input held all the while.

        Raises:
            Error: If the fight cannot move on.
        """
        for _ in range(Int(seconds * 20 + 0.5)):
            self.tick(input)

    def press(mut self, input: MoveInput) raises:
        """Hold an input for a frame, and let go for a frame.

        Args:
            input: The input.

        Raises:
            Error: If the fight cannot move on.
        """
        self.tick(input)
        self.tick(no_input())


def popup_texts(battle: Battle) -> List[String]:
    """Return the text of each number and word that shows.

    Args:
        battle: The fight.

    Returns:
        The texts, oldest first.
    """
    var out = List[String]()
    for popup in battle.popups:
        out.append(popup.text)
    return out^


def holds_text(texts: List[String], text: String) -> Bool:
    """Return whether a list holds a text.

    Args:
        texts: The list.
        text: The text.

    Returns:
        Whether some entry equals it.
    """
    for t in texts:
        if t == text:
            return True
    return False
