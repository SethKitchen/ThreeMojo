"""Recover the exact qualified prototype from retained generation calls.
No compiler, formatter, test, or qualification is invoked.
"""
from pathlib import Path
import sys,re,hashlib,json
P=Path(__file__).parent
BASE_SHA='370dee032a5e126e727c46d0ceb7103359f1ad7fba8151e341b594df0c7d0e30'
FINAL_SHA='13ae6d4658458a7d243597428eee762f9bbc40f8fe3507a47beac9ebd4ac1737'
base=Path(sys.argv[1]); s=base.read_text()
assert hashlib.sha256(s.encode()).hexdigest()==BASE_SHA
start=s.index('            # A clamped singleton endpoint can have a different jet from\n',s.index('def _run_lane_search('))
end=s.index('\n        if task[2] >= max_depth:',start)+1
old=s[start:end]
(P/'ORIGINAL-PHASE.txt').write_text(old)
block='\n'.join(line[8:] for line in old.splitlines())+'\n'
for bound in ['fast_lower','natural','tightened_lower','lower']:
    pat=r'(if '+bound+r' > best_upper:\n)([ ]+)continue'
    block,n=re.subn(pat,lambda m:m[1]+m[2]+'return _LaneBoundProposal(_LaneBoundDiscard('+bound+', cell))',block)
    assert n==1,(bound,n)
for bound in ['fast_lower','natural','tightened_lower','lower']:
    pat=r'(?m)^( +)closed\.add\(\n(?:.*\n)*?\1\)\n\1continue'
    match=re.search(pat,block)
    assert match and bound in match[0]
    support='support' if bound=='lower' else 'cell'
    block=block[:match.start()]+match[1]+f'return _LaneBoundProposal(_LaneBoundClose({bound}, {support}))'+block[match.end():]
m=re.search(r'(?m)^( +)if support.low > lo or support.high < hi:\n[\s\S]+$',block);assert m
block=block[:m.start()]+m[1]+'if support.low > lo or support.high < hi:\n'+m[1]+'    return _LaneBoundProposal(_LaneBoundContract(lower, support))\n'
block=block.replace('certificate.terms','terms').replace('certificate.nodes','nodes')
block=block.replace('            if grouped:\n','            var point_domain: Tuple[_Jet, _Jet, _Jet]\n            if grouped:\n')
for oldname,newname in {'section':'context.section','lane':'context.lane','low':'context.root.low','high':'context.root.high','location':'context.location','spiral_proof':'context.spiral_proof','frozen':'context.frozen','external_witness':'context.external_witness','cached_fast':'context.cached_fast','cached_expansion':'context.cached_expansion','lo':'cell.low','hi':'cell.high','best_upper':'policy.upper','scale':'policy.scale','tolerance':'policy.tolerance','goal':'policy.goal','work':'whole_work'}.items():
    lines=[]
    for line in block.splitlines():
        if line.lstrip().startswith('#') or '"' in line:lines.append(line);continue
        lines.append(re.sub(r'(?<![.\w])'+oldname+r'\b',newname,line))
    block='\n'.join(lines)+'\n'
block+='    return None\n'
types='''@fieldwise_init
struct _LaneExpansionContext(Copyable, Movable):
    # One search invocation only. The Road argument must remain unchanged.
    # Exact station/scale words are meaningful only for this owner and query.
    var section: Int
    var lane: Int
    var root: _Interval
    var location: Vector3
    var spiral_proof: Optional[_SpiralDomainProof]
    var frozen: Optional[_RoundedArc]
    var external_witness: Optional[Array[Float64, 3]]
    var cached_fast: Optional[Tuple[UInt64, UInt64, _Jet]]
    var cached_expansion: Optional[Tuple[UInt64, UInt64, _Jet]]


@fieldwise_init
struct _LaneBoundPolicy(ImplicitlyCopyable):
    # Already-computed stopping criteria for this cell and incumbent.
    var upper: Float64
    var scale: Float64
    var tolerance: Float64
    var goal: Optional[_LaneExclusionGoal]


@fieldwise_init
struct _LaneBoundDiscard(ImplicitlyCopyable):
    var lower: Float64
    var support: _Interval


@fieldwise_init
struct _LaneBoundClose(ImplicitlyCopyable):
    var lower: Float64
    var support: _Interval


@fieldwise_init
struct _LaneBoundContract(ImplicitlyCopyable):
    var lower: Float64
    var support: _Interval


# Named alternatives carry the exact bound/support from their decision site.
# No numeric tag protocol or re-evaluation of acceptance in the caller.
comptime _LaneBoundProposal = Variant[
    _LaneBoundDiscard, _LaneBoundClose, _LaneBoundContract
]


def _try_lane_center_bound(
    road: Road,
    mut context: _LaneExpansionContext,
    cell: _Interval,
    best: Float64,
    var domain: _Jet,
    var natural: Float64,
    whole_work: Int,
    policy: _LaneBoundPolicy,
    mut nodes: Int,
    mut terms: Int,
    max_nodes: Int,
    max_terms: Int,
) raises -> Optional[_LaneBoundProposal]:
    # The caller supplies a real incumbent and the already-paid whole-cell
    # enclosure. An unknown enclosure is valid. This optional phase owns no
    # traversal state. None retains all work/cache effects of an inconclusive
    # admitted attempt; count refusal returns before either kind of effect.
'''
helper=types+block+'\n\n'
caller='''            var proposal = _try_lane_center_bound(
                road,
                expansion_context,
                _Interval(lo, hi),
                best,
                domain,
                natural,
                work,
                _LaneBoundPolicy(best_upper, scale, tolerance, goal),
                certificate.nodes,
                certificate.terms,
                max_nodes,
                max_terms,
            )
            if proposal:
                ref bound = proposal.value()
                if bound.isa[_LaneBoundDiscard]():
                    continue
                if bound.isa[_LaneBoundClose]():
                    var close = bound[_LaneBoundClose]
                    closed.add(
                        _ClosedInterval(
                            close.support.low,
                            close.support.high,
                            task[2],
                            close.lower,
                            scale,
                        )
                    )
                    continue
                var support = bound[_LaneBoundContract].support
                if task[2] >= max_depth:
                    raise Error(
                        "Lane refinement exhausted its numerical accuracy"
                        " limit"
                    )
                pending.append((support.low, support.high, task[2] + 1))
                continue
'''
s=s[:start]+caller+s[end:]
s=s.replace('    var cached_fast: Optional[Tuple[UInt64, UInt64, _Jet]] = None\n    var cached_expansion: Optional[Tuple[UInt64, UInt64, _Jet]] = None\n','',1)
s=s.replace('    while len(pending) > 0 or closed.needs_validation():','''    var expansion_context = _LaneExpansionContext(
        section,
        lane,
        _Interval(low, high),
        location,
        spiral_proof,
        frozen,
        external_witness.copy(),
        None,
        None,
    )
    while len(pending) > 0 or closed.needs_validation():''',1)
