<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Lane correction controls

These controls explain intentional differences from CARLA 1360bb9.
They keep the original queries, map fixtures and numerical tolerances.
They do not establish that every admitted map is release-qualified.
The lane implementation remains a held draft until all final gates pass.

The reproducible scripts are in `tools/carla_lane_oracle`. The rounding
report is `tools/carla_rounding_bound.mojo`. They bind their
proofs to evaluator and fixture source hashes and preserve the native-exported
constant bits. Their README lists the four commands and report directory.
`tools/carla_distance_gate.mojo` checks the spiral-domain token digest and the interval token digest. `tools/carla_moment_gate.mojo` checks the moment-producer token digests and the stored coefficient bounds.

It keeps the spiral-domain proof path.

It reuses that spiral-domain check when the same texts are read again.
The proof file and the interval file are still read.
A changed text is checked again.
A failed check is not kept.

It keeps the moment proof path and the interval path.

It reuses that moment-producer check when the same texts are read again.
The proof file, the interval file, the geometry file, and the trig file are still read.
A changed text is checked again.
A failed check is not kept.

It keeps the moment pin file, the stored table, and the word count.

It reads the moment check plan before the pin file, the table, and the word count in one check.

`tools/carla_selection_gate.mojo` checks the selection-producer token digests and the phase-constant bounds.

It keeps the two selection producer digests.

It uses those producer paths for the grouped and roundoff flags.

It checks the producer names before that gate.

It checks the producer names before the selection tokens in one check.

It reads the selection labels before the producer paths in one check.

It returns the selection labels after that producer check in one check.

It reuses that producer check when the same texts are read again.
The producer files, the interval file, and the trig file are still read.
A changed text is checked again.
A failed check is not kept.

It restores one selection function inside its line span.

It keeps the selection contract path and the predecessor messages.

It reuses that selection record gate when the same bytes are read again.
The migration file is still read.
A changed byte is checked again.
A failed check is not kept.

It keeps the interval token digest.

It compares the selection token digest in one check.

It keeps the selector constant message.

`tools/carla_grouped_gate.mojo` checks the grouped-table token digest and the stored node and weight bounds.

It keeps the grouped proof module and its token digest.

It keeps the grouped consumer digest.

It compares that grouped-table token digest before the predecessor fallback.

It checks that digest and the stored bounds in one check when the digest matches.

It reuses that grouped table check when the same texts are read again.
The proof file and the geometry file are still read.
A changed text is checked again.
A failed check is not kept.
It reads the lane-control record paths after that reused check.

It checks those stored bounds before the lane-control record paths in one check.

It compares that grouped-table token digest in one check.

`tools/carla_y_gate.mojo` checks the five Y-finiteness token digests, the successor record digests, and the module token identity.

`tools/carla_speed_gate.mojo` checks the speed-parser record, its module token, and its correctness tests.

It keeps the speed-limit module and its two correctness tests.

It reads those paths before the migration record in one check.

It reads the companion record paths after that migration record in one check.

It lists the protected inputs from that same check.

It keeps the accepted successor record path.

It keeps the speed-parser contract prefix.

It reuses that speed check when the same bytes are read again.

A changed byte is checked again.

A failed speed check is not kept.

`tools/carla_raw_cut_gate.mojo` checks the raw-cut inverse record, the fixture token, the successor binding, and the operation graph.

`tools/carla_runtime_view_gate.mojo` checks the runtime-view record and its bound tests.

`tools/carla_followup_gate.mojo` checks the coverage-followup record, the pin digests, the ordered pin pair, and the pin placements.

`tools/carla_singleton_gate.mojo` checks the rounded LINE singleton record, the lane text token, the consumer graphs, and the selector path.

It translates universal newlines before that lane text comparison.

It translates those newlines and compares that lane text in one check.

It reuses that lane comparison when the same bytes are read again.
The files are still read.
A changed byte is compared again.
A failed comparison is not kept.

