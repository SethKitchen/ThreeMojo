# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What plays a clip and writes it into the scene, from three.js
`src/animation/AnimationMixer.js` and `AnimationAction.js`.

An `AnimationAction` is one clip being played: where it has got to, how
fast, whether it repeats, and how much of it to use. An `AnimationMixer`
holds the actions, moves them all on by one frame's worth of time, and
sets the nodes.

## Why the mixer and not each action writes

Two actions can drive one node at once, and that is the whole reason a
mixer exists. Walking at a weight of one and waving at a weight of one
half is one pose, not two, and the node can only be set once. So every
action's value goes into a pile, one pile per node and property, and the
piles are written when every action has had its say.

A pile is a running average by weight, three.js's own arrangement in
`_mixBufferRegion`: the first value in is the pile, and every value after
it moves the pile a share of the way toward itself. That share is the new
weight over the weight so far plus the new weight, which leaves the pile
at the weighted mean however many values arrive and in whatever order.

A rotation moves along the arc rather than along the line, by `slerp`, for
the reason a rotation track is interpolated by `slerp`: the average of
four numbers is not the average of two turns.

## Looping

`ONCE` stops at the end and stays there, `REPEAT` starts over, and
`PING_PONG` runs back the way it came. A negative `time_scale` runs a clip
backward, and each of the three handles that the same way going the other
way. three.js has the same three, as `LoopOnce`, `LoopRepeat` and
`LoopPingPong`.

## What is refused

A weight below zero, which is not a share of anything. A loop mode that is
none of the three. An action index the mixer does not have. A clip of no
length is refused where clips are built, which is what lets the looping
divide by the length without asking.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import POSITION, QUATERNION, SCALE, TrackKind
from core.object3d import NodeId
from core.scene import Scene
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import floor
from units.si import Duration, SECOND

# How many numbers a pile holds: four, which is what the widest value, a
# rotation, needs. A position uses three of them and leaves the fourth.
comptime PILE = 4


@fieldwise_init
struct Loop(Equatable, ImplicitlyCopyable, Writable):
    """What an action does when it reaches the end of its clip, as a type
    rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three loop modes there are."""
        return self == ONCE or self == REPEAT or self == PING_PONG


# Stop at the end and stay there: three.js's `LoopOnce`.
comptime ONCE = Loop(0)
# Start over: three.js's `LoopRepeat`.
comptime REPEAT = Loop(1)
# Run back the way it came: three.js's `LoopPingPong`.
comptime PING_PONG = Loop(2)


def find_pile(nodes: List[Int], kinds: List[Int], node: Int, kind: Int) -> Int:
    """Return where the pile for one node's one property is, or minus one
    when nothing has been put there yet.

    A list walked through rather than a table looked up: a frame has one
    pile per node per property that an action touches, which is a handful,
    and a handful is quicker walked than hashed.

    Args:
        nodes: Which node each pile is for.
        kinds: Which property each pile is for.
        node: The node wanted.
        kind: The property wanted.

    Returns:
        The pile's place in the lists, or minus one.
    """
    for slot in range(len(nodes)):  # pragma: no branch
        if nodes[slot] == node:
            if kinds[slot] == kind:
                return slot
    return -1


def mix_into_pile(
    mut piles: List[Float32],
    slot: Int,
    so_far: Float32,
    share: Float32,
    value: List[Float32],
    kind: TrackKind,
):
    """Move one pile a share of the way toward `value`.

    The share is `share` over `so_far` plus `share`, which is what leaves
    the pile at the mean weighted by every contribution it has had.

    Args:
        piles: Every pile's numbers, `PILE` of them each.
        slot: Which pile.
        so_far: How much weight the pile already holds.
        share: How much weight this value brings.
        value: The value, its own numbers alone.
        kind: Which property, which decides whether the move is along a
            line or along an arc.
    """
    var part = share / (so_far + share)
    var at = slot * PILE
    if kind == QUATERNION:
        var mixed = Quaternion(
            piles[at], piles[at + 1], piles[at + 2], piles[at + 3]
        ).slerp(Quaternion(value[0], value[1], value[2], value[3]), part)
        piles[at] = mixed.x
        piles[at + 1] = mixed.y
        piles[at + 2] = mixed.z
        piles[at + 3] = mixed.w
        return
    for offset in range(len(value)):  # pragma: no branch
        piles[at + offset] += (value[offset] - piles[at + offset]) * part


