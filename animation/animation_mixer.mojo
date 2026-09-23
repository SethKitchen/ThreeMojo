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

## Fades and warps run on the mixer's clock

A fade scales an action's weight, and a warp scales its time scale, along
a straight ramp between two times on the mixer's clock. three.js keeps each
in a two-key `LinearInterpolant` it lends the action, and evaluates it at
the mixer's time in every update. A `Ramp` here is the same two keys.

The ramp starts at the mixer's time *now*, which is why an action carries
`now`: the mixer sets it when the action is added and in every update,
active or not. The ramp is read at the mixer's time after the update has
added its delta, as three.js reads it, so a fade over one second is done
one second of updates later.

Both end the update after the mixer's clock passes their end, not the one
that reaches it. A fade that ends at nothing then takes the action out of
the pose. A warp that ends at nothing pauses it, and one that ends anywhere
else leaves the time scale there. A warp holds its values as shares of the
time scale it was scheduled against, again as three.js does, so an action
with a time scale of zero cannot be warped.

A cross-fade needs two actions at once, and one action cannot reach
another through the list that holds them both. So `cross_fade_from` and
`cross_fade_to` are the mixer's, and take two indices.

## Events are drained, not dispatched

three.js's mixer dispatches `loop` and `finished` to listeners. Here each
update records them in a list of `AnimationEvent`, and the caller drains it.
A `LOOPED` event says how many ends of the clip the action ran past, signed
by the way it ran, which is three.js's `loopDelta`. For `PING_PONG` both
ends count, as they do in three.js.

## What is refused

A weight below zero, which is not a share of anything. A weight, a time
scale or a frame time that is not a number. A loop mode that is none of
the three. An action index the mixer does not have, or a cross-fade from
an action to itself. A fade, a warp or a cross-fade that lasts less than no
time, or a time that is not a number. A warp on an action whose time scale
is zero. A track naming a node the scene does not have. A clip of no length is refused where clips are
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


@fieldwise_init
struct AnimationEventKind(Equatable, ImplicitlyCopyable, Writable):
    """What happened to an action during an update, as a type rather than
    a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the two event kinds there are."""
        return self == LOOPED or self == FINISHED


# The action ran past an end of its clip and went on: three.js's `loop`.
comptime LOOPED = AnimationEventKind(0)
# The action reached the end of a `ONCE` clip: three.js's `finished`.
comptime FINISHED = AnimationEventKind(1)


@fieldwise_init
struct AnimationEvent(Copyable, ImplicitlyCopyable, Movable):
    """One thing that happened to one action during one update.

    three.js dispatches these to listeners. Here the mixer keeps them in a
    list, and the caller drains the list after each update.
    """

    # What happened.
    var kind: AnimationEventKind
    # Which action it happened to, as `AnimationMixer.add` returned it.
    var action: Int
    # For `LOOPED`, how many ends of the clip the action ran past, signed
    # by the way it ran. Zero for `FINISHED`.
    var loop_delta: Int
    # Which way the action ran: one forward, minus one backward.
    var direction: Int


@fieldwise_init
struct Ramp(Copyable, ImplicitlyCopyable, Movable):
    """A value that runs in a straight line from one number to another
    over a span of the mixer's clock, three.js's two-key
    `LinearInterpolant` as `_scheduleFading` and `warp` fill it in.

    Every time is in seconds of the mixer's clock.
    """

    # When the ramp starts.
    var start: Float32
    # When it ends; not before `start`.
    var end: Float32
    # The value at the start and before it.
    var from_value: Float32
    # The value at the end and after it.
    var to_value: Float32

    def at(self, time: Float32) -> Float32:
        """Return the ramp's value at a time on the mixer's clock.

        Args:
            time: When, in seconds of the mixer's clock.

        Returns:
            `from_value` up to the start, `to_value` from the end on, and
            the straight line between them in between. A ramp that lasts
            no time is at its end value from its start on.
        """
        if time >= self.end:
            return self.to_value
        if time <= self.start:
            return self.from_value
        var part = (time - self.start) / (self.end - self.start)
        return self.from_value + (self.to_value - self.from_value) * part


