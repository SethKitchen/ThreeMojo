# Complete v21 profile: diagnostic evidence only

The single authorized profile completed with exit 0 under 58-second inner and
60-second outer bounds. The profiler reports 32.867349857 seconds; the supervisor
records 33.083843828 seconds for its stage. These are different measured windows.
The original maintained 10-second cold gate remains failed. This diagnostic
completion does not change that limit or establish qualification/readiness.

All twelve original phase files are preserved, including 916 raw code entries,
317 module bindings, original object identities and binary pstats. One full-audit
verify and one operation finish invocation are observed. The original log keeps
the scheduled 29-second faulthandler stack; its Timeout header is not a stage
watchdog failure. The profiler template's Partial wording is unchanged, while
its actual status is completed. Raw timings include profiling overhead.

The original launcher read, hash-checked and compiled the same profiler bytes.
That exact source, underlying command, config, supervisor, source/SDK receipts,
29 frozen manifest source paths and referenced support files are included.
The prior three-phase packet remains unchanged; its exact manifest and selected
original cold-gate context are included without importing its entire contents.

Readable inputs retain exact bytes. Remaining originals, including pstats, are
base64-encoded per member in a JSON container, gzip-compressed with mtime=0,
then base64-encoded for transport. INNER-MEMBER-MANIFEST.json records each original
path, length, SHA-256 and storage. PUBLISHABLE-EVIDENCE-MANIFEST.json seals the
transport payloads, excluding itself. Summary and command bindings are derived.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies all bytes before writing and rejects unsafe paths,
duplicates, symlinks and existing output. It never executes candidate/profiler
content or loads/unmarshals pstats. Full unchanged repository and SDK executables
are not included. No candidate edit, test/native rerun or upload is performed.
