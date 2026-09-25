# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Frame-by-frame morph animations blended by weight, from three.js
`examples/jsm/misc/MorphBlendMesh.js`.

A `MorphBlendMesh` plays runs of a mesh's morph targets as flip-books.
Each animation is a range of targets, from `start` to `end`, played at
`fps` frames a second. At each `update` an active animation finds the
frame its time is on, and sets that frame's weight and the last frame's so
the two cross-fade. Several animations can run at once, each scaled by
its `weight`, which is how three.js's MD2 character blends one animation
into the next.

The mesh is one of the scene's meshes. `update` writes its
`morph_influences` there, as three.js's writes `morphTargetInfluences`.

A new blend mesh has one animation, `__default`, of every target at as
many frames a second as there are targets, with a weight of one. It is not
playing. `auto_create_animations` adds one animation for each run of
targets whose names share a word, as `run1` to `run6` share `run`.

**What is refused.** Nothing is refused where three.js does nothing: a
name that no animation has is passed over, as three.js passes it over.
An `update` by a time that is not a number is refused, and so is a mesh
that is not in the scene.
"""

from core.scene import Scene
from animation.keyframe_track import MeshIndex
from std.math import floor, isfinite, nan

# The name three.js gives the animation every blend mesh starts with.
comptime DEFAULT_ANIMATION = "__default"


def js_remainder(a: Float64, b: Float64) -> Float64:
    """Return JavaScript's `a % b`: the remainder with the sign of `a`.

    Args:
        a: The dividend.
        b: The divisor.

    Returns:
        The remainder. Not a number for a divisor of zero, as in
        JavaScript.
    """
    if b == 0:
        return nan[DType.float64]()
    var r = a % b
    if r != 0 and (r < 0) != (a < 0):
        r -= b
    return r


struct MorphBlendAnimation(Copyable, Movable):
    """One flip-book of a blend mesh, three.js's animation record."""

    var name: String
    # The first and the last morph target it plays, and how many that is.
    var start: Int
    var end: Int
    var length: Int
    # Frames a second, and how long one pass takes, in seconds.
    var fps: Float64
    var duration: Float64
    # The frame shown before the current one, and the current one.
    var last_frame: Int
    var current_frame: Int
    var active: Bool
    # How far into a pass it is, in seconds.
    var time: Float64
    # One to play forward, minus one to play back.
    var direction: Float64
    # How much of the mesh it moves.
    var weight: Float32
    var direction_backwards: Bool
    # Whether it plays back and forth, three.js's `mirroredLoop`.
    var mirrored_loop: Bool

    def __init__(
        out self, name: String, start: Int, end: Int, fps: Float64
    ):
        """Create an animation, three.js's record in `createAnimation`.

        Args:
            name: Its name.
            start: The first target.
            end: The last target.
            fps: Frames a second.
        """
        self.name = name
        self.start = start
        self.end = end
        self.length = end - start + 1
        self.fps = fps
        self.duration = Float64(end - start) / fps
        self.last_frame = 0
        self.current_frame = 0
        self.active = False
        self.time = 0
        self.direction = 1
        self.weight = 1
        self.direction_backwards = False
        self.mirrored_loop = False


def _animation_word(name: String) -> Optional[String]:
    """Return the word three.js's `/([a-z]+)_?(\\d+)/i` takes from a
    target's name: the first run of letters that a digit, or an underscore
    and a digit, follows. None when no run of letters is followed so."""
    var bytes = name.as_bytes()
    var at = 0
    while at < len(bytes):
        if not _letter(bytes[at]):
            at += 1
            continue
        var end = at
        while end < len(bytes) and _letter(bytes[end]):
            end += 1
        var next = end
        if next < len(bytes) and bytes[next] == 95:
            next += 1
        if next < len(bytes) and bytes[next] >= 48 and bytes[next] <= 57:
            return String(name[byte=at:end])
        at = end
    return None


def _letter(byte: UInt8) -> Bool:
    """Return True for an ASCII letter, either case."""
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)


