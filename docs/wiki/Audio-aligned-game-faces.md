# Audio-aligned game faces

Use caller-aligned intervals to drive a game character from its audio clock.
Set `facial_animation=True` in `add_game_humanoid`.
This path preserves the original scanned face, teeth, gums and tongue.
It supports body LOD and a validated glTF bake/load cycle.

This is visual animation. It does not simulate jaw contact, muscle forces,
tongue articulation or biomechanics. A successful bake does not establish
anatomical or engineering fidelity. See [Humanoid fidelity](Humanoid-fidelity).

## Input contract

Import `AlignedSpeech`, `TimedViseme`, `TimedPhoneme`, `Phoneme`,
`aligned_phonemes` and `AudioSpeechPlayback` from
`extensions.humanoid.skeleton.head.aligned_speech`.

- `utterance` is a nonempty caller label for the audio asset
- `duration` includes leading, internal and trailing silence
- `origin` is the media-clock position of utterance time zero
- Start and end times are utterance-relative `Duration` values in seconds
- All times must be finite and nonnegative
- Each interval must have a positive duration and fit within the utterance
- Intervals must arrive in time order and must not overlap
- The start is inclusive and the end is exclusive
- Each interval holds its specified viseme at full weight
- Gaps, explicit `SILENT`, and times outside the utterance produce rest weights

The default origin is zero. `Duration` stores Float32 seconds.
The sampler compares each endpoint after adding the origin in that domain.
An interval that collapses at that clock precision is refused.
Use a short media time origin for fine timing over a long session.
There is no frame-delta accumulation, timing inference or hidden coarticulation.

`TimedViseme` accepts the existing fifteen named `Viseme` values.
`TimedPhoneme` accepts an uppercase, unstressed ARPABET `Phoneme`, or `SIL`.
Unknown labels and stress suffixes such as `AH0` are refused.
The caller must select the intended pronunciation and strip stress labels.

Diphthongs use one held shape. Supply separate timed visemes to split one.
`HH` uses an open vowel shape and does not create a pause.

The mapping revision is `threemojo-arpabet-viseme-v1`.
The timing revision is `audio-clock-half-open-held-v1`.
For example, caller-aligned `AH V` drives “of”, regardless of its spelling.
No model, audio decoder, aligner, microphone or audio device is included.
The application must supply an authorized audio source and its alignment.

```mojo
var speech = AlignedSpeech("recording-v1", Duration(1), [
    TimedViseme(PP, Duration(0), Duration(0.125)),
    TimedViseme(AA, Duration(0.125), Duration(0.75)),
    TimedViseme(SILENT, Duration(0.75), Duration(1)),
])
var player = AudioSpeechPlayback(speech)
player.resume(audio_position)
var weights = player.sample(audio_position)
person.face.value().apply(scene, assets, weights)
```

`audio_position` must come from the audio player's media clock.
Do not substitute wall time or a frame counter.
Sample once per displayed frame. A dropped or repeated frame does not change
which shape the next clock position selects.

## Pause, seek and reset

Call `pause(position)` with the position where the audio actually paused.
Samples then hold that position even if a later observation moves forward.
Call `resume(position)` with the player's current position after it resumes.
Neither operation starts or stops the audio device.

Call `seek(position)` after the audio player accepts a seek.
It returns the destination's weights at once and keeps the paused state.
Backward and repeated samples use the same stateless lookup.
`reset()` pauses and samples at the utterance origin.
Repeated paused samples return the same weights.

Each sample creates fresh `FaceWeights`. It never adds a previous frame.
Add an expression to the fresh result before applying it when needed.
An added mouth expression can change the appearance of a speech closure.
Invalid transport times leave the previous playback state unchanged.

## Geometry and HEAD transforms

The game body has no second static copy of the face.
`body_skin_parts` returns the nonfacial body and original scanned facial
submesh separately. Only the nonfacial part is decimated.
The scan keeps its vertex order, indices, named relative targets and normals.
The facial targets fade to zero at the neck as in the existing head rig.
The mouth uses the same target order as the facial skin.

All facial geometry is authored in the pelvis frame.
The holder is a direct child of `HEAD` and has translation `-rig.at(HEAD)`.
Each facial mesh is a child of that holder with an identity local transform.
At rest, the holder cancels the head joint's rest translation.
During animation, HEAD turns the face and mouth about that joint.

The hair and eyes use the same holder. Parent character motion still applies.
The face is rigidly attached to HEAD; there is no separate mechanical jaw.
Large neck poses do not guarantee a physically continuous neck seam.

`GameFace.apply` validates correspondence before it changes any of its meshes.
It refuses missing targets, changed target order, invalid dimensions,
changed vertex or index content, and missing mesh bindings.
It then replaces all three meshes' weights.
The validation reads the original facial content each time; profile this
cost for your scene. No frame-rate claim is made for this new path.

