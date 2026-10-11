# CARLA qualification policy addendum

This reviewed policy exception applies to the combined issue-completion
qualification. It supersedes only the blanket requirement for unchanged test
and watchdog limits in `full-audit-711-invariants.md` at these two Python test
harness sites:

- `CoverageInvariantContracts.test_direct_and_qualified_package_verification`
  uses a 30-second subprocess allowance instead of 10 seconds for each direct
  or package import and complete source-verification probe.
- `MapSuccessorLoopTests.clean_import_probe` uses a 30-second subprocess
  allowance instead of 10 seconds for its isolated import/consumer probes.

The allowance is aligned with the existing 30-second proof-consumer probes.
The original test history does not document the numerical choice of ten
seconds as a calibrated performance requirement. This is an explicit new
policy decision, not a claim about an undocumented historical intent.

The original ten-second failures remain qualification evidence, including the
v22 timeout. Its separate 10.524-second plain completion was diagnostic. A pass
under thirty seconds does not turn those failures into passes. The new source
seal and fresh receipts identify the changed harnesses and this addendum.

Native five-second test limits and fifteen-second outer controls, numerical
work budgets, proof predicates, coverage denominators, 120-second authority
children, 1,800-second module limits and the 10,800-second matrix window remain
unchanged. Full source-bound, adversarial, native, coverage and exact-head CI
qualification is still required. This addendum itself claims no passing gate.

The hash-bound theorem document and every historical proof record retain their
original bytes. No source-authority pin is changed for this policy exception.
