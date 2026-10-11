# Compact frozen-v17 center-observer evidence transport

This transport preserves all 639 payloads of the original evidence packet,
plus the original manifest, byte-for-byte. No validation evidence is dropped.
Source files, configs, seals, summaries, the final result, SDK receipts and
window start remain readable. The other 610 original raw receipt files are
grouped into one deterministic JSON container. Each member carries its original
path, byte length, SHA-256 and base64 data; the JSON is gzip-compressed with
mtime=0 and base64-encoded for text transport.

INNER-MEMBER-MANIFEST.json maps every original member to its readable payload or
container. source-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json is the byte-exact
original manifest. This directory's PUBLISHABLE-EVIDENCE-MANIFEST.json seals
the 35 transport payloads. A manifest does not recursively list itself.

Verify without writing or executing content:
  python -B decode_verify.py

Restore the entire original packet into a new directory:
  python -B decode_verify.py --output /path/to/new-directory

The decoder verifies all outer payloads, original member hashes, inventory and
bytes before writing. It rejects path traversal, duplicate members, symlink
payloads and existing output. It only writes bytes; it never imports, launches,
compiles or executes decoded content. The original absolute local_source paths
in the restored manifest remain historical provenance and are not dereferenced.

The original packet's acceptance and limits are unchanged: 202/202 stages and
49 exact before/after exported-observation pairs per O3/O0 mode, original caps,
unchanged source/SDK receipts and no owned descendants. This is newly executed
reconstructed frozen-v17 observer evidence. It does not restore lost historical
receipts, establish exhaustive internal traces, claim old full-search refusal
reachability, or qualify v18 or other validation. Native executables remain
excluded; their original hashes are preserved.