s=s.replace('def _run_lane_search(',helper+'def _run_lane_search(',1)
s=s.replace('_LaneBoundDiscard(lower, cell)','_LaneBoundDiscard(lower, support)')
s=s.replace('from std.memory import bitcast\n','from std.memory import bitcast\nfrom std.utils import Variant\n')
# Exact static formatting edits retained from the original tool calls.
for bound in ['fast_lower','tightened_lower']:
    for kind in ['Discard','Close']:
        s=s.replace(f'return _LaneBoundProposal(_LaneBound{kind}({bound}, cell))',f'return _LaneBoundProposal(\n                        _LaneBound{kind}({bound}, cell)\n                    )')
s=s.replace('var fast_delta = _Interval(cell.low, cell.high) - _Interval.point(\n                    center_s\n                )','var fast_delta = _Interval(\n                    cell.low, cell.high\n                ) - _Interval.point(center_s)')
s=s.replace('point_domain = _lane_jet(road, context.section, context.lane, cell.low, cell.high)','point_domain = _lane_jet(\n                    road, context.section, context.lane, cell.low, cell.high\n                )')
s=s.replace('context.frozen.value(), center_s, context.location, policy.scale','context.frozen.value(),\n                        center_s,\n                        context.location,\n                        policy.scale')
s=s.replace('road, context.section, context.lane, center_s, context.location, policy.scale','road,\n                        context.section,\n                        context.lane,\n                        center_s,\n                        context.location,\n                        policy.scale')
assert hashlib.sha256(s.encode()).hexdigest()=='f94902c5f43eaa539f3cf45cfadf92d2e353ef43bd99411c2bfb7d8bc1045a91',hashlib.sha256(s.encode()).hexdigest()
(P/'lane_refinement.before-format.mojo').write_text(s)
# Exact pinned formatter diff was printed in full before the reset.
s=s.replace('''            raise Error(
                "Lane refinement exhausted its quadrature work limit"
            )''','''            raise Error("Lane refinement exhausted its quadrature work limit")''',1)
s=s.replace('''_global_lower(
                        domain, fast_center.value(), fast_delta
                    )''','''_global_lower(domain, fast_center.value(), fast_delta)''',1)
s=s.replace('''return _LaneBoundProposal(
                        _LaneBoundClose(fast_lower, cell)
                    )''','''return _LaneBoundProposal(_LaneBoundClose(fast_lower, cell))''',1)
s=s.replace('''                    "Lane refinement exhausted its quadrature work"
                    " limit"''','''                    "Lane refinement exhausted its quadrature work limit"''',1)
s=s.replace('''_global_lower(
                        domain, fast_center.value(), tightened_delta
                    )''','''_global_lower(domain, fast_center.value(), tightened_delta)''',1)
s=s.replace('''        if (
            domain.second.is_finite()
            or not domain.rounded_value().is_finite()
        ):''','''        if domain.second.is_finite() or not domain.rounded_value().is_finite():''',1)
s=s.replace('                        policy.scale\n','                        policy.scale,\n')
s=s.replace('''                        "Lane refinement exhausted its numerical accuracy"
                        " limit"''','''                        "Lane refinement exhausted its numerical accuracy limit"''',1)
actual=hashlib.sha256(s.encode()).hexdigest()
out=P/('lane_refinement.mojo' if actual==FINAL_SHA else 'lane_refinement.RECONSTRUCTED.mojo');out.write_text(s)
(P/'PRODUCTION-RECOVERY.json').write_text(json.dumps({'base_sha256':BASE_SHA,'expected_sha256':FINAL_SHA,'actual_sha256':actual,'exact':actual==FINAL_SHA,'file':out.name,'native_qualification':'Not rerun; raw prior receipts were lost'},indent=2)+'\n')
print(actual,out)
if actual!=FINAL_SHA:raise SystemExit('Not exact; inspect reconstruction')
