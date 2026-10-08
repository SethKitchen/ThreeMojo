# Anatomy validity

The canonical anatomy produces template estimates. No use case has an engineering-validation or clinical-certification label.

The bounded report covers static geometry, mass, center of mass and the full inertia tensor of one canonical lower limb. It records numerical controls, sampling sensitivity, overlap witnesses, input provenance and unsupported uses. Game and fantasy use remains permitted.

The default geometry pass checks all 8,911 distinct pairs among 134 named lower-limb fields. These include bones, knee tissues, muscles and tendons, foot ligaments, vessels, nerves and lymphatics. It does not check whole-body geometry, dynamic contact or visual/rig/bake correspondence. Separate dermis/fat interfaces and bone pore-fluid and pore-marrow mass remain unresolved. These limits remain explicit in every report.

## Generate a report

Use the pinned Mojo 1.1.0 compiler. Run this command from the repository root:

```sh
python3 tools/anatomy_validity.py --build --output anatomy-report.json
```

The default spec is a 1.8288 m male, untoned, right-side template. The three maximum grid widths are 20, 10 and 5 mm. Each probe execution has a five-second limit. The probe has no GPU dependency.

Use `--sex female`, `--side left`, `--athleticism toned` or `--stature-m 1.63` to select another canonical template. Use `--steps-mm 16 8 4` to select three other grid widths. Each width must be finite and between 2 and 20 mm. Supply three through ten distinct widths. A tiny width fails before integer conversion or iteration.

Each grid permits at most two million cells. Pair batches also check their complete work request before sampling. A budget failure or timeout stops report generation. It never removes a costly pair from a successful report.

Use `--pair-scope representative` for a smaller diagnostic run. It retains the complete 8,911-pair inventory. Each unselected pair has an explicit omission reason. Selection uses the largest intersecting box in each tissue-class and leg/foot combination.

This rule is reproducible. It does not identify the worst anatomical overlap. The default `--pair-scope full` executes every catalog pair.

Omit `--build` to reuse the probe. Its sidecar must match the source digest and binary digest. Rebuild after a source change. Reports record both digests, the exact compiler version and `--Werror`.

The source digest includes the import closure of `tools/anatomy_probe.mojo`, which holds every Mojo file the probe build can read. Imports resolve as `tools/affected.py` resolves them to select test suites: a module beside the importer first, then the repository root. The digest also includes the report writer and provenance inventory. A change to a Mojo file outside the closure does not require a rebuild, so unrelated pull requests do not invalidate each other's reports.

The committed report is a reference for its recorded source revision. It does not describe a later combined revision. Probe reuse rejects changed source until `--build` regenerates the evidence. Regenerate the report after the final integration batch.

The report uses an initial source and inventory snapshot. It rechecks source, probe and metadata before return. An observed change fails the report. These checks do not provide an atomic filesystem transaction.

`--use game-fantasy` permits the labeled template estimate. Engineering, whole-body, dynamic/constitutive, patient-specific and clinical/safety requests still produce an evidence report. They return exit code 2 because their use gate is unsupported. A failed calculation returns exit code 1. A supported labeled estimate returns 0.

## Read the report

The JSON schema version is 2. Every quantity has a unit in its key or its stated frame. Pair IDs use a canonical group plus sorted component IDs. They remain stable when pair order changes. Reports retain source-file, report-logic, inventory and executable hashes.

- `spec` identifies the input template. The report uses the template genome
- `build_provenance` identifies the exact source and executable
- `controls` records the independent analytic and input-guard checks
- `segments` contains the three-step estimates and differences for each cut
- `composition` contains only the selected side's three disjoint cuts
- `diagnostics` contains sampled overlaps and spine endplane checks
- `pair_inventory` lists all components, all unordered pairs, class counts and execution status
- `diagnostic_limits` names regions and uses not checked
- `accounting` states assignment precedence and missing contributions
- `provenance_inventory` distinguishes cited inputs from authored parameters
- `gate` states the supported label and the missing validation evidence

The leg frame origin is the tibiofemoral joint line. Plus x is body-right. Plus y is proximal. Plus z is anterior. Spine diagnostics use the midpoint of the two hip joint centers as their origin. Each diagnostic record names its frame.

The pair inventory also lists the 67 checked neighboring-spine pairs and 23 endplane checks outside the lower-limb catalog. No cross-frame pair is inferred.

