// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes three.json: what three.js 0.180's `SceneOptimizer.toBatchedMesh`
// makes of one scene, for `tests/test_scene_optimizer.mojo`. Run it with
// three 0.180 installed beside it: `node three_optimizer.mjs > three.json`.
//
// A group `Shelf` at (1, 0, 0), turned 0.5 radians about y, holds three
// boxes and a sphere whose materials differ only in color, and a box of
// another material. A group `Empty` holds a bare node `Leaf`, and a node
// `Lamp` holds a point light. `batches` lists each batch's name, its
// parent's name, its geometries, and each instance's matrix and color.
// `nodes` lists the names left in the scene, depth first.

import * as THREE from 'three';
import { SceneOptimizer } from 'three/examples/jsm/utils/SceneOptimizer.js';

const r = ( v ) => + v.toFixed( 6 );
const scene = new THREE.Scene();
const shelf = new THREE.Group();
shelf.name = 'Shelf';
shelf.position.set( 1, 0, 0 );
shelf.rotation.y = 0.5;
scene.add( shelf );
const box = new THREE.BoxGeometry( 1, 1, 1 );
const ball = new THREE.SphereGeometry( 0.5 );
const place = ( name, geometry, color, x, y, z ) => {

	const mesh = new THREE.Mesh( geometry, new THREE.MeshLambertMaterial( { color } ) );
	mesh.name = name;
	mesh.position.set( x, y, z );
	mesh.rotation.x = x * 0.1;
	shelf.add( mesh );
	return mesh;

};

place( 'A', box, 0xff0000, 0, 1, 0 );
place( 'B', box, 0x00ff00, 2, 0, 1 );
place( 'C', box, 0x0000ff, - 1, 0.5, 2 );
place( 'D', ball, 0xff0000, 0, - 1, - 1 );
const odd = new THREE.Mesh( box, new THREE.MeshStandardMaterial( { roughness: 0.3 } ) );
odd.name = 'Odd';
shelf.add( odd );
const empty = new THREE.Group();
empty.name = 'Empty';
const leaf = new THREE.Object3D();
leaf.name = 'Leaf';
empty.add( leaf );
scene.add( empty );
const lamp = new THREE.PointLight();
lamp.name = 'Lamp';
scene.add( lamp );

new SceneOptimizer( scene ).toBatchedMesh();

const batches = [];
const nodes = [];
const matrix = new THREE.Matrix4();
const color = new THREE.Color();
scene.traverse( ( node ) => {

	if ( node !== scene ) nodes.push( node.name );
	if ( ! node.isBatchedMesh ) return;
	const instances = [];
	for ( let i = 0; i < node.instanceCount; i ++ ) {

		node.getMatrixAt( i, matrix );
		node.getColorAt( i, color );
		instances.push( { matrix: matrix.elements.map( r ), color: [ r( color.r ), r( color.g ), r( color.b ) ] } );

	}

	batches.push( { name: node.name, parent: node.parent.name, geometries: node._geometryCount, instances } );

} );

console.log( JSON.stringify( { batches, nodes } ) );