It selects the rounded lane minimum before restoring a changed declaration.

It selects every rounded lane minimum in one check.

It reads every rounded LINE declaration in one check.

It compares every selected rounded LINE declaration in one check.

It reads every rounded LINE declaration and compares each selected one in one check.

It checks every declaration graph when every selected declaration matches in one check.

It reuses that declaration-graph check when the same texts are read again.
The declaration files are still read.
A changed text is checked again.
A failed check is not kept.

It restores every changed rounded LINE declaration and checks every graph in one check.

It compares every rounded LINE module text in one check.

It compares every rounded LINE source pair by its tokens in one check.

It checks the dependency words before those token pairs in one check.
A word failure is returned before a token result.
The same pairs are not compared again after that check.
A changed module is compared again.
A token error is still reported after the modules are read again.

It reuses that word-and-token check when the same texts are read again.
The module files are still read.
A changed text is checked again.
A failed check is not kept.

It reuses a matching rounded LINE module when that module is read again.
A changed module is compared again.

It reuses a rounded LINE record when the same bytes are read again.

It checks every rounded LINE consumer graph in one check.

It keeps the consumer import scope before the first definition.

It extracts every consumer import scope in one check.

It checks every consumer import scope when the lane scope matches in one check.

It checks those import scopes before the lane minima in one check.

It reuses that import-scope check when the same texts are read again.
The scope files are still read.
A changed text is checked again.
A failed check is not kept.

It checks those restored graphs before the lane minima in one check.

It reads the restored import scope before those graphs and the lane minima in one check.

A restored scope still fails before a graph is accepted.

It keeps the lane path, the rounded-line path, and the consumer messages.

It compares each module path with that rounded-line path in one check.

It keeps the rounded-line contract prefix.

`tools/carla_frozen_arc_gate.mojo` checks the frozen ARC producer record, the producer functions, and the arc layout.

It reads the companion record paths after that frozen record check in one check.

It keeps the frozen-arc source and the polynomial and road paths.

It reads those paths before the frozen migration record in one check.

It checks the guard pin digest before the frozen ARC successor token in one check.

It reads the guard label before that pin digest in one check.

It reuses that digest and token check when the same bytes are read again.
The frozen ARC source is still read.
A changed byte is checked again.
A failed check is not kept.

It keeps the frozen runtime-pin labels and the public successor message.

It keeps the reviewed cleanup record path.

It keeps the frozen-arc contract prefix.

It writes each frozen runtime pin back to its historical value.

It writes that restored pin with two-space indentation.

It rebuilds one frozen runtime pin predecessor in one check.

It reads the frozen pin labels before that runtime predecessor in one check.

It reads the frozen-arc paths after that runtime predecessor in one check.

It reuses that frozen record when the same bytes are read again.

It reuses one prior digest pair when that pair is checked again.
A changed digest is checked again.
A failed check is not kept.

It relabels one runtime pin failure when the cause is the reviewed contract error.

`tools/carla_invariant_gate.mojo` checks the coverage-invariant record, the pin digests, the ordered pin pair, and the pin placements.

It reuses one coverage-invariant record gate when the same bytes are read again.
The migration file, the prior record, and each component are still read.
A changed byte is checked again.
A failed check is not kept.
The first record read checks the ordered pin pair with the component digests.
That pair check also covers the component gate for those same bytes.

It compares every coverage-invariant successor digest in one check.

It compares those successor digests before the dispatch migration record in one check.

It reuses that successor comparison when the same digests are read again.
The source files are still read.
A changed digest is checked again.
A failed check is not kept.

It checks every coverage-invariant predecessor in one check.

It reuses that ordered pin pair when the same names are checked again.

A changed name list is checked again.

A wrong pair still fails before the next record is read.

It rebuilds one coverage-invariant pin predecessor in one check.

It rebuilds the runtime and guard pin predecessors in one check.

The runtime predecessor still fails before the guard pin is checked.

It reuses that predecessor pair when the same pins are placed again.

