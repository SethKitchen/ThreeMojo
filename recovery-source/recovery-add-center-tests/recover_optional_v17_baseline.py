"""Recover the exact old optional test baseline from the restored public file.

Only standard-library text processing; output stays in this recovery directory.
"""
import ast
import hashlib
import os
from pathlib import Path
import sys

base=Path(__file__).resolve().parent
raw=Path(sys.argv[1]).read_bytes()
if hashlib.sha256(raw).hexdigest()!='7f95ec2b7be3d10228d9eab9d42c0a4ca00f8f5adb9e2bb77907f00a0612f60e':
    raise RuntimeError('Unexpected public optional test source')
s=raw.decode()
changes=[
('from pathlib import Path\n','from pathlib import Path\nimport full_audit_cleanup_contracts as cleanup\n'),
('    def setUpClass(cls):\n','    def setUpClass(cls):\n        cls.cleanup_fixture = cleanup.verify(ROOT, exact=True)[\'sources\']\n'),
("                    target.write_bytes(seed_count.historical_source(ROOT).encode('utf-8'))\n                else:\n",
 "                    target.write_bytes(seed_count.historical_source(ROOT).encode('utf-8'))\n                elif path in self.cleanup_fixture:\n                    target.write_text(self.cleanup_fixture[path]['before_source'])\n                else:\n"),
("            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), expected)\n",
"""            comparison_root = ROOT
            if path in self.cleanup_fixture:
                step = self.cleanup_fixture[path]
                self.assertEqual(step['before_sha256'], expected)
                self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),
                                 step['after_sha256'])
                # Verify the immutable lineage against physical predecessor
                # bytes only after setUpClass qualified the exact live root.
                comparison_root = Path(self.enterContext(tempfile.TemporaryDirectory()))
                target = comparison_root/path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(step['before_source'].encode('utf-8'))
            self.assertEqual(hashlib.sha256((comparison_root/path).read_bytes()).hexdigest(), expected)
""")]
for before,after in changes:
    if s.count(before)!=1:
        raise RuntimeError('Missing unique reconstruction target')
    s=s.replace(before,after,1)
ast.parse(s)
actual=hashlib.sha256(s.encode()).hexdigest()
expected='249ff8921939d0da2b9a9a6032f77c632eaca8d9658b8df31914bd65add0b543'
if actual!=expected:
    raise RuntimeError('Optional v17 baseline did not byte-recover: '+actual)
target=base/'test_optional_runtime_contracts.v17.py'
tmp=target.with_suffix('.tmp');tmp.write_text(s);os.replace(tmp,target)
print(str(target)+' '+actual)
