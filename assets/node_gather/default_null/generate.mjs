// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Usage: node generate.mjs /absolute/path/to/three-package
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';

const root = resolve(process.argv[2]);
const pkg = JSON.parse(await readFile(resolve(root, 'package.json')));
if (pkg.version !== '0.186.0') throw new Error('Expected three 0.186.0');
// UUIDs only: fix the RNG before module initialization for repeatable JSON.
let state = 678;
Math.random = () => ((state = (Math.imul(state, 1664525) + 1013904223) >>> 0) / 2 ** 32);
const THREE = await import(pathToFileURL(resolve(root, 'src/Three.WebGPU.js')));
const { texture, int } = await import(pathToFileURL(resolve(root, 'src/Three.TSL.js')));
if (THREE.REVISION !== '186') throw new Error('Expected revision 186');
const map = new THREE.DataTexture(new Uint8Array([
    32, 0, 0, 255, 64, 0, 0, 255,
    96, 0, 0, 255, 128, 0, 0, 255,
]), 2, 2);
const gather = texture(map).gather(int(0));
const material = new THREE.MeshBasicNodeMaterial();
material.colorNode = gather;
const scene = new THREE.Scene();
scene.add(new THREE.Mesh(new THREE.PlaneGeometry(1, 1), material));
const out = new URL('./', import.meta.url);
for (const [name, value] of Object.entries({
    node: gather.toJSON(), material: material.toJSON(), object: scene.toJSON(),
})) {
    await writeFile(new URL(`${name}.json`, out), JSON.stringify(value, null, 2) + '\n');
}
const hashes = {};
for (const file of ['src/nodes/accessors/TextureNode.js', 'src/nodes/core/Node.js', 'package.json']) {
    hashes[file] = createHash('sha256').update(await readFile(resolve(root, file))).digest('hex');
}
await writeFile(new URL('provenance.json', out), JSON.stringify({
    package: 'three', version: pkg.version, revision: THREE.REVISION,
    registry: 'https://registry.npmjs.org',
    node: process.versions.node, v8: process.versions.v8,
    platform: process.platform, arch: process.arch,
    generator: 'generate.mjs', seed: 678, source_sha256: hashes,
    scope: 'Serialization only. No GPU gather execution or ordering claim.',
}, null, 2) + '\n');
