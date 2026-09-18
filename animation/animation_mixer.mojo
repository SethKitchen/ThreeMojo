# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What plays a clip and writes it into the scene, from three.js
`src/animation/AnimationMixer.js`, `AnimationAction.js` and
`PropertyMixer.js`.

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
at the weighted mean however many values arrive.

For a position or a scale that mean is the same whatever order the values
arrive in. For a rotation it is not: `slerp` runs along an arc, and three
or more rotations mixed in a different order end somewhere slightly
different. three.js accumulates rotations the same way and has the same
property. Order here is the order the actions were added, which is at
least the same from frame to frame.

## Weight, and the pose that was already there

A pile is a mean, so on its own it says nothing about *how much* of the
node the actions have claimed. An action alone at a weight of one quarter
would set the node to its full value, and fading a single animation out
would do nothing until the weight reached zero.

So the mixer remembers, per node and property, the value the node held
before anything drove it, and mixes the pile back toward it by whatever
weight is missing:

    result = total * pile + (1 - total) * original

three.js does this in `PropertyMixer.apply`, against the same saved
original. A rotation blends back along the arc rather than the line, for
the reason a rotation pile is mixed along the arc.

That original is captured **once**, the first time a property is driven,
and never again. Reading the node each frame would read back what the
mixer wrote last frame, and the pose would wander.

## Letting go

A weight of zero is not the same as a weight of nearly zero. Nearly zero
writes the pile blended almost entirely back toward the original; zero
means the action contributes nothing at all, so no pile is made, so
nothing is written -- and the node kept whatever the last frame left on it.
Fading an action out therefore ended one frame short of where it was
going, and stopping the only action left its last pose behind for ever.

So a binding remembers whether anything drove it last frame. The frame
after the last contribution goes, it is written back to the value it held
before the mixer ever touched it, and then released.

Released is not deleted. The original is kept, so playing the action again
fades back toward the same pose. What release means is that the mixer
stops writing the property, which is what lets ordinary scene editing move
it afterwards: a mixer that wrote every property it had ever bound, every
frame, would fight the caller for the node for ever.

## Looping

`ONCE` stops at the end and stays there, `REPEAT` starts over, and
`PING_PONG` runs back the way it came.

What an action carries is a *phase*, not the time it is read at. For
`PING_PONG` the phase runs from zero to twice the clip's length and the
read time folds back out of it. Storing the folded time instead loses
which leg it was on: the second half of every period has the same time as
the first, so the action turned around, came back to the fold, and turned
around again. It bounced near the end for ever, and moving the same
elapsed time in smaller steps gave a different answer from moving it in
one.

## Pausing, and holding at the end

Three things are kept apart that a single flag ran together.

`active` says the action contributes to the pose. `paused` says its clock
has stopped. A paused action still contributes, which is what "hold where
it is" has to mean: with a single flag, pausing one of two actions on one
node did not freeze the pose, it handed the node to the other action.

`clamp_when_finished` says what a `ONCE` action does at the end. False,
three.js's default, and it stops contributing, so the node settles back
toward the pose it had. True, and it holds its last frame for as long as
it is kept. Either way the last frame is applied once before it takes
effect.

## What is refused

A weight below zero, which is not a share of anything. A weight, a time
scale or a frame time that is not a number. A loop mode that is none of
the three. An action index the mixer does not have. A track naming a node
the scene does not have. A clip of no length is refused where clips are
built, which is what lets the looping divide by the length without asking.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import POSITION, QUATERNION, SCALE, TrackKind
from core.object3d import NodeId
from core.scene import Scene
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import floor, isfinite
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


