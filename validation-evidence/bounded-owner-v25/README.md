# V25 focused and bounded-owner control evidence

Both actual phases passed in normal and optimized modes: four focused methods
per mode (eight executions), then the existing thirty-method suite per mode
(sixty executions). All sixty-eight executions had zero skips. The four focused
methods repeat within the thirty-method suite; this is thirty unique methods,
not sixty-eight distinct tests. All four stage exits were zero without timeout.
Source/SDK receipts were unchanged and no owned descendants remained.

The unchanged 1,800-second stage and 10,800-second phase-window limits apply.
This packet qualifies only these two executed phases. It does not claim a
dynamic per-site observation sweep, the full Python matrix, native coverage,
exact-head hosted CI or overall completion.

The earlier v24 run remains FAILED in the separate packet referenced by path
and manifest hash in VALIDATION-SUMMARY.json. None of that earlier packet's raw
failure members is included here, and no historical error is relabeled as a
v25 pass. The sealed v25 source differs from v24 only in the test file.

Every file from both original thirteen-file phase directories is preserved,
including merged test logs, START/RESULT, process histories, source and SDK
seals. Exact actual configs and supervisor consoles, bound supervisor source,
all thirty-one frozen manifest source paths and SDK identity helper are included.
The exact executed test is readable. The source-only manifest remains unchanged.
Supervisor console records precede the later test-count annotations retained
in original stage/final JSON. Nothing absent is reconstructed.

Readable members retain exact bytes. Other originals use per-member base64 in
one JSON container, gzip-compressed with mtime=0 and base64-encoded for transport.
INNER-MEMBER-MANIFEST.json records each original path, size, hash and storage.
PUBLISHABLE-EVIDENCE-MANIFEST.json seals payloads, excluding itself. Summary and
command-binding documents are derived and separate from original receipts.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies bytes before writing and rejects unsafe paths, duplicate
members, symlink payloads and existing output. It never executes decoded source.
Full unchanged repository and SDK binary images are not distributed. Packaging
performs no candidate edit, test/native rerun or upload. No private notes or
unexecuted proposal sources are included.
