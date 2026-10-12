# CARLA qualification policy addendum

This reviewed policy exception applies to the combined issue-completion
qualification. It supersedes only the blanket requirement for unchanged test
and watchdog limits in `full-audit-711-invariants.md` at these Python test
harness sites:

- `CoverageInvariantContracts.test_direct_and_qualified_package_verification`
  uses a 30-second subprocess allowance instead of 10 seconds for each direct
  or package import and complete source-verification probe.
- `MapSuccessorLoopTests.clean_import_probe` uses a 30-second subprocess
  allowance instead of 10 seconds for its isolated import/consumer probes.

The import allowances originally aligned with the then-existing 30-second
proof-consumer probes.
The original test history does not document the numerical choice of ten
seconds as a calibrated performance requirement. This is an explicit new
policy decision, not a claim about an undocumented historical intent.

The original ten-second failures remain qualification evidence, including the
v22 timeout. Its separate 10.524-second plain completion was diagnostic. A pass
under thirty seconds does not turn those failures into passes. The new source
seal and fresh receipts identify the changed harnesses and this addendum.

Native five-second test limits and fifteen-second outer controls, numerical
work budgets, proof predicates, coverage denominators and all other maintained
individual child timeouts remain unchanged. This includes the 120-second
authority children and the separate 1,800-second AIR-emission child in
`tools/check_air_calls.py`. Full source-bound, adversarial, native, coverage and
exact-head CI qualification is still required. This addendum claims no passing
gate.

Two external scheduling allowances are revised for a new final Python matrix.
Only the complete `tools/carla_lane_oracle/test_full_audit_cleanup_contracts.py`
authority batch receives 3,600 seconds per normal or optimized mode, instead of
1,800. Every other module retains its 1,800-second cap. The aggregate matrix
window changes from 10,800 to 21,600 seconds. These values govern externally
supervised batches, not individual tests or public API performance. The old
values originated in external orchestration and were later preserved by this
policy; the maintained test-tools recipe itself specifies neither allowance.
No maintained test, internal child, native, numerical or hosted-CI limit changes.

The measured planning basis is 10,082.615892 seconds for 152 distinct completed
historical v28 non-authority stages. Adding 7,200 seconds for both proposed
3,600-second authority batches, 600 seconds for supervision, and 3,600 seconds
for new tests, repaired fixtures and runtime uncertainty gives 21,482.615892
seconds, rounded up to 21,600. The historical stages include failures. These
are bounded scheduling allowances, not a final-source runtime guarantee or an
assertion that either authority batch will pass.

All original 10,800-second-window and 1,800-second-authority receipts remain
unchanged, including the timed-out normal authority batch and the unlaunched
optimized batch. A new attempt must bind this policy, one newly frozen complete
source identity, fresh normal/optimized discovery and the entire required
module/test inventory. No skipped, omitted or substituted obligations are
permitted. Every final test body must run fresh in both modes; partial or
subset diagnostics cannot be combined into a passing complete authority batch.
Any new batch or aggregate timeout remains a failure under its actual limits.

The external scheduling changes did not themselves approve the two import
allowances. On 12 October 2026, the owner explicitly authorized necessary
validation-timeout changes. Both import guards remain at thirty seconds.

`MapSuccessorLoopTests.consumer_script_probe` now allows forty-five seconds
instead of thirty for each complete isolated Python proof-consumer process.
This applies to its CLI, package, direct-import and refusal controls in both
interpreter modes. All assertions, source checks and coverage requirements stay
unchanged. Earlier thirty-second timeouts remain failures under their original
limit; the new allowance does not turn them into passing evidence.

The hash-bound theorem document and every historical proof record retain their
original bytes. No source-authority pin is changed for this policy exception.
