# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the coverage-loop qualification labels.

The live captures still run in the checker. These texts only name the
expected receipts and the pass line.
"""


def coverage_loop_labels() -> String:
    """Return the coverage-loop qualification labels.

    Returns:
        JSON with the dependency names, the expected receipts, and the
        pass line.
    """
    return (
        '{"dependencies":["core/__init__.mojo","core/search.mojo","core/binary.mojo"],'
        + '"copy_message":"Native tool dependency copy changed: ",'
        + '"owner":{"fresh_receipts":3,"counted_receipts":2,'
        + '"full_per_counted_receipt":1,"typed_per_counted_receipt":1,'
        + '"conditioned_authority_refusal":true},'
        + '"owner_message":"Maintained generated owner controls did not'
        ' complete",'
        + '"root_only":{"completed":["root-only-seed-and-shared-positive",'
        + '"root-only-wrong-nonempty-root","root-only-stage-tamper-at-finish"],'
        + '"fresh_receipts":3},'
        + '"root_message":"Maintained root-only receipt controls did not'
        ' complete",'
        + '"theorems":"Current generated include-root theorems:",'
        + '"pass_line":"PASS: unchanged native loop streams; constant reachable'
        " outcomes; dynamic-empty negative; raw/reduced report parity; actual"
        " native entry-probe mutation rejected; shadowed range stays"
        ' unknown",'
        + '"results":{"entry-probe-mutation":"rejected contradictory actual'
        ' native probe",'
        + '"shadowed-range":"native empty custom iterable; both obligations'
        ' retained; T remains missing",'
        + '"native-alias-drift":"rejected original/staged mismatch",'
        + '"generation-byte-correspondence":"native LF, CRLF, CR and UTF-8'
        ' pairs verified",'
        + '"production-wrapper":"actual sealed raw capture and full'
        " original-manifest report; prebuilt executables retain 5s; raw main"
        ' retains alarm(5); exact stdout and reduced evidence parity",'
        + '"test_production_hang":{"status":142,"success_receipt":false},'
        + '"test_production_compile_error":{"success_receipt":false},'
        + '"production-deadline":{"status":124,"success_receipt":false},'
        + '"interrupted-generation":"old origin index invalidated before'
        ' failing writes"}}'
    )
