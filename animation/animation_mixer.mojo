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

## Repetitions

A `REPEAT` or `PING_PONG` action runs through its clip `repetitions`
times and then finishes, as a `ONCE` action does at its end: it holds
its last frame if `clamp_when_finished`, and lets go of the node if not.
None, the default, repeats without end, three.js's `Infinity`. A
`PING_PONG` leg is one repetition. Run backward from the start, the first
pass through zero is not a repetition, as three.js counts it.

A finished `PING_PONG` action stops at the end its last leg was running
to. three.js reads the other end in the update it finishes in, and the
right one from the next update on; the counter it reads the leg from is
the one it has not yet stored. Here the right end is read in both.

## Smooth tracks and the ends of a clip

A `SMOOTH` track needs a key past each end of the track, and the action
says which, three.js's `_setEndings`. A `ONCE` clip is flat at both ends,
or unbent if `zero_slope_at_start` or `zero_slope_at_end` is False. A
`REPEAT` clip wraps an end once it runs on past it: going forward it is
flat at the start until the first loop, and wraps the end from the first
frame. A `PING_PONG` clip turns back at both ends, so both are flat.
`stop` starts this over, as three.js's `reset` does.

three.js works the weights out once per pair of keys and keeps them until
the time moves to another pair. A track of two keys never moves to another
pair, so three.js goes on using the endings of the first frame it read.
Here the track is read with the action's endings every frame.

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

## The mixer's clock, root and cache

`time_scale` is three.js's mixer `timeScale`: every update's delta is
multiplied by it before any action sees it, so a mixer at one half plays
every action at half speed and its fades and warps with them.

A mixer is made for a root node, three.js's `root`, and `add` can file an
action under another. Here a track names its target by index, so the root
does not scope a lookup as three.js's does. It is what `get_root`,
`existing_action` and `uncache_root` find actions by.

`uncache_action`, `uncache_clip` and `uncache_root` forget actions, as
three.js's do. An uncached action keeps its index, and `action` refuses
it, so no other index moves. Its tracks are let go. Then every binding
that nothing drove in the last update is dropped: a property is read
again whenever something starts to drive it, so such a binding holds
nothing the mixer needs.

## Events are drained, not dispatched

three.js's mixer dispatches `loop` and `finished` to listeners. Here each
update records them in a list of `AnimationEvent`, and the caller drains it.
A `LOOPED` event says how many ends of the clip the action ran past, signed
by the way it ran, which is three.js's `loopDelta`. For `PING_PONG` both
ends count, as they do in three.js.

## Properties other than a node's transform

A track can also drive a node's `visible` flag and name, a mesh's or a
skinned mesh's morph target influences, a material's colors, numbers and
flags, a light's color, intensity, distance, angle and penumbra, and a
camera's field of view, zoom, near plane and far plane; see
`animation.keyframe_track`. Each is a property with its own
binding and its own pile, and the piles mix the way three.js's
`PropertyMixer` mixes each type of value:

    numbers and colors    by weight, one number at a time
    rotations             by weight, along the arc
    flags and strings     the value whose share is at least one half

A flag is three.js's `_select`: each value in takes the pile if its share
of the weight so far is at least one half, and the original takes it back
if the missing weight is at least one half. That is the heaviest action
for two actions. For three or more it is the order they arrive in that
decides a near tie, as it is in three.js.

A color pile holds three linear channels, and the channels are what is
mixed, as three.js mixes its `Color`'s own numbers. A material's and a
light's colors are stored as sRGB bytes here, so the mixer decodes them
when it binds and encodes the result when it writes.

A string pile holds the place of a string in the mixer's own list of
strings, so a string is chosen as a flag is, and three.js mixes its
strings with the same `_select`.

`update(scene, delta)` drives nodes, meshes and lights, which are all in
the scene. A material is in the assets, so a clip with a material track
needs `update(scene, assets, delta)`. A camera is in a `CameraList`
beside the scene, so a clip with a camera track needs
`update(scene, assets, cameras, delta)`. three.js leaves a camera's
projection to be updated by hand after a track moves it; here the
projection is worked out when it is asked for, so it follows the track.

A node that `Scene.remove` took out of the scene is not driven, nor is a
mesh or a light on it or under it: its values stay as they were until it
is added back. three.js goes on writing to an object it holds after the
object leaves the scene; this port stops, because a removed node here is
not a separate object that something else can show.

## Additive actions

An action on a clip made additive, by
`animation.animation_utils.make_clip_additive`, adds its values on top of
what the normal actions make rather than mixing with them. three.js keeps
a second pile per property for this, and so does the mixer here:

    numbers and colors    pile += weight * value
    rotations             pile = slerp(pile, pile * value, weight)
    flags                 as a normal flag, starting from the original

When every action has had its say, the normal pile is rested toward the
original as above, and then the additive pile is put on top: added, or for
a rotation multiplied on the right. That is three.js's
`PropertyMixer.apply`, and like three.js the flag of an additive pile
replaces the normal one.

## Groups

An action given an `AnimationObjectGroup` plays every track on every member
of the group instead of the target the track names; see
`animation.animation_object_group`. Each member's property has its own
binding and pile, so a group action mixes with the other actions on the
same nodes as any other action does.

## What is refused

