# Frozen-v18 failure and diagnostic evidence

The real normal-direct admission command failed its original 10-second bound
(10.033769374 seconds, exit -9). Normal package and both optimized cold commands
were not run. The separate diagnostic was intentionally interrupted after eight
seconds under a 10-second outer limit and returned 1. Its completed collection
sequence is not an admission or timing-cap pass. Raw profile identities, binary
pstats and the four-second faulthandler stack are preserved. The partial profile
observes one full-audit verify invocation and no operation finish entry; it does
not establish successful gate completion or uncensored finalizer behavior.

The synthetic normal run executed eight methods: seven passed and the new
supplied-comment positive fixture raised the recorded error. Optimized synthetic
controls were not run. No later fixture correction replaces those failure bytes.

Every original file in all three phase directories is preserved, together with
actual configs, supervisor output, profiler source/payload and exact frozen
18-path source bytes plus their original source manifest and full source seal.
The SDK identity helper is included. All original source/SDK receipt hashes are
checked. The profiler's path is recorded by the original command; its source
digest is newly sealed by this packet rather than a historical stage hash.

Readable receipt/config files retain their exact bytes. Remaining originals,
including binary pstats and RAW-PROFILE.json, are losslessly encoded as per-member
base64 inside one JSON container, compressed with gzip mtime=0, then base64-encoded.
INNER-MEMBER-MANIFEST.json records every member's path, length, SHA-256 and storage.
The outer PUBLISHABLE-EVIDENCE-MANIFEST.json seals all transport payloads and does
not recursively list itself. Derived summary and command bindings are separate.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies all bytes before writing and rejects traversal, duplicates,
symlinks and existing output. It never executes decoded content, imports candidate
modules or loads/unmarshals pstats. Original absolute paths are provenance only.
No native executable, internal review, private design note, v19 source or v19
qualification is included. This packet performs no rerun and makes no pass claim.
