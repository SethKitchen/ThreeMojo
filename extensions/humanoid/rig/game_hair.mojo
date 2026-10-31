# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A game humanoid's strand hair in motion, stepped and shaded each frame.

`add_game_humanoid` grows strands when it is given guides, and cards when
it is given cards. They hang from the head's bone, in the pelvis frame,
as the hair's shell does. `GameHairMotion` moves them as the person
moves:

1. It reads where the head's bone is in the world, and carries each loose
   point of every strand through the head's move since the last frame.
   So the hair lags as the head starts, swings as it stops, and sways as
   it turns. See `HairSimulation.carry`.
2. It turns gravity, the wind, the lights and the camera into the head's
   frame, so the hair falls toward the ground and is lit from where the
   lights are.
3. It steps the strands against the head and the body, writes them, and
   shades them. A groom of cards writes its moved strands into its
   ribbons.

A groom that a helmet or a hood hides is not moved or shaded. It costs
nothing until it shows again.

This is not a three.js port. See Extensions.

    var person = add_game_humanoid(scene, assets, root, spec, 20000,
        cards=600)
    var motion = GameHairMotion(scene, person, spec)
    # Each frame, after the mixer and `scene.update()`:
    motion.update(scene, assets, person, lights, eye, ambient, wind)
"""

from core.assets import Assets
from core.object3d import NodeId
from core.scene import Scene
from extensions.humanoid.rig.game import GameHumanoid
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.hair.groom import HairBody
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.simulation import (
    HairSimulation,
    HairWind,
)
from extensions.humanoid.spec import HumanoidSpec
from math.matrix4 import Matrix4
from math.vector3 import Vector3


def _toward(back: Matrix4, direction: Vector3) -> Vector3:
    """Return a world direction in a frame, as a unit vector.

    Args:
        back: The frame's world matrix, inverted.
        direction: A direction in the world.

    Returns:
        The direction in the frame, of unit length, or the direction as
        it is if it has no length.
    """
    var turned = back.transform_direction(direction)
    if turned.length() == 0:
        return direction
    turned.normalize()
    return turned


struct GameHairMotion(Movable):
    """The motion of each groom of one game humanoid."""

    var simulations: List[HairSimulation]
    """One simulation per groom: those of `GameHumanoid.strands` in their
    order, then those of `GameHumanoid.cards`."""
    var poses: List[Matrix4]
    """Each groom's frame in the world when it was last moved."""
    var body: HairBody
    """What the hair falls against: the head's skin and the body's."""
    var steps: Int
    """How many simulation steps one update takes."""

    def __init__(
        out self,
        scene: Scene,
        person: GameHumanoid,
        spec: HumanoidSpec,
        guides_only: Bool = True,
        steps: Int = 1,
    ) raises:
        """Start each groom of a person at rest, where it was grown.

        Args:
            scene: The scene the person is in, updated.
            person: A game humanoid. One with no strands or cards has
                nothing to move.
            spec: The spec the person was built from.
            guides_only: True steps only the guide strands and lays each
                follower along its guide, for about a third of the cost.
            steps: Simulation steps per update, one or more. Each step is
                a thirtieth of a second.

        Raises:
            Error: If `steps` is below one, a groom has no node, the scene
                was not updated, or a groom is refused.
        """
        if steps < 1:
            raise Error("Hair motion needs one step an update or more")
        self.simulations = List[HairSimulation]()
        self.poses = List[Matrix4]()
        for k in range(len(person.strands)):
            ref hair = person.strands[k]
            if not hair.node:
                raise Error("A game humanoid's groom must hang from a node")
            self.simulations.append(
                HairSimulation(hair.groom, guides_only=guides_only)
            )
            self.poses.append(scene.world_matrix(hair.node.value()))
        for k in range(len(person.cards)):
            ref cards = person.cards[k]
            if not cards.node:
                raise Error("A game humanoid's cards must hang from a node")
            self.simulations.append(
                HairSimulation(cards.groom, guides_only=guides_only)
            )
            self.poses.append(scene.world_matrix(cards.node.value()))
        self.body = HairBody(head_muscle_dimensions(spec))
        self.steps = steps

    def update(
        mut self,
        scene: Scene,
        mut assets: Assets,
        mut person: GameHumanoid,
        lights: List[HairLight],
        camera: Vector3,
        ambient: Vector3,
        wind: HairWind,
    ) raises:
        """Move and shade each groom that shows, for one frame.

        Call it after the scene is updated for the frame.

        Args:
            scene: The scene, updated.
            assets: The store of the grooms' geometry.
            person: The person this motion was made for.
            lights: The distant lights, in the world.
            camera: Where the camera is, in the world.
            ambient: The light from all round, linear.
            wind: The wind, blowing in a world direction.

        Raises:
            Error: If the person has a different number of grooms, the
                scene was not updated, or a step, write or shade fails.
        """
        var strands = len(person.strands)
        if strands + len(person.cards) != len(self.simulations):
            raise Error("The hair motion was made for another person")
        for k in range(len(self.simulations)):
            var node: NodeId
            if k < strands:
                node = person.strands[k].node.value()
            else:
                node = person.cards[k - strands].node.value()
            if not scene.get(node).visible:
                continue
            var pose = scene.world_matrix(node)
            var back = pose.copy()
            back.invert()
            self.simulations[k].carry(back * self.poses[k])
            self.simulations[k].down = _toward(back, Vector3(0, -1, 0))
            self.poses[k] = pose^
            var local = wind
            local.direction = _toward(back, wind.direction)
            for _ in range(self.steps):  # pragma: no branch
                self.simulations[k].step(self.body, local)
            var seen = List[HairLight](capacity=len(lights))
            for light in lights:
                seen.append(
                    HairLight(_toward(back, light.direction), light.radiance)
                )
            var eye = back.transform_point(camera)
            if k < strands:
                self.simulations[k].write(person.strands[k].groom)
                person.strands[k].shade(assets, seen, eye, ambient)
            else:
                self.simulations[k].write(person.cards[k - strands].groom)
                person.cards[k - strands].shade(assets, seen, eye, ambient)