struct AnimationAction(Copyable, Movable):
    """One clip being played: where it has got to, and how much of it to
    use."""

    var clip: AnimationClip
    var loop: Loop
    # How far into the clip the action has got, in seconds.
    var time: Float32
    # How much of this action goes into the pose, three.js's `weight`.
    var weight: Float32
    # How fast the clip runs, and which way. Negative runs it backward.
    var time_scale: Float32
    var playing: Bool

    def __init__(
        out self,
        var clip: AnimationClip,
        loop: Loop = REPEAT,
        weight: Float32 = 1,
        time_scale: Float32 = 1,
    ) raises:
        """Create an action on a clip, stopped at its start.

        Args:
            clip: The clip to play, consumed.
            loop: What to do at the end; `REPEAT` by default, as three.js
                has it.
            weight: How much of this action goes into the pose; not
                negative.
            time_scale: How fast the clip runs. One is its own speed, two
                is twice as fast, and a negative number runs it backward.

        Raises:
            Error: If the loop mode is none of the three, or the weight is
                negative.
        """
        if not loop.is_valid():
            raise Error("An action needs a loop mode that exists")
        if weight < 0:
            raise Error("An action's weight cannot be negative")
        self.clip = clip^
        self.loop = loop
        self.time = 0
        self.weight = weight
        self.time_scale = time_scale
        self.playing = False

    def __init__(out self, *, copy: Self):
        """Copy another action, its clip included."""
        self.clip = AnimationClip(copy=copy.clip)
        self.loop = copy.loop
        self.time = copy.time
        self.weight = copy.weight
        self.time_scale = copy.time_scale
        self.playing = copy.playing

    def play(mut self):
        """Start the action from where it is, three.js's `play`."""
        self.playing = True

    def pause(mut self):
        """Stop the action where it is, three.js's `paused`."""
        self.playing = False

    def stop(mut self):
        """Stop the action and rewind it, three.js's `stop`."""
        self.playing = False
        self.time = 0

    def is_playing(self) -> Bool:
        """Return True if the mixer will move this action on."""
        return self.playing

    def at(self) -> Duration:
        """Return how far into the clip the action has got."""
        return Duration(self.time, SECOND)

    def set_weight(mut self, weight: Float32) raises:
        """Set how much of this action goes into the pose.

        Args:
            weight: The new weight; not negative.

        Raises:
            Error: If the weight is negative.
        """
        if weight < 0:
            raise Error("An action's weight cannot be negative")
        self.weight = weight

    def advance(mut self, seconds: Float32):
        """Move the action on by `seconds` of real time, and handle the end
        of the clip the way its loop mode says.

        A clip lasts longer than no time, which `AnimationClip` has already
        made sure of, so dividing by its length is safe here.

        Args:
            seconds: How much real time has passed. It is multiplied by
                `time_scale`, so this can move the action either way.
        """
        var length = self.clip.duration().to(SECOND)
        var moved = self.time + seconds * self.time_scale
        if self.loop == ONCE:
            if moved >= length:
                moved = length
                self.playing = False
            if moved < 0:
                moved = 0
                self.playing = False
        elif self.loop == REPEAT:
            moved -= floor(moved / length) * length
        else:
            var there_and_back = length * 2
            moved -= floor(moved / there_and_back) * there_and_back
            if moved > length:
                moved = there_and_back - moved
        self.time = moved


struct AnimationMixer(Movable):
    """The actions playing, and what writes their pose into a scene."""

    var actions: List[AnimationAction]
    # How much time the mixer has been given, in seconds.
    var elapsed: Float32

    def __init__(out self):
        """Create a mixer with nothing playing."""
        self.actions = List[AnimationAction]()
        self.elapsed = 0

    def add(mut self, var action: AnimationAction) -> Int:
        """Add an action and return the index it was given.

        Args:
            action: The action, consumed. three.js's `clipAction` makes one
                and remembers it; here the caller makes it and this keeps
                it.

        Returns:
            Which action it is, for `action`.
        """
        self.actions.append(action^)
        return len(self.actions) - 1

    def action_count(self) -> Int:
        """Return how many actions the mixer holds."""
        return len(self.actions)

    def action(
        mut self, index: Int
    ) raises -> ref[origin_of(self.actions[0])] AnimationAction:
        """Return one action, for playing, stopping or reweighting.

        Args:
            index: Which action, as `add` returned it.

        Returns:
            A reference to it.

        Raises:
            Error: If there is no action at that index.
        """
        if index < 0 or index >= len(self.actions):
            raise Error("The mixer has no action at that index")
        return self.actions[index]

    def time(self) -> Duration:
        """Return how much time the mixer has been given in all."""
        return Duration(self.elapsed, SECOND)

    def update(mut self, mut scene: Scene, delta: Duration) raises:
        """Move every playing action on by `delta`, and write the pose the
        actions make into the scene.

        Args:
            scene: The scene whose nodes the tracks name.
            delta: How much real time has passed since the last update.

        Raises:
            Error: If a track names a node the scene does not have.
        """
        var seconds = delta.to(SECOND)
        self.elapsed += seconds

        var nodes = List[Int]()
        var kinds = List[Int]()
        var weights = List[Float32]()
        var piles = List[Float32]()

        for index in range(len(self.actions)):  # pragma: no branch
            if not self.actions[index].playing:
                continue
            self.actions[index].advance(seconds)
            var share = self.actions[index].weight
            if share <= 0:
                continue
            var at = self.actions[index].at()
            for which in range(
                self.actions[index].clip.track_count()
            ):  # pragma: no branch
                var node = self.actions[index].clip.tracks[which].node.value
                var kind = self.actions[index].clip.tracks[which].kind
                var value = self.actions[index].clip.tracks[which].sample(at)
                var slot = find_pile(nodes, kinds, node, kind.value)
                if slot < 0:
                    nodes.append(node)
                    kinds.append(kind.value)
                    weights.append(share)
                    for offset in range(PILE):  # pragma: no branch
                        if offset < len(value):
                            piles.append(value[offset])
                        else:
                            piles.append(0)
                    continue
                mix_into_pile(piles, slot, weights[slot], share, value, kind)
                weights[slot] += share

        for slot in range(len(nodes)):  # pragma: no branch
            if nodes[slot] >= scene.count():
                raise Error("A track must name a node that is in the scene")
            var at = slot * PILE
            ref node = scene.node(NodeId(nodes[slot]))
            if kinds[slot] == POSITION.value:
                node.position = Vector3(piles[at], piles[at + 1], piles[at + 2])
            elif kinds[slot] == SCALE.value:
                node.scale = Vector3(piles[at], piles[at + 1], piles[at + 2])
            else:
                node.quaternion = Quaternion(
                    piles[at], piles[at + 1], piles[at + 2], piles[at + 3]
                )
