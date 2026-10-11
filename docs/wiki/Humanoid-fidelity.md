# Humanoid fidelity

A rendered humanoid is not a validated engineering model. Visual detail and physical fidelity are separate choices. The software keeps them apart with four records: a creation recipe, a content record, mapping records and a canonical record.

The anatomical templates provide named parts, dimensions, tissue properties and approximate masses. They do not establish accuracy for a real person. Engineering use requires independent geometry, material, load and solver validation.

## Representations

| Representation | Preserved | Limits |
|---|---|---|
| Anatomical fields | Named bones and tissues, template dimensions, meter coordinates | Authored dimensions and approximate fields; no patient-specific calibration |
| Scanned head | ICT identity modes, facial topology and expression shapes | A visual surface fitted over a vault and neck proxy |
| Game humanoid | Skin, nineteen animation joints, skin weights and clips | No tissue fields, mass model or constitutive simulation |
| Decimated mesh | Fewer triangles, rebuilt normals and texture coordinates | Changed topology; most custom attributes and physical meaning are not preserved |
| glTF bake | Visual geometry, materials, skeletons, morphs, animations, the creation recipe and the content record | No tissue model or engineering validation |
| Canonical record | Versioned SI geometry fingerprints, tissue labels and sampled properties of named parts | Template estimates of the listed parts only; no whole-body or clinical claim |

`Length` values enter the templates with units. Frames place geometry in meters. A `Vector3` position does not retain a unit tag or anatomical identity. A game bake stores the complete `HumanoidSpec` in its creation recipe. The canonical record is a separate document.

## Face identity and anatomy

Authored head controls move landmarks through `HeadMorph`. This lets several anatomical layers share a frame.

The eight `FACE_SHAPE` controls follow a different path. They apply ICT identity modes to scanned vertices. They do not deform the authored skull, mandible, muscles or vessels with those same modes. Eyeball placement uses approximate mean shifts from the identity modes.

`ScannedHead` fits a coarse surface over `HeadHull`. That hull represents the vault and neck. It does not test containment against every anatomical part. A shared frame does not prove correct tissue clearance or contact.

