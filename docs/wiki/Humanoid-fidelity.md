# Humanoid fidelity

A rendered humanoid is not a validated engineering model. Visual detail and physical fidelity are separate choices.

The anatomical templates provide named parts, dimensions, tissue properties and approximate masses. They do not establish accuracy for a real person. Engineering use requires independent geometry, material, load and solver validation.

## Representations

| Representation | Preserved | Limits |
|---|---|---|
| Anatomical fields | Named bones and tissues, template dimensions, meter coordinates | Authored dimensions and approximate fields; no patient-specific calibration |
| Scanned head | ICT identity modes, facial topology and expression shapes | A visual surface fitted over a vault and neck proxy |
| Game humanoid | Skin, nineteen animation joints, skin weights and clips | No tissue fields, mass model or constitutive simulation |
| Decimated mesh | Fewer triangles, rebuilt normals and texture coordinates | Changed topology; most custom attributes and physical meaning are not preserved |
| glTF bake | Supported visual geometry, materials, skeletons, morphs and animations | No automatic anatomical provenance, tissue model or engineering validation |

`Length` values enter the templates with units. Frames place geometry in meters. A `Vector3` position does not retain a unit tag or anatomical identity. A glTF file also does not store the original `HumanoidSpec` automatically.

## Face identity and anatomy

Authored head controls move landmarks through `HeadMorph`. This lets several anatomical layers share a frame.

The eight `FACE_SHAPE` controls follow a different path. They apply ICT identity modes to scanned vertices. They do not deform the authored skull, mandible, muscles or vessels with those same modes. Eyeball placement uses approximate mean shifts from the identity modes.

`ScannedHead` fits a coarse surface over `HeadHull`. That hull represents the vault and neck. It does not test containment against every anatomical part. A shared frame does not prove correct tissue clearance or contact.

Changing an identity requires separate checks of bone containment, eye fit, dental fit and tissue thickness. The software does not perform those engineering checks.

## Expressions and teeth

Facial morphs move the scanned skin, teeth, gums and tongue. They do not update the anatomical mandible field, joint constraints or tissue loads.

`BONES` draws the authored anatomical teeth. `MOUTH` draws the scanned expression teeth and soft mouth tissues. `ALL` includes both representations. They are separate meshes and do not share a dental correspondence map.

Use `BONES` for the anatomical view. Use `SKIN.plus(EYES).plus(MOUTH)` for the expression view. Adding `HAIR` also draws the scalp shell. A view with both tooth sets is an overlay, not one coupled dentition.

`Speech` is a spelling-based visual animation. It does not supply muscle forces, jaw mechanics or audio alignment.
[Audio-aligned game faces](Audio-aligned-game-faces) adds caller-provided alignment and an audio-clock contract. It remains visual-only and does not validate physical correspondence.

## Skin, mass and hair

Head skin mass samples a thin shell of the scanned-and-modeled skin field. The rendered scan also contains mouth and eye sockets. It is not a volume mesh for that mass calculation.

Bone and tissue masses use their own fields or analytic volumes. They are not computed from the decimated game skin. Facial expressions do not recalculate them.

Scalp hair mass uses the authored hair volume and a packing factor. It does not sum the strands of a groom. Changing strand count, style or simulation state is not a mass update.

Hair dynamics are a visual position-constraint model. They do not provide validated human-hair constitutive properties or forces coupled to the body.

## Animation, level of detail and baking

`add_game_humanoid` creates skin and nineteen animation joints. It does not include the anatomical layers. Its joints support animation, without anatomical limits, contact forces or muscle activation.

The game builder does not currently combine the facial morph rig with its skinned body. Its mesh budget is a visual setting. It is not an engineering accuracy setting.

The simplifier changes topology and vertex positions. It has no volume, mass, tissue-boundary or joint-clearance error limit. The game builder restores color and thinness by nearest-vertex transfer. This does not restore anatomical correspondence.

The glTF exporter preserves supported visual attributes and supplied animations. It does not automatically export `thinness`, tissue fields, masses or solver parameters. Node and geometry `user_data` can carry explicit provenance through `extras`. The game builder now populates a fail-closed creation recipe; see below.

The game example checks the expected creation recipe before reusing a bake. Its filename alone is not a verified fingerprint of the spec or mesh budget.

## Engineering use

Keep the canonical anatomical inputs separate from visual meshes and baked files. Record the spec, coordinate frame, source versions, units and tissue assumptions. Record every identity transform and mesh operation.

An engineering workflow must validate its own discretization and material model. It must check convergence, boundaries, contact, mass and inertia against the intended use. It must also define any mapping between visual vertices and physical tissues.

The current templates, scans and game assets do not meet these requirements by default. A higher visual quality level does not change that limit.

See [Head](Head), [Genome](Genome), [Game humanoid](Game-humanoid), [Mesh quality](Mesh-quality) and [Segment inertia](Segment-inertia).

## Versioned creation contract

`extensions.humanoid.fidelity` separates the supported `VISUAL_USE` from
`ENGINEERING_USE`. `require_humanoid_use` always refuses engineering use.
No mesh quality, identity setting or material can change that result.
The gate does not claim that the canonical template is calibrated.

`canonical_inputs` copies the full accepted `HumanoidSpec`. It records
stature in meters, sex, athleticism and all 43 genes. It also records exact
Float32 bits. Adjacent input values cannot share a recipe by rounding.
The snapshot is independent of mesh budgets and visual widening.

