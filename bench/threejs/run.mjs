// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as THREE from "three";

const here = dirname(fileURLToPath(import.meta.url));
const catalog = JSON.parse(readFileSync(join(here, "../catalog.json"), "utf8"));

const name = process.argv[2];
if (!name) {
  console.error("usage: node run.mjs <example>");
  process.exit(2);
}

const spec = catalog.find((item) => item.name === name);
if (!spec) {
  console.error("unknown example:", name);
  process.exit(2);
}

function checkerTexture() {
  const size = 64;
  const data = new Uint8Array(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const on = ((x >> 3) + (y >> 3)) & 1;
      const i = (y * size + x) * 4;
      const v = on ? 245 : 35;
      data[i] = v;
      data[i + 1] = on ? 245 : 70;
      data[i + 2] = on ? 250 : 150;
      data[i + 3] = 255;
    }
  }
  const texture = new THREE.DataTexture(data, size, size);
  texture.wrapS = THREE.RepeatWrapping;
  texture.wrapT = THREE.RepeatWrapping;
  texture.needsUpdate = true;
  return texture;
}

function lights(scene, kind) {
  scene.add(new THREE.AmbientLight(0xffffff, kind === "additive" ? 0.05 : 0.25));
  if (kind === "lamps" || kind === "lit_scene") {
    const bulb = new THREE.PointLight(0xffdcb4, 1.5, 0, 2);
    bulb.position.set(0.8, 1.0, 1.5);
    scene.add(bulb);
    return;
  }
  if (kind === "additive") {
    const a = new THREE.PointLight(0xff4040, 1.2, 0, 2);
    a.position.set(-1.2, 0.8, 1.0);
    const b = new THREE.PointLight(0x40a0ff, 1.2, 0, 2);
    b.position.set(1.2, 0.8, 1.0);
    scene.add(a, b);
    return;
  }
  const lamp = new THREE.DirectionalLight(0xffffff, 0.75);
  lamp.position.set(0.4, 0.8, 0.5);
  scene.add(lamp);
}

function perspective(width, height, fov = 45) {
  const camera = new THREE.PerspectiveCamera(fov, width / height, 0.1, 100);
  camera.position.set(0, 0.6, 3);
  camera.lookAt(0, 0, 0);
  return camera;
}

