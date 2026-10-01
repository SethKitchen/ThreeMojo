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

## Skin, mass and hair

Head skin mass samples a thin shell of the scanned-and-modeled skin field. The rendered scan also contains mouth and eye sockets. It is not a volume mesh for that mass calculation.

Bone and tissue masses use their own fields or analytic volumes. They are not computed from the decimated game skin. Facial expressions do not recalculate them.

Scalp hair mass uses the authored hair volume and a packing factor. It does not sum the strands of a groom. Changing strand count, style or simulation state is not a mass update.

Hair dynamics are a visual position-constraint model. They do not provide validated human-hair constitutive properties or forces coupled to the body.

## Animation, level of detail and baking

`add_game_humanoid` creates skin and nineteen animation joints. It does not include the anatomical layers. Its joints support animation, without anatomical limits, contact forces or muscle activation.

The game builder does not currently combine the facial morph rig with its skinned body. Its mesh budget is a visual setting. It is not an engineering accuracy setting.

The simplifier changes topology and vertex positions. It has no volume, mass, tissue-boundary or joint-clearance error limit. The game builder restores color and thinness by nearest-vertex transfer. This does not restore anatomical correspondence.

The glTF exporter preserves supported visual attributes and supplied animations. It does not automatically export `thinness`, tissue fields, masses or solver parameters. Node and geometry `user_data` can carry explicit provenance through `extras`. The humanoid builders do not populate that provenance.

The game example reuses an existing bake until the file is deleted. Its filename is not a verified fingerprint of the spec or mesh budget.

## Engineering use

Keep the canonical anatomical inputs separate from visual meshes and baked files. Record the spec, coordinate frame, source versions, units and tissue assumptions. Record every identity transform and mesh operation.

An engineering workflow must validate its own discretization and material model. It must check convergence, boundaries, contact, mass and inertia against the intended use. It must also define any mapping between visual vertices and physical tissues.

The current templates, scans and game assets do not meet these requirements by default. A higher visual quality level does not change that limit.

See [Head](Head), [Genome](Genome), [Game humanoid](Game-humanoid), [Mesh quality](Mesh-quality) and [Segment inertia](Segment-inertia).
