# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A person's weapons, and the clips that a `Body` plays as it fights.

`Arms` adds the clips of `extensions.humanoid.rig.sword_clips` and
`extensions.humanoid.rig.style_clips` to a body's mixer, and hangs the
weapon of each fighting style it carries: in the hand, and stowed. See
`extensions.village.blade` and `extensions.village.weapons`. `Arms.pose`
stands the body where its character stands, and picks what it plays from
its `Fighter` and the fighter's style:

1. A fighter that makes a move plays that move's clip in its style, from
   its start. A move that starts again, such as a second dodge, starts its
   clip again. A move slowed by the stance or the style plays its clip as
   much slower.
2. A free fighter that guards plays its style's guard.
3. A free fighter with its weapon drawn, standing, plays its style's ready
   stance.
4. Any other plays its stance's clip, as `Body.pose` does.

| Style | Its own clips | Held in | Stowed |
|---|---|---|---|
| Hand to hand | A jab, a cross, a kick, a haymaker, an uppercut, a spinning heel kick and a ground punch; the fists' stance and guard | Nothing | Nothing |
| Sword | The sword clips | The weapon hand | At the hip, in the scabbard |
| Axe | The sword clips | The weapon hand | At the other hip |
| Mace | The sword clips | The weapon hand | At the other hip |
| Magic | A bolt, a blast, a nova and a mend; the staff's stance | The weapon hand | Across the back |
| Archery | A quick shot, an aimed shot, a volley, a leap shot and a rain; the bow's stance | The other hand | Across the back |

A move a style has no clip of plays the sword's. A clip fades in over
`QUICK_FADE`, and back to the body's own clips over the body's fade. The
weapon in the hand shows while it is drawn, and the stowed one while it is
not. The scabbard always shows on a body that carries a sword.
"""

from animation.animation_clip import AnimationClip
from animation.animation_mixer import ONCE, AnimationAction
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.rig.joints import CHEST, HIPS, LEFT_HAND, RIGHT_HAND
from extensions.humanoid.rig.giant_clips import (
    giant_call_clip,
    giant_charge_clip,
    giant_cleave_clip,
    giant_roar_clip,
    giant_slam_clip,
    giant_stomp_clip,
)
from extensions.humanoid.rig.style_clips import (
    aimed_shot_clip,
    bow_ready_clip,
    cross_clip,
    fists_guard_clip,
    fists_ready_clip,
    ground_punch_clip,
    haymaker_clip,
    jab_clip,
    kick_clip,
    leap_shot_clip,
    mend_clip,
    nova_clip,
    quick_shot_clip,
    rain_clip,
    spin_kick_clip,
    staff_blast_clip,
    staff_bolt_clip,
    staff_ready_clip,
    uppercut_clip,
    volley_clip,
)
from extensions.humanoid.rig.sword_clips import (
    pierce_clip,
    cast_clip,
    dodge_clip,
    ground_wave_clip,
    fall_clip,
    flinch_clip,
    guard_clip,
    heavy_clip,
    light_one_clip,
    light_three_clip,
    light_two_clip,
    ultimate_clip,
    plunge_clip,
    ready_clip,
    rising_edge_clip,
    stagger_clip,
    whirlwind_clip,
    throw_clip,
)
from extensions.village.blade import SwordLooks, add_scabbard, add_sword
from extensions.village.character import STANDING, Character
from extensions.village.combat import (
    AIMED_SHOT,
    ARROW_RAIN,
    LEAP_SHOT,
    MEND,
    NOVA,
    PIERCE,
    CAST,
    GROUND_WAVE,
    DODGE,
    FALL,
    FLINCH,
    HEAVY,
    LIGHT_ONE,
    LIGHT_THREE,
    LIGHT_TWO,
    MOVES,
    QUICK_SHOT,
    SPELL_BLAST,
    SPELL_BOLT,
    ULTIMATE,
    PLUNGE,
    RISING_EDGE,
    STAGGER,
    VOLLEY,
    WHIRLWIND,
    THROW,
    CombatMove,
    Fighter,
)
from extensions.village.residents import FADE, Body, clip_of, facing_turn
from extensions.village.styles import (
    ARCHERY,
    AXE,
    HAND_TO_HAND,
    MACE,
    MAGIC,
    STYLES,
    SWORD,
    FightingStyle,
)
from extensions.village.weapons import add_weapon
from math.vector3 import Vector3
from units.si import SECOND, Duration

comptime QUICK_FADE = Duration(0.08, SECOND)
"""How long a weapon's clip takes to fade in."""