A changed pin is placed again.

The runtime hash and repeated-key check still run before that reused pair.

It keeps the four coverage-invariant source paths.

It keeps the six extra coverage-invariant inputs.

It reads the invariant migration and the dispatch paths before that protected tail in one check.

It keeps the pin file names, the prior record, and the successor message.

It reads those labels before the migration record in one check.

It keeps the coverage-invariant contract prefix.

It keeps a component name inside its directory.

It checks those component names before the record digests in one check.

An escaping name still fails before a digest is accepted.

It checks the ordered pin pair after those component digests in one check.

A component digest still fails before that pair is accepted.

It uses the last path part as the pin file name.

It writes each historical pin with two-space indentation.

It compares each successor token digest before the predecessor fallback.

It compares the junction token digest in one check.

It checks that junction digest before the other successor tokens in one check.

It reuses that token check when the same texts are read again.
The source files are still read.
A changed text is checked again.
A failed check is not kept.

`tools/carla_dispatch_gate.mojo` checks the curve support and dispatch record, the predecessor edge, and the operation graphs.

It checks every historical dispatch pin in one check.

It checks every dispatch operation graph in one check.

It checks every dispatch source graph and every premise graph in one check.

It reuses that source-graph check when the same texts are read again.
The source files are still read.
A changed text is checked again.
A failed check is not kept.

It keeps the current dispatch source when the token matches.

It hashes the dispatch source before that choice.

It chooses every dispatch source in one check.

It compares each premise text before the predecessor fallback.

It reads every dispatch premise declaration in one check.

It compares every dispatch premise text in one check.

It reads every dispatch premise declaration and compares its tokens in one check.

It checks every dispatch reference declaration token in one check.

It checks those reference tokens before the grouped proof identity in one check.

It reuses that reference-token check when the same texts are read again.
The reference files are still read.
A changed text is checked again.
A failed check is not kept.

It chooses every dispatch premise fallback in one check.

It compares every dispatch premise and chooses its fallback in one check.

It reuses that premise fallback check when the same texts are read again.
The premise files are still read.
A changed text is checked again.
A failed check is not kept.

It checks every Map seed premise in one check.

It reads every dispatch reference declaration in one check.

It selects the Map seed or the lane predecessor after that comparison.

It checks every lane predecessor in one check.

It keeps the two dispatch sources and the five protected paths.

It reuses that migration record document when the next checker asks for it.

A failed read is tried again.

It reuses the checker failure prefixes when the next checker asks for them.

It reuses the contract prefixes when the next checker asks for them.

A failed prefix read is tried again.

It reads the dispatch migration record before those protected paths in one check.

It reuses that dispatch record when the same bytes are read again.

It keeps the dispatch path, the choice names, and the premise messages.

It reads those dispatch labels before the source choices in one check.

It reuses those dispatch labels after the source choices.

It checks those complete tokens after the current choices in one check.

It keeps the current sources when that token list is already checked.

It reuses a current source choice when that source is read again.
A changed source still chooses again.

It checks every restored predecessor edge in one check.
The first mismatched edge still fails before a later edge is accepted.

It keeps the dispatch contract prefix.

`tools/carla_cleanup_gate.mojo` checks the reviewed cleanup record, the winner-sign digest, the guard pin digest, the trig and geometry stored words, and the successor tokens.

It reads the companion record paths after that cleanup record check in one check.

It reuses that cleanup record when the same bytes are read again.

It reads the companion record paths before that protected tail in one check.

It reads the cleanup paths and the migration record before that protected tail in one check.

It reads the frozen and invariant protected inputs after that cleanup bundle in one check.

It admits trig and geometry word changes only for their reviewed token.

It hashes a premise dependency before choosing its word check.

It chooses every premise dependency word check in one check.

It checks every selected stored-word list in one check.

It chooses every dependency check and checks its selected words in one check.

It reads the dependency pins before those selected words in one check.