A weight below zero, which is not a share of anything. A weight, a time
scale, the mixer's time scale or a frame time that is not a number.
Repetitions below zero, and a duration of zero for `set_duration`. An
uncached action. A loop mode that is none of
the three. An action index the mixer does not have, or a cross-fade from
an action to itself. A fade, a warp or a cross-fade that lasts less than no
time, or a time that is not a number. A warp on an action whose time scale
is zero. A track naming a node, a mesh, a light or a material the scene
or the assets do not have, and a material track played without the assets.
A camera track played without the cameras. A group member that is not in
the scene. A value written that the property cannot hold: a color channel
outside zero to one, a light intensity below zero, a light distance, angle
or penumbra that `Light.validate` refuses, a material number outside the
range `Material` accepts for it, which an additive action can reach, a
field of view outside zero to half a turn, a zoom of zero or less, and
planes that cross. A blend mode that is neither of the
two. A clip of no length is refused where clips are built, which is what
lets the looping divide by the length without asking.
"""

from animation.animation_clip import (
    ADDITIVE_BLEND_MODE,
    AnimationBlendMode,
    AnimationClip,
)
from animation.animation_object_group import AnimationObjectGroup
from animation.keyframe_track import (
    KeyframeTrack,
    CAMERA_FAR,
    CAMERA_FOV,
    CAMERA_NEAR,
    CAMERA_ZOOM,
    Ending,
    LIGHT_ANGLE,
    LIGHT_COLOR,
    LIGHT_DISTANCE,
    LIGHT_INTENSITY,
    LIGHT_PENUMBRA,
    MATERIAL_ALPHA_TEST,
    MATERIAL_CLEARCOAT,
    MATERIAL_CLEARCOAT_ROUGHNESS,
    MATERIAL_COLOR,
    MATERIAL_EMISSIVE,
    MATERIAL_EMISSIVE_INTENSITY,
    MATERIAL_ENV_MAP_INTENSITY,
    MATERIAL_IOR,
    MATERIAL_MAP_CENTER,
    MATERIAL_MAP_OFFSET,
    MATERIAL_MAP_REPEAT,
    MATERIAL_MAP_ROTATION,
    MATERIAL_METALNESS,
    MATERIAL_OPACITY,
    MATERIAL_REFLECTIVITY,
    MATERIAL_ROUGHNESS,
    MATERIAL_SHININESS,
    MATERIAL_SPECULAR,
    MATERIAL_SPECULAR_INTENSITY,
    MATERIAL_TRANSPARENT,
    MATERIAL_WIREFRAME,
    NODE_NAME,
    ORTHOGRAPHIC_SLOT,
    POSITION,
    POSITION_ELEMENT,
    QUATERNION,
    ROTATION_ELEMENT,
    SCALE,
    SCALE_ELEMENT,
    TrackKind,
    TrackTarget,
    VISIBLE,
    WRAP_AROUND_ENDING,
    ZERO_CURVATURE_ENDING,
    ZERO_SLOPE_ENDING,
)
from cameras.camera_list import CameraList
from core.assets import Assets
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from materials.material import MAX_IOR, MIN_IOR
from math.euler import Euler
from math.quaternion import Quaternion
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from render.texture_store import NO_TEXTURE, TextureId
from std.math import floor, inf, isfinite
from units.si import Angle, DEGREE, Duration, Length, METER, RADIAN, SECOND

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
            line or along an arc, or for a flag a choice of one value.
    """
    var part = share / (so_far + share)
    var at = slot * PILE
    if kind.is_boolean():
        # three.js's `_select`: the value takes the pile if its share is
        # at least one half.
        if part >= 0.5:
            piles[at] = value[0]
        return
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
            a line or along an arc, or for a flag a choice of one value.
    """
    var at = slot * PILE
    if kind.is_boolean():
        # three.js's `_select` with the original coming in at the missing
        # weight.
        if 1 - total >= 0.5:
            piles[at] = original[0]
        return
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


def find_target(targets: List[TrackTarget], target: TrackTarget) -> Int:
    """Return where the pile for one target is, or minus one when nothing
    has been put there yet.

    Args:
        targets: Which target each pile is for.
        target: The target wanted.

    Returns:
        The pile's place in the list, or minus one.
    """
    for slot in range(len(targets)):  # pragma: no branch
        if targets[slot] == target:
            return slot
    return -1


def additive_identity(
    mut piles: List[Float32],
    slot: Int,
    original: List[Float32],
    kind: TrackKind,
):
    """Set one additive pile to what adds nothing, three.js's
    `_setAdditiveIdentity`.

    Args:
        piles: Every additive pile's numbers, `PILE` of them each.
        slot: Which pile.
        original: The `PILE` numbers the property held before it was
            driven, which is where a flag starts.
        kind: Which property.
    """
    var at = slot * PILE
    for offset in range(PILE):  # pragma: no branch
        piles[at + offset] = 0
    if kind == QUATERNION:
        piles[at + 3] = 1
    elif kind.is_boolean():
        piles[at] = original[0]


def mix_additive_into_pile(
    mut piles: List[Float32],
    slot: Int,
    share: Float32,
    value: List[Float32],
    kind: TrackKind,
):
    """Add one weighted value to an additive pile, three.js's
    `_mixBufferRegionAdditive`.

    Args:
        piles: Every additive pile's numbers, `PILE` of them each.
        slot: Which pile.
        share: How much weight this value brings.
        value: The value, its own numbers alone.
        kind: Which property. A number or a color is added by weight, a
            rotation is turned toward the pile times the value by weight,
            and a flag is chosen as `mix_into_pile` chooses one.
    """
    var at = slot * PILE
    if kind.is_boolean():
        if share >= 0.5:
            piles[at] = value[0]
        return
    if kind == QUATERNION:
        var pile = Quaternion(
            piles[at], piles[at + 1], piles[at + 2], piles[at + 3]
        )
        var turned = pile
        turned.multiply(Quaternion(value[0], value[1], value[2], value[3]))
        var mixed = pile.slerp(turned, share)
        piles[at] = mixed.x
        piles[at + 1] = mixed.y
        piles[at + 2] = mixed.z
        piles[at + 3] = mixed.w
        return
    for offset in range(len(value)):  # pragma: no branch
        piles[at + offset] += value[offset] * share


def add_onto_pile(
    mut piles: List[Float32],
    slot: Int,
    additive: List[Float32],
    kind: TrackKind,
):
    """Put an additive pile on top of a normal one, the last step of
    three.js's `PropertyMixer.apply`.

    Args:
        piles: Every normal pile's numbers, `PILE` of them each.
        slot: Which pile, the same place in both lists.
        additive: Every additive pile's numbers.
        kind: Which property. Numbers and colors add, a rotation is
            multiplied by the additive one on the right, and a flag takes
            the additive one.
    """
    var at = slot * PILE
    if kind.is_boolean():
        piles[at] = additive[at]
        return
    if kind == QUATERNION:
        var turned = Quaternion(
            piles[at], piles[at + 1], piles[at + 2], piles[at + 3]
        )
        turned.multiply(
            Quaternion(
                additive[at],
                additive[at + 1],
                additive[at + 2],
                additive[at + 3],
            )
        )
        piles[at] = turned.x
        piles[at + 1] = turned.y
        piles[at + 2] = turned.z
        piles[at + 3] = turned.w
        return
    for offset in range(PILE):  # pragma: no branch
        piles[at + offset] += additive[at + offset]


def checked_value(
    value: Float32, low: Float32, high: Float32, what: String
) raises -> Float32:
    """Return a value about to be written into a property, refused if the
    property cannot hold it.

    Args:
        value: The value.
        low: The least the property holds.
        high: The most it holds.
        what: What the property is, to name it in the error.

    Returns:
        The value.

    Raises:
        Error: If the value is not a number or is outside `low` to `high`.
    """
    if not isfinite(value) or value < low or value > high:
        raise Error("An animation drove " + what + " to a value it cannot hold")
    return value


def color_to_pile(color: Color) -> List[Float32]:
    """Return a color as the `PILE` numbers a pile holds: its three linear
    channels and a zero.

    Args:
        color: An eight-bit sRGB color, as materials and lights store it.

    Returns:
        The decoded channels.
    """
    var linear = FloatColor(srgb=color)
    return [linear.r, linear.g, linear.b, 0]


def pile_to_color(
    values: List[Float32], at: Int, alpha: UInt8, what: String
) raises -> Color:
    """Return three linear channels as an eight-bit sRGB color.

    Args:
        values: The numbers to read.
        at: Where the channels start.
        alpha: The alpha to keep, which a color track does not drive.
        what: What the color is, to name it in the error.

    Returns:
        The encoded color.

    Raises:
        Error: If a channel is not a number or is outside zero to one.
    """
    var encoded = FloatColor(
        checked_value(values[at], 0, 1, what),
        checked_value(values[at + 1], 0, 1, what),
        checked_value(values[at + 2], 0, 1, what),
    ).encode()
    return Color(encoded.r, encoded.g, encoded.b, alpha)


def material_number(kind: TrackKind, top: Bool) -> Float32:
    """Return one end of the range `Material` accepts for a number field.

    Args:
        kind: A `MATERIAL_` number kind.
        top: False for the least value, True for the most.

    Returns:
        The end asked for. Every field starts at zero but `MATERIAL_IOR`,
        and has no top but those that run to one and `MATERIAL_IOR`.
    """
    if kind == MATERIAL_IOR:
        return MAX_IOR if top else MIN_IOR
    if not top:
        return 0
    if (
        kind == MATERIAL_EMISSIVE_INTENSITY
        or kind == MATERIAL_SHININESS
        or kind == MATERIAL_ENV_MAP_INTENSITY
    ):
        return inf[DType.float32]()
    return 1


def read_target(
    scene: Scene,
    assets: Assets,
    target: TrackTarget,
    cameras: CameraList = CameraList(),
) raises -> List[Float32]:
    """Return what one property holds, as the `PILE` numbers a pile holds.

    The one place a property is read, beside `write_target`, the one place
    it is written, so the two cannot drift apart. A node's name is a
    string, which the mixer reads into its own table of strings instead.

    Args:
        scene: The scene the nodes, meshes and lights are in.
        assets: The assets the materials are in.
        target: The property. The caller has checked its index.
        cameras: The cameras a camera target names.

    Returns:
        The numbers, zero after the property's own. A camera's field of
        view is in degrees and its planes in meters, a light's distance in
        meters and its angle in radians, as three.js keeps them.

    Raises:
        Error: If the scene has no such node, or the target is a string,
            which is not numbers.
    """
    var kind = target.kind
    if kind.is_string():
        raise Error("A string property is read into the mixer's strings")
    if kind.is_camera():
        return _read_camera(cameras, target)
    if kind.is_node():
        ref held = scene.get(NodeId(target.index))
        if kind == POSITION_ELEMENT:
            return [_axis(held.position, target.slot), 0, 0, 0]
        if kind == SCALE_ELEMENT:
            return [_axis(held.scale, target.slot), 0, 0, 0]
        if kind == ROTATION_ELEMENT:
            return [_euler_axis(held.quaternion, target.slot), 0, 0, 0]
        if kind == QUATERNION:
            return [
                held.quaternion.x,
                held.quaternion.y,
                held.quaternion.z,
                held.quaternion.w,
            ]
        if kind == SCALE:
            return [held.scale.x, held.scale.y, held.scale.z, 0]
        if kind == POSITION:
            return [held.position.x, held.position.y, held.position.z, 0]
        return [Float32(1) if held.visible else Float32(0), 0, 0, 0]
    if kind.is_skinned():
        return [
            scene.skinned_meshes[target.index].morph_influence(target.slot),
            0,
            0,
            0,
        ]
    if kind.is_morph():
        return [
            scene.meshes[target.index].morph_influence(target.slot),
            0,
            0,
            0,
        ]
    if kind.is_light():
        ref light = scene.lights[target.index]
        if kind == LIGHT_COLOR:
            return color_to_pile(light.color)
        var number = light.intensity
        if kind == LIGHT_DISTANCE:
            number = light.distance
        elif kind == LIGHT_ANGLE:
            number = light.angle.to(RADIAN)
        elif kind == LIGHT_PENUMBRA:
            number = light.penumbra
        return [number, 0, 0, 0]
    ref material = assets.materials.materials[target.index]
    if kind.is_map():
        ref laid = assets.textures.textures[_map_of(assets, target).value]
        if kind == MATERIAL_MAP_OFFSET:
            return [laid.offset.x, laid.offset.y, 0, 0]
        if kind == MATERIAL_MAP_REPEAT:
            return [laid.repeat.x, laid.repeat.y, 0, 0]
        if kind == MATERIAL_MAP_CENTER:
            return [laid.center.x, laid.center.y, 0, 0]
        return [laid.rotation.to(RADIAN), 0, 0, 0]
    if kind == MATERIAL_TRANSPARENT:
        return [Float32(1) if material.transparent else Float32(0), 0, 0, 0]
    if kind == MATERIAL_WIREFRAME:
        return [Float32(1) if material.wireframe else Float32(0), 0, 0, 0]
    if kind == MATERIAL_COLOR:
        return color_to_pile(material.color)
    if kind == MATERIAL_EMISSIVE:
        return color_to_pile(material.emissive)
    if kind == MATERIAL_SPECULAR:
        return color_to_pile(material.specular)
    var number: Float32
    if kind == MATERIAL_OPACITY:
        number = material.opacity
    elif kind == MATERIAL_EMISSIVE_INTENSITY:
        number = material.emissive_intensity
    elif kind == MATERIAL_ROUGHNESS:
        number = material.roughness
    elif kind == MATERIAL_METALNESS:
        number = material.metalness
    elif kind == MATERIAL_SHININESS:
        number = material.shininess
    elif kind == MATERIAL_ALPHA_TEST:
        number = material.alpha_test
    elif kind == MATERIAL_REFLECTIVITY:
        number = material.reflectivity
    elif kind == MATERIAL_ENV_MAP_INTENSITY:
        number = material.env_map_intensity
    elif kind == MATERIAL_CLEARCOAT:
        number = material.clearcoat
    elif kind == MATERIAL_CLEARCOAT_ROUGHNESS:
        number = material.clearcoat_roughness
    elif kind == MATERIAL_SPECULAR_INTENSITY:
        number = material.specular_intensity
    else:
        number = material.ior
    return [number, 0, 0, 0]


def _axis(vector: Vector3, axis: Int) -> Float32:
    """Return one number of a vector: 0 for x, 1 for y, 2 for z."""
    if axis == 0:
        return vector.x
    if axis == 1:
        return vector.y
    return vector.z


def _with_axis(vector: Vector3, axis: Int, value: Float32) -> Vector3:
    """Return a vector with one number replaced."""
    var out = vector
    if axis == 0:
        out.x = value
    elif axis == 1:
        out.y = value
    else:
        out.z = value
    return out


def _euler_axis(turn: Quaternion, axis: Int) raises -> Float32:
    """Return one angle of a turn read as x, y and z angles, in radians,
    three.js's `rotation[axis]`."""
    var angles = Euler.from_quaternion(turn)
    if axis == 0:
        return angles.x.to(RADIAN)
    if axis == 1:
        return angles.y.to(RADIAN)
    return angles.z.to(RADIAN)


