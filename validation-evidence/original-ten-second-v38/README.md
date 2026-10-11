# Original 10-second diagnostic, candidate v38

COLLECTION COMPLETE. 22 actual child attempts: 16 returned zero and 6 timed out.
All four maintained-method stages returned 1; all four inventory checks returned
0. No supervisor stage timed out. Collection took 118.93802166300884 seconds,
with original receipts reporting source/SDK unchanged and zero owned descendants.

Invariant direct and qualified-package children each timed out once and returned
zero once (successful durations 9.718523084011395s and 9.99215825900319s). All four
invariant children ran without -O and without inherited PYTHONOPTIMIZE, even under
optimized parents. Clean-import ordinary CLI and shadowed CLI timed out in normal
and -O modes; the other fourteen clean-import attempts returned zero.

This is only a diagnostic of five maintained methods per parent mode. The two
helper timeout arguments were changed from the maintained 30s to original 10s
only in memory. Source bytes were unchanged. Completion under accept_nonzero=true
is not a pass. This establishes no current-30-second qualification or owner
timeout-policy approval, native/coverage/hosted-CI readiness, merge readiness,
repeatable timing headroom, or issue completion.

VALIDATION-SUMMARY.json is a derived index of every exact child argv, cwd, parent
and child mode, outcome and timing, plus all stage commands/caps/receipts. Raw
originals remain authoritative. Child wrapper timing, unittest timing and parent
supervisor timing are distinct. The original protocol review is cited by exact
hash only; private review bytes are excluded. Publication metadata is preserved
as a reference, without new remote verification. Stability is attributed to the
original receipts; no candidate/SDK scan, import or test was performed here.

All 41 originals are preserved losslessly, including full logs and observations,
all START/RESULT receipts, terminal RESULT, source seals, SDK before/after, window,
config, both protocol files and seal, supervisor source/console, and publication
binding. Only polling LATEST/PROCESSES, private notes/reviews, other phases,
candidate source contents and SDK images are excluded.

INNER-MEMBER-MANIFEST.json lists exact original hashes and byte sizes. Originals
are base64 JSON inside deterministic gzip mtime=0, then UTF-8 base64. The outer
manifest seals every transport payload except itself. Independently compare the
outer-manifest hash with the supplied hash before using the packet.

Verify without writing: python -B decode_verify.py
Decode originals to a NEW directory: python -B decode_verify.py --output /new/directory
The existing byte-identical safe decoder verifies hashes, sizes and paths without
executing or importing evidence. The builder is provided as source only; it was
used for static packaging, not diagnostic execution. Its output is create-only
and all consumed inputs are fixed by the input lock. No remote writes occurred.
