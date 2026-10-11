# V34 post-diagnostic repair focus

This packet reports the actual terminal outcomes of twelve focused stages with
forty planned method executions. VALIDATION-SUMMARY.json distinguishes recorded
passing, failing, interrupted and unrun evidence. Even if every selected method
passes, this is source-scoped diagnostic evidence. Qualification remains false;
full modules, the full matrix, native/coverage and hosted CI are outside scope.
The configured two-probe timeout-policy approval remains a separate decision.

All actual per-stage START/RESULT/full raw UTF-8 logs, terminal phase files and
complete actual console are preserved without truncation. Exact source/SDK,
commands and original 1800/10800-second caps remain bound. Both baseline source
seals, reviewed installed/config audit, exact four-path and cumulative eleven-path
manifests, before/revised sources and related sealed helpers are included.
Earlier v28 failed receipts remain separate provenance and are not relabeled.

Method totals are distinct from failure records and subtests. Missing totals
or unrun stages are disclosed. The supervisor's source/SDK/cleanup receipts are
identified as that boundary; the packet builder neither executes code nor scans
candidate or SDK trees. No live receipt is packaged as completed evidence.

Original members carry path, size, hash and storage. Archived originals use
base64 JSON, deterministic gzip mtime=0, then UTF-8 base64. Outer manifest seals
all payloads except itself. Summary and command index are derived metadata.

Verify: python -B decode_verify.py
Decode: python -B decode_verify.py --output /path/to/new-directory
The reviewed decoder validates safe paths, sizes and hashes, rejects symlinks
and existing output, and never executes decoded bytes. No private notes or
unrelated later-run evidence is included. Publication requires separate review.