def checked_span(duration: Duration, what: String) raises -> Float32:
    """Return a span of the mixer's clock in seconds, refused if it cannot
    be one.

    Args:
        duration: How long the span lasts.
        what: What the span is for, to name it in the error.

    Returns:
        The span in seconds.

    Raises:
        Error: If the span is not a number or is negative.
    """
    var seconds = duration.to(SECOND)
    if not isfinite(seconds):
        raise Error(what + " must last a time that is a number")
    if seconds < 0:
        raise Error(what + " cannot last less than no time")
    return seconds


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
    # The mixer's clock, in seconds, as of the last update. Fades and
    # warps are scheduled from it; see the module docstring.
    var now: Float32
    # Whether `fade` scales the weight, three.js's `_weightInterpolant`.
    var fading: Bool
    var fade: Ramp
    # Whether `warp_ramp` scales the time scale, three.js's
    # `_timeScaleInterpolant`.
    var warping: Bool
    var warp_ramp: Ramp
    # Whether the action waits for `start_time` on the mixer's clock
    # before its clock runs, three.js's `_startTime`.
    var scheduled: Bool
    var start_time: Float32
    # The weight and the time scale the last update used, three.js's
    # `_effectiveWeight` and `_effectiveTimeScale`.
    var applied_weight: Float32
    var applied_time_scale: Float32
    # What the last move did: how many ends of the clip it ran past,
    # signed, and whether it finished a `ONCE` clip and which way.
    var loop_delta: Int
    var just_finished: Bool
    var direction: Int

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
        self.now = 0
        self.fading = False
        self.fade = Ramp(0, 0, 1, 1)
        self.warping = False
        self.warp_ramp = Ramp(0, 0, 1, 1)
        self.scheduled = False
        self.start_time = 0
        self.applied_weight = weight
        self.applied_time_scale = time_scale
        self.loop_delta = 0
        self.just_finished = False
        self.direction = 1

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
        self.now = copy.now
        self.fading = copy.fading
        self.fade = copy.fade
        self.warping = copy.warping
        self.warp_ramp = copy.warp_ramp
        self.scheduled = copy.scheduled
        self.start_time = copy.start_time
        self.applied_weight = copy.applied_weight
        self.applied_time_scale = copy.applied_time_scale
        self.loop_delta = copy.loop_delta
        self.just_finished = copy.just_finished
        self.direction = copy.direction

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
        three.js's `stop`.

        Like three.js's `reset`, it also drops any fade, warp or start
        time that was scheduled.
        """
        self.active = False
        self.paused = False
        self.phase = 0
        self.scheduled = False
        self.stop_fading()
        self.stop_warping()

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

        A fade that is running goes on scaling the new weight, as it does
        in three.js when `weight` is set directly.

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

    def set_effective_weight(mut self, weight: Float32) raises:
        """Set the weight and stop any fade, three.js's
        `setEffectiveWeight`.

        Args:
            weight: The new weight; not negative.

        Raises:
            Error: If the weight is negative or is not a number.
        """
        self.set_weight(weight)
        self.applied_weight = weight if self.active else Float32(0)
        self.stop_fading()

    def get_effective_weight(self) -> Float32:
        """Return the weight the action had in the last update, with its
        fade applied, three.js's `getEffectiveWeight`.

        Returns:
            The weight times the fade, or zero if the action did not
            contribute.
        """
        return self.applied_weight

    def set_effective_time_scale(mut self, time_scale: Float32) raises:
        """Set the time scale and stop any warp, three.js's
        `setEffectiveTimeScale`.

        Args:
            time_scale: The new time scale.

        Raises:
            Error: If the time scale is not a number.
        """
        if not isfinite(time_scale):
            raise Error("An action's time scale must be a number")
        self.time_scale = time_scale
        self.applied_time_scale = Float32(0) if self.paused else time_scale
        self.stop_warping()

    def get_effective_time_scale(self) -> Float32:
        """Return the time scale the action ran at in the last update,
        with its warp applied, three.js's `getEffectiveTimeScale`.

        Returns:
            The time scale times the warp, or zero if the action was
            paused.
        """
        return self.applied_time_scale

    def fade_in(mut self, duration: Duration) raises:
        """Raise the weight from nothing to all of it over `duration` of
        the mixer's clock, three.js's `fadeIn`.

        The fade starts at the mixer's time now. It does not play the
        action; call `play` as well.

        Args:
            duration: How long the fade lasts; not negative.

        Raises:
            Error: If `duration` is negative or is not a number.
        """
        self._schedule_fading(duration, 0, 1)

    def fade_out(mut self, duration: Duration) raises:
        """Lower the weight from all of it to nothing over `duration` of
        the mixer's clock, three.js's `fadeOut`.

        Once the fade is over the action stops contributing, as three.js's
        does when it sets `enabled` to false.

        Args:
            duration: How long the fade lasts; not negative.

        Raises:
            Error: If `duration` is negative or is not a number.
        """
        self._schedule_fading(duration, 1, 0)

    def _schedule_fading(
        mut self, duration: Duration, weight_now: Float32, weight_then: Float32
    ) raises:
        """Scale the weight along a ramp from the mixer's time now,
        three.js's `_scheduleFading`."""
        var span = checked_span(duration, "A fade")
        self.fade = Ramp(self.now, self.now + span, weight_now, weight_then)
        self.fading = True

    def stop_fading(mut self):
        """Drop any fade and use the weight as it is, three.js's
        `stopFading`."""
        self.fading = False

    def warp(
        mut self,
        start_time_scale: Float32,
        end_time_scale: Float32,
        duration: Duration,
    ) raises:
        """Change the time scale from one value to another over `duration`
        of the mixer's clock, three.js's `warp`.

        As in three.js, the ramp holds each value as a share of the time
        scale now. When the warp is over the time scale takes the end
        value, or the action pauses if the end value is zero.

        Args:
            start_time_scale: The time scale at the start.
            end_time_scale: The time scale at the end.
            duration: How long the warp lasts; not negative.

        Raises:
            Error: If either time scale is not a number, `duration` is
                negative or is not a number, or the time scale now is
                zero, which leaves nothing to take a share of.
        """
        if not isfinite(start_time_scale) or not isfinite(end_time_scale):
            raise Error("A warp needs time scales that are numbers")
        var span = checked_span(duration, "A warp")
        if self.time_scale == 0:
            raise Error("An action with a time scale of zero cannot warp")
        self.warp_ramp = Ramp(
            self.now,
            self.now + span,
            start_time_scale / self.time_scale,
            end_time_scale / self.time_scale,
        )
        self.warping = True

    def halt(mut self, duration: Duration) raises:
        """Slow the action to a stop over `duration` of the mixer's clock,
        and then pause it, three.js's `halt`.

        Args:
            duration: How long the slowing lasts; not negative.

        Raises:
            Error: If `duration` is negative or is not a number, or the
                time scale now is zero.
        """
        self.warp(self.applied_time_scale, 0, duration)

    def stop_warping(mut self):
        """Drop any warp and use the time scale as it is, three.js's
        `stopWarping`."""
        self.warping = False

    def start_at(mut self, time: Duration) raises:
        """Hold the action's clock until the mixer's clock reaches `time`,
        three.js's `startAt`.

        The action still contributes its pose while it waits.

        Args:
            time: When to start, on the mixer's clock.

        Raises:
            Error: If `time` is not a number.
        """
        var seconds = time.to(SECOND)
        if not isfinite(seconds):
            raise Error("An action cannot start at a time that is not a number")
        self.start_time = seconds
        self.scheduled = True

    def _finish(mut self, moved_by: Float32):
        """End a `ONCE` action, either holding its last frame or letting
        go of the node, and note which way it was going."""
        if self.clamp_when_finished:
            self.paused = True
        else:
            self.active = False
        self.just_finished = True
        self.direction = -1 if moved_by < 0 else 1

    def advance(mut self, seconds: Float32) raises:
        """Move the action on by `seconds` of real time, and handle the end
        of the clip the way its loop mode says.

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
        self._move(seconds * self.time_scale)

    def _move(mut self, moved_by: Float32):
        """Move the phase by `moved_by` seconds of clip time, and note in
        `loop_delta`, `just_finished` and `direction` what that did.

        A clip lasts longer than no time, which `AnimationClip` has already
        made sure of, so dividing by its length is safe here. A move of
        nothing does nothing, as three.js's `_updateTime` returns early on
        a delta of zero.
        """
        self.loop_delta = 0
        self.just_finished = False
        if moved_by == 0:
            return
        var length = self.clip.duration().to(SECOND)
        var moved = self.phase + moved_by
        if self.loop == ONCE:
            if moved >= length:
                moved = length
                self._finish(moved_by)
            if moved < 0:
                moved = 0
                self._finish(moved_by)
            self.phase = moved
            return
        # Each end of the clip passed is one of three.js's loops, for
        # `PING_PONG` as much as for `REPEAT`: the phase has one end every
        # clip's length, whichever leg it is on.
        self.loop_delta = Int(floor(moved / length)) - Int(
            floor(self.phase / length)
        )
        self.direction = -1 if moved_by < 0 else 1
        var period = length
        if self.loop == PING_PONG:
            # The phase runs over the whole there-and-back, and `at` folds
            # it. Folding it here instead would lose which leg it is on.
            period = length * 2
        moved -= floor(moved / period) * period
        self.phase = moved

    def _update_time_scale(mut self, time: Float32) -> Float32:
        """Return the time scale for this update with any warp applied,
        and end the warp once the mixer's clock is past it, three.js's
        `_updateTimeScale`."""
        var scale: Float32 = 0
        if not self.paused:
            scale = self.time_scale
            if self.warping:
                scale *= self.warp_ramp.at(time)
                if time > self.warp_ramp.end:
                    self.warping = False
                    if scale == 0:
                        self.paused = True
                    else:
                        self.time_scale = scale
        self.applied_time_scale = scale
        return scale

    def _update_weight(mut self, time: Float32) -> Float32:
        """Return the weight for this update with any fade applied, and
        end the fade once the mixer's clock is past it, three.js's
        `_updateWeight`. A fade that ends at nothing takes the action out
        of the pose."""
        var weight = self.weight
        if self.fading:
            var share = self.fade.at(time)
            weight *= share
            if time > self.fade.end:
                self.fading = False
                if share == 0:
                    self.active = False
        self.applied_weight = weight
        return weight

    def _tick(mut self, time: Float32, seconds: Float32) -> Float32:
        """Run one mixer update for an active action, three.js's `_update`,
        and return the weight it contributes.

        `time` is the mixer's clock after the update and `seconds` is how
        far it moved. A start time still ahead holds the clock; the update
        that passes it runs only the part after it.
        """
        self.now = time
        var step = seconds
        if self.scheduled:
            var way = Float32(1) if seconds > 0 else (
                Float32(-1) if seconds < 0 else Float32(0)
            )
            var running = (time - self.start_time) * way
            if running < 0 or way == 0:
                step = 0
            else:
                self.scheduled = False
                step = way * running
        self._move(step * self._update_time_scale(time))
        return self._update_weight(time)


struct AnimationMixer(Movable):
    """The actions playing, what they held before, and what writes their
    pose into a scene."""

    var actions: List[AnimationAction]
    var bindings: List[Binding]
    # How much time the mixer has been given, in seconds.
    var elapsed: Float32
    # What happened to the actions during the last update, three.js's
    # `loop` and `finished` events. Each update starts a new list.
    var events: List[AnimationEvent]

    def __init__(out self):
        """Create a mixer with nothing playing."""
        self.actions = List[AnimationAction]()
        self.bindings = List[Binding]()
        self.elapsed = 0
        self.events = List[AnimationEvent]()

    def add(mut self, var action: AnimationAction) -> Int:
        """Add an action and return the index it was given.

        Args:
            action: The action, consumed. three.js's `clipAction` makes one
                and remembers it; here the caller makes it and this keeps
                it.

        Returns:
            Which action it is, for `action`.
        """
        action.now = self.elapsed
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

    def cross_fade_from(
        mut self,
        index: Int,
        from_index: Int,
        duration: Duration,
        warp: Bool = False,
    ) raises:
        """Fade one action in while another fades out, three.js's
        `crossFadeFrom`.

        With `warp`, the action going out speeds up or slows down from its
        own pace to the pace of the one coming in, and the one coming in
        does the reverse, so their loops line up as they cross. The paces
        are the ratio of the two clips' lengths, as three.js has them. The
        call does not play either action.

        Args:
            index: The action to fade in.
            from_index: The action to fade out.
            duration: How long the cross-fade lasts; not negative.
            warp: True to warp the two time scales as well.

        Raises:
            Error: If either index names no action, the two are the same
                action, `duration` is negative or is not a number, or
                `warp` is True and either time scale is zero. Nothing is
                changed when it raises.
        """
        if index < 0 or index >= len(self.actions):
            raise Error("The mixer has no action at that index")
        if from_index < 0 or from_index >= len(self.actions):
            raise Error("The mixer has no action at that index")
        if index == from_index:
            raise Error("An action cannot cross-fade from itself")
        _ = checked_span(duration, "A cross-fade")
        if warp:
            if (
                self.actions[index].time_scale == 0
                or self.actions[from_index].time_scale == 0
            ):
                raise Error("An action with a time scale of zero cannot warp")
        self.actions[from_index].fade_out(duration)
        self.actions[index].fade_in(duration)
        if warp:
            var in_length = self.actions[index].clip.duration().to(SECOND)
            var out_length = self.actions[from_index].clip.duration().to(SECOND)
            self.actions[from_index].warp(1, out_length / in_length, duration)
            self.actions[index].warp(in_length / out_length, 1, duration)

    def cross_fade_to(
        mut self,
        index: Int,
        to_index: Int,
        duration: Duration,
        warp: Bool = False,
    ) raises:
        """Fade one action out while another fades in, three.js's
        `crossFadeTo`.

        Args:
            index: The action to fade out.
            to_index: The action to fade in.
            duration: How long the cross-fade lasts; not negative.
            warp: True to warp the two time scales as well; see
                `cross_fade_from`.

        Raises:
            Error: As `cross_fade_from` does.
        """
        self.cross_fade_from(to_index, index, duration, warp)

    def event_count(self) -> Int:
        """Return how many events the last update recorded and nobody has
        drained yet."""
        return len(self.events)

    def drain_events(mut self) -> List[AnimationEvent]:
        """Hand over the events the last update recorded, and forget them.

        three.js dispatches `loop` and `finished` to listeners. Here the
        caller drains them after each update, in the order they happened:
        by action, in the order the actions were added.

        Returns:
            The events, oldest first.
        """
        var drained = self.events^
        self.events = List[AnimationEvent]()
        return drained^

    def _record(mut self, index: Int):
        """Turn what one action's last move did into events."""
        if self.actions[index].loop_delta != 0:
            self.events.append(
                AnimationEvent(
                    LOOPED,
                    index,
                    self.actions[index].loop_delta,
                    self.actions[index].direction,
                )
            )
        if self.actions[index].just_finished:
            self.events.append(
                AnimationEvent(
                    FINISHED, index, 0, self.actions[index].direction
                )
            )

    def _binding(self, node: Int, kind: Int) -> Int:
        """Return where the binding for one node property is, or minus one
        when the mixer has not taken it over yet."""
        for slot in range(len(self.bindings)):  # pragma: no branch
            if self.bindings[slot].node == node:
                if self.bindings[slot].kind == kind:
                    return slot
        return -1

    def _bind(mut self, scene: Scene, node: Int, kind: TrackKind) raises:
        """Remember what one node property holds, each time something
        starts to drive it.

        Read again when a released property is driven again, not only the
        first time: three.js's `PropertyMixer.saveOriginalState` runs
        whenever a binding's use count rises from zero, so a node the
        caller moved while nothing drove it is blended toward, and put
        back to, where the caller left it. Reading it once and keeping it
        threw the caller's edit away.

        Raises:
            Error: If the scene has no such node.
        """
        if node < 0 or node >= scene.count():
            raise Error("A track must name a node that is in the scene")
        var known = self._binding(node, kind.value)
        if known >= 0 and self.bindings[known].driven:
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
        if known >= 0:
            self.bindings[known].original = original^
            self.bindings[known].driven = True
            return
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

        The update also starts a new list of events. Each action that runs
        past an end of its clip adds a `LOOPED` event, and each that
        finishes a `ONCE` clip adds a `FINISHED` one. Read them with
        `drain_events`.

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
        self.events = List[AnimationEvent]()

        var nodes = List[Int]()
        var kinds = List[Int]()
        var weights = List[Float32]()
        var piles = List[Float32]()

        for index in range(len(self.actions)):  # pragma: no branch
            if not self.actions[index].active:
                # Kept in step all the same, so a fade or a warp scheduled
                # on it before it plays starts at the mixer's time now.
                self.actions[index].now = self.elapsed
                self.actions[index].applied_weight = 0
                continue
            var share = self.actions[index]._tick(self.elapsed, seconds)
            self._record(index)
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