def _once(mut body: Body, var clip: AnimationClip) raises -> Int:
    """Add a clip that plays once and holds its last pose; return its
    action."""
    var action = body.mixer.add(AnimationAction(clip^))
    body.mixer.action(action).set_loop(ONCE)
    body.mixer.action(action).clamp_when_finished = True
    return action


struct Arms(Movable):
    """A body's weapons and its fighting clips, and which clip plays."""

    # The mixer's action for each style's move, at `style * MOVES + move`,
    # or -1 for `FREE` and for a beast's bite; and each style's ready
    # stance and guard.
    var table: List[Int]
    var readies: List[Int]
    var guards: List[Int]
    # Whether the body carries each style's weapon, and the nodes of the
    # weapon in the hand and stowed; the fists' are empty nodes.
    var armed: List[Bool]
    var held: List[NodeId]
    var stowed: List[NodeId]
    # The scabbard, or the hips if the body carries no sword.
    var scabbard: NodeId
    # The action of the clip that plays, or -1 while the body plays its
    # own clips.
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
        styles: List[FightingStyle] = [SWORD],
        giant: Bool = False,
    ) raises:
        """Add the fighting clips to a body, and hang its weapons.

        Args:
            scene: The scene the body is in.
            assets: The stores for the weapons' geometries.
            body: The body. Its mixer gets the clips.
            looks: The weapons' materials.
            steel: The sword's blade's color.
            styles: The styles whose weapons and clips the body carries.
            giant: Whether the body is a raid boss's: it plays a giant's
                clips for the moves that stand in for its attacks.

        Raises:
            Error: If a style is not one, or a clip or a weapon cannot be
                built.
        """
        ref bones = body.person.bones
        ref rig = body.person.rig
        var scale = rig.stature / Float32(1.8288)
        var sword = List[Int](length=MOVES, fill=-1)
        sword[LIGHT_ONE.value] = _once(body, light_one_clip(bones, rig))
        sword[LIGHT_TWO.value] = _once(body, light_two_clip(bones, rig))
        sword[LIGHT_THREE.value] = _once(body, light_three_clip(bones, rig))
        sword[HEAVY.value] = _once(body, heavy_clip(bones, rig))
        sword[RISING_EDGE.value] = _once(body, rising_edge_clip(bones, rig))
        sword[WHIRLWIND.value] = _once(body, whirlwind_clip(bones, rig))
        sword[GROUND_WAVE.value] = _once(body, ground_wave_clip(bones, rig))
        sword[ULTIMATE.value] = _once(body, ultimate_clip(bones, rig))
        sword[PLUNGE.value] = _once(body, plunge_clip(bones, rig))
        sword[PIERCE.value] = _once(body, pierce_clip(bones, rig))
        sword[CAST.value] = _once(body, cast_clip(bones, rig))
        sword[THROW.value] = _once(body, throw_clip(bones, rig))
        sword[DODGE.value] = _once(body, dodge_clip(bones, rig))
        sword[FLINCH.value] = _once(body, flinch_clip(bones, rig))
        sword[STAGGER.value] = _once(body, stagger_clip(bones, rig))
        sword[FALL.value] = _once(body, fall_clip(bones, rig))
        # A spell or a shot that a style has no clip of casts as the sword
        # casts.
        for move in [
            SPELL_BOLT,
            SPELL_BLAST,
            NOVA,
            MEND,
            QUICK_SHOT,
            AIMED_SHOT,
            VOLLEY,
            LEAP_SHOT,
            ARROW_RAIN,
        ]:  # pragma: no branch
            sword[move.value] = sword[CAST.value]
        var ready = body.mixer.add(AnimationAction(ready_clip(bones, rig)))
        var guard = body.mixer.add(AnimationAction(guard_clip(bones, rig)))
        self.table = List[Int]()
        for _ in range(STYLES):  # pragma: no branch
            self.table.extend(sword.copy())
        self.readies = List[Int](length=STYLES, fill=ready)
        self.guards = List[Int](length=STYLES, fill=guard)
        self.armed = List[Bool](length=STYLES, fill=False)
        self.held = List[NodeId]()
        self.stowed = List[NodeId]()
        ref hips = bones[HIPS.value]
        for _ in range(STYLES):  # pragma: no branch
            self.held.append(hips)
            self.stowed.append(hips)
        self.scabbard = hips
        self.showing = -1
        self.seen = FALL
        self.seen_clock = 0
        for style in styles:
            if not style.is_valid():
                raise Error("A body's styles must each be one of the six")
            if self.armed[style.value]:
                continue
            self.armed[style.value] = True
            self._arm(scene, assets, body, looks, steel, style, scale)
        if giant:
            self._giant(body)

    def _giant(mut self, mut body: Body) raises:
        """Play a giant's clips, in each style, for the moves that stand in
        for a boss's attacks: see `extensions.village.raid.puppet_move`."""
        ref bones = body.person.bones
        ref rig = body.person.rig
        var cleave = _once(body, giant_cleave_clip(bones, rig))
        var slam = _once(body, giant_slam_clip(bones, rig))
        var stomp = _once(body, giant_stomp_clip(bones, rig))
        var charge = _once(body, giant_charge_clip(bones, rig))
        var call = _once(body, giant_call_clip(bones, rig))
        var roar = _once(body, giant_roar_clip(bones, rig))
        for k in range(STYLES):  # pragma: no branch
            var style = FightingStyle(k)
            self._set(style, HEAVY, cleave)
            self._set(style, PLUNGE, slam)
            self._set(style, GROUND_WAVE, stomp)
            self._set(style, PIERCE, charge)
            self._set(style, CAST, call)
            self._set(style, MEND, roar)

    def _set(mut self, style: FightingStyle, move: CombatMove, action: Int):
        """Play an action for a style's move."""
        self.table[style.value * MOVES + move.value] = action

    def _arm(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        mut body: Body,
        looks: SwordLooks,
        steel: Vector3,
        style: FightingStyle,
        scale: Float32,
    ) raises:
        """Hang one style's weapons, and add its own clips."""
        ref bones = body.person.bones
        ref rig = body.person.rig
        if style == SWORD:
            self.held[style.value] = add_sword(
                scene,
                assets,
                looks,
                bones[LEFT_HAND.value],
                scale,
                steel,
                False,
            )
            self.stowed[style.value] = add_sword(
                scene, assets, looks, bones[HIPS.value], scale, steel, True
            )
            self.scabbard = add_scabbard(
                scene, assets, looks, bones[HIPS.value], scale
            )
        elif style == HAND_TO_HAND:
            self.held[style.value] = scene.attach(
                Object3D(), bones[LEFT_HAND.value]
            )
            self.stowed[style.value] = scene.attach(
                Object3D(), bones[HIPS.value]
            )
            self._set(style, LIGHT_ONE, _once(body, jab_clip(bones, rig)))
            self._set(style, LIGHT_TWO, _once(body, cross_clip(bones, rig)))
            self._set(style, LIGHT_THREE, _once(body, kick_clip(bones, rig)))
            self._set(style, HEAVY, _once(body, haymaker_clip(bones, rig)))
            self._set(
                style, RISING_EDGE, _once(body, uppercut_clip(bones, rig))
            )
            self._set(style, WHIRLWIND, _once(body, spin_kick_clip(bones, rig)))
            var punch = _once(body, ground_punch_clip(bones, rig))
            self._set(style, GROUND_WAVE, punch)
            self._set(style, PLUNGE, punch)
            self.readies[style.value] = body.mixer.add(
                AnimationAction(fists_ready_clip(bones, rig))
            )
            self.guards[style.value] = body.mixer.add(
                AnimationAction(fists_guard_clip(bones, rig))
            )
        elif style == MAGIC:
            self.held[style.value] = add_weapon(
                scene,
                assets,
                looks,
                bones[LEFT_HAND.value],
                scale,
                style,
                False,
            )
            self.stowed[style.value] = add_weapon(
                scene, assets, looks, bones[CHEST.value], scale, style, True
            )
            self._set(
                style, SPELL_BOLT, _once(body, staff_bolt_clip(bones, rig))
            )
            self._set(
                style, SPELL_BLAST, _once(body, staff_blast_clip(bones, rig))
            )
            self._set(style, NOVA, _once(body, nova_clip(bones, rig)))
            self._set(style, MEND, _once(body, mend_clip(bones, rig)))
            self.readies[style.value] = body.mixer.add(
                AnimationAction(staff_ready_clip(bones, rig))
            )
        elif style == ARCHERY:
            self.held[style.value] = add_weapon(
                scene,
                assets,
                looks,
                bones[RIGHT_HAND.value],
                scale,
                style,
                False,
            )
            self.stowed[style.value] = add_weapon(
                scene, assets, looks, bones[CHEST.value], scale, style, True
            )
            self._set(
                style, QUICK_SHOT, _once(body, quick_shot_clip(bones, rig))
            )
            self._set(
                style, AIMED_SHOT, _once(body, aimed_shot_clip(bones, rig))
            )
            self._set(style, VOLLEY, _once(body, volley_clip(bones, rig)))
            self._set(style, LEAP_SHOT, _once(body, leap_shot_clip(bones, rig)))
            self._set(style, ARROW_RAIN, _once(body, rain_clip(bones, rig)))
            var bow = body.mixer.add(
                AnimationAction(bow_ready_clip(bones, rig))
            )
            self.readies[style.value] = bow
            self.guards[style.value] = bow
        else:
            self.held[style.value] = add_weapon(
                scene,
                assets,
                looks,
                bones[LEFT_HAND.value],
                scale,
                style,
                False,
            )
            self.stowed[style.value] = add_weapon(
                scene, assets, looks, bones[HIPS.value], scale, style, True
            )

    def clip_for(
        self, character: Character, fighter: Fighter, drawn: Bool
    ) -> Int:
        """Return the fighting clip that a body plays, or -1 for its own.

        Args:
            character: Where the body stands, and its stance.
            fighter: What the body does in a fight, and its style.
            drawn: Whether its weapon is drawn.

        Returns:
            The action of the fighter's move in its style; else of the
            style's guard, for a fighter that guards; else of the style's
            ready stance, for a drawn weapon and a standing character; else
            -1.
        """
        var style = fighter.style.value
        if not fighter.free():
            return self.table[style * MOVES + fighter.move.value]
        if fighter.guarding:
            return self.guards[style]
        if drawn and character.stance == STANDING:
            return self.readies[style]
        return -1

    def show(
        mut self, mut scene: Scene, style: FightingStyle, drawn: Bool
    ) raises:
        """Show the weapon of a style in the hand while it is drawn, and
        stowed while it is not. The other styles' weapons are put away.

        Args:
            scene: The scene the body is in.
            style: The style the fighter fights in.
            drawn: Whether its weapon is drawn.

        Raises:
            Error: Never: each weapon's node is in the scene.
        """
        for k in range(STYLES):  # pragma: no branch
            if not self.armed[k]:
                continue
            var mine = k == style.value
            scene.node(self.held[k]).visible = drawn and mine
            scene.node(self.stowed[k]).visible = mine and not drawn

    def place(self, mut scene: Scene, body: Body, character: Character) raises:
        """Stand the body where its character stands, and turn it the way it
        faces, without playing its clips: for a body posed less often.

        Args:
            scene: The scene the body is in.
            body: The body that `__init__` armed.
            character: The character the body shows.

        Raises:
            Error: Never: the body's carrier is in the scene.
        """
        ref node = scene.node(body.carrier)
        var at = character.position
        node.set_position(at.x, at.y + body.lift, at.z)
        node.set_rotation_from_axis_angle(
            Vector3(0, 1, 0), facing_turn(character.heading)
        )

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
            drawn: Whether the weapon is drawn: in the hand, not stowed.
            delta: The frame's time.

        Raises:
            Error: If the time is negative, or a clip cannot be played.
        """
        self.show(scene, fighter.style, drawn)
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