It reuses a selected word check when the same text is read again.
The dependency files are still read.
A changed text is checked again.
A failed check is not kept.

It checks those selected words before the cleanup paths in one check.

It records the accepted words from that paths check.
A later word check does not send those words again.

It selects each reviewed declaration and checks that each premise fragment occurs once, in order.

It keeps the five reviewed premise fragment lists.

It keeps the three successor paths and the two premise paths.

It keeps the fourteen extra cleanup inputs.

It keeps the trig and geometry dependency paths and tokens.

It keeps the trig and geometry choice names.

It keeps the cleanup contract prefix.

It keeps the eight migration record paths and digests.

It keeps the five premise declarations and the junction path.

It reads those five premise declarations in one check.

It reads those declarations and checks every premise in one check.

It reads the cleanup declaration catalog before those premise checks in one check.

It checks those premise fragments before the frozen migration record in one check.

It reuses that premise check when the same texts are read again.
The three source files are still read.
A changed text is checked again.
A failed check is not kept.

It checks the guard pin digest before the declaration catalog in one check.

It reads that declaration catalog after the runtime pin predecessor in one check.

It reads the frozen-arc paths after that declaration catalog in one check.
It reuses that predecessor when the same pins are placed again.
The paths stay in that result.
The runtime digest is checked before that reuse.
A changed pin is placed again.
A failed placement is not kept.

It keeps the winner-sign record and the runtime pin path.

The singleton, frozen ARC, dispatch, raw-cut, and optional-runtime contracts use that declaration text.

It also builds the significant token lists for the singleton, frozen ARC, dispatch, raw-cut, and selection contracts.

It reports the declaration line span used by the selection contract.

`tools/carla_frozen_arc_gate.mojo` builds the declaration routing for the frozen ARC producer.

It reads every frozen ARC producer declaration in one check.

It checks every frozen ARC producer function and the arc layout in one check.

It checks that producer review before the invariant labels in one check.

It reuses that producer review when the same texts are read again.
The producer files and the arc file are still read.
A changed text is checked again.
A failed check is not kept.

It reads those declarations and checks the arc layout in one check.

It lists the executable names checked by the optional-runtime contract.

It lists the production Mojo files for the containing-model scan in one check.
It keeps the reviewed path order.
Each kept file is still read.

It reuses that containing-model consumer check when the same texts are read again.
Each kept file is still read.
A changed text is checked again.
A failed check is not kept.

It reuses that optional-runtime declaration group when the same texts are read again.
The module files are still read.
A changed text is checked again.
A failed check is not kept.

It removes an argument move sigil before that contract parses a function body.

It returns the top-level statements used by the spiral-moment and selection contracts.

It returns the top-level `def`, `from`, and `@` lines used by the spiral-moment block check.

It masks the stored-word routing used by the spiral-moment check.

It removes `var`, `comptime`, and the `derivatives: Bool` parameter list from one ideal function.

It returns Python source and generic parameters for one sampled declaration.

The Sum2, optional-runtime, and heading checks parse declarations through that syntax.

It slices one top-level function for the heading check.

It replaces one executable token fragment for the cleanup mutation tests.

It reads the decimal literals in one stored array or scalar declaration.

It reads those array literals and rounds them in one check.

It rounds one stored decimal literal to a binary64 word.

It rounds those decimal literals and reads them as integers in one check.

It rounds one literal and classifies that word in one check.

It checks a signed zero before that rounded word in one check.

It classifies an unsupported literal as nearest in that same check.

It rounds one plus each stored node before the moment rows.

It reads the exact fraction of each stored binary64 word.

It returns the SHA-256 digest of each reviewed source text and pin file.

It checks the stored-half helper result uses.

It requires the helper text before that stored-half check in one check.

It projects the Sum2 ideal spiral by removing the reviewed auxiliaries.

It projects the Sum2 ideal spiral and returns its result in one check.

It rewrites each stored-half call into a product with one half.

It swaps each legacy half-rate product into rate times one half.

