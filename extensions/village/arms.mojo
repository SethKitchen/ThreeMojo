# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A person's sword, and the sword clips that a `Body` plays as it fights.

`Arms` adds the clips of `extensions.humanoid.rig.sword_clips` to a body's
mixer, hangs a sword in the hand and another at the hip, and a scabbard.
`Arms.pose` stands the body where its character stands, and picks what
it plays from its `Fighter`:

1. A fighter that makes a move plays that move's clip, from its start.
   A move that starts again, such as a second dodge, starts its clip
   again. A move slowed by the stance plays its clip as much slower.
2. A free fighter that guards plays the guard.
3. A free fighter with its sword drawn, standing, plays the ready stance.
4. Any other plays its stance's clip, as `Body.pose` does.

A sword clip fades in over `QUICK_FADE`, and back to the body's own clips
over the body's fade. The sword in the hand shows while the sword is
drawn, and the sword at the hip while it is not. The scabbard always
shows.
"""

from animation.animation_mixer import ONCE, AnimationAction
from core.assets import Assets
from core.object3d import NodeId
from core.scene import Scene
from extensions.humanoid.rig.joints import HIPS, LEFT_HAND
from extensions.humanoid.rig.sword_clips import (
    burst_clip,
    cast_clip,
    dodge_clip,
    fang_clip,
    fall_clip,
    flinch_clip,
    guard_clip,
    heavy_clip,
    light_one_clip,
    light_three_clip,
    light_two_clip,
    mystic_clip,
    plunge_clip,
    ready_clip,
    rising_edge_clip,
    stagger_clip,
    tempest_clip,
    throw_clip,
)
from extensions.village.blade import SwordLooks, add_scabbard, add_sword
from extensions.village.character import STANDING, Character
from extensions.village.combat import (
    BURST,
    CAST,
    DEMON_FANG,
    DODGE,
    FALL,
    FLINCH,
    HEAVY,
    LIGHT_ONE,
    LIGHT_THREE,
    LIGHT_TWO,
    MOVES,
    MYSTIC_ARTE,
    PLUNGE,
    RISING_EDGE,
    STAGGER,
    TEMPEST,
    THROW,
    CombatMove,
    Fighter,
)
from extensions.village.residents import FADE, Body, clip_of, facing_turn
from math.vector3 import Vector3
from units.si import SECOND, Duration

comptime QUICK_FADE = Duration(0.08, SECOND)
"""How long a sword clip takes to fade in."""


struct Arms(Movable):
    """A body's swords and its sword clips, and which clip plays."""

    # The mixer's action for each move, by the move's value, or -1 for
    # `FREE` and for a beast's bite; and the ready stance's and the
    # guard's.
    var moves: List[Int]
    var ready: Int
    var guard: Int
    # The sword in the hand, the sword at the hip, and the scabbard.
    var held: NodeId
    var sheathed: NodeId
    var scabbard: NodeId
    # The action of the sword clip that plays, or -1 while the body plays
    # its own clips.
    var showing: Int
    # The move last shown, and how far into it the fighter was then, in
    # seconds: a clock that runs back starts the move's clip again.
    var seen: CombatMove
    var seen_clock: Float32

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        mut body: Body,
        looks: SwordLooks,
        steel: Vector3,
    ) raises:
        """Add the sword clips to a body, and hang its swords.

        Args:
            scene: The scene the body is in.
            assets: The stores for the swords' geometries.
            body: The body. Its mixer gets the sword clips.
            looks: The swords' materials.
            steel: The blades' color.

        Raises:
            Error: If a clip or a sword cannot be built.
        """
        ref bones = body.person.bones
        ref rig = body.person.rig
        var scale = rig.stature / Float32(1.8288)
        self.moves = List[Int](length=MOVES, fill=-1)
        self.moves[LIGHT_ONE.value] = body.mixer.add(
            AnimationAction(light_one_clip(bones, rig))
        )
        self.moves[LIGHT_TWO.value] = body.mixer.add(
            AnimationAction(light_two_clip(bones, rig))
        )
        self.moves[LIGHT_THREE.value] = body.mixer.add(
            AnimationAction(light_three_clip(bones, rig))
        )
        self.moves[HEAVY.value] = body.mixer.add(
            AnimationAction(heavy_clip(bones, rig))
        )
        self.moves[RISING_EDGE.value] = body.mixer.add(
            AnimationAction(rising_edge_clip(bones, rig))
        )
        self.moves[TEMPEST.value] = body.mixer.add(
            AnimationAction(tempest_clip(bones, rig))
        )
        self.moves[DEMON_FANG.value] = body.mixer.add(
            AnimationAction(fang_clip(bones, rig))
        )
        self.moves[MYSTIC_ARTE.value] = body.mixer.add(
            AnimationAction(mystic_clip(bones, rig))
        )
        self.moves[PLUNGE.value] = body.mixer.add(
            AnimationAction(plunge_clip(bones, rig))
        )
        self.moves[BURST.value] = body.mixer.add(
            AnimationAction(burst_clip(bones, rig))
        )
        self.moves[CAST.value] = body.mixer.add(
            AnimationAction(cast_clip(bones, rig))
        )
        self.moves[THROW.value] = body.mixer.add(
            AnimationAction(throw_clip(bones, rig))
        )
        self.moves[DODGE.value] = body.mixer.add(
            AnimationAction(dodge_clip(bones, rig))
        )
        self.moves[FLINCH.value] = body.mixer.add(
            AnimationAction(flinch_clip(bones, rig))
        )
        self.moves[STAGGER.value] = body.mixer.add(
            AnimationAction(stagger_clip(bones, rig))
        )
        self.moves[FALL.value] = body.mixer.add(
            AnimationAction(fall_clip(bones, rig))
        )
        # Every move's clip plays once, and holds its last pose.
        for action in self.moves:  # pragma: no branch
            if action >= 0:
                body.mixer.action(action).set_loop(ONCE)
                body.mixer.action(action).clamp_when_finished = True
        self.ready = body.mixer.add(AnimationAction(ready_clip(bones, rig)))
        self.guard = body.mixer.add(AnimationAction(guard_clip(bones, rig)))
        self.held = add_sword(
            scene, assets, looks, bones[LEFT_HAND.value], scale, steel, False
        )
        self.sheathed = add_sword(
            scene, assets, looks, bones[HIPS.value], scale, steel, True
        )
        self.scabbard = add_scabbard(
            scene, assets, looks, bones[HIPS.value], scale
        )
        scene.node(self.held).visible = False
        self.showing = -1
        self.seen = FALL
        self.seen_clock = 0

    def clip_for(
        self, character: Character, fighter: Fighter, drawn: Bool
    ) -> Int:
        """Return the sword clip that a body plays, or -1 for its own.

        Args:
            character: Where the body stands, and its stance.
            fighter: What the body does in a fight.
            drawn: Whether its sword is drawn.

        Returns:
            The action of the fighter's move; else of the guard, for a
            fighter that guards; else of the ready stance, for a drawn
            sword and a standing character; else -1.
        """
        if not fighter.free():
            return self.moves[fighter.move.value]
        if fighter.guarding:
            return self.guard
        if drawn and character.stance == STANDING:
            return self.ready
        return -1

    def pose(
        mut self,
        mut scene: Scene,
        mut body: Body,
        character: Character,
        fighter: Fighter,
        drawn: Bool,
        delta: Duration,
    ) raises:
        """Stand the body where its character stands, and play what its
        fighter does.

        Args:
            scene: The scene the body is in.
            body: The body that `__init__` armed.
            character: The character the body shows.
            fighter: What the body does in a fight.
            drawn: Whether the sword is drawn: in the hand, not at the hip.
            delta: The frame's time.

        Raises:
            Error: If the time is negative, or a clip cannot be played.
        """
        scene.node(self.held).visible = drawn
        scene.node(self.sheathed).visible = not drawn
        var want = self.clip_for(character, fighter, drawn)
        var again = (
            fighter.move == self.seen
            and fighter.clock < self.seen_clock
            and not fighter.free()
        )
        self.seen = fighter.move
        self.seen_clock = fighter.clock
        if want < 0:
            if self.showing >= 0:
                # Back to the body's own clip of its stance.
                var back = body.actions[clip_of(character.stance)]
                body.mixer.action(back).reset()
                body.mixer.action(back).play()
                body.mixer.cross_fade_from(back, self.showing, FADE)
                body.playing = character.stance
                self.showing = -1
            body.pose(scene, character, delta)
            return
        if want != self.showing or again:
            var last = self.showing
            if last < 0:
                last = body.actions[clip_of(body.playing)]
            body.mixer.action(want).reset()
            body.mixer.action(want).play()
            if last != want:
                body.mixer.cross_fade_from(want, last, QUICK_FADE)
            self.showing = want
        body.mixer.action(want).time_scale = 1 / fighter.pace
        ref node = scene.node(body.carrier)
        var at = character.position
        node.set_position(at.x, at.y + body.lift, at.z)
        node.set_rotation_from_axis_angle(
            Vector3(0, 1, 0), facing_turn(character.heading)
        )
        body.mixer.update(scene, delta)