Inertia entries are `xx`, `yy`, `zz`, `xy`, `xz` and `yz`, about the center of mass. Off-diagonal entries are negative products of inertia. The six-entry representation is symmetric by construction.

## Numerical evidence

The independent controls use a uniform rectangular solid and two unequal point masses. Their expected values come from closed-form integrals, not the anatomical template. The solid has an unaligned cut at each of three grid widths. Tests compare its mass, center and all six tensor entries before and after composition. Separate controls test a rigid rotation, a translation and all parallel-axis tensor entries.

The uniform-solid absolute tolerances are 2e-8 kg for mass, 2e-8 m for center and 1e-10 kg m² for inertia. The point-mass tensor tolerance is 1e-8 kg m². The rigid-center tolerance is 2e-8 m. The overlap-box volume tolerance is 1e-11 m³.

Thin-layer and narrow-interface controls use 1e-12 m³. These are numerical test tolerances. They are not physical acceptance thresholds.

The report checks all principal minors of a scaled symmetric tensor for positive semidefiniteness. It also checks all principal minors of the central second-moment matrix, `C = trace(I)/2 Identity - I`. This tests the principal-moment triangle inequalities in any frame. Coordinate-diagonal triangle checks alone are insufficient. The relative roundoff tolerance is 5e-6.

Each refinement comparison records mass differences, the center displacement vector and norm, and all tensor differences. The tensor norm includes both copies of each off-diagonal entry. These are observed sampling sensitivities. They are not proven error bounds. The report does not assume a convergence order or transfer a CFD grid-convergence index to this sampler. Thin regions and density discontinuities can produce nonmonotone changes.

## Region accounting

Each accepted cell receives one density assignment. The final cell on each axis stops at the exact integration plane. Cuboid self-inertia is included. This avoids the gaps or overlaps from rounded counts of full-sized cells.

The assignment order is dermis, bone or marrow, then soft tissue. Bone selection uses femur, tibia, fibula, patella and the named foot-bone order. Cortical and trabecular assignments use apparent bone density. Marrow uses the named fat proxy before any overlapping muscle or tendon.

Soft tissue uses the first leg muscle or tendon, then the first foot muscle or tendon, then the unresolved fat proxy.

The report stores volume and mass for all seven exclusive assignments. Region mass must sum to segment mass. Region volume must not exceed its integration box. Composition rejects duplicate segments, missing segments, mismatched steps, different envelope bounds, gaps and overlapping cut planes.

Apparent bone density applies porosity once. The integral does not add separate fluid or marrow mass in bone pores. Knee tissues, foot ligaments, vessels, lymphatics and nerves have no separate density assignment. A higher-priority region can replace them; otherwise they use the fat proxy. These approximations have no quantified uncertainty in this model.

Do not add individual bone mass, soft-part mass, a second skin mass or `SweepField.volume()` totals to the report. Construction solids can overlap. Sweep volumes also omit subtraction of cuts. The selected-side total omits the other limb, pelvis, trunk, head, arms and hands. It is not whole-body mass.

## Geometry diagnostics

The default probe retains all 435 distinct pairs among 30 lower-limb bones. These are six leg/leg pairs, 104 leg/foot pairs and 325 foot/foot pairs. It checks 30 knee pairs: 20 leg-bone/tissue pairs and ten tissue/tissue pairs.

Spine checks include C2 through C7, T1 through L5, the C7/T1 transition and the neighboring discs. The spine pass returns 67 pair records and 23 endplane records. The L5 lower disc endpoint uses the authored sacral support plane. It does not assert a flat sacral-body surface.

A positive gap between conservative bounding boxes is a clearance lower bound. A negative field witness identifies sampled common interior of the component envelopes. Bone fields are outer envelopes; a witness does not identify cortical, trabecular or marrow occupancy. Field values need not be exact distances. They are not penetration depth or physical clearance.

No sampled hit does not prove no overlap. A field witness is null when no cell was sampled. An analytic thin-layer control demonstrates a missed interior with loose bounds. Tight bounds recover its known volume. A separate control checks a narrow interface and an edited attachment that creates positive overlap.

The catalog contains 30 bones, five knee tissues, 49 muscles or tendons, ten foot ligaments, 19 vessels, 13 nerves and eight lymphatic fields. Every distinct combination is executable. This includes same-class, cross-class and leg/foot pairs. The 465 existing bone and knee diagnostics retain their IDs. Another 8,446 pairs use the same `diagnose_pair` sampler through a canonical-field adapter.