function build(spec) {
  const { width, height, kind } = spec;
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x12141a);
  let camera = perspective(width, height);
  let subject = null;
  let extra = null;

  if (kind === "triangle" || kind === "spin" || kind === "edges") {
    const geo = new THREE.BufferGeometry();
    geo.setAttribute(
      "position",
      new THREE.Float32BufferAttribute([-0.8, -0.6, 0, 0, 0.8, 0, 0.8, -0.6, 0], 3),
    );
    subject = new THREE.Mesh(
      geo,
      new THREE.MeshBasicMaterial({ color: 0xff8020, side: THREE.DoubleSide }),
    );
    scene.add(subject);
    camera.position.set(0, 0, 3);
    camera.lookAt(0, 0, 0);
    return { scene, camera, subject, extra };
  }

  if (kind === "ortho") {
    const halfW = 2 * (width / height);
    camera = new THREE.OrthographicCamera(-halfW, halfW, 2, -2, 0.1, 100);
    camera.position.set(0, 0.6, 3);
    camera.lookAt(0, 0, 0);
  }

  if (kind === "uv" || kind === "floor") {
    subject = new THREE.Mesh(
      new THREE.PlaneGeometry(6, 6),
      new THREE.MeshLambertMaterial({
        color: 0xffffff,
        map: kind === "floor" ? checkerTexture() : null,
      }),
    );
    subject.rotation.x = -Math.PI / 2;
    scene.add(subject);
    lights(scene, kind);
    camera.position.set(0, 0.8, 3.4);
    camera.lookAt(0, 0, -1.5);
    return { scene, camera, subject, extra };
  }

  if (kind === "glass") {
    const pane = new THREE.MeshLambertMaterial({
      color: 0x88ccee,
      transparent: true,
      opacity: 0.35,
    });
    for (const x of [-0.7, 0, 0.7]) {
      const plane = new THREE.Mesh(new THREE.PlaneGeometry(0.8, 1.2), pane);
      plane.position.set(x, 0.2, 0.3);
      scene.add(plane);
    }
    subject = new THREE.Mesh(
      new THREE.BoxGeometry(0.6, 0.6, 0.6),
      new THREE.MeshLambertMaterial({ color: 0xff8c28 }),
    );
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "instances") {
    const mesh = new THREE.InstancedMesh(
      new THREE.BoxGeometry(0.25, 0.25, 0.25),
      new THREE.MeshLambertMaterial({ color: 0x50d0a0 }),
      24,
    );
    const m = new THREE.Matrix4();
    let i = 0;
    for (let y = 0; y < 3; y++) {
      for (let x = 0; x < 8; x++) {
        m.makeTranslation((x - 3.5) * 0.35, (y - 1) * 0.35, 0);
        mesh.setMatrixAt(i, m);
        i += 1;
      }
    }
    subject = mesh;
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "geometry") {
    subject = new THREE.Mesh(
      new THREE.TorusKnotGeometry(0.7, 0.22, 64, 12),
      new THREE.MeshLambertMaterial({ color: 0x40b4ff }),
    );
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "curves") {
    const curve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(-1, 0, 0),
      new THREE.Vector3(-0.3, 0.6, 0.2),
      new THREE.Vector3(0.3, -0.4, -0.2),
      new THREE.Vector3(1, 0.2, 0),
    ]);
    subject = new THREE.Mesh(
      new THREE.TubeGeometry(curve, 48, 0.12, 8, false),
      new THREE.MeshLambertMaterial({ color: 0xffc040 }),
    );
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "phong") {
    subject = new THREE.Mesh(
      new THREE.SphereGeometry(0.9, 32, 16),
      new THREE.MeshPhongMaterial({ color: 0x4488ff, shininess: 40 }),
    );
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "normals") {
    subject = new THREE.Mesh(
      new THREE.SphereGeometry(0.9, 24, 16),
      new THREE.MeshNormalMaterial(),
    );
    scene.add(subject);
    return { scene, camera, subject, extra };
  }

  if (kind === "fragments") {
    subject = new THREE.Mesh(
      new THREE.SphereGeometry(0.9, 8, 6),
      new THREE.MeshLambertMaterial({ color: 0xff8040 }),
    );
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "gpu_backend") {
    subject = new THREE.Mesh(
      new THREE.IcosahedronGeometry(1.05, 1),
      new THREE.MeshLambertMaterial({ color: 0x50d296 }),
    );
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "fog") {
    scene.fog = new THREE.Fog(0x12141a, 1.5, 8);
    subject = new THREE.Mesh(
      new THREE.BoxGeometry(1, 1, 1),
      new THREE.MeshLambertMaterial({ color: 0xff8c28 }),
    );
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "exposure") {
    subject = new THREE.Mesh(
      new THREE.BoxGeometry(1, 1, 1),
      new THREE.MeshLambertMaterial({ color: 0xffe0a0 }),
    );
    scene.add(subject);
    lights(scene, kind);
    extra = { toneMapping: THREE.ACESFilmicToneMapping, exposure: 0.8 };
    return { scene, camera, subject, extra };
  }

  if (kind === "raycast") {
    subject = new THREE.Mesh(
      new THREE.SphereGeometry(0.9, 24, 16),
      new THREE.MeshLambertMaterial({ color: 0x80c0ff }),
    );
    scene.add(subject);
    lights(scene, kind);
    extra = { raycaster: new THREE.Raycaster() };
    return { scene, camera, subject, extra };
  }

  if (kind === "chain") {
    let parent = scene;
    for (let i = 0; i < 5; i++) {
      const link = new THREE.Mesh(
        new THREE.BoxGeometry(0.35, 0.35, 0.35),
        new THREE.MeshLambertMaterial({ color: 0xff8c28 }),
      );
      link.position.x = i === 0 ? -0.8 : 0.4;
      parent.add(link);
      if (i === 0) subject = link;
      parent = link;
    }
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "cubes") {
    const big = new THREE.Mesh(
      new THREE.BoxGeometry(1.2, 1.2, 1.2),
      new THREE.MeshLambertMaterial({ color: 0xff8c28 }),
    );
    const moon = new THREE.Mesh(
      new THREE.BoxGeometry(0.4, 0.4, 0.4),
      new THREE.MeshLambertMaterial({ color: 0x40a0ff }),
    );
    moon.position.set(1.6, 0.3, 0);
    const pivot = new THREE.Group();
    pivot.add(moon);
    scene.add(big, pivot);
    subject = pivot;
    extra = { moon };
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "keyframes") {
    subject = new THREE.Mesh(
      new THREE.BoxGeometry(1, 1, 1),
      new THREE.MeshLambertMaterial({ color: 0xff8c28 }),
    );
    scene.add(subject);
    const clip = new THREE.AnimationClip("turn", 1, [
      new THREE.NumberKeyframeTrack(".rotation[y]", [0, 1], [0, Math.PI * 2]),
    ]);
    const mixer = new THREE.AnimationMixer(subject);
    mixer.clipAction(clip).play();
    extra = { mixer };
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "skinning") {
    const geo = new THREE.BoxGeometry(0.35, 2, 0.35, 1, 8, 1);
    const pos = geo.attributes.position;
    const skinIndex = new THREE.Uint16BufferAttribute(pos.count * 4, 4);
    const skinWeight = new THREE.Float32BufferAttribute(pos.count * 4, 4);
    for (let i = 0; i < pos.count; i++) {
      const y = pos.getY(i);
      const w = THREE.MathUtils.clamp((y + 1) / 2, 0, 1);
      skinIndex.setXYZW(i, 0, 1, 0, 0);
      skinWeight.setXYZW(i, 1 - w, w, 0, 0);
    }
    geo.setAttribute("skinIndex", skinIndex);
    geo.setAttribute("skinWeight", skinWeight);
    const root = new THREE.Bone();
    const tip = new THREE.Bone();
    tip.position.y = 1;
    root.add(tip);
    subject = new THREE.SkinnedMesh(
      geo,
      new THREE.MeshLambertMaterial({ color: 0xe0a060 }),
    );
    const skeleton = new THREE.Skeleton([root, tip]);
    subject.add(root);
    subject.bind(skeleton);
    extra = { tip };
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "orbit") {
    subject = new THREE.Mesh(
      new THREE.SphereGeometry(0.25, 16, 12),
      new THREE.MeshLambertMaterial({ color: 0x40a0ff }),
    );
    extra = { pivot: new THREE.Group() };
    extra.pivot.add(subject);
    subject.position.set(1.4, 0, 0);
    scene.add(extra.pivot);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  const material =
    kind === "textured" || kind === "photo" || kind === "lit_scene"
      ? new THREE.MeshLambertMaterial({ color: 0xffffff, map: checkerTexture() })
      : kind === "lamps"
        ? new THREE.MeshLambertMaterial({ color: 0xf0f0f0 })
        : new THREE.MeshLambertMaterial({ color: 0xff8c28 });
  const geometry =
    kind === "lamps"
      ? new THREE.SphereGeometry(0.7, 24, 16)
      : new THREE.BoxGeometry(1, 1, 1);
  subject = new THREE.Mesh(geometry, material);
  if (kind === "culling") {
    subject.position.z = 4;
  }
  scene.add(subject);
  lights(scene, kind);
  return { scene, camera, subject, extra };
}

