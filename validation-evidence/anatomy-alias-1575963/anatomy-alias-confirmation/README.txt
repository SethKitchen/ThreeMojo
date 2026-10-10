Anatomy input-binding alias whitespace regression, issue #702

Reviewed commit: 15759631d496469d23227ca64e9641b1290f83b2
Compiler: official Mojo 1.1.0 (8189361e), wheel launcher; identity receipt included.

Six compile/run fixtures passed, each printing 42. The four tab-separated aliases omit actual dependencies from the reviewed binding and preserve the digest after dependency mutation; ordinary-space controls bind the dependencies and change the digest.

results.json records exact executed commands, limits, exit statuses and durations. source-bytes.json preserves actual tab bytes and fixture hashes. run.py is the executed native runner, with local environment paths recorded in its source. It is provided for provenance; adapt its workspace-local SDK/evidence paths when replaying on another host. No compiler payloads, binaries or caches are included.

To replay the compiler-free binding mutation, obtain the named commit in a trusted local ThreeMojo checkout, then run:
mkdir -p /tmp/anatomy-702-review.6AM1Xk
git archive 15759631d496469d23227ca64e9641b1290f83b2 | tar -x -C /tmp/anatomy-702-review.6AM1Xk
PYTHONDONTWRITEBYTECODE=1 python3 check_binding.py

check_binding.py is the unmodified executed reproducer and assumes its six fixture files are beside it. This replay creates temporary synthetic trees only. The original donor repository was unchanged.