def _with_euler_axis(
    turn: Quaternion, axis: Int, radians: Float32
) raises -> Quaternion:
    """Return a turn with one of its x, y and z angles replaced, as setting
    three.js's `rotation[axis]` turns its quaternion."""
    var angles = Euler.from_quaternion(turn)
    if axis == 0:
        angles.x = Angle(radians, RADIAN)
    elif axis == 1:
        angles.y = Angle(radians, RADIAN)
    else:
        angles.z = Angle(radians, RADIAN)
    return angles.to_quaternion()


def _map_of(assets: Assets, target: TrackTarget) raises -> TextureId:
    """Return the texture a map track's material wears as its map.

    Raises:
        Error: If the material has no map, or names a texture the assets
            do not have. three.js cannot bind `.map` there either.
    """
    var map = assets.materials.materials[target.index].map
    if map == NO_TEXTURE:
        raise Error("A map track needs a material with a map")
    if map.value < 0 or map.value >= assets.textures.count():
        raise Error("A map track's material names a texture that is not there")
    return map


def _read_camera(cameras: CameraList, target: TrackTarget) -> List[Float32]:
    """Return a camera's field of view in degrees, its zoom, or one of its
    planes in meters, as the `PILE` numbers a pile holds."""
    var kind = target.kind
    var number: Float32
    if target.slot == ORTHOGRAPHIC_SLOT:
        ref lens = cameras.orthographic[target.index]
        number = lens.zoom
        if kind == CAMERA_NEAR:
            number = lens.near.to(METER)
        elif kind == CAMERA_FAR:
            number = lens.far.to(METER)
        return [number, 0, 0, 0]
    ref eye = cameras.perspective[target.index]
    number = eye.zoom
    if kind == CAMERA_FOV:
        number = eye.fov.to(DEGREE)
    elif kind == CAMERA_NEAR:
        number = eye.near.to(METER)
    elif kind == CAMERA_FAR:
        number = eye.far.to(METER)
    return [number, 0, 0, 0]


def _write_camera(
    mut cameras: CameraList, target: TrackTarget, value: Float32
) raises:
    """Write a camera's field of view, zoom or plane, refusing a value the
    camera cannot hold.

    A field of view must be above zero and below half a turn, a zoom above
    zero, a near plane in front of a perspective camera, and the far plane
    beyond the near plane. three.js leaves the camera's projection to be
    updated by hand after a track moves it; here the projection is worked
    out when it is asked for, so it follows the track.
    """
    var kind = target.kind
    if not isfinite(value):
        raise Error("An animation drove a camera to a value it cannot hold")
    if kind == CAMERA_ZOOM and value <= 0:
        raise Error("An animation drove a camera's zoom to zero or below")
    if target.slot == ORTHOGRAPHIC_SLOT:
        ref lens = cameras.orthographic[target.index]
        var near = lens.near.to(METER)
        var far = lens.far.to(METER)
        if kind == CAMERA_ZOOM:
            lens.zoom = value
        elif kind == CAMERA_NEAR:
            near = value
        else:
            far = value
        if far <= near:
            raise Error("An animation drove a camera's far plane to its near")
        lens.near = Length(near, METER)
        lens.far = Length(far, METER)
        return
    ref eye = cameras.perspective[target.index]
    var near = eye.near.to(METER)
    var far = eye.far.to(METER)
    if kind == CAMERA_FOV:
        if value <= 0 or value >= 180:
            raise Error(
                "An animation drove a camera's field of view outside zero to"
                " half a turn"
            )
        eye.fov = Angle(value, DEGREE)
    elif kind == CAMERA_ZOOM:
        eye.zoom = value
    elif kind == CAMERA_NEAR:
        near = value
    else:
        far = value
    if near <= 0 or far <= near:
        raise Error(
            "An animation drove a camera's near plane behind it or its far"
            " plane to its near"
        )
    eye.near = Length(near, METER)
    eye.far = Length(far, METER)