Component IDs contain the region, part family and declared typed part value. Aliases add no duplicate entry.

These IDs are independent of the display label and catalog order. A change to a declared part value changes that component identity.

Each report also records the source digest. New pair IDs sort these component IDs.

Foot fields translate by the assembled ankle center. Local long bones use their assembly origins. Other leg fields already use the knee origin. No display-radius helper is used.

The machine-readable inventory marks each pair as checked or intentionally omitted. Class totals include both statuses. A representative run never claims all catalog pairs were checked. Unsupported domains are separate entries and never count as completed checks. These domains include unresolved material interfaces, other body regions, nonneighbor spine pairs and dynamic or visual mappings.

The provenance inventory has an explicit intentional-overlap allowlist. It covers construction primitives inside one named field, contained anatomy inside the skin domain, and the leg/foot envelope union. It permits a shared body/disc endplane surface within 1e-6 m. It permits no positive-volume body/disc overlap. Distinct named fields are not exempted by the construction-union rule.

No positive-volume attachment allowance is currently justified for catalog pairs. A shared tendon path, vascular junction or apparent anatomical attachment remains a finding. Its permitted overlap volume is unknown. The skin-domain rule only prevents duplicate domain accounting; it does not validate containment or dermis clearance.

Finite positive dimensions can still be geometrically incompatible. A reversed disc gap, endplane mismatch or unexpected overlap is evidence to inspect. It does not authorize automatic changes to measured or cited inputs. Use `diagnose_pair` with edited canonical fields for additional pairs. The caller must supply conservative bounds in one frame.

## Provenance and intended use

`docs/validation/anatomy-provenance.json` inventories the active parameter groups. It records units, source files, research citations, software ranges and explicit unknowns. Null uncertainty means unknown. It does not mean zero uncertainty.

Long-bone templates invert historical stature regressions. An inverse regression is not a calibrated prediction of bone length from stature. The source populations and unknown calibration ranges remain visible. Most shape ratios, landmarks, skin envelopes, blends and density proxies are authored.

Before a use case can be called engineering-validated, define its task, population, quantities of interest and acceptance thresholds. Supply independent matched reference measurements with their uncertainty. Compare the model against those thresholds and quantify relevant numerical and model uncertainty. This deliverable supplies no such task-specific reference set. Its gate remains unsupported even when every numerical test passes.

Tissue elastic metadata does not implement a constitutive law, activation or contact. Static packing and posed graphics do not establish dynamic or load-bearing behavior. No generic biomedical, clinical or safety certification is claimed.

Canonical-to-visual, rig and bake mapping remains [issue #297](https://github.com/SethKitchen/ThreeMojo/issues/297). This report does not validate a posed, simplified or textured mesh.

## Tracked limits

[Issue #595](https://github.com/SethKitchen/ThreeMojo/issues/595) tracks classification and repair of current sampled-overlap findings. The default 5 mm template reports 21 bone-pair hits, 14 knee-pair hits and one full C2/C3 field hit. These 36 findings remain unallowlisted. All 23 body/disc endplane checks pass. A signed field witness is not a measured penetration depth. A sampled volume is not an exact overlap volume.

[Issue #596](https://github.com/SethKitchen/ThreeMojo/issues/596) adds the complete selected-side pair inventory and missing tissue-class execution. The source-bound `docs/validation/anatomy-pair-example.json` uses the explicit representative scope. It is focused evidence for the implementation. The full integrated report and aggregate qualification remain separate checks. Neither pair coverage nor passing analytic controls grants a clearance or certification claim.

## References

- [MIT inertia-tensor lecture](https://ocw.mit.edu/courses/16-07-dynamics-fall-2009/resources/mit16_07f09_lec26/) defines the independent tensor and parallel-axis controls
- [NASA grid-refinement guidance](https://www.grc.nasa.gov/www/wind/valid/tutorial/spatconv.html) explains why numerical refinement evidence needs explicit limits
- [FDA computational-model credibility guidance](https://www.fda.gov/regulatory-information/search-fda-guidance-documents/assessing-credibility-computational-modeling-and-simulation-medical-device-submissions) distinguishes context-specific credibility evidence. This report claims no FDA assessment or conformance