def rest_into_pile(
    mut piles: List[Float32],
    slot: Int,
    total: Float32,
    original: List[Float32],
    kind: TrackKind,
):
    """Mix one pile back toward the pose the node held before it was
    driven, by however much weight is missing.

    With a total weight of one the pile is left alone. With a total of one
    quarter the node keeps three quarters of what it was. three.js's
    `PropertyMixer.apply` does the same against the same saved value.

    Args:
        piles: Every pile's numbers, `PILE` of them each.
        slot: Which pile.
        total: How much weight the pile holds in all; below one.
        original: The `PILE` numbers the node held before.
        kind: Which property, which decides whether the move back is along
            a line or along an arc.
    """
    var at = slot * PILE
    if kind == QUATERNION:
        var mixed = Quaternion(
            original[0], original[1], original[2], original[3]
        ).slerp(
            Quaternion(piles[at], piles[at + 1], piles[at + 2], piles[at + 3]),
            total,
        )
        piles[at] = mixed.x
        piles[at + 1] = mixed.y
        piles[at + 2] = mixed.z
        piles[at + 3] = mixed.w
        return
    for offset in range(PILE):  # pragma: no branch
        piles[at + offset] = (
            original[offset] + (piles[at + offset] - original[offset]) * total
        )


struct Binding(Copyable, Movable):
    """One node property the mixer drives, and the value it held before.

    Kept for as long as the mixer is, because it is the pose a weight of
    less than one blends back toward. Reading the node instead would read
    back what the mixer wrote last frame.
    """

    var node: Int
    var kind: Int
    var original: List[Float32]
    # Whether anything drove this property in the last update. The frame
    # after it goes false, the original is written back and the mixer
    # leaves the property alone; see the module docstring.
    var driven: Bool

    def __init__(out self, node: Int, kind: Int, var original: List[Float32]):
        """Remember what one node property held.

        Args:
            node: Which node.
            kind: Which property.
            original: The `PILE` numbers it held.
        """
        self.node = node
        self.kind = kind
        self.original = original^
        self.driven = False


def apply_pose(
    mut scene: Scene, node: Int, kind: TrackKind, values: List[Float32], at: Int
) raises:
    """Write one node property from four numbers.

    The one place a property is set, so the pose the actions make and the
    pose a released binding goes back to cannot drift apart.

    Args:
        scene: The scene to write into.
        node: Which node.
        kind: Which property.
        values: The numbers to write, `PILE` of them per entry.
        at: Where this property's numbers start in `values`.

    Raises:
        Error: If the scene has no such node.
    """
    ref placed = scene.node(NodeId(node))
    if kind == POSITION:
        placed.position = Vector3(values[at], values[at + 1], values[at + 2])
    elif kind == SCALE:
        placed.scale = Vector3(values[at], values[at + 1], values[at + 2])
    else:
        placed.quaternion = Quaternion(
            values[at], values[at + 1], values[at + 2], values[at + 3]
        )