Changing an identity requires separate checks of bone containment, eye fit, dental fit and tissue thickness. [Fit checks](#fit-checks) measure the geometric clearances. They show that the current identity path does not keep these fits.

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

The glTF exporter preserves supported visual attributes and supplied animations. It does not automatically export `thinness`, tissue fields, masses or solver parameters. Node and geometry `user_data` can carry explicit provenance through `extras`. The game builder writes a fail-closed creation recipe and a content record; see below.

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

## Bake fingerprints and stale-bake checks

A bake record holds three fingerprints. A changed spec or quality option
changes a fingerprint.

| Field | Fingerprint of |
|---|---|
| `spec_fingerprint` | The complete canonical inputs: stature, sex, athleticism and all 43 genes |
| `visual_settings_fingerprint` | The triangle budget, details, hair, materials and facial recipe |
| `recipe_digest` | The complete recipe, with revisions, units, frame and transform |

Each fingerprint is the 64-bit FNV-1a hash of normalized JSON text. It is
sixteen lowercase hexadecimal digits. It is not a cryptographic hash.

The recipe records `canonical_to_local_rest` as a column-major 4x4 matrix.
The game path uses the identity matrix. Translations are in meters.

Schema version 2 adds the fingerprints and the matrix. Schema version 3
adds `converted_sources`. A bake of an earlier version is refused as stale.

Use these checks after you load a bake:

- `stored_provenance` recomputes each fingerprint from the stored recipe.
  It refuses a missing, incomplete or edited record.
- `require_current_spec` compares the exact canonical inputs with a spec.
  It ignores visual settings and revisions.
- `require_bake_provenance` names a changed spec or changed settings first.
  It then compares the complete record.

A stale bake raises an error. It never represents a changed spec silently.
The recipe checks do not hash the mesh bytes. The
[content record](#bake-content-record) does.

The canonical, visual and asset revisions are semantic versions. A
producer must change its recipe revision when its topology, rig or mapping
changes. Custom material IDs identify entries in the caller's store, not
immutable material bytes. The converted sources are verified hashes; see
the next section.

The record marks identity, expression/jaw, dental, skin-weight and LOD
physical mappings as unsupported. It does not embed canonical geometry or
physical properties. The game mesh remains a visual derivative.

## Verified converted sources

`converted_sources` binds each converted input to its pinned manifest. The
module is `extensions/humanoid/sources.mojo`. It reads
`assets/converted-asset-manifest.json`, which #303 pins. See
[Converted face and hair assets](Converted-assets).

1. `game_source_paths` names the assets that a build reads. Every build
   reads the face model. Strand guides of a scanned style also read that
   style's hair file.
2. The function computes the SHA-256 of each asset with `file_sha256`.
3. The digest must equal the manifest's pinned SHA-256.
4. The record copies the upstream repository, commit, format version and
   license of each asset. It also records the manifest's own SHA-256.

A changed asset, an unpinned asset or another manifest schema is an error.
`add_game_humanoid` records the result in the recipe and sets
`source_manifest_verified`. A consumer calls `converted_sources` again to
build its expected recipe. So a changed source makes an old bake stale.

`sha256_hex` is a FIPS 180-4 SHA-256 in Mojo. The tests check it against
published test vectors. The check reads the files at build time. It does
not prove that a later reader loads the same bytes.

## Bake content record

`add_game_humanoid` also writes a content record under
`threemojo_humanoid_content`. The module is `extensions/humanoid/bake.mojo`.

| Field | Contents |
|---|---|
| `recipe_digest` | The digest of the creation recipe that this content belongs to |
| `meshes` | One `geometry_fingerprint` per skinned and rigid mesh under the root, sorted |
| `content_digest` | The fingerprint of the complete mesh inventory |
| `mappings` | One mapping record per named mapping |

`geometry_fingerprint` hashes the exact Float32 bits of the positions, the
index list, the skin indices and weights, and every morph target. Normals,
texture coordinates and colors are not covered. The hash is FNV-1a over
little-endian words. It detects changed bytes, not a deliberate forgery.

`require_bake_content` checks a loaded humanoid:

1. It applies `require_bake_provenance` to the root's extras.
2. The content must belong to the expected recipe.
3. It fingerprints every mesh under the root again. A changed vertex is an
   error.
4. Each mapping must match the expected source and the loaded topology.
5. The complete record must equal a rebuilt record.

A glTF round trip keeps every checked byte. The game builder snaps its skin
weights so that the loader's normalization keeps them. See
[Game humanoid](Game-humanoid#the-skin-and-its-weights).

## Mappings and invalidation

`extensions/humanoid/mapping.mojo` names each path from canonical data to a
visual asset. `MappingKind` is a type with `is_valid`.

| Kind | Source fingerprint | Topology fingerprint | Scope |
|---|---|---|---|
| `IDENTITY_MAP` | Face model SHA-256 | Scanned face part ranges | Genes weigh scanned identity modes; canonical bones do not follow |
| `EXPRESSION_JAW_MAP` | Face model SHA-256 | Scanned face part ranges | Expressions move the scanned skin and mouth; the canonical mandible does not follow |
| `EYE_MAP` | Face model SHA-256 | Scanned face part ranges | Identity mean shifts place the eyeballs; no orbit containment |
| `DENTAL_MAP` | Face model SHA-256 | Scanned face part ranges | Two separate dentitions |
| `SKIN_WEIGHT_MAP` | Rig revision and joint count | Mesh inventory topology | Animation weights; no tissue or load transfer |
| `LOD_MAP` | Full-resolution topology | Mesh inventory topology | Visual decimation; canonical mass and contact geometry stay in the canonical record |

`require_mapping` refuses a record when its source or topology fingerprint
changed. It also refuses an edited record. So a changed face model, rig or
mesh topology invalidates each mapping that indexes it.

The level-of-detail source is the topology before decimation. A load check
verifies the decimated topology. Only a rebuild can compute the source
fingerprint again. Compare the stored record with a rebuilt one to check it.

The dental record names two representations: the authored `BONES` teeth and
the scanned `MOUTH` teeth. They stay separate until a tested correspondence
exists. `require_physical_mapping` refuses every kind. No mapping carries a
tested physical correspondence.

## Canonical record

`canonical_record(spec)` returns a versioned record of named canonical
parts. The module is `extensions/humanoid/canonical.mojo`. It reads only
the spec. No mesh budget, visual widening, material or bake enters it.

| Part | Geometry | Physical properties |
|---|---|---|
| Skull, mandible, authored teeth | Isosurface mesh fingerprints and bounds in meters | Sampled bone-tissue mass and region volumes; the tensor is `null` |
| Right and left eyeballs | Mesh fingerprints, center and radius in meters | `null`; no density is assigned |
| Thigh, shank and foot of each leg | Integration bounds in meters | Mass, center and all six tensor entries about the center of mass, with region masses |

Each part has a stable ID such as `head/skull` and tissue labels. Each part
names its frame and origin. Head parts use the pelvis frame. Leg parts use
the tibiofemoral leg frame of [Segment inertia](Segment-inertia).
`CanonicalPart` is a type with `is_valid`.

`require_canonical_record` evaluates the record again and compares every
field. It refuses another schema, revision or spec, and any edited value.
The game example stores the record in the scene extras beside the bake.
It checks the record after each load.

The record is independent of the visual derivative. A decimated build or a
bake leaves its bytes unchanged. A different triangle budget cannot change a
canonical mass or a contact-geometry fingerprint. The values remain template
estimates. The record does not cover the whole body or establish
convergence.

## Fit checks

`extensions/humanoid/fit.mojo` measures visual vertices against authored
canonical fields. Each check returns a `FitReport` of signed distances in
meters. A negative distance is inside the field.

| Check | Samples | Field |
|---|---|---|
| `skin_bone_fit` | Fitted scanned skin above the scan floor | A head bone, such as the skull |
| `eye_bone_fit` | Eyeball vertices | A head bone |
| `dental_fit` | Scanned `MOUTH` teeth | The authored `BONES` teeth |

`require_clearance` refuses a report whose minimum is below a clearance.
`require_containment` refuses a report whose maximum exceeds a tolerance.

These results apply to the six-foot template at this revision. The tests
check the sign of each result:

- The fitted skin clears the skull by about 0.25 mm. It is about 0.1 mm
  inside the mandible at its closest vertex.
- With every face-shape gene at +1, the skin enters the skull by about
  1.3 mm and the mandible by about 9 mm.
- With every gene at -1 at 2.5 m, the skin enters the skull by about 16 mm.
- The eyeballs enter the authored skull field by about 6 mm. The identity
  moves the eyes but not the skull.
- Most scanned tooth vertices lie outside the authored teeth, up to about
  27 mm away.

So the identity, eye and dental mappings remain visual. These checks
measure geometry only. They do not validate tissue thickness or contact.

## Independent canonical snapshots

`tools/humanoid_fidelity.py` packages explicit canonical part meshes and
properties supplied by a caller. It never derives physical properties from
a visual mesh. Each part has a stable ID, a tissue label, meter vertices
and triangle indices. Parts and properties must explicitly match the snapshot's
frame and origin label. Properties retain mass in kilograms, center in meters
and all six tensor entries in kilogram-meter-squared units.

A missing
property remains `null`. It is not replaced by a guessed density.

The snapshot retains the complete schema-version-1 or schema-version-2 anatomy
validity report. Both versions use the same sampled-property contract.
Version 2 also retains its diagnostic frames and versioned pair inventory.
The snapshot's own schema version remains 1.

It does not consume raw probe
rows or recompute anatomy. Keep the report's accounting proxy names, scope
and unsupported uses. The reader
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

All six acceptance criteria of #297 are met. The contract keeps the visual
derivative and the canonical data apart. It does not validate anatomy.

| Requirement | Evidence |
|---|---|
| Separate visual and engineering capabilities | `HumanoidUse` gate; game and bake records fail closed |
| Retain canonical SI geometry, labels and properties | `canonical_record` with eleven typed parts, independent of every visual setting; checked after decimation and a GLB round trip |
| Identity, jaw, weights and LOD mappings | `MappingKind` records with source and topology fingerprints; `require_mapping` refuses changed sources and topologies; both dentitions stay named |
| Bake provenance and stale-spec checks | Schema 3 recipe with revisions, units, handedness, origin, transform, fingerprints and verified source SHA-256 values; a content record of every checked mesh byte |
| Frames, full tensors and reference points | Tested offline proper-rotation and parallel-axis adapter |
| Round trips and extreme identities | GLB round trips of the recipe, content and canonical records; extreme-identity records and fit checks; refused unsupported paths |

Global anatomical validation, constitutive models and mass convergence are
out of scope for #297. No mapping has a tested physical correspondence, so
engineering use stays refused. No measured anatomical parameter changes for
appearance. No biomechanical, patient-specific or clinical calibration is
claimed.