function step(world, spec, frame) {
  const { subject, extra, camera } = world;
  const t = spec.frames <= 1 ? 0 : frame / spec.frames;
  const turn = t * Math.PI * 2;
  if (spec.kind === "raycast" && extra?.raycaster) {
    extra.raycaster.setFromCamera(new THREE.Vector2(0, 0), camera);
    extra.raycaster.intersectObject(subject);
  }
  if (spec.kind === "keyframes" && extra?.mixer) {
    extra.mixer.update(1 / spec.frames);
    return;
  }
  if (spec.kind === "skinning" && extra?.tip) {
    extra.tip.rotation.z = Math.sin(turn) * 0.6;
    return;
  }
  if (spec.kind === "orbit" && extra?.pivot) {
    extra.pivot.rotation.y = turn;
    return;
  }
  if (spec.kind === "photo") {
    camera.position.set(Math.sin(turn) * 3, 0.6, Math.cos(turn) * 3);
    camera.lookAt(0, 0, 0);
    return;
  }
  if (spec.kind === "culling") {
    subject.position.z = 4 - t * 6;
  }
  if (subject) {
    subject.rotation.y = turn;
  }
}

function tryWebGL(width, height) {
  try {
    const require = createRequire(import.meta.url);
    const createContext = require("gl");
    const gl = createContext(width, height, { preserveDrawingBuffer: true });
    if (!gl) return null;
    const renderer = new THREE.WebGLRenderer({
      context: gl,
      antialias: false,
    });
    renderer.setSize(width, height, false);
    return { kind: "webgl", renderer, pixels: new Uint8Array(width * height * 4) };
  } catch {
    return null;
  }
}

function softwareTarget(width, height) {
  return {
    kind: "cpu",
    color: new Uint8Array(width * height * 4),
    depth: new Float32Array(width * height),
  };
}

function projectPoint(vector, camera, width, height, out) {
  out.copy(vector).project(camera);
  out.x = (out.x * 0.5 + 0.5) * width;
  out.y = (-out.y * 0.5 + 0.5) * height;
  return out;
}

