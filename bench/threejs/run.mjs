// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// Imported here rather than statically so the cost of loading three.js can
// be measured apart from the frames. It is most of what this process does:
// the module is large, and Node parses and compiles it before a single
// triangle is drawn. The number goes out in the JSON line below.
const importStarted = performance.now();
const THREE = await import("three");
const importMs = performance.now() - importStarted;

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

let TeapotGeometry = null;
let MarchingCubes = null;
if (name === "utah") {
  ({ TeapotGeometry } = await import("three/addons/geometries/TeapotGeometry.js"));
}
if (name === "blobs") {
  ({ MarchingCubes } = await import("three/addons/objects/MarchingCubes.js"));
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
  scene.add(new THREE.AmbientLight(0xffffff, kind === "additive" ? 0.16 : 0.79));
  if (kind === "lamps" || kind === "lit_scene") {
    const bulb = new THREE.PointLight(0xffdcb4, 4.71, 0, 2);
    bulb.position.set(0.8, 1.0, 1.5);
    scene.add(bulb);
    return;
  }
  if (kind === "additive") {
    const a = new THREE.PointLight(0xff4040, 3.77, 0, 2);
    a.position.set(-1.2, 0.8, 1.0);
    const b = new THREE.PointLight(0x40a0ff, 3.77, 0, 2);
    b.position.set(1.2, 0.8, 1.0);
    scene.add(a, b);
    return;
  }
  const lamp = new THREE.DirectionalLight(0xffffff, 2.36);
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

  if (kind === "lines" || kind === "sprites" || kind === "outlines" || kind === "gizmo") {
    subject = new THREE.Mesh(
      new THREE.BoxGeometry(0.8, 0.8, 0.8),
      new THREE.MeshLambertMaterial({ color: kind === "gizmo" ? 0x466ec8 : 0xff8c28 }),
    );
    scene.add(subject);
    if (kind === "gizmo" || kind === "sprites") {
      const ball = new THREE.Mesh(
        new THREE.SphereGeometry(0.28, 16, 12),
        new THREE.MeshLambertMaterial({ color: 0xe68c3c }),
      );
      ball.position.set(0.85, 0.1, 0.35);
      scene.add(ball);
    }
    if (kind === "lines" || kind === "sprites") {
      const curve = new THREE.CatmullRomCurve3([
        new THREE.Vector3(-1, 0.2, 0),
        new THREE.Vector3(0, 0.8, 0.4),
        new THREE.Vector3(1, 0.2, 0),
      ]);
      const path = new THREE.Mesh(
        new THREE.TubeGeometry(curve, 24, kind === "sprites" ? 0.02 : 0.015, 4, false),
        new THREE.MeshBasicMaterial({ color: 0xffe080 }),
      );
      scene.add(path);
    }
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "wide") {
    subject = new THREE.Mesh(
      new THREE.BoxGeometry(0.7, 0.7, 0.7),
      new THREE.MeshLambertMaterial({ color: 0x3c5aa0 }),
    );
    const ribbon = new THREE.Mesh(
      new THREE.TorusGeometry(1.05, 0.06, 8, 48),
      new THREE.MeshBasicMaterial({ color: 0x40d0a0 }),
    );
    subject.add(ribbon);
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "stereo" || kind === "split") {
    subject = new THREE.Mesh(
      new THREE.BoxGeometry(0.8, 0.8, 0.8),
      new THREE.MeshLambertMaterial({ color: 0x466ec8 }),
    );
    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(0.5, 0.12, 8, 24),
      new THREE.MeshLambertMaterial({ color: 0xe6b43c }),
    );
    ring.position.set(0.3, 0.1, 0.4);
    scene.add(subject, ring);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "television" || kind === "json_scene") {
    subject = new THREE.Mesh(
      new THREE.BoxGeometry(0.9, 0.9, 0.9),
      new THREE.MeshLambertMaterial({ color: kind === "television" ? 0xffffff : 0xe68c32 }),
    );
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "mirror") {
    subject = new THREE.Mesh(
      new THREE.SphereGeometry(0.7, 24, 16),
      new THREE.MeshLambertMaterial({ color: 0xd0d4dc }),
    );
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "physical") {
    const group = new THREE.Group();
    for (let row = 0; row < 2; row++) {
      for (let column = 0; column < 5; column++) {
        const sphere = new THREE.Mesh(
          new THREE.SphereGeometry(0.5, 16, 12),
          new THREE.MeshStandardMaterial({
            color: 0xc83c32,
            roughness: 1 - column / 4,
            metalness: row,
          }),
        );
        sphere.position.set((column - 2) * 1.15, (0.5 - row) * 1.15, 0);
        group.add(sphere);
      }
    }
    subject = group;
    scene.add(subject);
    lights(scene, kind);
    camera.position.set(0, 0.3, 6.2);
    camera.lookAt(0, 0, 0);
    return { scene, camera, subject, extra };
  }

  if (kind === "shadows") {
    const sun = new THREE.DirectionalLight(0xfff8ec, 2.8);
    sun.position.set(2.2, 2.6, 0);
    sun.castShadow = true;
    scene.add(sun, new THREE.AmbientLight(0xb4bed2, 0.35));
    const floor = new THREE.Mesh(
      new THREE.PlaneGeometry(4, 4),
      new THREE.MeshLambertMaterial({ color: 0x969aa4 }),
    );
    floor.rotation.x = -Math.PI / 2;
    floor.receiveShadow = true;
    const box = new THREE.Mesh(
      new THREE.BoxGeometry(0.9, 0.9, 0.9),
      new THREE.MeshLambertMaterial({ color: 0xe68c32 }),
    );
    box.position.y = 0.45;
    box.castShadow = true;
    box.receiveShadow = true;
    scene.add(floor, box);
    camera.position.set(2.4, 1.8, 2.6);
    camera.lookAt(0, 0.2, 0);
    extra = { lamp: sun };
    return { scene, camera, subject, extra };
  }

  if (kind === "transmission") {
    const glass = new THREE.Mesh(
      new THREE.SphereGeometry(0.62, 24, 16),
      new THREE.MeshPhysicalMaterial({
        color: 0xffffff,
        roughness: 0.04,
        transmission: 1,
        thickness: 0.7,
        ior: 1.5,
        attenuationColor: 0xbedcff,
        attenuationDistance: 1.4,
      }),
    );
    scene.add(glass);
    const colors = [0xd23228, 0x28aa46, 0x285ac8];
    colors.forEach((color, index) => {
      const box = new THREE.Mesh(
        new THREE.BoxGeometry(0.7, 0.7, 0.7),
        new THREE.MeshLambertMaterial({ color }),
      );
      box.position.set((index - 1) * 1.15, 0, -1.35);
      scene.add(box);
    });
    subject = glass;
    lights(scene, kind);
    extra = { orbit: true };
    return { scene, camera, subject, extra };
  }

  if (kind === "distance") {
    // three.js fills MeshDistanceMaterial only while drawing a point-light
    // shadow, from that light's matrix. A normal material is the sphere the
    // bench can draw on its own.
    subject = new THREE.Mesh(
      new THREE.SphereGeometry(1, 24, 16),
      new THREE.MeshNormalMaterial(),
    );
    scene.add(subject);
    return { scene, camera, subject, extra };
  }

  if (kind === "unfogged") {
    scene.fog = new THREE.Fog(0xaab2be, 2.2, 9);
    const depths = [0.4, -1.5, -2.2];
    depths.forEach((z, index) => {
      const box = new THREE.Mesh(
        new THREE.BoxGeometry(0.7, 0.7, 0.7),
        new THREE.MeshLambertMaterial({ color: 0xe68c28, fog: index !== 1 }),
      );
      box.position.set((index - 1) * 1.15, 0, z);
      if (index === 0) subject = box;
      scene.add(box);
    });
    lights(scene, kind);
    extra = { dolly: true };
    return { scene, camera, subject, extra };
  }

  if (kind === "targets") {
    subject = new THREE.Mesh(
      new THREE.SphereGeometry(0.85, 24, 16),
      new THREE.MeshLambertMaterial({ color: 0xb4bac4 }),
    );
    scene.add(subject);
    const bulb = new THREE.PointLight(0xffdcaa, 8, 0, 2);
    bulb.position.set(0.7, 0.9, 1.1);
    scene.add(bulb, new THREE.AmbientLight(0xffffff, 0.15));
    return { scene, camera, subject, extra };
  }

  if (kind === "layers") {
    const specs = [
      {
        x: -1.25,
        material: new THREE.MeshPhysicalMaterial({
          color: 0x320c24,
          roughness: 0.9,
          sheen: 1,
          sheenColor: new THREE.Color(0xff82be),
          sheenRoughness: 0.35,
        }),
      },
      {
        x: 0,
        material: new THREE.MeshPhysicalMaterial({
          color: 0xb4b4be,
          roughness: 0.15,
          metalness: 1,
          iridescence: 1,
          iridescenceIOR: 1.3,
          iridescenceThicknessRange: [100, 400],
        }),
      },
      {
        x: 1.25,
        material: new THREE.MeshPhysicalMaterial({
          color: 0xd4a040,
          roughness: 0.28,
          metalness: 1,
          anisotropy: 0.85,
          anisotropyRotation: Math.PI / 2,
        }),
      },
    ];
    const group = new THREE.Group();
    for (const spec of specs) {
      const sphere = new THREE.Mesh(new THREE.SphereGeometry(0.55, 24, 16), spec.material);
      sphere.position.x = spec.x;
      group.add(sphere);
    }
    subject = group;
    scene.add(subject);
    lights(scene, kind);
    extra = { orbit: true };
    return { scene, camera, subject, extra };
  }

  if (kind === "graph") {
    subject = new THREE.Mesh(
      new THREE.SphereGeometry(0.9, 24, 16),
      new THREE.MeshStandardMaterial({ color: 0xff8c28, roughness: 0.45 }),
    );
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "coats") {
    function coatMap() {
      const w = 8;
      const h = 2;
      const data = new Uint8Array(w * h * 4);
      for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
          const i = (y * w + x) * 4;
          const on = x % 2 === 0 ? 255 : 0;
          data[i] = on;
          data[i + 3] = 255;
        }
      }
      const texture = new THREE.DataTexture(data, w, h);
      texture.colorSpace = THREE.NoColorSpace;
      texture.needsUpdate = true;
      return texture;
    }
    function tintMap() {
      const size = 4;
      const data = new Uint8Array(size * size * 4);
      for (let y = 0; y < size; y++) {
        for (let x = 0; x < size; x++) {
          const i = (y * size + x) * 4;
          const gold = (x + y) % 2 === 0;
          data[i] = gold ? 255 : 64;
          data[i + 1] = gold ? 184 : 115;
          data[i + 2] = gold ? 51 : 255;
          data[i + 3] = 255;
        }
      }
      const texture = new THREE.DataTexture(data, size, size);
      texture.colorSpace = THREE.NoColorSpace;
      texture.needsUpdate = true;
      return texture;
    }
    const lacquer = new THREE.Mesh(
      new THREE.SphereGeometry(0.62, 32, 20),
      new THREE.MeshPhysicalMaterial({
        color: 0xaa1c1c,
        roughness: 0.55,
        clearcoat: 1,
        clearcoatRoughness: 0.05,
        clearcoatMap: coatMap(),
      }),
    );
    lacquer.position.x = -0.85;
    const plastic = new THREE.Mesh(
      new THREE.SphereGeometry(0.62, 32, 20),
      new THREE.MeshPhysicalMaterial({
        color: 0x96989e,
        roughness: 0.35,
        specularIntensity: 1,
        specularColorMap: tintMap(),
      }),
    );
    plastic.position.x = 0.85;
    scene.add(lacquer, plastic);
    subject = lacquer;
    lights(scene, kind);
    extra = { orbit: true };
    return { scene, camera, subject, extra };
  }

  if (kind === "skyjson") {
    const images = [0xdc3228, 0x2846c8, 0xebebf0, 0x282a30, 0x28aa46, 0xe6b428].map(
      (hex) => {
        const data = new Uint8Array(16 * 16 * 4);
        const color = new THREE.Color(hex);
        for (let i = 0; i < 16 * 16; i++) {
          data[i * 4] = Math.round(color.r * 255);
          data[i * 4 + 1] = Math.round(color.g * 255);
          data[i * 4 + 2] = Math.round(color.b * 255);
          data[i * 4 + 3] = 255;
        }
        const face = new THREE.DataTexture(data, 16, 16);
        face.needsUpdate = true;
        return face;
      },
    );
    const sky = new THREE.CubeTexture(images);
    sky.needsUpdate = true;
    scene.background = sky;
    scene.environment = sky;
    subject = new THREE.Mesh(
      new THREE.SphereGeometry(0.7, 24, 16),
      new THREE.MeshStandardMaterial({ color: 0xdcdce0, roughness: 0.12, metalness: 1 }),
    );
    scene.add(subject);
    lights(scene, kind);
    return { scene, camera, subject, extra };
  }

  if (kind === "daylight") {
    scene.add(
      new THREE.Mesh(
        new THREE.BoxGeometry(40, 40, 40),
        new THREE.MeshBasicMaterial({ color: 0x87b4e0, side: THREE.BackSide }),
      ),
    );
    subject = new THREE.Mesh(
      new THREE.SphereGeometry(0.7, 24, 16),
      new THREE.MeshLambertMaterial({ color: 0xd2c8b9 }),
    );
    subject.position.set(0, 0.15, -1.6);
    scene.add(subject);
    const lamp = new THREE.DirectionalLight(0xfff4dc, 2.2);
    lamp.position.set(4, 2, -1);
    scene.add(lamp, new THREE.AmbientLight(0xb4c8e6, 0.45));
    camera = perspective(width, height, 50);
    camera.position.set(0, 0.25, 1.5);
    camera.lookAt(0, 0.45, -1.6);
    extra = { sun: lamp };
    return { scene, camera, subject, extra };
  }

  if (kind === "faces") {
    const colors = [0xd23228, 0x285ac8, 0x28aa46, 0xe6aa28, 0x9646be, 0xe6e6eb];
    subject = new THREE.Mesh(
      new THREE.BoxGeometry(1.1, 1.1, 1.1),
      colors.map((color) => new THREE.MeshLambertMaterial({ color })),
    );
    scene.add(subject);
    lights(scene, kind);
    camera = perspective(width, height, 38);
    camera.position.set(0.6, 0.7, 3.1);
    camera.lookAt(0, 0, 0);
    extra = { tumble: true };
    return { scene, camera, subject, extra };
  }

  if (kind === "utah") {
    subject = new THREE.Mesh(
      new TeapotGeometry(0.85, 6, true, true, true, true, true),
      new THREE.MeshLambertMaterial({ color: 0xc49a76 }),
    );
    subject.position.y = -0.15;
    scene.add(subject);
    lights(scene, kind);
    camera = perspective(width, height, 38);
    camera.position.set(1.5, 1.05, 2.3);
    camera.lookAt(0, 0.2, 0);
    return { scene, camera, subject, extra };
  }

  if (kind === "blobs") {
    const material = new THREE.MeshLambertMaterial({ color: 0xffffff, vertexColors: true });
    const field = new MarchingCubes(16, material, false, true, 20000);
    field.isolation = 80;
    field.addBall(0.42, 0.52, 0.5, 1.2, 12, new THREE.Color(1, 0.35, 0.12));
    field.addBall(0.58, 0.5, 0.48, 1.0, 12, new THREE.Color(0.2, 0.45, 1));
    field.scale.set(1.45, 1.45, 1.45);
    scene.add(field);
    subject = field;
    lights(scene, kind);
    camera = perspective(width, height, 38);
    camera.position.set(0.9, 0.55, 2.4);
    camera.lookAt(0, 0, 0);
    return { scene, camera, subject, extra };
  }

  if (kind === "basis") {
    const group = new THREE.Group();
    for (let index = 0; index < 3; index++) {
      const panel = new THREE.Mesh(
        new THREE.PlaneGeometry(0.9, 0.9),
        new THREE.MeshBasicMaterial({ color: [0xc04040, 0x40a060, 0x4060c0][index], map: checkerTexture() }),
      );
      panel.position.x = (index - 1) * 1.05;
      group.add(panel);
    }
    subject = group;
    scene.add(subject);
    return { scene, camera, subject, extra };
  }

  if (kind === "bloom" || kind === "reloaded") {
    subject = new THREE.Mesh(
      kind === "bloom"
        ? new THREE.TorusKnotGeometry(0.55, 0.16, 64, 8)
        : new THREE.TorusKnotGeometry(0.62, 0.18, 72, 10),
      new THREE.MeshLambertMaterial({ color: kind === "bloom" ? 0x1c1e26 : 0x4696dc }),
    );
    scene.add(subject);
    if (kind === "bloom") {
      for (const place of [
        [-0.85, 0.35, 0.2, 0xffc440],
        [0.9, -0.15, -0.15, 0x50dcff],
      ]) {
        const glow = new THREE.Mesh(
          new THREE.SphereGeometry(0.22, 16, 12),
          new THREE.MeshStandardMaterial({
            color: place[3],
            emissive: place[3],
            emissiveIntensity: 2,
          }),
        );
        glow.position.set(place[0], place[1], place[2]);
        scene.add(glow);
      }
    }
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
  if (spec.kind === "shadows" && extra?.lamp) {
    extra.lamp.position.set(Math.cos(turn) * 2.2, 2.6, Math.sin(turn) * 2.2);
    return;
  }
  if (spec.kind === "daylight" && extra?.sun) {
    const sunTurn = t * Math.PI;
    const sun = new THREE.Vector3(Math.cos(sunTurn) * 0.4, Math.sin(sunTurn), -0.6);
    extra.sun.position.set(sun.x * 8, sun.y * 8, sun.z * 4);
    return;
  }
  if (extra?.tumble && subject) {
    subject.rotation.y = turn;
    subject.rotation.x = turn * 0.35;
    return;
  }
  if (extra?.orbit) {
    camera.position.set(Math.sin(turn) * 3.3, 0.35, Math.cos(turn) * 3.3);
    camera.lookAt(0, 0, 0);
    if (subject) subject.rotation.y = turn;
    return;
  }
  if (extra?.dolly) {
    camera.position.set(0, 0.45, 4.2 + 1.6 * Math.cos(turn));
    camera.lookAt(0, 0, -1.2);
    return;
  }
  if (subject) {
    subject.rotation.y = turn;
  }
}

