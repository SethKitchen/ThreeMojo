"""Freeze two completed Linux TMPDIR-alias fixture phases as byte-exact evidence.

Source review and explicit parent release are required before execution. Stdlib
only: never imports or executes candidate/protocol/supervisor code, runs tests,
profiles, native tools, network operations, or reads polling/private-review bytes.
Only fixed original files and the reviewed decoder/builder are read. No scans of
candidate or SDK trees are performed. Output is create-only.
"""
from pathlib import Path
from datetime import datetime
import argparse
import base64
import gzip
import hashlib
import json
import re
import stat

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-macos-fixture-alias-v35-packet'
PROTOCOL = 'macos-fixture-alias-v35-protocol/revision-1'
SOURCE_SEAL = 'CANDIDATE-V35-MACOS-SOURCE-SEAL.json'
DECODER_SOURCE = 'validation-evidence-qualification-policy-v23-packet/decode_verify.py'
HOSTED_FAILURE = R.parent / 'ci-macos-lint-7347189-job114482905701.log'
LIMIT = 64 * 1024 * 1024
SHA = lambda data: hashlib.sha256(data).hexdigest()
JSON = lambda value: (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()

PHASE_NAMES = ['RESULT.json',
 'SDK-AFTER.json',
 'SDK-BEFORE.json',
 'SOURCE-SEAL.json',
 'WINDOW-START.json',
 'normal.log',
 'normal-START.json',
 'normal-RESULT.json',
 'normal/START.json',
 'normal/RESULT.json',
 'normal/CHILD-RESULT.json',
 'normal/ENVIRONMENT.json',
 'optimized.log',
 'optimized-START.json',
 'optimized-RESULT.json',
 'optimized/START.json',
 'optimized/RESULT.json',
 'optimized/CHILD-RESULT.json',
 'optimized/ENVIRONMENT.json']

ORIGINALS = [{'source': 'evidence/macos-fixture-alias-v35-phase1/RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/RESULT.json',
  'readable': True},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/SDK-AFTER.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/SDK-AFTER.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/SDK-BEFORE.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/SDK-BEFORE.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/SOURCE-SEAL.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/SOURCE-SEAL.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/WINDOW-START.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/WINDOW-START.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/normal.log',
  'path': 'actual/macos-fixture-alias-v35-phase1/normal.log',
  'readable': True},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/normal-START.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/normal-START.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/normal-RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/normal-RESULT.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/normal/START.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/normal/START.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/normal/RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/normal/RESULT.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/normal/CHILD-RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/normal/CHILD-RESULT.json',
  'readable': True},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/normal/ENVIRONMENT.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/normal/ENVIRONMENT.json',
  'readable': True},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/optimized.log',
  'path': 'actual/macos-fixture-alias-v35-phase1/optimized.log',
  'readable': True},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/optimized-START.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/optimized-START.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/optimized-RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/optimized-RESULT.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/optimized/START.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/optimized/START.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/optimized/RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/optimized/RESULT.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/optimized/CHILD-RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/optimized/CHILD-RESULT.json',
  'readable': True},
 {'source': 'evidence/macos-fixture-alias-v35-phase1/optimized/ENVIRONMENT.json',
  'path': 'actual/macos-fixture-alias-v35-phase1/optimized/ENVIRONMENT.json',
  'readable': True},
 {'source': 'macos-fixture-alias-v35-phase1.supervisor.log',
  'path': 'actual/macos-fixture-alias-v35-phase1.supervisor.log',
  'readable': True},
 {'source': 'macos-fixture-alias-v35-phase1.json',
  'path': 'reproduce/macos-fixture-alias-v35-phase1.json',
  'readable': True},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/RESULT.json',
  'readable': True},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/SDK-AFTER.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/SDK-AFTER.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/SDK-BEFORE.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/SDK-BEFORE.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/SOURCE-SEAL.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/SOURCE-SEAL.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/WINDOW-START.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/WINDOW-START.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/normal.log',
  'path': 'actual/macos-fixture-alias-v35-phase2/normal.log',
  'readable': True},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/normal-START.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/normal-START.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/normal-RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/normal-RESULT.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/normal/START.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/normal/START.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/normal/RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/normal/RESULT.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/normal/CHILD-RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/normal/CHILD-RESULT.json',
  'readable': True},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/normal/ENVIRONMENT.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/normal/ENVIRONMENT.json',
  'readable': True},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/optimized.log',
  'path': 'actual/macos-fixture-alias-v35-phase2/optimized.log',
  'readable': True},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/optimized-START.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/optimized-START.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/optimized-RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/optimized-RESULT.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/optimized/START.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/optimized/START.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/optimized/RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/optimized/RESULT.json',
  'readable': False},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/optimized/CHILD-RESULT.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/optimized/CHILD-RESULT.json',
  'readable': True},
 {'source': 'evidence/macos-fixture-alias-v35-phase2/optimized/ENVIRONMENT.json',
  'path': 'actual/macos-fixture-alias-v35-phase2/optimized/ENVIRONMENT.json',
  'readable': True},
 {'source': 'macos-fixture-alias-v35-phase2.supervisor.log',
  'path': 'actual/macos-fixture-alias-v35-phase2.supervisor.log',
  'readable': True},
 {'source': 'macos-fixture-alias-v35-phase2.json',
  'path': 'reproduce/macos-fixture-alias-v35-phase2.json',
  'readable': True},
 {'source': 'macos-fixture-alias-v35-protocol/revision-1/driver.py',
  'path': 'reproduce/macos-fixture-alias-v35-protocol/revision-1/driver.py',
  'readable': False},
 {'source': 'macos-fixture-alias-v35-protocol/revision-1/manifest.json',
  'path': 'reproduce/macos-fixture-alias-v35-protocol/revision-1/manifest.json',
  'readable': False},
 {'source': 'macos-fixture-alias-v35-protocol/revision-1/phase1.json',
  'path': 'reproduce/macos-fixture-alias-v35-protocol/revision-1/phase1.json',
  'readable': False},
 {'source': 'macos-fixture-alias-v35-protocol/revision-1/phase2.json',
  'path': 'reproduce/macos-fixture-alias-v35-protocol/revision-1/phase2.json',
  'readable': False},
 {'source': 'MACOS-FIXTURE-ALIAS-PROTOCOL-SEAL.json',
  'path': 'reproduce/MACOS-FIXTURE-ALIAS-PROTOCOL-SEAL.json',
  'readable': False},
 {'source': 'CANDIDATE-V35-MACOS-SOURCE-SEAL.json',
  'path': 'reproduce/CANDIDATE-V35-MACOS-SOURCE-SEAL.json',
  'readable': False},
 {'source': 'MACOS-CANONICAL-FIXTURE-SOURCE-MANIFEST.json',
  'path': 'reproduce/MACOS-CANONICAL-FIXTURE-SOURCE-MANIFEST.json',
  'readable': False},
 {'source': 'run_checkpoint_matrix.py', 'path': 'reproduce/run_checkpoint_matrix.py', 'readable': False},
 {'source': 'macos-canonical-fixture-proposal/revision-2/proposed/tools/carla_lane_oracle/_full_audit_test_fixtures.py',
  'path': 'reproduce/fixture-overlay/tools/carla_lane_oracle/_full_audit_test_fixtures.py',
  'readable': False},
 {'source': 'macos-canonical-fixture-proposal/revision-2/proposed/tools/carla_lane_oracle/test_full_audit_cleanup_contracts.py',
  'path': 'reproduce/fixture-overlay/tools/carla_lane_oracle/test_full_audit_cleanup_contracts.py',
  'readable': False},
 {'source': 'macos-canonical-fixture-proposal/revision-2/proposed/tools/carla_lane_oracle/test_optional_runtime_contracts.py',
  'path': 'reproduce/fixture-overlay/tools/carla_lane_oracle/test_optional_runtime_contracts.py',
  'readable': False},
 {'source': 'macos-canonical-fixture-proposal/revision-2/proposed/tools/carla_lane_oracle/test_paired_pin_contracts.py',
  'path': 'reproduce/fixture-overlay/tools/carla_lane_oracle/test_paired_pin_contracts.py',
  'readable': False},
 {'source': 'macos-canonical-fixture-proposal/revision-2/proposed/tools/carla_lane_oracle/test_runtime_correspondence.py',
  'path': 'reproduce/fixture-overlay/tools/carla_lane_oracle/test_runtime_correspondence.py',
  'readable': False},
 {'source': 'macos-canonical-fixture-proposal/revision-2/proposed/tools/carla_lane_oracle/test_spiral_moments.py',
  'path': 'reproduce/fixture-overlay/tools/carla_lane_oracle/test_spiral_moments.py',
  'readable': False},
 {'source': 'macos-canonical-fixture-proposal/revision-2/proposed/tools/test_coverage_loop_proofs.py',
  'path': 'reproduce/fixture-overlay/tools/test_coverage_loop_proofs.py',
  'readable': False},
 {'source': 'macos-canonical-fixture-proposal/revision-2/proposed/tools/test_sampled_values.py',
  'path': 'reproduce/fixture-overlay/tools/test_sampled_values.py',
  'readable': False},
 {'source': '@hosted-failure',
  'path': 'prior-hosted-failure/ci-macos-lint-7347189-job114482905701.log',
  'readable': False}]

