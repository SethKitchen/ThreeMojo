// Print what three.js 0.180 computes for the scene objects of
// `tests/test_scene_objects.mojo` and `tests/test_marching_cubes.mojo`, as
// the JSON in `reference.json` beside this file.
//
// Run it with node 22 from a folder whose `node_modules` holds three.js
// 0.180: `node reference.mjs > reference.json`.
import * as THREE from 'three';
import { MarchingCubes } from 'three/addons/objects/MarchingCubes.js';
import { GroundedSkybox } from 'three/addons/objects/GroundedSkybox.js';
import { ShadowMesh } from 'three/addons/objects/ShadowMesh.js';
import { Reflector } from 'three/addons/objects/Reflector.js';
import { Refractor } from 'three/addons/objects/Refractor.js';
import { Water } from 'three/addons/objects/Water.js';
import { Water as Water2 } from 'three/addons/objects/Water2.js';

const out = {};
const list = (array) => Array.from(array);

// --- marching cubes -----------------------------------------------------------

function surface(cubes) {
  const n = cubes.count;
  const result = {
    count: n,
    position: list(cubes.positionArray.slice(0, n * 3)),
    normal: list(cubes.normalArray.slice(0, n * 3)),
  };
  if (cubes.enableUvs) result.uv = list(cubes.uvArray.slice(0, n * 2));
  if (cubes.enableColors) result.color = list(cubes.colorArray.slice(0, n * 3));
  return result;
}

{
  const material = new THREE.MeshBasicMaterial();
  const cubes = new MarchingCubes(10, material, true, true, 10000);
  cubes.reset();
  cubes.addBall(0.45, 0.5, 0.52, 0.5, 12);
  cubes.addBall(0.62, 0.55, 0.43, 0.35, 12, new THREE.Color(1, 0.25, 0));
  cubes.addPlaneY(2, 12);
  cubes.update();
  out.balls = surface(cubes);
  // Without a reset, the normals of the first field stay cached.
  cubes.addBall(0.4, 0.4, 0.4, 0.3, 12);
  cubes.update();
  out.cached = surface(cubes);
}

{
  const material = new THREE.MeshStandardMaterial({ flatShading: true });
  const cubes = new MarchingCubes(8, material, false, false, 10000);
  cubes.isolation = 60;
  cubes.addBall(0.5, 0.5, 0.5, 0.9, 10);
  cubes.addBall(0.55, 0.45, 0.5, -0.2, 20);
  cubes.addPlaneX(1.5, 10);
  cubes.addPlaneZ(1.5, 10);
  cubes.setCell(4, 4, 4, 300);
  cubes.blur(0.5);
  cubes.update();
  out.flat = surface(cubes);
  out.flat.cell = cubes.getCell(3, 4, 4);
}

// --- grounded skybox ----------------------------------------------------------

{
  const skybox = new GroundedSkybox(null, 2, 10, 4);
  out.skybox = {
    position: list(skybox.geometry.getAttribute('position').array),
    normal: list(skybox.geometry.getAttribute('normal').array),
    index: list(skybox.geometry.index.array),
  };
}

// --- shadow mesh ----------------------------------------------------------------

{
  const caster = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1));
  caster.position.set(0.5, 2, -0.25);
  caster.rotation.set(0.3, 0.6, 0.1);
  caster.updateMatrixWorld();
  const shadow = new ShadowMesh(caster);
  const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0.01);
  shadow.update(plane, new THREE.Vector4(2, 5, 1, 1));
  out.shadow_point = list(shadow.matrix.elements);
  shadow.update(plane, new THREE.Vector4(0.3, 1, 0.2, 0));
  out.shadow_direction = list(shadow.matrix.elements);
}

// --- reflector, refractor and waters ------------------------------------------

// A renderer that renders nothing, for `onBeforeRender`.
const renderer = {
  autoClear: true,
  xr: { enabled: false },
  shadowMap: { autoUpdate: true },
  state: { buffers: { depth: { setMask() {} } } },
  getRenderTarget() { return null; },
  setRenderTarget() {},
  clear() {},
  render() {},
};

function camera() {
  const eye = new THREE.PerspectiveCamera(45, 1.25, 0.1, 100);
  eye.position.set(1, 2, 3);
  eye.lookAt(0.2, -0.3, 0.1);
  eye.updateMatrixWorld();
  return eye;
}

function place(object) {
  object.position.set(0.3, -0.5, 0.2);
  object.rotation.set(-Math.PI / 2 + 0.2, 0.1, 0.3);
  object.updateMatrixWorld();
}

const scene = new THREE.Scene();

{
  const reflector = new Reflector(new THREE.PlaneGeometry(2, 2));
  place(reflector);
  reflector.onBeforeRender(renderer, scene, camera());
  out.reflector = {
    view: list(reflector.camera.matrixWorldInverse.elements),
    texture_matrix: list(reflector.material.uniforms.textureMatrix.value.elements),
  };
}

{
  const refractor = new Refractor(new THREE.PlaneGeometry(2, 2));
  place(refractor);
  refractor.onBeforeRender(renderer, scene, camera());
  out.refractor = {
    view: list(refractor.camera.matrixWorldInverse.elements),
    texture_matrix: list(refractor.material.uniforms.textureMatrix.value.elements),
  };
}

{
  const water = new Water(new THREE.PlaneGeometry(2, 2), { waterNormals: new THREE.Texture() });
  place(water);
  water.onBeforeRender(renderer, scene, camera());
  out.water = {
    texture_matrix: list(water.material.uniforms.textureMatrix.value.elements),
    eye: water.material.uniforms.eye.value.toArray(),
  };
}

{
  // A clock that reads the times given, in milliseconds.
  const times = [1000, 1000, 1700, 4200, 5100, 5100, 9000];
  let at = 0;
  const now = performance.now.bind(performance);
  performance.now = () => times[Math.min(at++, times.length - 1)];
  const water = new Water2(new THREE.PlaneGeometry(2, 2), {
    normalMap0: new THREE.Texture(),
    normalMap1: new THREE.Texture(),
    flowSpeed: 0.04,
  });
  place(water);
  const configs = [];
  for (let frame = 0; frame < 6; frame++) {
    water.onBeforeRender(renderer, scene, camera());
    configs.push(water.material.uniforms.config.value.toArray());
  }
  performance.now = now;
  out.water2 = {
    texture_matrix: list(water.material.uniforms.textureMatrix.value.elements),
    configs,
  };
}

console.log(JSON.stringify(out));
