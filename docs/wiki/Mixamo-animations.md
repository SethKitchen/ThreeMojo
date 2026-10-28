# Mixamo animations

Any Mixamo animation can play on the [game humanoid](Game-humanoid). One script downloads the animations from your Adobe account. Another script puts them on the humanoid's nineteen bones and writes one `.glb` file with a clip for each.

```bash
export MIXAMO_TOKEN=...   # see "Get the token"
.venv/bin/mojo run -I . tools/mixamo.mojo download
.venv/bin/mojo run -I . tools/mixamo.mojo bake
```

The first command saves every animation in `.cache/mixamo/animations`. The second writes `out/humanoid_mixamo.glb`. Git ignores both places.

## Before you start

Mixamo's terms of use apply to the files. They are yours to use in your own projects. Do not commit them. Do not share them. Do not share the `.glb` file that holds them.

The download script talks to the same web interface as the Mixamo site. Adobe does not publish this interface. It can change. The script uses the calls of the community downloader `gnuton/mixamo_anims_downloader`.

On 25 October 2026 the script listed all 2,444 animations of a free account, with 41 bundles. It downloaded 21 of them as real skin-less FBX files. All 21 baked onto the humanoid. The retarget and the bake also ran on two Mixamo files with skin from the three.js examples: `Samba Dancing.fbx` and `mixamo.fbx`. The humanoid followed the Mixamo character's pose in each frame that was compared.

The tests use a stub `curl`, so they do not reach Mixamo. Run `download --limit 1` first, then `inspect`, before you start a long run. A full run takes about four hours.

You need:

- The Mojo pin in `.venv/`.
- `curl` on your path.
- An Adobe account that can use mixamo.com.

## Get the token

1. Sign in on mixamo.com.
2. Open the browser's developer tools. Open the storage view for `https://www.mixamo.com`.
3. Copy the value of `access_token` from the local storage.
4. Put it in the environment variable `MIXAMO_TOKEN`. Or put it alone in a file, and pass `--token-file FILE`.

The token is a password. The script never puts it on a command line. It writes it to a private file for `curl`, and removes the file after each request. Do not paste the token into a shell history or a shared file.

The token expires. When Mixamo refuses it, the script stops and says so. Get a new token and run the command again.

Mixamo exports every animation for one character. The script uses your account's primary character, the one the site has selected. Pass `--character ID` to use another one. The humanoid does not use this character's mesh.

## Download every animation

```bash
.venv/bin/mojo run -I . tools/mixamo.mojo download
```

The script reads the whole list. For each animation it asks Mixamo for an export without a skin, waits until the export is ready, and saves the FBX file. The script skips a bundle, because an export needs one animation.

Mixamo's list changes order between requests. A page can repeat an animation and leave another out. So the script reads the list again until it has seen every animation that Mixamo counts.

| Option | Meaning |
|---|---|
| `--character ID` | The character to export for. The default is the account's primary character. |
| `--output DIR` | The folder. The default is `.cache/mixamo/animations`. |
| `--token-file FILE` | A file that holds the token. |
| `--api URL` | The API's address. Use it for a test server. |
| `--query TEXT` | Only the animations whose name has this text. |
| `--limit N` | Stop after `N` new files. |
| `--list` | Print the names. Fetch nothing. |
| `--in-place` | Ask Mixamo to keep the hips in place. |
| `--fps N` | Frames a second in the file. The default is 30. |
| `--format NAME` | An FBX format. The default is `fbx7`. |
| `--delay SECONDS` | The wait between polls and between animations. The default is 1. |
| `--polls N` | How often to ask if an export is ready. The default is 120. |

A run that stops starts again where it was. A file that is there is not fetched again. The script also writes `animations.json` in the folder, which maps each Mixamo id to its file.

A busy server answers 429. The script waits and asks again. An animation that fails is listed at the end, and the exit status is 1. The other animations are still saved.

## Check a file

```bash
.venv/bin/mojo run -I . tools/mixamo.mojo inspect .cache/mixamo/animations/Walking.fbx
```

`inspect` says how many bones the file has. It says how many of the 23 bones that the retarget reads are there. It lists each animation with its length and its number of tracks. The exit status is 1 when a file holds no animation.