It rejects a binding that shadows a reviewed helper.

It reads each top-level helper import in source order.

It compares the fresh heading graph with each stored consumer.

It reads the package path and the heading consumers in one check.

It checks the fresh heading graph and returns the consumer count in one check.

It reuses that heading check when the same texts are read again.
The bounds file, the consumer files, and the proof file are still read.
A changed text is checked again.
A failed check is not kept.

It returns the heading consumer count after that comparison.

It returns the runtime-support result after the heading, optional-runtime, and Sum2 checks.

It writes the runtime-support result with two-space indentation.

It indents that runtime-support result after the result in one check.

It reuses that runtime-support result when the same inputs are read again.
A changed input is checked again.
A failed check is not kept.

It keeps the runtime failure prefix.

It compares the projected ideal spiral with the historical half-rate form.

It checks the ideal spiral declaration before projecting it.

It projects the ideal spiral from its source text.

It checks the legacy digest, the helper, and the projected graph in one check.

It checks the lane proof refusal before routing.

It compares the Sum2 recurrence, leaf, and caller graphs.

It checks those caller graphs before the helper imports in one check.

It checks those graphs before the Sum2 projection in one check.

It reads the Sum2 checkpoints before those graphs in one check.

It reuses that Sum2 graph check when the same texts are read again.
The module files are still read.
A changed text is checked again.
A failed check is not kept.

It keeps the reviewed Sum2 helper digest.

It reads the Sum2 plan before the package path in one check.

It compares the scalar environment call with its stored statement.

It counts one stored statement or expression in a runtime helper.

It checks the fresh guard and the helper body against the stored fragment.

It checks the fresh cell producer after the original debit.

It requires each dispatch debit to precede the optional loop.

It keeps the dispatch setup after the depth refusal.

It refuses a center error used as the world error.

It requires the stored-half declaration before the projection.

It binds each runtime helper from its moved declaration.

It refuses a runtime fragment that has no moved declaration.

It derives the stored moment rows in exact arithmetic.

It spells those stored words and derives the rows in one check.

It reuses those derived rows when the same words are read again.
A changed word is checked again.
A failed check is not kept.

It checks the stored moment table against the derived words.

It packs the derived moment words into big-endian payload bytes.

It writes those packed bytes from the hexadecimal payload.

It checks the derived payload size and the three pin-file digests.

It builds the report meta from the payload, the projection, and the pin digests.

It builds that report meta after the moment payload in one check.

It checks the stored table before that report meta in one check.

It reuses that table check when the same table is read again.
The table file is still read.
A changed table is checked again.
A failed check is not kept.

It writes the moment report and the coefficient file with two-space indentation.

It indents that moment report before the output-path guard in one check.

It checks the stored array names, word counts, and output paths.

It drops comments and blank lines from one source block.

It reads the stored moment words from the generated table.

It keeps the scalar spelling prefix.

It rounds one exact fraction to binary64.

It keeps a negative zero and reports one binary64 word.

It spells each stored word as `0x` and 16 uppercase digits.

It reads each stored hexadecimal word as an integer.

It reads a stored table and its words as integers in one check.

It reads the word count before that stored table in one check.

It checks the moment pin sets, paths, dependency closure, legacy digest, and result pins.

It builds the moment pin specification before that pin check in one check.

It reuses that moment pin check when the same document is read again.
The pin file is still read.
A changed document is checked again.
A failed check is not kept.

It keeps the moment array paths, scalar names, block boundaries, and routing paths.

It keeps the moment routing constants and the route comparison.

It checks every stored-moment route digest before the source read.

It compares every stored-moment route after that read.

It reuses that route batch when the same texts are read again.
The route files are still read.
A changed text is checked again.
A failed check is not kept.

It reads the sampled closure after those live routing documents in one check.

It checks the try-only refusal before the route pins in one check.

It keeps every stored-moment operation block in one check.

It checks every operation block before the route digests in one check.

It keeps every stored-moment constant array in one check.

