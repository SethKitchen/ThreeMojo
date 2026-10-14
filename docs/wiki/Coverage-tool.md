# Coverage tool

`coverage/`. A source-to-source instrumenter and a report that measure line, branch, condition and MC/DC coverage. Mojo ships no coverage tool, and the toolchain has no `llvm-cov` to build one on.

This is original work with no three.js lineage.

## How it works

1. `build_cli.mojo` rewrites every covered module into `coverage/build/`, with a probe before each statement and around each decision. It writes a manifest of everything the probes can report.
2. The coverage tool and the suites are copied into `coverage/build/` as well, and the suites run from there. Each probe writes a hit or complete evaluation record to `stderr`. `stdout` is unchanged.
3. `report_cli.mojo` groups the records, matches them to the manifest, and prints the table. It exits with an error when anything is uncovered.

`make coverage` runs all three. See [How to measure coverage](How-to-measure-coverage).

### Why the run happens inside the build tree

Mojo 1.1 resolves a module beside the file being compiled before it looks at any `-I` path. A suite run from the repository root therefore imports the *real* library, whatever the search path says.

The suites used to run with `-I coverage/build -I .` and the first `-I` decided. Under 1.1 that arrangement measured nothing at all and reported a clean zero, which is the worst way for a coverage tool to fail. Copying the suites in makes the instrumented copies the ones beside them.

The repository coverage run copies the tool without instrumentation. Separate diagnostic runs can instrument the tool, but those results cannot independently validate the instrumenter.

## Modules

| Module | Job |
|---|---|
| `scanner.mojo` | Find statements, decisions and loop headers in a source file. |
| `instrument.mojo` | Emit probes around Boolean leaves and decisions. |
| `runtime.mojo` | The probe functions the instrumented code calls. |
| `mcdc.mojo` | Read complete decision vectors from version 2 records. |
| `report.mojo` | Build the report and decide whether it is complete. |
| `build_cli.mojo`, `report_cli.mojo` | The two commands the Makefile runs. |

## Metrics

| Metric | Question |
|---|---|
| Line | Did this statement run? |
| Branch | Did this decision go both ways? A `for` loop counts, including running zero times. Constant-loop proofs can classify an impossible outcome separately while retaining the reachable outcome. |
| Condition | Did each Boolean leaf of a compound decision take both values? |
| MC/DC | Did each operand change the outcome on its own? |

MC/DC is the masking variant. Short-circuit evaluation makes unique-cause MC/DC unreachable for most compound decisions.

### Grouped conditions

The instrumenter preserves `and`, `or`, `not` and their parentheses. It wraps each Boolean leaf of a compound decision once. The leaf indexes follow source order. A skipped leaf emits no record. A `not` operator stays outside its leaf probe, so the probe records the value before negation.

Redundant parentheses and multiline headers do not remove leaf obligations. Calls, indexing, comparisons and conditional expressions remain atomic leaves. The tool does not split logical expressions inside call arguments, indexes or comparison operands. Those expressions supply values to a leaf. A decision with one leaf uses its decision probe without duplicate condition probes.