def _node_of(
    scene: Scene, target: TrackTarget, cameras: CameraList = CameraList()
) -> NodeId:
    """Return the node a target's property rides: its own node, a mesh's
    node, a light's node, a camera's node, or `NO_PARENT` for a material,
    which rides none."""
    if target.kind.is_node():
        return NodeId(target.index)
    if target.kind.is_camera():
        if target.slot == ORTHOGRAPHIC_SLOT:
            return cameras.orthographic[target.index].node
        return cameras.perspective[target.index].node
    if target.kind.is_skinned():
        return scene.skinned_meshes[target.index].node
    if target.kind.is_morph():
        return scene.meshes[target.index].node
    if target.kind.is_light():
        return scene.lights[target.index].node
    return NO_PARENT


def write_target(
    mut scene: Scene,
    mut assets: Assets,
    target: TrackTarget,
    values: List[Float32],
    at: Int,
) raises:
    """Write one property from the numbers of a pile, with no cameras.

    Args:
        scene: The scene the nodes, meshes and lights are in.
        assets: The assets the materials are in.
        target: The property. The caller has checked its index.
        values: The numbers to write, `PILE` of them per entry.
        at: Where this property's numbers start in `values`.

    Raises:
        Error: As the version that takes the cameras does.
    """
    var none = CameraList()
    write_target(scene, assets, none, target, values, at)


def write_target(
    mut scene: Scene,
    mut assets: Assets,
    mut cameras: CameraList,
    target: TrackTarget,
    values: List[Float32],
    at: Int,
    strings: List[String] = List[String](),
) raises:
    """Write one property from the numbers of a pile.

    The one place a property is set, so the pose the actions make and the
    pose a released binding goes back to cannot drift apart. Nothing is
    written to a node out of the scene, or to a mesh, a light or a camera
    on one.

    Args:
        scene: The scene the nodes, meshes and lights are in.
        assets: The assets the materials are in.
        cameras: The cameras a camera target names.
        target: The property. The caller has checked its index.
        values: The numbers to write, `PILE` of them per entry.
        at: Where this property's numbers start in `values`.
        strings: The mixer's strings, which a string property's number
            is the place of.

    Raises:
        Error: If the scene has no such node, or the value is one the
            property cannot hold: a morph influence that is not a number,
            a color channel outside zero to one, a light intensity below
            zero, a light distance, angle or penumbra that `Light.validate`
            refuses, a material number outside the range `Material`
            accepts for it, a camera number the camera cannot hold, or a
            string that is not in `strings`.
    """
    var kind = target.kind
    if not scene.in_scene(_node_of(scene, target, cameras)):
        return
    if kind.is_camera():
        _write_camera(cameras, target, values[at])
        return
    if kind.is_string():
        var place = Int(values[at])
        if place < 0 or place >= len(strings):
            raise Error(
                "An animation drove a name to a string it does not hold"
            )
        scene.node(NodeId(target.index)).name = strings[place]
        return
    if kind.is_node():
        ref placed = scene.node(NodeId(target.index))
        if kind == POSITION_ELEMENT:
            placed.position = _with_axis(
                placed.position, target.slot, values[at]
            )
        elif kind == SCALE_ELEMENT:
            placed.scale = _with_axis(placed.scale, target.slot, values[at])
        elif kind == ROTATION_ELEMENT:
            placed.quaternion = _with_euler_axis(
                placed.quaternion, target.slot, values[at]
            )
        elif kind == POSITION:
            placed.position = Vector3(
                values[at], values[at + 1], values[at + 2]
            )
        elif kind == SCALE:
            placed.scale = Vector3(values[at], values[at + 1], values[at + 2])
        elif kind == QUATERNION:
            placed.quaternion = Quaternion(
                values[at], values[at + 1], values[at + 2], values[at + 3]
            )
        else:
            placed.visible = values[at] >= 0.5
        return
    if kind.is_skinned():
        scene.skinned_meshes[target.index].set_morph_influence(
            target.slot, values[at]
        )
        return
    if kind.is_morph():
        scene.meshes[target.index].set_morph_influence(target.slot, values[at])
        return
    if kind.is_light():
        ref light = scene.lights[target.index]
        if kind == LIGHT_COLOR:
            light.color = pile_to_color(
                values, at, light.color.a, "a light's color"
            )
        elif kind == LIGHT_INTENSITY:
            light.intensity = checked_value(
                values[at], 0, inf[DType.float32](), "a light's intensity"
            )
        else:
            if kind == LIGHT_DISTANCE:
                light.distance = values[at]
            elif kind == LIGHT_ANGLE:
                light.angle = Angle(values[at], RADIAN)
            else:
                light.penumbra = values[at]
            light.validate()
        return
    ref material = assets.materials.materials[target.index]
    if kind.is_map():
        var map = _map_of(assets, target)
        ref laid = assets.textures.textures[map.value]
        if kind == MATERIAL_MAP_OFFSET:
            laid.offset = Vector2(values[at], values[at + 1])
        elif kind == MATERIAL_MAP_REPEAT:
            laid.repeat = Vector2(values[at], values[at + 1])
        elif kind == MATERIAL_MAP_CENTER:
            laid.center = Vector2(values[at], values[at + 1])
        else:
            laid.rotation = Angle(values[at], RADIAN)
        return
    if kind == MATERIAL_TRANSPARENT:
        material.transparent = values[at] >= 0.5
        return
    if kind == MATERIAL_WIREFRAME:
        material.wireframe = values[at] >= 0.5
        return
    if kind == MATERIAL_COLOR:
        material.color = pile_to_color(
            values, at, material.color.a, "a material's color"
        )
        return
    if kind == MATERIAL_EMISSIVE:
        material.emissive = pile_to_color(
            values, at, material.emissive.a, "a material's emissive"
        )
        return
    if kind == MATERIAL_SPECULAR:
        material.specular = pile_to_color(
            values, at, material.specular.a, "a material's specular"
        )
        return
    var number = checked_value(
        values[at],
        material_number(kind, False),
        material_number(kind, True),
        "a material's number",
    )
    if kind == MATERIAL_OPACITY:
        material.opacity = number
    elif kind == MATERIAL_EMISSIVE_INTENSITY:
        material.emissive_intensity = number
    elif kind == MATERIAL_ROUGHNESS:
        material.roughness = number
    elif kind == MATERIAL_METALNESS:
        material.metalness = number
    elif kind == MATERIAL_SHININESS:
        material.shininess = number
    elif kind == MATERIAL_ALPHA_TEST:
        material.alpha_test = number
    elif kind == MATERIAL_REFLECTIVITY:
        material.reflectivity = number
    elif kind == MATERIAL_ENV_MAP_INTENSITY:
        material.env_map_intensity = number
    elif kind == MATERIAL_CLEARCOAT:
        material.clearcoat = number
    elif kind == MATERIAL_CLEARCOAT_ROUGHNESS:
        material.clearcoat_roughness = number
    elif kind == MATERIAL_SPECULAR_INTENSITY:
        material.specular_intensity = number
    else:
        material.ior = number