It keeps every stored-moment scalar word in one check.

It checks every scalar word before the blocks and route digests in one check.

It reuses that scalar and block check when the same texts are read again.
The scalar files and the block files are still read.
A changed text is checked again.
A failed check is not kept.

It groups every stored-moment fraction text by array.

It spells each stored word before its fraction text in one check.

It reads every stored array, its fractions, and its name set in one check.

It reuses that array-fraction check when the same texts are read again.
The array files are still read.
A changed text is checked again.
A failed check is not kept.

It checks every rounded node sum in one check.

It reuses that node-sum check when the same nodes and weights are read again.
A changed word is checked again.
A failed check is not kept.

It derives the moment rows after those rounded node sums in one check.

It reuses that sum-and-row check when the same rows are read again.
A changed row is checked again.
A failed check is not kept.

It spells the stored nodes and weights before their rounded sums in one check.

It reuses that spelling when the same nodes and weights are read again.
A changed word is checked again.
A failed check is not kept.

It checks the ideal half projection in one call.

It checks the legacy pin digest before the ideal half projection in one check.

It reuses that legacy projection when the same record is read again.
A changed record is checked again.
A failed check is not kept.

It checks the stored-half tail before the projection.

It keeps the moment dependency record and the check messages.

It keeps the moment report names and the pass line.

It keeps the moment failure prefix.

It keeps the moment command help and the two command errors.

It keeps the KeyError mark and the moment-word prefix.

It keeps the moment derive prefix.

It keeps the derived coefficient words in cosine, then sine, order.

It checks those coefficient words before the stored table in one check.

It builds the moment payload after those coefficient words in one check.

It writes the canonical stored-moment table source.

It writes that table source after those coefficient words in one check.

It writes that table source before the moment payload in one check.

It reads those payload bytes after that table source in one check.

It indents the coefficient rows after those payload bytes in one check.

It indents the moment report before those generated products in one check.

It checks the output paths after those generated products in one check.

It reads those coefficient words as integers in one check.

It returns one normalized source block between two markers.

It checks each operation block and routing text against its pin.

It removes the try-only parameter from one routing declaration.

It keeps the bounds path and the reference refusal.

It reads the current pin value at each coverage transition and writes the historical value.

It returns the kept-token digest and declaration text for the lane-control and Sum2 checks.

It compares the two lane-control token digests in one check.

It checks those declaration tokens before the lane predecessors in one check.

A token mismatch still fails before a predecessor is accepted.

It reuses that lane-control record when the same bytes are read again.
It reuses those token pairs when the same texts are checked again.
It reuses that prepare when the same declarations are read again.
The files are still read.
A changed byte is checked again.
A failed check is not kept.

It reuses one kept-token comparison when the same texts are compared again.
A changed text is compared again.

It reads every lane-control declaration in one check.

The cleanup, dispatch, selection, grouped-table, and lane-control checks use that digest.

`tools/carla_lane_control_gate.mojo` checks the lane-control migration digest, its source digests, and the declaration tokens.

It accepts one historical lane declaration when the owner is empty and the token matches.

It renames the first frozen lane declaration.

It renames every frozen lane declaration in one check.

It renames those declarations and reads every declaration in one check.

It reads the lane-control labels before that prepare in one check.

It keeps the lane-control labels and the frozen reference prefix.

It keeps the lane-control record digests.

It keeps the lane-control pass line.

It keeps the lane-control migration path.

`tools/carla_render_actor_gate.mojo` checks the render-actor reuse record and its bound tests.

It reads the module paths after that record check in one check.

It checks every render-actor file digest in one check.

It reads the render-actor ledger once for every edge.

It puts the module path on the render-actor edge.

It puts every render-actor path on its edge in one check.

It checks every render-actor digest and writes each path in one check.

It reads the consumer messages before those digests in one check.

It reuses that render-actor record and those digest checks when the same bytes are read again.

A changed render-actor byte is checked again.

