# Animation

`animation/keyframe_track.mojo`, `animation/animation_clip.mojo`, `animation/animation_mixer.mojo`, `animation/animation_object_group.mojo` and `animation/animation_utils.mojo`. A track gives one property a value at a list of times. The property is on a node, a mesh, a material or a light. A clip plays tracks together. A mixer plays clips and writes the result into a scene and its assets.

![A mixer slides and turns a cube from keyframes](out/keyframes.png)

three.js: `KeyframeTrack`, `VectorKeyframeTrack`, `QuaternionKeyframeTrack`, `NumberKeyframeTrack`, `ColorKeyframeTrack`, `BooleanKeyframeTrack`, `PropertyBinding`, `PropertyMixer`, `AnimationClip`, `AnimationAction`, `AnimationMixer`, `AnimationObjectGroup`, `AnimationUtils.subclip`, `AnimationUtils.makeClipAdditive`, `AdditiveAnimationBlendMode`, and the mixer's `loop` and `finished` events. The smooth and cubic spline modes port `CubicInterpolant` and the glTF loader's `GLTFCubicSplineInterpolant`.

## KeyframeTrack

A track is two lists of the same length: when, and what.

```mojo
from animation.keyframe_track import KeyframeTrack, POSITION, STEP
from core.object3d import NodeId
from units.si import Duration, SECOND

var times = List[Duration]()
times.append(Duration(0, SECOND))
times.append(Duration(2, SECOND))

var slide = KeyframeTrack(
    NodeId(0), POSITION, times, [0, 0, 0, 4, 0, 0]
)
```

| Kind | Numbers a key holds | What it drives |
|---|---|---|
| `POSITION` | 3 | Where the node is. |
| `SCALE` | 3 | How big it is. |
| `QUATERNION` | 4 | Which way it is turned. |
| `VISIBLE` | 1, zero or one | Whether the node is drawn. |
| `MORPH_INFLUENCE` | 1 | How much of one morph target a mesh wears. |
| `MATERIAL_COLOR`, `MATERIAL_EMISSIVE`, `MATERIAL_SPECULAR` | 3 | A material's colors, as linear channels. |
| `MATERIAL_OPACITY` and the other `MATERIAL_` numbers | 1 | One number field of a material. |
| `LIGHT_COLOR` | 3 | A light's color, as linear channels. |
| `LIGHT_INTENSITY` | 1 | How bright a light is. |

The material numbers are `OPACITY`, `EMISSIVE_INTENSITY`, `ROUGHNESS`, `METALNESS`, `SHININESS`, `ALPHA_TEST`, `REFLECTIVITY`, `ENV_MAP_INTENSITY`, `CLEARCOAT`, `CLEARCOAT_ROUGHNESS`, `SPECULAR_INTENSITY` and `IOR`, each with the `MATERIAL_` prefix.

This port has no `StringKeyframeTrack`. Nothing in the port has a string property for it to drive.

