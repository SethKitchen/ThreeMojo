# Pinned representative anatomy pair example

This historical example is pinned to source commit `2c91d60c660d05cf5e0fa093e6774558ba14332f`.
It illustrates the representative report schema and its recorded measurements.
It is not a report of the current checkout.
`test_anatomy_pair_example.py` checks its exact bytes, historical source binding, probe fingerprint and representative counts.

The current full report is `anatomy-template-report.json`.
Its separate binding check requires the current source.
Full pair execution there does not repair the diagnostic geometry findings or complete aggregate/platform qualification.

## Source and scope

- Original implementation base: `720fcce4921fa1d83328c4ddfdb078501a253a74`
- Captured implemented source: `2c91d60c660d05cf5e0fa093e6774558ba14332f`
- Compiler: `Mojo 1.1.0 (8189361e)`
- Build flags: `--Werror --num-threads 1 -I .`
- Source SHA-256: `b3dd9ea15888167980fcff72e43e489d52f1106784c01d52ce9484fb7a36bc4d`
- Probe SHA-256: `752cbe627c526d4e2251d4c933f3eb051281bc5e9be32fd5565b943a56de5d30`
- Report SHA-256: `c4b74bfa37670407512eedeac3601ce1d2fd670771143b78276ecac8add31f39`
- Report: `anatomy-pair-example.json`, schema version 2

The catalog has 134 distinct canonical fields and 8,911 unordered pairs. The default full mode executes every pair. Native batches use the existing guarded sampler. A work-budget failure or timeout fails report generation. No costly pair is silently removed.

The representative run checks 528 lower-limb pairs. These are the 465 existing bone and knee pairs and 63 new tissue pairs. Its inventory explicitly omits 8,383 pairs for this run. Every omitted pair remains executable in full mode. All 28 tissue-class combinations have checked representatives. The report also retains 67 neighboring-spine pairs and 23 endplane checks.

## Focused checks

- Seven native tests passed in two suites under the unchanged five-second runtime gate
- Both native suites and the probe compiled with the pinned compiler and `--Werror`
- Seventeen Python tests passed for accounting, source binding, inventory completeness, batching and strict report protocol
- The import-only adapter passed `mojo doc --Werror`
- The build manifest treats the adapter as a library and copies it into the coverage tree
- Documentation checks passed for the two changed documentation files
- A second report run was byte-identical without rebuilding the probe
- Source, executable and metadata bindings were rechecked after all measurements

The independent controls include exact box intersections, thin-feature misses, narrow interfaces, shared surfaces, edited attachments and internal construction unions. They retain finite-input and pre-iteration work-budget failures. The catalog suite tests both sides and every canonical adapter type.

## Geometry findings

All 36 existing findings match the earlier report exactly. Eleven new representative tissue-pair hits remain unallowlisted. No anatomy was changed. Classifying or repairing these findings remains issue #595.

A sampled volume is an estimate. A signed field witness is not penetration depth or measured clearance. No sampled hit does not prove no overlap. Attachment allowances and biological tolerances remain unknown. No distinct named pair receives a positive-volume exemption.

## Reproduce separately

Keep the pinned example unchanged during ordinary source updates.
The probe fingerprint identifies the original build; another machine or toolchain can produce different binary bytes.
Write a new experiment to a separate output and retain its own source binding.
Checkout the captured source commit to reproduce that revision's measurements.


Run from the repository root with pinned Mojo 1.1.0:

```sh
python3 -m unittest discover -s tools -p 'test_anatomy_validity.py'
python3 -m unittest discover -s tools -p 'test_anatomy_pair_inventory.py'
mojo build --Werror --num-threads 1 -I . tests/test_anatomy_diagnostics.mojo -o .cache/test_anatomy_diagnostics
python3 tools/run_suite.py --seconds 5 --suite tests/test_anatomy_diagnostics.mojo -- .cache/test_anatomy_diagnostics
mojo build --Werror --num-threads 1 -I . tests/test_anatomy_pair_catalog.mojo -o .cache/test_anatomy_pair_catalog
python3 tools/run_suite.py --seconds 5 --suite tests/test_anatomy_pair_catalog.mojo -- .cache/test_anatomy_pair_catalog
python3 tools/anatomy_validity.py --build --pair-scope representative --output .cache/anatomy-pair-example-current.json
```

For full integrated pair evidence, omit `--pair-scope representative`. Regenerate `anatomy-template-report.json` on the final integrated source. This historical example does not establish current coverage or CI status.

Static template evidence does not establish whole-body, dynamic, clinical, constitutive or safety validity.