def check_target(
    scene: Scene,
    assets: Assets,
    has_assets: Bool,
    target: TrackTarget,
    cameras: CameraList = CameraList(),
    has_cameras: Bool = False,
) raises:
    """Refuse a target that names nothing in the scene, the assets or the
    cameras.

    Args:
        scene: The scene the nodes, meshes and lights are in.
        assets: The assets the materials are in.
        has_assets: False when the caller gave no assets, so a material
            cannot be driven at all.
        target: The target to check.
        cameras: The cameras a camera target names.
        has_cameras: False when the caller gave no cameras, so a camera
            cannot be driven at all.

    Raises:
        Error: If the target's kind is none of the named ones or its slot
            does not fit it, or its index is below zero or past the end of
            the list it indexes, or it drives a material and there are no
            assets, or a camera and there are no cameras.
    """
    if not target.is_valid():
        raise Error("A track needs a kind that exists and fits its slot")
    var kind = target.kind
    var count = scene.count()
    if kind.is_camera():
        if not has_cameras:
            raise Error(
                "A camera track needs the cameras: call update(scene,"
                " assets, cameras, delta)"
            )
        count = len(cameras.perspective)
        if target.slot == ORTHOGRAPHIC_SLOT:
            count = len(cameras.orthographic)
    elif kind.is_skinned():
        count = len(scene.skinned_meshes)
    elif kind.is_morph():
        count = len(scene.meshes)
    elif kind.is_light():
        count = len(scene.lights)
    elif kind.is_material():
        if not has_assets:
            raise Error(
                "A material track needs the assets: call update(scene,"
                " assets, delta)"
            )
        count = assets.materials.count()
    if target.index < 0 or target.index >= count:
        raise Error(
            "A track must name a node, a mesh, a light, a material or a"
            " camera that is there"
        )
    if kind.is_map():
        _ = _map_of(assets, target)


def resolve_targets(
    scene: Scene,
    target: TrackTarget,
    group: AnimationObjectGroup,
    cameras: CameraList = CameraList(),
) raises -> List[TrackTarget]:
    """Return the targets one track drives on the members of a group.

    Each member is to the track what the object is to a three.js path: the
    member node for a node kind, every mesh at the member for a morph
    influence, every skinned mesh at the member for a skinned morph
    influence, the material of every mesh at the member for a material
    kind, every light at the member for a light kind, and every camera at
    the member, of the list the track names, for a camera kind. A target
    reached twice is listed once.

    Args:
        scene: The scene the members are in.
        target: What the track names. Its kind and slot are kept, and its
            index is replaced.
        group: The members.
        cameras: The cameras a camera kind reaches.

    Returns:
        The targets, in the order of the members.

    Raises:
        Error: If a member is not in the scene.
    """
    var found = List[TrackTarget]()
    var kind = target.kind
    for member in range(group.count()):
        var node = group.members[member].value
        if node < 0 or node >= scene.count():
            raise Error("A group member must be a node in the scene")
        var reached = List[TrackTarget]()
        if kind.is_node():
            reached.append(TrackTarget(kind, node, target.slot))
        elif kind.is_light():
            for light in range(len(scene.lights)):
                if scene.lights[light].node.value == node:
                    reached.append(TrackTarget(kind, light, 0))
        elif kind.is_camera():
            for which in range(_camera_count(cameras, target.slot)):
                var lens = _node_of(
                    scene, TrackTarget(kind, which, target.slot), cameras
                )
                if lens.value == node:
                    reached.append(TrackTarget(kind, which, target.slot))
        elif kind.is_skinned():
            for mesh in range(len(scene.skinned_meshes)):
                if scene.skinned_meshes[mesh].node.value == node:
                    reached.append(TrackTarget(kind, mesh, target.slot))
        else:
            for mesh in range(len(scene.meshes)):
                if scene.meshes[mesh].node.value != node:
                    continue
                if kind.is_morph():
                    reached.append(TrackTarget(kind, mesh, target.slot))
                else:
                    reached.append(
                        TrackTarget(kind, scene.meshes[mesh].material.value, 0)
                    )
        for index in range(len(reached)):
            if find_target(found, reached[index]) < 0:
                found.append(reached[index])
    return found^


def _camera_count(cameras: CameraList, slot: Int) -> Int:
    """Return how many cameras the list a camera slot names holds."""
    if slot == ORTHOGRAPHIC_SLOT:
        return len(cameras.orthographic)
    return len(cameras.perspective)


