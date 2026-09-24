# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A named set of tracks that play together, from three.js
`src/animation/AnimationClip.js`.

A clip is a walk cycle, a door opening, a wave. It is a name, a list of
tracks and a length. The length is the longest track's unless the clip is
given another, which is three.js's `duration` and its `resetDuration`.

Nothing in a clip says which node it drives. Every track says that for
itself, so one clip can move a whole rig, and two tracks of one clip can
name two nodes.

## Blend modes

A clip carries three.js's `blendMode`. `NORMAL_BLEND_MODE`, the default,
mixes the clip's values with the other actions' by weight.
`ADDITIVE_BLEND_MODE` adds them on top of whatever the normal actions make:
its tracks hold changes from a reference pose rather than poses, which is
what `animation.animation_utils.make_clip_additive` makes of a clip.

## Editing a clip

`trim`, `optimize`, `validate` and `reset_duration` are three.js's, and
work on every track: see `animation.keyframe_track`. `find_by_name` finds a
clip in a list. `create_from_morph_target_sequence` and
`create_clips_from_morph_target_sequences` make clips that show a mesh's
morph targets in turn, as an MD2 model's frames are.

A clip is written to JSON and read from it by
`animation.animation_json`, since a track names its target by a path in
JSON and the path needs a scene to mean anything.

## What is refused

A clip with no tracks, and a clip that lasts no time: one whose tracks all
hold one key and that is given no length, or one given a length that is
not a number above zero. A thing that lasts no time cannot be played: an
action looping over it would divide by its length. A blend mode that is
neither of the two.
"""

from animation.keyframe_track import KeyframeTrack, TrackTarget
from std.math import isfinite
from units.si import Duration, SECOND


@fieldwise_init
struct AnimationBlendMode(Equatable, ImplicitlyCopyable, Writable):
    """How a clip's values join the other actions' values, as a type rather
    than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the two blend modes there are."""
        return self == NORMAL_BLEND_MODE or self == ADDITIVE_BLEND_MODE


# Mix by weight with the other actions, three.js's
# `NormalAnimationBlendMode`.
comptime NORMAL_BLEND_MODE = AnimationBlendMode(0)
# Add on top of what the normal actions make, three.js's
# `AdditiveAnimationBlendMode`.
comptime ADDITIVE_BLEND_MODE = AnimationBlendMode(1)


struct AnimationClip(Copyable, Movable):
    """A named set of tracks, played as one."""

    var name: String
    var tracks: List[KeyframeTrack]
    # How the clip's values join the other actions' values, three.js's
    # `blendMode`.
    var blend_mode: AnimationBlendMode
    # How long the clip runs, in seconds, three.js's `duration`. The
    # longest track's length unless the clip was given another;
    # `reset_duration` sets it back.
    var length: Float32

    def __init__(
        out self,
        name: String,
        var tracks: List[KeyframeTrack],
        blend_mode: AnimationBlendMode = NORMAL_BLEND_MODE,
        duration: Optional[Duration] = None,
    ) raises:
        """Create a clip from its tracks.

        Args:
            name: What the clip is called, as three.js's clips are named.
            tracks: The tracks it plays, at least one.
            blend_mode: `NORMAL_BLEND_MODE`, the default and three.js's, or
                `ADDITIVE_BLEND_MODE`.
            duration: How long the clip runs. None, the default, takes the
                longest track's length, as three.js does for a duration
                below zero. A clip can be given a length shorter or longer
                than its tracks; `trim` cuts the tracks to it.

        Raises:
            Error: If the blend mode is neither of the two, if there are no
                tracks, if the duration is not a number above zero, or if
                there is no duration and every track holds a single key,
                which is a clip of no length.
        """
        if not blend_mode.is_valid():
            raise Error("A clip needs a blend mode that exists")
        if len(tracks) == 0:
            raise Error("A clip needs at least one track")
        var runs = _longest(tracks)
        if Bool(duration):
            runs = duration.value().to(SECOND)
            if not isfinite(runs):
                raise Error("A clip's duration must be a number")
        if runs <= 0:
            raise Error("A clip must last longer than no time")
        self.name = name
        self.tracks = tracks^
        self.blend_mode = blend_mode
        self.length = runs

    def __init__(out self, *, copy: Self):
        """Copy another clip, its tracks included, three.js's `clone`."""
        self.name = copy.name
        self.tracks = copy.tracks.copy()
        self.blend_mode = copy.blend_mode
        self.length = copy.length

    def track_count(self) -> Int:
        """Return how many tracks the clip plays."""
        return len(self.tracks)

    def duration(self) -> Duration:
        """Return how long the clip runs, three.js's `duration`."""
        return Duration(self.length, SECOND)

    def reset_duration(mut self) raises:
        """Set the clip's length to its longest track's, three.js's
        `resetDuration`.

        Raises:
            Error: If every track now holds one key or none, which would
                leave a clip of no length.
        """
        var runs = _longest(self.tracks)
        if runs <= 0:
            raise Error("A clip must last longer than no time")
        self.length = runs

    def trim(mut self) raises:
        """Cut every track to the clip's length, three.js's `trim`: each
        drops its keys before zero and after the end. See
        `KeyframeTrack.trim`.

        Raises:
            Error: As `KeyframeTrack.trim` does.
        """
        for index in range(len(self.tracks)):  # pragma: no branch
            self.tracks[index].trim(Duration(0, SECOND), self.duration())

    def validate(self) -> Bool:
        """Return True if every track is sound, three.js's `validate`; see
        `KeyframeTrack.validate`."""
        for index in range(len(self.tracks)):
            if not self.tracks[index].validate():
                return False
        return True

    def optimize(mut self) raises:
        """Drop every key of every track that its neighbors make needless,
        three.js's `optimize`; see `KeyframeTrack.optimize`.

        Raises:
            Error: As `KeyframeTrack.optimize` does.
        """
        for index in range(len(self.tracks)):  # pragma: no branch
            self.tracks[index].optimize()