It keeps the render-actor module and its three bound tests.

It reads the render migration record before those paths in one check.

It keeps the render-actor consumer and test messages.

It keeps the render-actor contract prefix.

`tools/carla_runtime_boundary_gate.mojo` checks the runtime-boundary record, its bound tests, and the view-step edges.

It checks every runtime-boundary file digest in one check.

It reads the runtime-boundary ledger once for every edge.

It extends an edge when a reviewed view step starts at that edge.

It extends every runtime-boundary edge in one check.

It checks every runtime-boundary extension in one check.

It decides every runtime-boundary edge and checks its extension in one check.

It checks the view steps before the module paths and the edge extensions in one check.

It reuses that runtime-boundary record and those edge checks when the same bytes are read again.

A changed runtime-boundary byte is checked again.

It puts the module path on that edge.

It puts every runtime-boundary path on its edge in one check.

It checks every runtime-boundary digest and writes each path in one check.

It reads the consumer messages before those digests in one check.

It keeps the four runtime-boundary module paths.

It reads the runtime migration record before those modules and tests in one check.

It keeps the twelve runtime-boundary test paths.

It keeps the runtime-boundary consumer and test messages.

It keeps the runtime-boundary contract prefix.

`tools/carla_envelope_gate.mojo` checks the envelope budget predecessor record and the admission token.

`tools/carla_selection_record_gate.mojo` checks the selection predecessor record and the restored token.

It reads the declaration line span before restoring that function.

It rebuilds that selection predecessor in one check.

It checks the grouped table after that restored predecessor in one check.

A predecessor failure still fails before the grouped table is accepted.

It chooses the grouped roundoff envelope name from the module path.

It chooses that envelope name while rebuilding the selection predecessor.

`tools/carla_ideal_gate.mojo` checks the historical ideal source digest and the projected graph digest.

It keeps the legacy digest and the projected digest.

It requires the helper and the current spiral to be text.

It returns the eight ideal-projection result counts.

`tools/carla_accepted_gate.mojo` checks the accepted successor record, the pin digests, the ordered pin pair, and the pin placements.

## Lane poses

The pose follows the derivative of the actual lane-center expression.
The horizontal tangent gives yaw. Elevation change divided by horizontal
lane-center speed gives pitch. The traffic direction keeps CARLA's winding
convention. The stored trigonometric polynomials and sampled-position
interpolation are differentiated as implemented. Exact sine identities are
not substituted for those polynomials.

In the town fixture, road 1, section 1, lane -1 at s=50 has tangent
(1, 0.025, 0) in CARLA coordinates. Its yaw is atan(0.025) in degrees,
or 1.4320961841646465. The old expectation, 1.4323944878270582,
is 0.025 converted directly from radians. It treats a slope as an angle.
The tree-transform expectation uses the same corrected tangent.

Independent differentiation gives these further town poses before public
Float32 narrowing:

- Road 5, lane -1, s=10: yaw -7.1619724391352903 degrees and pitch -1.1110515913233193 degrees
- Road 5, lane +1, s=40: yaw 133.96511248044121 degrees and pitch 361.26665243151570 degrees
- Road 5, lane -2, s=50: yaw -46.95450998676703 degrees and pitch -2.0180642587511068 degrees

The horizontal speeds are 1.03125, 0.9045329833818656 and
1.1351885149427073. Thus elevation grade alone is not the pitch tangent.
The sampled-geometry controls reconstruct the small parabola chord tables
independently. Existing angular tolerances stay at 1e-4 or 1e-3 degrees.
Existing position expectations and tolerances are unchanged.

## Ordinary nearest minima

The ARC query is (70, 10, 0), on road 11, lane -1. Its center circle has
radius 18.25 and center (60, 20) in CARLA coordinates. The independent
circle minimum is s=pi/(4*stored(0.05)). The shipped half-angle polynomial
has a smooth minimum at s=15.7079632679489652900784.
The old s=15.603252062536761 loses more than 0.00707462 in squared distance.

