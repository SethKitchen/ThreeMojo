# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bake and reload an audio-aligned visual game face.

    mojo run -I . examples/audio_game_humanoid.mojo [character.glb]

This example has synthetic alignment and simulated media-clock observations.
It does not synthesize, decode, align or play audio. Replace these observations
with your audio player's position in seconds. See Audio-aligned-game-faces.
"""

from core.assets import Assets
from core.object3d import NO_PARENT, Object3D
from core.scene import Scene
from exporters.gltf import GLB, write_gltf
from extensions.humanoid.rig.game import add_game_humanoid
from extensions.humanoid.rig.game_face import GAME_FACE_KEY, bind_game_face
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.head.aligned_speech import (
    AlignedSpeech,
    AudioSpeechPlayback,
    TimedViseme,
)
from extensions.humanoid.skeleton.head.expression import AA, PP, SILENT
from loaders.gltf import read_gltf
from std.sys import argv
from units.si import Duration, FOOT, Length


def main() raises:
    """Build, bake, load and sample the synthetic demonstration.

    Raises:
        Error: If character construction, export, load or binding fails.
    """
    var args = argv()
    var path = String("out/audio-character.glb")
    if len(args) > 1:
        path = String(args[1])
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var person = add_game_humanoid(
        scene,
        assets,
        root,
        HumanoidSpec(Length(6, FOOT), MALE),
        detail=12,
        hand_detail=8,
        hair_detail=8,
        facial_animation=True,
    )
    var face = person.face.value().copy()
    var speech = AlignedSpeech(
        "synthetic-demo-no-audio",
        Duration(1),
        [
            TimedViseme(PP, Duration(0), Duration(0.125)),
            TimedViseme(AA, Duration(0.125), Duration(0.75)),
            TimedViseme(SILENT, Duration(0.75), Duration(1)),
        ],
    )
    face.store_alignment(scene, speech)
    face.apply(scene, assets, speech.sample(Duration(0.5)))
    write_gltf(path, scene, assets, GLB)
    var loaded = Scene()
    var restored = Assets()
    var model = read_gltf(path, loaded, restored)
    var holder = NO_PARENT
    for node in model.nodes:
        if node != NO_PARENT and loaded.get(node).user_data.has(
            String(GAME_FACE_KEY)
        ):
            if holder != NO_PARENT:
                raise Error("The example expects exactly one game face")
            holder = node
    if holder == NO_PARENT:
        raise Error("The baked character has no audio-ready game face")
    var binding = bind_game_face(loaded, restored, holder)
    var player = AudioSpeechPlayback(binding.alignment(loaded))
    player.resume(Duration(0))
    for observed in [Float32(0.0625), 0.5, 0.875]:
        binding.apply(loaded, restored, player.sample(Duration(observed)))
        print(
            "Media seconds:",
            observed,
            "jawOpen:",
            loaded.meshes[binding.meshes[0]].morph_influence(
                loaded.meshes[binding.meshes[0]].morph_target_dictionary[
                    "jawOpen"
                ]
            ),
        )
    player.pause(Duration(0.5))
    binding.apply(loaded, restored, player.sample(Duration(0.9)))
    binding.apply(loaded, restored, player.seek(Duration(0.0625)))
    binding.apply(loaded, restored, player.reset())
    print("Baked and validated", path, ": visual morphs only")