struct AnimationAction(Copyable, Movable):
    """One clip being played: where it has got to, and how much of it to
    use."""

    var clip: AnimationClip
    var loop: Loop
    # How far through the loop the action has got, in seconds. For
    # `PING_PONG` this runs to twice the clip's length and `at` folds it;
    # see the note on phase above.
    var phase: Float32
    # How much of this action goes into the pose, three.js's `weight`.
    var weight: Float32
    # How fast the clip runs, and which way. Negative runs it backward.
    var time_scale: Float32
    # Whether the action contributes to the pose at all.
    var active: Bool
    # Whether its clock has stopped. A paused action still contributes.
    var paused: Bool
    # Whether a `ONCE` action holds its last frame once it finishes.
    var clamp_when_finished: Bool

    def __init__(
        out self,
        var clip: AnimationClip,
        loop: Loop = REPEAT,
        weight: Float32 = 1,
        time_scale: Float32 = 1,
        clamp_when_finished: Bool = False,
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
            clamp_when_finished: True if a `ONCE` action holds its last
                frame rather than letting the node settle back. three.js's
                flag of the same name, and False by default as it is
                there.

        Raises:
            Error: If the loop mode is none of the three, or the weight or
                the time scale is negative or is not a number.
        """
        if not loop.is_valid():
            raise Error("An action needs a loop mode that exists")
        if not isfinite(weight):
            raise Error("An action's weight must be a number")
        if weight < 0:
            raise Error("An action's weight cannot be negative")
        if not isfinite(time_scale):
            raise Error("An action's time scale must be a number")
        self.clip = clip^
        self.loop = loop
        self.phase = 0
        self.weight = weight
        self.time_scale = time_scale
        self.active = False
        self.paused = False
        self.clamp_when_finished = clamp_when_finished

    def __init__(out self, *, copy: Self):
        """Copy another action, its clip included."""
        self.clip = AnimationClip(copy=copy.clip)
        self.loop = copy.loop
        self.phase = copy.phase
        self.weight = copy.weight
        self.time_scale = copy.time_scale
        self.active = copy.active
        self.paused = copy.paused
        self.clamp_when_finished = copy.clamp_when_finished

    def play(mut self):
        """Start the action from where it is, three.js's `play`."""
        self.active = True
        self.paused = False

    def pause(mut self):
        """Stop the action's clock where it is, three.js's `paused`.

        It goes on contributing to the pose. That is what holding a pose
        means, and a paused action that stopped contributing would hand
        the node to whatever else drives it.
        """
        self.paused = True

    def stop(mut self):
        """Stop the action, rewind it, and take it out of the pose,
        three.js's `stop`."""
        self.active = False
        self.paused = False
        self.phase = 0

    def is_active(self) -> Bool:
        """Return True if the action contributes to the pose."""
        return self.active

    def is_playing(self) -> Bool:
        """Return True if the action's clock is running, which needs it to
        be active and not paused."""
        return self.active and not self.paused

    def at(self) -> Duration:
        """Return how far into the clip the action is being read.

        For `PING_PONG` this is the phase folded back at the end of the
        clip, so it runs up to the end and back down to the start.
        """
        var length = self.clip.duration().to(SECOND)
        if self.loop == PING_PONG:
            if self.phase > length:
                return Duration(length * 2 - self.phase, SECOND)
        return Duration(self.phase, SECOND)

    def set_weight(mut self, weight: Float32) raises:
        """Set how much of this action goes into the pose.

        Args:
            weight: The new weight; not negative.

        Raises:
            Error: If the weight is negative or is not a number.
        """
        if not isfinite(weight):
            raise Error("An action's weight must be a number")
        if weight < 0:
            raise Error("An action's weight cannot be negative")
        self.weight = weight

    def _finish(mut self):
        """End a `ONCE` action, either holding its last frame or letting
        go of the node."""
        if self.clamp_when_finished:
            self.paused = True
        else:
            self.active = False

    def advance(mut self, seconds: Float32) raises:
        """Move the action on by `seconds` of real time, and handle the end
        of the clip the way its loop mode says.

        A clip lasts longer than no time, which `AnimationClip` has already
        made sure of, so dividing by its length is safe here.

        Args:
            seconds: How much real time has passed. It is multiplied by
                `time_scale`, so this can move the action either way.

        Raises:
            Error: If `seconds` is not a number.
        """
        if not isfinite(seconds):
            raise Error(
                "An action cannot advance by a time that is not a number"
            )
        var length = self.clip.duration().to(SECOND)
        var moved = self.phase + seconds * self.time_scale
        if self.loop == ONCE:
            if moved >= length:
                moved = length
                self._finish()
            if moved < 0:
                moved = 0
                self._finish()
        elif self.loop == REPEAT:
            moved -= floor(moved / length) * length
        else:
            # The phase runs over the whole there-and-back, and `at` folds
            # it. Folding it here instead would lose which leg it is on.
            var there_and_back = length * 2
            moved -= floor(moved / there_and_back) * there_and_back
        self.phase = moved


struct AnimationMixer(Movable):
    """The actions playing, what they held before, and what writes their
    pose into a scene."""

    var actions: List[AnimationAction]
    var bindings: List[Binding]
    # How much time the mixer has been given, in seconds.
    var elapsed: Float32

    def __init__(out self):
        """Create a mixer with nothing playing."""
        self.actions = List[AnimationAction]()
        self.bindings = List[Binding]()
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

    def binding_count(self) -> Int:
        """Return how many node properties the mixer has taken over."""
        return len(self.bindings)

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

    def _binding(self, node: Int, kind: Int) -> Int:
        """Return where the binding for one node property is, or minus one
        when the mixer has not taken it over yet."""
        for slot in range(len(self.bindings)):  # pragma: no branch
            if self.bindings[slot].node == node:
                if self.bindings[slot].kind == kind:
                    return slot
        return -1

    def _bind(mut self, scene: Scene, node: Int, kind: TrackKind) raises:
        """Remember what one node property holds, the first time anything
        drives it.

        Raises:
            Error: If the scene has no such node.
        """
        if node < 0 or node >= scene.count():
            raise Error("A track must name a node that is in the scene")
        var known = self._binding(node, kind.value)
        if known >= 0:
            self.bindings[known].driven = True
            return
        ref held = scene.get(NodeId(node))
        var original = List[Float32]()
        if kind == QUATERNION:
            original.append(held.quaternion.x)
            original.append(held.quaternion.y)
            original.append(held.quaternion.z)
            original.append(held.quaternion.w)
        elif kind == SCALE:
            original.append(held.scale.x)
            original.append(held.scale.y)
            original.append(held.scale.z)
            original.append(0)
        else:
            original.append(held.position.x)
            original.append(held.position.y)
            original.append(held.position.z)
            original.append(0)
        var made = Binding(node, kind.value, original^)
        made.driven = True
        self.bindings.append(made^)

    def update(mut self, mut scene: Scene, delta: Duration) raises:
        """Move every playing action on by `delta`, and write the pose the
        actions make into the scene.

        An action that finishes its `ONCE` clip during this call still
        contributes its last frame, and stops contributing from the next
        call on unless it holds.

        A property that was driven last time and is not driven now is put
        back to what it held before the mixer first touched it, and then
        released: the mixer stops writing it until something drives it
        again.

        Args:
            scene: The scene whose nodes the tracks name.
            delta: How much real time has passed since the last update.

        Raises:
            Error: If `delta` is not a number, or a track names a node the
                scene does not have.
        """
        var seconds = delta.to(SECOND)
        if not isfinite(seconds):
            raise Error("A mixer cannot advance by a time that is not a number")
        self.elapsed += seconds

        var nodes = List[Int]()
        var kinds = List[Int]()
        var weights = List[Float32]()
        var piles = List[Float32]()

        for index in range(len(self.actions)):  # pragma: no branch
            if not self.actions[index].active:
                continue
            if not self.actions[index].paused:
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
                self._bind(scene, node, kind)
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
            var kind = TrackKind(kinds[slot])
            if weights[slot] < 1:
                var held = self._binding(nodes[slot], kinds[slot])
                rest_into_pile(
                    piles,
                    slot,
                    weights[slot],
                    self.bindings[held].original,
                    kind,
                )
            apply_pose(scene, nodes[slot], kind, piles, slot * PILE)

        # Anything that was driven last frame and is not driven now goes
        # back to what it held before the mixer touched it, once, and is
        # then left alone. Without this a weight fading to zero stopped one
        # frame short of the pose it was fading toward, because a weight of
        # zero makes no pile and an empty pile writes nothing.
        for slot in range(len(self.bindings)):  # pragma: no branch
            if not self.bindings[slot].driven:
                continue
            if (
                find_pile(
                    nodes,
                    kinds,
                    self.bindings[slot].node,
                    self.bindings[slot].kind,
                )
                >= 0
            ):
                continue
            apply_pose(
                scene,
                self.bindings[slot].node,
                TrackKind(self.bindings[slot].kind),
                self.bindings[slot].original,
                0,
            )
            self.bindings[slot].driven = False