struct MorphBlendMesh(Movable):
    """A mesh's morph targets played as blended flip-books, three.js's
    `MorphBlendMesh`."""

    # Which of the scene's meshes it plays.
    var mesh: MeshIndex
    # Every animation, in the order made. A name made twice is found as
    # its last, as three.js's `animationsMap` keeps the last.
    var animations: List[MorphBlendAnimation]
    # The first animation `auto_create_animations` found, three.js's
    # `firstAnimation`, or empty.
    var first_animation: String

    def __init__(out self, mesh: MeshIndex, scene: Scene) raises:
        """Play a mesh's morph targets, with three.js's `__default`
        animation of them all.

        Args:
            mesh: Which of the scene's meshes. Its targets are counted by
                its `morph_target_dictionary`, as three.js counts them.
            scene: The scene it is in.

        Raises:
            Error: If the scene has no such mesh.
        """
        _check(mesh, scene)
        self.mesh = mesh
        self.animations = List[MorphBlendAnimation]()
        self.first_animation = String()
        var frames = len(scene.meshes[mesh.value].morph_target_dictionary)
        self.create_animation(
            DEFAULT_ANIMATION, 0, frames - 1, Float64(frames) / 1
        )
        self.set_animation_weight(DEFAULT_ANIMATION, 1)

    def _find(self, name: String) -> Int:
        """Return the place of the last animation of a name, or -1."""
        var found = -1
        for at in range(len(self.animations)):
            if self.animations[at].name == name:
                found = at
        return found

    def create_animation(
        mut self, name: String, start: Int, end: Int, fps: Float64
    ):
        """Add an animation of a range of targets, three.js's
        `createAnimation`.

        Args:
            name: Its name.
            start: The first target.
            end: The last target.
            fps: Frames a second.
        """
        self.animations.append(MorphBlendAnimation(name, start, end, fps))

    def auto_create_animations(mut self, scene: Scene, fps: Float64) raises:
        """Add an animation for each word the targets' names start with,
        three.js's `autoCreateAnimations`.

        A target whose name has a word and a number, `run1` or `run_1`,
        joins the animation of that word. Each animation runs from the
        first target of its word to the last.

        Args:
            scene: The scene the mesh is in.
            fps: Frames a second, for every animation made.

        Raises:
            Error: If the scene has no such mesh.
        """
        _check(self.mesh, scene)
        ref dictionary = scene.meshes[self.mesh.value].morph_target_dictionary
        var words = List[String]()
        var starts = List[Int]()
        var ends = List[Int]()
        var first = String()
        var index = 0
        for entry in dictionary.items():
            var word = _animation_word(entry.key)
            if word:
                var found = -1
                for at in range(len(words)):
                    if words[at] == word.value():
                        found = at
                if found < 0:
                    words.append(word.value())
                    starts.append(index)
                    ends.append(index)
                    found = len(words) - 1
                starts[found] = min(starts[found], index)
                ends[found] = max(ends[found], index)
                if first == "":
                    first = word.value()
            index += 1
        for at in range(len(words)):
            self.create_animation(words[at], starts[at], ends[at], fps)
        self.first_animation = first

    def set_animation_direction_forward(mut self, name: String):
        """Play an animation forward, three.js's
        `setAnimationDirectionForward`.

        Args:
            name: The animation. Nothing happens for a name no animation has.
        """
        var at = self._find(name)
        if at >= 0:
            self.animations[at].direction = 1
            self.animations[at].direction_backwards = False

    def set_animation_direction_backward(mut self, name: String):
        """Play an animation back, three.js's
        `setAnimationDirectionBackward`.

        Args:
            name: The animation. Nothing happens for a name no animation has.
        """
        var at = self._find(name)
        if at >= 0:
            self.animations[at].direction = -1
            self.animations[at].direction_backwards = True

    def set_animation_fps(mut self, name: String, fps: Float64):
        """Set an animation's frames a second, and so its duration,
        three.js's `setAnimationFPS`.

        Args:
            name: The animation. Nothing happens for a name no animation has.
            fps: Frames a second.
        """
        var at = self._find(name)
        if at >= 0:
            ref animation = self.animations[at]
            animation.fps = fps
            animation.duration = Float64(animation.end - animation.start) / fps

    def set_animation_duration(mut self, name: String, duration: Float64):
        """Set how long a pass of an animation takes, and so its frames a
        second, three.js's `setAnimationDuration`.

        Args:
            name: The animation. Nothing happens for a name no animation has.
            duration: The seconds a pass takes.
        """
        var at = self._find(name)
        if at >= 0:
            ref animation = self.animations[at]
            animation.duration = duration
            animation.fps = Float64(animation.end - animation.start) / duration

    def set_animation_weight(mut self, name: String, weight: Float32):
        """Set how much of the mesh an animation moves, three.js's
        `setAnimationWeight`.

        Args:
            name: The animation. Nothing happens for a name no animation has.
            weight: The share.
        """
        var at = self._find(name)
        if at >= 0:
            self.animations[at].weight = weight

    def set_animation_time(mut self, name: String, time: Float64):
        """Set how far into a pass an animation is, three.js's
        `setAnimationTime`.

        Args:
            name: The animation. Nothing happens for a name no animation has.
            time: The seconds into the pass.
        """
        var at = self._find(name)
        if at >= 0:
            self.animations[at].time = time

    def get_animation_time(self, name: String) -> Float64:
        """Return how far into a pass an animation is, three.js's
        `getAnimationTime`.

        Args:
            name: The animation.

        Returns:
            The seconds into the pass, or zero for a name no animation has.
        """
        var at = self._find(name)
        if at < 0:
            return 0
        return self.animations[at].time

    def get_animation_duration(self, name: String) -> Float64:
        """Return how long a pass of an animation takes, three.js's
        `getAnimationDuration`.

        Args:
            name: The animation.

        Returns:
            The seconds, or minus one for a name no animation has.
        """
        var at = self._find(name)
        if at < 0:
            return -1
        return self.animations[at].duration

    def play_animation(mut self, name: String) -> Bool:
        """Start an animation from its first frame, three.js's
        `playAnimation`.

        Args:
            name: The animation.

        Returns:
            False for a name no animation has, where three.js warns.
        """
        var at = self._find(name)
        if at < 0:
            return False
        self.animations[at].time = 0
        self.animations[at].active = True
        return True

    def stop_animation(mut self, name: String):
        """Stop an animation where it is, three.js's `stopAnimation`.

        Args:
            name: The animation. Nothing happens for a name no animation has.
        """
        var at = self._find(name)
        if at >= 0:
            self.animations[at].active = False

    def update(mut self, mut scene: Scene, delta: Float64) raises:
        """Move every active animation on and set the frames it shows,
        three.js's `update`.

        Args:
            scene: The scene the mesh is in.
            delta: The seconds since the last update.

        Raises:
            Error: If the time is not a number, or the scene has no such
                mesh.
        """
        if not isfinite(delta):
            raise Error("A blend mesh cannot move on by a time that is not a number")
        _check(self.mesh, scene)
        ref mesh = scene.meshes[self.mesh.value]
        for at in range(len(self.animations)):
            ref animation = self.animations[at]
            if not animation.active:
                continue
            var frame_time = animation.duration / Float64(animation.length)
            animation.time += animation.direction * delta
            if animation.mirrored_loop:
                if animation.time > animation.duration or animation.time < 0:
                    animation.direction *= -1
                    if animation.time > animation.duration:
                        animation.time = animation.duration
                        animation.direction_backwards = True
                    if animation.time < 0:
                        animation.time = 0
                        animation.direction_backwards = False
            else:
                animation.time = js_remainder(
                    animation.time, animation.duration
                )
                if animation.time < 0:
                    animation.time += animation.duration
            var ratio = floor(animation.time / frame_time)
            if not isfinite(ratio):
                # An animation of no frames, or of no length: three.js's
                # frame is not a number, and sets no target.
                continue
            var step = Int(ratio)
            var keyframe = animation.start + max(0, min(step, animation.length - 1))
            var weight = animation.weight
            if keyframe != animation.current_frame:
                mesh.set_morph_influence(animation.last_frame, 0)
                mesh.set_morph_influence(animation.current_frame, weight)
                mesh.set_morph_influence(keyframe, 0)
                animation.last_frame = animation.current_frame
                animation.current_frame = keyframe
            var mix = Float32(js_remainder(animation.time, frame_time) / frame_time)
            if animation.direction_backwards:
                mix = 1 - mix
            if animation.current_frame != animation.last_frame:
                mesh.set_morph_influence(animation.current_frame, mix * weight)
                mesh.set_morph_influence(animation.last_frame, (1 - mix) * weight)
            else:
                mesh.set_morph_influence(animation.current_frame, weight)


def _check(mesh: MeshIndex, scene: Scene) raises:
    """Refuse a mesh the scene does not have."""
    if mesh.value < 0 or mesh.value >= len(scene.meshes):
        raise Error("A blend mesh must name one of the scene's meshes")
