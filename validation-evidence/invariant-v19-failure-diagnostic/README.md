# Frozen-v19 cold failure and censored diagnostic evidence

The exact maintained normal-direct admission command failed its original
10-second bound (10.045146466 seconds, exit -9). Normal package and both optimized
cold commands were not run. The single separately authorized diagnostic was
censored after 28 seconds under a 30-second outer collection limit and returned
1. Its collection sequence accepted that nonzero result; it is not an admission,
timing-cap or readiness pass. The original 10-second qualification limit remains.

The diagnostic contains 889 raw code entries and 309 module bindings. Raw object
identities, binary pstats and the 14-second faulthandler stack are preserved.
One full-audit verify invocation and no operation finish entry are observed in
the censored profile. End-to-end completion, full finalizer behavior and complete
operation cost are not established. The prospective stage label is retained
unchanged and does not override the actual diagnostic-deadline result.

Every original file in both phase directories is preserved, including the
existing numeric RAW-CALL-EDGE-ANALYSIS.txt, explicitly identified as derived
analysis. Actual commands/configs, supervisor output, profiler source/payload,
all 29 frozen source-manifest paths, full source seal and SDK receipts are kept.
The profiler path is historically recorded; this packet seals its present source
bytes rather than inventing a historical source-content hash. The supervisor is
independently bound by the original WINDOW-START hash.

Readable receipt/config files retain exact bytes. Remaining original members,
including pstats and RAW-PROFILE.json, are encoded as per-member base64 in one
JSON container, gzip-compressed with mtime=0 and base64-encoded for transport.
INNER-MEMBER-MANIFEST.json records each original path, byte length, SHA-256 and
storage. PUBLISHABLE-EVIDENCE-MANIFEST.json seals transport payloads and does not
recursively list itself. Derived summary and command bindings are separate.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies bytes before writing and rejects traversal, duplicate
members, symlink payloads and existing output. It never executes decoded content,
imports candidate modules, or loads/unmarshals pstats. Original absolute paths
are provenance only. No candidate modification, rerun, upload or new test/native
execution occurs. This is a durable failure/diagnostic record, with no acceptance
or readiness claim.
