# Frozen-v17 center observer evidence

Fresh reconstructed observer execution completed 202/202 stages: four builds,
196 native case executions and two comparisons. All 49 before/after pairs match
in each of O3 and O0 (98 total). Original caps: 180-second builds, 5-second tests,
15-second outer case stages, 30-second comparisons and a 1200-second window.

The actual/ directory contains every original stage START, RESULT and merged
stdout/stderr log, final RESULT, SDK before/after receipts, source seal, process
receipts and both PAIRS files. These bytes are unchanged. Separate stdout and
stderr streams were never recorded. The four executable payloads are omitted;
their original post-run hashes remain in PAIRS and EXCLUDED-EXECUTABLES.json.

The reproduce/ directory contains exact source seals, original commands/config,
observer driver, cases, comparator, contract, preparation inputs, before/after
center-lane source and the executed Python support files. Original paths are
retained. Full SDK and unchanged repository source are not distributed here.
Preparation files still contain their original prospective status wording.

VALIDATION-SUMMARY.json and COMMAND-RECEIPT-SEAL.json are explicitly derived
documents, separate from actual execution receipts. The manifest lists payload
paths, byte counts and SHA-256 values; it excludes its own recursive hash.

This is fresh frozen-v17 exported-observation evidence. It does not recover or
relabel lost receipts, establish an exhaustive internal traversal trace, prove
old full-search count-refusal reachability, or qualify candidate-v18 or any
other outstanding validation stage. No native code is run by the packet builder.
