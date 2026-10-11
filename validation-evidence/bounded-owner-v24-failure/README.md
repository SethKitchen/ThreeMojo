# V24 bounded-owner control failure evidence

FAILED: ten normal-mode methods ran; nine passed and one errored. Fail-fast
left twenty normal methods and all thirty optimized methods unrun. These are
unrun methods, not skips. The normal stage returned 1 without a timeout after
141.832963303 seconds, under its unchanged 1,800-second module allowance and
10,800-second collection window. Source and SDK receipts were unchanged and
no owned descendants remained. This is not a suite or qualification pass.

The raw test log retains the root-fault subtest error, the internal coherence
exception and the public ValueError wrapper traceback. Its final unittest
summary is Ran 10 tests / FAILED (errors=1). The supervisor stopped before
adding its post-success test-inventory annotations. Configured expected_tests=30
must not be mistaken for thirty executed methods. Derived observed/unrun method
lists are separate from the untouched original runtime receipts.

All eleven original phase files, actual supervisor console, exact config,
supervisor source, full source/SDK seals, 31-path source manifest and frozen
source bytes are preserved. The exact executed test source is readable. Later
corrected proposals, private reviews and design notes are not included. No
missing evidence is reconstructed. The full unchanged repository and SDK binary
image are not distributed; their identities remain bound by the original seals.

Readable members retain exact bytes. Remaining originals use per-member base64
inside one JSON container, gzip-compressed with mtime=0 and then base64-encoded.
INNER-MEMBER-MANIFEST.json records all original paths, lengths, hashes and storage.
PUBLISHABLE-EVIDENCE-MANIFEST.json seals all payloads, excluding itself. Summary
and command-binding documents are derived and explicitly separate.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies bytes before writing and rejects unsafe paths, duplicate
members, symlink payloads and existing output. It never executes decoded source.
Packaging performs no candidate edit, test/native rerun or upload. Broader
lifecycle/per-site controls, full matrices, native coverage and hosted CI remain
outside the qualification supported by this failed run.
