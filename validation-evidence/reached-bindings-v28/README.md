# V28 focused reached-binding sweep evidence

PASSED: one selected method ran in each mode, two executions with zero skips.
Each mode emitted four owner reports: invariant, winner, Map and Rtree. Their
union contains all108 consumed-read IDs of this sweep with no residual. The
per-owner residuals remain explicit. This does not establish general source,
branch, condition or native coverage, nor results for every possible input.

Each Map report records62 pending streams matched by actual queued publish
replay and8 active streams matched in live original frames. Each Rtree report
records1 active live-frame stream. Both modes preserve the complete per-path
and per-site reports. These are two executions of one method, not eight tests.
The other41 methods in the source file were not selected in this phase.

Stage times were69.641646264 and70.298505679 seconds, exits zero and no timeout.
The original1,800-second stage and10,800-second window caps remain unchanged.
Source/SDK receipts were unchanged and no owned descendants remained. The v27
failure remains separate and failed; its manifest is referenced by path/hash.
No full Python matrix, native coverage, hosted CI or overall pass is claimed.

Both complete1,827,235-byte merged logs are preserved byte-for-byte, including
all four reports, warnings, unittest summaries and the original ok suffix on
the Rtree report line. No original log or JSON report has been normalized.
All thirteen phase files, actual config and supervisor console, exact test,
all31 frozen manifest source paths, full source/SDK seals, supervisor and SDK
support source are retained. The original source-only manifest is unchanged.

Readable originals retain exact bytes. Archived originals, including both
full UTF-8 logs, use per-member base64 inside a JSON container, deterministic
gzip with mtime=0, then base64 transport. The inner manifest records original
paths, byte lengths, hashes and storage. The outer manifest seals payloads
and excludes itself. Summary and command binding are explicitly derived.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies bytes before writing; it rejects unsafe paths, duplicates,
symlink payloads and existing output. It never executes decoded content.
The full unchanged repository and SDK executable image are not distributed.
Packaging performs no candidate edit, test/native execution or upload. Private
review/design notes and unexecuted proposals are excluded.
