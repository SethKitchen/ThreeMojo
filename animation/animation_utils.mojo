# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cutting a clip down and making it additive, from three.js
`src/animation/AnimationUtils.js`: `subclip` and `makeClipAdditive`.

`getKeyframeOrder` and `sortedArray` are in `animation.animation_clip`,
beside the morph target sequences that use them. `convertArray`,
`isTypedArray` and `flattenJSON` are not ported: a track holds a
`List[Float32]` and nothing else, so there is no other array to convert
from, and three.js's `keys` form of a track is not read.

## subclip

A file often holds every move a model makes in one long clip, and a frame
range says where each move is. `subclip` keeps the keys whose frame, the
key's time times the frame rate, is at or after the first frame and before
the last, and moves them all back so the earliest kept key is at zero.
That is three.js's arithmetic, key for key: no key is made at the cut, so
a track is read between the keys it kept.

## make_clip_additive

An additive clip holds changes, not poses. `make_clip_additive` reads every
track of a reference clip at a reference frame and takes that value off
every key of the matching track: it subtracts a number or a color, and it
multiplies a rotation by the reference's conjugate on the left, so each key
becomes the turn from the reference to it. Played additively, the mixer
puts each change back on top of whatever the normal actions make. Flags
have no difference to take and are left as they are, as three.js leaves
them.

Tracks match when they drive the same target, which is three.js matching
them by name and type.

## Cubic spline tracks

A `CUBIC_SPLINE` key is three numbers deep: in-tangent, value and
out-tangent. `subclip` keeps all three of every key it keeps, as three.js
keeps a glTF key's whole stride. `make_clip_additive` changes the values
alone and leaves the tangents, as three.js does: a number less a constant
has the same slope. A rotation's tangents are left unturned, which is
three.js's arithmetic too.

## What differs from three.js

Both return a new clip. three.js's `makeClipAdditive` changes the clip it
is given, which suits a language where the caller keeps a reference to it;
here the clip given is borrowed and left alone.

three.js falls back to thirty frames a second when it is given a rate of
zero or less. Here such a rate is refused, since a caller who asked for it
asked for something else. A frame below zero is refused too.

A cubic spline reference read between two of its keys gives the value of
its curve there. three.js slices that value out of its result as though
the result held the tangents as well, which it does not, and takes off
nothing it can use: every key of the target comes out not a number.