def _longest(tracks: List[KeyframeTrack]) -> Float32:
    """Return the longest track's length in seconds, or zero for none."""
    var longest = Float32(0)
    for index in range(len(tracks)):
        var runs = tracks[index].duration().to(SECOND)
        if runs > longest:
            longest = runs
    return longest


def find_by_name(clips: List[AnimationClip], name: String) -> Optional[Int]:
    """Return where the first clip of a name is, three.js's
    `AnimationClip.findByName`.

    Args:
        clips: The clips to look through.
        name: The name wanted.

    Returns:
        The place of the first clip with that name, or None if there is
        none, where three.js returns `null`.
    """
    for index in range(len(clips)):
        if clips[index].name == name:
            return index
    return None


def get_keyframe_order(times: List[Float32]) -> List[Int]:
    """Return the order that sorts keys by time, three.js's
    `AnimationUtils.getKeyframeOrder`.

    Args:
        times: The keys' times, in any order.

    Returns:
        The key places, earliest first. Keys at one time keep the order
        they had, as JavaScript's sort keeps them.
    """
    var order = List[Int]()
    for index in range(len(times)):
        # Insertion sort: stable, and a sequence has three keys.
        var at = len(order)
        while at > 0 and times[order[at - 1]] > times[index]:
            at -= 1
        order.insert(at, index)
    return order^


def sorted_array(
    values: List[Float32], stride: Int, order: List[Int]
) -> List[Float32]:
    """Return values put in an order, a stride at a time, three.js's
    `AnimationUtils.sortedArray`.

    Args:
        values: The values, `stride` numbers a key.
        stride: How many numbers one key holds.
        order: The key places in the order wanted, as
            `get_keyframe_order` returns them.

    Returns:
        The values in that order.
    """
    var out = List[Float32]()
    for index in range(len(order)):
        for offset in range(stride):
            out.append(values[order[index] * stride + offset])
    return out^


