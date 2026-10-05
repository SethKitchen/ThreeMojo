// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// node compare_three.mjs /path/to/three revision output.json
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const [root, revision, output] = process.argv.slice(2);
const loaderPath = path.join(root, 'examples/jsm/loaders/EXRLoader.js');
const packageVersion = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).version;
if (packageVersion !== `0.${revision}.0`) throw Error(`Unexpected package version ${packageVersion}`);
const { EXRLoader } = await import(pathToFileURL(loaderPath));
const { FloatType, REVISION } = await import(pathToFileURL(path.join(root, 'build/three.module.js')));
if (String(REVISION) !== revision) throw Error(`Expected ${revision}; got ${REVISION}`);
const dir = path.dirname(new URL(import.meta.url).pathname);
const results = [];
for (const name of fs.readdirSync(dir).filter(n => /^c[5-9]_.+\.exr\.hex$/.test(n)).sort()) {
  const codec = Number(name[1]);
  if (revision === '180' && (codec === 6 || codec === 7)) continue;
  const bytes = Buffer.from(fs.readFileSync(path.join(dir, name), 'utf8').replace(/\s/g, ''), 'hex');
  const expected = Buffer.from(fs.readFileSync(path.join(dir, name.replace('.exr.hex', '.exr.rgba.hex')), 'utf8').replace(/\s/g, ''), 'hex');
  try {
    const parsed = new EXRLoader().setDataType(FloatType).parse(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length));
    let maxAbs = 0, maxRelative = 0, mismatches = 0;
    for (let y = 0; y < parsed.height; y++) for (let x = 0; x < parsed.width * 4; x++) {
      const got = parsed.data[((parsed.height-1-y) * parsed.width * 4) + x];
      const ref = expected.readFloatLE((y * parsed.width * 4 + x) * 4);
      const error = Math.abs(got-ref);
      if (!Number.isFinite(got) || error > 0.004 * Math.max(1,Math.abs(ref))) mismatches++;
      maxAbs = Math.max(maxAbs,error);
      maxRelative = Math.max(maxRelative,error/Math.max(1,Math.abs(ref)));
    }
    results.push({ name, status: mismatches ? 'difference' : 'pass', maxAbs, maxRelative, mismatches });
  } catch (e) { results.push({ name, status: 'upstream-error', error: String(e.message) }); }
}
fs.writeFileSync(output, JSON.stringify({ revision: `three.js r${revision}`, packageVersion, loaderSha256: crypto.createHash('sha256').update(fs.readFileSync(loaderPath)).digest('hex'), comparisonMetric: 'abs(actual-reference)/max(1,abs(reference))', tolerance: 0.004, results }, null, 2) + '\n');
console.log(JSON.stringify({ revision, pass: results.filter(r=>r.status==='pass').length, difference: results.filter(r=>r.status==='difference').length, error:results.filter(r=>r.status==='upstream-error').length }));
