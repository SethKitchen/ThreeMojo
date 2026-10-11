# V28 seed-count terminal diagnostic failure pair

FAILED in both selected modes. Independently parsed normal and optimized logs
each report68methods:59passing methods, five methods with328failure records,
and four distinct errored methods, zero skips. There are327subtest failures
plus one ordinary method failure, not328subtests or328failed methods. Normal
elapsed694.025092691seconds; optimized684.602375748. Both returned1 without
timeout under unchanged1,800-second stage caps.

Every failure record shows an actual earlier Map rejection that mismatches the
expected target-path regex. No failure record says the exception was not raised.
This does not prove the intended dependency-specific rejection was reached;
the tests still fail. Four other methods error on the same Map rejection,
three directly and one through canonical-accumulation validation. The exact
per-method breakdown and error endings are derived from each log separately.
The sealed source contains historical Map read_bytes overlays and the nested
full-audit edge check preceding individual dependency validation. No fixture
was rerun and no failing assertion was weakened or converted to success.

Both complete498,953-byte raw merged logs, all warnings, all328failure blocks
and all4error tracebacks per mode are preserved in the reversible container.
START/RESULT receipts remain readable. No log is truncated or replaced with
the summary. Method counts and subtest counts remain separate throughout.

Only terminal configuration positions40/41 of the137-stage diagnostic collection
are selected. No outcomes are assigned to the other135stages or the collection.
No mutable RESULT/LATEST/PROCESSES/SDK-AFTER/console/handoff file is read/copied.
Constant initial source/SDK/window bindings remain exact. The absolute deadline
is2026-10-11T08:35:38.016452Z; its original initial clamp is9,158.74437seconds.

Terminal test-count annotations occur after the exact supervisor's source/SDK
post-stage checks return. This control-flow inference is explicit and is not
a fabricated final receipt. Both selected leaders were reaped without remaining
owned descendants in their receipts; no live overall process status is claimed.
Old qualification failures and later repair evidence remain separate.

The inner manifest records original path/size/hash/storage. Archived originals
are per-member base64 JSON, deterministic gzip mtime=0, then base64. Readable
originals are byte-exact. Outer manifest seals all payloads except itself;
summary and command index are derived. Full unchanged repository/SDK images
are not distributed.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The copied reviewed decoder checks safe paths/hashes/sizes, rejects symlinks and
existing output, and never executes decoded content. Packaging performs no
project imports, tests/native runs, candidate edits or uploads. Private notes,
mutable collection files and later repair evidence are excluded.