def create_from_morph_target_sequence(
    name: String,
    sequence: List[TrackTarget],
    fps: Float32,
    no_loop: Bool = False,
) raises -> AnimationClip:
    """Return a clip that shows each morph target of a sequence in turn,
    three.js's `AnimationClip.CreateFromMorphTargetSequence`.

    Target `i` of `n` is at an influence of one at frame `i` and of zero at
    the frames either side of it, wrapping around. Unless `no_loop`, a
    track with a key at frame zero gets its value again at frame `n`, so
    the clip loops without a jump. Frames become seconds at `fps`.

    three.js names each target by its name in the mesh's
    `morphTargetDictionary`. Here the sequence holds the targets, made
    with `morph_target` or `skinned_morph_target`.

    With one or two targets three.js builds keys at the same time, and
    reads the later of them past that time. Here only the later is kept,
    since the times of a track rise.

    Args:
        name: What the clip is called.
        sequence: The morph targets, in the order they are shown.
        fps: How many frames a second; above zero.
        no_loop: True to leave out the key that closes the loop.

    Returns:
        The clip, one track per target.

    Raises:
        Error: If the sequence is empty or holds a target that is not a
            morph target, or the frame rate is not a number above zero.
    """
    if not isfinite(fps) or fps <= 0:
        raise Error("A frame rate must be a number above zero")
    var count = len(sequence)
    if count == 0:
        raise Error("A morph target sequence needs at least one target")
    var tracks = List[KeyframeTrack]()
    for index in range(count):  # pragma: no branch
        if not sequence[index].kind.is_morph():
            raise Error("A morph target sequence holds morph targets only")
        # three.js's three keys, put in time order by `getKeyframeOrder`
        # and `sortedArray`.
        var frames: List[Float32] = [
            Float32((index + count - 1) % count),
            Float32(index),
            Float32((index + 1) % count),
        ]
        var shares: List[Float32] = [0, 1, 0]
        var order = get_keyframe_order(frames)
        frames = sorted_array(frames, 1, order)
        shares = sorted_array(shares, 1, order)
        if not no_loop and frames[0] == 0:
            frames.append(Float32(count))
            shares.append(shares[0])
        var times = List[Duration]()
        var values = List[Float32]()
        for key in range(len(frames)):  # pragma: no branch
            var later = key + 1 < len(frames) and frames[key + 1] == frames[key]
            if later:
                continue
            times.append(Duration(frames[key] / fps, SECOND))
            values.append(shares[key])
        tracks.append(KeyframeTrack(sequence[index], times, values^))
    return AnimationClip(name, tracks^)


def morph_sequence_name(name: String) -> Optional[String]:
    """Return the animation a morph target's name puts it in, by three.js's
    pattern: letters, digits, `_` and `-`, then a run of digits to the end.

    Args:
        name: The morph target's name, such as `Walk_001`.

    Returns:
        The part before the last run of digits, such as `Walk_`, or None
        if the name does not end in a digit or the part before holds a
        character other than a letter, a digit, `_` or `-`.
    """
    var bytes = name.as_bytes()
    var cut = len(bytes)
    while cut > 0 and bytes[cut - 1] >= 48 and bytes[cut - 1] <= 57:
        cut -= 1
    if cut == len(bytes):
        return None
    for index in range(cut):
        var byte = bytes[index]
        var word = (
            (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122)
            or (byte >= 48 and byte <= 57)
            or byte == 95
            or byte == 45
        )
        if not word:
            return None
    return String(name[byte=0:cut])


def create_clips_from_morph_target_sequences(
    names: List[String],
    targets: List[TrackTarget],
    fps: Float32,
    no_loop: Bool = False,
) raises -> List[AnimationClip]:
    """Return one clip per animation that a mesh's morph target names hold,
    three.js's `AnimationClip.CreateClipsFromMorphTargetSequences`.

    Names such as `Walk_001`, `Walk_002`, `Run_001` sort into the
    animations `Walk_` and `Run_`, and each becomes a clip of its targets
    by `create_from_morph_target_sequence`. A name that does not end in a
    digit is left out.

    Args:
        names: Each morph target's name, as three.js's morph targets carry
            them. This port's geometry does not.
        targets: The morph target each name is, one a name.
        fps: How many frames a second; above zero.
        no_loop: True to leave out the key that closes each loop.

    Returns:
        The clips, in the order their animations first appear.

    Raises:
        Error: If there is not one target a name, or as
            `create_from_morph_target_sequence` does.
    """
    if len(names) != len(targets):
        raise Error("A morph target sequence needs one target a name")
    var animations = List[String]()
    var members = List[List[TrackTarget]]()
    for index in range(len(names)):
        var animation = morph_sequence_name(names[index])
        if not Bool(animation):
            continue
        var found = -1
        for known in range(len(animations)):
            if animations[known] == animation.value():
                found = known
        if found < 0:
            found = len(animations)
            animations.append(animation.value())
            members.append(List[TrackTarget]())
        members[found].append(targets[index])
    var clips = List[AnimationClip]()
    for index in range(len(animations)):
        clips.append(
            create_from_morph_target_sequence(
                animations[index], members[index], fps, no_loop
            )
        )
    return clips^
