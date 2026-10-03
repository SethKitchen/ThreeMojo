# Anatomy validity

The canonical anatomy produces template estimates. No use case has an engineering-validation or clinical-certification label.

The bounded report covers static geometry, mass, center of mass and the full inertia tensor of one canonical lower limb. It records numerical controls, sampling sensitivity, overlap witnesses, input provenance and unsupported uses. Game and fantasy use remains permitted.

The default geometry pass does not check muscle-to-muscle or muscle-to-bone pairs, foot ligaments, or vascular, nerve and lymphatic pairs. It does not check whole-body geometry, dynamic contact or visual/rig/bake correspondence. Bone pore-fluid and pore-marrow mass is missing. These limits remain explicit in every report.

## Generate a report

Use the pinned Mojo 1.1.0 compiler. Run this command from the repository root:

```sh
python3 tools/anatomy_validity.py --build --output anatomy-report.json
```

The default spec is a 1.8288 m male, untoned, right-side template. The three maximum grid widths are 20, 10 and 5 mm. Each probe execution has a five-second limit. The probe has no GPU dependency.

Use `--sex female`, `--side left`, `--athleticism toned` or `--stature-m 1.63` to select another canonical template. Use `--steps-mm 16 8 4` to select three other grid widths. Each width must be finite and between 2 and 20 mm. Supply three through ten distinct widths. A tiny width fails before integer conversion or iteration. Each grid permits at most two million cells.

Omit `--build` to reuse the probe. Its sidecar must match the source digest and binary digest. Rebuild after a source change. Reports record both digests, the exact compiler version and `--Werror`.

`--use game-fantasy` permits the labeled template estimate. Engineering, whole-body, dynamic/constitutive, patient-specific and clinical/safety requests still produce an evidence report. They return exit code 2 because their use gate is unsupported. A failed calculation returns exit code 1. A supported labeled estimate returns 0.

## Read the report

The JSON schema version is 1. Every quantity has a unit in its key or its stated frame.

- `spec` identifies the input template. The report uses the template genome
- `build_provenance` identifies the exact source and executable
- `controls` records the independent analytic and input-guard checks
- `segments` contains the three-step estimates and differences for each cut
- `composition` contains only the selected side's three disjoint cuts
- `diagnostics` contains sampled overlaps and spine endplane checks
- `diagnostic_limits` names regions and uses not checked
- `accounting` states assignment precedence and missing contributions
- `provenance_inventory` distinguishes cited inputs from authored parameters
- `gate` states the supported label and the missing validation evidence

The leg frame origin is the tibiofemoral joint line. Plus x is body-right. Plus y is proximal. Plus z is anterior. Inertia entries are `xx`, `yy`, `zz`, `xy`, `xz` and `yz`, about the center of mass. Off-diagonal entries are negative products of inertia. The six-entry representation is symmetric by construction.

## Numerical evidence

The independent controls use a uniform rectangular solid and two unequal point masses. Their expected values come from closed-form integrals, not the anatomical template. The solid has an unaligned cut at each of three grid widths. Tests compare its mass, center and all six tensor entries before and after composition. Separate controls test a rigid rotation, a translation and all parallel-axis tensor entries.

The uniform-solid absolute tolerances are 2e-8 kg for mass, 2e-8 m for center and 1e-10 kg m² for inertia. The point-mass tensor tolerance is 1e-8 kg m². The rigid-center tolerance is 2e-8 m. The overlap-box volume tolerance is 1e-11 m³. These are numerical test tolerances. They are not physical acceptance thresholds.

The report checks all principal minors of a scaled symmetric tensor for positive semidefiniteness. It also checks the inertia triangle inequalities. The relative roundoff tolerance is 5e-6.

Each refinement comparison records mass differences, the center displacement vector and norm, and all tensor differences. The tensor norm includes both copies of each off-diagonal entry. These are observed sampling sensitivities. They are not proven error bounds. The report does not assume a convergence order or transfer a CFD grid-convergence index to this sampler. Thin regions and density discontinuities can produce nonmonotone changes.

## Region accounting

Each accepted cell receives one density assignment. The final cell on each axis stops at the exact integration plane. Cuboid self-inertia is included. This avoids the gaps or overlaps from rounded counts of full-sized cells.