A subclip is a clip and must last longer than no time, so a range that
keeps one key of every track, or none, is refused. three.js returns a
clip of no length and nothing can play it.
"""

from animation.animation_clip import ADDITIVE_BLEND_MODE, AnimationClip
from animation.keyframe_track import CUBIC_SPLINE, KeyframeTrack, QUATERNION
from math.quaternion import Quaternion
from std.math import isfinite
from units.si import Duration, SECOND


def checked_fps(fps: Float32) raises -> Float32:
    """Return a frame rate, refused if it is not one.

    Args:
        fps: Frames a second.

    Returns:
        The rate.

    Raises:
        Error: If the rate is not a number or is not above zero.
    """
    if not isfinite(fps) or fps <= 0:
        raise Error("A frame rate must be a number above zero")
    return fps


def subclip(
    source: AnimationClip,
    name: String,
    start_frame: Int,
    end_frame: Int,
    fps: Float32 = 30,
) raises -> AnimationClip:
    """Return the part of a clip between two frames, three.js's
    `AnimationUtils.subclip`.

    Args:
        source: The clip to cut from. It is left as it is.
        name: What the new clip is called.
        start_frame: The first frame kept; not negative.
        end_frame: The frame the new clip stops before; after
            `start_frame`.
        fps: How many frames a second the frame numbers count; thirty by
            default, as in three.js.

    Returns:
        A clip of the kept keys, moved back so that it starts at zero, in
        the source clip's blend mode. A track with no key in the range is
        left out.

    Raises:
        Error: If the frame rate is not a number above zero, the start
            frame is negative, the end frame is not after the start, or
            the keys kept make no clip: no track keeps a key, or every
            track keeps one key only.
    """
    var rate = checked_fps(fps)
    if start_frame < 0:
        raise Error("A subclip cannot start before frame zero")
    if end_frame <= start_frame:
        raise Error("A subclip must end after it starts")
    var first = Float32(start_frame)
    var last = Float32(end_frame)
    var kept_times = List[List[Float32]]()
    var kept_values = List[List[Float32]]()
    var kept_in = List[List[Float32]]()
    var kept_out = List[List[Float32]]()
    var kept_from = List[Int]()
    var earliest = Float32(0)
    for index in range(len(source.tracks)):  # pragma: no branch
        ref track = source.tracks[index]
        var width = track.target.kind.component_count()
        var times = List[Float32]()
        var values = List[Float32]()
        var ins = List[Float32]()
        var outs = List[Float32]()
        var tangents = track.interpolation == CUBIC_SPLINE
        for key in range(len(track.times)):  # pragma: no branch
            var frame = track.times[key] * rate
            if frame < first or frame >= last:
                continue
            times.append(track.times[key])
            for offset in range(width):  # pragma: no branch
                values.append(track.values[key * width + offset])
                if tangents:
                    # A glTF key is three values, and three.js's subclip
                    # keeps all three.
                    ins.append(track.in_tangents[key * width + offset])
                    outs.append(track.out_tangents[key * width + offset])
        if len(times) == 0:
            continue
        if len(kept_from) == 0 or times[0] < earliest:
            earliest = times[0]
        kept_times.append(times^)
        kept_values.append(values^)
        kept_in.append(ins^)
        kept_out.append(outs^)
        kept_from.append(index)
    var tracks = List[KeyframeTrack]()
    for index in range(len(kept_from)):
        var shifted = List[Duration]()
        for key in range(len(kept_times[index])):  # pragma: no branch
            shifted.append(Duration(kept_times[index][key] - earliest, SECOND))
        ref track = source.tracks[kept_from[index]]
        if track.interpolation == CUBIC_SPLINE:
            tracks.append(
                KeyframeTrack(
                    track.target,
                    shifted,
                    in_tangents=kept_in[index].copy(),
                    values=kept_values[index].copy(),
                    out_tangents=kept_out[index].copy(),
                )
            )
            continue
        tracks.append(
            KeyframeTrack(
                track.target,
                shifted,
                kept_values[index].copy(),
                track.interpolation,
            )
        )
    var clip = AnimationClip(name, tracks^, source.blend_mode)
    # three.js's `subclip` starts from a clone, which keeps the user data.
    clip.user_data = source.user_data.copy()
    return clip^


def make_clip_additive(
    target: AnimationClip, reference_frame: Int = 0, fps: Float32 = 30
) raises -> AnimationClip:
    """Return a clip as changes from its own pose at a frame, three.js's
    `AnimationUtils.makeClipAdditive` with the clip as its own reference.

    Args:
        target: The clip to make additive. It is left as it is.
        reference_frame: The frame whose pose is taken off; zero by
            default, as in three.js.
        fps: How many frames a second the frame number counts.

    Returns:
        The additive clip.

    Raises:
        Error: As the version that takes a reference clip does.
    """
    return make_clip_additive(target, reference_frame, target, fps)


def make_clip_additive(
    target: AnimationClip,
    reference_frame: Int,
    reference_clip: AnimationClip,
    fps: Float32 = 30,
) raises -> AnimationClip:
    """Return a clip as changes from another clip's pose at a frame,
    three.js's `AnimationUtils.makeClipAdditive`.

    Args:
        target: The clip to make additive. It is left as it is.
        reference_frame: The frame of `reference_clip` whose pose is taken
            off; not negative.
        reference_clip: The clip the pose is read from.
        fps: How many frames a second the frame number counts; thirty by
            default, as in three.js.

    Returns:
        A copy of `target` in `ADDITIVE_BLEND_MODE`, every track that
        matches a track of the reference made into changes from it. A
        number or a color has the reference taken off. A rotation is
        multiplied by the reference's conjugate on the left. A flag, and a
        track the reference does not drive, is kept as it is.

    Raises:
        Error: If the frame rate is not a number above zero or the frame
            is negative.
    """
    var rate = checked_fps(fps)
    if reference_frame < 0:
        raise Error("A reference frame cannot be before frame zero")
    var at = Duration(Float32(reference_frame) / rate, SECOND)
    var made = AnimationClip(copy=target)
    for index in range(len(reference_clip.tracks)):  # pragma: no branch
        ref reference = reference_clip.tracks[index]
        var kind = reference.target.kind
        if kind.is_boolean():
            continue
        var found = -1
        for which in range(len(made.tracks)):  # pragma: no branch
            if made.tracks[which].target == reference.target:
                found = which
                break
        if found < 0:
            continue
        var pose = reference.sample(at)
        ref changed = made.tracks[found]
        var width = kind.component_count()
        for key in range(changed.key_count()):  # pragma: no branch
            var start = key * width
            if kind == QUATERNION:
                var undo = Quaternion(pose[0], pose[1], pose[2], pose[3])
                undo.normalize()
                var turn = undo.conjugate()
                turn.multiply(
                    Quaternion(
                        changed.values[start],
                        changed.values[start + 1],
                        changed.values[start + 2],
                        changed.values[start + 3],
                    )
                )
                changed.values[start] = turn.x
                changed.values[start + 1] = turn.y
                changed.values[start + 2] = turn.z
                changed.values[start + 3] = turn.w
                continue
            for offset in range(width):  # pragma: no branch
                changed.values[start + offset] -= pose[offset]
    made.blend_mode = ADDITIVE_BLEND_MODE
    return made^