Before [issue #535](https://github.com/SethKitchen/ThreeMojo/issues/535), the instrumenter split only top-level `and` and `or` operators. An outer group could therefore report both decision outcomes with no leaf-condition or MC/DC records. Historical 100% reports described the old manifest. They did not establish coverage of these hidden leaves.

The baseline audit at `b0222cbcb0c111bfe78cf330d79b757864b40e9f` covered 759 CPU modules. Group recognition increases the condition count from 5760 to 7438. It adds 1678 MC/DC obligations across 609 decisions in 207 modules.

Quote-aware scanning also reveals code after multiline shader strings. The line count rises from 122629 to 122792. The decision count rises from 22221 to 22236. No old manifest entry is removed. These are manifest counts, not passing coverage results. The new obligations need fresh captures from the complete suite set.

`make test-coverage-tool` compares native and rewritten Mojo fixtures. It checks leaf manifests, short-circuit order, call counts, exceptions, and raw and reduced traces. It also verifies that both decision outcomes can pass while leaf coverage fails. It also checks recursion, abandoned evaluations, nested callbacks, repeated loop and `elif` decisions, and concurrent tasks.

## Report columns

The text report separates each field with at least one space. Long module
names and large counts cannot touch the next field. Short fields keep their
padding. Percentages and measured totals do not change.

Do not read the table by fixed character positions. Tools can use the manifest
and probe formats described on this page when they need structured records.

## Rules

- The Makefile's `COVERED` list is every CPU module. `COVERAGE_EXCLUDE` names the GPU modules, `render/gpu.mojo`, `render/gpu_vxgi.mojo` and `extensions/water/gpu.mojo`, because a kernel has no `stderr`.
- `# pragma: no branch` opts one decision out. Use it only when the other outcome is provably unreachable.
- Probes cannot reach compile-time code, and the instrumenter recognizes `def` and `async def` only.
- The tool does not measure itself.

## Limits

Coverage must reach 100% under the measured rules. A badge states this requirement. It does not prove that a revision passed its checks.

Executable trait defaults are measured. Abstract `...` declarations and docstrings are not runtime steps. See [trait defaults and generated names](#trait-defaults-and-generated-names).

Version 2 fixes the ambiguous evaluation boundaries tracked in [issue #385](https://github.com/SethKitchen/ThreeMojo/issues/385). Its supported limits are below. These targeted checks do not establish full repository coverage. The leaf obligations added by issue #535 still require a new complete repository capture. Check the source, test scope and trace limits with each result. A percentage is not an engineering validation certificate.

### Truth-conversion limit

Simple decisions accept any `Boolable` value. Their helper borrows the value and calls `__bool__` exactly once.

Compound decisions keep the native `and`, `or` and `not` operators. Pinned Mojo 1.1.0 selects the truth semantics of `and` and `or` from the operand types:

- **One type.** Mojo converts the left operand. It returns the left operand, or the right operand without a conversion. The result owns the selected operand: Mojo moves a temporary into it. Mojo copies a retained operand into it, or moves the operand at its last use. The enclosing operator or truth test converts the result again. In `a or b or c`, a true `a` is converted three times.
- **Two types without a join.** Mojo converts each evaluated operand to `Bool` once. It does not copy or move the operand.
- **An implicit conversion.** Mojo can join two types into one. For example, `Optional[Int](None) or 0` wraps `0` in an `Optional` and is true.
- **A custom merge.** A type can define `__merge_with__`. Mojo first tests the original left operand, then merges the selected operand. The merge can return `Bool` and change its value or run other source code.

Operands of `Bool`, `SIMD[DType.bool, 1]`, `Int`, `String`, `Optional[T]` and `List[T]` become `Bool` when they are recorded. Their pinned standard-library truth tests read only the value, presence flag or length.

A pure truth test does not make every payload lifecycle safe. An operator that returns an `Optional` can copy or move its selected payload. The operator check also tests these omitted operations.

It keeps move-only values with trivial moves, including values with a custom destructor. For implicitly copyable values, it requires both trivial copying and trivial destruction. Standard `String` and its standard `Optional` wrappers retain the fixed standard-value path. A user-defined wrapper around `String` does not get that exception.

Atomic custom operands directly under `not` use immediate truth observation. Retained values are borrowed; temporaries convert in place. The native `not` remains unchanged. Parentheses preserve this context, but `and` and `or` stop it.

Other admitted custom operands retain the recording-proxy path. This preserves the existing 13 positive expression-tree controls, but does not prove arbitrary identity-sensitive selection:

- A temporary operand moves into a proxy that owns it. The proxy type has no operand origin, so two temporaries of one type give one proxy type. This move is bitwise, so it runs no source code.
- A temporary operand with a user-defined move constructor does not move. The probe converts it once in place, records it and returns its `Bool`. `not` also converts a temporary once at that point, and then destroys it.
- A retained operand whose copy, move and destruction are bitwise is copied into a proxy that owns it. These operations run no source code. Its proxy type is the proxy type of a temporary of the same type, so a one-type operator stays one-type.
- Another retained operand goes into a proxy that borrows it with its origin. Examples are a variable, a field and a conditional expression with two retained arms. `not` converts the borrowed operand once and does not copy it.
- The probe of a right operand also gets the native result type of its operator. If the operand has that type, the probe takes the operand as an owned argument. Mojo then copies a retained operand, or moves it at its last use, at the same point as the native operator. The probe repeats the text of its operator, so an operator text longer than 256 bytes gets the plain probe.
- Each conversion calls the operand's `__bool__` once. The first conversion records the condition. A later conversion of the same selected operand with a different truth records that hit too, and marks the condition `?`.

Each `and` and `or` operator also gets an unevaluated `type_of` check. It compares the original subexpression with the instrumented one when Mojo instantiates the function, also in generic code. The check fails compilation when the probes would change the semantics of the operator.

These operands fail compilation with a coverage diagnostic:

- A one-type operator whose left operand is retained, and whose copy, move or destruction runs source code. Examples are `copied or other`, `copied or copied` and `copied or Copied(False)`. So is such a right operand of an operator text longer than 256 bytes.
- A one-type operator over a type with a user-defined move constructor, for example `Moving(False) or Moving(True)`.
- An operator that joins two operand types through an implicit conversion. An `Optional` wrap of a pure operand also fails, because it replaces the value with its presence. This includes a wrap from an empty `Optional[T]` into a present `Optional[Optional[T]]`.
- A mixed-type operator with a custom operand and a native `Bool` result. This includes a custom operand combined with `Bool`, for example `copied or flag` and `Moving(False) or flag`. The type check cannot distinguish Boolean fallback from a custom merge that also returns `Bool`. Independently declared generic parameters can also select Boolean fallback when both bind to the same concrete type. Such equal bindings do not prove a same-type join; the same refusal applies.
- An `Optional`-valued operator whose selected move, copy or extra destructor is not covered by the lifecycle checks. This includes custom payload methods and unlisted wrappers with nontrivial operations. The check lacks operand ownership information, so it can conservatively refuse a temporary implicitly copyable payload even when that expression does not copy it. Nested `Optional` payloads are subject to the same check.

A mixed-type operator of standard operands stays supported. Standard types have no custom merge. An example is a retained `Optional` with a custom payload and a `Bool`. A custom operand in a mixed-type operator is supported when `not` converts it first, for example `not copied or flag`.

The mixed-type restriction closes a case that previously compiled but changed execution. Two custom types can each merge to `Bool` and invert their stored truth. Native `and` and `or` call the selected merge. The probes omitted it and used Boolean fallback. A pinned native control shows opposite final outcomes for both operators across all four truth assignments.

The Optional restriction closes a separate case that also compiled but changed execution. In the pinned control, retained selected values lose a custom copy and its destructor. Temporary selected values lose a custom move. The final Boolean outcomes still match, so an outcome-only test cannot detect the defect. A direct `List` transfer moves its storage owner, not its elements, and does not require this restriction. Unary `not` and mixed Boolean fallback do not select an Optional value and remain outside this check.

Do not omit the source or its obligations to bypass these limits.

#### Why the one-type refusals are necessary

The native operator converts the left operand first. Then it copies or moves the operand only if it selects the operand. The current proxy path cannot reproduce every such case:

- A probe can see a conversion only through a proxy. Mojo makes the proxy when it evaluates the operand, before the conversion.
- An owning proxy must move or copy the operand into itself at that time. This runs the source code before the conversion, and also when the operator does not select the operand.
- A borrowing proxy cannot move the operand out later. The caller still owns it and destroys it.
- Mojo copies a retained operand only if a later statement uses it. Otherwise it moves the operand. Two programs can have the same decision line and differ only in a later statement. The probes of that line are the same in both programs. They cannot make a copy in one program and a move in the other.

A right operand avoids the left-selection timing problem, but an additional proxy move can still change its identity. The native operator selects it when it evaluates it, before any conversion. An owned argument gets the same copy or move at the same point. A bitwise copy or move runs no source code, but can still change the identity observed by `__bool__`. The existing owning-proxy selection path therefore has a known identity-sensitive limitation.

#### Known identity-sensitive selection limitation

The atomic-negation repair does not repair a custom object selected by `and` or `or`. An address-sensitive temporary under `not (a or b)` still exposes the owning-proxy move. Both retained-copy and temporary-move failure witnesses remain recorded. This is a known defect, not a proof that Mojo cannot support the behavior.

Restoring the existing positive controls does not complete arbitrary custom truth support in issue #560. A type-preserving selection lowering is being investigated separately. It must preserve native copy, move, last-use and destructor behavior before admission. The full condition denominator and existing mixed-merge refusals remain unchanged.

#### Why mixed custom operators are refused

A mixed-type operator with a `Bool` result can use Boolean fallback or a custom merge. The two need different probes. Boolean fallback converts each evaluated operand once. A merge converts only the left operand, and then calls the merge of the selected operand. Pinned Mojo 1.1.0 gives no way to tell the two apart at compile time:

- Both give the same native result type, `Bool`. The `type_of` check sees only types.
- Generic code can call only the methods of its trait bounds. No standard trait declares `__merge_with__`. A generic helper that calls it does not compile: "'T' value has no attribute '__merge_with__'". This is also true in a `where` clause, so an overload cannot test for a merge.
- Trait conformance is nominal. A type with a matching `__merge_with__` does not conform to a trait that declares it, unless it names the trait. `downcast` to such a trait fails: "does not have witness table".
- The pinned reflection API reports names and fields, not methods.
- A probe type cannot stand in for the other operand. A merge can have a `where` clause on its `other_type` parameter. Then it can apply to the real operand type and not to a probe type.
- A conditional expression joins its arms with the same rules, but it fails compilation when there is no join. It cannot tell a test that both cases compile.

So a proxy cannot forward a merge, and the operator check cannot detect one. The check refuses each mixed-type operator with a custom operand instead of a false vector.

#### Why implicit-conversion joins are refused

The native operator converts the left operand in its own type. Then it converts the selected operand to the joined type and moves it into the result. The enclosing operator converts the joined value.

To keep this order, a probe must run the native implicit conversion at that point. No probe can do this in pinned Mojo 1.1.0:

- Only code with concrete types can call an implicit conversion. A generic function that returns a generic `L` value as a generic `J` does not compile: "cannot implicitly convert 'L' value to 'J'". The runtime helpers are generic, so they cannot convert.
- The instrumenter reads source text without types. It writes the same probe text for a join and for every other operator. That text must select its behavior through overloads.
- An overload whose argument type is the joined type needs an implicit conversion. The overload rules select an exact generic overload before it, and every probe needs exact generic overloads for its other operands. Inference also does not convert: an overload that infers the joined type from a second argument does not accept the operand.
- A text that always converts, such as a conditional expression whose other arm has the result type, changes other operators. It copies a retained operand of a two-type operator, and it does not compile when there is no conversion between the two types.
- A lifted left operand also needs the conversion only after its own conversion and only on selection. The only deferred expressions are `and`, `or` and a conditional expression, and these cannot convert, for the reasons above.

The operator check therefore refuses each join, instead of a false vector. This includes an `Optional` wrap of a pure operand, which replaces the value with its presence.

#### Retry the refused forms on a new Mojo

The refused forms are limits of pinned Mojo 1.1.0. They are not limits of the coverage design. When the toolchain pin moves, test each form again. Admit a form only if the native and instrumented controls agree. These language features can remove a refusal:

- A way to copy or move an operand after its truth test, and only on selection. This removes the one-type refusals for a retained left operand and for a type with a user-defined move constructor.
- A generic implicit conversion, or reflection that can call a conversion between two generic types. This removes the refusal of implicit-conversion joins.
- A compile-time test for an applicable `__merge_with__`, such as reflection of methods, structural conformance or a standard trait for merges. The proxies can then forward a merge, or the operator check can admit Boolean fallback only when no merge applies. This removes the refusal of mixed-type operators with a custom operand.
- Reflection that names the origin parameters of a type. This can make the operator check simpler.

Keep each refusal until its native control passes. Do not admit a form because it compiles.

The pinned reflection API names types without their origin parameters. A same-type check therefore also needs a proxy as the instrumented result. Different origins produce distinct proxy types. An operator that therefore selects mixed-type semantics for custom operands is refused too.

[Issue #556](https://github.com/SethKitchen/ThreeMojo/issues/556) fixes standard-library truth conversion. Native and instrumented checks cover optional, string, list and integer operands, including throwing operand expressions and short-circuit order.

[Issue #560](https://github.com/SethKitchen/ThreeMojo/issues/560) adds custom compound operands. An independent Python model of the native semantics supplies the expected results for 43 decision trees. The trees combine one-type and two-type operators, `not`, temporary and retained operands, `Bool` operands and conditional-expression operands. The operand types include these:

- A type whose copy logs itself. It is a retained operand of a two-type operator, and a retained right operand of a one-type operator.
- A type with a user-defined move constructor that logs itself.
- A type with a bitwise copy, also as both operands of one retained variable.

Each tree runs natively with 16 truth assignments and 5 throwing positions, with stable truth tests and with truth tests that change at each conversion. The model also states which trees the operator check admits.

Thirteen supported trees also run with instrumentation. The check compares the exact sequence of operand creation, conversion and destruction, the condition and decision hits, and the vectors. The reducer and the report must refuse each `?` vector. The other 30 trees have a two-type custom operator. Each one must fail instrumented compilation with the coverage diagnostic.

A second copy of the trees uses caller-scope names that collide with the instrumenter. Retained operands are named `List`, `Int`, `Bool` and `_cov_eval_finish`. The helpers are named `_cov_eval_leaf`, `_cov_eval_node`, `_cov_eval_buffer`, `_cov_eval_truth`, `_cov_eval_right` and `_cov_branch`. The state is named `_cov_eval_state0` and `_cov_hit`. The check requires that each generated alias and buffer name is absent from the source. The same model must then agree with each log, hit and vector of the supported trees.

More supported controls compare `while` and `elif` decisions, recursion and eight concurrent tasks. They include retained move-only and copyable operands and non-movable temporaries under `not`, one-parameter generic calls instantiated with two concrete types, and pure one-type operators. A retained right operand of a one-type operator is copied while a later statement uses it, and moved at its last use. A generic function converts a borrowed retained copyable operand with `not` in one instantiation and has two `Bool` operands in the other.

The original mixed-custom controls remain native-success and instrumented-refusal tests. They include the mixed generic instantiation and retained lifetime cases. The exact previously accepted control with two independent generic parameters also remains a native-success/refusal fixture, including equal concrete bindings. A separate one-parameter fixture checks 64 native/model outputs and 328 ordered line, condition, decision and vector records, including changing truth.

Twenty more programs compile natively and must fail with the coverage diagnostic. Four have custom merges that return `Bool`, and their native logs must agree with an independent model. In two of them, both operand types merge. In the other two, the merge has a `where` clause that accepts only `Bool`. Mojo calls it in `Gated(x) or flag` and uses Boolean fallback in `Gated(x) or Plain(y)`. Both forms are refused.

Four programs must also print the native copy or move of the selected operand. One of these is a retained `Optional` whose element copy logs itself. Before this change, such an operand became `Bool` and its native copy was lost. Four cover nested `Optional` operands in both orders, with `and` and `or`, all empty and present combinations, and construction logs that check short-circuit order.

Destructor-order controls compare retained and temporary optional/list values with move-only elements. Shared drop-state observations cover later operands, grouped same-type and mixed-type decisions, and the final body.

Additional Optional controls separate observable copy, move and destructor methods. Native successful programs must receive the specific coverage diagnostic after instrumentation. Supported controls retain pure payloads, Boolean fallback, unary `not`, lists with custom elements and standard strings. They compare the original and instrumented output and preserve the complete source manifest.

### Evaluation protocol

Each function invocation that has a compound decision owns one private operand buffer. Other functions have no buffer. The new buffer and helper names use a prefix absent from the source. The buffer factory also avoids unqualified caller-scope `List` and `Int` names.

A begin operation clears the buffer before each reached `if`, `elif` or `while` evaluation. It does not change the original operand order or short-circuit behavior. Each completed pure leaf writes its condition hit. A proxy writes its condition hit when Mojo first converts it. The runtime accepts standard-library truth-testable operands without requiring implicit argument conversion. All hit records use `COVLINE`, including payloads with a condition index and a `T` or `F` outcome.

A completed decision writes its outcome hit and one `COVEVAL2:<decision>:<T|F>:<vector>;` record. Each vector character is `T`, `F`, `-` for an unevaluated leaf, or `?` for a leaf whose repeated truth tests disagree. The parser and the reducer refuse a `?` vector, because it cannot certify MC/DC. The record ends with a newline.

Recursive calls and concurrent calls have separate local buffers. An exception before completion writes no evaluation record. The observed condition hits remain available. A later begin clears any abandoned operands.

A nested call that catches an exception cannot overwrite its caller's buffer. Normal function lifetime releases the buffer. The parser and reducer do not reconstruct vectors from pending condition records.

Each record uses one successful POSIX `write` call. The complete UTF-8 record, including its terminator and newline, must fit in 512 bytes. [POSIX write](https://pubs.opengroup.org/onlinepubs/9690949599/functions/write.html) guarantees atomic pipe records through `PIPE_BUF`. The [portable minimum](https://man7.org/linux/man-pages/man7/pipe.7.html) is 512 bytes. Concurrent probe writers cannot split a record.

Module IDs must fit in 480 UTF-8 bytes. This reserves enough bytes for line numbers and outcome suffixes. The instrumenter refuses an oversized module ID or decision vector. It does not remove the obligation.

A `write` interrupted before any byte is sent returns `-1` with `EINTR`. The runtime retries the complete record only for that result. It terminates on an oversized record, any other error, or a short write, including a zero-byte write. The parser rejects incomplete vector records. These checks prevent a partial capture from passing as a shorter complete vector.

The runtime uses the C library already used by the project. The pinned private `std.sys._libc_errno` adapter reads thread-local `errno` through `__errno_location` on Linux and `__error` on macOS. The native protocol checks inject repeated `EINTR` and other write results, and interrupt a blocked pipe with a real signal. It requires no helper library, global counter, thread-local key or new access permission. Linux x86-64 tests exercise overlapping task calls and concurrent 512-byte records through actual pipes. macOS and Linux aarch64 use the same POSIX guarantee, but require their own native execution checks.

All generated helper aliases and local names now avoid source identifiers. See [trait defaults and generated names](#trait-defaults-and-generated-names).

Old `COVBRANCH` condition records cannot distinguish recursion from an abandoned evaluation. The parser and reducer reject these ambiguous compound records and require a new capture. Old decision-only records remain readable, without condition evidence. `COVLINE` condition hits remain readable, but do not certify MC/DC on their own.

### Trait defaults and generated names

Trait scopes can contain abstract declarations and executable default methods. The scanner skips an abstract `...` body, including a trailing comment. It measures statements in a default method and preserves its docstring. Each invocation with compound decisions receives its own buffer. Nested functions have separate buffers, as they do outside traits.

The complete 759-module CPU manifest comparison against `e488e4ffc23cf85d006d5a5d111968de64f6cacb` adds 16 line obligations. Eleven are `NodeSource` default returns in `materials/nodes.mojo`. Five are `RenderHooks` default `pass` statements in `renderers/renderer.mojo`. No previous entry is removed.

No branch, condition or MC/DC obligation changes in these production sources. The line total is now 122808. These manifest counts do not certify full repository coverage.

The instrumenter checks the full source text before it chooses any injected name. Hit and branch aliases, evaluation helper and buffer names, and loop-counter prefixes must be absent from that text. A collision adds underscores until the name is unused. This includes names in nested functions, parameters and generic callbacks. A loop counter also includes its original source line number.

These names do not change probe IDs or manifest entries. The imported buffer factory avoids caller-scope `List` and `Int` names. The operator checks also use `type_of`. Mojo reserves that name, so the source cannot define another `type_of`. The proxy types are inferred results, and the instrumented source never names them.

`make test-coverage-tool` checks exact inherited-default line, branch, condition and MC/DC entries. It also checks native versus instrumented output, full default-method probe streams, recursive defaults, exceptions, nested callbacks and collisions with loop line numbers. `tests/test_trait_defaults.mojo` calls all eleven defaults through `ProgramSource` and checks inherited values through the node interpreter. The render-hook suite checks sun and point-light shadows with inherited `NoHooks` defaults.

### Loop body indentation

The loop rewrite uses the actual indentation of the first body statement. Blank lines and comments do not set that indentation. Multiline headers and literals retain their original probe line IDs.

Physical lines can end with LF, CRLF or CR. The rewrite keeps literal line-ending bytes and tabs. A missing final newline does not change source identities. This fixes [issue #544](https://github.com/SethKitchen/ThreeMojo/issues/544).

A loop entry probe reports a nonempty sequence before a body can return or raise. For a loop with an `else` clause, the final probe runs at the start of that clause. This preserves the empty outcome when the clause returns or raises. A `break` skips the clause; the entry probe has already reported the nonempty outcome.

The instrumenter rejects inline loop and loop-else bodies. Put each body on a separate indented line. It also rejects a complete loop header without an indented body.

`make test-coverage-tool` compares native and instrumented loops at widths of one, two, three, four and eight spaces, and with mixed block widths. The checks pin line and branch identities and exact loop outcomes. They cover comments, multiline headers and literals, nested loops, `break`, `continue`, `return`, `for`-`else` and exceptions. An `else` header can have spaces or tabs before its colon. This correction leaves the rewrites and manifests of the 761 measured repository modules byte-identical.

### Constant-loop outcome proofs

A loop's True probe still means its body ran. Its False probe still means its sequence was empty. Normal exhaustion of a nonempty loop does not supply a False hit. All runtime probes and the original `manifest.txt` remain unchanged.

Before loading or compiling the producer, the official workflow creates `generation-inputs.json`. This binds the maintained input inventory, selected modules, producer command/compiler and flags. It invalidates any previous ready index. `build_cli` pairs each exact source string passed to the unchanged instrumenter with the generated bytes and that module's original manifest fragment. A length-delimited `.cov-origin` record holds this pair. It invalidates `origins.ready` before regeneration and publishes the exact checkpoint bytes, complete source index and original manifest only after all writes succeed.

The verifier rejects missing, duplicate, extra, truncated, mixed-module or trailing records. The checkpoint, current source/tools/compiler, stage, fragments and complete manifest must match the same generation. Editing the producer after generation requires regeneration before sealing.

These records are a trusted producer contract, not independent authentication of arbitrary user-forged files or an arbitrary precompiled producer. Direct diagnostic uses of `build_cli` without a checkpoint retain the original unmasked manifest but cannot be sealed for feasibility reporting.

After instrumentation and copy-through, `tools/coverage_loop_proofs.py` writes `loop-proofs.json`. Its literal inference recognizes a conservative subset in nongeneric top-level function bodies. Direct builtin `range` calls can have one or two nonnegative integer literals no larger than 2^31-1. Direct builtin list literals cannot use expansion or comprehension.

The integer limit keeps endpoint and cardinality arithmetic representable on supported CPU targets. Literal inference does not fold named constants or expressions, inspect producer invariants, or infer positive dynamic lengths. For literal inference, methods, nested functions, generic functions, unresolved syntax, and ambiguous bindings retain both requirements.

A module-wide binding check rejects range inference when any code identifier named `range` appears outside a verified for-iterable callee position. Wildcard imports reject inference. A code identifier named `List` conservatively rejects direct-list inference. Strings and comments do not introduce bindings. No module names, paths, or site-specific exceptions participate in literal inference.

A separate named registry contains fourteen reviewed nonempty-loop proofs. It binds complete module bytes and required producer dependencies. These hashes are fixed review inputs. Source mismatches retain both original outcomes. This registry does not infer other dynamic, generic, or method loops.

- Spiral moments bind six runtime literal ranges and one guarded piece-count range. Compile-time loops are not masked.
- Sample dispatch has a checked count of one or two. Its minimum cardinality is one.
- Lane refinement forwards its axis count to a callee with a compile-time assertion. The permitted count is one through three.
- Stored blend error checks a literal list of four Float64 values. Its cardinality is exactly four.
- Hair upload uses literal ranges for two endpoints and three color channels. Their cardinalities are exactly two and three.
- The speed-number underflow scan iterates a guarded nonempty owned string.
- Retained R-tree frontiers reach nonempty nodes from public insertion. Empty trees keep their original outcomes. The rule binds every reviewed frontier caller and rejects new callers.

All fourteen proofs keep True mandatory. Any observed False contradicts the proof and fails reporting. Literal proofs report exact cardinalities. Reviewed range and iterator proofs report a minimum cardinality of one. Original potential and remaining required totals stay separate. Other line, branch, condition, and MC/DC requirements stay unchanged.

A proved positive cardinality keeps True required and classifies False as impossible. A proved zero cardinality keeps False required and classifies True as impossible. A missing reachable hit still fails. Body line obligations remain, including unreachable body lines in a literal-empty loop. This is not general unreachable-code removal.

The receipt uses the repository's maintained cache-input inventory, including native C fixtures, imported Python tooling and assets. It binds both the original closure and staged executable inputs; a custom `COV_DIR` is excluded by its declared identity. Source and build roots are the only path substitutions. Generation identity, the original manifest, Python/Mojo/native-C compiler invocation identities and executable hashes, flags and potential/required totals are bound. Native fixture and hit-helper cache keys also include the C compiler bytes, so a replacement with unchanged `--version` invalidates old objects. The source identities of the executing proof, inventory and report implementations are checked too.

Each successful capture receives a `*.txt.gz.proof.json` receipt binding those identities, compressed bytes and stdout. Before launch, its actual command must match the sealed wrapper/profile, staged suite, compiler invocation, cache location and capture flags. The maintained capture flags are `run -I <build> <staged suite>`; they are checked separately from instrumentation flags.

Filenames must identify the same suite. The command stored in the receipt is its validated canonical form, not an unchecked command log. Inputs are checked before and after execution, and a failed replacement attempt removes its old success receipt before preflight. Shard placement and the supported raw/AOT transport choice do not change loop meanings or select different proofs.

The official `coverage_io.py report` path independently rederives proofs, validates all source/tool/capture bindings, and creates a temporary manifest. Its final check must match the exact initial receipt; concurrent source changes followed by a successful reseal cannot return an old success. A `P constant-loops-v2 <sha256>` record identifies the validated proof receipt.

Each affected `B module line` becomes an `R` outcome record. Literal records use `literal-range` or `literal-list` and their exact cardinality. Reviewed range records use `reviewed-nonempty-range`. Reviewed byte and child iterators use `reviewed-nonempty-iterator`. Both reasons require True with minimum cardinality one. All other entries remain unchanged.

The native reporter rejects malformed masks, duplicate/compound-decision conflicts, and any actual runtime probe contradicting a proof. It prints each impossible classification and the original potential, remaining required, and impossible totals. No hit is synthesized.

The native reporter on an original manifest remains conservative. Its parser checks derived record structure and runtime contradictions; the official Python wrapper owns source and tool identity validation. Do not use an arbitrary hand-written masked manifest as an independently validated coverage result. Stale sources, tool versions, manifests, proof metadata, or capture receipts require regeneration/recapture, not weaker validation.

The official Mojo wheel launcher receives a relocatable identity. Its absolute Python shebang is normalized only after the interpreter is validated. The exact launcher body, interpreter bytes and capabilities, wheel metadata, compiler, linker, runtime libraries, Python package code and Mojo import payload stay content-bound. A different checkout or venv directory can therefore match without making different compiler bytes equivalent.

The actual interpreter prefix, isolated site inventory and resolved Mojo entry point must match the bound venv. System site packages, .pth hooks, customizers, package initialization hooks and launcher-directory import shadows are rejected. Compiler environment overrides that redirect the wheel driver or import tree are rejected. Unrecognized command wrappers keep their exact byte identity; they do not gain an inferred identity for a downstream compiler. Native qualification through such a wrapper must bind that downstream compiler separately. The maintained hosted jobs invoke the official wheel launcher directly.

Coverage capture and report jobs use the same digest-pinned Python 3.12.14 Bookworm image. This fixes their Python and native compiler provisioning independently of hosted runner-image updates. The suite inventory, eight shards, capture deadline, report deadline and floating-point compiler flags stay unchanged. Xvfb and its X11 runtime remain installed for the native window suite. Actual hosted execution is still required to qualify this setup.

Proof-related source changes participate in the existing repository cache key, and the key explicitly includes the proof schema. Native binary and exact-hit record caches retain their existing content/protocol identities because runtime instrumentation is unchanged. Capture receipts prevent older evidence from silently inheriting a new proof identity.

Compiler-free controls run under normal Python and `python -O`. Native qualification checks actual source-to-origin-to-stage byte correspondence for LF, CRLF, CR and UTF-8. It checks failed generation, alias drift, original/instrumented output and exact loop records. It also checks a missing dynamic-empty outcome and an actual contradictory entry-probe mutant. It also captures one real staged suite through the maintained wrapper and reports its complete original manifest through the proof-aware boundary.

Its separate branch-only reporter projections are explicit unit diagnostics; they do not replace the original manifest or claim a production gate. `make test-coverage-tool` includes these checks. Historical percentages refer to their original denominators; impossible classifications are denominator changes, not newly executed tests.

### Platform-specific witnesses

Coverage captures run only on Linux x86-64. Some obligations need a floating-point state that only x86 has. The macOS arm64 runner runs those suites as correctness tests, and its results do not enter a coverage report.

The junction endpoint refusal in `extensions/carla/junction_bounds.mojo` is one such obligation (issue #721). Its last-endpoint witness needs x86 denormals-are-zero. The test fixture `tools/fixtures/carla_sum2_fp_state.c` exposes seven modes on x86 and five on Arm.

On x86, `tests/test_carla_junction_endpoint_refusals.mojo` runs both last-endpoint vectors. On Arm, it runs the first-endpoint control and prints `LAST_DAZ_CAPABILITY_UNAVAILABLE`. The suite fails on any other mode count. The Arm run claims no last-endpoint witness.

The obligations that issue #721 lists, and the tests that witness them, are in [the #721 coverage record](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/full-audit-721-coverage.md).

### The capture grows with every statement run

Each statement that runs writes one record, so the capture grows with the work a suite does. A PMREM blur reads its source about half a million times, and each read ran about 150 statements. That made `test_pmrem` write 14 GB and run for six and a half minutes.

Keep the innermost helpers short for this reason:

- A small value type uses `@fieldwise_init`. Its constructor then has no body and writes no record. `FloatColor` and `Vector3` do this.
- A helper that runs per texel or per tap is one statement where the code stays clear. `Vector3.cross` and the `CLAMP` case of `wrap_index` are.
- Work that is the same for every texel is done once, outside the loop. The PMREM blur finds its weights, sines, cosines and copy position once per pass.

See [Benchmarks](Benchmarks#pmrem-and-the-coverage-run) for the numbers.

## Compiler hang

A `Bool` loop flag read after nested loops hangs the Mojo compiler. The instrumenter emits an `Int` counter instead. See [The Mojo compiler hang](The-Mojo-compiler-hang).

### Compile-time name tests

The operator check must not call `startswith` or `find` at compile time. Pinned Mojo 1.1.0 can deadlock a build that evaluates these methods at compile time. The compiler then waits on a semaphore and uses no CPU. The build does not fail and does not stop. The capture reports "waiting for probes (compile/startup)" until the shard budget stops it.

The instrumented `materials/nodes.mojo` caused this deadlock in `test_glsl614_reference_refusals`. One operator in that module, `flag or mask.reduce_or()`, joins a `Bool` and a `SIMD[DType.bool, 1]`. Its check got to the reflected-name tests and their `startswith` calls. With one compiler thread, the build did not stop in 900 seconds. Without that one check, the build took 45 seconds.

The deadlock depends on the build. A different instrumented form of the same module can build, so a passing build does not prove that a helper is safe.

The runtime obeys these rules:

- `node` answers the fixed scalar types by type identity before it reflects names. These types are `Bool`, `SIMD[DType.bool, 1]`, `Int` and `String`. The pure-type branch gives the same answer for them.
- `_starts` and `_bracket` compare bytes. They give the results of `startswith` and `find`. The compile-time helpers use them, not the methods.
- The `Bool` identity check stays first in `node`.

`make test-coverage-tool` checks these rules. `check_coverage_grouping.py` fails if a compile-time helper of `node` calls `startswith` or `find`. It compares `_starts` and `_bracket` with `startswith` and `find` on 272 name pairs. It also builds a fixture of mixed pure operators with one compiler thread. The build must stop in 120 seconds, and the native and instrumented output must agree.

## Capture storage

The Makefile reduces each suite's stderr as it arrives, and compresses what is left. The report reads two things: the set of distinct probe payloads, and each decision's distinct MC/DC evaluations. A probe in a loop repeats both millions of times. `tools/coverage_io.py`'s `Reducer` keeps each payload once, as a `COVLINE:` record, and each distinct complete `COVEVAL2` record once.

The report receives evaluations in first-completion order. The reducer has no pending evaluation state. Its storage depends on distinct hits and vectors, not the number of repeated or abandoned evaluations.

`test_rasterizer` writes 9.9 million records. The reduced capture holds 3,477 lines, and the report reads it in 0.02 s instead of 8 s, with an identical result. The reduction runs on the capture runners, in parallel, and the report reads the captures on one core.

The reporter reads the captures through named pipes, one suite at a time. Other output from a suite passes through unchanged, for the summary of a failed suite.

## Capture scheduling and progress

CPU test groups use imported source size. Coverage groups use `tools/coverage_shard.mojo` and `tools/coverage_costs.json`. Probe output can take much longer than compilation. The scheduler puts the longest estimated capture in the group with the lowest total cost. Each group starts its longest captures first.

Ties use the suite path and group number. Every affected suite stays in exactly one group. CI uses eight groups and a budget of 9000 seconds a group. The budget is a hang detector, not a target. Hosted runners differ: one took a quarter longer than another on the same group.

The current profile uses attempt 1 of [CI run 37725421233](https://github.com/SethKitchen/ThreeMojo/actions/runs/37725421233), from October 8, 2026. Its source commit is `6c0391ea03bfe4ec28b3ae23e497f51e1ba43806`; its merge checkout is `fdd972921b9f179119815acd4e10f1486786d9f8`. It used Mojo `1.1.0` (`8189361e`), the `aot-hits` profile, eight groups and four capture workers per runner. The profile contains 717 successful capture durations and one explicit scheduling estimate.

The recorder-world capture stopped at the group deadline after 8281.5 seconds. It did not complete. Its profile value is a lower bound used to start that expensive suite first, not a measured successful duration or a completion forecast. The JSON labels this estimate separately.

Its previous successful capture in [CI run 37638046555](https://github.com/SethKitchen/ThreeMojo/actions/runs/37638046555), at commit `b96ba07ecd0ccba732f5e5d81a4e3bb2fe62b2bc`, took 6622.2 seconds. Different source versions and runner contention limit direct timing comparisons. New complete captures must verify that the current work fits the unchanged budget.

The previous profile used [CI run 37301265769](https://github.com/SethKitchen/ThreeMojo/actions/runs/37301265769), from October 5, 2026, at commit `c115c0f51f601638bc7fc22dae04d70e7382ded3`.

The first profile used [CI run 36903778725](https://github.com/SethKitchen/ThreeMojo/actions/runs/36903778725), from October 1, 2026. Its costs are estimates from artifact completion times, at two-second precision.

A new suite gets a source-size estimate. The scheduler uses the median measured seconds per imported byte among the selected known suites. If none are known, it uses one second per 10000 bytes. The estimate is at least one second.

Missing profile entries never remove a suite. Invalid costs fail the scheduling command. Timing data changes only placement and order, never coverage requirements or test validation.

Each capture prints its start, first probe, elapsed time and exit status. A running capture prints progress once per minute. Before the first probe, compilation or startup can still be in progress. Once probes arrive, the log identifies runtime work and gives the record count.

Output is flushed at each update. Failed CI captures upload separate diagnostic artifacts. The report job does not use those artifacts as completed captures.

Refresh the profile when completed capture logs show material changes. Use the per-suite completion times from those logs. Keep the source run, commit, compiler and worker count with the profile. A simulation from the initial estimates gives a longest group of 4554 seconds with longest-first scheduling. This is an estimate, not a guarantee for another runner.