PINS = {'@hosted-failure': '4cf5b5bafd156f6fcd9d95b86c228bf934d82c3f7e9c23b72014f6e52ace7984',
 'CANDIDATE-V35-MACOS-SOURCE-SEAL.json': 'e94ec30f91aaaded522a9c68cc014c8ee04b92749370322555983dc41ad4706e',
 'MACOS-CANONICAL-FIXTURE-SOURCE-MANIFEST.json': '4d0ea74f258bccf2a70ebf384105beb0af0299031665e47fcaa19520644a6abf',
 'MACOS-FIXTURE-ALIAS-PROTOCOL-SEAL.json': '538bb5e863d792a4b1cd8bb44bd66f1c48c069798b32ebdff630dbbb73972312',
 'evidence/macos-fixture-alias-v35-phase1/RESULT.json': '37d988838357d04c2d3f0b53463dd45bd8c0927fb2434f57b59e987c6824f05f',
 'evidence/macos-fixture-alias-v35-phase1/SDK-AFTER.json': '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207',
 'evidence/macos-fixture-alias-v35-phase1/SDK-BEFORE.json': '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207',
 'evidence/macos-fixture-alias-v35-phase1/SOURCE-SEAL.json': 'e94ec30f91aaaded522a9c68cc014c8ee04b92749370322555983dc41ad4706e',
 'evidence/macos-fixture-alias-v35-phase1/WINDOW-START.json': 'a976d364a155fcc8c568d4a9bad0a8b87f50d89e3711851932cd3546684fa081',
 'evidence/macos-fixture-alias-v35-phase1/normal-RESULT.json': 'e497f70dd56d8e317bbfec5bbe5f492fc078d4d3fef8c23bcb50f881cdf9aef1',
 'evidence/macos-fixture-alias-v35-phase1/normal-START.json': '07bdff05fd8e170f239513f817e10adfb2a989ced1500d035092596860e3618a',
 'evidence/macos-fixture-alias-v35-phase1/normal.log': '7e25e6bcc6ad4b1af6aef7550120f74a28f66f9f2f7ec345d3fa974b9ced5c67',
 'evidence/macos-fixture-alias-v35-phase1/normal/CHILD-RESULT.json': 'a046d23a44c03bfa4007ccb63a27d2280820576d4671baf88c5ca32a779231b1',
 'evidence/macos-fixture-alias-v35-phase1/normal/ENVIRONMENT.json': 'ac3027dd2e676282c7501a80154788025046d498f5dbeae0a6230d12694e483c',
 'evidence/macos-fixture-alias-v35-phase1/normal/RESULT.json': 'ff719148ca1510603867cae15979422edbecdff34fb1942681afeb3baebece98',
 'evidence/macos-fixture-alias-v35-phase1/normal/START.json': 'd11cf9177d41c96861e10abc6de76ecfd59fe7f243cc2d4effeaaee42352e633',
 'evidence/macos-fixture-alias-v35-phase1/optimized-RESULT.json': '40580749956ba68bb7d6af2a07ff215e16ea2d4011e551f36fd7c792387f2d0c',
 'evidence/macos-fixture-alias-v35-phase1/optimized-START.json': 'ad30b2115a309a4aa0a35937a4404d966cd604bd9fd963b23ba9c5e9d9cd8c13',
 'evidence/macos-fixture-alias-v35-phase1/optimized.log': 'a66fc5377a323b0c678aefdb9a2fa7ac58f9957ca744d5ba6805af505729bcc9',
 'evidence/macos-fixture-alias-v35-phase1/optimized/CHILD-RESULT.json': '181d5bdceea4a0acd79cc9cd9cc8e04eb6fe1e1442a8c71ec2e5968ae60ac803',
 'evidence/macos-fixture-alias-v35-phase1/optimized/ENVIRONMENT.json': '12c42d86eb8ce7d2fdddac3b515eb36ff151358f55d910bcd50d4130c68df259',
 'evidence/macos-fixture-alias-v35-phase1/optimized/RESULT.json': '968fa9f4345ae854264e23e27769fd52cdf4d7fa59b2b0cf2a34a8d18f1420b8',
 'evidence/macos-fixture-alias-v35-phase1/optimized/START.json': '7b91509dfe00e581b2bab8a604a381ab163754c7719a05b2501a459ed25f9f4d',
 'evidence/macos-fixture-alias-v35-phase2/RESULT.json': 'a8d35defdd71e6764a1a733c8b226558f23aacccefb681ac2911061e12d776ed',
 'evidence/macos-fixture-alias-v35-phase2/SDK-AFTER.json': '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207',
 'evidence/macos-fixture-alias-v35-phase2/SDK-BEFORE.json': '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207',
 'evidence/macos-fixture-alias-v35-phase2/SOURCE-SEAL.json': 'e94ec30f91aaaded522a9c68cc014c8ee04b92749370322555983dc41ad4706e',
 'evidence/macos-fixture-alias-v35-phase2/WINDOW-START.json': '8ced6c41bb48be0d7b36d698367de92b04e6f3c40f340610d0fd9aa55626ebd0',
 'evidence/macos-fixture-alias-v35-phase2/normal-RESULT.json': '5629f14cd2ba2909150cb1468d931a5f176f207a9776d8fa278e9ea4c84db49e',
 'evidence/macos-fixture-alias-v35-phase2/normal-START.json': '8b69f653b69f07c3918efd2cd214401bc77ed1b24f4c4e0e60e2446ec00b24a0',
 'evidence/macos-fixture-alias-v35-phase2/normal.log': 'f46b873107a29e0bc3bb42cba26652cdf8b3bf4ac992745b3f802b1124fed6cc',
 'evidence/macos-fixture-alias-v35-phase2/normal/CHILD-RESULT.json': '9598c1f7b2340fccf2cfb9d29d46e8a544b9316382a2c98080e28d5c8436a34f',
 'evidence/macos-fixture-alias-v35-phase2/normal/ENVIRONMENT.json': 'e3e9bf6a338e304c01a6e2f8812418183e83b82693f3d98149f96ffe618184f3',
 'evidence/macos-fixture-alias-v35-phase2/normal/RESULT.json': 'd2ae3d3e41f7968a52b62e634f1e12aac26e1f28ac67a6c6c234f37e1bf232d9',
 'evidence/macos-fixture-alias-v35-phase2/normal/START.json': '692febce536d82db04b6d0c82d0542af3945886e5c5df1750f5e54e6303eed20',
 'evidence/macos-fixture-alias-v35-phase2/optimized-RESULT.json': '55370d2655ebb321639ea86296e4382298c8b359e78f823b4fce2319054a8e88',
 'evidence/macos-fixture-alias-v35-phase2/optimized-START.json': '0900990cf78b4501fd03a480db6a627a177cbc7ef64362d6ebddd6f1c9fb287b',
 'evidence/macos-fixture-alias-v35-phase2/optimized.log': 'dfa38cbce3d6486eda7cd4b81c24943f95d79483f7859b1d66b7ac794d5f948f',
 'evidence/macos-fixture-alias-v35-phase2/optimized/CHILD-RESULT.json': '01f9595fd400569248edfd177dbaf9e34d48f9a7777179b21f337a16b9429ebd',
 'evidence/macos-fixture-alias-v35-phase2/optimized/ENVIRONMENT.json': '7c1f337ffb472a7b244b16f66e148eed2b712164582ae924ae4100d6008d9838',
 'evidence/macos-fixture-alias-v35-phase2/optimized/RESULT.json': '5c7feebb3851a87218ac25b17e064b3902576c73da55501bcc0e6569db8ba1a3',
 'evidence/macos-fixture-alias-v35-phase2/optimized/START.json': '5e7ecfff5c3e2045c65c7cd252d18fb9555dc6549b3a6858d46996c97486029d',
 'macos-canonical-fixture-proposal/revision-2/proposed/tools/carla_lane_oracle/_full_audit_test_fixtures.py': 'f49baa248d91c3150c39b239ed3f6fe8c26d340e34b1c9f89b8bfef6234886a4',
 'macos-canonical-fixture-proposal/revision-2/proposed/tools/carla_lane_oracle/test_full_audit_cleanup_contracts.py': '020659120c9b79052a4ae45e587e37d7ecda1f46a684a1239757ab610c92ad5a',
 'macos-canonical-fixture-proposal/revision-2/proposed/tools/carla_lane_oracle/test_optional_runtime_contracts.py': 'd24d5fd35f2b3cbb21b617116d3b18f1b3104864c1ce72d207880027b23e9a5a',
 'macos-canonical-fixture-proposal/revision-2/proposed/tools/carla_lane_oracle/test_paired_pin_contracts.py': '9c5ae9a6658ef277d725ad4bfa4a8c0992aef4b0c7175d1cb1823437383e7435',
 'macos-canonical-fixture-proposal/revision-2/proposed/tools/carla_lane_oracle/test_runtime_correspondence.py': '8231fb64a22f6d4df5fff5295c7795f84a549b408f405cde0814f0a6e9dde167',
 'macos-canonical-fixture-proposal/revision-2/proposed/tools/carla_lane_oracle/test_spiral_moments.py': '4412d9b135121dbe0cf8357524c92fe5419d3b31316b39f0d6da2df81e3a0d3b',
 'macos-canonical-fixture-proposal/revision-2/proposed/tools/test_coverage_loop_proofs.py': '02f76d4d139b739c1f4e4420d77f18a1247fb49cf4c6f9b3311a9209f809b3f5',
 'macos-canonical-fixture-proposal/revision-2/proposed/tools/test_sampled_values.py': '5ba7af72140d1a950bdec177123d3d0595b524833e55f42bf819fa3055d8e470',
 'macos-fixture-alias-v35-phase1.json': '93dd94486174e9dbea234822d63d27917585f237a432c042c4070c6c3197d65d',
 'macos-fixture-alias-v35-phase1.supervisor.log': '362b31594903b363a64df7b1546584ebea8ec8ce4cbb706184f5f5832f99b29e',
 'macos-fixture-alias-v35-phase2.json': 'f85b9bbcc058e62a36393fc72051cacc46e00e04119f92f218b5aa09b5a1e78c',
 'macos-fixture-alias-v35-phase2.supervisor.log': '917f40b5aae81aac3b39ed8e1e19ee1d9c10abc46f8ad35df0b01c76958b5447',
 'macos-fixture-alias-v35-protocol/revision-1/driver.py': '2c6fd88a508f36b6c0ee35601f261613f69e396e124cecfe561700a247200da9',
 'macos-fixture-alias-v35-protocol/revision-1/manifest.json': 'e1a7d0da100ca92891d2da13b695c92408bd984150294cd033bdc2dca9c6821b',
 'macos-fixture-alias-v35-protocol/revision-1/phase1.json': 'a3fa0ed7fdf6746bc3260e2aefd1eaa907a4eb5924c2a3c928070f7c99d55500',
 'macos-fixture-alias-v35-protocol/revision-1/phase2.json': 'cb1cd11cc5659a7262cc3c5c35ece8348b84ba3ac93c71c4f530ad453c4b7507',
 'run_checkpoint_matrix.py': '6727063772b92efdd559328b302db613626025bc6df5159937af56882f67e032',
 'validation-evidence-qualification-policy-v23-packet/decode_verify.py': 'a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4'}