| Member | Meaning |
|---|---|
| `key_count() -> Int` | How many keys the track holds. |
| `duration() -> Duration` | When the last key is. |
| `sample(at, start, end) -> List[Float32]` | The value at a time, as numbers. `start` and `end` are the [ending modes](#ending-modes) of a `SMOOTH` track. |
| `sample_vector3(at, start, end) -> Vector3` | The value of a `POSITION` or `SCALE` track. |
| `sample_quaternion(at) -> Quaternion` | The value of a `QUATERNION` track. |

Before the first key the value is the first key's. After the last it is the last key's. three.js's interpolants do the same at their ends.

### A track names a target, not a string

A track holds a `TrackTarget`: a kind, and the index of the thing it drives. three.js names its target with a string path, such as `.material.opacity`. Its `PropertyBinding` parses the path and looks the object up by name at run time.

Make a target with the function for its kind. Each function takes the id type that its kind needs:

```mojo
from animation.keyframe_track import (
    KeyframeTrack, LIGHT_INTENSITY, LightIndex, MATERIAL_OPACITY, MeshIndex,
    light_target, material_target, morph_target,
)
from materials.material import MaterialId

var fade = KeyframeTrack(
    material_target(MaterialId(0), MATERIAL_OPACITY), times, [1, 0]
)
var smile = KeyframeTrack(morph_target(MeshIndex(0), 2), times, [0, 1])
var dim = KeyframeTrack(
    light_target(LightIndex(1), LIGHT_INTENSITY), times, [2, 0]
)
```

| Function | Id it takes | Kinds |
|---|---|---|
| `node_target(node, kind)` | `NodeId` | `POSITION`, `SCALE`, `QUATERNION`, `VISIBLE` |
| `morph_target(mesh, target)` | `MeshIndex`, into `scene.meshes` | `MORPH_INFLUENCE`, target 0 to 7 |
| `material_target(material, kind)` | `MaterialId`, into `assets.materials` | The `MATERIAL_` kinds |
| `light_target(light, kind)` | `LightIndex`, into `scene.lights` | `LIGHT_COLOR`, `LIGHT_INTENSITY` |

`KeyframeTrack(node, kind, times, values)` is the short form of a node track.

A string that matches nothing is three.js's most common animation bug. A typed target removes it. A typed *index* does not prove that the thing is there, because the scene and the assets are chosen at `update`. The mixer checks there, and raises on an index that names nothing.

### Colors are linear

A color key holds three linear channels from 0 to 1, as three.js's `Color` holds them. A material and a light store sRGB bytes. The mixer decodes a color when it binds it and encodes the result when it writes it.

### How two keys are mixed

There are four interpolations.

| Interpolation | three.js | Between two keys |
|---|---|---|
| `LINEAR`, the default | `InterpolateLinear` | Runs evenly from one key to the next. |
| `STEP` | `InterpolateDiscrete` | Holds the first key's value. |
| `SMOOTH` | `InterpolateSmooth` | A cubic curve through the keys. See [Smooth tracks](#smooth-tracks). |
| `CUBIC_SPLINE` | glTF's `CUBICSPLINE` | A cubic curve from values and tangents. See [Cubic spline tracks](#cubic-spline-tracks). |

A `VISIBLE` track is always `STEP`, as three.js's `BooleanKeyframeTrack` is. Leave `interpolation` out, or give `STEP`. A key must be 0 or 1.

Two rotations are mixed by `slerp`, not one number at a time. A rotation is not four numbers to average. Averaging them makes a turn that speeds up in the middle. It also makes a quaternion that is no longer a rotation. three.js keeps `QuaternionLinearInterpolant` apart for the same reason.

### Smooth tracks

`SMOOTH` runs a cubic curve through the keys, as three.js's `CubicInterpolant` does. The slope at a key comes from the keys on each side of it, divided by the time between them. So uneven spacing of the times changes the curve.

```mojo
from animation.keyframe_track import SMOOTH

var glide = KeyframeTrack(
    NodeId(0), POSITION, times, [0, 0, 0, 4, 0, 0], SMOOTH
)
```

`SMOOTH` is not a Catmull-Rom spline. The spline in [Curves and paths](Curves) does not use the times, so it is a different curve.

A `POSITION`, `SCALE`, `MORPH_INFLUENCE`, color or material number track can be `SMOOTH`. A `QUATERNION` track cannot. three.js's `QuaternionKeyframeTrack` has no smooth interpolant. There it prints a warning and uses `LINEAR`. This port raises an error, because a caller who asks for smooth did not ask for linear.

#### Ending modes

The first and the last pair of keys have no key on one side. An `Ending` tells the curve what to use there.

| Ending | three.js | The curve at that end |
|---|---|---|
| `ZERO_CURVATURE_ENDING` | `ZeroCurvatureEnding` | Does not bend. This is a natural spline. |
| `ZERO_SLOPE_ENDING` | `ZeroSlopeEnding` | Is flat. |
| `WRAP_AROUND_ENDING` | `WrapAroundEnding` | Continues into the other end of the track. |

`sample(at)` uses `ZERO_CURVATURE_ENDING` at both ends, as a three.js `CubicInterpolant` does on its own. An action sets the endings from its loop mode, as three.js's `_setEndings` does:

| Loop | Start | End |
|---|---|---|
| `ONCE` | Flat | Flat |
| `REPEAT`, forward | Flat until the first loop, then wraps | Wraps |
| `REPEAT`, backward | Wraps | Flat until the first loop, then wraps |
| `PING_PONG` | Flat | Flat |

Set `zero_slope_at_start` or `zero_slope_at_end` to False on an action to use `ZERO_CURVATURE_ENDING` in place of flat. Both are True by default, as in three.js. `stop` starts the sequence again.

### Cubic spline tracks

A `CUBIC_SPLINE` track is glTF's cubic spline sampler, three.js's `GLTFCubicSplineInterpolant`. Each key has an in-tangent, a value and an out-tangent. The curve between two keys is a Hermite cubic. It starts at the first value along the first out-tangent and ends at the second value along the second in-tangent. A tangent is in value units per second, so the curve scales it by the time between the two keys.

A cubic spline track has its own constructor. It takes the tangents as two lists, laid out as the values are:

```mojo
from animation.keyframe_track import node_target

var arc = KeyframeTrack(
    node_target(NodeId(0), POSITION),
    times,
    in_tangents=[0, 0, 0, -2, 0, 0],
    values=[0, 0, 0, 4, 0, 0],
    out_tangents=[2, 0, 0, 0, 0, 0],
)
```

glTF puts the in-tangent, the value and the out-tangent of each key one after the other. Split them into the three lists. The in-tangent of the first key and the out-tangent of the last key have no effect.

Every kind except `VISIBLE` can be `CUBIC_SPLINE`. A `QUATERNION` track is run one number at a time and then made of unit length, as three.js's `GLTFCubicSplineQuaternionInterpolant` does. Endings have no effect on a cubic spline track.

`subclip` keeps the tangents of each key that it keeps. `make_clip_additive` changes the values and keeps the tangents, as three.js does.

## AnimationClip

```mojo
from animation.animation_clip import AnimationClip

var clip = AnimationClip("slide", [slide^])
```

A clip is a name, a list of tracks and a blend mode. It lasts as long as its longest track, which is how three.js works a duration out in `resetDuration`.

The blend mode is `NORMAL_BLEND_MODE` by default. `ADDITIVE_BLEND_MODE` makes the clip add to the pose; see [Additive animation](#additive-animation).

Nothing in a clip says which node it drives. Every track says that for itself, so one clip can move a whole rig.

| Member | Meaning |
|---|---|
| `track_count() -> Int` | How many tracks the clip plays. |
| `duration() -> Duration` | How long the clip runs. |

## AnimationAction

An action is one clip being played.

| Member | Meaning |
|---|---|
| `play()`, `pause()`, `stop()` | Start, hold where it is, or stop and rewind. |
| `is_active() -> Bool` | True if it contributes to the pose. |
| `is_playing() -> Bool` | True if its clock is running: active and not paused. |
| `clamp_when_finished` | True if a `ONCE` action holds its last frame. |
| `at() -> Duration` | How far into the clip it has got. |
| `set_weight(weight)` | How much of it goes into the pose. |
| `time_scale` | How fast it runs. A negative number runs it backward. |
| `loop` | `ONCE`, `REPEAT` or `PING_PONG`. |
| `fade_in(duration)`, `fade_out(duration)` | Ramp the weight up from zero, or down to zero. |
| `stop_fading()` | Drop the fade and use `weight` as it is. |
| `warp(start, end, duration)` | Ramp the time scale from `start` to `end`. |
| `halt(duration)` | Ramp the time scale down to zero, then pause. |
| `stop_warping()` | Drop the warp and use `time_scale` as it is. |
| `start_at(time)` | Hold the clock until the mixer's clock reaches `time`. |
| `get_effective_weight() -> Float32` | The weight of the last update, with the fade applied. |
| `get_effective_time_scale() -> Float32` | The time scale of the last update, with the warp applied. |
| `set_effective_weight(weight)` | Set the weight and stop the fade. |
| `set_effective_time_scale(scale)` | Set the time scale and stop the warp. |
| `blend_mode` | `NORMAL_BLEND_MODE` or `ADDITIVE_BLEND_MODE`. The clip's mode unless you change it. |
| `use_group(group)` | Play every track on every member of an `AnimationObjectGroup`. |

`ONCE` stops at the end and stays there. `REPEAT` starts over. `PING_PONG` runs back the way it came. A negative `time_scale` runs a clip backward, and each mode handles that going the other way.

An action carries a *phase*, not the time it is read at. For `PING_PONG` the phase runs to twice the clip's length, and the read time folds out of it. The return leg is therefore a different phase from the outward one. Storing the folded time loses which leg it is on, and the action bounces near the end instead of coming back.

Three states are kept apart. `active` says the action contributes to the pose; `paused` says its clock has stopped. A paused action still contributes, which is what holding a pose has to mean. `clamp_when_finished` says whether a `ONCE` action holds its last frame or lets the node settle back; it is False by default, as in three.js.

## AnimationMixer

```mojo
from animation.animation_mixer import AnimationAction, AnimationMixer

var mixer = AnimationMixer()
var which = mixer.add(AnimationAction(clip^))
mixer.action(which).play()

mixer.update(scene, clock.delta())
```

| Member | Meaning |
|---|---|
| `add(action) -> Int` | Add an action and return its index. |
| `action(index)` | The action, for playing or reweighting. |
| `action_count() -> Int` | How many actions the mixer holds. |
| `time() -> Duration` | How much time the mixer has been given. |
| `update(scene, delta)` | Move every playing action on, and set the nodes, meshes and lights. |
| `update(scene, assets, delta)` | The same, and set the materials too. |
| `cross_fade_from(index, from_index, duration, warp)` | Fade one action in and another out. |
| `cross_fade_to(index, to_index, duration, warp)` | Fade one action out and another in. |
| `event_count() -> Int` | How many events the last update recorded. |
| `drain_events() -> List[AnimationEvent]` | The events of the last update, oldest first. |

### Why the mixer and not each action writes

Two actions can drive one node at once, and that is the whole reason a mixer exists. Walking at a weight of one and waving at a weight of one half is one pose, not two. The node can only be set once.

So every action's value goes into a pile, one pile per node and property. The piles are written when every action has had its say.

A pile is a running average by weight, three.js's arrangement in `_mixBufferRegion`. The first value in is the pile, and every value after it moves the pile a share of the way toward itself. That share is the new weight over the total weight, which leaves the pile at the weighted mean however many values arrive.

A rotation pile moves along the arc, by `slerp`, for the reason a rotation track is interpolated by `slerp`. That makes a rotation pile depend on the order the actions were added, which a position pile does not. three.js has the same property.

### Weight is a share of the node, not a share of the actions

A pile is a mean, so on its own it says nothing about how much of the node the actions have claimed. The mixer remembers what each node property held before anything drove it, and mixes the pile back toward it by whatever weight is missing:

```text
result = total * pile + (1 - total) * original
```

An action alone at a weight of one quarter therefore moves the node a quarter of the way. That is what lets a single animation be faded in and out. three.js does this in `PropertyMixer.apply`.

That original is read once, the first time a property is driven. Reading the node each frame would read back what the mixer wrote last frame, and the pose would wander.

### How each type of value mixes

The mixer mixes each type of value the way three.js's `PropertyMixer` does.

| Value | How two actions mix | How it rests toward the original |
|---|---|---|
| Number, color | Weighted mean, one number at a time. | Along the line. |
| Rotation | Weighted mean along the arc, by `slerp`. | Along the arc. |
| Flag | The value takes the pile if its share is at least one half. | The original takes it back if the missing weight is at least one half. |

The flag rule is three.js's `_select`. With two actions, the heavier action wins. With three or more, the order of the actions can decide a near tie, as it does in three.js.

### Materials need the assets

A material is in the assets, not in the scene. Use `update(scene, assets, delta)` for a clip that drives a material. `update(scene, delta)` raises on a material track.

### Values a property cannot hold

The mixer refuses to write a value that its property cannot hold. It checks a color channel against 0 to 1 and a light intensity against zero. It checks a material number against the range that `Material` accepts for that field. A normal action cannot leave the range of its keys, but an additive action can.

The mixer does not check if a material's kind reads the field. A roughness track on a `LAMBERT` material writes a number that the renderer ignores.

## Additive animation

An additive clip holds changes from a reference pose, not poses. An action on it adds its changes to what the normal actions make. A nod added to a walk is one example.

```mojo
from animation.animation_utils import make_clip_additive

var nod = make_clip_additive(nod_clip)
var walking = mixer.add(AnimationAction(walk_clip^))
var nodding = mixer.add(AnimationAction(nod^))
```

`make_clip_additive(clip, reference_frame, reference_clip, fps)` reads each track of the reference clip at the reference frame. It takes that value off every key of the matching track in the clip. Tracks match when they have the same target.

| Value | The change a key holds | How the mixer adds it |
|---|---|---|
| Number, color | The key minus the reference. | Plus the change times the weight. |
| Rotation | The reference's conjugate times the key. | The pose times the change, along the arc by the weight. |
| Flag | The key, unchanged. | As a normal flag, from the original. |

The rotation rule is three.js's: a change is relative to the reference, and it turns after the pose. The reference clip is the clip itself by default, at frame 0 and 30 frames a second.

The mixer keeps an additive pile beside each normal pile, as three.js does. It rests the normal pile toward the original first. Then it puts the additive pile on top. A property that only additive actions drive gets its changes on top of its original.

In three.js the additive pile of a flag replaces the normal one. This port does the same.

## Subclips

`subclip(clip, name, start_frame, end_frame, fps)` returns the part of a clip between two frames, as three.js's `AnimationUtils.subclip` does.

```mojo
from animation.animation_utils import subclip

var wave = subclip(everything, "wave", 30, 60, 30)
```

A key stays if its frame, its time times `fps`, is at `start_frame` or after it and before `end_frame`. The kept keys move back so that the earliest one is at zero. No key is made at the cut. A track with no key in the range is left out. The subclip keeps the clip's blend mode.

## Groups

An `AnimationObjectGroup` is a list of nodes that one action plays on together. A crowd that walks with one walk is an example.

```mojo
from animation.animation_object_group import AnimationObjectGroup

var crowd = AnimationObjectGroup()
crowd.add(first)
crowd.add(second)
var action = AnimationAction(walk_clip^)
action.use_group(crowd^)
```

An action with a group plays each track on each member, not on the index that the track names. Each member is to a track what the object is to a three.js path:

| Kind | What a member drives |
|---|---|
| A node kind | The member node. |
| `MORPH_INFLUENCE` | Every mesh at the member. |
| A `MATERIAL_` kind | The material of every mesh at the member. |
| A `LIGHT_` kind | Every light at the member. |

Two members whose meshes share a material drive it once.

| Member | Meaning |
|---|---|
| `add(node)` | Add a node. A node already in the group stays where it is. |
| `remove(node)` | Take a node out. A node not in the group is ignored. |
| `contains(node) -> Bool` | True if the node is a member. |
| `count() -> Int` | How many nodes the group holds. |

In three.js, actions share one group by reference. Here an action keeps its own copy. To change the members of a playing action, edit `mixer.action(index).group`.

## Fades, warps and start times

A fade changes the weight along a straight line. A warp changes the time scale the same way. Both run on the mixer's clock.

```mojo
from units.si import Duration, SECOND

mixer.action(walk).play()
mixer.action(walk).fade_in(Duration(0.5, SECOND))
mixer.cross_fade_from(run, walk, Duration(1, SECOND), warp=True)
```

A fade or a warp starts at the mixer's time now. It is read at the mixer's time after each update adds its delta. three.js reads its `_weightInterpolant` and `_timeScaleInterpolant` the same way.

| Call | Weight or time scale | At the end |
|---|---|---|
| `fade_in(d)` | Weight times 0, rising to 1. | The action goes on. |
| `fade_out(d)` | Weight times 1, falling to 0. | The action stops contributing. |
| `warp(a, b, d)` | Time scale from `a` to `b`. | `time_scale` becomes `b`. |
| `halt(d)` | Time scale from its effective value to 0. | The action pauses. |

A fade or a warp ends on the first update after the mixer's clock passes its end. An update that reaches the end exactly uses the end value.

A warp keeps its two values as shares of the time scale at the call. three.js does the same. So you cannot warp an action with a time scale of zero.

`fade_in` does not play the action. Call `play` as well.

### Cross-fades

`cross_fade_from(index, from_index, d)` fades `index` in and `from_index` out over `d`. `cross_fade_to(index, to_index, d)` does the same the other way round.

With `warp=True`, each action also ramps its pace toward the pace of the other clip. The pace is the ratio of the two clip lengths, as in three.js.

A cross-fade is a mixer call, not an action call. It changes two actions, and one action cannot reach another in the mixer's list.

### Start times

`start_at(time)` holds the action's clock until the mixer's clock reaches `time`. The action contributes its pose while it waits. The update that passes `time` runs only the part after it.

## Events

The mixer records what happens to each action during an update. Read the events with `drain_events` after each update.

```mojo
from animation.animation_mixer import FINISHED, LOOPED

mixer.update(scene, clock.delta())
for event in mixer.drain_events():
    if event.kind == FINISHED:
        print("action", event.action, "finished")
```

| Kind | When | `loop_delta` | `direction` |
|---|---|---|---|
| `LOOPED` | A `REPEAT` or `PING_PONG` action runs past an end of its clip. | Ends passed, signed. | 1 or -1. |
| `FINISHED` | A `ONCE` action reaches an end of its clip. | 0 | 1 or -1. |

`action` is the index that `add` returned. A `PING_PONG` action counts both ends, as three.js does.

Each update starts a new list. Events that you do not drain are gone after the next update.

### Why a list and not a listener

three.js dispatches `loop` and `finished` to listener functions. A Mojo closure that captures the caller's state does not fit in a list on the mixer. A list of typed events does, and the caller reads it when it is ready.

## What is refused

| Mistake | Answer |
|---|---|
| A kind or an interpolation that is not named. | An error at construction. |
| A track with no keys. | An error at construction. |
| Times that are negative, or that do not rise. | An error at construction. |
| Values that do not divide into one per key. | An error at construction. |
| A rotation key that is not of unit length. | An error at construction. |
| A `QUATERNION` track that is `SMOOTH`. | An error at construction. |
| A `CUBIC_SPLINE` track without tangents, or with tangents that are not one per value. | An error at construction. |
| An ending mode that is not named. | An error at `sample`. |
| Reading a rotation off a position track, or the other way round. | An error. |
| A clip with no tracks, or one that lasts no time. | An error at construction. |
| A weight below zero, or a loop mode that is not named. | An error. |
| A fade, a warp or a cross-fade that lasts less than no time. | An error. |
| A warp on an action with a time scale of zero. | An error. |
| A cross-fade from an action to itself. | An error. Nothing changes. |
| A weight, a time scale, a frame time, a start time or a key that is not a number. | An error. |
| An action index the mixer does not have. | An error. |
| A track naming a node the scene does not have. | An error at `update`. |
| A track naming a mesh, a light or a material that is not there. | An error at `update`. |
| A material track given to `update(scene, delta)`. | An error. Use `update(scene, assets, delta)`. |
| A group member that is not in the scene. | An error at `update`. |
| A value that its property cannot hold. | An error at `update`. |
| A target function given a kind of another thing. | An error. |
| A morph target below 0 or above 7. | An error. |
| A `VISIBLE` track that is not `STEP`, or a key of one that is not 0 or 1. | An error at construction. |
| A blend mode that is not named. | An error. |
| A frame rate that is not above zero, or a frame below zero. | An error. |
| A subclip range that ends before it starts, or that keeps no clip. | An error. |

A clip of no length is refused where clips are built. That is what lets an action divide by the length when it loops, without asking first.

## Not ported

- `StringKeyframeTrack`: nothing in the port has a string property.
- `InterpolateBezier`, three.js's cubic Bezier keys with 2D control points.
- Tracks on other properties. A track drives only the properties in the table of kinds.
- `AnimationObjectGroup.uncache` and its statistics. An action keeps no binding per member to release.
- `repetitions`: a `REPEAT` or `PING_PONG` action loops without end. So a `FINISHED` event comes only from `ONCE`.
- The mixer's own `timeScale`.
- `setDuration` and `syncWith`.

## Where this port differs from three.js

- A `SMOOTH` rotation track is an error. three.js prints a warning and uses `LINEAR`.
- A `SMOOTH` track reads the action's endings on every frame. three.js keeps the weights of a pair of keys until the time moves to a different pair. On a track with two keys it keeps the endings of the first frame, so a `REPEAT` clip never wraps.
- `make_clip_additive` with a `CUBIC_SPLINE` reference read between two keys takes off the value of the curve. three.js reads the wrong numbers from its result there, and every key of the target becomes not a number.

- `make_clip_additive` returns a new clip. three.js changes the clip that you give it.
- A frame rate of zero or less is an error. three.js uses 30 frames a second in its place.
- A subclip must last longer than no time. three.js returns a clip of no length, which nothing can play.
- An action keeps its own copy of a group. three.js shares the group between actions.

## See also

- [Scene graph](Scene-graph) has the nodes a track drives.
- [Materials](Materials) has the fields a material track drives.
- [Rotations](Rotations) has `slerp`, which a rotation track turns along.
- [Units](Units#clock) has the `Clock` that gives `update` its delta.
