# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A mesh that plays one morph target clip at a time, from three.js
`examples/jsm/misc/MorphAnimMesh.js`.

A `MorphAnimMesh` holds a mesh's clips and a mixer of its own.
`play_animation(label, fps)` stops the clip that plays and plays the one
of that name. Its time scale makes it run at `fps` frames a second: the
clip's tracks times `fps`, over the clip's duration, as three.js works it
out. `update_animation` moves the mixer on.

three.js's mesh finds the clip in its geometry's `animations`. A geometry
here holds no clips, so the caller gives them: `md2_clip` and
`create_clips_from_morph_target_sequences` make them. The clips' tracks
name the mesh they drive.

**Where this differs from three.js.** An action is made once for each
clip and played again after a stop, as three.js's mixer caches one. A
label no clip has raises, as three.js's throws.
"""

from animation.animation_clip import AnimationClip, find_by_name
from animation.animation_mixer import AnimationAction, AnimationMixer
from animation.keyframe_track import MeshIndex
from core.scene import Scene
from units.si import Duration, SECOND


struct MorphAnimMesh(Movable):
    """A mesh's morph target clips, played one at a time, three.js's
    `MorphAnimMesh`."""

    # Which of the scene's meshes the clips drive.
    var mesh: MeshIndex
    # The clips it can play, three.js's `geometry.animations`.
    var clips: List[AnimationClip]
    # Its own mixer, three.js's `mixer`.
    var mixer: AnimationMixer
    # Each clip's action in the mixer, or -1 before it first plays.
    var actions: List[Int]
    # The clip that plays, as its place in `clips`, three.js's
    # `activeAction`; -1 for none.
    var active: Int

    def __init__(out self, mesh: MeshIndex, var clips: List[AnimationClip]):
        """Hold a mesh's clips, with none playing.

        Args:
            mesh: Which of the scene's meshes the clips drive.
            clips: The clips it can play.
        """
        self.mesh = mesh
        self.actions = List[Int](length=len(clips), fill=-1)
        self.clips = clips^
        self.mixer = AnimationMixer()
        self.active = -1

    def set_direction_forward(mut self):
        """Play forward, three.js's `setDirectionForward`: the mixer's time
        scale goes to one."""
        self.mixer.time_scale = 1

    def set_direction_backward(mut self):
        """Play back, three.js's `setDirectionBackward`: the mixer's time
        scale goes to minus one."""
        self.mixer.time_scale = -1

    def play_animation(mut self, label: String, fps: Float64) raises:
        """Stop the clip that plays and play the clip of a name, three.js's
        `playAnimation`.

        Args:
            label: The clip's name.
            fps: How many of its frames a second to play: the time scale is
                the clip's tracks times `fps` over its duration.

        Raises:
            Error: If no clip has the name.
        """
        if self.active >= 0:
            self.mixer.action(self.actions[self.active]).stop()
            self.active = -1
        var found = find_by_name(self.clips, label)
        if not found:
            raise Error(
                "MorphAnimMesh: animations[" + label + "] is not a clip"
            )
        var at = found.value()
        if self.actions[at] < 0:
            self.actions[at] = self.mixer.add(
                AnimationAction(self.clips[at].copy())
            )
        ref clip = self.clips[at]
        ref action = self.mixer.action(self.actions[at])
        action.time_scale = Float32(
            Float64(clip.track_count()) * fps / Float64(clip.length)
        )
        action.play()
        self.active = at

    def update_animation(mut self, mut scene: Scene, delta: Duration) raises:
        """Move the clip on, three.js's `updateAnimation`.

        Args:
            scene: The scene the mesh is in.
            delta: The time since the last update.

        Raises:
            Error: As `AnimationMixer.update` does.
        """
        self.mixer.update(scene, delta)
