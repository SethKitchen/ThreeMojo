# V21 classifier controls, cold failure and plain diagnostic

Normal and optimized focused classifier controls each passed 291 differential
cases, 941 always-active checks and six designated measured-negative Path-elision
checks. The exact executed harness is SHA-256 checked by each original command.
These are classifier-only controls using synthetic frame records with real
canonical code/global identities, not real operation-lifecycle qualification.

The original maintained 10-second normal-direct cold gate failed at
10.061513043 seconds with exit -9. The remaining normal-package and two optimized
commands were not run. A separately authorized plain diagnostic used the exact
same argv, body, working directory and frozen source, without profiling, and
completed at 12.531899081 seconds with exit 0 under a 30-second outer cap.
That completion exceeds the original ten-second bound and is not a cap pass,
readiness finding or broader qualification result.

Every file in the three terminal evidence directories is preserved, including
all START/RESULT/logs, empty output, process receipts, full control reports,
source and before/after SDK seals. Exact configs and supervisor output, the
checked harness, all 29 frozen v21 manifest source paths, the v19 baseline seal
and report-bound baseline core bytes are included. The unexecuted rejected
harness revision and internal reviews/notes are omitted.

Readable files retain exact bytes. Remaining originals are represented by
per-member base64 in one JSON container, gzip-compressed with mtime=0 and then
base64-encoded. INNER-MEMBER-MANIFEST.json records every original path, length,
SHA-256 and storage. PUBLISHABLE-EVIDENCE-MANIFEST.json seals all transport
payloads, excluding itself. Summary and command binding documents are derived.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies all bytes before writing and rejects unsafe paths,
duplicates, symlink payloads and existing output. It never executes decoded
source or harness content. Original absolute paths are provenance only. No
candidate changes, tests, native runs or uploads are performed by packaging.
