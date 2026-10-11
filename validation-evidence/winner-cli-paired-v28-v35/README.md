# Terminal paired normal CLI winner diagnostic

COLLECTION COMPLETE, MIXED OUTCOMES. v28 failed when the maintained child hit
its unchanged 30-second cap; v35 passed this one wrapper. sequence_completed=true
means both outcomes were collected under accept_nonzero=true. It is not pair PASS,
qualification, timeout-policy approval, merge readiness or broader success.

The original unittest wrappers report 30.068s (v28 failure) and 29.796s (v35 pass).
Those are not exact child-only durations. Supervisor stage durations are separate;
neither supervisor hit its 45-second stage cap. The complete window cap was 120s.
One paired observation cannot establish repeatability, performance improvement or
stable timing headroom. No previous failure is rewritten or replaced.

Both original stage receipts carry the v35 primary source seal. The v28 stage
has v28 cwd; config additionally seals v28 and the probe protocol. Original
source seals, SDK before/after, window, config, driver, supervisor, full logs,
START/RESULT receipts, terminal RESULT and entire console are preserved exactly.
Publication bindings are references, not new repository or remote verification.
Protocol review is cited by exact hash only; private review bytes are excluded.
Method identity is attributed to that review, not a new candidate-source scan.

VALIDATION-SUMMARY.json and COMMAND-RECEIPT-SEAL.json are derived indexes.
INNER-MEMBER-MANIFEST.json identifies every complete original by path, size and
SHA256. Container members are base64 JSON in deterministic gzip mtime=0 then
UTF-8 base64. No evidence is truncated, normalized or replaced by its summary.
The outer manifest seals every payload except itself.

Verify without writing: python -B decode_verify.py
Decode into a new directory: python -B decode_verify.py --output /new/directory
The copied, hash-bound decoder verifies paths, sizes and hashes without executing
or unmarshaling evidence. No profile files are included or read. Builder output is
create-only and requires explicit exact terminal RESULT/console/builder hashes.