// three.js r163 and later need WebGL 2. The `gl` package is WebGL 1, so
// `texImage3D` is missing and the renderer never starts. `webgl-node` is a
// WebGL 2 context on EGL. It needs `libGLESv2.so.2` on the loader path.
async function tryWebGL(width, height) {
  try {
    const { createWebGL2Context } = await import("webgl-node");
    const created = createWebGL2Context(width, height);
    if (created.makeCurrent) created.makeCurrent();
    const renderer = new THREE.WebGLRenderer({
      canvas: created.canvas,
      context: created.gl,
      antialias: false,
    });
    renderer.setSize(width, height, false);
    return {
      backend: {
        kind: "webgl",
        renderer,
        gl: created.gl,
        pixels: new Uint8Array(width * height * 4),
      },
      error: "",
    };
  } catch (error) {
    const message = error && error.message ? error.message : String(error);
    return { backend: null, error: message };
  }
}

// What runs when the `gl` package is missing or cannot make a context. It is
// not three.js rendering: three.js has no CPU rasterizer, so this fills the
// projected triangles with each material's flat color and a depth test, and
// nothing else. No lighting, no textures, no clipping, no sRGB, no
// transparency, and no file is written. The backend name says so, and the
// benchmark page explains what the column then measures.
function softwareTarget(width, height) {
  return {
    kind: "cpu-flat",
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
  if (target.extra?.lamp) {
    target.renderer.shadowMap.enabled = true;
  }
  target.renderer.render(scene, camera);
  const gl = target.renderer.getContext();
  if (target.gl && target.gl.makeCurrent) target.gl.makeCurrent();
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

const requested = process.argv[3] || "auto";
const world = build(spec);
let backend = null;
let webglError = "";
if (requested !== "cpu-flat") {
  const loaded = await tryWebGL(spec.width, spec.height);
  backend = loaded.backend;
  webglError = loaded.error;
}
if (requested === "webgl" && !backend) {
  console.error(webglError || "webgl unavailable");
  process.exit(1);
}
if (!backend) {
  if (webglError) console.error("webgl unavailable: " + webglError);
  backend = softwareTarget(spec.width, spec.height);
}
backend.extra = world.extra;

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

// The frames alone, timed inside the process, so the benchmark can show the
// drawing apart from starting Node and importing three.js.
let framesStarted = performance.now();
try {
  drawFrames(backend);
} catch (err) {
  if (backend.kind !== "webgl" || requested === "webgl") throw err;
  const message = err && err.message ? err.message : String(err);
  console.error("webgl draw failed: " + message);
  backend = softwareTarget(spec.width, spec.height);
  backend.extra = world.extra;
  framesStarted = performance.now();
  drawFrames(backend);
}
const framesMs = performance.now() - framesStarted;

const sample =
  backend.kind === "webgl" ? backend.pixels[0] : backend.color[0];
console.log(
  JSON.stringify({
    name: spec.name,
    width: spec.width,
    height: spec.height,
    frames: spec.frames,
    backend: backend.kind,
    import_ms: Math.round(importMs * 10) / 10,
    frames_ms: Math.round(framesMs * 10) / 10,
    sample,
  }),
);
