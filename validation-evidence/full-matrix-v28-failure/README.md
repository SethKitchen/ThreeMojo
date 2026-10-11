# Original full-matrix v28 failure evidence

FAILED. The original 154-stage matrix stopped at stage 17. Sixteen complete
stages passed 110 executions. The normal frozen-arc module ran five methods:
four passed and one failed its diagnostic-string assertion. The mutation was
rejected, but the resulting ValueError did not match "unreviewed runtime pin".
The complete original traceback is readable in actual/full-python-matrix-final-v28/.
All 137 later stages (2,559 expected executions) were unrun in this attempt.
The failed stage returned 1 without timeout. The 1,800-second module and
10,800-second whole-window limits were unchanged; the actual window lasted
1,001.456662562 seconds. Source/SDK receipts stayed unchanged; no descendants
remained. This is a failed qualification attempt, not an overall pass.

The exact published source commit is 031f9f726edb6e9409853fd777af966c8ebba88d,
with tree d2c9f94523b9c03aa94b04eaad774f73f147cd74. The pre-execution publication
binding is retained as originally written. All original matrix files, logs and
actual console output are retained. All fresh discovery files and console
output are also retained: 77 modules in both modes, 1,337 IDs per mode.
Discovery did not run test bodies and contributes no passing executions.
Later diagnostic-continuation receipts are deliberately outside this packet.
They cannot retroactively complete or rewrite the original failed attempt.

The inner manifest lists each original's path, size, SHA-256 and storage.
Readable originals are byte-exact. Other originals are per-member base64 in
JSON, compressed with deterministic gzip mtime=0 and base64 encoded. Raw merged
logs are complete; stdout/stderr separation is not reconstructed. Derived
summary and command-index files are labeled separately. The outer manifest
seals every payload and excludes itself. Exact source payloads cover all 31
changed paths, all 77 selected test modules and SDK support/runtime record;
the entire unchanged repository and installed SDK image are not distributed.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The copied reviewed decoder verifies hashes/sizes and safe paths before writing,
refuses symlinks and existing output, and never executes decoded contents.
The packet builder only reads, checks and serializes bytes. No project import,
rerun, native operation, candidate edit or upload is performed by packaging.
No private design/review notes or diagnostic-continuation evidence is included.