The assignment order is dermis, bone or marrow, then soft tissue. Bone selection uses femur, tibia, fibula, patella and the named foot-bone order. Cortical and trabecular assignments use apparent bone density. Marrow uses the named fat proxy before any overlapping muscle or tendon. Soft tissue uses the first leg muscle or tendon, then the first foot muscle or tendon, then the unresolved fat proxy.

The report stores volume and mass for all seven exclusive assignments. Region mass must sum to segment mass. Region volume must not exceed its integration box. Composition rejects duplicate segments, missing segments, mismatched steps, different envelope bounds, gaps and overlapping cut planes.

Apparent bone density applies porosity once. The integral does not add separate fluid or marrow mass in bone pores. Knee tissues, foot ligaments, vessels, lymphatics and nerves have no separate density assignment. A higher-priority region can replace them; otherwise they use the fat proxy. These approximations have no quantified uncertainty in this model.

Do not add individual bone mass, soft-part mass, a second skin mass or `SweepField.volume()` totals to the report. Construction solids can overlap. Sweep volumes also omit subtraction of cuts. The selected-side total omits the other limb, pelvis, trunk, head, arms and hands. It is not whole-body mass.

## Geometry diagnostics

The default probe compares all 30 lower-limb bones in pairs. It compares the four leg bones with the five knee tissue fields and compares those tissues with one another. Spine checks include C2 through C7, T1 through L5, the C7/T1 transition and the neighboring discs. The L5 lower disc endpoint uses the authored sacral support plane. It does not assert a flat sacral-body surface.

A positive gap between conservative bounding boxes is a clearance lower bound. A negative field witness identifies sampled common interior. Field values need not be exact distances. They are not penetration depth or physical clearance. No sampled hit does not prove no overlap. The report names omitted muscle, foot-ligament, vessel, nerve and lymphatic pair checks.

The provenance inventory has an explicit intentional-overlap allowlist. It covers construction primitives inside one named field, contained anatomy inside the skin domain, and the leg/foot envelope union. It permits a shared body/disc endplane surface within 1e-6 m. It permits no positive-volume body/disc overlap. Distinct bones are not exempted by the construction-union rule.

Finite positive dimensions can still be geometrically incompatible. A reversed disc gap, endplane mismatch or unexpected overlap is evidence to inspect. It does not authorize automatic changes to measured or cited inputs. Use `diagnose_pair` with edited canonical fields for additional pairs. The caller must supply conservative bounds in one frame.

## Provenance and intended use

`docs/validation/anatomy-provenance.json` inventories the active parameter groups. It records units, source files, research citations, software ranges and explicit unknowns. Null uncertainty means unknown. It does not mean zero uncertainty.

Long-bone templates invert historical stature regressions. An inverse regression is not a calibrated prediction of bone length from stature. The source populations and unknown calibration ranges remain visible. Most shape ratios, landmarks, skin envelopes, blends and density proxies are authored.

Before a use case can be called engineering-validated, define its task, population, quantities of interest and acceptance thresholds. Supply independent matched reference measurements with their uncertainty. Compare the model against those thresholds and quantify relevant numerical and model uncertainty. This deliverable supplies no such task-specific reference set. Its gate remains unsupported even when every numerical test passes.

Tissue elastic metadata does not implement a constitutive law, activation or contact. Static packing and posed graphics do not establish dynamic or load-bearing behavior. No generic biomedical, clinical or safety certification is claimed.

Canonical-to-visual, rig and bake mapping remains [issue #297](https://github.com/SethKitchen/ThreeMojo/issues/297). This report does not validate a posed, simplified or textured mesh.

## References

- [MIT inertia-tensor lecture](https://ocw.mit.edu/courses/16-07-dynamics-fall-2009/resources/mit16_07f09_lec26/) defines the independent tensor and parallel-axis controls
- [NASA grid-refinement guidance](https://www.grc.nasa.gov/www/wind/valid/tutorial/spatconv.html) explains why numerical refinement evidence needs explicit limits
- [FDA computational-model credibility guidance](https://www.fda.gov/regulatory-information/search-fda-guidance-documents/assessing-credibility-computational-modeling-and-simulation-medical-device-submissions) distinguishes context-specific credibility evidence. This report claims no FDA assessment or conformance
