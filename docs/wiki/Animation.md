# Animation

`animation/keyframe_track.mojo`, `animation/animation_clip.mojo` and `animation/animation_mixer.mojo`. A track gives one property of one node a value at a list of times. A clip plays tracks together. A mixer plays clips and writes the pose into a scene.

![A mixer slides and turns a cube from keyframes](out/keyframes.png)

three.js: `KeyframeTrack`, `VectorKeyframeTrack`, `QuaternionKeyframeTrack`, `AnimationClip`, `AnimationAction`, `AnimationMixer`.

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

| Member | Meaning |
|---|---|
| `key_count() -> Int` | How many keys the track holds. |
| `duration() -> Duration` | When the last key is. |
| `sample(at) -> List[Float32]` | The value at a time, as numbers. |
| `sample_vector3(at) -> Vector3` | The value of a `POSITION` or `SCALE` track. |
| `sample_quaternion(at) -> Quaternion` | The value of a `QUATERNION` track. |

Before the first key the value is the first key's. After the last it is the last key's. three.js's interpolants do the same at their ends.

### A track names a node, not a string

three.js names its target with a string, `.position` or `.quaternion`, and looks the object up by name at run time. Here a track holds a `NodeId` and a kind, both of which the compiler checks.

A string that matches nothing is three.js's most common animation bug, and naming the property by type removes it. Naming the *node* by type does not: a `NodeId` is an index, and the scene it indexes is chosen at `update`. The mixer checks there, and raises on a node the scene does not have.

### How two keys are mixed

`LINEAR`, the default, runs evenly from each key to the next. `STEP` holds each key's value until the next key, which is three.js's `InterpolateDiscrete`.

Two rotations are mixed by `slerp`, not one number at a time. A rotation is not four numbers to average. Averaging them makes a turn that speeds up in the middle. It also makes a quaternion that is no longer a rotation. three.js keeps `QuaternionLinearInterpolant` apart for the same reason.

three.js has a third mode, `InterpolateSmooth`. It is not ported. It is not a Catmull-Rom spline through the keys. It takes the uneven spacing of the times into account, and the spline in [Curves and paths](Curves) does not.

## AnimationClip

```mojo
from animation.animation_clip import AnimationClip

var clip = AnimationClip("slide", [slide^])
```

A clip is a name and a list of tracks. It lasts as long as its longest track, which is how three.js works a duration out in `resetDuration`.

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
| `update(scene, delta)` | Move every playing action on, and set the nodes. |

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

## What is refused

| Mistake | Answer |
|---|---|
| A kind or an interpolation that is not named. | An error at construction. |
| A track with no keys. | An error at construction. |
| Times that are negative, or that do not rise. | An error at construction. |
| Values that do not divide into one per key. | An error at construction. |
| A rotation key that is not of unit length. | An error at construction. |
| Reading a rotation off a position track, or the other way round. | An error. |
| A clip with no tracks, or one that lasts no time. | An error at construction. |
| A weight below zero, or a loop mode that is not named. | An error. |
| A weight, a time scale, a frame time or a key that is not a number. | An error. |
| An action index the mixer does not have. | An error. |
| A track naming a node the scene does not have. | An error at `update`. |

A clip of no length is refused where clips are built. That is what lets an action divide by the length when it loops, without asking first.

## See also

- [Scene graph](Scene-graph) has the nodes a track drives.
- [Rotations](Rotations) has `slerp`, which a rotation track turns along.
- [Units](Units#clock) has the `Clock` that gives `update` its delta.
