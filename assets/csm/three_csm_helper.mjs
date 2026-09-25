// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes three.json: the parts three.js 0.180's CSMHelper draws for the CSM
// that `tests/test_csm_helper.mojo` builds, in world space. Run it with
// three 0.180 installed beside it: `node three_csm_helper.mjs > three.json`.
//
// - `frustum`: the frustum's twelve edges, two points each.
// - `cascades`, `shadows`: each cascade's box and shadow box, likewise.
// - `planes`: each cascade plane's two triangles, three points each.
// Each light's shadow camera is moved to its light first, as a render does.

import * as THREE from 'three';
import { CSM } from 'three/examples/jsm/csm/CSM.js';
import { CSMHelper } from 'three/examples/jsm/csm/CSMHelper.js';

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(50, 1.5, 0.5, 200);
camera.position.set(10, 8, 20); camera.lookAt(0, 0, 0); camera.updateMatrixWorld();
const csm = new CSM({ camera, parent: scene, cascades: 3, maxFar: 120, mode: 'practical', shadowMapSize: 1024,
  lightDirection: new THREE.Vector3(1, -1, 1).normalize(), lightIntensity: 3, lightNear: 1, lightFar: 500, lightMargin: 50 });
csm.update();
scene.updateMatrixWorld(true);
for (const light of csm.lights) light.shadow.updateMatrices(light);
const helper = new CSMHelper(csm);
helper.update();
helper.updateMatrixWorld(true);
const r = v => +v.toFixed(5);
function segs(obj) {
  obj.updateMatrixWorld(true);
  const g = obj.geometry, p = g.getAttribute('position'), idx = g.index;
  const out = [];
  const n = idx ? idx.count : p.count;
  for (let i = 0; i < n; i++) {
    const k = idx ? idx.getX(i) : i;
    const v = new THREE.Vector3().fromBufferAttribute(p, k).applyMatrix4(obj.matrixWorld);
    out.push(r(v.x), r(v.y), r(v.z));
  }
  return out;
}
const out = { frustum: segs(helper.frustumLines), cascades: [], shadows: [], planes: [] };
for (let i = 0; i < 3; i++) {
  out.cascades.push(segs(helper.cascadeLines[i]));
  out.shadows.push(segs(helper.shadowLines[i].children[0]));
  out.planes.push(segs(helper.cascadePlanes[i]));
}
out.lightPositions = csm.lights.map(l => [r(l.position.x), r(l.position.y), r(l.position.z)]);
out.extent = csm.lights.map(l => r(l.shadow.camera.right));
console.log(JSON.stringify(out));