The shoulder query is (10, 105, 0), on road 5, lane -2. Its smooth
stored-expression minimum is s=4.5865313100931020167150.
The old s=6 has a nonzero squared-distance derivative of 11.09057786
and loses more than 7.55224 in squared distance.

These are minima of smooth expressions over stored binary64 constants.
Rounded evaluation is a staircase; it need not have one unique minimizer.
The independent forward-error analysis covers each executed arithmetic
operation, permitted FMA contraction, quadrature count transitions and
ARC quadrant and sinc transitions. Exact rational moment calculations
cover all 23 possible shoulder quadrature counts and 46 endpoint signs.
The shoulder expression has second derivative greater than 1.813299999999992.

Other count boundaries have squared-distance gaps greater than 0.44312915.
Other geometry records have gaps greater than 1991.35.

The rounded-distance error bounds are 5e-11 for the shoulder and 4e-12
for the ARC. The ARC second derivative is greater than 0.912499999999998
on the relevant interior. A strong-convexity bound then encloses every
rounded global minimizer within 1.050220e-5 of the shoulder minimum and
4.187392e-6 of the ARC minimum. Endpoint and competing-lane alternatives
are excluded separately. These enclosures are smaller than the unchanged
1e-4 station tolerance. The expected values come from these bounds, not
from copying the search output.

## Public index partition

`Map.segment_count()` and `Map.segment()` expose the certified nearest-waypoint index.
The default nearest queries use CARLA's own partition, which the map keeps separately.
They do not expose a separate meshing partition. The index uses deterministic
lane order and can add subdivisions for accuracy.

The existing 250-meter gentle ARC has curvature 0.000001 and lane width 3.5.
The heading threshold does not split it. The original distance trigger
produces spans of approximately 101, 101 and 47.999999 meters.
Its lane-center radius is 1000001.75 meters. Independent circle sagitta
bounds give 1.2751272312 millimeters for each long span and
0.3187818079 millimeters for either half. The tail is below
0.2880004920 millimeters. The one-millimeter target therefore gives five
segments. The test checks every station and every exact shared endpoint.
The original final-position tolerance is unchanged.

The town index has 987 segments in the current candidate. This count is a
native regression observation, not an independent proof by itself.
Additional controls check all 26 nonzero lane sections in deterministic
order, directed parameter coverage (including closed point segments),
exact-or-adjacent joins, and required
record splits. They check finite cached full-evaluator boxes and scalar
containment. Scalar samples only check consistency; they do not certify
unsampled extrema. The separate full-curve bounds and narrow unsampled
admission controls remain required.

## Mesh rows

MeshFactory does not consume the nearest-waypoint index. Its row policy
uses the corrected section-wide straightness predicate.

Town road 1, section 1 spans s=30 through s=60. A width record changes
slope at s=40. At the unchanged two-meter mesh resolution, each of its
four nonzero lanes has 16 rows, 32 vertices and 30 triangles.
Section 0 retains 16 vertices. Thus the road has 144 vertices, and
section 1 with both walls has 192 vertices.

Joining the old two-row section-0 lane to the 16-row section-1 lane gives
36 vertices and 34 triangles with the two-triangle stitch. Plain append
and the one-vertex-wide stitch give 32 triangles. Controls independently
check both edges at all 16 rows against the fixture's piecewise width.
The old workloads and position tolerances stay unchanged.

## Remaining scope

The translated-s construction fixture near 1e20 requires an explicit
Float64 road-s resolution error. Its original inputs stay unchanged.
The [road-s proof](CARLA-road-s-resolution) establishes why the current
parameter-matched construction criterion is impossible for that fixture.
The line and its direct-Road stored-point minima remain representable.
Final consumer, coverage, format, generated-code and performance gates
remain required. These corrections do not implement global work budgets
(#580).

The OpenDRIVE reader handles border-only lanes (#577). See
[CARLA lane borders](CARLA-lane-borders).
