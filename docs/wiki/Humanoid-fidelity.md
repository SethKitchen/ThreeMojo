# Humanoid fidelity

A rendered humanoid is not a validated engineering model. Visual detail and physical fidelity are separate choices. The canonical parts keep the physical template apart from every visual mesh.

The anatomical templates provide named parts, dimensions, tissue properties and approximate masses. They do not establish accuracy for a real person. Engineering use requires independent geometry, material, load and solver validation.

`extensions.humanoid.canonical` generates versioned canonical part meshes and properties from the library's own fields. `extensions.humanoid.correspondence` holds the versioned maps from those parts to the visual meshes. Each map refuses an identity, a jaw weight or a path that its tests do not support. See [Canonical parts](#canonical-parts) and [Canonical-to-visual maps](#canonical-to-visual-maps).

## Representations

| Representation | Preserved | Limits |
|---|---|---|
| Anatomical fields | Named bones and tissues, template dimensions, meter coordinates | Authored dimensions and approximate fields; no patient-specific calibration |
| Canonical parts | Versioned SI part meshes, tissue labels and whole-body mass properties from the fields | A sampled template estimate at a recorded grid step; no convergence or clinical claim |
| Scanned head | ICT identity modes, facial topology and expression shapes | A visual surface fitted over a vault and neck proxy |
| Game humanoid | Skin, nineteen animation joints, skin weights and clips | No tissue fields, mass model or constitutive simulation |
| Decimated mesh | Fewer triangles, rebuilt normals and texture coordinates | Changed topology; most custom attributes and physical meaning are not preserved |
| glTF bake | Supported visual geometry, materials, skeletons, morphs and animations | No automatic anatomical provenance, tissue model or engineering validation |

`Length` values enter the templates with units. Frames place geometry in meters. A `Vector3` position does not retain a unit tag or anatomical identity. A glTF file also does not store the original `HumanoidSpec` automatically.

## Face identity and anatomy

Authored head controls move landmarks through `HeadMorph`. This lets several anatomical layers share a frame.

The eight `FACE_SHAPE` controls follow a different path. They apply ICT identity modes to scanned vertices. They do not deform the authored skull, mandible, muscles or vessels with those same modes. Eyeball placement uses approximate mean shifts from the identity modes.

`ScannedHead` fits a coarse surface over `HeadHull`. That hull represents the vault and neck. It does not contain every anatomical part by itself. A shared frame does not prove correct tissue clearance or contact.