## Triangle budgets and LOD

The default `facial_animation=False` keeps the existing game API and its
legacy budget behavior. With facial animation, zero means full detail.
A positive budget counts every triangle in body, hands, facial skin,
teeth, gums/tongue, hair shell and both eyes.

The builder reserves the original face, mouth and eye triangles first.
It reserves 32 more triangles for each body, hand and hair-shell part.
It distributes the remainder with the existing body/hand/hair shares.
It reduces the hands and hair first and gives the body the actual remainder.
This accounts for protected hair topology without two body-reduction passes.

It checks the actual total after safe edge collapse.
If a part exceeds its share, the builder reclaims excess from reducible parts.
It tries the body, right hand, left hand and hair shell in that order.
It requests at least 32 triangles per part during this extra reduction.

An insufficient minimum or an unmet safe-collapse budget raises an error.
The builder does not exceed the requested total or drop facial animation.
These budget refusals occur before scene nodes or assets are added.
The exact minimum depends on the character's retained scan topology.

Build another body LOD with the same spec and asset input to keep the same
facial correspondence. Different specs or source assets need separate bindings.
Strand hair is refused on this path; use the shell.
The general humanoid simplifier refuses morph-bearing geometry.
It cannot retarget or resample facial morphs onto a new topology.

## Bake and load

Use the ordinary `write_gltf(..., GLB)` and `read_gltf` functions.
`face.store_alignment(scene, speech)` puts the caller's timing record on
the facial holder before export. This record includes the audio label,
time origin, duration, every interval and both mapping revisions.
Audio bytes are not embedded. The application must resolve the same audio.

The holder's `GAME_FACE_KEY` metadata stores the facial recipe and an ordered
content fingerprint for each of the three parts.
The glTF mesh records retain `targetNames`, morph offsets and current weights.
After loading, find the holder in `model.nodes` by that metadata key.
Call `bind_game_face(scene, assets, loaded_holder)` to resolve new scene indices.
Call `binding.alignment(scene)` to recover and validate the timing record.
Never reuse node or mesh indices from the scene before export.

The fingerprint checks vertex order, base positions, indices, target names
and target offsets. It is a noncryptographic change detector.
It does not authenticate files or prove source provenance.
Missing or changed recipes, mappings, parts or correspondence are refused.
Do not use generic decimation or mesh reordering on the facial parts after bake.
If an external exporter changes those parts, rebuild instead of skipping checks.

## Existing spelling animation

`Speech(text, rate)` remains a lightweight spelling-based visual animation.
Its letter rules, timing and additive `speak` behavior are unchanged.
It does not use audio, phoneme alignment or a pronunciation model.
See [Head](Head#expressions-and-speech) for that API.

## Assets, licenses and verification

This feature adds no neural speech reference, pretrained model or new face asset.
The ARPABET-to-viseme table and synthetic test timing are authored source code.
The renderer uses the existing ICT FaceKit scan and expression deltas.
The visual recipes do not claim phonetic, anatomical or perceptual validation.

The pinned ICT source is commit
`da5f95a607f5e6b37755b38d3385d7f2853732e5` of
[USC-ICT/ICT-FaceKit](https://github.com/USC-ICT/ICT-FaceKit/tree/da5f95a607f5e6b37755b38d3385d7f2853732e5).
Its [MIT license](https://github.com/USC-ICT/ICT-FaceKit/blob/da5f95a607f5e6b37755b38d3385d7f2853732e5/LICENSE)
permits use, modification and distribution with its notice.

The bundled `ict_face.bin` SHA-256 is
`a1e9423fdbd88363e3ab9582e395720003d1459c8ed8ea5d55214b0148163271`.
The converter is `tools/ict_face_model.py`; its output format is ICTF v6.
The source pin and bundled asset above match the production reproduction
tracked in [issue #303](https://github.com/SethKitchen/ThreeMojo/issues/303).
[Converted assets](Converted-assets) describes input validation and converter use.

Verify the production manifest before packaging a release.
Keep the original notices. ThreeMojo's own license still applies.
A replacement model or future neural backend needs its own exact revision,
asset digests and intended-use license review before integration.

`examples/audio_game_humanoid.mojo` builds, bakes and loads a real game face.
It demonstrates synthetic clock positions, pause, seek and reset.
Run it with an output `.glb` path. It does not play audio.

Tests exercise plosive lip closure, sustained vowels, silent restoration,
teeth and gum motion, and irregular pronunciations.
Transport tests cover 24/30/60/144 Hz clock samples, nonzero origins,
and repeated and backward seeks.
Geometry tests cover strict LOD, HEAD transforms, glTF weights and target
round trips, and unsupported topology or mapping refusals.
