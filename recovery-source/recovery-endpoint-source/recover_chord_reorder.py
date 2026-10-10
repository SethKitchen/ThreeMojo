"""Recover the exact endpoint reorder from retained task context; no native work."""
from pathlib import Path
import hashlib,json,difflib,subprocess
R=Path(__file__).resolve().parent;ROOT=R.parent
sha=lambda s:hashlib.sha256(s.encode()).hexdigest()
old='''    var derivative = _length_up(
        point[0].second.magnitude(),
        point[1].second.magnitude(),
        point[2].second.magnitude(),
    )
    if not isfinite(derivative):
        return (natural, box, spent)
    var first_work = _reference_work(road, low, low)
    var last_work = _reference_work(road, high, high)
    if first_work < 0 or last_work < 0:
        return (natural, box, spent)
'''
new='''    # Endpoint admission and a finite second derivative are independent
    # requirements for the optional smooth certificate. Check the counts
    # first, including when the original coarse box is already unbounded.
    # Either refusal retains the same natural bound and spent-work ledger.
    var first_work = _reference_work(road, low, low)
    var last_work = _reference_work(road, high, high)
    if first_work < 0 or last_work < 0:
        return (natural, box, spent)
    var derivative = _length_up(
        point[0].second.magnitude(),
        point[1].second.magnitude(),
        point[2].second.magnitude(),
    )
    if not isfinite(derivative):
        return (natural, box, spent)
'''
source=ROOT/'recovery-pr711-assembly/assessment-original/original-cleanup/extensions/carla/lane_refinement.mojo'
before=source.read_text();assert sha(before)=='091ffefc963b3185ed82062bbcb6e1b0a18b910c8609a9a436868f45cfb219b2';assert before.count(old)==1
after=before.replace(old,new);expected='370dee032a5e126e727c46d0ceb7103359f1ad7fba8151e341b594df0c7d0e30';assert sha(after)==expected,(sha(after),expected)
out=R/'endpoint-current/extensions/carla/lane_refinement.mojo';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(after)
(R/'chord-refusal-order.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='a/extensions/carla/lane_refinement.mojo',tofile='b/extensions/carla/lane_refinement.mojo')))
canonical=subprocess.check_output(['git','-C',str(ROOT/'ThreeMojo-restored'),'show','a45ec12b:extensions/carla/lane_refinement.mojo'],text=True)
assert sha(canonical)=='d6bb8cb266fa350491f71e92295e70bcbfc2566b34db02400b3a6cb5bb5a93ad';assert sha(canonical.replace(old,new))=='b44bc4a5f44b005f775cfe1ad96c82c5991f44edc2c99d4c8d70bd39ea847f25'
record={'classification':'byte-exact production recovery verified against two recorded post-edit hashes','original_cleanup_before':sha(before),'endpoint_current_after':sha(after),'head_711_before':sha(canonical),'head_711_endpoint_only_after':sha(canonical.replace(old,new)),'before':old,'after':new,'before_sha256':sha(old),'after_sha256':sha(new),'native_qualification':'Not rerun; old receipt files lost. Historical observed MC/DC vectors retained only as task-context facts, not replacement capture evidence.'}
(R/'CHORD-RECOVERY.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps({k:v for k,v in record.items() if k not in ('before','after')},indent=2))