`identity_fit` measures bone containment, eye fit and dental fit of each canonical body. `require_identity_fit` refuses an identity that fails a check. See [Identity map](#identity-map).

## Expressions and teeth

Facial morphs move the scanned skin, teeth, gums and tongue. They do not update the anatomical mandible field, joint constraints or tissue loads. Only `jawOpen` has a canonical coupling: a fitted hinge for the canonical mandible. See [Expression and jaw map](#expression-and-jaw-map).

`BONES` draws the authored anatomical teeth. `MOUTH` draws the scanned expression teeth and soft mouth tissues. `ALL` includes both representations. They are separate meshes and do not share a dental correspondence map. See [Dental map](#dental-map).

Use `BONES` for the anatomical view. Use `SKIN.plus(EYES).plus(MOUTH)` for the expression view. Adding `HAIR` also draws the scalp shell. A view with both tooth sets is an overlay, not one coupled dentition.

`Speech` is a spelling-based visual animation. It does not supply muscle forces, jaw mechanics or audio alignment.
[Audio-aligned game faces](Audio-aligned-game-faces) adds caller-provided alignment and an audio-clock contract. It remains visual-only and does not validate physical correspondence.

## Skin, mass and hair

Head skin mass samples a thin shell of the scanned-and-modeled skin field. The rendered scan also contains mouth and eye sockets. It is not a volume mesh for that mass calculation.

Bone and tissue masses use their own fields or analytic volumes. They are not computed from the decimated game skin. Facial expressions do not recalculate them. The canonical parts give whole-body properties from the same fields.

Scalp hair mass uses the authored hair volume and a packing factor. It does not sum the strands of a groom. Changing strand count, style or simulation state is not a mass update.

Hair dynamics are a visual position-constraint model. They do not provide validated human-hair constitutive properties or forces coupled to the body.

## Animation, level of detail and baking

`add_game_humanoid` creates skin and nineteen animation joints. It does not include the anatomical layers. Its joints support animation, without anatomical limits, contact forces or muscle activation.

The game builder does not currently combine the facial morph rig with its skinned body. Its mesh budget is a visual setting. It is not an engineering accuracy setting.

The simplifier changes topology and vertex positions. It has no volume, mass, tissue-boundary or joint-clearance error limit. The game builder restores color and thinness by nearest-vertex transfer. This does not restore anatomical correspondence. A decimated mesh never becomes a canonical part. See [LOD map](#lod-map).

The glTF exporter preserves supported visual attributes and supplied animations. It does not automatically export `thinness`, tissue fields, masses or solver parameters. Node and geometry `user_data` can carry explicit provenance through `extras`. The game builder now populates a fail-closed creation recipe; see below.

The game example checks the expected creation recipe before reusing a bake. Its filename alone is not a verified fingerprint of the spec or mesh budget.

## Engineering use

Keep the canonical anatomical inputs separate from visual meshes and baked files. Record the spec, coordinate frame, source versions, units and tissue assumptions. Record every identity transform and mesh operation. The canonical record and the map records hold these values.

An engineering workflow must validate its own discretization and material model. It must check convergence, boundaries, contact, mass and inertia against the intended use. The maps in this page are template checks. They are not that validation.

The current templates, scans and game assets do not meet these requirements by default. A higher visual quality level does not change that limit. `require_humanoid_use` still refuses `ENGINEERING_USE`.

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

The game example writes the bake with `write_sealed_bake`. The scene extras
then hold the record with a sealed geometry digest. After loading, the
example calls `require_sealed_bake` before animation or rendering. A
missing, stale or changed record is an error. Edited geometry is an error.
Delete the stale bake to build a new one.

`stored_spec` reads the exact spec back from a loaded record. Generate the
canonical parts from it to get the parts of the baked person. The record
names the canonical parts revision and the map revision for this reason.

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
adds the geometry digest. A version 1 or version 2 bake is refused as
stale. Rebuild it.

Use these checks after you load a bake:

- `stored_provenance` recomputes each fingerprint from the stored recipe.
  It refuses a missing, incomplete or edited record.
- `require_current_spec` compares the exact canonical inputs with a spec.
  It ignores visual settings and revisions.
- `require_bake_provenance` names a changed spec or changed settings first.
  It then compares the complete record.

A stale bake raises an error. It never represents a changed spec silently.
These recipe checks do not verify the geometry. The geometry digest does.

## Bake geometry digest

A sealed bake record holds a digest of its baked geometry. A geometry edit
after the build changes the digest, and the load check refuses the bake.

`extensions.humanoid.bake` writes and checks the digest:

- `write_sealed_bake` exports the scene as GLB and reads it back. It
  computes the digest over the loaded geometry and seals the record. It
  then writes the file with the sealed record in the scene extras.
- `require_sealed_bake` runs `require_bake_provenance` and then
  `require_bake_geometry`.
- `require_bake_geometry` recomputes the digest over the loaded scene. It
  refuses a mismatch, an unsealed record and a missing record.

The digest covers the geometry as the glTF loader reads it. The export
side and the load side thus hash the same values. The loader scales skin
weights to a sum of one. The loader drops attributes that glTF cannot
carry, for example `thinness`. The seal reads its own export back for this
reason. The digest is the same for GLB and embedded glTF.

The digest is the 64-bit FNV-1a hash of this byte stream. Each count and
index is eight little-endian bytes. Each value is the four little-endian
bytes of its float32 bit pattern.

1. The lengths of the scene's mesh, skinned mesh, instanced mesh, batched
   mesh, LOD, line and point lists.
2. Each skinned mesh, in list order: the bone count, the name of each
   bone's node, then its geometry.
3. Each mesh, in list order: its geometry.

A geometry adds these items, in this order:

| Item | Bytes |
|---|---|
| Groups | Count, then start, count and material index of each group |
| Index | Count, then each entry |
| Attributes | Count, then for each attribute in stored order: name length, UTF-8 name, item size, item count and each component |
| Morph positions, normals and colors | Count of each list, then each target as an attribute without a name |

The attributes include `position`, `normal`, `uv`, `color`, `skinIndex`
and `skinWeight` when the bake has them. A changed value, a reordered
vertex, a reordered mesh, a reordered attribute or an added mesh changes
the digest. Materials, textures, node transforms, inverse bind matrices
and animations are not covered.

The record field `geometry_digest` holds sixteen lowercase hexadecimal
digits. A record built before export holds `unsealed` in that field.
`add_game_humanoid` writes such a record on its root node.

`require_bake_provenance` accepts an unsealed record for its recipe check.
It does not verify the geometry. `require_bake_geometry` refuses an
unsealed record as unverified. `stored_provenance` refuses any other value.

You must verify the scene the bake was loaded into. Do the check before you
add other meshes. The digest is not cryptographic. It detects a careless
edit. It does not authenticate a file that an editor rewrote together with
its digest.

These recipe revisions are semantic versions. They are not verified
upstream commits or content hashes. A producer must change its recipe
revision when its source, topology, rig or mapping changes. Custom material
IDs identify entries in the caller's store, not immutable material bytes.
Converted ICTF and THRS source manifests remain unverified under #303.
The record exposes that limit instead of inventing a source or license.

The record does not embed canonical geometry, physical properties or a
map. Its mapping fields say where each map comes from: canonical parts
regenerated from `canonical_inputs`, and the maps of
`extensions.humanoid.correspondence`. The dental map stays unsupported.
The game mesh remains a visual derivative. A recipe check does not prove
that an externally edited asset still matches its recipe. The sealed
geometry digest checks the loaded geometry.

## Independent canonical snapshots

`tools/humanoid_fidelity.mojo` packages explicit canonical part meshes and
properties supplied by a caller. The native generator is in
[Canonical parts](#canonical-parts). It never derives physical properties from
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

To verify a snapshot file against its SHA-256, run this command from the
repository root:

```sh
mojo run -I . tools/humanoid_fidelity.mojo canonical.json --sha256 DIGEST
```

The command does not change the file. It prints the same text and exits
with the same status as the Python tool that it replaces.

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

## Canonical parts

`canonical_body(spec)` generates 28 canonical parts from the library's own
fields. It reads no visual, widened, decimated, skinned or baked mesh. The
parts partition the sampled body, so their sum is the whole body.

```mojo
from extensions.humanoid.canonical import (
    BONE_TISSUE,
    RIGHT_THIGH_REGION,
    canonical_body,
    canonical_record,
    part_index,
)

var body = canonical_body(person)
var thigh = body.parts[part_index(RIGHT_THIGH_REGION, BONE_TISSUE)]
var record = canonical_record(body)
```

Each part has a region, a tissue label, a mesh in meters and its sampled
properties. The properties are volume, mass, center of mass and all six
tensor entries about the center. `body.whole` holds the whole-body
properties. Coordinates use the pelvis frame: right-handed, +y up, +x
body-right and +z anterior.

### Regions

`BodyRegion` names fourteen regions. A grid point belongs to one region
under this rule:

| Region | Rule |
|---|---|
| Hand | The hand skin is the nearest skin, and the point is past the wrist plane |
| Forearm and upper arm | The arm skin is nearer than the trunk skins; the elbow and wrist planes split it |
| Head and neck | Above the center of C7 |
| Trunk | From the hip centers to C7 |
| Thigh, shank and foot | Horizontal planes through the femoral-condyle midpoint and the lateral malleolus |

The planes are normal to the bone axes in the arm. A named bone belongs to
its anatomical region, wherever its cells lie. For example, the femoral head
is in the thigh.

### Tissue labels

| Label | Volume | Density |
|---|---|---|
| `BONE_TISSUE` | Cells inside a named bone field | The bone family's cortical shell and trabecular fill at apparent density; marrow at the adipose proxy |
| `SOFT_TISSUE` | Other cells inside the skin | `muscle_tissue` wet density for all skin, fat, muscle, organs and airways |

The soft label has no fat, organ or airway partition. It is a proxy, and
the record names it. The skeleton holds 181 named bone fields. The bone
meshes use each field's own marching grid, without display widening.

### Canonical skin

The canonical skin is the union of the body skin field, both hand skin
fields and both eyeballs. It differs from the visual skin in three ways:

- It has no crotch crease. A crease is a display seam, not a tissue boundary.
- It has no leg gap. The game humanoid parts its legs for animation.
- It holds the whole eyeball, which stands a little proud of the scanned lids.

The canonical skull has its orbits carved round each eyeball, with
`ORBIT_CLEARANCE` (1 mm) of space. The library skull keeps shallow orbits,
so its face block reaches into each eyeball by about 6 mm. The eye genes
and the face-shape eye shifts move the carved orbit with the eye.

### Grid and limits

The property grid step is 10 mm by default and 5 mm through 10 mm in all.
The grid is symmetric about the midsagittal plane, so the left and right
limb parts agree. Each grid vertex stands for one cubic cell.

The mesh of a soft part cuts the skin to its region and removes each bone.
Its cut faces lie midway between grid vertices of two regions. A part mesh
encloses its sampled volume to within about 20% at the default step.

These are template estimates. No convergence, anatomical, biomechanical
or clinical validation is claimed.

### Record and invalidation

`canonical_record` writes a versioned record. It holds the complete
canonical inputs, the frame, the units, the grid step and the bone count.
Each part has its tissue rule, mesh digest and properties. The
`parts_digest` is the FNV-1a fingerprint of all parts.

`require_canonical_record(stored, expected)` compares a stored record with
a fresh one. It refuses a missing record, an incomplete record and a change
of schema, revision, spec, step or any value. Store the record under
`CANONICAL_PARTS_KEY`, for example in a bake's node extras. A visual
edit to the bake does not change it.

`require_part_geometry` refuses any mesh that is not the part's own mesh.
A visual, widened, decimated or baked mesh therefore cannot become a mass or
contact geometry.

Change `CANONICAL_PARTS_REVISION` when a region rule, a tissue rule, a
density, the field inventory or the mesher changes. Any change of a field
also changes the part digests.

## Canonical-to-visual maps

Each map is versioned, and each map refuses what its tests do not cover:

| Map | Supported | Refused |
|---|---|---|
| Identity | Shared spec; carved orbits and the canonical skin follow the eyes; per-region tissue clearance | A region whose bones leave the skin; any identity that fails a fit |
| Expression and jaw | `jawOpen` as a fitted hinge of the canonical mandible and lower teeth | Every other expression shape; a weight that drives the jaw into the skull |
| Skin weights | A fixed joint-to-region table and its measured agreement | Weights as a tissue or mass map |
| LOD | The nearest full-mesh vertex of each reduced vertex | A reduced mesh as a mass or contact geometry |
| Dental | Each dentition with itself | `BONES` to `MOUTH`: no tested correspondence |

### Map records and invalidation

`mapping_record` binds a map's values to its inputs. The record names the
map kind and `MAPPING_REVISION`. It names the canonical revision, the
canonical parts digest and the spec fingerprint. It also names the visual
revision and the topology digest of the visual mesh.

`require_mapping` refuses a record when any of these changes. It also
refuses an edited payload. The topology digest covers the vertex count and
every index entry. A pose or a morph does not change it. A decimation, a
reordered triangle or a new vertex does.

Change `MAPPING_REVISION` when a map rule, a tolerance or a table changes.

### Identity map

`identity_fit(body)` measures one canonical body:

| Check | Requirement |
|---|---|
| Tissue clearance | Each bone mesh vertex lies inside the canonical skin, to within `CLEARANCE_TOLERANCE` (0.5 mm) |
| Eye fit | Each eyeball sample lies outside the carved skull and inside the skin |
| `BONES` dental fit | The upper teeth touch the skull, and the lower teeth touch the mandible |

The tolerance allows for the bone marching grid. `require_tissue_clearance`
checks one region. `require_identity_fit` checks every region, the eyes and
the `BONES` teeth. The error names the region, the bone and the distance.

The face-shape modes move the scanned skin but not the skull. A tested
identity therefore either keeps every fit or is refused:

| Spec | Result |
|---|---|
| 1.8288 m male template | Supported |
| 1.2 m female | Supported |
| Every face-shape gene at -1 | Supported |
| Every face-shape gene at +1 | Refused: the teeth lie about 21 mm outside the scanned face |
| Every gene at +1 | Refused: the teeth lie about 24 mm outside the skin |
| Every gene at -1 | Refused: the skull lies about 4 mm outside the skin |
| 2.5 m male | Refused: the skull lies about 10 mm outside the skin |

Each eye fit holds for every tested identity, because the orbit follows the
eye. These checks found two template defects, now fixed. The natal cleft
exposed the coccyx and sacrum. The lower teeth floated about 4 mm above
the mandible, which had no alveolar arch.

### Expression and jaw map

`jaw_coupling(spec)` fits a hinge to the scanned `jawOpen` shape. The fit
takes the scanned teeth that the shape moves: the lower dentition. It finds
the rotation about the x axis in closed form, then the pivot.

On the template the hinge turns about 25 degrees at full weight. Its
residual is about 0.14 mm over about 2,500 scanned vertices.
`canonical_point` moves a canonical mandible point by a weight.
`rest_point` undoes it, and a zero weight moves nothing.

`jaw_fit` measures the moved mandible and lower teeth against the skull.
`require_jaw_fit` refuses a weight that drives either part deeper into the
skull than at rest. The hinge has no temporomandibular translation. On the
template, a weight of 0.5 passes and a weight of 1 is refused.

`require_coupled_shape` refuses every shape except `jawOpen`. Other shapes
move only the visual face, teeth, gums and tongue.

### Skin-weight map

`joint_region` maps each of the nineteen joints to a canonical region. The
hips, spine and chest map to the trunk. The neck and head map to the head and
neck. Each limb joint maps to its limb region, and the toes map to the foot.

`skin_weight_agreement` counts the vertices whose strongest joint names
their canonical region. On a decimated game humanoid, more than 85% of each
skin agrees. The skin weights stay animation weights, not a tissue map.

### LOD map

`lod_map(full, reduced)` maps each reduced vertex to the nearest full-mesh
vertex. A tie keeps the lowest index. `lod_shift` returns the largest
distance. A mesh with distinct vertices maps to itself as the identity.

On a decimated body skin, more than 95% of the reduced vertices keep the
region of their full-mesh vertex. The map is visual only. Mass and contact
geometry come from the canonical parts.

### Geometry correspondence

`region_map(envelope, geometry)` gives each visual vertex its canonical
region and its signed distance to the canonical skin. It never moves a
canonical part.

### Dental map

`Dentition` names `BONES_DENTITION` and `MOUTH_DENTITION`.
`head_dentitions(ALL)` returns both, because `ALL` is an overlay of two
representations. `require_dental_correspondence` refuses every map between
the two.

`dental_payload` keeps the mesh digest of each dentition. On the template
the scanned teeth lie about 22 mm in front of the authored teeth. They also
leave the canonical skin by about 12 mm. `require_dental_fit` therefore
refuses the `MOUTH` teeth.

## Acceptance boundary for #297

| Requirement | Implemented boundary | Remaining work |
|---|---|---|
| Separate visual and engineering capabilities | Typed native gate; game and bake records fail closed | A validated engineering coupling could add a capability only with independent evidence |
| Retain canonical SI geometry, labels and properties | Generated versioned part meshes, two tissue labels and properties for all 28 parts and the whole body; records independent of widening, decimation and bakes | None for #297 |
| Identity, jaw, weights and LOD mappings | Versioned map records with source, spec and topology invalidation; identity fit, jaw hinge, joint table and LOD map; two dental identities | None for #297. A tested BONES-to-MOUTH correspondence does not exist, so that map stays refused |
| Bake provenance and stale-spec checks | Game roots and example scene extras retain exact spec/options/frame recipes, an explicit transform and spec, settings and recipe fingerprints; sealed bakes retain a digest of the loaded geometry; loaded bakes are refused when stale, edited or unsealed | None for #297. Pin and verify converted source/model inputs and license manifests under #303 |
| Frames, full tensors and reference points | Tested offline proper-rotation and parallel-axis adapter; native parts in the pelvis frame | None for #297 |
| Round trips and extreme identities | Hinge, LOD, bake and record round trips; extreme identities; eye, dental and clearance fixtures; unsupported paths refused | None for #297 |

No measured anatomical parameter changes for appearance. No biomechanical,
patient-specific or clinical calibration is claimed. Global anatomical and
biomechanical validation is separate work.