struct Binding(Copyable, Movable):
    """One property the mixer drives, and the value it held before,
    three.js's `PropertyBinding` and the original a `PropertyMixer` saves.

    Kept for as long as the mixer is, because it is the pose a weight of
    less than one blends back toward. Reading the node instead would read
    back what the mixer wrote last frame.
    """

    # The node, mesh, material or light, as its index; `kind` says which.
    var node: Int
    var kind: Int
    # Which morph target, for `MORPH_INFLUENCE`; zero for every other kind.
    var slot: Int
    var original: List[Float32]
    # Whether anything drove this property in the last update. The frame
    # after it goes false, the original is written back and the mixer
    # leaves the property alone; see the module docstring.
    var driven: Bool

    def __init__(
        out self,
        node: Int,
        kind: Int,
        var original: List[Float32],
        slot: Int = 0,
    ):
        """Remember what one property held.

        Args:
            node: Which node, mesh, material or light.
            kind: Which property.
            original: The `PILE` numbers it held.
            slot: Which morph target, for `MORPH_INFLUENCE`.
        """
        self.node = node
        self.kind = kind
        self.slot = slot
        self.original = original^
        self.driven = False

    def target(self) -> TrackTarget:
        """Return the property this binding is for, as a target."""
        return TrackTarget(TrackKind(self.kind), self.node, self.slot)


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
    # How the action's values join the others', three.js's `blendMode`.
    # The clip's own unless changed.
    var blend_mode: AnimationBlendMode
    # The nodes the action plays on instead of the targets its tracks
    # name, three.js's group given to `clipAction`, when `grouped` is True.
    var group: AnimationObjectGroup
    var grouped: Bool
    # Whether a `SMOOTH` track is flat, rather than unbent, at the start
    # and at the end of a clip that does not run on past it. three.js's
    # `zeroSlopeAtStart` and `zeroSlopeAtEnd`, True by default as there.
    var zero_slope_at_start: Bool
    var zero_slope_at_end: Bool
    # The ending modes a `SMOOTH` track is read with, three.js's
    # `_interpolantSettings`. Set by `_move` from the loop mode.
    var ending_start: Ending
    var ending_end: Ending
    # Whether the action has been counted since it was built or stopped,
    # three.js's `_loopCount` being other than -1: a `ONCE` action once it
    # moves, a repeating one once it first wraps.
    var started: Bool
    # How many ends of the clip a repeating action has run past, three.js's
    # `_loopCount`: -1 until it first wraps. Kept in step with `started`.
    var loop_count: Int
    # How many times a `REPEAT` or `PING_PONG` action runs through its
    # clip before it finishes, three.js's `repetitions`. None, the
    # default, repeats without end, three.js's `Infinity`. A `PING_PONG`
    # leg is one repetition.
    var repetitions: Optional[Int]
    # The node the action was filed under, three.js's `_localRoot`, or
    # `NO_PARENT` for the mixer's own root. See `AnimationMixer.add`.
    var root: NodeId

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
        self.blend_mode = clip.blend_mode
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
        self.group = AnimationObjectGroup()
        self.grouped = False
        self.zero_slope_at_start = True
        self.zero_slope_at_end = True
        self.ending_start = ZERO_CURVATURE_ENDING
        self.ending_end = ZERO_CURVATURE_ENDING
        self.started = False
        self.loop_count = -1
        self.repetitions = None
        self.root = NO_PARENT

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
        self.blend_mode = copy.blend_mode
        self.group = AnimationObjectGroup(copy=copy.group)
        self.grouped = copy.grouped
        self.zero_slope_at_start = copy.zero_slope_at_start
        self.zero_slope_at_end = copy.zero_slope_at_end
        self.ending_start = copy.ending_start
        self.ending_end = copy.ending_end
        self.started = copy.started
        self.loop_count = copy.loop_count
        self.repetitions = copy.repetitions
        self.root = copy.root

    def use_group(mut self, var group: AnimationObjectGroup):
        """Play every track on every member of a group instead of on the
        target the track names, three.js's `clipAction` given a group.

        Args:
            group: The members, consumed.
        """
        self.group = group^
        self.grouped = True

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
        three.js's `stop`: `reset`, and no longer active.
        """
        self.active = False
        self.reset()

    def reset(mut self):
        """Rewind the action and forget its loops, three.js's `reset`.

        It unpauses the action, drops any fade, warp or start time that
        was scheduled, and leaves whether it is active as it is. three.js's
        `reset` also enables the action; here `active` is both three.js's
        `enabled` and its being scheduled, so `play` does that.
        """
        self.paused = False
        self.phase = 0
        self.started = False
        self.loop_count = -1
        self.scheduled = False
        self.stop_fading()
        self.stop_warping()

    def set_loop(
        mut self, loop: Loop, repetitions: Optional[Int] = None
    ) raises:
        """Set what the action does at the end of its clip, and how many
        times it repeats, three.js's `setLoop`.

        Args:
            loop: `ONCE`, `REPEAT` or `PING_PONG`.
            repetitions: How many times a `REPEAT` or `PING_PONG` action
                runs through its clip, a `PING_PONG` leg being one. None,
                the default, repeats without end, as three.js's `Infinity`
                does. A `ONCE` action ignores it.

        Raises:
            Error: If the loop mode is none of the three, or the
                repetitions are below zero.
        """
        if not loop.is_valid():
            raise Error("An action needs a loop mode that exists")
        if Bool(repetitions):
            if repetitions.value() < 0:
                raise Error("An action cannot repeat fewer than zero times")
        self.loop = loop
        self.repetitions = repetitions

    def set_duration(mut self, duration: Duration) raises:
        """Set the time scale so that one run through the clip lasts
        `duration`, and stop any warp, three.js's `setDuration`.

        Args:
            duration: How long one run through the clip lasts; not zero. A
                negative duration runs the clip backward, as the time
                scale it makes does in three.js.

        Raises:
            Error: If the duration is zero or is not a number.
        """
        var seconds = duration.to(SECOND)
        if not isfinite(seconds) or seconds == 0:
            raise Error("An action's duration must be a number other than zero")
        self.time_scale = self.clip.duration().to(SECOND) / seconds
        self.stop_warping()

    def sync_with(mut self, other: AnimationAction):
        """Take another action's place in its clip and its time scale, and
        stop any warp, three.js's `syncWith`.

        The place is the other action's phase. For `PING_PONG` that says
        which leg it is on as well; three.js copies the time alone and
        keeps its own leg.

        Args:
            other: The action to keep in step with.
        """
        self.phase = other.phase
        self.time_scale = other.time_scale
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

    def _set_endings(mut self, at_start: Bool, at_end: Bool, ping_pong: Bool):
        """Set the ending modes a `SMOOTH` track is read with, three.js's
        `_setEndings`.

        An end the clip does not run on past is flat, or unbent if the
        action's `zero_slope_at_` flag for it is False. An end it runs on
        past wraps around to the other end. A `PING_PONG` clip turns back
        at both ends, so both are flat.
        """
        if ping_pong:
            self.ending_start = ZERO_SLOPE_ENDING
            self.ending_end = ZERO_SLOPE_ENDING
            return
        self.ending_start = WRAP_AROUND_ENDING
        if at_start:
            self.ending_start = (
                ZERO_SLOPE_ENDING if self.zero_slope_at_start else ZERO_CURVATURE_ENDING
            )
        self.ending_end = WRAP_AROUND_ENDING
        if at_end:
            self.ending_end = (
                ZERO_SLOPE_ENDING if self.zero_slope_at_end else ZERO_CURVATURE_ENDING
            )

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
        var ping_pong = self.loop == PING_PONG
        if self.loop == ONCE:
            if not self.started:
                self.started = True
                self.loop_count = 0
                self._set_endings(True, True, False)
            if moved >= length:
                moved = length
                self._finish(moved_by)
            if moved < 0:
                moved = 0
                self._finish(moved_by)
            self.phase = moved
            return
        # three.js leaves a clip uncounted, its `_loopCount` at -1, until
        # it first wraps, whichever way it ran before that. A pass backward
        # through zero then wraps to the end, for `PING_PONG` as for
        # `REPEAT`, so a clip run backward plays backward. Here that is a
        # leg's worth of phase: without it the pass turned round, and the
        # clip ran forward under a negative time scale.
        var wraps_first = ping_pong and not self.started and moved_by < 0
        var none_left = Bool(self.repetitions) and self.repetitions.value() == 0
        # three.js's `_loopCount`: a clip run forward counts from zero as it
        # starts, and one run backward from -1, so its first pass through
        # zero is not a repetition.
        var count = self.loop_count
        if not self.started:
            # A clip that repeats runs on past the end it is heading for,
            # unless it repeats no times at all, and is flat at the end it
            # left.
            if moved_by > 0:
                count = 0
                self._set_endings(True, none_left, ping_pong)
            else:
                self._set_endings(none_left, True, ping_pong)
        # Each end of the clip passed is one of three.js's loops, for
        # `PING_PONG` as much as for `REPEAT`: the phase has one end every
        # clip's length, whichever leg it is on.
        var from_end = Int(floor(self.phase / length))
        self.loop_delta = Int(floor(moved / length)) - from_end
        if self.loop_delta != 0:
            if Bool(self.repetitions):
                var pending = self.repetitions.value() - count
                if pending <= abs(self.loop_delta):
                    self._finish_repeating(moved_by, from_end, pending)
                    return
                if pending == abs(self.loop_delta) + 1:
                    # Entering the last run, which does not run on past
                    # the end it is heading for.
                    var at_start = moved_by < 0
                    self._set_endings(at_start, not at_start, ping_pong)
                else:
                    self._set_endings(False, False, ping_pong)
            else:
                self._set_endings(False, False, ping_pong)
            self.started = True
            self.loop_count = count + abs(self.loop_delta)
            if wraps_first:
                moved += length
        self.direction = -1 if moved_by < 0 else 1
        var period = length
        if ping_pong:
            # The phase runs over the whole there-and-back, and `at` folds
            # it. Folding it here instead would lose which leg it is on.
            period = length * 2
        moved -= floor(moved / period) * period
        self.phase = moved

    def _finish_repeating(
        mut self, moved_by: Float32, from_end: Int, pending: Int
    ):
        """End a `REPEAT` or `PING_PONG` action whose last repetition ran
        out during this move, three.js's `finished` branch of
        `_updateTime`.

        The action stops at the end of the clip it ran to: the end for a
        `REPEAT` action run forward, the start run backward. A
        `PING_PONG` action stops at whichever end the leg that ran out was
        heading for. three.js reads the other end in the update that
        finishes a `PING_PONG` action, and the right one from the next
        update on; here the right one is read in both.

        Args:
            moved_by: The move, in seconds of clip time.
            from_end: Which end of the clip, counted in clip lengths, the
                phase was past before the move.
            pending: How many ends the action had left to run past, the
                last of them the one it stops at; at least zero.
        """
        var length = self.clip.duration().to(SECOND)
        self.loop_delta = 0
        self._finish(moved_by)
        if self.loop != PING_PONG:
            self.phase = length if moved_by > 0 else Float32(0)
            return
        # The ends the move runs past are at whole clip lengths of phase,
        # the next one forward `from_end + 1` and the next one back
        # `from_end`. The one it stops at is the last it had left, and at
        # least the first. An even end is the start of the clip and an odd
        # one its end, since the phase runs there and back.
        var ends = max(pending, 1)
        var stop = from_end + ends if moved_by > 0 else from_end - ends + 1
        self.phase = length if stop % 2 != 0 else Float32(0)

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
    # How much time the mixer has been given, in seconds, after its time
    # scale.
    var elapsed: Float32
    # What happened to the actions during the last update, three.js's
    # `loop` and `finished` events. Each update starts a new list.
    var events: List[AnimationEvent]
    # How fast the mixer's clock runs, three.js's `timeScale`: every
    # update's delta is multiplied by it. Zero stops every action, and a
    # negative number runs them all backward.
    var time_scale: Float32
    # The node the mixer was made for, three.js's `_root`, or `NO_PARENT`
    # for the whole scene. A track names its target by index, so the root
    # does not scope a lookup as three.js's does; it is what actions are
    # filed under.
    var root: NodeId
    # Whether each action has been uncached, by index. An uncached action
    # keeps its index, so no other index moves, and cannot be reached.
    var uncached: List[Bool]
    # Every string a string property has held or been driven to, each
    # once. A string pile holds a place here, so a string mixes as a flag
    # does.
    var strings: List[String]

    def __init__(out self, root: NodeId = NO_PARENT):
        """Create a mixer with nothing playing.

        Args:
            root: The node the mixer is for, three.js's `root`, or
                `NO_PARENT`, the default, for the whole scene.
        """
        self.actions = List[AnimationAction]()
        self.bindings = List[Binding]()
        self.elapsed = 0
        self.events = List[AnimationEvent]()
        self.time_scale = 1
        self.root = root
        self.uncached = List[Bool]()
        self.strings = List[String]()

    def add(
        mut self, var action: AnimationAction, root: NodeId = NO_PARENT
    ) -> Int:
        """Add an action and return the index it was given.

        Args:
            action: The action, consumed. three.js's `clipAction` makes one
                and remembers it; here the caller makes it and this keeps
                it.
            root: The node the action is filed under, three.js's
                `optionalRoot`, or `NO_PARENT`, the default, for the
                mixer's own root. `existing_action` and `uncache_root`
                find it by it.

        Returns:
            Which action it is, for `action`.
        """
        action.now = self.elapsed
        action.root = root
        self.actions.append(action^)
        self.uncached.append(False)
        return len(self.actions) - 1

    def action_count(self) -> Int:
        """Return how many actions the mixer holds, the uncached ones
        included, since they keep their indices."""
        return len(self.actions)

    def get_root(self) -> NodeId:
        """Return the node the mixer was made for, three.js's `getRoot`, or
        `NO_PARENT` for the whole scene."""
        return self.root

    def _check_index(self, index: Int) raises:
        """Refuse an index that names no action, or an uncached one."""
        if index < 0 or index >= len(self.actions):
            raise Error("The mixer has no action at that index")
        if self.uncached[index]:
            raise Error("The mixer uncached the action at that index")

    def existing_action(
        self, clip_name: String, root: NodeId = NO_PARENT
    ) -> Optional[Int]:
        """Return the action on a clip, three.js's `existingAction`.

        Args:
            clip_name: The clip's name. three.js finds a clip by its uuid or
                by its name; a clip here has no uuid.
            root: The node the action was filed under by `add`, or
                `NO_PARENT`, the default, for the mixer's own root.

        Returns:
            The first action on a clip of that name filed under that root
            and not uncached, or None if there is none.
        """
        for index in range(len(self.actions)):
            if self.uncached[index]:
                continue
            if self.actions[index].root != root:
                continue
            if self.actions[index].clip.name == clip_name:
                return index
        return None

    def stop_all_action(mut self):
        """Stop every action that is active, three.js's `stopAllAction`;
        see `AnimationAction.stop`."""
        for index in range(len(self.actions)):
            if self.actions[index].active:
                self.actions[index].stop()

    def sync_with(mut self, index: Int, with_index: Int) raises:
        """Put one action in step with another, three.js's `syncWith`; see
        `AnimationAction.sync_with`.

        Args:
            index: The action to move.
            with_index: The action to keep in step with.

        Raises:
            Error: If either index names no action or an uncached one.
        """
        self._check_index(index)
        self._check_index(with_index)
        var other = self.actions[with_index].copy()
        self.actions[index].sync_with(other)

    def uncache_action(mut self, index: Int) raises:
        """Forget one action, three.js's `uncacheAction`.

        The action stops contributing, and its clip's tracks are let go.
        Its index stays its own, so no other action's index moves, and
        `action` refuses it. A property it drove goes back to what it held
        in the next update, as it does after `stop`. Then every property
        that nothing drives is forgotten; see `uncache_clip`.

        Args:
            index: Which action, as `add` returned it.

        Raises:
            Error: If there is no action at that index, or it is already
                uncached.
        """
        self._check_index(index)
        self.actions[index].active = False
        self.actions[index].clip.tracks = List[KeyframeTrack]()
        self.uncached[index] = True
        self._prune()

    def uncache_action(
        mut self, clip_name: String, root: NodeId = NO_PARENT
    ) raises:
        """Forget the action `existing_action` finds, three.js's
        `uncacheAction(clip, root)`.

        Args:
            clip_name: The clip's name.
            root: The node the action was filed under.

        Raises:
            Error: If there is no such action.
        """
        var found = self.existing_action(clip_name, root)
        if not Bool(found):
            raise Error("The mixer has no action on a clip of that name")
        self.uncache_action(found.value())

    def uncache_clip(mut self, clip_name: String):
        """Forget every action on a clip, three.js's `uncacheClip`.

        Each action is forgotten as `uncache_action` forgets it. Then
        every binding that nothing drove in the last update is dropped: it
        holds nothing the mixer needs, since a property is read again when
        something next drives it. three.js drops only the bindings of the
        actions it forgets.

        Args:
            clip_name: The clip's name.
        """
        for index in range(len(self.actions)):
            if self.uncached[index]:
                continue
            if self.actions[index].clip.name == clip_name:
                self.actions[index].active = False
                self.actions[index].clip.tracks = List[KeyframeTrack]()
                self.uncached[index] = True
        self._prune()

    def uncache_root(mut self, root: NodeId):
        """Forget every action filed under a root, three.js's
        `uncacheRoot`; see `uncache_clip`.

        Args:
            root: The node the actions were filed under by `add`, or
                `NO_PARENT` for the mixer's own root.
        """
        for index in range(len(self.actions)):
            if self.uncached[index]:
                continue
            if self.actions[index].root == root:
                self.actions[index].active = False
                self.actions[index].clip.tracks = List[KeyframeTrack]()
                self.uncached[index] = True
        self._prune()

    def _prune(mut self):
        """Drop every binding that nothing drove in the last update."""
        var kept = List[Binding]()
        for slot in range(len(self.bindings)):
            if self.bindings[slot].driven:
                kept.append(self.bindings[slot].copy())
        self.bindings = kept^

    def _intern(mut self, text: String) -> Float32:
        """Return the place of a string in the mixer's strings, adding it
        the first time it is seen."""
        for place in range(len(self.strings)):
            if self.strings[place] == text:
                return Float32(place)
        self.strings.append(text)
        return Float32(len(self.strings) - 1)

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
        self._check_index(index)
        return self.actions[index]

    def time(self) -> Duration:
        """Return how much time the mixer has been given in all, after its
        time scale."""
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
            Error: If either index names no action or an uncached one, the
                two are the same action, `duration` is negative or is not
                a number, or `warp` is True and either time scale is zero.
                Nothing is changed when it raises.
        """
        self._check_index(index)
        self._check_index(from_index)
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

    def _binding(self, target: TrackTarget) -> Int:
        """Return where the binding for one property is, or minus one when
        the mixer has not taken it over yet."""
        for slot in range(len(self.bindings)):  # pragma: no branch
            if self.bindings[slot].target() == target:
                return slot
        return -1

    def _bind(
        mut self,
        scene: Scene,
        assets: Assets,
        has_assets: Bool,
        cameras: CameraList,
        has_cameras: Bool,
        target: TrackTarget,
    ) raises -> Int:
        """Remember what one property holds, each time something starts to
        drive it, and return where its binding is.

        Read again when a released property is driven again, not only the
        first time: three.js's `PropertyMixer.saveOriginalState` runs
        whenever a binding's use count rises from zero, so a node the
        caller moved while nothing drove it is blended toward, and put
        back to, where the caller left it. Reading it once and keeping it
        threw the caller's edit away.

        Raises:
            Error: If the target names nothing in the scene, the assets or
                the cameras.
        """
        check_target(scene, assets, has_assets, target, cameras, has_cameras)
        var known = self._binding(target)
        if known >= 0 and self.bindings[known].driven:
            return known
        var original: List[Float32]
        if target.kind.is_string():
            original = [
                self._intern(scene.get(NodeId(target.index)).name),
                0,
                0,
                0,
            ]
        else:
            original = read_target(scene, assets, target, cameras)
        if known >= 0:
            self.bindings[known].original = original^
            self.bindings[known].driven = True
            return known
        var made = Binding(
            target.index, target.kind.value, original^, target.slot
        )
        made.driven = True
        self.bindings.append(made^)
        return len(self.bindings) - 1

    def update(mut self, mut scene: Scene, delta: Duration) raises:
        """Move every playing action on by `delta`, and write what the
        actions make into the scene.

        The same as the update that takes the assets, for clips that drive
        nothing in them: nodes, meshes and lights are in the scene.

        Args:
            scene: The scene whose nodes, meshes and lights the tracks name.
            delta: How much real time has passed since the last update.

        Raises:
            Error: As the update that takes the assets does, and if a track
                drives a material, which is in the assets.
        """
        var none = Assets()
        var no_cameras = CameraList()
        self._update(scene, none, False, no_cameras, False, delta)

    def update(
        mut self, mut scene: Scene, mut assets: Assets, delta: Duration
    ) raises:
        """Move every playing action on by `delta`, and write what the
        actions make into the scene and the assets.

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
            scene: The scene whose nodes, meshes and lights the tracks name.
            assets: The assets whose materials the tracks name.
            delta: How much real time has passed since the last update.

        Raises:
            Error: If `delta` or the mixer's time scale is not a number, an
                action's blend mode is neither of the two, a track names
                something the scene or the assets do not have, a track
                drives a camera, a group member is not in the scene, or a
                value written is one its property cannot hold.
        """
        var no_cameras = CameraList()
        self._update(scene, assets, True, no_cameras, False, delta)

    def update(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        mut cameras: CameraList,
        delta: Duration,
    ) raises:
        """Move every playing action on by `delta`, and write what the
        actions make into the scene, the assets and the cameras.

        Args:
            scene: The scene whose nodes, meshes and lights the tracks name.
            assets: The assets whose materials the tracks name.
            cameras: The cameras whose field of view, zoom and planes the
                tracks name.
            delta: How much real time has passed since the last update.

        Raises:
            Error: As the update that takes the assets does, but for a
                track that drives a camera.
        """
        self._update(scene, assets, True, cameras, True, delta)

    def _zero_time(mut self):
        """Set the mixer's clock and every action's time to zero, the first
        half of three.js's `setTime`."""
        self.elapsed = 0
        for index in range(len(self.actions)):
            self.actions[index].phase = 0

    def set_time(mut self, mut scene: Scene, time: Duration) raises:
        """Play every action from its start to `time`, three.js's `setTime`.

        The mixer's clock and each action's time go to zero, and one update
        then moves them on by `time`. Fades, warps and start times are
        read on the new clock.

        Args:
            scene: The scene whose nodes, meshes and lights the tracks name.
            time: Where to put the actions.

        Raises:
            Error: As `update` does.
        """
        self._zero_time()
        self.update(scene, time)

    def set_time(
        mut self, mut scene: Scene, mut assets: Assets, time: Duration
    ) raises:
        """Play every action from its start to `time`, three.js's `setTime`,
        with the assets the tracks can name.

        Args:
            scene: The scene whose nodes, meshes and lights the tracks name.
            assets: The assets whose materials the tracks name.
            time: Where to put the actions.

        Raises:
            Error: As `update` does.
        """
        self._zero_time()
        self.update(scene, assets, time)

    def set_time(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        mut cameras: CameraList,
        time: Duration,
    ) raises:
        """Play every action from its start to `time`, three.js's `setTime`,
        with the assets and the cameras the tracks can name.

        Args:
            scene: The scene whose nodes, meshes and lights the tracks name.
            assets: The assets whose materials the tracks name.
            cameras: The cameras the tracks name.
            time: Where to put the actions.

        Raises:
            Error: As `update` does.
        """
        self._zero_time()
        self.update(scene, assets, cameras, time)

    def _update(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        has_assets: Bool,
        mut cameras: CameraList,
        has_cameras: Bool,
        delta: Duration,
    ) raises:
        """Run one update; see `update`."""
        if not isfinite(self.time_scale):
            raise Error("A mixer's time scale must be a number")
        # three.js's `update` multiplies the delta by the time scale
        # before anything else sees it.
        var seconds = delta.to(SECOND) * self.time_scale
        if not isfinite(seconds):
            raise Error("A mixer cannot advance by a time that is not a number")
        self.elapsed += seconds
        self.events = List[AnimationEvent]()

        var targets = List[TrackTarget]()
        var weights = List[Float32]()
        var piles = List[Float32]()
        var added = List[Float32]()
        var additive = List[Float32]()

        for index in range(len(self.actions)):  # pragma: no branch
            if self.uncached[index]:
                continue
            if not self.actions[index].active:
                # Kept in step all the same, so a fade or a warp scheduled
                # on it before it plays starts at the mixer's time now.
                self.actions[index].now = self.elapsed
                self.actions[index].applied_weight = 0
                continue
            if not self.actions[index].blend_mode.is_valid():
                raise Error("An action needs a blend mode that exists")
            var share = self.actions[index]._tick(self.elapsed, seconds)
            self._record(index)
            if share <= 0:
                continue
            var at = self.actions[index].at()
            var adds = self.actions[index].blend_mode == ADDITIVE_BLEND_MODE
            for which in range(
                self.actions[index].clip.track_count()
            ):  # pragma: no branch
                var named = self.actions[index].clip.tracks[which].target
                var kind = named.kind
                var value = (
                    self.actions[index]
                    .clip.tracks[which]
                    .sample(
                        at,
                        self.actions[index].ending_start,
                        self.actions[index].ending_end,
                    )
                )
                if kind.is_string():
                    var place = Int(value[0])
                    var text = String(
                        self.actions[index].clip.tracks[which].strings[place]
                    )
                    value[0] = self._intern(text)
                var reached: List[TrackTarget] = [named]
                if self.actions[index].grouped:
                    reached = resolve_targets(
                        scene, named, self.actions[index].group, cameras
                    )
                for each in range(len(reached)):
                    var target = reached[each]
                    var held = self._bind(
                        scene, assets, has_assets, cameras, has_cameras, target
                    )
                    var slot = find_target(targets, target)
                    if slot < 0:
                        slot = len(targets)
                        targets.append(target)
                        weights.append(0)
                        added.append(0)
                        for _ in range(PILE):  # pragma: no branch
                            piles.append(0)
                            additive.append(0)
                    if adds:
                        if added[slot] == 0:
                            additive_identity(
                                additive,
                                slot,
                                self.bindings[held].original,
                                kind,
                            )
                        mix_additive_into_pile(
                            additive, slot, share, value, kind
                        )
                        added[slot] += share
                        continue
                    if weights[slot] == 0:
                        for offset in range(len(value)):  # pragma: no branch
                            piles[slot * PILE + offset] = value[offset]
                    else:
                        mix_into_pile(
                            piles, slot, weights[slot], share, value, kind
                        )
                    weights[slot] += share

        for slot in range(len(targets)):  # pragma: no branch
            var kind = targets[slot].kind
            var held = self._binding(targets[slot])
            if weights[slot] == 0:
                # Only additive actions drive it: they add onto the pose it
                # held, which is three.js's rest at a missing weight of one.
                for offset in range(PILE):  # pragma: no branch
                    piles[slot * PILE + offset] = self.bindings[held].original[
                        offset
                    ]
            elif weights[slot] < 1:
                rest_into_pile(
                    piles,
                    slot,
                    weights[slot],
                    self.bindings[held].original,
                    kind,
                )
            if added[slot] > 0:
                add_onto_pile(piles, slot, additive, kind)
            write_target(
                scene,
                assets,
                cameras,
                targets[slot],
                piles,
                slot * PILE,
                self.strings,
            )

        # Anything that was driven last frame and is not driven now goes
        # back to what it held before the mixer touched it, once, and is
        # then left alone. Without this a weight fading to zero stopped one
        # frame short of the pose it was fading toward, because a weight of
        # zero makes no pile and an empty pile writes nothing.
        for slot in range(len(self.bindings)):  # pragma: no branch
            if not self.bindings[slot].driven:
                continue
            if find_target(targets, self.bindings[slot].target()) >= 0:
                continue
            write_target(
                scene,
                assets,
                cameras,
                self.bindings[slot].target(),
                self.bindings[slot].original,
                0,
                self.strings,
            )
            self.bindings[slot].driven = False