## Put the animations on the humanoid

```bash
.venv/bin/mojo run -I . tools/mixamo.mojo bake
```

`bake` builds the game humanoid as `examples/game_humanoid.mojo` does. It retargets every FBX file of the folder. It then writes one sealed `.glb` file. A file that cannot be read is skipped and listed. The other files are still baked.

| Option | Meaning |
|---|---|
| `--animations DIR` | The folder of FBX files. |
| `--output FILE` | The `.glb` file. The default is `out/humanoid_mixamo.glb`. |
| `--height-feet N` | The humanoid's height. The default is 6. |
| `--sex NAME` | `male` or `female`. The default is `male`. |
| `--triangles N` | The skin's triangle budget. The default is 10,000. |
| `--only TEXT` | Only the files whose name has this text. |
| `--limit N` | At most `N` files. |
| `--fps N` | Keys a second in the clips. The default is 30. |
| `--keep-travel` | Keep the hips' travel along the ground. |

The clip takes the file's name. `Walking.fbx` gives the clip `Walking`. Two files with one name get `Walking` and `Walking 2`.

## Use a clip in a game

A game loads the file with `read_gltf` and finds each clip by its name. Then it calls `require_sealed_bake`, as for any [baked humanoid](Game-humanoid#baking-and-speed).

To retarget in the game itself, call `read_mixamo` with the humanoid's bones and rig.

```mojo
from extensions.humanoid.rig.game import add_game_humanoid
from extensions.humanoid.rig.mixamo import read_mixamo

var person = add_game_humanoid(scene, assets, root, spec, 10000)
var clips = read_mixamo("Walking.fbx", person.bones, person.rig)
var walk = mixer.add(AnimationAction(clips[0].copy()))
mixer.action(walk).play()
```

`read_mixamo` returns one clip for each animation stack in the file. `MixamoOptions(in_place, samples_per_second)` sets the two options of the retarget. `retarget_mixamo` does the same for a file that you already loaded with `read_fbx`.

## How the retarget works

The Mixamo skeleton has 65 bones and stands in a T-pose. The humanoid has 19 bones and stands with its arms by its sides. The two do not share bone directions. So the retarget cannot copy rotations from one to the other.

Each humanoid bone has one driving Mixamo bone.

| Humanoid | Mixamo |
|---|---|
| hips | `Hips` |
| spine, chest | `Spine1`, `Spine2` |
| neck, head | `Neck`, `Head` |
| upper arm, forearm, hand | `Arm`, `ForeArm`, `Hand` |
| thigh, shin, foot, toes | `UpLeg`, `Leg`, `Foot`, `ToeBase` |

For each sample, the retarget takes the driver's world rotation since the rest pose. It first swings the humanoid's bone from where it hangs to where the driver stands at rest. It then applies the driver's rotation. So each humanoid bone points where its driver points in every frame.

The hips move as the Mixamo hips move, scaled by the ratio of the two hip heights above the ankles. With `in_place`, the straight line of the hips' travel along the ground is taken out. A walk then stays near the origin and keeps its sway. A game moves the humanoid's root node itself.

The file's own pose is the rest pose. Mixamo files hold their T-pose there.

## Limits

- **Sides.** The humanoid faces +z with its right side at +x. Mixamo faces +z with its left side at +x. The retarget pairs the sides by where they stand. A Mixamo left arm drives the humanoid arm at +x.
- **Roll.** The retarget keeps the twist of each driver but does not correct a forearm's roll. A hand can turn its palm differently from the Mixamo character.
- **Fingers and shoulders.** The humanoid has no finger bones and no shoulder bones. The retarget drops them. The arm's world rotation already holds the shoulder's.
- **Required bones.** A file must hold `Hips`, and an `Arm`, `ForeArm`, `UpLeg`, `Leg` and `Foot` of each side. The retarget refuses a file without them. Missing spine, head, hand or toe bones make the joint follow its parent.
- **Skin.** The skin's weights decide how a bent arm looks. A T-pose can show webbing at the armpit.

## See also

- [Game humanoid](Game-humanoid): the rig, the skin and the clips that ship with it.
- [Animation](Animation): clips, tracks and the mixer.
- [Model files](Model-files): the FBX loader.