function fillTriangle(target, width, height, ax, ay, az, bx, by, bz, cx, cy, cz, r, g, b) {
  let minX = Math.max(0, Math.floor(Math.min(ax, bx, cx)));
  let maxX = Math.min(width - 1, Math.ceil(Math.max(ax, bx, cx)));
  let minY = Math.max(0, Math.floor(Math.min(ay, by, cy)));
  let maxY = Math.min(height - 1, Math.ceil(Math.max(ay, by, cy)));
  const area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  if (area === 0) return;
  const inv = 1 / area;
  for (let y = minY; y <= maxY; y++) {
    for (let x = minX; x <= maxX; x++) {
      const w0 = ((bx - x) * (cy - y) - (by - y) * (cx - x)) * inv;
      const w1 = ((cx - x) * (ay - y) - (cy - y) * (ax - x)) * inv;
      const w2 = 1 - w0 - w1;
      if (w0 < 0 || w1 < 0 || w2 < 0) continue;
      const z = w0 * az + w1 * bz + w2 * cz;
      const di = y * width + x;
      if (z >= target.depth[di]) continue;
      target.depth[di] = z;
      const i = di * 4;
      target.color[i] = r;
      target.color[i + 1] = g;
      target.color[i + 2] = b;
      target.color[i + 3] = 255;
    }
  }
}

const _a = new THREE.Vector3();
const _b = new THREE.Vector3();
const _c = new THREE.Vector3();
const _pa = new THREE.Vector3();
const _pb = new THREE.Vector3();
const _pc = new THREE.Vector3();
const _color = new THREE.Color();
const _matrix = new THREE.Matrix4();

function drawSoftware(target, scene, camera, width, height) {
  target.color.fill(18);
  for (let i = 3; i < target.color.length; i += 4) target.color[i] = 255;
  target.depth.fill(1);
  scene.updateMatrixWorld(true);
  camera.updateMatrixWorld(true);
  scene.traverse((obj) => {
    if (!obj.isMesh && !obj.isInstancedMesh) return;
    const geom = obj.geometry;
    const pos = geom.attributes.position;
    if (!pos) return;
    obj.material.color ? _color.copy(obj.material.color) : _color.set(0xffffff);
    const r = Math.round(_color.r * 255);
    const g = Math.round(_color.g * 255);
    const b = Math.round(_color.b * 255);
    const index = geom.index;
    const triCount = index ? index.count / 3 : pos.count / 3;
    const instances = obj.isInstancedMesh ? obj.count : 1;
    for (let inst = 0; inst < instances; inst++) {
      if (obj.isInstancedMesh) {
        obj.getMatrixAt(inst, _matrix);
        _matrix.premultiply(obj.matrixWorld);
      } else {
        _matrix.copy(obj.matrixWorld);
      }
      for (let t = 0; t < triCount; t++) {
        const i0 = index ? index.getX(t * 3) : t * 3;
        const i1 = index ? index.getX(t * 3 + 1) : t * 3 + 1;
        const i2 = index ? index.getX(t * 3 + 2) : t * 3 + 2;
        _a.fromBufferAttribute(pos, i0).applyMatrix4(_matrix);
        _b.fromBufferAttribute(pos, i1).applyMatrix4(_matrix);
        _c.fromBufferAttribute(pos, i2).applyMatrix4(_matrix);
        projectPoint(_a, camera, width, height, _pa);
        projectPoint(_b, camera, width, height, _pb);
        projectPoint(_c, camera, width, height, _pc);
        fillTriangle(
          target,
          width,
          height,
          _pa.x,
          _pa.y,
          _pa.z,
          _pb.x,
          _pb.y,
          _pb.z,
          _pc.x,
          _pc.y,
          _pc.z,
          r,
          g,
          b,
        );
      }
    }
  });
}

function drawWebGL(target, scene, camera) {
  if (target.extra?.toneMapping != null) {
    target.renderer.toneMapping = target.extra.toneMapping;
    target.renderer.toneMappingExposure = target.extra.exposure;
  }
  target.renderer.render(scene, camera);
  const gl = target.renderer.getContext();
  gl.readPixels(
    0,
    0,
    spec.width,
    spec.height,
    gl.RGBA,
    gl.UNSIGNED_BYTE,
    target.pixels,
  );
}

const world = build(spec);
let backend = tryWebGL(spec.width, spec.height);
if (backend) backend.extra = world.extra;
if (!backend) backend = softwareTarget(spec.width, spec.height);

function drawFrames(target) {
  for (let frame = 0; frame < spec.frames; frame++) {
    step(world, spec, frame);
    if (target.kind === "webgl") {
      drawWebGL(target, world.scene, world.camera);
    } else {
      drawSoftware(target, world.scene, world.camera, spec.width, spec.height);
    }
  }
}

try {
  drawFrames(backend);
} catch (err) {
  if (backend.kind !== "webgl") throw err;
  backend = softwareTarget(spec.width, spec.height);
  drawFrames(backend);
}

const sample =
  backend.kind === "webgl" ? backend.pixels[0] : backend.color[0];
console.log(
  JSON.stringify({
    name: spec.name,
    width: spec.width,
    height: spec.height,
    frames: spec.frames,
    backend: backend.kind,
    sample,
  }),
);