`add_game_humanoid` writes the creation contract to its root's user data.
The glTF exporter retains it as `extras.threemojo_humanoid_fidelity`.
The record identifies the canonical, visual and converted-model recipes.
It records the right-handed, y-up, pelvis-origin rest frame. Parent and
animation transforms remain separate glTF node and animation data.

The game example also writes scene extras. It checks the complete expected
record after loading, before animation or rendering. A missing or changed
record is an error. Delete the stale bake to build a new one.

These recipe revisions are semantic versions. They are not verified
upstream commits or content hashes. A producer must change its recipe
revision when its source, topology, rig or mapping changes. Custom material
IDs identify entries in the caller's store, not immutable material bytes.
Converted ICTF and THRS source manifests remain unverified under #303.
The record exposes that limit instead of inventing a source or license.

The record marks identity, expression/jaw, dental, skin-weight and LOD
physical mappings as unsupported. It does not embed canonical geometry or
physical properties. The game mesh remains a visual derivative.
A recipe check does not prove that an externally edited asset still matches
its recipe. Use a separate content digest for that check.

## Independent canonical snapshots

`tools/humanoid_fidelity.py` packages explicit canonical part meshes and
properties supplied by a caller. It never derives physical properties from
a visual mesh. Each part has a stable ID, a tissue label, meter vertices
and triangle indices. Parts and properties must explicitly match the snapshot's
frame and origin label. Properties retain mass in kilograms, center in meters
and all six tensor entries in kilogram-meter-squared units.

A missing
property remains `null`. It is not replaced by a guessed density.

The snapshot retains the complete schema-version-1 anatomy validity report
from #289. It does not consume raw probe rows or recompute anatomy. Keep
that report's accounting proxy names, scope and unsupported uses. The reader
checks its typed envelope, axis directions and exact tensor convention. A
supplied part mesh is not automatically a mesh of a report's sampled region.
The caller must establish that correspondence separately.

Snapshots have canonical JSON bytes and SHA-256 content identities. A
snapshot write refuses to replace different bytes at an existing path.
A visual derivative records both its own asset digest and the canonical
snapshot digest. Changed spec, identity, topology, source, LOD or visual
bytes invalidate the derivative. Editing a visual derivative cannot change
the retained canonical bytes. Both dental representations remain named.

## Coordinate and tensor adapters

The offline adapter accepts two explicit right-handed conventions:

- Y-up: +x is body-right, +y is up and +z is anterior
- Z-up: +x is body-right, +z is up and -y is anterior

The y-up to z-up adapter maps `(x, y, z)` to `(x, -z, y)`.
It is a proper rotation, not a reflection. Both conventions use meters.
The reverse adapter maps `(x, y, z)` to `(x, z, -y)`.
The snapshot requires an explicit source-origin label and retains its coordinates.

A translation is explicit and uses target-frame meters. Do not confuse the pelvis origin of the visual recipe
with the tibiofemoral origin of the lower-limb report.

`transform_inertia` consumes a tensor about the center of mass. Its six
entries are `xx, yy, zz, xy, xz, yz`. Off-diagonal entries use tensor signs.
It transforms the complete tensor with `R I Rᵀ`, including products of
inertia.

It then adds `m ((d·d) Identity - d dᵀ)`, where `d` is the transformed
center minus the requested target reference point. Omit the reference to
keep a center-of-mass tensor. Never reuse a shifted tensor as a COM tensor.

`adapt_part` moves a part's vertices and properties together. It preserves
labels and refuses to reuse a shifted tensor as a COM tensor. Existing part
and property frames must match the declared source frame. A nonzero
translation requires an explicit target-origin label.
The adapter refuses nonfinite values, negative mass, scales and reflections.
It does not test physiological validity or convergence.

## Acceptance boundary for #297

| Requirement | Implemented boundary | Exact remaining work |
|---|---|---|
| Separate visual and engineering capabilities | Typed native gate; game and bake records fail closed | A validated engineering coupling could add a capability only with independent evidence |
| Retain canonical SI geometry, labels and properties | Immutable caller-supplied part snapshots retain the full #289 report | Generate and verify complete canonical part meshes and region correspondence from library fields; whole-body property coverage is absent |
| Identity, jaw, weights and LOD mappings | Explicit unsupported maps, source/topology invalidation and two dental identities | Tested coupled maps, including eye fit and tissue clearance |
| Bake provenance and stale-spec checks | Game roots and example scene extras retain exact spec/options/frame recipes; offline manifests bind artifact bytes | Pin and verify converted source/model inputs and license manifests under #303; generic exporters cannot detect arbitrary post-build scene edits |
| Frames, full tensors and reference points | Tested offline proper-rotation and parallel-axis adapter | Native whole-body export integration when canonical part generation is available |
| Round trips and extreme identities | Synthetic glTF recipe round trips, immutable SI data, full-tensor analytic controls, all extreme gene recipes, stale assets and unsupported paths | Anatomical correspondence, eye/dental fit and tissue-clearance fixtures with approved source assets |

This slice does not close #297. No measured anatomical parameter changes
for appearance. No biomechanical, patient-specific or clinical calibration
is claimed. Synthetic fixtures need no new asset downloads or licenses.