def need(condition, message):
    if not condition:
        raise ValueError(message)


def raw(path):
    relative = path.relative_to(R.parent)
    need(relative.parts and all(p not in ('', '.', '..') for p in relative.parts), 'Unsafe path')
    current = R.parent
    for index, part in enumerate(relative.parts):
        current /= part
        mode = current.lstat().st_mode
        need(stat.S_ISREG(mode) if index == len(relative.parts) - 1 else stat.S_ISDIR(mode),
             'Nonregular or symlink path: ' + str(current))
    need(path.stat().st_size <= LIMIT, 'Oversize input: ' + str(path))
    return path.read_bytes()


def unique(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'Duplicate JSON key: ' + key)
        result[key] = value
    return result


def parse(data):
    return json.loads(data, object_pairs_hook=unique)


def input_path(name):
    return HOSTED_FAILURE if name == '@hosted-failure' else R / name


def phase_inventory(phase):
    folder = R / 'evidence' / phase
    expected = {name.split('/')[0] for name in PHASE_NAMES} | {'LATEST.json', 'PROCESSES.jsonl'}
    need(stat.S_ISDIR(folder.lstat().st_mode), 'Non-directory evidence phase')
    need({path.name for path in folder.iterdir()} == expected, 'Unexpected terminal phase inventory')
    for mode in ('normal', 'optimized'):
        inner = folder / mode
        need(stat.S_ISDIR(inner.lstat().st_mode), 'Non-directory inner evidence')
        need({path.name for path in inner.iterdir()} ==
             {'START.json', 'RESULT.json', 'CHILD-RESULT.json', 'ENVIRONMENT.json'},
             'Unexpected terminal inner inventory')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('phase1-result', 'phase1-console', 'phase2-result', 'phase2-console', 'builder'):
        parser.add_argument('--expected-' + name + '-sha256', required=True)
    args = parser.parse_args()
    for name, value in vars(args).items():
        need(re.fullmatch(r'[0-9a-f]{64}', value) is not None, 'Invalid exact hash: ' + name)
    need(not O.exists() and not O.is_symlink(), 'Create-only output already exists')
    observed = {}

    def read(name):
        need(name in PINS, 'Input not on the exact read allowlist: ' + name)
        data = raw(input_path(name))
        need(SHA(data) == PINS[name], 'Changed exact input binding: ' + name)
        need(name not in observed or observed[name] == data, 'Input changed: ' + name)
        observed[name] = data
        return data

    # Terminal receipts are the first evidence bytes read. No polling or partial
    # phase packaging is supported; caller hashes must match this exact attempt.
    for number in (1, 2):
        phase = 'macos-fixture-alias-v35-phase' + str(number)
        need(getattr(args, 'expected_phase' + str(number) + '_result_sha256') ==
             PINS['evidence/' + phase + '/RESULT.json'], 'Wrong terminal RESULT release')
        need(getattr(args, 'expected_phase' + str(number) + '_console_sha256') ==
             PINS[phase + '.supervisor.log'], 'Wrong terminal console release')
        read('evidence/' + phase + '/RESULT.json')
        phase_inventory(phase)
    builder_path = Path(__file__).resolve()
    builder = raw(builder_path)
    need(SHA(builder) == args.expected_builder_sha256, 'Reviewed builder hash differs')
    need(len(ORIGINALS) == 59 and len(PHASE_NAMES) == 19 and len(PINS) == 60,
         'Fixed member/read inventory differs')
    need(len({row['path'] for row in ORIGINALS}) == len({row['source'] for row in ORIGINALS}) == 59,
         'Duplicate original member')
    originals = []
    for row in ORIGINALS:
        data = read(row['source'])
        data.decode('utf-8')
        originals.append({**row, 'data': data})
    decoder = read(DECODER_SOURCE)
    seal_hash = PINS[SOURCE_SEAL]
    need(seal_hash == 'e94ec30f91aaaded522a9c68cc014c8ee04b92749370322555983dc41ad4706e',
         'Source seal release differs')
    seal = parse(read(SOURCE_SEAL))
    source_manifest = parse(read('MACOS-CANONICAL-FIXTURE-SOURCE-MANIFEST.json'))
    need(source_manifest['base_commit'] == '19287a0b1564b9a628f15c96e7675c51413ca1a9'
         and len(source_manifest['files']) == 8, 'Fixture source base/inventory differs')
    fixture_rows = [row for row in ORIGINALS if row['path'].startswith('reproduce/fixture-overlay/')]
    expected_fixture_rows = []
    for item in source_manifest['files']:
        name = str(Path(item['source']).relative_to(R))
        data = read(name)
        need(len(data) == item['bytes'] and SHA(data) == item['sha256'] == seal[item['path']],
             'Fixture source/manifest/seal mismatch: ' + item['path'])
        expected_fixture_rows.append(dict(source=name, path='reproduce/fixture-overlay/' + item['path'],
                                          readable=False))
    need(fixture_rows == expected_fixture_rows, 'Exact eight-file source overlay differs')
    protocol = parse(read(PROTOCOL + '/manifest.json'))
    protocol_seal = parse(read('MACOS-FIXTURE-ALIAS-PROTOCOL-SEAL.json'))
    driver_hash = PINS[PROTOCOL + '/driver.py']
    manifest_hash = PINS[PROTOCOL + '/manifest.json']
    supervisor_hash = PINS['run_checkpoint_matrix.py']
    need(set(protocol_seal) == {'README.md', 'driver.py', 'independent-review.json',
                               'manifest.json', 'phase1.json', 'phase2.json'},
         'Protocol source inventory differs')
    for name in ('driver.py', 'manifest.json', 'phase1.json', 'phase2.json'):
        need(protocol_seal[name] == PINS[PROTOCOL + '/' + name], 'Protocol source binding differs')
    need(protocol['candidate'] == 'candidate-v35-macos' and protocol['source_seal'] == SOURCE_SEAL
         and set(protocol['phases']) == {'phase1', 'phase2'}
         and set(protocol['source_files']) == {item['path'] for item in source_manifest['files']} |
             {'tools/carla_lane_oracle/full_audit_cleanup_contracts.py'}, 'Protocol candidate inputs differ')
    need(all(seal[name] == digest for name, digest in protocol['source_files'].items()),
         'Protocol source hashes differ from full candidate seal')
    python = str(R.parent / 'restored-toolchain/official-venv/bin/python')
    source = str(R / 'candidate-v35-macos')
    driver = str(R / PROTOCOL / 'driver.py')
    phases, commands = [], []
    for number, expected_tests, stage_cap, child_cap, window_cap in (
            (1, 4, 300, 270, 650), (2, 6, 1800, 1770, 3700)):
        short = 'phase' + str(number)
        phase = 'macos-fixture-alias-v35-' + short
        prefix = 'evidence/' + phase + '/'
        folder = R / 'evidence' / phase
        evidence = lambda name: read(prefix + name)
        result = parse(evidence('RESULT.json'))
        window = parse(evidence('WINDOW-START.json'))
        config = parse(read(phase + '.json'))
        original_config = parse(read(PROTOCOL + '/' + short + '.json'))
        need({k: v for k, v in config.items() if k != 'additional_sources'} == original_config,
             'Effective config is not the exact protocol plan plus source binding')
        need(config['additional_sources'] == [dict(source=str(R / PROTOCOL),
             seal=str(R / 'MACOS-FIXTURE-ALIAS-PROTOCOL-SEAL.json'))], 'Additional protocol binding differs')
        need(config['phase'] == phase and config['source'] == 'candidate-v35-macos'
             and config['seal'] == SOURCE_SEAL and config['window_seconds'] == window_cap
             and config['pause_request_file'] == 'macos-fixture-alias-v35.pause', 'Outer config differs')
        selection = protocol['phases'][short]
        need(selection['evidence'] == phase and selection['expected_tests'] == expected_tests
             and selection['child_timeout_seconds'] == child_cap
             and selection['alias_controls'] is (number == 1)
             and len(selection['selectors']) == (3 if number == 1 else 6), 'Phase selection differs')
        need(evidence('SOURCE-SEAL.json') == read(SOURCE_SEAL), 'Source seal copy differs')
        need(evidence('SDK-BEFORE.json') == evidence('SDK-AFTER.json') ==
             read('evidence/macos-fixture-alias-v35-phase1/SDK-BEFORE.json'), 'SDK receipts differ')
        sdk_hash = PINS[prefix + 'SDK-BEFORE.json']
        need(result['sequence_completed'] is True and result['failure'] is None
             and result['source_seal_unchanged'] is True and result['sdk_identity_unchanged'] is True
             and result['remaining_owned_descendants'] == [] and result['scope'] == config['scope'],
             'Terminal completion/stability/cleanup differs')
        need(window['supervisor_sha256'] == supervisor_hash and window['source_seal_sha256'] == seal_hash
             and window['whole_window_seconds'] == window_cap and window['python_optimize'] == 0
             and window['runtime_gate_seconds'] == 5, 'Window identity/cap differs')
        need(datetime.fromisoformat(result['finished']) >= datetime.fromisoformat(window['started'])
             and 0 <= result['elapsed_seconds'] < window_cap, 'Terminal chronology/cap differs')
        console = [parse(line) for line in read(phase + '.supervisor.log').decode().splitlines()]
        need(len(console) == 3 and console[-1] == result, 'Full console terminal receipt differs')
        need(len(result['stages']) == len(config['stages']) == 2, 'Stage inventory differs')
        modes = []
        for index, mode in enumerate(('normal', 'optimized')):
            flags = ['-O', '-B'] if mode == 'optimized' else ['-B']
            plan = dict(label=mode, expected_tests=expected_tests, seconds=stage_cap,
                command=['{python}', *flags, '{root}/' + PROTOCOL + '/driver.py', short, '{evidence}'])
            need(config['stages'][index] == plan, 'Fixed stage plan differs')
            outer_start = parse(evidence(mode + '-START.json'))
            outer = parse(evidence(mode + '-RESULT.json'))
            inner_start = parse(evidence(mode + '/START.json'))
            inner = parse(evidence(mode + '/RESULT.json'))
            child = parse(evidence(mode + '/CHILD-RESULT.json'))
            environment = parse(evidence(mode + '/ENVIRONMENT.json'))
            need(result['stages'][index] == outer and all(outer.get(k) == v for k, v in outer_start.items()),
                 'Outer START/RESULT/terminal differ')
            # Supervisor prints stage receipts before it appends test-count keys.
            need(console[index] == {k: v for k, v in outer.items() if k not in
                 ('test_count', 'expected_tests', 'skipped_test_count')}, 'Full stage console differs')
            need(outer['argv'] == [python, *flags, driver, short, str(folder)]
                 and outer['cwd'] == source and outer['label'] == mode
                 and outer['stage_timeout_seconds'] == stage_cap and outer['source_seal_sha256'] == seal_hash
                 and outer['log_sha256'] == PINS[prefix + mode + '.log'] and outer['returncode'] == 0
                 and outer['timed_out'] is False and outer['leader_reaped'] is True
                 and outer['remaining_owned_descendants'] == [] and outer['test_count'] == expected_tests
                 and outer['expected_tests'] == expected_tests and outer['skipped_test_count'] == 0
                 and 0 <= outer['seconds'] < stage_cap, 'Outer command/result/count/cap differs')
            identity = dict(source=source, source_seal_sha256=seal_hash, manifest_sha256=manifest_hash,
                driver_sha256=driver_hash, phase=short, mode=mode, expected_tests=expected_tests)
            for receipt in (inner_start, inner, child, environment):
                need(all(receipt.get(k) == v for k, v in identity.items()), 'Inner identity differs')
            need(inner_start['success'] is False and all(inner.get(k) == v for k, v in inner_start.items()
                 if k != 'success'), 'Inner START/RESULT binding differs')
            need(inner['command'] == [python, *flags, driver, '--child', short, str(folder)]
                 and inner['success'] is True and inner['returncode'] == 0
                 and inner['child_timeout_seconds'] == child_cap and 0 <= inner['elapsed_seconds'] < child_cap
                 and inner['remaining_temporary_entries'] == [] and inner['work_removed'] is True
                 and 'error' not in inner and 'cleanup_error' not in inner, 'Inner completion/cleanup differs')
            need(child['success'] is True and child['tests_run'] == expected_tests
                 and [child[k] for k in ('errors', 'failures', 'skips')] == [0, 0, 0]
                 and child['selectors'] == selection['selectors']
                 and child['alias_controls'] == selection['alias_controls'], 'Exact child outcomes differ')
            alias = str(folder / mode / 'temporary-parent/alias')
            real = str(folder / mode / 'temporary-parent/real')
            need(environment['actual_alias_selected'] is True and environment['TMPDIR'] == alias
                 and environment['gettempdir'] == alias and environment['resolved_temp_parent'] == real
                 and environment['pid'] != environment['ppid'] == outer['pid'],
                 'Fresh-child or selected aliased TMPDIR evidence differs')
            log = evidence(mode + '.log').decode('utf-8')
            need(re.findall(r'(?m)^Ran (\d+) tests? in ', log) == [str(expected_tests)]
                 and re.search(r'(?m)^OK$', log) is not None
                 and parse(log.splitlines()[-1]) == inner, 'Full unittest log/count/inner receipt differs')
            modes.append(dict(mode=mode, tests_run=expected_tests, outer_seconds=outer['seconds'],
                inner_seconds=inner['elapsed_seconds'], child_pid=environment['pid'],
                driver_pid=environment['ppid'], actual_alias_selected=True, success=True,
                dedicated_alias_control=selection['alias_controls'], selectors=selection['selectors'],
                environment_sha256=PINS[prefix + mode + '/ENVIRONMENT.json'],
                child_result_sha256=PINS[prefix + mode + '/CHILD-RESULT.json'],
                log_sha256=PINS[prefix + mode + '.log']))
            commands.append(dict(phase=phase, mode=mode, original_outer_start=outer_start,
                original_outer_result=outer, original_inner_start=inner_start,
                original_inner_result=inner, planned_stage=plan))
        need(modes[0]['child_pid'] != modes[1]['child_pid'], 'Mode child process identity reused')
        phases.append(dict(phase=phase, result_sha256=PINS[prefix + 'RESULT.json'],
            console_sha256=PINS[phase + '.supervisor.log'], config_sha256=PINS[phase + '.json'],
            started=window['started'], finished=result['finished'], executions=2 * expected_tests,
            elapsed_seconds=result['elapsed_seconds'], sdk_receipt_sha256=sdk_hash,
            stage_cap_seconds=stage_cap, child_cap_seconds=child_cap, window_cap_seconds=window_cap,
            modes=modes, scope=config['scope']))
    need(datetime.fromisoformat(phases[1]['started']) > datetime.fromisoformat(phases[0]['finished']),
         'Phase 2 did not follow completed phase 1')
    hosted = read('@hosted-failure').decode('utf-8')
    need('Ran 811 tests in 789.973s' in hosted and 'FAILED (failures=1, errors=10, skipped=4)' in hosted
         and 'Process completed with exit code 2.' in hosted
         and '7347189fe9ab82901dd691d82c21538aa946a593' in hosted
         and 'de9298895458871e1e1872c3c8f3e840f0495340' in hosted,
         'Original hosted failure attribution differs')
    scope = ('Focused Linux TMPDIR-alias fixture controls only: phase 1 passed 4 tests per mode and '
             'phase 2 passed 6 tests per mode, 20 executions total on one source seal. '
             'No actual macOS-hosted, full-module, native, lexical-v37, performance, CI-readiness, '
             'merge-readiness, or issue-completion claim.')
    summary = dict(schema=1, kind='derived-focused-linux-alias-fixture-summary',
        status='FOCUSED_LINUX_ALIAS_CONTROLS_PASSED_ONLY', scope=scope,
        focused_controls_passed=True, actual_macos_host_qualified=False,
        full_module_qualification=False, overall_qualification_passed=False,
        native_qualification=False, lexical_v37_qualification=False,
        total_test_executions=20, distinct_selected_cases=10,
        source_seal_sha256=seal_hash, driver_sha256=driver_hash, manifest_sha256=manifest_hash,
        protocol_seal_sha256=PINS['MACOS-FIXTURE-ALIAS-PROTOCOL-SEAL.json'],
        supervisor_sha256=supervisor_hash, phases=phases,
        fixture_overlay=dict(base_commit=source_manifest['base_commit'], file_count=8,
            source_manifest_sha256=PINS['MACOS-CANONICAL-FIXTURE-SOURCE-MANIFEST.json'],
            files=[dict(path=item['path'], bytes=item['bytes'], sha256=item['sha256'])
                   for item in source_manifest['files']],
            original_manifest_status_preserved=source_manifest['status']),
        alias_control_boundary='Each of four modes uses a fresh child that selected lexical aliased TMPDIR. '
            'The additional real _regular/resolver positive-negative control runs only in phase 1, once per mode. '
            'Phase 2 runs its six fixed maintained selectors per mode.',
        assertion_boundary='Exact maintained selectors and fixture source bytes are preserved. The dedicated '
            'phase-1 control passes explicit root/ancestor aliases directly into production rejection checks; '
            'this packet does not relax production admission or rewrite maintained assertions.',
        stability_boundary='Source/SDK stability, fresh-child selection, cleanup and descendant state are '
            'original terminal receipts, not new candidate/SDK/process or removed-fixture checks.',
        prior_hosted_failure=dict(path='prior-hosted-failure/ci-macos-lint-7347189-job114482905701.log',
            sha256=PINS['@hosted-failure'], bytes=len(read('@hosted-failure')),
            head_commit='7347189fe9ab82901dd691d82c21538aa946a593',
            tested_merge_commit='de9298895458871e1e1872c3c8f3e840f0495340',
            job_id=114482905701, tests_run=811, failures=1, errors=10, skips=4, exit_code=2,
            scope='Original earlier hosted macOS failure preserved separately and unchanged. '
                'It is not a run of the candidate-v35-macos controls or a current-head result. '
                'Focused Linux passes do not supersede or qualify this failure.'),
        private_review_bytes_included=False,
        exclusions='Polling LATEST/PROCESSES bytes, private review/design bytes, unrelated phases, '
            'SDK payload bytes, and all candidate source contents except the eight fixture files.')
    patterns = (rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', rb'gh[pousr]_[A-Za-z0-9]{30,}',
                rb'AKIA[0-9A-Z]{16}', rb'(?i)Bearer [A-Za-z0-9._-]{24,}')
    for row in originals:
        need(not any(re.search(pattern, row['data']) for pattern in patterns),
             'Credential pattern: ' + row['path'])
    archive = 'containers/ORIGINAL-EVIDENCE.json.gz.b64'
    payloads, members, archived = [], [], []
    for row in sorted(originals, key=lambda row: row['path']):
        data = row['data']
        member = dict(path=row['path'], original_source=str(input_path(row['source'])),
            kind='byte-exact-original', bytes=len(data), sha256=SHA(data),
            identity_basis='frozen-original-byte-identity')
        if row['readable']:
            payloads.append((row['path'], data, 'byte-exact-readable-original'))
            member.update(storage='readable', transport_path=row['path'])
        else:
            archived.append(dict(path=row['path'], bytes=len(data), sha256=SHA(data),
                                 data_base64=base64.b64encode(data).decode('ascii')))
            member.update(storage='container', transport_path=archive)
        members.append(member)
    container = (json.dumps(dict(schema=1, encoding='base64', members=archived),
                           sort_keys=True, separators=(',', ':')) + '\n').encode()
    need(len(container) < LIMIT, 'Reviewed decoder 64 MiB limit exceeded')
    encoded = base64.b64encode(gzip.compress(container, compresslevel=9, mtime=0)) + b'\n'
    need(gzip.decompress(base64.b64decode(encoded.strip(), validate=True)) == container,
         'Transport round-trip differs')
    inner = dict(schema=1, original_member_count=len(members),
        original_member_bytes=sum(row['bytes'] for row in members),
        container=dict(path=archive, encoding='base64 of deterministic gzip mtime=0 containing JSON',
                       members=len(archived), json_bytes=len(container), json_sha256=SHA(container)), members=members)
    guide = '''# Focused Linux TMPDIR-alias fixture controls

FOCUSED CONTROLS PASSED ONLY. Phase 1: 4 tests per mode, 8 executions.
Phase 2: 6 tests per mode, 12 executions. All 20 executions completed without
failures, errors, skips, timeout or leftover owned descendants on one source seal.
Both normal and optimized modes selected the lexical aliased TMPDIR in fresh
child processes. The added real _regular/resolver positive-negative control ran
only in phase 1, once per mode; phase 2 used its six fixed maintained selectors.
Explicit supplied alias rejection and historical maintained assertions remain
represented by the original selected methods, exact source files and raw logs.

This is Linux focused evidence, not actual macOS-hosted qualification, full-module
qualification, native qualification, lexical-v37 qualification, performance
improvement, CI readiness, merge readiness or issue completion. Hosted macOS
make -B test-tools on the final exact commit remains a separate gate.

The separate prior-hosted-failure member preserves the original full macOS log
for head 7347189fe9ab82901dd691d82c21538aa946a593, tested as merge
 de9298895458871e1e1872c3c8f3e840f0495340, job 114482905701. It recorded
811 tests, 1 failure, 10 errors, 4 skips and process exit 2. It is neither a
candidate-v35-macos control run nor a current-head result. Nothing here rewrites,
supersedes or grants a pass to that failure.

All 19 non-polling terminal originals from each phase are preserved, plus both
full supervisor consoles, effective configs, original protocol phase configs,
driver, protocol manifest/seal, full candidate source seal, fixture source
manifest, supervisor source, exact eight fixture files, and original hosted
failure log: 59 originals. Private review/design bytes are excluded. Original
manifests may retain historical pending/source-only wording; they are preserved
unchanged and do not replace the later terminal receipts. Seals can reference
excluded review/README members by hash without including those private bytes.
Source/SDK/cleanup claims describe original receipts, not new live scans.

VALIDATION-SUMMARY.json and COMMAND-RECEIPT-SEAL.json are derived indexes.
INNER-MEMBER-MANIFEST.json lists every complete original path, size and SHA256.
Raw logs, terminal results, child results and ENVIRONMENT receipts are readable.
The other complete originals use base64 JSON in deterministic gzip mtime=0,
then UTF-8 base64. No original is truncated, normalized or replaced by a summary.
The outer manifest seals every payload except itself.

Verify without writing: python -B decode_verify.py
Decode into a new directory: python -B decode_verify.py --output /new/directory
The unchanged, hash-bound decoder verifies paths, sizes and hashes without
executing original code or interpreting evidence beyond transport metadata.

Reproduction inputs are archival, not an invitation to execute during verification.
The eight-file overlay is based on commit 19287a0b1564b9a628f15c96e7675c51413ca1a9.
A separate reproduction requires the full checkout matching the candidate seal,
the recorded Linux SDK/interpreter, and reviewed equivalent sandbox paths.
The exact original driver and supervisor use fixed paths and create-only phase
directories; do not run them against the preserved original evidence. A changed
path, new phase name or new host requires a separately reviewed configuration.
COMMAND-RECEIPT-SEAL.json preserves original commands, caps and result bindings.
The packaging builder is create-only and requires explicit exact terminal
RESULT, console and builder hashes. Packaging launches no tests or native tools.
'''
    command_index = dict(schema=1, kind='derived-original-command-and-cap-index',
        source_seal_sha256=seal_hash, supervisor_sha256=supervisor_hash,
        driver_sha256=driver_hash, manifest_sha256=manifest_hash, stages=commands,
        scope=scope, original_commands_are_archival=True)
    payloads += [(archive, encoded, 'lossless-original-focused-alias-evidence'),
        ('INNER-MEMBER-MANIFEST.json', JSON(inner), 'complete-original-member-inventory'),
        ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-focused-only-summary'),
        ('COMMAND-RECEIPT-SEAL.json', JSON(command_index), 'derived-command-cap-and-receipt-index'),
        ('decode_verify.py', decoder, 'unchanged-hash-bound-safe-decoder'),
        ('reproduce/' + builder_path.name, builder, 'source-only-packet-builder'),
        ('README.md', guide.encode(), 'focused-scope-and-safe-transport-guide')]
    need(len(payloads) == len({name for name, _, _ in payloads}) == 25, 'Payload inventory differs')
    need(set(observed) == set(PINS), 'Read allowlist inventory differs')
    for number in (1, 2):
        phase_inventory('macos-fixture-alias-v35-phase' + str(number))
    for name, data in observed.items():
        need(raw(input_path(name)) == data, 'Consumed input changed during packaging: ' + name)
    need(raw(builder_path) == builder, 'Builder changed during packaging')
    O.mkdir(parents=False, exist_ok=False)
    rows = []
    for name, data, kind in sorted(payloads):
        path = O / name
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as stream:
            stream.write(data)
        need(raw(path) == data, 'Written payload differs')
        rows.append(dict(path=name, local_source=str(path), bytes=len(data), sha256=SHA(data), kind=kind))
    manifest = O / 'PUBLISHABLE-EVIDENCE-MANIFEST.json'
    with manifest.open('xb') as stream:
        stream.write(JSON(dict(schema=1, scope=scope, files=rows)))
    print(json.dumps(dict(manifest=str(manifest), sha256=SHA(raw(manifest)), payloads=len(rows),
        original_members=len(members), archived_members=len(archived), original_bytes=inner['original_member_bytes'],
        status=summary['status'], focused_controls_passed=True, actual_macos_host_qualified=False,
        content_executed_or_unmarshaled=False,
        packet_bytes_including_manifest=sum(row['bytes'] for row in rows) + len(raw(manifest))), sort_keys=True))


if __name__ == '__main__':
    main()
