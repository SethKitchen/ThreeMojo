# Four distinct terminal lexical focused phases

The earlier v36 normal attempt failed: 4 methods ran, 1 failure and 51 error
records. Its full raw log and FAILURE receipt remain byte-exact. One method
passed; two methods had ordinary errors; the differential method had 49 subtest
errors plus the failure. Those records affect 3 methods, not 52 methods. The
configured optimized v36 stage never launched and has no invented receipt.

Three later v37 focused phases passed independently: 4 normal + 4 optimized
mechanics methods; one normal CLI wrapper (28.203s); and two maintained consumer
methods in each interpreter mode (4 method executions). This is 13 successful
v37 method/wrapper executions, not a full matrix or hosted qualification.

Exactly one mechanics method defines 49 differential cases (19 fast, 30
fallback) per interpreter mode. The sealed consumer source defines 6 real-script
variants and 4 CLI/package shadow variants per mode, 20 child variants overall.
Logs report 2 consumer methods per mode; they do not contain individual child
timings. Shadow variants do not include direct mode. The child cap remains 30s.
The standalone CLI wrapper's 28.203s is not a raw child duration or proof of
repeatable timing headroom; its parent-stage duration and 45s cap are separate.

The four phase identities, source seals, configs, complete consoles, logs,
START/RESULT/FAILURE records, SDK before/after, and window records are preserved.
The source manifest's older 'variants ongoing' status is deliberately unchanged
beside the later terminal receipts. Exactly two final changed source files are
bound by that manifest; the failed v36 test and unchanged v37 consumer support
source are additional audit originals. The v35 publication binding is only a
historical base reference. No v37 remote or source-backup binding is invented.

VALIDATION-SUMMARY, COMMAND-RECEIPT-SEAL and SOURCE-VARIANT-INDEX are derived.
INNER-MEMBER-MANIFEST inventories every one of 58 complete originals by path,
size and SHA256. Archived members are lossless base64 JSON in deterministic gzip
(mtime=0), then base64 text. Evidence is never truncated or replaced by a summary.
The outer manifest seals every payload except itself. LATEST/PROCESSES polling
bytes, private review/design notes, and all other phases are excluded.

Verify without writing: python -B decode_verify.py
Decode into a new directory: python -B decode_verify.py --output /new/directory
The unchanged hash-bound decoder verifies paths, lengths and hashes. It does not
execute or unmarshal content. Builder output is create-only and requires the
reviewed builder and exact input-manifest hashes. Candidate/protocol code and
tests are never imported or executed by packaging. Original source/SDK stability
is attributed to terminal receipts, not new scans. No readiness, merge approval,
issue completion, timing-robustness or broader qualification is claimed.
